# 55 — Lane Dispatch (the parallel-execution contract)

Binding for every orchestrator and every lane subagent. This is feature #130's
core contract: rule 48 says *when* parallelism is legal; this rule says *how*
the sanctioned mechanism works. Plan:
`dev-docs/plans/20260708-feature-130-agent-lane-harness.md`.

## Roles

- **Orchestrator** — the invoking session (interactive or cron). Owns EVERY
  contended surface: `docs/bugs.md`, `docs/features.md`,
  `docs/architecture.md`, `README.md`, `project.yml` /
  `vreader.xcodeproj/*` (version allocation), `git tag`, `gh pr
  create/merge`, and all tracker/docs finalization edits. Runs the
  integration tail serially. Width: **1 lane by default; 2 only with memory
  headroom** (`vm_stat` check) — the machine ceiling is real (16 GB / 10
  cores).
- **Lane** — a worktree-isolated subagent (the `implementer` agent) that does
  the heavy work for exactly ONE work unit and returns a HANDOFF. Lanes never
  touch the orchestrator's surfaces and **never edit ANY file via Bash**
  (sed/heredocs bypass the PreToolUse Edit-matcher hooks — use Edit/Write
  tools, everywhere, so hooks fire in lane sessions too).
- **Verifier** — a read-only observer on the leased verify sim (the
  `verifier` agent). Returns observations; the orchestrator writes evidence
  files and flips rows (so `check_terminal_status_evidence.sh` fires where
  the evidence file lives).

## Hook model (what enforces where)

The project's PreToolUse hooks fire on Edit/Write/MultiEdit TOOL calls in ANY
session working in this repo — including lanes ( `check_codex_audit_artifact.sh`
is already worktree-aware). The real bypass is Bash-mediated file edits and
Stop-hook state derived from the main checkout. Hence: (1) no Bash file
edits, ever; (2) shared surfaces are orchestrator-only anyway — for
single-writer serialization (rule 48), not because hooks wouldn't fire;
(3) `scripts/check-write-set.sh` at integration is the trust-but-verify
detection layer; a disobedient lane costs a redone lane, never a corrupted
main (lanes cannot merge).

## Lock model (total order — deadlock-free by construction)

```
dispatch  →  sim leases  →  id-reserve  →  tracker-write
(global,     (per-UDID,     (leaf inside     (short-held: ANY shared
 long-held)   medium-held)   reserve-id.sh)    tracker/docs edit)
```

- Acquire only left-to-right; a `tracker-write` holder acquires NOTHING.
- **`dispatch`** (via `scripts/agent-lock.sh`): one orchestrator per repo.
  Acquired by the /dispatch skill itself at step 0 — **cron prompts take only
  their `cron-<kind>` reentry lock and then invoke /dispatch** (pre-acquiring
  `dispatch` self-deadlocks; the lock is non-reentrant). Released after the
  integration tail (merge/tag/teardown), BEFORE Gate-5 — that is what lets
  the next batch's Gate-3 lanes overlap a Gate-5 pass (rule 48 matrix).
- **Sim leases** (via `scripts/sim-lease.sh`): purpose-tagged (`test` ≤2,
  `verify` 1, `android` ≤ online-emulator count — an Android lane leases an
  `emulator-NNNN` serial); a device never serves two purposes (rule 52
  mutual exclusion mechanized). Every lane exit path releases its lease; a
  batch ends with zero held.
- **`id-reserve`**: all new row IDs are minted via `scripts/reserve-id.sh`
  BEFORE `tracker-write` is acquired; calling reserve-id while holding
  tracker-write is forbidden.
- **`tracker-write`**: serializes every shared tracker/docs edit across ALL
  writers — the orchestrator's integration-tail step (legal: it already
  holds `dispatch`) and the verify flow's finalization (observations first,
  then a bounded-wait acquire, edit, release immediately).
- **Staleness** (all locks/leases, `scripts/lib/lock.sh`): steal only on
  dead pid or PID-reuse (start-time mismatch). A live matching owner is
  NEVER stolen, regardless of age. No non-holder removes anything — a dead
  stealer's `.steal.d` mutex is reaped ONLY by `scripts/sweep-ghosts.sh`
  (the single sweep actor); acquire fails fast with a pointer meanwhile.

## Kill switch

`touch .claude/state/dispatch-kill` disables dispatch instantly: the
/dispatch skill and (post-WI-7) the cron prompts check it at start and fall
back to today's inline single-item mode. Remove the file to re-enable.

## Dependency gate

Nothing is spawned that `scripts/deps-check.sh <kind> <id>` didn't mark
READY. The typed token grammar and readiness semantics live in the trackers'
`## Rules`; `deps-check.sh --lint` is the drift check (legacy prose warns,
malformed tokens error).

## The HANDOFF (lane → orchestrator return; normative)

A lane's final message is EXACTLY one JSON object (no prose around it).
Required fields and semantics:

