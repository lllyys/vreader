# Feature #130 — Parallel agent-lane harness (thin orchestrator + leased-spoke fan-out)

Redesign the agent/skill execution layer so bug fixes and feature WIs can fan out in
parallel inside **worktree-isolated subagent lanes** while the invoking session stays a
**thin orchestrator** that owns every contended surface. Adds machine-readable
dependencies (typed `Deps:[…]` token), per-WI machine-readable Spec blocks (the SDD+TDD
combination), resource leases (simulators, generic agent locks, build-daemon safety),
and a dispatch layer (`/dispatch` skill). No app code is touched.

> **Rule 51 scope note**: this feature is entirely CLI / config / hooks / scripts /
> skill-markdown — no user-visible UI surface. Rule 51 does not apply (explicitly listed
> out-of-scope categories).

> **Cron guard**: at the Gate-2 → `PLANNED` flip, the feature row is filed with a
> "cron: skip — interactive session owns this (harness self-modification)" note in its
> Notes cell. The autonomous crons must NOT pick this feature up: it rewrites the crons'
> own prompts and the skills they execute, and mid-flight self-modification is an
> unbounded failure mode. The owner's interactive session is the single writer for all
> WIs. (The row does not exist while this plan is under Gate-2 audit — filing the row IS
> the PLANNED flip, per rule 47.)

## Problem

An audit of the execution layer (2026-07-08, 6-reader + 3-lens workflow run) found:

1. **Everything runs inline.** `/fix-issue` (9 phases) and `/feature-workflow` (6 gates)
   execute entirely in the invoking session — diffs, RED/GREEN iterations, multi-round
   Codex audit output, test logs, and sim transcripts all accumulate in one context. The
   only isolation in use is the external `codex exec` process.
2. **The 9 `.claude/agents/*.md` definitions are unused and mostly broken.** Nothing
   invokes them (zero references across skills/commands/cron-prompts). They were
   bulk-copied from the vmark project (mtime Jun 19 20:34); several still reference
   vmark internals. `implementer.md` lacks the `Write` tool (fatal for its own RED-first
   mandate), `planner.md` is read-only yet its output requires writing plan files,
   `test-runner.md` has no YAML frontmatter at all. Only `verifier.md` (fully) and
   `test-runner.md`'s §0.0 (partially) were ever vreader-adapted.
