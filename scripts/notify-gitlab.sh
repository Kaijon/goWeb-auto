#!/usr/bin/env bash
# notify-gitlab.sh
# Posts the CI result as a comment on the originating GitLab issue and
# optionally closes the issue or applies labels.
#
# Usage:
#   ./notify-gitlab.sh [OPTIONS]
#
# Options:
#   --api-url     URL     Required. GitLab API base URL
#   --token       TOKEN   Required. GitLab private/project access token
#   --project-id  ID      Required. Numeric GitLab project ID
#   --issue-iid   IID     Required. Issue internal ID
#   --results     PATH    Optional. test-results.json (compute pass/fail summary)
#   --report-url  URL     Optional. Link to the published HTML report artifact
#   --build-url   URL     Optional. Jenkins build URL
#   --close       BOOL    Optional. "true" to close issue on success (default: false)
#   --healed      BOOL    Optional. "true" if self-heal succeeded
#   --error       MSG     Optional. Post a plain error message instead of results
#   --label       LABEL   Optional. Apply this label to the issue

set -euo pipefail

########################################
# Argument parsing
########################################
API_URL=""
TOKEN=""
PROJECT_ID=""
ISSUE_IID=""
RESULTS_FILE=""
REPORT_URL=""
BUILD_URL=""
CLOSE_ISSUE="false"
HEALED="false"
ERROR_MSG=""
EXTRA_LABEL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --api-url)     API_URL="$2";      shift 2 ;;
        --token)       TOKEN="$2";        shift 2 ;;
        --project-id)  PROJECT_ID="$2";   shift 2 ;;
        --issue-iid)   ISSUE_IID="$2";    shift 2 ;;
        --results)     RESULTS_FILE="$2"; shift 2 ;;
        --report-url)  REPORT_URL="$2";   shift 2 ;;
        --build-url)   BUILD_URL="$2";    shift 2 ;;
        --close)       CLOSE_ISSUE="$2";  shift 2 ;;
        --healed)      HEALED="$2";       shift 2 ;;
        --error)       ERROR_MSG="$2";    shift 2 ;;
        --label)       EXTRA_LABEL="$2";  shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

for var_name in API_URL TOKEN PROJECT_ID ISSUE_IID; do
    if [[ -z "${!var_name}" ]]; then
        echo "Error: --${var_name//_/-} is required" >&2
        exit 1
    fi
done

if ! [[ "${PROJECT_ID}" =~ ^[0-9]+$ ]] || ! [[ "${ISSUE_IID}" =~ ^[0-9]+$ ]]; then
    echo "Error: project-id and issue-iid must be numeric" >&2
    exit 1
fi
if ! [[ "${API_URL}" =~ ^https:// ]]; then
    echo "Error: API_URL must use HTTPS" >&2
    exit 1
fi

ISSUES_ENDPOINT="${API_URL}/projects/${PROJECT_ID}/issues/${ISSUE_IID}"
NOTES_ENDPOINT="${ISSUES_ENDPOINT}/notes"

########################################
# Helper: post a note (comment) to the issue
########################################
post_comment() {
    local body="${1}"
    local payload
    payload=$(jq -n --arg b "${body}" '{ body: $b }')

    curl -sf \
        --max-time 30 \
        --request POST \
        --header "PRIVATE-TOKEN: ${TOKEN}" \
        --header "Content-Type: application/json" \
        --data   "${payload}" \
        "${NOTES_ENDPOINT}" > /dev/null
}

########################################
# Helper: add a label to the issue
########################################
add_label() {
    local label="${1}"
    local payload
    payload=$(jq -n --arg l "${label}" '{ add_labels: $l }')

    curl -sf \
        --max-time 30 \
        --request PUT \
        --header "PRIVATE-TOKEN: ${TOKEN}" \
        --header "Content-Type: application/json" \
        --data   "${payload}" \
        "${ISSUES_ENDPOINT}" > /dev/null
}

########################################
# Helper: close the issue
########################################
close_issue() {
    curl -sf \
        --max-time 30 \
        --request PUT \
        --header "PRIVATE-TOKEN: ${TOKEN}" \
        --header "Content-Type: application/json" \
        --data   '{"state_event":"close"}' \
        "${ISSUES_ENDPOINT}" > /dev/null
}

########################################
# Error path — post error message and label
########################################
if [[ -n "${ERROR_MSG}" ]]; then
    COMMENT="## ❌ Pipeline Error

\`\`\`
${ERROR_MSG}
\`\`\`

**Jenkins Build:** ${BUILD_URL:-N/A}

_The pipeline encountered an infrastructure error and could not complete. Please check the Jenkins logs._"

    post_comment "${COMMENT}"
    [[ -n "${EXTRA_LABEL}" ]] && add_label "${EXTRA_LABEL}"
    echo "Error comment posted to issue #${ISSUE_IID}" >&2
    exit 0
fi

########################################
# Success path — compose results summary
########################################
PASSED=0
FAILED=0
COVERAGE="N/A"

if [[ -n "${RESULTS_FILE}" && -f "${RESULTS_FILE}" ]]; then
    PASSED=$(grep -c '"Action":"pass"' "${RESULTS_FILE}"  2>/dev/null || echo "0")
    FAILED=$(grep -c '"Action":"fail"' "${RESULTS_FILE}"  2>/dev/null || echo "0")
    COVERAGE=$(grep -oP 'coverage: \K[0-9.]+%' "${RESULTS_FILE}" | tail -1 || echo "N/A")
fi

if (( FAILED > 0 )); then
    STATUS_ICON="⚠️"
    STATUS_TEXT="UNSTABLE — ${FAILED} test(s) still failing after self-heal"
    RESULT_LABEL="ci-unstable"
else
    STATUS_ICON="✅"
    STATUS_TEXT="All tests passed"
    RESULT_LABEL="ci-passed"
fi

HEAL_NOTE=""
if [[ "${HEALED}" == "true" ]]; then
    HEAL_NOTE="
> 🔧 **Self-Heal:** The pipeline automatically detected and fixed failing tests."
fi

REPORT_SECTION=""
if [[ -n "${REPORT_URL}" ]]; then
    REPORT_SECTION="
**📊 Test Report:** [View Interactive Report](${REPORT_URL})"
fi

COMMENT="${STATUS_ICON} ## Self-Healing CI Result

| Metric | Value |
|--------|-------|
| Status | ${STATUS_TEXT} |
| Tests Passed | ${PASSED} |
| Tests Failed | ${FAILED} |
| Coverage | ${COVERAGE} |
| Build | [Jenkins](${BUILD_URL:-#}) |
${REPORT_SECTION}
${HEAL_NOTE}

_Generated by the embedded camera UI self-healing pipeline — $(date -u '+%Y-%m-%dT%H:%M:%SZ')_"

post_comment "${COMMENT}"
echo "Comment posted to issue #${ISSUE_IID}" >&2

########################################
# Apply label based on result
########################################
add_label "${RESULT_LABEL}"
[[ -n "${EXTRA_LABEL}" ]] && add_label "${EXTRA_LABEL}"

########################################
# Close issue if all tests passed and option is set
########################################
if [[ "${CLOSE_ISSUE}" == "true" && "${FAILED}" -eq 0 ]]; then
    close_issue
    echo "Issue #${ISSUE_IID} closed." >&2
fi
