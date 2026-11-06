// Package helper implements the stateless JSON adapters used by the QML UI.
package helper

import (
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/joho/godotenv"
)

// Run loads shared configuration and dispatches one helper command.
func Run(args []string, configDir string) int {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "Usage: qs-helper <astronomy|updates|codex-usage|fritz-traffic|habits|k8s-alerts|llama-models|notification-controls|systemd-failed-units|calendar|idle-inhibitors> [args]")
		return 2
	}
	// Exported environment variables take precedence over the shared dotenv file.
	if err := godotenv.Load(filepath.Join(configDir, ".env")); err != nil && !os.IsNotExist(err) {
		emit(obj{"error": "Cannot load helpers/.env: " + err.Error(), "state": "error", "visible": true})
		return 1
	}
	var payload obj
	exitCode := 0
	switch args[0] {
	case "astronomy":
		payload = astronomy(time.Now())
	case "updates":
		payload = updates()
	case "codex-usage":
		payload = codexUsage()
	case "fritz-traffic":
		payload = fritzTraffic()
	case "habits":
		return habits(args[1:])
	case "k8s-alerts":
		payload = k8sAlerts()
	case "llama-models":
		payload = llamaModels()
	case "notification-controls":
		payload, exitCode = notificationControls(args[1:])
	case "systemd-failed-units":
		return systemdFailedUnits(args[1:])
	case "calendar":
		payload = calendar(args[1:])
	case "idle-inhibitors":
		payload = idleInhibitors()
	default:
		fmt.Fprintln(os.Stderr, "Unknown helper:", args[0])
		return 2
	}
	emit(payload)
	return exitCode
}
