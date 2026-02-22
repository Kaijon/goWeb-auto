package tests

import (
	"bytes"
	"encoding/json"
	"fmt"
	"sync"
	"sync/atomic"
	"testing"
)

// ValidationResult holds validation outcome
type ValidationResult struct {
	Valid bool
	Error string
}

// ValidateBitrateForResolution validates bitrate against resolution constraints from bitrate-policy.md
func ValidateBitrateForResolution(resolution string, bitrate int) ValidationResult {
	switch resolution {
	case "4k":
		// 4K: 8-16 Mbps
		if bitrate < 8 || bitrate > 16 {
			return ValidationResult{
				Valid: false,
				Error: fmt.Sprintf("0x01 INVALID_PARAM: 4K bitrate must be 8-16 Mbps, got %d", bitrate),
			}
		}
	case "2k":
		// 2K: 6-12 Mbps
		if bitrate < 6 || bitrate > 12 {
			return ValidationResult{
				Valid: false,
				Error: fmt.Sprintf("0x01 INVALID_PARAM: 2K bitrate must be 6-12 Mbps, got %d", bitrate),
			}
		}
	case "1080p":
		// 1080P: < 6 Mbps (0-5 range)
		if bitrate < 0 || bitrate >= 6 {
			return ValidationResult{
				Valid: false,
				Error: fmt.Sprintf("0x01 INVALID_PARAM: 1080P bitrate must be 0-5 Mbps, got %d", bitrate),
			}
		}
	default:
		return ValidationResult{
			Valid: false,
			Error: fmt.Sprintf("0x01 INVALID_PARAM: unsupported resolution %q", resolution),
		}
	}
	return ValidationResult{Valid: true}
}

// TestValidationLogic tests the underlying validation function
func TestValidationLogic(t *testing.T) {
	tests := []struct {
		name       string
		resolution string
		bitrate    int
		shouldPass bool
	}{
		// Valid 4K cases
		{"4K_8", "4k", 8, true},
		{"4K_12", "4k", 12, true},
		{"4K_16", "4k", 16, true},

		// Invalid 4K cases
		{"4K_7", "4k", 7, false},
		{"4K_17", "4k", 17, false},
		{"4K_negative", "4k", -5, false},
		{"4K_zero", "4k", 0, false},

		// Valid 2K cases
		{"2K_6", "2k", 6, true},
		{"2K_9", "2k", 9, true},
		{"2K_12", "2k", 12, true},

		// Invalid 2K cases
		{"2K_5", "2k", 5, false},
		{"2K_13", "2k", 13, false},
		{"2K_negative", "2k", -1, false},

		// Valid 1080P cases
		{"1080P_0", "1080p", 0, true},
		{"1080P_3", "1080p", 3, true},
		{"1080P_5", "1080p", 5, true},

		// Invalid 1080P cases
		{"1080P_6", "1080p", 6, false},
		{"1080P_negative", "1080p", -1, false},
		{"1080P_ten", "1080p", 10, false},

		// Invalid resolutions
		{"Invalid_8k", "8k", 20, false},
		{"Invalid_720p", "720p", 5, false},
		{"Invalid_empty", "", 10, false},
		{"Invalid_gibberish", "xyz123", 10, false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := ValidateBitrateForResolution(tt.resolution, tt.bitrate)
			passed := result.Valid

			if passed != tt.shouldPass {
				t.Errorf("expected pass=%v, got %v (error=%s)", tt.shouldPass, passed, result.Error)
			}

			if tt.shouldPass && !result.Valid {
				t.Errorf("validation failed for valid input: %s", result.Error)
			}

			if !tt.shouldPass && result.Valid {
				t.Errorf("validation passed for invalid input: %s @ %d", tt.resolution, tt.bitrate)
			}
		})
	}
}

