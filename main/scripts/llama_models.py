#!/usr/bin/env python3

import json
import os
import shlex
import subprocess
import urllib.error
import urllib.request


BASE_URL = "http://127.0.0.1:11435"
# Never send local llama.cpp child requests through an environment HTTP proxy.
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def fetch_url(url, timeout=1.5):
    with OPENER.open(url, timeout=timeout) as response:
        return response.read().decode("utf-8")


def fetch(path):
    return fetch_url(f"{BASE_URL}{path}")


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


def model_host(args):
    host = "127.0.0.1"
    for index, arg in enumerate(args):
        if arg == "--host" and index + 1 < len(args):
            host = str(args[index + 1])
            break
        if isinstance(arg, str) and arg.startswith("--host="):
            host = arg.removeprefix("--host=")
            break

    # Connect through loopback even if a server was deliberately bound wider.
    if host == "0.0.0.0":
        host = "127.0.0.1"
    elif host == "::":
        host = "::1"
    return f"[{host}]" if ":" in host and not host.startswith("[") else host


def child_url(args, port):
    return f"http://{model_host(args)}:{port}" if port > 0 else ""


def command_args(command):
    try:
        return shlex.split(command)
    except (TypeError, ValueError):
        return []


def decoded_tokens(slot):
    next_token = slot.get("next_token", [])
    if isinstance(next_token, list) and next_token:
        return int(next_token[0].get("n_decoded", 0))
    # Compatibility with alternate llama.cpp slot schemas.
    return int(slot.get("n_decoded", slot.get("n_tokens", 0)))


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


def swap_items():
    """Return normalized llama-swap /running entries, or None if not swap."""
    try:
        payload = json.loads(fetch("/running"))
    except (OSError, ValueError, urllib.error.URLError):
        return None
    running = payload.get("running")
    if not isinstance(running, list):
        return None

    items = []
    for item in running:
        args = command_args(item.get("cmd", ""))
        port = model_port(args)
        state = str(item.get("state", "starting"))
        items.append(
            {
                "id": str(item.get("model", "Unknown model")),
                "status": "loaded" if state == "ready" else "loading",
                "args": args,
                "port": port,
                "proxy": str(item.get("proxy", "")).rstrip("/")
                or child_url(args, port),
                "contextSize": 0,
                "params": 0,
            }
        )
    return items


def llama_router_items():
    """Return normalized native llama.cpp multi-model router entries."""
    payload = json.loads(fetch("/v1/models"))
    catalog = payload.get("data", [])
    if not isinstance(catalog, list):
        return []

    items = []
    for item in catalog:
        status_info = item.get("status", {})
        status = str(status_info.get("value", "unloaded"))
        if status not in ("loaded", "loading"):
            continue
        raw_args = status_info.get("args", [])
        args = [str(arg) for arg in raw_args] if isinstance(raw_args, list) else []
        port = model_port(args)
        meta = item.get("meta", {})
        items.append(
            {
                "id": str(item.get("id", "Unknown model")),
                "status": status,
                "args": args,
                "port": port,
                "proxy": child_url(args, port),
                "contextSize": int(meta.get("n_ctx", 0)),
                "params": float(meta.get("n_params", 0)),
            }
        )
    return items


def main():
    backend = "llama-swap"
    items = swap_items()
    if items is None:
        backend = "llama.cpp"
        try:
            items = llama_router_items()
        except (OSError, ValueError, TypeError, urllib.error.URLError) as error:
            print(json.dumps({"models": [], "backend": "", "error": str(error)}))
            return

    pids = model_pids({item["port"] for item in items if item["port"] > 0})
    gpu_memory = gpu_memory_by_pid(set(pids.values()))
    models = []

    for item in items:
        port = item["port"]
        model = {
            "id": item["id"],
            "status": item["status"],
            "active": False,
            "generationId": "",
            "generationTokens": 0,
            "promptTokens": 0,
            "contextSize": item["contextSize"],
            "params": item["params"],
            "vramBytes": int(gpu_memory.get(pids.get(port), 0)),
        }

        # Query only an already-running child. Polling the bar must never route
        # through a model endpoint that could load or evict a model.
        proxy = item["proxy"]
        if model["status"] == "loaded" and proxy:
            try:
                slots = json.loads(fetch_url(f"{proxy}/slots"))
                if isinstance(slots, list):
                    slot_context = max(
                        (int(slot.get("n_ctx", 0)) for slot in slots), default=0
                    )
                    if slot_context > 0:
                        model["contextSize"] = slot_context
                    processing = [slot for slot in slots if slot.get("is_processing")]
                    model["active"] = bool(processing)
                    model["promptTokens"] = sum(
                        int(slot.get("n_prompt_tokens_processed", 0))
                        for slot in processing
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

    print(
        json.dumps(
            {"models": models, "backend": backend, "error": ""},
            separators=(",", ":"),
        )
    )


if __name__ == "__main__":
    main()
