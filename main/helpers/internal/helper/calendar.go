package helper

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"syscall"
	"time"

	_ "modernc.org/sqlite"
)

var calendarPrefRE = regexp.MustCompile(`(?m)^user_pref\("(calendar\.[^"]+)", (.+)\);$`)
var registryPrefRE = regexp.MustCompile(`^calendar\.registry\.([^.]+)\.(.+)$`)

func findProfile(root string) (string, error) {
	b, _ := os.ReadFile(filepath.Join(root, "profiles.ini"))
	type section struct {
		name   string
		values map[string]string
	}
	sections := []section{}
	for _, line := range strings.Split(string(b), "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			sections = append(sections, section{line[1 : len(line)-1], map[string]string{}})
			continue
		}
		if len(sections) == 0 || strings.HasPrefix(line, "#") || strings.HasPrefix(line, ";") {
			continue
		}
		k, v, ok := strings.Cut(line, "=")
		if ok {
			sections[len(sections)-1].values[strings.TrimSpace(k)] = strings.TrimSpace(v)
		}
	}
	profiles := []string{}
	for _, s := range sections {
		if strings.HasPrefix(s.name, "Install") && s.values["Default"] != "" {
			profiles = append(profiles, filepath.Join(root, s.values["Default"]))
		}
	}
	for _, s := range sections {
		if !strings.HasPrefix(s.name, "Profile") || s.values["Path"] == "" {
			continue
		}
		path := s.values["Path"]
		if getString(s.values, "IsRelative", "1") == "1" {
			path = filepath.Join(root, path)
		}
		if s.values["Default"] == "1" {
			profiles = append([]string{path}, profiles...)
		} else {
			profiles = append(profiles, path)
		}
	}
	for _, p := range profiles {
		if info, e := os.Stat(filepath.Join(p, "prefs.js")); e == nil && info.Mode().IsRegular() {
			return p, nil
		}
	}
	return "", fmt.Errorf("No Thunderbird profile found")
}

func getString(m map[string]string, k, d string) string {
	if v, ok := m[k]; ok {
		return v
	}
	return d
}

func calendarSettings(profile string) (map[string]obj, *time.Location, error) {
	b, e := os.ReadFile(filepath.Join(profile, "prefs.js"))
	if e != nil {
		return nil, nil, e
	}
	calendars := map[string]obj{}
	zone := time.Local
	for _, m := range calendarPrefRE.FindAllStringSubmatch(string(b), -1) {
		var v any
		if e := json.Unmarshal([]byte(m[2]), &v); e != nil {
			return nil, nil, e
		}
		if m[1] == "calendar.timezone.local" {
			zone = timezoneFor(str(v), zone)
		}
		if match := registryPrefRE.FindStringSubmatch(m[1]); match != nil {
			if calendars[match[1]] == nil {
				calendars[match[1]] = obj{}
			}
			calendars[match[1]][match[2]] = v
		}
	}
	for id, c := range calendars {
		if strings.EqualFold(strings.TrimSpace(text(c, "name")), "sleep as android") {
			delete(calendars, id)
		}
	}
	return calendars, zone, nil
}

type fileSignature struct {
	inode  uint64
	size   int64
	mtime  int64
	exists bool
}

func signature(path string) (fileSignature, error) {
	info, e := os.Stat(path)
	if os.IsNotExist(e) {
		return fileSignature{}, nil
	}
	if e != nil {
		return fileSignature{}, e
	}
	stat := info.Sys().(*syscall.Stat_t)
	return fileSignature{stat.Ino, info.Size(), info.ModTime().UnixNano(), true}, nil
}

