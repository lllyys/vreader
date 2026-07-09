#!/usr/bin/env bash
# worktree-teardown.sh <id> [--force] [--delete-branch] — remove a lane
# worktree + its DerivedData (feature #130 WI-3; lifts the fix-issue M5
# cleanup out of skill prose). Refuses a worktree with uncommitted changes
# unless --force. --delete-branch also deletes the lane's local branch —
# POST-MERGE only (a requeued lane's branch must survive for the redo);
# gh pr merge --delete-branch is banned (it checks out the default branch,
# which fails in a linked worktree).
#
# Usage: worktree-teardown.sh <id> [--force] [--delete-branch]
#   exit 0 REMOVED | 1 dirty without --force / git failure | 3 no such worktree

set -euo pipefail

id="${1:-}"
[ -n "$id" ] || { echo "usage: worktree-teardown.sh <id> [--force] [--delete-branch]" >&2; exit 64; }
force=""
delete_branch=""
shift || true
for a in "$@"; do
    case "$a" in
        --force) force="--force" ;;
        --delete-branch) delete_branch=1 ;;
        *) echo "usage: worktree-teardown.sh <id> [--force] [--delete-branch]" >&2; exit 64 ;;
    esac
done

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

BRANCH="$(git -C "$WT" branch --show-current 2>/dev/null || true)"

if [ "$force" = "--force" ]; then
    git -C "$ROOT" worktree remove --force "$WT" >/dev/null
else
    git -C "$ROOT" worktree remove "$WT" >/dev/null
fi

if [ -n "$delete_branch" ] && [ -n "$BRANCH" ]; then
    git -C "$ROOT" branch -D "$BRANCH" >/dev/null 2>&1 \
        && echo "[worktree-teardown] deleted branch $BRANCH" \
        || echo "[worktree-teardown] branch $BRANCH not deleted (already gone?)" >&2
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
