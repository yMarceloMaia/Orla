"""Line-delimited local IPC with the shared Quickshell project service."""

import json
import os
import shutil
import subprocess
import sys
import time
import uuid
from pathlib import Path

import registry
import runner
from metrics import Sampler, system_ports


class Backend:
    def __init__(self):
        self.db = registry.database()
        self.db.execute("CREATE TABLE IF NOT EXISTS docker_cache(at REAL, rows TEXT)")
        self.metrics = Sampler()
        self.last_metrics = {}
        self.last_reconcile = 0
        self.docker = []

    def request(self, msg):
        db = self.db
        op = msg.get("op", "tick")
        if op == "systemPorts":
            return {"systemPorts": system_ports()}
        key = msg.get("project", "")
        row = db.execute("SELECT * FROM projects WHERE id=?", (key,)).fetchone()
        if op == "discover":
            registry.discover(db, msg["path"])
        elif op == "add":
            db.execute(
                "DELETE FROM excluded WHERE path=?",
                (str(Path(msg["path"]).expanduser().resolve()),),
            )
            registry.register(db, msg["path"])
        elif op == "importDocker":
            candidates = {
                r.get("workingDir")
                for r in self.docker
                if r.get("project") == msg["name"] and r.get("workingDir")
            }
            if len(candidates) != 1:
                raise ValueError("Associate the Compose project with a folder manually.")
            folder = Path(candidates.pop())
            if (
                not folder.is_absolute()
                or not folder.is_dir()
                or not any((folder / m).exists() for m in registry.MARKERS)
            ):
                raise ValueError("The Compose project folder is unavailable.")
            owner = db.execute(
                "SELECT projects.id FROM projects,json_each(projects.compose) AS labels WHERE labels.value=? LIMIT 1",
                (msg["name"],),
            ).fetchone()
            if owner:
                raise ValueError("This Compose project is already linked.")
            key = registry.register(db, folder)
            db.execute(
                "UPDATE projects SET compose=json_insert(compose,'$[#]',?) WHERE id=?",
                (msg["name"], key),
            )
        elif op == "docker":
            self.docker = msg["rows"]
            db.execute("DELETE FROM docker_cache")
            db.execute(
                "INSERT INTO docker_cache VALUES(?,?)",
                (time.time(), json.dumps(self.docker)),
            )
        elif op not in ("tick", "refresh"):
            if not row:
                raise ValueError("Project unavailable.")
            if op == "openEditor":
                editor = msg["editor"]
                variants = {"nvim": ("nvim",), "code": ("code",), "zed": ("zed", "zeditor")}
                if editor not in variants:
                    raise ValueError("Unknown editor.")
                folder = Path(row["path"])
                if not folder.is_dir():
                    raise ValueError("The project folder is unavailable.")
                executable = next(filter(None, map(shutil.which, variants[editor])), None)
                if executable is None:
                    raise ValueError("Editor not found in PATH: " + editor)
                command = [executable, str(folder)]
                if editor == "nvim":
                    terminal = shutil.which("xdg-terminal-exec")
                    if terminal is None:
                        raise ValueError("xdg-terminal-exec is required to open Neovim.")
                    command = [terminal, "--", *command]
                return {"editorLaunch": {"command": command, "workingDirectory": str(folder)}}
            if op == "configure":
                names = msg["compose"]
                if not isinstance(names, list) or not all(
                    isinstance(n, str) and n for n in names
                ):
                    raise ValueError("Enter a list of Compose project names.")
                for other in db.execute(
                    "SELECT compose FROM projects WHERE id<>?", (key,)
                ):
                    if set(names) & set(json.loads(other[0])):
                        raise ValueError("A Compose name already belongs to another project.")
                db.execute(
                    "UPDATE projects SET name=?,compose=? WHERE id=?",
                    (msg["name"].strip() or row["name"], json.dumps(names), key),
                )
            elif op == "remove":
                if db.execute(
                    f"SELECT 1 FROM runs WHERE project=? AND state IN {runner.SQL_ACTIVE}",
                    (key,),
                ).fetchone():
                    raise ValueError("Stop active runs before removing this project.")
                db.execute("INSERT OR IGNORE INTO excluded VALUES(?)", (row["path"],))
                db.execute("DELETE FROM commands WHERE project=?", (key,))
                db.execute("DELETE FROM projects WHERE id=?", (key,))
                registry._cache.pop(key, None)
            elif op == "save":
                data = dict(msg["command"])
                cid = data.get("id") or "custom:" + uuid.uuid4().hex
                original = registry.commands(db, row).get(cid, {})
                if not original and not cid.startswith("custom:"):
                    raise ValueError("Unknown command source.")
                data["id"] = cid
                if not data.get("name"):
                    raise ValueError("Enter a name.")
                runner.validate(data)
                if original.get("source"):
                    for field in ("argv", "source", "id"):
                        if data.get(field) != original.get(field):
                            raise ValueError(
                                "Edit this command in its project source file."
                            )
                    data = {
                        k: v
                        for k, v in data.items()
                        if k not in ("argv", "source", "id")
                    }
                db.execute(
                    "INSERT OR REPLACE INTO commands VALUES(?,?,?)",
                    (key, cid, json.dumps(data)),
                )
            elif op == "delete":
                if not msg["id"].startswith("custom:"):
                    raise ValueError("Only custom commands can be deleted.")
                db.execute(
                    "DELETE FROM commands WHERE project=? AND id=?", (key, msg["id"])
                )
            elif op in ("start", "all", "restart", "restartAll"):
                cmds = registry.commands(db, row)
                targets = (
                    [msg["id"]]
                    if op in ("start", "restart")
                    else [k for k, c in cmds.items() if c.get("environment")]
                )
                if not targets:
                    raise ValueError(
                        "Mark at least one command to start with the environment."
                    )
                if op == "restartAll":
                    if not msg.get("confirmed"):
                        raise ValueError("Confirm the environment restart.")
                    order = runner.dependency_order(cmds, targets, True)
                    for cid in reversed(order):
                        for active in db.execute(
                            f"SELECT id FROM runs WHERE project=? AND cmd=? AND state IN {runner.SQL_ACTIVE}",
                            (key, cid),
                        ).fetchall():
                            runner.stop(db, key, active[0])
                if op == "restart":
                    if not msg.get("confirmed"):
                        raise ValueError("Confirm the restart.")
                    if targets[0] not in cmds:
                        raise ValueError("Command unavailable.")
                    active = db.execute(
                        f"SELECT id FROM runs WHERE project=? AND cmd=? AND state IN {runner.SQL_ACTIVE}",
                        (key, targets[0]),
                    ).fetchone()
                    if active:
                        runner.stop(db, key, active[0], True)
                runner.start(db, row, cmds, targets, msg.get("confirmed", False))
            elif op == "stop":
                runner.stop(db, key, msg.get("run"), msg.get("confirmed", False))
            elif op == "logs":
                return dict(
                    logs=[
                        r[0]
                        for r in db.execute(
                            "SELECT line FROM logs JOIN runs ON runs.id=logs.run WHERE run=? AND project=? ORDER BY n",
                            (msg["run"], key),
                        )
                    ],
                    run=msg["run"],
                )
            else:
                raise ValueError("Unknown operation.")
        db.commit()
        if op == "refresh":
            registry._cache.clear()
        now = time.time()
        if now - self.last_reconcile > 30:
            active = list(
                db.execute(
                    f"SELECT id FROM runs WHERE state IN {runner.SQL_ACTIVE} AND started<?",
                    (now - 5,),
                )
            )
            if active:
                result = subprocess.run(
                    [
                        "systemctl",
                        "--user",
                        "list-units",
                        "--all",
                        "--no-legend",
                        "--plain",
                        "orla-project-*.service",
                    ],
                    capture_output=True,
                    text=True,
                    timeout=5,
                )
                if result.returncode == 0:
                    units = {
                        r.split()[0] for r in result.stdout.splitlines() if r.strip()
                    }
                    for r in active:
                        if runner.unit(r[0]) not in units:
                            runner.finish(db, r[0], "Failed", None)
            db.execute(
                "DELETE FROM runs WHERE ended IS NOT NULL AND id NOT IN (SELECT id FROM runs WHERE ended IS NOT NULL ORDER BY started DESC LIMIT 100) AND NOT EXISTS (SELECT 1 FROM runs active WHERE active.ended IS NULL AND instr(active.deps,runs.id)>0)"
            )
            db.execute("DELETE FROM logs WHERE run NOT IN (SELECT id FROM runs)")
            db.commit()
            self.last_reconcile = now
        if op in ("tick", "refresh"):
            for root in db.execute("SELECT * FROM roots").fetchall():
                path = Path(root["path"])
                if path.is_dir() and (
                    op == "refresh" or path.stat().st_mtime_ns != root["mtime"]
                ):
                    registry.discover(db, path)
        projects = []
        for entry in db.execute("SELECT * FROM projects ORDER BY name"):
            p = dict(entry)
            p["compose"] = json.loads(p["compose"])
            try:
                p["commands"] = list(registry.commands(db, p).values())
            except Exception as exc:
                p.update(commands=[], error=str(exc))
            projects.append(p)
        runs = [
            dict(r) | {"state": runner.state_label(r["state"]), "deps": json.loads(r["deps"])}
            for r in db.execute(
                """SELECT id,project,cmd,state,started,ended,pid,code,deps,
                          json_extract(spec, '$.ready.type') AS readiness
                   FROM runs ORDER BY started DESC"""
            )
        ]
        if msg.get("monitor") and op in ("tick", "refresh"):
            self.last_metrics = self.metrics.sample(
                projects,
                {r["id"]: r["project"] for r in runs if not r["ended"]},
                self.docker,
                msg.get("detail", False),
            )
        for p in projects:
            p["metric"] = self.last_metrics.get(p["id"], {})
        return dict(projects=projects, runs=runs)


if __name__ == "__main__":
    os.umask(0o077)
    backend = Backend()
    for line in sys.stdin:
        try:
            msg = json.loads(line)
            result = backend.request(msg)
            result["tick"] = msg.get("op") == "tick"
        except Exception as exc:
            backend.db.rollback()
            result = dict(error=str(exc))
        print(json.dumps(result), flush=True)
