#!/usr/bin/python3 -I
"""Docker CLI adapter. Only project the metadata used by the panel."""
import grp
import ipaddress
import json
import os
import pwd
import re
import select
import time
import subprocess
import sys
from urllib.parse import urlsplit


HELPER = "/usr/local/lib/orla-docker-manager"
LOCAL = "unix:///var/run/docker.sock"
CLI = ["docker"]


def restrict_helper():
    # Only the installed, isolated entry point may access the system socket.
    if os.path.abspath(__file__) != HELPER or not sys.flags.isolated:
        raise ValueError("Use o auxiliar instalado em /usr/local/lib.")
    uid = pwd.getpwnam("nobody").pw_uid
    gid = grp.getgrnam("docker").gr_gid
    os.chdir("/")
    os.environ.clear()
    os.environ.update(PATH="/usr/bin", HOME="/nonexistent", LC_ALL="C", DOCKER_HOST=LOCAL)
    os.setgroups([])
    os.setgid(gid)
    os.setuid(uid)
    CLI[:] = ["/usr/bin/docker", "--host", LOCAL]


def docker(*args, timeout=15):
    result = subprocess.run([*CLI, *args], capture_output=True, text=True,
                            errors="replace", timeout=timeout)
    if result.returncode:
        raise ValueError(result.stderr.strip()[:600] or "O Docker não concluiu a operação.")
    return result.stdout.strip()


def memory_bytes(value):
    match = re.fullmatch(r"([\d.]+)\s*([KMGT]?i?B)", value)
    if not match:
        return 0
    unit = match[2]
    power = "BKMGT".index(unit[0])
    return float(match[1]) * (1024 if "i" in unit else 1000) ** power


def browser_host():
    endpoint = os.getenv("DOCKER_HOST", "")
    if not endpoint or os.getenv("DOCKER_CONTEXT"):
        endpoint = docker("context", "inspect", "--format", "{{.Endpoints.docker.Host}}")
    return "localhost" if endpoint.startswith("unix:") else urlsplit(endpoint).hostname


def ports(bindings, endpoint):
    result = set()
    for target, entries in (bindings or {}).items():
        if not target.endswith("/tcp"):
            continue
        for entry in entries or []:
            ip = ipaddress.ip_address(entry["HostIp"] or "0.0.0.0")
            host = endpoint if ip.is_unspecified else str(ip)
            if not host or (ip.is_loopback and endpoint != "localhost"):
                continue
            if ":" in host:
                host = "[" + host + "]"
            scheme = "https" if target == "443/tcp" else "http"
            result.add(f'{scheme}://{host}:{int(entry["HostPort"])}')
    return sorted(result)


def snapshot(detail):
    ids = docker("ps", "-aq", "--no-trunc").splitlines()
    rows = []
    if ids:
        fields = [".Id", ".Name", '.State.Status', '.Config.Labels', '.NetworkSettings.Ports']
        fmt = "\t".join("{{json " + field + "}}" for field in fields)
        endpoint = browser_host()
        for line in docker("inspect", "--type", "container", "--format", fmt, *ids).splitlines():
            cid, name, state, labels, bindings = map(json.loads, line.split("\t"))
            rows.append(dict(id=cid, name=name.lstrip("/"), state=state,
                             project=(labels or {}).get("com.docker.compose.project") or "Sem projeto Compose",
                             urls=ports(bindings, endpoint), cpu=None, ram=None))
    warnings = ""
    active = [row for row in rows if row["state"] == "running"]
    if detail and active:
        try:
            lines = docker("stats", "--no-stream", "--no-trunc", "--format",
                           "{{.ID}}\t{{.CPUPerc}}\t{{.MemUsage}}", *(r["id"] for r in active))
            by_id = {row["id"]: row for row in active}
            for line in lines.splitlines():
                cid, cpu, ram = line.split("\t")
                if cid in by_id:
                    by_id[cid].update(cpu=float(cpu.rstrip("%")), ram=memory_bytes(ram.split("/")[0].strip()))
        except (ValueError, subprocess.TimeoutExpired):
            warnings = "Métricas de recursos indisponíveis."
    rows.sort(key=lambda r: (r["project"].casefold(), r["name"].casefold()))
    return dict(rows=rows, warning=warnings)


def main(args):
    if args in (["summary"], ["detail"]):
        return snapshot(args == ["detail"])
    op, cid = args
    if not re.fullmatch("[0-9a-f]{64}", cid):
        raise ValueError("ID de container inválido.")
    if op == "health":
        state = json.loads(docker("inspect", "--format", "{{json .State.Health}}", cid) or "null")
        if not state:
            return dict(message="Sem health check configurado.")
        recent = [f'{log["End"]} · saída {log["ExitCode"]}\n{log["Output"].strip()[:500]}'
                  for log in state.get("Log", [])[-3:]]
        return dict(message="\n".join([state["Status"], *recent]))
    if op in ("start", "stop", "restart"):
        docker(op, cid, timeout=90)
        return dict(message="Operação concluída.")
    raise ValueError("Operação desconhecida.")


def reply(args):
    try:
        return main(args)
    except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
        error = str(exc)
        denied = "permission denied" in error.lower() and "/var/run/docker.sock" in error
        return dict(error=error, locked=denied, installed=os.access(HELPER, os.X_OK))


def read_session():
    # EOF (closed panel, disabled plugin or dead dock) ends the session.
    # A hard deadline also bounds an abandoned or deliberately held-open pipe.
    deadline = time.monotonic() + 600
    while time.monotonic() < deadline:
        if select.select([sys.stdin], [], [], 0)[0]:
            break
        print(json.dumps(reply(["detail"])), flush=True)
        if select.select([sys.stdin], [], [], 5)[0]:
            break


def privileged(args):
    if args == ["watch"]:
        read_session()
        return
    if len(args) != 2 or not re.fullmatch("[0-9a-f]{64}", args[1]):
        raise ValueError("Destino inválido.")
    op, cid = args
    if op in ("shell", "logs"):
        command = ["exec", "-it", cid, "sh"] if op == "shell" else ["logs", "--tail", "200", "--follow", cid]
        os.execv(CLI[0], [*CLI, *command])
    if op not in ("health", "start", "stop", "restart"):
        raise ValueError("Operação inválida.")
    print(json.dumps(reply(args)))


if __name__ == "__main__":
    try:
        if os.geteuid() == 0:
            restrict_helper()
            privileged(sys.argv[1:])
        else:
            print(json.dumps(reply(sys.argv[1:])))
    except (KeyError, OSError, ValueError) as exc:
        sys.exit(str(exc))
