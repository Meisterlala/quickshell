#!/usr/bin/env python3
"""Report failed services without mistaking a failed query for a healthy system."""

import json
import os
import subprocess


def query_units(user=False):
    command = ["systemctl"]
    if user:
        command.append("--user")
    command.extend(["--failed", "--type=service", "--no-legend", "--plain"])
    environment = dict(os.environ)
    runtime = environment.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    environment.setdefault("DBUS_SESSION_BUS_ADDRESS", f"unix:path={runtime}/bus")
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=5, env=environment)
    except (OSError, subprocess.TimeoutExpired) as error:
        return None, str(error)
    if result.returncode:
        return None, result.stderr.strip() or f"systemctl exited with {result.returncode}"
    return [line.split()[0] for line in result.stdout.splitlines() if line.strip()], ""


def collect():
    system, system_error = query_units()
    user, user_error = query_units(user=True)
    errors = []
    if system_error:
        errors.append("System services: " + system_error)
    if user_error:
        errors.append("User services: " + user_error)
    return {"systemUnits": system, "userUnits": user, "error": "\n".join(errors)}


if __name__ == "__main__":
    print(json.dumps(collect()))
