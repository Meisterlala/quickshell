package helper

import (
	"math"
	"net/http"
	"os"
	"time"
)

const daySeconds = 86400.0
const rad = math.Pi / 180

func astroLocation() obj {
	path := cachePath("astronomy-location.json")
	v, _ := readJSON(path)
	cached := dict(v)
	now := float64(time.Now().UnixNano()) / 1e9
	interval := 3600.0
	if _, ok := cached["latitude"]; ok {
		interval = 30 * daySeconds
	}
	if now-num(cached["attempt"]) > interval {
		cached["attempt"] = now
		v, e := httpJSON(&http.Client{Timeout: 5 * time.Second}, "GET", "https://ipapi.co/json/", map[string]string{"User-Agent": "quickshell-astronomy/1.0"}, nil)
		if e == nil {
			m := dict(v)
			lat, lok := m["latitude"]
			lon, ook := m["longitude"]
			if lok && ook {
				latitude, longitude := num(lat), num(lon)
				if latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180 {
					cached["latitude"], cached["longitude"], cached["city"] = latitude, longitude, get(m, "city", "Approximate location")
				}
			}
		}
		saveJSON(path, cached, 0600)
		_ = os.Chmod(path, 0600)
	}
	if _, ok := cached["latitude"]; !ok {
		return nil
	}
	return cached
}
func solar(date time.Time, latitude, longitude float64) obj {
	noon := time.Date(date.Year(), date.Month(), date.Day(), 12, 0, 0, 0, date.Location())
	days := float64(noon.Unix())/daySeconds + 2440587.5 - 2451545
	lw := -longitude * rad
	cycle := math.Floor(days - 0.0009 - lw/(2*math.Pi) + 0.5)
	approx := 0.0009 + lw/(2*math.Pi) + cycle
	anomaly := rad * (357.5291 + 0.98560028*approx)
	center := rad * (1.9148*math.Sin(anomaly) + 0.02*math.Sin(2*anomaly) + 0.0003*math.Sin(3*anomaly))
	longitudeSun := anomaly + center + rad*102.9372 + math.Pi
	declination := math.Asin(math.Sin(longitudeSun) * math.Sin(rad*23.4397))
	transit := 2451545 + approx + 0.0053*math.Sin(anomaly) - 0.0069*math.Sin(2*longitudeSun)
	cosAngle := (math.Sin(-0.833*rad) - math.Sin(latitude*rad)*math.Sin(declination)) / (math.Cos(latitude*rad) * math.Cos(declination))
	if cosAngle > 1 {
		return obj{"state": "Polar night"}
	}
	if cosAngle < -1 {
		return obj{"state": "Midnight sun"}
	}
	offset := math.Acos(cosAngle) / (2 * math.Pi)
	return obj{"sunrise": (transit - offset - 2440587.5) * daySeconds, "sunset": (transit + offset - 2440587.5) * daySeconds, "state": ""}
}
func moon(timestamp float64) obj {
	phase := (timestamp - 947182440) / daySeconds / 29.530588853
	phase -= math.Floor(phase)
	names := []string{"New moon", "Waxing crescent", "First quarter", "Waxing gibbous", "Full moon", "Waning gibbous", "Last quarter", "Waning crescent"}
	return obj{"phase": phase, "illumination": math.RoundToEven((1 - math.Cos(2*math.Pi*phase)) * 50), "moonName": names[int(phase*8+0.5)%8]}
}
func astronomy(now time.Time) obj {
	result := moon(float64(now.UnixNano()) / 1e9)
	loc := astroLocation()
	if loc == nil {
		result["error"] = "Location unavailable · retry later"
		return result
	}
	lat, lon := num(loc["latitude"]), num(loc["longitude"])
	for k, v := range solar(now, lat, lon) {
		result[k] = v
	}
	result["previousSunset"] = solar(now.AddDate(0, 0, -1), lat, lon)["sunset"]
	result["nextSunrise"] = solar(now.AddDate(0, 0, 1), lat, lon)["sunrise"]
	result["city"] = get(loc, "city", "Approximate location")
	return result
}
