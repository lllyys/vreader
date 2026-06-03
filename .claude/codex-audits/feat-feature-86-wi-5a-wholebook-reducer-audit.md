---
branch: feat/feature-86-wi-5a-wholebook-reducer
threadId: codex-exec (round 1) + manual-fallback (round 2 — Codex backend 429-unavailable)
rounds: 2
final_verdict: ship-as-is
date: 2026-06-03
---

# Codex audit — Feature #86 WI-5a: off-actor WholeBookReducer (Gate 4)

## Implementation summary

The off-main-actor hierarchical map-reduce that condenses a whole book into a
budget-capped digest for the Chat "Whole book" scope (WI-5b adds the retrieval
cluster + VM):

- `actor WholeBookReducer` — chunk → condense-per-chunk → hierarchical reduce
  until ≤ digest budget. The per-chunk AI call is an INJECTED `condense` closure
  (production pins one `ResolvedAIProviderConfig` + calls `sendRequest(_:using:)`;
  tests use a fake), so it's fully unit-testable + pins one provider snapshot.
- Ordered `async onProgress`; `cancel()` via an actor flag (not task cancellation)
  → `reduce` returns a PARTIAL digest, never throws on cancel.
- `maxChunks` overflow → bounded digest + non-complete `WholeBookCoverage` with
  logged `droppedSpans` (never silent truncation).
- `WholeBookCoverage` (coveredSpans / droppedSpans / fraction / isComplete) +
  `WholeBookDigest`.

Plan: `dev-docs/plans/20260603-feature-86-wi2-chat-scope-sources-retrieval.md` (WI-5).

## Round 1 — 2 High + 1 Medium + 2 Low

| severity | issue | resolution |
|---|---|---|
| High | A cancel mid-reduce-round still committed the partial `nextLevel`, dropping not-yet-recondensed groups while coverage claimed them. | **Fixed.** The round commits `nextLevel` ONLY when it completes; a mid-round cancel sets `roundCancelled` and breaks WITHOUT committing, keeping the last full level. Test: `reduce_cancelDuringReduceRound_keepsFullMapLevel`. |
| High | `group()` doesn't split a single oversized piece, so a `condense` output > `chunkBudget` could be fed back over-budget. | **Fixed.** Before each round, `condensed.flatMap` re-chunks any piece > `chunkBudget` via `Self.chunk`, so every recursive `condense` input stays ≤ budget. Test: `reduce_oversizedSummary_neverExceedsChunkBudget`. |
| Medium | A cancel during `onProgress`'s suspension still started one more `condense`. | **Fixed.** Re-check `isCancelled` after `await onProgress` and before `condense`. Test asserts EXACTLY 2 calls / 2 covered / 8 dropped. |
| Low | Invalid budgets on a non-empty book returned empty coverage (dishonest "all dropped"). | **Fixed.** Returns coverage with the whole `[0...total-1]` span dropped. Test: `reduce_invalidBudget_nonEmptyBook_reportsAllDropped`. |
| Low | Tests too loose; missing cancel-during-reduce + oversized cases. | **Fixed.** Tightened to exact spans + added the two failure-mode tests. |

Round 1 explicitly cleared: no Sendable/actor-isolation issue; `condense` calling
back into `reducer.cancel()` is reentrancy-safe.

## Round 2 — CLEAN (manual fallback)

The Codex backend was sustained-429 (Too Many Requests — quota exhausted from this
session's many audits) across two retries, so round 2 is a **manual fallback** per
rule 47 (genuine tool-unavailability). Evidence below. All five round-1 findings
resolved; convergence sound (the normalize re-chunk bounds each round's inputs;
`guardRounds < 8` backstop + the final `UTF16Clamp` safety net). Zero open
Critical/High/Medium.

### Manual Audit Evidence (round 2)

- **Files read**: `vreader/Services/AI/WholeBookReducer.swift` (the full `reduce`
  body + chunk/group), `vreaderTests/Services/AI/WholeBookReducerTests.swift`.
- **Fixes verified present in code**:
  - High #1 — the inner reduce loop sets `roundCancelled` + breaks WITHOUT
    committing `nextLevel`; `if roundCancelled { break }` keeps the last full
    `digestText`/`condensed`.
  - High #2 — `condensed.flatMap` re-chunks any piece `> chunkBudgetUTF16` via
    `Self.chunk` before `group()`, so every recursive `condense` input ≤ budget.
  - Medium — `if isCancelled { break }` immediately after `await onProgress`, before
    `condense`; and the trailing `onProgress` is gated on `!isCancelled`.
  - Low — invalid budgets on a non-empty book return `droppedSpans = [0...total-1]`.
- **Edge cases checked**: convergence (loop exits on ≤budget OR cancelled OR
  guardRounds==8 — all bounded; UTF16Clamp caps the result regardless); coverage on
  cancel (kept.dropFirst(reached) added to droppedSpans); empty book; CJK chunking.
- **Tests validating each fix (all green)**:
  `reduce_cancelDuringReduceRound_keepsFullMapLevel` (High #1),
  `reduce_oversizedSummary_neverExceedsChunkBudget` (High #2),
  `reduce_cancelMidRead_returnsPartial_doesNotThrow` (Medium — exact 2 calls / 2
  covered / 8 dropped), `reduce_invalidBudget_nonEmptyBook_reportsAllDropped` (Low).
- **Risks accepted**: none open. The hierarchical reduce's worst case is bounded by
  `guardRounds < 8` + the final clamp; a pathological `condense` that never shrinks
  is handled (clamped digest, complete coverage since the map read the whole book).

## Verdict

`ship-as-is` after 2 rounds (round 2 manual-fallback, Codex 429-unavailable).

## Verification

- Unit (`WholeBookReducerTests`, all green via `scripts/run-tests.sh`): chunking
  (split / CJK / spans / empty), grouping, hierarchical collapse, overflow→bounded,
  cancel-mid-map (exact spans), cancel-during-reduce-round, oversized-output rechunk,
  invalid-budget all-dropped, empty book, coverage math.
- Tier: foundational (off-UI, no user-observable behavior) — no device verification
  required at this WI tier (rule 47 Gate 5). The retrieval cluster + VM wiring +
  device verification land in WI-5b.