func snapshotDatabase(path string) (*sql.DB, func(), error) {
	temp, e := os.MkdirTemp("", "qs-calendar-")
	if e != nil {
		return nil, nil, e
	}
	cleanup := func() { _ = os.RemoveAll(temp) }
	target := filepath.Join(temp, filepath.Base(path))
	sources := []string{path, path + "-wal", path + "-journal"}
	for attempt := 0; attempt < 3; attempt++ {
		before := make([]fileSignature, len(sources))
		for i, source := range sources {
			before[i], e = signature(source)
			if e != nil {
				cleanup()
				return nil, nil, e
			}
			destination := filepath.Join(temp, filepath.Base(source))
			if !before[i].exists {
				_ = os.Remove(destination)
				continue
			}
			in, err := os.Open(source)
			if err != nil {
				cleanup()
				return nil, nil, err
			}
			out, err := os.OpenFile(destination, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0600)
			if err == nil {
				_, err = io.Copy(out, in)
				closeErr := out.Close()
				if err == nil {
					err = closeErr
				}
			}
			_ = in.Close()
			if err != nil {
				cleanup()
				return nil, nil, err
			}
		}
		stable := true
		for i, source := range sources {
			after, err := signature(source)
			if err != nil {
				cleanup()
				return nil, nil, err
			}
			if after != before[i] {
				stable = false
			}
		}
		if stable {
			db, err := sql.Open("sqlite", target)
			if err != nil {
				cleanup()
				return nil, nil, err
			}
			db.SetMaxOpenConns(1)
			return db, func() { _ = db.Close(); cleanup() }, nil
		}
	}
	cleanup()
	return nil, nil, fmt.Errorf("Thunderbird is updating its calendar; try again")
}

func sqlRows(db *sql.DB, query string) ([]obj, error) {
	rows, e := db.Query(query)
	if e != nil {
		return nil, e
	}
	defer rows.Close()
	columns, e := rows.Columns()
	if e != nil {
		return nil, e
	}
	result := []obj{}
	for rows.Next() {
		values := make([]any, len(columns))
		ptrs := make([]any, len(columns))
		for i := range values {
			ptrs[i] = &values[i]
		}
		if e := rows.Scan(ptrs...); e != nil {
			return nil, e
		}
		m := obj{}
		for i, k := range columns {
			if b, ok := values[i].([]byte); ok {
				m[k] = string(b)
			} else {
				m[k] = values[i]
			}
		}
		result = append(result, m)
	}
	return result, rows.Err()
}

func nativeDate(value any, zone string, local *time.Location, allDay bool) time.Time {
	t := time.UnixMicro(int64(num(value))).UTC()
	if allDay {
		return t
	}
	if zone == "" || zone == "floating" {
		return inWallZone(t, local)
	}
	return t.In(timezoneFor(zone, local))
}

type calendarKey struct{ cal, id string }
type occurrenceKey struct {
	calendarKey
	native    int64
	hasNative bool
}

func rowKey(row obj) calendarKey { return calendarKey{text(row, "cal_id"), text(row, "id")} }
func occurrenceKeyFor(key calendarKey, native any) occurrenceKey {
	return occurrenceKey{key, int64(num(native)), native != nil}
}

