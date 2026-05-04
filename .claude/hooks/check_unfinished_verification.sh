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

# --- Mirror debt scan (mechanical-mirror rule, AGENTS.md) ---
# Both trackers: surface mirror-required rows that lack GH cross-refs.
# Scoped to actionable debt per Codex's design recommendation:
#   features: PLANNED / IN PROGRESS / DONE / VERIFIED without GH:#N
#   bugs:     anything not in {DUPLICATE, WONT FIX, WONT DO, DEFERRED}
#             without GH:#N AND without "Mirror: no" escape.

if command -v python3 >/dev/null 2>&1; then
    BUGS_FILE="$PROJECT_DIR/docs/bugs.md"
    FEATURES_FILE="$PROJECT_DIR/docs/features.md"
    MIRROR_DEBT="$(BUGS="$BUGS_FILE" FEATURES="$FEATURES_FILE" python3 <<'PYEOF'
import os, re

GH_RE = re.compile(r"GH:\s*#?\d+")
MIRROR_NO_FEATURE = re.compile(r"Mirror:\s*no", re.IGNORECASE)
MIRROR_NO_BUG = re.compile(r"Mirror:\s*no\s*[—-]\s*local-only", re.IGNORECASE)
ID_RE = re.compile(r"^\| *(\d+) *\|")

def scan(path, kind):
    if not os.path.exists(path):
        return []
    out = []
    with open(path) as f:
        for line in f:
            m = ID_RE.match(line)
            if not m:
                continue
            rid = m.group(1)
            cells = [c.strip() for c in line.split("|")]
            if len(cells) < 7:
                continue
            status = cells[5]
            notes = cells[6]
            if kind == "feature":
                if status not in {"PLANNED", "IN PROGRESS", "DONE", "VERIFIED"}:
                    continue
            else:
                if status in {"DUPLICATE", "WONT FIX", "WONT DO", "DEFERRED", ""}:
                    continue
            if GH_RE.search(notes):
                continue
            if kind == "feature" and MIRROR_NO_FEATURE.search(notes):
                continue
            if kind == "bug" and MIRROR_NO_BUG.search(notes):
                continue
            out.append(rid)
    return out

bug_debt = scan(os.environ["BUGS"], "bug")
feature_debt = scan(os.environ["FEATURES"], "feature")
parts = []
if bug_debt:
    head = ", ".join(f"#{r}" for r in bug_debt[:8])
    extra = "" if len(bug_debt) <= 8 else f" (+{len(bug_debt) - 8} more)"
    parts.append(f"BUG-DEBT|{len(bug_debt)}|{head}{extra}")
if feature_debt:
    head = ", ".join(f"#{r}" for r in feature_debt[:8])
    extra = "" if len(feature_debt) <= 8 else f" (+{len(feature_debt) - 8} more)"
    parts.append(f"FEATURE-DEBT|{len(feature_debt)}|{head}{extra}")
if parts:
    print("\n".join(parts))
PYEOF
    )"

    if [[ -n "$MIRROR_DEBT" ]]; then
        echo "[mirror-debt-hook] Unmirrored tracker rows (per AGENTS.md mechanical-mirror rule):" >&2
        echo "$MIRROR_DEBT" | while IFS='|' read -r kind count ids; do
            label="${kind/-DEBT/}"
            echo "  ${label} rows lacking GH:#N: ${count} — ${ids}" >&2
        done
        echo "" >&2
        echo "Open a GH issue per row (or use \`/file-bug\` / \`/file-feature\` slash commands)" >&2
        echo "and add \`GH: #N\` to the Notes column. \`Mirror: no\` (features) and" >&2
        echo "\`Mirror: no — local-only\` (bugs only, terminal status) bypass." >&2
    fi
fi

exit 0
