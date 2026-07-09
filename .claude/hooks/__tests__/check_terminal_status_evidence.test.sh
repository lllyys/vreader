#!/usr/bin/env bash
# Bug #360 (GH #1890) — regression test for check_terminal_status_evidence.sh.
#
# The hook's block message advertised a `verify-skip:<id>:<reason>` prompt-prefix
# bypass that NO code anywhere implements — a phantom bypass. Contract after the
# fix: nothing under .claude/hooks/ or scripts/ mentions the prefix (this test
# file is the one legitimate exception — it names the string to assert its
# absence), and the hook's real behavior is preserved: allow benign edits, block
# unevidenced VERIFIED flips, allow evidenced ones, let bugs.md FIXED through.
#
# Run: bash .claude/hooks/__tests__/check_terminal_status_evidence.test.sh

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/../check_terminal_status_evidence.sh"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
fails=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok()   { echo "ok   — $1"; }
fail() { echo "FAIL — $1"; fails=$((fails+1)); }

# The hook itself silently allows everything when jq is missing; a missing jq
# here would turn every block-assertion into a confusing false failure.
command -v jq >/dev/null 2>&1 || { echo "FAIL — jq is required to run this test"; exit 1; }

# ---- fixture builder: a minimal repo with a features tracker -------------
# The hook derives the project root from the edited file's path
# (dirname(dirname(FILE_PATH))), so each fixture is self-contained.
make_fixture() {
    local dir="$TMP/$1"
    mkdir -p "$dir/docs"
    cat > "$dir/docs/features.md" <<'EOF'
| ID | Description | Area | Priority | Status | Notes |
|----|-------------|------|----------|--------|-------|
| 42 | Sample feature | Reader | High | DONE | GH: #900 |
| 43 | Other feature | Library | Low | VERIFIED | GH: #901 |
EOF
    echo "$dir"
}

edit_payload() {  # $1=file_path $2=old_string $3=new_string
    jq -n --arg fp "$1" --arg old "$2" --arg new "$3" \
        '{tool_name: "Edit", tool_input: {file_path: $fp, old_string: $old, new_string: $new}}'
}

run_hook() {  # $1=fixture dir; payload on stdin; stderr → $TMP/stderr.txt
    CLAUDE_PROJECT_DIR="$1" bash "$HOOK" 2>"$TMP/stderr.txt"
}

echo "== check_terminal_status_evidence.sh =="

# 1. THE BUG — no production hook/script advertises or references the phantom
#    verify-skip bypass. Only this test file may name the string.
MATCHES="$(grep -rn "verify-skip" "$REPO_ROOT/.claude/hooks" "$REPO_ROOT/scripts" 2>/dev/null \
    | grep -v "/__tests__/check_terminal_status_evidence.test.sh:" || true)"
if [ -z "$MATCHES" ]; then
    ok "no verify-skip reference in .claude/hooks/ or scripts/ (phantom bypass gone)"
else
    fail "phantom verify-skip reference still present: $MATCHES"
fi

# 2. benign edit (non-tracker file) → exit 0
FX="$(make_fixture benign)"
edit_payload "$FX/notes/scratch.txt" "foo" "bar" | run_hook "$FX"
RC=$?
if [ "$RC" -eq 0 ]; then ok "benign non-tracker edit allowed (exit 0)"; else fail "benign edit blocked (rc=$RC)"; fi

# 3. features.md flip DONE → VERIFIED with NO evidence file → exit 2 + BLOCKED
FX="$(make_fixture block)"
edit_payload "$FX/docs/features.md" "| 42 | Sample feature | Reader | High | DONE |" \
    "| 42 | Sample feature | Reader | High | VERIFIED |" | run_hook "$FX"
RC=$?
if [ "$RC" -eq 2 ] && grep -q "BLOCKED" "$TMP/stderr.txt"; then
    ok "unevidenced VERIFIED flip blocked (exit 2)"
else
    fail "unevidenced VERIFIED flip not blocked (rc=$RC)"
fi

# 4. the block message itself must not advertise the phantom bypass
if ! grep -q "verify-skip" "$TMP/stderr.txt"; then
    ok "block message does not advertise a verify-skip bypass"
else
    fail "block message still advertises verify-skip: $(grep "verify-skip" "$TMP/stderr.txt")"
fi

# 5. same flip WITH a matching evidence file → exit 0
FX="$(make_fixture evidenced)"
mkdir -p "$FX/dev-docs/verification"
: > "$FX/dev-docs/verification/feature-42-20260709.md"
edit_payload "$FX/docs/features.md" "| 42 | Sample feature | Reader | High | DONE |" \
    "| 42 | Sample feature | Reader | High | VERIFIED |" | run_hook "$FX"
RC=$?
if [ "$RC" -eq 0 ]; then ok "evidenced VERIFIED flip allowed (exit 0)"; else fail "evidenced flip blocked (rc=$RC)"; fi

# 6. docs/bugs.md flip to FIXED → exit 0 (FIXED is the merge gate, not enforced here)
FX="$(make_fixture bugs)"
cat > "$FX/docs/bugs.md" <<'EOF'
| ID | Description | Area | Priority | Status | Notes |
|----|-------------|------|----------|--------|-------|
| 360 | Phantom verify-skip bypass | Hooks | Medium | OPEN | GH: #1890 |
EOF
edit_payload "$FX/docs/bugs.md" "| OPEN |" "| FIXED |" | run_hook "$FX"
RC=$?
if [ "$RC" -eq 0 ]; then ok "bugs.md FIXED flip allowed (exit 0)"; else fail "bugs.md flip blocked (rc=$RC)"; fi

# 7. Write payload flipping to VERIFIED without evidence → exit 2
FX="$(make_fixture write)"
NEW_CONTENT="$(sed 's/| DONE |/| VERIFIED |/' "$FX/docs/features.md")"
jq -n --arg fp "$FX/docs/features.md" --arg c "$NEW_CONTENT" \
    '{tool_name: "Write", tool_input: {file_path: $fp, content: $c}}' | run_hook "$FX"
RC=$?
if [ "$RC" -eq 2 ]; then ok "Write-tool VERIFIED flip blocked (exit 2)"; else fail "Write-tool flip not blocked (rc=$RC)"; fi

# 8. MultiEdit payload flipping to VERIFIED without evidence → exit 2
FX="$(make_fixture multiedit)"
jq -n --arg fp "$FX/docs/features.md" \
    '{tool_name: "MultiEdit", tool_input: {file_path: $fp, edits: [
        {old_string: "| 42 | Sample feature | Reader | High | DONE |",
         new_string: "| 42 | Sample feature | Reader | High | VERIFIED |"}]}}' | run_hook "$FX"
RC=$?
if [ "$RC" -eq 2 ]; then ok "MultiEdit VERIFIED flip blocked (exit 2)"; else fail "MultiEdit flip not blocked (rc=$RC)"; fi

echo
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$fails FAILURE(S)"; exit 1; fi
