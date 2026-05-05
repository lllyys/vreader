---
branch: fix/132-tts-highlight-coordinator-wiring
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-06
---

## Manual audit evidence

High-severity wiring bug. The TTS sentence-highlight coordinator was completely orphaned — instantiated (in MD only) but never invoked. Manual audit performed.

### Files changed

| File | Change |
|---|---|
| `vreader/Views/Reader/MDReaderContainerView.swift` | Added `onChange(of: ttsService?.currentOffsetUTF16)` + `onChange(of: ttsService?.state)`. |
| `vreader/Views/Reader/TXTReaderContainerView.swift` | Added missing coordinator instantiation in `.task`; added the same two onChange observations. |
| `docs/bugs.md` | New row #132 (FIXED, High, GH: #283). |

### Why this was bad

`grep -rn 'updateHighlight'` against production code (excluding tests) returns zero hits. The coordinator's entire purpose is to update `uiState.highlightRange` and `uiState.scrollToOffset` based on TTS position; without invoking `updateHighlight`, neither effect ever happened. Features #40 and #41 looked DONE on paper but produced no user-visible behavior at runtime.

### What's now wired

For each view (MD and TXT):

```swift
.onChange(of: ttsService?.currentOffsetUTF16) { _, newOffset in
    guard let newOffset, let coordinator = ttsHighlightCoordinator else { return }
    if let text = viewModel.{renderedText|textContent} {
        coordinator.ensureConfigured(text: text)
    }
    coordinator.updateHighlight(offset: newOffset)
}
.onChange(of: ttsService?.state) { _, newState in
    if newState == .idle {
        ttsHighlightCoordinator?.clearHighlight()
    }
}
```

The lazy `ensureConfigured` call inside the offset observer means the O(n) sentence tokenization happens on the FIRST TTS position update, not on book open — preserving the performance fix the coordinator was designed for.

### Edge cases checked

- **TTS not enabled**: `ttsService` is optional; `?.currentOffsetUTF16` is nil → onChange doesn't fire on initial nil. Coordinator stays inert. No regression.
- **Coordinator nil** (no TTS service injected): guard returns; safe.
- **Source text not yet loaded**: `viewModel.textContent`/`renderedText` is nil → ensureConfigured is skipped; updateHighlight runs against an empty `sentenceRanges` array; binary search returns nil; uiState unchanged. Safe but no highlight until text loads — when text DOES load, the next TTS offset update triggers ensureConfigured and the system catches up.
- **State transitions** (.speaking → .paused → .speaking): `updateHighlight` itself short-circuits when state != .speaking; the .idle clear path explicitly resets via `clearHighlight`. Pause leaves the existing highlight visible (matches user expectation — pause is "where I am right now").
- **TXT chapter mode**: `viewModel.textContent` is the current chapter's text in chapter mode. TTS feeds offsets relative to that chapter. Highlight aligns. (TTS in chapter mode wraps at chapter boundaries, but that's an existing behavior of TTSService, not introduced here.)

### What I deliberately did NOT change

- TTSHighlightCoordinator itself: zero production-code change, just wiring.
- The `static func tokenizeSentences`: kept static. It's a pure function; no state needed.
- EPUB and PDF readers: out of scope. The coordinator's doc explicitly says "TXT/MD only — EPUB/PDF deferred". This PR honors that.

### Tests added

None. The coordinator has its own test suite (TTSHighlightCoordinatorTests.swift). The wiring in views is SwiftUI .onChange handlers — view-test coverage is high-cost low-value at this layer.

### Verdict

**ship-as-is**. Fixes a high-severity gap (entire feature non-functional). 4 SwiftUI handler additions; 1 line of instantiation in TXT. No new abstractions, no risk of regression.
