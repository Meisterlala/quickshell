#!/usr/bin/env python3
"""Read Thunderbird's local/offline calendars, without opening its accounts.

Requires python-dateutil. Thunderbird owns syncing; SQLite files (including WAL)
are copied to a private temporary directory because Thunderbird locks them.
"""

import argparse
import configparser
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from functools import lru_cache
from io import StringIO
import json
from pathlib import Path
import re
import shutil
import sqlite3
import tempfile
from urllib.parse import urlparse
from zoneinfo import ZoneInfo

from dateutil import parser, rrule, tz

UTC = timezone.utc
ALL_DAY = 8
DELETED = 3  # calIOfflineStorage.OFFLINE_FLAG_DELETED_RECORD
EXCLUDED_CALENDARS = {"sleep as android"}


def find_profile(root=None):
    root = root or Path.home() / ".thunderbird"
    config = configparser.ConfigParser()
    config.read(root / "profiles.ini")
    profiles = []
    for section in config.sections():
        if section.startswith("Install") and config.has_option(section, "Default"):
            profiles.append(root / config[section]["Default"])
    for section in config.sections():
        if section.startswith("Profile") and config.has_option(section, "Path"):
            path = Path(config[section]["Path"])
            if config[section].get("IsRelative", "1") == "1":
                path = root / path
            if config[section].get("Default") == "1":
                profiles.insert(0, path)
            else:
                profiles.append(path)
    for profile in profiles:
        if (profile / "prefs.js").is_file():
            return profile
    raise ValueError("No Thunderbird profile found")


def calendar_settings(profile):
    calendars = {}
    local_zone = tz.tzlocal()
    # Parse only calendar preferences, never account passwords or login data.
    for key, raw in re.findall(r'^user_pref\("(calendar\.[^"]+)", (.+)\);$',
                               (profile / "prefs.js").read_text(), re.M):
        value = json.loads(raw)
        if key == "calendar.timezone.local":
            local_zone = timezone_for(value, local_zone)
        match = re.fullmatch(r"calendar\.registry\.([^.]+)\.(.+)", key)
        if match:
            calendars.setdefault(match[1], {})[match[2]] = value
    calendars = {identifier: settings for identifier, settings in calendars.items()
                 if settings.get("name", "").strip().casefold() not in EXCLUDED_CALENDARS}
    return calendars, local_zone


@lru_cache(maxsize=64)
def named_timezone(name):
    if name.startswith("BEGIN:VTIMEZONE"):
        return tz.tzical(StringIO(name)).get()
    try:
        return ZoneInfo(name)
    except (ValueError, KeyError):
        return None


def timezone_for(name, fallback):
    if not name or name == "floating":
        return fallback
    return named_timezone(name) or fallback


def native_date(value, zone, local_zone, all_day=False):
    result = datetime.fromtimestamp(value / 1_000_000, UTC)
    if all_day:
        return result.replace(tzinfo=None)
    if not zone or zone == "floating":
        return result.replace(tzinfo=local_zone)
    return result.astimezone(timezone_for(zone, local_zone))


def file_signature(path):
    try:
        stat = path.stat()
        return stat.st_ino, stat.st_size, stat.st_mtime_ns
    except FileNotFoundError:
        return None


@contextmanager
def snapshot_database(path):
    """Never connect to/write the original database, even when it's locked."""
    with tempfile.TemporaryDirectory(prefix="qs-calendar-") as temp:
        target = Path(temp) / path.name
        sources = [path, Path(str(path) + "-wal"), Path(str(path) + "-journal")]
        for _ in range(3):
            before = [file_signature(source) for source in sources]
            for source, signature in zip(sources, before):
                destination = Path(temp) / source.name
                if signature:
                    shutil.copyfile(source, destination)
                else:
                    destination.unlink(missing_ok=True)
            if before == [file_signature(source) for source in sources]:
                break
        else:
            raise ValueError("Thunderbird is updating its calendar; try again")
        connection = sqlite3.connect(target)
        connection.row_factory = sqlite3.Row
        try:
            yield connection
        finally:
            connection.close()