func readCalendarDatabase(db *sql.DB, calendars map[string]obj, zone *time.Location, lower, upper time.Time) ([]obj, error) {
	recurrence := map[calendarKey][]string{}
	rows, e := sqlRows(db, "SELECT cal_id, item_id, icalString FROM cal_recurrence")
	if e != nil {
		return nil, e
	}
	for _, row := range rows {
		key := calendarKey{text(row, "cal_id"), text(row, "item_id")}
		recurrence[key] = append(recurrence[key], text(row, "icalString"))
	}
	locations := map[occurrenceKey]any{}
	rows, e = sqlRows(db, "SELECT cal_id, item_id, recurrence_id, value FROM cal_properties WHERE key='LOCATION'")
	if e != nil {
		return nil, e
	}
	for _, row := range rows {
		key := calendarKey{text(row, "cal_id"), text(row, "item_id")}
		locations[occurrenceKeyFor(key, row["recurrence_id"])] = row["value"]
	}
	result := []obj{}
	for _, kind := range []string{"event", "task"} {
		table := "cal_events"
		if kind == "task" {
			table = "cal_todos"
		}
		rows, e = sqlRows(db, "SELECT * FROM "+table)
		if e != nil {
			return nil, e
		}
		exceptions := map[occurrenceKey]bool{}
		for _, row := range rows {
			if row["recurrence_id"] != nil {
				exceptions[occurrenceKeyFor(rowKey(row), row["recurrence_id"])] = true
			}
		}
		for _, row := range rows {
			key := rowKey(row)
			c := calendars[key.cal]
			if c == nil || strings.EqualFold(str(get(c, "disabled", false)), "true") {
				continue
			}
			if num(row["offline_journal"]) == 3 || row["ical_status"] == "CANCELLED" {
				continue
			}
			if kind == "task" && (truth(row["todo_completed"]) || num(row["todo_complete"]) >= 100 || row["ical_status"] == "COMPLETED") {
				continue
			}
			allDay := int64(num(row["flags"]))&8 != 0
			prefix := "event_start"
			if kind == "task" {
				prefix = "todo_due"
				if row[prefix] == nil {
					prefix = "todo_entry"
				}
			}
			if row[prefix] == nil {
				continue
			}
			zoneName := ""
			if row[prefix+"_tz"] != nil {
				zoneName = text(row, prefix+"_tz")
			}
			start := nativeDate(row[prefix], zoneName, zone, allDay)
			end := start
			if kind == "event" && row["event_end"] != nil {
				z := ""
				if row["event_end_tz"] != nil {
					z = text(row, "event_end_tz")
				}
				end = nativeDate(row["event_end"], z, zone, allDay)
			}
			duration := end.Sub(start)
			if start.Location() == end.Location() {
				duration = wallTime(end).Sub(wallTime(start))
			}
			if duration < 0 {
				duration = 0
			}
			if allDay && duration == 0 {
				duration = 24 * time.Hour
			}
			low, high := lower, upper
			if allDay {
				low, high = wallTime(lower), wallTime(upper)
			}
			rules := []string{}
			if row["recurrence_id"] == nil {
				rules = recurrence[key]
			}
			starts := []time.Time{start}
			if len(rules) > 0 {
				starts, e = recurrenceDates(start, rules, addWall(low, -duration), high, allDay)
				if e != nil {
					return nil, e
				}
			}
			for _, occurrence := range starts {
				native := occurrence.UnixMicro()
				if allDay || zoneName == "" || zoneName == "floating" {
					native = wallTime(occurrence).UnixMicro()
				}
				if len(rules) > 0 && exceptions[occurrenceKey{key, native, true}] {
					continue
				}
				finish := addWall(occurrence, duration)
				if !occurrence.Before(high) || (!finish.After(low) && occurrence.Before(low)) {
					continue
				}
				localStart, localEnd := occurrence.In(zone), finish.In(zone)
				if allDay {
					localStart, localEnd = inWallZone(occurrence, zone), inWallZone(finish, zone)
				}
				result = append(result, obj{
					"id": fmt.Sprintf("%s:%s:%d", key.cal, key.id, native), "title": fallback(row["title"], "Untitled"),
					"start": localStart.UnixMilli(), "end": localEnd.UnixMilli(), "date": localStart.Format("2006-01-02"), "endDate": localEnd.Format("2006-01-02"),
					"allDay": allDay, "kind": kind, "calendar": get(c, "name", "Calendar"), "color": get(c, "color", "#89dceb"),
					"location": str(fallback(locations[occurrenceKeyFor(key, row["recurrence_id"])], "")),
				})
			}
		}
	}
	return result, nil
}