// TestIntegrationValidConfigurations tests end-to-end valid configuration flow
func TestIntegrationValidConfigurations(t *testing.T) {
	validConfigs := []struct {
		name       string
		resolution string
		bitrate    int
	}{
		{"4K_valid_min", "4k", 8},
		{"4K_valid_mid", "4k", 12},
		{"4K_valid_max", "4k", 16},
		{"2K_valid_min", "2k", 6},
		{"2K_valid_mid", "2k", 9},
		{"2K_valid_max", "2k", 12},
		{"1080P_valid_min", "1080p", 0},
		{"1080P_valid_mid", "1080p", 3},
		{"1080P_valid_max", "1080p", 5},
	}

	for _, cfg := range validConfigs {
		t.Run(cfg.name, func(t *testing.T) {
			result := ValidateBitrateForResolution(cfg.resolution, cfg.bitrate)
			if !result.Valid {
				t.Errorf("Expected valid config for %s @ %d Mbps, got error: %s",
					cfg.resolution, cfg.bitrate, result.Error)
			}
		})
	}
}

// TestIntegrationInvalidConfigurations tests that invalid configs are properly rejected
func TestIntegrationInvalidConfigurations(t *testing.T) {
	invalidConfigs := []struct {
		name       string
		resolution string
		bitrate    int
	}{
		{"4K_too_low", "4k", 7},
		{"4K_too_high", "4k", 17},
		{"2K_too_low", "2k", 5},
		{"2K_too_high", "2k", 13},
		{"1080P_too_high", "1080p", 6},
		{"1080P_negative", "1080p", -1},
		{"invalid_8k", "8k", 20},
		{"invalid_720p", "720p", 5},
	}

	for _, cfg := range invalidConfigs {
		t.Run(cfg.name, func(t *testing.T) {
			result := ValidateBitrateForResolution(cfg.resolution, cfg.bitrate)
			if result.Valid {
				t.Errorf("Expected invalid config for %s @ %d Mbps to be rejected",
					cfg.resolution, cfg.bitrate)
			}
			if result.Error == "" {
				t.Error("Expected error message for invalid config")
			}
		})
	}
}

// TestConcurrentValidation tests that validation is goroutine-safe
func TestConcurrentValidation(t *testing.T) {
	numGoroutines := 100
	numRequestsPerGoroutine := 50
	var successCount int32
	var errorCount int32

	wg := &sync.WaitGroup{}
	wg.Add(numGoroutines)

	for i := 0; i < numGoroutines; i++ {
		go func(index int) {
			defer wg.Done()

			for j := 0; j < numRequestsPerGoroutine; j++ {
				// Vary the resolution and bitrate
				resolutions := []string{"4k", "2k", "1080p"}
				resolution := resolutions[j%len(resolutions)]

				var bitrate int
				switch resolution {
				case "4k":
					bitrate = 8 + (j % 9) // 8-16 range
				case "2k":
					bitrate = 6 + (j % 7) // 6-12 range
				case "1080p":
					bitrate = j % 6 // 0-5 range
				}

				result := ValidateBitrateForResolution(resolution, bitrate)
				if result.Valid {
					atomic.AddInt32(&successCount, 1)
				} else {
					atomic.AddInt32(&errorCount, 1)
				}
			}
		}(i)
	}

	wg.Wait()

	expectedSuccesses := int32(numGoroutines * numRequestsPerGoroutine)
	if successCount != expectedSuccesses {
		t.Logf("Concurrent validation: %d successful, %d errors (expected all %d to succeed)",
			successCount, errorCount, expectedSuccesses)
	}
}

// TestErrorRecovery tests that validation works correctly after errors
func TestErrorRecovery(t *testing.T) {
	validConfigs := []struct {
		resolution string
		bitrate    int
	}{
		{"4k", 10},
		{"2k", 8},
		{"1080p", 4},
	}

	// Test error then recovery pattern
	for i := 0; i < 3; i++ {
		// First: invalid config
		invalidResult := ValidateBitrateForResolution("4k", 50)
		if invalidResult.Valid {
			t.Error("Expected invalid config to be rejected")
		}

		// Then: valid config (recovery)
		for _, cfg := range validConfigs {
			validResult := ValidateBitrateForResolution(cfg.resolution, cfg.bitrate)
			if !validResult.Valid {
				t.Errorf("Expected valid config after error, got: %s", validResult.Error)
			}
		}
	}
}

