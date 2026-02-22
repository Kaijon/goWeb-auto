package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

// TestCameraConfigValidConfigurations tests that valid resolution/bitrate combinations are accepted
func TestCameraConfigValidConfigurations(t *testing.T) {
	tests := []struct {
		name              string
		resolution        string
		bitrate           int
		expectedStatus    int
		expectedSuccess   bool
		expectedErrorCode string
	}{
		// 4K: 8-16 Mbps
		{
			name:              "4K_min_bitrate",
			resolution:        "4k",
			bitrate:           8,
			expectedStatus:    http.StatusOK,
			expectedSuccess:   true,
			expectedErrorCode: "",
		},
		{
			name:              "4K_mid_bitrate",
			resolution:        "4k",
			bitrate:           12,
			expectedStatus:    http.StatusOK,
			expectedSuccess:   true,
			expectedErrorCode: "",
		},
		{
			name:              "4K_max_bitrate",
			resolution:        "4k",
			bitrate:           16,
			expectedStatus:    http.StatusOK,
			expectedSuccess:   true,
			expectedErrorCode: "",
		},

		// 2K: 6-12 Mbps
		{
			name:              "2K_min_bitrate",
			resolution:        "2k",
			bitrate:           6,
			expectedStatus:    http.StatusOK,
			expectedSuccess:   true,
			expectedErrorCode: "",
		},
		{
			name:              "2K_mid_bitrate",
			resolution:        "2k",
			bitrate:           9,
			expectedStatus:    http.StatusOK,
			expectedSuccess:   true,
			expectedErrorCode: "",
		},
		{
			name:              "2K_max_bitrate",
			resolution:        "2k",
			bitrate:           12,
			expectedStatus:    http.StatusOK,
			expectedSuccess:   true,
			expectedErrorCode: "",
		},

		// 1080P: 0-5 Mbps (< 6 Mbps)
		{
			name:              "1080P_min_bitrate",
			resolution:        "1080p",
			bitrate:           0,
			expectedStatus:    http.StatusOK,
			expectedSuccess:   true,
			expectedErrorCode: "",
		},
		{
			name:              "1080P_mid_bitrate",
			resolution:        "1080p",
			bitrate:           3,
			expectedStatus:    http.StatusOK,
			expectedSuccess:   true,
			expectedErrorCode: "",
		},
		{
			name:              "1080P_max_bitrate",
			resolution:        "1080p",
			bitrate:           5,
			expectedStatus:    http.StatusOK,
			expectedSuccess:   true,
			expectedErrorCode: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req, err := newConfigRequest("POST", "/api/camera/config", tt.resolution, tt.bitrate)
			if err != nil {
				t.Fatalf("Failed to create request: %v", err)
			}

			w := httptest.NewRecorder()
			handleCameraConfig(w, req)

			if w.Code != tt.expectedStatus {
				t.Errorf("Expected status %d, got %d", tt.expectedStatus, w.Code)
			}

			var resp struct {
				Success   bool   `json:"success"`
				Message   string `json:"message"`
				ErrorCode string `json:"errorCode,omitempty"`
			}
			if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
				t.Errorf("Failed to unmarshal response: %v", err)
			}

			if resp.Success != tt.expectedSuccess {
				t.Errorf("Expected success=%v, got %v", tt.expectedSuccess, resp.Success)
			}

			if resp.ErrorCode != tt.expectedErrorCode {
				t.Errorf("Expected errorCode=%q, got %q", tt.expectedErrorCode, resp.ErrorCode)
			}
		})
	}
}

