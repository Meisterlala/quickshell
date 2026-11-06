package helper

import (
	"fmt"
	"math"
	"os"
	"strconv"
)

// These helpers normalize optional, loosely typed fields in upstream JSON APIs.
// Command-specific presentation and defaults stay in their integration files.
type obj = map[string]any

func dict(value any) obj {
	if object, ok := value.(map[string]any); ok && object != nil {
		return object
	}
	return obj{}
}

func list(value any) []any {
	if items, ok := value.([]any); ok {
		return items
	}
	return []any{}
}

func get(object obj, key string, defaultValue any) any {
	if value, ok := object[key]; ok {
		return value
	}
	return defaultValue
}

func str(value any) string {
	// Preserve existing display labels for nullable/boolean API fields.
	switch value := value.(type) {
	case nil:
		return "None"
	case string:
		return value
	case bool:
		if value {
			return "True"
		}
		return "False"
	default:
		return fmt.Sprint(value)
	}
}

func text(object obj, key string) string {
	return str(get(object, key, ""))
}

func num(value any) float64 {
	switch value := value.(type) {
	case float64:
		return value
	case int:
		return float64(value)
	case int64:
		return float64(value)
	case bool:
		if value {
			return 1
		}
	}
	return 0
}

func numeric(value any) bool {
	switch value.(type) {
	case float64, int, int64, bool:
		return true
	default:
		return false
	}
}

func truth(value any) bool {
	switch value := value.(type) {
	case nil:
		return false
	case bool:
		return value
	case string:
		return value != ""
	case []any:
		return len(value) > 0
	case map[string]any:
		return len(value) > 0
	default:
		return num(value) != 0
	}
}

func fallback(values ...any) any {
	for _, value := range values {
		if truth(value) {
			return value
		}
	}
	if len(values) > 0 {
		return values[len(values)-1]
	}
	return nil
}

func env(key, defaultValue string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}
	return defaultValue
}

func envFloat(key string, defaultValue float64) float64 {
	value, err := strconv.ParseFloat(os.Getenv(key), 64)
	if err != nil || math.IsNaN(value) || math.IsInf(value, 0) {
		return defaultValue
	}
	return value
}
