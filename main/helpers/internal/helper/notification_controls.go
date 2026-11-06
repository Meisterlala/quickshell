package helper

import (
	"encoding/json"
	"fmt"
	"strings"
	"time"
)

const inhibitUnit = "quickshell-idle-inhibit.service"
const monitorDescription = "Acer Technologies ED270U P TKYEE0013W01"

func inhibited() (bool, error) {
	c, o, e := command(5*time.Second, nil, "systemctl", "--user", "is-active", inhibitUnit)
	if c != 0 && c != 3 && c != 4 {
		return false, fmt.Errorf("%s", fallback(strings.TrimSpace(e), "Could not query sleep inhibition"))
	}
	s := strings.TrimSpace(o)
	return s == "active" || s == "activating", nil
}
func monitor() (obj, error) {
	c, o, e := command(5*time.Second, nil, "hyprctl", "monitors", "all", "-j")
	if c != 0 {
		return nil, fmt.Errorf("%s", fallback(strings.TrimSpace(e), "Could not query monitors"))
	}
	var monitors []obj
	if e := json.Unmarshal([]byte(o), &monitors); e != nil {
		return nil, e
	}
	for _, m := range monitors {
		if m["description"] == monitorDescription {
			return m, nil
		}
	}
	return nil, nil
}
func monitorState(m obj) string {
	if m == nil {
		return "missing"
	}
	if truth(m["disabled"]) {
		return "disabled"
	}
	if truth(m["dpmsStatus"]) {
		return "on"
	}
	return "off"
}
func notificationControls(args []string) (obj, int) {
	action := "status"
	if len(args) > 0 {
		action = args[0]
	}
	work := func() error {
		switch action {
		case "idle":
			active, e := inhibited()
			if e != nil {
				return e
			}
			var c int
			var err string
			if active {
				c, _, err = command(5*time.Second, nil, "systemctl", "--user", "stop", inhibitUnit)
			} else {
				c, _, err = command(5*time.Second, nil, "systemd-run", "--user", "--quiet", "--collect", "--unit="+inhibitUnit, "--", "systemd-inhibit", "--what=idle", "--who=Quickshell", "--why=Stay awake toggle", "--mode=block", "sleep", "infinity")
			}
			if c != 0 {
				return fmt.Errorf("%s", fallback(strings.TrimSpace(err), "Could not toggle sleep inhibition"))
			}
		case "monitor":
			m, e := monitor()
			if e != nil {
				return e
			}
			state := monitorState(m)
			if state != "on" && state != "off" {
				return fmt.Errorf("Second monitor is %s", state)
			}
			next := "on"
			if state == "on" {
				next = "off"
			}
			name, _ := json.Marshal(m["name"])
			c, _, err := command(5*time.Second, nil, "hyprctl", "dispatch", fmt.Sprintf("hl.dsp.dpms({ state = \"%s\", monitor = %s })", next, name))
			if c != 0 {
				return fmt.Errorf("%s", fallback(strings.TrimSpace(err), "Could not toggle second monitor"))
			}
		case "status":
		default:
			return fmt.Errorf("Expected status, idle, or monitor")
		}
		return nil
	}
	if e := work(); e != nil {
		return obj{"error": e.Error()}, 1
	}
	active, e := inhibited()
	if e != nil {
		return obj{"error": e.Error()}, 1
	}
	m, e := monitor()
	if e != nil {
		return obj{"error": e.Error()}, 1
	}
	return obj{"inhibited": active, "monitor": monitorState(m), "error": ""}, 0
}
