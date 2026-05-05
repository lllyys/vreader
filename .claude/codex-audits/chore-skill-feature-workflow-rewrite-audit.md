---
branch: chore/skill-feature-workflow-rewrite
threadId: 019df5d4-4497-7fa0-a05e-28f6d1bbd4ed
rounds: 3
final_verdict: ship-as-is
date: 2026-05-05
---

# Codex audit: skill rewrite for `.claude/commands/feature-workflow.md`

## Scope

Single-file change: `.claude/commands/feature-workflow.md` (62 → 580+
lines). Rewrite to align with `.claude/rules/47-feature-workflow.md`'s
binding 6-gate sequence + rules 40 / 24 / 10 / 48, AGENTS.md close gate,
and the active hooks at `.claude/hooks/check_*.sh`.

## Round 1

5 findings.

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| `feature-workflow.md:449` | Critical | Gate 6 said every WI PR uses `Refs #N` and may merge while feature row is `IN PROGRESS`. Contradicts AGENTS.md merge gate ("a PR that references an open feature does not merge until the feature reaches `DONE`"). | **Fixed**: split reference convention — intermediate WI PRs use plain prose `Part of feature #N`; only the final WI uses `Refs #N` because that PR is the one that brings the feature to `DONE`. Updated PR body template + Type-of-Change line. |
| `feature-workflow.md:393` | Critical | Gate 5 / Gate 6 sequencing impossible for final WI: Gate 6 required Gate 5 verification before merge, but the SCHEMA evidence file requires `commit_sha` of the merge commit on `main` — which doesn't exist pre-merge. Chicken-and-egg. | **Fixed**: split Gate 5 into 5a (pre-merge slice per WI, recorded in PR description, no evidence file required) and 5b (post-merge final acceptance, only after final WI's PR merges, with merge-commit SHA in evidence file). Gate 6 merge requirements now reference 5a only. Status transitions updated: final WI merges → DONE; 5b evidence file with `result: pass` lands → VERIFIED. |
| `feature-workflow.md:14` | Medium | Doc claimed each gate has all 5 fields explicitly (required artifact / owner-auditor / status transition / blocking hook / exit criteria), but Gates 3, 5, 6 had them only implicitly. | **Fixed in two passes**: round 1 added the structural section; round 2 added uniform `\| Field \| Value \|` summary tables at the top of every gate (1, 2, 3, 4, 5, 6). |
| `feature-workflow.md:330` | Medium | Version-bump rule was ambiguous for non-final behavioral WIs (only specified `minor` for final and `patch` for foundational). | **Fixed**: added deterministic table — foundational and behavioral-but-not-final WIs use `patch`; only the final WI uses `minor` (or `major` for breaking changes). |
| `feature-workflow.md:467` | Low | `git tag` block under Gate 6 implied tagging every WI merge but didn't explain why. | **Fixed**: clarified — every PR carries a mandatory version bump per rule 40, so every merge gets its own tag. |

## Round 2

After fixes. 2 residual findings.

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| `feature-workflow.md:14` | Medium | Structural template still not 1:1 — Gates 3, 5, 6 had narrative coverage of the 5 fields but no uniform labeled table. | **Fixed**: added `\| Field \| Value \|` summary tables at the top of every gate (1, 2, 3, 4, 5, 6) with the five labeled fields. |
| `feature-workflow.md:390` | Low | PR template's Gate 5 section still said "pointer to evidence file path" for the final WI, but after the 5a/5b split that file doesn't exist pre-merge. Invited the wrong behavior in the exact case I just fixed. | **Fixed**: changed to "Gate 5a Verification (per-PR slice — pre-merge)" with explicit final-WI instruction "pre-merge slice with `5b post-merge evidence file pending`". |

## Round 3 (verify only)

Same thread, after the round-2 fixes.

> Final verdict: clean.
>
> The six gates now have the explicit summary tables you were aiming for, the Gate 5a/5b split is consistent with SCHEMA.md, the /fix-issue Gate 4 mechanics are aligned, and the PR template no longer implies a pre-merge evidence file for the final WI. I do not see any remaining contradictions with rule 47, rule 48, rule 40, rule 24, rule 10, AGENTS.md, or the active hooks.

## Verdict

**ship-as-is.** Seven findings total across two rounds, all addressed
and re-verified. The rewrite was the same shape as the recent
`fix-issue.md` rewrite (PR #237) and is now consistent with that
skill's Gate 4 + post-merge close-gate mechanics. Per the user's
explicit instruction "all the changes need to be audited, not just md
files and code files" — this audit covers the full diff (single MD
file).
