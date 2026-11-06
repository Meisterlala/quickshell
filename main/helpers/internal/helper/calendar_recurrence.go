package helper

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/teambition/rrule-go"
)

var foldRE = regexp.MustCompile(`\r?\n[ \t]`)
var untilRE = regexp.MustCompile(`UNTIL=([^;]+)`)
var tzidRE = regexp.MustCompile(`;TZID="?([^;\"]+)`)

func wallTime(t time.Time) time.Time {
	return time.Date(t.Year(), t.Month(), t.Day(), t.Hour(), t.Minute(), t.Second(), t.Nanosecond(), time.UTC)
}

func inWallZone(t time.Time, zone *time.Location) time.Time {
	return time.Date(t.Year(), t.Month(), t.Day(), t.Hour(), t.Minute(), t.Second(), t.Nanosecond(), zone)
}

func addWall(t time.Time, d time.Duration) time.Time {
	return inWallZone(wallTime(t).Add(d), t.Location())
}

func parseICALTime(value string, zone *time.Location) (time.Time, error) {
	value = strings.TrimSpace(value)
	if strings.HasSuffix(value, "Z") {
		zone = time.UTC
		value = strings.TrimSuffix(value, "Z")
	}
	for _, layout := range []string{"20060102T150405", "20060102T1504", "20060102", "2006-01-02T15:04:05", "2006-01-02"} {
		if t, e := time.ParseInLocation(layout, value, zone); e == nil {
			return t, nil
		}
	}
	return time.Time{}, fmt.Errorf("invalid date: %s", value)
}

func timezoneFor(name string, fallback *time.Location) *time.Location {
	if name == "" || name == "floating" {
		return fallback
	}
	if strings.HasPrefix(name, "BEGIN:VTIMEZONE") {
		if zone, e := embeddedTimezone(name); e == nil {
			return zone
		}
		return fallback
	}
	if zone, e := time.LoadLocation(name); e == nil {
		return zone
	}
	return fallback
}

func recurrenceRule(value string, start time.Time, naive bool) (*rrule.RRule, error) {
	value = strings.TrimSpace(value)
	// dateutil accepts date-only and local UNTIL values. Normalize before parsing.
	if match := untilRE.FindStringSubmatch(value); match != nil {
		end, e := parseICALTime(match[1], start.Location())
		if e != nil {
			return nil, e
		}
		if len(match[1]) == 8 && !naive {
			end = end.Add(23*time.Hour + 59*time.Minute + 59*time.Second)
		}
		value = strings.Replace(value, match[0], "UNTIL="+end.UTC().Format("20060102T150405Z"), 1)
	}
	option, e := rrule.StrToROptionInLocation(value, start.Location())
	if e != nil {
		return nil, e
	}
	option.Dtstart = start
	return rrule.NewRRule(*option)
}

type dateIterator struct {
	next  func() (time.Time, bool)
	value time.Time
	ok    bool
}

func recurrenceDates(start time.Time, lines []string, lower, upper time.Time, naive bool) ([]time.Time, error) {
	includes, excludes := []*dateIterator{}, []*dateIterator{}
	rdates, exdates := []time.Time{start}, []time.Time{}
	for _, line := range strings.Split(foldRE.ReplaceAllString(strings.Join(lines, "\n"), ""), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		header, value, ok := strings.Cut(line, ":")
		if !ok {
			return nil, fmt.Errorf("invalid recurrence: %s", line)
		}
		kind := strings.ToUpper(strings.SplitN(header, ";", 2)[0])
		switch kind {
		case "RRULE", "EXRULE":
			rule, e := recurrenceRule(value, start, naive)
			if e != nil {
				return nil, e
			}
			it := &dateIterator{next: rule.Iterator()}
			if kind == "RRULE" {
				includes = append(includes, it)
			} else {
				excludes = append(excludes, it)
			}
		case "RDATE", "EXDATE":
			zone := start.Location()
			if match := tzidRE.FindStringSubmatch(header); match != nil {
				zone = timezoneFor(match[1], zone)
			}
			for _, raw := range strings.Split(value, ",") {
				t, e := parseICALTime(raw, zone)
				if e != nil {
					return nil, e
				}
				// All-day dates have wall-clock semantics, even with a TZID.
				if naive {
					t = inWallZone(t, time.UTC)
				}
				if kind == "RDATE" {
					rdates = append(rdates, t)
				} else {
					exdates = append(exdates, t)
				}
			}
		}
	}
	fromDates := func(dates []time.Time) *dateIterator {
		sort.Slice(dates, func(i, j int) bool { return dates[i].Before(dates[j]) })
		i := 0
		return &dateIterator{next: func() (time.Time, bool) {
			if i == len(dates) {
				return time.Time{}, false
			}
			t := dates[i]
			i++
			return t, true
		}}
	}
	includes = append(includes, fromDates(rdates))
	excludes = append(excludes, fromDates(exdates))
	for _, it := range append(append([]*dateIterator{}, includes...), excludes...) {
		for it.value, it.ok = it.next(); it.ok && it.value.Before(lower); it.value, it.ok = it.next() {
		}
	}
	result := []time.Time{}
	for len(result) < 10000 {
		var candidate time.Time
		found := false
		for _, it := range includes {
			if it.ok && (!found || it.value.Before(candidate)) {
				candidate = it.value
				found = true
			}
		}
		if !found || !candidate.Before(upper) {
			break
		}
		for _, it := range includes {
			for it.ok && it.value.Equal(candidate) {
				it.value, it.ok = it.next()
			}
		}
		excluded := false
		for _, it := range excludes {
			for it.ok && it.value.Before(candidate) {
				it.value, it.ok = it.next()
			}
			if it.ok && it.value.Equal(candidate) {
				excluded = true
			}
		}
		if !excluded {
			result = append(result, candidate)
		}
	}
	return result, nil
}

