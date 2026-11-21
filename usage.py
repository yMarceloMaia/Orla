"""Read plan limits independently for local CLI profiles."""
import json
import os
import subprocess
import time
from http.client import HTTPException
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from http.client import HTTPSConnection
from pathlib import Path


class ProfileError(Exception):
    pass


def window(label, used, reset):
    if not isinstance(used, (int, float)) or not 0 <= used <= 100:
        return None
    if isinstance(reset, str):
        reset = datetime.fromisoformat(reset.replace("Z", "+00:00")).timestamp()
    return {"label": label, "used": used, "reset": reset}


def claude(directory):
    credentials = json.loads((directory / ".credentials.json").read_text())
    if credentials["claudeAiOauth"].get("expiresAt", 0) <= time.time() * 1000:
        subprocess.run(["claude", "auth", "status"], env={**os.environ, "CLAUDE_CONFIG_DIR": str(directory)},
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
        credentials = json.loads((directory / ".credentials.json").read_text())
    token = credentials["claudeAiOauth"]["accessToken"]
    connection = HTTPSConnection("api.anthropic.com", timeout=10)
    try:
        connection.request("GET", "/api/oauth/usage", headers={
            "Authorization": "Bearer " + token, "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": "Orla/1.0",
        })
        response = connection.getresponse()
        if response.status == 429:
            raise ProfileError("Limite de consultas. Tente mais tarde.")
        if response.status in (401, 403):
            raise ProfileError("Verifique o login deste perfil.")
        if response.status != 200:
            raise OSError("Service unavailable")
        data = json.load(response)
    finally:
        connection.close()
    return [window(label, data[key].get("utilization"), data[key].get("resets_at"))
            for key, label in (("five_hour", "5 horas"), ("seven_day", "Semanal"))
            if isinstance(data.get(key), dict)]


def codex():
    # Keep stdin open until the server has answered the rate-limit request.
    import selectors

    messages = [
        {"id": 1, "method": "initialize", "params": {"clientInfo": {"name": "orla", "version": "1"}}},
        {"method": "initialized"},
        {"id": 2, "method": "account/rateLimits/read", "params": {}},
    ]
    proc = subprocess.Popen(["codex", "app-server"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL)
    try:
        def send(message):
            proc.stdin.write(json.dumps(message).encode() + b"\n")
            proc.stdin.flush()

        send(messages[0])
        pending = b""
        deadline = time.monotonic() + 18
        with selectors.DefaultSelector() as selector:
            selector.register(proc.stdout, selectors.EVENT_READ)
            while selector.select(max(0, deadline - time.monotonic())):
                chunk = os.read(proc.stdout.fileno(), 65536)
                if not chunk or time.monotonic() > deadline:
                    break
                pending += chunk
                while b"\n" in pending:
                    line, pending = pending.split(b"\n", 1)
                    reply = json.loads(line)
                    if reply.get("id") == 1 and "result" in reply:
                        send(messages[1])
                        send(messages[2])
                    if reply.get("id") == 2:
                        result = reply["result"]
                        limits = (result.get("rateLimitsByLimitId") or {}).get("codex") or result["rateLimits"]
                        rows = []
                        for key in ("primary", "secondary"):
                            item = limits.get(key)
                            if item:
                                minutes = item.get("windowDurationMins")
                                label = {300: "5 horas", 10080: "Semanal"}.get(minutes)
                                rows.append(window(label or (f"{minutes} min" if minutes else "Limite"),
                                                   item["usedPercent"], item.get("resetsAt")))
                        return rows
        raise TimeoutError()
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        proc.stdin.close()
        proc.stdout.close()


def read(profile):
    label, fetch = profile
    try:
        rows = [r for r in fetch() if r]
        return dict(name=label, windows=rows, error="" if rows else "Uso indisponível neste plano.")
    except FileNotFoundError:
        error = "CLI ou perfil não encontrado."
    except ProfileError as exc:
        error = str(exc)
    except (OSError, HTTPException, KeyError, TypeError, ValueError, subprocess.SubprocessError):
        error = "Não foi possível consultar este perfil."
    return dict(name=label, windows=[], error=error)


if __name__ == "__main__":
    config = Path.home() / ".config/orla/settings.json"
    extra = json.loads(config.read_text()).get("extraClaudeProfile") if config.exists() else None
    primary = Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude").expanduser()
    profiles = [("Claude", lambda: claude(primary))]
    if isinstance(extra, dict):
        name, directory = extra.get("name"), extra.get("directory")
        if isinstance(name, str) and name.strip() and name not in ("Claude", "Codex", "all") and isinstance(directory, str):
            path = Path(directory).expanduser()
            if path.is_absolute() and path != primary:
                profiles.append((name, lambda: claude(path)))
    profiles.append(("Codex", codex))
    with ThreadPoolExecutor(max_workers=3) as pool:
        print(json.dumps(list(pool.map(read, profiles))))
