package helper

import (
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/google/shlex"
)

type modelItem struct {
	id, status, proxy string
	args              []string
	port              int
	context, params   float64
}

func modelPort(args []string) int {
	for i, a := range args {
		value := ""
		if a == "--port" && i+1 < len(args) {
			value = args[i+1]
		} else if strings.HasPrefix(a, "--port=") {
			value = strings.TrimPrefix(a, "--port=")
		} else {
			continue
		}
		n, _ := strconv.Atoi(value)
		return n
	}
	return 0
}

func childURL(args []string, port int) string {
	if port <= 0 {
		return ""
	}
	host := "127.0.0.1"
	for i, a := range args {
		if a == "--host" && i+1 < len(args) {
			host = args[i+1]
			break
		}
		if strings.HasPrefix(a, "--host=") {
			host = strings.TrimPrefix(a, "--host=")
			break
		}
	}
	if host == "0.0.0.0" {
		host = "127.0.0.1"
	} else if host == "::" {
		host = "::1"
	}
	if strings.Contains(host, ":") && !strings.HasPrefix(host, "[") {
		host = "[" + host + "]"
	}
	return fmt.Sprintf("http://%s:%d", host, port)
}

func modelPIDs(ports map[int]bool) map[int]int {
	pids := map[int]int{}
	entries, _ := os.ReadDir("/proc")
	for _, entry := range entries {
		pid, err := strconv.Atoi(entry.Name())
		if err != nil {
			continue
		}
		b, err := os.ReadFile(filepath.Join("/proc", entry.Name(), "cmdline"))
		if err != nil {
			continue
		}
		args := []string{}
		for _, a := range strings.Split(string(b), "\x00") {
			if a != "" {
				args = append(args, a)
			}
		}
		port := modelPort(args)
		if ports[port] {
			pids[port] = pid
		}
	}
	return pids
}

func gpuMemory(pids map[int]int) map[int]int64 {
	result := map[int]int64{}
	if len(pids) == 0 {
		return result
	}
	code, out, _ := command(time.Second, nil, "/usr/bin/nvidia-smi", "--query-compute-apps=pid,used_gpu_memory", "--format=csv,noheader,nounits")
	if code != 0 {
		return result
	}
	wanted := map[int]bool{}
	for _, pid := range pids {
		wanted[pid] = true
	}
	for _, line := range strings.Split(out, "\n") {
		fields := strings.SplitN(line, ",", 2)
		if len(fields) != 2 {
			continue
		}
		pid, e1 := strconv.Atoi(strings.TrimSpace(fields[0]))
		mib, e2 := strconv.ParseInt(strings.TrimSpace(fields[1]), 10, 64)
		if e1 == nil && e2 == nil && wanted[pid] {
			result[pid] += mib * 1048576
		}
	}
	return result
}

func llamaModels() obj {
	// Local child requests must never use HTTP_PROXY, even for custom bind hosts.
	client := &http.Client{Timeout: 1500 * time.Millisecond, Transport: &http.Transport{Proxy: nil}}
	defer client.CloseIdleConnections()
	fetch := func(url string) (any, error) { return httpJSON(client, "GET", url, nil, nil) }
	backend := "llama-swap"
	items := []modelItem{}
	payload, err := fetch("http://127.0.0.1:11435/running")
	running, swap := dict(payload)["running"].([]any)
	if err == nil && swap {
		for _, raw := range running {
			item := dict(raw)
			args, _ := shlex.Split(text(item, "cmd"))
			port := modelPort(args)
			status := "loading"
			if get(item, "state", "starting") == "ready" {
				status = "loaded"
			}
			proxy := strings.TrimRight(text(item, "proxy"), "/")
			if proxy == "" {
				proxy = childURL(args, port)
			}
			items = append(items, modelItem{id: str(get(item, "model", "Unknown model")), status: status, args: args, port: port, proxy: proxy})
		}
	} else {
		backend = "llama.cpp"
		payload, err = fetch("http://127.0.0.1:11435/v1/models")
		if err != nil {
			return obj{"models": []any{}, "backend": "", "error": err.Error()}
		}
		for _, raw := range list(dict(payload)["data"]) {
			item := dict(raw)
			statusInfo := dict(item["status"])
			status := str(get(statusInfo, "value", "unloaded"))
			if status != "loaded" && status != "loading" {
				continue
			}
			args := []string{}
			for _, a := range list(statusInfo["args"]) {
				args = append(args, str(a))
			}
			port := modelPort(args)
			meta := dict(item["meta"])
			items = append(items, modelItem{id: str(get(item, "id", "Unknown model")), status: status, args: args, port: port, proxy: childURL(args, port), context: num(meta["n_ctx"]), params: num(meta["n_params"])})
		}
	}
	ports := map[int]bool{}
	for _, item := range items {
		if item.port > 0 {
			ports[item.port] = true
		}
	}
	pids := modelPIDs(ports)
	memory := gpuMemory(pids)
	models := []obj{}
	for _, item := range items {
		model := obj{"id": item.id, "status": item.status, "active": false, "generationId": "", "generationTokens": 0, "promptTokens": 0, "contextSize": item.context, "params": item.params, "vramBytes": memory[pids[item.port]]}
		// Never poll a routing endpoint which could load or evict a model.
		if item.status == "loaded" && item.proxy != "" {
			value, err := fetch(item.proxy + "/slots")
			if slots, ok := value.([]any); err == nil && ok {
				contextSize, promptTokens, generationTokens := 0.0, 0.0, 0.0
				ids := []string{}
				active := false
				for _, raw := range slots {
					slot := dict(raw)
					contextSize = max(contextSize, num(slot["n_ctx"]))
					if !truth(slot["is_processing"]) {
						continue
					}
					active = true
					promptTokens += num(slot["n_prompt_tokens_processed"])
					next := list(slot["next_token"])
					if len(next) > 0 {
						generationTokens += num(dict(next[0])["n_decoded"])
					} else {
						generationTokens += num(get(slot, "n_decoded", get(slot, "n_tokens", 0)))
					}
					if slot["id_task"] != nil {
						ids = append(ids, str(slot["id_task"]))
					}
				}
				if contextSize > 0 {
					model["contextSize"] = contextSize
				}
				sort.Strings(ids)
				model["active"], model["promptTokens"], model["generationTokens"], model["generationId"] = active, promptTokens, generationTokens, strings.Join(ids, ",")
			}
		}
		models = append(models, model)
	}
	return obj{"models": models, "backend": backend, "error": ""}
}