| Field | Type | Semantics |
| --- | --- | --- |
| `id` | string | the dispatched item — `bug:#N`, `feat:#N/WI-k`, or `chore:<slug>` (shakedown-class micro-chores) |
| `branch` | string | the lane's branch name |
| `head_sha` | string | HEAD of the branch at return |
| `outcome` | enum | `ready-for-integration` \| `blocked` \| `failed` |
| `root_cause` | string | one line; required for bugs when outcome=ready |
| `red_test` | string | the RED test's full identifier; required when ready |
| `files_touched` | string[] | must ⊆ the brief's declared write-set |
| `test_result_line` | string | the verbatim wrapper `RUN-* RESULT:` line — or a bash suite's `ALL PASS` final line (M-SHAKEDOWN canary finding: hook/script lanes have no xcodebuild wrapper) |
| `audit` | object | `{artifact_path, final_verdict, rounds, thread_id}`; required when ready |
| `tracker_edit` | object | `{file, row_id, status_to, notes_append}` — the EXACT proposed row mutation (the orchestrator applies it, not the lane) |
| `docs_sync` | object | `{needed, files[], proposed_lines[]}` |
| `bump_tier` | enum | `patch` \| `minor` \| `major` (rule-40 tiers) |
| `blockers` | string[] | non-empty explains outcome=blocked |

Example (strict JSON):

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

### Normative JSON Schema (authoritative — the table above is a summary)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "vreader lane HANDOFF",
  "type": "object",
  "additionalProperties": false,
  "required": ["id", "branch", "head_sha", "outcome", "files_touched",
               "test_result_line", "tracker_edit", "docs_sync",
               "bump_tier", "blockers"],
  "properties": {
    "id":        { "type": "string", "pattern": "^(bug:#[0-9]+|feat:#[0-9]+(/WI-[0-9]+)?|chore:[a-z0-9][a-z0-9-]*)$" },
    "branch":    { "type": "string", "minLength": 1 },
    "head_sha":  { "type": "string", "pattern": "^[0-9a-f]{7,40}$" },
    "outcome":   { "enum": ["ready-for-integration", "blocked", "failed"] },
    "root_cause": { "type": "string" },
    "red_test":   { "type": "string" },
    "files_touched": { "type": "array", "items": { "type": "string" } },
    "test_result_line": { "type": "string", "pattern": "^(RUN-(TESTS|ANDROID-TESTS) RESULT:.*|ALL PASS)$" },
    "audit": {
      "type": "object",
      "required": ["artifact_path", "final_verdict", "rounds", "thread_id"],
      "properties": {
        "artifact_path": { "type": "string" },
        "final_verdict": { "enum": ["ship-as-is", "follow-up-recommended", "block-recommended"] },
        "rounds":        { "type": "integer", "minimum": 1 },
        "thread_id":     { "type": "string" }
      }
    },
    "tracker_edit": {
      "type": "object",
      "required": ["file", "row_id", "status_to", "notes_append"],
      "properties": {
        "file":         { "enum": ["docs/bugs.md", "docs/features.md"] },
        "row_id":       { "type": "integer", "minimum": 1 },
        "status_to":    { "type": "string" },
        "notes_append": { "type": "string" }
      }
    },
    "docs_sync": {
      "type": "object",
      "required": ["needed", "files", "proposed_lines"],
      "properties": {
        "needed":         { "type": "boolean" },
        "files":          { "type": "array", "items": { "type": "string" } },
        "proposed_lines": { "type": "array", "items": { "type": "string" } }
      }
    },
    "bump_tier": { "enum": ["patch", "minor", "major"] },
    "blockers":  { "type": "array", "items": { "type": "string" } },
    "notes":     { "type": "string", "description": "optional one-paragraph operational notes (ghost-hygiene report, environment observations) — the ONLY legal home for prose; the HANDOFF JSON itself stays the entire final message" }
  },
  "allOf": [
    { "if":   { "properties": { "outcome": { "const": "ready-for-integration" } } },
      "then": { "required": ["red_test", "audit"] } },
    { "if":   { "properties": { "outcome": { "const": "blocked" } } },
      "then": { "properties": { "blockers": { "minItems": 1 } } } }
  ]
}
```

(`root_cause` is additionally required for `bug:#N` items when outcome is
ready — expressed here as convention since the schema cannot see the id kind
without further nesting.)

Orchestrator behavior: validate the HANDOFF; **invalid or missing = lane
failure** — requeue the item once (fresh lane), then escalate. The
orchestrator independently re-runs the declared targeted suite on the rebased
branch before opening a PR (a fabricated `test_result_line` buys nothing).
The HANDOFF doubles as the PR body and the GH gate-timeline comment.

## The lane brief (orchestrator → lane; generated, never hand-written)

Every brief MUST contain, in this order:

