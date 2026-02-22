#!/usr/bin/env bash
# copilot-generate.sh
# Calls the GitHub Copilot / GitHub Models chat completions API to generate source
# code from a .prompt.md skill file plus contextual inputs.
#
# The strategy mirrors VS Code agent skills:
#   System prompt  = copilot-instructions.md + bitrate-policy spec
#   User prompt    = .prompt.md content + issue body + (optional) heal context
#
# The response is expected to contain one or more fenced code blocks.
# Each block is extracted and written to the appropriate output file.
#
# Usage:
#   ./copilot-generate.sh [OPTIONS]
#
# Options:
#   --prompt     PATH    Required. Skill prompt file (.prompt.md)
#   --system     PATH    Required. copilot-instructions.md
#   --spec       PATH    Required. bitrate-policy.md (appended to system prompt)
#   --context    PATH    Required. issue-context.json from read-gitlab-issue.sh
#   --out-file   PATH    Required. Primary output file path
#   --secondary  PATH    Optional. Second output file (for test generation)
#   --heal-file  PATH    Optional. JSON with failure context (self-heal mode)
#   --api-url    URL     Required. Copilot/Models API base URL
#   --model      NAME    Optional. Model name (default: gpt-4o)
#   --heal-mode          Flag. Appends failures section to user prompt

set -euo pipefail

########################################
# Argument parsing
########################################
PROMPT_FILE=""
SYSTEM_FILE=""
SPEC_FILE=""
CONTEXT_FILE=""
OUT_FILE=""
SECONDARY_FILE=""
HEAL_FILE=""
API_URL=""
MODEL="gpt-4o"
HEAL_MODE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prompt)     PROMPT_FILE="$2";    shift 2 ;;
        --system)     SYSTEM_FILE="$2";    shift 2 ;;
        --spec)       SPEC_FILE="$2";      shift 2 ;;
        --context)    CONTEXT_FILE="$2";   shift 2 ;;
        --out-file)   OUT_FILE="$2";       shift 2 ;;
        --secondary)  SECONDARY_FILE="$2"; shift 2 ;;
        --heal-file)  HEAL_FILE="$2";      shift 2 ;;
        --api-url)    API_URL="$2";        shift 2 ;;
        --model)      MODEL="$2";          shift 2 ;;
        --heal-mode)  HEAL_MODE=true;      shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# Validate required args
for var_name in PROMPT_FILE SYSTEM_FILE SPEC_FILE CONTEXT_FILE OUT_FILE API_URL; do
    if [[ -z "${!var_name}" ]]; then
        echo "Error: --${var_name//_/-} is required" >&2
        exit 1
    fi
done

