package helper

import (
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"
)

func points(v any) string {
	if !numeric(v) {
		return "0"
	}
	n := num(v)
	if n == math.Trunc(n) {
		return strconv.FormatFloat(n, 'f', 0, 64)
	}
	return strings.TrimRight(strings.TrimRight(strconv.FormatFloat(n, 'f', 1, 64), "0"), ".")
}

func signedPoints(v any) string {
	if num(v) > 0 {
		return "+" + points(v)
	}
	return points(v)
}

func amountMinutes(v any) string {
	minutes := num(v)
	if minutes <= 0 {
		return "0m"
	}
	if minutes < 60 {
		return fmt.Sprintf("%dm", int(math.RoundToEven(minutes)))
	}
	hours, rest := int(minutes/60), int(math.RoundToEven(math.Mod(minutes, 60)))
	if rest == 0 {
		return fmt.Sprintf("%dh", hours)
	}
	return fmt.Sprintf("%dh %dm", hours, rest)
}

func daysUntil(value any, today string) any {
	s, ok := value.(string)
	if !ok || len(s) < 10 {
		return nil
	}
	due, err := time.Parse("2006-01-02", s[:10])
	if err != nil {
		return nil
	}
	reference, err := time.Parse("2006-01-02", today)
	if err != nil {
		now := time.Now()
		reference = time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)
	}
	return int(due.Sub(reference).Hours() / 24)
}

func dueLabel(value any, today string) string {
	d := daysUntil(value, today)
	if d == nil {
		return "No due date"
	}
	n := d.(int)
	switch {
	case n < 0:
		return fmt.Sprintf("Overdue by %dd", -n)
	case n == 0:
		return "Due today"
	case n == 1:
		return "Due tomorrow"
	default:
		return fmt.Sprintf("Due in %dd", n)
	}
}

func visibleHabits(day obj) []obj {
	result := []obj{}
	for _, raw := range list(day["habits"]) {
		h, ok := raw.(map[string]any)
		if !ok || h["visibility"] == "hidden" {
			continue
		}
		done := h["status"] == "done" || (numeric(h["effective_points"]) && num(h["effective_points"]) > 0)
		effective := num(h["effective_points"])
		if !numeric(h["effective_points"]) {
			if done {
				effective = num(h["points_done"])
			} else {
				effective = num(h["points_missed"])
			}
		}
		result = append(result, obj{
			"id": text(h, "id"), "name": str(get(h, "name", get(h, "id", "Habit"))),
			"status": text(h, "status"), "done": done,
			"points_done": get(h, "points_done", 0), "points_missed": get(h, "points_missed", 0),
			"effective_points": effective, "points_label": signedPoints(effective),
		})
	}
	return result
}

func eventView(e obj) obj {
	amount, earned := get(e, "amount", 0), get(e, "earned_points", 0)
	return obj{"id": text(e, "id"), "name": str(get(e, "name", get(e, "id", "Event"))),
		"is_active": truth(e["is_active"]), "amount": amount, "amount_label": amountMinutes(amount),
		"earned_points": earned, "points_label": signedPoints(earned)}
}

func habitEvents(day obj) ([]obj, []obj) {
	active, nonzero := []obj{}, []obj{}
	for _, raw := range list(day["events"]) {
		e, ok := raw.(map[string]any)
		if !ok || e["visibility"] != "shown" {
			continue
		}
		if truth(e["is_active"]) {
			active = append(active, eventView(e))
		} else if numeric(e["amount"]) && num(e["amount"]) != 0 {
			nonzero = append(nonzero, eventView(e))
		}
	}
	return active, nonzero
}

