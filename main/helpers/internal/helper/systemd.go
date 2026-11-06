package helper

import (
	"errors"
	"fmt"
	"os"
	"strings"
	"time"
)

func systemctlEnvironment() []string {
	runtime := env("XDG_RUNTIME_DIR", fmt.Sprintf("/run/user/%d", os.Getuid()))
	return []string{"DBUS_SESSION_BUS_ADDRESS=" + env("DBUS_SESSION_BUS_ADDRESS", "unix:path="+runtime+"/bus")}
}

func systemctlFailure(result commandResult) error {
	if message := strings.TrimSpace(result.Stderr); message != "" {
		return errors.New(message)
	}
	if result.Err != nil {
		return result.Err
	}
	return fmt.Errorf("systemctl exited with %d", result.Code)
}

func queryFailedUnits(user bool) ([]string, error) {
	args := []string{"systemctl"}
	if user {
		args = append(args, "--user")
	}
	args = append(args, "--failed", "--type=service", "--no-legend", "--plain")
	result := runCommand(5*time.Second, systemctlEnvironment(), args...)
	if result.Code != 0 {
		return nil, systemctlFailure(result)
	}
	units := []string{}
	for _, line := range strings.Split(result.Stdout, "\n") {
		if fields := strings.Fields(line); len(fields) > 0 {
			units = append(units, fields[0])
		}
	}
	return units, nil
}

func failedUnits() obj {
	system, systemError := queryFailedUnits(false)
	user, userError := queryFailedUnits(true)
	messages := []string{}
	if systemError != nil {
		messages = append(messages, "System services: "+systemError.Error())
	}
	if userError != nil {
		messages = append(messages, "User services: "+userError.Error())
	}
	return obj{"systemUnits": system, "userUnits": user, "error": strings.Join(messages, "\n")}
}

func restartFailedUnits() (int, error) {
	// Discover both scopes successfully before restarting anything. A failed
	// query must never be interpreted as an empty/healthy scope.
	system, err := queryFailedUnits(false)
	if err != nil {
		return 0, fmt.Errorf("Cannot query system services: %w", err)
	}
	user, err := queryFailedUnits(true)
	if err != nil {
		return 0, fmt.Errorf("Cannot query user services: %w", err)
	}

	restarted := 0
	var failures []error
	for _, scope := range []struct {
		name  string
		user  bool
		units []string
	}{{"system", false, system}, {"user", true, user}} {
		for _, unit := range scope.units {
			args := []string{"systemctl"}
			if scope.user {
				args = append(args, "--user")
			}
			args = append(args, "restart", "--", unit)
			result := runCommand(2*time.Minute, systemctlEnvironment(), args...)
			if result.Code != 0 {
				failures = append(failures, fmt.Errorf("Failed to restart %s:%s: %w", scope.name, unit, systemctlFailure(result)))
			} else {
				restarted++
			}
		}
	}
	return restarted, errors.Join(failures...)
}

func systemdFailedUnits(args []string) int {
	if len(args) == 0 || (len(args) == 1 && args[0] == "status") {
		emit(failedUnits())
		return 0
	}
	if len(args) != 1 || args[0] != "restart" {
		fmt.Fprintln(os.Stderr, "Usage: qs-helper systemd-failed-units [status|restart]")
		return 2
	}
	restarted, err := restartFailedUnits()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	if restarted > 0 {
		fmt.Fprintf(os.Stdout, "Restarted %d service(s).\n", restarted)
	}
	return 0
}
