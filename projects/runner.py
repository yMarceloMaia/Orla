"""One transient user service per run; SQLite stores the bounded run journal."""

import http.client
import json
import os
import re
import selectors
import signal
import socket
import subprocess
import sys
import time
import uuid
from pathlib import Path
from urllib.parse import urlsplit

from registry import database

ACTIVE = ("Aguardando", "Iniciando", "Executando", "Pronto")
SQL_ACTIVE = "('Aguardando','Iniciando','Executando','Pronto')"
SENSITIVE = re.compile(
    r"password|passwd|token|secret|authorization|credential|api.?key|private.?key|cookie|senha",
    re.IGNORECASE,
)


def unit(run):
    if not re.fullmatch("[a-f0-9]{32}", run):
        raise ValueError("Execução inválida.")
    return "orla-project-" + run + ".service"


def compose_command(spec):
    argv = spec.get("argv", [])
    return spec.get("id", "").startswith("compose:") or bool(
        argv
        and (
            Path(argv[0]).name == "docker-compose"
            or (Path(argv[0]).name == "docker" and "compose" in argv[1:])
        )
    )


def validate(spec):
    argv = spec.get("argv")
    if (
        not isinstance(argv, list)
        or not argv
        or not all(isinstance(a, str) and "\0" not in a for a in argv)
    ):
        raise ValueError("Informe o executável e argumentos como uma lista.")
    if (
        Path(argv[0]).name in {"sh", "bash", "zsh", "fish", "dash"}
        and any(a.startswith("-") and "c" in a for a in argv[1:])
        and spec.get("shell") is not True
    ):
        raise ValueError("Defina shell como true para executar texto via shell.")
    credentials = re.compile(
        r"(?i)(?:password|passwd|token|secret|api[_-]?key|authorization)\s*[:=]\s*[^\s]+|://[^ /]+:[^ /]+@|(?:gh[pousr]_|github_pat_|sk-)[\w.-]{10,}"
    )
    if any(
        credentials.search(a) or (a.startswith("-") and SENSITIVE.search(a))
        for a in argv
    ):
        raise ValueError("Use uma referência de ambiente para a credencial.")
    env = spec.get("env", {})
    if not isinstance(env, dict) or any(
        not re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*", k)
        or not isinstance(v, str)
        or not re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*", v)
        for k, v in env.items()
    ):
        raise ValueError(
            "Variáveis devem referenciar nomes do ambiente do systemd de usuário."
        )
    if not isinstance(spec.get("depends", []), list) or not all(
        isinstance(d, str) for d in spec.get("depends", [])
    ):
        raise ValueError("depends deve conter IDs de comandos.")
    if not 1 <= int(spec.get("timeout", 120)) <= 3600:
        raise ValueError("Timeout deve estar entre 1 e 3600 segundos.")
    if compose_command(spec) and spec.get("policy", "shared") != "shared":
        raise ValueError("Serviços Compose exigem parada individual confirmada.")
    if spec.get("policy", "managed") not in ("managed", "shared"):
        raise ValueError("Política desconhecida.")
    check = spec.get("ready", {})
    kind = check.get("type", "process")
    if kind not in ("process", "tcp", "http", "docker"):
        raise ValueError("Verificação de prontidão desconhecida.")
    if kind == "tcp" and not 0 < int(check["port"]) < 65536:
        raise ValueError("Porta inválida.")
    if kind == "http" and (
        credentials.search(check["url"]) or urlsplit(check["url"]).password is not None
    ):
        raise ValueError("Use um endpoint de prontidão sem credenciais.")
    if kind == "http" and (
        urlsplit(check["url"]).scheme not in ("http", "https")
        or not urlsplit(check["url"]).hostname
    ):
        raise ValueError("Use um endpoint HTTP.")
    if kind == "docker" and not (check.get("service") and check.get("project")):
        raise ValueError("Informe o serviço Compose.")


def dependency_order(cmds, targets, confirmed):
    order, visiting = [], set()

    def visit(k):
        if k in visiting or k not in cmds:
            raise ValueError("Dependência circular ou desconhecida: " + k)
        if k in order:
            return
        spec = cmds[k]
        validate(spec)
        if spec.get("confirm", False) and not confirmed:
            raise ValueError("Confirme a execução de " + spec["name"])
        visiting.add(k)
        for dep in spec.get("depends", []):
            visit(dep)
        visiting.remove(k)
        order.append(k)

    for k in targets:
        visit(k)
    return order


