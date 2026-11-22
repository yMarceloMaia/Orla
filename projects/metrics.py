"""Sample only this user's host processes; account container usage separately."""

import ipaddress
import os
import re
import sys
import time
from collections import deque
from pathlib import Path

TICKS = os.sysconf("SC_CLK_TCK")
HOST_NS = os.readlink("/proc/self/ns/pid")
CONTAINER = re.compile(r"(?:docker[-/]|cri-containerd-|libpod-)[0-9a-f]{12,}")
UNIT = re.compile(r"/orla-project-([0-9a-f]{32})\.service(?:/|$)")


def fields(path):
    return {
        k: int(v.split()[0])
        for line in path.read_text().splitlines()
        if ":" in line
        for k, v in [line.split(":", 1)]
        if v.strip().split()[0].isdigit()
    }


def listening_sockets():
    for family in ("tcp", "tcp6", "udp", "udp6"):
        protocol = family.rstrip("6")
        try:
            lines = Path("/proc/net", family).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            parts = line.split()
            if parts[3] == ("0A" if protocol == "tcp" else "07"):
                host, port = parts[1].split(":")
                yield parts[9], protocol, host, int(port, 16)


def listeners():
    return {
        inode: f"{protocol}/{port}"
        for inode, protocol, _, port in listening_sockets()
    }