func policyViews(policies []any) []obj {
	result := []obj{}
	for _, raw := range policies {
		p, ok := raw.(map[string]any)
		if !ok {
			continue
		}
		display := dict(p["display"])
		target := get(display, "min", get(display, "min_occurrences", get(p, "target_value", 0)))
		delta := get(p, "points_delta", 0)
		result = append(result, obj{
			"id": text(p, "id"), "description": str(get(p, "description", get(p, "id", "Policy"))),
			"status": strings.ReplaceAll(text(p, "status"), "_", " "), "message": text(p, "message"),
			"points_delta": delta, "points_label": signedPoints(delta), "current_value": get(p, "current_value", 0),
			"target_value": target, "progress_label": points(get(p, "current_value", 0)) + "/" + points(target),
			"window_end": text(p, "window_end"),
		})
	}
	sort.SliceStable(result, func(i, j int) bool {
		a, b := num(result[i]["points_delta"]), num(result[j]["points_delta"])
		if a != b {
			return a < b
		}
		return text(result[i], "window_end") < text(result[j], "window_end")
	})
	return result
}

func habitNotifications(response obj) []obj {
	result := []obj{}
	for _, raw := range list(response["notifications"]) {
		n, ok := raw.(map[string]any)
		if !ok {
			continue
		}
		progress := dict(n["progress"])
		current, maximum := progress["current"], progress["max"]
		label := ""
		if numeric(current) && numeric(maximum) && num(maximum) > 0 {
			label = amountMinutes(current) + " / " + amountMinutes(maximum)
		}
		result = append(result, obj{"id": text(n, "id"), "category": text(n, "category"),
			"title": str(get(n, "title", "Notification")), "description": text(n, "description"),
			"progress_current": num(current), "progress_max": num(maximum), "progress_label": label})
	}
	return result
}

func habitDeadlines(response obj, today string) []obj {
	result := []obj{}
	for _, raw := range list(response["deadlines"]) {
		d, ok := raw.(map[string]any)
		if !ok || d["status"] != "active" {
			continue
		}
		due := fallback(d["due_date"], d["due_at"])
		result = append(result, obj{"id": text(d, "id"), "title": str(get(d, "title", "Deadline")),
			"description": text(d, "description"), "due": str(fallback(due, "")),
			"due_label": dueLabel(due, today), "days_until": daysUntil(due, today)})
	}
	rank := func(v any) int {
		if v == nil {
			return 99999
		}
		return v.(int)
	}
	sort.SliceStable(result, func(i, j int) bool { return rank(result[i]["days_until"]) < rank(result[j]["days_until"]) })
	return result
}

func habitContracts(response obj) []obj {
	result := []obj{}
	for _, raw := range list(response["today_active"]) {
		c, ok := raw.(map[string]any)
		if !ok {
			continue
		}
		result = append(result, obj{"id": text(c, "id"), "name": str(get(c, "name", get(c, "id", "Contract"))), "description": text(c, "description")})
	}
	return result
}

func habitsPayload(summary, tomorrow, weight, punishment, day obj, policiesResponse []any, contractsResponse, notificationsResponse, deadlinesResponse obj) obj {
	today := str(fallback(summary["date"], day["date"], time.Now().Format("2006-01-02")))
	habits := visibleHabits(day)
	active, events := habitEvents(day)
	policies := policyViews(policiesResponse)
	notifications := habitNotifications(notificationsResponse)
	deadlines := habitDeadlines(deadlinesResponse, today)
	contracts := habitContracts(contractsResponse)
	done, total := int(num(summary["habits_done"])), int(num(summary["habits_total"]))
	attention := len(active) > 0 || len(notifications) > 0
	state := "pending"
	if total > 0 && done >= total && !attention {
		state = "done"
	} else if attention {
		state = "warning"
	} else if done > 0 {
		state = "active"
	}
	var delta any
	deltaLabel := ""
	if numeric(summary["recent_points"]) && numeric(tomorrow["recent_points"]) {
		delta = num(tomorrow["recent_points"]) - num(summary["recent_points"])
		deltaLabel = signedPoints(delta)
	}
	weightLabel := ""
	if w := dict(weight["latest_weight"])["weight_kg"]; numeric(w) {
		weightLabel = fmt.Sprintf("%.1fkg", num(w))
	}
	tier := dict(summary["current_tier"])
	label := fmt.Sprintf("%d/%d", done, total)
	if len(active) > 0 {
		label += fmt.Sprintf(" 󰥔%d", len(active))
	}
	if n := len(policies) + len(deadlines); n > 0 {
		label += fmt.Sprintf(" 󰄬%d", n)
	}
	if len(notifications) > 0 {
		label += fmt.Sprintf(" %d", len(notifications))
	}
	return obj{"ok": true, "date": today, "text": label, "state": state,
		"summary": obj{
			"habits_done": done, "habits_total": total,
			"points_today": get(summary, "points_today", 0), "points_today_label": signedPoints(get(summary, "points_today", 0)),
			"banked_points": get(summary, "banked_points", 0), "banked_points_label": points(get(summary, "banked_points", 0)),
			"punishment_points": get(punishment, "negative_banked_points", 0), "punishment_points_label": points(get(punishment, "negative_banked_points", 0)),
			"recent_points": get(summary, "recent_points", 0), "recent_points_label": points(get(summary, "recent_points", 0)),
			"rolling_delta": delta, "rolling_delta_label": deltaLabel, "tier": str(fallback(tier["name"], tier["id"], "Unknown")), "weight_label": weightLabel,
		},
		"habits": habits, "active_events": active, "events": events, "policies": policies,
		"notifications": notifications, "deadlines": deadlines, "contracts": contracts,
		"counts": obj{"active_events": len(active), "notifications": len(notifications), "policies": len(policies), "deadlines": len(deadlines)},
	}
}

