package helper

import (
	"crypto/md5"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/xml"
	"fmt"
	"io"
	"math"
	"net/http"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"
)

const fritzService = "urn:dslforum-org:service:WANCommonInterfaceConfig:1"
const fritzAction = "X_AVM-DE_GetOnlineMonitor"
const soapBody = `<?xml version="1.0"?>
<s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
  <s:Body>
    <u:X_AVM-DE_GetOnlineMonitor xmlns:u="urn:dslforum-org:service:WANCommonInterfaceConfig:1">
      <NewSyncGroupIndex>0</NewSyncGroupIndex>
    </u:X_AVM-DE_GetOnlineMonitor>
  </s:Body>
</s:Envelope>
`

var digestRE = regexp.MustCompile(`(\w+)=(?:"([^"]*)"|([^,\s]+))`)

// Digest authentication is required by TR-064; Basic auth is not equivalent.
func digestAuth(challenge, method, uri, user, password string) (string, error) {
	if !strings.HasPrefix(strings.ToLower(challenge), "digest ") {
		return "", nil
	}
	fields := map[string]string{}
	for _, m := range digestRE.FindAllStringSubmatch(challenge, -1) {
		fields[m[1]] = m[2] + m[3]
	}
	algorithm := strings.ToUpper(fields["algorithm"])
	if algorithm == "" {
		algorithm = "MD5"
	}
	hash := func(s string) string {
		if strings.HasPrefix(algorithm, "SHA-256") {
			h := sha256.Sum256([]byte(s))
			return hex.EncodeToString(h[:])
		}
		h := md5.Sum([]byte(s))
		return hex.EncodeToString(h[:])
	}
	if algorithm != "MD5" && algorithm != "MD5-SESS" && algorithm != "SHA-256" && algorithm != "SHA-256-SESS" {
		return "", fmt.Errorf("Unsupported digest algorithm: %s", algorithm)
	}
	random := make([]byte, 8)
	if _, e := rand.Read(random); e != nil {
		return "", e
	}
	cnonce := hex.EncodeToString(random)
	ha1 := hash(user + ":" + fields["realm"] + ":" + password)
	if strings.HasSuffix(algorithm, "-SESS") {
		ha1 = hash(ha1 + ":" + fields["nonce"] + ":" + cnonce)
	}
	ha2 := hash(method + ":" + uri)
	qop := ""
	for _, q := range strings.Split(fields["qop"], ",") {
		if strings.TrimSpace(q) == "auth" {
			qop = "auth"
		}
	}
	if fields["qop"] != "" && qop == "" {
		return "", fmt.Errorf("Unsupported digest qop")
	}
	response := hash(ha1 + ":" + fields["nonce"] + ":" + ha2)
	if qop != "" {
		response = hash(ha1 + ":" + fields["nonce"] + ":00000001:" + cnonce + ":auth:" + ha2)
	}
	quote := func(s string) string { return `"` + strings.NewReplacer(`\`, `\\`, `"`, `\"`).Replace(s) + `"` }
	auth := "Digest username=" + quote(user) + ", realm=" + quote(fields["realm"]) + ", nonce=" + quote(fields["nonce"]) + ", uri=" + quote(uri) + ", response=" + quote(response) + ", algorithm=" + algorithm
	if fields["opaque"] != "" {
		auth += ", opaque=" + quote(fields["opaque"])
	}
	if qop != "" {
		auth += ", qop=auth, nc=00000001, cnonce=" + quote(cnonce)
	}
	return auth, nil
}
func fetchFritz(url, user, password string, timeout time.Duration) (string, error) {
	client := &http.Client{Timeout: timeout}
	send := func(auth string) (*http.Response, error) {
		req, e := http.NewRequest("POST", url, strings.NewReader(soapBody))
		if e != nil {
			return nil, e
		}
		req.Header.Set("Content-Type", `text/xml; charset="utf-8"`)
		req.Header.Set("SOAPAction", `"`+fritzService+"#"+fritzAction+`"`)
		if auth != "" {
			req.Header.Set("Authorization", auth)
		}
		return client.Do(req)
	}
	resp, e := send("")
	if e != nil {
		return "", e
	}
	if resp.StatusCode == 401 {
		challenge := resp.Header.Get("WWW-Authenticate")
		_, _ = io.Copy(io.Discard, resp.Body)
		_ = resp.Body.Close()
		req, _ := http.NewRequest("POST", url, nil)
		auth, e := digestAuth(challenge, "POST", req.URL.RequestURI(), user, password)
		if e != nil {
			return "", e
		}
		resp, e = send(auth)
		if e != nil {
			return "", e
		}
	}
	defer resp.Body.Close()
	if resp.StatusCode == 401 {
		return "", fmt.Errorf("FRITZ!Box rejected the configured user/password")
	}
	if resp.StatusCode >= 400 {
		return "", fmt.Errorf("FRITZ!Box traffic request failed: HTTP %d", resp.StatusCode)
	}
	b, e := io.ReadAll(resp.Body)
	return string(b), e
}
func parseTraffic(raw string) (float64, float64, error) {
	decoder := xml.NewDecoder(strings.NewReader(raw))
	values := map[string]string{}
	fault := false
	for {
		token, e := decoder.Token()
		if e == io.EOF {
			break
		}
		if e != nil {
			return 0, 0, fmt.Errorf("Could not parse FRITZ!Box response: %s", e)
		}
		if start, ok := token.(xml.StartElement); ok {
			name := start.Name.Local
			if name == "Fault" {
				fault = true
			}
			for _, key := range []string{"Newds_current_bps", "Newus_current_bps"} {
				if strings.HasSuffix(name, key) {
					var value string
					if e := decoder.DecodeElement(&value, &start); e != nil {
						return 0, 0, fmt.Errorf("Could not parse FRITZ!Box response: %s", e)
					}
					if _, ok := values[key]; !ok {
						values[key] = value
					}
				}
			}
		}
	}
	if fault {
		return 0, 0, fmt.Errorf("FRITZ!Box returned a SOAP fault")
	}
	rates := []float64{}
	for _, key := range []string{"Newds_current_bps", "Newus_current_bps"} {
		samples := []int64{}
		for _, part := range strings.Split(strings.ReplaceAll(values[key], ";", ","), ",") {
			n, e := strconv.ParseInt(strings.TrimSpace(part), 10, 64)
			if e == nil {
				samples = append(samples, n)
			}
		}
		if len(samples) == 0 {
			return 0, 0, fmt.Errorf("FRITZ!Box response is missing valid traffic samples")
		}
		for _, n := range samples {
			if n < 0 {
				return 0, 0, fmt.Errorf("FRITZ!Box response is missing valid traffic samples")
			}
		}
		recent := samples[max(0, len(samples)-5):]
		total := 0.0
		for _, n := range recent {
			total += float64(n)
		}
		rates = append(rates, total*8/float64(len(recent))/1e6)
	}
	return rates[0], rates[1], nil
}
func fritzTraffic() obj {
	downLimit, upLimit := envFloat("FRITZ_TRAFFIC_DOWN_LIMIT_MBIT", 250), envFloat("FRITZ_TRAFFIC_UP_LIMIT_MBIT", 50)
	warn, critical, hide := envFloat("FRITZ_TRAFFIC_WARN_AT", .75), envFloat("FRITZ_TRAFFIC_CRITICAL_AT", .90), envFloat("FRITZ_TRAFFIC_HIDE_AT", .65)
	p := obj{"visible": env("FRITZ_TRAFFIC_HIDE_ERRORS", "1") != "1", "state": "error", "error": "", "downMbit": 0, "upMbit": 0, "downLimitMbit": downLimit, "upLimitMbit": upLimit, "downRatio": 0, "upRatio": 0, "maxRatio": 0, "warnAt": warn, "criticalAt": critical, "hideAt": hide}
	raw, e := fetchFritz(strings.TrimRight(env("FRITZBOX_URL", "http://fritz.box:49000"), "/")+"/upnp/control/wancommonifconfig1", os.Getenv("FRITZBOX_USER"), os.Getenv("FRITZBOX_PASSWORD"), time.Duration(envFloat("FRITZ_TRAFFIC_TIMEOUT", 4)*float64(time.Second)))
	if e != nil {
		message := e.Error()
		if !strings.HasPrefix(message, "FRITZ!Box") {
			message = "FRITZ!Box traffic request failed: " + message
		}
		p["error"] = message
		return p
	}
	down, up, e := parseTraffic(raw)
	if e != nil {
		p["error"] = e.Error()
		return p
	}
	dr, ur := 0.0, 0.0
	if downLimit > 0 {
		dr = down / downLimit
	}
	if upLimit > 0 {
		ur = up / upLimit
	}
	ratio := math.Max(dr, ur)
	path := cachePath("fritz_traffic.json")
	previous, _ := readJSON(path)
	visible := ratio >= warn || (truth(dict(previous)["visible"]) && ratio >= hide)
	saveJSON(path, obj{"visible": visible}, 0600)
	state := "normal"
	if ratio >= critical {
		state = "critical"
	} else if ratio >= warn {
		state = "warning"
	}
	p["visible"], p["state"], p["downMbit"], p["upMbit"], p["downRatio"], p["upRatio"], p["maxRatio"] = visible, state, down, up, dr, ur, ratio
	return p
}
