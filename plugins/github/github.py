import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def github_activity(org):
    from datetime import datetime, timezone

    now = datetime.now(timezone.utc)
    year = str(now.year)
    cmd = ["gh", "api", "--hostname", "github.com", "graphql", "-f",
           "query=" + (ROOT / "github.graphql").read_text(), "-f", "from=" + year + "-01-01T00:00:00Z", "-f", "to=" + now.isoformat()]
    search = "is:pr is:open"
    if org:
        if not isinstance(org, str) or not re.fullmatch(r"[a-zA-Z0-9-]+", org):
            raise ValueError("Organização inválida")
        org_id = subprocess.check_output(["gh", "api", "--hostname", "github.com", "orgs/" + org,
                                          "--jq", ".node_id"], text=True, timeout=20).strip()
        cmd.extend(["-f", "orgId=" + org_id])
        search += " -user:" + org
    cmd.extend(["-F", "exclude=" + str(bool(org)).lower(),
                "-f", "reviewsQuery=" + search + " review-requested:@me",
                "-f", "authoredQuery=" + search + " author:@me"])

    def fetch(*variables):
        result = subprocess.run(cmd + list(variables), capture_output=True, text=True, timeout=30, check=True)
        return json.loads(result.stdout)["data"]

    data = fetch("-F", "overview=true")
    authored = data["authored"]
    page = authored
    while page["pageInfo"]["hasNextPage"]:
        page = fetch("-F", "overview=false", "-f", "cursor=" + page["pageInfo"]["endCursor"])["authored"]
        authored["nodes"].extend(page["nodes"])
    cal = data["viewer"]["contributionsCollection"]["contributionCalendar"]
    levels = ["NONE", "FIRST_QUARTILE", "SECOND_QUARTILE", "THIRD_QUARTILE", "FOURTH_QUARTILE"]
    excluded = {day["date"]: day["contributionCount"]
                for week in data["viewer"]["excluded"]["contributionCalendar"]["weeks"]
                for day in week["contributionDays"]} if org else {}
    total = 0
    weeks = []
    for week in cal["weeks"]:
        days = [-1] * 7
        for day in week["contributionDays"]:
            if day["date"].startswith(year):
                count = max(0, day["contributionCount"] - excluded.get(day["date"], 0))
                total += count
                original = day["contributionCount"]
                days[day["weekday"]] = max(1, round(levels.index(day["contributionLevel"]) * count / original)) if count else 0
        weeks.append(days)
    payload = dict(total=total, weeks=weeks, search=search, login=data["viewer"]["login"], alerts={})
    for group in ("reviews", "authored"):
        rows = []
        for pr in filter(None, data[group]["nodes"]):
            if group == "authored":
                payload["alerts"][pr["url"]] = dict(count=pr["totalCommentsCount"], merge=pr["mergeable"],
                                                     created=pr["createdAt"], repo=pr["repository"]["nameWithOwner"],
                                                     number=pr["number"])
            if len(rows) >= 20:
                continue
            commits = pr["commits"]["nodes"]
            rollup = commits[-1]["commit"]["statusCheckRollup"] if commits else None
            rows.append(dict(title=pr["title"], url=pr["url"], repo=pr["repository"]["nameWithOwner"],
                             head=pr["headRefName"], base=pr["baseRefName"], conflict=pr.get("mergeable") == "CONFLICTING",
                             number=pr["number"], checks=rollup["state"] if rollup else "NONE"))
        payload[group] = dict(count=data[group]["issueCount"], rows=rows)
    return payload


if __name__ == "__main__":
    try:
        payload = github_activity(sys.argv[1] if len(sys.argv) > 1 else "")
    except FileNotFoundError:
        payload = {"error": "Instale o GitHub CLI (gh) para conectar sua conta."}
    except (subprocess.SubprocessError, ValueError, KeyError, TypeError):
        payload = {"error": "Falha ao consultar o GitHub. Verifique a conexão e o login do gh."}
    print(json.dumps(payload))
