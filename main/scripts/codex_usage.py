#!/usr/bin/env python3
"""Fetch OpenAI Codex usage and print JSON for Quickshell."""

import datetime
import json
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
        stderr=subprocess.PIPE,
        text=True,
    )

    def send(msg):
        assert proc.stdin is not None
        proc.stdin.write(json.dumps(msg) + "\n")
        proc.stdin.flush()

    try:
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

        deadline = time.time() + REQUEST_TIMEOUT_SECONDS
        initialized_sent = False
        while time.time() < deadline:
            assert proc.stdout is not None
            line = proc.stdout.readline()
            if not line:
                break

            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                continue

            if str(msg.get("id")) == "1" and not initialized_sent:
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
            elif str(msg.get("id")) == "2":
                res = msg.get("result") or {}
                return (res.get("rateLimits") or {}), None

        return None, "No account/rateLimits/read response from codex app-server"
    finally:
        try:
            if proc.stdin is not None:
                proc.stdin.close()
        except Exception:
            pass
        try:
            proc.terminate()
            proc.wait(timeout=1)
        except Exception:
            try:
                proc.kill()
            except Exception:
                pass


def usage_window(label, window, now):
    try:
        used = int(round(float((window or {}).get("usedPercent", 0))))
    except (TypeError, ValueError):
        used = 0

    resets_at = (window or {}).get("resetsAt")
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
        "usedPercent": max(0, min(100, used)),
        "resetIn": human_delta(reset_dt, now) if reset_dt else "",
        "resetAt": reset_dt.astimezone().strftime("%H:%M" if label == "5h" else "%d.%m")
        if reset_dt
        else "",
    }


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
    primary = usage_window("5h", limits.get("primary") or {}, now)
    secondary = usage_window("7d", limits.get("secondary") or {}, now)
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