// TestCameraConfigInvalidBitrates tests that out-of-range bitrates are rejected with 0x01 error
func TestCameraConfigInvalidBitrates(t *testing.T) {
	tests := []struct {
		name              string
		resolution        string
		bitrate           int
		expectedStatus    int
		expectedSuccess   bool
		expectedErrorCode string
	}{
		// 4K: too low (< 8)
		{
			name:              "4K_bitrate_too_low",
			resolution:        "4k",
			bitrate:           7,
			expectedStatus:    http.StatusBadRequest,
			expectedSuccess:   false,
			expectedErrorCode: "0x01",
		},
		// 4K: too high (> 16)
		{
			name:              "4K_bitrate_too_high",
			resolution:        "4k",
			bitrate:           17,
			expectedStatus:    http.StatusBadRequest,
			expectedSuccess:   false,
			expectedErrorCode: "0x01",
		},

		// 2K: too low (< 6)
		{
			name:              "2K_bitrate_too_low",
			resolution:        "2k",
			bitrate:           5,
			expectedStatus:    http.StatusBadRequest,
			expectedSuccess:   false,
			expectedErrorCode: "0x01",
		},
		// 2K: too high (> 12)
		{
			name:              "2K_bitrate_too_high",
			resolution:        "2k",
			bitrate:           13,
			expectedStatus:    http.StatusBadRequest,
			expectedSuccess:   false,
			expectedErrorCode: "0x01",
		},

		// 1080P: too high (>= 6)
		{
			name:              "1080P_bitrate_too_high",
			resolution:        "1080p",
			bitrate:           6,
			expectedStatus:    http.StatusBadRequest,
			expectedSuccess:   false,
			expectedErrorCode: "0x01",
		},
		// 1080P: negative bitrate
		{
			name:              "1080P_negative_bitrate",
			resolution:        "1080p",
			bitrate:           -1,
			expectedStatus:    http.StatusBadRequest,
			expectedSuccess:   false,
			expectedErrorCode: "0x01",
		},

		// Generic: negative bitrate
		{
			name:              "4K_negative_bitrate",
			resolution:        "4k",
			bitrate:           -5,
			expectedStatus:    http.StatusBadRequest,
			expectedSuccess:   false,
			expectedErrorCode: "0x01",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req, err := newConfigRequest("POST", "/api/camera/config", tt.resolution, tt.bitrate)
			if err != nil {
				t.Fatalf("Failed to create request: %v", err)
			}

			w := httptest.NewRecorder()
			handleCameraConfig(w, req)

			if w.Code != tt.expectedStatus {
				t.Errorf("Expected status %d, got %d", tt.expectedStatus, w.Code)
			}

			var resp struct {
				Success   bool   `json:"success"`
				Message   string `json:"message"`
				ErrorCode string `json:"errorCode"`
			}
			if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
				t.Errorf("Failed to unmarshal response: %v", err)
			}

			if resp.Success != tt.expectedSuccess {
				t.Errorf("Expected success=%v, got %v", tt.expectedSuccess, resp.Success)
			}

			if resp.ErrorCode != tt.expectedErrorCode {
				t.Errorf("Expected errorCode=%q, got %q", tt.expectedErrorCode, resp.ErrorCode)
			}
		})
	}
}

// TestCameraConfigInvalidResolution tests that unsupported resolutions are rejected
func TestCameraConfigInvalidResolution(t *testing.T) {
	tests := []struct {
		name              string
		resolution        string
		bitrate           int
		expectedStatus    int
		expectedSuccess   bool
		expectedErrorCode string
	}{
		{
			name:              "invalid_resolution_8k",
			resolution:        "8k",
			bitrate:           20,
			expectedStatus:    http.StatusBadRequest,
			expectedSuccess:   false,
			expectedErrorCode: "0x01",
		},
		{
			name:              "invalid_resolution_720p",
			resolution:        "720p",
			bitrate:           5,
			expectedStatus:    http.StatusBadRequest,
			expectedSuccess:   false,
			expectedErrorCode: "0x01",
		},
		{
			name:              "invalid_resolution_empty",
			resolution:        "",
			bitrate:           10,
			expectedStatus:    http.StatusBadRequest,
			expectedSuccess:   false,
			expectedErrorCode: "0x01",
		},
		{
			name:              "invalid_resolution_gibberish",
			resolution:        "xyz123",
			bitrate:           10,
			expectedStatus:    http.StatusBadRequest,
			expectedSuccess:   false,
			expectedErrorCode: "0x01",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req, err := newConfigRequest("POST", "/api/camera/config", tt.resolution, tt.bitrate)
			if err != nil {
				t.Fatalf("Failed to create request: %v", err)
			}

			w := httptest.NewRecorder()
			handleCameraConfig(w, req)

			if w.Code != tt.expectedStatus {
				t.Errorf("Expected status %d, got %d", tt.expectedStatus, w.Code)
			}

			var resp struct {
				Success   bool   `json:"success"`
				Message   string `json:"message"`
				ErrorCode string `json:"errorCode"`
			}
			if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
				t.Errorf("Failed to unmarshal response: %v", err)
			}

			if resp.ErrorCode != tt.expectedErrorCode {
				t.Errorf("Expected errorCode=%q, got %q", tt.expectedErrorCode, resp.ErrorCode)
			}
		})
	}
}

// TestCameraConfigHTTPMethods tests that only POST is accepted
func TestCameraConfigHTTPMethods(t *testing.T) {
	tests := []struct {
		name           string
		method         string
		expectedStatus int
	}{
		{
			name:           "GET_not_allowed",
			method:         "GET",
			expectedStatus: http.StatusMethodNotAllowed,
		},
		{
			name:           "PUT_not_allowed",
			method:         "PUT",
			expectedStatus: http.StatusMethodNotAllowed,
		},
		{
			name:           "DELETE_not_allowed",
			method:         "DELETE",
			expectedStatus: http.StatusMethodNotAllowed,
		},
		{
			name:           "PATCH_not_allowed",
			method:         "PATCH",
			expectedStatus: http.StatusMethodNotAllowed,
		},
		{
			name:           "POST_allowed",
			method:         "POST",
			expectedStatus: http.StatusOK,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req, err := newConfigRequest(tt.method, "/api/camera/config", "4k", 12)
			if err != nil {
				t.Fatalf("Failed to create request: %v", err)
			}

			w := httptest.NewRecorder()
			handleCameraConfig(w, req)

			if w.Code != tt.expectedStatus {
				t.Errorf("Expected status %d, got %d", tt.expectedStatus, w.Code)
			}
		})
	}
}

