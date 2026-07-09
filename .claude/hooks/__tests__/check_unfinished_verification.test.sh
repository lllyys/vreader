#!/usr/bin/env bash
# Bug #361 (GH #1891) — regression test for check_unfinished_verification.sh.
#
# The hook split tracker rows on EVERY `|`, including backslash-escaped ones
# (`\|`), so a `\|` inside a cell shifted all subsequent cell indices:
#   - the awk pass read notes as cells[n-1], so `\|` inside the Notes cell
#     truncated the "awaiting VERIFIED" ack marker → false verification debt;
#   - the python mirror scan read status=cells[5]/notes=cells[6] from the
#     front, so `\|` in the Summary made status read the Sev/Prio cell and
#     notes read the Status cell → false BUG-/FEATURE-DEBT (and real GH refs
#     invisible).
# Contract after the fix: `\|` is masked before splitting (deps-check.sh
# pattern), Status/Notes parse correctly, and the hook still ALWAYS exits 0
# (Stop hooks are informational).
#
# Run: bash .claude/hooks/__tests__/check_unfinished_verification.test.sh

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/../check_unfinished_verification.sh"
fails=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok()   { echo "ok   — $1"; }
fail() { echo "FAIL — $1"; fails=$((fails+1)); }

# The hook silently exits 0 when jq/python3 are missing — that would turn
# every assertion below into a confusing false pass.
command -v jq >/dev/null 2>&1 || { echo "FAIL — jq is required to run this test"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL — python3 is required to run this test"; exit 1; }

# ---- fixture builder ------------------------------------------------------
# $1=name → prints fixture dir. Caller fills docs/features.md, docs/bugs.md,
# dev-docs/verification/ afterwards.
make_fixture() {
    local dir="$TMP/$1"
    mkdir -p "$dir/docs" "$dir/dev-docs/verification"
    printf '%s' "$dir"
}

tracker_header() {
    cat <<'EOF'
| ID | Summary | Area | Priority | Status | Notes |
|----|---------|------|----------|--------|-------|
EOF
}

run_hook() {  # $1=fixture dir; Stop-hook JSON on stdin; stderr → $TMP/stderr.txt
    # /bin/bash pins the production runtime (the hook's shebang → macOS 3.2).
    echo '{}' | CLAUDE_PROJECT_DIR="$1" /bin/bash "$HOOK" 2>"$TMP/stderr.txt"
}

echo "== check_unfinished_verification.sh =="

# 1. NEGATIVE (normal rows, clean state) — no warnings, exit 0.
FX="$(make_fixture clean)"
{ tracker_header; echo '| 42 | Sample feature | Reader | High | DONE | GH: #900 |'; } > "$FX/docs/features.md"
{ tracker_header; echo '| 7 | Sample bug | Hooks | Medium | OPEN | GH: #100 |'; } > "$FX/docs/bugs.md"
: > "$FX/dev-docs/verification/feature-42-20260709.md"
run_hook "$FX"; RC=$?
if [ "$RC" -eq 0 ]; then ok "clean fixture exits 0"; else fail "clean fixture rc=$RC"; fi
if [ ! -s "$TMP/stderr.txt" ]; then ok "clean fixture emits no warnings"; else fail "clean fixture warned: $(head -3 "$TMP/stderr.txt")"; fi

# 2. POSITIVE (normal rows, real debt) — both debt classes surface; exit 0.
FX="$(make_fixture debt)"
{ tracker_header; echo '| 43 | Unverified feature | Reader | High | DONE | no issue yet |'; } > "$FX/docs/features.md"
{ tracker_header; echo '| 8 | Unmirrored bug | Hooks | Low | OPEN | none |'; } > "$FX/docs/bugs.md"
run_hook "$FX"; RC=$?
if [ "$RC" -eq 0 ]; then ok "debt fixture still exits 0 (Stop-hook contract)"; else fail "debt fixture rc=$RC (must never block)"; fi
if grep -q "verification-debt-hook" "$TMP/stderr.txt" && grep -q "#43" "$TMP/stderr.txt"; then
    ok "verification debt surfaced for #43"
else
    fail "verification debt for #43 not surfaced"
fi
if grep -q "BUG rows lacking GH:#N: 1 — #8" "$TMP/stderr.txt"; then
    ok "mirror debt surfaced for bug #8"
else
    fail "mirror debt for bug #8 not surfaced"
fi
if grep -q "FEATURE rows lacking GH:#N: 1 — #43" "$TMP/stderr.txt"; then
    ok "mirror debt surfaced for feature #43"
else
    fail "mirror debt for feature #43 not surfaced"
fi

# 3. THE BUG (awk lane) — `\|` inside the NOTES cell of a DONE row. The ack
#    marker "awaiting VERIFIED" precedes the escaped pipe; pre-fix the awk
#    read notes=cells[n-1]=" GH: #500", missed the ack, and reported false
#    verification debt (and the python scan read notes as "awaiting VERIFIED \"
#    → false FEATURE-DEBT despite the GH ref).
FX="$(make_fixture esc-notes)"
{ tracker_header; echo '| 44 | Acked feature | Reader | High | DONE | awaiting VERIFIED \| GH: #500 |'; } > "$FX/docs/features.md"
{ tracker_header; } > "$FX/docs/bugs.md"
run_hook "$FX"; RC=$?
if [ "$RC" -eq 0 ]; then ok "esc-notes fixture exits 0"; else fail "esc-notes fixture rc=$RC"; fi
if ! grep -q "verification-debt-hook" "$TMP/stderr.txt"; then
    ok "escaped pipe in Notes: ack marker still honored (no false verification debt)"
else
    fail "escaped pipe in Notes truncated the ack marker: $(head -5 "$TMP/stderr.txt")"
fi
if ! grep -q "FEATURE rows lacking" "$TMP/stderr.txt"; then
    ok "escaped pipe in Notes: GH ref still visible (no false FEATURE-DEBT)"
else
    fail "escaped pipe in Notes hid the GH ref from the mirror scan"
fi

# 4. THE BUG (python lane) — `\|` in the SUMMARY cell of a bug row that HAS a
#    GH ref. Pre-fix the mirror scan read status='Medium' (Sev cell) and
#    notes='OPEN' (Status cell) → false BUG-DEBT. The features fixture keeps
#    one plain DONE row (evidenced + GH'd) so the mirror scan is reached.
FX="$(make_fixture esc-summary)"
{ tracker_header; echo '| 50 | Normal done | Reader | High | DONE | GH: #800 |'; } > "$FX/docs/features.md"
{ tracker_header; echo '| 9 | Split \| pipes bug | Hooks | Medium | OPEN | GH: #100 |'; } > "$FX/docs/bugs.md"
: > "$FX/dev-docs/verification/feature-50-20260709.md"
run_hook "$FX"; RC=$?
if [ "$RC" -eq 0 ]; then ok "esc-summary fixture exits 0"; else fail "esc-summary fixture rc=$RC"; fi
if ! grep -q "BUG rows lacking" "$TMP/stderr.txt"; then
    ok "escaped pipe in Summary: Status/Notes parsed correctly (no false BUG-DEBT)"
else
    fail "escaped pipe in Summary shifted Status/Notes: $(grep 'BUG rows' "$TMP/stderr.txt")"
fi

# 5. Shift direction that HIDES real debt — `\|` in a feature Summary with NO
#    GH ref. Pre-fix status read 'High' (not mirror-required) → the real
#    violation vanished. Post-fix it must surface as FEATURE-DEBT.
FX="$(make_fixture esc-hidden)"
{ tracker_header
  echo '| 50 | Normal done | Reader | High | DONE | GH: #800 |'
  echo '| 51 | Esc \| feature | Reader | High | PLANNED | no issue yet |'
} > "$FX/docs/features.md"
{ tracker_header; } > "$FX/docs/bugs.md"
: > "$FX/dev-docs/verification/feature-50-20260709.md"
run_hook "$FX"; RC=$?
if [ "$RC" -eq 0 ]; then ok "esc-hidden fixture exits 0"; else fail "esc-hidden fixture rc=$RC"; fi
if grep -q "FEATURE rows lacking GH:#N: 1 — #51" "$TMP/stderr.txt"; then
    ok "escaped pipe in Summary no longer hides a real mirror violation (#51)"
else
    fail "real mirror violation #51 still hidden by the escaped pipe"
fi

echo
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$fails FAILURE(S)"; exit 1; fi
