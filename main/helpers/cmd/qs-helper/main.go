package main

import (
	"os"
	"path/filepath"
	"quickshell-helper/internal/helper"
)

func main() {
	// The binary is cached outside the config; the wrapper supplies its source directory.
	configDir := os.Getenv("QUICKSHELL_HELPER_DIR")
	if configDir == "" {
		configDir = filepath.Join("main", "helpers")
	}
	os.Exit(helper.Run(os.Args[1:], configDir))
}