def recurrence_dates(start, lines, lower, upper):
    dates = rrule.rruleset()
    dates.rdate(start)
    for line in re.sub(r"\r?\n[ \t]", "", "\n".join(lines)).splitlines():
        if not line.strip():
            continue
        header, value = line.split(":", 1)
        kind = header.split(";", 1)[0].upper()
        if kind in ("RRULE", "EXRULE"):
            # dateutil requires UTC UNTIL for aware DTSTART, while Thunderbird
            # also accepts date-only UNTIL values.
            until = re.search(r"UNTIL=([^;]+)", value)
            if until:
                end = parser.isoparse(until[1])
                if start.tzinfo and end.tzinfo is None:
                    if len(until[1]) == 8:
                        end = end.replace(hour=23, minute=59, second=59)
                    end = end.replace(tzinfo=start.tzinfo).astimezone(UTC)
                elif start.tzinfo is None:
                    end = end.replace(tzinfo=None)
                value = value.replace(until[0], "UNTIL=" + end.strftime(
                    "%Y%m%dT%H%M%S" + ("Z" if end.tzinfo else "")))
            rule = rrule.rrulestr(value, dtstart=start)
            (dates.rrule if kind == "RRULE" else dates.exrule)(rule)
        elif kind in ("RDATE", "EXDATE"):
            zone_match = re.search(r';TZID="?([^;\"]+)', header)
            zone = timezone_for(zone_match[1], start.tzinfo) if zone_match else start.tzinfo
            for raw in value.split(","):
                occurrence = parser.isoparse(raw)
                if start.tzinfo:
                    occurrence = occurrence.replace(tzinfo=zone) if not occurrence.tzinfo else occurrence
                else:
                    occurrence = occurrence.replace(tzinfo=None)
                (dates.rdate if kind == "RDATE" else dates.exdate)(occurrence)
    # Iterate lazily so an accidentally secondly recurring event stays bounded.
    for index, occurrence in enumerate(dates.xafter(lower, inc=True)):
        if occurrence >= upper or index >= 10000:
            break
        yield occurrence


def read_database(connection, calendars, local_zone, lower, upper):
    recurrence = {}
    for row in connection.execute("SELECT cal_id, item_id, icalString FROM cal_recurrence"):
        recurrence.setdefault((row["cal_id"], row["item_id"]), []).append(row["icalString"])
    locations = {}
    for row in connection.execute("SELECT cal_id, item_id, recurrence_id, value FROM cal_properties WHERE key='LOCATION'"):
        locations[(row["cal_id"], row["item_id"], row["recurrence_id"])] = row["value"]
    results = []
    for table, kind in (("cal_events", "event"), ("cal_todos", "task")):
        rows = [dict(row) for row in connection.execute(f"SELECT * FROM {table}")]
        exceptions = {(row["cal_id"], row["id"], row["recurrence_id"]) for row in rows if row["recurrence_id"] is not None}
        for row in rows:
            calendar = calendars.get(row["cal_id"])
            if not calendar or str(calendar.get("disabled", False)).lower() == "true":
                continue
            if row["offline_journal"] == DELETED or row["ical_status"] == "CANCELLED":
                continue
            if kind == "task" and (row["todo_completed"] or (row["todo_complete"] or 0) >= 100 or row["ical_status"] == "COMPLETED"):
                continue
            all_day = bool(row["flags"] & ALL_DAY)
            prefix = "event_start" if kind == "event" else ("todo_due" if row["todo_due"] is not None else "todo_entry")
            if row[prefix] is None:
                continue
            start = native_date(row[prefix], row[prefix + "_tz"], local_zone, all_day)
            end = start
            if kind == "event" and row["event_end"] is not None:
                end = native_date(row["event_end"], row["event_end_tz"], local_zone, all_day)
            duration = max(end - start, timedelta())
            if all_day and not duration:
                duration = timedelta(days=1)
            low, high = lower, upper
            if all_day:
                low, high = low.replace(tzinfo=None), high.replace(tzinfo=None)
            key = (row["cal_id"], row["id"])
            rules = recurrence.get(key, []) if row["recurrence_id"] is None else []
            starts = recurrence_dates(start, rules, low - duration, high) if rules else [start]
            for occurrence in starts:
                native = int(occurrence.replace(tzinfo=UTC).timestamp() * 1_000_000) if all_day or row[prefix + "_tz"] in (None, "floating") else int(occurrence.timestamp() * 1_000_000)
                if rules and (*key, native) in exceptions:
                    continue
                finish = occurrence + duration
                if occurrence >= high or (finish <= low and occurrence < low):
                    continue
                local_start = occurrence.replace(tzinfo=local_zone) if all_day else occurrence.astimezone(local_zone)
                local_end = finish.replace(tzinfo=local_zone) if all_day else finish.astimezone(local_zone)
                results.append({
                    "id": f"{row['cal_id']}:{row['id']}:{native}",
                    "title": row["title"] or "Untitled",
                    "start": int(local_start.timestamp() * 1000),
                    "end": int(local_end.timestamp() * 1000),
                    "date": local_start.date().isoformat(),
                    "endDate": local_end.date().isoformat(),
                    "allDay": all_day,
                    "kind": kind,
                    "calendar": calendar.get("name", "Calendar"),
                    "color": calendar.get("color", "#89dceb"),
                    "location": str(locations.get((*key, row["recurrence_id"]), "") or ""),
                })
    return results


