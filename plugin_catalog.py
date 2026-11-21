"""Discover v1 widget manifests without executing plugin code."""
import json
import re
import time
from pathlib import Path

ID = re.compile(r"[a-z0-9]+(?:[.-][a-z0-9]+)*")
ROOT = Path(__file__).resolve().parent


def entry(folder, name):
    path = (folder / name).resolve()
    if not path.is_relative_to(folder.resolve()) or path.suffix != ".qml" or not path.is_file():
        raise ValueError("Invalid QML entry point")
    return path.as_uri()


_cache = []
_next_scan = 0.0


def discover():
    global _cache, _next_scan
    now = time.monotonic()
    if now < _next_scan:
        return _cache
    catalog = {}
    for official, base in ((True, ROOT / "plugins"), (False, Path.home() / ".config/orla/plugins")):
        for path in sorted(base.glob("*/manifest.json")):
            try:
                data = json.loads(path.read_text())
                key = data["id"]
                if (data["apiVersion"] != 1 or not ID.fullmatch(key) or key in catalog
                        or not isinstance(data["name"], str) or not data["name"].strip()):
                    continue
                catalog[key] = dict(pluginId=key, name=data["name"], widgetUrl=entry(path.parent, data["widget"]),
                                    serviceUrl=entry(path.parent, data["service"]) if data.get("service") else "",
                                    setting=data["setting"] if official else "plugin." + key + ".enabled",
                                    defaultOn=official and data.get("defaultEnabled") is True,
                                    order=int(data.get("order", 100)) if official else 100,
                                    options=data.get("options", []) if official else [])
            except (OSError, ValueError, KeyError, TypeError, RuntimeError):
                continue
    _next_scan = now + 2
    _cache = sorted(catalog.values(), key=lambda p: (p["order"], p["pluginId"]))
    return _cache