// TestCameraConfigMalformedJSON tests that malformed JSON is properly rejected
func TestCameraConfigMalformedJSON(t *testing.T) {
	tests := []struct {
		name           string
		body           string
		expectedStatus int
	}{
		{
			name:           "invalid_json",
			body:           `{invalid json}`,
			expectedStatus: http.StatusBadRequest,
		},
		{
			name:           "empty_body",
			body:           ``,
			expectedStatus: http.StatusBadRequest,
		},
		{
			name:           "missing_bitrate",
			body:           `{"resolution":"4k"}`,
			expectedStatus: http.StatusBadRequest,
		},
		{
			name:           "missing_resolution",
			body:           `{"bitrate":12}`,
			expectedStatus: http.StatusBadRequest,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest("POST", "/api/camera/config", bytes.NewBufferString(tt.body))
			req.Header.Set("Content-Type", "application/json")

			w := httptest.NewRecorder()
			handleCameraConfig(w, req)

			if w.Code != tt.expectedStatus {
				t.Errorf("Expected status %d, got %d", tt.expectedStatus, w.Code)
			}

			var resp struct {
				Success   bool   `json:"success"`
				ErrorCode string `json:"errorCode"`
			}
			if err := json.Unmarshal(w.Body.Bytes(), &resp); err == nil {
				if resp.Success {
					t.Error("Expected success=false for malformed request")
				}
			}
		})
	}
}

// TestCameraConfigResponseFormat tests that response format is correct and contains proper fields
func TestCameraConfigResponseFormat(t *testing.T) {
	t.Run("success_response_format", func(t *testing.T) {
		req, err := newConfigRequest("POST", "/api/camera/config", "4k", 12)
		if err != nil {
			t.Fatalf("Failed to create request: %v", err)
		}

		w := httptest.NewRecorder()
		handleCameraConfig(w, req)

		if w.Code != http.StatusOK {
			t.Errorf("Expected status 200, got %d", w.Code)
		}

		// Check content type
		if ct := w.Header().Get("Content-Type"); ct != "application/json" {
			t.Errorf("Expected Content-Type application/json, got %s", ct)
		}

		// Verify response structure
		var resp struct {
			Success   bool   `json:"success"`
			Message   string `json:"message"`
			ErrorCode string `json:"errorCode"`
		}
		if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
			t.Errorf("Failed to unmarshal response: %v", err)
		}

		if !resp.Success {
			t.Error("Expected success=true")
		}

		if resp.Message == "" {
			t.Error("Expected non-empty message")
		}

		if resp.ErrorCode != "" {
			t.Error("Expected empty errorCode for successful response")
		}
	})

	t.Run("error_response_format", func(t *testing.T) {
		req, err := newConfigRequest("POST", "/api/camera/config", "4k", 7) // Out of range
		if err != nil {
			t.Fatalf("Failed to create request: %v", err)
		}

		w := httptest.NewRecorder()
		handleCameraConfig(w, req)

		if w.Code != http.StatusBadRequest {
			t.Errorf("Expected status 400, got %d", w.Code)
		}

		var resp struct {
			Success   bool   `json:"success"`
			Message   string `json:"message"`
			ErrorCode string `json:"errorCode"`
		}
		if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
			t.Errorf("Failed to unmarshal response: %v", err)
		}

		if resp.Success {
			t.Error("Expected success=false")
		}

		if resp.ErrorCode == "" {
			t.Error("Expected non-empty errorCode for error response")
		}

		if resp.Message == "" {
			t.Error("Expected non-empty message")
		}
	})
}

// Helper function to create a config request
func newConfigRequest(method, path, resolution string, bitrate int) (*http.Request, error) {
	body := struct {
		Resolution string `json:"resolution"`
		Bitrate    int    `json:"bitrate"`
	}{
		Resolution: resolution,
		Bitrate:    bitrate,
	}

	bodyBytes, err := json.Marshal(body)
	if err != nil {
		return nil, err
	}

	req := httptest.NewRequest(method, path, bytes.NewBuffer(bodyBytes))
	req.Header.Set("Content-Type", "application/json")
	return req, nil
}

// Benchmark test for camera config endpoint
func BenchmarkCameraConfig(b *testing.B) {
	req, _ := newConfigRequest("POST", "/api/camera/config", "4k", 12)

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		w := httptest.NewRecorder()
		handleCameraConfig(w, req)
	}
}
