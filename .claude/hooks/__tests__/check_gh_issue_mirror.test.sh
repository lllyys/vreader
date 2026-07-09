#!/usr/bin/env bash
# Bug #361 (GH #1891) — regression test for check_gh_issue_mirror.sh.
#
# The hook's row parser split tracker rows on EVERY `|`, including
# backslash-escaped ones (`\|`), shifting all subsequent cell indices:
# a `\|` in the Summary made status read the Sev/Prio cell and notes read
# the Status cell — wrongly BLOCKING rows that carry a valid `GH: #N`, and
# (worse) silently ALLOWING mirror-required rows without one. A secondary
# runtime break: the block message used `${KIND^}` (bash 4+), a fatal "bad
# substitution" under the hook's actual /bin/bash 3.2 shebang runtime that
# turned every block (exit 2) into a non-blocking error (exit 1).
# Contract after the fix: `\|` is masked before splitting (deps-check.sh
# pattern), and the exit-code contract holds on /bin/bash 3.2 — allow=0,
# block=2 with the full BLOCKED message.
#
# Run: bash .claude/hooks/__tests__/check_gh_issue_mirror.test.sh

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/../check_gh_issue_mirror.sh"
fails=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok()   { echo "ok   — $1"; }
fail() { echo "FAIL — $1"; fails=$((fails+1)); }

