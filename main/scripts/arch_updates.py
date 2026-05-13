#!/usr/bin/env python3
import json
import os
import re
import shutil
import subprocess


PARU_TIMEOUT = int(os.environ.get("QUICKSHELL_UPDATES_TIMEOUT", "120"))
MAX_ITEMS = int(os.environ.get("QUICKSHELL_UPDATES_MAX_ITEMS", "160"))
LINE_RE = re.compile(
    r"^(?P<pkg>\S+)\s+(?P<old>\S+)\s+->\s+(?P<new>\S+)(?:\s+\[(?P<flag>[^\]]+)\])?$"
)


def run_cmd(args, timeout=PARU_TIMEOUT):
    try:
        proc = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return proc.returncode, proc.stdout, proc.stderr
    except Exception as exc:
        return 1, "", str(exc)


def query_repo_updates():
    if shutil.which("checkupdates"):
        return run_cmd(["checkupdates"])
    return run_cmd(["paru", "-Qu", "--repo", "--color", "never"])


def parse_upgrade_lines(raw):
    updates = []
    for line in raw.splitlines():
        line = line.strip()
        if not line:
            continue
        match = LINE_RE.match(line)
        if not match:
            continue
        flag = (match.group("flag") or "").lower()
        if "ignored" in flag:
            continue
        updates.append(
            {
                "name": match.group("pkg"),
                "old": match.group("old"),
                "new": match.group("new"),
            }
        )
    return updates


def repo_for_packages(package_names):
    if not package_names:
        return {}

    code, out, _ = run_cmd(["pacman", "-Si", *package_names], timeout=90)
    if code != 0 or not out:
        return {name: "repo" for name in package_names}

    result = {}
    current_name = ""
    current_repo = "repo"

    def flush_block():
        if current_name:
            result[current_name] = current_repo or "repo"

    for raw_line in out.splitlines() + [""]:
        line = raw_line.strip()
        if not line:
            flush_block()
            current_name = ""
            current_repo = "repo"
            continue
        if line.startswith("Name"):
            parts = line.split(":", 1)
            current_name = parts[1].strip() if len(parts) > 1 else ""
        elif line.startswith("Repository"):
            parts = line.split(":", 1)
            current_repo = parts[1].strip() if len(parts) > 1 else "repo"

    for name in package_names:
        result.setdefault(name, "repo")
    return result


def classify_updates(repo_updates, aur_updates):
    mapping = repo_for_packages([item["name"] for item in repo_updates])
    result = []

    for item in repo_updates:
        source = mapping.get(item["name"], "repo").lower()
        result.append({**item, "source": source})

    for item in aur_updates:
        source = "devel" if item["new"] == "latest-commit" else "aur"
        result.append({**item, "source": source})

    order = {
        "core": 0,
        "extra": 1,
        "multilib": 2,
        "aur": 3,
        "devel": 4,
        "repo": 5,
    }
    result.sort(key=lambda x: (order.get(x["source"], 9), x["source"], x["name"]))
    return result


def main():
    repo_code, repo_out, repo_err = query_repo_updates()
    aur_code, aur_out, aur_err = run_cmd(["paru", "-Qua", "--devel", "--color", "never"])

    if repo_code != 0 and aur_code != 0:
        print(
            json.dumps(
                {
                    "error": (repo_err or aur_err or "Failed to query updates").strip(),
                    "count": 0,
                    "state": "error",
                    "counts": {},
                    "items": [],
                }
            )
        )
        return

    items = classify_updates(parse_upgrade_lines(repo_out), parse_upgrade_lines(aur_out))
    counts = {}
    for item in items:
        counts[item["source"]] = counts.get(item["source"], 0) + 1

    count = len(items)
    state = "critical" if count >= 50 else "warning" if count >= 15 else "normal"
    print(
        json.dumps(
            {
                "count": count,
                "state": "updated" if count == 0 else state,
                "counts": counts,
                "items": items[:MAX_ITEMS],
                "truncated": max(0, count - MAX_ITEMS),
            }
        )
    )


if __name__ == "__main__":
    main()
