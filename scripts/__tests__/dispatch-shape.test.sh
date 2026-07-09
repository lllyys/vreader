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

# Gate-4 R1 operational invariants (audit thread 019f4467)
has "$SKILL" "git -C <worktree> commit" "tail tracker/docs edits committed ON the lane branch"
has "$SKILL" "as the branch's LAST commit" "bump is the branch's last commit, in the worktree"
has "$SKILL" "after EACH successful merge" "tags are per-PR, never batch-end"
has "$SKILL" "EVERY non-ready outcome" "one cleanup routine for all failure exits"
has "$SKILL" "while still holding the \`dispatch\` lock" "inline fallbacks run under the dispatch lock"
has "$SKILL" "worktree-teardown.sh <id> --delete-branch" "post-merge branch deletion via teardown flag"
# ordering: the contamination check must be defined for use BEFORE the merge
# (validation-time + pre-PR assertion) — assert both call sites exist
CONTAM_VALIDATION=$(grep -n "HANDOFF validation + contamination check" "$SKILL" | head -1 | cut -d: -f1)
CONTAM_PREPR=$(grep -n "second contamination check" "$SKILL" | head -1 | cut -d: -f1)
MERGE_LINE=$(grep -n "gh pr merge --squash" "$SKILL" | head -1 | cut -d: -f1)
if [ -n "$CONTAM_VALIDATION" ] && [ -n "$CONTAM_PREPR" ] && [ -n "$MERGE_LINE" ] \
   && [ "$CONTAM_VALIDATION" -lt "$MERGE_LINE" ] && [ "$CONTAM_PREPR" -lt "$MERGE_LINE" ]; then
    ok "contamination checks precede the merge (lines $CONTAM_VALIDATION,$CONTAM_PREPR < $MERGE_LINE)"
else
    fail "contamination-check ordering (validation=$CONTAM_VALIDATION prePR=$CONTAM_PREPR merge=$MERGE_LINE)"
fi

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

# rule-55 HANDOFF schema block: must parse as JSON, patterns anchored,
# widened classes present (WI-5 audit: an edit here could false-green)
RULE55="$ROOT/.claude/rules/55-lane-dispatch.md"
SCHEMA_JSON="$(awk '/^### Normative JSON Schema/,0' "$RULE55" | awk '/^```json$/{f=1;next} /^```$/{f=0} f')"
if printf '%s' "$SCHEMA_JSON" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
    ok "rule-55 normative schema block parses as JSON"
else
    fail "rule-55 normative schema block is not valid JSON"
fi
if printf '%s' "$SCHEMA_JSON" | grep -q '"pattern": "\^(RUN-(TESTS|ANDROID-TESTS) RESULT:\.\*|ALL PASS)\$"'; then
    ok "test_result_line pattern is anchored (no over-match)"
else
    fail "test_result_line pattern missing or unanchored"
fi
has "$RULE55" "chore:\[a-z0-9\]\[a-z0-9-\]\*" "HANDOFF id accepts the chore class"
has "$RULE55" '"notes"' "HANDOFF schema carries the optional notes field"
has "$RULE55" "NOT dispatchable in v1" "new-Swift-file lanes forbidden in v1 (route inline)"
has "$SKILL" "No new Swift files in a lane" "skill eligibility mirrors the new-file prohibition"

# WI-6 standing probe: hello-lane.js meta must stay literal + named
HELLO="$ROOT/.claude/workflows/hello-lane.js"
if [ -f "$HELLO" ] && grep -q "^export const meta" "$HELLO" \
   && grep -q "name: 'hello-lane'" "$HELLO" && grep -q "description:" "$HELLO"; then
    ok "hello-lane.js standing probe present with literal meta"
else
    fail "hello-lane.js probe missing or meta malformed"
fi

# WI-7 cron cutover: the four prompts must keep their load-bearing clauses
BUGFIX="$ROOT/.claude/cron-prompts/bugfix.md"
FEATURE="$ROOT/.claude/cron-prompts/feature.md"
VERIFY="$ROOT/.claude/cron-prompts/verify.md"
WATCHDOG="$ROOT/.claude/cron-prompts/watchdog.md"
has "$BUGFIX" "agent-lock.sh acquire cron-bugfix" "bugfix cron takes its reentry lock"
has "$BUGFIX" "dispatch-kill" "bugfix cron honors the kill switch"
has "$BUGFIX" "agent-lock.sh acquire dispatch" "kill-switch inline fallback takes the global dispatch lock"
has "$BUGFIX" "dispatch-inline-mode" "bugfix cron distinguishes the N=1 inline degrade from a true lane run"
has "$BUGFIX" "no-dispatch" "bugfix cron has a mode token for pre-dispatch exits"
has "$BUGFIX" "scan-untrusted-content.sh" "bugfix cron keeps rule-54 comment scanning"
# the self-gate pattern must exist VERBATIM in both files (feature greps what bugfix logs)
if grep -qF 'ENDED work_done dispatch-mode' "$BUGFIX" && grep -qF 'ENDED work_done dispatch-mode' "$FEATURE"; then
    ok "self-gate grep pattern identical across bugfix/feature prompts"
else
    fail "self-gate pattern mismatch between bugfix.md and feature.md"
fi
has "$FEATURE" "agent-lock.sh acquire cron-feature" "feature cron takes its reentry lock"
has "$FEATURE" "dispatch-inline-mode" "feature cron is honest about the N=1 degrade"
has "$VERIFY" "sim-lease.sh acquire verify" "verify cron leases the verify sim"
has "$VERIFY" "tracker-write" "verify cron scopes tracker-write around row flips"
has "$VERIFY" "reserve-id.sh bug" "verify cron mints IDs atomically"
has "$WATCHDOG" "sweep-ghosts.sh" "watchdog runs the single reaper"

# implementer ladder (probe-shaped: custom agents get NO Skill tool — probed
# 2026-07-09 twice, incl. with Skill in frontmatter; run-codex.sh is PRIMARY)
has "$IMPL" "PROBED 2026-07-09" "implementer records the probe verdict"
has "$IMPL" "run-codex.sh" "implementer names the watchdogged primary rung"
if grep -q "Skill" <<<"$(head -4 "$IMPL")"; then fail "implementer frontmatter lists an ungrantable Skill tool"; else ok "implementer frontmatter honest (no phantom Skill grant)"; fi

echo
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$fails FAILURE(S)"; exit 1; fi
