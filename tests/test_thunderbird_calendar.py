"""Synthetic fixtures only: never use the user's calendar data in tests."""
import importlib.util
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from zoneinfo import ZoneInfo

SPEC = importlib.util.spec_from_file_location(
    "thunderbird_calendar", Path(__file__).parents[1] / "main/scripts/thunderbird_calendar.py")
calendar = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(calendar)
BERLIN = ZoneInfo("Europe/Berlin")


def native(value):
    # Floating/all-day values use wall-clock time encoded as UTC.
    return int((value if value.tzinfo else value.replace(tzinfo=timezone.utc)).timestamp() * 1_000_000)


class CalendarTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.profile = Path(self.temp.name)
        (self.profile / "calendar-data").mkdir()
        settings = {"calendar.timezone.local": "Europe/Berlin",
                    "calendar.registry.work.name": "Work",
                    "calendar.registry.work.color": "#123456",
                    "calendar.registry.work.type": "caldav",
                    "calendar.registry.work.cache.enabled": True,
                    "calendar.registry.hidden.name": "Disabled",
                    "calendar.registry.hidden.disabled": "true"}
        (self.profile / "prefs.js").write_text("\n".join(
            f'user_pref("{key}", {json.dumps(value)});' for key, value in settings.items()))
        self.path = self.profile / "calendar-data/cache.sqlite"
        self.db = sqlite3.connect(self.path)
        self.addCleanup(self.db.close)
        self.db.executescript("""
            CREATE TABLE cal_events (
                cal_id TEXT, id TEXT, title TEXT, ical_status TEXT, flags INTEGER,
                event_start INTEGER, event_end INTEGER, event_start_tz TEXT,
                event_end_tz TEXT, recurrence_id INTEGER, offline_journal INTEGER);
            CREATE TABLE cal_todos (
                cal_id TEXT, id TEXT, title TEXT, ical_status TEXT, flags INTEGER,
                todo_due INTEGER, todo_entry INTEGER, todo_due_tz TEXT,
                todo_entry_tz TEXT, todo_completed INTEGER, todo_complete INTEGER,
                recurrence_id INTEGER, offline_journal INTEGER);
            CREATE TABLE cal_properties (cal_id TEXT, item_id TEXT,
                recurrence_id INTEGER, key TEXT, value TEXT);
            CREATE TABLE cal_recurrence (cal_id TEXT, item_id TEXT, icalString TEXT);
        """)
        self.now = datetime(2026, 10, 25, 12, tzinfo=BERLIN)

    def event(self, name, start, end=None, cal_id="work", flags=0,
              status=None, recurrence_id=None, deleted=None, zone="Europe/Berlin"):
        self.db.execute("INSERT INTO cal_events VALUES (?,?,?,?,?,?,?,?,?,?,?)", (
            cal_id, name, name, status, flags, native(start), native(end or start + (timedelta(days=1) if flags & 8 else timedelta(hours=1))),
            zone, zone, native(recurrence_id) if recurrence_id else None, deleted))
        self.db.commit()

    def rule(self, name, text):
        self.db.execute("INSERT INTO cal_recurrence VALUES ('work',?,?)", (name, text))
        self.db.commit()

    def collect(self, month="2026-10"):
        result = calendar.collect(self.profile, month, self.now)
        self.assertEqual(result["error"], "")
        return result

    def test_upcoming_ongoing_disabled_cancelled_and_deleted(self):
        for name, options in (("upcoming", {}), ("disabled", {"cal_id": "hidden"}),
                              ("cancelled", {"status": "CANCELLED"}), ("deleted", {"deleted": 3})):
            self.event(name, self.now + timedelta(days=1), **options)
        self.event("ongoing", self.now - timedelta(hours=1), self.now + timedelta(hours=1))
        self.event("finished", self.now - timedelta(hours=3))
        self.event("outside", self.now + timedelta(days=31))
        result = self.collect()
        self.assertEqual([e["title"] for e in result["events"]], ["ongoing", "upcoming"])
        self.assertEqual(result["events"][1]["color"], "#123456")

    def test_month_events_include_past_and_far_future_dates(self):
        self.event("past meeting", datetime(2026, 10, 2, 9, tzinfo=BERLIN))
        self.event("future meeting", datetime(2027, 1, 15, 9, tzinfo=BERLIN))
        result = self.collect()
        self.assertEqual(result["events"], [])
        self.assertEqual([event["title"] for event in result["monthEvents"]], ["past meeting"])
        result = self.collect("2027-01")
        self.assertEqual([event["title"] for event in result["monthEvents"]], ["future meeting"])

    def test_selected_day_survives_browsing_other_months(self):
        self.event("selected meeting", datetime(2026, 10, 2, 9, tzinfo=BERLIN))
        self.event("other day", datetime(2026, 10, 3, 9, tzinfo=BERLIN))
        self.event("browsed month", datetime(2027, 1, 15, 9, tzinfo=BERLIN))
        result = calendar.collect(self.profile, "2027-01", self.now, selected_day="2026-10-02")
        self.assertEqual(result["error"], "")
        self.assertEqual([event["title"] for event in result["dayEvents"]], ["selected meeting"])
        self.assertEqual([event["title"] for event in result["monthEvents"]], ["browsed month"])
        self.assertEqual(result["dayCounts"], {"2027-01-15": 1})

    def test_all_day_exclusive_end_and_month_boundaries(self):
        self.event("trip", datetime(2026, 10, 31), datetime(2026, 11, 3), flags=8, zone="floating")
        result = self.collect("2026-11")
        self.assertEqual(result["dayCounts"], {"2026-11-01": 1, "2026-11-02": 1})
        self.assertTrue(result["events"][0]["allDay"])
        self.assertEqual(result["events"][0]["date"], "2026-10-31")

    def test_event_ending_at_month_start_does_not_mark_next_month(self):
        self.event("trip", datetime(2026, 10, 31), datetime(2026, 11, 1), flags=8, zone="floating")
        result = self.collect("2026-11")
        self.assertEqual(result["dayCounts"], {})
        self.assertEqual(result["monthEvents"], [])

    def test_sleep_calendar_excluded_from_agenda_and_dots(self):
        prefs = self.profile / "prefs.js"
        prefs.write_text(prefs.read_text() + '\nuser_pref("calendar.registry.sleep.name", "Sleep as Android");')
        self.event("Sleep", self.now + timedelta(days=1), cal_id="sleep")
        self.event("Meeting", self.now + timedelta(days=2))
        result = self.collect()
        self.assertEqual([event["title"] for event in result["events"]], ["Meeting"])
        self.assertEqual(result["dayCounts"], {"2026-10-27": 1})
        self.assertEqual([event["title"] for event in result["monthEvents"]], ["Meeting"])

    def test_weekly_recurrence_preserves_local_time_across_dst(self):
        self.event("weekly", datetime(2026, 10, 18, 20, tzinfo=BERLIN))
        self.rule("weekly", "RRULE:FREQ=WEEKLY;COUNT=3\r\n")
        result = self.collect()
        starts = [datetime.fromtimestamp(e["start"] / 1000, BERLIN) for e in result["events"]]
        self.assertEqual([(s.day, s.hour, s.utcoffset()) for s in starts],
                         [(25, 20, timedelta(hours=1)), (1, 20, timedelta(hours=1))])
        self.assertEqual(result["dayCounts"]["2026-10-18"], 1)

    def test_exdate_and_moved_exception(self):
        start = datetime(2026, 10, 18, 20, tzinfo=BERLIN)
        self.event("weekly", start)
        self.rule("weekly", "RRULE:FREQ=WEEKLY;COUNT=3\r\nEXDATE;TZID=Europe/Berlin:20261025T200000\r\n")
        original = datetime(2026, 11, 1, 20, tzinfo=BERLIN)
        self.event("weekly", original + timedelta(days=1), recurrence_id=original)
        result = self.collect()
        self.assertEqual(len(result["events"]), 1)
        self.assertEqual(result["events"][0]["date"], "2026-11-02")
        self.assertNotIn("2026-10-25", result["dayCounts"])

    def test_cancelled_exception_suppresses_occurrence(self):
        start = datetime(2026, 10, 18, 20, tzinfo=BERLIN)
        self.event("weekly", start)
        self.rule("weekly", "RRULE:FREQ=WEEKLY;COUNT=2")
        original = datetime(2026, 10, 25, 20, tzinfo=BERLIN)
        self.event("weekly", original, recurrence_id=original, status="CANCELLED")
        self.assertEqual(self.collect()["events"], [])

    def test_date_only_until_and_rdate(self):
        self.event("birthday", datetime(2026, 10, 24), flags=8, zone="floating")
        self.rule("birthday", "RRULE:FREQ=DAILY;UNTIL=20261025\r\nRDATE;VALUE=DATE:20261028")
        self.assertEqual([e["date"] for e in self.collect()["events"]], ["2026-10-25", "2026-10-28"])

    def test_floating_event_and_timed_until(self):
        self.event("floating", datetime(2026, 10, 25, 18), zone="floating")
        self.rule("floating", "RRULE:FREQ=DAILY;UNTIL=20261026")
        starts = [datetime.fromtimestamp(e["start"] / 1000, BERLIN) for e in self.collect()["events"]]
        self.assertEqual([(s.day, s.hour) for s in starts], [(25, 18), (26, 18)])

    def test_tasks_hide_completed(self):
        for name, completed in (("task", 0), ("done", 100)):
            self.db.execute("INSERT INTO cal_todos VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", (
                "work", name, name, None, 0, native(self.now + timedelta(days=1)), None,
                "Europe/Berlin", None, None, completed, None, None))
        self.db.commit()
        event = self.collect()["events"]
        self.assertEqual(len(event), 1)
        self.assertEqual(event[0]["kind"], "task")

    def test_reads_locked_database_and_wal_without_touching_source(self):
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("PRAGMA locking_mode=EXCLUSIVE")
        self.event("only in WAL", self.now + timedelta(days=1))
        wal = Path(str(self.path) + "-wal")
        before = (self.path.read_bytes(), wal.read_bytes())
        self.assertEqual(self.collect()["events"][0]["title"], "only in WAL")
        self.assertEqual(before, (self.path.read_bytes(), wal.read_bytes()))

    def test_select_default_profile(self):
        (self.profile / "profiles.ini").write_text(
            "[Profile0]\nName=default\nIsRelative=1\nPath=.\nDefault=1\n")
        self.assertEqual(calendar.find_profile(self.profile), self.profile)


if __name__ == "__main__":
    unittest.main()
