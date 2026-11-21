"""Follow a single supervised run using its existing filtered log."""
import os
import sqlite3
import sys
import time
from pathlib import Path


def printable(text):
    return "".join(c for c in str(text) if c.isprintable() or c == "\t")


def follow(run_id):
    root = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
    path = root / "orla/projects/registry.sqlite"
    db = sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True)
    cursor = 0
    heading = True
    try:
        while True:
            db.execute("BEGIN")
            run = db.execute("SELECT cmd,state,ended,code FROM runs WHERE id=?", (run_id,)).fetchone()
            rows = db.execute("SELECT n,line FROM logs WHERE run=? AND n>? ORDER BY n", (run_id,cursor)).fetchall()
            db.commit()
            if not run:
                print("Execução indisponível no histórico.")
                return
            if heading:
                print(f"{printable(run[0])}  ·  {printable(run[1])}\n", flush=True)
                heading = False
            for cursor, line in rows:
                print(printable(line), flush=True)
            if run[2] is not None:
                code = f" (saída {run[3]})" if run[3] is not None else ""
                print(f"\n{printable(run[1])}{code}", flush=True)
                return
            time.sleep(0.5)
    finally:
        db.close()


if __name__ == "__main__":
    try:
        follow(sys.argv[1])
        if sys.stdin.isatty():
            input("\nPressione Enter para fechar.")
    except (KeyboardInterrupt, EOFError):
        pass
    except sqlite3.Error as exc:
        sys.exit(f"Falha ao abrir o histórico: {exc}")
