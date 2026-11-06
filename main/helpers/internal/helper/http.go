package helper

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

type httpStatusError struct {
	Code int
}

func (err *httpStatusError) Error() string {
	return fmt.Sprintf("HTTP %d", err.Code)
}

func httpJSON(client *http.Client, method, endpoint string, headers map[string]string, body any) (any, error) {
	var reader io.Reader
	if body != nil {
		data, err := json.Marshal(body)
		if err != nil {
			return nil, err
		}
		reader = bytes.NewReader(data)
	}
	request, err := http.NewRequest(method, endpoint, reader)
	if err != nil {
		return nil, err
	}
	for key, value := range headers {
		request.Header.Set(key, value)
	}
	if body != nil {
		request.Header.Set("Content-Type", "application/json")
	}
	response, err := client.Do(request)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	if response.StatusCode >= http.StatusBadRequest {
		return nil, &httpStatusError{Code: response.StatusCode}
	}
	if response.StatusCode == http.StatusNoContent {
		return obj{}, nil
	}
	var value any
	err = json.NewDecoder(response.Body).Decode(&value)
	return value, err
}
