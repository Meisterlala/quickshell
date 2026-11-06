package helper

import (
	"encoding/json"
	"fmt"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
)

type idleLock struct{ app, reason, owner string }
type idleEntry struct {
	Title string `json:"title"`
	Body  string `json:"body"`
}

var idleEvent = regexp.MustCompile(`ScreenSaver inhibit: (true|false) dbus message from (.*?) \(owner: (.*?)\) with content (.*)`)
var idleCount = regexp.MustCompile(`Inhibit locks: (-?\d+)`)

func idleApp(name string) string {
	name = filepath.Base(name)
	names := map[string]string{
		"discord": "Discord", "zen": "Zen Browser", "firefox": "Firefox",
		"chromium": "Chromium", "brave": "Brave Browser", "vlc": "VLC Media Player",
		"mpv": "mpv Player", "steam": "Steam", "webcord": "WebCord",
		"jellyfin-desktop": "Jellyfin", "com.feralinteractive.gamemode": "GameMode", "gamemode": "GameMode",
	}
	if friendly, ok := names[strings.ToLower(name)]; ok {
		return friendly
	}
	return name
}

// The journal only contains a bounded history. Preserve the reported lock count
// and expose any locks whose creation is no longer present as unidentified.
func parseIdleJournal(log string) ([]idleLock, int) {
	locks := []idleLock{}
	count := 0
	for _, line := range strings.Split(log, "\n") {
		if match := idleCount.FindStringSubmatch(line); match != nil {
			count, _ = strconv.Atoi(match[1])
			if count <= 0 {
				locks = nil
			}
		}
		match := idleEvent.FindStringSubmatch(line)
		if match == nil {
			continue
		}
		lock := idleLock{idleApp(match[2]), strings.TrimSpace(match[4]), match[3]}
		index := -1
		for i, existing := range locks {
			// A D-Bus owner can hold several different locks simultaneously.
			if existing.owner == lock.owner && existing.reason == lock.reason && existing.app == lock.app {
				index = i
				break
			}
		}
		if match[1] == "true" && index < 0 {
			locks = append(locks, lock)
		} else if match[1] == "false" && index >= 0 {
			locks = append(locks[:index], locks[index+1:]...)
		}
	}
	return locks, max(0, count)
}

func groupIdleLocks(locks []idleLock) []idleEntry {
	entries := []idleEntry{}
	reasons := [][]string{}
	for _, lock := range locks {
		title := idleApp(lock.app)
		reason := lock.reason
		if title == "GameMode" && (strings.EqualFold(reason, "GameMode Activated") || strings.EqualFold(reason, "GameMode active")) {
			reason = "GameMode active"
		}
		index := -1
		for i, entry := range entries {
			if strings.EqualFold(entry.Title, title) {
				index = i
				break
			}
		}
		if index < 0 {
			index = len(entries)
			entries = append(entries, idleEntry{Title: title})
			reasons = append(reasons, nil)
		}
		duplicate := reason == ""
		for _, existing := range reasons[index] {
			duplicate = duplicate || existing == reason
		}
		if !duplicate {
			reasons[index] = append(reasons[index], reason)
			entries[index].Body = strings.Join(reasons[index], "\n")
		}
	}
	return entries
}

func idleInhibitors() obj {
	result := runCommand(5*time.Second, nil, "journalctl", "--user", "-u", "hypridle", "-n", "300", "--no-pager", "-o", "cat")
	if result.Code != 0 {
		return obj{"text": "!", "tooltip": "Failed to read hypridle logs", "class": "error", "entries": []idleEntry{}}
	}
	locks, count := parseIdleJournal(result.Stdout)
	if count == 0 {
		return obj{"text": "", "tooltip": "", "class": "idle", "entries": []idleEntry{}}
	}
	warnings := []string{}
	result = runCommand(5*time.Second, nil, "systemd-inhibit", "--list", "--mode=block", "--json=short", "--no-pager")
	var systemLocks []struct{ Who, Why, What, Mode string }
	if result.Code != 0 || json.Unmarshal([]byte(result.Stdout), &systemLocks) != nil {
		warnings = append(warnings, "Could not read systemd inhibitors")
	} else {
		for _, lock := range systemLocks {
			if lock.Mode == "block" {
				for _, what := range strings.Split(lock.What, ":") {
					if what == "idle" {
						locks = append(locks, idleLock{app: idleApp(lock.Who), reason: lock.Why})
						break
					}
				}
			}
		}
	}
	entries := groupIdleLocks(locks)
	// Count grouped apps, plus locks whose identity is missing from the journal.
	displayCount := len(entries)
	if count > len(locks) {
		unknown := count - len(locks)
		displayCount += unknown
		entries = append(entries, idleEntry{Title: fmt.Sprintf("+ %d unidentified lock(s)", unknown)})
	}
	if len(warnings) > 0 {
		entries = append(entries, idleEntry{Title: "Unavailable", Body: strings.Join(warnings, "\n")})
	}
	return obj{"text": strconv.Itoa(displayCount), "class": "active", "entries": entries}
}
