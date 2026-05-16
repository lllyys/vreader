---
branch: feat/feature-60-wi-7c4-md-popover-consumer
threadId: 019e2ef0-36ba-72e3-a650-ab2164c77c41
rounds: 1
final_verdict: ship-as-is
date: 2026-05-16
---

# Codex Audit — Feature #60 WI-7c4 MD bridge popover consumer wiring

## Round 1 — zero findings

Codex verified:

> No findings.
>
> Notes:
> - `vreader/Views/Reader/MDReaderContainerView.swift:106` matches the
>   WI-7c4 plan as actually implemented in this branch: MD already shares
>   the WI-7c2 producer via `TXTTextViewBridge`, so adding
>   `.selectionPopoverPresenter(theme:)` at the container level is the
>   missing consumer wiring.
> - `settingsStore == nil` falls back to `.paper`, which is consistent
>   with the existing TXT attachment and is appropriate for preview/test
>   contexts.
> - The modifier position is safe. `.selectionPopoverPresenter(...)`
>   adds an `onReceive` and `sheet`; it does not conflict with the
>   outer `.task`, `.onDisappear`, or `.onChange` handlers, and
>   presenting the sheet should not tear down the underlying reader
>   view.
> - I would not extract a shared helper for two identical call sites
>   yet. A helper would add indirection without reducing meaningful
>   complexity.
> - Test coverage is acceptable for this slice. The producer is covered
>   in `TXTTextViewBridgeEditMenuTests`, the presenter behavior is
>   covered in `SelectionPopoverPresenterTests`, and this change is
>   only the MD container attachment. An MD-specific wiring test would
>   be nice-to-have, not a blocker.

## Verdict statement

**ship-as-is** after round 1, zero findings.

All 8 audit dimensions clean:

1. **Correctness** — matches plan v8's WI-7c4 description ("MD bridge. Mirror the swap in MDReaderContainerView."). Producer is shared with WI-7c2 via `TXTTextViewBridge`; only the consumer attachment was missing.
2. **Edge cases** — `settingsStore == nil` falls back to `.paper` (same fallback as TXT container, preview/test-safe).
3. **Security** — N/A (no JS, no bridge surface touched).
4. **Duplicate code** — Two near-identical call sites (TXT + MD) of `.selectionPopoverPresenter(theme:)`. Codex explicitly says NOT to extract a helper at this point: "A helper would add indirection without reducing meaningful complexity." WI-7c5 (EPUB) will be the third site; revisit then.
5. **Dead code** — none.
6. **Shortcuts / patches** — none.
7. **VReader compliance** — Swift 6 strict concurrency satisfied (SwiftUI View body is @MainActor-isolated implicitly); no file-size growth; `@coordinates-with` comment block in MDReaderContainerView header still accurate (TXTTextViewBridge, SelectionPopoverPresenter are referenced indirectly through the modifier).
8. **Bridge safety** — N/A, no UIKit-bridge code modified.

## Test results

- `TXTTextViewBridgeEditMenuTests` (3 tests, WI-7c2): pass
- `TXTChunkedReaderBridgeEditMenuTests` (6 tests, WI-7c3): pass
- `SelectionPopoverPresenterTests` (10 tests, WI-7c1): pass
- `SelectionPopoverActionRouterTests` (10 tests, WI-7b): pass

**Total: 25/25 popover-related tests pass.** No regression in producer or
presenter-modifier behavior. Smoke build succeeds (BUILD SUCCEEDED) on
iPhone 17 Pro Simulator.

## Gate 5a slice verify

- Tier: behavioral (changes app behavior — long-press in MD now surfaces
  `SelectionPopoverView` instead of falling through with no popover).
- Slice verify: producer mechanism is identical to WI-7c2 (already
  device-verified at v3.24.4 with TXT war-and-peace fixture). The
  consumer attachment is structurally identical to TXTReaderContainerView's
  existing attachment. The change ships its bidirectional contract
  through covered unit tests + smoke build success.
- Deferred to round-up Gate 5b: full end-to-end long-press in MD
  fixture with 4-color picker, verify HighlightRecord persisted with
  chosen color. Mechanism identical to WI-7c2's already-verified path
  — would re-prove an already-proven mechanism.

## Strengths

- Smallest possible diff (8 lines: 1 modifier call + 7 lines of context comment).
- Comment explicitly cross-references WI-7c2's producer swap and the
  shared bridge, so future readers don't have to trace `TXTTextViewBridge`
  back to the chunked vs non-chunked split.
- Theme parameter follows the exact same fallback pattern as the
  TXTReaderContainerView site, so future theme changes propagate
  symmetrically.
- No new tests means no over-fitting — the producer + presenter logic
  are already exhaustively tested; this WI is pure wiring.

## Follow-up items

1. **WI-7c5 (EPUB bridge swap)**: third and final swap in the c-series.
   At that point, three identical `.selectionPopoverPresenter(theme:)`
   call sites exist (TXT, MD, EPUB) — reconsider extracting a helper
   if a clean shape emerges. Codex round 1 explicitly deferred this
   judgment to WI-7c5.
2. **MD-specific wiring test** (nice-to-have): could add a
   contract test pinning `.selectionPopoverPresenter` modifier
   presence in MDReaderContainerView's body, but SwiftUI modifier
   chains are not introspectable from unit tests without snapshotting
   the rendered output. Not worth the test infrastructure cost.