// Convert embedded VTIMEZONE observances to TZif rather than silently dropping DST.
// This covers historical and future transitions through Go's normal Location API.
func embeddedTimezone(raw string) (*time.Location, error) {
	type observance struct {
		kind   string
		values map[string][]string
	}
	observances := []observance{}
	name := "calendar"
	var current *observance
	for _, line := range strings.Split(foldRE.ReplaceAllString(raw, ""), "\n") {
		line = strings.TrimSpace(line)
		key, value, ok := strings.Cut(line, ":")
		if !ok {
			continue
		}
		if key == "TZID" {
			name = value
		}
		if key == "BEGIN" && (value == "STANDARD" || value == "DAYLIGHT") {
			current = &observance{value, map[string][]string{}}
			continue
		}
		if key == "END" && current != nil {
			observances = append(observances, *current)
			current = nil
			continue
		}
		if current != nil {
			current.values[strings.SplitN(key, ";", 2)[0]] = append(current.values[strings.SplitN(key, ";", 2)[0]], value)
		}
	}
	type transition struct {
		at    int64
		index byte
	}
	type zoneType struct {
		offset int32
		dst    byte
		label  byte
	}
	transitions := []transition{}
	types := []zoneType{}
	labels := []byte{}
	offset := func(s string) (int, error) {
		sign := 1
		if strings.HasPrefix(s, "-") {
			sign = -1
		}
		s = strings.TrimLeft(s, "+-")
		if len(s) != 4 && len(s) != 6 {
			return 0, fmt.Errorf("invalid timezone offset")
		}
		h, e1 := strconv.Atoi(s[:2])
		m, e2 := strconv.Atoi(s[2:4])
		sec := 0
		if len(s) == 6 {
			sec, _ = strconv.Atoi(s[4:])
		}
		if e1 != nil || e2 != nil {
			return 0, fmt.Errorf("invalid timezone offset")
		}
		return sign * (h*3600 + m*60 + sec), nil
	}
	first := func(m map[string][]string, k string) string {
		if len(m[k]) > 0 {
			return m[k][0]
		}
		return ""
	}
	for _, o := range observances {
		from, e := offset(first(o.values, "TZOFFSETFROM"))
		if e != nil {
			return nil, e
		}
		to, e := offset(first(o.values, "TZOFFSETTO"))
		if e != nil {
			return nil, e
		}
		start, e := parseICALTime(first(o.values, "DTSTART"), time.UTC)
		if e != nil {
			return nil, e
		}
		if len(types) == 0 {
			types = append(types, zoneType{int32(from), 0, 0})
			labels = append(labels, []byte("LMT\x00")...)
		}
		label := first(o.values, "TZNAME")
		if label == "" {
			label = o.kind
		}
		if len(labels)+len(label) > 255 || len(types) > 254 {
			return nil, fmt.Errorf("timezone too complex")
		}
		index := byte(len(types))
		dst := byte(0)
		if o.kind == "DAYLIGHT" {
			dst = 1
		}
		types = append(types, zoneType{int32(to), dst, byte(len(labels))})
		labels = append(labels, []byte(label+"\x00")...)
		lines := []string{}
		for _, k := range []string{"RRULE", "RDATE"} {
			for _, v := range o.values[k] {
				lines = append(lines, k+":"+v)
			}
		}
		dates, e := recurrenceDates(start, lines, time.Date(1800, 1, 1, 0, 0, 0, 0, time.UTC), time.Date(2400, 1, 1, 0, 0, 0, 0, time.UTC), true)
		if e != nil {
			return nil, e
		}
		for _, t := range dates {
			transitions = append(transitions, transition{t.Unix() - int64(from), index})
		}
	}
	if len(types) == 0 {
		return nil, fmt.Errorf("empty VTIMEZONE")
	}
	sort.SliceStable(transitions, func(i, j int) bool { return transitions[i].at < transitions[j].at })
	var buf bytes.Buffer
	header := func(count int) {
		buf.WriteString("TZif2")
		buf.Write(make([]byte, 15))
		for _, n := range []int{0, 0, 0, count, len(types), len(labels)} {
			_ = binary.Write(&buf, binary.BigEndian, int32(n))
		}
	}
	block := func(ts []transition, wide bool) {
		for _, t := range ts {
			if wide {
				_ = binary.Write(&buf, binary.BigEndian, t.at)
			} else {
				_ = binary.Write(&buf, binary.BigEndian, int32(t.at))
			}
		}
		for _, t := range ts {
			buf.WriteByte(t.index)
		}
		for _, z := range types {
			_ = binary.Write(&buf, binary.BigEndian, z.offset)
			buf.WriteByte(z.dst)
			buf.WriteByte(z.label)
		}
		buf.Write(labels)
	}
	narrow := []transition{}
	for _, t := range transitions {
		if t.at >= -2147483648 && t.at <= 2147483647 {
			narrow = append(narrow, t)
		}
	}
	header(len(narrow))
	block(narrow, false)
	header(len(transitions))
	block(transitions, true)
	buf.WriteString("\n\n")
	return time.LoadLocationFromTZData(name, buf.Bytes())
}