# The hook silently exits 0 when jq/python3 are missing — that would turn
# every block-assertion below into a confusing false failure.
command -v jq >/dev/null 2>&1 || { echo "FAIL — jq is required to run this test"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL — python3 is required to run this test"; exit 1; }

# ---- fixture builders -----------------------------------------------------
BUG_ROW_1='| 1 | Existing bug | Hooks | Low | FIXED | GH: #50 |'
FEAT_ROW_1='| 42 | Existing feature | Reader | High | DONE | GH: #900 |'

make_bugs_fixture() {  # $1=name → prints fixture docs dir path
    local dir="$TMP/$1"
    mkdir -p "$dir/docs"
    cat > "$dir/docs/bugs.md" <<EOF
| ID | Summary | Area | Sev | Status | Notes |
|----|---------|------|-----|--------|-------|
$BUG_ROW_1
EOF
    printf '%s' "$dir"
}

make_features_fixture() {  # $1=name → prints fixture docs dir path
    local dir="$TMP/$1"
    mkdir -p "$dir/docs"
    cat > "$dir/docs/features.md" <<EOF
| ID | Summary | Area | Priority | Status | Notes |
|----|---------|------|----------|--------|-------|
$FEAT_ROW_1
EOF
    printf '%s' "$dir"
}

append_row_payload() {  # $1=file_path $2=anchor_row $3=new_row → Edit payload appending a row
    jq -n --arg fp "$1" --arg old "$2" --arg new "$2
$3" '{tool_name: "Edit", tool_input: {file_path: $fp, old_string: $old, new_string: $new}}'
}

run_hook() {  # payload on stdin; stderr → $TMP/stderr.txt
    # /bin/bash pins the production runtime (the hook's shebang → macOS 3.2).
    /bin/bash "$HOOK" 2>"$TMP/stderr.txt"
}

echo "== check_gh_issue_mirror.sh =="

# 1. benign edit (non-tracker file) → exit 0
FX="$(make_bugs_fixture benign)"
jq -n --arg fp "$FX/notes/scratch.txt" \
    '{tool_name: "Edit", tool_input: {file_path: $fp, old_string: "a", new_string: "b"}}' | run_hook
RC=$?
if [ "$RC" -eq 0 ]; then ok "non-tracker edit allowed (exit 0)"; else fail "non-tracker edit rc=$RC"; fi

# 2. POSITIVE (normal row) — new mirror-required bug row without GH → exit 2,
#    full BLOCKED message (incl. the tail after the row list, which died with
#    "bad substitution" under /bin/bash 3.2 pre-fix, exiting 1 instead of 2).
FX="$(make_bugs_fixture block-plain)"
append_row_payload "$FX/docs/bugs.md" "$BUG_ROW_1" '| 8 | Plain bug | Hooks | Low | OPEN | none |' | run_hook
RC=$?
if [ "$RC" -eq 2 ] && grep -q "BLOCKED" "$TMP/stderr.txt" && grep -q "#8" "$TMP/stderr.txt"; then
    ok "unmirrored bug row blocked (exit 2, row named)"
else
    fail "unmirrored bug row not blocked correctly (rc=$RC)"
fi
if grep -q "gh issue create" "$TMP/stderr.txt" && ! grep -qi "bad substitution" "$TMP/stderr.txt"; then
    ok "block message complete on /bin/bash 3.2 (no bad substitution)"
else
    fail "block message truncated/broken under /bin/bash 3.2: $(tail -3 "$TMP/stderr.txt")"
fi

# 3. NEGATIVE (normal row) — new bug row WITH GH → exit 0
FX="$(make_bugs_fixture allow-plain)"
append_row_payload "$FX/docs/bugs.md" "$BUG_ROW_1" '| 9 | Plain ok | Hooks | Low | OPEN | GH: #200 |' | run_hook
RC=$?
if [ "$RC" -eq 0 ]; then ok "GH-referenced bug row allowed (exit 0)"; else fail "GH-referenced bug row blocked (rc=$RC)"; fi

# 4. THE BUG — `\|` in the SUMMARY of a new bug row that HAS `GH: #N`.
#    Pre-fix: status read 'Medium' (Sev cell), notes read 'OPEN' (Status
#    cell) → the GH ref was invisible → wrongly blocked (exit 2).
FX="$(make_bugs_fixture esc-summary)"
append_row_payload "$FX/docs/bugs.md" "$BUG_ROW_1" '| 7 | Split \| pipes | Hooks | Medium | OPEN | GH: #100 |' | run_hook
RC=$?
if [ "$RC" -eq 0 ]; then
    ok "escaped pipe in Summary: GH-referenced bug row allowed (exit 0)"
else
    fail "escaped pipe in Summary shifted Status/Notes — GH ref invisible (rc=$RC)"
fi

# 5. THE BUG (hidden-violation direction) — `\|` in the SUMMARY of a new
#    PLANNED feature row with NO GH. Pre-fix: status read 'High' (Priority
#    cell) → not mirror-required → violation silently allowed (exit 0).
FX="$(make_features_fixture esc-hidden)"
append_row_payload "$FX/docs/features.md" "$FEAT_ROW_1" '| 99 | Esc \| feature | Reader | High | PLANNED | no issue yet |' | run_hook
RC=$?
if [ "$RC" -eq 2 ] && grep -q "#99" "$TMP/stderr.txt"; then
    ok "escaped pipe in Summary no longer hides a mirror violation (#99 blocked)"
else
    fail "mirror violation #99 still hidden by the escaped pipe (rc=$RC)"
fi

# 6. `\|` inside the NOTES cell before the GH ref → GH still visible, exit 0
FX="$(make_bugs_fixture esc-notes)"
append_row_payload "$FX/docs/bugs.md" "$BUG_ROW_1" '| 10 | Notes pipe | Hooks | Low | OPEN | see a\|b GH: #201 |' | run_hook
RC=$?
if [ "$RC" -eq 0 ]; then
    ok "escaped pipe inside Notes: GH ref after it still honored (exit 0)"
else
    fail "escaped pipe inside Notes hid the GH ref (rc=$RC)"
fi

# 7. Mirror-escape hatch still works with `\|` in the Summary (features)
FX="$(make_features_fixture esc-mirror-no)"
append_row_payload "$FX/docs/features.md" "$FEAT_ROW_1" '| 100 | Local \| only | Reader | Low | PLANNED | Mirror: no |' | run_hook
RC=$?
if [ "$RC" -eq 0 ]; then
    ok "Mirror: no escape honored despite escaped pipe in Summary (exit 0)"
else
    fail "Mirror: no escape broken by escaped pipe (rc=$RC)"
fi

# 8. Write payload with an escaped-pipe row (covers the Write branch through
#    the same parser) — GH present → exit 0
FX="$(make_bugs_fixture write-esc)"
NEW_CONTENT="$(cat "$FX/docs/bugs.md")
| 11 | Write \| path | Hooks | Low | OPEN | GH: #202 |"
jq -n --arg fp "$FX/docs/bugs.md" --arg c "$NEW_CONTENT" \
    '{tool_name: "Write", tool_input: {file_path: $fp, content: $c}}' | run_hook
RC=$?
if [ "$RC" -eq 0 ]; then ok "Write payload with escaped pipe + GH allowed (exit 0)"; else fail "Write payload wrongly blocked (rc=$RC)"; fi

echo
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$fails FAILURE(S)"; exit 1; fi
