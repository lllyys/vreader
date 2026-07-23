---
name: dispatch
description: "Parallel lane dispatch — the ONLY sanctioned multi-item fan-out (feature #130, rule 55). Use when the user asks to fix several bugs at once ('fix #a #b #c'), implement independent feature WIs in parallel, or run a dispatch batch. Orchestrates worktree-isolated implementer lanes on leased simulators, validates HANDOFFs, and runs the serial integration tail (rebase → re-test → tracker/docs → version-at-slot → PR → merge-from-worktree → tag). A single item degrades to the inline /fix-issue or /feature-workflow flow."
---

# Dispatch (rule 55 — the lane orchestrator)

You are the ORCHESTRATOR. Lanes do the heavy work; you own every contended
surface (trackers, `project.yml`/pbxproj versions, `git tag`, `gh pr`,
docs sync) and all policy decisions. Lanes never decide anything.

## Step 0 — preconditions (any failure ⇒ report, do not dispatch)

1. **Global lock FIRST**: `scripts/agent-lock.sh acquire dispatch` — exit 2
   means another orchestrator (interactive or cron) is mid-batch: report
   "blocked (dispatch busy)" and STOP. Cron prompts take only their
   `cron-<kind>` lock; /dispatch itself owns `dispatch` (pre-acquiring it
   outside would self-deadlock — the lock is non-reentrant).
2. **Kill switch**: if `.claude/state/dispatch-kill` exists → dispatch is
   disabled; run the item(s) through the inline single-item flow
   **while still holding the `dispatch` lock** (the inline flow edits the
   same shared surfaces — running it unlocked could race a concurrent
   batch), release the lock at the end, and say so.
3. **N=1 degrade**: a single work item runs today's inline flow
   (/fix-issue or /feature-workflow) — fan-out overhead isn't worth it
   (rule 48 decision test). Same rule: **the inline degrade runs under the
   `dispatch` lock**, released when the inline flow finishes.
4. **Width**: default 1 lane; open a second ONLY with memory headroom —
   check `vm_stat` free+inactive pages ≳ 4GB equivalent. Hard cap 2.
   `android-app`/`android-spike` items are width 1 **in practice** because only
   one AVD is booted by default (the `android` lease capacity = online-emulator
   count). Routing exists — `run-android-tests.sh` honors `ANDROID_SERIAL` and
   `sim-lease.sh acquire android` leases a distinct serial — so width 2 is
   possible once a **second AVD** is booted (rule 55 Android tier / rule 52).

## Step 1 — intake + the ephemeral ledger

Build the batch ledger IN CONTEXT (never persisted — durable state lives in
tracker rows, GH gate-timeline comments, `git worktree list`,
`scripts/sim-lease.sh status`, `scripts/agent-lock.sh status`):

```
| item | branch | write-set | device (UDID or emulator serial) | status | verdict/version |
```

Statuses: dispatched → returned → integrating → merged | requeued | escalated.
Update the row on every spawn and every HANDOFF.