def system_ports():
    sockets = {}
    for inode, protocol, host, port in listening_sockets():
        # The kernel prints each 32-bit address word in native byte order.
        raw = b"".join(
            int(host[i : i + 8], 16).to_bytes(4, sys.byteorder)
            for i in range(0, len(host), 8)
        )
        sockets[inode] = {
            "address": str(ipaddress.ip_address(raw)),
            "protocol": protocol,
            "port": port,
            "owners": [],
        }
    if not sockets:
        return []

    for process in Path("/proc").iterdir():
        if not process.name.isdecimal():
            continue
        try:
            owned = set()
            for fd in (process / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in sockets:
                    owned.add(target[8:-1])
            if owned:
                owner = {
                    "pid": int(process.name),
                    "name": (process / "comm").read_text(errors="replace").strip(),
                }
                for inode in owned:
                    sockets[inode]["owners"].append(owner)
        except OSError:
            continue

    for entry in sockets.values():
        entry["owners"].sort(key=lambda owner: owner["pid"])
    return sorted(
        sockets.values(),
        key=lambda entry: (entry["port"], entry["protocol"], entry["address"]),
    )


class Sampler:
    def __init__(self):
        self.old = {}
        self.history = {}
        self.last = None
        self.discovery_at = 0
        self.signature = None
        self.candidates = set()

    def sample(self, projects, managed, docker, detail):
        now = time.monotonic()
        age = now - self.last if self.last is not None else None
        uptime = float(Path("/proc/uptime").read_text().split()[0])
        roots = sorted(
            ((p["path"], p["id"]) for p in projects), key=lambda x: -len(x[0])
        )

        def owner(path):
            return next(
                (
                    key
                    for root, key in roots
                    if path == root or path.startswith(root + "/")
                ),
                None,
            )

        live, parents, matches = {}, {}, {}
        signature = (tuple(roots), tuple(sorted(managed.items())))
        sweep = signature != self.signature or now >= self.discovery_at
        if sweep:
            paths = Path("/proc").iterdir() if roots else ()
            self.discovery_at = now + 10
            self.signature = signature
        else:
            paths = (Path("/proc", str(pid)) for pid in self.candidates)
        for path in paths:
            if not path.name.isdigit():
                continue
            try:
                if (
                    path.stat().st_uid != os.getuid()
                    or os.readlink(path / "ns/pid") != HOST_NS
                ):
                    continue
                cg = (path / "cgroup").read_text()
                if CONTAINER.search(cg):
                    continue
                stat = (path / "stat").read_text()
                end = stat.rindex(")")
                nums = stat[end + 2 :].split()
                pid = int(path.name)
                with (path / "cmdline").open("rb") as stream:
                    cmd = stream.read(8192).split(b"\0")
                unit = UNIT.search(cg)
                project = managed.get(unit[1]) if unit else None
                reason = "Managed" if project else "Working directory"
                if not project:
                    project = owner(os.readlink(path / "cwd"))
                if not project:
                    project = next(
                        (
                            p
                            for arg in cmd[1:]
                            if arg.startswith(b"/") and (p := owner(os.fsdecode(arg)))
                        ),
                        None,
                    )
                    reason = "Path argument"
                if project:
                    matches[pid] = project, reason
                parents[pid] = int(nums[1])
                live[pid] = (
                    path,
                    stat[stat.index("(") + 1 : end],
                    nums,
                    os.path.basename(os.fsdecode(cmd[0])),
                )
            except (OSError, ValueError, IndexError):
                continue
        current = {}
        sockets = listeners() if detail and live else {}
        data = {
            p["id"]: dict(
                cpu=None,
                local=0,
                containerRam=0,
                containerCpu=None,
                processes=[],
                containers=[],
                ports=set(),
            )
            for p in projects
        }
        for pid, (path, name, nums, exe) in live.items():
            ancestor, seen = pid, set()
            while (
                ancestor not in matches and ancestor in parents and ancestor not in seen
            ):
                seen.add(ancestor)
                ancestor = parents[ancestor]
            if ancestor not in matches:
                continue
            project, reason = matches[ancestor]
            if project not in data:
                continue
            try:
                key = pid, nums[19]
                ticks = int(nums[11]) + int(nums[12])
                try:
                    ram = fields(path / "smaps_rollup")["Pss"] * 1024
                    memory = "PSS"
                except (OSError, KeyError):
                    ram = int(nums[21]) * os.sysconf("SC_PAGE_SIZE")
                    memory = "Estimated RSS"
                try:
                    io = fields(path / "io")
                except OSError:
                    io = {}
                old = self.old.get(key)
                cpu = (
                    max(0, (ticks - old) / TICKS / age * 100)
                    if old is not None and age
                    else None
                )
                current[key] = ticks
                row = data[project]
                if cpu is not None:
                    row["cpu"] = (row["cpu"] or 0) + cpu
                row["local"] += ram
                row["processes"].append(
                    dict(
                        pid=pid,
                        name=name,
                        command=exe,
                        cpu=cpu,
                        ram=ram,
                        memory=memory,
                        seconds=int(uptime - int(nums[19]) / TICKS),
                        state=nums[0],
                        association=reason
                        if ancestor == pid
                        else "Inferred subprocess",
                        read=io.get("read_bytes"),
                        write=io.get("write_bytes"),
                    )
                )
                if detail and os.readlink(path / "ns/net") == os.readlink(
                    "/proc/self/ns/net"
                ):
                    for fd in (path / "fd").iterdir():
                        try:
                            target = os.readlink(fd)
                            if (
                                target.startswith("socket:[")
                                and target[8:-1] in sockets
                            ):
                                row["ports"].add(sockets[target[8:-1]])
                        except OSError:
                            pass
            except (OSError, ValueError, IndexError):
                continue
        for c in docker:
            owners = [p["id"] for p in projects if c["project"] in p["compose"]]
            if len(owners) != 1:
                continue
            row = data[owners[0]]
            row["containers"].append(c)
            row["ports"].update(c.get("urls", []))
            row["containerRam"] += c.get("ram") or 0
            if c.get("cpu") is not None:
                row["containerCpu"] = (row["containerCpu"] or 0) + c["cpu"]
        self.history = {k: v for k, v in self.history.items() if k in data}
        for key, row in data.items():
            row["ports"] = sorted(row["ports"])
            row["processes"].sort(key=lambda r: (r["cpu"] or 0, r["ram"]), reverse=True)
            row["total"] = row["local"] + row["containerRam"]
            row["partial"] = any(
                c["state"] == "running" and c.get("ram") is None
                for c in row["containers"]
            )
            row["totalCpu"] = (row["cpu"] or 0) + (row["containerCpu"] or 0)
            row["cpuPartial"] = any(p["cpu"] is None for p in row["processes"]) or any(
                c["state"] == "running" and c.get("cpu") is None
                for c in row["containers"]
            )
            row["approxMemory"] = any(p["memory"] != "PSS" for p in row["processes"])
            history = self.history.setdefault(key, deque(maxlen=60))
            history.append([round(row["totalCpu"], 1), row["total"]])
            row["history"] = list(history)
        self.candidates = {pid for pid, _ in current}
        self.old, self.last = current, now
        return data
