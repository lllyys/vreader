---
branch: fix/issue-443-txt-search-highlight-orphan-state
threadId: manual-fallback
rounds: 1
final_verdict: follow-up-recommended
date: 2026-05-08
---

## Summary

Manual audit per `/fix-issue` Phase 4f — Codex MCP unavailable (stream disconnected on the availability ping). The fix is a 5-line `@State` wiring rename in one production file plus 4 regression-guard tests in a new test file. The bug was filed earlier today (2026-05-08T22:57) by the verify cron with a complete root-cause analysis and an explicit fix sketch; this PR implements that sketch verbatim.

## Manual Audit Evidence

### Files read (production)

- `vreader/Views/Reader/TXTReaderContainerView.swift` (whole file, ~600 lines) — focus on lines 55-90 (the `@State` declarations) and lines 463-532 (the `readerContent` / `chapterReaderContent` / `chunkedReaderContent` bridge wiring).
- `vreader/Views/Reader/TextReaderUIState.swift` (whole file) — confirmed `highlightRange: NSRange?` (line 31) and `highlightIsTemporary: Bool = true` (line 33) are `var` properties on the `@Observable @MainActor` class.
- `vreader/Views/Reader/ReaderNotificationModifier.swift` (lines 30-50) — confirmed the `.readerNavigateToLocator` handler writes `uiState.highlightRange` and `uiState.highlightIsTemporary`.
- `vreader/Views/Reader/MDReaderContainerView.swift` (lines 308-318) — confirmed `uiState.highlightRange` is the correct wiring; this is what TXT now matches.
- `vreader/Views/Reader/ReaderNotificationHandlers.swift` (lines 95-111) — confirmed `handleNavigateToLocator` sets `state.highlightIsTemporary = true` and `state.highlightRange = NSRange(...)` when both `charRangeStartUTF16` and `charRangeEndUTF16` are present on the locator.

### Files read (tests)

- `vreaderTests/Views/Reader/ReaderNotificationHandlerTests.swift` (lines 89-134) — existing tests already cover the handler-level assertion that `state.highlightRange` is set correctly when `.readerNavigateToLocator` fires with a TXT-shaped locator. The orphan-state bug was at the wiring layer above these tests, not in the handler logic.

### Symbols / signatures verified

- `TXTTextViewBridge.init(...)` accepts `highlightRange: NSRange?` and `highlightIsTemporary: Bool` — matched by `TextReaderUIState`'s field types.
- `TXTChunkedReaderBridge.init(...)` accepts the same parameters with the same types — matched.
- `@Observable` on `TextReaderUIState` ensures SwiftUI re-renders any view body that reads its tracked properties. `readerContent` and `chunkedReaderContent` now read `uiState.highlightRange` and `uiState.highlightIsTemporary`, so the wiring will reactively update when `ReaderNotificationModifier` mutates them.
- `@MainActor` on both `TextReaderUIState` and the view containing `readerContent`/`chunkedReaderContent` — no actor-hop concern.

### Audit dimensions (1-8)