1. **The rule-48 "Critical Operational" cwd preamble, verbatim** (absolute
   worktree path substituted). Non-optional — PR #1029 precedent. The exact
   block (kept in sync with rule 48's template):

```
## CRITICAL OPERATIONAL — binding

Your worktree path is: <ABSOLUTE-WORKTREE-PATH>

Every `Bash` tool call you issue MUST begin with `cd "<ABSOLUTE-WORKTREE-PATH>"`.
Before your first edit or write, run `pwd` and confirm it prints the worktree
path. If `pwd` does NOT match, stop and report — do NOT attempt to recover by
guessing.

The Agent harness creates the worktree but does NOT set your initial cwd to
it. Your Bash tool starts with cwd = the orchestrator's main checkout
(`/Users/ll/workspace/vreader`). A single Bash call that forgets the `cd`
prefix can write to the main checkout instead of your worktree; a later
`xcodegen generate` then folds stray files into `project.pbxproj` and breaks
the build on every clean clone. Standing precedent: PR #1029 (v3.37.19) was a
hotfix for exactly this pattern; bug #957's agent self-rescued from the same
drift mid-flow.

This is binding for every Bash call, not just the first. Do not skip this in
the interest of brevity.
```
2. The rule-48 six-field contract instantiated: objective (the one work
   unit), inputs (Spec block or bug micro-spec: repro + expected-vs-actual +
   regression-test name; exact file list; the leased device — `TEST_UDID`
   for an iOS/`shared` lane, `ANDROID_SERIAL=<emulator-NNNN>` for an
   Android lane), allowed writes (the `writes:` prefixes), forbidden (the
   orchestrator surfaces above + "no Bash file edits" + no paths outside
   the write-set), output format (the HANDOFF), stop condition
   (ready-for-integration or blocked).
3. The test-gate command shape: iOS/`shared` → `TEST_UDID=<udid>
   scripts/run-tests.sh <targeted-suite>`; Android →
   `ANDROID_SERIAL=<emulator-NNNN> ANDROID_CMD="…"
   scripts/run-android-tests.sh` (the runner validates + re-exports the
   serial) — wrappers only (rule 52), targeted suites only (never the
   >20-min full suite).
4. The in-lane Gate-4 instruction: `scripts/run-codex.sh` (rule 53) is the
   PRIMARY rung — **probed 2026-07-09 (twice, incl. with `Skill` in the
   agent frontmatter): custom agents get NO Skill tool in this harness, so
   cc-suite slash-skills are unreachable from a lane** — artifact committed
   on the branch, ≤3 rounds then blocked. Long output goes to
   `<worktree>/.reports/` and travels as paths.

## Degrades

- **N=1**: a single work item runs today's inline flow — fan-out overhead
  isn't worth it (rule 48 decision test).
- **Memory pressure**: width 2 → 1 (`vm_stat` free-pages check before
  opening the second lane).
- **Android**: `run-android-tests.sh` now honors `ANDROID_SERIAL` (validate +
  export + ambiguity guard) and `sim-lease.sh acquire android` leases an online
  emulator serial, so an `android-app`/`android-spike` lane CAN be routed to a
  specific emulator. Width is still **1 in practice** because only one AVD is
  booted by default — the `android` lease capacity = the number of online
  emulators. To run width 2, boot a **second AVD** (`avdmanager create avd …`;
  `emulator -avd vreader-test-2` → `emulator-5556`), then each lane leases a
  distinct serial and passes it as `ANDROID_SERIAL` (rule 52 Cause D — never two
  runs on one emulator).
- **Width gate weighs LANE TYPES, not lane count** (M-SHAKEDOWN finding): the
  4GB `vm_stat` headroom check applies per SWIFT lane (xcodebuild + booted
  sim ≈ real load); a bash-only lane (hooks/scripts work) adds near-zero
  build load — a mixed bash+Swift pair is effectively width 1 for memory
  purposes. Document any deviation in the batch evidence.
- **New Swift FILES in a lane's write-set are NOT dispatchable in v1**
  (M-SHAKEDOWN finding): a new file needs an xcodegen structural regen to
  join `project.pbxproj`, which is orchestrator-owned — so the lane's own
  test gate can never compile the file, and the integration tail has no
  post-regen retest step. Design the item to EXTEND an existing file
  (target globs pick it up with no regen); if a new file is genuinely
  unavoidable, the item routes INLINE (`/fix-issue` / `/feature-workflow`),
  not through a lane. First-class support (a conditional post-regen suite
  run in the tail) is a named follow-up.
- **The no-Bash-file-edits rule binds the ORCHESTRATOR too** (M-SHAKEDOWN
  self-caught deviation): shared-surface tracker/docs edits go through
  Edit/Write even in the integration tail — a heredoc edit dodges the
  PreToolUse hooks exactly like a lane's would. Nothing mechanical enforces
  this on the orchestrator; the discipline is the gate, and batch evidence
  must record any lapse.

## What this rule does NOT change

TDD (rule 10), the six gates (rule 47), sim isolation (rule 52), codex
isolation (rule 53), background-shell discipline (rule 49), untrusted-content
quarantine (rule 54) — all unchanged. Rule 48 remains the *when*; this rule
is the *how*.
