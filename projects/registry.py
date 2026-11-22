"""Shared project and command registry. Discovery never executes project files."""

import json
import os
import re
import sqlite3
import uuid
from pathlib import Path

MARKERS = (
    ".git",
    "package.json",
    "pyproject.toml",
    "requirements.txt",
    "Makefile",
    "justfile",
    "Justfile",
    "Taskfile.yml",
    "Taskfile.yaml",
    "compose.yml",
    "compose.yaml",
    "docker-compose.yml",
    "docker-compose.yaml",
)


def database():
    root = (
        Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
        / "orla/projects"
    )
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(root, 0o700)
    db = sqlite3.connect(root / "registry.sqlite", timeout=5)
    db.row_factory = sqlite3.Row
    db.executescript("""
    CREATE TABLE IF NOT EXISTS roots(path TEXT PRIMARY KEY,mtime INTEGER);
    CREATE TABLE IF NOT EXISTS excluded(path TEXT PRIMARY KEY);
    CREATE TABLE IF NOT EXISTS projects(id TEXT PRIMARY KEY,path TEXT UNIQUE,name TEXT,compose TEXT);
    CREATE TABLE IF NOT EXISTS commands(project TEXT,id TEXT,data TEXT, PRIMARY KEY(project,id));
    CREATE TABLE IF NOT EXISTS runs(id TEXT PRIMARY KEY,project TEXT,cmd TEXT,state TEXT,
        started REAL,ended REAL,pid INTEGER,code INTEGER,spec TEXT,deps TEXT);
    CREATE INDEX IF NOT EXISTS recent ON runs(project,started);
    CREATE TABLE IF NOT EXISTS logs(run TEXT,n INTEGER PRIMARY KEY,line TEXT);
    CREATE INDEX IF NOT EXISTS logrun ON logs(run,n);
    """)
    return db


def register(db, path, name="", compose=None):
    directory = Path(path).expanduser().resolve(strict=True)
    if not directory.is_dir():
        raise ValueError("Select a folder.")
    key = uuid.uuid4().hex
    db.execute(
        "INSERT INTO projects VALUES(?,?,?,?) ON CONFLICT(path) DO NOTHING",
        (key, str(directory), name or directory.name, json.dumps(compose or [])),
    )
    db.commit()
    return db.execute(
        "SELECT id FROM projects WHERE path=?", (str(directory),)
    ).fetchone()[0]


def discover(db, path):
    root = Path(path).expanduser().resolve(strict=True)
    db.execute(
        "INSERT OR REPLACE INTO roots VALUES(?,?)", (str(root), root.stat().st_mtime_ns)
    )
    excluded = {r[0] for r in db.execute("SELECT path FROM excluded")}
    # A workspace collection is searched one level deep, only on request.
    candidates = (
        [root]
        if any((root / m).exists() for m in MARKERS)
        else (
            d
            for d in root.iterdir()
            if not d.name.startswith(".")
            and not d.is_symlink()
            and d.name
            not in {
                "node_modules",
                "vendor",
                "build",
                "dist",
                "target",
                "venv",
                "__pycache__",
            }
            and d.is_dir()
            and any((d / m).exists() for m in MARKERS)
        )
    )
    return [register(db, d) for d in candidates if str(d) not in excluded]


def read(path):
    if path.stat().st_size > 2_000_000:
        raise ValueError(f"File is too large: {path.name}")
    return path.read_text(errors="replace")


def source_commands(root, errors):
    root = Path(root)
    result = {}

    def add(tool, name, argv, source):
        key = tool + ":" + name
        result[key] = dict(id=key, name=name, argv=argv, category=tool, source=source)

    package = root / "package.json"
    if package.is_file():
        try:
            data = json.loads(read(package))
            if not isinstance(data, dict) or not isinstance(
                data.get("scripts", {}), dict
            ):
                raise ValueError()
        except (OSError, ValueError):
            errors.append("Could not read scripts from package.json.")
            data = {}
        manager = str(data.get("packageManager", "")).split("@")[0]
        if manager not in {"npm", "pnpm", "yarn", "bun"}:
            manager = next(
                (
                    name
                    for lock, name in [
                        ("pnpm-lock.yaml", "pnpm"),
                        ("yarn.lock", "yarn"),
                        ("bun.lock", "bun"),
                        ("bun.lockb", "bun"),
                    ]
                    if (root / lock).exists()
                ),
                "npm",
            )
        for name in data.get("scripts", {}):
            if not name.startswith("-"):
                add(manager, name, [manager, "run", name], package.name)
    for source, tool, pattern in [
        ("Makefile", "make", r"^([\w./-]+(?: +[\w./-]+)*)\s*:(?!=)"),
        ("justfile", "just", r"^([\w-]+)(?:\s+[^:=\n]+)?\s*:(?!=)"),
        ("Justfile", "just", r"^([\w-]+)(?:\s+[^:=\n]+)?\s*:(?!=)"),
    ]:
        path = root / source
        if path.is_file():
            for match in re.finditer(pattern, read(path), re.MULTILINE):
                for name in match[1].split():
                    if not name.startswith((".", "-")):
                        add(tool, name, [tool, name], source)
    for source in MARKERS:
        path = root / source
        if not source.endswith((".yaml", ".yml")) or not path.is_file():
            continue
        try:
            import yaml
        except ImportError:
            errors.append("Install python-yaml to discover YAML tasks.")
            break
        try:
            data = yaml.safe_load(read(path)) or {}
            field = "tasks" if source.startswith("Taskfile") else "services"
            if not isinstance(data, dict) or not isinstance(data.get(field, {}), dict):
                raise ValueError()
        except (yaml.YAMLError, OSError, ValueError):
            errors.append("Could not read " + source + ".")
            continue
        if source.startswith("Taskfile"):
            for name in data.get("tasks", {}):
                if isinstance(name, str) and not name.startswith("-"):
                    add("task", name, ["task", name], source)
        else:
            for name in data.get("services", {}):
                if isinstance(name, str) and re.fullmatch(r"[a-zA-Z0-9][\w.-]*", name):
                    add(
                        "compose",
                        name,
                        ["docker", "compose", "-f", source, "up", name],
                        source,
                    )
    return result


_cache = {}


def commands(db, project):
    root = Path(project["path"])
    stamp = tuple(
        (s, (root / s).stat().st_mtime_ns)
        for s in (*MARKERS, "yarn.lock", "pnpm-lock.yaml", "bun.lock", "bun.lockb")
        if (root / s).is_file()
    )
    cached = _cache.get(project["id"])
    if not cached or cached[0] != stamp:
        errors = []
        cached = _cache[project["id"]] = (stamp, source_commands(root, errors), errors)
    if isinstance(project, dict) and cached[2]:
        project["error"] = " ".join(cached[2])
    result = {k: dict(v) for k, v in cached[1].items()}
    for row in db.execute("SELECT * FROM commands WHERE project=?", (project["id"],)):
        data = json.loads(row["data"])
        if row["id"] in result:
            result[row["id"]].update(data)
        elif row["id"].startswith("custom:"):
            result[row["id"]] = data
    return result