func habitsError(message string) obj {
	return obj{"ok": false, "text": "?/?", "state": "error", "error": message, "summary": obj{},
		"habits": []any{}, "active_events": []any{}, "events": []any{}, "policies": []any{},
		"notifications": []any{}, "deadlines": []any{}, "contracts": []any{}, "counts": obj{}}
}

type habitsAPI struct{ base, key string }

func loadHabitsConfig() (habitsAPI, error) {
	path := filepath.Join(env("XDG_CONFIG_HOME", filepath.Join(home(), ".config")), "habits-server", "waybar.json")
	v, err := readJSON(path)
	if os.IsNotExist(err) {
		return habitsAPI{}, fmt.Errorf("Missing config: %s", path)
	}
	if _, ok := err.(*json.SyntaxError); ok {
		return habitsAPI{}, fmt.Errorf("Invalid JSON config: %s", path)
	}
	if err != nil {
		return habitsAPI{}, err
	}
	config, ok := v.(map[string]any)
	if !ok {
		return habitsAPI{}, fmt.Errorf("Invalid config shape: %s", path)
	}
	raw := strings.TrimSpace(str(get(config, "api_base_url", "https://habits.meisterlala.dev/api")))
	if raw == "" {
		return habitsAPI{}, fmt.Errorf("Missing api_base_url in habits config")
	}
	u, err := url.Parse(raw)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
		return habitsAPI{}, fmt.Errorf("api_base_url must be an http(s) URL")
	}
	u.Path = strings.TrimRight(strings.SplitN(u.Path, ";", 2)[0], "/")
	if !strings.HasSuffix(u.Path, "/api") {
		u.Path += "/api"
	}
	u.RawQuery, u.Fragment, u.RawPath = "", "", ""
	key := strings.TrimSpace(str(get(config, "api_key", "")))
	if key == "" {
		return habitsAPI{}, fmt.Errorf("Missing api_key in config: %s", path)
	}
	return habitsAPI{u.String(), key}, nil
}

func (a habitsAPI) request(path, method string, body any) (any, error) {
	v, err := httpJSON(&http.Client{Timeout: 3 * time.Second}, method, a.base+path, map[string]string{
		"Accept": "application/json", "Authorization": "Bearer " + a.key, "User-Agent": "habits-quickshell/0.1",
	}, body)
	if err != nil {
		var statusError *httpStatusError
		if errors.As(err, &statusError) {
			return nil, fmt.Errorf("Habits API returned HTTP %d", statusError.Code)
		}
		var requestError *url.Error
		if errors.As(err, &requestError) {
			return nil, fmt.Errorf("Habits API unreachable")
		}
	}
	return v, err
}

