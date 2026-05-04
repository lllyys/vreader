#!/bin/bash
# PreToolUse hook for Edit / Write / MultiEdit tools.
#
# Purpose: blocks any tracker edit (docs/features.md, docs/bugs.md)
# that flips a row's status column to VERIFIED (features) or FIXED
# (bugs) without a corresponding evidence file in
# dev-docs/verification/. See dev-docs/verification/SCHEMA.md for
# the required shape.
#
# Reads PreToolUse JSON from stdin per Claude Code's hook spec:
#   { tool_name, tool_input: { file_path, old_string, new_string,
#                              edits: [...] } , ... }
#
# Exits 0 to allow the edit, exits 2 with a message on stderr to
# block. The agent reads stderr and surfaces it.

set -euo pipefail

# Read all of stdin so we don't deadlock if Claude Code closes early.
INPUT="$(cat)"

# Helpers — extract fields with jq. Bail with allow if jq isn't
# available (don't break the agent for a missing tool).
if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // ""')"
case "$TOOL_NAME" in
    Edit|Write|MultiEdit) ;;
    *) exit 0 ;;
esac

FILE_PATH="$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')"

# Only guard the two trackers.
case "$FILE_PATH" in
    */docs/features.md|*/docs/bugs.md) ;;
    *) exit 0 ;;
esac

# Determine the new content the agent wants to write. For Write,
# it's tool_input.content. For Edit, it's the full file with
# old_string replaced. For MultiEdit, apply each edit in turn.
new_content() {
    case "$TOOL_NAME" in
        Write)
            echo "$INPUT" | jq -r '.tool_input.content // ""'
            ;;
        Edit)
            # python is more reliable than awk -v for multi-line
            # old/new strings (embedded newlines break -v parsing).
            if [[ ! -f "$FILE_PATH" ]]; then return; fi
            HOOK_INPUT="$INPUT" HOOK_FILE="$FILE_PATH" python3 -c '
import json, os, sys
data = json.loads(os.environ["HOOK_INPUT"])
old = data["tool_input"].get("old_string", "")
new = data["tool_input"].get("new_string", "")
with open(os.environ["HOOK_FILE"]) as f:
    content = f.read()
idx = content.find(old)
if idx < 0:
    sys.stdout.write(content)
else:
    sys.stdout.write(content[:idx] + new + content[idx + len(old):])
'
            ;;
        MultiEdit)
            if [[ ! -f "$FILE_PATH" ]]; then return; fi
            HOOK_INPUT="$INPUT" HOOK_FILE="$FILE_PATH" python3 -c '
import json, os, sys
data = json.loads(os.environ["HOOK_INPUT"])
edits = data["tool_input"].get("edits", [])
with open(os.environ["HOOK_FILE"]) as f:
    content = f.read()
for e in edits:
    old = e.get("old_string", "")
    new = e.get("new_string", "")
    idx = content.find(old)
    if idx >= 0:
        content = content[:idx] + new + content[idx + len(old):]
sys.stdout.write(content)
'
            ;;
    esac
}

OLD="$(cat "$FILE_PATH" 2>/dev/null || echo "")"
NEW="$(new_content)"

# Decide which terminal column to enforce based on the tracker.
# Per AGENTS.md, bug FIXED is the merge gate (passing tests = enough);
# only feature VERIFIED requires device-evidence. So we only enforce
# the features tracker here. Bug FIXED is a separate, lighter bar.
TERMINAL_RE=""
KIND=""
case "$FILE_PATH" in
    */docs/features.md)
        TERMINAL_RE="VERIFIED"
        KIND="feature"
        ;;
    */docs/bugs.md)
        # FIXED is the merge gate, not a verification gate; let it
        # through. The verified-against-real-environment requirement
        # for closing the GH issue is enforced at the issue-close
        # step, not at the bug-row flip.
        exit 0
        ;;
esac

# Find rows in NEW whose status column is the terminal value but
# whose corresponding row in OLD was NOT. Only those count as
# "transitions" we need evidence for.
#
# Tracker rows look like:
#   | <id> | <description> | <area> | <priority> | <STATUS> | <notes> |
# The id is the first cell after the leading "|".
#
# Algorithm: scan NEW for rows with the terminal status. For each,
# look up the same id in OLD; if OLD's status was not the terminal,
# require an evidence file.

# Newline-separated list of "id:status" tuples for terminal rows.
extract_terminal_ids() {
    local content="$1"
    printf '%s\n' "$content" | awk -v term="$TERMINAL_RE" '
        /^\| *[0-9]+ *\|/ {
            n = split($0, cells, "|")
            id = cells[2]; gsub(/^ *| *$/, "", id)
            for (i = 1; i <= n; i++) {
                cell = cells[i]; gsub(/^ *| *$/, "", cell)
                if (cell == term) { print id; next }
            }
        }
    '
}

# Newline-separated list of ALL ids that appear in OLD (to detect
# whether a terminal row in NEW is actually a transition vs.
# already-terminal in OLD).
extract_terminal_ids_old() {
    local content="$1"
    printf '%s\n' "$content" | awk -v term="$TERMINAL_RE" '
        /^\| *[0-9]+ *\|/ {
            n = split($0, cells, "|")
            id = cells[2]; gsub(/^ *| *$/, "", id)
            for (i = 1; i <= n; i++) {
                cell = cells[i]; gsub(/^ *| *$/, "", cell)
                if (cell == term) { print id; next }
            }
        }
    '
}

# Compute new transitions = terminal in NEW − terminal in OLD.
NEW_TERMINAL_IDS="$(extract_terminal_ids "$NEW" | sort -u)"
OLD_TERMINAL_IDS="$(extract_terminal_ids_old "$OLD" | sort -u)"
TRANSITIONS="$(comm -23 <(echo "$NEW_TERMINAL_IDS") <(echo "$OLD_TERMINAL_IDS"))"

if [[ -z "$TRANSITIONS" ]]; then
    exit 0
fi

# For each transition, require a verification evidence file.
# FILE_PATH is .../docs/features.md or .../docs/bugs.md → project
# root is the parent of the docs/ dir.
PROJECT_DIR="$(dirname "$(dirname "$FILE_PATH")")"
EVIDENCE_DIR="$PROJECT_DIR/dev-docs/verification"
MISSING=""

for id in $TRANSITIONS; do
    # Match feature-<id>-*.md or bug-<id>-*.md.
    if ! ls "$EVIDENCE_DIR/${KIND}-${id}-"*.md >/dev/null 2>&1; then
        MISSING="$MISSING $KIND #$id"
    fi
done

if [[ -n "$MISSING" ]]; then
    cat >&2 <<EOF
[verification-evidence-hook] BLOCKED.

The edit you're about to write flips${MISSING} to ${TERMINAL_RE}, but
no matching verification evidence file exists in
\`dev-docs/verification/\`.

Expected file(s):
EOF
    for id in $TRANSITIONS; do
        if ! ls "$EVIDENCE_DIR/${KIND}-${id}-"*.md >/dev/null 2>&1; then
            echo "  - dev-docs/verification/${KIND}-${id}-$(date +%Y%m%d).md" >&2
        fi
    done
    cat >&2 <<EOF

Run the verification per .claude/rules/47-feature-workflow.md Gate 5,
write the evidence file (schema: dev-docs/verification/SCHEMA.md),
then retry the edit.

To bypass for legitimate reasons (rare), submit your next prompt
prefixed with: verify-skip:<id>:<reason>
EOF
    exit 2
fi

exit 0