def start(db, project, cmds, targets, confirmed=False):
    order = dependency_order(cmds, targets, confirmed)
    ids, new = {}, []
    db.execute("BEGIN IMMEDIATE")
    try:
        for k in order:
            old = db.execute(
                f"SELECT id FROM runs WHERE project=? AND cmd=? AND state IN {SQL_ACTIVE}",
                (project["id"], k),
            ).fetchone()
            if old:
                ids[k] = old[0]
                continue
            spec = dict(cmds[k])
            cwd = (Path(project["path"]) / spec.get("cwd", ".")).resolve(strict=True)
            if not cwd.is_dir() or not cwd.is_relative_to(Path(project["path"])):
                raise ValueError("Diretório de execução fora do projeto.")
            spec["cwd"] = str(cwd)
            rid = ids[k] = uuid.uuid4().hex
            deps = [ids[d] for d in spec.get("depends", [])]
            db.execute(
                "INSERT INTO runs VALUES(?,?,?,?,?,?,?,?,?,?)",
                (
                    rid,
                    project["id"],
                    k,
                    "Aguardando",
                    time.time(),
                    None,
                    None,
                    None,
                    json.dumps(spec),
                    json.dumps(deps),
                ),
            )
            new.append(rid)
        db.commit()
    except Exception:
        db.rollback()
        raise
    for rid in new:
        args = [
            "systemd-run",
            "--user",
            "--quiet",
            "--collect",
            "--service-type=exec",
            "--unit",
            unit(rid),
            "--property=KillMode=control-group",
            "--property=NoNewPrivileges=yes",
            "--property=TimeoutStopSec=6",
            "--property=StandardOutput=null",
            "--property=StandardError=null",
        ]
        if "XDG_STATE_HOME" in os.environ:
            args.append("--setenv=XDG_STATE_HOME=" + os.environ["XDG_STATE_HOME"])
        result = subprocess.run(
            [*args, sys.executable, str(Path(__file__).resolve()), rid],
            capture_output=True,
        )
        if result.returncode:
            finish(db, rid, "Falhou", result.returncode)
    return ids


def finish(db, rid, state, code):
    db.execute(
        "UPDATE runs SET state=?,ended=?,code=? WHERE id=?",
        (state, time.time(), code, rid),
    )
    db.commit()


def stop(db, project, rid=None, shared=False):
    for row in db.execute(
        f"SELECT * FROM runs WHERE project=? AND state IN {SQL_ACTIVE} ORDER BY started DESC",
        (project,),
    ).fetchall():
        if rid and row["id"] != rid:
            continue
        spec = json.loads(row["spec"])
        if (compose_command(spec) or spec.get("policy") == "shared") and not (
            shared and rid
        ):
            continue
        res = subprocess.run(
            ["systemctl", "--user", "stop", unit(row["id"])], capture_output=True
        )
        if (
            res.returncode
            and not db.execute(
                "SELECT ended FROM runs WHERE id=?", (row["id"],)
            ).fetchone()[0]
        ):
            raise ValueError("Não foi possível encerrar a unidade.")
        if not res.returncode:
            finish(db, row["id"], "Cancelado", None)


def probe(db, check):
    kind = check.get("type", "process")
    if kind == "process":
        return True
    if kind == "docker":
        row = db.execute("SELECT at,rows FROM docker_cache LIMIT 1").fetchone()
        return bool(
            row
            and time.time() - row[0] < 60
            and any(
                c.get("service") == check["service"]
                and c.get("project") == check.get("project")
                and c.get("health") == "healthy"
                for c in json.loads(row[1])
            )
        )
    if kind == "tcp":
        with socket.create_connection(
            (check.get("host", "127.0.0.1"), int(check["port"])), timeout=0.4
        ):
            return True
    u = urlsplit(check["url"])
    conn = (
        http.client.HTTPSConnection
        if u.scheme == "https"
        else http.client.HTTPConnection
    )(u.hostname, u.port, timeout=0.5)
    try:
        conn.request("GET", (u.path or "/") + ("?" + u.query if u.query else ""))
        return 200 <= conn.getresponse().status < 400
    finally:
        conn.close()