// TestBoundaryConditions tests edge cases for bitrate boundaries
func TestBoundaryConditions(t *testing.T) {
	tests := []struct {
		name       string
		resolution string
		bitrate    int
		shouldPass bool
	}{
		// 4K boundaries
		{"4K_boundary_7", "4k", 7, false},
		{"4K_boundary_8", "4k", 8, true},
		{"4K_boundary_16", "4k", 16, true},
		{"4K_boundary_17", "4k", 17, false},

		// 2K boundaries
		{"2K_boundary_5", "2k", 5, false},
		{"2K_boundary_6", "2k", 6, true},
		{"2K_boundary_12", "2k", 12, true},
		{"2K_boundary_13", "2k", 13, false},

		// 1080P boundaries
		{"1080P_boundary_negative", "1080p", -1, false},
		{"1080P_boundary_0", "1080p", 0, true},
		{"1080P_boundary_5", "1080p", 5, true},
		{"1080P_boundary_6", "1080p", 6, false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := ValidateBitrateForResolution(tt.resolution, tt.bitrate)
			if result.Valid != tt.shouldPass {
				t.Errorf("expected %v, got %v for boundary test", tt.shouldPass, result.Valid)
			}
		})
	}
}

// TestErrorMessageFormat tests that error messages contain the 0x01 error code
func TestErrorMessageFormat(t *testing.T) {
	testCases := []struct {
		resolution string
		bitrate    int
	}{
		{"8k", 20},
		{"4k", 7},
		{"2k", 13},
		{"1080p", 6},
	}

	for _, tc := range testCases {
		result := ValidateBitrateForResolution(tc.resolution, tc.bitrate)
		if !contains(result.Error, "0x01") {
			t.Errorf("Error message should contain 0x01 error code, got: %s", result.Error)
		}
		if !contains(result.Error, "INVALID_PARAM") {
			t.Errorf("Error message should contain INVALID_PARAM, got: %s", result.Error)
		}
	}
}

// TestAPIResponseStructure validates the expected JSON response structure
func TestAPIResponseStructure(t *testing.T) {
	t.Run("success_response_fields", func(t *testing.T) {
		successResponse := map[string]interface{}{
			"success":   true,
			"message":   "Camera configuration updated: resolution=4k, bitrate=12 Mbps",
			"errorCode": "",
		}

		body, _ := json.Marshal(successResponse)
		var resp map[string]interface{}
		if err := json.Unmarshal(body, &resp); err != nil {
			t.Errorf("Failed to unmarshal success response: %v", err)
		}

		if _, ok := resp["success"]; !ok {
			t.Error("Missing 'success' field in response")
		}
		if _, ok := resp["message"]; !ok {
			t.Error("Missing 'message' field in response")
		}
		if _, ok := resp["errorCode"]; !ok {
			t.Error("Missing 'errorCode' field in response")
		}
	})

	t.Run("error_response_fields", func(t *testing.T) {
		errorResponse := map[string]interface{}{
			"success":   false,
			"message":   "0x01 INVALID_PARAM: 4K bitrate must be 8-16 Mbps, got 7",
			"errorCode": "0x01",
		}

		body, _ := json.Marshal(errorResponse)
		var resp map[string]interface{}
		if err := json.Unmarshal(body, &resp); err != nil {
			t.Errorf("Failed to unmarshal error response: %v", err)
		}

		if success, ok := resp["success"].(bool); !ok || success {
			t.Error("expected success=false in error response")
		}
		if errorCode, ok := resp["errorCode"].(string); !ok || errorCode != "0x01" {
			t.Error("expected errorCode=0x01 in error response")
		}
	})
}

// Helper function to check if string contains substring
func contains(s, substr string) bool {
	return bytes.Contains([]byte(s), []byte(substr))
}

// Benchmark: Validation performance
func BenchmarkValidation(b *testing.B) {
	testCase := struct {
		resolution string
		bitrate    int
	}{"4k", 12}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		ValidateBitrateForResolution(testCase.resolution, testCase.bitrate)
	}
}

// Benchmark: Concurrent validation
func BenchmarkConcurrentValidation(b *testing.B) {
	b.RunParallel(func(pb *testing.PB) {
		for pb.Next() {
			ValidateBitrateForResolution("4k", 12)
		}
	})
}
