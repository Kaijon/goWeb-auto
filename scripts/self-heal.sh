#!/usr/bin/env bash
# self-heal.sh
# Analyses go test -json output and produces a structured failure context JSON
# that copilot-generate.sh uses to augment the next generation prompt.
#
# Sub-commands:
#   extract  <RESULTS_JSON> <HEAL_FILE>   — Parse failures, write heal context
#   summary  <HEAL_FILE>                  — Print human-readable failure summary
#
# Heal context format (heal-context.json):
# {
#   "attempt":   1,
#   "failures": [
#     {
#       "test":    "TestCameraConfigInvalidBitrates/4K_bitrate_too_low",
#       "package": "github.com/you/goWeb/cmd/server",
#       "output":  "--- FAIL: TestCameraConfigInvalidBitrates/4K_bitrate_too_low\n    main_test.go:87: expected status 400, got 200"
#     }
#   ]
# }

set -euo pipefail

SUB_CMD="${1:?Sub-command required: extract | summary}"
shift

########################################
# extract: build heal context from test-results.json
########################################
cmd_extract() {
    local results_json="${1:?RESULTS_JSON path required}"
    local heal_file="${2:?HEAL_FILE path required}"

    if [[ ! -f "${results_json}" ]]; then
        echo "Error: ${results_json} not found" >&2
        exit 1
    fi

    # Determine current attempt number (increment if heal file already exists)
    local attempt=1
    if [[ -f "${heal_file}" ]]; then
        local prev_attempt
        prev_attempt=$(jq -r '.attempt // 0' "${heal_file}" 2>/dev/null || echo "0")
        attempt=$(( prev_attempt + 1 ))
    fi

    # Extract all failing test names and their output lines from go test -json stream.
    # go test -json format:
    #   {"Action":"fail","Package":"...","Test":"TestName","Elapsed":0.001}
    #   {"Action":"output","Package":"...","Test":"TestName","Output":"    some output\n"}
    #
    # Strategy: collect all output lines per test, then emit failures.

    python3 - <<PYEOF
import json, sys, re

results_file = "${results_json}"
heal_file    = "${heal_file}"
attempt      = ${attempt}

# Read all events
events = []
with open(results_file, "r") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            pass

# Group output lines by (package, test)
outputs = {}
for ev in events:
    pkg  = ev.get("Package", "")
    test = ev.get("Test")
    if not test:
        continue
    key = (pkg, test)
    if ev.get("Action") == "output":
        outputs.setdefault(key, []).append(ev.get("Output", ""))

# Collect failing tests
failures = []
for ev in events:
    if ev.get("Action") != "fail":
        continue
    test = ev.get("Test")
    if not test:
        continue  # skip package-level fail events
    pkg = ev.get("Package", "")
    key = (pkg, test)
    output_lines = outputs.get(key, [])
    failures.append({
        "test":    test,
        "package": pkg,
        "output":  "".join(output_lines).strip()
    })

heal_ctx = {
    "attempt":  attempt,
    "failures": failures
}

with open(heal_file, "w") as f:
    json.dump(heal_ctx, f, indent=2)

print(f"Heal context written: {len(failures)} failure(s) recorded (attempt {attempt})")
PYEOF

    cat "${heal_file}" >&2
}

########################################
# summary: print a human-readable failure summary
########################################
cmd_summary() {
    local heal_file="${1:?HEAL_FILE path required}"

    if [[ ! -f "${heal_file}" ]]; then
        echo "No heal context file found at ${heal_file}"
        exit 0
    fi

    echo "=== Self-Heal Context ==="
    jq -r '"Attempt: " + (.attempt | tostring)' "${heal_file}"
    echo ""
    jq -r '.failures[] | "FAIL: \(.test)\n  Package: \(.package)\n  Output:\n\(.output | split("\n") | map("    " + .) | join("\n"))\n"' "${heal_file}"
}

########################################
# Dispatch
########################################
case "${SUB_CMD}" in
    extract) cmd_extract "$@" ;;
    summary) cmd_summary "$@" ;;
    *)
        echo "Unknown sub-command: ${SUB_CMD}. Use: extract | summary" >&2
        exit 1
        ;;
esac
