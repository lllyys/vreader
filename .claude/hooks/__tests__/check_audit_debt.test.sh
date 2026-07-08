#!/usr/bin/env bash
# Feature #130 WI-1 — regression test for check_audit_debt.sh's scan window.
# The old hook scanned `main -5`, so a batch of >5 merges between Stop events
# silently dropped audit debt. New contract: scan since the last version tag,
# with a MINIMUM floor of 15 commits (a rogue merge hidden behind a later tag
# still surfaces), and a best-effort fetch that must not fail the hook offline.
#
# Run: bash .claude/hooks/__tests__/check_audit_debt.test.sh

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/../check_audit_debt.sh"
REAL_LIB="$HERE/../lib/code-paths.sh"
fails=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok()   { echo "ok   — $1"; }
fail() { echo "FAIL — $1"; fails=$((fails+1)); }

# ---- fixture repo: 7 code-touching squash-merges AFTER the last tag ----
REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email t@t && git -C "$REPO" config user.name t
mkdir -p "$REPO/.claude/hooks/lib" "$REPO/.claude/codex-audits" "$REPO/vreader"
cp "$REAL_LIB" "$REPO/.claude/hooks/lib/code-paths.sh"
echo base > "$REPO/README.md"
git -C "$REPO" add -A && git -C "$REPO" commit -qm "chore: base"
git -C "$REPO" tag v0.0.1

for n in 1 2 3 4 5 6 7; do
    echo "code $n" > "$REPO/vreader/File$n.swift"
    git -C "$REPO" add -A && git -C "$REPO" commit -qm "feat: change $n (#10$n)"
done

# ---- stub gh: maps `pr view 10N` → branch feat/branch-10N ----
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env bash
# stub: gh pr view <N> --json headRefName -q .headRefName
for a in "$@"; do
    if [[ "$a" =~ ^[0-9]+$ ]]; then echo "feat/branch-$a"; exit 0; fi
done
exit 1
EOF
chmod +x "$BIN/gh"

run_hook() {
    echo '{}' | env PATH="$BIN:$PATH" CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" 2>&1
}

echo "== check_audit_debt.sh scan window =="

# 1. all 7 post-tag merges surface (old -5 window would show only 5)
OUT="$(run_hook)"; RC=$?
if [ "$RC" -eq 0 ]; then ok "hook exits 0 (informational contract)"; else fail "hook exited $RC"; fi
MISSING=""
for n in 1 2 3 4 5 6 7; do
    grep -q "#10$n" <<<"$OUT" || MISSING="$MISSING #10$n"
done
if [ -z "$MISSING" ]; then ok "all 7 post-tag merges surfaced (>5-batch regression)"; else fail "dropped:$MISSING"; fi

# 2. an audited branch is not flagged
: > "$REPO/.claude/codex-audits/feat-branch-103-audit.md"
OUT="$(run_hook)"
if ! grep -q "#103" <<<"$OUT" && grep -q "#104" <<<"$OUT"; then
    ok "audited branch (#103) excluded; others still flagged"
else
    fail "audit-file exclusion broken"
fi

# 3. no tag at all → floor window still works, no error
git -C "$REPO" tag -d v0.0.1 -q >/dev/null 2>&1 || git -C "$REPO" tag -d v0.0.1 >/dev/null 2>&1
OUT="$(run_hook)"; RC=$?
if [ "$RC" -eq 0 ] && grep -q "#107" <<<"$OUT"; then ok "tagless repo falls back to floor window"; else fail "tagless fallback (rc=$RC)"; fi

# 4. offline fetch must not break the hook (fixture has NO remote at all)
#    (implicitly proven by 1–3 running with no origin; assert explicitly)
if ! git -C "$REPO" remote | grep -q .; then ok "ran with no remote — fetch is best-effort"; else fail "fixture unexpectedly has a remote"; fi

# 5. tag AT HEAD (zero commits since tag) — the real-repo steady state; the
#    since-tag count is 0 and must not blow up the hook's arithmetic
#    (regression: `grep -c` prints 0 AND exits 1; a careless `|| echo 0`
#    doubles the zero and breaks [[ -gt ]]).
git -C "$REPO" tag v9.9.9
OUT="$(run_hook)"; RC=$?
if [ "$RC" -eq 0 ] && ! grep -qi "arithmetic\|syntax error" <<<"$OUT"; then
    ok "tag-at-HEAD: no arithmetic blowup, exit 0"
else
    fail "tag-at-HEAD broke the hook (rc=$RC): $(grep -i 'arithmetic\|syntax' <<<"$OUT" | head -1)"
fi

# 6. prefers origin/main over a stale local main: a merge that exists ONLY on
#    origin/main (local main is behind) must still be scanned + flagged.
BARE="$TMP/origin.git"
git init -q --bare "$BARE"
git -C "$REPO" remote add origin "$BARE"
git -C "$REPO" push -q origin main
CLONE="$TMP/clone"
git clone -q "$BARE" "$CLONE"
git -C "$CLONE" config user.email t@t && git -C "$CLONE" config user.name t
echo "code 8" > "$CLONE/vreader/File8.swift"
git -C "$CLONE" add -A && git -C "$CLONE" commit -qm "feat: change 8 (#108)"
git -C "$CLONE" push -q origin main
OUT="$(run_hook)"
if grep -q "#108" <<<"$OUT"; then
    ok "origin-only merge (#108) scanned via origin/main (stale local main)"
else
    fail "origin-only merge (#108) not scanned — hook stuck on local main"
fi

echo
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$fails FAILURE(S)"; exit 1; fi
