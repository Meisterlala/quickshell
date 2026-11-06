package helper

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

var alertURLRE = regexp.MustCompile(`https?://[^\s)\]>"']+`)

func shortenURLs(s string) string {
	return alertURLRE.ReplaceAllStringFunc(s, func(raw string) string {
		u, e := url.Parse(raw)
		if e != nil {
			return raw
		}
		host := strings.TrimRight(u.Host, "/")
		if host == "" {
			return raw
		}
		return host
	})
}
func formatAlertTime(s string) string {
	if s == "" {
		return ""
	}
	for _, f := range []string{time.RFC3339Nano, "2006-01-02T15:04:05", "2006-01-02 15:04:05", "2006-01-02"} {
		t, e := time.ParseInLocation(f, s, time.Local)
		if e == nil {
			return t.In(time.Local).Format("02.01 15:04")
		}
	}
	return s
}
func normalizeAlert(a obj) obj {
	labels, ann := dict(a["labels"]), dict(a["annotations"])
	clean := func(v any) string { return strings.TrimSpace(shortenURLs(strings.ReplaceAll(str(v), `\n`, "\n"))) }
	sev := strings.ToLower(str(get(labels, "severity", "unknown")))
	if sev == "" {
		sev = "unknown"
	}
	return obj{"name": get(labels, "alertname", "unknown"), "namespace": get(labels, "namespace", "-"), "severity": sev, "summary": clean(get(ann, "summary", "")), "description": clean(get(ann, "description", "")), "message": clean(fallback(ann["summary"], ann["description"], ann["message"], "")), "startsAt": formatAlertTime(text(a, "startsAt")), "labels": obj{"pod": get(labels, "pod", ""), "container": get(labels, "container", ""), "job": get(labels, "job", ""), "instance": get(labels, "instance", "")}}
}
func alertsPayload(alerts []any, context, namespace string) obj {
	watchdog := false
	normalized := []obj{}
	for _, raw := range alerts {
		a := dict(raw)
		if dict(a["status"])["state"] != "active" {
			continue
		}
		name := dict(a["labels"])["alertname"]
		if name == "Watchdog" {
			watchdog = true
		}
		if name == "Watchdog" || name == "InfoInhibitor" {
			continue
		}
		normalized = append(normalized, normalizeAlert(a))
	}
	sort.SliceStable(normalized, func(i, j int) bool {
		for _, k := range []string{"severity", "name", "namespace"} {
			a, b := str(normalized[i][k]), str(normalized[j][k])
			if a != b {
				return a < b
			}
		}
		return false
	})
	counts := map[string]int{"total": len(normalized), "critical": 0, "error": 0, "warning": 0, "info": 0, "unknown": 0}
	for _, a := range normalized {
		sev := text(a, "severity")
		if sev != "critical" && sev != "error" && sev != "warning" && sev != "info" {
			sev = "unknown"
		}
		counts[sev]++
	}
	state := "ok"
	if !watchdog || counts["critical"] > 0 {
		state = "critical"
	} else if counts["error"] > 0 {
		state = "error"
	} else if counts["warning"]+counts["info"]+counts["unknown"] > 0 {
		state = "warning"
	}
	text := ""
	if state != "ok" {
		text = ""
		if state == "critical" || state == "error" {
			text = ""
		}
		if len(normalized) > 0 {
			text += fmt.Sprintf(" %d", len(normalized))
		}
	}
	lines := []string{}
	if !watchdog {
		lines = append(lines, "Watchdog alert is missing")
	}
	if len(normalized) == 0 {
		lines = append(lines, "No active alerts")
	}
	for _, a := range normalized {
		line := fmt.Sprintf("%s: %s (%s)", a["severity"], a["name"], a["namespace"])
		if a["message"] != "" {
			line += "\n  " + str(a["message"])
		}
		lines = append(lines, line)
	}
	return obj{"text": text, "tooltip": strings.Join(lines, "\n\n"), "class": state, "state": state, "context": context, "namespace": namespace, "watchdogRunning": watchdog, "counts": counts, "alerts": normalized}
}
func k8sError(message, context, namespace string) obj {
	return obj{"text": "", "tooltip": message, "class": "critical", "state": "error", "error": message, "context": context, "namespace": namespace, "watchdogRunning": false, "counts": obj{"total": 0, "critical": 0, "error": 1, "warning": 0, "info": 0, "unknown": 0}, "alerts": []any{}}
}
func k8sAlerts() obj {
	// Preserve fatal command errors independently of kubectl's ordinary nonzero status.
	var fatal string
	run := func(args ...string) (int, string) {
		result := runCommand(30*time.Second, nil, args...)
		var exitError *exec.ExitError
		if result.Err != nil && !errors.As(result.Err, &exitError) {
			fatal = result.Err.Error()
		}
		return result.Code, result.Stdout
	}
	kubectl := func(args ...string) string {
		c, o := run(append([]string{"kubectl", "--request-timeout=" + env("K8S_ALERTS_TIMEOUT", "8s")}, args...)...)
		if c != 0 {
			return ""
		}
		return o
	}
	c, _ := run("kubectl", "version", "--client")
	if fatal != "" {
		return k8sError(fatal, "", "")
	}
	if c != 0 {
		return k8sError("Missing dependency: kubectl", "", "")
	}
	c, o := run("kubectl", "config", "current-context")
	context := ""
	if c == 0 {
		context = strings.TrimSpace(o)
	}
	if fatal != "" {
		return k8sError(fatal, "", "")
	}
	if context == "" {
		return k8sError("No current Kubernetes context configured.", "", "")
	}
	path := cachePath("alertmanager-namespace")
	if os.MkdirAll(filepath.Dir(path), 0700) != nil {
		path = fmt.Sprintf("/tmp/quickshell-alertmanager-namespace-%d", os.Getuid())
	}
	discover := func() string {
		raw := kubectl("get", "svc", "-A", "-o", "json")
		var data obj
		if json.Unmarshal([]byte(raw), &data) != nil {
			return ""
		}
		for _, it := range list(data["items"]) {
			md := dict(dict(it)["metadata"])
			if md["name"] == "alertmanager-operated" {
				return text(md, "namespace")
			}
		}
		return ""
	}
	save := func(ns string) { _ = writeAtomic(path, []byte(ns+"\n"), 0600) }
	ns := strings.TrimSpace(os.Getenv("ALERTMANAGER_NAMESPACE"))
	if ns == "" {
		b, _ := os.ReadFile(path)
		ns = strings.TrimSpace(string(b))
	}
	if ns == "" {
		ns = discover()
		if ns != "" {
			save(ns)
		}
	}
	if fatal != "" {
		return k8sError(fatal, "", "")
	}
	if ns == "" {
		return k8sError("Cannot find Alertmanager service (alertmanager-operated).", context, "")
	}
	fetch := func(ns string) string {
		return kubectl("get", "--raw", "/api/v1/namespaces/"+ns+"/services/http:alertmanager-operated:9093/proxy/api/v2/alerts")
	}
	raw := fetch(ns)
	if raw == "" && fatal == "" {
		refreshed := discover()
		if refreshed != "" && refreshed != ns {
			ns = refreshed
			save(ns)
			raw = fetch(ns)
		}
	}
	if fatal != "" {
		return k8sError(fatal, "", "")
	}
	if raw == "" {
		return k8sError("Cannot connect to cluster or Alertmanager API.", context, ns)
	}
	var alerts []any
	valid := json.Unmarshal([]byte(raw), &alerts) == nil && alerts != nil
	for _, a := range alerts {
		m, ok := a.(map[string]any)
		if !ok {
			valid = false
		}
		for _, key := range []string{"status", "labels", "annotations"} {
			if _, ok := get(m, key, obj{}).(map[string]any); !ok {
				valid = false
			}
		}
	}
	if !valid {
		return k8sError("Invalid alert data returned by Alertmanager API.", context, ns)
	}
	return alertsPayload(alerts, context, ns)
}
