package helper

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"math"
	"os"
	"os/exec"
	"strconv"
	"time"
)

func callRateLimits() (obj, error) {
	if _, e := os.Stat("/usr/bin/codex"); os.IsNotExist(e) {
		return nil, fmt.Errorf("codex CLI not found")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "/usr/bin/codex", "app-server")
	cmd.WaitDelay = time.Second
	in, e := cmd.StdinPipe()
	if e != nil {
		return nil, e
	}
	out, e := cmd.StdoutPipe()
	if e != nil {
		_ = in.Close()
		return nil, e
	}
	if e = cmd.Start(); e != nil {
		_ = in.Close()
		return nil, e
	}
	defer func() {
		_ = in.Close()
		_ = cmd.Process.Signal(os.Interrupt)
		done := make(chan struct{})
		go func() { _ = cmd.Wait(); close(done) }()
		select {
		case <-done:
		case <-time.After(time.Second):
			_ = cmd.Process.Kill()
			<-done
		}
	}()
	enc := json.NewEncoder(in)
	send := func(m obj) error { return enc.Encode(m) }
	if e = send(obj{"jsonrpc": "2.0", "id": "1", "method": "initialize", "params": obj{"clientInfo": obj{"name": "quickshell-codex-usage", "version": "1.0"}, "capabilities": obj{"experimentalApi": true}}}); e != nil {
		return nil, e
	}
	scanner := bufio.NewScanner(out)
	scanner.Buffer(make([]byte, 65536), 16*1024*1024)
	initialized := false
	for scanner.Scan() {
		var m obj
		if json.Unmarshal(scanner.Bytes(), &m) != nil || m == nil {
			continue
		}
		id := str(m["id"])
		if (id == "1" || id == "2") && truth(m["error"]) {
			er := m["error"]
			if mm, ok := er.(map[string]any); ok {
				return nil, fmt.Errorf("%s", get(mm, "message", str(er)))
			}
			return nil, fmt.Errorf("%s", str(er))
		}
		if id == "1" && !initialized {
			initialized = true
			if e = send(obj{"jsonrpc": "2.0", "method": "initialized", "params": obj{}}); e != nil {
				return nil, e
			}
			if e = send(obj{"jsonrpc": "2.0", "id": "2", "method": "account/rateLimits/read", "params": obj{}}); e != nil {
				return nil, e
			}
		} else if id == "2" {
			return dict(dict(m["result"])["rateLimits"]), nil
		}
	}
	return nil, fmt.Errorf("No account/rateLimits/read response from codex app-server")
}
func floatValue(v any) (float64, error) {
	if numeric(v) {
		return num(v), nil
	}
	return strconv.ParseFloat(str(v), 64)
}
func usageWindow(label string, window obj, now time.Time) obj {
	used, _ := floatValue(get(window, "usedPercent", 0))
	if math.IsNaN(used) || math.IsInf(used, 0) {
		used = 0
	}
	used = math.Max(0, math.Min(100, math.RoundToEven(used)))
	resetIn, resetAt := "", ""
	if v := window["resetsAt"]; v != nil {
		n, e := floatValue(v)
		if e == nil && !math.IsInf(n, 0) && !math.IsNaN(n) && n >= -62135596800 && n <= 253402300799 {
			reset := time.Unix(int64(n), 0)
			secs := int(reset.Sub(now).Seconds())
			if secs <= 0 {
				resetIn = "now"
			} else {
				days := secs / 86400
				hours := secs % 86400 / 3600
				mins := secs % 3600 / 60
				if days > 0 {
					resetIn += fmt.Sprintf("%dd", days)
				}
				if hours > 0 {
					resetIn += fmt.Sprintf("%dh", hours)
				}
				resetIn += fmt.Sprintf("%dm", mins)
			}
			format := "15:04"
			if label != "5h" {
				format = "02.01"
			}
			resetAt = reset.In(time.Local).Format(format)
		}
	}
	return obj{"label": label, "available": len(window) > 0, "usedPercent": used, "resetIn": resetIn, "resetAt": resetAt}
}
func codexPayload(limits obj, now time.Time) obj {
	primary, secondary := usageWindow("5h", obj{}, now), usageWindow("7d", obj{}, now)
	for _, key := range []string{"primary", "secondary"} {
		w := dict(limits[key])
		duration, e := floatValue(w["windowDurationMins"])
		if e != nil {
			continue
		}
		if int(duration) == 300 {
			primary = usageWindow("5h", w, now)
		} else if int(duration) == 10080 {
			secondary = usageWindow("7d", w, now)
		}
	}
	pct := math.Max(num(primary["usedPercent"]), num(secondary["usedPercent"]))
	state := "normal"
	if pct >= 90 {
		state = "critical"
	} else if pct >= 66 {
		state = "warning"
	}
	credits := dict(limits["credits"])
	return obj{"state": state, "primary": primary, "secondary": secondary, "credits": obj{"hasCredits": truth(credits["hasCredits"]), "unlimited": truth(credits["unlimited"]), "balance": credits["balance"]}}
}
func codexUsage() obj {
	limits, e := callRateLimits()
	if e != nil {
		return obj{"error": e.Error()}
	}
	if len(limits) == 0 {
		return obj{"error": "No usage data (run `codex login`)"}
	}
	return codexPayload(limits, time.Now())
}
