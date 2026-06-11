#!/bin/bash
# PreToolUse hook for Edit / Write / MultiEdit tools.
#
# Purpose: blocks any tracker edit (docs/features.md, docs/bugs.md)
# that adds OR materially edits a mirror-required row that lacks a
# `GH: #N` cross-reference in its Notes column. Implements the
# mechanical-mirror rule from AGENTS.md (every PLANNED+ feature, every
# non-exempt bug → GH issue).
#
# Mirror-required state:
#   features: PLANNED, IN PROGRESS, DONE, VERIFIED
#   bugs:     anything not in {DUPLICATE, WONT FIX, WONT DO, DEFERRED}
#
# Escape hatches:
#   features: `Mirror: no` anywhere in the Notes column
#   bugs:     `Mirror: no — local-only` anywhere in Notes — narrower
#             phrasing required so a copy-paste from features rule
#             can't bypass; only valid with terminal non-actionable
#             status. The hook here just checks the literal phrase;
#             the policy guard is the AGENTS.md rule.
#
# Reads PreToolUse JSON from stdin. Exits 0 to allow, 2 to block.

set -euo pipefail

INPUT="$(cat)"

if ! command -v jq >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
    exit 0
fi

TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // ""')"
case "$TOOL_NAME" in
    Edit|Write|MultiEdit) ;;
    *) exit 0 ;;
esac

FILE_PATH="$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')"

KIND=""
case "$FILE_PATH" in
    */docs/features.md) KIND="feature" ;;
    */docs/bugs.md) KIND="bug" ;;
    *) exit 0 ;;
esac

# Compute post-edit content via python (handles multi-line cleanly).
new_content() {
    case "$TOOL_NAME" in
        Write)
            echo "$INPUT" | jq -r '.tool_input.content // ""'
            ;;
        Edit)
            # INPUT goes via stdin, not env/argv — env vars count against
            # ARG_MAX (E2BIG: "Argument list too long" once bugs.md grew >1MB).
            printf '%s' "$INPUT" | HOOK_FILE="$FILE_PATH" python3 -c '
import json, os, sys
data = json.load(sys.stdin)
old = data["tool_input"].get("old_string", "")
new = data["tool_input"].get("new_string", "")
try:
    with open(os.environ["HOOK_FILE"]) as f:
        content = f.read()
except FileNotFoundError:
    content = ""
idx = content.find(old)
if idx < 0:
    sys.stdout.write(content)
else:
    sys.stdout.write(content[:idx] + new + content[idx + len(old):])
'
            ;;
        MultiEdit)
            # stdin, not env — see the Edit branch (ARG_MAX / E2BIG).
            printf '%s' "$INPUT" | HOOK_FILE="$FILE_PATH" python3 -c '
import json, os, sys
data = json.load(sys.stdin)
edits = data["tool_input"].get("edits", [])
try:
    with open(os.environ["HOOK_FILE"]) as f:
        content = f.read()
except FileNotFoundError:
    content = ""
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

# Parse rows out of NEW + OLD, then identify mirror-required rows in
# NEW that either (a) didn't exist in OLD, or (b) had different
# status/notes than OLD. For each such row, require `GH: #N` (or the
# kind-appropriate Mirror escape) in the Notes column.
MISSING_FILE="$(mktemp)"
OLD_FILE="$(mktemp)"
NEW_FILE="$(mktemp)"
trap 'rm -f "$MISSING_FILE" "$OLD_FILE" "$NEW_FILE"' EXIT
# Contents go via temp FILES, paths via env — passing the full tracker
# text as env vars exceeded ARG_MAX once docs/bugs.md grew past ~1MB
# ("python3: Argument list too long", E2BIG; env + argv share the limit).
# printf is a bash builtin: no exec, no ARG_MAX exposure.
printf '%s' "$OLD" > "$OLD_FILE"
printf '%s' "$NEW" > "$NEW_FILE"
KIND="$KIND" NEW_PATH="$NEW_FILE" OLD_PATH="$OLD_FILE" python3 - >"$MISSING_FILE" <<'PYEOF'
import os, re, sys

