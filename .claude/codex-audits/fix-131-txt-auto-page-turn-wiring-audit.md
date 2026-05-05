---
branch: fix/131-txt-auto-page-turn-wiring
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-06
---

## Manual audit evidence

Mechanical wiring fix — copy-paste the missing handlers from MDReaderContainerView into TXTReaderContainerView. Manual audit performed.

### Files changed

| File | Change |
|---|---|
| `vreader/Views/Reader/TXTReaderContainerView.swift` | Added 4 missing handlers + 1 bonus (interval live-apply). |
| `docs/bugs.md` | New row #131 (FIXED, Medium, GH: #281). |

### What was added (mirrored from MD)

1. `uiState.autoPageTurner?.pause()` appended to existing `.readerContentTapped` handler.
2. New `onReceive(.readerNextPage)` — page navigator advance + pause turner.
3. New `onReceive(.readerPreviousPage)` — page navigator back + pause turner.
4. New `onChange(of: settingsStore?.autoPageTurn)` — live-apply toggle.
5. **New (bonus)** `onChange(of: settingsStore?.autoPageTurnInterval)` — live-apply interval changes for an already-running turner. MD doesn't have this either; could be a follow-up there.

### Why it was missing

Auto-page-turn (B10) was originally implemented in MD reader. The TXT reader gained paged mode via the `epubLayout == .paged` flag (line 513-515) without porting the auto-turn handlers. Bug #82 was listed as the unblocker for #31 in features.md, but actually #82 only fixed the navigator-preserve race; the wiring port was a separate forgotten step.

### Edge cases checked

- **Non-paged TXT** (large files, scroll mode): the new `onReceive` handlers are guarded by `guard isPagedMode else { return }`. No behavior change for scroll-mode books.
- **autoPageTurner not yet created**: `uiState.autoPageTurner?.pause()` is optional-chained; safe if turner is nil.
- **autoPageTurn=false → turn off**: `updateAutoPageTurner(enabled: false, ...)` calls `autoPageTurner?.stop()` (per TextReaderUIState.swift:115). Live-toggle off works.
- **Interval change while turner is OFF**: bonus handler checks `autoPageTurn == true` first; if disabled, no-op. Correct.
- **`uiState.pageNavigator?.nextPage()` when navigator is nil**: optional-chained; if no navigator, the manual swipe is a no-op. Same shape as MD.

### What I deliberately did NOT change

- MD's missing interval-onChange handler: noting it in the audit but not fixing in this PR. Symmetric fix could be a follow-up if the MD interval-change UX gap is reported.
- Pause vs stop semantics: kept `pause()` (resumable from where it left off) rather than `stop()` (full reset). Matches MD.

### Tests added

None. The handlers are pure plumbing — call into existing `AutoPageTurner.pause()` / `updateAutoPageTurner()` which are already covered by AutoPageTurner's own behavior. Adding view-level tests for SwiftUI handlers is high-effort low-value.

### Verdict

**ship-as-is**. Mechanical port of 4 handlers from MD to TXT + 1 bonus interval handler. No new abstractions. Safe.
