#!/usr/bin/env bash
# worktree-teardown.sh <id> [--force] — remove a lane worktree + its
# DerivedData (feature #130 WI-3; lifts the fix-issue M5 cleanup out of
# skill prose). Refuses a worktree with uncommitted changes unless --force.
#
# Usage: worktree-teardown.sh <id> [--force]
#   exit 0 REMOVED | 1 dirty without --force / git failure | 3 no such worktree

set -euo pipefail

id="${1:-}"
force="${2:-}"
[ -n "$id" ] || { echo "usage: worktree-teardown.sh <id> [--force]" >&2; exit 64; }

ROOT="$(git rev-parse --show-toplevel)"
WT="$ROOT/.claude/worktrees/$id"

if [ ! -d "$WT" ]; then
    echo "worktree-teardown: no worktree at $WT" >&2
    exit 3
fi

if [ "$force" != "--force" ] && [ -n "$(git -C "$WT" status --porcelain 2>/dev/null)" ]; then
    echo "worktree-teardown: $WT has uncommitted changes — commit them or pass --force" >&2
    exit 1
fi

if [ "$force" = "--force" ]; then
    git -C "$ROOT" worktree remove --force "$WT" >/dev/null
else
    git -C "$ROOT" worktree remove "$WT" >/dev/null
fi

# M5 DerivedData sweep: each worktree accrues ~5GB keyed on WorkspacePath.
DD="$HOME/Library/Developer/Xcode/DerivedData"
if [ -d "$DD" ]; then
    for d in "$DD"/vreader-*; do
        [ -e "$d/info.plist" ] || continue
        wsp="$(plutil -extract WorkspacePath raw "$d/info.plist" 2>/dev/null || true)"
        case "$wsp" in
            "$WT"|"$WT"/*) rm -rf "$d"
                echo "[worktree-teardown] swept DerivedData $(basename "$d")" ;;
        esac
    done
fi

echo "WORKTREE RESULT: REMOVED $id"
