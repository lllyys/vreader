# Bug History (Archived)

Historical descriptions, root causes, solutions, and lessons for all bugs.
Moved from `docs/bugs.md` to reduce file size. The Summary table in `docs/bugs.md` is the source of truth for status.

## Original Descriptions

1. CJK search returns no results
2. The search results are incomplete; only a few results are shown.
3. Progress cannot be saved. Each time the TXT file is opened, it starts from the beginning.
4. The performance of text search is poor. I have to wait for a while each time I open the search panel.
5. The performance of the text page is poor. I have to wait for a while each time I open a TXT book.
6. The reading settings do not take effect.
7. Scrolling performance is poor in the TXT reader.
8. There is nothing displayed on the reading panel.
9. The theme does not work in EPUB.
10. Theme changes do not take effect in TXT; they only apply after changing the font size or reopening the file.
11. Opening a large TXT file causes very poor scrolling performance; the page is nearly impossible to scroll, and scrolling is not smooth.
12. The toolbar cannot be hidden while reading.
13. @'/Users/ll/Downloads/黑暗血时代世界观设定+剧情整理（起点活动）第十五卷生存之战（未完待续） (1).txt' #11,#7 bug still exist
14. It takes too long to start the app and open the library page.
15. Observation tracking feedback loop — UITextView infinite layout invalidation, CPU 100%, app frozen, can't scroll or navigate back
16. Large CJK TXT file can't remember reading progress
17. Scrolling stuck and rebounds every time in another TXT file
18. Failed to create 1206x0 image slot (alpha=1 wide=1) (client=0xda0b106d) [0x5 (os/kern) failure]
19. All TXT files cannot remember the reading progress.
20. EPUB cannot hide the toolbar.
21. After opening a TXT file, it takes two clicks to hide the toolbar instead of one.
22. After hiding the toolbar, there is black padding at the top.
23. All TXT files cannot remember the reading progress. #19, The progress is lost again.
24. The bug #19, #23 is not fixed. It happens after reinstalling the app, but disappears after a while. Sometimes it restores the progress; sometimes it is lost and the file reopens at the beginning. It seems to vary depending on how long the file remains open. The progress must not be lost.
25. The bug #19, #23,#24 is not fixed.
26. The bug #19, #23,#24 ,#25is not fixed.
27. It is unacceptable for a TXT file to start at the beginning and then jump to the last read position.
28. All the search results are the same.
29. After changing the font size, the theme changes to a different pattern.
30. The reading settings bar is too long, covering the content and making it difficult to preview the changes.
31. Cannot add bookmarks, contents, highlights, or notes.
32. Cannot hide the top and bottom bars in PDF files.
33. TXT files do not show the reading time or the remaining time.
34. The sorting feature for books by reading time and last read is unavailable.
35. The bottom bar does not share the same theme as the top bar.
36. Cannot jump to the searched location when tapped.
37. It takes time for the changes to take effect after the theme or font size is changed.
38. It takes time to jump to the saved progress after reopening the file.
39. The bottom bar cannot be hidden when tapped.
40. Cannot jump to the searched location when tapped. It jumped, but not to the correct location.
41. It takes time to jump to the saved progress after reopening the file. # 38 I have to wait for a while.
42. Bookmarks cannot be edited and cannot jump to the location when tapped.
43. The search result is not highlighted when jumped to.
44. Cannot manually highlight or add notes.
45. Books sorted by "Last Read" do not take effect.
46. Manual highlight saves record but content not highlighted.
47. The app flashes and exits when jumping to a search result and tapping the screen. Also crashes on bookmark navigation + double tap.
48. The highlight and note features do not appear in some TXT files (large CJK files using chunked reader).
49. The input box is too narrow when adding a note with a long paragraph.
50. It cannot jump to the location when highlights or notes are tapped in the annotations panel.
51. The notes do not show the original content, so I cannot tell what the notes refer to.
52. Large CJK TXT files cannot jump to the location when notes, highlights, or bookmarks are tapped in the annotations panel.
53. Manual highlight saves record but content is not visually highlighted in large CJK TXT files (chunked reader).
54. Highlight disappears in large CJK TXT after selecting other text and canceling.

## Causes

- **#13**: UITextView with TextKit 1 allocates glyph storage for the entire NSAttributedString upfront (~65MB for a 9.5MB CJK file). Even with `allowsNonContiguousLayout`, the initial allocation and layout computation causes extreme scroll jank because UITextView must manage millions of glyphs in a single text container.
- **#14**: `LibraryView` checked `viewModel.isEmpty` immediately on appear — before `loadBooks()` had a chance to run. Since `books` starts empty, the empty state ("Your Library is Empty") flashed briefly before the actual book list loaded, making the app feel slow.
- **#15, #17**: `TXTReaderContainerView` (and `MDReaderContainerView`) passed `viewModel.currentOffsetUTF16` — an `@Observable` property that changes on every scroll — directly to the bridge as `restoreOffset`. This created an observation feedback loop: scroll -> viewModel update -> SwiftUI re-render -> `restoreScrollPosition` -> scroll again, infinitely.
- **#16**: The chunked reader's `restoreChunkIndex()` also read `viewModel.currentOffsetUTF16` in the body (same observation cycle). Additionally, position restore only worked in `makeUIView`, not on subsequent renders.
- **#19**: The one-shot scroll position restore in `TXTTextViewBridge.makeUIView` used `DispatchQueue.main.async`, but the UITextView hasn't been sized by SwiftUI at that point. TextKit's `lineFragmentRect` returns `CGRect.zero` when the text container has zero width.
- **#20**: WKWebView in `EPUBWebViewBridge` intercepts all tap events through its internal gesture recognizers. SwiftUI's `onTapGesture` modifier on the parent `ReaderContainerView` never fires because UIKit gesture recognizers have priority.
- **#21**: `UITextView` with `isSelectable = true` has internal gesture recognizers that consume single-tap events (for cursor placement).
- **#22**: When `.toolbar(.hidden, for: .navigationBar)` and `.statusBarHidden(true)` are applied, the safe area inset remains. The content doesn't extend into the vacated area.
- **#23**: Three compounding issues: (1) No `scenePhase` wiring for `onBackground()`/`onForeground()`. (2) `close()`/`open()` race condition at `positionStore.loadPosition()` suspension point. (3) `asyncAfter(0.15s)` one-shot scroll restore had no fallback if the view still had no valid frame.
- **#24**: `onBackground()` used a fire-and-forget `Task` that required an async actor hop to `PersistenceActor`. iOS could suspend the process before the hop completed.
- **#25**: TextKit 1 compatibility mode switch triggers a full relayout that resets `contentOffset` to near zero. Ghost `scrollViewDidScroll` overwrites saved position.
- **#26**: The #25 fix suppressed ghost scroll callbacks but did NOT fix the visual position. TextKit relayout happened AFTER Phase 1 restore and physically reset `contentOffset` to 0.
- **#27**: UX issue: Phase 2 restore (t+0.8s) works correctly, but UITextView is visible showing content at offset 0 for ~0.8s before jumping.
- **#28**: FTS5 `snippet()` returns one snippet per database row, but `findAllMatchOffsets` expands each row to multiple hit occurrences. All shared the same snippet.
- **#29**: `attrStringKey` excluded `textColor` and `backgroundColor`, so theme changes didn't trigger NSAttributedString rebuild.
- **#30**: Settings sheet used `.presentationDetents([.medium, .large])`, allowing full height.
- **#31**: No bookmark creation mechanism existed. No way to trigger from toolbar or pass model container to format-specific views.
- **#32**: Same root cause as #20/#21 — PDFView's internal gesture recognizers consume tap events.
- **#33**: No bottom overlay in TXT reader for reading progress or session time.
- **#34**: `ReadingStats.recompute(from:)` existed but was never called. Stats remained at initial values.
- **#35**: Bottom overlays used `.ultraThinMaterial` (system theme), not reader's custom theme.
- **#36**: `onNavigate` callback was a no-op stub.
- **#37**: Loading spinner shown during settings-driven rebuilds. Should keep old content visible.
- **#38**: Position restore used a fixed 0.8s Phase 2 delay. TextKit layout often completes much faster.
- **#39**: `isChromeVisible` only controlled nav bar. Bottom overlays had no access to it.
- **#40**: (1) `allowsNonContiguousLayout` causes estimated line heights for unvisited regions. (2) `SearchHitToLocatorResolver` didn't populate `charRangeStartUTF16`/`charRangeEndUTF16`.
- **#41**: Phase 1 + Phase 2 delay totaling ~0.3s, with fade-in animation on top.
- **#42**: `AnnotationsPanelSheet` had no-op `onNavigate` closures. `BookmarkPersisting` lacked `updateBookmarkTitle`.
- **#43**: Bridge scrolled to offset but applied no visual indicator on matched text.
- **#44**: No UI to create highlights or notes from selection. UITextView only offered Copy/Select All.
- **#45**: v1-v2: `.task` only runs once + throttle blocked refresh. v3: `markBookAsJustRead()` updated in-memory then called `await loadBooks()` which re-fetched from DB before `recomputeStats()` committed, overwriting the fix with stale data. Root cause: calling `loadBooks()` immediately after an in-memory fix when the DB write hasn't committed yet.
- **#46**: Highlight action saved record but never set `highlightRange` state for visual feedback.
- **#47**: v1-v2: Unsigned integer underflow + missing bounds guards. v3: Timer callbacks in both `TXTChunkedReaderBridge` and `TXTTextViewBridge` accessed UIKit objects (`textStorage.removeAttribute`, `tableView.visibleCells`) without `DispatchQueue.main.async`. When main thread was blocked in TextKit 1 relayout (holding `os_unfair_lock`), Timer fired on background thread → lock ownership violation → crash.
- **#48**: `TXTChunkedReaderBridge` lacked `UITextViewDelegate` conformance. No custom edit menu for large CJK files.
- **#49**: "Add Note" used `.alert` with `TextField` — inherently single-line.
- **#50**: `LocatorFactory.txtRange()` set range fields but not `charOffsetUTF16`. Navigation handler guarded on it, silently dropping.
- **#51**: `AnnotationRowView` only displayed note text, not the original annotated text from `locator.textQuote`.
- **#52**: `chunkedReaderContent()` did not pass `scrollToOffset` to `TXTChunkedReaderBridge`.
- **#53**: Same as #52 — `highlightRange` not passed to chunked bridge.
- **#54**: v1: Cell reuse wiped highlights + missing `textViewDidChangeSelection`. v2: 3-second auto-clear timer cleared `activeHighlightChunkIndex`/`activeHighlightLocalRange`, destroying the persistent state needed for cell reuse re-application. No distinction between temporary (search nav) and persistent (user-created) highlights — both treated as temporary.

