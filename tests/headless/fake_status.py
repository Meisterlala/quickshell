"""Slow, deterministic router response; never contacts a router."""
import json
import time

time.sleep(0.25)
print(json.dumps({"visible": True, "state": "warning", "error": "", "downMbit": 123, "upMbit": 0, "downRatio": 0.8, "upRatio": 0, "maxRatio": 0.8}))