def collect(profile, month, now=None, selected_day=None):
    calendars, local_zone = calendar_settings(profile)
    now = now or datetime.now(local_zone)
    now = now.astimezone(local_zone)
    today = now.replace(hour=0, minute=0, second=0, microsecond=0)
    first = datetime.strptime(month, "%Y-%m").replace(tzinfo=local_zone)
    next_month = (first.replace(day=28) + timedelta(days=4)).replace(day=1)
    agenda_end = today + timedelta(days=30)
    lower, upper = min(today, first), max(agenda_end, next_month)
    day_start = datetime.strptime(selected_day, "%Y-%m-%d").replace(tzinfo=local_zone) if selected_day else None
    day_end = day_start + timedelta(days=1) if day_start else None
    if day_start:
        lower, upper = min(lower, day_start), max(upper, day_end)
    events, errors = {}, []
    for name in ("local.sqlite", "cache.sqlite"):
        path = profile / "calendar-data" / name
        if not path.exists():
            continue
        try:
            with snapshot_database(path) as connection:
                for event in read_database(connection, calendars, local_zone, lower, upper):
                    events[event["id"]] = event
        except (OSError, sqlite3.Error, ValueError, OverflowError) as error:
            errors.append(f"{name}: {error}")
    ordered = sorted(events.values(), key=lambda event: (event["start"], not event["allDay"], event["title"]))
    day_counts = {}
    for event in ordered:
        day = max(datetime.fromisoformat(event["date"]).date(), first.date())
        last = datetime.fromisoformat(event["endDate"]).date()
        if event["allDay"] and event["end"] > event["start"]:
            last -= timedelta(days=1)  # iCalendar's all-day DTEND is exclusive.
        elif event["end"] > event["start"] and datetime.fromtimestamp(event["end"] / 1000, local_zone).time() == datetime.min.time():
            last -= timedelta(days=1)
        while day <= last and day < next_month.date():
            day_counts[day.isoformat()] = day_counts.get(day.isoformat(), 0) + 1
            day += timedelta(days=1)
    agenda = [event for event in ordered if event["start"] < agenda_end.timestamp() * 1000 and
              (event["end"] > now.timestamp() * 1000 or event["start"] >= now.timestamp() * 1000)]
    month_events = [event for event in ordered if event["start"] < next_month.timestamp() * 1000 and
                    (event["end"] > first.timestamp() * 1000 or event["start"] >= first.timestamp() * 1000)]
    selected_events = [event for event in ordered if day_start and event["start"] < day_end.timestamp() * 1000 and
                       (event["end"] > day_start.timestamp() * 1000 or event["start"] >= day_start.timestamp() * 1000)]
    uncached = sum(1 for calendar in calendars.values() if calendar.get("type") in ("caldav", "ics") and
                   str(calendar.get("disabled", False)).lower() != "true" and
                   not calendar.get("cache.enabled") and urlparse(calendar.get("uri", "")).scheme != "file")
    return {"events": agenda[:100], "monthEvents": month_events, "dayEvents": selected_events, "dayCounts": day_counts,
            "error": "; ".join(errors),
            "warning": f"{uncached} calendar(s) need Thunderbird Offline Support" if uncached else ""}


def main():
    argument_parser = argparse.ArgumentParser(description=__doc__)
    argument_parser.add_argument("--profile", type=Path)
    argument_parser.add_argument("--month", default=datetime.now().strftime("%Y-%m"))
    argument_parser.add_argument("--day", help="Selected date, independent of the displayed month")
    args = argument_parser.parse_args()
    try:
        result = collect(args.profile or find_profile(), args.month, selected_day=args.day)
    except (OSError, ValueError, sqlite3.Error) as error:
        result = {"events": [], "monthEvents": [], "dayEvents": [], "dayCounts": {}, "error": str(error), "warning": ""}
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
