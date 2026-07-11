# 56 — Agent ↔ Canon Collaboration

How every agent (interactive, cron, dispatch lane) reads from and keeps fresh
the bureau knowledge base under `canon/` (compiled by the 2026-07-11 codebase
audit; workspace + trust-tier rules in `BUREAU.md`). The thesis: **route reads,
don't force them; funnel writes, never write direct.** Blanket "read the whole
canon before acting" is unverifiable friction; unreviewed post-hoc dossier
writes dilute the trust tiers that make the canon usable. Four enforcement
points, each mechanical where it can be, plus two hard prohibitions.

## Trust tiers (from `BUREAU.md`, restated because they gate everything here)

`canonical` = human-approved, treat as fact. `verified` = auto-checked against
the repo, not yet human-approved — usable but reconfirm anything load-bearing.
`proposed`/`stale`/`contested` = NOT fact, verify before relying. Only a human
(`bureau:review`) writes `canonical`; AI writes `proposed`/`verified`/
`contested`/`stale`.

## Read side — route, don't force

1. **Sessions**: `CLAUDE.md` imports `BUREAU.md`, so every session already
   carries the consult-before-deriving instruction. Before deciding something
   the repo may have settled (an architecture choice, a convention, a prior
   call), `bureau:query` first instead of re-deriving. No extra machinery.
2. **Dispatch lanes**: the `/dispatch` brief generator runs
   `scripts/canon-owner.sh <the lane's writes: prefixes>` (which resolves paths
   to owning dossiers via `canon/_coverage-ledger.json`) and injects the
   returned dossier path(s) into the lane brief as READ-ONLY orientation inputs
   — "read for cross-module context and known edge cases before editing;
   reconfirm load-bearing claims against the live code." This is the *relevant*
   page arriving as a contract input, not a vague instruction. Enforced by
   `scripts/__tests__/dispatch-shape.test.sh` (asserts the brief carries the
   `canon-owner.sh` clause + the lane-never-edits-canon guard). See rule 55.

## Write side — funnel through capture → compile → review

3. **Capture is automatic, per session.** The bureau plugin self-registers a
   `SessionEnd` hook (`capture-stub.mjs`) that writes a mechanical logbook stub
   for every session — write-after-action already happens at session
   granularity. Rich `bureau:note` capture is for sessions that produced
   durable knowledge (a decision, a resolved question); most bugfix/verify cron
   runs produce none and need no note.
4. **Compile is periodic, not per-action.** `bureau:compile` distils the
   accumulated minutes into dossier updates on a cadence (or piggybacked on a
   maintenance pass) — never once per edit. Compile is where claims are placed,
   conflicts become `contested`, and checkable facts are re-verified.
5. **Staleness is detected, not hoped for.** `canon/_verify.json` holds a
   sha256 of every artifact behind each `verified` page. The watchdog cron runs
   `scripts/canon-staleness.sh --apply` (rule-56 step in `watchdog.md`): it
   re-hashes those artifacts and demotes any page whose **code** evidence
   drifted to `stale` (a legal AI tier). High-churn provenance files
   (`docs/features.md`, `docs/bugs.md`, `docs/tasks.md`,
   `archive/bugs-history.md`) are advisory only — a page cites them for
   bug/feature numbers, and their churn does not invalidate its claims about the
   code. `canonical` pages are never touched. A demoted page waits for the next
   compile/verify pass; it is never silently rewritten by the sweep.

## Lane contribution — propose, don't write

A lane that discovers a documented claim is wrong or stale reports it in the
rule-55 HANDOFF `notes` field. The orchestrator routes that into the session
minute (capture), and the next `bureau:compile` reconciles it. Canon is an
orchestrator-owned surface like the trackers, `project.yml`, and the tags —
lanes never edit it directly (sed/heredoc or Edit alike).

## Hard prohibitions

- **No PreToolUse hook that blocks an action until "the canon was read."** It is
  unverifiable (there is no signal that a read happened or that it was the right
  page) and is pure friction. Read-routing (point 2) is the mechanism; a
  blocking gate is not.
- **No per-action dossier writes.** An agent finishing a task does not append to
  or edit a dossier. That violates the one-writer rule (rule 48), churns the
  `verified` corpus (any substantive edit demotes a page — see
  `Decision — composite dossier schema`), and skips the review gate. Durable
  knowledge goes to the logbook (capture) and reaches the cabinets only through
  compile.

## What this rule does NOT change

Trust tiers and the write gate (`BUREAU.md`), the compile/review skills, TDD
(rule 10), the six gates (rule 47), lane dispatch (rule 55). This rule is only
the read-routing + freshness contract layered on top.
