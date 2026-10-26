#!/usr/bin/env python3
"""Notification-center controls. No SwayNC dependency or background polling."""
import json
import subprocess
import sys

MONITOR_DESCRIPTION = "Acer Technologies ED270U P TKYEE0013W01"
INHIBIT_UNIT = "quickshell-idle-inhibit.service"


def run(*args):
    return subprocess.run(args, text=True, capture_output=True, timeout=5)


def inhibited():
    result = run("systemctl", "--user", "is-active", INHIBIT_UNIT)
    if result.returncode not in (0, 3, 4):
        raise RuntimeError(result.stderr.strip() or "Could not query sleep inhibition")
    return result.stdout.strip() in ("active", "activating")


def monitor():
    result = run("hyprctl", "monitors", "all", "-j")
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "Could not query monitors")
    return next((item for item in json.loads(result.stdout)
                 if item.get("description") == MONITOR_DESCRIPTION), None)


def monitor_state(target):
    if target is None:
        return "missing"
    if target.get("disabled"):
        return "disabled"
    return "on" if target.get("dpmsStatus") else "off"


def collect():
    return {"inhibited": inhibited(), "monitor": monitor_state(monitor()), "error": ""}


def toggle_idle():
    if inhibited():
        result = run("systemctl", "--user", "stop", INHIBIT_UNIT)
    else:
        result = run("systemd-run", "--user", "--quiet", "--collect",
                     "--unit=" + INHIBIT_UNIT, "--", "systemd-inhibit",
                     "--what=idle", "--who=Quickshell", "--why=Stay awake toggle",
                     "--mode=block", "sleep", "infinity")
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "Could not toggle sleep inhibition")


def toggle_monitor():
    target = monitor()
    state = monitor_state(target)
    if state not in ("on", "off"):
        raise RuntimeError("Second monitor is " + state)
    # Preserve the existing helper's DPMS behavior; do not disable/rearrange it.
    dispatch = 'hl.dsp.dpms({ state = "%s", monitor = %s })' % (
        "off" if state == "on" else "on", json.dumps(target["name"]))
    result = run("hyprctl", "dispatch", dispatch)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "Could not toggle second monitor")


def main():
    try:
        action = sys.argv[1] if len(sys.argv) > 1 else "status"
        if action == "idle":
            toggle_idle()
        elif action == "monitor":
            toggle_monitor()
        elif action != "status":
            raise ValueError("Expected status, idle, or monitor")
        print(json.dumps(collect()))
        return 0
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(json.dumps({"error": str(error)}))
        return 1


if __name__ == "__main__":
    sys.exit(main())