def worker(rid):
    db = database()
    row = db.execute("SELECT * FROM runs WHERE id=?", (rid,)).fetchone()
    spec = json.loads(row["spec"])
    deps = json.loads(row["deps"])
    deadline = time.monotonic() + int(spec.get("timeout", 120))
    process = None

    def note(text):
        db.execute("INSERT INTO logs(run,line) VALUES(?,?)", (rid, text))

    def cancel(*_):
        raise InterruptedError()

    signal.signal(signal.SIGTERM, cancel)
    try:
        while deps:
            states = [
                db.execute("SELECT state FROM runs WHERE id=?", (d,)).fetchone()
                for d in deps
            ]
            if (
                any(not s or s[0] in ("Falhou", "Cancelado") for s in states)
                or time.monotonic() > deadline
            ):
                raise ValueError("Dependência indisponível")
            if all(
                s[0] in ("Pronto", "Concluído")
                or (
                    s[0] == "Executando"
                    and not json.loads(
                        db.execute("SELECT spec FROM runs WHERE id=?", (d,)).fetchone()[
                            0
                        ]
                    ).get("ready")
                )
                for d, s in zip(deps, states)
            ):
                break
            time.sleep(0.25)
        db.execute("UPDATE runs SET state='Iniciando' WHERE id=?", (rid,))
        db.commit()
        allowed = {
            "PATH",
            "HOME",
            "USER",
            "LOGNAME",
            "SHELL",
            "LANG",
            "TERM",
            "DISPLAY",
            "WAYLAND_DISPLAY",
            "DBUS_SESSION_BUS_ADDRESS",
            "XDG_RUNTIME_DIR",
            "SSH_AUTH_SOCK",
        }
        env = {
            k: v for k, v in os.environ.items() if k in allowed or k.startswith("LC_")
        }
        env.update(
            {key: os.environ[source] for key, source in spec.get("env", {}).items()}
        )
        secrets = [
            v
            for k, v in env.items()
            if (SENSITIVE.search(k) or k in spec.get("env", {})) and v
        ]
        process = subprocess.Popen(
            spec["argv"],
            cwd=spec["cwd"],
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        db.execute(
            "UPDATE runs SET state='Executando',pid=? WHERE id=?", (process.pid, rid)
        )
        db.commit()
        check = spec.get("ready")
        deadline = time.monotonic() + int(spec.get("timeout", 120))
        sel = selectors.DefaultSelector()
        sel.register(process.stdout, selectors.EVENT_READ)
        tail = b""
        private_block = False

        def log(line):
            nonlocal private_block
            if spec.get("capture", True) is False:
                return
            value = line.decode(errors="replace")
            if re.search(r"-----BEGIN .*PRIVATE KEY-----", value):
                private_block = True
            if private_block:
                if re.search(r"-----END .*PRIVATE KEY-----", value):
                    private_block = False
                value = "[linha protegida]"
            if (
                SENSITIVE.search(value)
                or any(v in value for v in secrets)
                or re.search(
                    r"(?:gh[pousr]_|github_pat_|sk-|eyJ)[\w.-]{10,}|://[^ /]+:[^ /]+@",
                    value,
                )
            ):
                value = "[linha protegida]"
            db.execute("INSERT INTO logs(run,line) VALUES(?,?)", (rid, value[:1000]))

        if check and check.get("type", "process") == "process":
            db.execute("UPDATE runs SET state='Pronto' WHERE id=?", (rid,))
            db.commit()
            check = None
        next_probe = 0
        drained = 0
        while True:
            exited = process.poll() is not None
            if sel.get_map() and sel.select(0 if exited else 0.35):
                chunk = os.read(process.stdout.fileno(), 16384)
                lines = (tail + chunk).split(b"\n")
                tail = lines.pop()[:4096]
                for line in lines[-150:]:
                    log(line)
                db.execute(
                    "DELETE FROM logs WHERE run=? AND n < (SELECT n FROM logs WHERE run=? ORDER BY n DESC LIMIT 1 OFFSET 149)",
                    (rid, rid),
                )
                db.commit()
                if not chunk:
                    sel.unregister(process.stdout)
                if exited and chunk:
                    drained += len(chunk)
                    if drained < 262144:
                        continue
            elif not sel.get_map() and not exited:
                time.sleep(0.2)
            if exited:
                break
            if check and time.monotonic() >= next_probe:
                next_probe = time.monotonic() + 1
                try:
                    ready = probe(db, check)
                except (OSError, http.client.HTTPException):
                    ready = False
                if ready:
                    db.execute("UPDATE runs SET state='Pronto' WHERE id=?", (rid,))
                    db.commit()
                    check = None
                elif time.monotonic() > deadline:
                    raise TimeoutError()
        if tail:
            log(tail)
        code = process.wait()
        finish(db, rid, "Concluído" if code == 0 and not check else "Falhou", code)
    except InterruptedError:
        finish(db, rid, "Cancelado", None)
    except Exception as exc:
        messages = {
            FileNotFoundError: "Executável ou diretório indisponível.",
            KeyError: "Variável de ambiente não disponível.",
            TimeoutError: "A verificação de prontidão expirou.",
            ValueError: "Dependência ou configuração inválida.",
        }
        note(messages.get(type(exc), "Não foi possível executar o comando."))
        finish(db, rid, "Falhou", None)
    finally:
        if process and process.poll() is None:
            process.terminate()
            try:
                process.wait(2)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


if __name__ == "__main__":
    worker(sys.argv[1])
