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

echo
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$fails FAILURE(S)"; exit 1; fi