func (a habitsAPI) status() (obj, error) {
	health, err := a.request("/health", "GET", nil)
	if err != nil {
		return nil, err
	}
	if dict(health)["status"] != "OK" || dict(health)["app"] != "habits-api" {
		return habitsError("Habits API is not healthy"), nil
	}
	paths := []string{"/summary/today", "/summary/tomorrow", "/summary/weight", "/punishments/status", "/days/today", "/policies/to-do", "/contracts/status", "/notifications/persistent", "/deadlines"}
	values := make([]any, len(paths))
	for i, path := range paths {
		values[i], err = a.request(path, "GET", nil)
		if err != nil {
			return nil, err
		}
	}
	return habitsPayload(dict(values[0]), dict(values[1]), dict(values[2]), dict(values[3]), dict(values[4]), list(values[5]), dict(values[6]), dict(values[7]), dict(values[8])), nil
}

func hyprJSON(args ...string) any {
	args = append(append([]string{"hyprctl"}, args...), "-j")
	code, out, _ := command(time.Second, nil, args...)
	if code != 0 {
		return nil
	}
	var v any
	_ = json.Unmarshal([]byte(out), &v)
	return v
}

func launchHabits() int {
	workspace := dict(hyprJSON("activeworkspace"))
	name := strings.TrimSpace(str(fallback(workspace["name"], workspace["id"], "")))
	if existsCommand("systemctl") {
		_, _, _ = command(30*time.Second, nil, "systemctl", "--user", "start", "habits.service")
	}
	commands := [][]string{{"habits", "--toggle"}, {"flatpak", "run", "dev.meisterlala.habits", "--toggle"},
		{"gtk-launch", "habits"}, {"gtk-launch", "dev.meisterlala.habits"}, {"gio", "launch", "/usr/share/applications/habits.desktop"}}
	for _, args := range commands {
		if !existsCommand(args[0]) {
			continue
		}
		cmd := exec.Command(args[0], args[1:]...)
		cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
		if cmd.Start() != nil {
			continue
		}
		go func() { _ = cmd.Wait() }()
		if name != "" && existsCommand("hyprctl") {
			for i := 0; i < 10; i++ {
				address := ""
				for _, raw := range list(hyprJSON("clients")) {
					c := dict(raw)
					class := strings.ToLower(text(c, "class"))
					if class == "habits" || class == "habits-desktop" {
						address = strings.TrimSpace(text(c, "address"))
						if address != "" {
							break
						}
					}
				}
				if address != "" {
					_, _, _ = command(5*time.Second, nil, "hyprctl", "dispatch", "movetoworkspacesilent", "name:"+name+",address:"+address)
					_, _, _ = command(5*time.Second, nil, "hyprctl", "dispatch", "focuswindow", "address:"+address)
					break
				}
				time.Sleep(100 * time.Millisecond)
			}
		}
		return 0
	}
	fmt.Fprintln(os.Stderr, "Unable to launch Habits desktop app")
	return 1
}

func habits(args []string) int {
	if len(args) > 0 && args[0] == "--toggle-app" {
		return launchHabits()
	}
	action := len(args) > 0
	if action && !((args[0] == "--set-habit" && len(args) == 4) || (args[0] == "--stop-event" && len(args) == 3)) {
		fmt.Fprintln(os.Stderr, "Expected --toggle-app, --set-habit DATE ID STATUS, or --stop-event DATE ID")
		return 2
	}
	api, err := loadHabitsConfig()
	var payload obj
	if err == nil {
		if action {
			path := "/days/" + url.PathEscape(args[1])
			if args[0] == "--set-habit" {
				if args[3] != "done" && args[3] != "missed" {
					err = fmt.Errorf("Habit status must be done or missed")
				} else {
					_, err = api.request(path+"/habits/"+url.PathEscape(args[2]), "PUT", obj{"status": args[3]})
				}
			} else {
				_, err = api.request(path+"/events/"+url.PathEscape(args[2])+"/stop", "POST", obj{})
			}
		} else {
			payload, err = api.status()
		}
	}
	if err != nil {
		if action {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		payload = habitsError(err.Error())
	}
	if !action {
		emit(payload)
	}
	return 0
}