## Solutions

- **#13**: Added `TXTTextChunker` + `TXTChunkedReaderBridge` (UITableView). Files >500K UTF-16 use chunked renderer.
- **#14**: Added `isInitialLoad` property to `LibraryViewModel`. Shows `ProgressView` during initial fetch.
- **#15, #16, #17**: Replaced live `viewModel.currentOffsetUTF16` with `@State var initialRestoreOffset` captured once. Made restore one-shot in `makeUIView` only.
- **#19**: Changed `DispatchQueue.main.async` to `asyncAfter(0.15s)` for layout pass.
- **#20, #21**: Added `UITapGestureRecognizer` with `shouldRecognizeSimultaneously` + `NotificationCenter`.
- **#22**: Added `.ignoresSafeArea(edges: .top)` when chrome is hidden.
- **#23**: Three fixes: scenePhase wiring, `isOpenComplete` race guard, scroll restore retry.
- **#24**: Made `onBackground()` async + `beginBackgroundTask`. Added scenePhase to EPUB/PDF.
- **#25**: `suppressScrollCallbacks` flag + time-based `restoreSuppressUntil` guard.
- **#26**: Two-phase scroll restore. Phase 2 at t+0.8s re-applies after TextKit relayout settles.
- **#27**: Hide UITextView (`alpha = 0`) until Phase 2 completes, then fade in.
- **#28**: Added `source_texts` table + per-occurrence `extractSnippet()`.
- **#29**: Added textColor/backgroundColor hash to `attrStringKey`.
- **#30**: Changed `.presentationDetents` to `[.medium]` only.
- **#31**: Added `NotificationCenter`-based bookmark creation via toolbar button + `modelContainer` passthrough.
- **#32**: Added `UITapGestureRecognizer` to `PDFViewBridge.Coordinator`.
- **#33**: Added `txtBottomOverlay` showing progress % and session time.
- **#34**: Created `PersistenceActor+Stats.swift`. Wired into all 4 ViewModel `close()` methods.
- **#35**: Replaced `.ultraThinMaterial` with theme-matched colors + `.toolbarColorScheme`.
- **#36**: Wired `onNavigate` via `.readerNavigateToLocator` notification.
- **#37**: Changed to `isBuildingInitialAttrString` — only spinner for initial load.
- **#38**: Added `ensureLayout(forCharacterRange:)` before Phase 1. Reduced Phase 2 to 0.15s.
- **#39**: Added `isChromeVisible` to all container views, gated bottom overlays.
- **#40**: Added `ensureLayout` in search path + populated `charRangeStart/End` in resolver.
- **#41**: Reduced Phase 2 to 0.05s, removed fade-in animation.
- **#42**: Wired all `AnnotationsPanelSheet` tabs + added bookmark rename via context menu.
- **#43**: Added `highlightRange` to bridge with yellow background attribute, auto-clears after 3s.
- **#44**: Added `editMenuForTextIn:suggestedActions:` with Highlight/Add Note actions + `NotificationCenter`.
- **#45**: v1: `.onAppear` refresh. v2: Event-driven `.readerDidClose` notification. v3: In-memory `lastReadAt` update + `loadBooks()`. v4: Remove `loadBooks()` — it overwrote the in-memory fix with stale DB data.
- **#46**: Set `highlightRange` immediately in `.readerHighlightRequested` handler.
- **#47**: v1: Bounds guard before unsigned subtraction. v2: Defensive guards in chunked `applyHighlight`. v3: Wrap all Timer callbacks in `DispatchQueue.main.async` — Timer can fire off-main when main thread is blocked in TextKit relayout.
- **#48**: Added `UITextViewDelegate` to `TXTChunkedReaderBridge.Coordinator` + `editMenuForTextIn` with chunk offset translation.
- **#49**: Created `AddNoteSheet.swift` with `TextEditor` for multi-line input.
- **#50**: Added `charOffsetUTF16 = charRangeStartUTF16` fallback in `LocatorFactory` + navigation handlers.
- **#51**: Added display of `locator.textQuote` in `AnnotationRowView`.
- **#52**: Added `scrollToOffset` to chunked bridge + `scrollToGlobalOffset` with binary search.
- **#53**: Added `highlightRange` to chunked bridge + `applyHighlight` with global-to-local conversion.
- **#54**: v1: Track active highlight on Coordinator; re-apply in `cellForRowAt`. v2: Distinguish temporary (search nav) vs persistent (user-created) highlights — only auto-clear temporary; persistent keeps `activeHighlight*` state indefinitely.

## Lessons