3. **The multi-issue mode of `/fix-issue` is not executable as written.** It presumes
   resumable two-way agents ("integrator resumes each worktree-agent through Phases
   7→8") — the Agent primitive is fire-and-forget. It never specifies spawn mechanics or
   the rule-48 cwd preamble (PR #1029 contamination class).
4. **Zero dependency awareness at dispatch time.** Dependencies are free-text in Notes
   cells (`Depends on #44`, `HARD-BLOCKED on feature #58's … (#58 WI-6)`) with a 4-way
   ambiguous `#N`. Rule 48 hard rule 2 ("hard dependency blocks downstream Gate 3") has
   no mechanical enforcement.
5. **Latent hazards baked into skill bodies**: Phase 5 / Gate 3c embed bare
   `xcodebuild test` (violates rule 52 — no watchdog, full >20-min suite as a per-WI
   gate); the `.claude/skills/` and `.claude/commands/` copies of both pipelines
   (~600 lines each) have drifted (the command copies carry the #107 platform-routing
   section; the skill copies don't); `check_audit_debt.sh` scans only the last 5 commits
   so a merged batch outruns it; the tracker row-ID allocation race is documented
   (memory: "the cron races on tracker IDs") but unfixed.

## Goals / non-goals

**Goals**: (a) up to 2 concurrent work lanes with disjoint write-sets, each in its own
worktree + leased simulator; (b) invoking-session context reduced to dispatch state +
~1 KB structured returns; (c) machine-readable dependency gating before any spawn;
(d) spec-as-brief-contract so lanes are self-contained (no context absorption);
(e) all existing gates/hooks keep enforcing under delegation (see "Hook model" below).

**Non-goals**: >2 build lanes (16 GB / 10-core ceiling); a merge-queue daemon (serial
integration tail is the accepted cap); a sidecar dependency file (`graph.yml` — rejected,
see below); an external SDD toolchain; changing TDD discipline (rule 10) or any gate
semantics (rule 47); **Android lane fan-out** (deferred — `run-android-tests.sh` has no
`ANDROID_SERIAL` routing and `emulator_online()` grabs any device; until a serial-aware
emulator lease lands as a named follow-up, `android-app`/`android-spike` items dispatch
at width 1 only); persistent warm worktree slots (deferred optimization — v1 uses
ephemeral worktrees with the existing M5 teardown pattern); WI-level dependency EDGES in
the Deps token (see "Dependency representation" — WI ordering lives in the plan's Spec
blocks, the only canonical WI source).

## Prior art / project precedent / rejected alternatives

**Building on (existing, proven)**:
- The fix-issue **M3 integrator pattern** (sequential version assignment after parallel
  work; sequential rebase-before-merge; single tag pass) — promoted from "multi-issue
  mode prose" to the universal integration tail.
- **Rule 48's decision matrix** already legalizes exactly the parallelism used here
  (disjoint-file Gate 3s in worktrees, parallel Gate-2/4 Codex audits, Gate 5 ∥ Gate 3 on
  different resources) and mandates the six-field subagent contract + cwd preamble.
- `scripts/run-tests.sh` **already supports `TEST_UDID`** — the sanctioned multi-sim path
  (rule 52). Simulator capacity is discovered dynamically at lease time
  (`xcrun simctl list -j devices available`) — never a hardcoded count.
- The **watchdog-wrapper pattern** (`run-tests.sh`, `run-codex.sh`, `sweep-ghosts.sh`):
  every new long-runner/lease primitive follows it (single RESULT line, exact-pid waits,
  rule 49/53 compliance).
- Hook test conventions: `.claude/hooks/__tests__/*.test.sh`, `scripts/__tests__/*.test.sh`.
- Codex audits run through **cc-suite** (`/cc-suite:audit`, `/cc-suite:review-plan`,
  job-tracked runner); `scripts/run-codex.sh` stays the raw fallback (rule 53).
- Claude Code **Workflow tool** (deterministic JS orchestration): exists and was
  exercised in the planning session itself (9-agent run `wf_db1871f2-c76`), but has NO
  repo precedent and unproven availability in cron-fired sessions — therefore demoted to
  an **optional WI gated on a runtime-proof acceptance** (see WI-6), never a load-bearing
  dependency of the dispatch path.

**Rejected alternatives**:
- **Sidecar dependency DAG file** (`docs/graph.yml` / `docs/deps.yml`): two sources of
  dependency truth WILL drift. Chosen instead: a typed token at the head of the existing
  Notes cell — single source of truth stays the tracker row.
- **External SDD toolchain** (spec-kit-style `specs/` tree): duplicates the Gate-1 plan
  artifact, adds a second contended doc surface, and re-fights the existing hook
  enforcement. The Gate-1 plan already IS the spec; we make it machine-readable instead.
- **Merge-queue daemon / >2 lanes / persistent worktree slots / JS-first dispatch**:
  over-engineering at the current scale; each is a named deferred follow-up, not a
  hidden assumption.
- **Lanes writing trackers/versions themselves**: shared-surface writes are
  orchestrator-only — see "Hook model" for the precise (corrected) rationale.

## Hook model (what actually enforces, where)

Corrected per Gate-2 round-1 audit — the naive claim "hooks only fire in the main
session" is wrong:

- The project's PreToolUse hooks (`check_terminal_status_evidence.sh`,
  `check_gh_issue_mirror.sh` on `Edit|Write|MultiEdit`; `check_codex_audit_artifact.sh`
  on `Bash`) are wired in `.claude/settings.json` and fire on matching TOOL calls in
  ANY session working in this project — including lane subagents.
  `check_codex_audit_artifact.sh` is already worktree-aware (resolves cwd from the
  PreToolUse payload).
- **The real bypass is Bash-mediated file edits** (`sed`/`python` heredocs), which no
  PreToolUse Edit-matcher sees, plus Stop-hook state derived from the main checkout.
- Therefore the binding rules are: (1) tracker/docs/rules edits use the Edit/Write
  tools, never Bash — everywhere, orchestrator and lanes alike; (2) shared-surface
  writes are **orchestrator-only** anyway — not because hooks wouldn't fire in lanes,
  but for single-writer serialization (rule 48) and deterministic integration ordering;
  (3) `check-write-set.sh` at integration is the trust-but-verify detection layer for a
  lane that disobeys; (4) a VERIFIED flip is performed where the evidence file exists
  relative to the edited tracker (the evidence-hook derives paths from the edited file's
  location), i.e. on the branch that carries the evidence file.

## Architecture (target state)

```
owner / cron prompt
      │
      ▼
ORCHESTRATOR (main session; loads only the ~150-line dispatch skill)
  0. kill-switch check (.claude/state/dispatch-kill present ⇒ refuse, inline mode only)
     + acquire the GLOBAL dispatch lock (scripts/agent-lock.sh acquire dispatch)
     — one orchestrator per repo at a time, interactive or cron alike
  1. candidate intake (issue list / tracker rows / plan WIs)
  2. scripts/deps-check.sh per candidate  → READY / BLOCKED(blockers)
  3. write-set overlap check              → overlapping pairs serialize
  4. per dispatched item:
       scripts/worktree-setup.sh <id>     → .claude/worktrees/<id>, branch off main
       scripts/sim-lease.sh acquire test  → TEST_UDID for the lane
       spawn lane subagent (Agent tool, worktree isolation) with templated brief:
         rule-48 cwd preamble (verbatim) + six-field contract + Spec/micro-spec
         + leased UDID + FORBIDDEN paths + HANDOFF schema
  5. lanes (≤2 concurrent; width 1 unless memory headroom): repro →
     RED/GREEN/REFACTOR → in-lane Codex audit loop (cc-suite runner or
     scripts/run-codex.sh fallback; artifact committed on branch) → targeted test gate
     via scripts/run-tests.sh TEST_UDID=<leased> → commit code+tests+audit artifact →
     return structured HANDOFF (~1 KB). Lanes NEVER touch: docs/bugs.md,
     docs/features.md, docs/architecture.md, README.md, project.yml, pbxproj,
     git tag, gh pr create/merge — and never edit ANY file via Bash.
  6. integration tail (orchestrator, strictly serial per returned lane, ordered so
     that any failure before PR-open leaves ZERO shared-surface changes):
       a. scripts/check-write-set.sh <worktree> <declared-prefixes>
       b. rebase branch on origin/main   — conflict ⇒ RECOVERY (below), no state leaked
       c. independent re-run of the lane's declared targeted suite (run-tests.sh)
       d. tracker flip + docs sync via Edit tool (under the short `tracker-write`
          lock), committed on the branch
       e. allocate next version (sequential, merge order) → bump + xcodegen, commit
       f. gh pr create (HANDOFF as body) → hook-gated squash merge → tag
       g. lane cleanup — runs on EVERY lane exit path (success, invalid-HANDOFF
          requeue, rebase-abandon, escalation): release the lane's test sim lease +
          scripts/worktree-teardown.sh (M5 DerivedData sweep). Step 6c's independent
          re-test REUSES the lane's still-held test lease (the orchestrator inherits
          it when the lane returns — no second acquire); a requeued redo re-acquires
          fresh. A batch ends with `sim-lease.sh status` showing zero held leases.
  7. release the GLOBAL `dispatch` lock — it covers dispatch + integration ONLY
     (through merge/tag/teardown). Gate-5 verification runs OUTSIDE it: serial, on the
     dedicated verify-sim lease, with tracker/evidence finalization edits under the
     short `tracker-write` lock. This is what lets the NEXT batch's Gate-3 lanes start
     while Gate 5 runs (rule 48 matrix row "Gate 5 + Gate 3").
  8. report per-lane outcomes + measured wall-clock.
```

**Rebase-conflict recovery (step 6b)**, defined: `git rebase --abort`; the lane's branch
is left intact; the item is requeued for **serialized redo** — a fresh lane brief
containing "rebase onto current main and resolve conflicts" (re-brief-once, rule 48); if
the redo also fails, collapse to orchestrator-inline handling. Because version
allocation (6e) and PR creation (6f) happen only AFTER a clean rebase + re-test, a
conflict burns no version number, opens no PR, and touches no tracker. Failure between
PR-open and merge ⇒ close the PR with a comment and requeue. Failure at merge (hook
block) ⇒ leave the PR open and escalate to the owner.

## Lock model (total order — deadlock-free by construction)

Three lock classes, with a **total acquisition order**; locks are acquired only in this
order and `tracker-write` is never held while acquiring anything else:

```
dispatch  →  sim leases  →  id-reserve  →  tracker-write
(global,     (per-UDID,     (leaf: inside    (short-held: ANY shared tracker/docs
 long-held)   medium-held)   reserve-id.sh)   finalization edit, by anyone)
```

`id-reserve` is `reserve-id.sh`'s internal lock — a self-contained leaf acquired and
released within the call. The binding rule it adds: **all new row IDs are minted
BEFORE acquiring `tracker-write`** (calling reserve-id.sh while holding
`tracker-write` is forbidden). The verify flow satisfies this naturally: observations
complete first, the bug list is known, IDs are minted, THEN `tracker-write` is taken
for the edit pass.

- **`dispatch`** — one orchestrator per repo (interactive or cron). Owned and acquired
  by the `/dispatch` skill itself at step 0. **Cron prompts acquire ONLY their
  `cron-<kind>` reentry lock and then invoke `/dispatch`** — they never pre-acquire the
  global lock (that was a self-deadlock: `agent-lock.sh` is non-reentrant by design).
- **sim leases** — as specified in WI-3; `test` and `verify` purposes never share a UDID.
- **`tracker-write`** — serializes every shared-surface edit (docs/bugs.md,
  docs/features.md, docs/architecture.md, README.md) across ALL writers: the
  orchestrator's integration-tail step 6d (legal: it already holds `dispatch`, order
  preserved) and the verify flow's finalization (evidence commit, VERIFIED flips, GH
  closes). The verify flow completes its sim observations FIRST, then takes
  `tracker-write` with a bounded wait — a `tracker-write` holder never acquires a sim
  lease or `dispatch`, so no cycle exists.

**Staleness (all locks/leases, incl. reserve-id)**: the owner record stores `pid`,
`pid start-time` (`ps -p PID -o lstart=`), `host`, `created-at`. Steal ONLY when the
pid is dead OR its start-time mismatches the record (PID-reuse guard). **A live
matching owner is NEVER stolen, regardless of age** — no heartbeat-TTL stealing (a TTL
would either need an unspecified heartbeat updater or steal from long-but-healthy
runs). Long-held locks (>2 h) are REPORTED by `sweep-ghosts.sh` for operator attention,
never auto-stolen; the kill switch + manual reap remain the override for a genuinely
hung holder.

Concurrency budget (honest): 2 build/test lanes + 1 external Codex lane + the
orchestrator. The dispatcher **starts at width 1 and opens the second lane only when**
free memory allows (`vm_stat` check) — and the WI-4 shakedown records measured
wall-clock so the 2-lane benefit is demonstrated, not asserted. Context isolation is the
unconditional win regardless of speedup.

## Dependency representation (typed Deps token)

Codified in both trackers' `## Rules` (WI-2):

