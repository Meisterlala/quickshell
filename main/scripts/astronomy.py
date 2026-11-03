#!/usr/bin/env python3
"""Offline solar times and approximate lunar phase, with cached IP geolocation."""
import datetime as dt
import json
import math
import os
from pathlib import Path
import time
import urllib.request

DAY = 86400
RAD = math.pi / 180
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "quickshell/astronomy-location.json"


def location():
    cached = {}
    try:
        cached = json.loads(CACHE.read_text())
    except (OSError, ValueError):
        pass
    now = time.time()
    if now - cached.get("attempt", 0) > (30 * DAY if "latitude" in cached else 3600):
        cached["attempt"] = now
        try:
            request = urllib.request.Request("https://ipapi.co/json/", headers={"User-Agent": "quickshell-astronomy/1.0"})
            with urllib.request.urlopen(request, timeout=5) as response:
                data = json.load(response)
            lat, lon = float(data["latitude"]), float(data["longitude"])
            if not (-90 <= lat <= 90 and -180 <= lon <= 180):
                raise ValueError("Invalid coordinates")
            cached.update(latitude=lat, longitude=lon, city=data.get("city", "Approximate location"))
        except (OSError, ValueError, KeyError, TypeError):
            pass  # Keep the last successful location when offline.
        try:
            CACHE.parent.mkdir(parents=True, exist_ok=True)
            CACHE.write_text(json.dumps(cached))
            CACHE.chmod(0o600)
        except OSError:
            pass
    return cached if "latitude" in cached else None


def solar(date, latitude, longitude):
    """SunCalc solar transit equations; sunrise includes refraction (-0.833°)."""
    noon = dt.datetime.combine(date, dt.time(12)).astimezone().timestamp()
    days = noon / DAY + 2440587.5 - 2451545
    lw = -longitude * RAD
    cycle = math.floor(days - 0.0009 - lw / (2 * math.pi) + 0.5)
    approx = 0.0009 + lw / (2 * math.pi) + cycle
    anomaly = RAD * (357.5291 + 0.98560028 * approx)
    center = RAD * (1.9148 * math.sin(anomaly) + 0.02 * math.sin(2 * anomaly) + 0.0003 * math.sin(3 * anomaly))
    longitude_sun = anomaly + center + RAD * 102.9372 + math.pi
    declination = math.asin(math.sin(longitude_sun) * math.sin(RAD * 23.4397))
    transit = 2451545 + approx + 0.0053 * math.sin(anomaly) - 0.0069 * math.sin(2 * longitude_sun)
    cos_angle = (math.sin(-0.833 * RAD) - math.sin(latitude * RAD) * math.sin(declination)) / (math.cos(latitude * RAD) * math.cos(declination))
    if cos_angle > 1:
        return {"state": "Polar night"}
    if cos_angle < -1:
        return {"state": "Midnight sun"}
    offset = math.acos(cos_angle) / (2 * math.pi)
    return {"sunrise": (transit - offset - 2440587.5) * DAY,
            "sunset": (transit + offset - 2440587.5) * DAY, "state": ""}


def moon(timestamp):
    # Mean synodic month from the 2000-01-06 new moon (approximate, not an ephemeris).
    phase = ((timestamp - 947182440) / DAY / 29.530588853) % 1
    names = ["New moon", "Waxing crescent", "First quarter", "Waxing gibbous",
             "Full moon", "Waning gibbous", "Last quarter", "Waning crescent"]
    return {"phase": phase, "illumination": round((1 - math.cos(2 * math.pi * phase)) * 50),
            "moonName": names[int(phase * 8 + 0.5) % 8]}


def main():
    result = moon(time.time())
    loc = location()
    if loc:
        today = dt.date.today()
        result.update(solar(today, loc["latitude"], loc["longitude"]))
        result["previousSunset"] = solar(today - dt.timedelta(days=1), loc["latitude"], loc["longitude"]).get("sunset")
        result["nextSunrise"] = solar(today + dt.timedelta(days=1), loc["latitude"], loc["longitude"]).get("sunrise")
        result["city"] = loc.get("city", "Approximate location")
    else:
        result["error"] = "Location unavailable · retry later"
    print(json.dumps(result))


if __name__ == "__main__":
    main()
