---
branch: chore/skill-fix-issue-rewrite
threadId: 019df5bc-0283-7ff3-aa70-e5e19384287d
rounds: 2
final_verdict: ship-as-is
date: 2026-05-05
---

# Codex audit: skill rewrite for `.claude/commands/fix-issue.md`

## Scope

Single-file change: `.claude/commands/fix-issue.md` (333 → 533 lines).
Rewrite to align with current `AGENTS.md` + rules 40 (version bump),
47 (feature workflow), 24 (docs sync), and 10 (TDD), and with the
active hooks at `.claude/hooks/check_*.sh`.

## Round 1

Codex returned 6 findings.

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| `fix-issue.md:36–38` | Critical | Reintroduced an opt-out for the feature path ("user explicitly opts out and accepts the gate gap in writing"), contradicting rule 47's "binding for every feature, never skip a gate." | **Fixed**: removed the opt-out entirely. Replaced with hard "Always redirect features to `/feature-workflow`. STOP this pipeline. No user waiver bypasses Gates 2 or 5." |
| `fix-issue.md:397–406` | High | Phase 9 verification-exception evidence file shape was wrong. I claimed `commands_run` lived in frontmatter, but `dev-docs/verification/SCHEMA.md` requires it as the body section `## Commands run`. | **Fixed**: replaced with the actual SCHEMA frontmatter (kind, id, status_target, commit_sha, app_version, date, verifier, device_or_simulator, os_version, build_configuration, backend, result) and added an explicit list of required body sections (`## Acceptance criteria`, `## Commands run`, `## Observations`, `## Artifacts`). |
| `fix-issue.md:461–469` | High | Multi-issue parallel flow allowed each worktree-agent to run its own version bump and (implicitly) its own tag, with the comment "different MARKETING_VERSION values across worktrees are fine." Two parallel branches off the same `main` baseline can pick the same next version, and tagging from worktrees collides on `main`. | **Fixed in two passes**: (round 1) rewrote M3 with three integrator-controlled gates — version bump coordinated, PR merges sequential, tagging single-shot on `main`. (round 2) resolved residual contradiction (see below). |
| `fix-issue.md:136–175` | Medium | Tool names referenced `mcp__codex__codex` and `mcp__codex__codex-reply`, but the installed Codex MCP server in this repo is `mcp__plugin_codex-toolkit_codex__codex` (and `-reply`). Following the skill literally would dead-end. | **Fixed**: `replace_all` swap to the actual installed names. |
| `fix-issue.md:256–259` | Medium | Phase 6 flipped bug rows to `FIXED` after only tests + audit. `docs/bugs.md`'s binding workflow is "Understand → RED → GREEN → REFACTOR → **Verify** → Track" — Verify comes BEFORE Track. For UI/behavioral bugs, this means re-running the original repro is required before the FIXED flip, not deferred to Phase 9. | **Fixed**: inserted Phase 6a "Pre-FIXED verify (mandatory)" with three branches: UI/behavioral bugs re-run original repro on working-tree binary; data/persistence bugs re-run failing scenario; pure-logic bugs are gated by RED→GREEN already. The bug-tracker FIXED flip moved to Phase 6b and is gated on 6a passing. Phase 9 deep verification stays as a separate post-merge close-gate. |
| `fix-issue.md:197–199` | Low | Said audit log "required before Phase 8 (PR creation)." The hook `check_codex_audit_artifact.sh` actually only blocks `gh pr merge`, not `gh pr create`. Misleading. | **Fixed**: reworded to "Required before merge; recommended before PR creation so review sees it." |

## Round 2

After fixes, Codex re-audited via `mcp__plugin_codex-toolkit_codex__codex-reply` on the same thread. 1 residual finding.

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| `fix-issue.md:516–524` | Medium | Internal contradiction in M3: the lead said agents run "Phases 0.5 → 8 (PR creation)" but item 1 said "stops just before Phase 7 and reports 'ready for bump.'" Cannot both be true. | **Fixed**: rewrote M3 lead to "Each worktree-agent runs **Phases 0.5 → 6c only**, then stops and reports 'ready for bump.' The integrator controls everything from Phase 7 onward." Item 1 then describes the resume-through-7→8 sequence. No remaining contradiction. |

## Round 3 (verify only)

Same thread, re-audit after the round-2 fix.

> Final verdict: ship-as-is.
>
> I don't see remaining findings in the revised flow. The original six issues are fixed, and the last multi-issue sequencing contradiction is resolved: agents now stop at `Phase 6c`, and the integrator alone owns `Phases 7 → 9`, which is consistent with the version-bump rule, merge sequencing, and tag/finalizer handling.

## Verdict

**ship-as-is.** Seven findings total across two rounds, all addressed
and re-verified. No code touched (Swift untouched), so the
`check_codex_audit_artifact.sh` hook wouldn't have blocked the merge
anyway — but the audit was run per the user's explicit instruction
that "all the changes need to be audited, not just md files and code
files." This audit log records that the MD-only diff was Codex-audited
to a clean verdict before merge.