- TextKit 1 can't handle multi-megabyte attributed strings. Use virtualized rendering (UITableView) for large documents.
- Distinguish "not loaded yet" from "loaded and empty" in ViewModel state.
- Never read a rapidly-mutating `@Observable` property in SwiftUI body that feeds back to the same `UIViewRepresentable`. Use `@State` for one-shot values.
- `DispatchQueue.main.async` in `makeUIView` is unreliable for layout-dependent operations. Use `asyncAfter` with delay or check `bounds.width > 0` with retry.
- UIKit gesture recognizers in `UIViewRepresentable` intercept touches before SwiftUI gesture modifiers. Use `shouldRecognizeSimultaneously`.
- `@MainActor` async methods can interleave at `await` suspension points. Use generation counters and completion flags.
- Never use fire-and-forget `Task {}` for critical saves in `onBackground()` or `.onDisappear`. Make async + `beginBackgroundTask`.
- Every reader container view must wire `@Environment(\.scenePhase)`.
- TextKit 1 compatibility mode switch destroys scroll position. Suppress callbacks + re-apply position after relayout.
- Distance-based scroll guards are insufficient for layout storms. Use time-based or flag-based suppression.
- Suppressing callbacks is not enough — the visual position must also be re-applied.
- Hide content during async position restore to avoid jarring jumps.
- FTS5 `snippet()` is per-row, not per-occurrence.
- Composite keys for `@Observable`-driven rebuilds must include ALL mutable properties.
- Sheet `.presentationDetents` should match the use case.
- `NotificationCenter` is the right cross-view communication pattern when views don't share a direct data path.
- UIKit views with internal gesture recognizers need `shouldRecognizeSimultaneously` for tap coexistence.
- Wire computed stats to lifecycle events, not just data mutations.
- Reader chrome must use the reader's theme, not system theme.
- Never leave stub callbacks in shipping code.
- Show old content during settings-driven rebuilds.
- Use `ensureLayout(forCharacterRange:)` instead of fixed delays for TextKit layout.
- Search result match ranges must travel end-to-end through the pipeline.
- Temporary visual highlights should auto-clear.
- `textView(_:editMenuForTextIn:suggestedActions:)` (iOS 16+) is the cleanest way to add custom edit menu actions.
- `.task` in SwiftUI only runs once per view lifetime. Use `.onAppear` with throttled refresh for updates.
- Throttles can silently drop critical refreshes. Add a `force` parameter for known-stale scenarios.
- SwiftUI `@State` survives re-renders — stale navigation state can re-apply. Guard with bounds checks.
- Guard unsigned integer subtraction BEFORE performing it.
- Feature parity across rendering paths must be explicit. Check alternative bridges when adding features.
- Chunk-local offsets must be translated to document-global offsets.
- SwiftUI `.alert` with `TextField` is single-line. Use `.sheet` with `TextEditor` for multi-line input.
- Range-based locators should also set point offsets for navigation compatibility.
- Data already in the model often doesn't need schema changes.
- Never use fixed delays to coordinate async operations across views. Use event-driven signaling.
- Every feature wired to a standard bridge must also be wired to the alternative bridge.
- Chunk-based rendering requires coordinate translation in both directions.
- Never call `loadBooks()` (DB re-fetch) immediately after an in-memory fix — the DB write may not have committed yet. Trust the in-memory state for immediate UI; let eventual consistency handle the rest.
- Always wrap Timer callbacks in `DispatchQueue.main.async` when accessing UIKit objects. Even main-runloop Timers can fire off-main when the main thread is blocked in framework code (e.g., TextKit relayout).
- Distinguish temporary visual feedback (auto-clear after N seconds) from persistent user-created state. Use separate state variables or type flags to prevent auto-clear from destroying persistent data.

### Bug #45 v5 — "Last Read" sort resets on refresh/restart
- **Root cause**: `recomputeStats()` derived `lastReadAt` from session `endedAt`, but sessions shorter than 5s were discarded by `ReadingSessionTracker` (minimum duration threshold). Quick opens/closes left `lastReadAt` nil. The v4 in-memory fix via `markBookAsJustRead()` worked until `loadBooks()` re-fetched stale DB data.
- **Solution**: Added `stats.lastReadAt = Date()` after `stats.recompute(from:)` in `recomputeStats()`. Since this method is only called from reader `close()`, "now" is always correct. DB now has reliable `lastReadAt` that survives refresh/restart.
- **Lessons**: Session-based derived timestamps can have gaps when sessions are filtered. If a timestamp should always be set on a lifecycle event (close), set it explicitly rather than deriving from filtered data.

### Bug #47 v5 — Crash on highlight (EXC_BAD_ACCESS stack overflow)
- **Root cause**: `textStorage.addAttribute()` notifies UIKit's accessibility system, which calls `UITextViewAccessibility setAttributedText:`, which modifies textStorage again → infinite recursion → stack overflow (EXC_BAD_ACCESS code=2). This is NOT a threading issue (crash is on main thread) and `beginEditing()/endEditing()` does NOT prevent it because the recursion happens through the accessibility callback after `endEditing()` fires notifications.
- **Solution (v5, reverted)**: Attempted `layoutManager.addTemporaryAttribute` — but this API is macOS-only (AppKit). iOS `NSLayoutManager` has no temporary attribute methods at all. Build failed.
- **Solution (v6)**: Created `HighlightableTextView` UITextView subclass with reentrancy guard on `attributedText` setter. When `isApplyingHighlight` is true, the accessibility system's `setAttributedText:` callback is blocked, breaking the infinite recursion. Used `beginEditing()/endEditing()` around textStorage modifications.
- **Solution (v7)**: Removed `beginEditing()/endEditing()` — `endEditing()` calls `processEditing()` which triggers internal UIKit queue assertions (`_dispatch_assert_queue_fail`) when the accessibility setter is blocked. Single `addAttribute`/`removeAttribute` calls don't need the batch wrapper. Still crashed with `_dispatch_assert_queue_fail` on text selection.
- **Solution (v8)**: Removed the `attributedText` property override entirely. Swift 6's `@MainActor` enforcement on the override generates runtime dispatch queue assertions; UIKit accessibility accesses the property from an internal queue, failing the check. Instead, `addHighlightAttribute`/`removeHighlightAttribute` rebuild the full `NSMutableAttributedString` with the highlight baked in and set via `attributedText = mutable` in one shot. Saves/restores `contentOffset` and `selectedRange` across the replacement. **Crashed**: infinite loop — `addHighlightAttribute` sets `textView.attributedText` → `updateUIView` detects content differs from source → calls `applyText` (overwrites highlight) → `applyPersistedHighlights` → `addHighlightAttribute` → loop → stack overflow at `applyText`.
- **Solution (v9)**: Fixed the infinite loop by tracking the source `text` and `attributedText` by value/reference in the Coordinator (`lastAppliedText`, `lastAppliedAttrText`). `updateUIView` now compares against coordinator state (the SOURCE), not the textView's current content. Highlight modifications change the textView's content but NOT the source → no re-application → no loop. **Crashed**: `addHighlightAttribute` reads `self.attributedText` (getter acquires os_unfair_lock) then writes `self.attributedText = mutable` (setter tries same lock) → `_os_unfair_lock_recursive_abort`.
- **Solution (v10)**: Complete restructure — NEVER read from `textView.attributedText`, NEVER modify attributes post-creation. `HighlightableTextView` simplified to only `setHighlightedText(_:)`. New pure function `TXTTextViewBridge.buildHighlightedString(base:persistedHighlights:activeHighlight:)` builds the full NSAttributedString with all highlight ranges baked in. Coordinator stores `baseAttributedText`, `persistedHighlights`, `currentHighlightRange` — `updateUIView` detects changes and rebuilds. Timer callback uses `coordinator.rebuildHighlights(in:)`. `TXTChunkedReaderBridge` adopts the same pattern: `buildChunkWithHighlights(forChunk:)` builds per-chunk attributed strings with global→local range conversion, set via `setHighlightedText`.
- **Solution (v11)**: The `attributedText` setter still crashes at frame #45 deep in UIKit accessibility traversal when the text view has an active selection (from edit menu highlight action). Fix: (1) Clear `selectedTextRange` before replacement to remove stale selection state, (2) Use `textStorage.setAttributedString()` instead of `attributedText =` — bypasses the setter's heavy accessibility processing, (3) Added `isReplacingText` guard flag on `HighlightableTextView` to suppress delegate callbacks (`textViewDidChangeSelection`, `scrollViewDidScroll`) during replacement. Guards added in both bridge coordinators. **Still crashed**: even `textStorage.setAttributedString()` triggers internal UIKit processing that crashes at frame #6 when the text view has an active selection.
- **Solution (v12, current)**: Completely decoupled highlight visualization from text storage modification. Created `HighlightingLayoutManager` (custom `NSLayoutManager` subclass) that overrides `drawBackground(forGlyphRange:at:)` to draw yellow highlight rectangles. Highlights are NEVER written to text storage — they exist only as `highlightRanges: [NSRange]` on the layout manager, rendered during UIKit's normal display pipeline. `HighlightableTextView.setHighlightRanges(persisted:active:)` updates ranges and invalidates display. `setSourceText(_:)` is used only for source text changes (initial load, config). Applied to both `TXTTextViewBridge` and `TXTChunkedReaderBridge` — chunked reader uses `chunkLocalHighlightRanges(forChunk:)` for global→local range conversion.
- **Lessons**:
  1. `NSLayoutManager.addTemporaryAttribute` is macOS-only (AppKit). iOS has no equivalent. Always check platform availability.
  2. Never override `attributedText` on UITextView in Swift 6 — `@MainActor` enforcement adds runtime queue checks that fail when UIKit accessibility accesses the property from an internal queue (`_dispatch_assert_queue_fail`).
  3. Never use `textStorage.addAttribute` directly on a live UITextView — triggers `UITextViewAccessibility setAttributedText:` infinite recursion → EXC_BAD_ACCESS stack overflow.
  4. Never read then write `self.attributedText` — getter and setter both acquire `os_unfair_lock`, causing recursive abort.
  5. **ANY text storage modification on a visible UITextView with active selection will crash** — `textStorage.setAttributedString()`, `attributedText =`, `textStorage.addAttribute()` all trigger UIKit accessibility/internal processing that is unsafe during selection. The ONLY safe approach is to decouple visual effects from text storage entirely.
  6. `NSLayoutManager.drawBackground(forGlyphRange:at:)` is the correct iOS approach for overlaying visual highlights without touching text storage. It's called by UIKit's display pipeline for visible glyphs only — efficient, scroll-synchronized, and crash-free.
  7. When using full `attributedText` replacement for source text changes, `updateUIView` must compare against the SOURCE text (tracked in coordinator), not the textView's current content.
  8. `beginEditing()/endEditing()` on textStorage triggers `processEditing()` which has internal queue assertions — avoid when the accessibility callback path is blocked.

