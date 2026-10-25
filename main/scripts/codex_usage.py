#!/usr/bin/env python3
"""Fetch OpenAI Codex usage and print JSON for Quickshell."""

import datetime
import json
import os
import selectors
import subprocess
import time


CODEX_COMMAND = ["/usr/bin/codex", "app-server"]
CLIENT_INFO = {"name": "quickshell-codex-usage", "version": "1.0"}
REQUEST_TIMEOUT_SECONDS = 15


def human_delta(dt, now):
    if not dt:
        return ""

    delta = dt - now
    secs = int(delta.total_seconds())
    if secs <= 0:
        return "now"

    days, rem = divmod(secs, 86400)
    hours, rem = divmod(rem, 3600)
    mins, _ = divmod(rem, 60)

    res = []
    if days:
        res.append(f"{days}d")
    if hours:
        res.append(f"{hours}h")
    res.append(f"{mins}m")
    return "".join(res)


def call_rate_limits():
    proc = subprocess.Popen(
        CODEX_COMMAND,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        bufsize=0,
    )
    selector = selectors.DefaultSelector()

    def send(msg):
        assert proc.stdin is not None
        proc.stdin.write((json.dumps(msg) + "\n").encode())
        proc.stdin.flush()

    try:
        assert proc.stdout is not None
        selector.register(proc.stdout, selectors.EVENT_READ)
        send(
            {
                "jsonrpc": "2.0",
                "id": "1",
                "method": "initialize",
                "params": {
                    "clientInfo": CLIENT_INFO,
                    "capabilities": {"experimentalApi": True},
                },
            }
        )

        deadline = time.monotonic() + REQUEST_TIMEOUT_SECONDS
        initialized_sent = False
        buffer = b""
        while (remaining := deadline - time.monotonic()) > 0:
            if not selector.select(remaining):
                break
            chunk = os.read(proc.stdout.fileno(), 65536)
            if not chunk:
                break
            buffer += chunk
            while b"\n" in buffer:
                line, buffer = buffer.split(b"\n", 1)
                try:
                    msg = json.loads(line)
                except (json.JSONDecodeError, UnicodeDecodeError):
                    continue
                if not isinstance(msg, dict):
                    continue

                request_id = str(msg.get("id"))
                if request_id in ("1", "2") and msg.get("error"):
                    error = msg["error"]
                    message = error.get("message", str(error)) if isinstance(error, dict) else str(error)
                    return None, message
                if request_id == "1" and not initialized_sent:
                    initialized_sent = True
                    send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
                    send(
                        {
                            "jsonrpc": "2.0",
                            "id": "2",
                            "method": "account/rateLimits/read",
                            "params": {},
                        }
                    )
                elif request_id == "2":
                    res = msg.get("result") or {}
                    return (res.get("rateLimits") or {}), None

        return None, "No account/rateLimits/read response from codex app-server"
    finally:
        selector.close()
        if proc.stdin is not None:
            try:
                proc.stdin.close()
            except OSError:
                pass
        try:
            proc.terminate()
            proc.wait(timeout=1)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        finally:
            if proc.stdout is not None:
                proc.stdout.close()


def usage_window(label, window, now):
    window = window or {}
    try:
        used = int(round(float(window.get("usedPercent", 0))))
    except (TypeError, ValueError):
        used = 0

    resets_at = window.get("resetsAt")
    try:
        reset_dt = (
            datetime.datetime.fromtimestamp(int(resets_at), datetime.timezone.utc)
            if resets_at is not None
            else None
        )
    except (TypeError, ValueError, OSError):
        reset_dt = None

    return {
        "label": label,
        "available": bool(window),
        "usedPercent": max(0, min(100, used)),
        "resetIn": human_delta(reset_dt, now) if reset_dt else "",
        "resetAt": reset_dt.astimezone().strftime("%H:%M" if label == "5h" else "%d.%m")
        if reset_dt
        else "",
    }


def rate_limit_windows(limits, now):
    windows = {"5h": usage_window("5h", {}, now), "7d": usage_window("7d", {}, now)}
    for window in (limits.get("primary"), limits.get("secondary")):
        if not window:
            continue

        try:
            duration = int(window.get("windowDurationMins"))
        except (TypeError, ValueError):
            continue

        # Codex names these primary/secondary, but their positions are not stable.
        if duration == 300:
            windows["5h"] = usage_window("5h", window, now)
        elif duration == 10080:
            windows["7d"] = usage_window("7d", window, now)

    return windows


def main():
    try:
        limits, err = call_rate_limits()
    except FileNotFoundError:
        print(json.dumps({"error": "codex CLI not found"}))
        return
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        return

    if not limits:
        print(json.dumps({"error": err or "No usage data (run `codex login`)"}))
        return

    now = datetime.datetime.now(datetime.timezone.utc)
    windows = rate_limit_windows(limits, now)
    primary = windows["5h"]
    secondary = windows["7d"]
    max_pct = max(primary["usedPercent"], secondary["usedPercent"])

    state = "critical" if max_pct >= 90 else "warning" if max_pct >= 66 else "normal"
    credits = limits.get("credits") or {}

    print(
        json.dumps(
            {
                "state": state,
                "primary": primary,
                "secondary": secondary,
                "credits": {
                    "hasCredits": bool(credits.get("hasCredits", False)),
                    "unlimited": bool(credits.get("unlimited", False)),
                    "balance": credits.get("balance"),
                },
            }
        )
    )


if __name__ == "__main__":
    main()
