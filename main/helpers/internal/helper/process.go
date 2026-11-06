package helper

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"
)

type commandResult struct {
	Code   int
	Stdout string
	Stderr string
	Err    error
}

func runCommand(timeout time.Duration, extraEnv []string, args ...string) commandResult {
	if len(args) == 0 {
		return commandResult{Code: 1, Err: errors.New("empty command")}
	}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, args[0], args[1:]...)
	cmd.Env = append(os.Environ(), extraEnv...)
	// Bound waits on pipes inherited by grandchildren as well as the command.
	cmd.WaitDelay = time.Second
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	err := cmd.Run()
	result := commandResult{Stdout: stdout.String(), Stderr: stderr.String(), Err: err}
	if ctx.Err() != nil {
		result.Code = 1
		result.Err = fmt.Errorf("%s timed out after %g seconds: %w", strings.Join(args, " "), timeout.Seconds(), ctx.Err())
	} else if err != nil {
		result.Code = 1
		var exitError *exec.ExitError
		if errors.As(err, &exitError) {
			result.Code = exitError.ExitCode()
		}
	}
	return result
}

// Most adapters only need an exit status and captured streams. Callers that
// distinguish a timeout/start failure from an ordinary exit use runCommand.
func command(timeout time.Duration, extraEnv []string, args ...string) (int, string, string) {
	result := runCommand(timeout, extraEnv, args...)
	var exitError *exec.ExitError
	if result.Err != nil && result.Stderr == "" && !errors.As(result.Err, &exitError) {
		result.Stderr = result.Err.Error()
	}
	return result.Code, result.Stdout, result.Stderr
}

func existsCommand(name string) bool {
	_, err := exec.LookPath(name)
	return err == nil
}
