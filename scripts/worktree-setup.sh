#!/usr/bin/env bash
# worktree-setup.sh <id> <branch> — create a lane worktree (feature #130 WI-3).
#
# Preconditions (rule 48/55): the main tree must be clean of modified TRACKED
# files — with ONE carve-out: `vreader.xcodeproj/project.pbxproj` (the owner's
# standing local signing edit, documented in memory + AGENTS practice) —
# and at most 1 other lane worktree may exist (cap 2). Prints the ABSOLUTE
# worktree path (the orchestrator substitutes it into the rule-48 brief
# preamble).
#
# Usage: worktree-setup.sh <id> <branch>
#   exit 0 CREATED | 1 dirty tree / bad args / git failure | 2 cap reached

set -euo pipefail

id="${1:-}"
branch="${2:-}"
if [ -z "$id" ] || [ -z "$branch" ]; then
    echo "usage: worktree-setup.sh <id> <branch>" >&2
    exit 64
fi
printf '%s' "$id" | grep -qE '^[A-Za-z0-9][A-Za-z0-9._-]*$' || { echo "worktree-setup: invalid id '$id'" >&2; exit 64; }

ROOT="$(git rev-parse --show-toplevel)"
WT_BASE="$ROOT/.claude/worktrees"
WT="$WT_BASE/$id"

# Clean-tree precondition. Modified tracked files poison a lane's git context
# (rule 48); the standing pbxproj signing edit is the documented exception.
DIRTY="$(git -C "$ROOT" status --porcelain --untracked-files=no \
    | grep -v 'vreader.xcodeproj/project.pbxproj$' || true)"
if [ -n "$DIRTY" ]; then
    echo "worktree-setup: main tree is dirty (tracked changes beyond the pbxproj signing carve-out):" >&2
    printf '%s\n' "$DIRTY" >&2
    exit 1
fi

# Cap: at most 2 lane worktrees (the machine's honest build ceiling).
mkdir -p "$WT_BASE"
count="$(find "$WT_BASE" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
if [ "$count" -ge 2 ]; then
    echo "worktree-setup: lane cap reached ($count worktrees exist) — teardown one first" >&2
    exit 2
fi

git -C "$ROOT" worktree add "$WT" -b "$branch" main >/dev/null
echo "WORKTREE RESULT: CREATED $WT"
