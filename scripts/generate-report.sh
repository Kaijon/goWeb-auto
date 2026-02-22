#!/usr/bin/env bash
# generate-report.sh
# Generates the interactive HTML test report from go test JSON output.
#
# Strategy:
#   1. Parse test-results.json (go test -json format) to extract metrics.
#   2. Call the Copilot API with generate-test-report.prompt.md + the parsed metrics
#      so Copilot can produce a polished, context-aware HTML report.
#   3. If the API call fails, fall back to regenerating the static test-report.html
#      already present in the repository using the embedded JSON patch approach.
#
# Usage:
#   ./generate-report.sh [OPTIONS]
#
# Options:
#   --results   PATH   Required. go test -json output file
#   --prompt    PATH   Required. generate-test-report.prompt.md
#   --api-url   URL    Required. Copilot/Models API base URL
#   --model     NAME   Optional. Model name (default: gpt-4o)
#   --out-file  PATH   Optional. Output HTML file (default: test-report.html)
#   --build-url URL    Optional. Jenkins build URL for link in report

set -euo pipefail

########################################
# Argument parsing
########################################
RESULTS_FILE=""
PROMPT_FILE=""
API_URL=""
MODEL="gpt-4o"
OUT_FILE="test-report.html"
BUILD_URL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --results)   RESULTS_FILE="$2";  shift 2 ;;
        --prompt)    PROMPT_FILE="$2";   shift 2 ;;
        --api-url)   API_URL="$2";       shift 2 ;;
        --model)     MODEL="$2";         shift 2 ;;
        --out-file)  OUT_FILE="$2";      shift 2 ;;
        --build-url) BUILD_URL="$2";     shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

for var_name in RESULTS_FILE PROMPT_FILE API_URL; do
    if [[ -z "${!var_name}" ]]; then
        echo "Error: --${var_name//_/-} is required" >&2
        exit 1
    fi
done

if ! [[ "${API_URL}" =~ ^https:// ]]; then
    echo "Error: API_URL must use HTTPS" >&2
    exit 1
fi

########################################
# Parse go test -json output into summary metrics
########################################
echo "Parsing test results from ${RESULTS_FILE}..." >&2

# Count pass/fail/skip at test action level (not package level)
PASSED=$(grep -c '"Action":"pass"' "${RESULTS_FILE}"  2>/dev/null || echo "0")
FAILED=$(grep -c '"Action":"fail"' "${RESULTS_FILE}"  2>/dev/null || echo "0")
SKIPPED=$(grep -c '"Action":"skip"' "${RESULTS_FILE}" 2>/dev/null || echo "0")

# Extract individual test results as JSON array
TEST_ARRAY=$(jq -c '[
    select(.Action == "pass" or .Action == "fail" or .Action == "skip")
    | select(.Test != null)
    | { name: .Test, status: .Action, time: (.Elapsed // 0 | tostring + "s"), package: .Package }
]' "${RESULTS_FILE}" 2>/dev/null || echo "[]")

# Extract coverage percentage
COVERAGE_PCT=$(grep -oP 'coverage: \K[0-9.]+' "${RESULTS_FILE}" | tail -1 || echo "0")

# Total elapsed time (sum of package elapsed)
TOTAL_TIME=$(jq -r '[select(.Action=="pass" or .Action=="fail") | select(.Test==null) | .Elapsed // 0] | add // 0' "${RESULTS_FILE}" 2>/dev/null || echo "0")

# Build metrics JSON
METRICS=$(jq -n \
    --argjson passed   "${PASSED}" \
    --argjson failed   "${FAILED}" \
    --argjson skipped  "${SKIPPED}" \
    --argjson coverage "${COVERAGE_PCT}" \
    --argjson elapsed  "${TOTAL_TIME}" \
    --argjson tests    "${TEST_ARRAY}" \
    --arg     build    "${BUILD_URL}" \
    '{
        summary: {
            passed:   $passed,
            failed:   $failed,
            skipped:  $skipped,
            duration: ($elapsed | tostring + "s"),
            coverage: $coverage,
            build_url: $build
        },
        tests: $tests
    }')

########################################
# Call Copilot API to generate the report HTML
########################################
PROMPT_CONTENT=$(cat "${PROMPT_FILE}")

USER_PROMPT="${PROMPT_CONTENT}

---

## Test Metrics (from go test -json)

Generate the complete self-contained HTML report with this exact test data embedded:

\`\`\`json
${METRICS}
\`\`\`

Build URL: ${BUILD_URL:-N/A}
Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')

Return ONLY the complete HTML file content inside a single \`\`\`html ... \`\`\` code block."

PAYLOAD=$(jq -n \
    --arg model "${MODEL}" \
    --arg user  "${USER_PROMPT}" \
    '{
        model: $model,
        messages: [
            { role: "user", content: $user }
        ],
        temperature: 0.1,
        max_tokens:  16384
    }')

echo "Calling Copilot API for report generation..." >&2

RESPONSE=$(curl -sf \
    --max-time 120 \
    --header "Authorization: Bearer ${GITHUB_TOKEN:?GITHUB_TOKEN env var required}" \
    --header "Content-Type: application/json" \
    --data   "${PAYLOAD}" \
    "${API_URL}/chat/completions") || {
    echo "Warning: Copilot API call failed; falling back to patching existing report." >&2
    RESPONSE=""
}

########################################
# Extract HTML from response or fall back
########################################
if [[ -n "${RESPONSE}" ]]; then
    HTML=$(echo "${RESPONSE}" | jq -r '.choices[0].message.content // ""' | \
        awk '/^```html/{found=1; next} found && /^```/{found=0; next} found')

    if [[ -n "${HTML}" ]]; then
        printf '%s\n' "${HTML}" > "${OUT_FILE}"
        echo "Report written via Copilot API: ${OUT_FILE}" >&2
        exit 0
    fi
fi

########################################
# Fallback: patch the static test-report.html already in the repo
# by injecting the real metrics JSON into the embedded <script> tag.
########################################
echo "Falling back to patching existing test-report.html..." >&2

EXISTING_REPORT="test-report.html"

if [[ ! -f "${EXISTING_REPORT}" ]]; then
    echo "Error: No existing ${EXISTING_REPORT} and Copilot API unavailable." >&2
    exit 1
fi

# Replace the embedded JSON test-data script block with actual metrics
python3 - <<PYEOF
import re, sys, json

with open("${EXISTING_REPORT}", "r") as f:
    html = f.read()

new_data = json.loads(r"""${METRICS}""")

# Patch summary fields in the embedded JSON block
def patch_json(match):
    try:
        old = json.loads(match.group(1))
        old.update(new_data)
        return match.group(0).replace(match.group(1), json.dumps(old, indent=4))
    except Exception:
        return match.group(0)

patched = re.sub(
    r'<script type="application/json" id="test-data">(.*?)</script>',
    lambda m: '<script type="application/json" id="test-data">' + json.dumps(new_data, indent=4) + '</script>',
    html,
    flags=re.DOTALL
)

with open("${OUT_FILE}", "w") as f:
    f.write(patched)
PYEOF

echo "Report patched from existing template: ${OUT_FILE}" >&2
