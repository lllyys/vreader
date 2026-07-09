#!/usr/bin/env bash
# Feature #130 WI-3 — contract tests for scripts/check-write-set.sh
# (--name-status -M semantics: renames count both paths, deletions count,
# forbidden list hard-fails, prefix ⊆ enforced). Scratch repo.
#
# Run: bash scripts/__tests__/check-write-set.test.sh

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/../check-write-set.sh"
fails=0
TMP="$(mktemp -d)" || { echo "FATAL: mktemp failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

ok()   { echo "ok   — $1"; }
fail() { echo "FAIL — $1"; fails=$((fails+1)); }

if [ ! -f "$CHECK" ]; then echo "FAIL — $CHECK does not exist"; echo "1 FAILURE(S)"; exit 1; fi

# scratch repo: base commit on main, work on a branch
REPO="$TMP/repo"; mkdir -p "$REPO/src/feature" "$REPO/docs" "$REPO/other"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email t@t && git -C "$REPO" config user.name t
echo a > "$REPO/src/feature/a.txt"; echo b > "$REPO/src/feature/b.txt"
echo d > "$REPO/docs/bugs.md"; echo o > "$REPO/other/o.txt"; echo p > "$REPO/project.yml"
git -C "$REPO" add -A && git -C "$REPO" commit -qm base
git -C "$REPO" checkout -q -b lane

run() { # prefixes...
    ( cd "$REPO" && env CHECK_BASE_REF=main bash "$CHECK" "$REPO" "$@" 2>&1 );
}

echo "== check-write-set.sh contract =="

# 1. in-prefix modification passes
echo mod >> "$REPO/src/feature/a.txt"; git -C "$REPO" commit -aqm m1
OUT="$(run src/feature/)"; RC=$?
if [ "$RC" -eq 0 ]; then ok "in-prefix edit passes"; else fail "in-prefix (rc=$RC): $OUT"; fi

# 2. out-of-prefix edit fails, names the path
echo x >> "$REPO/other/o.txt"; git -C "$REPO" commit -aqm m2
OUT="$(run src/feature/)"; RC=$?
if [ "$RC" -ne 0 ] && grep -q "other/o.txt" <<<"$OUT"; then ok "out-of-prefix fails naming path"; else fail "out-of-prefix (rc=$RC): $OUT"; fi
git -C "$REPO" reset -q --hard HEAD~1

# 3. FORBIDDEN paths hard-fail even when inside a declared prefix
echo evil >> "$REPO/docs/bugs.md"; git -C "$REPO" commit -aqm m3
OUT="$(run docs/ src/feature/)"; RC=$?
if [ "$RC" -ne 0 ] && grep -qi "forbidden" <<<"$OUT"; then ok "forbidden path hard-fails despite prefix"; else fail "forbidden (rc=$RC): $OUT"; fi
git -C "$REPO" reset -q --hard HEAD~1

# 4. rename INTO a forbidden path fails (both rename sides checked)
git -C "$REPO" mv src/feature/b.txt project.yml.new 2>/dev/null || { git -C "$REPO" mv src/feature/b.txt docs/bugs.md.bak; }
git -C "$REPO" commit -qm m4
OUT="$(run src/feature/ docs/)"; RC=$?
if [ "$RC" -ne 0 ]; then ok "rename lands outside/forbidden → fails"; else fail "rename (rc=$RC): $OUT"; fi
git -C "$REPO" reset -q --hard HEAD~1

# 5. deletion outside prefix fails; deletion inside passes
git -C "$REPO" rm -q other/o.txt && git -C "$REPO" commit -qm m5
OUT="$(run src/feature/)"; RC=$?
if [ "$RC" -ne 0 ]; then ok "out-of-prefix deletion fails"; else fail "deletion out (rc=$RC): $OUT"; fi
git -C "$REPO" reset -q --hard HEAD~1
git -C "$REPO" rm -q src/feature/b.txt && git -C "$REPO" commit -qm m6
OUT="$(run src/feature/)"; RC=$?
if [ "$RC" -eq 0 ]; then ok "in-prefix deletion passes"; else fail "deletion in (rc=$RC): $OUT"; fi
git -C "$REPO" reset -q --hard HEAD~1

# 6. exact-file prefix (not just directories)
echo mod2 >> "$REPO/src/feature/a.txt"; git -C "$REPO" commit -aqm m7
OUT="$(run src/feature/a.txt)"; RC=$?
if [ "$RC" -eq 0 ]; then ok "exact-file prefix matches"; else fail "exact file (rc=$RC): $OUT"; fi

# 7. no declared prefixes → usage error
OUT="$( cd "$REPO" && env CHECK_BASE_REF=main bash "$CHECK" "$REPO" 2>&1 )"; RC=$?
if [ "$RC" -eq 64 ]; then ok "missing prefixes → usage (64)"; else fail "usage (rc=$RC): $OUT"; fi

# 8. STANDING ALLOWANCE: the lane contract commits .claude/codex-audits/ on
#    the branch — it never appears in a Spec write-set and must still pass
#    (lucid finding: without this, every contract-compliant lane fails 6a)
mkdir -p "$REPO/.claude/codex-audits"
echo audit > "$REPO/.claude/codex-audits/lane-branch-audit.md"
echo mod3 >> "$REPO/src/feature/a.txt"
git -C "$REPO" add -A && git -C "$REPO" commit -qm m8
OUT="$(run src/feature/)"; RC=$?
if [ "$RC" -eq 0 ]; then ok "committed audit artifact passes via standing allowance"; else fail "audit allowance (rc=$RC): $OUT"; fi

# 8b. FAIL CLOSED on diff error (Gate-4 High): a bogus base ref must never
#     print CLEAN
OUT="$( cd "$REPO" && env CHECK_BASE_REF=no-such-ref bash "$CHECK" "$REPO" src/feature/ 2>&1 )"; RC=$?
if [ "$RC" -eq 1 ] && grep -q "ERROR" <<<"$OUT" && ! grep -q "CLEAN" <<<"$OUT"; then ok "diff failure → fail closed (ERROR, never CLEAN)"; else fail "diff failure (rc=$RC): $OUT"; fi

# 8c. platform boundary (rule 48): an ios lane touching android-owned paths
#     is rejected via the real classifier
mkdir -p "$REPO/.claude/hooks/lib"
cp "$HERE/../../.claude/hooks/lib/code-paths.sh" "$REPO/.claude/hooks/lib/code-paths.sh"
git -C "$REPO" add -A && git -C "$REPO" commit -qm m9-classifier
mkdir -p "$REPO/android/app"
echo kt > "$REPO/android/app/Foo.kt"
git -C "$REPO" add -A && git -C "$REPO" commit -qm m9
OUT="$(run android/ src/feature/)"; RC=$?   # prefixes allow it — platform gate must still fire
OUT="$( cd "$REPO" && env CHECK_BASE_REF=main CHECK_LANE_PLATFORM=ios bash "$CHECK" "$REPO" android/ src/feature/ .claude/ 2>&1 )"; RC=$?
if [ "$RC" -eq 1 ] && grep -qi "platform boundary" <<<"$OUT"; then ok "ios lane + .kt paths → platform violation"; else fail "platform gate (rc=$RC): $OUT"; fi
git -C "$REPO" reset -q --hard HEAD~1
echo mod4 >> "$REPO/src/feature/a.txt"; git -C "$REPO" commit -aqm m10
OUT="$( cd "$REPO" && env CHECK_BASE_REF=main CHECK_LANE_PLATFORM=ios bash "$CHECK" "$REPO" src/feature/ .claude/ 2>&1 )"; RC=$?
if [ "$RC" -eq 0 ]; then ok "ios lane + plain paths passes platform gate"; else fail "platform pass (rc=$RC): $OUT"; fi
# reciprocal direction: an android-app lane touching iOS-owned paths fails
mkdir -p "$REPO/vreader"
echo swift > "$REPO/vreader/Foo.swift"
git -C "$REPO" add -A && git -C "$REPO" commit -qm m11
OUT="$( cd "$REPO" && env CHECK_BASE_REF=main CHECK_LANE_PLATFORM=android-app bash "$CHECK" "$REPO" vreader/ src/feature/ .claude/ 2>&1 )"; RC=$?
if [ "$RC" -eq 1 ] && grep -qi "platform boundary" <<<"$OUT"; then ok "android lane + .swift paths → platform violation (reciprocal)"; else fail "reciprocal platform gate (rc=$RC): $OUT"; fi
git -C "$REPO" reset -q --hard HEAD~1

# 9. worktree-path run: gate a LANE WORKTREE while cwd = main checkout
#    (lucid FIX-1 class: 'fires' ≠ 'fires correctly in a lane')
git -C "$REPO" checkout -q main
git -C "$REPO" worktree add "$REPO/.claude/worktrees/lane-x" -b lane-x main -q 2>/dev/null || git -C "$REPO" worktree add "$REPO/.claude/worktrees/lane-x" -b lane-x main
WT="$REPO/.claude/worktrees/lane-x"
echo lane >> "$WT/src/feature/a.txt"; git -C "$WT" commit -aqm lane1
OUT="$( cd "$REPO" && env CHECK_BASE_REF=main bash "$CHECK" "$WT" src/feature/ 2>&1 )"; RC=$?
if [ "$RC" -eq 0 ]; then ok "lane worktree gated from main-checkout cwd"; else fail "worktree cwd (rc=$RC): $OUT"; fi
echo stray >> "$WT/other/o.txt"; git -C "$WT" commit -aqm lane2
OUT="$( cd "$REPO" && env CHECK_BASE_REF=main bash "$CHECK" "$WT" src/feature/ 2>&1 )"; RC=$?
if [ "$RC" -ne 0 ] && grep -q "other/o.txt" <<<"$OUT"; then ok "lane worktree violation caught from main-checkout cwd"; else fail "worktree violation (rc=$RC): $OUT"; fi

echo
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$fails FAILURE(S)"; exit 1; fi
