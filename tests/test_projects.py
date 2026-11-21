"""Integration tests use temporary projects and real transient systemd user units."""

import json
import os
import shutil
import signal
import socket
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "projects"))
import runner
from backend import Backend
from metrics import Sampler


class Projects(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.env = patch.dict(os.environ, {"XDG_STATE_HOME": str(self.root / "state")})
        self.env.start()
        self.backend = Backend()
        self.fixtures = self.root / "work"
        self.fixtures.mkdir()
        self.py = self.fixtures / "python"
        self.js = self.fixtures / "node"
        self.py.mkdir()
        self.js.mkdir()
        (self.py / "requirements.txt").touch()
        (self.js / "package.json").write_text(
            json.dumps(
                {"scripts": {"dev": "node server.js"}, "packageManager": "pnpm@9"}
            )
        )
        (self.fixtures / "irrelevant").mkdir()
        projects = self.req("discover", path=str(self.fixtures))["projects"]
        self.assertEqual(len(projects), 2)
        self.p = next(p["id"] for p in projects if p["name"] == "python")
        self.j = next(p["id"] for p in projects if p["name"] == "node")
        self.assertEqual(
            next(p for p in projects if p["id"] == self.j)["commands"][0]["argv"],
            ["pnpm", "run", "dev"],
        )

    def tearDown(self):
        for r in self.backend.db.execute(
            "SELECT id FROM runs WHERE ended IS NULL"
        ).fetchall():
            import subprocess

            subprocess.run(
                ["systemctl", "--user", "stop", runner.unit(r[0])], capture_output=True
            )
        self.backend.db.close()
        self.env.stop()
        self.temp.cleanup()

    def req(self, op, **kwargs):
        return self.backend.request(dict(op=op, **kwargs))

    def cmd(self, p, name, argv, **extra):
        spec = dict(name=name, id="custom:" + name, argv=argv, **extra)
        self.req("save", project=p, command=spec)
        return spec["id"]

    def wait(self, cmd, states):
        until = time.monotonic() + 10
        while time.monotonic() < until:
            row = self.backend.db.execute(
                "SELECT * FROM runs WHERE cmd=? ORDER BY started DESC LIMIT 1", (cmd,)
            ).fetchone()
            if row and row["state"] in states:
                return row
            time.sleep(0.1)
        self.fail(f"{cmd}: {row['state'] if row else 'missing'}")

    def test_supervision_and_resources(self):
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        path = self.py / "server.py"
        path.write_text(
            'import subprocess,sys,os\nsubprocess.Popen([sys.executable,"-c","import os,time;os.chdir(\'/\');time.sleep(90)"])\nfrom http.server import HTTPServer,SimpleHTTPRequestHandler\nHTTPServer(("127.0.0.1",'
            + str(port)
            + "),SimpleHTTPRequestHandler).serve_forever()"
        )
        server = self.cmd(
            self.p,
            "server",
            [sys.executable, str(path)],
            ready={"type": "tcp", "port": port},
        )
        output = self.py / "output.py"
        output.write_text("print('started');print('token=private')")
        downstream = self.cmd(
            self.p,
            "dependent",
            [sys.executable, str(output)],
            depends=[server],
            environment=True,
        )
        node = self.cmd(
            self.j,
            "node",
            [shutil.which("node"), "-e", "setInterval(()=>{},10000)"],
            policy="shared",
        )
        self.req("all", project=self.p)
        self.req("start", project=self.j, id=node)
        self.wait(server, ["Pronto"])
        done = self.wait(downstream, ["Concluído"])
        active = self.wait(node, ["Executando"])
        self.assertEqual(
            self.req("logs", project=self.p, run=done["id"])["logs"],
            ["started", "[linha protegida]"],
        )
        self.backend.db.close()
        self.backend = Backend()
        self.req("tick", monitor=True, detail=True)
        result = self.req("tick", monitor=True, detail=True)
        p = next(p for p in result["projects"] if p["id"] == self.p)
        self.assertGreaterEqual(len(p["metric"]["processes"]), 2)
        self.assertIn("tcp/" + str(port), p["metric"]["ports"])
        self.assertGreater(p["metric"]["local"], 0)
        self.assertTrue(
            any(r["association"] == "Gerenciado" for r in p["metric"]["processes"])
        )
        with self.assertRaises(ValueError):
            self.req("remove", project=self.p)
        self.req("stop", project=self.j)
        self.assertIsNone(
            self.backend.db.execute(
                "SELECT ended FROM runs WHERE id=?", (active["id"],)
            ).fetchone()[0]
        )
        os.kill(active["pid"], signal.SIGKILL)
        self.wait(node, ["Falhou"])
        self.req("stop", project=self.p)
        self.wait(server, ["Cancelado"])
        self.req("remove", project=self.p)
        self.assertEqual(len(self.req("tick", monitor=True)["projects"]), 1)

    def test_invalid_dag_and_failure(self):
        a = self.cmd(self.p, "a", ["false"], depends=["custom:b"])
        self.cmd(self.p, "b", ["true"], depends=[a])
        with self.assertRaises(ValueError):
            self.req("start", project=self.p, id=a)
        fail = self.cmd(self.p, "fail", ["false"])
        self.req("start", project=self.p, id=fail)
        self.assertEqual(self.wait(fail, ["Falhou"])["code"], 1)

    def test_sources_permissions_and_refresh(self):
        (self.py / "Makefile").write_text("build:\n\ttrue\n")
        (self.py / "justfile").write_text("lint:\n    true\n")
        (self.py / "Taskfile.yml").write_text(
            "version: '3'\ntasks:\n  check:\n    cmds: [true]\n"
        )
        (self.py / "compose.yaml").write_text("services:\n  db:\n    image: postgres\n")

        def catalog():
            return {
                c["id"]
                for p in self.req("refresh")["projects"]
                if p["id"] == self.p
                for c in p["commands"]
            }

        self.assertEqual(
            catalog(), {"make:build", "just:lint", "task:check", "compose:db"}
        )
        (self.py / "Makefile").write_text("new:\n\ttrue\n")
        self.assertIn("make:new", catalog())
        self.assertNotIn("make:build", catalog())
        with self.assertRaises(ValueError):
            self.cmd(self.p, "bad", ["app", "--password", "secret"])
        with self.assertRaises(ValueError):
            self.cmd(self.p, "shell", ["sh", "-c", "echo ok"])
        self.assertEqual(
            (self.root / "state/orla/projects").stat().st_mode & 0o777, 0o700
        )

    def test_readiness_history_and_restart(self):
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        cmd = self.cmd(
            self.p,
            "http",
            [sys.executable, "-m", "http.server", str(port), "--bind", "127.0.0.1"],
            ready={"type": "http", "url": f"http://127.0.0.1:{port}/"},
        )
        self.req("start", project=self.p, id=cmd)
        first = self.wait(cmd, ["Pronto"])
        self.req("restart", project=self.p, id=cmd, confirmed=True)
        second = self.wait(cmd, ["Pronto"])
        self.assertNotEqual(first["id"], second["id"])
        many = self.cmd(
            self.p, "logs", [sys.executable, "-c", "for n in range(400): print(n)"]
        )
        self.req("start", project=self.p, id=many)
        done = self.wait(many, ["Concluído"])
        lines = self.req("logs", project=self.p, run=done["id"])["logs"]
        self.assertEqual(len(lines), 150)
        self.assertEqual(lines[-1], "399")

    def test_live_docker_when_available(self):
        import importlib.util

        path = Path(__file__).resolve().parents[1] / "plugins/docker/manager.py"
        spec = importlib.util.spec_from_file_location("orla_docker", path)
        docker = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(docker)
        snapshot = docker.reply(["detail"])
        if "error" in snapshot:
            self.skipTest("Engine não acessível")
        rows = [
            r
            for r in snapshot["rows"]
            if r["project"] != "Sem projeto Compose" and r["state"] == "running"
        ]
        if len(rows) < 2:
            self.skipTest("São necessários dois containers Compose ativos")
        self.req(
            "configure",
            project=self.p,
            name="integration",
            compose=sorted({r["project"] for r in rows}),
        )
        self.req("docker", rows=rows)
        local = self.cmd(self.p, "local", ["sleep", "30"])
        self.req("start", project=self.p, id=local)
        self.wait(local, ["Executando"])
        metric = next(
            p["metric"]
            for p in self.req("tick", monitor=True)["projects"]
            if p["id"] == self.p
        )
        self.assertEqual(len(metric["containers"]), len(rows))
        self.assertGreater(metric["local"], 0)

    def test_container_contract_and_retention(self):
        self.req("configure", project=self.p, name="Renamed", compose=["stack"])
        rows = [
            dict(
                id=str(i),
                name="svc" + str(i),
                project="stack",
                state="running",
                ram=100,
                cpu=2,
                urls=[],
            )
            for i in range(2)
        ]
        self.req("docker", rows=rows)
        process = self.cmd(self.p, "sleep", ["sleep", "30"])
        self.req("start", project=self.p, id=process)
        self.wait(process, ["Executando"])
        sample = self.req("tick", monitor=True)
        p = next(p for p in sample["projects"] if p["id"] == self.p)
        self.assertEqual(p["metric"]["containerRam"], 200)
        self.assertGreater(p["metric"]["total"], 200)
        self.req("docker", rows=[])
        self.assertFalse(
            next(
                p
                for p in self.req("tick", monitor=True)["projects"]
                if p["id"] == self.p
            )["metric"]["containers"]
        )
        sampler = Sampler()
        with patch("metrics.Path.iterdir", return_value=[]):
            for _ in range(1000):
                sampler.sample([p], {}, [], False)
        self.assertEqual(len(sampler.history[self.p]), 60)


if __name__ == "__main__":
    unittest.main()
