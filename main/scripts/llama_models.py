#!/usr/bin/env python3

import json
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


def main():
    try:
        catalog = json.loads(fetch("/v1/models")).get("data", [])
    except (OSError, ValueError, urllib.error.URLError) as error:
        print(json.dumps({"models": [], "error": str(error)}))
        return

    active_ports = connected_ports()
    models = []
    for item in catalog:
        status_info = item.get("status", {})
        status = str(status_info.get("value", "unloaded"))
        if status not in ("loaded", "loading"):
            continue

        meta = item.get("meta", {})
        port = model_port(status_info.get("args", []))
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
            "size": float(meta.get("size", 0)),
            "modalities": item.get("architecture", {}).get("input_modalities", []),
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
