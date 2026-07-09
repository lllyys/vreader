#!/usr/bin/env bash
# Feature #130 WI-3 — contract tests for scripts/worktree-setup.sh +
# worktree-teardown.sh against a SCRATCH git repo (never the real checkout).
#
# Run: bash scripts/__tests__/worktree.test.sh

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="$HERE/../worktree-setup.sh"
TEARDOWN="$HERE/../worktree-teardown.sh"
fails=0
TMP="$(mktemp -d)" || { echo "FATAL: mktemp failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

ok()   { echo "ok   — $1"; }
fail() { echo "FAIL — $1"; fails=$((fails+1)); }

for f in "$SETUP" "$TEARDOWN"; do
    if [ ! -f "$f" ]; then echo "FAIL — $f does not exist"; echo "1 FAILURE(S)"; exit 1; fi
done

# scratch repo with a main branch + one commit
REPO="$TMP/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email t@t && git -C "$REPO" config user.name t
echo hello > "$REPO/file.txt"
mkdir -p "$REPO/vreader.xcodeproj"; echo proj > "$REPO/vreader.xcodeproj/project.pbxproj"
git -C "$REPO" add -A && git -C "$REPO" commit -qm base

run_setup()    { ( cd "$REPO" && bash "$SETUP" "$@" 2>&1 ); }
run_teardown() { ( cd "$REPO" && bash "$TEARDOWN" "$@" 2>&1 ); }

echo "== worktree-setup / teardown contract =="

# 1. happy path: creates .claude/worktrees/<id> on a new branch, prints abs path
OUT="$(run_setup issue-1 fix/issue-1-slug)"; RC=$?
WT="$REPO/.claude/worktrees/issue-1"
if [ "$RC" -eq 0 ] && [ -d "$WT" ] && grep -q "$WT" <<<"$OUT"; then ok "setup creates worktree + prints abs path"; else fail "setup (rc=$RC): $OUT"; fi
if [ "$(git -C "$WT" branch --show-current)" = "fix/issue-1-slug" ]; then ok "worktree on the new branch"; else fail "branch: $(git -C "$WT" branch --show-current)"; fi

# 2. duplicate branch name → refuse
OUT="$(run_setup issue-1b fix/issue-1-slug)"; RC=$?
if [ "$RC" -ne 0 ]; then ok "duplicate branch refused"; else fail "dup branch accepted"; fi

# 3. cap: a 2nd lane worktree is allowed, a 3rd refused
OUT="$(run_setup issue-2 fix/issue-2-slug)"; RC=$?
if [ "$RC" -eq 0 ]; then ok "second lane worktree allowed"; else fail "2nd worktree (rc=$RC): $OUT"; fi
OUT="$(run_setup issue-3 fix/issue-3-slug)"; RC=$?
if [ "$RC" -eq 2 ]; then ok "third worktree refused (cap 2)"; else fail "cap (rc=$RC): $OUT"; fi

# 4. dirty main tree (a tracked file, not the pbxproj carve-out) → refuse
run_teardown issue-2 >/dev/null 2>&1
echo dirty >> "$REPO/file.txt"
OUT="$(run_setup issue-4 fix/issue-4-slug)"; RC=$?
if [ "$RC" -ne 0 ] && grep -qi "dirty\|clean" <<<"$OUT"; then ok "dirty main tree refused"; else fail "dirty tree (rc=$RC): $OUT"; fi
git -C "$REPO" checkout -q -- file.txt

# 5. the standing pbxproj signing edit is CARVED OUT (docs'd local-only edit)
echo "DEVELOPMENT_TEAM = X;" >> "$REPO/vreader.xcodeproj/project.pbxproj"
OUT="$(run_setup issue-5 fix/issue-5-slug)"; RC=$?
if [ "$RC" -eq 0 ]; then ok "pbxproj signing edit carve-out honored"; else fail "carve-out (rc=$RC): $OUT"; fi
run_teardown issue-5 >/dev/null 2>&1
git -C "$REPO" checkout -q -- vreader.xcodeproj/project.pbxproj

# 6. teardown refuses uncommitted changes without --force, obeys with it
echo work > "$WT/file.txt"
OUT="$(run_teardown issue-1)"; RC=$?
if [ "$RC" -ne 0 ] && [ -d "$WT" ]; then ok "teardown refuses dirty worktree"; else fail "teardown dirty (rc=$RC)"; fi
OUT="$(run_teardown issue-1 --force)"; RC=$?
if [ "$RC" -eq 0 ] && [ ! -d "$WT" ]; then ok "teardown --force removes"; else fail "teardown --force (rc=$RC): $OUT"; fi

# 7. SETUP CAP RACE (Gate-4 Medium): 8 concurrent setups on an empty base →
#    exactly 2 CREATED (the setup mutex serializes count+add)
rm -rf "$REPO/.claude/worktrees"
git -C "$REPO" worktree prune
CWINS="$TMP/cap-wins"; : > "$CWINS"
for i in 1 2 3 4 5 6 7 8; do
    ( cd "$REPO" && env AGENT_LOCK_ROOT="$TMP/race-locks" bash "$SETUP" "race-$i" "fix/race-$i" >> "$CWINS" 2>/dev/null ) &
done
wait
CREATED=$(grep -c "WORKTREE RESULT: CREATED" "$CWINS" || true)
if [ "$CREATED" -eq 2 ]; then ok "8-way setup race → exactly 2 worktrees (cap held)"; else fail "setup race: $CREATED created"; fi

echo
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$fails FAILURE(S)"; exit 1; fi