- Notes cell HEAD may carry `Deps:[<edge>, …]` where `<edge>` ∈
  `bug:#N` | `feat:#N` | `gh:#N` | `design:#N`. (**No WI-level edges in v1** — WI
  ordering/fan-out lives in the plan doc's Spec blocks, which are the only canonical WI
  status source; a cross-feature dependency on a specific WI is expressed as `feat:#N`
  (whole feature) until a machine-readable WI ledger exists — named follow-up.)
- **Current edges only** — resolved/historical dependency prose moves to the GH issue
  timeline. Strict parsing applies ONLY inside the `Deps:[…]` brackets (bare `#N` there
  is an error); legacy free-text prose elsewhere in Notes is untouched and produces
  **lint warnings, never hard failures** (migration-friendly).
- Readiness resolution (`scripts/deps-check.sh`): `bug:#N` requires status FIXED (or
  terminal WONT FIX/DUPLICATE ⇒ warn + treat as resolved), `feat:#N` requires
  DONE|VERIFIED, `design:#N` requires a committed bundle (row no longer carries
  `BLOCKED: needs-design`), `gh:#N` requires the GH issue closed.
- Absent token ⇒ READY (with a `no-deps-token` info line so silence is visible).
- Migration (WI-2): a **mechanical recount** of non-terminal rows in BOTH trackers is
  run at WI-2 time (`deps-check.sh --lint` output committed in the PR body) and every
  non-terminal row's free-text dependencies are migrated to tokens in that PR.
  2026-07-08 snapshot (exact row counts intentionally omitted — the WI-2 recount is
  the authoritative one): **zero non-terminal bug rows**; **exactly 4 non-terminal
  feature rows** (#68 DONE, #102 DONE, #110 program driver, #129 in flight) — so the
  token migration is a four-row edit. Separately, bugs.md carries **~119 stale
  Open-Bug-Detail entries** for already-terminal rows — that reconciliation is
  EXPLICITLY OUT OF #130's SCOPE (it would dominate WI-2's diff in a contended file);
  it is filed as an independent tracker-hygiene chore at the PLANNED flip, and #130's
  WIs never edit those entries.

## Spec blocks (the SDD+TDD combination)

Gate-1 plans gain a **mandatory per-WI machine-readable Spec block** (fenced ```yaml)
with: `id`, `tier` (foundational|behavioral), `depends` (WI ids and named `M-*`
milestones — a milestone is ready when its evidence artifact exists, e.g.
`M-SHAKEDOWN` ⇒ `dev-docs/verification/feature-130-*.md` with `result: pass`),
`writes` (path prefixes/files), `tests` (named test files/suites), `acceptance`
(criterion list). The block drives four things: (1) the lane's self-contained brief,
(2) WI-level fan-out predicate (`depends` + disjoint `writes`), (3) the auto-generated
allowed-writes contract enforced by `check-write-set.sh`, (4) the exact targeted suite
both the lane AND the orchestrator's independent re-test run (never the >20-min full
suite — rule 52 Cause C). TDD stays the unchanged inner loop; the spec supplies RED.
Bugs stay spec-light: the brief carries a micro-spec (repro + expected-vs-actual +
regression-test name) — same contract shape, no new ceremony.

## HANDOFF schema (lane → orchestrator return)

Defined normatively in rule 55 (WI-2) as a JSON Schema + a STRICT-JSON example (the
schema, not this summary, is authoritative). Field semantics: `id` = the dispatched
item (`bug:#N` / `feat:#N/WI-k`); `outcome` ∈ `ready-for-integration | blocked |
failed`; `root_cause` + `red_test` + `audit` required when `outcome` is ready;
`files_touched` must ⊆ the declared write-set; `test_result_line` is the verbatim
wrapper RESULT line; `tracker_edit` is the EXACT proposed row mutation; `bump_tier` ∈
rule-40 tiers; non-empty `blockers` explains a blocked outcome. Strict-JSON example:

```json
{
  "id": "bug:#361",
  "branch": "fix/issue-361-slug",
  "head_sha": "abc1234def",
  "outcome": "ready-for-integration",
  "root_cause": "one line",
  "red_test": "vreaderTests/FooTests/test_bar",
  "files_touched": ["vreader/Services/Foo/Bar.swift", "vreaderTests/Services/Foo/BarTests.swift"],
  "test_result_line": "RUN-TESTS RESULT: SUCCEEDED (vreaderTests/FooTests)",
  "audit": {
    "artifact_path": ".claude/codex-audits/fix-issue-361-slug-audit.md",
    "final_verdict": "ship-as-is",
    "rounds": 1,
    "thread_id": "uuid"
  },
  "tracker_edit": {
    "file": "docs/bugs.md",
    "row_id": 361,
    "status_to": "FIXED",
    "notes_append": "root cause + fix pointer"
  },
  "docs_sync": { "needed": false, "files": [], "proposed_lines": [] },
  "bump_tier": "patch",
  "blockers": []
}
```

Orchestrator behavior: validate against the schema; **invalid or missing HANDOFF = lane
failure** (item requeued once, then escalated). The HANDOFF doubles as the PR body and
the GH gate-timeline comment.

## Surface area (file-by-file)

### WI-1 — hygiene (no architecture change, no deletions)

- `.claude/skills/fix-issue/SKILL.md` — CHANGE: absorb the newer command copy's
  "Platform routing (feature #107)" section (single-source); replace Phase 5's bare
  `xcodebuild test` with `scripts/run-tests.sh` + **targeted `-only-testing` suites**
  chosen from the fix's touched areas (full suite stays a periodic/CI sweep); note
  `TEST_UDID` as the parallel-lane mechanism. The Multi-Issue M1–M5 section gets a
  banner: "scheduled for replacement by /dispatch (feature #130 WI-4); do not
  hand-execute M1–M5's agent-resume steps — they are not executable (fire-and-forget)".
- `.claude/commands/fix-issue.md` — CHANGE: reduce to a ~10-line stub that invokes the
  skill (kills two-copy drift permanently). Same for
  `.claude/commands/feature-workflow.md`.
- `.claude/skills/feature-workflow/SKILL.md` — CHANGE: absorb command-copy drift;
  replace Gate 3c raw `xcodebuild` with `scripts/run-tests.sh` + targeted suites.
- `.claude/agents/implementer.md` — REWRITE for vreader (it is broken today — missing
  Write): frontmatter `tools: Read, Write, Edit, Bash, Grep, Glob`; body = rule-48
  six-field contract, the verbatim rule-48 cwd-preamble slot, `scripts/run-tests.sh`
  mandate, forbidden-paths list, "no Bash file edits", stop condition
  "ready-for-integration + HANDOFF".
- `.claude/agents/verifier.md` — CHANGE: keep (already vreader-adapted); add the
  six-field contract, sim-lease input, stop condition, and "returns structured
  observations only — never writes evidence files or flips rows (the orchestrator
  does)".
- **Deletion of the 7 dead agents is DEFERRED to WI-5** (post-dispatch-proof) — audit
  finding D5#2: don't remove surfaces before the replacement path exists.
  `test-runner.md`'s vreader-adapted §0.0 routing content is folded into rule 55 / the
  dispatch skill before its file is deleted.
- `.claude/hooks/check_audit_debt.sh` — CHANGE: `git fetch origin main` (best-effort,
  bounded) first; scan merge commits **since the last version tag** instead of the last
  5 commits.
- `scripts/lib/lock.sh` — NEW: the ONE sourceable mkdir-atomic lock helper
  (`lock_acquire <dir>` / `lock_release <dir>` / staleness = pid + start-time, live
  matching owner never stolen — the full rule in "Lock model" above). macOS ships NO
  `flock(1)` (verified: only `shlock` + python `fcntl`); mkdir-atomicity is the one
  idiom shared by every lock primitive in this plan. WI-3's `agent-lock.sh` and
  `sim-lease.sh` reuse this helper (WI-3 therefore depends on WI-1).
- `scripts/reserve-id.sh` — NEW: `reserve-id.sh {bug|feature}` prints the next row ID
  atomically via `lib/lock.sh` on `docs/.id-locks/<kind>.lock.d`.
  ID = max(max ID parsed from the tracker, counter file) + 1, persist counter. The
  counter + lock dirs are LOCAL STATE, not tracked: this WI adds `docs/.id-locks/` and
  `docs/.id-counters/` to `.gitignore` (runtime paths are ignored in the same WI that
  creates them — audit finding R2#5). Trackers' `## Rules` gain one line: "IDs come
  from scripts/reserve-id.sh".
- `scripts/__tests__/reserve-id.test.sh` — NEW;
  `.claude/hooks/__tests__/check_audit_debt.test.sh` — NEW.

```yaml
id: WI-1
tier: foundational
depends: []
writes:
  - ".claude/skills/fix-issue/SKILL.md"
  - ".claude/skills/feature-workflow/SKILL.md"
  - ".claude/commands/fix-issue.md"
  - ".claude/commands/feature-workflow.md"
  - ".claude/agents/implementer.md"
  - ".claude/agents/verifier.md"
  - ".claude/hooks/check_audit_debt.sh"
  - ".claude/hooks/__tests__/check_audit_debt.test.sh"
  - "scripts/lib/lock.sh"
  - "scripts/reserve-id.sh"
  - "scripts/__tests__/lock.test.sh"
  - "scripts/__tests__/reserve-id.test.sh"
  - ".gitignore"          # docs/.id-locks/, docs/.id-counters/
  - "docs/bugs.md"        # one Rules line (ID allocation)
  - "docs/features.md"    # one Rules line (ID allocation)
tests:
  - scripts/__tests__/lock.test.sh
  - scripts/__tests__/reserve-id.test.sh
  - .claude/hooks/__tests__/check_audit_debt.test.sh
acceptance:
  - "commands/fix-issue.md and commands/feature-workflow.md are <15-line stubs; skills carry the platform-routing content"
  - "no bare 'xcodebuild test' remains in either skill body (grep gate)"
  - "implementer.md has Write in tools + the six-field contract; verifier.md contracted"
  - "lib/lock.sh: two concurrent acquires never both succeed; dead-pid + pid-reuse steal; live matching owner never stolen (long-held test)"
  - "two concurrent reserve-id.sh calls never mint the same ID (test proves via parallel invocation)"
  - "check_audit_debt.sh covers a 7-merge batch in its test fixture"
  - "git status stays clean after creating locks/counters (paths gitignored in this WI)"
```

### WI-2 — contracts (deps token, spec blocks, lane contract rule)

- `docs/bugs.md` + `docs/features.md` `## Rules` — CHANGE: define the `Deps:[…]` token
  (grammar above); run the mechanical recount; migrate every non-terminal row's
  free-text dependencies to tokens; state that in parallel mode tracker writes are
  orchestrator-only and always via Edit/Write tools (never Bash). The stale
  Open-Bug-Detail entries are NOT touched in this WI or anywhere in #130 — they belong
  to the separate hygiene chore filed at the PLANNED flip.
- `.claude/skills/planning/SKILL.md` — CHANGE: WI template gains the mandatory Spec
  block; plan path unified to `dev-docs/plans/YYYYMMDD-feature-<id>-<slug>.md`.
- `.claude/skills/feature-workflow/SKILL.md` — CHANGE: Gate-1 template requires Spec
  blocks; Gate-2 audit prompt adds the spec↔test-catalogue alignment check.
- `.claude/rules/55-lane-dispatch.md` — NEW: the binding lane contract — the HANDOFF
  JSON Schema (normative) + strict-JSON example, the brief template (embedding rule
  48's cwd preamble verbatim), forbidden-paths list, "no Bash file edits" rule, hook
  model (as corrected above), **the lock model with its total acquisition order**
  (dispatch → sim leases → id-reserve → tracker-write; cron prompts take only
  `cron-<kind>`),
  orchestrator-owns-shared-writes, ≤2-lane cap + width-1 default, lease requirements,
  N=1 inline degrade, kill-switch semantics.
- `scripts/deps-check.sh` — NEW: parse token + rule-51 `BLOCKED: needs-design` marker
  from a row; resolve each edge; exit 0 READY / 2 BLOCKED with blocker list; `--lint`
  mode scans a whole tracker (strict inside brackets, warn-only for legacy prose;
  greps rows — never Reads the 499 KB file wholesale).
- `scripts/__tests__/deps-check.test.sh` — NEW (fixture trackers; covers: absent token,
  malformed token, bare #N inside brackets (reject), every edge type,
  terminal-WONT-FIX warn path, rule-51 marker, unknown ID, legacy-prose warn-not-fail).

```yaml
id: WI-2
tier: foundational
depends: [WI-1]
writes:
  - "docs/bugs.md"
  - "docs/features.md"
  - ".claude/skills/planning/SKILL.md"
  - ".claude/skills/feature-workflow/SKILL.md"
  - ".claude/rules/55-lane-dispatch.md"
  - "scripts/deps-check.sh"
  - "scripts/__tests__/deps-check.test.sh"
tests:
  - scripts/__tests__/deps-check.test.sh
acceptance:
  - "deps-check.sh returns READY/BLOCKED correctly for every edge type in the fixture"
  - "mechanical recount output in the PR body; all non-terminal rows migrated; --lint clean (warnings allowed only for terminal rows)"
  - "rule 55 exists with the normative HANDOFF JSON Schema + example + verbatim rule-48 preamble"
```

### WI-3 — resource primitives (locks, leases, write-set gate)

All locks/leases in this WI are built on WI-1's `scripts/lib/lock.sh` (one staleness
implementation: steal only on dead pid or pid-reuse start-time mismatch; a live
matching owner is NEVER stolen — see "Lock model").

- `scripts/agent-lock.sh` — NEW: generic named mutex — `acquire <name>` /
  `release <name>` / `status`; mkdir-atomic `.claude/locks/<name>.lock.d` via
  `lib/lock.sh`; held-by-live-owner ⇒ exit 2 ("blocked"); stale ⇒ steal + warn. Names
  used by this feature: `dispatch` (the GLOBAL orchestrator/integration lock, acquired
  by the /dispatch skill itself — closes the two-orchestrator race for interactive AND
  cron sessions from day one), `tracker-write` (the short shared-surface edit lock),
  and `cron-<kind>` (per-cron reentry locks, used from WI-7; cron prompts take ONLY
  these, never `dispatch`).
- `scripts/sim-lease.sh` — NEW: `acquire <purpose>` / `release <udid>` / `status`.
  mkdir-atomic lease dirs `.claude/locks/sim-<udid>.lock.d`; purposes: `test` (≤2) and
  `verify` (1). **UDID discovery is dynamic**: `xcrun simctl list -j devices available`
  (DEVELOPER_DIR handled); the verify UDID resolves as `VERIFY_UDID` env override →
  persisted choice in `.claude/state/verify-udid` (non-lock state lives under
  `.claude/state/`, gitignored in THIS WI along with `.claude/locks/` +
  `.claude/worktrees/`) → first booted iPhone 17 Pro → boot one. `test` and `verify`
  can never share a UDID. Prints one `SIM-LEASE RESULT:` line. Release paths: the
  dispatch flow's step-6g lane cleanup releases test leases on every exit path; the
  verify flow releases its lease before ENDED; `status` exposes held leases and a
  batch must end at zero.
- `scripts/worktree-setup.sh` — NEW: preconditions (clean main tree, <2 live lane
  worktrees), `git worktree add .claude/worktrees/<id> -b <branch> main`, prints the
  absolute path. `scripts/worktree-teardown.sh` — NEW: worktree remove + the fix-issue
  M5 per-worktree DerivedData sweep, refuses on uncommitted changes unless `--force`.
- `scripts/check-write-set.sh` — NEW: `git diff --name-status -M origin/main...HEAD`
  on the lane branch; **renames count BOTH paths, deletions count, paths normalized to
  the worktree root**; every path must match a declared prefix/file; hard-fail on the
  forbidden list (project.yml, pbxproj, docs/{bugs,features,architecture}.md, README.md)
  and on cross-platform violations (reuses `code_paths_platform`).
- `scripts/run-tests.sh` — CHANGE: the timeout path runs
  `pkill -9 -x SWBBuildService` **only when no other live `xcodebuild` process exists**
  (sibling-lane safety).
- `scripts/sweep-ghosts.sh` — CHANGE: also report/reap stale `.claude/locks/*` entries
  (dead-pid / pid-reuse only — same `lib/lock.sh` rule), REPORT (never reap) locks held
  >2 h by a live matching owner, and reap orphaned `.claude/worktrees/*`.
- `scripts/__tests__/{agent-lock,sim-lease,worktree,check-write-set}.test.sh` — NEW
  (temp state dirs + fake pids — no sim boot needed; worktree tests against a scratch
  git repo; write-set fixtures include rename/delete/symlink cases).

```yaml
id: WI-3
tier: foundational
depends: [WI-1]   # reuses scripts/lib/lock.sh
writes:
  - ".gitignore"          # .claude/locks/, .claude/worktrees/, .claude/state/
  - "scripts/agent-lock.sh"
  - "scripts/sim-lease.sh"
  - "scripts/worktree-setup.sh"
  - "scripts/worktree-teardown.sh"
  - "scripts/check-write-set.sh"
  - "scripts/run-tests.sh"
  - "scripts/sweep-ghosts.sh"
  - "scripts/__tests__/agent-lock.test.sh"
  - "scripts/__tests__/sim-lease.test.sh"
  - "scripts/__tests__/worktree.test.sh"
  - "scripts/__tests__/check-write-set.test.sh"
tests:
  - scripts/__tests__/agent-lock.test.sh
  - scripts/__tests__/sim-lease.test.sh
  - scripts/__tests__/worktree.test.sh
  - scripts/__tests__/check-write-set.test.sh
acceptance:
  - "two concurrent acquires of one lock/lease name never both succeed (mkdir atomicity test)"
  - "PID-reuse guard: a record whose pid is alive but start-time mismatches is stealable; a live matching owner is never stolen — including a LONG-HELD lock (explicit >TTL-age test, no heartbeat stealing)"
  - "verify lease and test lease can never share a UDID; discovery is dynamic (no hardcoded UDIDs/counts)"
  - "check-write-set fails on forbidden-path, out-of-prefix, rename-into-forbidden, and delete-outside-prefix cases"
  - "run-tests.sh timeout with a (mock) sibling xcodebuild alive does NOT pkill SWBBuildService"
  - "git status stays clean after lock/lease/worktree creation (paths gitignored in this WI)"
```

### WI-4 — dispatch skill (the capability; skill-only, no JS)

- `.claude/skills/dispatch/SKILL.md` — NEW (~150 lines): the orchestrator procedure
  exactly as in the Architecture section: kill-switch check → global `dispatch` lock →
  intake → deps-check → write-set partition → worktree+lease setup → brief generation
  from rule 55's template → lane spawn via the **Agent tool** (width 1 default, width 2
  only with memory headroom) → HANDOFF validation → integration tail (with the defined
  rebase-conflict recovery) → Gate-5 → teardown → lock release. Escalation handling
  (audit round-3 failure, needs-design, blocked repro ⇒ orchestrator files issues/marks
  rows; lanes never make policy decisions). N=1 degrade to today's inline flow.
  **Lucid-informed procedure details (v6 — from the live `../lucid/.claude`
  architecture study, 2026-07-09):**
  - **Merge FROM the lane worktree, never the main checkout** —
    `check_codex_audit_artifact.sh` checks the audit artifact as a filesystem
    path under the resolved root; run from main, the branch-committed artifact
    doesn't exist there and the hook FALSE-BLOCKS. Never pass `--delete-branch`
    (gh then checks out the default branch, which fails in a linked worktree —
    `worktree-teardown.sh` owns branch deletion). Both grep-gated in
    `dispatch-shape.test.sh`.
  - **Post-merge-failure disambiguation**: on a non-hook nonzero `gh pr merge`
    exit, run `gh pr view --json state,mergeCommit` BEFORE acting — never
    close-and-requeue an ALREADY-MERGED PR (network-blip double-work hazard).
  - **`git pull --rebase` on main before cutting the tag** — verify-flow
    tracker-write commits can sit unpushed on local main while the batch
    merges remotely; the tag must land on the true merge commit.
  - **Committed-contamination detection** in the post-return check:
    `git log origin/main..main --oneline` (only the orchestrator's own
    chore/plan/evidence commits allowed) IN ADDITION to the porcelain check —
    a drifted lane that COMMITTED from main-checkout cwd leaves `git status`
    clean; the log check is the only detector. Keep both (pbxproj
    contamination also arrives uncommitted via a later `xcodegen generate`).
  - **Ephemeral batch ledger** (in-context, NEVER persisted — a durable file
    is the two-sources-of-truth trap already rejected): one row per lane —
    `item | branch | write-set | UDID | status | verdict/version`, statuses
    dispatched → returned → integrating → merged | requeued | escalated.
    Durable resumable state = tracker rows + GH gate-timeline comments +
    `git worktree list` + `sim-lease.sh status` + `agent-lock.sh status`.
  - **Pre-spawn checklist** (a failed item blocks the SPAWN): main tree clean;
    worktree created + ABSOLUTE path in the brief; `GH: #N` stamped;
    deps-check READY; write-set pairwise-disjoint vs the ledger; UDID leased;
    and an intra-batch Spec dependency counts as satisfied only when the
    dependency WI's branch has **MERGED** — not merely HANDOFF-returned or
    PR-opened (a returned branch can still bounce at integration).
  - **Never-READ lists** (context protection; the N=1 inline degrade stays):
    in dispatch mode the orchestrator never reads full diffs, test logs,
    Codex rawOutput, sim transcripts, or plan bodies (Spec blocks + HANDOFFs
    only), and never runs `git diff` beyond `--name-only`.
  - **Skill-in-custom-agent probe as the canary PRECONDITION**: dispatch a
    real `implementer` (tools: frontmatter) invoking `Skill(cc-suite:status)`;
    PASS ⇒ `Skill(cc-suite:audit)` stays the lanes' primary Gate-4 rung;
    FAIL ⇒ `scripts/run-codex.sh` (rule 53) promotes to primary. Lucid's PASS
    was observed in a broad-toolset subagent, NOT a tools:-frontmatter custom
    agent — vreader observes its own case. cc-suite job state keys on
    process.cwd(): the lane owns its audit loop end-to-end; the orchestrator
    never polls a lane's Codex job.
  - **Skill-override clause** in the lane-mode sections: name exactly which
    standing phases the lane contract OVERRIDES (no PR creation, no tracker
    edits, no close-gate, no version bump — STOP at ready-for-integration).
    A skill loaded "for method" otherwise hijacks the lane past its dispatch.
  - **Bug-mode Phase 0.5 in the brief template**: reproduce FIRST; one
    explicit root-cause line ("the bug is X because Y"); the RED test must
    fail for the bug's reason; re-run the original repro after GREEN and
    record it in the HANDOFF's `notes_append`.
  - **"Dropped by design — do not reintroduce"** section replaces M1–M5:
    names the dead behaviors (resumable two-way agents, integrator "resuming"
    agents through phases, per-WI inline bump/PR) so a future rewrite cannot
    regress into fire-and-forget-incompatible designs.
  - **Version-at-slot wording made explicit**: the orchestrator computes
    X.Y.Z at the merge slot from then-current `project.yml` + latest tag;
    the HANDOFF carries only `bump_tier`; never pre-assign (a requeued lane
    would shift every subsequent number). Width-2 waves dispatch in ONE
    message (both Agent calls together).
- `.claude/agents/implementer.md` — CHANGE (v6): add `Skill` to the tools
  frontmatter and spell the Gate-4 ladder explicitly —
  `Skill(cc-suite:audit)` primary → `scripts/run-codex.sh` (rule 53, the
  watchdogged rung — never bare `codex exec`) → HANDOFF `outcome: blocked`.
  Without the Skill tool the contract's cc-suite wording is physically
  uninvokable from a lane. Must land before the canary.
- `.claude/commands/dispatch.md` — NEW: stub invoking the skill.
- `.claude/skills/fix-issue/SKILL.md` — CHANGE: add "lane mode" section
  (STOP_AFTER=ready-for-integration contract; phases a lane runs: 0.5→6a + in-lane
  Gate-4 audit; HANDOFF as return); replace the M1–M5 banner with "invoke /dispatch".
- `.claude/skills/feature-workflow/SKILL.md` — CHANGE: add lane mode for Gate-3 WIs
  (dispatchable when the plan's Spec blocks declare independence + disjoint writes);
  Gate 5 pinned to the verify-sim lease.
- `.claude/rules/48-parallel-execution.md` — CHANGE: add a short "Lane dispatch"
  section naming /dispatch + rule 55 as THE sanctioned fan-out mechanism (briefs are
  generated, never hand-written).
- `.claude/rules/40-version-bump.md` — CHANGE: add a "Batch mode" note — in parallel
  batches the orchestrator allocates sequential versions at integration time (the M3
  integrator pattern as the universal rule); each PR still ends with its bump commit
  before opening (letter of the rule preserved).
- `.claude/state/dispatch-kill` — the kill-switch flag file (the `.claude/state/` dir
  + gitignore entry land with WI-3, which already persists `verify-udid` there).
  `touch .claude/state/dispatch-kill` disables dispatch instantly (skill + cron
  prompts check it and fall back to inline single-item mode).
- `scripts/__tests__/dispatch-shape.test.sh` — NEW static gate: brief template embeds
  the rule-48 preamble verbatim; forbidden-path list matches rule 55; kill-switch check
  present in the skill text.

**Gate-5 verification for WI-4 is staged** (audit findings D5#1, R2#7):
- **Slice (5a, pre-merge, part of WI-4's PR acceptance): single-lane live canary** —
  one real small work item driven end-to-end through /dispatch at width 1 (lane
  worktree + leased sim + HANDOFF + integration tail). Recorded in the PR body with
  measured wall-clock.
- **`M-SHAKEDOWN` (named post-merge milestone = the feature's Gate-5b, NOT part of any
  WI's PR acceptance): two-lane live shakedown** — two real, independent, small work
  items at width 2. The two candidate items are **identified concretely at shakedown
  time** from the tracker; if no suitable real items exist, use two controlled
  micro-chores that are genuine repo improvements (e.g. two independent test-coverage
  additions in disjoint suites) — never synthetic no-ops. Evidence file
  (`dev-docs/verification/feature-130-<date>.md`) records: both PRs, monotonic
  versions, hooks fired, check-write-set clean, zero cross-lane contamination,
  measured wall-clock vs the serial baseline. **WI-5 and WI-7 both gate on
  `M-SHAKEDOWN`**, and it is what flips the feature row DONE → VERIFIED.

```yaml
id: WI-4
tier: behavioral
depends: [WI-2, WI-3]
writes:
  - ".claude/skills/dispatch/"
  - ".claude/commands/dispatch.md"
  - ".claude/skills/fix-issue/SKILL.md"
  - ".claude/skills/feature-workflow/SKILL.md"
  - ".claude/agents/implementer.md"   # v6: Skill tool + Gate-4 ladder
  - ".claude/rules/48-parallel-execution.md"
  - ".claude/rules/40-version-bump.md"
  - "scripts/__tests__/dispatch-shape.test.sh"
tests:
  - scripts/__tests__/dispatch-shape.test.sh
acceptance:   # PR-level only; the two-lane shakedown is the post-merge M-SHAKEDOWN milestone
  - "single-lane live canary passes (slice, pre-merge; measured wall-clock recorded)"
  - "N=1 request degrades to today's inline flow"
  - "a lane returning a forbidden-path edit is caught by check-write-set before PR"
  - "kill-switch file disables dispatch (verified in canary)"
```

### WI-5 — cleanup: delete the dead agents (post-proof)

- `.claude/agents/` — DELETE `auditor.md`, `impact-analyst.md`, `manual-test-author.md`,
  `planner.md`, `release-steward.md`, `spec-guardian.md`, `test-runner.md` — only now
  that /dispatch is live-proven (M-SHAKEDOWN). `test-runner.md`'s vreader-adapted §0.0
  content is confirmed folded into rule 55 / the dispatch skill in the same PR.
  This cleanup is **non-blocking for WI-7** (cron cutover) — both gate on M-SHAKEDOWN
  independently; the numbered sequence is not an ordering claim between them.

```yaml
id: WI-5
tier: foundational
depends: [WI-4, M-SHAKEDOWN]
writes:
  - ".claude/agents/"
  - ".claude/rules/55-lane-dispatch.md"   # §0.0 fold-in, if any residue
tests: []
acceptance:
  - "only implementer.md and verifier.md remain; both with valid frontmatter"
  - "grep proves no skill/command/cron references a deleted agent name"
```

### WI-6 — OPTIONAL: Workflow-JS batch drivers (gated on runtime proof)

**Entry gate (runtime proof)**: a trivial named workflow (`.claude/workflows/
hello-lane.js`) runs successfully (a) in an interactive session and (b) in a cron-fired
session. If (b) fails, this WI is dropped and the dispatch skill remains the only
driver — no other WI depends on this one.

- `.claude/workflows/fix-batch.js` + `.claude/workflows/feature-wave.js` — NEW:
  deterministic fan-out drivers with structured-output schemas matching the HANDOFF;
  the JS never writes shared surfaces (integration tail stays in the invoking session).

```yaml
id: WI-6
tier: foundational
depends: [WI-4]
writes:
  - ".claude/workflows/"
tests:
  - scripts/__tests__/dispatch-shape.test.sh   # extended: workflow meta blocks parse
acceptance:
  - "runtime proof recorded (interactive + cron-fired hello-lane run) BEFORE the drivers land"
  - "fix-batch.js drives the same lane contract as the skill (HANDOFF schema identical)"
```

### WI-7 — cron cutover (gated on owner go-ahead after shakedown)

Rollout: **one-cron canary** — bugfix cron cuts over first; feature/verify follow only
after ≥3 clean bugfix-cron iterations. Instant disable: `touch
.claude/state/dispatch-kill` (crons then run today's inline path). Exact rollback:
`git revert` of this WI's cron-prompt commit (single commit, no other files).

- `.claude/cron-prompts/bugfix.md` — CHANGE: check kill-switch; acquire ONLY
  `agent-lock.sh acquire cron-bugfix` (or exit `ENDED blocked (lock held)`); pick up to
  2 READY issues via deps-check; run /dispatch — **which takes the global `dispatch`
  lock itself** (the cron never pre-acquires it; `agent-lock.sh` is non-reentrant and
  pre-acquisition would self-deadlock — audit finding R2#1); if /dispatch exits
  "blocked (dispatch busy)", log `ENDED blocked` and exit; release `cron-bugfix` before
  the ENDED line.
- `.claude/cron-prompts/feature.md` — CHANGE: same pattern (after canary); WI fan-out
  only when Spec blocks declare independence; keeps the 4-tier pick order.
- `.claude/cron-prompts/verify.md` — CHANGE: acquire the verify-sim lease at start;
  perform all sim observations first; then take the short `tracker-write` lock
  (bounded wait) for its finalization writes — evidence file commit, VERIFIED flips,
  GH closes, bug filings — and release it immediately after (a verify session is a
  shared-surface WRITER, so it participates in the lock order like everyone else —
  audit finding R2#3); release the sim lease before ENDED. Legal concurrent with a
  bugfix wave (rule 48 matrix) because it never touches `dispatch`.
- `.claude/cron-prompts/watchdog.md` — CHANGE: add stale lock/lease/worktree sweep
  (via the extended sweep-ghosts.sh) to its checklist.

```yaml
id: WI-7
tier: behavioral
depends: [WI-4, M-SHAKEDOWN]   # WI-5 cleanup is explicitly NON-blocking for this WI
writes:
  - ".claude/cron-prompts/"
tests: []   # prompt-text change; the primitives it calls are tested in WI-3
acceptance:
  - "explicit owner go-ahead recorded before this WI's PR opens (shakedown observed)"
  - "bugfix-cron canary: ≥3 clean iterations before feature/verify cut over"
  - "overlapping cron fire exits 'blocked' instead of colliding (observed once)"
  - "kill-switch fallback to inline mode verified once"
```

## Edge cases (tests required)

- **reserve-id**: parallel invocation race; tracker max > counter (manual row); missing
  counter file (seed from tracker); malformed rows.
- **deps-check**: absent token; malformed token; bare `#N` inside brackets (reject);
  unknown ID; edge to WONT FIX/DUPLICATE row (warn-resolve); design edge with/without
  committed bundle; rule-51 BLOCKED marker; legacy prose (warn only); CJK/long Notes
  cells (grep rows, never Read the 499 KB file wholesale).
- **lib/lock / agent-lock / sim-lease**: mkdir race (two acquires, one winner);
  dead-pid steal; **PID-reuse (live pid, mismatched start-time) steal**; live-matching
  owner never stolen — including long-held (>TTL age, no heartbeat stealing); lock
  ORDER violations impossible by construction (tracker-write holder never acquires);
  release of non-owned lock (refuse); no available sims; DEVELOPER_DIR unset.
- **worktree**: dirty main tree (abort); cap reached; branch name exists; teardown with
  uncommitted changes (refuse without --force); orphan sweep.
- **check-write-set**: forbidden path; out-of-prefix path; rename INTO a forbidden path;
  deletion outside prefix; symlink; cross-platform violation.
- **run-tests sibling-kill**: timeout with sibling alive (no daemon kill) / without
  (kill as today).
- **dispatch**: lane returns null/invalid HANDOFF (requeue once, then escalate); every
  lane exit path releases its test lease + tears down its worktree (batch ends with
  zero held leases — asserted in the canary); IDs minted before tracker-write (never
  inside it); rebase
  conflict (defined recovery — no version burned, no PR opened, no tracker change);
  failure between PR-open and merge (close PR + requeue); audit verdict
  block-recommended (escalate, never merge); memory degrade to width 1; two
  orchestrators (second blocks on the `dispatch` lock); kill-switch present; CJK issue
  titles in branch slugs (ASCII-safe slugify).

## Test catalogue

| Test file | Covers |
| --- | --- |
| `scripts/__tests__/lock.test.sh` | lib/lock.sh: atomicity, dead-pid/PID-reuse steal, live-owner-never-stolen (incl. long-held) |
| `scripts/__tests__/reserve-id.test.sh` | atomic ID allocation, race, seeding |
| `.claude/hooks/__tests__/check_audit_debt.test.sh` | >5-merge batch window, fetch fallback |
| `scripts/__tests__/deps-check.test.sh` | full edge-type matrix + lint modes |
| `scripts/__tests__/agent-lock.test.sh` | mutex atomicity, staleness (incl. PID reuse) |
| `scripts/__tests__/sim-lease.test.sh` | purpose isolation, dynamic discovery, staleness |
| `scripts/__tests__/worktree.test.sh` | preconditions, cap, teardown, DD sweep hook |
| `scripts/__tests__/check-write-set.test.sh` | prefix ⊆, forbidden, rename/delete/symlink |
| `scripts/__tests__/dispatch-shape.test.sh` | brief embeds preamble; kill-switch present; (WI-6) workflow meta parse |

All shell tests follow the existing `run-android-tests.test.sh` pattern (temp dirs, fake
pids, no real sims/network). TDD order per rule 10: each script's test lands RED first.

## Risks + mitigations

| Risk | Mitigation |
| --- | --- |
| Bash-mediated edits bypass PreToolUse Edit-matcher hooks (the REAL hook gap) | "No Bash file edits" is a lane-brief AND rule-55 hard rule; `check-write-set.sh` at integration is the detection layer; lanes cannot merge anything |
| Worktree cwd contamination (PR #1029 class) | Preamble templated into every brief by the dispatch skill (never hand-written); orchestrator checks main's tree cleanliness before merging |
| Two orchestrators (interactive + cron) double-integrate | Global `dispatch` lock from WI-3/WI-4 day one — not deferred to cron cutover |
| 16 GB RAM thrash with 2 lanes + 2 sims | Width-1 default; second lane only with memory headroom; shakedown records measured wall-clock so the 2-lane benefit is proven, not asserted |
| SWBBuildService is a shared singleton; a genuinely wedged daemon poisons the sibling | Sibling-aware kill removes the self-inflicted case; the wedged-daemon case is accepted (re-run protocol, rule 52) |
| PID reuse steals a live lease | Staleness record = pid + start-time; steal only on dead pid or start-time mismatch; live matching owners never stolen (sweep-ghosts reports long-held) |
| Lock-order deadlock (dispatch / sim / tracker-write) | Total acquisition order; tracker-write holders acquire nothing; crons take only cron-<kind>; tested lock ordering in rule 55 |
| Deps token rots like the prose did | `deps-check.sh --lint` warn layer + absent-token info lines; verify-cron sweep is the backstop (WI-7) |
| HANDOFF truthfulness (fabricated RESULT line) | Orchestrator independently re-runs the declared targeted suite on the rebased branch before PR |
| Workflow-JS runtime unavailable in cron sessions | It is OPTIONAL (WI-6) behind an explicit runtime-proof gate; the dispatch skill is the only required driver |
| Rebase-conflict mid-tail corrupts state | Tail ordering guarantees zero shared-surface changes before PR-open; defined abort/requeue/escalate ladder |
| Stale locks stall crons | Hardened staleness + watchdog/sweep-ghosts reap; kill-switch as the manual override |
| Cron picks up this feature mid-redesign | Row Notes carry the cron-skip guard from the PLANNED flip; WI-7 (the only cron-touching WI) is last and canaried |

## Backward compat

- N=1 requests keep today's inline single-issue flow (explicit degrade rule).
- `/fix-issue` and `/feature-workflow` command entry points keep working (stubs).
- Crons are byte-identical until WI-7, which is canaried + kill-switched + trivially
  revertable.
- No app code, no schema, no contracts/ change. All-platform-neutral (`shared` lane;
  version bumps ride the iOS `project.yml` per rule 40's routing table).
- Rules 10/47/51/52/53/54 semantics unchanged; rules 40/48 gain additive sections.
- Android items remain dispatchable at width 1 only (no emulator pooling) until the
  ANDROID_SERIAL follow-up lands.

## Version bumps

WI-1/2/3/5/7: patch. WI-4: minor (new capability). WI-6 (if built): patch.

## Acceptance criteria (feature level → VERIFIED)

1. Hygiene: single-sourced skills; no bare `xcodebuild test` in skill bodies; atomic ID
   allocation in place; audit-debt window covers batches.
2. Contracts: Deps token defined + mechanically recounted + migrated + lint-warn-clean;
   Spec blocks mandatory in the Gate-1 template; rule 55 carries the normative HANDOFF
   JSON Schema + brief template.
3. Primitives: all five scripts pass their test suites (incl. PID-reuse staleness);
   run-tests.sh sibling-safe; global dispatch lock live.
4. **Canary + shakedown (Gate 5)**: WI-4's single-lane live canary (slice) and two-lane
   live shakedown (feature 5b) pass with measured wall-clock, recorded in
   `dev-docs/verification/feature-130-<date>.md`.
5. Dead agents deleted only post-proof (WI-5); cron cutover shipped only after the
   shakedown + explicit owner go-ahead, canaried on the bugfix cron with a live
   kill-switch (WI-7).

## Revision history

- v7 2026-07-09 — post-proof consolidation (WI-5). **M4a single-lane canary
  PASSED** (bug #360 end-to-end via /dispatch: PR #1892, v3.66.57, merged
  FROM the worktree, per-PR tag, zero leases/locks at end; 6m47s lane,
  ~1KB HANDOFF). **M-SHAKEDOWN PASSED** (two concurrent lanes: bug #361
  hook-hygiene + export-formatter test chore; 1.76× lane-phase concurrency;
  PRs #1894 v3.67.1 + #1895 v3.67.2 both merged from their worktrees with
  per-PR tags; contamination probes clean; zero leases/locks/worktrees at
  end; GH #1890 + #1891 verified & closed). **WI-6 dispositioned
  dropped-pending-(b)**: runtime proof (a) PASSED (`.claude/workflows/hello-lane.js`
  runs via Workflow scriptPath, structured output round-trips, 11s) but
  proof (b) — a cron-fired headless session invoking Workflow — is not
  cheaply provable; the workflow drivers are dropped until (b) is shown,
  hello-lane.js is committed as the standing probe. Rule 55 widened from
  shakedown findings: `ALL PASS` accepted as a bash-suite `test_result_line`;
  `chore:<slug>` id class; optional HANDOFF `notes` field; width gate weighs
  lane types (bash lane ≈ zero build load); new-Swift-file lanes need the
  orchestrator's structural regen (extend-existing-file is the v1 answer);
  the no-Bash-edits rule binds the orchestrator too (self-caught lapse in
  the shakedown tail). 7 dead vmark agents deleted (auditor, impact-analyst,
  manual-test-author, planner, release-steward, spec-guardian, test-runner)
  — only `implementer` + `verifier` remain; test-runner's content confirmed
  already covered by rules 52/55.
- v6 2026-07-09 — lucid cross-pollination (structured study of the LIVE
  `../lucid/.claude` architecture — same problem, independently-converged
  design, proven in production there). WI-4 gains eleven procedure details
  (merge-from-worktree + no --delete-branch, gh-pr-view merge disambiguation,
  pull --rebase before tag, committed-contamination log-check, ephemeral
  ledger, merged-not-returned dependency rule, never-READ lists, Skill-probe
  canary precondition, skill-override clause, bug Phase-0.5 brief discipline,
  dropped-by-design section, explicit version-at-slot wording);
  implementer.md added to WI-4's writes (Skill tool + Gate-4 ladder). WI-3
  absorbed the immediate items pre-audit: `.claude/codex-audits/` standing
  allowance in check-write-set (every contract-compliant lane would have
  failed its own gate), `.reports/` overflow channel, worktree-cwd test
  cases, sweep-ghosts as the single lock reaper + Codex.app ghost-class
  exclusion. Deliberate rejections recorded (integrator agent, cap 3,
  absolute never-inline, prose envelope, planner-packed Gates 1+2, verifier
  evidence-writing, weakened FIXED gate, bare codex exec, persisted ledger).
  Two same-class hook defects confirmed in vreader and queued as a separate
  hook-hygiene bug PR (phantom verify-skip bypass; naive pipe-split columns
  in check_unfinished_verification.sh).
- v5 2026-07-08 — Gate-2 round-3 fixes (same thread, verdict NEEDS REVISION with 7 new
  findings, all introduced by v4's lock-model additions; the 3-round ceiling is
  reached — v5 applies every finding and is escalated to the owner per rule 47):
  explicit lane-lease lifecycle — step-6g cleanup releases the test lease on EVERY
  exit path, step-6c re-test reuses the still-held lease, batch ends at zero held
  (High); `id-reserve` added to the total lock order as a leaf before `tracker-write`
  with "mint IDs before tracker-write" binding (High); WI-2's contradictory
  Open-Bug-Detail reconciliation clause removed — stale entries are never touched in
  #130 (Medium); Spec-block `depends` grammar extended to named `M-*` milestones with
  evidence-artifact readiness semantics (Medium); verify-udid unified to
  `.claude/state/verify-udid` with the state-dir gitignore moved to WI-3 (Low); exact
  row counts dropped from the recount snapshot (Low); `lock.test.sh` added to the test
  catalogue (Low).
- v1 2026-07-08 — initial plan (from the 6-reader + 3-lens audit workflow, this session).
- v2 2026-07-08 — pre-audit self-fix: `flock(1)` does not exist on macOS (verified);
  reserve-id.sh and cron-lock.sh respecified on mkdir-atomic lock dirs.
- v4 2026-07-08 — Gate-2 round-2 fixes (same thread, verdict NEEDS REVISION → all 9
  findings applied): cron self-deadlock removed — crons take ONLY `cron-<kind>`,
  /dispatch owns the global lock (Critical); `dispatch` lock scope narrowed to
  dispatch+integration, released before Gate 5, which runs under verify-sim +
  short `tracker-write` lock (High); verify flow made an explicit `tracker-write`
  participant with observations-first ordering (High); heartbeat-TTL stealing removed —
  steal only on dead-pid/PID-reuse, live matching owners never stolen, sweep-ghosts
  reports long-held (High); `.gitignore` coverage moved into the WI that creates each
  runtime path, id-counters declared local state (High); shared `scripts/lib/lock.sh`
  moved to WI-1 and WI-3 now depends on WI-1 (Medium); WI-4 acceptance split from the
  post-merge `M-SHAKEDOWN` milestone, WI-5/WI-7 gate on it explicitly (Medium);
  WI-5 declared non-blocking for WI-7 (Medium); HANDOFF example made strict JSON (Low).
  Plus: mechanical recount folded in (bugs 0 non-terminal of 353; features 4
  non-terminal of 126; the 119 stale bug-detail entries scoped OUT to a separate chore).
- v3 2026-07-08 — Gate-2 round-1 fixes (cc-suite review-plan, thread
  `019f41ff-1ed6-7fb0-a039-d4ba1a96b42d`, verdict MAJOR GAPS). Applied: Workflow-JS
  demoted to optional runtime-proof-gated WI-6 (Critical); WI-4 split — skill-only
  dispatch + staged single-lane canary → two-lane shakedown (Critical); global
  `dispatch` lock added at WI-3/4, not deferred to cron cutover (High); hook model
  rewritten — hooks fire in any session on Edit/Write tool calls, the real gap is
  Bash-mediated edits (High); agent deletions deferred to post-proof WI-5 (High);
  rebase-conflict recovery ladder defined with zero-shared-state-before-PR ordering
  (High); HANDOFF given a normative JSON schema (High); WI-level dependency edges
  dropped from the Deps token v1 — plan Spec blocks are the canonical WI source (High);
  cron cutover gains kill-switch + one-cron canary + exact rollback (High);
  `cron-lock.sh` generalized to `agent-lock.sh`; staleness hardened against PID reuse
  (pid + start-time + heartbeat); check-write-set semantics defined via
  `--name-status -M` incl. rename/delete/symlink fixtures; verify-UDID discovery
  ladder defined; sim discovery dynamic (no fixed counts); migration scope recount made
  mechanical + reconciles bugs.md detail drift; Android fan-out explicitly deferred
  (width-1 only) pending ANDROID_SERIAL routing; shakedown item selection defined;
  "0 open bugs" claim corrected to recount-at-WI-2; test-runner §0.0 fold-in noted;
  cron-guard wording fixed (row filed at the PLANNED flip, not pre-existing).
