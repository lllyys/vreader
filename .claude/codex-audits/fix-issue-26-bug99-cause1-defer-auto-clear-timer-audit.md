---
branch: fix/issue-26-bug99-cause1-defer-auto-clear-timer
threadId: 019dfd4d-956a-7ed1-9d68-c241e3b50c04
rounds: 2
final_verdict: ship-as-is
date: 2026-05-06
---

# Codex audit — bug #99 cause #1 (chunked reader auto-clear timer race)

## Round 1

**Findings**:

| File:Line | Severity | Issue | Resolution |
|---|---|---|---|
| `vreader/Views/Reader/TXTChunkedHighlightHelper.swift:137` | Medium | `clearHighlight(in:)` cleared timer + pending flag but did NOT clear `activeHighlightChunkIndex` / `activeHighlightLocalRange`. If a highlight was applied to an off-screen chunk and then explicitly cleared before render, a later `cellForRowAt` would still see `active != nil` and redraw the stale highlight. | **Fixed in round 2** — `clearHighlight(in:)` now also nils `activeHighlightChunkIndex` / `activeHighlightLocalRange`. The auto-clear timer's closure simplifies because `clearHighlight` is now the single reset path. |
| `vreaderTests/Views/Reader/TXTChunkedHighlightDeferredTimerTests.swift:25` | Low | Tests covered pending/timer bookkeeping but did not exercise the `cellForRowAt` render-time path — the actual seam where the deferred timer starts. | **Fixed in round 2** — 3 new tests added: `clearHighlight_fullyResetsActiveState`, `cellForRowAt_pendingChunkRender_startsTimer`, `cellForRowAt_unrelatedChunk_doesNotStartTimer`. The render-path tests set up a real UITableView with the Coordinator as dataSource + delegate, then manually invoke `cellForRowAt` to drive the seam. |

**Verdict round 1**: `follow-up-recommended`.

## Round 2

After applying the round-1 fixes:

**No findings.**

Codex round-2 confirmation:

> The round-1 medium issue is closed: `clearHighlight(in:)` now fully resets timer, pending, and active highlight state, so an off-screen row rendered after an explicit clear no longer redraws stale highlight. The timer closure simplification is also correct because `clearHighlight(in:)` is now the single reset path.
>
> The round-1 test gap is also closed: the new tests add direct coverage for full reset plus both `cellForRowAt` branches, which are the critical render-time transitions for this bug.

**Verdict round 2**: `ship-as-is`.

## Other audit dimensions confirmed

- Core fix correct: visible-cell apply still starts immediately, invisible-cell apply defers, later render starts the 3 s clock, permanent highlights still skip timers.
- `scrollViewDidScroll` doesn't interact with highlight state — no race there.
- Rapid repeated `applyHighlight` calls effectively serialized on main thread; "invalidate + clear pending first" makes the latest highlight win.
- `active != nil` check in cellForRowAt is defensive (now that clearHighlight fully resets, index match alone would suffice — but defensive is fine).
- Test file at `vreaderTests/Views/Reader/` mirrors source path; all `@MainActor` since UITableView. Idiomatic.
- No memory leak risk — Int? value type, no retain cycle.

## Summary

Bug #99 cause #1 fixed:
- Auto-clear timer no longer races against scroll completion.
- Pre-fix: timer started in applyHighlight even when target cell wasn't visible — slow scroll could let the timer fire before the user saw the highlight.
- Post-fix: `pendingAutoClearForChunk` defers timer start to `cellForRowAt` (the actual cell-render moment).

Round-1 audit also caught a pre-existing leak in `clearHighlight` (didn't fully reset active state). Round-2 fix consolidates: `clearHighlight` is the single reset path; `startHighlightAutoClearTimer`'s closure simplifies accordingly.

8 tests in the new test file (5 from round 1 + 3 round-2 cellForRowAt + clear-fully-resets coverage).

Causes #2 (encoding offset mismatch) and #3 (programmaticScrollCount timing race — already fixed in PR #263) of bug #99 stay separate; this PR closes only cause #1.