func collectCalendar(profile, month, selected string, now time.Time) (obj, error) {
	calendars, zone, e := calendarSettings(profile)
	if e != nil {
		return nil, e
	}
	now = now.In(zone)
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, zone)
	first, e := time.ParseInLocation("2006-01", month, zone)
	if e != nil {
		return nil, e
	}
	nextMonth, agendaEnd := first.AddDate(0, 1, 0), today.AddDate(0, 0, 30)
	lower, upper := today, agendaEnd
	if first.Before(lower) {
		lower = first
	}
	if nextMonth.After(upper) {
		upper = nextMonth
	}
	var dayStart, dayEnd time.Time
	if selected != "" {
		dayStart, e = time.ParseInLocation("2006-01-02", selected, zone)
		if e != nil {
			return nil, e
		}
		dayEnd = dayStart.AddDate(0, 0, 1)
		if dayStart.Before(lower) {
			lower = dayStart
		}
		if dayEnd.After(upper) {
			upper = dayEnd
		}
	}
	events := map[string]obj{}
	errors := []string{}
	for _, name := range []string{"local.sqlite", "cache.sqlite"} {
		path := filepath.Join(profile, "calendar-data", name)
		if _, e := os.Stat(path); os.IsNotExist(e) {
			continue
		}
		db, cleanup, e := snapshotDatabase(path)
		if e == nil {
			var rows []obj
			rows, e = readCalendarDatabase(db, calendars, zone, lower, upper)
			cleanup()
			if e == nil {
				for _, event := range rows {
					events[text(event, "id")] = event
				}
			}
		}
		if e != nil {
			errors = append(errors, name+": "+e.Error())
		}
	}
	ordered := []obj{}
	for _, event := range events {
		ordered = append(ordered, event)
	}
	sort.Slice(ordered, func(i, j int) bool {
		a, b := ordered[i], ordered[j]
		if num(a["start"]) != num(b["start"]) {
			return num(a["start"]) < num(b["start"])
		}
		if a["allDay"] != b["allDay"] {
			return truth(a["allDay"])
		}
		return text(a, "title") < text(b, "title")
	})
	dayCounts := map[string]int{}
	agenda, monthEvents, dayEvents := []obj{}, []obj{}, []obj{}
	overlaps := func(event obj, start, end time.Time) bool {
		return num(event["start"]) < float64(end.UnixMilli()) && (num(event["end"]) > float64(start.UnixMilli()) || num(event["start"]) >= float64(start.UnixMilli()))
	}
	for _, event := range ordered {
		day, _ := time.ParseInLocation("2006-01-02", text(event, "date"), zone)
		if day.Before(first) {
			day = first
		}
		last, _ := time.ParseInLocation("2006-01-02", text(event, "endDate"), zone)
		if num(event["end"]) > num(event["start"]) {
			end := time.UnixMilli(int64(num(event["end"]))).In(zone)
			if truth(event["allDay"]) || (end.Hour() == 0 && end.Minute() == 0 && end.Second() == 0 && end.Nanosecond() == 0) {
				last = last.AddDate(0, 0, -1)
			}
		}
		for !day.After(last) && day.Before(nextMonth) {
			dayCounts[day.Format("2006-01-02")]++
			day = day.AddDate(0, 0, 1)
		}
		if overlaps(event, now, agendaEnd) && len(agenda) < 100 {
			agenda = append(agenda, event)
		}
		if overlaps(event, first, nextMonth) {
			monthEvents = append(monthEvents, event)
		}
		if selected != "" && overlaps(event, dayStart, dayEnd) {
			dayEvents = append(dayEvents, event)
		}
	}
	uncached := 0
	for _, c := range calendars {
		u, _ := url.Parse(text(c, "uri"))
		if (c["type"] == "caldav" || c["type"] == "ics") && !strings.EqualFold(str(get(c, "disabled", false)), "true") && !truth(c["cache.enabled"]) && (u == nil || u.Scheme != "file") {
			uncached++
		}
	}
	warning := ""
	if uncached > 0 {
		warning = fmt.Sprintf("%d calendar(s) need Thunderbird Offline Support", uncached)
	}
	return obj{"events": agenda, "monthEvents": monthEvents, "dayEvents": dayEvents, "dayCounts": dayCounts, "error": strings.Join(errors, "; "), "warning": warning}, nil
}

func calendarError(message string) obj {
	return obj{"events": []any{}, "monthEvents": []any{}, "dayEvents": []any{}, "dayCounts": obj{}, "error": message, "warning": ""}
}

func calendar(args []string) obj {
	profile, month, day := "", time.Now().Format("2006-01"), ""
	for i := 0; i < len(args); i++ {
		key, value, hasValue := strings.Cut(args[i], "=")
		if !hasValue {
			i++
			if i >= len(args) {
				return calendarError("Missing value for " + key)
			}
			value = args[i]
		}
		switch key {
		case "--profile":
			profile = value
		case "--month":
			month = value
		case "--day":
			day = value
		default:
			return calendarError("Unknown argument: " + key)
		}
	}
	var e error
	if profile == "" {
		profile, e = findProfile(filepath.Join(home(), ".thunderbird"))
		if e != nil {
			return calendarError(e.Error())
		}
	}
	result, e := collectCalendar(profile, month, day, time.Now())
	if e != nil {
		return calendarError(e.Error())
	}
	return result
}
