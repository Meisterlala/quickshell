package helper

import (
	"fmt"
	"regexp"
	"sort"
	"strings"
	"time"
)

var upgradeRE = regexp.MustCompile(`^(\S+)\s+(\S+)\s+->\s+(\S+)(?:\s+\[([^\]]+)\])?$`)

func parseUpgrades(raw string) []obj {
	result := []obj{}
	for _, line := range strings.Split(raw, "\n") {
		m := upgradeRE.FindStringSubmatch(strings.TrimSpace(line))
		if m == nil || strings.Contains(strings.ToLower(m[4]), "ignored") {
			continue
		}
		result = append(result, obj{"name": m[1], "old": m[2], "new": m[3]})
	}
	return result
}
func updates() obj {
	timeout := time.Duration(envFloat("QUICKSHELL_UPDATES_TIMEOUT", 120) * float64(time.Second))
	maxItems := int(envFloat("QUICKSHELL_UPDATES_MAX_ITEMS", 160))
	run := func(args ...string) (int, string, string) { return command(timeout, []string{"LC_ALL=C"}, args...) }
	var rc int
	var ro, re string
	if existsCommand("checkupdates") {
		rc, ro, re = run("checkupdates")
	} else {
		rc, ro, re = run("paru", "-Qu", "--repo", "--color", "never")
	}
	ac, ao, ae := run("paru", "-Qua", "--devel", "--color", "never")
	repoOK := rc == 0 || (rc == 2 && strings.TrimSpace(ro) == "" && strings.TrimSpace(re) == "")
	aurOK := ac == 0
	repos, aur := []obj{}, []obj{}
	if repoOK {
		repos = parseUpgrades(ro)
	}
	if aurOK {
		aur = parseUpgrades(ao)
	}
	mapping := map[string]string{}
	if len(repos) > 0 {
		args := []string{"pacman", "-Si"}
		for _, it := range repos {
			args = append(args, text(it, "name"))
		}
		c, out, _ := command(90*time.Second, []string{"LC_ALL=C"}, args...)
		if c == 0 {
			name, repo := "", "repo"
			for _, line := range append(strings.Split(out, "\n"), "") {
				line = strings.TrimSpace(line)
				if line == "" {
					if name != "" {
						mapping[name] = repo
					}
					name, repo = "", "repo"
					continue
				}
				parts := strings.SplitN(line, ":", 2)
				if len(parts) != 2 {
					continue
				}
				if strings.HasPrefix(line, "Name") {
					name = strings.TrimSpace(parts[1])
				} else if strings.HasPrefix(line, "Repository") {
					repo = strings.TrimSpace(parts[1])
				}
			}
		}
	}
	items := []obj{}
	for _, it := range repos {
		source := mapping[text(it, "name")]
		if source == "" {
			source = "repo"
		}
		it["source"] = strings.ToLower(source)
		items = append(items, it)
	}
	for _, it := range aur {
		source := "aur"
		if it["new"] == "latest-commit" {
			source = "devel"
		}
		it["source"] = source
		items = append(items, it)
	}
	order := map[string]int{"core": 0, "extra": 1, "multilib": 2, "aur": 3, "devel": 4, "repo": 5}
	rank := func(s string) int {
		n, ok := order[s]
		if !ok {
			return 9
		}
		return n
	}
	sort.SliceStable(items, func(i, j int) bool {
		a, b := items[i], items[j]
		as, bs := text(a, "source"), text(b, "source")
		if rank(as) != rank(bs) {
			return rank(as) < rank(bs)
		}
		if as != bs {
			return as < bs
		}
		return text(a, "name") < text(b, "name")
	})
	counts := map[string]int{}
	for _, it := range items {
		counts[text(it, "source")]++
	}
	count := len(items)
	state := "normal"
	if count == 0 {
		state = "updated"
	} else if count >= 50 {
		state = "critical"
	} else if count >= 15 {
		state = "warning"
	}
	// Preserve Python slicing, including a negative configured item limit.
	stop := maxItems
	if stop < 0 {
		stop = count + stop
	}
	stop = max(0, min(count, stop))
	payload := obj{"count": count, "state": state, "counts": counts, "items": items[:stop], "truncated": max(0, count-maxItems), "stale": false, "status": "ok"}
	path := cachePath("arch-updates.json")
	if !repoOK || !aurOK {
		errors := []string{}
		if !repoOK {
			errors = append(errors, "Repository check failed: "+str(fallback(strings.TrimSpace(re), fmt.Sprintf("exit %d", rc))))
		}
		if !aurOK {
			errors = append(errors, "AUR check failed: "+str(fallback(strings.TrimSpace(ae), fmt.Sprintf("exit %d", ac))))
		}
		message := strings.Join(errors, "\n")
		cached, _ := readJSON(path)
		if m, ok := cached.(map[string]any); ok {
			payload = m
			payload["stale"] = true
		}
		payload["state"] = "error"
		payload["error"] = message
		status := "error"
		if repoOK || aurOK {
			status = "partial"
		}
		for _, needle := range []string{"could not lock database", "failed to init transaction", "unable to lock database", "database is locked", "failed to synchronize", "timed out", "timeout"} {
			if strings.Contains(strings.ToLower(message), needle) {
				status = "updating"
				break
			}
		}
		payload["status"] = status
	} else {
		saveJSON(path, payload, 0600)
	}
	return payload
}
