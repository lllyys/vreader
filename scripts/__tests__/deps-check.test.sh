#!/usr/bin/env bash
# Feature #130 WI-2 — contract tests for scripts/deps-check.sh (typed Deps
# token readiness resolution + --lint). Fixture trackers + a stub gh; never
# the real docs/ or network.
#
# Run: bash scripts/__tests__/deps-check.test.sh

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/../deps-check.sh"
fails=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok()   { echo "ok   — $1"; }
fail() { echo "FAIL — $1"; fails=$((fails+1)); }

if [ ! -f "$CHECK" ]; then
    echo "FAIL — $CHECK does not exist"; echo "1 FAILURE(S)"; exit 1
fi

# ---- fixture trackers ----
BUGS="$TMP/bugs.md"
cat > "$BUGS" <<'EOF'
| #  | Summary | File/Area | Severity | Status | Notes |
| --- | --- | --- | --- | --- | --- |
| 10 | fixed bug | a | Low | FIXED | n |
| 11 | wontfix bug | a | Low | WONT FIX | n |
| 12 | open bug | a | Low | TODO | n |
EOF
FEATS="$TMP/features.md"
# Row 20: no token. 21: ready deps. 22: blocked by open bug. 23: malformed
# (bare #N). 24: rule-51 marker. 25: unknown id. 26: legacy prose only.
# 27: CJK + huge Notes with a valid token at head. 28: gh + design edges.
{
cat <<'EOF'
| #  | Summary | Area | Priority | Status | Notes |
| --- | --- | --- | --- | --- | --- |
| 19 | done dep | x | Low | DONE | n |
| 20 | no token | x | Low | TODO | plain notes |
| 21 | ready | x | Low | TODO | Deps:[bug:#10, feat:#19] rest of notes |
| 22 | blocked | x | Low | TODO | Deps:[bug:#12] notes |
| 23 | malformed | x | Low | TODO | Deps:[#12] notes |
| 24 | design-gated | x | Low | TODO | BLOCKED: needs-design (#900) — waiting |
| 25 | unknown | x | Low | TODO | Deps:[bug:#999] notes |
| 26 | legacy | x | Low | TODO | Blocked by bug #12 (old prose) |
| 27 | cjk | x | Low | TODO | Deps:[bug:#11] 中文备注——超长
EOF
printf '| 28 | ghdesign | x | Low | TODO | Deps:[gh:#500, design:#501] notes |\n'
printf '| 29 | prose-mention | x | Low | TODO | this row merely MENTIONS the typed Deps:[…] token mid-notes |\n'
} > "$FEATS"
# pad row 27's notes to a multi-KB single line (parse must stay grep-scoped)
python3 - "$FEATS" <<'EOF'
import sys
p=sys.argv[1]; lines=open(p).read().splitlines()
for i,l in enumerate(lines):
    if l.startswith("| 27 "):
        lines[i]=l+" 数据"*2000+" |"
open(p,"w").write("\n".join(lines)+"\n")
EOF

# ---- stub gh: issue 500 closed, 501 open ----
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
    case "$a" in
        500) echo "CLOSED"; exit 0 ;;
        501) echo "OPEN"; exit 0 ;;
    esac
done
exit 1
EOF
chmod +x "$BIN/gh"

run() { # kind id
    env PATH="$BIN:$PATH" DEPS_BUGS_FILE="$BUGS" DEPS_FEATURES_FILE="$FEATS" bash "$CHECK" "$@" 2>&1
}

echo "== deps-check.sh readiness =="

# 1. absent token → READY with visibility line
OUT="$(run feature 20)"; RC=$?
if [ "$RC" -eq 0 ] && grep -q "no-deps-token" <<<"$OUT"; then ok "absent token → READY + no-deps-token info"; else fail "absent token (rc=$RC): $OUT"; fi

# 2. all edges terminal → READY; WONT FIX resolves with a warning
OUT="$(run feature 21)"; RC=$?
if [ "$RC" -eq 0 ]; then ok "bug:FIXED + feat:DONE → READY"; else fail "ready row blocked (rc=$RC): $OUT"; fi
OUT="$(run feature 27)"; RC=$?
if [ "$RC" -eq 0 ] && grep -qi "warn" <<<"$OUT"; then ok "bug:WONT FIX → READY with warning (CJK/huge Notes row parsed)"; else fail "wontfix edge (rc=$RC): $(head -c 200 <<<"$OUT")"; fi

# 3. open-bug edge → BLOCKED, names the blocker
OUT="$(run feature 22)"; RC=$?
if [ "$RC" -eq 2 ] && grep -q "bug:#12" <<<"$OUT"; then ok "open bug edge → BLOCKED naming bug:#12"; else fail "open-bug edge (rc=$RC): $OUT"; fi

# 4. bare #N inside brackets → malformed (exit 1)
OUT="$(run feature 23)"; RC=$?
if [ "$RC" -eq 1 ]; then ok "bare #N in token → malformed (exit 1)"; else fail "malformed token (rc=$RC): $OUT"; fi

# 5. rule-51 needs-design marker → BLOCKED even with no token
OUT="$(run feature 24)"; RC=$?
if [ "$RC" -eq 2 ] && grep -q "needs-design" <<<"$OUT"; then ok "rule-51 marker → BLOCKED"; else fail "needs-design marker (rc=$RC): $OUT"; fi

# 6. unknown referenced id → BLOCKED (conservative), names it
OUT="$(run feature 25)"; RC=$?
if [ "$RC" -eq 2 ] && grep -q "bug:#999" <<<"$OUT"; then ok "unknown id → BLOCKED (conservative)"; else fail "unknown id (rc=$RC): $OUT"; fi

# 7. gh edge: closed → ready contribution; design edge with OPEN issue → BLOCKED
OUT="$(run feature 28)"; RC=$?
if [ "$RC" -eq 2 ] && grep -q "design:#501" <<<"$OUT" && ! grep -q "gh:#500" <<<"$OUT"; then
    ok "gh closed passes; design open blocks"
else fail "gh/design edges (rc=$RC): $OUT"; fi

# 7b. token is HEAD-of-Notes only: a mid-notes prose MENTION of Deps:[…] is
#     NOT a token (readiness = no-deps-token; lint = clean for that row)
OUT="$(run feature 29)"; RC=$?
if [ "$RC" -eq 0 ] && grep -q "no-deps-token" <<<"$OUT"; then ok "mid-notes Deps mention is not a token"; else fail "prose mention parsed as token (rc=$RC): $OUT"; fi

# 8. nonexistent ROW asked about → error (not READY)
OUT="$(run feature 999)"; RC=$?
if [ "$RC" -ne 0 ]; then ok "missing row → non-zero"; else fail "missing row returned READY"; fi

echo "== deps-check.sh --lint =="

# 9. lint: malformed token → error line; legacy prose on non-terminal row →
#    warning ONLY (exit stays 1 due to the malformed row, but the legacy row
#    is a warn, not an error)
OUT="$(env PATH="$BIN:$PATH" DEPS_BUGS_FILE="$BUGS" DEPS_FEATURES_FILE="$FEATS" bash "$CHECK" --lint "$FEATS" 2>&1)"; RC=$?
if grep -q "malformed" <<<"$OUT" && grep -qE "row 23" <<<"$OUT"; then ok "lint flags the malformed token row"; else fail "lint malformed: $OUT"; fi
if grep -qiE "warn.*row 26|row 26.*warn" <<<"$OUT"; then ok "lint warns (not errors) on legacy prose"; else fail "lint legacy prose: $OUT"; fi
if [ "$RC" -eq 1 ]; then ok "lint exits 1 when malformed rows exist"; else fail "lint rc=$RC want 1"; fi

# 10. lint on a clean tracker → exit 0
CLEAN="$TMP/clean.md"
printf '| #  | Summary | Area | Priority | Status | Notes |\n| 30 | ok | x | Low | TODO | Deps:[bug:#10] n |\n' > "$CLEAN"
OUT="$(env PATH="$BIN:$PATH" DEPS_BUGS_FILE="$BUGS" DEPS_FEATURES_FILE="$FEATS" bash "$CHECK" --lint "$CLEAN" 2>&1)"; RC=$?
if [ "$RC" -eq 0 ]; then ok "clean tracker lints clean"; else fail "clean lint rc=$RC: $OUT"; fi

echo
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$fails FAILURE(S)"; exit 1; fi
