---
branch: feat/feature-60-wi-7c5b-epub-popover-swap
threadId: 019e2f39-5a40-7af3-b26c-277be2ce949e
rounds: 2
final_verdict: ship-as-is
date: 2026-05-16
---

# Codex Audit — Feature #60 WI-7c5b EPUB SelectionPopover producer/consumer swap

## Round 1 — 1 Low

### Low #1 — cache-lifecycle "clear on dismiss" spec gap
- **`vreader/Views/Reader/EPUBReaderContainerView.swift`** | Low
  Plan v10 WI-7c5b specified the token cache entry is "removed after
  consumption + on sheet dismiss". The implementation consumed on
  highlight/note action and replaced on a new selection, but a
  popover dismissed *without* an action left the last
  `ReaderSelectionEvent` resident until the next long-press. Codex:
  *"Token matching makes mis-routing unlikely, so this is not a
  correctness break today, but it is still spec drift."*

**Resolution**: Fixed. `SelectionPopoverPresenterModifier` gained an
optional `onDismiss: (() -> Void)?` wired straight into SwiftUI's
`.sheet(isPresented:onDismiss:content:)`. `selectionPopoverPresenter
(theme:onDismiss:)` gained the param (default `nil` — existing
TXT/MD/chunked attach sites unchanged). `EPUBReaderContainerView`
passes `onDismiss: { selectionTokenCache.clear() }`. On the dispatch
path the cache was already consumed by `resolve`, so `clear()` is an
idempotent no-op; on a genuine dismiss it drops the stale entry. The
deferred `.askAI`/`.read` actions keep the sheet open (dismiss
policy), so `onDismiss` correctly does NOT fire while the selection
is still active.

## Round 2 — clean

Codex verified: *"No findings. The round-2 change closes the only
issue from the first pass ... That brings the cache lifecycle back in
line with the WI-7c5b plan. WI-7c5b looks clean for merge."*

## Verdict statement

**ship-as-is** after round 1 (1 Low fixed). Round 2 clean.

All 8 audit dimensions clean:
1. Correctness — matches plan v10 WI-7c5b: producer at the container's `onSelectionEvent` closure (not the bridge coordinator), `EPUBSelectionTokenCache` single-entry round-trip, `.selectionPopoverPresenter` + tokenized `.onReceive` handlers, `handleHighlightAction(color:)`, legacy `confirmationDialog` removed, Copy dropped (accepted product decision).
2. Edge cases — nil token / wrong token / replayed notification / same-text-different-anchor / replace-on-new-selection / clear — all exhaustively pinned by `EPUBSelectionTokenCacheTests` (11 tests). Clear-on-dismiss closed in round 1.
3. Security — none (NotificationCenter; no JS interpolation touched).
4. Duplicate code — `handleHighlightAction`'s fallback now mirrors `handleHighlightWithNote`'s fallback (`persistence.addHighlight` direct call). Codex did not flag it — the two are genuinely parallel highlight-vs-highlight+note paths.
5. Dead code — `EPUBHighlightActions.persistHighlight` removed (no remaining caller after the fallback switched to `addHighlight` directly); its test suite + `SpyHighlightStore` + `makeTestEvent` removed with it. `UIKit` import retained (still needed for `UIApplication`).
6. Shortcuts / patches — the `TextSelectionInfo(startUTF16: 0, endUTF16: utf16.count)` placeholder in the producer is not a landmine: EPUB highlight/note consumers ignore the offsets and use the cached `ReaderSelectionEvent`; Translate uses only `selectedText`. Codex confirmed.
7. VReader compliance — Swift 6 (`@State` cache mutated only on main-actor paths — `onSelectionEvent` + SwiftUI `.onReceive`); `ReaderSelectionEvent` is `Sendable`. `EPUBReaderContainerView.swift` is ~415 lines, pre-existing over the ~300 guideline; WI-7c5b is roughly net-neutral on its size (removed the 22-line `confirmationDialog`, added the presenter attach + 2 `.onReceive` handlers). New `EPUBSelectionTokenCache.swift` is 70 lines.
8. Bridge safety — `onSelectionEvent` is a `@MainActor` callback from `EPUBWebViewBridge.Coordinator`; the producer closure runs on MainActor. No JS bridge code changed.

## Observer-isolation verification (Codex confirmed)

- `.readerHighlightRequested` / `.readerAnnotationRequested` have only one other observer — `ReaderNotificationModifier` — attached to TXT/MD containers only, NOT EPUB. The EPUB container's new `.onReceive` handlers are the sole EPUB consumers; no double-handling.
- `.readerTranslateRequested` is handled by the parent `ReaderContainerView` — the popover's Translate action works for EPUB with no EPUB-specific handler.

## Test results

- WI-7c5b suites: 44 tests pass across 5 suites — `EPUBSelectionTokenCacheTests` (11), `SelectionPopoverPresenterTests` (9), `SelectionPopoverActionRouterTests` (14), `EPUBHighlightActionsCreateJSTests` (3), `EPUBHighlightActionsRestoreTests` (7).
- Full `vreaderTests` gate: WI-7c5b code clean. The 5 full-gate failures were all pre-existing flakes:
  - `DebugReaderRegistryAwaitReaderTests` (`case2`/`case5` `.awaitReaderTimeout`) — **confirmed fails identically on the stashed `main` baseline** (instant ~0.007s timeout) — a pre-existing feature-#49 test flake, not a WI-7c5b regression.
  - `SearchWiringTests`, `LazyDownloadReattachTests`, `EPUBReaderViewModelTests` — passed in the isolated re-run; parallel-execution cross-fire flakes (same class documented in WI-7c2's audit log).

## Strengths called out by Codex

- Producer ownership at the container level (not the bridge coordinator) is the cleaner boundary — the bridge stays presentation-agnostic.
- `handleHighlightAction(..., color:)` threads the popover color through both the coordinator and the fallback paths correctly.
- The token-identity model means same-text selections at different DOM anchors are distinguishable — the whole reason the WI-7c5 decomposition rejected cache-by-`selectedText`.

## Follow-up items

- **Pre-existing flake `DebugReaderRegistryAwaitReaderTests`**: `case2_registerAfterInstall_resumesWaiter` + `case5_multipleWaiters_singleRegisterResumesAll` fail with an instant `.awaitReaderTimeout` on `main` baseline (feature #49 WI-7a). Out of WI-7c5b scope; noted for the bug-fix cron.
