#!/usr/bin/env bash
# check-write-set.sh <worktree-dir> <prefix>... — the trust-but-verify gate
# (feature #130 WI-3, rule 55): assert a lane branch's diff stayed inside its
# declared write-set and off the forbidden shared surfaces.
#
# Diff semantics: `git diff --name-status -M <base>...HEAD` — renames count
# BOTH sides, deletions count, paths are repo-relative. A prefix ending in
# `/` matches a directory subtree; otherwise it must match the path exactly.
# The forbidden list hard-fails EVEN inside a declared prefix.
#
# Usage: check-write-set.sh <worktree-dir> <prefix> [<prefix>...]
#   exit 0 CLEAN | 1 violations | 64 usage
# Env: CHECK_BASE_REF (default origin/main).

set -euo pipefail

dir="${1:-}"
[ -n "$dir" ] && [ -d "$dir" ] || { echo "usage: check-write-set.sh <worktree-dir> <prefix>..." >&2; exit 64; }
shift
[ "$#" -ge 1 ] || { echo "check-write-set: no write-set prefixes declared" >&2; exit 64; }
PREFIXES=("$@")
BASE="${CHECK_BASE_REF:-origin/main}"

# The orchestrator-only shared surfaces (rule 55). A lane touching ANY of
# these is a contract violation regardless of its declared prefixes.
FORBIDDEN_FILES=(project.yml docs/bugs.md docs/features.md docs/architecture.md README.md)
FORBIDDEN_DIRS=(vreader.xcodeproj/)

path_forbidden() { # $1=path → 0 iff forbidden
    local p="$1" f
    for f in "${FORBIDDEN_FILES[@]}"; do
        [ "$p" = "$f" ] && return 0
    done
    for f in "${FORBIDDEN_DIRS[@]}"; do
        case "$p" in "$f"*) return 0 ;; esac
    done
    return 1
}

# Standing allowances (lucid post-return-check precedent): the lane CONTRACT
# itself requires committing the Gate-4 audit artifact on the branch, so it
# can never appear in a Spec block's write-set — without this allowance every
# contract-compliant lane fails its own gate.
STANDING_ALLOWED=(".claude/codex-audits/")

path_in_prefixes() { # $1=path → 0 iff covered by a declared prefix/allowance
    local p="$1" pref
    for pref in "${STANDING_ALLOWED[@]}" "${PREFIXES[@]}"; do
        if [ "$p" = "$pref" ]; then return 0; fi
        case "$pref" in
            */) case "$p" in "$pref"*) return 0 ;; esac ;;
        esac
    done
    return 1
}

violations=0
paths=""
while IFS=$'\t' read -r status p1 p2; do
    [ -n "$status" ] || continue
    case "$status" in
        R*|C*) paths="$p1"$'\n'"$p2" ;;   # rename/copy: BOTH sides checked
        *)     paths="$p1" ;;
    esac
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        if path_forbidden "$p"; then
            echo "VIOLATION (forbidden surface): $status $p"
            violations=$((violations + 1))
        elif ! path_in_prefixes "$p"; then
            echo "VIOLATION (outside write-set): $status $p"
            violations=$((violations + 1))
        fi
    done <<< "$paths"
done < <(git -C "$dir" diff --name-status -M "$BASE...HEAD" 2>/dev/null)

if [ "$violations" -gt 0 ]; then
    echo "CHECK-WRITE-SET RESULT: VIOLATIONS $violations"
    exit 1
fi
echo "CHECK-WRITE-SET RESULT: CLEAN"
exit 0