1. **Correctness & logic** — the fix solves the root cause: orphan local `@State highlightRange` / `highlightIsTemporary` in `TXTReaderContainerView` are removed; bridge wiring now reads `uiState.highlightRange` / `uiState.highlightIsTemporary`, which is the actual mutation target of `ReaderNotificationModifier.readerNavigateToLocator` handler. Same wiring shape as the already-correct `MDReaderContainerView.swift:312`.
2. **Edge cases** — `uiState.highlightRange` is `NSRange?` (same nullability as the orphan) and `uiState.highlightIsTemporary` defaults to `true` (same default). Behaviour preserved for all states (nil range → no highlight; non-nil range → temporary yellow highlight with auto-clear at 3s). The chapter-mode path at `chapterReaderContent` (line 495 of the original) intentionally hard-codes `highlightRange: nil` — that's a separate WI-7 deferred concern noted in a comment in the file, untouched by this fix.
3. **Security** — N/A (no JS, no string interpolation, no network/IO; one file's `@State` rename + 4 read-only test functions that load a source file via `#filePath` and check substring presence).
4. **Duplicate code** — fix REMOVES duplication (two `@State`s for the same conceptual field). No new duplication introduced.
5. **Dead code** — confirmed `@State private var scrollToOffset: Int?` at line 60 (renumbered to 60 in fixed file) is also an orphan with no assignments. It's read at lines 470/525 as the fallback in `uiState.scrollToOffset ?? scrollToOffset`. Effectively a `?? nil` after `uiState.scrollToOffset` is non-nil. Flagged but **NOT cleaned up** in this PR — outside the bug's scope, and removing it would change the parameter shape of two function calls. Recommend a follow-up housekeeping issue.
6. **Shortcuts & patches** — none. The fix is the canonical 5-line @State rewiring.
7. **VReader compliance** — Swift 6 concurrency: `uiState` is `@Observable @MainActor`, accessed only from `@MainActor` view bodies. ✓. File size: `TXTReaderContainerView.swift` is ~600 lines (already over the 300-line guideline before this fix); the fix doesn't change size materially. Pre-existing scope for a future split.
8. **Bridge safety** — N/A (no JS bridge changes; no `evaluateJavaScript` callsites touched).

### Edge cases checked

- Notification fires before the view's first `body` render: `uiState` is constructed in the view's `@State var uiState = TextReaderUIState()` at view init time; the field is always reachable. ✓
- Notification fires while a persistent highlight is active: `applyHighlights(to:coordinator:)` at `TXTTextViewBridge.swift:233` takes both `persisted` and `active` ranges separately; the search-tap active range overlay is independent of persistent highlights. ✓
- Auto-clear timer fires at 3s: `TXTTextViewBridge.swift:144-152` schedules the timer when `highlightChanged && range.length > 0 && highlightIsTemporary`. With the fix, `highlightIsTemporary` flows from `uiState.highlightIsTemporary` (which the handler sets to `true`), so the 3s auto-clear will fire correctly. ✓
- Search-then-immediately-tap-another-result: each tap re-fires `.readerNavigateToLocator` → handler resets `uiState.highlightRange` to the new range, restarting the timer. ✓
- Empty / nil locator: handler at `ReaderNotificationModifier.swift:40-44` sets `uiState.highlightRange = nil` if `charRangeStartUTF16` / `charRangeEndUTF16` aren't both present. The bridge sees `nil` → `applyHighlights` is a no-op for active range. ✓

### Risks accepted

- Pre-existing test failures in unrelated suites (`AutoPageTurner`, `PersistenceActor — Bookmarks/Highlights`, `TTSService Speed Control`, `PhaseBMediumAudit`) — verified these fail on `main` BEFORE this PR (ran the same `-only-testing` flags after `git stash + git checkout main`; same `TEST FAILED` outcome). Outside this PR's scope.
- The orphan `@State private var scrollToOffset: Int?` at line 60 is left in place. It's harmless (always `nil`, used as a fallback in `?? nil`) and removing it is out of scope for the bug being fixed. Future PR.

### Tests added

- 4 new tests in `vreaderTests/Views/Reader/TXTReaderContainerSearchHighlightWiringTests.swift` (Swift Testing, ~85 LOC):
  - `orphanLocalHighlightRangeStateIsRemoved` — fails if the orphan `@State private var highlightRange: NSRange?` declaration ever returns.
  - `orphanLocalHighlightIsTemporaryStateIsRemoved` — fails if the orphan `@State private var highlightIsTemporary: Bool` declaration ever returns.
  - `bridgeWiringReadsHighlightFromUIState` — asserts ≥2 occurrences of `highlightRange: uiState.highlightRange` (one in `readerContent`, one in `chunkedReaderContent`).
  - `bridgeWiringReadsHighlightTemporaryFromUIState` — asserts ≥2 occurrences of `highlightIsTemporary: uiState.highlightIsTemporary`.
- Test discovery anchored via `#filePath` (compile-time literal) so the test works under both `xcodebuild` and Xcode IDE without depending on `SRCROOT` env-var (which isn't reliably set at simulator runtime).
- RED → GREEN cycle confirmed: all 4 tests fail on the orphan-state code; all 4 pass after the wiring rename.
- Pre-existing handler-level tests at `ReaderNotificationHandlerTests.handleNavigateToLocatorSetsScrollOffset` and adjacent already cover the state-mutation correctness on the upstream side; this PR adds the wiring-layer guard that was missing.

## Pre-FIXED runtime verify finding (post-write addendum, 2026-05-09T00:13Z)

When attempting Phase 6a pre-FIXED verify on iPhone 17 Pro Sim with the fixed build (v3.14.93, build 23:52:38), the original Position Test Book repro **still shows no yellow highlight** after search-tap. Investigation:

- Position Test Book has chapter markers (`Section 1`...`Section 100`) and triggers `hasChapterDisplay = true` (`TXTReaderViewModel.chapterIndex != nil`).
- The reader body branches at `TXTReaderContainerView.body`: chapter mode (`viewModel.currentChapterText != nil`) takes precedence over the small-file path (`readerContent`) and the chunked-large-file path (`chunkedReaderContent`).
- `chapterReaderContent` at line 496 hardcodes `highlightRange: nil // Highlight offset translation is WI-7`. **My fix does not touch this path** — it only re-wires `readerContent` (line 472) and `chunkedReaderContent` (line 527).
- Bug #154's original analysis listed `chapterReaderContent` (line 526 in its description) as one of the orphan call sites, but the on-disk source has chapter at 496 with hardcoded nil; the orphan was actually feeding `readerContent` + `chunkedReaderContent`. The verify cron's analysis conflated two distinct concerns: (a) orphan `@State` in non-chapter paths (real, my fix addresses), and (b) chapter-mode global→local offset translation (WI-7, deferred work).

**Implication for the originally-reported repro**: tapping search results in chapter-mode TXT files (Position Test Book, war-and-peace, any chaptered novel) will continue to show no highlight at the destination, **but for WI-7 reasons, not orphan-@State reasons**. My fix correctly addresses the orphan @State for non-chapter TXT files (small unchaptered files using `readerContent`; very-large unchaptered files using `chunkedReaderContent`).

No non-chapter TXT fixture exists in `vreader/Resources/DebugFixtures/` to runtime-verify the readerContent/chunked paths against. The 4 regression-guard tests in `TXTReaderContainerSearchHighlightWiringTests.swift` pin the wiring at source level — that is the verification anchor for this PR.

## Verdict

**follow-up-recommended**. The orphan-@State portion of bug #154 is genuinely fixed by this PR; the chapter-mode portion (the only one runtime-observable on the project's existing test fixtures) requires WI-7 (separately scoped). Audit dimensions 1-8 all clean. New tests pin the wiring contract. No new failures introduced. The PR ships as a partial fix; bug #154 stays open as `PARTIALLY FIXED` with the WI-7 dependency tracked as a separate feature row.
