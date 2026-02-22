#!/usr/bin/env bash
# read-gitlab-issue.sh
# Fetches a GitLab issue and emits a JSON context object consumed by the pipeline.
#
# Usage:
#   ./read-gitlab-issue.sh <API_URL> <TOKEN> <PROJECT_ID> <ISSUE_IID>
#
# Output (stdout, JSON):
#   { "title": "...", "body": "...", "labels": [...], "author": "..." }

set -euo pipefail

API_URL="${1:?GitLab API URL required}"
TOKEN="${2:?GitLab token required}"
PROJECT_ID="${3:?Project ID required}"
ISSUE_IID="${4:?Issue IID required}"

########################################
# Validate inputs — avoid injection via URL parameters
########################################
if ! [[ "${PROJECT_ID}" =~ ^[0-9]+$ ]]; then
    echo '{"error":"Invalid PROJECT_ID — must be numeric"}' >&2
    exit 1
fi
if ! [[ "${ISSUE_IID}" =~ ^[0-9]+$ ]]; then
    echo '{"error":"Invalid ISSUE_IID — must be numeric"}' >&2
    exit 1
fi
# Ensure API_URL is HTTPS
if ! [[ "${API_URL}" =~ ^https:// ]]; then
    echo '{"error":"GITLAB_API_URL must use HTTPS"}' >&2
    exit 1
fi

########################################
# Fetch issue from GitLab REST API
########################################
ENDPOINT="${API_URL}/projects/${PROJECT_ID}/issues/${ISSUE_IID}"

RESPONSE=$(curl -sf \
    --max-time 30 \
    --header "PRIVATE-TOKEN: ${TOKEN}" \
    "${ENDPOINT}") || {
    echo '{"error":"Failed to reach GitLab API"}' >&2
    exit 1
}

########################################
# Parse and sanitize — use jq for safe JSON handling (never eval)
########################################
TITLE=$(echo "${RESPONSE}" | jq -r '.title // ""')
BODY=$(echo "${RESPONSE}"  | jq -r '.description // ""')
AUTHOR=$(echo "${RESPONSE}" | jq -r '.author.username // "unknown"')
STATE=$(echo "${RESPONSE}"  | jq -r '.state // "opened"')

# Labels as JSON array
LABELS=$(echo "${RESPONSE}" | jq -c '[.labels[]? | tostring]')

# Emit normalized context JSON
jq -n \
    --arg title  "${TITLE}" \
    --arg body   "${BODY}" \
    --arg author "${AUTHOR}" \
    --arg state  "${STATE}" \
    --argjson labels "${LABELS}" \
    '{
        title:  $title,
        body:   $body,
        author: $author,
        state:  $state,
        labels: $labels
    }'
