---
branch: fix/issue-765-foliate-create-overlay-restore
threadId: 019e2e96-980c-7092-8abb-695981e6258c
rounds: 3
final_verdict: ship-as-is
date: 2026-05-16
---

# Codex Audit — Bug #207 / GH #765 — AZW3/MOBI saved-highlight restore on book reopen

## Round 1 — 1 Medium

### Finding
- **`vreader/Views/Reader/FoliateSpikeView+Restore.swift:61-91` | Medium**
  Every `.foliateOverlayReadyForSection` event spawned an untracked
  `Task` that re-fetched the full highlight set and re-dispatched
  every CFI. If two sections fire close together (initial book open +
  immediate scroll), the un-coalesced version produced duplicate
  fetches. If the reader closed mid-flight, the work was not
  cancelled. Correctness mostly survives because JS `addAnnotation`
  is idempotent, but this is an avoidable race/perf hole.

### Fix applied
Switched the modifier to single-task / latest-wins coalescing:
- `@State private var restoreTask: Task<Void, Never>?`
- `scheduleRestore(forFingerprintKey:)` cancels the previous in-flight
  task before starting a new one (cancel-then-replace ordering is
  safe because the modifier is `@MainActor`-isolated).
- The new Task checks `Task.isCancelled` after the awaited
  `fetchHighlights` and bails before dispatching if a newer event
  superseded it.
- Added `.onDisappear { restoreTask?.cancel(); restoreTask = nil }`
  so view dismissal cancels work cleanly.

Codex round 2 verified: "two overlay notifications cannot mutate
restoreTask concurrently", "the post-`await` `Task.isCancelled`
check is sufficient", "`.onDisappear` is the right lifecycle hook".

## Round 2 — 1 Low

### Finding
- **`vreader/Views/Reader/FoliateSpikeView+Restore.swift:102` | Low**
  Normal cancellation may be logged as an error if `fetchHighlights`
  becomes cancellation-throwing. That would turn expected
  latest-wins churn or view dismissal into noisy logs.

### Fix applied
Added `} catch is CancellationError { return }` before the generic
`catch`. Catch order is correct (specific before generic). Real
persistence failures still log; cancellation churn returns silently.

## Round 3 — clean

Codex verified: "The catch order is correct... I don't see any new
issues in this change. The combination of cancel-then-replace on
@MainActor, Task.isCancelled after the awaited fetch, catch is
CancellationError, and .onDisappear cleanup gives the modifier the
right latest-wins behavior without noisy logs."

## Verdict statement

**ship-as-is** after rounds 1 (Medium → fixed via single-task
coalescing) and 2 (Low → fixed via CancellationError special-case).
Round 3 clean.

All 8 audit dimensions clean:
1. Correctness — the create-overlay → restore round-trip works
   end-to-end through parser → Coordinator → modifier → dispatcher →
   existing observer (Bug #201's JS-eval observer). Root-cause fix.
2. Edge cases — handled: concurrent section events (latest-wins),
   view close mid-flight (onDisappear), non-EPUB anchors (dispatcher
   filter), empty CFI (defense-in-depth filter), empty
   fingerprintKey (Coordinator guard + dispatcher guard).
3. Security — clean: dispatcher forwards CFI/color as plain strings;
   `FoliateHighlightRenderer` normalizes color and escapes both via
   `FoliateJSEscaper` before `evaluateJavaScript`. No new injection
   surface.
4. Duplicate code — clean: re-uses the existing
   `.foliateRequestAnnotationJSCreate` observer (Bug #201) rather
   than spinning a parallel JS path.
5. Dead code — clean.
6. Shortcuts / patches — none.
7. VReader compliance — clean: `@MainActor` on dispatcher enum,
   Swift 6 strict concurrency satisfied (test files use
   eagerly-extracted Sendable values across the
   `MainActor.assumeIsolated` boundary). New files each under 110
   lines; no growth of the already-over-threshold
   `FoliateSpikeView.swift` beyond a 39-line case (the new logic
   lives in the dedicated +Restore + dispatcher files per the
   established `+Selection` / `+HighlightTap` pattern).
8. Bridge safety — `parseCreateOverlay` handles non-dict / missing
   index / non-int index / index=0 correctly. The dispatcher's
   identity guard rejects empty `fingerprintKey`.

## Test results

- 5 `ParseCreateOverlayTests` pass
- 4 `FoliateSpikeViewCreateOverlayTests` pass
- 5 `FoliateHighlightRestoreDispatcherTests` pass
- Total new: 14/14 pass

Full `vreaderTests` run shows 2 pre-existing flaky failures
(`CoverLifecycleTests.deleteBook_noCrashWhenNoCoverExists` +
`SelectiveRestoreCoordinatorTests.preplant_partialSuccess_...`) —
both pre-existing NotificationCenter cross-fire under parallel test
execution, unrelated to Foliate/highlights. Documented in prior
audit logs.

## Strengths called out by Codex

- Reusing the existing create-annotation observer keeps the bridge
  surface small and avoids a second JS injection path.
- JS injection chain is safe end-to-end.
- Parser + Coordinator + pure fan-out tests pin the missing bridge
  contract well.
- Splitting restore logic into `+Restore.swift` and a separate
  dispatcher is the right move given `FoliateSpikeView.swift`'s size.
- Latest-wins is implemented in the right place: SwiftUI modifier
  owns async fetch lifecycle, dispatcher stays pure.
- Cancellation check is placed at the only point that matters for
  correctness: after the awaited fetch and before notification
  fan-out.
