#!/usr/bin/env python3

import json
import os
import subprocess
import urllib.error
import urllib.parse
import urllib.request


BASE_URL = "http://127.0.0.1:11435"


def fetch(path, model=None):
    if model:
        path = f"{path}?{urllib.parse.urlencode({'model': model})}"
    with urllib.request.urlopen(f"{BASE_URL}{path}", timeout=1.5) as response:
        return response.read().decode("utf-8")


def model_port(args):
    for index, arg in enumerate(args):
        if arg == "--port" and index + 1 < len(args):
            try:
                return int(args[index + 1])
            except (TypeError, ValueError):
                return 0
        if isinstance(arg, str) and arg.startswith("--port="):
            try:
                return int(arg.removeprefix("--port="))
            except ValueError:
                return 0
    return 0


def connected_ports():
    # A child connection proves a real request is already in flight, so querying
    # /slots cannot be what prevents an otherwise-idle model from sleeping.
    ports = set()
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(path, encoding="ascii") as connections:
                next(connections, None)
                for line in connections:
                    fields = line.split()
                    if len(fields) < 4 or fields[3] != "01":
                        continue
                    try:
                        ports.add(int(fields[1].rsplit(":", 1)[1], 16))
                        ports.add(int(fields[2].rsplit(":", 1)[1], 16))
                    except (IndexError, ValueError):
                        continue
        except OSError:
            continue
    return ports


def decoded_tokens(slot):
    next_token = slot.get("next_token", [])
    if not isinstance(next_token, list) or not next_token:
        return 0
    return int(next_token[0].get("n_decoded", 0))


def model_pids(ports):
    pids = {}
    for entry in os.scandir("/proc"):
        if not entry.name.isdigit():
            continue
        try:
            with open(f"{entry.path}/cmdline", "rb") as cmdline_file:
                args = [
                    part.decode(errors="replace")
                    for part in cmdline_file.read().split(b"\0")
                    if part
                ]
            port = model_port(args)
            if port in ports:
                pids[port] = int(entry.name)
        except OSError:
            continue
    return pids


def gpu_memory_by_pid(pids):
    if not pids:
        return {}
    try:
        result = subprocess.run(
            [
                "/usr/bin/nvidia-smi",
                "--query-compute-apps=pid,used_gpu_memory",
                "--format=csv,noheader,nounits",
            ],
            capture_output=True,
            check=True,
            text=True,
            timeout=1,
        )
    except (OSError, subprocess.SubprocessError):
        return {}

    memory = {}
    for line in result.stdout.splitlines():
        try:
            pid_text, mib_text = line.split(",", 1)
            pid = int(pid_text.strip())
            if pid in pids:
                memory[pid] = memory.get(pid, 0) + int(mib_text.strip()) * 1048576
        except ValueError:
            continue
    return memory


def main():
    try:
        catalog = json.loads(fetch("/v1/models")).get("data", [])
    except (OSError, ValueError, urllib.error.URLError) as error:
        print(json.dumps({"models": [], "error": str(error)}))
        return

    running_items = []
    for item in catalog:
        status_info = item.get("status", {})
        status = str(status_info.get("value", "unloaded"))
        if status not in ("loaded", "loading"):
            continue
        running_items.append(
            (item, status_info, status, model_port(status_info.get("args", [])))
        )

    pids = model_pids({port for _, _, _, port in running_items if port > 0})
    gpu_memory = gpu_memory_by_pid(set(pids.values()))
    active_ports = connected_ports()
    models = []
    for item, status_info, status, port in running_items:
        meta = item.get("meta", {})
        has_active_request = status == "loaded" and port in active_ports
        model = {
            "id": str(item.get("id", "Unknown model")),
            "status": status,
            "active": has_active_request,
            "generationId": "",
            "generationTokens": 0,
            "promptTokens": 0,
            "contextSize": int(meta.get("n_ctx", 0)),
            "params": float(meta.get("n_params", 0)),
            "vramBytes": int(gpu_memory.get(pids.get(port), 0)),
        }

        if has_active_request:
            try:
                slots = json.loads(fetch("/slots", model["id"]))
                processing = [slot for slot in slots if slot.get("is_processing")]
                model["active"] = bool(processing)
                model["promptTokens"] = sum(
                    int(slot.get("n_prompt_tokens_processed", 0)) for slot in processing
                )
                model["generationTokens"] = sum(
                    decoded_tokens(slot) for slot in processing
                )
                model["generationId"] = ",".join(
                    sorted(
                        str(slot.get("id_task"))
                        for slot in processing
                        if slot.get("id_task") is not None
                    )
                )
            except (OSError, ValueError, TypeError, urllib.error.URLError):
                pass

        models.append(model)

    print(json.dumps({"models": models, "error": ""}, separators=(",", ":")))


if __name__ == "__main__":
    main()
