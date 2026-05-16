#!/usr/bin/env python3

import argparse
import datetime as dt
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


CONFIG_PATH = (
    Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    / "habits-server"
    / "waybar.json"
)
DEFAULT_API_BASE_URL = "https://habits.meisterlala.dev/api"
REQUEST_TIMEOUT_SECONDS = 3
USER_SERVICE_NAME = "habits.service"
DESKTOP_FILE_PATH = "/usr/share/applications/habits.desktop"
HABITS_WINDOW_CLASSES = {"habits", "habits-desktop"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Quickshell adapter for Habits.")
    parser.add_argument("--toggle-app", action="store_true", help="Launch or toggle the desktop app.")
    parser.add_argument("--set-habit", nargs=3, metavar=("DATE", "HABIT_ID", "STATUS"))
    parser.add_argument("--stop-event", nargs=2, metavar=("DATE", "EVENT_ID"))
    return parser.parse_args()


def normalize_api_base_url(raw_value: str) -> str:
    value = (raw_value or "").strip()
    if not value:
        raise ValueError("Missing api_base_url in habits config")

    parsed = urllib.parse.urlparse(value)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise ValueError("api_base_url must be an http(s) URL")

    path = parsed.path.rstrip("/")
    if not path.endswith("/api"):
        path = f"{path}/api" if path else "/api"

    return urllib.parse.urlunparse(
        parsed._replace(path=path, params="", query="", fragment="")
    )


def load_api_config() -> tuple[str, str]:
    try:
        raw = CONFIG_PATH.read_text(encoding="utf-8")
        config = json.loads(raw)
    except FileNotFoundError as exc:
        raise ValueError(f"Missing config: {CONFIG_PATH}") from exc
    except json.JSONDecodeError as exc:
        raise ValueError(f"Invalid JSON config: {CONFIG_PATH}") from exc

    if not isinstance(config, dict):
        raise ValueError(f"Invalid config shape: {CONFIG_PATH}")

    api_base_url = normalize_api_base_url(str(config.get("api_base_url", DEFAULT_API_BASE_URL)))
    api_key = str(config.get("api_key", "")).strip()
    if not api_key:
        raise ValueError(f"Missing api_key in config: {CONFIG_PATH}")
    return api_base_url, api_key


def request_json(
    api_base_url: str,
    api_key: str,
    path: str,
    method: str = "GET",
    body: object | None = None,
) -> object:
    data = None
    headers = {
        "Accept": "application/json",
        "Authorization": f"Bearer {api_key}",
        "User-Agent": "habits-quickshell/0.1",
    }
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"

    request = urllib.request.Request(
        f"{api_base_url.rstrip('/')}{path}",
        data=data,
        headers=headers,
        method=method,
    )
    with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
        if response.status == 204:
            return {}
        return json.load(response)


def as_dict(value: object) -> dict:
    return value if isinstance(value, dict) else {}


def as_list(value: object) -> list:
    return value if isinstance(value, list) else []


def number(value: object, fallback: float = 0.0) -> float:
    return float(value) if isinstance(value, (int, float)) else fallback


def format_points(value: object) -> str:
    if not isinstance(value, (int, float)):
        return "0"
    if float(value).is_integer():
        return str(int(value))
    return f"{value:.1f}".rstrip("0").rstrip(".")


def format_signed_points(value: object) -> str:
    if not isinstance(value, (int, float)):
        return "0"
    sign = "+" if value > 0 else ""
    return f"{sign}{format_points(value)}"


def is_habit_done(habit: dict) -> bool:
    if habit.get("status") == "done":
        return True
    effective_points = habit.get("effective_points")
    return isinstance(effective_points, (int, float)) and effective_points > 0


def habit_effective_points(habit: dict) -> float:
    effective_points = habit.get("effective_points")
    if isinstance(effective_points, (int, float)):
        return float(effective_points)
    if is_habit_done(habit):
        return number(habit.get("points_done"))
    return number(habit.get("points_missed"))


def parse_date(value: object) -> dt.date | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        return dt.date.fromisoformat(value[:10])
    except ValueError:
        return None


def days_until(value: object, today: str) -> int | None:
    due = parse_date(value)
    reference = parse_date(today) or dt.datetime.now().date()
    if due is None:
        return None
    return (due - reference).days


def due_label(value: object, today: str) -> str:
    remaining = days_until(value, today)
    if remaining is None:
        return "No due date"
    if remaining < 0:
        return f"Overdue by {abs(remaining)}d"
    if remaining == 0:
        return "Due today"
    if remaining == 1:
        return "Due tomorrow"
    return f"Due in {remaining}d"


def format_amount_minutes(value: object) -> str:
    minutes = number(value)
    if minutes <= 0:
        return "0m"
    if minutes < 60:
        return f"{int(round(minutes))}m"
    hours = int(minutes // 60)
    rest = int(round(minutes % 60))
    if rest == 0:
        return f"{hours}h"
    return f"{hours}h {rest}m"


def policy_sort_key(policy: dict) -> tuple[float, str]:
    return (number(policy.get("points_delta")), str(policy.get("window_end", "")))


def visible_habits(day_view: dict) -> list[dict]:
    result = []
    for habit in as_list(day_view.get("habits")):
        if not isinstance(habit, dict):
            continue
        if habit.get("visibility") == "hidden":
            continue
        result.append(
            {
                "id": str(habit.get("id", "")),
                "name": str(habit.get("name", habit.get("id", "Habit"))),
                "status": str(habit.get("status", "")),
                "done": is_habit_done(habit),
                "points_done": habit.get("points_done", 0),
                "points_missed": habit.get("points_missed", 0),
                "effective_points": habit_effective_points(habit),
                "points_label": format_signed_points(habit_effective_points(habit)),
            }
        )
    return result


def event_view(event: dict) -> dict:
    amount = event.get("amount", 0)
    earned = event.get("earned_points", 0)
    return {
        "id": str(event.get("id", "")),
        "name": str(event.get("name", event.get("id", "Event"))),
        "is_active": bool(event.get("is_active")),
        "amount": amount,
        "amount_label": format_amount_minutes(amount),
        "earned_points": earned,
        "points_label": format_signed_points(earned),
    }


def active_events(day_view: dict) -> list[dict]:
    return [
        event_view(event)
        for event in as_list(day_view.get("events"))
        if isinstance(event, dict)
        and event.get("visibility") == "shown"
        and bool(event.get("is_active"))
    ]


def nonzero_events(day_view: dict) -> list[dict]:
    return [
        event_view(event)
        for event in as_list(day_view.get("events"))
        if isinstance(event, dict)
        and event.get("visibility") == "shown"
        and not bool(event.get("is_active"))
        and isinstance(event.get("amount"), (int, float))
        and event.get("amount") not in (0, 0.0)
    ]


def relevant_policies(policies: list) -> list[dict]:
    result = []
    for policy in policies:
        if not isinstance(policy, dict):
            continue
        status = str(policy.get("status", ""))
        points_delta = policy.get("points_delta", 0)
        if status in {"", "ok", "inactive"} and not (
            isinstance(points_delta, (int, float)) and points_delta < 0
        ):
            continue
        display = as_dict(policy.get("display"))
        target = display.get("min", display.get("min_occurrences", policy.get("target_value", 0)))
        result.append(
            {
                "id": str(policy.get("id", "")),
                "description": str(policy.get("description", policy.get("id", "Policy"))),
                "status": status.replace("_", " "),
                "message": str(policy.get("message", "")),
                "points_delta": points_delta,
                "points_label": format_signed_points(points_delta),
                "current_value": policy.get("current_value", 0),
                "target_value": target,
                "progress_label": f"{format_points(policy.get('current_value', 0))}/{format_points(target)}",
                "window_end": str(policy.get("window_end", "")),
            }
        )
    result.sort(key=policy_sort_key)
    return result


def persistent_notifications(response: dict) -> list[dict]:
    result = []
    for item in as_list(response.get("notifications")):
        if not isinstance(item, dict):
            continue
        progress = as_dict(item.get("progress"))
        current = progress.get("current")
        maximum = progress.get("max")
        progress_label = ""
        if isinstance(current, (int, float)) and isinstance(maximum, (int, float)) and maximum > 0:
            progress_label = f"{format_amount_minutes(current)} / {format_amount_minutes(maximum)}"
        result.append(
            {
                "id": str(item.get("id", "")),
                "category": str(item.get("category", "")),
                "title": str(item.get("title", "Notification")),
                "description": str(item.get("description", "")),
                "progress_current": current if isinstance(current, (int, float)) else 0,
                "progress_max": maximum if isinstance(maximum, (int, float)) else 0,
                "progress_label": progress_label,
            }
        )
    return result


def active_deadlines(response: dict, today: str) -> list[dict]:
    result = []
    for deadline in as_list(response.get("deadlines")):
        if not isinstance(deadline, dict) or deadline.get("status") != "active":
            continue
        due_value = deadline.get("due_date") or deadline.get("due_at")
        result.append(
            {
                "id": str(deadline.get("id", "")),
                "title": str(deadline.get("title", "Deadline")),
                "description": str(deadline.get("description", "")),
                "due": str(due_value or ""),
                "due_label": due_label(due_value, today),
                "days_until": days_until(due_value, today),
            }
        )
    result.sort(key=lambda item: 99999 if item["days_until"] is None else item["days_until"])
    return result


def active_contracts(response: dict) -> list[dict]:
    result = []
    for contract in as_list(response.get("today_active")):
        if not isinstance(contract, dict):
            continue
        result.append(
            {
                "id": str(contract.get("id", "")),
                "name": str(contract.get("name", contract.get("id", "Contract"))),
                "description": str(contract.get("description", "")),
            }
        )
    return result


def tier_name(summary: dict) -> str:
    tier = as_dict(summary.get("current_tier"))
    return str(tier.get("name") or tier.get("id") or "Unknown")


def build_text(summary: dict, policies: list, deadlines: list, notifications: list, events: list) -> str:
    done = int(summary.get("habits_done", 0) or 0)
    total = int(summary.get("habits_total", 0) or 0)
    text = f"{done}/{total}"
    if events:
        text += f" 󰥔{len(events)}"
    alerts = len(policies) + len(deadlines)
    if alerts:
        text += f" 󰄬{alerts}"
    if notifications:
        text += f" {len(notifications)}"
    return text


def build_payload(
    summary: dict,
    tomorrow_summary: dict,
    weight_summary: dict,
    punishment_status: dict,
    day_view: dict,
    policies_response: list,
    contracts_response: dict,
    notifications_response: dict,
    deadlines_response: dict,
) -> dict:
    today = str(summary.get("date") or day_view.get("date") or dt.datetime.now().date())
    habits = visible_habits(day_view)
    events_active = active_events(day_view)
    events_nonzero = nonzero_events(day_view)
    policies = relevant_policies(policies_response)
    notifications = persistent_notifications(notifications_response)
    deadlines = active_deadlines(deadlines_response, today)
    contracts = active_contracts(contracts_response)
    done = int(summary.get("habits_done", 0) or 0)
    total = int(summary.get("habits_total", 0) or 0)
    has_attention = bool(events_active or notifications)
    if total > 0 and done >= total and not has_attention:
        state = "done"
    elif has_attention:
        state = "warning"
    elif done > 0:
        state = "active"
    else:
        state = "pending"

    rolling_delta = None
    if isinstance(summary.get("recent_points"), (int, float)) and isinstance(
        tomorrow_summary.get("recent_points"), (int, float)
    ):
        rolling_delta = tomorrow_summary["recent_points"] - summary["recent_points"]

    latest_weight = as_dict(weight_summary.get("latest_weight"))
    return {
        "ok": True,
        "date": today,
        "text": build_text(summary, policies, deadlines, notifications, events_active),
        "state": state,
        "summary": {
            "habits_done": done,
            "habits_total": total,
            "points_today": summary.get("points_today", 0),
            "points_today_label": format_signed_points(summary.get("points_today", 0)),
            "banked_points": summary.get("banked_points", 0),
            "banked_points_label": format_points(summary.get("banked_points", 0)),
            "punishment_points": punishment_status.get("negative_banked_points", 0),
            "punishment_points_label": format_points(punishment_status.get("negative_banked_points", 0)),
            "recent_points": summary.get("recent_points", 0),
            "recent_points_label": format_points(summary.get("recent_points", 0)),
            "rolling_delta": rolling_delta,
            "rolling_delta_label": format_signed_points(rolling_delta) if rolling_delta is not None else "",
            "tier": tier_name(summary),
            "weight_label": f"{latest_weight.get('weight_kg'):.1f}kg" if isinstance(latest_weight.get("weight_kg"), (int, float)) else "",
        },
        "habits": habits,
        "active_events": events_active,
        "events": events_nonzero,
        "policies": policies,
        "notifications": notifications,
        "deadlines": deadlines,
        "contracts": contracts,
        "counts": {
            "active_events": len(events_active),
            "notifications": len(notifications),
            "policies": len(policies),
            "deadlines": len(deadlines),
        },
    }


def error_payload(message: str) -> dict:
    return {
        "ok": False,
        "text": "?/?",
        "state": "error",
        "error": message,
        "summary": {},
        "habits": [],
        "active_events": [],
        "events": [],
        "policies": [],
        "notifications": [],
        "deadlines": [],
        "contracts": [],
        "counts": {},
    }


def start_user_service() -> None:
    if shutil.which("systemctl"):
        subprocess.run(
            ["systemctl", "--user", "start", USER_SERVICE_NAME],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


def hyprctl_json(args: list[str]) -> object | None:
    if not shutil.which("hyprctl"):
        return None
    try:
        proc = subprocess.run(
            ["hyprctl", *args, "-j"],
            check=False,
            capture_output=True,
            text=True,
            timeout=1,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if proc.returncode != 0 or not proc.stdout.strip():
        return None
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return None


def current_hypr_workspace() -> str | None:
    workspace = hyprctl_json(["activeworkspace"])
    if not isinstance(workspace, dict):
        return None
    name = str(workspace.get("name", "")).strip()
    return name or str(workspace.get("id", "")).strip() or None


def find_habits_window() -> str | None:
    clients = hyprctl_json(["clients"])
    if not isinstance(clients, list):
        return None
    for client in clients:
        if not isinstance(client, dict):
            continue
        window_class = str(client.get("class", "")).lower()
        if window_class in HABITS_WINDOW_CLASSES:
            address = str(client.get("address", "")).strip()
            if address:
                return address
    return None


def move_habits_to_current_workspace(workspace: str | None) -> None:
    if not workspace or not shutil.which("hyprctl"):
        return
    for _ in range(10):
        address = find_habits_window()
        if address:
            subprocess.run(
                [
                    "hyprctl",
                    "dispatch",
                    "movetoworkspacesilent",
                    f"name:{workspace},address:{address}",
                ],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            subprocess.run(
                ["hyprctl", "dispatch", "focuswindow", f"address:{address}"],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            return
        time.sleep(0.1)


def launch_desktop_app() -> int:
    workspace = current_hypr_workspace()
    start_user_service()
    commands = []
    if shutil.which("habits"):
        commands.append(["habits", "--toggle"])
    if shutil.which("flatpak"):
        commands.append(["flatpak", "run", "dev.meisterlala.habits", "--toggle"])
    if shutil.which("gtk-launch"):
        commands.append(["gtk-launch", "habits"])
        commands.append(["gtk-launch", "dev.meisterlala.habits"])
    if shutil.which("gio"):
        commands.append(["gio", "launch", DESKTOP_FILE_PATH])

    for command in commands:
        try:
            subprocess.Popen(
                command,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                close_fds=True,
                start_new_session=True,
            )
            move_habits_to_current_workspace(workspace)
            return 0
        except OSError:
            continue
    print("Unable to launch Habits desktop app", file=sys.stderr)
    return 1


def set_habit(api_base_url: str, api_key: str, date: str, habit_id: str, status: str) -> None:
    if status not in {"done", "missed"}:
        raise ValueError("Habit status must be done or missed")
    escaped_date = urllib.parse.quote(date, safe="")
    escaped_id = urllib.parse.quote(habit_id, safe="")
    request_json(
        api_base_url,
        api_key,
        f"/days/{escaped_date}/habits/{escaped_id}",
        method="PUT",
        body={"status": status},
    )


def stop_event(api_base_url: str, api_key: str, date: str, event_id: str) -> None:
    escaped_date = urllib.parse.quote(date, safe="")
    escaped_id = urllib.parse.quote(event_id, safe="")
    request_json(
        api_base_url,
        api_key,
        f"/days/{escaped_date}/events/{escaped_id}/stop",
        method="POST",
        body={},
    )


def render_status(api_base_url: str, api_key: str) -> dict:
    health = as_dict(request_json(api_base_url, api_key, "/health"))
    if health.get("status") != "OK" or health.get("app") != "habits-api":
        return error_payload("Habits API is not healthy")

    summary = as_dict(request_json(api_base_url, api_key, "/summary/today"))
    tomorrow_summary = as_dict(request_json(api_base_url, api_key, "/summary/tomorrow"))
    weight_summary = as_dict(request_json(api_base_url, api_key, "/summary/weight"))
    punishment_status = as_dict(request_json(api_base_url, api_key, "/punishments/status"))
    day_view = as_dict(request_json(api_base_url, api_key, "/days/today"))
    policies = as_list(request_json(api_base_url, api_key, "/policies/status"))
    contracts = as_dict(request_json(api_base_url, api_key, "/contracts/status"))
    notifications = as_dict(request_json(api_base_url, api_key, "/notifications/persistent"))
    deadlines = as_dict(request_json(api_base_url, api_key, "/deadlines"))
    return build_payload(
        summary,
        tomorrow_summary,
        weight_summary,
        punishment_status,
        day_view,
        policies,
        contracts,
        notifications,
        deadlines,
    )


def main() -> int:
    args = parse_args()
    if args.toggle_app:
        return launch_desktop_app()

    try:
        api_base_url, api_key = load_api_config()
        if args.set_habit:
            set_habit(api_base_url, api_key, *args.set_habit)
            return 0
        if args.stop_event:
            stop_event(api_base_url, api_key, *args.stop_event)
            return 0
        payload = render_status(api_base_url, api_key)
    except urllib.error.HTTPError as exc:
        if args.set_habit or args.stop_event:
            print(f"Habits API returned HTTP {exc.code}", file=sys.stderr)
            return 1
        payload = error_payload(f"Habits API returned HTTP {exc.code}")
    except (urllib.error.URLError, TimeoutError):
        if args.set_habit or args.stop_event:
            print("Habits API unreachable", file=sys.stderr)
            return 1
        payload = error_payload("Habits API unreachable")
    except (ValueError, json.JSONDecodeError) as exc:
        if args.set_habit or args.stop_event:
            print(str(exc), file=sys.stderr)
            return 1
        payload = error_payload(str(exc))

    json.dump(payload, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
