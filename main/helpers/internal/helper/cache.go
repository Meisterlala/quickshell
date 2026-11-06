package helper

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

func home() string {
	path, _ := os.UserHomeDir()
	return path
}

func cachePath(name string) string {
	return filepath.Join(env("XDG_CACHE_HOME", filepath.Join(home(), ".cache")), "quickshell", name)
}

func readJSON(path string) (any, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var value any
	err = json.Unmarshal(data, &value)
	return value, err
}

// Caches are best-effort, but concurrent readers must never see partial JSON.
func saveJSON(path string, value any, mode os.FileMode) {
	data, err := json.Marshal(value)
	if err != nil {
		return
	}
	_ = writeAtomic(path, data, mode)
}

func writeAtomic(path string, data []byte, mode os.FileMode) error {
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return err
	}
	file, err := os.CreateTemp(filepath.Dir(path), ".helper-cache-*")
	if err != nil {
		return err
	}
	defer os.Remove(file.Name())
	defer file.Close()
	if err := file.Chmod(mode); err != nil {
		return err
	}
	if _, err := file.Write(data); err != nil {
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	return os.Rename(file.Name(), path)
}

func emit(value any) {
	encoder := json.NewEncoder(os.Stdout)
	encoder.SetEscapeHTML(false)
	if err := encoder.Encode(value); err != nil {
		fmt.Fprintln(os.Stderr, "Cannot encode helper response:", err)
	}
}