KIND = os.environ["KIND"]

# Mirror-required statuses per AGENTS.md.
if KIND == "feature":
    MIRROR_STATUSES = {"PLANNED", "IN PROGRESS", "DONE", "VERIFIED"}
else:  # bug
    EXEMPT_STATUSES = {"DUPLICATE", "WONT FIX", "WONT DO", "DEFERRED"}
    MIRROR_STATUSES = None  # any status NOT in EXEMPT

ID_RE = re.compile(r"^\| *(\d+) *\|")
GH_RE = re.compile(r"GH:\s*#?\d+")
MIRROR_NO_FEATURE = re.compile(r"Mirror:\s*no", re.IGNORECASE)
MIRROR_NO_BUG = re.compile(r"Mirror:\s*no\s*[—-]\s*local-only", re.IGNORECASE)

def parse_rows(content):
    rows = {}
    for line in content.splitlines():
        m = ID_RE.match(line)
        if not m:
            continue
        rid = m.group(1)
        cells = [c.strip() for c in line.split("|")]
        # Cells: ['', id, title, area, priority, status, notes, '']
        if len(cells) < 7:
            continue
        status = cells[5] if len(cells) > 5 else ""
        notes = cells[6] if len(cells) > 6 else ""
        rows[rid] = (status, notes)
    return rows

def needs_mirror(status):
    if KIND == "feature":
        return status in MIRROR_STATUSES
    else:
        return status not in EXEMPT_STATUSES

def has_gh_or_exempt(notes):
    if GH_RE.search(notes):
        return True
    if KIND == "feature" and MIRROR_NO_FEATURE.search(notes):
        return True
    if KIND == "bug" and MIRROR_NO_BUG.search(notes):
        return True
    return False

with open(os.environ["NEW_PATH"]) as f:
    new_rows = parse_rows(f.read())
with open(os.environ["OLD_PATH"]) as f:
    old_rows = parse_rows(f.read())

missing = []
for rid, (status, notes) in new_rows.items():
    if not needs_mirror(status):
        continue
    if has_gh_or_exempt(notes):
        continue
    # Material change check: row added (not in OLD), or status/notes
    # changed vs OLD. Bare presence in OLD with identical fields
    # bypasses (no edit-touch, no enforcement).
    old = old_rows.get(rid)
    if old is None:
        # New row, mirror-required, no GH → block.
        missing.append(rid)
    elif old != (status, notes):
        # Existing row touched (status or notes changed). Either way,
        # if it's now mirror-required without GH, block. This is the
        # "retroactive gap" case Codex called out.
        missing.append(rid)

if missing:
    print(",".join(missing))
PYEOF

MISSING="$(cat "$MISSING_FILE")"

if [[ -z "$MISSING" ]]; then
    exit 0
fi

cat >&2 <<EOF
[gh-issue-mirror-hook] BLOCKED.

The edit you're about to write touches mirror-required ${KIND} row(s) that lack
a \`GH: #N\` cross-reference in their Notes column:

EOF
for rid in $(echo "$MISSING" | tr ',' ' '); do
    echo "  - ${KIND} #${rid}" >&2
done
cat >&2 <<EOF

Per AGENTS.md "GitHub Issues — mechanical mirror" rule: every
mirror-required tracker row needs a paired GH issue. Two ways to
proceed:

  1. Run \`gh issue create --title "${KIND^} #N: <summary>" --label "${KIND}" \\
       --body "..."\` then add \`GH: #<issue>\` to the Notes column.
     Easiest path: use the slash command \`/file-${KIND}\` if available.
  2. (Features only) Add \`Mirror: no\` to Notes if the row is
     intentionally local-only.
  3. (Bugs only, narrow) Add \`Mirror: no — local-only\` to Notes —
     valid only with terminal non-actionable status, never \`TODO\`.
EOF
exit 2
