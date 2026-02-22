#!/usr/bin/env bash
# run-simulation.sh
# Manages the Go host simulator lifecycle and runs the test suite.
#
# Sub-commands:
#   start  <PORT> <DIST_DIR> <PID_FILE>   — Build and launch Go server
#   test   <RESULTS_JSON>                  — Run go test with JSON + coverage output
#   stop   <PID_FILE>                      — Gracefully terminate the simulator
#
# The test sub-command writes go test -json output to RESULTS_JSON and also
# writes a human-readable coverage summary to coverage.txt.

set -euo pipefail

SUB_CMD="${1:?Sub-command required: start | test | stop}"
shift

########################################
# start: Compile and launch Go simulator
########################################
cmd_start() {
    local port="${1:?PORT required}"
    local dist_dir="${2:?DIST_DIR required}"
    local pid_file="${3:?PID_FILE required}"

    # Validate port is numeric and in safe range
    if ! [[ "${port}" =~ ^[0-9]+$ ]] || (( port < 1024 || port > 65535 )); then
        echo "Error: PORT must be a number between 1024 and 65535" >&2
        exit 1
    fi

    # Kill any existing simulator on that port
    if [[ -f "${pid_file}" ]]; then
        local old_pid
        old_pid=$(cat "${pid_file}")
        kill "${old_pid}" 2>/dev/null || true
        rm -f "${pid_file}"
    fi

    # Ensure the dist/ directory was built
    if [[ ! -d "${dist_dir}" ]]; then
        echo "Error: ${dist_dir} not found. Run 'npm run build' first." >&2
        exit 1
    fi

    # Compile the Go server
    echo "Building Go simulator..." >&2
    go build -o .simulator ./cmd/server/

    # Start in background, redirect logs to simulator.log
    PORT="${port}" DIST_DIR="${dist_dir}" ./.simulator > simulator.log 2>&1 &
    echo $! > "${pid_file}"
    echo "Simulator started (PID $(cat "${pid_file}")) on :${port}" >&2
}

########################################
# test: Run the Go test suite
########################################
cmd_test() {
    local results_json="${1:?RESULTS_JSON path required}"

    echo "Running test suite..." >&2

    # Run all packages with JSON output + coverage; tee to file and stderr for visibility
    go test ./... \
        -v \
        -coverprofile=coverage.out \
        -json \
        2>&1 | tee "${results_json}"

    # Generate human-readable coverage summary
    go tool cover -func=coverage.out > coverage.txt 2>/dev/null || true

    # Determine exit status from JSON results (jq counts failed actions)
    local failed_count
    failed_count=$(grep -c '"Action":"fail"' "${results_json}" || echo "0")

    echo "Test failures detected: ${failed_count}" >&2

    if (( failed_count > 0 )); then
        exit 1
    fi
}

########################################
# stop: Terminate the simulator
########################################
cmd_stop() {
    local pid_file="${1:?PID_FILE required}"

    if [[ -f "${pid_file}" ]]; then
        local pid
        pid=$(cat "${pid_file}")
        if kill -0 "${pid}" 2>/dev/null; then
            kill "${pid}"
            echo "Simulator (PID ${pid}) stopped." >&2
        fi
        rm -f "${pid_file}"
    else
        echo "No simulator PID file found; nothing to stop." >&2
    fi

    rm -f .simulator
}

########################################
# Dispatch
########################################
case "${SUB_CMD}" in
    start) cmd_start "$@" ;;
    test)  cmd_test  "$@" ;;
    stop)  cmd_stop  "$@" ;;
    *)
        echo "Unknown sub-command: ${SUB_CMD}. Use: start | test | stop" >&2
        exit 1
        ;;
esac