### Bug #55 — Highlights not visible when file is reopened
- **Root cause**: Highlights were correctly persisted to DB via `PersistenceActor.addHighlight()`, but no code loaded persisted `HighlightRecord`s on file open and applied their character ranges as background colors to the text view.
- **Solution**: Added `persistedHighlights: [NSRange]` parameter to both `TXTTextViewBridge` and `TXTChunkedReaderBridge`. Container views (`TXTReaderContainerView`, `MDReaderContainerView`) fetch highlights via `persistence.fetchHighlights()` in their `.task` block after file open. Ranges are rendered via `HighlightingLayoutManager.drawBackground()` (bug #47 v12) — zero text storage mutation.
- **Lessons**: Persisting data is only half the story — loading and rendering it on the display path must also be implemented. When adding a "save" feature, always plan the "load and display" counterpart.

### Bug #62 — Content shifts down when top bar reappears
- **Root cause**: `ReaderContainerView` toggled `.ignoresSafeArea(edges: isChromeVisible ? [] : [.top])` in the same `withAnimation` block as `isChromeVisible`. SwiftUI does not animate `ignoresSafeArea` changes — it applies them immediately. When chrome was shown, the safe area was restored at the START of the animation, snapping content down by ~88pt while the nav bar was still animating in.
- **Solution**: Introduced a separate `@State var isIgnoringTopSafeArea` that lags behind `isChromeVisible` when showing chrome. When HIDING: `isIgnoringTopSafeArea = true` immediately (no gap during nav bar exit). When SHOWING: nav bar animates in (0.2s), then `isIgnoringTopSafeArea = false` fires at 0.22s (after nav bar is fully visible). The safe area snap now occurs after the nav bar is in place, making it imperceptible.
- **Lessons**: SwiftUI's `ignoresSafeArea` is not an animatable property — layout state that depends on it must be managed separately if smooth transitions are needed. Use separate state variables when two values need different timing.

### Bug #63 — Progress bar unresponsive in Native mode
- **Root cause**: `TapZoneModifier` placed `Color.clear.contentShape(Rectangle()).onTapGesture` in a ZStack ABOVE the entire native reader container (including `ReadingProgressBar`). The `Color.clear` with `contentShape(Rectangle())` makes the full screen area participate in hit-testing, capturing touch events before they reached the underlying SwiftUI `Slider`. The Slider's internal drag gesture never received the touch.
- **Solution**: Replaced the single full-screen clear overlay with a `VStack` containing: (1) a `Color.clear` tap detector for the reading area, and (2) a `Color.clear.allowsHitTesting(false)` spacer with `height: bottomInset` (default 100pt) at the bottom. The bottom zone passes all touches through to the progress bar Slider and bottom overlay. Added `bottomInset` parameter to both `TapZoneModifier` and `tapZoneOverlay(config:bottomInset:)` extension.
- **Lessons**: ZStack overlay views with `contentShape(Rectangle())` intercept all gestures in their frame — never place them above interactive controls. If a full-screen overlay is needed, always add a hit-testing exclusion zone for any interactive child controls.

### Bug #56 — PDF crash after adding highlight and reopening
- **Root cause**: `PDFAnnotationBridge.denormalizeRects()` did not validate input rects. If an `AnnotationAnchor` contained rects with NaN, infinity, or negative dimension values (from corrupt Codable decode or edge-case coordinate math), these were passed directly to `PDFAnnotation(bounds:forType:withProperties:)`. PDFKit forwards these to CoreGraphics, which logs "NaN passed to CoreGraphics API" errors and can crash on certain devices/OS versions. Additionally, `denormalizeRects` lacked the zero-dimension `pageBounds` guard that `normalizeRects` had, creating an asymmetry.
- **Solution**: Added `isValidRect(_:)` private helper that checks `origin.x/y.isFinite`, `size.width/height.isFinite`, and `size.width/height >= 0` (using `size.width` not `width` because `CGRect.width` auto-normalizes negatives). Applied validation in two layers: (1) `denormalizeRects` now guards against zero-dimension pageBounds AND filters input/output rects via `isValidRect`; (2) `createHighlight` filters rects before passing to `PDFAnnotation`. Defense-in-depth prevents any invalid rect from reaching PDFKit.
- **Lessons**: (1) `CGRect.width` always returns positive (it's the absolute value) — use `CGRect.size.width` to detect negative dimensions. (2) When a "normalize" function has a safety guard (zero pageBounds), the corresponding "denormalize" function must have the same guard for symmetry. (3) PDFKit does not validate bounds inputs — the caller must validate before creating annotations.

### Bugs #65–69 — Stale UI test expectations (batch fix)
- **Root cause**: Five UI tests had stale expectations from before features were fully implemented:
  - #65: Empty state text updated to include "Markdown" but test still had old string without it.
  - #66: Annotation panel tabs replaced placeholder text ("...will appear here once the reader is fully wired") with real `ContentUnavailableView` descriptions, but tests still expected old strings.
  - #67: `findFirstRow()` in `DeleteConfirmationTests` only searched `app.buttons` for `bookRow_*` identifiers. SwiftUI List items on iOS 26 may render as cells instead of buttons.
  - #68: Dynamic Type tests at xxxLarge/AX5 used `.exists` (no wait) for toolbar buttons that need rendering time at large type sizes.
  - #69: PDF reader placeholder replaced by real PDFKit implementation; test still looked for `pdfReaderPlaceholder` identifier that no longer exists.
- **Solution**: Updated all test strings to match production code. Broadened `findFirstRow()`/`bookRowCount()` to check both `app.buttons` and `app.cells`. Changed `.exists` to `waitForExistence(timeout: 5)`. Updated PDF tests to verify `pdfReaderContainer`.
- **Lessons**: (1) When production code evolves (placeholders → real implementation), UI tests must be updated in the same change. (2) SwiftUI element type in the accessibility tree can change across iOS versions — always query multiple element types for resilience. (3) Toolbar items at large Dynamic Type sizes need explicit waits, not synchronous `.exists` checks.

### Bug #62 v2 — Content shifts down when top bar reappears
- **Root cause**: v1 fix used `isIgnoringTopSafeArea` with a 0.22s delay to toggle `.ignoresSafeArea(edges: .top)`, but `ignoresSafeArea` is not animatable — it's a discrete layout rule change that always causes an instant content jump regardless of timing.
- **Solution**: Always set `.ignoresSafeArea(edges: .top)` (constant, never toggled). The navigation bar now overlaps content like Apple Books / Kindle / KOReader. Content position is pixel-stable because the safe area participation never changes. Removed `isIgnoringTopSafeArea` state and `DispatchQueue.main.asyncAfter` hack. Simplified `toggleChrome()` to a single `isChromeVisible.toggle()` with animation.
- **Lessons**: (1) `ignoresSafeArea` is a layout rule, not a visual property — toggling it always causes a jump regardless of timing hacks. (2) Reader apps should use a constant full-screen layout with the toolbar as an overlay, not toggle safe area participation. (3) If a timing-based fix doesn't fully solve a layout problem, the approach is fundamentally wrong.

### Bug #70 — Cannot scroll content in native mode — all formats
- **Root cause**: `TapZoneModifier` placed `Color.clear.contentShape(Rectangle()).onTapGesture` in a ZStack above the native reader content. In SwiftUI, the topmost hit-testable view "owns" touches — `contentShape(Rectangle())` made the overlay intercept ALL touch events, preventing scroll/drag gestures from ever reaching the underlying UIKit views (UITextView, WKWebView, PDFView). The touch wasn't re-routed even when the tap recognizer failed.
- **Solution**: Removed `.tapZoneOverlay()` from the native reader path in `ReaderContainerView`. All four native bridges already had their own `UITapGestureRecognizer` with `shouldRecognizeSimultaneously` (or JS click handler for EPUB) that posts `.readerContentTapped`. The overlay is now only used for the unified renderer (SwiftUI-native, no UIKit views underneath).
- **Lessons**: (1) Never place a SwiftUI `contentShape(Rectangle())` overlay in a ZStack above UIKit scroll views — it blocks ALL gestures, not just the ones it handles. (2) For UIKit-wrapped views, tap detection belongs inside the bridge using native `UITapGestureRecognizer` with `shouldRecognizeSimultaneously`. (3) SwiftUI's gesture routing is "top view wins" — failed gesture recognizers do NOT forward touches to views behind in a ZStack.

### Bug #97 — TTS control bar overlaps bottom bar
- **Root cause**: TTSControlBar was rendered in ReaderContainerView's ZStack at the bottom, but format-specific containers also had their own bottom overlay (ReadingProgressBar + ReaderBottomOverlay) in a separate ZStack layer. When TTS was active and chrome was visible, both bars competed for the bottom position.
- **Solution**: Passed `ttsService` through format hosts to all 4 container views. Each container now hides its bottom overlay when `ttsService.state != .idle`. The TTS bar replaces the bottom overlay during playback.
- **Lessons**: (1) Overlapping overlays across ZStack layers need explicit coordination — SwiftUI won't auto-stack them. (2) Passing observable state down the view hierarchy is cleaner than notifications for simple boolean conditions.

### Bug #85 — Cannot add books to collections
- **Root cause**: The library context menu (`bookContextMenu`) had Info, Share, Set Cover, and Delete actions but no collection management option. The persistence layer (`addBookToCollection`) was already implemented.
- **Solution**: Added "Add to Collection" submenu to `bookContextMenu` with a list of existing collections. Collections are loaded eagerly on library appear. Selecting a collection calls `PersistenceActor.addBookToCollection()`.
- **Lessons**: Context menus should expose all major entity operations — CRUD for relationships is as important as single-entity actions.

### Bug #86 — Tags never shown in collection sidebar
- **Root cause**: `LibraryView` passed `allTags: []` and `allSeries: []` to `CollectionSidebar`. No methods existed to aggregate tags/series across all books.
- **Solution**: Added `fetchAllTags()` and `fetchAllSeriesNames()` to `PersistenceActor+Collections`. LibraryView now loads tags and series when opening the collections sidebar.
- **Lessons**: When adding aggregate UI (sidebar filters), the corresponding aggregate queries must exist in the persistence layer.

### Bug #84 — Per-book settings affect all books instead of one
- **Root cause**: `PerBookSettingsStore.resolve()` existed and was tested, but `ReaderContainerView` never called it on book open. The settings panel saved per-book overrides to disk, but opening a book always loaded global `UserDefaults` settings.
- **Solution**: Added `applyResolvedSettings(_:)` to `ReaderSettingsStore` that maps `ResolvedSettings` fields back to store properties. Added `.task` in `ReaderContainerView` to load per-book settings and apply them on book open.
- **Lessons**: (1) Feature implementation is incomplete until the "load on open" path is wired — save-only is half the feature. (2) Adding a method to apply resolved settings back to the store closes the read/write symmetry gap.

### Bug #110 — WebDAV Test Connection blocked by App Transport Security on Tailscale URL
- **Root cause**: `project.yml` used `GENERATE_INFOPLIST_FILE: YES` + `INFOPLIST_KEY_*` flat settings. iOS App Transport Security defaults to HTTPS-only and blocks plain HTTP to all non-loopback hostnames; vreader's Info.plist had no `NSAppTransportSecurity` exception. Localhost / `127.0.0.1` worked because iOS exempts loopback. `*.tail-XXXXX.ts.net` (and any NAS / NextCloud / Synology over HTTP) was blocked before the request left the device.
- **Why per-domain wasn't an option**: Codex review confirmed (a) `NSAllowsLocalNetworking` covers `.local` mDNS / IP literals only — not `*.ts.net` MagicDNS hostnames; (b) `NSExceptionDomains` for `ts.net` only reaches one subdomain label, not the two-label `host.tail-XXXXX.ts.net` shape; the user-specific tailnet suffix can't be hardcoded; (c) Apple ignores `NSAllowsArbitraryLoads` on iOS 10+ if any "narrowing" key like `NSAllowsArbitraryLoadsInWebContent` or `NSAllowsLocalNetworking` is present alongside it.
- **Solution**: Migrated `project.yml` from auto-generated Info.plist (`GENERATE_INFOPLIST_FILE: YES` + flat `INFOPLIST_KEY_*` settings) to managed Info.plist via XcodeGen `info.properties`. Added `NSAppTransportSecurity > NSAllowsArbitraryLoads = true` — the honest opt-out for an app whose feature is connecting to arbitrary user-entered WebDAV servers. Preserved version-bump rule by referencing `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)` in `CFBundleShortVersionString` / `CFBundleVersion`.
- **Tests**: `vreaderTests/Services/Backup/WebDAVATSTests.swift` — two regression tests. (1) `infoPlist_AllowsArbitraryLoads` reads `Bundle.main.NSAppTransportSecurity` and asserts the dict shape. (2) `urlSession_NonLoopbackHTTP_doesNotFailWithATS` makes a real `URLSession.dataTask` to `http://198.51.100.1:9999/` (TEST-NET-2, RFC 5737) with 1s timeout and asserts the resulting `URLError` is NOT `.appTransportSecurityRequiresSecureConnection`. Both fail before the project.yml change (verified RED) and pass after (verified GREEN).
- **Lessons**: (1) Apple's auto-generated Info.plist (`GENERATE_INFOPLIST_FILE: YES`) doesn't support nested dicts — for `NSAppTransportSecurity` and similar structured plist data, you have to manage Info.plist explicitly. (2) ATS keys aren't compositional: most "narrowing" exceptions silently disable `NSAllowsArbitraryLoads`. (3) iOS Simulator's loopback exemption hides ATS bugs from any test that only hits `127.0.0.1` — the integration test in PR #128 passed because of this; the Tailscale path needed its own test. (4) For an app whose feature is "connect to arbitrary user-entered URLs," per-domain ATS exceptions don't scale — the broad opt-out is the honest choice.
- **Verification (2026-05-03)**: End-to-end verified against `lllyys/vreader-webdav-host` (rclone serve webdav over Tailscale) on simulator with build 10 (v3.10.9). Initial run returned `502 Bad Gateway` even though direct `curl` from the Mac returned the expected `401`. Root cause was a **system HTTP proxy** on the Mac (`scutil --proxy` showed `127.0.0.1:7897` with bypass list missing `*.ts.net`); iOS Simulator inherits the Mac's proxy, so URLSession funnelled Tailscale traffic into the proxy, which returned 502. Adding `*.ts.net` and `100.64.0.0/10` to the proxy bypass list cleared it. README's WebDAV bullet now documents this footgun. The ATS fix itself is confirmed working on the Tailscale path.

### Bug #111 — DebugFixtures resources ship in Release builds
- **Root cause**: `vreader/Resources/DebugFixtures/war-and-peace.txt` was included in the app target's Resources copy build phase via the wildcard `sources: - path: vreader` entry in `project.yml`. xcodegen's `excludes:` is path-level, not build-config-conditional, so there was no way to "exclude in Release, include in Debug" with a single `sources:` stanza.
- **Discovery**: surfaced by the Codex audit of feature #48's plan (2026-05-03) while verifying the planned test-fixture catalog could expand without bloating Release.
- **Solution**: (1) added `Resources/DebugFixtures/**` to the app target's `excludes:` so the directory is fully stripped from the Resources copy phase; (2) added a `preBuildScripts:` Run Script that copies fixtures into the bundle's `DebugFixtures/` subdirectory ONLY when `${CONFIGURATION} == Debug`. Used `rsync -a --delete` so empty source dirs don't fail the script and changed fixtures invalidate Xcode's incremental build correctly. Verified end-to-end: Debug build produces `vreader.app/DebugFixtures/war-and-peace.txt`; Release build produces no `DebugFixtures/` anywhere in the bundle. `find vreader.app -name 'war-and-peace*'` returns zero results in Release.
- **Lessons**: (1) xcodegen's `sources.excludes` is build-config-blind — it strips files from a target unconditionally. The honest pattern for "include in Debug only" is exclude unconditionally + re-inject via a `preBuildScripts:` Run Script that gates on `${CONFIGURATION}`. (2) `rsync -a --delete` is the right copy primitive for build phases; `cp -R src/* dst/` fails on empty sources and doesn't sync deletions. (3) Build-phase scripts need explicit `inputFiles` / `outputFiles` so Xcode can dependency-track them; without those, the script either runs every build (slow) or never re-runs when fixtures change (stale).

<!-- Entries below moved 2026-05-07 from `docs/bugs.md` Open Bug Detail. -->
<!-- All bugs were FIXED at the time of move; the Open Bug Detail section -->
<!-- accumulated entries that should have been archived per the bugs.md rules. -->

### Bug #103 — Cannot add highlight in native EPUB
- **Repro**: Open EPUB in native reader, select text, tap Highlight
- **Expected**: Highlight created and rendered in-page
- **Actual**: JS silently dropped because `onInjectJS` is nil during race with `.task` setup
- **Root cause**: `EPUBHighlightRenderer.onInjectJS` callback swap during `restoreHighlightsOnLoad` loses concurrent highlight JS
- **RED tests**: `EPUBHighlightRendererBug77Tests.swift` (intentionally failing)

### Bug #104 — EPUB 3 nav titles not extracted
- **Repro**: Open EPUB with nav.xhtml containing real chapter titles
- **Expected**: TOC shows "Chapter One: The Beginning"
- **Actual**: Shows "Section 1" (fallback)
- **Root cause**: Bug #74 fix (`withResolvedTitles`) incomplete — nav.xhtml parsing may not match spine hrefs
- **RED test**: `EPUBParserTests.epub3NavTitlesExtracted`

### Bug #105 — Highlighted snippet multi-word overlap
- **Repro**: Search for a multi-word query where matches overlap in snippet text
- **Expected**: Multiple bold runs for overlapping matches
- **Actual**: Only 1 bold run
- **RED test**: `HighlightedSnippetTests.multiWordQuery_overlappingMatches_handled`

### Bug #106 — AZW3 reader stuck on "Opening book"
- **Repro**: Import any .azw3 or .mobi file, tap to open
- **Expected**: Book renders with text visible
- **Actual**: Loading screen stays forever ("Opening book...")
- **Root cause**: `WKURLSchemeHandler` + JS `fetch()` doesn't work on device. The `bridge-ready` event fires, `openBookJS()` runs `fetch('vreader-resource://localhost/book/file')`, but fetch fails silently. `book-ready` never arrives so `isLoading` stays true.
- **Fix**: Switch to `loadHTMLString` + base64 book handoff (proven working in FoliateSpikeView)

### Bug #107 — Cover images with light/white edges show visible "padding"
- **Repro**: Import AZW3 book (被讨厌的勇气) with light-colored cover art edges, view in library grid
- **Expected**: Cover fills card edge-to-edge with no visible gap
- **Actual**: White areas at top of cover art blend into white page background, looks like padding
- **Root cause**: Cover art content (not layout) — image fills container correctly but has white/light pixels at edges. Container size verified identical via debug overlay.
- **Fix options**: Auto-crop white borders in CustomCoverStore, or add contrast background behind covers

### Bug #99 — Search highlight missing in some TXT files
- **Repro (cause #3, addressed by current PR)**: Open a medium-size TXT file (under the 500K-UTF-16 chunked-reader threshold). Search → tap a result. The yellow search highlight does not appear.
- **Root cause #3 (programmaticScrollCount timing race)**: Old `clearSearchHighlightIfTemporary` skipped clearing when `programmaticScrollCount > 0` and decremented the counter via `DispatchQueue.main.asyncAfter(deadline: .now() + 0.3)`. TextKit 1's lazy-layout `scrollViewDidScroll` callbacks for medium files arrive 400-1200ms after `setContentOffset` returns — past the 0.3s window. So the highlight got cleared by the late callback before the user could see it.
- **Fix shipped (cause #3 only)**: Replaced the counter+timer with a canonical signal — `clearSearchHighlightIfTemporary(scrollView:)` checks `scrollView.isTracking || isDragging || isDecelerating`. Programmatic scrolls and their late layout callbacks have all three flags false (skip), user-driven scrolls have at least one true (clear). No timer needed. Tests in `TXTTextViewBridgeConfigTests` + `TXTSearchHighlightGatingTests` exercise both branches via a `StubScrollView` subclass.
- **Remaining causes (open candidates, NOT addressed)**:
  - **Cause #1**: Chunked reader (`TXTChunkedReaderBridge`) `applyHighlight` looks up `cellForRow(at: chunkIndex)`; if the destination cell isn't yet visible after `scrollToGlobalOffset`, no rebuild happens and the auto-clear timer can fire before the cell becomes visible.
  - **Cause #2**: Encoding offset mismatch — search index built against detected encoding may not align with the bridge's displayed UTF-16 positions for non-UTF-8 TXTs.
- **Fix scope (remaining)**: Cause #1 needs a "wait for cell to become visible" signal in the chunked-reader's apply path. Cause #2 needs investigation of `TXTService.detectEncodingFromSample` vs the bridge's `text` property to find where the offsets diverge.
- **Caught by**: 2026-05-05 reading session (medium-size TXT search-tap). Initial investigation captured 2026-05-05; cause #3 fixed in PR #263 (v3.13.18).

### Bug #123 — DebugBridge `.onOpenURL` handler doesn't fire — URL accepted but no dispatch
- **Repro**: After bug #121 fix (v3.13.9), `simctl openurl booted vreader-debug://reset` returns exit 0 (URL is accepted by iOS — bug #121 is genuinely fixed). But the in-app handler does NOT fire: ZBOOK count stays at 3 before and after; no books wiped from `ImportedBooks/`; no log lines on `subsystem == com.vreader.app` during invocation; `Library/Caches/DebugBridge/` directory exists but stays empty (no `state.json`, no sentinel files for any of seven commands).
- **Root cause**: iOS LaunchServices presents a one-shot **"Open in 'vreader'?"** approval prompt from `lsd` when `simctl openurl` (running as `CoreSimulatorBridge`) opens `vreader-debug://` on a simulator that has no prior approval entry for that source/scheme pair. Until the user taps **Open**, the URL is held by `lsd` and never reaches `.onOpenURL`. `simctl openurl` exits 0 because the request was accepted by LaunchServices (queued for approval), not because the app received the URL. Diagnosed by streaming `process == "SpringBoard"`: the log shows `Received request to activate alertItem: <SBUserNotificationAlert: ...; title: Open in "vreader"?; source: lsd; pid: 6184>` immediately after each `simctl openurl` call. After tapping Open once, the DIAG-instrumented `.onOpenURL` handler fires correctly on subsequent calls (verified in this fix — `reset: removed 3 book(s)` log line). The handler code in `vreader/App/VReaderApp.swift:225` is correct.
- **Why bug #121's fix exposed this**: before bug #121, the URL scheme wasn't registered → `simctl openurl` returned `LSApplicationWorkspaceErrorDomain code=115` (no app handles this scheme). After bug #121, the scheme IS registered → `simctl openurl` reaches LaunchServices, which then enforces its third-party-scheme approval policy.
- **Approval persistence**: once granted, the approval is stored at `~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Library/Preferences/com.apple.launchservices.schemeapproval.plist` with key `com.apple.CoreSimulator.CoreSimulatorBridge-->vreader-debug = com.vreader.app`. Survives reinstalls; does NOT survive `simctl erase`.
- **Fix**: `scripts/grant-debug-scheme-approval.sh` writes the plist entry directly. Idempotent. Verification harness should call this once per fresh simulator before its first `simctl openurl`. Documented in `docs/subsystems/debug-bridge.md` § "iOS scheme-approval prompt (bug #123)".
- **Impact (resolved)**: feature #44's command-surface criteria 3 and 4 are reachable again from a verification harness that uses the grant script. Feature #45's verification harness premise is unblocked.
- **Caught by**: feature #44 re-verification post bug-#121-fix (commit `aff7085`, v3.13.9).

### Bug #122 — EPUB cover extraction fails on books with redundant-prefix `href` in `<meta name="cover">` manifest entry
- **Repro**: Import an EPUB whose `OEBPS/content.opf` declares the cover via `<item href="OEBPS/cover.jpg" id="cover" .../>` (publisher mistake — `href` should be relative to the OPF directory but is written as if absolute from archive root). Real-world example: "道诡异仙" EPUB.
- **Root cause**: `MetadataExtractor.resolveArchivePath` joined `opfDirPath="OEBPS"` + `coverHref="OEBPS/cover.jpg"` → `"OEBPS/OEBPS/cover.jpg"`, which does not exist in the archive. The actual cover is at `OEBPS/Images/cover.jpg`. The previous `extractCoverImage` returned nil on the first archive miss with no fallback.
- **Fix**: Added `EPUBMetadataExtractor.coverPathCandidates(coverHref:opfDirPath:entries:)` that emits an ordered, de-duplicated list of archive paths to try: (1) spec-compliant resolved path; (2) bare-basename match across image-extension entries (jpg/jpeg/png/gif/webp), case-insensitive, ranked so entries inside the OPF directory tree come before entries outside it; (3) archive-root canonical `cover.{jpg,jpeg,png,gif}`. `extractCoverImage` now opens the ZIP once and probes candidates in order, returning the first one whose bytes decode as a valid `UIImage`. End-to-end regression test in `EPUBMetadataExtractorTests.extractCoverImage_redundantPrefixHref` builds a synthetic EPUB matching the "道诡异仙" repro shape and asserts the basename fallback locates the real cover.
- **Caught by**: feature #43 device-verification 2026-05-05. Evidence: `dev-docs/verification/feature-43-20260505.md`.
- **Related (unproven)**: Same evidence file flags an AZW3 case where MOBICoverExtractor *should* have succeeded (EXTH 201 record valid, target record carries a valid JPEG) but `CustomCovers/` is empty. Cannot isolate without deterministic re-import; tracked separately, not addressed by this fix.

### Bug #121 — DebugBridge URL scheme not registered in installed builds (orphaned `DebugBridge.plist`)
- **Repro**: `xcrun simctl openurl booted vreader-debug://snapshot?dest=state.json` → returns `LSApplicationWorkspaceErrorDomain code=115` ("Simulator device failed to open"). Same for `seed`, `reset`, `theme`, `open`, `settle`, `eval`.
- **Expected**: DEBUG build registers the scheme; the URL reaches the in-app handler; a `state.json` lands in `Library/Caches/DebugBridge/` (or the path the caller specified).
- **Actual**: scheme not in `Info.plist`. `xcrun simctl get_app_container booted com.vreader.app | xargs -I{} plutil -p {}/Info.plist` shows `CFBundleURLTypes` absent.
- **Root cause**: `vreader/SupportingFiles/DebugBridge.plist` exists with the right URL types declaration. Its own header claims it is "Wired via per-configuration INFOPLIST_FILE: vreader target Debug config references this file; Release config leaves INFOPLIST_FILE unset...". But `project.yml`'s `info:` block at line 60–87 hard-codes one path (`vreader/SupportingFiles/Info.plist`) for both configurations and there is no merge step. As a result `DebugBridge.plist` ships only as a sibling Resources-phase file (pbxproj line 3123) which iOS never consults for URL types.
- **Impact**: every `simctl openurl vreader-debug://` invocation fails. Feature #45's whole verification harness is blocked. Every "Needs device verification" item that names DebugBridge as its driver was already silently impossible to run against an installed build.
- **Caught by**: feature #44 device-verification 2026-05-05 (`dev-docs/verification/feature-44-20260505.md`). Bug #111 ("DebugFixtures resources ship in Release") fixed the *fixture leak* via a Debug-only Run Script, which is the model for the Right Fix here too.
- **Fix scope**: 5–10 line `project.yml` change. Two viable shapes — (a) per-configuration `INFOPLIST_FILE` (one path for Debug, one for Release; the Debug one is a generated merge of `Info.plist` + `DebugBridge.plist`); or (b) a Debug-only Run Script that writes the URL types into the built `Info.plist` after the source plist is copied (mirroring the bug #111 DebugFixtures fix). After fix, re-run this verification + run `scripts/verify-release-no-debugbridge.sh` against a fresh Release build (it currently catches the sibling-file leak via line 90's `*DebugBridge*` filename glob — likely failing if anyone runs it).

### Bug #88 — Imported annotations not visually highlighted
- **Repro**: Import annotations JSON, check if highlights are rendered in reader
- **Expected**: Imported highlights visible in the reader
- **Actual**: DB records created but reader doesn't refresh visual highlights
- **Root cause**: Import writes to DB but no notification to reader to re-render
- **Fix**: Added `.readerHighlightsDidImport` notification; all format containers observe and call `coordinator.restoreAll()`

### Bug #120 — Simp/Trad conversion has no visible effect in realistic cases (Native default + complex EPUBs)
- **Repro**: Open any Chinese EPUB (e.g. "道诡异仙") in default settings; Reader Settings → Chinese Text → "Simp → Trad"; observe body text. Or: keep Native mode, set conversion to anything, observe.
- **Expected**: Simplified chars (e.g. 关/图/无/让/还) swap to Traditional (關/圖/無/讓/還) in the rendered body.
- **Actual**: Body text stays Simplified. Setting persists in UserDefaults and the picker UI updates, but no visible effect.
- **Root cause**: Conversion is wired only into `unifiedCoordinator.activeTransforms` (`ReaderContainerView+Sheets.swift:117–124`, `ReaderContainerView.swift:193`). Two gaps stack: (a) Native mode (default) never builds `activeTransforms` so the setting is a no-op for the most common user state; (b) in Unified mode, complex EPUBs get `textContent == nil` and `ReaderUnifiedDispatch.swift:73–76` falls back to `nativeReaderView` (WKWebView) which doesn't consume the transforms either. Realistically every published Chinese EPUB takes the fallback. PDF/AZW3/MOBI native renderers also don't apply transforms.
- **Caught by**: feature #28 device verification 2026-05-05. Evidence: `dev-docs/verification/feature-28-20260505.md`. SimpTradTransform unit tests pass — they verify the pure transform, not the wiring.
- **Fix scope**: Two viable directions. (1) Route `activeTransforms` into the native EPUB WKWebView via JS message that swaps text nodes through `SimpTradDictionary` so the existing setting works for the realistic path. (2) Disable the picker (or show a "Unified mode only" footer) when the current book/format uses native rendering, so the setting doesn't claim to do something it can't.

### Bug #241 — Background agents spawned via `Agent(isolation: worktree)` drift cwd into the main checkout
- **Repro**: spawn 3-5 agents in one session with `Agent(subagent_type: claude, isolation: worktree, ...)`. Multiple agents' early Bash calls inadvertently run from `/Users/ll/workspace/vreader` (orchestrator's main checkout) instead of the spawned worktree. When the agent later runs `xcodegen generate` for a version bump while stray files lie in main's working tree, those stray files get added to `vreader.xcodeproj/project.pbxproj` as references → produces a build that fails on any clean clone ("file not found in compile sources").
- **Root cause**: the `Agent` tool's `isolation: worktree` mode creates the worktree but does NOT set the spawned subprocess's initial cwd to the worktree path. The agent's Bash tool inherits cwd from the orchestrator (the main checkout). The Bash tool persists cwd between calls within a single session, so a single early call from the wrong cwd is enough to write files to the wrong place; once contaminated, subsequent `xcodegen generate` invocations fold those stray files into the pbxproj.
- **Session evidence (precedent)**: (1) v3.37.18 → v3.37.19 hotfix PR #1029 was caused by exactly this — stray `ReaderMoreMenuBilingualTests.swift` references landed in `project.pbxproj` without the source file being git-tracked, required a dedicated hotfix; (2) bugfix #957 agent self-reported "my first 4 Bash calls accidentally cd'd into /Users/ll/workspace/vreader (main checkout) instead of staying in the worktree, so the initial RED→GREEN cycle ran in the main repo. I patched this mid-flow by saving the diff to /tmp, reverting the main checkout, and re-applying the patch inside the worktree on the proper branch before committing" — agent self-rescued, no main contamination shipped, but only because it noticed.
- **Fix shipped (direction 2 — brief-template codification, PR #1052)**: `.claude/rules/48-parallel-execution.md` gained a new "Worktree cwd discipline (binding for every worktree-isolated agent)" subsection that documents the failure mode, names the precedent (PR #1029 + bug #957 self-rescue), mandates that every worktree-isolated agent's brief MUST include a "Critical Operational" preamble with `cd "<worktree-path>"` at the start of every Bash call + `pwd` confirmation before the first edit, provides a copy-pasteable preamble template orchestrators can paste verbatim, and lists an orchestrator-side checklist of what to verify before sending the brief. `AGENTS.md`'s parallel-execution bullet gained a one-line pointer to the new subsection so orchestrators see the discipline without deep-diving rule 48.
- **Directions not taken** (available as higher-scope follow-ups if needed): (1) harness-side cwd fix — out of vreader's scope (the `Agent` tool ships with Claude Code); (3) runtime pre-tool-use hook on `Bash` that detects cwd != worktree for a worktree-isolated session and auto-corrects or errors — feasible but more invasive than the brief-template workaround that's already proven effective in the session.
- **Caught by**: 2026-05-20 verify cron (this session's WI-7b→WI-8 hotfix + bug #957 agent self-report + 1 additional recurrence).

---

### Bug #245 — TXT bilingual mode renders chrome pill but does NOT render inline translations even after disk-cache hit
- **Repro on v3.38.16 / build 591**: (1) Configure an AI provider; (2) seed war-and-peace.txt; (3) open the book; (4) turn bilingual ON via More menu → setup sheet → Confirm; (5) tap Book details → Translate entire book → wait ~30s for 4/4 DONE; (6) close the Book Details sheet and observe the chapter — English-only despite 4 `ZCHAPTERTRANSLATION` rows in the cache. App kill + relaunch + re-open the book does not change the outcome.
- **Root cause**: TXT reader's `bilingualNonce` queries `vm.translations(for: unit)?.count` from `BilingualReadingViewModel.translationsByUnit` — an in-memory dict, NOT the on-disk store. The dict is only populated by `vm.startPrefetch(...)` → `prefetcher.translatedSegments(...)` (which reads the disk cache via `ChapterTranslationService`) → `vm.setTranslations(...)`, and the only trigger for `startPrefetch` is `vm.handlePositionChange(locator)`. EPUB / Foliate / PDF all wire `handlePositionChange` in their `+Bilingual` extensions; MD posts `.readerPositionDidChange` whose observer in `ReaderContainerView` keeps the AI coordinator's locator fresh. TXT shipped without ANY observer that ever called `vm.handlePositionChange`, so the in-memory dict never populated for TXT books — the renderer's compose pipeline short-circuited to the identity pass-through (no segments → returns source verbatim).
- **Fix shipped (PR #1070 / v3.38.17)**: (a) added `TXTReaderContainerView.triggerBilingualPositionChange(viewModel:locator:)` static helper that launches a Task calling `vm.handlePositionChange(locator)`; (b) added `onPositionChanged: () -> Void` field to `TXTBilingualSurfacesModifier` mirroring `PDFBilingualSurfacesModifier`; (c) wired chapter-idx `onChange` and `.readerPositionDidChange` observer to fire `onPositionChanged` in the modifier body; (d) `ensureBilingualViewModel()` kicks the initial trigger when `vm.isEnabled && !vm.needsSetupSheet` (re-open path with persisted state); (e) `confirmBilingualSetup` + the subsequent-enable branch of `handleMoreBilingualToggle` also trigger it. Mirrors PDF's Gate-4 round-1 H1 fix.
- **Test**: `vreaderTests/Views/Reader/Bilingual/TXTReaderContainerBilingualPositionTriggerTests.swift` — 5 cases: structural assertion that the modifier exposes `onPositionChanged`, behavioral assertion that the static helper populates `translationsByUnit` for the unit indicated by the locator (using real `TXTChapterTextProvider` + stub prefetcher), plus three no-op guards (nil VM, nil locator, disabled VM).
- **Lessons**: per-format bilingual host wiring requires a `handlePositionChange` call site, NOT just the chrome-pill toggle. The chrome pill's existence is decoupled from the renderer's data path — they meet at `translationsByUnit`. EPUB / Foliate / PDF / MD do this differently (direct calls vs notification posting), so there's no single shared wire; each format needs its own trigger surface, and a missing one fails silently because the renderer simply pass-throughs the source.
- **Caught by**: 2026-05-20 Feature #56 Gate-5b round-2 acceptance verification (`dev-docs/verification/feature-56-20260520-round2.md`).

---

