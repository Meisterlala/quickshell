#!/usr/bin/env python3
"""Fetch Alertmanager alerts and print structured JSON for Quickshell."""

import datetime as dt
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlparse


ICON_ALERT = ""
ICON_ERROR = ""
TIMEOUT = os.environ.get("K8S_ALERTS_TIMEOUT", "8s")
URL_RE = re.compile(r"https?://[^\s)\]>\"']+")


def emit(payload: dict) -> None:
    print(json.dumps(payload, ensure_ascii=False))


def error_out(message: str, context: str = "", namespace: str = "") -> None:
    emit(
        {
            "text": ICON_ERROR,
            "tooltip": message,
            "class": "critical",
            "state": "error",
            "error": message,
            "context": context,
            "namespace": namespace,
            "watchdogRunning": False,
            "counts": {"total": 0, "critical": 0, "error": 1, "warning": 0, "info": 0, "unknown": 0},
            "alerts": [],
        }
    )
    sys.exit(0)


def run(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, capture_output=True, text=True)


def run_kubectl(args: list[str]) -> str:
    proc = run(["kubectl", f"--request-timeout={TIMEOUT}", *args])
    if proc.returncode != 0:
        return ""
    return proc.stdout


def find_cache_file() -> Path:
    cache_home = Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "quickshell"
    try:
        cache_home.mkdir(parents=True, exist_ok=True)
        return cache_home / "alertmanager-namespace"
    except Exception:
        return Path(f"/tmp/quickshell-alertmanager-namespace-{os.getuid()}")


def discover_namespace() -> str:
    raw = run_kubectl(["get", "svc", "-A", "-o", "json"])
    if not raw:
        return ""
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return ""
    for item in data.get("items", []):
        md = item.get("metadata", {})
        if md.get("name") == "alertmanager-operated":
            return md.get("namespace", "")
    return ""


def get_namespace(cache_file: Path) -> str:
    env_ns = os.environ.get("ALERTMANAGER_NAMESPACE", "").strip()
    if env_ns:
        return env_ns
    if cache_file.exists():
        cached = cache_file.read_text(encoding="utf-8").strip()
        if cached:
            return cached
    ns = discover_namespace()
    if ns:
        try:
            cache_file.write_text(ns + "\n", encoding="utf-8")
        except Exception:
            pass
    return ns


def shorten_urls(value: str) -> str:
    def repl(match: re.Match[str]) -> str:
        raw_url = match.group(0)
        parsed = urlparse(raw_url)
        host = (parsed.netloc or parsed.path).rstrip("/")
        return host or raw_url

    return URL_RE.sub(repl, value)


def format_time(value: str) -> str:
    if not value:
        return ""
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return value
    return parsed.astimezone().strftime("%d.%m %H:%M")


def alert_message(alert: dict) -> str:
    ann = alert.get("annotations", {})
    message = ann.get("summary") or ann.get("description") or ann.get("message") or ""
    return shorten_urls(str(message).replace("\\n", "\n")).strip()


def normalize_alert(alert: dict) -> dict:
    labels = alert.get("labels", {})
    ann = alert.get("annotations", {})
    severity = str(labels.get("severity", "unknown")).lower() or "unknown"
    name = str(labels.get("alertname", "unknown"))
    namespace = str(labels.get("namespace", "-"))
    message = alert_message(alert)

    return {
        "name": name,
        "namespace": namespace,
        "severity": severity,
        "summary": shorten_urls(str(ann.get("summary", "")).replace("\\n", "\n")).strip(),
        "description": shorten_urls(str(ann.get("description", "")).replace("\\n", "\n")).strip(),
        "message": message,
        "startsAt": format_time(str(alert.get("startsAt", ""))),
        "labels": {
            "pod": labels.get("pod", ""),
            "container": labels.get("container", ""),
            "job": labels.get("job", ""),
            "instance": labels.get("instance", ""),
        },
    }


def tooltip_for(alerts: list[dict], watchdog_running: bool) -> str:
    lines: list[str] = []
    if not watchdog_running:
        lines.append("Watchdog alert is missing")
    if not alerts:
        lines.append("No active alerts")
    for alert in alerts:
        message = alert.get("message", "")
        line = f"{alert['severity']}: {alert['name']} ({alert['namespace']})"
        if message:
            line += f"\n  {message}"
        lines.append(line)
    return "\n\n".join(lines)


def main() -> None:
    if run(["kubectl", "version", "--client"]).returncode != 0:
        error_out("Missing dependency: kubectl")

    ctx = run(["kubectl", "config", "current-context"])
    context = ctx.stdout.strip() if ctx.returncode == 0 else ""
    if not context:
        error_out("No current Kubernetes context configured.")

    cache_file = find_cache_file()
    namespace = get_namespace(cache_file)
    if not namespace:
        error_out("Cannot find Alertmanager service (alertmanager-operated).", context)

    raw = run_kubectl(
        [
            "get",
            "--raw",
            f"/api/v1/namespaces/{namespace}/services/http:alertmanager-operated:9093/proxy/api/v2/alerts",
        ]
    )
    if not raw:
        refreshed = discover_namespace()
        if refreshed and refreshed != namespace:
            namespace = refreshed
            try:
                cache_file.write_text(namespace + "\n", encoding="utf-8")
            except Exception:
                pass
            raw = run_kubectl(
                [
                    "get",
                    "--raw",
                    f"/api/v1/namespaces/{namespace}/services/http:alertmanager-operated:9093/proxy/api/v2/alerts",
                ]
            )

    if not raw:
        error_out("Cannot connect to cluster or Alertmanager API.", context, namespace)

    alerts: list[dict] = []
    try:
        alerts = json.loads(raw)
    except json.JSONDecodeError:
        error_out("Invalid JSON returned by Alertmanager API.", context, namespace)

    active = [a for a in alerts if a.get("status", {}).get("state") == "active"]
    watchdog_running = any(a.get("labels", {}).get("alertname", "") == "Watchdog" for a in active)
    visible = [
        a
        for a in active
        if a.get("labels", {}).get("alertname", "") not in ("Watchdog", "InfoInhibitor")
    ]
    normalized = [normalize_alert(a) for a in visible]
    normalized.sort(key=lambda a: (a["severity"], a["name"], a["namespace"]))

    counts = {"total": len(normalized), "critical": 0, "error": 0, "warning": 0, "info": 0, "unknown": 0}
    for alert in normalized:
        sev = alert["severity"]
        if sev in ("critical", "error", "warning", "info"):
            counts[sev] += 1
        else:
            counts["unknown"] += 1

    state = "ok"
    if not watchdog_running or counts["critical"] > 0:
        state = "critical"
    elif counts["error"] > 0:
        state = "error"
    elif counts["warning"] > 0 or counts["info"] > 0 or counts["unknown"] > 0:
        state = "warning"

    text = ""
    if state != "ok":
        icon = ICON_ERROR if state in ("critical", "error") else ICON_ALERT
        text = icon if counts["total"] == 0 else f"{icon} {counts['total']}"

    emit(
        {
            "text": text,
            "tooltip": tooltip_for(normalized, watchdog_running),
            "class": state,
            "state": state,
            "context": context,
            "namespace": namespace,
            "watchdogRunning": watchdog_running,
            "counts": counts,
            "alerts": normalized,
        }
    )


if __name__ == "__main__":
    main()