For each candidate item:
- **Bug**: `scripts/deps-check.sh bug <id>` must say READY; micro-spec =
  repro + expected-vs-actual + regression-test name (+ bug-mode Phase 0.5:
  reproduce FIRST; one explicit root-cause line "the bug is X because Y";
  the RED test must fail for the bug's REASON; re-run the original repro
  after GREEN and record it in the HANDOFF's `notes_append`).
- **Feature WI**: read ONLY the plan's Spec blocks (never the plan body);
  `scripts/deps-check.sh feature <id>` READY; an intra-batch `depends:`
  edge counts as satisfied only when the dependency WI's branch has
  **MERGED** — not merely HANDOFF-returned or PR-opened (a returned branch
  can still bounce at integration).
- Write-sets must be pairwise-disjoint across the batch (compare `writes:`
  prefixes against every in-flight ledger row); overlap ⇒ serialize those
  items into later waves.
- **No new Swift files in a lane's write-set** (rule 55 Degrades): a new
  file needs the orchestrator-owned xcodegen structural regen, which the
  lane's test gate can't see and this tail has no post-regen retest for.
  Shape the item to extend an existing file; if a new file is genuinely
  unavoidable, the item is NOT dispatchable — route it inline
  (`/fix-issue` / `/feature-workflow`).

## Step 2 — pre-spawn checklist (a failed item blocks the SPAWN)

Per item, in order: main tree clean (pbxproj signing carve-out excepted) →
`scripts/worktree-setup.sh <id> <branch>` (records the ABSOLUTE path) →
GH issue exists with `GH: #N` stamped → **lease the device by platform**
(`code_paths_platform`): an iOS/`shared` item → `scripts/sim-lease.sh acquire
test` (record the UDID); an `android-app`/`android-spike` item →
`scripts/sim-lease.sh acquire android` (record the `emulator-NNNN` SERIAL) →
brief generated from the template below.

## Step 3 — the lane brief (generated, NEVER hand-written)

Every brief contains, in this order:

1. The rule-48 preamble VERBATIM with the worktree path substituted:

```
## CRITICAL OPERATIONAL — binding

Your worktree path is: <ABSOLUTE-WORKTREE-PATH>

Every `Bash` tool call you issue MUST begin with `cd "<ABSOLUTE-WORKTREE-PATH>"`.
Before your first edit or write, run `pwd` and confirm it prints the worktree
path. If `pwd` does NOT match, stop and report — do NOT attempt to recover by
guessing.

The Agent harness creates the worktree but does NOT set your initial cwd to
it. Your Bash tool starts with cwd = the orchestrator's main checkout. A
single Bash call that forgets the `cd` prefix can write to the main checkout
instead of your worktree; a later `xcodegen generate` then folds stray files
into `project.pbxproj` and breaks the build on every clean clone. Standing
precedent: PR #1029 (v3.37.19) was a hotfix for exactly this pattern.

This is binding for every Bash call, not just the first. Do not skip this in
the interest of brevity.
```

2. The six-field contract instantiated (objective = the one item; inputs =
   Spec block or micro-spec + exact file list + the leased device: `TEST_UDID`
   for iOS/`shared`, or `ANDROID_SERIAL=<emulator-NNNN>` for an Android item;
   allowed writes = the `writes:` prefixes; forbidden = rule 55's shared
   surfaces + "no Bash file edits" + nothing outside the write-set; output =
   the rule-55 HANDOFF JSON; stop = ready-for-integration or blocked).
3. **Skill-override clause**: the lane contract OVERRIDES any standing
   skill phases — no PR creation, no tracker edits, no close-gate, no
   version bump, no `git tag`; STOP at ready-for-integration + HANDOFF.
4. Test gate shape: iOS/`shared` → `TEST_UDID=<udid> scripts/run-tests.sh
   <targeted-suite>`; Android → `ANDROID_SERIAL=<emulator-NNNN> ANDROID_CMD="…"
   scripts/run-android-tests.sh` (the runner validates + re-exports the serial,
   so the connected task targets the leased emulator). Wrappers only, targeted
   only — never a bare `xcodebuild`/`gradle`.
5. Gate-4 ladder (probed 2026-07-09): `scripts/run-codex.sh` (rule 53) is
   the lanes' PRIMARY audit rung — custom agents have no Skill tool
   (probe: "Skill exists but is not enabled in this context") — artifact
   committed on the branch, ≤3 rounds then blocked. Long logs go to
   `<worktree>/.reports/` and travel as PATHS in the HANDOFF.
6. **Canon orientation** (rule 56 — read-routing, not read-forcing): run
   `scripts/canon-owner.sh <the lane's writes: prefixes>` and add each
   returned dossier path to the brief's inputs as READ-ONLY orientation —
   "read this dossier for cross-module context and known edge cases before
   editing; it is `verified`/`proposed` (not human-approved `canonical`), so
   reconfirm anything load-bearing against the live code."
   A lane NEVER edits canon — it is an orchestrator-owned surface like the
   trackers. A lane that finds a documented claim wrong or stale says so in the HANDOFF
   `notes`, and the orchestrator routes that to the next capture → compile
   pass — it does not edit the dossier from the lane.

Spawn a full wave in ONE message (both Agent calls together at width 2).

## Step 4 — HANDOFF validation + contamination check (per returned lane)

Validate against rule 55's JSON schema, then IMMEDIATELY run the first
contamination check (both probes — see "Contamination checks" below).

**One cleanup routine for EVERY non-ready outcome** (invalid HANDOFF,
missing HANDOFF, `outcome: failed`, `outcome: blocked`): release the lane's
lease (`scripts/sim-lease.sh release <udid-or-serial>` — the ledger's device
column, whichever kind the lane leased), tear down the worktree
(`scripts/worktree-teardown.sh <id>` — or preserve it with an explicit
"preserved for investigation" ledger note when the failure needs forensics),
update the ledger row, THEN requeue-once (fresh lane) or escalate per cause.
No exit path leaves a lease or an unaccounted worktree behind. Never argue
with a lane — re-brief once (rule 48) or collapse to inline.

## Step 5 — integration tail (serial, per lane, in ledger order)

Ordered so any failure before PR-open leaves ZERO shared-surface changes:

a. `scripts/check-write-set.sh <worktree> <declared-prefixes>` (+
   `CHECK_LANE_PLATFORM=<lane platform>`) — violations ⇒ requeue/escalate.
b. Rebase the branch on `origin/main` IN the worktree. Conflict ⇒
   `git rebase --abort`, requeue for serialized redo (fresh lane brief:
   "rebase onto current main and resolve"), no version burned, no PR.
c. Independent re-run of the lane's declared targeted suite — never trust the
   HANDOFF's RESULT line. iOS/`shared`: `TEST_UDID=<its udid>
   scripts/run-tests.sh <suite>`; Android: `ANDROID_SERIAL=<its serial>
   ANDROID_CMD="…" scripts/run-android-tests.sh`.
d. Apply `tracker_edit` + `docs_sync` yourself via Edit **on files under
   `<worktree>/`** (e.g. `<worktree>/docs/bugs.md`), committed on the lane
   branch with `git -C <worktree> commit` — the tracker/docs deltas ride
   the PR, never main. Take `scripts/agent-lock.sh acquire tracker-write`
   around the edit, release immediately after. New row IDs were minted via
   `scripts/reserve-id.sh` BEFORE taking tracker-write.
e. **Version-at-slot**: compute X.Y.Z NOW from the then-current
   `<worktree>/project.yml` + latest `v*` tag, applying the HANDOFF's
   `bump_tier`; never pre-assign (a requeued lane would shift every
   subsequent number). Edit `<worktree>/project.yml`, run
   `xcodegen generate` IN the worktree, commit both files with
   `git -C <worktree>` as the branch's LAST commit.
   **Pre-PR assertion**: `git -C <worktree> log origin/main..HEAD
   --oneline` shows fix + audit-artifact + tracker/docs + bump commits,
   AND the second contamination check (below) is clean.
f. `gh pr create` (HANDOFF as body, `Part of feature #N` / `Refs #N` per
   the merge-gate convention), then run `gh pr merge --squash`
   **FROM the lane worktree** — the audit-artifact hook checks the
   artifact as a filesystem path under the resolved root; merging from
   main false-blocks. And never pass `--delete-branch` (gh then checks
   out the default branch, which fails in a linked worktree — branch
   deletion is teardown's `--delete-branch` flag, post-merge only). On a
   NON-hook nonzero exit: `gh pr view --json state,mergeCommit` FIRST —
   never close-and-requeue an already-MERGED PR (network blips happen).
g. **Tag per PR, immediately**: on the MAIN checkout `git pull --rebase`
   (local main may carry cron finalizer chore(tracker) commits), resolve
   THIS PR's merge commit (`gh pr view --json mergeCommit`), tag its
   `vX.Y.Z` there, push the tag — after EACH successful merge, never a
   single batch-end tag pass (rule 40: every PR's bump gets its tag on
   its own merge commit; a batch-end pass can miss earlier PRs and
   corrupts version-at-slot's latest-tag input for the NEXT slot).
h. Lane cleanup: `scripts/sim-lease.sh release <udid-or-serial>` (the
   ledger's device column — an Android lane's `emulator-NNNN` serial lease
   releases through the same command) +
   `scripts/worktree-teardown.sh <id> --delete-branch` (post-merge).
   Batch ends with `sim-lease.sh status` clean.

After the last item: post the per-item GATE-TIMELINE comments on the GH
issues (rule 47's per-WI-merge rows — unrelated to this skill's step
numbering) and report the final ledger.

## Contamination checks (run at BOTH points: after each HANDOFF validation,
## and again in step 5e's pre-PR assertion)

BOTH probes, always:
- `git status --porcelain` on the main checkout (uncommitted contamination —
  the pbxproj class arrives via a later `xcodegen generate`).
- `git log origin/main..main --oneline` on the main checkout — only YOUR OWN
  chore/tracker/plan/evidence commits may appear. A drifted lane that
  COMMITTED from main-checkout cwd leaves `git status` clean; the log check
  is the only detector. Anything unexpected ⇒ quarantine the lane's output
  (do NOT merge), restore main, escalate.

## Step 6 — Gate 5 + release the lock

Release the `dispatch` lock BEFORE Gate-5 verification (rule 55: the lock
covers dispatch+integration only — the next batch's lanes may start while
verification runs). Verification uses `sim-lease.sh acquire verify` + the
verifier agent (observations only); you write evidence files and flip rows
under `tracker-write`.

## Context protection (binding in dispatch mode)

You never read: full diffs, run-tests logs, Codex rawOutput, sim
transcripts, or plan bodies (Spec blocks + HANDOFFs only). You never run
`git diff` beyond `--name-only`. MAY read: HANDOFF JSON, single tracker
rows (grep, never a full Read of the 499KB tracker), one-line gh results,
`RUN-* RESULT:` lines, `--name-only` lists, `<worktree>/.reports/` paths
(pass them on, don't open them).

## Within-WI fan-out is the ORCHESTRATOR's, never the lane's (rule 57)

A lane is a restricted-tool `implementer` subagent — no `Agent`/Workflow tool, and Workflow nesting
is one level — so a lane CANNOT fan out. Under ultracode, the analytical fan-out that rule 57
mandates (parallel context sweep, pre-write adversarial brainstorm, deep+broad audit) is front-loaded
by the **orchestrator** *before* dispatch (it already owns Gate-2's deep+broad plan audit) and folded
into the generated lane brief's Spec block. The lane then authors solo against a pre-hardened spec.
Never expect a lane to run a Workflow.

## Escalation

Audit round-3 failure, needs-design (rule 51 — file the `needs-design`
issue yourself), non-reproducible bugs, double-requeue → escalate to the
user with the ledger row + the lane's blockers. Lanes never make policy
decisions.

## Dropped by design — do not reintroduce

The pre-#130 fix-issue "Multi-Issue Pipeline" (M1–M5) is dead. Its
load-bearing defects, so a future rewrite can't regress into them:
- **Resumable two-way agents** ("integrator resumes each worktree-agent
  through Phases 7→8") — subagents are fire-and-forget with a single
  return; there is no resume. Lanes STOP at ready-for-integration.
- **Per-WI inline bump/PR by the worktree agent** — versions are
  orchestrator-allocated at the merge slot; lanes never touch project.yml.
- **Un-briefed spawns** — every lane gets the generated brief; there is no
  "the agent has context" shortcut (context absorption was the multi-issue
  design's silent failure).
