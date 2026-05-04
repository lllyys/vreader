#!/bin/bash
# Stop hook (or SessionEnd) — surfaces unfinished verification debt
# at session end. Reads PreCompact / Stop / SessionEnd JSON from
# stdin per Claude Code's hook spec. The hook DOES NOT block (exit 0
# always); it prints a warning to stderr that the agent will see in
# its transcript so future sessions can pick up the debt.
#
# What "unfinished verification debt" means:
#   - A feature row in docs/features.md is at status DONE, AND
#   - There is NO matching dev-docs/verification/feature-<id>-*.md
#     file, AND
#   - The DONE row's notes column doesn't say "awaiting VERIFIED" or
#     similar marker that indicates the gap is acknowledged.
#
# Conservative: surface a warning even if technically not actionable
# this session. The agent / next session decides whether to flip to
# VERIFIED, run the evidence pass, or update the row notes to
# acknowledge the gap.

set -euo pipefail

# Don't block startup if jq is missing.
if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

# Project root is wherever the hook is invoked from. Claude Code
# sets CLAUDE_PROJECT_DIR for hooks.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
FEATURES="$PROJECT_DIR/docs/features.md"
EVIDENCE_DIR="$PROJECT_DIR/dev-docs/verification"

if [[ ! -f "$FEATURES" ]]; then exit 0; fi

# Find every feature row whose status is exactly DONE. Cheap awk pass.
DONE_IDS="$(awk '
    /^\| *[0-9]+ *\|/ {
        n = split($0, cells, "|")
        id = cells[2]; gsub(/^ *| *$/, "", id)
        notes = cells[n - 1]; gsub(/^ *| *$/, "", notes)
        for (i = 1; i <= n; i++) {
            cell = cells[i]; gsub(/^ *| *$/, "", cell)
            if (cell == "DONE") {
                # Skip if the row already explicitly acknowledges
                # the gap. Lowercase the notes for matching since
                # BSD awk does not support the /i regex flag.
                lower = tolower(notes)
                if (lower ~ /awaiting *verified/) { next }
                if (lower ~ /verification *deferred/) { next }
                print id
                next
            }
        }
    }
' "$FEATURES")"

if [[ -z "$DONE_IDS" ]]; then exit 0; fi

UNVERIFIED=""
for id in $DONE_IDS; do
    if ! ls "$EVIDENCE_DIR/feature-${id}-"*.md >/dev/null 2>&1; then
        UNVERIFIED="$UNVERIFIED #$id"
    fi
done

if [[ -n "$UNVERIFIED" ]]; then
    cat >&2 <<EOF
[verification-debt-hook] Unfinished verification debt:

The following feature rows are at status DONE but have no
verification evidence file in dev-docs/verification/ and don't say
"awaiting VERIFIED" in their notes column:

  Features:${UNVERIFIED}

Per .claude/rules/47-feature-workflow.md Gate 5, behavioral
features need on-device / integration verification before they
can move to VERIFIED. Either:

  1. Run the verification, write evidence file(s), flip to VERIFIED.
  2. Update the row notes to "DONE awaiting VERIFIED — <reason>"
     to acknowledge the gap (a follow-up evidence pass is still
     required to close the GH issue).

Note: this is a warning, not a block. The session may still end.
EOF
fi

exit 0
