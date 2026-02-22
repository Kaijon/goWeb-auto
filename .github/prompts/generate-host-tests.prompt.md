---
description: Generates comprehensive Go test code for the camera configuration backend and host simulator.
tools: [read-file]
---

# Task
Create comprehensive Go test code for the Embedded Camera Configuration Backend/Host Simulator.

# Context Gathering
1. Read `docs/specs/bitrate-policy.md` to understand the strict hardware constraints (bitrate ranges for each resolution).
2. Review `cmd/server/main.go` to understand the current API endpoint and server structure.
3. Review `.github/copilot-instructions.md` to understand error handling requirements and error codes (e.g., `0x01 INVALID_PARAM`).

# Test Coverage Guidelines
1. **Hardware Constraint Validation Tests**
   * Test each resolution with valid bitrate ranges (should succeed)
   * Test each resolution with out-of-range bitrates (should fail with `0x01 INVALID_PARAM`)
   * Test edge cases (min/max bitrate values)
   
2. **API Endpoint Tests**
   * Test successful POST request with valid payload
   * Test invalid HTTP method (non-POST) → HTTP 405
   * Test malformed JSON payload → HTTP 400
   * Test missing required fields (resolution or bitrate) → HTTP 400
   * Test invalid resolution value → error code `0x01`
   * Test negative or zero bitrate → error code `0x01`

3. **Error Handling Tests**
   * Verify response format for successful configuration
   * Verify response format for error cases with correct error codes
   * Verify error messages are clear and actionable

4. **Integration Tests (optional)**
   * Full request/response cycle for each valid resolution
   * Concurrent request handling
   * Server startup and graceful shutdown

# Implementation Details
1. **Test Structure:** Use Go's standard `testing` package with table-driven tests.
2. **Isolation:** Tests must be completely isolated and run without real hardware (mock/stub all hardware calls).
3. **Response Format:** Tests should validate JSON response structure and error codes per the backend contract.
4. **Logging:** Include debug logging for test failures to aid CI/local debugging.

# Output
Provide complete Go test files:
- `cmd/server/main_test.go` - Tests for the HTTP server and API endpoint
- `tests/integration_test.go` (optional) - Integration tests for end-to-end camera config flow

Both files should follow Go testing best practices:
- Table-driven tests for multiple scenarios
- Clear test names describing what is being tested
- Helper functions for setup/teardown
- Comprehensive error assertions