# Ensure API URL is HTTPS
if ! [[ "${API_URL}" =~ ^https:// ]]; then
    echo "Error: API_URL must use HTTPS" >&2
    exit 1
fi

########################################
# Build system prompt
########################################
SYSTEM_CONTENT=$(cat "${SYSTEM_FILE}")
SPEC_CONTENT=$(cat "${SPEC_FILE}")

SYSTEM_PROMPT="${SYSTEM_CONTENT}

---

## Hardware Specification (bitrate-policy.md)

${SPEC_CONTENT}"

########################################
# Build user prompt
########################################
# Strip YAML frontmatter from .prompt.md (between first two --- lines)
PROMPT_CONTENT=$(awk '/^---/{found++; if(found==2){print_it=1; next}} print_it' "${PROMPT_FILE}")
# Fallback if awk strips everything (no frontmatter)
if [[ -z "${PROMPT_CONTENT}" ]]; then
    PROMPT_CONTENT=$(cat "${PROMPT_FILE}")
fi

# Append issue context
ISSUE_TITLE=$(jq -r '.title // ""' "${CONTEXT_FILE}")
ISSUE_BODY=$(jq -r '.body  // ""' "${CONTEXT_FILE}")

USER_PROMPT="${PROMPT_CONTENT}

---

## GitLab Issue Context

**Title:** ${ISSUE_TITLE}

**Requirements from Issue:**
${ISSUE_BODY}"

# Append existing source file for context (update mode)
if [[ -f "${OUT_FILE}" ]]; then
    EXISTING=$(cat "${OUT_FILE}")
    USER_PROMPT="${USER_PROMPT}

---

## Existing File (${OUT_FILE}) — Modify as needed

\`\`\`
${EXISTING}
\`\`\`"
fi

# Append failure context when in self-heal mode
if [[ "${HEAL_MODE}" == "true" && -n "${HEAL_FILE}" && -f "${HEAL_FILE}" ]]; then
    FAILURES=$(jq -r '.failures[]? | "- \(.test): \(.output)"' "${HEAL_FILE}" 2>/dev/null || echo "See heal file.")
    USER_PROMPT="${USER_PROMPT}

---

## Self-Heal: Failing Tests to Fix

The following tests are currently failing. Analyse each failure and fix the generated
code so that all tests pass while staying within the hardware constraints:

${FAILURES}"
fi

# Append secondary file for context (e.g. existing test file)
if [[ -n "${SECONDARY_FILE}" && -f "${SECONDARY_FILE}" ]]; then
    SEC_EXISTING=$(cat "${SECONDARY_FILE}")
    USER_PROMPT="${USER_PROMPT}

---

## Existing File (${SECONDARY_FILE}) — Modify as needed

\`\`\`
${SEC_EXISTING}
\`\`\`"
fi

########################################
# Assemble JSON payload safely with jq
########################################
PAYLOAD=$(jq -n \
    --arg model  "${MODEL}" \
    --arg sys    "${SYSTEM_PROMPT}" \
    --arg user   "${USER_PROMPT}" \
    '{
        model: $model,
        messages: [
            { role: "system", content: $sys  },
            { role: "user",   content: $user }
        ],
        temperature: 0.2,
        max_tokens:  8192
    }')

########################################
# Call the API
########################################
CHAT_ENDPOINT="${API_URL}/chat/completions"

echo "Calling Copilot API: ${CHAT_ENDPOINT} (model: ${MODEL})" >&2

RESPONSE=$(curl -sf \
    --max-time 120 \
    --header  "Authorization: Bearer ${GITHUB_TOKEN:?GITHUB_TOKEN env var required}" \
    --header  "Content-Type: application/json" \
    --data    "${PAYLOAD}" \
    "${CHAT_ENDPOINT}") || {
    echo "Error: Copilot API call failed" >&2
    exit 1
}

########################################
# Extract generated code from response
# Copilot returns one assistant message containing markdown fenced code blocks.
# We extract blocks and write them to the target files.
########################################
RAW_CONTENT=$(echo "${RESPONSE}" | jq -r '.choices[0].message.content // ""')

if [[ -z "${RAW_CONTENT}" ]]; then
    echo "Error: Empty response from Copilot API" >&2
    echo "${RESPONSE}" >&2
    exit 1
fi

# Helper: extract first code block matching optional language tag
extract_block() {
    local lang_pattern="${1:-}"
    if [[ -n "${lang_pattern}" ]]; then
        echo "${RAW_CONTENT}" | awk "/^\`\`\`${lang_pattern}/{found=1; next} found && /^\`\`\`/{found=0; next} found"
    else
        # First code block regardless of language
        echo "${RAW_CONTENT}" | awk '/^```/{found++; if(found==1){next} if(found==2){exit}} found==1'
    fi
}

# Determine file language from extension
EXT="${OUT_FILE##*.}"
case "${EXT}" in
    vue)  LANG="vue" ;;
    go)   LANG="go"  ;;
    ts)   LANG="typescript|ts" ;;
    html) LANG="html" ;;
    *)    LANG="" ;;
esac

PRIMARY_CODE=$(extract_block "${LANG}")

if [[ -z "${PRIMARY_CODE}" ]]; then
    echo "Warning: No ${LANG} code block found; using full response as code." >&2
    PRIMARY_CODE="${RAW_CONTENT}"
fi

# Write primary output file — create parent dirs if needed
mkdir -p "$(dirname "${OUT_FILE}")"
printf '%s\n' "${PRIMARY_CODE}" > "${OUT_FILE}"
echo "Written: ${OUT_FILE}" >&2

# Extract and write secondary output file if requested (e.g. integration_test.go)
if [[ -n "${SECONDARY_FILE}" ]]; then
    # Try to find a second go block in the response
    SECONDARY_CODE=$(echo "${RAW_CONTENT}" | awk 'BEGIN{found=0; block=0} /^```go/{block++; if(block==2){found=1; next}} found && /^```/{found=0; next} found')
    if [[ -n "${SECONDARY_CODE}" ]]; then
        mkdir -p "$(dirname "${SECONDARY_FILE}")"
        printf '%s\n' "${SECONDARY_CODE}" > "${SECONDARY_FILE}"
        echo "Written: ${SECONDARY_FILE}" >&2
    else
        echo "Info: No secondary code block found; ${SECONDARY_FILE} not updated." >&2
    fi
fi
