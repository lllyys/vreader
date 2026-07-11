---
title: Decision — six-gate workflow and lane dispatch
updated: 2026-07-10
status: proposed
---

# Decision — six-gate workflow and lane dispatch

## Purpose

Two coupled process decisions govern how ALL code ships in this repo: (1) rule 47's binding six-gate feature workflow (Plan → Independent plan audit → TDD implementation → Implementation audit loop → Device/integration verification → Merge), and (2) rule 55's lane-dispatch contract (feature #130) — the ONLY sanctioned mechanism for multi-item parallel work. Rule 48 decides *when* parallelism is legal; rule 55 defines *how* the machinery works. Bugs skip Gates 1–2 (reactive: Understand → RED → GREEN → REFACTOR → Verify → Track per `docs/bugs.md` rules); this sequence is analogous to, but not literally numbered as, feature Gates 4–6 — Verify and Track carry equivalent independent-audit and verification-before-merge rigor, but the bug close gate and feature Gate 6 are distinct controls, not the same numbered gate.

## The six gates (rule 47, `.claude/rules/47-feature-workflow.md`)

1. **Plan** — `dev-docs/plans/YYYYMMDD-feature-N-<slug>.md` with problem, file-by-file surface area with signatures, prior art/rejected alternatives, WI sequencing, test catalogue, risks, backward compat. Row flips to `PLANNED` only when this exists.
2. **Independent plan audit** — a different agent/model (Codex via `codex exec` today; the invariant is independence, not the brand) verifies model assumptions, edge cases, protocol shapes, concurrency hazards, WI cohesion. Bar: zero open Critical/High/Medium findings; max 3 rounds then escalate. Rationale recorded in the rule: audits routinely catch 5–10 real bugs per round (worked example: feature #46, where round 1 found `Book.originalFilename` doesn't exist).
3. **TDD implementation** — RED→GREEN→REFACTOR per WI (rule 10), one small PR per WI.
4. **Implementation audit loop** — independent audit of the diff, same 3-round bar. Mechanically enforced: the PreToolUse hook `check_codex_audit_artifact.sh` blocks `gh pr merge` for any code-touching branch without `.claude/codex-audits/<branch>-audit.md` carrying `final_verdict: ship-as-is|follow-up-recommended`; `block-recommended` is a hard block. Docs-only PRs escape via the `code_paths_touched` classifier.
5. **Device/integration verification** — foundational WIs need only tests+audit; behavioral WIs need slice verification on the iPhone 17 Pro simulator via the `vreader-debug://` harness (Android WIs: emulator via `scripts/run-android-verify.sh`); the final WI needs a full acceptance pass recorded at `dev-docs/verification/feature-<id>-<YYYYMMDD>.md`. Enforced: `check_terminal_status_evidence.sh` blocks flipping a features row to `VERIFIED` without that evidence file. "Tooling unavailable" is not a deferral reason unless a named tool is confirmed missing.
6. **Merge** — tests green, Gates 4–5 clean, docs sync (rule 24), version bump as the branch's last commit (rule 40), and the referenced row at its merge-eligible status (`FIXED` for bugs, `DONE` for features) — not yet terminal. Post-merge: `DONE` → `VERIFIED` is a separate, later status (the actual terminal one); GH issues close only after verification (the close gate), with gate transitions posted as append-only GH-issue timeline comments.

## Lane dispatch (rule 55 / feature #130, `.claude/rules/55-lane-dispatch.md` + `.claude/skills/dispatch/SKILL.md`)

**Decision**: multi-item fan-out runs exclusively through the `/dispatch` skill. Roles: the **orchestrator** (the invoking session) owns EVERY contended surface — trackers, `docs/architecture.md`, `README.md`, `project.yml`/pbxproj version allocation, `git tag`, `gh pr create/merge` — and runs a serial integration tail; **lanes** (the `implementer` agent, `.claude/agents/implementer.md`) are worktree-isolated, do exactly one work unit, never edit any file via Bash (sed/heredocs dodge the PreToolUse Edit-matcher hooks), and return a strict-JSON **HANDOFF** (id, branch, head_sha, outcome, root_cause, red_test, files_touched, test_result_line, audit{artifact_path, final_verdict, rounds, thread_id}, tracker_edit, docs_sync, bump_tier, blockers — normative JSON Schema embedded in rule 55); the **verifier** agent is a read-only Gate-5 observer that never writes evidence files or flips rows.

Mechanics (all implemented in `scripts/`, see [[Module — automation and tooling]]):
- **Lock order** (total, deadlock-free): `dispatch` (global, via `scripts/agent-lock.sh`) → sim leases (`scripts/sim-lease.sh`, `test` ≤2 / `verify` 1, a UDID never serves both) → id-reserve (`scripts/reserve-id.sh`) → `tracker-write` (short-held). Staleness: steal only on dead pid / PID reuse (`scripts/lib/lock.sh`); `scripts/sweep-ghosts.sh` is the single reaper for dead steal-mutexes, stale leases, and orphaned worktrees.
- **Dependency gate**: nothing spawns that `scripts/deps-check.sh` didn't mark READY (typed `Deps:[bug:#N|feat:#N|gh:#N|design:#N]` tokens; bare `#N` banned).
- **Briefs are generated, never hand-written**, and always embed rule 48's "CRITICAL OPERATIONAL" cwd preamble verbatim — the Agent harness does NOT set a worktree subagent's initial cwd, and PR #1029 (the v3.37.19 hotfix for stray `project.pbxproj` references) plus bug #957's mid-flow self-rescue are the standing precedents. `scripts/__tests__/dispatch-shape.test.sh` statically asserts the skill text still carries the preamble, kill switch, merge-from-worktree, and contamination-check clauses.
- **Integration tail** (serial, per lane): `scripts/check-write-set.sh` (declared write-set + forbidden shared surfaces, fail-closed) → rebase on origin/main → independent re-run of the lane's targeted suite (never trust the HANDOFF's result line) → tracker/docs edits applied by the orchestrator in the worktree under `tracker-write` → **version-at-slot** (rule 40 batch mode: compute X.Y.Z at the merge slot from then-current `project.yml` + latest `v*` tag; lanes only report a `bump_tier`; never pre-assign) → `gh pr create` + `gh pr merge --squash` FROM the worktree (the audit hook resolves paths there; `--delete-branch` is banned in a linked worktree) → tag per PR immediately on its merge commit → lease release + `worktree-teardown.sh`. Contamination checks (main-checkout `git status --porcelain` AND `git log origin/main..main --oneline`) run after each HANDOFF and again pre-PR.
- **Degrades**: N=1 runs inline (under the `dispatch` lock); width 2 → 1 without ~4GB `vm_stat` headroom (weighed per SWIFT lane, not lane count — M-SHAKEDOWN finding); Android items width 1 (no `ANDROID_SERIAL` routing yet); new Swift FILES are not dispatchable in v1 (they need an orchestrator-owned xcodegen regen the lane's gate can't compile) — route inline. Kill switch: `.claude/state/dispatch-kill` disables dispatch instantly.
- **In-lane Gate 4**: `scripts/run-codex.sh` is the PRIMARY audit rung — probed 2026-07-09 twice: custom agents get NO Skill tool in this harness ("Skill exists but is not enabled in this context"), so cc-suite slash-skills are unreachable from a lane.

## Rejected alternatives

- **The pre-#130 fix-issue "Multi-Issue Pipeline" (M1–M5)** — dead by design, per the dispatch skill's "Dropped by design" section: resumable two-way agents (subagents are fire-and-forget), per-WI inline bump/PR by the worktree agent (versions are now orchestrator-allocated at the slot), and un-briefed "the agent has context" spawns (context absorption was its silent failure).
- **Heartbeat-TTL lock stealing** — rejected in `lib/lock.sh`: a live matching owner is never stolen regardless of age; long-held locks are reported, not broken.
- **Priority-based GH mirroring** — rejected in AGENTS.md: mechanical mirroring (every PLANNED feature / every bug) because selective mirroring dropped critical bugs; enforced by `check_gh_issue_mirror.sh`.
- **Skipping the plan audit** — rule 47 names the cost: audit-catchable bugs shift into wasted implementation work.

## Consequences and invariants

- Author/auditor separation is an invariant (rule 47/48): the writer never audits its own work.
- One writer per file/area; cross-platform write isolation (iOS agents never touch `android/` and vice versa, rule 48; `check-write-set.sh`'s `CHECK_LANE_PLATFORM` mechanizes it).
- A disobedient lane costs a redone lane, never a corrupted main — lanes cannot merge; the write-set gate plus contamination checks are the detection layer.
- The `dispatch` lock releases BEFORE Gate-5 verification, letting the next batch's Gate-3 lanes overlap a Gate-5 pass (rule 48's decision matrix row).
- Cron autonomy rides the same rails: the bugfix cron cut over to `/dispatch` in feature #130 WI-7 (PR #1897); the feature cron self-gates on ≥3 proven `ENDED work_done dispatch-mode` bugfix iterations before routing WIs through dispatch.

## History

Rule 47's worked example is feature #46 (WebDAV materializing restore, 11 WIs, 2 Codex plan-audit rounds). Feature #130 landed via PRs #1886 (Gate-2-clean plan), #1887 (WI-1 hygiene + lock/reserve-id), #1888 (WI-2 Deps token + deps-check), #1889 (WI-3 locks/leases/worktrees/write-set gate/sibling-safe watchdog), #1893 (WI-4 /dispatch, canary-proven), #1895 (M-SHAKEDOWN Lane B), #1896 (WI-5 cleanup — deleted the seven vmark-era role agents, leaving only `implementer` and `verifier`), #1897 (WI-7 cron cutover), #1899 (Gate-5b acceptance evidence, row VERIFIED). Shaping precedents: PR #1029 / bug #957 / bug #241 (worktree cwd contamination class), bugs #353/#360/#361 (hook fail-closed hardening), the 2026-05-10/-31/-06-01 ghost incidents (rules 49/52/53) and the 2026-06-28 comment-lure attack (rule 54 quarantine now embedded in the bugfix cron's scope guardrail).

**Sources.** [[session 014jggU2u3f3t6YRoPLS457u · 2026-07-10]] · [[session 014jggU2u3f3t6YRoPLS457u-audit · 2026-07-11]]
