#!/usr/bin/env bash
# Feature #130 WI-4 — static shape gates for the dispatch layer: the skill
# text must carry every load-bearing clause (verbatim preamble, kill switch,
# merge-from-worktree, disambiguation, contamination check, never-read lists,
# ledger, merged-dependency rule) so a future edit can't silently drop one.
#
# Run: bash scripts/__tests__/dispatch-shape.test.sh

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SKILL="$ROOT/.claude/skills/dispatch/SKILL.md"
CMD="$ROOT/.claude/commands/dispatch.md"
IMPL="$ROOT/.claude/agents/implementer.md"
fails=0

ok()   { echo "ok   — $1"; }
fail() { echo "FAIL — $1"; fails=$((fails+1)); }

has() { # file pattern description
    if grep -q -- "$2" "$1" 2>/dev/null; then ok "$3"; else fail "$3 (missing: $2)"; fi
}

echo "== dispatch layer shape =="

if [ ! -f "$SKILL" ]; then
    echo "FAIL — $SKILL does not exist"; echo "1 FAILURE(S)"; exit 1
fi

# rule-48 preamble embedded VERBATIM (the two load-bearing sentences)
has "$SKILL" "CRITICAL OPERATIONAL — binding" "brief template carries the preamble header"
has "$SKILL" "does NOT set your initial cwd" "preamble carries the harness-cwd warning verbatim"
has "$SKILL" "PR #1029" "preamble names the contamination precedent"

# kill switch + global lock + lock order
has "$SKILL" "dispatch-kill" "kill-switch check present"
has "$SKILL" "agent-lock.sh acquire dispatch" "global dispatch lock acquired by the skill"
has "$SKILL" "tracker-write" "tracker-write lock named"
has "$SKILL" "deps-check.sh" "dependency gate wired"

# lucid-informed integration tail
has "$SKILL" "FROM the lane worktree" "merge runs from the lane worktree"
has "$SKILL" "never pass \`--delete-branch\`" "no --delete-branch clause"
has "$SKILL" "state,mergeCommit" "gh pr view merge disambiguation"
has "$SKILL" "pull --rebase" "pull --rebase before tag"
has "$SKILL" "git log origin/main..main" "committed-contamination detection"
has "$SKILL" "check-write-set.sh" "write-set gate in the tail"
has "$SKILL" "sim-lease.sh" "sim leases wired"

# ledger + scheduling discipline
has "$SKILL" "dispatched → returned → integrating" "ephemeral ledger statuses"
has "$SKILL" "never persisted" "ledger declared ephemeral"
has "$SKILL" "MERGED" "intra-batch dependency = merged, not returned"
has "$SKILL" "vm_stat" "memory-pressure width degrade"
has "$SKILL" "N=1" "single-item inline degrade kept"

# context protection
has "$SKILL" "never read" "never-READ list present"
has "$SKILL" "--name-only" "diff reading capped at --name-only"
has "$SKILL" ".reports/" "overflow channel named"

# version-at-slot
has "$SKILL" "bump_tier" "HANDOFF carries only bump_tier"
has "$SKILL" "never pre-assign" "version-at-slot: no pre-assigned numbers"

# dropped-by-design (replaces M1–M5)
has "$SKILL" "Dropped by design" "dropped-by-design section present"

# command stub
if [ -f "$CMD" ] && grep -q "dispatch" "$CMD" && [ "$(wc -l < "$CMD" | tr -d ' ')" -le 20 ]; then
    ok "commands/dispatch.md is a stub invoking the skill"
else
    fail "commands/dispatch.md stub missing or oversized"
fi

# implementer ladder (probe-shaped: custom agents get NO Skill tool — probed
# 2026-07-09 twice, incl. with Skill in frontmatter; run-codex.sh is PRIMARY)
has "$IMPL" "PROBED 2026-07-09" "implementer records the probe verdict"
has "$IMPL" "run-codex.sh" "implementer names the watchdogged primary rung"
if grep -q "Skill" <<<"$(head -4 "$IMPL")"; then fail "implementer frontmatter lists an ungrantable Skill tool"; else ok "implementer frontmatter honest (no phantom Skill grant)"; fi

echo
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$fails FAILURE(S)"; exit 1; fi
