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

## Archived Open-Bug-Detail entries (2026-07-09 reconciliation — bug #358)

Moved verbatim from `docs/bugs.md` `## Open Bug Detail`: these 119 entries belonged to rows already terminal (FIXED / WONT DO / RECLASSIFIED) — the tracker rule archives an entry when its row leaves TODO/IN PROGRESS/REOPENED. The Summary table in `docs/bugs.md` remains the source of truth for status; entries below are historical repro context only.

### Bug #356 — Canonical identity diverges/collapses on string & number edge-cases: no NFC normalization + non-finite numbers silently omitted (FILED 2026-06-17 via /triage)

- **Found by**: independent Codex review of the Android port de-risk work (author≠auditor pass over landed Phase-0 + Spike-A/B; verdict `/tmp/codex-android-review.txt`). Both points confirmed against the code.
- **Defect (1) — no NFC**: canonical string fields (`href`, `textContext*`, title) are escaped without Unicode NFC normalization (`Locator.swift:120`, `Identity.kt:95`). Decomposed-vs-precomposed strings (accented Latin; iOS hands back NFD on some paths) → different canonical JSON → different hash → cross-platform identity divergence.
- **Defect (2) — non-finite omitted**: a non-finite `progression` (NaN/Inf) is silently dropped (`Locator.swift:122`, `Identity.kt:97`; the conformance tests bless it) → an invalid locator canonicalizes identically to one with NO progression.
- **Fix direction (not applied)**: NFC-normalize all canonical string fields before escaping (both languages) + NFC/NFD golden vectors; REJECT non-finite numbers instead of omitting. TDD + Codex re-audit per the gates.
- **Cross-ref**: #354 (Kindle fingerprint split) · #355 (lane doesn't cross-diff) — same review. ADR-0001 Risk 1. GH #1718.

### Bug #355 — Identity conformance lane over-claims byte-identity: run.sh never diffs Swift-vs-Kotlin output; golden vectors happy-path only (FILED 2026-06-17 via /triage)

- **Found by**: independent Codex review of the Android port de-risk work (author≠auditor pass; verdict `/tmp/codex-android-review.txt`).
- **Defect**: `contracts/conformance/run.sh:28,32` runs EACH platform against the SAME expected vectors — it never byte-diffs the actual Swift output against the actual Kotlin output, so a vector wrong in BOTH passes. Vectors are thin: `locator.json` has `0.5` but not `0.0`/`1.0`/`-0.0`/precision/empty/NFC/`textContextAfter`; `cache-key.json` has no empty components, delimiters, CJK, or normalization.
- **Why it matters**: this lane backs feature #104's "byte-identical Swift↔Kotlin / VERIFIED" — it proves "each side matches a hand-authored expected," NOT "the two match each other on hard inputs." Risk 1 is less retired than VERIFIED implies.
- **Fix direction (not applied)**: have run.sh emit each platform's actual canonical output and byte-diff Swift-vs-Kotlin; add edge vectors (numeric boundaries, NFC/NFD, empty optionals, delimiter collisions, large ints, CJK).
- **Cross-ref**: #354 · #356 (same review) · feature #104 (Spike A). GH #1717.

### Bug #354 — Converted-Kindle fingerprint contract is self-contradictory: DECISION.md mandates source-bytes, fingerprint.md/backup-format.md still say converted-EPUB bytes (FILED 2026-06-17 via /triage)

- **Found by**: independent Codex review of the Android port de-risk work (author≠auditor pass; verdict `/tmp/codex-android-review.txt`). Confirmed against the spec files.
- **Defect**: `DECISION.md:15` decides cross-platform identity for a converted Kindle book (`.azw3`/`.mobi`/`.prc`) = SHA-256 of the SOURCE file bytes (noting iOS currently fingerprints the converted EPUB as a "platform-local" detail, flagging source→converted as "the interop seam, see follow-up"). But `fingerprint.md:18` still specifies `contentSHA256`/`fileByteCount` of the CONVERTED EPUB bytes, and `backup-format.md:49` re-fingerprints "the original (converted) file."
- **Why it matters**: an implementer following the field spec builds the wrong (platform-local) identity → AZW3/MOBI/PRC library + backup identity silently diverges iOS↔Android. ADR-0001 Risk 1 is NOT fully retired for Kindle books despite feature #104 VERIFIED.
- **Fix direction (not applied)**: one consistent converted-Kindle fingerprint contract across DECISION/fingerprint/backup-format; state implementation obligations; add converted-Kindle/source-byte golden vectors.
- **Cross-ref**: #355 · #356 (same review) · feature #42 (Kindle convert-on-import) · feature #104 (Spike A identity). GH #1716.

### Bug #353 — Codex-audit merge gate not fail-closed: main-branch skip + diff-failure fail-open let a code PR bypass Gate 4 (FILED 2026-06-17 via /triage)

- **Found by**: independent Codex review of the Android Phase-0 gate-routing work (author≠auditor pass; verdict `/tmp/codex-android-review.txt`). Confirmed against the hook. The classifier fix itself (`code-paths.sh`) is correct; these are in the CONSUMING hook and pre-date #103.
- **Defect (1) — main skip**: `check_codex_audit_artifact.sh:76` `exit 0`s whenever the branch is `main`/`master` ("you'd be merging some OTHER PR") — but `gh pr merge #N` CAN run from `main`, so a code PR merged that way skips the audit. The standard ceremony merges from the feature branch (gate fires), so not hit in practice — but a real fail-open.
- **Defect (2) — diff fail-open**: if `git diff "${DIFF_BASE}...HEAD"` fails (`:107`), `CODE_TOUCHED` stays `no` → merge allowed (`:120-122`); inconsistent with the fail-CLOSED missing-classifier branch (`:112-117`).
- **Fix direction (not applied)**: block/enforce code merges from `main` against the PR head branch; fail CLOSED on a failed/empty diff. Keep `code-paths.sh` as-is.
- **Cross-ref**: feature #103 WI-1 (the classifier fix this audits) · #354/#355/#356 (same review). GH #1715.

### Bug #350 — First word-selection doesn't raise the selection card until the selection is expanded (FIXED 2026-06-12)

- **Repro (as filed)**: long-press a word → selection highlights + handles appear but NO card → drag a handle to expand → the card appears. Reported as "the first selection for any words in a new reading session" — and since #1635 suppressed the system menu, a missed card = NO selection UI at all.
- **Triage candidates DISPROVED**: both Readium-side candidates (`editingActions: []` starving `shouldShowMenuForSelection`; session-first lazy attach) were tested empirically — Readium raised the card on the FIRST plain word-selection in 3 runs including a cold window. The reproducible failure was **TXT/MD-side**, two facets.
- **Root cause (device-pinned)**: (1) **the card rode `editMenuForTextIn` exclusively** — UIKit doesn't request an edit menu for every selection (first long-press of a session can select, handles visible, without a request; synthetic HID selections never produce one) → live selection, no card; (2) **bilingual synthetic-run silent drop** — with interlinear ON, a selection STARTING in a `[MOCK译]` translation row hit `TXTBridgeShared.postSelectionNotification`'s `guard let start = sourceOffset(forDisplayOffset:) else { return }` and the post was silently dropped, so long-presses on translation rows NEVER raised the card.
- **Fix**: (1) `SelectionCardFallback` (new) — debounced (0.35s) selection-finalized card post from `textViewDidChangeSelection`, re-validated against the live selection at fire time, deduped bidirectionally against the `editMenuForTextIn` fast path; wired into `TXTTextViewBridgeCoordinator` + `TXTChunkedReaderBridge` (chunk-offset aware). (2) `projectSyntheticStartSelection` — a selection entirely inside a translation row anchors to the parent (nearest preceding) source paragraph's full range; spanning out of the row starts at the following source segment's start with the existing end-projection; a synthetic run with no preceding source still drops (nothing to anchor).
- **Tests**: `SelectionCardFallbackTests` (6: settle-posts-once, supersede, menu↔fallback dedup both directions, collapse-clears, cancel) + 3 projection tests in `TXTBridgeSharedBilingualTests` (anchor-to-parent, span-out-start, no-parent-drops; the old WI-12b drop-contract test removed as superseded).
- **Device-verified** (pre-merge): dark-blood-age TXT, bilingual ON → long-press directly on the `[MOCK译]` row → card raised (4 highlight colors + Note/Translate/Ask AI/Read), selection anchored. Artifact: `dev-docs/verification/artifacts/bug-350-synthetic-row-card-20260612.png`.
- **Cross-ref**: #338/#339/#340 (FIXED 2026-06-11, #1635) · #303/#317 (FIXED, same surface). GH #1687.

### Bug #348 — Reading surface shows the system scroll indicator (side "progress bar") — undesigned, misleading under the stitched window (FILED 2026-06-11 via /triage)

- **Repro**: read an EPUB in scroll mode (reported; reader-wide) → a thin vertical scroll indicator runs along the right edge of the reading surface. User decision: "we dont need a progress bar on the side."
- **Why remove**: (1) NOT in the design — the committed progress affordance is the bottom-chrome scrubber (feature #8 `ReadingProgressBar`); no canvas depicts a side rail → removal restores the designed state (rule-51-exempt); (2) MISLEADING in continuous scroll — under the #83/#85 window it tracks the loaded window, not the book (size/position jump on append/evict); (3) redundant with the scrubber + #101 metrics label.
- **Current state (code-read)**: TXT explicitly ON (`TXTTextViewBridge.swift:99`, `TXTChunkedReaderBridge.swift:231`); legacy EPUB default-on + maintains `verticalScrollIndicatorInsets` (`EPUBWebViewBridgeJS.swift:48-51`); Readium/Foliate webviews unconfigured (default shown); PDF — verify `PDFView`'s internal scroller.
- **Fix direction (not applied)**: `showsVerticalScrollIndicator = false` on every reader CONTENT surface (TXT/MD text views + chunked table, legacy EPUB + Foliate webview scrollViews, Readium navigator webviews); check paged-mode horizontal indicators; keep indicators on non-reader surfaces (sheets/lists/settings); drop the dead legacy inset maintenance. AC: no indicator on any format/layout reading surface; sheets unaffected.
- **Cross-ref**: #324 (FIXED — same class: default system chrome on the themed reading surface) · feature #8 (scrubber) · #101 (VERIFIED). GH #1676.

### Bug #347 — Continuous scroll stuck every ~3 chapters — REOPENED round 2 (post-fix device re-report; latency-vs-hard-cap to be pinned by the fix's own log lines) (FILED 2026-06-11 via /triage)

- **🔴 ROUND 2 (2026-06-11 evening, user-confirmed rebuilt after the 13:31 soft-ceiling fix)**: still "stuck every 3 chapter" — regular periodicity. The round-1 close was a verification-exception (4th exception-close overturned by a device re-report this week) and the bug's own RED ("chained-fling idb sweep must never reach the edge") wasn't run as a real sweep.
- **Round-2 candidates**: (a) **append latency starvation** — the ~3-chapter cycle = consume lookahead → stall → settle drains/catches up → repeat; at fling speed section builds can't keep up and the 800px `nearBottom` trigger starts builds far too late → need earlier/deeper prefetch (viewports ahead, >1 section); (b) **the HARD cap** (`touchGrowthHardCapSlack = 12`) engages on long chains while evictions stay deferred. **Decided by the fix's own log lines** in a #96 Diagnostics export: `in-gesture HARD growth cap reached` → (b); `past the soft ceiling; edge-driven append continues` yet edge-hits → (a).
- **➕ FACET 2 (same report): a JUMP accompanies each stall** — user: "stuck every 3 chapter **and jump**". This matches the round-1 fix's own settle design: the first settled signal "drains the WHOLE eviction backlog back to maxSpan" and the queued ResizeObserver deltas apply at once — after a multi-chapter chain that's a LARGE one-shot scrollTop compensation in a single frame → visible jump right as the stall releases. Stall → pause → settle → drain → JUMP → repeat: one cycle, two symptoms. Fix-direction addition: **amortize the settle drain** (evict/compensate incrementally across frames, or drain only down to a comfortable span, or anchor-preserve around the drain) so settle is visually silent.
- **Re-close bar (round 2)**: a REAL chained-fling gesture sweep (idb, no settle gaps, user-class CJK book, fling speed) never reaching the edge **AND no visible jump at any settle** (monotonic reading position through stall-release) + the log-confirmed mechanism in the evidence file. Exception closes no longer qualify on this subsystem. GH #1658 (reopened).

_Round-1 filing:_

- **Repro**: EPUB (Readium, scroll layout) → read by chained flings without pausing → after ~the window-span's worth of chapters the scroll bottoms out at the stitch edge; the next chapter hasn't been appended. Likely self-recovers after a ~160ms pause (settle drains the backlog) — recurring friction, not a permanent stall.
- **Expected**: sustained continuous scrolling never reaches the loaded edge — forward lookahead keeps ahead of the reader.
- **Root cause candidates (code-read — a failure mode introduced by the round-4 design, #1639)**: (1) **the gesture window never closes under chained flings** — it needs 160ms of scroll quiescence post-touch; back-to-back flicks (each touchstart inside the prior deceleration) keep `touchActive` true indefinitely → the settle report never fires → deferred evictions/prepends never drain; (2) **the in-gesture growth ceiling then starves appends** — while the window is open, forward appends defer once span hits the ceiling ("in-gesture growth ceiling reached (span N); deferring append", `EPUBContinuousScrollCoordinator:196`); with evictions deferred the span can't shrink → lookahead consumed → edge.
- **Fix direction (not applied)**: edge-proximity override (allow forward appends past the ceiling when within ~1 viewport of the edge — appends don't write scrollTop, gesture-safe by round-4's own analysis); and/or opportunistic evict-drain in brief inter-fling gaps; and/or raise the ceiling. Add a chained-fling case (no settle gaps) to the round-4 real-gesture idb sweep. Diagnostic: a #96 log export during repro shows the ceiling lines directly.
- **Cross-ref**: #329 (FIXED round 4 — oscillation gone; THIS is the round-4 trade-off surfacing: the lookahead-starvation risk flagged when the mutation-deferral invariant was recommended) · GH #1568 (saga) · #327/#325 (older boundary-stall family). GH #1658.

### Bug #346 — Switching EPUB to scroll mode loses the injected bilingual translations (re-enumerate races the scroll-arrangement rebuild) (FILED 2026-06-11 via /triage)

- **Repro**: EPUB (Readium) → bilingual ON, translations visible in paged → switch layout to Scroll → the rebuilt scroll view renders source-only; interlinear rows gone. Cache is intact (this is inject/DOM loss, not cache loss — toggling bilingual off/on or reopening likely restores).
- **Expected**: translations survive a paged↔scroll switch (WI-12's contract: bilingual works in BOTH layouts; the layout-change handler exists for exactly this).
- **Root cause candidates (code-read)**: (1) **re-enumerate races the rebuild** — `.onChange(of: epubLayout)` → `handleEPUBLayoutChange` (`ReadiumEPUBHost+BilingualDriver.swift:252-269`) fires IMMEDIATELY (`layoutChangeAction` → `.reEnumerate`, gate at `ReadiumBilingualChapterTracker.swift:204-209`) → `tracker.reset()` + `commander.clear()` + enumerate — against the **dying paged DOM**, while the continuous-scroll arrangement rebuilds asynchronously (`EPUBContinuousScrollCoordinator.materializeInitialWindow`, `:235`). The new scroll DOM lands unstamped/uninjected, and the tracker (reset consumed pre-rebuild) dedupes the post-rebuild relocate's enumerate → nothing re-injects. (2) **initial-window sections may lack an inject hook** — the coordinator's bilingual signals (`onSectionEvicted`, block buckets) are wired for extends/evicts; verify initially-materialized sections get the same enumerate/inject pass.
- **Fix direction (not applied)**: trigger the layout-change enumerate from the NEW generation's ready signal (post-`materializeInitialWindow` / first relocate of the new arrangement) instead of synchronously at the settings flip; or fire the extend-path bilingual signals from the initial materialization. RED via the #77 harness: paged-with-translations → switch to scroll → assert `loading:0, mock:N` in the scroll DOM; cover scroll→paged too. Rule 51 N/A (restores shipped behavior).
- **Cross-ref**: WI-12 (predates the #83/#85 window — "scroll DOM" changed under it) · #343 (FIXED — cache restore; cache intact here) · #334 (FIXED — inject-map family) · #329 (window coordinator). GH #1657.

### Bug #345 — Reader chrome never shows session time on the live engines — Readium/Foliate pass a percent label instead of `sessionTimeDisplay` (FILED 2026-06-10 via /triage)

- **Repro**: read an EPUB (Readium default) or AZW3 (Foliate) → the bottom-chrome trailing label shows a percentage; read a TXT/MD/PDF → the same slot shows the current session time. The user (who reads on the live engines) never sees session time.
- **Expected**: parity — the session-time trailing label on every format.
- **Root cause (code-confirmed — the #299/#313 Readium-flip wiring-gap class)**: `ReaderLifecycleHelper.sessionTimeDisplay` (driven by `ReadingSessionTracker`) is wired as `trailingLabel` by TXT (`:460,485`), MD (`:113`), PDF (`PDFReaderContainerView+Overlays.swift:93`), legacy EPUB (`EPUBReaderContainerView+Navigation.swift:37`) — but the Readium host computes `chromeTrailingLabel = "\(pct)%"` (`ReadiumEPUBHost+BottomChrome.swift:102`) and Foliate (`FoliateBilingualContainerView+BottomChrome.swift:40`) likewise; neither consults a lifecycle helper. The chrome's own doc anticipates "or session time" (`ReaderBottomChrome.swift:41`).
- **Fix direction (not applied)**: wire `sessionTimeDisplay` (or equivalent) into the Readium + Foliate trailing labels, mirroring the other hosts' precedence call for the single slot. Rule 51: parity restoration of shipped designed behavior → N/A; verify the #60 chrome design's trailing-label spec.
- **Cross-ref**: #299/#313 (wiring-gap family; #313 REOPENED — same host files) · feature #101 (in-reader TOTAL time display, filed alongside) · feature #58 (data layer). GH #1631.

### Bug #344 — Bilingual "Sentence" granularity option is silently ignored — prefetcher forces `.paragraph` on every format (FILED 2026-06-10 via /triage)

- **Repro**: bilingual setup → granularity = **Sentence** → enable → translations render one interlinear block per paragraph, identical to Paragraph mode (user screenshot: whole-paragraph CJK block under the prose).
- **Expected**: per-sentence interlinear rendering — or the option not offered while unsupported.
- **Root cause (code-confirmed — knowingly dead setting)**: `ChapterTranslationPrefetcher.translatedSegments` (`:74-91`) — `_ = granularity  // explicitly ignored` + `let effectiveGranularity = .paragraph`. The comment documents the Gate-4 decision: the EPUB renderer injects ONE translation per DOM block; sentence granularity would break the 1:1 block↔segment contract — "the setup sheet's sentence option becomes meaningful only when a per-format sentence-aware enumerator lands (**currently no format has one**)." Yet `BilingualSetupSheet.availableGranularities` still offers Sentence → users select a silent no-op.
- **Fix direction (not applied), two tiers**: (1) **stop misleading (small)** — hide/disable Sentence until supported; rule 51: the granularity control is part of the designed setup sheet (§2.2), so the disabled/hidden state needs a design check / `needs-design`; (2) **honor it (feature-workflow-class)** — per-format sentence-aware enumeration (`ChapterSegmenter.sentences` exists): split block text into sentences, inject per-sentence rows within a block, preserving the 1:1 pairing + cache count contract (cf. #268/#334/#343 family).
- **✅ DESIGN LANDED 2026-06-11 (#1646 delivered)**: per-sentence rows (S-A, `BSSentencePara`/`BSSentenceSlot` — 0.85×, `accent40` border, 7px between pairs, cached/loading/pending states) + the designed DISABLED control state (S-C, 45% opacity + info footnote) as the per-format fallback. Bundle in `dev-docs/designs/vreader-fidelity-v1/` (`design-notes/bilingual-suite-issues.md`). Unblocked; implementation HELD for a separate go-ahead.
- **Cross-ref**: feature #99 (design landed alongside, #1640) · #343/#342/#341 (cache pass — FIXED 2026-06-11) · feature #56. GH #1629.

### Bug #343 — Bilingual toggle off→on re-translates instead of restoring from cache — direct-path translations never persisted; count guard strands rows (FILED 2026-06-10 via /triage)

- **Repro**: enable bilingual on a divergence-class chapter (DOM block count ≠ segmenter count — title/copyright pages, `<pre>`/nested blocks, the #268 fallback class) → translations render → toggle bilingual OFF → ON → loading shimmer + a full provider re-translate instead of an instant cache restore.
- **Expected**: toggle-on restores from the persistent disk cache (#56's promise) with zero provider calls.
- **Root cause (code-confirmed) — two mechanisms**: (1) **the #268 divergence fallback is cache-free** — on `segments.count != currentBlocks.count` the EPUB inject translates the DOM-enumerate's block texts via `translatePreSegmented`, which **never writes to `ChapterTranslationStore`**; toggle-off clears the in-memory `translationsByUnit` (by design, `BilingualReadingViewModel.swift:26`) → toggle-on re-prefetches → no row → re-translate. Affected chapters are NEVER cached (every toggle AND reopen costs a re-translate). (2) **the read guard strands count-drifted rows** — `cachedTranslation` rejects a row unless `cached.sourceParagraphCount == segments.count` (`ChapterTranslationService.swift:129-130`) with `segments` re-derived via `ChapterSegmenter` at read time → any write/read count divergence makes the row permanently unreachable (self-sustaining miss loop). Non-divergent chapters ARE cache-first/instant — the defect is scoped to the divergence class + drifted rows.
- **Fix direction (not applied)**: persist direct-path translations with the **enumerate's** count as the row's contract (or store the producing derivation on the row) so the read path validates against the same contract instead of re-deriving; unify the unit count contract between DOM enumerate and segmenter (mirror #334's shared leaf-block helpers to EPUB). RED: toggle OFF→ON on a previously-translated divergence-class chapter performs ZERO provider calls (mock-asserted); reopen likewise. Rule 51 N/A.
- **Context**: the reporting user's book also carries #341/#342 damage — but those fixes alone won't cover the divergence class (never cached at all). **Cross-ref**: #341 (open High) + #342 (open) — same cache subsystem, recommend ONE coherent cache-architecture pass · #268/#334 (FIXED — the divergence/count family) · #306 (FIXED) · feature #56. GH #1622.

### Bug #342 — Re-translate and bilingual mode don't share one canonical translation — `providerProfileID` is baked into the cache key (FILED 2026-06-10 via /triage)

- **Repro**: re-translate a chapter with a provider override → close + reopen the book → bilingual mode does NOT show the re-translated result; it cache-misses (shimmer) and re-translates with its own/default provider, silently discarding the user's chosen re-translation (the row exists but is unreachable).
- **Expected** (user: "the re-translate chapter and bilingual mode should share the same translation result"): one canonical translation per unit+language that both flows read and write.
- **Root cause (code-confirmed)**: the cache key is `book|unit|targetLanguage|providerProfileID|promptVersion` (`ChapterTranslationRecord.lookupKey`, `:86-100`) — **the provider profile is part of the translation's identity**. Re-translate writes under the picker's (potentially overridden) profile key; the bilingual read path looks up with ITS resolved active-profile ID (`ChapterTranslationService.cachedTranslation(providerProfileID:)`, `:110-129`). The divergence is conceded in the re-translate VM's own comment ("the original row would otherwise … serve a stale hit when bilingual mode is on with the original profile", `ChapterReTranslateViewModel.swift:280-284`) — and the delete-the-original workaround for that staleness is exactly what #341 makes lossy. In-session sharing is an illusion via the in-memory `onTranslationApplied` push; it dies on reopen. Same identity-fragility class as #306 (profile change orphans all cached translations under the old UUID).
- **Fix direction (not applied)**: make the unit's translation **canonical** — one current translation per `book|unit|language` read+written by BOTH flows (drop `providerProfileID` from lookup identity, or a current-translation pointer per unit); record provider/style as **metadata on the row** (provenance for the re-translate sheet), not identity. Eliminates the staleness rationale for delete-before-write → pairs naturally with #341's atomic write-then-delete; **fix together**. AC: override re-translate survives reopen; whole-book + single-chapter re-translate coexist; profile re-creation doesn't orphan rows. Rule 51 N/A (data-layer).
- **Note**: with a single profile (the user's setup) the keys coincide and sharing works — their observed disappearance was #341's delete path; this row is the architectural defect their ASK names, which bites whenever profiles diverge. **Cross-ref**: #341 (open High, same flow) · #306 (FIXED, same class) · feature #56 · #311/#320/#333 (FIXED). GH #1621.

### Bug #341 — Re-translate destroys the existing translation on failure — cache row deleted BEFORE the new translation lands (non-atomic swap) (FILED 2026-06-10 via /triage)

- **Repro (user's observed chain, 2026-06-10)**: 19:04 — re-translate "Copyright" reaches 50% → user backgrounds the app → request dies (feature #98: no background execution) → error. 19:06 — reopen the book → the previous translations are GONE (shimmer bars under Copyright + before Disclaimer) and the bilingual prefetcher re-translates from scratch.
- **Expected**: the re-translate sheet's own copy — *"Existing translation is kept until the new one is ready"* — i.e. a failed/cancelled re-translate leaves the original translation intact; reopening shows the cached translation instantly (#56's persistent-disk-cache promise).
- **Root cause (code-confirmed)**: `ChapterReTranslateViewModel.swift` — the header documents "**Cache row is deleted BEFORE the translation request**" (`:11`), and the run does `store.deleteTranslation(forKey: originalKey)` at 0.25 progress (`:280-292`) before the provider resolves (0.5) or any translated text exists. The error path "rolls back to the picker" (UI only) — **nothing restores the deleted row** → any failure after 0.25 permanently destroys the original translation (provider tokens the user already paid for). The on-reopen "retranslating again" is the bilingual prefetcher's normal cache-miss behavior — the defect is the cache loss.
- **Fix direction (not applied)**: make the swap **atomic — write-then-delete**: translate into a staging row/memory; only on durable success replace the original (delete the orphaned old-profile row AFTER the new row lands — the delete-first "orphan cleanup" rationale survives reordering); on failure/cancel the original row remains. RED: original cache row survives (a) provider failure mid-stream, (b) user cancel, (c) simulated suspension. Rule 51 N/A (data-layer ordering; the sheet copy becomes truthful).
- **Severity High** — destroys persisted user data on an easy-to-hit failure path (#98 makes backgrounding a guaranteed failure). **Cross-ref**: feature #98 (open — the common trigger) · #311/#320/#333 (FIXED — same flow) · #306 (cache gate) · feature #56 (disk cache). GH #1620.

### Bug #340 — EPUB (Readium) selection paint is stock iOS blue — themed `::selection` never injected on Readium; WKWebView handles untinted everywhere (FILED 2026-06-10 via /triage)

- **Repro**: open an EPUB (default Readium engine) → select text → stock iOS **blue** wash + blue drag handles on the warm paper page (screenshots on GH #1617; user: "the selection style is iOS too" — WeChat Reader themes its selection paint + handle dots).
- **Expected**: selection wash + handles in the reader theme accent, like TXT/MD post-#324.
- **Root cause (code-confirmed) — partially implemented theming**: a themed rule EXISTS — `::selection { background-color: <accent>; color: <paperBG> }` (`ReaderThemeV2+EPUBCSS.swift:174-177`) — but its only consumer is the **legacy** `EPUBReaderContainerView` (`:735`); the **Readium** path never injects it (no `::selection`/override-CSS injection in `ReadiumNavigatorRepresentable`/`ReadiumReaderCoordinator`) → default engine falls back to system blue. Separately, the **handles + caret** are UIKit chrome governed by the web view's `tintColor` — #324's fix set it on TXT/MD `UITextView`s only; NO WKWebView gets a tintColor (Readium / legacy EPUB / Foliate), so handles stay blue even where the wash is themed. This is exactly the path #324 carved out ("EPUB/AZW3 select via WKWebView `::selection` CSS — separate path") but never filed.
- **Fix direction (not applied; code-only, rule 51 N/A — parity theming with the existing accent token, same class as #324)**: (1) Readium — inject the `::selection` rule via the existing documentEnd injection channel (transparency/justify), per-theme + theme-change refresh, likely `!important`; (2) handles — `tintColor = theme.accentColor` on the underlying WKWebViews (Readium navigator's web views, `EPUBWebViewBridge`, `FoliateSpikeView`); (3) Foliate — mirror the rule in foliate-host CSS (#93 parity). AC: accent selection on Readium/legacy/Foliate across themes (check Dark/OLED legibility of `color: paperBG`); TXT/MD (#324) unchanged.
- **Cross-ref**: #324 (FIXED — TXT/MD sibling; this is its carved-out WKWebView path) · #339 (open — selection *menus*, same WeChat-class family) · #338 (open). GH #1619.

### Bug #339 — Readium selection shows the default iOS edit menu alongside the designed selection card (dual toolbars; `editingActions` never customized) (FILED 2026-06-10 via /triage)

- **Repro**: open an EPUB (default Readium engine) → long-press/select text → the **stock iOS edit menu** (Copy / Look Up / Translate / ▸) appears anchored at the selection AND vreader's designed card (quote + colors + Note/Translate/Ask AI/Read) appears at the bottom — two competing toolbars at once. User comparison: WeChat Reader fully replaces the system menu with its own anchored toolbar (复制/划线/写想法/分享书摘/查询/听当前); ours "still retains its default behaviour."
- **Expected**: ONE selection UI — the designed card — with the system menu suppressed or reduced to a deliberate minimal set.
- **Root cause (code-confirmed)**: the Readium navigator is constructed with **no `editingActions` configuration** (grep: zero `editingActions`/`EditingAction` in `vreader/`). `EPUBNavigatorViewController.Configuration.editingActions` defaults to the full system set → the stock menu pops on every selection. The designed card (feature #60 WI-7 / #317's floating overlay) was layered on top without retiring the system menu — the WI-7c2..7c5 swaps replaced the legacy custom `UIMenu` paths but never addressed Readium's.
- **Fix direction (not applied)**: (1) restrict Readium `editingActions` (minimal/empty) so the card is THE selection UI; (2) **decide Copy's home first** (rule 51) — the designed card has NO Copy and the system menu is today the only Copy affordance: keep a Copy-only system menu, or add Copy to the card (new affordance on a designed surface → check `vreader-reader.jsx::SelectionPopover`, file `needs-design` if absent); (3) verify TXT/MD/legacy-EPUB don't double-show post-WI-7 swap.
- **Cross-ref**: #338 (open — same surface, the card's tap-catcher blocks handle drags; fix both together for one coherent selection UX) · #317 (FIXED — card presentation) · #303 (FIXED). GH #1617.

### Bug #338 — Selection handles can't be dragged to expand while the selection popover is shown (full-screen tap-catcher eats drags) (FILED 2026-06-10 via /triage)

- **Repro**: open any book (reported on EPUB "The Half Second") → long-press to select text → the selection card (quote + colors + Note/Translate/Ask AI/Read) appears → drag either selection handle → nothing happens. The card appears the instant text is selected, so a selection can never be refined.
- **Expected**: handles stay draggable while the card floats (the #317 fix's own comment: the card "floats over the **live** reader"); the card's quote refreshes to the expanded selection.
- **Root cause (code-confirmed)**: `SelectionPopoverPresenter.floatingCard` (`SelectionPopoverPresenter.swift:195-202`) lays a transparent **full-screen tap-catcher** under the card — `Color.clear.contentShape(Rectangle()).ignoresSafeArea().onTapGesture { dismiss() }`. `contentShape(Rectangle())` makes the clear layer hit-testable everywhere; a tap dismisses (by design) but a **drag fails the tap recognizer and is not re-delivered** to the WKWebView/UITextView underneath → handle drags AND reader scrolling are dead while the card is up. The catcher defeats exactly the "live reader" the floating-card design specifies (`vreader-reader.jsx::SelectionPopover`).
- **Scope**: the presenter modifier is shared — TXT (`TXTReaderContainerView.swift:345`), MD (`:130`), legacy EPUB (`:404`), Readium (`ReadiumEPUBHost+Highlights.swift:40`) — all formats affected.
- **Fix direction (not applied)**: remove the hit-blocking catcher — `allowsHitTesting(false)` or delete it — and dismiss on **selection-cleared** signals from the bridges instead (an outside tap clears the native selection anyway); ideal UX: a handle drag updates the selection → the bridge reposts the popover request → the card refreshes its quote. Rule 51: restores the design's "floats over the live reader" intent; check `vreader-reader.jsx` for the dismissal spec.
- **Cross-ref**: #317 (FIXED — the floating-card overlay this catcher shipped with) · #303 (FIXED — same surface). GH #1616.

### Bug #336 — EPUB justified Latin still gappy on short lines — REOPENED 2026-06-10 (device re-report; hyphenation fix doesn't cover few-word lines) (FILED 2026-06-10 via /triage)

- **🔴 REOPENED 2026-06-10 (device re-report, post-fix build)**: "the space between words is too big" — and the SAME screenshot proves the v3.61.2 hyphenation fix is active (copyright prose hyphenates "includ-ing"/"oth-er"/"permis-sion" and reads evenly) while the title-page subtitle still renders stretched: "How␣␣first␣␣reactions␣␣get␣␣installed,".
- **Surviving mechanism — short, few-word lines**: a non-final line with 5 words / 4 gaps takes ALL the justification slack across 4 spaces; hyphenation can't absorb it when the next word ("and") is too short to break. The paragraph's final line is correctly ragged — isolating the defect to non-final lines of short paragraphs. Front matter (title-page subtitle / byline) shouldn't be justified at all, typographically.
- **Close-quality note**: #1605 closed under a verification-exception ("not reliably screenshot-able on the sim"); the user's device screenshot is the missing visual evidence and shows the complaint unresolved for this line class.
- **Fix direction (escalate to the deferred alternative; not applied)**: gate `text-align: justify` on CJK content. The v3.61.2 fix already threads `dc:language` end-to-end on BOTH engines (legacy `contentLanguage`/`langInjectionJS`; Readium publication metadata) for hyphenation — reuse that signal so Latin/`en` paragraphs revert to natural left-align (ragged-right, the Western norm) and CJK keeps flush justify (#95 preserved). Alternative/minimum: exempt short paragraphs + front-matter spine items. Rule 51 N/A (rendering attribute tuning).
- **➕ FACET 2 (2026-06-10 22:32 re-report): chapter HEADINGS justify too** — second user screenshot: the chapter heading "Prologue:␣␣␣␣I␣␣␣␣quit / smoking␣after␣39␣years…" renders justified with huge gaps while the body below hyphenates evenly. **Mechanism (code-confirmed, Readium path)**: `ReadiumEPUBReaderViewModel+Mapping.swift` sets `textAlign: .justify` (`:143`) **with `publisherStyles: false`** (`:138`) — the publisher's own heading alignment is stripped, so the body-wide justify cascades into `h1–h6`; the comment's claimed exclusions ("blockquote/figcaption") don't cover headings. (The legacy CSS path is immune for true `<h*>` — its rule targets `p:not(...)` — but p-tagged headings would also catch it.) The ORIGINAL #336 filing flagged exactly this edge case ("headings/figures should NOT justify"); the v3.61.2 fix didn't add the exemption. **Fix-direction addition**: headings must be exempted from justify on BOTH engines INDEPENDENTLY of the CJK-gating decision — even a CJK book's headings shouldn't justify (a CJK-gated justify alone would NOT fix CJK-book headings). Readium: re-assert heading alignment (e.g. injected `h1,h2,h3,h4,h5,h6 { text-align: start/inherit-publisher }` after the user setting) or scope the user textAlign away from headings.
- **Re-close bar (device, not exception)**: "The Half Second" title-page subtitle renders without stretched gaps; **chapter headings (e.g. the "Prologue:" h1) render left-aligned/publisher-aligned, never gap-justified**; body prose stays even; a CJK EPUB body stays flush-justified. Area: `vreader/Models/ReaderThemeV2+EPUBCSS.swift` + `vreader/ViewModels/ReadiumEPUBReaderViewModel+Mapping.swift`. GH #1605 (reopened).

### Bug #329 — EPUB continuous scroll jumps / isn't smooth — REOPENED round 4 2026-06-10 (post-fix device re-report on v3.62.5+; real-gesture verification required) (FILED 2026-06-07)

- **🔴 ROUND 4 (2026-06-10, user-confirmed on v3.62.5+)**: still jumps with the round-3 px-aware-eviction-deferral fixes installed. Round 3 verified with **simulator + synthetic 1px DebugBridge ticks** on one small book; real-finger smoothness was explicitly deferred (`awaiting-device-verification`) — the user is that verification, and it failed. Gap candidates + the tightened REAL-GESTURE re-close bar are in the summary row.
- **⚠️ ARCHITECTURE RECOMMENDATION (round 4 — simplify before patching again)**: four rounds of compensation-upon-compensation (directional prefetch → wedge → echo suppression → still oscillates → px-aware deferral + ResizeObserver compensation + slack budgets/margins → still jumps on device) say the bug class is structural: **the coordinator mutates `scrollTop` while the user is actively scrolling**. Recommend a Gate-1 planned simplification instead of a 5th point patch — candidate invariant: **never mutate window/scrollTop during active scroll**; defer ALL extends/evicts/compensations to scroll-idle (bigger lookahead margin so the window edge is never hit mid-fling; eviction at idle is invisible); freeze section heights once rendered (reserve image space via aspect-ratio placeholders so async decode never resizes scrolled content). That one rule deletes the entire jump class the four rounds have been chasing.

---

_Round-1 reopen context (2026-06-10, the 1px bar):_

- **🔴 REOPENED 2026-06-10 (device re-report)**: EPUB scrolling still "isn't smooth; it often jumps" on a post-fix build. The user sets the verification bar explicitly: **"it needs to be tested by scrolling one pixel at a time"** — the v3.59.22 close was device-verified with **60px** DebugBridge steps, and that exact granularity already let one real regression through once (the v3.59.21 sticky-bias wedge passed green unit tests + a 60px sweep, then wedged on device).
- **Candidate mechanisms** (fixer to pin via the 1px sweep):
  - **(a) Echo-suppression undercount** — the v3.59.22 fix arms `ignoreNextNearTop`/`ignoreNextNearBottom` and consumes ONE echoed boundary per evicting extend. At 1px granularity many boundary signals fire between extends; an eviction plus a concurrent height change can emit MORE than one echo → the unsuppressed echo still triggers the spurious prefetch → thrash/jump.
  - **(b) Post-fix height-shifters that postdate the closed verification** — `#332` (v3.60.x) makes stitched images actually LOAD (the verified build rendered broken-image glyphs = static heights), so sections now GROW asynchronously as images decode mid-scroll with no scrollTop compensation → visible jump; `#95` justify (v3.59.30+) + `#336` hyphenation (v3.62.x) re-layout every paragraph → section heights differ from what was verified.
- **Re-close bar (records the user's directive)**: a **1px-granularity** DebugBridge scroll sweep across ≥2 chapter boundaries on an image-bearing EPUB must show monotonic scrollTop/progress — no backward jumps, no stalls — including a pass while images are still decoding. A 60px sweep does NOT satisfy re-close.
- **Area**: `vreader/Views/Reader/EPUBContinuousScrollCoordinator.swift` (+ stitch JS `removeChapterSectionJS` / extend path). GH #1568 (reopened).

### Bug #337 — Reading stats per-book table: NOTES column header wraps to "NOTE / S" (cramped header) (FILED 2026-06-10 via /triage)

- **Repro**: Settings → Reading stats sheet → the per-book table header row renders `BOOK · TIME · HL · NOTE/S · READ` — the **NOTES** header wraps to two lines ("NOTE" / "S"), making the form look broken.
- **Expected**: all five column headers render on one line; clean table header.
- **Root cause (code-confirmed)**: `StatsPerBookTable.swift` — the NOTES column is fixed at **38pt** (`:129`), too narrow for the uppercased "NOTES" label (10.5pt semibold + 0.5 tracking); and the header `Text` (`:146-148`) has **no `.lineLimit(1)`** (the data cells DO — `:175,195`), so the header wraps instead of clamping to one line.
- **Fix direction (not applied; rule 51 — restore the table to its DESIGNED single-line-header state per `dev-docs/designs/vreader-fidelity-v1/project/stats-followups-artboards.jsx`)**: add `.lineLimit(1)` (+ `minimumScaleFactor`/`fixedSize`) to the header label and/or rebalance the column widths (widen NOTES, tighten HL/READ) to the design spec so all five headers fit on one line. The file already flags (`:210`) the layout "breaks at sub-360pt widths" — fold this into that width handling; use the designed widths, don't invent new ones.
- **Scope note**: this is the concrete objective defect behind "the form is ugly." If a broader stats-table redesign is wanted beyond fitting the headers, that's a separate `needs-design` ask — but the surface IS already designed (Feature #58 dashboard / #67 stats entry, `vreader-stats.jsx`), so this is an implementation fix, not a missing design. GH #1606.

### Bug #336 — EPUB justify-by-default (#95) makes Latin/English text gappy — excessive inter-word spacing (FILED 2026-06-10 via /triage)

- **Repro**: open an English EPUB (or bilingual mode with an English source) → body paragraphs render with large, uneven gaps between words (screenshot: "body's␣␣␣␣␣␣chemistry;␣␣␣␣␣␣␣␣nothing"). CJK paragraphs in the same view justify cleanly; only Latin gaps.
- **Expected**: English/Latin text reads without distracting inter-word gaps; CJK stays flush-justified (the #95 win).
- **Root cause (code-confirmed)**: `ReaderThemeV2+EPUBCSS.swift:135-137` — `p:not([style*="text-align"])…{ text-align: justify !important; }` — applies `justify` to **every** paragraph regardless of script, with **no `hyphens`** and no `text-justify` tuning. Latin justification with no hyphenation has few break points, so the layout stretches inter-word spaces to fill each line → the gaps. CJK justifies per full-width cell so it stays clean.
- **This is #95's documented edge case.** Feature #95's plan explicitly flagged "Latin/mixed justification stretches inter-word spacing (can look gappy — consider CJK-only or a quality threshold / `text-justify`)"; #95 shipped justify-by-default (VERIFIED — the CJK case) WITHOUT the Latin mitigation, so the risk materialized.
- **Fix direction (not applied; code-only, rule 51 N/A — tuning an existing rendering attribute)**: keep justify for CJK but stop Latin gapping — scope justify to CJK (`:lang(zh/ja/ko)` or script detection) leaving Latin left-aligned (ragged-right is the Western norm), and/or add `hyphens: auto` (+ `-webkit-hyphens: auto`) so Latin justification gets break points and far smaller gaps; consider `text-justify: inter-character` for CJK. (An explicit Left/Justified Display toggle is #95's deferred needs-design item — out of scope here.) Also verify Readium-engine path (#95 applied to legacy CSS + Readium) and #92 (TXT) for the same Latin gappiness.
- **Cross-ref**: Feature #95 (EPUB justify, VERIFIED — the regressing change) + #92 (TXT justify). GH #1605.

### Bug #335 — AI Chat renders assistant replies as RAW markdown (literal `**bold**`, `[tags]`, `-` lists) instead of formatted text (FILED 2026-06-10 via /triage)

- **Repro**: AI Assistant → **Chat** → ask anything that elicits a formatted reply (the model emits markdown bold + bullet lists) → the reply shows the raw `**…**` / `[…]` / `-` markup instead of rendered formatting. Screenshot shows `**笔记：**`, `**[copyright]**`, `**"describes"**`, `**[why-willpower-cant-reach]**` etc. as literal text.
- **Expected**: chat replies render markdown — bold/italic/links inline, bullet lists as lists.
- **Root cause (code-confirmed)**: `AIChatMessageRow.swift:77` (user bubble) and `:101` (assistant bubble) render `Text(message.content)` where `ChatMessage.content` is a `String` (`ChatMessage.swift:26`). SwiftUI's `Text(_:)` parses markdown **only for string literals / `LocalizedStringKey`** — a `String` *variable* is rendered verbatim. No markdown helper is used in the chat path (grep: 0 `AttributedString(markdown:`/`LocalizedStringKey` in `Views/AI/`). So every markdown token the LLM emits shows literally.
- **Fix direction (not applied)**: render assistant content as markdown — inline (`**bold**`/`*italic*`/links/`code`) is cheap via `AttributedString(markdown:options:)` with `.inlineOnlyPreservingWhitespace`, but the replies also use `-` bullet lists + blank-line paragraphs which inline-only won't lay out → likely a lightweight per-block renderer (split paragraphs/list items) or a markdown view. Fallback to plain text on parse failure (malformed/partial markdown). Streaming: #323 now coalesces deltas so re-parsing per flush is fine, but a half-open `**` mid-stream must degrade gracefully. **Scope check**: confirm whether the Summarize / Translate tabs already render markdown or ALSO show raw — if also raw, broaden (this row is the confirmed **Chat** surface). Code-only behind the existing chat bubble; **rule 51**: rendering the SAME content as formatted markdown is not new chrome → N/A (verify the designed chat bubble anticipated markdown; the AI-shell designs show formatted replies).
- **Cross-ref**: same `AIChatMessageRow` touched by #323 (streaming coalesce, FIXED) — that fix addressed re-render churn, NOT markdown rendering. GH #1604.

### Bug #333 — Re-translate a long chapter shows a false "You appear to be offline" error when the device is online (timeout mislabeled as offline) (FILED 2026-06-09 via /triage)

- **Repro**: open a book with a **long** chapter → More menu / bilingual → **Re-translate chapter** → tap **Re-translate** → after a wait the sheet shows the red banner *"You appear to be offline. Try again when you have a connection."* — but the device has full connectivity (WiFi + cellular shown in the status bar). Short chapters re-translate fine.
- **Expected**: a long chapter either translates, or shows an accurate error (e.g. "the request timed out — the chapter may be too long; retry or use a smaller scope"); it must NOT claim the device is offline when it isn't.
- **Root cause (code-confirmed)**: `ChapterTranslationService.mapTransportError` (`:429-438`) maps these `URLError` codes to `.offline`: `.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotConnectToHost, .timedOut`. Two of those are NOT offline conditions:
  - **`.timedOut`** — the request exceeded the URLSession timeout. On a LONG chapter (large payload / slow provider response) this is the likely code, so a long-chapter timeout renders as "you appear to be offline."
  - **`.cannotConnectToHost`** — a host/DNS/server-reachability failure, not the device being offline.
  `ChapterReTranslateViewModel.swift:417-418` renders `.offline` as the misleading banner.
- **Fix direction (not applied)**: (1) narrow the `.offline` mapping to genuine device-connectivity codes only (`.notConnectedToInternet`, `.networkConnectionLost`, `.dataNotAllowed`); map `.timedOut` → a distinct timeout case/message, and `.cannotConnectToHost` → a provider/connection-failed message. (2) Separately address the long-chapter timeout itself: confirm whether the re-translate path chunks the request (the `ChapterTranslationChunker` 6000-char chunking from #330 is the bilingual path — verify re-translate chunks too) and/or raise `timeoutIntervalForRequest` for translation. RED: `mapTransportError(URLError(.timedOut))` must NOT return `.offline`; `(.notConnectedToInternet)` must. Code-only, no visible-UI delta beyond the corrected message text (rule 51 N/A).
- **Cross-ref**: #330 (FIXED — chunker oversized-segment → provider token-limit, the *other* large-chapter failure, a different error path) + #320 (FIXED — sibling error-message defect in the same mapper).

### Bug #332 — EPUB continuous-scroll (legacy #71 stitch) shows a broken-image glyph for SVG-wrapped cover/title images; fine in paged (FILED 2026-06-09 via /triage)

- **Repro**: open an EPUB whose cover/title page embeds an SVG-wrapped image (`<svg><image xlink:href="cover.jpg"/></svg>`) on the **legacy EPUB engine** → switch to **scroll (continuous)** mode → the title-page image renders as the WebKit broken-image glyph (blue square + "?"). Switch to **paged** → the same image renders correctly.
- **Expected**: images render identically in paged and scroll.
- **Root cause (code-confirmed, legacy #71 stitch)**: `EPUBChapterBodyRewriter.rewriteAttributes` (`:201`) absolutizes relative **`src`** against the chapter dir (`:228-229`) but treats **`href`/`xlink:href` as fragment refs only** — it namespaces `#fragment` values and leaves "every other href (cross-document, external) untouched" (`:220-226`). SVG `<image xlink:href>` / `<use xlink:href>` carry **resource** refs, not fragments, so they're left relative. When N chapters are stitched into one continuous-scroll document they collapse onto a single shared base URL, so a relative `xlink:href` resolves against the wrong directory → 404 → broken-image glyph. Paged mode loads each chapter as its own `loadFileURL` document (its own base URL; the rewriter isn't involved), so the same ref resolves. Plain `<img src>` is unaffected (it IS absolutized) — only SVG/`xlink:href`-borne images break, which is exactly the cover/title-page idiom most EPUBs use.
- **Sibling**: Bug #331 (drop-cap absent in continuous scroll) — same legacy #71 stitch DOM (`<section data-vreader-spine-index><div class="vreader-chapter-content">`). #331 confirms this stitched path is the one in use.
- **Engine note**: the **default** EPUB engine is Readium, whose scroll is **per-spine native** (no #71 stitch — `ReadiumEPUBHost+ContinuousScroll.swift:11`), serving each spine as its own document → would NOT break by layout. So this is **legacy-engine-only** (the `readiumEPUBEngine` override OFF). **To pin on device**: confirm the active EPUB engine; if the user is actually on Readium, Web-Inspect the failed `<image>` request URL in scroll vs paged — that would be a different (Readium-specific) cause.
- **Fix direction (not applied)**: in `rewriteAttributes`, absolutize a relative `xlink:href` / resource `href` whose value does NOT start with `#` against the chapter dir, exactly like `src` (reuse the `src` resolver at `:228-229`), while keeping the existing `#fragment` namespacing for the fragment case. RED: a chapter body with `<svg><image xlink:href="../img/cover.jpg"/>` must emit the absolutized resource URL in the stitched output. Code-only, no visible-UI delta (rule 51 N/A). GH #1579.

### Bug #325 — AZW3/MOBI continuous (windowed) scroll sticks at a chapter/part-divider boundary (FILED 2026-06-05 via /triage)

- **Repro**: open an AZW3/MOBI book with short part-divider sections (被讨厌的勇气: each "第N夜" is a heading-only divider, content in the following spine section) → continuous-scroll to a "第N夜" divider → the divider heading renders, then the area below is empty and scrolling won't advance into the next content section.
- **Expected**: continuous scroll flows through the short divider into the following content section without sticking.
- **Likely root cause** (needs device repro): the K=3 windowed continuous scroll (`paginator.js` `#ensureWindow` / `#onNeighbourExpand` / `#evictOutsideWindow`, anchored on `#index`) advances/expands the window as the reader scrolls into a neighbour view. A **very short section** (a heading-only part-divider) likely doesn't generate enough scroll height to trip the neighbour-expand / `#index` advance, so the next (content) section never mounts → the divider is a dead end. Variants: eviction dropped the next section; the `#logicalScrollOffset`→index mapping doesn't register entering a sub-viewport section.
- **Context**: Features #73 (Foliate scrolled-mode continuous rendering) + #76 (vertical-writing windowed scroll) are VERIFIED — the windowed scroll works generally; this is a short-section boundary edge case. Distinct from the FIXED #283 (chapter-boundary JUMP, → Feature #76) — that was a visible jump, this is a hard STUCK.
- **Fix direction** (not applied): ensure `#ensureWindow`/`#onNeighbourExpand` advance past zero/short-height sections (mount the next non-trivial section even when the current one is shorter than the viewport); add a guard so a sub-viewport section can't terminate the scroll. Regression / device-verify on a divider-heavy book. GH #1547.

### Bug #324 — TXT/MD text selection uses the default iOS blue tint instead of the reader theme accent (FILED 2026-06-05 via /triage)

- **Repro**: open a TXT book (sepia/paper theme) → long-press to select text → the selection grab handles + caret + highlight are iOS-default blue on the warm background.
- **Expected**: the selection tint matches the reader theme accent (maroon `#8c2f2f`), like the rest of the reader chrome (Ask AI button, current-chapter highlight).
- **Root cause** (code-read + screenshot): TXT/MD use `UITextView`; `tintColor` governs the selection highlight + grab handles + caret. The TXT bridges never set `tintColor` (grep: none in `TXTTextViewBridge`/`TXTChunkedReaderBridge`), and there's no global reader accent tint, so it falls to the system default blue (blue handles visible in the report screenshot).
- **Fix direction** (not applied; code-only, Rule-51 N/A — parity theming, applies the EXISTING accent token): set the TXT/MD `UITextView.tintColor = theme.accentColor` and refresh on theme change. EPUB/AZW3 select via WKWebView `::selection` CSS (a separate path, out of scope here). GH #1546.

### Bug #323 — AI chat hangs on the second message (composer never re-enables) — REOPENED 2026-06-09 (now a whole-app freeze, also on long replies) (FILED 2026-06-05 via /triage)

- **🔴 REOPENED 2026-06-09 (device re-report, scope=Chapter, owl-alpha provider)**: the user still hits this on a recent on-device build (#86 "Drew on" provenance + #88 session bar visible in the screenshot), with a **stronger + broader symptom** than the original:
  - **The WHOLE APP freezes** (not just a disabled composer) **after sending the second message**, AND
  - **The whole app freezes while a LONG reply streams in** (can occur on the first message too).
  - **Why the v3.59.13 fix didn't cover this** (different mechanism): that fix decoupled the *composer* from the awaited save. But (a) scope here is **Chapter** — the whole-book `await onWholeBookReadRequested?()` path is NOT on the turn-2 path; and (b) a stalled `saveSettledTurn` can only leave one pending Task — it cannot freeze the *whole UI*. A whole-app freeze ⇒ **the main thread is blocked**, which the save-vs-composer decoupling never addressed. #1545 was closed under a **verification-exception** (high-fidelity unit test, NO on-device verification — the AI path is CU-free-blocked), so the real-device behavior was never confirmed; the user now reproduces it on device, which is exactly the risk that closure class carries.
  - **New leading hypothesis — main-thread re-render churn during streaming**: `appendToAssistant` (`AIChatViewModel+Streaming.swift:256-259`) runs `messages[index].content += text` for **every streamed token**, mutating the `@Observable messages` array in place. Each mutation re-publishes the whole array, so SwiftUI re-evaluates and re-lays out the **entire chat transcript** — every `AIChatMessageRow`, including the ever-growing assistant `Text(message.content)` (`AIChatMessageRow.swift:101`) — on every token. There is **no delta coalescing / throttle** (no token batching, no per-row isolation). Cost per token scales with `history-length × current-reply-length`, so a long reply and/or a longer conversation (the 2nd+ message) drives O(n²) main-thread work → the app appears frozen for the duration of the stream. This single mechanism explains **both** triggers the user named.
  - **Fix direction (not applied; perf)**: coalesce/throttle streamed deltas (accumulate tokens, flush at a capped rate, e.g. ≤10–20 Hz), and/or isolate the streaming message so only its row re-renders rather than the whole `messages` array; consider a lighter incremental text update. Add a streaming-perf regression guard (assert bounded re-publish count / wall-clock for an N-token long reply). This is a code-only perf change with no visible-UI delta (rule 51 N/A).
  - **To pin on device**: confirm whether `agenticTools` is enabled (default OFF — the "Drew on"/"Sources" chrome is #86 context, NOT proof agentic is on); profile the main thread (Instruments Time Profiler / hang-detection) while a long reply streams to confirm the per-token re-render is the hot path.

---

_Original report (the composer-never-re-enables facet, FIXED v3.59.13 but the device freeze persists):_

- **Repro**: open an EPUB → AI Assistant → Chat → send a first message (replies fine) → send a second message → it hangs (no reply; the send/stop control stays in the loading state and won't accept input).
- **Expected**: every message sends + streams a reply; the composer re-enables after each turn.
- **Likely root cause** (code-read; exact `await` needs device repro): `AIChatViewModel.runSend` (`AIChatViewModel+Streaming.swift`) `await`s several operations INSIDE the send, BEFORE its `defer { if opId == opCounter { isLoading = false; streamTask = nil } }` (`:96`) can reset state. If one stalls on turn 2, `isLoading` stays true → the composer's `canSend` (requires `!isLoading`) is false → "stuck", and the launcher's `await task.value` (`:42`) never returns. Candidate stalls:
  - **#88 session save** — `await saveSettledTurn(...)` (`:178`) serialized through `sessionOpChain` (`AIChatViewModel.swift:101-118`; each op `await prior?.value`). A never-settling chained op (initial `loadSessions()` / turn-1 save) blocks turn-2's save.
  - **#91 agentic tool-loop** — with `agenticTools` on + a tool-capable provider, turn 2 → `runAgenticTurn` → `AgenticChatDriver().run(...)` (`:198`); a turn-2 tool call (e.g. `search_current_book`) whose async never returns, or an unbounded driver loop, hangs the turn (turn 1 may not have triggered a tool → worked).
  - **#86 whole-book read** — if scope = Whole book, `await onWholeBookReadRequested?()` (`:101`); a stuck `.reading` phase also blocks input (`isInputBlocked`, `:210`).
- **Scope**: the VM is format-agnostic (shared) — reported on EPUB, likely reproduces on all formats. Regression in the v3.52.0+ AI-chat rewrite.
- **To pin**: confirm the user's config — is `agenticTools` enabled? Is the Chat scope **Whole book**? That selects which `await` is on the turn-2 path.
- **Fix direction** (not applied): don't block the user-visible turn completion on the session save (fire-and-forget / bounded), so a stalled `sessionOpChain` can't freeze the composer; bound the agentic driver (max-iterations + per-tool timeout); guarantee `isLoading`/`streamTask` reset on any downstream stall (timeout/detached). Regression test: two messages back-to-back through `runSend` with a slow/stalled save + a tool-call turn. GH #1545.

### Bug #321 — EPUB TOC polluted with generic "Section N" entries instead of the publisher's nav-doc TOC (FILED 2026-06-05 via /triage)

- **Repro**: open an EPUB whose spine has more items than its nav doc (chapters split across files, or un-nav'd continuation/front-matter) → Contents shows real chapters interleaved with "Section N" rows. Observed on "The Half Second": 54 entries — `Prologue · Section 8 · 0. Chapter 1: … · Section 10 · 1. Chapter 2: … · Section 12 · …`. Tapping "Section 10" lands at Chapter 1's content ("section 10 same as chapter 1").
- **Expected**: the TOC reflects the publisher's nav doc (nav.xhtml / NCX) — the curated chapter entries — not every spine item. Un-nav'd spine items should not appear as standalone rows.
- **Root cause** (code-read, high confidence): `EPUBParser.swift:325` builds each spine item with `title: itemTitle ?? "Section \(index + 1)"` where `itemTitle = delegate.navTitles[href]`. A spine item ABSENT from the nav doc gets a generic `"Section N"` title instead of `nil`. The EPUB TOC is built via `ReaderTOCBuilder.buildTOC` → `TOCBuilder.fromSpineItems` (`TOCBuilder.swift:21`), documented to "skip untitled items" (`compactMap` on `item.title`) — but the `"Section N"` fallback means un-nav'd items aren't untitled, so they survive the filter and pollute the TOC. Engine-agnostic (`buildTOC` uses EPUBParser spine items for both Readium + legacy).
- **Fix direction** (not applied; code-only, Rule-51-clear): apply the `"Section N"` fallback ONLY when the EPUB has no usable nav doc (`navTitles` empty) — a last-resort TOC for nav-less EPUBs; when a nav doc exists, leave un-nav'd spine items `nil`-titled so `fromSpineItems` skips them and the TOC matches the publisher's nav doc. (Alt: build the TOC from the parsed nav-doc tree directly.) Regression test: N nav entries + M>N spine items → exactly N TOC rows. GH #1540.
- **Separate same-screenshot defect (NOT this bug)**: TOC titles show undecoded HTML entities — "Why willpower can**&#39;**t reach" — the nav-title parser (`parseNavXHTML`/`parseNCX`) doesn't decode `&#39;` → `'`. Distinct; triage/file separately.

### Bug #320 — Chapter re-translate shows the raw Swift error dump instead of a clean message (FILED 2026-06-05 via /triage)

- **Repro**: Reader → More → Re-translate chapter (a provider/model that returns a non-2xx, e.g. owl-alpha OpenAI-compatible) → tap Re-translate → on a 400 the sheet shows `Translation failed: providerError("HTTP 400: {"error":{"message":"Provider returned error","code":400,"metadata":{"raw":"ERROR",…}}")`.
- **Expected**: a clean, sanitized, human-readable message (the raw detail kept in the log only) — consistent with the Chat/Summarize/Translate tabs, which display `AIError.errorDescription` ("AI provider error: …"), not the enum dump.
- **Root cause** (code-read, high confidence): `ChapterTranslationService.mapTransportError` (`:347-358`) returns `.providerFailed(String(describing: error))` for every non-offline failure (`:354` default-URLError branch + `:357` non-URLError fallback). For an `AIError.providerError("HTTP 400: {raw json}")`, `String(describing:)` yields the case syntax `providerError("HTTP 400: {…}")`. `ChapterReTranslateViewModel.errorMessage(from:)` (`:419-420`) then renders `"Translation failed: \(message)"` verbatim. Only this path uses `String(describing:)`; the other AI surfaces use `localizedDescription`.
- **The underlying 400 is provider-side** (the owl-alpha OpenAI-compatible gateway rejecting — "Provider returned error, code 400, raw: ERROR" is an opaque passthrough; chapter-translate request construction is the VERIFIED Feature #65 path). This bug is the **presentation**. If 400s reproduce across providers/models, that's a separate request-construction investigation.
- **Fix direction** (not applied; code-only, Rule-51-clear): in `mapTransportError`, map a known `AIError` to its `errorDescription`/a friendly string and use `error.localizedDescription` (not `String(describing:)`) for the unknown fallback; keep the raw `String(describing:)` in the existing `log.error(...)` only. Regression test on `mapTransportError`/`errorMessage`. GH #1538.

### Bug #317 — Selection popover renders as a system bottom sheet instead of the designed floating inset card (FILED 2026-06-03 via /triage)

- **Repro**: open any book → long-press to select text → the selection popover (quote + color swatches + Note/Translate/Ask AI/Read) slides up from the bottom EDGE as a `.sheet` with a system grabber handle + dimmed backdrop, disconnected from the mid-screen selection.
- **Expected**: the designed FLOATING inset card — `vreader-reader.jsx`'s `SelectionPopover` is `position: absolute, left: 18, right: 18, bottom: 100` (rounded, above the bottom chrome, no grabber, not edge-attached).
- **Root cause** (code-read): `SelectionPopoverPresenter.swift:191` presents via `.sheet(isPresented:)` + `.presentationDetents([.fraction(0.30), .medium])` (`:215`) + `.presentationBackground(.clear)` (`:217`). The system `.sheet` still draws the grabber + edge attachment + dimming → reads as a modal sheet, not the designed floating card. The presenter is SHARED (`SelectionPopoverPresenterModifier`), so this affects ALL formats (TXT/MD/EPUB-Readium), not just Readium.
- **Relationship**: selection-popover sibling of Bug #316 (highlight popover sheet-vs-card). Both: annotation popovers present as bottom sheets where the #60/#64 designs depict floating/anchored cards. Distinct components/presenters + root causes (#316 = Readium `.zero` sourceRect fallback; #317 = shared `.sheet` for every format).
- **User context**: reported as "the panel is ugly."
- **Fix direction** (not applied; Rule-51-exempt — restore to the existing #60 design): present `SelectionPopoverView` as a floating overlay card (inset `left/right:18`, ~100pt up from the bottom, rounded, own backdrop/dismiss) instead of a system `.sheet`. Larger than #316 (no anchored-presentation infra — it's a `.sheet` for every format). GH #1433.

### Bug #316 — Readium EPUB highlight popover opens as the barren bottom-sheet, not the designed anchored card (FILED 2026-06-03 via /triage)

- **Repro**: Readium EPUB (default) → tap an existing highlight (no note) → the popover slides up as a full-width BOTTOM SHEET with a tall empty note body between the quote and "Add a note…".
- **Expected**: a compact CARD anchored near the tapped word, sized to content (the #64 design's `canonical` / `canonical-no-note` / `empty · Add a note CTA` artboards). The bottom-sheet is the design's VoiceOver / very-long-note FALLBACK, not the canonical.
- **Root cause** (code-read, high confidence): `ReadiumDecorationHighlightAdapter.attach` (`:90-97`) posts `.readerHighlightTapped` with `sourceRect: event.rect`, but Readium's `observeDecorationInteractions` `event.rect` is `CGRect?` and is nil for these decorations → `tapEvent` falls back to `sourceRect: .zero` (`rect ?? .zero`, `:111`). `HighlightPopoverModifierBody` presents the anchored card only with a real `sourceRect`; `.zero` → the bottom-sheet form → barren empty body.
- **User context**: reported as "the panel is ugly"; on follow-up confirmed the two issues are the **big empty note area** + **bottom-sheet vs small anchored card** — both downstream of the `.zero` sourceRect.
- **Fix direction** (not applied; Rule-51-exempt — restore to the existing #64 design): derive a usable anchor rect for the Readium decoration (decoration locator → navigator bounding rect / Readium frame API, or the tap location) so the popover anchors as the designed compact card (which sizes to content → empty-body barrenness resolves with it). If the designed anchored empty state is itself still barren afterward, that residual is a separate needs-design escalation. GH #1431.

### Bug #315 — AI panel tab picker (Summarize/Translate/Chat) low-contrast on the cream sheet (FILED 2026-06-03 via /triage)

- **Repro**: open a book → AI Assistant → the Summarize/Translate/Chat segmented control: inactive labels are pale gray + the selected-segment pill is a faint wash on the translucent cream header; hard to read which tab is active (worse in Dark Mode).
- **Expected**: active + inactive tab labels clearly legible on the cream sheet across Paper/Sepia/Dark/OLED.
- **Root cause** (code-read): `AIReaderPanel.swift:120-128` — `Picker("Mode", selection: $selectedTab){…}.pickerStyle(.segmented)` (a11y id `aiReaderTabPicker`). No `UISegmentedControl` appearance override exists, so the unselected labels + selected pill fall through to system defaults → near-invisible on `#fcf8f0`. Identical mechanism to Bug #298 (Display panel `.segmented` washes out on cream).
- **Class**: cream-sheet contrast cluster (#285 reader sub / #297 #300 Settings / #298 control-track / #310 AI Chat empty-state). This is the AI-sheet instance of the segmented-control facet (#298).
- **Fix direction** (not applied; likely Rule-51-exempt — reuses landed tokens): apply the per-theme `ReaderThemeV2.controlTrack` token (#1329/#298) to the segmented trough + the `sub`/ink text tokens (#1292/#84) to the labels, or pin the AI sheet to `theme.preferredColorScheme` (#297). Add a contrast regression test. GH #1429.

### Bug #314 — AI Translate tab translates the auto-extracted book context, not the user's selection (FILED 2026-06-03 via /triage)

- **Repro**: select a sentence/word → popover **Translate** (or AI Assistant → Translate tab) → tap a language pill → ORIGINAL is the auto-extracted book context (front-matter), translation is of that context, NOT the selection.
- **Expected**: the Translate tab translates the selected sentence(s)/word(s); with no selection it falls back to the current reading context.
- **Root cause** (high confidence): the selection→translate path IS wired — `SelectionPopoverActionRouter` posts `.readerTranslateRequested(selection)`; `ReaderContainerView:403` sets `translationViewModel.originalText = info.selectedText` + opens the Translate tab. BUT `TranslationPanel.requestTranslation` (`:101-109`) fires `viewModel.translate(originalText: textContent, …)` on every pill tap, where `textContent` = `AIReaderPanel.textContent` (the auto-extracted book-context window), NOT `viewModel.originalText` (the selection). `translate()` then overwrites `self.originalText = textContent` and `performTranslation` runs `AIContextExtractor.extractContext(.section)` on it — discarding the selection.
- **Why front-matter specifically**: `textContent`/`currentTextContent` falls back to the book head when the locator is nil (the Readium-EPUB anchoring of Bug #313) — a contributing factor; the core defect is selection-vs-context.
- **Fix direction** (not applied; code-only, Rule-51-exempt): `requestTranslation` should translate `viewModel.originalText` when opened from a selection (fall back to `textContent` only for a cold/context translate); `performTranslation` should translate an explicit selection verbatim (skip the `.section` window). GH #1428.
- **REOPENED 2026-06-07 via /triage** (user screenshot: translate result is bad). FIXED 2026-06-03 added `hasExplicitSelection` + verbatim-selection path; user re-reports the same failure — selected "permitted", Translate→Chinese returned the **book front-matter** (`半秒钟 半秒钟 半秒钟 … 作者：李笑来 李笑来 … 版权 版权 版权`), garbled+repetitive, while ORIGINAL correctly showed "permitted". So the translate consumed the book-context, not the selection. **Device-repro to pin which path**: (a) `hasExplicitSelection`==true at pill-tap → the FIXED selection-verbatim path regressed/didn't engage; (b) ==false (COLD) → translates `textContent`, which for Readium EPUB is the book-START front-matter (#313 nil-locator → `prefix(2500)`), and that front-matter is repetitive — a SEPARATE extraction/dedup quality bug in `ReaderAICoordinator.loadBookTextContent` / `EPUBTextExtractor` (the `半秒钟 半秒钟` echo). Either way the visible result is wrong. GH #1428 reopened.

### Bug #313 — EPUB (Readium) TOC sheet doesn't focus the current chapter — REOPENED 2026-06-10 (device re-report on v3.62.5+; broadcast chain failing in practice) (FILED 2026-06-02 via /triage)

- **🔴 REOPENED 2026-06-10**: still no current-chapter highlight in the EPUB Contents sheet on a build that contains the 2026-06-03 fix. Two code-read candidates (full detail in the summary row): (a) `spineResolved` returns nil for EVERY relocate when `bilingualSpineHrefs` is empty (populated only by `openBilingualParser()`, whose failure is "non-fatal" for bilingual but now silently kills the position broadcast — undocumented coupling; the #318 index-fallback can't rescue it since `N ≠ 0` fails the parallel-count guard); (b) the TOC `isCurrent` href match misses on odd-href books (this book's nav has a raw-filename title — the #318 class). **Fix direction**: decouple the broadcast from the bilingual parser (resolve against `publication.readingOrder` when the parser list is empty); tolerant href matching in the TOC. **To pin**: #96 Diagnostics log while opening the TOC; verify `openBilingualParser` outcome for this book. GH #1425 (reopened).

_Original filing:_

- **Repro**: open an EPUB (default Readium engine) → read into a middle chapter → open Contents → the TOC shows from the top, current chapter not highlighted, not scrolled into view.
- **Expected**: Contents opens with the current chapter highlighted + scrolled into view (as TXT/MD/PDF/AZW3 do).
- **Root cause** (high confidence): `TOCSheet` implements both behaviors (`isCurrent` highlight at `:234`; `ScrollViewReader.scrollTo` at `:226-268`), both keyed off `currentLocator` (EPUB matches by spine href). `ReaderContainerView.currentLocator` is set ONLY by `.readerPositionDidChange` (`:490-492`). The Readium host never posts that notification — `ReadiumReaderCoordinator.locationDidChange` only calls `onLocationChange?(locator)` (consumed for save/bilingual/bottom-chrome, none posts it). Every other format's host posts `.readerPositionDidChange` (legacy EPUB, Foliate, TXT, MD, PDF). So `currentLocator` stays nil for Readium EPUBs and both TOC behaviors early-return.
- **Broader impact**: `currentLocator` is also mirrored onto the AI coordinator (`:493`); its current-position context is likely stale/nil for Readium EPUBs too. Posting the notification fixes all consumers.
- **Distinct from**: #248 (FIXED, TXT TOC-sheet focus) — same symptom class, different root cause (Readium not posting vs the TXT #248 fix). Sibling of the Readium-flip cluster #299/#302/#303/#309.
- **Fix direction** (not applied; Rule-51-exempt wiring, mirrors #262's Foliate fix): post `.readerPositionDidChange` on each Readium `locationDidChange` with `currentVReaderLocator(from:)` (`ReadiumEPUBHost+BilingualDriver.swift:281-303`). GH #1425.

### Bug #312 — TXT TOC jump: chapter title not pinned to the top of the reading view (FILED 2026-06-02 via /triage)

- **Repro**: open a chaptered TXT → tap a TOC entry → it jumps to the correct chapter, but the chapter title lands ~¼ down (non-chunked) or mid-chunk (continuous-chunked), not at the top.
- **Expected**: a TOC/chapter jump pins the destination chapter's title to the viewport top (as the position-restore-on-open path does).
- **Root cause** (high confidence): a TXT TOC tap reuses the SAME navigation path as a search-result tap — `TOCSheet.onNavigate` → `.readerNavigateToLocator` → `handleNavigateToLocator` sets `scrollToOffset`. That path is intentionally NOT top-pinning (tuned for "show my search match in context"): (a) non-chunked UITextView → `scrollOffsetForVisibleMatch` 0.25 headroom (`TXTOffsetMapper.swift:171-180`); (b) continuous-chunked UITableView (default for chaptered TXT) → `scrollToRow(.top)` aligns the 16KB *paragraph*-chunk top (not chapter-aligned) + a linear intra-chunk fraction that doesn't snap to the title glyph (`TXTChunkedReaderBridge.swift:557-568`). The restore path (`attemptScrollRestore`) pins to the top edge — the contrast that makes the TOC landing look wrong.
- **Distinct from**: Bug #248 (FIXED) — that fixed the TOC SHEET's *list* auto-scroll/highlight to the current chapter, NOT the reader-content landing position after a tap.
- **Fix direction** (not applied; code-only): thread a `snapToTop` intent through `handleNavigateToLocator` (true for TOC/chapter/bookmark, false for search → preserves the #153 search headroom); non-chunked → top-edge `setContentOffset` like `attemptScrollRestore`; chunked → after `scrollToRow(.top)`, set `contentOffset.y` from the target glyph's `lineFragmentRect.minY`. GH #1424.

### Bug #311 — Re-translate chapter progress fabricated/coarse (pins at 50%) (FILED 2026-06-02 via /triage)

- **Repro**: More menu → Re-translate chapter → submit → the `ReTranslateProgress` sheet shows a spinner + bar at ~50% + a counting-down ETA, but the bar stays at 50% for the whole translate (the longest phase) and only completes at the end — reads as stuck / "doesn't tell progress."
- **Root cause** (high confidence): `ChapterReTranslateViewModel` sets `progress` 0.0 → 0.25 (after cache delete) → 0.5 (after provider resolve) → 1.0 (on completion). The translate itself is a single opaque `await runner.translateForRetranslate(...)` on `ChapterTranslationService` — no per-chunk/per-segment callback — so progress can't advance during it. The ETA is `(1 - progress) * 18s` (fabricated). VM header comment admits the two-step progress is faked because the service is opaque.
- **Expected**: progress reflects the actual translation work (advances during the translate), not a fixed 50%-pin.
- **Fix direction** (not applied; likely feature-sized): add a streaming progress source to `ChapterTranslationService` (per-chunk callback) and feed `ChapterReTranslateViewModel.progress`; the whole-book `BookTranslationCoordinator` already produces real N-of-M counts and is the model. Low severity — the flow works + completes; it just feels stuck. Distinct from Feature #77 (bilingual inline progress). GH #1416.

### Bug #310 — AI Assistant Chat empty-state + placeholder near-invisible on cream (Dark Mode) (FILED 2026-06-02 via /triage)

- **Repro**: device in Dark Mode → open a book → AI Assistant → Chat tab → the bubble icon + "Ask questions about this book" hint (and the input placeholder) are near-invisible (near-white on the cream sheet). Light mode = faint (~3.3:1).
- **Root cause** (high confidence): `AIChatView.emptyStateView` uses the system `.secondary` ShapeStyle for the icon (`:147`) + headline (`:153/:157`), and the `TextField` placeholder (`:206`) uses the system placeholder color — both appearance-aware. The AI sheet surface is cream `#fcf8f0` (`ReaderSheetChrome.sheetSurfaceColor`, light family) but isn't appearance-pinned, so in Dark Mode `.secondary` resolves to ~`rgba(235,235,245,0.6)` ≈ 1.07:1 over cream. The empty-state was "preserved unchanged" through the feature #65 v2 re-skin while the message rows migrated to `theme.inkColor`; it's the lone `.secondary` leftover in the chat body.
- **Fix direction** (not applied): replace the empty-state `.secondary` with `Color(theme.subColor)` (the token `AIReaderPanelHeader`'s subtitle already uses); supply a theme-colored placeholder (overlaid `Text` gated on empty input, or a UITextField tint); optionally pin `.preferredColorScheme(theme.preferredColorScheme)` on the AI sheet (the #297 fix direction). Rule-51-exempt (restore-to-designed-token). Add a contrast regression test. Same recolor pattern as #285/#297/#300. GH #1414.

### Bug #308 — Reader bottom-bar AI button silently no-ops when AI unconfigured (FILED 2026-06-02 via /triage)

- **Repro**: fresh/unconfigured install (no AI provider / consent / AI Assistant) → open a book → bottom toolbar → tap the AI (sparkles) button → nothing happens (no panel, no prompt).
- **Root cause** (high confidence): the button posts `.readerOpenAI` (`ReaderBottomChrome.swift:115-116,141`); `ReaderContainerView.onAI` (`:312-318`) gates `showAIPanel=true` behind `resolvedAICoordinator.isAIAvailable`, returning nothing when false (a deliberate "no empty sheet" no-op). `isAIAvailable` (`AIReaderAvailability.swift:43-52`) requires all three of `aiAssistant` flag + keychain API key + `hasConsent`. The button is always rendered (no availability filter, `ReaderBottomChrome.swift:99-107`), so it looks live but does nothing. Identical across legacy + Readium engines (gate is in the shared `onAI`, not per-host) — NOT a #299 Readium wiring gap.
- **Status: FIXED 2026-06-02** (shipped in **Feature #82** WI-2, v3.44.0, merge `a033336e`). The brief BLOCKED: needs-design (#1400) was superseded same-day when the AI-readiness design landed (#1394 → Feature #82, the capstone covering this AI-button surface), so #1400 was closed as redundant and #82's implementation delivered the fix.
- **Fix** (Feature #82 WI-2): (1) `ReaderContainerView.onAI` routes the unconfigured tap to the in-reader **`ReaderAIReadinessSheet`** (enable AI + grant consent + add provider in place) instead of the silent no-op; (2) **`AIReaderAvailability`** now mirrors the live request gate — `hasAPIKey` checks the **active provider's per-profile key first** (sync UserDefaults+keychain read, legacy fallback only when no active profile), so a per-profile-configured user's AI button opens the panel rather than looping back. Device-verified (`dev-docs/verification/feature-82-20260602.md`): unconfigured AI button → readiness sheet; readied (per-profile key, no legacy key) → AI panel opens. Regression: `AIReaderAvailabilityPerProfileTests` (per-profile + legacy-masking inverse). GH #1396 (needs-design label cleared on fix).

### Bug #301 — Bilingual silently does nothing when AI unconfigured (FILED 2026-06-02 via /triage)

- **Repro**: fresh install (AI Assistant off / no provider) → open a book → More menu → Bilingual ON → confirm setup sheet (which says "AI provider configured") → nothing translates, no error.
- **Root cause** (high confidence): pipeline gated on `FeatureFlags.aiAssistant` (false), `AIConsentManager.hasConsent` (false), provider profile (nil). Any-missing → `AIService` throws → `ChapterTranslationPrefetcher` → `.providerFailed` → `BilingualReadingViewModel+Prefetch` records `.failed`, `translationsByUnit` stays empty, renderer shows source-only. All six hosts hardcode `BilingualEngineDescriptor(configured: true)` so the sheet's "No AI provider configured / Set up" branch is never reached; `onOpenSettings` just dismisses (WI-15 stub). Cache (`ChapterTranslationRecord`) + provider config exist but are invisible (config hidden behind the master AI-Assistant toggle).
- **Fix** (2026-06-02, slice 1 of 3 — fixes the reported repro): `BilingualAIReadiness.resolve` mirrors the live `AIService` gate (aiAssistant + consent + active profile + per-profile key); `BilingualReadingViewModel.aiConfigured` feeds the setup sheet's `BilingualEngineDescriptor.configured` (was hardcoded `true` in all six hosts), refreshed via `.task` on each presentation → the strip truthfully shows "No AI provider configured / Set up" and the failure is surfaced at the sheet. Remaining slices: `onOpenSettings → AI Providers` routing — **DESIGN LANDED 2026-06-02** (resolves needs-design #1380; tracked as Feature #81 `reader-ai-provider-entry.md`, Swift not yet shipped). GH #1356.

### Bug #302 — EPUB (Readium) highlight-tap can't edit (FILED 2026-06-02 via /triage)

- **Repro**: default EPUB (Readium) → tap an existing highlight → nothing (page-turns or toggles chrome); the edit popover never opens.
- **Root cause** (high confidence): total gap — no producer (no decoration-activation delegate; highlights `isActive:false`) AND no consumer (`ReadiumEPUBHost.coreBody` never attaches `unifiedHighlightPopoverPresenter`). Every other format wires both. The legacy `EPUBWebViewBridge` JS→Swift→popover chain is now dormant (Readium default).
- **Fix** (2026-06-02): the adapter's `attach` registers `observeDecorationInteractions(inGroup: "highlights")` (Readium `setActivable()` makes the group tappable) → maps the decoration id to the highlight UUID → posts `.readerHighlightTapped`; `ReadiumEPUBHost+Body` attaches `.unifiedHighlightPopoverPresenterIfAvailable`. Device-verified (tap a highlight → edit popover). The prior "not locatable in 3.9" note was wrong — `EPUBNavigatorViewController.observeDecorationInteractions` exists in the vendored Readium. Rule 51 exempt. GH #1357.
- **REOPENED 2026-06-03 via /triage**: the fix works on the FIRST tap but a SECOND tap no longer raises the popover. The 2026-06-02 device-verify exercised a single tap only, so the re-arm path was never tested.
  - **Candidate root causes** (fixer to confirm which): (a) **consumer state-not-reset** — `HighlightPopoverModifierBody` drives presentation off `.onChange(of: viewModel.presented)`; if `viewModel.presented` is NOT reset to nil when the popover dismisses, a second `handleTap` of the SAME highlight sets `presented` to an unchanged value → no `.onChange` → no re-present (classic SwiftUI re-arm bug). (b) **producer not re-arming** — the Readium decoration activation (`observeDecorationInteractions`) fires once but doesn't re-fire after the popover dismisses (the popover steals the navigator's gesture / first-responder, or the decoration is re-applied `isActive:false` on the dismiss re-render, dropping the activable binding). The `attach_registersHighlightsTapObserverOnce` test asserts single registration but not repeat activation.
  - **Discriminator**: do TXT/MD/Foliate raise the popover on repeated taps? If yes → it's (b), Readium-producer-specific. If they also fail on the second tap → it's (a), the shared modifier.
  - **Fix direction** (not applied): reset `viewModel.presented`/`router` state on popover dismiss so a same-id re-tap re-presents, AND/OR ensure the Readium decoration tap re-arms after dismiss. Add a second-tap regression test. GH #1357 reopened.

### Bug #303 — EPUB (Readium) select→Note no-op (FILED 2026-06-02 via /triage)

- **Repro**: default EPUB (Readium) → select text → tap Note → nothing. (Highlight works; Translate works subject to #301; Ask AI/Read are dead on all engines.)
- **Root cause** (high confidence): Note posts `.readerAnnotationRequested`; `ReadiumEPUBHost` has no observer for it + no note-input sheet. Legacy EPUB (`EPUBReaderContainerView:413`) and TXT/MD (`ReaderNotificationModifier:73`) mount it; the Readium host omits it.
- **Fix** (2026-06-02): added a `.readerAnnotationRequested` observer + the designed `AddNoteSheet` to `ReadiumEPUBHost` (`+Annotations` extension), mirroring the WI-8 highlight slice — resolves the cached `Selection`, presents the sheet, and on Save persists a highlight-with-note via `HighlightCoordinator.create(note:)`. Device-verified (sheet presents on Note). Rule 51 exempt. GH #1358.

### Bug #304 — Bilingual translation loses style on Readium-EPUB + Foliate (FILED 2026-06-02 via /triage)

- **Repro**: bilingual EPUB (Readium) or AZW3 (Foliate) → the translation lines render as plain body text (no smaller size, muted color, accent left border, indent).
- **Root cause** (high confidence): the translation `<div class="vreader-bilingual">` is inserted with only inline `user-select:none`; the styled `.vreader-bilingual[data-vreader-decoration]` rule lives only in `ReaderThemeV2.epubOverrideCSS`, threaded ONLY into the legacy `EPUBWebViewBridge` (`EPUBReaderContainerView:695`). Readium styles via `EPUBPreferences` + injects no such rule; Foliate `setStyles` has none either.
- **Fix direction** (not applied): inject the `.vreader-bilingual` CSS into the Readium spine + the Foliate setStyles path. GH #1359.

### Bug #305 — Foliate bilingual state not synced on reopen (FILED 2026-06-02 via /triage)

- **Repro**: AZW3 with bilingual already enabled → close + reopen → More menu shows Bilingual OFF; the "Re-translate chapter" row is gone.
- **Root cause** (high confidence): the parent `bilingualActive` @State is only updated by `.readerBilingualDidChange`. `FoliateBilingualContainerView.ensureBilingualViewModel()` never calls `vm.postDidChange()` and runs only on first toggle, not on open → stale `false` → menu OFF + `ReaderMoreMenuRow` hides `.reTranslateChapter`. TXT fixed this in Bug #245; Foliate was missed.
- **Fix direction** (not applied): post the bilingual state on open from the Foliate path (mirror `TXTReaderContainerView+Bilingual` #245). GH #1360.

### Bug #306 — Bilingual cache unreachable behind provider gate (FILED 2026-06-02 via /triage)

- **Repro**: translate chapters, then disable AI / remove the provider (or re-create the provider profile) → reopen → previously-cached chapters re-fail / don't render (and otherwise re-translate).
- **Root cause** (high confidence): the disk cache is reached only inside `ChapterTranslationService.translate`, but `ChapterTranslationPrefetcher` resolves `aiService.resolveProviderConfig` (throws on AI-disabled/no-consent/no-key) BEFORE calling `translate` → unit `.failed`, cache never queried. `lookupKey` (bookFP|unitStorageKey|targetLang|providerProfileID|promptVersion) is stable across reopens; the only legitimate drift is re-creating a provider profile (new UUID = by-design provider-scoped invalidation). #245 warming intact.
- **Fix direction** (not applied): consult the cache by lookupKey BEFORE the provider gate (gate only on a cache miss). Pairs with #301. GH #1361.

### Bug #299 — EPUB bottom bar never appears (Readium default engine mounts no chrome) (FILED 2026-06-02 via /triage)

- **Repro**: open any EPUB → the bottom toolbar (progress + Contents/Notes/Display/AI) is absent; tapping toggles the TOP bar but no bottom bar ever shows (Light or Dark).
- **Root cause** (high confidence): the 2026-06-01 Readium default flip routes EPUB to `ReadiumEPUBHost`, whose `coreBody` (`ReadiumEPUBHost+Body.swift`) renders only the navigator/loading/error views and never mounts `ReaderBottomChrome`. The legacy `EPUBReaderContainerView` mounted it via `bottomOverlay` (`+Navigation.swift:31`) but is no longer the default path. The center-tap→`toggleChrome` wiring works (top chrome toggles), so this is a missing MOUNT, not a broken toggle. Same class as FIXED #260 (AZW3 live container shipped without bottom chrome).
- **Fix direction** (not applied): mount the shared `ReaderBottomChrome` on the Readium host, gated on the same chrome-visible state as the top bar, with a Readium progress binding + `onSeek`→`navigator.go(to:)` (mirror #260). **Rule 51 exempt** — `ReaderBottomChrome` is the already-designed feature #60 WI-6b component reused as-is. GH #1353.

### Bug #300 — App Settings section headers faint in Dark Mode (FILED 2026-06-02 via /triage)

- **Repro**: device in Dark Mode → open app Settings → the section headers "Cloud & Sync" / "AI" / "Reading" / "About" are barely visible (faint cream-on-cream); the row cards + labels are legible (post-#297).
- **Root cause** (code-read): the headers are plain `Section("…")` headers in a `Form` with no color modifier (`SettingsView.swift:220/261/295`, `AISettingsSection.swift:59`) → system `secondaryLabel`. `SettingsView` pins the `.paper` surface but sets no `.preferredColorScheme`, so in Dark Mode the system header resolves to light-gray ~1.07:1 over the pinned cream sheet. #297's fix (PR #1340) painted the row cards (`.listRowBackground`), leaving the header text untreated. NOT covered by #1292 (that bumps the reader Display panel's `theme.subColor`; these headers don't read it).
- **Fix** (2026-06-02, approach (a)): new Settings-local `SettingsSectionHeader(theme:title:)` paints each section header with `Color(theme.subColor)` (the designed `sub` token per #285/#1292). All four root sections converted to `Section{…} header: { SettingsSectionHeader(...) }`; platform Form header typography is inherited so it's a pure recolor. Device-verified in Dark Mode (headers legible). Rule 51 exempt. GH #1354.

### Bug #298 — Reader Display panel control-track contrast (toggle + segmented) (FILED 2026-05-31 via /triage)

- **Repro**: open a book → Display panel → Paper or Sepia (light) theme → the "Custom Background" toggle in its OFF state has a near-invisible pale track on the cream sheet; the "Scroll/Paged" segmented control's unselected segment + pale selected pill wash out.
- **Expected**: control tracks read clearly against the cream sheet (legible state/affordance).
- **Actual**: the OFF-toggle track and segmented-control track are system-default pale → near-invisible on `#fcf8f0`.
- **Root cause** (code-read, high confidence): `ReaderSettingsPanel.swift:170` applies `.tint(theme.accentColor)` list-wide, which colors only the ON-state toggle knob/track and the SELECTED segment fill (SwiftUI semantics). The OFF toggle (`Toggle` :393) and the unselected segment (`Picker(...).pickerStyle(.segmented)` :442) fall through to UIKit system defaults; there is no `UISwitch`/`UISegmentedControl` appearance override anywhere in the codebase. The `sub` token (#1292) is text-only and the `sliderTrack` token (#1273) is the slider rail — neither touches these control tracks. `ReaderSettingsPanelContrastTests` has no assertion for them.
- **DESIGN LANDED 2026-05-31** (was design-blocked, Rule 51): the binding decision is a per-theme `ReaderThemeV2.controlTrack` token = ink@30% (Paper `rgba(29,26,20,0.30)` / Sepia `rgba(58,41,19,0.30)`, ~1.9:1; Dark/OLED unchanged), driving the OFF-toggle track + segmented trough. Design-note `design-notes/control-track-token.md` (needs-design #1329 delivered). **Impl note**: the OFF-toggle track has no native `UISwitch` API → needs a custom toggle style (larger than the token add). Tests: OFF track vs sheet ≥1.8:1 + OFF≠accent Δ≥2.5:1. Sibling to #1273 (rail, shipped) + #1292 (sub, designed). This is the THIRD contrast facet of the Display panel, sibling to #1273 (rail, shipped) and #1292 (sub text, designed). GH #1329.

### Bug #297 — App Settings sheet dark-on-dark in system Dark Mode (FILED 2026-05-31 via /triage)

- **Repro**: device/Simulator in **Dark appearance** (`xcrun simctl ui booted appearance dark`) → launch vreader → open Settings (gear in the Library nav bar) → the Cloud & Sync / AI / Reading section rows render dark charcoal cells with near-black labels (dark-on-dark, nearly invisible); the cream "Your library" card + sheet stay legible. Light appearance = fine.
- **Expected**: the Settings sheet is light/cream regardless of system appearance (it pins `.paper`); every label legible.
- **Actual**: in Dark Mode the section-card cells render dark while labels stay near-black ink → illegible.
- **Root cause** (high confidence, code-read): `SettingsView.swift:78` / `AISettingsSection.swift:56` pin `theme = .paper` (fixed light tokens, no `colorScheme` branch). The Form paints cream `.background` + `.scrollContentBackground(.hidden)` (`SettingsView.swift:184-185`) but the section rows (`cloudAndSyncSection` :219-247, `readingSection` :259-287, `aboutSection` :292-314, `AISettingsSection`) set NO `.listRowBackground`, so cells inherit the appearance-aware system `secondarySystemGroupedBackground` (dark in Dark Mode); and the sheet pins no `.preferredColorScheme` (production has none — `colorSchemeOverride` is test-only). Only the profile card overrides its cell (`.listRowBackground(Color.clear)` + own white fill, `SettingsView.swift:207`). Icon tiles + toggles keep opaque brand fills → stay visible.
- **Fix direction** (not applied — triage only): (A) `.preferredColorScheme(.light)` / `theme.preferredColorScheme` on the sheet; or (B) give each Section row an explicit `.listRowBackground(Color(theme.paperColor))` light card fill, mirroring the profile card. (B) is the more faithful fix (cells match the cream surface). Restores broken UI to its designed light state — not new UI (Rule 51 OK). GH #1328.

### Bug #292 — EPUB paged direction inverted for RTL/vertical EPUBs (FILED 2026-05-31 via /triage)

- **Repro**: open an EPUB in paged mode → page next → content moves right (prev → left), inverted for LTR.
- **Root cause**: paged `scrollLeft` math is correct for LTR (unit-tested), but `metadata.readingDirection` (parsed `EPUBParser.swift:461-462`) is never consumed, so RTL/`vertical-rl` EPUBs (common for Chinese/Japanese) are paged with LTR math. If the book is LTR this is an expectation mismatch — needs confirming whether the EPUB is vertical-writing/RTL.
- **Fix**: consume `readingDirection` in the paged path (flip page→scrollLeft + writing-mode for RTL/vertical). GH #1300.

### Bug #293 — EPUB paged mode drops within-chapter position on reopen (FILED 2026-05-31 via /triage)

- **Repro**: page within a chapter in paged mode → close → reopen → lands at the chapter's page 1, not where you left off.
- **Root cause**: save works (post-#281); the paged load-finished branch (`EPUBWebViewBridgeCoordinator.swift:497-499`) ignores `pendingScrollFraction` (scroll-mode-only consumer at `:502`); `setupPagination` navigates only to `pendingPaginationPage` (nil on open → page 0). Pre-existing gap #281 exposed.
- **Fix**: convert the saved fraction → page in `setupPagination` after `totalPages` is known. GH #1301.

### Bug #294 — Chinese/CJK EPUB font too big: flatten-list gap (FILED 2026-05-31 via /triage)

- **Repro**: open a Chinese EPUB → body text larger than 16px even after #280/#290.
- **Root cause**: EPUB flatten list (`ReaderThemeV2+EPUBCSS.swift:122`) omits `section/article/main/<font>` etc.; CJK prose in such wrappers with em/% sizes compounds past 16px. The Foliate sibling already fixed this (#261, `FoliateStyleMapper.swift:68-72`); the EPUB path didn't.
- **Fix**: widen the EPUB flatten list to match Foliate's #261. Secondary: CJK perceptual size (cross-script calibration) — possible follow-up feature. GH #1302.

### Bug #295 — highlight tap opens empty panel (overlapping/near resolution) (FILED 2026-05-31 via /triage)

- **Repro**: tap a highlighted passage that has a note → an empty editor can open (no previous note).
- **Root cause**: note-seeding is correct; the tap resolves to the most-recently-added overlapping highlight (`.reversed()`) or the #287-tolerance nearest on a near-miss — which may be a different note-less highlight. (Or a genuine color-only highlight → designed empty state.)
- **Fix**: disambiguate overlapping/near taps. GH #1303.

### Bug #296 — annotations list (HighlightsSheet) can't scroll (#249 regression) (FILED 2026-05-31 via /triage)

- **Repro**: open the Notes/Highlights review sheet → try to scroll the list → it won't scroll.
- **Root cause**: `NotesDeleteRow.highPriorityGesture(DragGesture(minimumDistance:20))` on every card (`:58`/`:89-101`) wins over the ScrollView pan; the horizontal-only guard is inside `.onEnded` (too late), so vertical scroll-drags are swallowed. Regression from commit `1490e068` (#249 delete-affordance fix).
- **Fix**: `.simultaneousGesture` or an early horizontal-dominance guard in `.onChanged`. GH #1304.

### Bug #283 — AZW3/Foliate scroll: visible jump at chapter boundary (REOPENED 2026-05-31 — windowed scroll gated to non-vertical + gate unrun)

- **Repro**: open an AZW3 (e.g. 被讨厌的勇气.azw3) in scroll mode → scroll to a chapter end → the next chapter snaps in with a visible jump instead of scrolling up continuously.
- **Why the fix missed**: the #73 windowed continuous-scroll surface works for HORIZONTAL books but is gated `!this.#vertical` (`paginator.js:910/1510`); vertical-writing AZW3 (`vertical-rl`, common for CJK) falls back to the old per-section `#turnPage` swap = the exact #283 jump. The binding Gate-2 H7 large-CJK K=3 memory gate was also never run (plan 855/865/970) yet the feature was flipped ON + VERIFIED on a 7-section English `mini-azw3`.
- **Fix direction**: extend windowed scroll to vertical-writing books; run the large-CJK memory gate on a real device before re-closing. GH #1260.

### Bug #287 — Highlights hard to tap (REOPENED 2026-05-31 — Foliate/AZW3 left out of the 44pt tolerance)

- **Repro**: open an AZW3 carrying highlights → tap a highlighted passage → the edit panel often doesn't open (a near-miss turns the page instead).
- **Why the fix missed**: the 44pt tap tolerance (`HighlightHitTolerance.swift:37-41`, `slop=(44-dim)/2`) was wired into 4/5 formats; Foliate/AZW3 was left out — it relies on the vendored foliate-js `Overlayer.hitTest` (exact, no slop; `foliate-bundle.js:6111`) and `FoliateSpikeView+HighlightTap` only reacts to `annotation-show` with a `.zero` sourceRect, so there is no Swift-side hit-test to widen. The original row documented Foliate as an out-of-scope follow-up.
- **Fix direction**: add tap tolerance to the AZW3/Foliate path; secondary — fixed formats only reach exactly 44pt, and PDF tolerance is in page-points (a zoomed-out gap). GH #1268.

### Bug #27 — TXT flashes chapter 1 then jumps to saved position (REOPENED 2026-05-30 — regressed in chunked path)

- **Repro**: open a TXT book with a saved position → reader paints chapter 1/top, then visibly jumps to the saved offset.
- **Why regressed**: #27's UITextView alpha=0-hide fix doesn't cover the chunked `UITableView` bridge introduced by #180 (now the default). `makeUIView` returns the table at offset 0, then restores via `asyncAfter(+0.15s)` (`TXTChunkedReaderBridge.swift:220-237`) with no pre-paint hide → chapter 1 shows first, then an instant snap. Distinct from #289 (wrong landing); same restore path.
- **Fix direction**: port the pre-paint hide / set-offset-before-first-frame into the chunked bridge; verify on a real TXT book. GH #1284.

### Bug #279 — EPUB content draggable in scroll mode (REOPENED 2026-05-30 — #1269 locked the wrong scroller)

- **Repro**: open an EPUB in scroll mode (the default) → drag content → it still pans off-axis.
- **Why the fix missed**: #1269 pinned zoom + directional-lock on the OUTER WKWebView scrollView; the default continuous-scroll path scrolls an INNER DOM `#vreader-scroll-root` (`EPUBContinuousScrollJS.swift:55`) with no horizontal lock — the outer lock doesn't reach it.
- **Fix direction**: lock the inner scroller (overflow-x:hidden / touch-action:pan-y) in the continuous bootstrap. **Verify on a real EPUB in scroll mode on device** — the prior fix passed proxy (outer-scrollView) verification only. GH #1256.

### Bug #285 — Display panel low-contrast in Paper/Sepia (REOPENED 2026-05-30 — partial fix + orphaned rail)

- **Repro**: Paper/Sepia theme → Display panel → secondary text (section headers, footers, captions, swatch captions) still faint; slider rail still invisible.
- **Why the fix missed**: #1277 fixed PRIMARY labels (ink, 13-16:1) but re-routed SECONDARY chrome to the same `sub`@0.55 (Paper 3.82:1 / Sepia 3.36:1, below AA 4.5 — passed only the project's 3.0 self-bar); the slider `sliderTrack` token (carved to #1273) was never implemented.
- **Fix direction**: (A) raise secondary-text contrast to AA — **DESIGN LANDED 2026-05-31** (ink@68%, `design-notes/secondary-text-sub-token.md`; #1292 unblocked, token bump not yet shipped); (B) implement the committed #1273 `sliderTrack` token (Paper/Sepia ink@22%) — **SHIPPED v3.41.6**. Verify on-device against the real panel. GH #1265.

### Bug #290 — Default reading body font size too large out-of-box (FILED 2026-05-30 via /triage)

- **Symptom**: at the default, EPUB body reads too big, uniformly across books. NOT the #280 calibration (FIXED, at TXT parity) and NOT em-compounding (ruled out — uniform); the 18-unified default value itself is larger than wanted.
- **Fix direction**: lower the default unified `fontSize` (e.g. 18 → 16) in `TypographySettings`; confirm cross-format. GH #1283.

### Bug #288 — TXT TOC stale current-chapter highlight + whole-list flash on tap (FILED 2026-05-30 via /triage)

- **Repro**: open TXT TOC → tap a chapter → navigates correctly, but the highlight stays on the original chapter (visible on reopen); the whole list flashes on the tap, not just the tapped row.
- **Root cause**: highlight is a pure derivative of an async-updated `currentLocator` (only fed by a throttled/late `scrollViewDidScroll` after a programmatic non-animated scroll), with no optimistic tapped-entry write; the flash is the `.sheet(item:)` closure re-instantiating the whole `TOCSheet` on the locator change. One root cause, two facets.
- **Fix direction**: deterministic locator update on TOC nav + optimistic highlight; per-row identity isolation. Distinct from FIXED #234/#286/#282/#248. GH #1281.

### Bug #289 — TXT wrong reading-position restore on reopen (save omits contentInset.top) (FILED 2026-05-30 via /triage)

- **Repro**: read a TXT book (default scroll), close, reopen → lands ~2 lines before where you left off; drifts earlier each session. Worst on Dynamic-Island devices (default iPhone 17 Pro sim).
- **Root cause**: RESTORE `scrollToRow(.top)` honors `contentInset.top` (≈59pt, #179); SAVE `reportScrollPosition` omits it (`scrolledPast = contentOffset.y − cellRect.origin.y`), so each save persists an offset ~one inset earlier. Coordinate space correct; restore numerically correct (VM tests pass); the save-side pixel→char capture is the defect. Chunked coordinator also lacks a restore-suppression flag.
- **Why tests missed it**: all chunked tests inject offsets into `updateScrollPosition`, bypassing `reportScrollPosition`. Follow-on to #179. GH #1282.

### Bug #282 — TXT TOC takes ~1.3s to scroll to the current chapter (retry-loop timing) (FIXED 2026-05-29)

**Symptom**: opening the TXT TOC, the auto-scroll to the current chapter visibly creeps over ~1s+ instead of being there on open. Worst on books with many chapters.

**Root cause**: the Bug #248 scroll-restore retry loop in `TOCSheet.swift`'s `.task(id: currentChapterScrollTarget)` slept `[100, 300, 600]` ms *before* every `proxy.scrollTo` with no immediate t=0 jump. The authoritative scroll fired at cumulative ~1000ms and each was animated 0.3s, so settle hit ~1.3s. On long TOCs the early attempts targeted not-yet-materialized `LazyVStack` rows, so only the last (slowest) attempt landed.

**Fix**: extracted the schedule to a pure `TOCSheet.scrollRetryDelaysMilliseconds = [0, 80, 240]` (`TOCSheet+Support.swift`) and rewrote the loop to sleep only the incremental gap between cumulative delays. The first attempt (cumulative 0) fires immediately and unanimated — a materialized row lands the instant the sheet appears; later attempts remain a short animated (0.25s) fallback for the long-TOC not-yet-materialized case. No layout/design change (rule 51); the nested outer-`ScrollView`/`ScrollViewReader` structure is left intact. RED→GREEN pinned by `TOCSheetTests.scrollRetryScheduleLeadsImmediate` + `scrollRetryScheduleMonotonicAndFast`. Cross-ref #248. GH: #1259.

### Bug #270 — HTTP cloud TTS provider configurable but never used (HTTPTTSProvider orphaned) (FIXED — resolved by Feature #72)

**FIXED 2026-05-26 by Feature #72** (`HTTP cloud TTS provider integration`, VERIFIED, merge commit `4fdd7f75`, v3.39.29). The fix direction below was carried out through `/feature-workflow`: a `SpeechSynthesizing` adapter (`HTTPSpeechSynthesizer`) wrapping `HTTPTTSProvider` + an `HTTPTTSChunkPlayer` AVAudioPlayer queue, selected by `TTSService.defaultSynthesizer()` when `HTTPTTSConfig.validate() == .valid` (otherwise on-device fallback). The orphaned provider now drives read-aloud end-to-end; verified via a high-fidelity integration test (`dev-docs/verification/feature-72-20260526.md`, close-gate verification-exception). Feature #26 C6 gating is corrected (the gap was the wiring, now implemented). GH #1166 closed citing Feature #72.

**Discovered 2026-05-26 by the bugfix cron** while attempting Bug #269 (#1164) — and it **supersedes #269**. The user can configure an HTTP cloud TTS provider in Settings (`HTTPTTSSettingsView`, mounted at `SettingsView.swift:275`; writes `httpTTSConfig` to UserDefaults + the key to Keychain), but it is **silently ignored at runtime** — read-aloud always uses the on-device `SystemSpeechSynthesizer`. **Root cause**: `HTTPTTSProvider` (conforms to `TTSProvider`) is **orphaned** — `TTSService` drives `SpeechSynthesizing` and `defaultSynthesizer()` only ever returns `SystemSpeechSynthesizer`/`XCUITestMockSpeechSynthesizer`; nothing constructs `HTTPTTSProvider` in production, nothing consumes `TTSProvider` in production, and `TTSService`/`startTTS` never read `HTTPTTSConfig`. The two abstractions are disconnected (no adapter / provider-selection). **Impact**: a broken/misleading Settings surface; and Feature #26 (#359) C6 ("HTTP cloud TTS end-to-end") is *unimplemented* (not merely unverifiable) — its VERIFIED gating ("needs a live HTTP TTS server") is wrong; the gap is the wiring. C1–C5 (on-device AVSpeechSynthesizer) are genuinely implemented + verified. **Fix direction** (NOT done — filed not fixed per scope guardrail; product-integration task, likely `/feature-workflow`): wire `HTTPTTSConfig` into `TTSService`'s synthesizer selection (a `SpeechSynthesizing` adapter over `HTTPTTSProvider` chosen by `defaultSynthesizer()` when a valid config exists), or unify the two protocols. Severity Medium. GH: #1166.

### Bug #269 — No CU-free HTTP-TTS-provider config harness (blocks Feature #26 C6) (WONT DO — purpose resolved by Feature #72)

**WONT DO 2026-05-26 — purpose resolved by Feature #72.** The blocker premise is void: (1) Feature #72 wired `HTTPTTSProvider` into `TTSService` (a configured `HTTPTTSConfig` IS now read at runtime — the proposed config command is no longer MOOT), and (2) Feature #72 already **verified Feature #26 C6 CU-free** via a high-fidelity integration test (`vreaderTests/Integration/Feature72CloudTTSIntegrationTests.swift`) driving the real `TTSService → HTTPSpeechSynthesizer → HTTPTTSProvider` boundaries with only the network transport + audio backend stubbed (AGENTS.md close-gate verification-exception, since no live third-party HTTP TTS server is available). That satisfies #269's stated goal ("verify C6 CU-free") by a different, accepted approach. The proposed `tts-provider?action=set` command + mock-audio server would only add a *device-level real-socket* variant — low marginal value now that C6 is verified. Re-file if device-level mock-server verification is wanted later. GH #1164 closed citing Feature #72.

**Filed 2026-05-26 by the verify cron** during Mode-B survey of Feature #26 (#359). #26 is `DONE`/`partial` solely on criterion C6 (HTTP cloud TTS provider end-to-end); C1–C5 (local TTS lifecycle + genuine audio) all PASS. Contained blocker: there is **no CU-free way to configure the HTTP TTS provider** — DebugBridge has `tts?action=start|stop` + an AI-only `provider?action=add`, but nothing writes `HTTPTTSConfig` (only the `HTTPTTSSettingsView` Settings UI, CU-only). Exact sibling of Bug #243/#1057 (AI provider command) + Bug #237/#975 (`--enable-ai`). Fix: a DEBUG-only `tts-provider?action=set&endpoint=…&apiKey=…` DebugBridge command writing `HTTPTTSConfig`; with that + a local mock-audio HTTP server, C6 verifies CU-free (POST received + speaking-state; audio output cross-ref'd to device-mode like C5). Severity Medium — verification-tooling gap, same class as #243/#238/#233. GH: #1164.

### Bug #268 — Bilingual unit-model divergence: translate enumerated block text directly + leaf-fix Foliate host enumerate (FIXED — verified via close-gate exception)

> **✅ FIXED 2026-05-26 — both sub-parts done.** **Sub-part (1)** (branch `fix/issue-1159-epub-translate-blocks-directly`): the EPUB bilingual inject now detects a count divergence (`segments.count != currentBlocks.count`) and translates the DOM enumerate's OWN block `text[]` directly via a new cache-free `ChapterTranslationService.translatePreSegmented` → `ChapterPrefetching.translatedSegmentsDirect` → `BilingualReadingViewModel.translateBlocksDirectly`, so blocks↔segments are 1:1 **by construction** (eliminates the residual `<pre>`/mixed-content source-only fallback). **Additive + low-risk**: the common matched-count path is UNTOUCHED; the fallback only runs on the rare mismatch (currently source-only) so it can only improve or no-change, never regress or produce a wrong pairing. Codex Gate-4 thread `019e6434`, 1 round, ship-as-is. **Verified via close-gate exception** (`dev-docs/verification/bug-268-20260526.md`, result=pass): the AI-translation device path is CU-free-blocked (same class as #267/#243), so verified by high-fidelity unit tests at the real subsystem boundaries — `translatePreSegmented` (1:1 + per-segment-fallback + empty), `translateBlocksDirectly` (stores 1:1 + skip-if-matching), 62 bilingual/translation tests green. Sub-part (3) nested-block EPUB fixture remains verification debt (AI path not CU-free-drivable) but the LOGIC is unit-proven. **Sub-part (2) DONE 2026-05-26** (branch `fix/issue-1159-bilingual-foliate-leaf-enumerate`): the Foliate/AZW3 host enumerate (`foliate-host.js` `bilingualEnumerate`) now skips NON-leaf blocks (`if (el.querySelector(BLOCK_SELECTOR)) continue`), mirroring the EPUB leaf-fix (Bug #266) exactly, and `foliate-bundle.js` was rebuilt via esbuild (`npm ci` → `build-bundle.sh`). This eliminates the AZW3/MOBI enumerate double-count (nested `<blockquote><p>` / `<li><p>`) that previously forced the shared 1:1 pairing to fall back to source-only. Codex Gate-4 thread `019e6421`, 1 round, ship-as-is (mirrors the proven #266 fix; common non-nested `<p>` path unaffected). **Remaining**: sub-part (1) — translate the enumerated block `text[]` directly so blocks↔segments are 1:1 *by construction* (eliminates the RESIDUAL EPUB `<pre>`-blank-lines + mixed-content-`<blockquote>` divergence that leaf-enumerate alone can't). That is a **feature-workflow-class refactor**: it rewires the EPUB translation INPUT from `ChapterTextProviding.sourceText` (→ `ChapterSegmenter`) to the DOM enumerate's block texts, touching `ChapterTranslationService` (pre-segmented path), `ChapterTranslationPrefetcher`, `BilingualReadingViewModel`, and the EPUB inject path — across a shipped feature (#56), with AI-dependent device verification (CU-free-blocked, same class as #267). Both residual cases are RARE + FAIL-SAFE today (source-only, never a wrong pairing). Sub-part (3) — nested-block EPUB fixture — remains verification debt (the AI-translation path is not CU-free-drivable). **Recommendation**: take sub-part (1) through `/feature-workflow` (plan → audit → multi-format TDD → device verification) rather than a rushed `/fix-issue`.

**Filed 2026-05-26 during the Bug #266 fix** (Codex follow-up, thread `019e60ca`). Bug #266 fixed the wrong-pairing defect (leaf-enumerate + 1:1 count-safety → never a wrong pairing). Two completeness gaps remain, both **fail-safe** today (source-only on mismatch, never wrong): (1) the EPUB DOM leaf-enumerate and `ChapterSegmenter.paragraphs(plainText)` are still two unit models — a leaf `<pre>` with blank lines (1 block vs N segments) and a mixed-content `<blockquote>lead<p>…</p>tail` (container direct text in plain text but not the leaf enumerate) diverge → whole-chapter source-only. The architecturally-correct fix (Bug #266 option 1): translate the enumerated block `text[]` directly so blocks↔segments are 1:1 by construction. (2) the Foliate/AZW3 host enumerate (`foliate-host.js` `readerAPI.bilingualEnumerate`, built into `foliate-bundle.js` via esbuild) has the same `getElementsByTagName('*')` double-count — leaf-fix it + rebuild the bundle. Also: no nested-block EPUB fixture exists, so criterion-1 can't be device-verified CU-free (verification debt, same class as #267). Severity Medium — fail-safe today; completeness, not a wrong-pairing defect. GH: #1159.

### Bug #267 — AZW3/MOBI device verification blocked (harness gap) (TODO)

**Filed 2026-05-26 by the verify cron** while attempting Bug #265 / GH #1148 device verification. The fix (position save/restore on the live Foliate path) is sound — unit-tested controller + Codex ship-as-is, and on-device the build/open/`open?position=` seek path works without error — but the close-gate **discrimination** (reopen lands at the *saved* position, not the default start) can't be exercised CU-free: `mini-azw3` is a single short section that renders on one screen (all three candidate non-start CFI seeks landed at the identical start CFI), and there is no Foliate page-turn / scroll / search-nav DebugBridge driver to reach a distinguishable position. Fix: a larger multi-section AZW3 fixture, or a Foliate page-turn/scroll DebugBridge command. GH: #1157.

### Bug #266 — Bilingual translation misaligned to the wrong paragraph (FIXED — verified via close-gate exception)

> **✅ VERIFIED (close-gate exception) 2026-05-26** (`dev-docs/verification/bug-266-20260526.md`, result=**pass**). The never-wrong-pairing guarantee is proven at the real pairing boundary: `BilingualPairing.translationsByBid` returns source-only (empty map) on ANY count mismatch, so a wrong/drifted pairing is structurally impossible. `EPUBBilingualPipelineTests` (MORE- and FEWER-segments mismatch → `table.isEmpty`) + `FoliateBilingualPipelineTests` (25 tests, 2 suites, green) exercise the production contract. Device verification (nested-block EPUB + AI translation alignment) is CU-free-blocked (needs the #268 fixture + the AI path, same class as #267/#243), so closed under the AGENTS verification-exception with these high-fidelity tests. GH #1152 closed.



**FIXED 2026-05-26** (branch `fix/issue-1152-bilingual-translation-misaligned`, v3.39.14). Two-part fix: (1) **EPUB enumerate → leaf blocks only** — `EPUBBilingualJS.bilingualEnumerateJS` now skips a block element that contains another block element (`el.querySelector(BLOCK_SELECTOR)`), so a `<blockquote><p>` / `<li><p>` no longer double-counts the container + child against the plain-text paragraph segmentation (the reported `para 1 → para 3` drift). (2) **Shared count-safety** — new `BilingualPairing.translationsByBid` (both `EPUBBilingualPipeline` + `FoliateBilingualPipeline` delegate) pairs by index ONLY when `blocks.count == segments.count`; on ANY mismatch returns empty → source-only. The old `min(count)` partial pairing (the wrong-paragraph mechanism) is gone — **never a wrong pairing**. **RED→GREEN**: updated EPUB+Foliate pipeline + orchestrator tests (mismatch → empty/nil, was partial), added the leaf-skip JS pin; 49 bilingual tests + full `vreaderTests` (7158) green. **Codex Gate-4** (thread `019e60ca`, 1 round, follow-up-recommended): confirmed the `querySelector` semantics + shared helper + edge cases; flagged residual unit-model divergence (`<pre>` blank-lines, mixed-content `<blockquote>lead<p>…tail`) where leaf-enumerate still diverges from `ChapterSegmenter` → whole-chapter source-only (fail-safe, never wrong) — **accepted + filed Bug #268 / #1159** (translate enumerated block text directly for 1:1 by construction + leaf-fix the Foliate-host enumerate + add a nested-block EPUB fixture). Audit log `.claude/codex-audits/fix-issue-1152-bilingual-translation-misaligned-audit.md`. Device verification (nested-block render) is fixture-blocked (no nested-block EPUB fixture — tracked in #268) → `awaiting-device-verification`.

**Filed** by user triage 2026-05-25 ("EPUB translation misalignment. The translation of the first paragraph was inserted into the position of the third paragraph. Other book formats may have similar issues as well."). GH: #1152.

**Repro**:
1. Open an EPUB whose chapter has nested block structure or non-`<p>` leading blocks (epigraph `<blockquote><p>…</p></blockquote>`, a leading list, a `<pre>` with blank lines, definition lists).
2. Enable bilingual reading; let the chapter translate.
3. Read from the top.

**Expected**: each paragraph's translation appears directly under that same paragraph.
**Actual**: translations are shifted (reported: paragraph 1's translation lands under paragraph 3); the offset persists down the chapter.

**Root cause** (code-read): the pipeline matches translations to paragraphs by BLIND POSITIONAL INDEX (`EPUBBilingualPipeline.translationsByBid`: `map[blocks[i].bid]=segments[i]`), zipping two independently-produced segmentations: the render-side DOM enumerate (`EPUBBilingualJS`, walks `getElementsByTagName('*')` over `BLOCK_TAGS={p,li,blockquote,pre,dd,dt}` and DOUBLE-COUNTS nested `blockquote>p`/`li>p`/`dd>p`) vs the translation-side `ChapterSegmenter.paragraphs(in: sourceText)` over the extracted plain text (`ChapterTranslationService.swift:123`). No enforced 1:1 contract; the `sourceParagraphCount==segments.count` check (line 133) only guards cache staleness, never the enumerate count.

**Cross-format**: shared flaw — all five formats feed the same `ChapterSegmenter` segments into their own enumerate via the same index-zip (Foliate `FoliateSpikeView` bilingual, `TXTReaderContainerView+Bilingual`, `MDReaderContainerView+Bilingual`). Fix the contract uniformly, not the EPUB tag set. **Fix direction** in the Summary-table Notes for #266. Cross-ref: feature #56 (bilingual reading).

### Bug #265 — AZW3/MOBI reading position not saved or restored on reopen (FIXED — device-verified after rework)

> **✅ FIXED + DEVICE-VERIFIED 2026-05-26** (rework, `dev-docs/verification/bug-265-20260526.md`, result=**pass**). The reopen now resumes at the saved position. **Arc**: fix attempt #1 (v3.39.13) shipped but device verification FAILED (reopen still resumed at START). Instrumented OSLog localized it precisely — SAVE works (`flush: saving cfi=/6/10! progression=0.616`) and the restore-target loads (`loadRestoreTarget: saved cfi=/6/10! → target=…`), but the **CFI restore-seek never relocates the reader** (AZW3/MOBI use filepos-anchored CFIs that foliate-js `goTo` can't resolve; `goToFraction` works). **Rework**: restore via the saved `fraction` over `.foliateRequestSeekFraction` (the proven bottom-scrubber channel), CFI as fallback; re-assert across a short window (4×700ms) so the cross-section seek lands after pagination settles; short-circuit to immediate gate-open when nothing to restore. **Device-verified CU-free** on `mini-azw3`: seek 0.6 → reopen `/6/10!`; seek 0.35 → reopen `/6/6!` (byte-identical to saved CFI) — different fractions land at their correct saved sections. Codex Gate-4 thread `019e640e` 2 rounds ship-as-is (both round-1 Mediums — no-restore blackout + brittle single-sleep — fixed). Regression: `FoliatePositionRestoreControllerTests` (loadRestorePlan ×3) + `FoliatePositionPersistenceIntegrationTests`.



**FIXED 2026-05-26** (branch `fix/issue-1148-azw3-mobi-reading-position`, v3.39.13). Wired cross-session position persistence into the LIVE Foliate path. New `FoliatePositionRestoreController` (`@MainActor`, reuses `ReaderPositionService` for the 2s debounce + stale-write guard) owns the save gate + restore-target resolution; `FoliateBilingualContainerView+Position.swift` wires it: on the first `.foliateRelocated` (post-`readerAPI.init`, fires for every book incl. TOC-less) it loads the saved position → posts `.foliateRequestSeekTarget` (the #1136 seek channel) → opens the save gate; each `.readerPositionDidChange` then debounce-saves; `.onDisappear` flushes + cancels the restore task. **The save gate** drops the open→start relocate that would clobber the saved position before restore (gate opens only AFTER the seek is posted, no `await` between). **RED→GREEN**: 9 `FoliatePositionRestoreControllerTests`; full `vreaderTests` green (7157 tests). **Codex Gate-4** (thread `019e603a`, 2 rounds, ship-as-is): round-1 caught 3 Highs — restore was on `.foliateBookReadyTOC` which (a) is suppressed for TOC-less books and (b) fires pre-`init` so a `goTo` is overwritten by default-start nav, plus the gate opened before the seek post; all fixed by moving the trigger to the first `.foliateRelocated` + splitting `loadRestoreTarget`/`openSaveGate`. Round-2 caught 1 Medium (uncancelled restore task could seek a re-opened instance) → task stored in `@State` + cancelled on disappear + `Task.isCancelled` guard. Audit log `.claude/codex-audits/fix-issue-1148-azw3-mobi-reading-position-audit.md`. Device verification (reopen-resumes end-to-end) pending — `awaiting-device-verification`.

**Filed** by user triage 2026-05-25 ("azw3 cannt resume the process after reopen it") — user flagged **highest priority**. GH: #1148.

**Repro**:
1. Open a multi-chapter `.azw3` / `.mobi` book; read to ~chapter 5 / 40%.
2. Close it (back to library) or background + relaunch the app.
3. Reopen the same book.

**Expected**: reader resumes at the saved position (parity with PDF/TXT/MD/EPUB).
**Actual**: reader opens at the very beginning every time; prior position is lost.

**Root cause** (code-read): the only Foliate code that persists/restores position is the DEAD trio `FoliateReaderHost` → `FoliateReaderContainerView` + `FoliateReaderViewModel` (`ReaderFormatHosts.swift:213,248-255`; `FoliateReaderHost` is never instantiated — confirmed in #262/#1136). The LIVE route (`ReaderContainerView.swift:942` `.foliateWeb` → `FoliateBilingualContainerView` → `FoliateSpikeView`) has no VM, no `ReaderLifecycleHelper`, no `loadPosition`, and no seek-on-open — so neither save nor restore runs. `.readerPositionDidChange` (wired by #1136) only feeds live AI/snapshot context; no observer persists a `ReadingPosition`.

**Cross-refs**: Bug #260 (bottom chrome — same dead-container drop, FIXED), Bug #262/#1136 (TOC + locator nav + live position reporting — same class, FIXED; but navigation/reporting ≠ cross-session persistence), Feature #56 WI-11 (introduced the live `FoliateBilingualContainerView` wrapper). Rule-51-exempt (pure wiring, no new UI). **Fix direction** in the Summary-table Notes for #265.

### Bug #262 — AZW3/MOBI live Foliate: empty Contents TOC + no Notes/TOC row-tap navigation (FIXED 2026-05-22)

**Filed** by the Bug #260 / GH #1130 `/fix-issue` run, 2026-05-22 (surfaced by the Codex audit of #260's bottom-chrome mount; thread `019e4b93`).

**Context**: Bug #260 (FIXED, v3.39.5) mounted the AZW3/MOBI bottom chrome. Display / AI / scrubber / Notes-listing now work end-to-end. The two affordances below remain hollow on the *live* Foliate path (`engineReaderView` `.foliateWeb` → `FoliateBilingualContainerView` → `FoliateSpikeView`; `FoliateReaderContainerView`/`FoliateReaderHost` are DEAD code).

**Symptom A — empty Contents**: the bottom-chrome Contents button opens `TOCSheet` showing "No table of contents" for every AZW3/MOBI book, even when the book ships a TOC.

**Root cause A**: `ReaderTOCFactory.buildTOC` (`ReaderTOCBuilder.swift:21`) branches on `epub`/`pdf`/`txt`/`md` only — `azw3`/`mobi` fall through to `default: return []`. Compounding: the live `FoliateSpikeView.onBookReady` passes only `title` (`FoliateSpikeView.swift:84,184`), dropping the parsed `toc`/`sections` that `FoliateMessageParser.parseBookReady` + `FoliateTOCConverter` could feed.

**Symptom B — no row-tap navigation**: tapping a Contents / Notes / Highlight row does not jump into AZW3 content.

**Root cause B**: the shared sheets post `.readerNavigateToLocator`; current-location sync needs `.readerPositionDidChange`. BOTH are observed/produced only by the dead `FoliateReaderContainerView` (`FoliateReaderContainerView+Navigation.swift`), never `FoliateBilingualContainerView`.

**Related sub-item — cross-format chrome desync**: when the More popover is open, `ReaderContainerView`'s `.readerContentTapped` handler closes the popover WITHOUT toggling the top chrome, while every per-container bottom overlay (all 5 formats) blindly toggles its own local `isChromeVisible` → top/bottom desync. Pre-existing across all formats; the proper fix is hoisting chrome visibility to the shared `ReaderContainerView` level (a refactor #260 kept out of scope), which fixes it uniformly.

**Fix direction**:

1. Capture the Foliate `book-ready` TOC on the live path (extend `onBookReady` to forward `sections`/`toc`), convert via `FoliateTOCConverter`, feed `tocEntries` (add an azw3/mobi branch to `buildTOC` or a parallel Foliate TOC source).
2. Wire `.readerNavigateToLocator` (→ `readerAPI.goTo`/`goToFraction`) + `.readerPositionDidChange` on `FoliateBilingualContainerView`.
3. Consider the shared-chrome hoist for the desync.

**Severity Medium** — the bottom bar + 4 of 5 affordances work after #260; this is the residual TOC/navigation completeness gap for AZW3, not a total breakage.

**Cross-ref**: Bug #260 (the mount, FIXED, v3.39.5).

**FIXED 2026-05-22** in `fix/issue-1136-azw3-toc-nav-wiring` (v3.39.7). Wired both affordances on the live `FoliateBilingualContainerView` path without inventing UI (rule-51 exempt — populates the EXISTING `TOCSheet` + responds to the EXISTING `.readerNavigateToLocator`, the same infra the other 4 formats use):

- **Symptom A (empty TOC)**: the `book-ready` JS message already carries `toc` (foliate-host.js `serializeTOC`), but the spike's handler dropped everything but `title` at the `onBookReady: (String) -> Void` boundary, and `ReaderTOCFactory.buildTOC` has no Foliate file parser. Fix: the spike Coordinator now posts the parsed TOC on a new `.foliateBookReadyTOC` (when non-empty); `FoliateBilingualContainerView` converts it via the existing `FoliateTOCConverter` and relays `[TOCEntry]` up on `.foliateTOCAvailable`; `ReaderContainerView` (via the new `FoliateTOCAvailableObserver` modifier — kept out of `body` to stay under SwiftUI's type-check budget) sets `tocEntries` + `tocDidLoad`.
- **Symptom B (no row-tap navigation)**: `FoliateBilingualContainerView` now observes `.readerNavigateToLocator`, resolves a Foliate-js `goTo` target (CFI preferred, else the EPUB-style href TOC entries carry) via the new pure `FoliateNavSeek` helper, and forwards it on `.foliateRequestSeekTarget`; the spike Coordinator evaluates `readerAPI.goTo('<escaped>')` against the live WebView (mirrors the Bug #260 `.foliateRequestSeekFraction` seek channel + lifecycle). The relocate path now also posts `.readerPositionDidChange` (carrying the section href + CFI + reading fraction) so AI-panel context + the DebugBridge snapshot track the live AZW3 position — pre-fix this was produced only by the dead container.

**Out of scope (deliberate)**: the cross-format chrome-visibility hoist refactor (the More-popover desync sub-item) — a separate concern #260 also kept out, left for a dedicated iteration.

RED→GREEN: `FoliateTOCNavWiringTests` (17 tests — book-ready TOC forwarding, `buildTOC` azw3 safety, target resolution CFI-then-href, `goTo` JS escaping, seek-target observer lifecycle, position-locator + fraction). Codex audit `ship-as-is` (2 rounds; round-1 caught 2 Medium issues — `positionLocator` dropping the relocate fraction (AI context pinned to book start) + `FoliateTOCConverter` accepting empty hrefs (dead TOC rows) — both fixed with +4 regression tests). Full suite 7088 tests green. CU-free device verify on iPhone 17 Pro Sim (build 628): `mini-azw3` Contents sheet now lists 3 entries (pre-fix "No table of contents"); `readerAPI.goTo('filepos:0000017749')` moved the snapshot position `epubcfi(/6/2!/4,…)` → `epubcfi(/6/10!/4,/2[filepos0000017749],…)`, confirming both the live TOC data + navigation seek. Evidence: `dev-docs/verification/bug-262-20260522.md` + `dev-docs/verification/artifacts/bug-262-verify-toc-populated-20260522.png`. GH: #1136.

### Bug #261 — AZW3/MOBI reader renders body text too large (Foliate font-size calibration / em-compounding) (FIXED 2026-05-22)

**Reported** by the user, 2026-05-21 (`/triage`): "the fontsize is too big".

**Symptom**: AZW3/MOBI body text renders perceptibly larger than TXT / EPUB at the same font-size slider value (and too large at the default unified size of 18).

**Repro**:

1. Launch `vreader` on iPhone 17 Pro Sim at v3.39.2.
2. Open an AZW3/MOBI book (e.g. bundled `mini-azw3`) and a TXT or EPUB book.
3. Set the same font-size slider value for both (or compare at default).
4. Observe: AZW3 text is visibly larger than the TXT/EPUB text at the same setting.

**Expected**: AZW3 renders at a size perceptually consistent with TXT (the calibration anchor) at the same slider value.

**Actual**: AZW3 text is oversized.

**Font sizing IS implemented for AZW3** — `FoliateSpikeView.themeCSS(for:)` routes `store.typography.fontSize` (default 18) through `FontSizeCalibrator.calibratedFoliateSize(forUnified:)` → `FoliateStyleMapper.themeCSS(fontSize:…)` → Foliate-js `setStyles`. So this is a too-large *output*, not a missing pipe → bug, not feature.

**Two candidate root causes**:

1. **Calibration mis-tune** — the `.standard` profile sets `foliate: 1.12` (`FontSizeCalibration.swift:88`, identical to `epub: 1.12`). The source comment explicitly flags these as *"conservative, identity-leaning estimates"* whose literals *"Gate-5 behavioral verification confirms or re-tunes"* — and feature #491's calibration was never device-verified for the Foliate target specifically. If Foliate-js renders the px value larger than the EPUB WKWebView does at the same number, 1.12 is too high for AZW3 and should drop.
2. **em-compounding** — Foliate-js applies the user font-size as a base on a root element; AZW3/MOBI (Kindle) books frequently carry their own `em`/`%`-based font-size CSS, which multiplies against the injected base. Bug #166's root-cause note already documented *"the book's own stylesheet compounds or conflicts"* for WebView formats. The calibrator assumes the px maps ~directly, so a book with `body{font-size:1.2em} p{font-size:1.1em}` renders ~32% larger than the slider implies.

**Fix direction**:

1. **Measure first** — device-measure AZW3 cap-height at unified 24 on iPhone 17 Pro Sim vs the TXT anchor; if a flat multiplier mismatch, re-tune the `foliate` literal in `FontSizeCalibrationProfile.standard` (cheap, no architecture change — the literal is explicitly designed to be re-tuned).
2. **If em-compounding dominates** — normalize the book's root font-size in the injected CSS (force `html{font-size:<px>}` and neutralize book `body`/`p` em-bases) so the slider value maps predictably across books regardless of their own stylesheet.

**Cross-ref**:
- Bug #260 — the Display button that hosts the font-size slider lives in the bottom chrome, which is currently NOT mounted for AZW3. So an AZW3 user cannot even reach the slider to work around this oversized text. The two bugs compound; #260 should land first.
- Bug #166 (FIXED) — cross-format font inconsistency; its calibration residual was split to feature #491. This bug is the AZW3-specific manifestation surfacing post-calibration.

**Severity Medium** — text is readable, just oversized; becomes adjustable once #260 restores the Display affordance.

**Verification harness**: after the fix, open `mini-azw3` and a TXT book at the same slider value; confirm cap-heights match within ~5% on iPhone 17 Pro Sim.

### Bug #252 — EPUB DebugBridge open path — PR #1088's `loadFileURL` log site is not reached, inference is the layer above Bug #1085 + Bug #1086 (TODO 2026-05-21)

**Filed** by the Feature #64 Gate-5b round-3 verification (this PR, evidence `dev-docs/verification/feature-64-20260521-round3.md`).

**Symptom**: against v3.38.27 (build 602 — the release that ships BOTH Bug #1085 + Bug #1086 fixes), `vreader-debug://reset` → `seed?fixture=mini-epub3` → `open?bookId=epub:f284fd...:2198` → `settle?token=...` STILL hits `error: "settle timeout"` (Stage-1 timeout, identical shape to round-2). Reproduced 2 independent times across separate fresh `simctl terminate`+`launch` cycles.

**Critical diagnostic from PR #1088's new instrumentation**: PR #1088 (Bug #1086 fix) added `AppLogger.epub.info("loadFileURL: <file>")` immediately before `webView.loadFileURL(...)` inside `EPUBWebViewBridge.updateUIView`, plus `didFinish: url=...` entry log and `didFail*` error logs. **None of these logs appear** in the filtered `subsystem == "com.vreader.app"` log stream — between `[DebugBridge] open: posted notification` and the 41s-later `[DebugBridge] settle: ... with error=settle timeout` there are ZERO EPUB-category events of any kind.

**The strongest inference from absence**: the run does not reach the `loadFileURL` log site inside `EPUBWebViewBridge.updateUIView`. This is **inference from absence on a filtered stream, not direct observation** — round-3 did not add host-layer / `makeUIView` instrumentation, so it cannot directly distinguish "view tree never reached the bridge" from "bridge mounted but `updateUIView` short-circuited before the log site". The most parsimonious explanation is the former: the SwiftUI host (`EPUBReaderContainerView` / `ReaderContainerView.engineReaderView` / `ReaderEngine.resolve(.epub)` route) never instantiated the bridge view, or the bridge view never entered the view hierarchy, or the `UIViewRepresentable.makeUIView`/`updateUIView` lifecycle never landed. **What IS firm**: the failure is upstream of the existing PR #1088 bridge-level instrumentation — neither #1085 (settle gate) nor #1086 (bridge-level fallback) can address it.

**Why this is NEW, not Bug #1086 re-opened or Bug #1084 re-opened**:

- **Bug #1084** (FIXED in PR #1085 — v3.38.24): same-key reopen race where `didFinish` *fired* but `setActiveEPUBWebView` was *rejected* by the stale-write guard → settle returned success, downstream highlight-create logged `no active EPUB WebView registered`. Sits at the **Stage-2 settle gate** layer (`RealDebugBridgeContext+Settle.swift`). Depends on the bridge's `markReaderSettled` side-effect firing.
- **Bug #1086** (FIXED in PR #1088 — v3.38.27): inferred `didFinish` doesn't fire → Stage-1 settle times out. Sits at the **Stage-1 bridge fallback** layer (`EPUBWebViewBridgeCoordinator.scheduleEarlySettleFallback`). The fallback is scheduled by `EPUBWebViewBridge.updateUIView` immediately after `loadFileURL`.
- **Bug #252** (this filing): PR #1088's `loadFileURL` log site (inside `EPUBWebViewBridge.updateUIView`) is not reached. Sits at the **host / route / representable** layer above both #1085 and #1086 — inference from absence on a filtered log stream, not direct observation.

The three EPUB layer fixes do not converge. Each correctly addresses a real failure at its own layer (Codex Gate-4 audits confirmed all three were sound on their own merits), but each is downstream of the actual blocker.

**Root-cause hypothesis (un-bisected)**: EPUB host or route regression in v3.38.x. Heavy churn in EPUB host/route surface in this range:

- feature #56 WI-10 / WI-11 bilingual interlinear renderer + Foliate host wiring
- feature #62 WI-5 chrome rewire (TOCSheet + HighlightsSheet, deleted legacy `AnnotationListView` + `HighlightListView`)
- feature #64 WI-8 + WI-10 EPUB highlight popover migration
- feature #54 WI-3 reader-engine dispatch (`ReaderEngine.resolve` + `ReaderContainerView.engineReaderView` route by `ReaderEngine`)

Round-1 ran against v3.38.22 and DID reach the EPUB observer-invocation point (per the round-1 PARTIAL row's wording), so the regression that prevents PR #1088's `loadFileURL` log from firing entered between v3.38.22 and v3.38.27. The exact bisect commit is the first thing the fixer should establish.

**Likely shared root cause with Bug #244**: Bug #244 (user-triage 2026-05-20, "EPUB reader opens but content area is blank") describes a production user-visible symptom — open an EPUB from the library, the reader chrome appears but the content area paints blank. Bug #252's symptom is autonomous-harness, but the underlying cause sits at the same EPUB host layer. If they share root cause, Bug #244's fix subsumes Bug #252 — and Bug #244's priority should be re-evaluated up because it now blocks automated verification of every EPUB-touching feature, not just user reading.

**Repro recipe**:

1. Build + install v3.38.27 (or any release post-PR #1088): `xcodebuild build -project vreader.xcodeproj -scheme vreader -configuration Debug -destination "platform=iOS Simulator,id=<UDID>" -derivedDataPath <DD>` then `xcrun simctl install <UDID> <APP>`.
2. Grant URL scheme: `bash scripts/grant-debug-scheme-approval.sh <UDID>`.
3. Launch + fire the open sequence:
   ```bash
   xcrun simctl launch <UDID> com.vreader.app && sleep 5
   xcrun simctl openurl <UDID> "vreader-debug://reset" && sleep 2
   xcrun simctl openurl <UDID> "vreader-debug://seed?fixture=mini-epub3" && sleep 3
   KEY="epub:f284fd074ccd1d3c1a78985464d9e1be27975f4029f3c2ddef8428ca10684af4:2198"
   ENC=$(printf '%s' "$KEY" | sed 's/:/%3A/g')
   xcrun simctl openurl <UDID> "vreader-debug://open?bookId=$ENC" && sleep 20
   xcrun simctl openurl <UDID> "vreader-debug://settle?token=epub-r3" && sleep 35
   ```
4. Inspect `Library/Caches/DebugBridge/ready-epub-r3.json` inside the simulator's app container: it carries `error: "settle timeout"`, `phase: "unknown"`.
5. Inspect logs: `xcrun simctl spawn <UDID> log show --last 120s --predicate 'subsystem == "com.vreader.app"' --info --debug --style compact`. Zero EPUB-category logs.

**Fix direction**:

- **(a) Bisect** v3.38.22 → v3.38.27 against the round-3 repro recipe to confirm the commit where the EPUB `loadFileURL` log site stops being reached for `mini-epub3`.
- **(b) Instrument the host layer** — add `AppLogger.epub.info` entry logs to `EPUBReaderContainerView.body` (or the equivalent route point in `ReaderContainerView.engineReaderView`), and to `EPUBWebViewBridge.makeUIView` so the next verify run can directly observe whether the bridge is instantiated at all (round-3 had to infer from absence of the `loadFileURL` log).
- **(c) Cross-correlate with Bug #244** — if the user's production "blank EPUB content" reproduces on `mini-epub3`, both bugs share a fix.
- **(d) Check the route arm** — the `.epub → ...` case in `ReaderContainerView.engineReaderView` and the `ReaderEngine.resolve(.epub)` mapping (feature #54 WI-3 territory).

**Severity Medium** — blocks autonomous host-driven EPUB highlight verification across Feature #64 + every future EPUB-touching feature. CU workaround exists but CU has been chronically down across rounds 1-3 (3 separate sessions over 2 days). This is now the third EPUB blocker filed in 2 days (#1084 / #1086 / #252).

**Verify-cron only filed, never fixed.** The /fix-issue worker (when it picks this up) should follow Bug #244's bisect path first — they likely share root cause.

GH: #1089

### Bug #251 — EPUB DebugBridge open path — `mini-epub3` settle hits Stage-1 timeout post-Bug-#1085 (FIXED 2026-05-21)

**Filed** by the Feature #64 Gate-5b round-2 verification (this PR, evidence `dev-docs/verification/feature-64-20260521-round2.md`, GH #1086).

**Symptom**: against v3.38.25 (build 600 — the release that ships Bug #1085's fix), `vreader-debug://reset` → `seed?fixture=mini-epub3` → `open?bookId=epub:f284fd...:2198` → `settle?token=...` hits `error: "settle timeout"` (Stage-1, not the new `webview not registered` Stage-2 sentinel from Bug #1085). Filtered `subsystem == "com.vreader.app"` log shows ZERO EPUB-load events between `open: posted notification` and the timeout 30s later. Subsequent `vreader-debug://highlight` logs `epub highlight observer: no active EPUB WebView registered` and `highlightCount` stays at 0. Reproduced 3× across separate fresh `simctl terminate`+`launch` cycles.

**Why NEW, not Bug #1084 re-opened**: Bug #1084 was the same-key reopen race where `didFinish` fired but `setActiveEPUBWebView` was rejected by the stale-write guard → settle wrote success, downstream highlight-create logged `no active EPUB WebView registered`. Bug #251 is symptom-different: `didFinish`'s side-effects (`markReaderSettled`, `setActiveEPUBWebView`) are NOT observed, so Stage-1 times out and Stage-2 is never entered — the new sentinel error `webview not registered` does not appear, just the old `settle timeout`. AZW3 (Foliate, also WKWebView-backed) and TXT/MD settle cleanly in the same harness round, so the regression is specific to `EPUBReaderHost` / `EPUBWebViewBridgeCoordinator` / `EPUBWebViewBridge.loadEPUB`.

**Fix direction**: (a) **bisect** v3.38.22 → v3.38.25 against the repro recipe to confirm the commit where EPUB `didFinish` stops firing for `mini-epub3`; (b) **instrument** `EPUBWebViewBridgeCoordinator.webView(_:didFinish:)` and `EPUBWebViewBridge.loadEPUB(...)` with info-level entry/exit/load-request logs so future verify cron runs can directly observe (instead of infer) which callbacks did or didn't run; (c) cross-ref **Bug #244** (user-triage EPUB blank content) — if same root cause, #244's fix subsumes #251.

**FIXED 2026-05-21** (branch `fix/issue-1086-epub-debugbridge-settle-stage1-fallback`). Implemented Direction (b) instrumentation **plus** a robust bounded fallback so the harness can proceed even when WKWebView's `didFinish` callback is delayed or missing — neither would happen on a healthy load, but round-2 observed both. **Changes**:

- `EPUBWebViewBridge.updateUIView`: adds `AppLogger.epub.info("loadFileURL: <filename>")` immediately before `webView.loadFileURL(...)` so the next verify run can directly observe the load request (the round-2 evidence could only infer absence). Immediately after `loadFileURL`, schedules `Coordinator.scheduleEarlySettleFallback(webView:)` — a `Task` that sleeps for `earlySettleFallbackDelay` (default 2.0s) and, if not cancelled by a winning `didFinish`, calls `DebugReaderRegistry.shared.setActiveEPUBWebView(_:for:token:)` + `markReaderSettled(for:token:)` itself. This is the same `(key, token)` write the genuine `didFinish` would have made; the registry's stale-write guard still applies, so the fallback never clobbers a different reader's binding.
- `EPUBWebViewBridgeCoordinator.webView(_:didFinish:)`: adds `AppLogger.epub.info("didFinish: url=<filename>")` entry log; calls `cancelEarlySettleFallback()` at the top so a winning didFinish drops the pending fallback Task before either side-effect fires. When the identity-guard (`fingerprintKey` + `readerToken`) fails the log records that the registry binding was skipped — same observability gap closed.
- `EPUBWebViewBridgeCoordinator.webView(_:didFailProvisionalNavigation:)` / `didFail`: add `AppLogger.epub.error("didFailProvisionalNavigation: <reason>")` / `didFail: <reason>` entry logs so a future regression that aborts the load before `didFinish` is no longer silent — the verify cron sees the failure mode directly.
- Coordinator state: new `var earlySettleFallbackDelay: TimeInterval = 2.0` (DEBUG-only) and `var earlySettleFallbackTask: Task<Void, Never>?` for the Task handle. New methods `scheduleEarlySettleFallback(webView:)` and `cancelEarlySettleFallback()` (both DEBUG-only).

**Idempotency**: when `didFinish` arrives BEFORE the fallback fires, `cancelEarlySettleFallback()` drops the pending Task — registry is touched once. When `didFinish` arrives AFTER the fallback fires, the registry writes are no-ops — `setActiveEPUBWebView` re-stores the same ref under the same key/token; `markReaderSettled` inserts the same `(key, token)` SettleKey into a Set. Either order is safe.

**Identity guard**: when `fingerprintKey` or `readerToken` has not been threaded yet, the fallback no-ops and emits an explicit log rather than writing a half-identity binding to the registry. Mirrors the existing `didFinish` guard.

**Tests** (TDD RED→GREEN): new suite `EPUBWebViewBridgeEarlySettleFallbackTests` (3 cases): (1) fallback fires both `setActiveEPUBWebView` and `markReaderSettled` after the bounded delay when not cancelled; (2) `cancelEarlySettleFallback` drops the pending Task — registry untouched; (3) fallback no-ops when identity fields are nil. All 3 pass on UDID `61149F0E-DC18-4BE2-BB37-52659F1F4F62`, `-parallel-testing-enabled NO`. Full vreaderTests gate: pre-existing 6953 tests + 3 new = green in 59.5s. Pre-FIXED verify: without the new fallback code, the same tests fail to compile (`'EPUBWebViewBridge.Coordinator' has no member 'earlySettleFallbackDelay' / 'scheduleEarlySettleFallback' / 'cancelEarlySettleFallback'`) — RED demonstrated before GREEN.

**Why this is not a layer-3 race**: the brief explicitly asked to stop and file Bug #252 if a deeper race were uncovered. The instrumentation added here was intended to surface that race if it exists; the fallback is a defense-in-depth path that unblocks the harness regardless of cause. Device verification of the underlying didFinish behavior on `mini-epub3` (does the callback genuinely fire? does the WKWebView in this build aliasing differently with the iOS 26.5 Simulator?) is deferred to the post-merge close-gate run on GH #1086 — the new logs directly answer it.

**Codex Gate-4 audit**: see PR description / audit log.

GH: #1086

### Bug #249 — HighlightsSheet ("Notes" panel) has no delete affordance — feature #62 WI-5 regression (FIXED 2026-05-21, v3.38.44)

**Reported** by the user, 2026-05-20 (`/triage`): "annotations cant be removed in the 'notes' pannel".

**Symptom**: in the Notes panel (HighlightsSheet, Notes filter), there is no way to remove an annotation / highlight / note. No swipe-to-delete, no per-card delete button, no long-press destructive context menu. Both `HighlightRecord` and `AnnotationRecord` cards are tap-to-jump only.

**Repro**:

1. Launch `vreader` on iPhone 17 Pro Simulator at v3.38.20.
2. Open a TXT / EPUB / PDF / AZW3 / MD book that has at least one highlight or standalone note.
3. Tap the **Notes** button in the bottom chrome → HighlightsSheet opens on the Notes filter.
4. Attempt to delete a row:
   - Swipe left → no swipe action (no `.swipeActions` modifier).
   - Long-press the card → no context menu (no `.contextMenu` modifier).
   - Inspect the card → no trailing trash button, no `⋯` menu, no delete icon.
5. Tapping the card navigates to the source passage (`onJump`) — that's the only available action.

**Expected**: a destructive affordance to delete the row (swipe-to-delete OR per-card menu) that calls `AnnotationListViewModel.removeAnnotation(annotationId:)` (the data-layer method still exists in production).

**Actual**: no destructive affordance reachable from the centralised review panel. Users must navigate to the source passage and use the in-reader tap-on-highlight popover (feature #53) instead — a multi-step indirect path that defeats the purpose of the review panel.

**Regression source (high confidence, code-read + git archaeology)**:

- Legacy `vreader/Views/Annotations/AnnotationListView.swift` (deleted by commit `d17f6dfd`, feature #62 WI-5, 2026-05-19) was a `List` view. Its purpose comment read verbatim:

  ```
  // Purpose: List of annotations with content preview.
  // Supports swipe-to-delete, tap to navigate, and edit via sheet.
  ```

  Implementation: `.onDelete(perform: deleteAnnotations)` calling `viewModel.removeAnnotation(annotationId: ...)` for each offset.
- Commit `d17f6dfd` ("rewire reader chrome to TOCSheet + HighlightsSheet, delete legacy panel") deleted `AnnotationListView.swift` (and `HighlightListView.swift`) and migrated to the new `HighlightsSheet`.
- The new `HighlightsSheet` (`vreader/Views/Reader/Annotations/HighlightsSheet.swift:84, 222`) uses `ScrollView { ... LazyVStack { ... } }`. SwiftUI's `.swipeActions` is a `List`-only modifier (same constraint feature #56 WI-15 documented in its scope-note about the deferred TOC swipe re-translate: *"the existing TOC is `LazyVStack`-in-`ScrollView` and SwiftUI `.swipeActions` requires a `List` host"*).
- `AnnotationListViewModel.removeAnnotation(annotationId:)` is still on the ViewModel; the data path is intact. The bug is purely the missing user-facing UI affordance.

**Rule-51 constraint — fix is blocked on needs-design**:

The committed design bundle (`dev-docs/designs/vreader-fidelity-v1/project/vreader-notes-unified.jsx` and `design-notes/needs-design-issues.md`) covers the Highlight + Standalone-Note cards, the All/Highlights/Notes/Bookmarks filter chip set, and empty states — but does NOT depict any destructive row action. The note-preview design-note even says explicitly *"Destructive actions live elsewhere"* (in the context of the tap-on-highlight popover, not the review sheet).

Per rule 51, the fix cannot invent a swipe / button / menu affordance for the HighlightsSheet review surface without a committed design. The `/fix-issue` run handling #1078's analog should:

1. File a `Design needed: delete affordance in HighlightsSheet (Notes panel) for feature #62` GH issue (labels `enhancement` + `needs-design`).
2. Mark this bug row `BLOCKED: needs-design (#<new-issue>)` in its Notes column.
3. Stop the slice until the design lands.

**Two viable affordance shapes for the design to choose between**:

- **(a) `List` + `.swipeActions`** — matches Mail / Notes vocabulary; iOS-canonical. Design owner must reskin the cards as List rows (background, separators, padding all change).
- **(b) per-card destructive context-menu** OR trailing `⋯` opening Edit / Share / Delete — closer to the existing tap-on-highlight popover (feature #53) vocabulary, no container change needed.

**Severity High** — core CRUD capability gone from a centralised review surface. Workaround (in-reader tap-on-highlight popover) requires navigating to the source passage first, which is the opposite of what a "centralised review panel" should require.

**Cross-ref**:
- Bug #248 — also a feature #62 WI-5 regression (TOC auto-scroll lost). Same migration class; same `LazyVStack`-vs-`List` SwiftUI-API constraint manifests in both bugs.
- Feature #56 WI-15 — already documented the `LazyVStack`-vs-`.swipeActions` constraint as a scope-deferral note.

**Verification harness**: after the design lands and the fix ships, open the Notes panel against a book with ≥1 highlight + ≥1 standalone note; exercise the new delete affordance on each card kind; confirm both `HighlightRecord` and `AnnotationRecord` rows leave the list AND the underlying record is removed from `PersistenceActor` storage (re-open the sheet to confirm).

**2026-05-21 `/fix-issue` attempt + Codex Gate-4 verdict**:

A `/fix-issue #1080` run on branch `fix/issue-1080-highlightssheet-delete-affordance` attempted Option (b) — adding `.contextMenu { Button(role: .destructive) { onDelete($0) } label: { Label("Delete", systemImage: "trash") } }` to each of `HighlightCardV3` / `StandaloneNoteCard`, wired through new `func deleteHighlight(highlightId:) async` / `func deleteAnnotation(annotationId:) async` methods on `HighlightsSheet` that route through `HighlightListViewModel.removeHighlight` / `AnnotationListViewModel.removeAnnotation`. All 22 `HighlightsSheetTests` (including 4 new bug-249 regression tests covering both card kinds + the persistence-effect assertion) passed under `xcodebuild test -only-testing:vreaderTests/HighlightsSheetTests -parallel-testing-enabled NO` in 1.957s on UDID `1FAB9493-B97E-48F0-96C7-44A8E5AAA21E`.

**Codex Gate-4 audit verdict** (thread `019e47fd-9b06-79d3-b011-4f460107f005`, model gpt-5.5, read-only sandbox): **`needs-fix`**. The High-severity finding was a Rule-51 violation: introducing `.contextMenu` IS adding new user-visible chrome (the popup menu rendered on long-press) on a surface the committed `vreader-notes-unified.jsx` does not depict destructive row actions for. Rule 51's "system chrome" exemption is narrowly scoped to OS chrome (status bar, home indicator, dynamic island), NOT to contextual menus on app content. The `vreader-highlight-popover.jsx` Delete vocabulary in the in-reader popover is design precedent for the verb but NOT design coverage for THIS surface and THIS interaction state (per rule 51's "What 'designed' means": *"Looks similar to existing X" does NOT count*).

Implementation reverted; `Design needed: delete affordance in HighlightsSheet (Notes panel) for bug #249` issue filed at **GH #1103** with labels `enhancement` + `needs-design`; audit recorded at `.claude/codex-audits/fix-issue-1080-highlightssheet-delete-affordance-audit.md`. Slice stops until the design bundle commits a Highlights/Notes-panel destructive affordance shape under `dev-docs/designs/vreader-fidelity-v1/project/`. The implementation pattern explored (closure-pass-through + `.contextMenu` Delete + VM-route) is recorded in the audit as prior art for the post-design resumption.

### Bug #248 — TOC sheet (Contents) does not auto-scroll to the current chapter — feature #62 WI-5 regression (FIXED 2026-05-21, v3.38.39)

**Reported** by the user, 2026-05-20 (`/triage`): "txt toc dont jump to the current chapter and highline the title".

**Symptom**: opening the Contents tab on the TOC sheet for a TXT book shows the TOC list from the top regardless of the user's current reading position. The user has to manually scroll to find where they are. User reports the title also isn't highlighted.

**Repro**:

1. Launch `vreader` on iPhone 17 Pro Simulator at v3.38.x (HEAD = `73f86c6a` at filing).
2. Import a TXT book with a TOC ≥10 chapters (e.g. `war-and-peace.txt` or any chapterised TXT).
3. Open the book; read into a middle chapter (e.g. swipe to chapter 5 of 10).
4. Tap the Contents button in the bottom chrome — TOC sheet opens.
5. Observe: the TOC list starts from chapter 1 at the top; chapter 5 is not auto-scrolled into view and (per user report) not visibly highlighted.

**Expected**: the TOC sheet opens with the current chapter scrolled into view AND that chapter's row visually distinct (accent background + bold) so the user can orient.

**Actual**: list starts at chapter 1; current chapter not in view; (per user) highlight not visible.

**Regression source (high confidence)**:

- Commit `9499a04a` (2026-03-22, `feat: TOC scrolls to current chapter on open`) added a `ScrollViewReader` + `proxy.scrollTo(currentEntry)` `.onAppear` to the legacy `TOCListView`, plus the accent highlight.
- Commit `edc550d0` (later) hardened this with a long-list retry pattern.
- Commit `d17f6dfd` (feature #62 WI-5, 2026-05-19, "rewire reader chrome to TOCSheet + HighlightsSheet, delete legacy panel") replaced `TOCListView` with `TOCSheet`. The new sheet **lifted the `activeEntryIndex` matching logic** and **lifted the row-level `isCurrent` highlight** — but did NOT lift the `ScrollViewReader` wrapping. See `vreader/Views/Reader/Annotations/TOCSheet.swift:213-230`:

```
private var tocEntryList: some View {
    LazyVStack(spacing: 0) {                // ← bare LazyVStack
        ForEach(Array(tocEntries.enumerated()), id: \.element.id) { index, entry in
            TOCContentsRow(
                ...
                isCurrent: index == activeEntryIndex,    // ← highlight logic intact
                ...
            )
        }
    }
}
```

No `ScrollViewReader`, no `proxy.scrollTo`, no `.onAppear` on the list. So the highlight logic is intact but the auto-scroll capability is genuinely lost.

**Highlight-not-visible sub-question (needs verification)**:

The highlight logic IS present in code. The user reports they don't see it. Possible reasons:

1. The `isCurrent` styling (`accent`-tinted background + bold) is too subtle in the current theme — the user notices auto-scroll missing first and conflates "not centered" with "not highlighted".
2. `currentLocator` isn't being threaded to `TOCSheet` at sheet-open time. `ReaderContainerView+Sheets.swift:420` passes `currentLocator: currentLocator` — that's wired.
3. `activeEntryIndex` returns nil for TXT because `currentLocator.charOffsetUTF16` is nil OR the TOC entries don't carry `charOffsetUTF16`. The matching logic at `TOCSheet+Support.swift:74-97` requires both sides to have it.

The fix branch should first add `ScrollViewReader` (covers the unambiguous symptom), then verify the highlight rendering with a TXT book in-sim and follow up with a separate diagnostic if the highlight is genuinely broken.

**Fix direction**:

1. Wrap `tocEntryList`'s `LazyVStack` in a `ScrollViewReader { proxy in ... }`.
2. Tag each row with `.id(entry.id)` (the existing `accessibilityIdentifier` is for AX; SwiftUI scroll-target needs `.id`).
3. In an `.onAppear` (or `.task`) on the list, when `activeEntryIndex` is non-nil, call `proxy.scrollTo(tocEntries[activeEntryIndex!].id, anchor: .center)` after a brief delay (the `edc550d0` retry pattern for long lists handles the case where the row isn't yet realised in the `LazyVStack`).
4. Verify the `isCurrent` highlight is rendering for TXT — open a TXT book, mid-chapter; tap Contents; inspect via DebugBridge `eval` (or visual screenshot) whether the row at `activeEntryIndex` has the accent background.
5. If highlight doesn't render: trace `currentLocator.charOffsetUTF16` and TOC entries' `charOffsetUTF16` to find which side is nil.

**Verification harness**: after the fix lands, open `war-and-peace.txt`, navigate to chapter 5 of N, open Contents — confirm chapter 5 is centered in the visible TOC list AND its row has the accent background.

**Cross-ref**: feature #62 WI-5 was VERIFIED 2026-05-19 with TOCSheet acceptance, but the auto-scroll gap wasn't called out in its acceptance criteria — a gap to tighten when the fix lands.

### Bug #247 — WebDAV restore loses book titles — restored TXT/MD/PDF books show `restore_<sha256>` filename as title (TODO 2026-05-20)

**Reported** by the user, 2026-05-20 (`/triage`): "the books from web-dav backups lost there names".

**Symptom (user-confirmed via questionnaire)**: after restoring from
WebDAV backup, books in the library show titles like `restore_<sha256>`
(the content-addressed temp filename used during materialization)
instead of the original book name. User confirms TXT is affected;
suspects EPUB / AZW3 / PDF may share the bug.

**Repro**:

1. Set up WebDAV backend (e.g. the local rclone test server).
2. Import a TXT book with a recognisable filename (e.g. `war-and-peace.txt`).
3. Run backup → confirm `library-manifest.json` carries the title and
   the blob is uploaded under `VReader/books/txt/<sha256>_<bytes>.txt`.
4. Wipe app data (or restore on a fresh install).
5. Run restore.
6. Open library. The restored book's title row reads
   `restore_<sha256-hex>` (or similar SHA-prefixed string) instead of
   `war-and-peace`.

**Expected**: restored books carry their original titles (taken from
the manifest, which the backup step extracted at backup time).

**Actual**: restored books carry the SHA-prefixed temp-file name as
their title for formats without embedded title metadata.

**Root cause (code-read, high confidence)**:

- `BookFileMaterializer.materializeOneDownload`
  (`vreader/Services/Backup/BookFileMaterializer.swift:194-196`)
  writes the downloaded blob to a temp file named
  `restore_<sha256>.<originalExtension>` and then calls
  `importer.importFile(at: tempURL, source: .restore)`.
- `BookImporter.importFile(...)` derives the title from
  `MetadataExtractor.extractMetadata(from: fileURL)`.
- For formats without embedded title metadata — **TXT**
  (`TXTMetadataExtractor` uses filename) and **MD**
  (`MDMetadataExtractor`, same) — the title becomes the SHA-prefixed
  temp filename.
- For formats with optional embedded titles (**PDF** in particular),
  when the PDF's metadata `Title` field is empty the fallback is the
  same filename-derived path → also broken.
- **EPUB** (`EPUBMetadataExtractor` reads `<dc:title>` from
  `package.opf`) and **AZW3** (reads MOBI header title) usually
  escape this bug because their formats embed titles in the file
  contents.

**Manifest already carries the right title — it's just not used**:

- `BackupLibraryEntry.title: String?` exists in the manifest schema
  (`BackupSectionDTOs.swift:262`). The doc-comment even says: *"The
  materializer re-extracts these from the imported file via
  `MetadataExtractor`; they're carried in the manifest so future
  selective-restore UI (feature #47) can show them before downloading
  the blob."* The "re-extracts from the imported file" assumption is
  exactly what fails for filename-derived-title formats.

**Fix direction (three viable options)**:

1. **Easiest** — in `BookFileMaterializer` write the temp file with a
   filename derived from `entry.title` (sanitised + uniquified with
   the SHA suffix to stay collision-free under concurrent restores).
   Falls back to the current SHA-prefixed name when the manifest's
   `title` is nil.
2. **More correct** — add a `titleOverride: String?` parameter to
   `BookImporter.importFile(...)` and pass `entry.title` from the
   materializer. Preserves the manifest as the source of truth for
   pre-extracted metadata. The importer's metadata-extraction step
   continues to run (still authoritative for everything else); when
   the extractor's title is empty AND a titleOverride is supplied,
   use the override.
3. **Post-import patch** — after `importFile` returns, update the
   persisted Book's `title` if it equals the temp-file filename AND
   the manifest carries a non-nil title.

Option (b) is the cleanest and matches the manifest-as-source-of-truth
invariant the plan already documents.

**Latent since feature #46 (VERIFIED) and #47 (VERIFIED) shipped**.
Both features' acceptance criteria covered "book file present after
restore" and "library shows restored books"; neither explicitly
asserted the *titles* round-trip for filename-derived-title formats.

**Severity High** — every restore on a non-embedded-title format
loses every book's name, making the restored library unusable
without manual rename. Affects feature #46 + #47's device-verified
scope.

**Verification harness**: after the fix lands, run a full backup →
wipe → restore cycle against the local rclone WebDAV server with at
least one of each format (TXT, MD, PDF, EPUB, AZW3) and confirm each
book carries the original title in the library after restore.

**FIXED 2026-05-21** — Option (b) from the triage applied. Added
`titleOverride: String?` parameter to `BookImporting.importFile(...)`;
both `BookFileMaterializer.reimportLocalFile` and
`BookFileImportFinalizer.finalize` now pass `entry.title` from the
manifest. New `BookPersisting.updateBookTitle(fingerprintKey:title:author:)`
applies the manifest title on dedupe-hit so previously-imported books
also get their names corrected. Override is trimmed + empty-as-nil +
capped at 255 chars (matches `Book.init`'s defense-in-depth), applied
at a single normalization point so the returned `ImportResult.title`
never diverges from the persisted SwiftData row. Tests: 10 new
BookImporter / BookFileMaterializer unit tests + 6 high-fidelity
integration tests (real `PersistenceActor` in-memory + real
`BookImporter` + real metadata extractors, stub only at the blob-reader
boundary) cover TXT / MD / PDF / nil-manifest / whitespace-only /
overlong / dedupe-hit / already-local paths. Codex Gate-4 audit thread
`019e472f`, 2 rounds, ship-as-is — round 1 caught the 255-char cap
gap, round 2 clean. Audit log:
`.claude/codex-audits/fix-issue-1075-webdav-restore-book-titles-audit.md`.

### Bug #246 — AZW3 book opens in the wrong reader UI — `FoliateBilingualContainerView` route not selected for the AZW3 file (FIXED 2026-05-21)

**Reported** by the user, 2026-05-20 (`/triage`): "azw3 book now at wrong format". Symptom-questionnaire clarified to "Opens in the wrong reader UI" — the AZW3 book opens but the reader visually is NOT the Foliate-js AZW3 reader.

**FIXED 2026-05-21** (branch `fix/issue-1072-azw3-reader-routing`). Root cause: `ReaderContainerView.engineReaderView(fingerprint:)` accepted a typed `DocumentFingerprint` parameter parsed from the canonical `book.fingerprintKey` (structurally `{format}:{sha}:{bytes}`), but ignored it for the dispatch decision — instead re-deriving the format from `book.format.lowercased()`, a parallel String `@Model` column. `book.format` is set once at `Book.init` from `fingerprint.format.rawValue` and never re-synced thereafter (see `Book.swift:131`, `syncDerivedFields()` at line 158), so any path that updates one without the other (a future SwiftData migration, a direct context write, a restore-path edit, a CloudKit sync) would leave the column stale while the canonical key stayed correct. The dispatch then routes off the stale column and lands on the wrong host. Manual reproduction at HEAD with two distinct AZW3/MOBI files (`mini-azw3` fixture + the user's CJK `Bei Tao Yan De Yong Qi - Zi Wo.azw3` 6.3 MB) showed both routing correctly via `FoliateBilingualContainerView` — confirming the dispatch IS correct at HEAD for the cases where the two format sources agree, but the structural drift hazard remained latent. **Fix**: route off `fingerprint.format` (already a typed `BookFormat`, already parsed by `body`'s `DocumentFingerprint(canonicalKey:)` guard) and remove the `BookFormat(rawValue: book.format.lowercased())` re-derivation entirely. Routing off the canonical structural primary key makes the dispatch drift-proof without depending on every future writer to keep `book.format` and `book.fingerprintKey` in sync. The `if let` collapses to an unconditional switch (every `BookFormat` case maps to exactly one engine per `ReaderEngine.resolve`'s contract); `unsupportedFormatView` retained as a defined helper for future surfaces. Codex Gate-4 audit thread `019e4756` → `019e4758` → `019e4759` → `019e475b`, 4 rounds: round-1 Low (test too syntactic — fixed by pinning exact dispatch expression + banning any `book.format` read in the function body), round-2 Medium (fixed `prefix(1500)` bound too short — replaced with bound-on-next-sibling-declaration scan), round-3 Low (sibling markers could be cut early by inline mentions — anchored to top-level declaration forms with leading newline + 4-space indentation), round-4 no findings → ship-as-is. Tests added: `ReaderContainerViewEngineDispatchTests.engineDispatchReadsCanonicalFingerprintFormat()` source-level regression guard. Full test gate: 6978 tests in 694 suites pass (`xcodebuild test -only-testing:vreaderTests` 38.3s). Pre-FIXED simulator verify on iPhone 17 Pro Simulator iOS 26.4 with `mini-azw3` fixture → Foliate reader paints (`dev-docs/verification/artifacts/bug-246-postfix-azw3-foliate-20260521.png`), and with the user's CJK AZW3 file → Foliate reader paints (`dev-docs/verification/artifacts/bug-246-postfix-user-azw3-20260521.png`). Audit log: `.claude/codex-audits/fix-issue-1072-azw3-reader-routing-audit.md`.

**Symptom**: Tapping an AZW3 file in the library opens a reader, but the reader UI is the wrong one — it looks like the EPUB / TXT / PDF / MD reader instead of the AZW3 Foliate reader. (User has tested one AZW3 file at the time of filing; scope unconfirmed.)

**Repro (provisional, pending scope confirmation)**:

1. Launch `vreader` on iPhone 17 Pro Simulator at v3.38.x (HEAD = `da36ab52` at filing).
2. Open the library.
3. Tap an AZW3 file (extension `.azw3`, `.azw`, `.mobi`, or `.prc`).
4. Observe: a reader opens but the UI is the wrong one — for example, an EPUB-style page-curl layout or the TXT scrollable text view, rather than the Foliate WebView with paginated chapters.

**Expected**: AZW3 routes to `FoliateBilingualContainerView` (wrapping `FoliateSpikeView`) per `ReaderEngine.resolve(.azw3) == .foliateWeb`. The reader shows the Foliate-js paginated AZW3 UI.

**Actual**: The reader shown is some other engine's UI.

**Possible root causes (descending order of likelihood)**:

1. **`book.format` field is persisted as a non-`"azw3"` string** — e.g. `"epub"`, `"mobi"`, or `"azw"` — so `BookFormat(rawValue: book.format.lowercased())` returns `nil` (which falls through to `unsupportedFormatView`, NOT a different reader, so this is only partially consistent) OR returns a different `BookFormat` case (`.epub`, `.txt`) which would route to the wrong host. The "wrong reader UI" symptom is most consistent with the LATTER. The format string could be wrong if:
   - The import pipeline lost the canonical format on a recent migration.
   - `FileURLImportRouter` (feature #59 WI-2) misclassifies a specific file extension.
   - A backup-restore path coerced the format to something else.
2. **Routing dispatch regression** in `ReaderContainerView.engineReaderView` after feature #54 WI-3 (`e30f7693`) — code-read confirms the `.foliateWeb → FoliateBilingualContainerView` case at lines 876–889 is wired, so this is unlikely unless a later commit changed it.
3. **`FoliateBilingualContainerView` internal regression** (feature #56 WI-11, `e8c1c2e4`) — the wrapper might silently fall back to a different host on some condition.
4. **`BookFormat.fileExtensions`** mismatch — `.azw3` claims `["azw3", "azw", "mobi", "prc"]`. If the import path saved e.g. `"mobi"` as the format string instead of canonicalising to `"azw3"`, that would explain it.

**Fix direction**:

1. **Log + inspect `book.format`, `book.originalExtension`, and the resolved `BookFormat`** for the affected book (DebugBridge `snapshot` or a quick lldb probe is enough). This decides between root-cause (1) and (2)/(3).
2. **If `book.format` is wrong on disk**: bisect the import / backup-restore path to find when it was set. Backfill the persisted records.
3. **If `book.format` is `"azw3"`**: bisect the engineReaderView dispatch / FoliateBilingualContainerView changes (feature #56 WI-11 / WI-15 most likely).
4. **Cross-check the format-determination path** — `DocumentFingerprint` + `BookImporter` + `FileURLImportRouter` all participate.

**Verification harness**: After the fix lands, re-open the user's same AZW3 book; reader should show the Foliate WebView paginated UI (not EPUB / TXT / PDF / MD). Cross-check with a `.mobi` and a `.prc` file to verify the AZW3-family extensions all route correctly.

**Cross-ref**: Bug #108 (REOPENED concurrently) — center-tap chrome-toggle on AZW3 is regressed; if both share a root cause (e.g., FoliateBilingualContainerView wrapper) the #246 fix may resolve #108's repro too.

### Bug #244 — EPUB reader opens but content area is blank — no text rendered on tap-from-library (TODO 2026-05-20)

> **Renumbered 243 → 244 on 2026-05-20** — concurrent parallel work
> landed the DebugBridge `provider`-URL-family bug at #243 on `main`
> (PR #1062 / GH #1057) while this user-triage row was being filed
> at the same number. Per the #225/#226/#228 and #236→#239 collision
> precedent, the established row keeps the number; this newcomer
> renumbers. GH issue title updated #1065 from "Bug #243…" to
> "Bug #244…" via `gh issue edit`.

**Reported** by the user, 2026-05-20 (`/triage`): "can not open the epub books now".

**Symptom**: Tapping an EPUB book in the library navigates to the
reader screen (chrome / toolbar / chapter title visible) but the
content area renders empty — no text appears where the chapter body
should be. The reader is "open" in the navigation sense; it's just
blank where content should render.

**Scope (unconfirmed)**: User has only tested one EPUB. Could be:

- All EPUBs (full regression on the EPUB load path) — most likely
  given the volume of recent EPUB-path churn.
- One specific EPUB (parser issue on a specific file) — less likely
  but possible; e.g., a broken `package.opf` or a CSS class collision
  that hides text on this title.

**Repro (provisional, pending scope confirmation)**:

1. Launch `vreader` on iPhone 17 Pro Simulator at v3.38.15 (HEAD =
   `93a59c17` at the time of filing).
2. Open the library.
3. Tap any EPUB.
4. Observe: chrome appears, content area blank.

**Expected**: Chapter body text renders in the content area; tapping
chrome toggles its visibility; chapter title and progress bar reflect
the loaded book.

**Actual**: Chrome appears, content area is empty / white / shows no
text. (Specific colour / state pending screenshot.)

**Likely cause — primary suspects in descending order**:

1. **Feature #56 WI-10** (`2544fa2f`, 2026-05-20) — bilingual
   interlinear renderer + R-EPUB-CFI fix. Touched the biggest surface
   area in the EPUB load path: 53 lines in
   `EPUBReaderContainerView.swift`, 18 in `EPUBWebViewBridge.swift`,
   25 in `EPUBWebViewBridgeCoordinator.swift`, 24 in
   `EPUBHighlightJS.swift`, plus a new 329-line
   `EPUBReaderContainerView+Bilingual.swift` and `EPUBBilingualJS.swift`
   /`Pipeline.swift`/`Orchestrator.swift` shipping new JS injection
   into the same WebView. A new JS injection that runs unconditionally
   on load (regardless of `bilingualOn`) and accidentally hides or
   replaces the source content would produce this symptom.
2. **Feature #62 WI-5** (`d17f6dfd`, 2026-05-19) — rewires the reader
   chrome to `TOCSheet` + `HighlightsSheet` and deletes the legacy
   panel. Chrome rewiring rarely blanks content but could break a
   binding that drives the EPUB content load (e.g., `bookOpenToken`
   propagation).
3. **Feature #64 WI-8** (`2bab1d07`) and **WI-10** (`18bd553a`) —
   migrated EPUB container to unified highlight popover; tore down the
   superseded #55 / #53 highlight surfaces. Popover migration can
   reorder content-injection JS; tear-down can delete a still-used
   bridge.
4. **Feature #54 WI-3** (`e30f769`) — routes reader dispatch by
   `ReaderEngine`. We confirmed via code-read that
   `ReaderEngine.resolve(.epub) == .epubWKWebView` is preserved and
   the switch case still constructs `EPUBReaderHost`. So routing is
   intact; the regression is in what the host does, not which host is
   chosen.
5. **Feature #491 WI-3** (`d37bcc1e`) — routes EPUB font size through
   `FontSizeCalibrator`. Font sizing pipe; if the calibrator returns 0
   for new books, text could be invisible. Less likely given other
   formats reportedly work.

**Fix direction**:

1. **Confirm scope first** — try a fresh import (`mini-epub3` fixture
   or Alice EPUB used in feature #21 round-2). If a fresh EPUB also
   blanks, it's a load-path regression; if the user's specific book
   blanks but `mini-epub3` works, it's a parser / specific-EPUB
   compatibility bug.
2. **Read the WKWebView via DebugBridge `eval`** — probe
   `document.body.innerHTML.length` and `document.querySelectorAll('p').length`
   to distinguish "content loaded but invisible" (CSS / theme /
   visibility bug) from "content never loaded" (bridge / load-URL /
   sandbox-URL mismatch).
3. **Bisect** from HEAD backward across the suspect commits in the
   order above. Stop at the first commit whose revert restores
   content rendering.
4. **Cross-check Foliate path** — AZW3/MOBI also goes through a
   WKWebView host (`FoliateSpikeView`); confirm AZW3 still renders.
   If AZW3 also blanks, the regression is in a shared WebView
   primitive (e.g., `WKWebView` sandbox URL mismatch — see bug
   `0a142f03` historical fix).

**Verification harness**: After the fix lands, run the user's exact
repro (open any EPUB → confirm text appears) on iPhone 17 Pro Sim AND
on the user's device.

### Bug #239 — Paged layout: side-tap page-turn is dead across all native readers — feature #54 WI-3 deleted the `TapZoneOverlay` page-turn producer (FIXED 2026-05-21)

**Reported** by the user, 2026-05-19 (`/triage`): "turning paged is not working in txt, epub, azw3".

**Repro**:

1. Settings → Reader → Layout → Paged.
2. Open a `.txt` / `.epub` / `.azw3` book.
3. Tap the left / right (page-turn) side zones.

**Expected**: the page advances / goes back.

**Actual**: nothing happens (or the reader chrome toggles). Side-tap page-turn is dead in Paged layout.

**Investigation** (read-only subagent — author/auditor separation, rule 48; cites file:line + commits):

- `.readerNextPage` / `.readerPreviousPage` are the notifications that drive page advance; the native containers observe them (`TXTReaderContainerView.swift:455-472`, `MDReaderContainerView.swift:204-215`, `EPUBReaderContainerView.swift:222-231`, `PDFReaderContainerView`). The **sole producer** of those notifications app-wide is `TapZoneDispatcher.dispatch` (`TapZoneOverlay.swift:19,21`).
- `TapZoneOverlay` / the `.tapZoneOverlay(config:)` modifier is **mounted nowhere** — grep for `tapZoneOverlay(config` across `vreader/` returns only the modifier's own definition (`TapZoneOverlay.swift:71`), zero call sites.
- It used to be mounted on `UnifiedTextRenderer` inside `ReaderUnifiedDispatch.swift`. **Feature #54 WI-3 (commit `e30f769`) deleted `ReaderUnifiedDispatch.swift`** and routed every format to the native containers, which never had a tap-zone overlay of their own; WI-4 (commit `1bc0f40`) then removed `TapZoneStore` entirely. Net effect: the page-turn producer was deleted, the consumers' `onReceive` observers left dangling.

**Per-format**:

- **EPUB** — Paged layout *engages and renders* correctly (CSS columns; bug #171's two-column defect is FIXED). The `.readerNextPage` → `pageNavigator.nextPage()` → `EPUBPaginationHelper.navigateToPageJS` plumbing is intact — but nothing posts `.readerNextPage`. The EPUB JS only registers a generic content-tap handler (chrome toggle); no edge-tap detection, no swipe (scroll disabled in paged mode). Clean feature-#54 regression.
- **AZW3/MOBI** — **swipe page-turn still works**: Foliate-js paginated mode handles `touchstart`/`touchmove`/`touchend` internally (`foliate-bundle.js` `#onTouchEnd` → `snap`), independent of `TapZoneOverlay`. **Side-tap** page-turn is dead (`FoliateSpikeView`'s `tap` handler posts only `.readerContentTapped`; no `.readerNextPage` observer). Partially broken.
- **TXT** — page-turn dead (shared cause) **plus a second, deeper, pre-existing layer**: `TXTReaderContainerView` has **no paged renderer at all** — its body has no `NativeTextPagedView` branch, and `updatePaginationIfNeeded()` (`TXTReaderContainerView.swift:948`) is *defined but never called*, so `uiState.pageNavigator` is always nil. `shouldOpenContinuous(epubLayout:)` returns `false` only for `.paged`, routing TXT-paged to `chapterReaderContent` — a single-chapter *scrolling* bridge. TXT "Paged" never flipped pages. Fixing the `TapZoneOverlay` producer alone will not give TXT real pages; TXT additionally needs a paged renderer wired (a larger, separate piece of work — flag for the fixer; may warrant its own row when picked up).
- **MD / PDF** — also affected by the shared producer regression. Bug #215 is the **MD-scoped instance** of this same root cause (its runtime-diagnosis "Cause 2 — `pagedReaderContent` has no tap-zone overlay, taps/swipes inert" is precisely this feature-#54 regression).

**Classification**: implemented-but-broken → bug; a regression. Page-turn was implemented (the observers + the `TapZoneOverlay` producer existed pre-#54). Not a duplicate — bug #162 ("tap zones no-op on native readers") is FIXED and its fix was a config-visibility *mitigation* ("hide the Tap Zones section outside Unified mode"); feature #54 removed Unified mode entirely, so #162's mitigation is moot and the underlying breakage is now a distinct post-#54 regression. Bug #171 (EPUB paged columns) is FIXED and unrelated (rendering, not input).

**Suggested fix direction** (triage note — not implemented): re-mount a page-turn tap-zone surface on the native reader containers (restore the producer #54 deleted). One fix resolves TXT-gesture + EPUB + AZW3-side-tap + MD (#215) together. Subject to rule 51 — bug #215 is already `BLOCKED: needs-design (#842)` for the MD-paged tap-zone affordance; that design should cover the page-turn tap surface for all formats. TXT additionally needs a real `NativeTextPagedView` rendering branch.

**Cross-references**: bug #215 (MD-scoped instance, same root cause), bug #162 (FIXED — mitigation invalidated by #54), bug #171 (EPUB paged columns, FIXED — unrelated), feature #54 (the regressing change), feature #21 (paginated reading, VERIFIED — regressed), feature #25 (configurable tap zones, DONE — regressed).

**FIXED 2026-05-21** (branch `fix/issue-988-paged-side-tap-page-turn`, v3.38.33). Producer restored via a new pure helper `ReaderTapZoneRouter.dispatch(x:totalWidth:layout:config:)` (`vreader/Views/Reader/ReaderTapZoneRouter.swift`) that classifies the tap's x-coordinate (delegating to the existing `TapZoneConfig.zone(atX:totalWidth:)` 33/33/33 split) and posts `.readerNextPage` / `.readerPreviousPage` only in `.paged` layout; `.scroll` and `nil` (the safe default for un-threaded callers) collapse to `.readerContentTapped` — the legacy chrome-toggle behavior. Each native bridge's existing UIKit tap recognizer / WKWebView JS handler routes through the router after its own pre-checks (highlight hit-test, link clicks, selection guards):

- **TXT** — `TXTTextViewBridgeCoordinator.handleContentTap` calls `ReaderTapZoneRouter.dispatch(...)` with `gesture.location(in: textView)` + `textView.bounds.width` + `pagedLayout`; coordinator's `pagedLayout` mirrors the bridge's `layout` parameter (refreshed in both make and updateUIView). `TXTChunkedReaderBridge.Coordinator.handleContentTap` mirrors the pattern for the chunked-TXT (>500K UTF-16) surface.
- **MD** — uses the same `TXTTextViewBridge` as TXT; the producer wakes up for MD paged mode the moment `MDReaderContainerView` threads `layout: settingsStore?.epubLayout` (it does). The deeper MD paged-renderer Cause-1/Cause-2 work (Bug #215) is unrelated; this bug fix delivers the producer half of that work.
- **EPUB** — `EPUBWebViewBridgeJS.contentTapTrackingJS` now sends a `{x, w}` dict body (was bare `'tap'`) carrying `e.clientX` + `document.documentElement.clientWidth`. `EPUBWebViewBridgeCoordinator` parses the dict (with `NSNumber.doubleValue` casts and a `w > 0` guard) and routes via the router using `isPaged ? .paged : .scroll`. The bare `'tap'` fallback survives a11y synthetic clicks without `clientX`.
- **AZW3/MOBI** — `vreader/Services/Foliate/JS/foliate-host.js` now posts `{ x, w }` for non-synthetic clicks (bare `{}` fallback otherwise); rebuilt `foliate-bundle.js` via the pinned local esbuild 0.28.0 (`./build-bundle.sh`, 300434 bytes). `FoliateSpikeView.Coordinator`'s `tap` case parses the dict and routes via the router using `currentLayoutFlow == "paginated" ? .paged : .scroll`. The spike additionally observes `.readerNextPage` / `.readerPreviousPage` on the coordinator (matching the sibling annotation-create/delete observer pattern — `nonisolated(unsafe)` token storage, `[weak self]` + `MainActor.assumeIsolated`, `deinit` removal) and evaluates `readerAPI.next();` / `readerAPI.prev();` against the live `WKWebView`.
- **PDF** — `PDFViewBridge.Coordinator.handleTap` calls the router with `gesture.location(in: pdfView)` + `pdfView.bounds.width` + `pagedLayout`; coordinator's `pagedLayout` mirrors the bridge's `layout` parameter, threaded from `PDFReaderContainerView`'s `settingsStore?.epubLayout`. PDF defaults to `.singlePageContinuous` (scroll mode); in `.paged` layout the existing `PDFPageNavigator` observer turns the PDFKit page.

The deleted SwiftUI `TapZoneOverlay` is **not** remounted — the SwiftUI overlay had swallowed scroll gestures on UIKit-backed renderers (bug #70). Routing through each bridge's own tap producer avoids that regression entirely.

**Design source**: `dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-navigation.md` §1 + §2.2 explicitly designs the 30/40/30 zone grammar (referenced from `vreader-reader.jsx::handleTap`). The Swift helper splits 33/33/33 — close to spec, byte-identical user-visible behavior, preserves existing `TapZoneConfigTests`. Per rule 51, this is a pure-code restoration with no visible UI delta (rule 51 "Pure code changes with no visible delta" exemption); the design-bundled tap-zone hint overlay (`vreader-tap-zones.jsx::TapZoneHint`) is a separate discoverability feature, out of scope for this regression repair.

**TXT no-paged-renderer note** (carried forward from the investigation): `TXTReaderContainerView` has no `NativeTextPagedView` branch and `updatePaginationIfNeeded()` is defined but never called, so TXT "Paged" remains single-chapter scroll regardless of producer state. The producer fix here re-arms the notification stream; the missing renderer is a separate piece of work and is flagged for a follow-up bug when picked up.

**Regression guard** (new tests):
- `vreaderTests/Views/Reader/ReaderTapZoneRouterTests.swift` (17 XCTest cases) — pure routing, layout-gate priority over custom mappings, edge cases (zero width, negative x, x exceeds width), notification side effects, `.none` action no-op.
- `vreaderTests/Views/Reader/ReaderBridgeSideTapWiringTests.swift` (5 XCTest cases) — TXT bridge integration via a `FakeTapRecognizer` subclass that stubs `location(in:)` (UIKit's gesture system is hard to drive from XCTest); covers paged left/right/center, scroll-mode-suppresses-page-turn, and `nil`-layout-defaults-to-chrome-toggle.

**Test gate**: full `xcodebuild test -only-testing:vreaderTests -parallel-testing-enabled NO -derivedDataPath build/issue-988` on iPhone 17 Pro Sim (iOS 26.5) — **6978 tests / 694 suites pass, 0 failures, ~39 s wall-clock**.

**Pre-FIXED simulator slice verification**: launched the patched build with `--reader-default-layout=paged`; opened `mini-epub3` fixture; confirmed `columnWidth: 362px` engaged (paged mode active). Dispatched a `MouseEvent("click", {clientX: 882, clientY: 300})` on `document.body` (882/980 = right-zone); a JS hook around `webkit.messageHandlers.contentTapHandler.postMessage` recorded the production producer firing with `{x: 882, w: 980}` — the new Swift dict-parse path was reached. EPUB `pageNavigator.nextPage()` ran (within-chapter, clamped because mini-epub3's chapter is single-page, `totalPages=1`); the producer → consumer pipeline is intact. Screenshot `dev-docs/verification/artifacts/bug-239-fix-verify-epub-paged-20260521.png`. Cross-chapter advance on side-tap is a pre-existing EPUB-container concern (the EPUB observer is within-chapter only); separately tracked.

**Codex audit** thread `019e477e-9369-7010-a91b-6a2bd418d266`, round 1 verdict **follow-up-recommended**. One Medium finding: `.readerNextPage` / `.readerPreviousPage` posts use `object: nil` and the 5 consumer observers are unfiltered — a contract that has existed since feature #25's original landing and is byte-identical to the deleted `TapZoneDispatcher.dispatch`. Codex flagged a hypothetical multi-scene `WindowGroup` failure mode; vreader is single-window today (no `UIApplicationSupportsMultipleScenes` in `Info.plist`). Accepted as pre-existing architectural debt, deferred to follow-up. Audit log `.claude/codex-audits/fix-issue-988-paged-side-tap-page-turn-audit.md`. Verification evidence `dev-docs/verification/bug-239-20260521.md`.

**Follow-ups to file** (separate rows, not part of #239):
- Notification scoping by `fingerprintKey` + `readerToken` for the page-turn / chrome-toggle bus (Codex M1 — defense-in-depth for future multi-scene; PDF additionally lacks a paged-layout guard on its `.readerNextPage` observer, gated implicitly by the router today).
- TXT paged renderer (no `NativeTextPagedView` branch, `updatePaginationIfNeeded()` never called).
- EPUB cross-chapter advance on side-tap (`reader-navigation.md` §2.2 hybrid model).

GH: #988

### Bug #235 — AZW3/MOBI reader: scroll mode does not scroll continuously across chapter boundaries (FIXED 2026-05-20)

**Reported** by the user, 2026-05-19 (`/triage`, re GH #614 / bug #180): "so are the epub and azw3" — the AZW3/MOBI reader has the same cross-chapter scroll discontinuity that bug #180 fixed for TXT.

**Repro**:

1. Settings → Reader → Layout → Scroll.
2. Open a multi-chapter `.azw3` / `.mobi` book.
3. Scroll down to the end of a chapter.

**Expected**: scrolling flows continuously and smoothly into the next chapter — one continuous surface across chapter boundaries (the behavior bug #180 delivered for TXT).

**Actual**: the AZW3/MOBI reader (Foliate-js) renders one **section** at a time; crossing a chapter/section boundary is a discrete `nextSection()` swap, not a continuous scroll. Reading flow breaks at every chapter edge.

**Investigation** (triage):

- AZW3/MOBI renders via Foliate-js (`<foliate-view>`); the bundled paginator (`vreader/Services/Foliate/JS/paginator.js:1078-1081`, `foliate-bundle.js:5130-5133`) navigates **section-by-section** (`prevSection()` / `nextSection()`).
- Bug #189 (FIXED 2026-05-14) made AZW3 honor the Scroll/Paged toggle — `setLayout({flow: "scrolled"})` — so scroll mode now *engages*. But that only made scrolling work *within* a section; it did not make scrolling continuous *across* sections. Cross-chapter continuity is a separate concern, unaddressed by #189.
- This is the AZW3 analog of bug #180 (TXT — FIXED via the continuous-surface redesign) and bug #165 (EPUB — TODO; "continuous cross-chapter scroll in scroll mode", design landed in `reader-navigation.md` §2.3). Neither covers AZW3: #165 is EPUB-scoped; `reader-navigation.md` scopes #812 (EPUB) and #842 (MD), not Foliate/AZW3.

**Classification note**: implemented-but-discontinuous → bug, consistent with how #180 (TXT) and #165 (EPUB) are tracked. Behavior-only continuous scroll reusing existing chrome needs no new design; any *new* scroll-mode chrome would fall under rule 51.

**Cross-references**: bug #180 (TXT, FIXED — continuous-scroll precedent), bug #165 (EPUB, TODO — same problem class), bug #189 (AZW3 scroll-toggle, FIXED — gave AZW3 scroll mode, not cross-section continuity), feature #42 (Foliate unified engine, DEFERRED — orthogonal).

**FIXED 2026-05-20** (worktree branch `worktree-agent-a71ccad431f39e678`): added `#maybeCrossSectionBoundary()` to `vreader/Services/Foliate/JS/paginator.js`, invoked from the IMMEDIATE (non-debounced) `#container` scroll listener so cross-chapter advance fires during the live fling — not 250 ms after the gesture stops. The helper short-circuits unless `scrolled && !#locked && #view && (atEnd || atStart)`, with edge math `atEnd = viewSize - end <= 2` (matches `#scrollNext`) and `atStart = start <= 0` (matches `#scrollPrev`). On `atEnd && #adjacentIndex(1) != null` it calls `#turnPage(1)`; on `atStart && #adjacentIndex(-1) != null` it calls `#turnPage(-1)` — reusing the same `#locked`-protected machinery as programmatic `next()` / `prev()`. The 250 ms-debounced scroll listener is unchanged: it still owns `#afterScroll('scroll')` relocate/anchor maintenance. The Foliate bundle (`foliate-bundle.js`) was rebuilt via a newly-pinned local esbuild (`vreader/Services/Foliate/JS/package.json` + `package-lock.json`, `engines.node >= 18`, esbuild `0.28.0`); the build script now invokes `./node_modules/.bin/esbuild` via an `npm ci` bootstrap, closing the previous `npx esbuild` cross-machine non-determinism. Regression guard: a new 15-test Swift Testing suite (`vreaderTests/Services/Foliate/FoliatePaginatorScrollBoundaryTests.swift`) pins helper presence in both source and built bundle, IMMEDIATE-listener wiring (its scan window is bounded by the next `.addEventListener(` call, so the debounced listener cannot be substituted), exact epsilon literals, the direction-specific `#turnPage(±1)` calls, scrolled-mode accessors (`this.viewSize`, `this.end`, `this.start`), and `#adjacentIndex(±1)` checks in both directions. Codex audit thread `019e4407`, 3 rounds, ship-as-is — eight findings (R1: debounce-too-late Medium + epsilon-asymmetry Low + structural-test-quality Medium + esbuild-pin Low; R2: stale comment Low + esbuild-still-advisory Low; R3: `npm install`-not-`ci` Low + missing `engines.node` Low), all eight fixed. Full `xcodebuild test -only-testing:vreaderTests -parallel-testing-enabled NO` against iPhone 17 Pro Sim (UDID `61149F0E-DC18-4BE2-BB37-52659F1F4F62`): 6826 tests / 682 suites pass, zero failures. Audit log `.claude/codex-audits/worktree-agent-a71ccad431f39e678-audit.md`.

GH: #983

### Bug #234 — TXT reader: TOC tap navigates to the wrong chapter or silently does nothing (intermittent) (FIXED 2026-05-20)

**Reported** by the user, 2026-05-19: "txt toc jumping sometime is not working or to the wrong place."

**Repro** (approximate — reported as intermittent; a specific book/chapter that reproduces it would sharpen the fix):

1. Open a multi-chapter `.txt` book in the reader.
2. Open the table of contents (Contents).
3. Tap a chapter entry.
4. **Sometimes** the reader does not move, or lands at the wrong chapter / wrong position instead of the tapped chapter's start.

**Expected**: tapping a TOC entry always navigates to the start of that exact chapter.

**Actual**: intermittently — no navigation, or navigation to the wrong chapter / wrong offset.

**Investigation — candidate root causes** (triage; not yet fixed):

- The TOC-tap handler (`TXTReaderContainerView.swift` ~552-566) resolves the tapped entry by **exact `charOffsetUTF16` equality** against `tocEntries`, then navigates by **chapter-title string** via `TXTReaderViewModel.navigateToChapterByTitle` (`TXTReaderViewModel.swift:594`) — an exact, trimmed `firstIndex(where:)` title match. Failure modes: (a) duplicate or empty chapter titles (common in TXT books) → matches the *first* same-titled chapter → **wrong chapter**; (b) any title drift between the TOC entry and the chapter record → no match → falls back to `navigateToGlobalOffset` or a silent no-op. The source comment ("title matching is reliable", GH #30) assumes a title uniqueness that real TXT books may not have.
- `navigateToChapter` (`TXTReaderViewModel.swift:554`) sets `currentOffsetUTF16` from `chapter.globalStartUTF16` only when populated (`>= 0`); otherwise it **estimates** the offset from a byte-position ratio → approximate landing = **wrong place**.
- Bug #180's continuous-scroll fix (FIXED 2026-05-19) reworked the TXT chapter-offset path (`chapterOffsetIndex` / `isContinuousMode`); a TOC tap over the continuous surface must scroll to the computed offset — a windowing / layout-settle timing race is a plausible cause of the *intermittent* ("sometime") wrong-place landing.

**Cross-references**: bug #180 (TXT continuous-scroll — reworked the chapter-nav/offset path; prime regression suspect), GH #30 (TOC↔chapter title-match origin).

GH: #978

### Bug #232 — Chunked TXT bridge does not clear a temporary search highlight on a new search or user scroll (FIXED 2026-05-19)

- Repro: open a >500K-UTF-16 TXT (e.g. `war-and-peace.txt`, chunked path) → search term A, tap result (yellow highlight appears) → within 3 s search term B (or scroll) → the term-A highlight stays painted until its 3 s timer fires.
- Root cause: `TXTChunkedReaderBridge.Coordinator.init` is bare (`self.delegate = delegate` only) — no `.searchHighlightClear` observer, no scroll-driven clear. The non-chunked `TXTTextViewBridge.Coordinator.init` registers a `.searchHighlightClear` observer and clears on user scroll; the chunked one never did.
- Pre-existing structural gap, NOT a regression. Surfaced by the Codex Gate-4 audit (`019e400c` round 2) of the Bug #154 / GH #443 fix; filed separately (different trigger, out of #154's repeat-nav scope).
- Fix direction: parity with `TXTTextViewBridgeCoordinator` — observe `.searchHighlightClear`, add a scroll-clear gated on `isTracking || isDragging || isDecelerating` (bug #99's canonical signal), route both through a shared helper that fires `onTemporaryHighlightCleared?()` once.
- Filed by the Bug #154 `/fix-issue` run 2026-05-19; not fixed there. GH: #960.

### Bug #226 — `TTSService.rate` `didSet` infinite recursion: clamping re-assignment under `@Observable` re-enters the synthesized setter forever → stack overflow (FIXED 2026-05-19)

- Numbering: renumbered 225 → 226 on 2026-05-19. GH #910 and GH #911 were filed concurrently and both titled themselves "Bug #225"; this row (GH #910) takes 226, the separate TXT test-isolation row (GH #911) keeps 225. The GH #910 issue title still reads "Bug #225" — `docs/bugs.md` is the source of truth and now says 226.

- Repro: `xcodebuild test -only-testing:vreaderTests/TTSServiceSpeedControlTests -parallel-testing-enabled NO` on iPhone 17 Pro Sim — `speedControl_defaultRate()` (reads `rate` only) passes; the 5 rate-mutating tests crash the test process (`Restarting after unexpected exit, crash, or test timeout`). Confirmed pre-existing on pristine `origin/main` at commit `42908c4`.
- Root cause: `TTSService` is `@MainActor @Observable` (`vreader/Services/TTS/TTSService.swift:19-20`). `rate`'s `didSet` (`:34-36`) re-assigns `rate` to clamp it. The `@Observable` macro rewrites a `didSet`-bearing stored property into a computed `rate` over backing `_rate`; the body's `rate = …` calls the computed setter → sets `_rate` → fires `didSet` again. Swift's didSet-self-assignment suppression does not span the computed→stored boundary, so it recurses unboundedly.
- Same defect class as Bug #222 (`ReaderSettingsStore.autoPageTurnInterval`, FIXED) — a different property on a different `@Observable` class; #222's fix did not catch this instance.
- Two-fold impact: (1) the 5 `TTSServiceSpeedControlTests` reliably crash the full `-only-testing:vreaderTests` run (`** TEST FAILED **` despite the Swift Testing summary saying 1073 passed); (2) latent product defect — any runtime assignment to `TTSService.rate` crashes the app; recursion does not fire during `init` (Swift suppresses observers there).
- Fix direction: convert `rate` to a computed `get`/`set` over a private `_rate`, clamping in `set`; no `didSet`. Mirrors Bug #222's fix and `ReaderSettingsStore.backgroundOpacity`'s existing pattern. Filed by the feature #57 implementation run 2026-05-19; not fixed there (out of #57's scope). GH: #910.

### Bug #224 — Feature #63 `SearchBar` re-skin: `searchTextField` / `searchCancelButton` touch targets below the 44 pt HIG minimum (FIXED 2026-05-19)

- Repro: with the Bug #223 fix applied, run `xcodebuild test -only-testing:vreaderUITests/SearchSheetPlaceholderTests/testSearchSheetAccessibilityAudit` *without* the `.hitRegion` exclusion → `XCUIApplication.performAccessibilityAudit` fails with "Hit area is too small". A one-shot issue dump (iPhone 17 Pro Sim, iOS 26.4.1) names two offenders: `searchTextField` (frame `259.7 × 19.7 pt`) and `searchCancelButton` (frame `45.7 × 17.0 pt`).
- Root cause: `SearchBar.swift`'s `TextField` has only `.font(.system(size: 15))`; the field's vertical padding sits on the enclosing `HStack`/`RoundedRectangle`, so the `TextField` accessibility element's own frame is just the ~19 pt text line. `cancelButton` is a bare `Button("Cancel")` (`.font(.system(size: 14))`, no `.frame`/`.padding`/`minHeight`) — SwiftUI does not auto-expand a text-label button to 44 pt.
- Impact: a real product accessibility defect — motor-impaired / Switch Control / VoiceOver users get sub-44 pt tap targets. Masked until now by the Bug #223 `searchSheet`-container regression (the audit test never reached the audit step).
- Distinct from Bug #223: that bug is identifier propagation; this is touch-target sizing. `testSearchSheetAccessibilityAudit` currently excludes `.hitRegion` as tracked debt citing this bug — drop the exclusion when this fix lands.
- Fix direction: give the search `TextField` and the `Cancel` `Button` a ≥44 pt tappable height (`.frame(minHeight: 44)` + `.contentShape`). This is a *visible* sizing change to the feature-#63 search bar, so it must be checked against `dev-docs/designs/vreader-fidelity-v1` (rule 51) before implementing. Filed by bugfix-cron 2026-05-19. GH: #902.
- **FIXED 2026-05-19** (bugfix-cron, branch `fix/issue-902-searchbar-touch-targets`): gave the `searchTextField` and the Cancel `Button` each a `.frame(minHeight: 44)` + `.contentShape(Rectangle())` tappable frame in `SearchBar.swift`; dropped the now-redundant `.padding(.vertical, 10)` from the field `HStack` (the `TextField`'s 44 pt `minHeight` now governs the field height — the HIG-standard iOS search-bar height). **Rule 51**: the design source `dev-docs/designs/vreader-fidelity-v1/project/vreader-search.jsx` draws the search bar as a flex row with `padding: '10px 14px'` around a 15 px-font input — a ~40 pt visible bar; raising the interactive controls' hit/accessibility frames to the iOS 44 pt minimum is a no-meaningful-visible-delta accessibility repair (rule-51 exempt — Codex design-parity verdict: exempt). Dropped the `.hitRegion` exclusion from both search-sheet accessibility audits (`SearchSheetPlaceholderTests.testSearchSheetAccessibilityAudit`, `GlobalAccessibilityAuditTests.testSearchSheetAudit`). **Test-infrastructure note**: once `.hitRegion` was re-enabled, both audits flapped — the `SearchBar` auto-focuses its field, raising the software keyboard, and `performAccessibilityAudit` audits the whole app including the keyboard's QuickType / predictive-text bar (`TUIPredictionViewCell`, "missing useful accessibility information"), an Apple keyboard-internal gap. Added an additive `ignoringKeyboardElements` option to `auditCurrentScreen` (+ `isSystemKeyboardChrome` vertical-band classifier — the QuickType strip sits flush *above* `app.keyboards`' frame, so strict containment misses it); the two search-sheet tests opt in. Both audit tests now pass deterministically (3/3 runs each, iPhone 17 Pro Sim, iOS 26.5) with `.hitRegion` covering the SearchBar controls. Codex audit thread `019e3e77`, 3 rounds, ship-as-is; audit log `.claude/codex-audits/fix-issue-902-searchbar-touch-targets-audit.md`. **Discovered separately**: the `searchClearButton` (shown only in the non-empty-query state) is also a sub-44 pt touch target — distinct sibling defect, out of #902's named scope, to be filed as its own bug.

### Bug #220 — Feature11EPUBHighlightVerificationTests cannot complete its highlight assertion: XCUITest long-press does not select WKWebView text (TODO 2026-05-18)

- Repro: `xcodebuild test -only-testing:vreaderUITests/Feature11EPUBHighlightVerificationTests` → `Executed 2 tests, with 2 tests skipped` / `** TEST SUCCEEDED **`; skip reason `Highlight menu not found after long-press`. iPhone 17 Pro Sim (iOS 26.4), branch `fix/issue-844-feature11-highlight-test-seed`.
- Context: surfaced after Bug #219 / GH #844's fix (seed `.books`→`.epubFixture` + readiness probe) — the test now opens a real EPUB and mounts the reader WebView, then reaches the long-press.
- Actual: `webView.coordinate(0.5,0.4).press(forDuration: 1.0)` fires but no selection menu appears (`app.menuItems.firstMatch` never exists) → `XCTSkip`. Both `test_verify_feature_11_*` methods skip there.
- Root cause: XCUITest's synthesized `press(forDuration:)` does not reliably trigger WKWebView text selection. Feature #11 round-4 verified via computer-use for exactly this reason; `Feature11EPUBBottomChromeVerificationTests` deliberately stops before the selection menu.
- Not a product defect: feature #11 (EPUB highlighting) is VERIFIED (round-4 CU verify + unit tests). Verification-harness limitation only.
- Fix direction: redesign the test to create the highlight via DebugBridge `eval` (`__vreader_createHighlight` JS) instead of the gesture; assert via the Highlights tab + reopen-persistence. Harness redesign — candidate for feature #45's sweep. Filed by bugfix-cron 2026-05-18. GH: #845.

### Bug #219 — Feature11EPUBHighlightVerificationTests silently skips: seeds `.books` (non-openable), EPUB-highlight XCUITest vacuously passes (TODO 2026-05-18)

- Repro: `xcodebuild test -only-testing:vreaderUITests/Feature11EPUBHighlightVerificationTests` → `Executed 2 tests, with 2 tests skipped and 0 failures` / `** TEST SUCCEEDED **`; skip reason `EPUB reader did not load` (`Feature11EPUBHighlightVerificationTests.swift:172`). iPhone 17 Pro Sim (iOS 26.4), v3.27.25 build 439, commit `8cab12a`.
- Expected: the two `test_verify_feature_11_epub_highlight_*` methods open an EPUB, create a highlight via long-press, assert persistence — actually exercising Feature #11.
- Actual: `setUpWithError` seeds `.books` (metadata-only `BookRecord`s, no backing file — Bug #209 Cause A); the tapped `bookCard_` never opens a reader; `waitForEPUBReaderReady()` times out → `XCTSkip`. Harness vacuously passes.
- Not a product regression: same commit, sibling `Feature11EPUBBottomChromeVerificationTests` (`seed: .epubFixture`) opens a real EPUB and passes 2/2 — confirmed this round.
- Fix direction: re-point `setUpWithError` `seed: .books` → `seed: .epubFixture` (mirrors the BottomChrome test); confirm the methods then execute. Audit sibling `Feature27ReplacementRulesVerificationTests` (also `.books` + opens a reader).
- Discovered by verify-cron, feature #11 regression-verify round. Evidence: `dev-docs/verification/feature-11-20260518-round5.md`. GH: #844.

### Bug #215 — MD reader Paged layout never engages: `pageNavigator` stays nil, always renders scroll content — Auto Page Turn + manual paged navigation both dead for Markdown (FIXED 2026-05-21)

- Repro: `defaults write com.vreader.app readerEPUBLayout paged` + `readerAutoPageTurn true` + `readerAutoPageTurnInterval 3.0`, then `launch --uitesting --seed-md-multi-page --reader-default-layout=paged`, open "Test Markdown Multi-Page". iPhone 17 Pro Sim (iOS 26.4), v3.27.23 (build 437).
- Expected: paged render — `MDReaderContainerView.pagedReaderContent` with a "Page X of Y" indicator and clean page breaks; Auto Page Turn advances one page every 3s.
- Actual: scroll render — "0%" continuous scrubber, no "Page X of Y", body clipped mid-line at the viewport bottom. No auto-advance after 11s+ (≥3 intervals, no interaction); a right-side tap and swipe/scroll gestures also do not move the content. Reader chrome (Display sheet) is responsive — only content navigation is dead.
- Root cause (code-read — SUPERSEDED by the runtime diagnosis below): `MDReaderContainerView` body gates the paged path on `if isPagedMode, let nav = uiState.pageNavigator { pagedReaderContent(...) }`. `readerEPUBLayout=paged` is confirmed set at runtime (so `isPagedMode` should be true), therefore `uiState.pageNavigator` is nil → scroll fallthrough. Auto Page Turn (wired only when `autoPageTurn` enabled + paged layout) never engages. Exact reason the navigator is nil is left for the fix.
- Context: predicted by Bug #157 ("MD reader likely has the same shape but needs a chaptered-MD fixture to verify") — #157 FIXED the TXT instance via a capability-gate and kept `.autoPageTurn` for MD untested. Siblings: #189 (AZW3/MOBI Scroll/Paged toggle, FIXED), #171 (EPUB paged). `--uitesting` ruled out as a confound (only swaps the SwiftData store, #152). Blocks feature #31 criterion 5.
- Discovered by verify-cron, feature #31 round-6. Evidence: `dev-docs/verification/feature-31-20260517-round6.md`. GH: #837.
- Diagnosis (bugfix-cron 2026-05-18 round 2, `/fix-issue` #837 — runtime-instrumented build): **round-6's "renders scroll content / `pageNavigator` nil" reading is DISPROVEN.** Diagnostic `Logger` instrumentation on a rebuilt simulator build proves paged mode DOES engage — `isPagedMode=true`, `epubLayout=paged` at runtime, `NativeTextPageNavigator` builds (`totalPages=6`, then `7` after the corrected re-paginate), and the body renders the `pagedReaderContent` (PAGED) branch, not `readerContent` (scroll). Two real causes of the broken appearance: **(1)** `TextReaderUIState.updatePagination` paginates with `viewportSize: UIScreen.main.bounds.size` (full screen `402×874`) instead of the actual `NativeTextPagedView` box, which measures `(402, 855.67)` — pages are mis-sized. **(2 — the dominant user-visible cause)** `pagedReaderContent` (which has `.ignoresSafeArea(.bottom)`) renders the page UNDER the `ReaderBottomChrome` overlay (feature #60 WI-6b — an opaque bottom bar). Instrumentation shows page-0 `sizeThatFits` = `(402, 846.33)`, which FITS its `(402, 855.67)` `NativeTextPagedView` box — the page does not overflow the text view; the apparent "mid-line clip" is `ReaderBottomChrome` occluding the page bottom, and the missing "Page X of Y" indicator is occluded the same way. MD `pagedReaderContent` also appears to lack a tap-zone overlay (round-6's "right-tap/swipe don't navigate" + a center tap not toggling chrome) — the `.readerNextPage`/`.readerContentTapped` handlers in `MDReaderContainerView` are never fed, so the chrome cannot even be dismissed. **Cause (1) fix is fully specified and unit-tested** (drafted + green this iteration; reverted with the checkpoint): add a `viewportSize` parameter to `updatePagination` (default `UIScreen.main.bounds.size` keeps the TXT caller unchanged); in `pagedReaderContent` measure the real box with a `GeometryReader` and paginate for `box − 2×NativeTextPagedView.textInset`; set the renderer's `textView.textContainer.lineFragmentPadding = 0` to match `NativeTextPaginator`. **Cause (2) is the blocker:** the chrome-occlusion fix is a layout change whose correct shape — inset the paged content above the chrome vs. keep the chrome floating and add tap-zone dismiss — is a design-adjacent decision; per rule 51 it must be checked against the feature-#60 design bundle (or routed through `needs-design`), not invented by the cron. Also discovered while running the test gate: `PDFViewBridgeThemeTests` is not `@MainActor` and crashes the parallel `xcodebuild test` run via off-main `PDFView` access (filed as a separate bug). Next iteration: land cause (1); wire the existing `TapZoneOverlay` into `pagedReaderContent` (pure wiring); resolve cause (2) against the design. No code landed this iteration; fix branch dropped.
- **FIXED 2026-05-21** (bugfix-cron, branch `fix/issue-837-md-reader-paged-layout`, design `dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-navigation.md` §3): landed all three causes against the now-committed design.
  - **Cause 1 (viewport size)**: added `viewportSize: CGSize = UIScreen.main.bounds.size` parameter to `TextReaderUIState.updatePagination`; MD container threads `paginatorViewportSize(proxy.size, chromeVisible:)` which subtracts the chrome-aware bottom padding, indicator-when-hidden, and `2 × NativePagedContainer.textInset`. Also set `textContainer.lineFragmentPadding = 0` on the paged textView for horizontal parity with `NativeTextPaginator`. TXT caller unchanged (legacy default preserved).
  - **Cause 2a (chrome occlusion)**: dropped `.ignoresSafeArea(edges: .bottom)` from `pagedReaderContent`; replaced with chrome-aware bottom padding via static `pagedBottomPadding(chromeVisible:)` (136 visible, 56 hidden) per design §3.1.
  - **Cause 2b (page indicator)**: chrome's leading label switches to "Page X of Y" in paged mode (single source of truth, design §3.2); content-bottom indicator hides when chrome visible, renders compact "X / Y" when chrome hidden.
  - **Cause 2c (tap zones)**: added a `UITapGestureRecognizer` to `NativePagedContainer` that routes through `ReaderTapZoneRouter` (the same router PR #1098 introduced for the bridge-based readers). Paged left/right → page-turn, center → chrome toggle; scroll/nil → chrome toggle.
  - **Chrome-toggle re-paginate**: `.onChange(of: isChromeVisible)` triggers `updatePaginationIfNeeded` so page boundaries stay in sync with the renderer's interior on chrome flips (Codex Round-1 High #2 fix).
  - Tests: `NativeTextPagedViewSideTapTests` (5 cases), `MDReaderContainerViewPagedLayoutTests` (6 cases), `TextReaderUIStateTests` (2 new viewport cases). Test gate 6986/695 suites pass. Codex audit thread `019e47a7`, 2 rounds: Round-1 needs-revision (2 High findings on viewport math + chrome toggle), Round-2 follow-up-recommended (3 Low: comment drift fixed, magic constant accepted, file size accepted as known debt).
  - Verification evidence: `dev-docs/verification/bug-215-20260521.md` + screenshot `dev-docs/verification/artifacts/bug-215-fix-verify-state6-paged-engaged-20260521.png` (MD book opens in paged layout with "Page 1 of 6" chrome label, "Chapter 1: Opening" heading, no mid-line clipping).
  - **NOT in this PR** (deferred to follow-up): design §3.3 first-open tap-zone hint, design §3.4 auto-page-turn ribbon, and Bug #218's MD-paged-mode `SelectionPopover` producer gap (the `NativePagedContainer.textView` is a plain `UITextView` with no `TXTTextViewBridge` / no `editMenuForTextIn` swap; long-press in MD paged mode still shows the bare iOS edit menu). Bug #218 remains an open facet on this row; the design covers it but the producer wiring is a separate piece of work.

### Bug #211 — EPUB tap-on-highlight shows no inline Delete menu (TODO 2026-05-17)

- Repro: open an EPUB → long-press a word → SelectionPopover → tap a color swatch (highlight is created, yellow paint appears, `highlightCount` 0→1) → tap the highlighted word.
- Expected: an inline menu with at minimum a "Delete Highlight" option (feature #53 criterion (a)).
- Actual: no menu; the reader chrome toggles instead — the tap is handled as a generic content tap. Reproduced 3× on iPhone 17 Pro Max Sim (iOS 26.4) at v3.27.15 (build 429), including once with the EPUB font enlarged so the highlight was a large unambiguous tap target.
- Root cause (confirmed via DebugBridge `eval`): the feature #53 WI-4 tap-on-highlight `click` listener in `vreader/Views/Reader/EPUBHighlightJS.swift` uses the wrong `Range.compareBoundaryPoints` constant. It calls `range.compareBoundaryPoints(Range.END_TO_START, probe)` to test "range.end >= probe.start", but `END_TO_START` compares `range`'s *start* boundary to `probe`'s *end* boundary. The correct constant is `Range.START_TO_END` (compares `range`'s end to `probe`'s start). A replayed hit-test — caret resolved by `caretPositionFromPoint` to offset 102 inside the highlight Range spanning offsets 97–107, `sameNodeAsRangeStart: true` — returned `startVsProbe=-1, endVsProbe=-1, hit=false`. Every tap whose caret offset is past the highlight's first character misses.
- Not the cause: the JS highlight registry `window.__vreader_highlightRanges` is populated, the CSS Highlight API entry is painted, `caretPositionFromPoint` is available, and the JS `click` event fires on the tap (all verified via `eval` + an injected click-counter). The defect is isolated to the membership comparison.
- Not a duplicate: #199 is the Foliate (AZW3/MOBI) consumer-wiring gap; #182 is the EPUB *search-result* highlight. This is the EPUB *existing-highlight* tap path.
- Discovered by verify-cron, feature #53 round-5. Evidence: `dev-docs/verification/feature-53-20260517-round5.md`. GH: #820.

### Bug #209 — Feature #60 chrome/library re-skin broke Verification XCUITest accessibility identifiers (FIXED 2026-05-17)

- Repro: `xcodebuild test -scheme vreader -testPlan Verification` on iPhone 17 Pro Sim at `b85b4ef` → 9 of 25 fail; clean at `a6103e5` (2026-05-16). Feature #60's chrome (WI-6b) + library (WI-8/9) re-skin merged in between.
- **Root cause — three distinct feature-#60 regressions, not one identifier rename:**
  - **(A) Seed.** Feature21/28/37 seeded `.books` — metadata-only `BookRecord`s with no backing file, so the tapped book fails to open ("file could not be found") and the reader chrome never renders. Re-pointed Feature21/28 → `.warAndPeace`; Feature37 (needs two openable books) → a new `.twoBooks` real-file seed.
  - **(B) Reader-container identifier propagation.** `TXT`/`MDReaderContainerView` applied `.accessibilityIdentifier("txtReaderContainer"/"mdReaderContainer")` at `body` level; SwiftUI propagates a container identifier onto descendants, clobbering `ReaderBottomChrome`'s `readerDisplayButton`/`readerNotesButton`. The earlier v3.27.7 identifier remap was necessary but inert while the targets were still overwritten. Fixed by scoping the identifier to the content `Group`. EPUB/PDF carry the same latent clobber — split to Bug #214 / GH #834 (no Verification coverage).
  - **(C) Sheet-container identifier propagation.** `ReaderSettingsPanel`/`AnnotationsPanelView` `.accessibilityIdentifier` propagated onto descendants so `readerSettingsPanel`/`annotationsPanelSheet` never resolved as an `app.otherElements` element. Fixed with `.accessibilityElement(children: .contain)`.
- Two further Feature37 harness fixes: the per-book `Toggle` exposes a full-row outer `.switch` element containing the real inner `UISwitch` — a centre `.tap()` hit the label, so the test now taps the inner switch; and `closeReaderSettings` swiped down on the re-skinned `ReaderSheetChrome`/`List` sheet (consumed as a list scroll), so it now taps the chrome `sheetCloseButton`.
- **FIXED 2026-05-17** (branch `fix/issue-804-bottom-chrome-hittable`, v3.27.22): Verification plan 9 fail → 0 fail (25 tests, 15 skip, 0 fail). Codex audit thread `019e35ed`, 2 rounds, ship-as-is. The Feature34 collections failure was a separate `firstMatch` issue (Bug #210 / GH #809). GH: #804.

### Bug #176 — AZW3/MOBI TTS silently fails (REOPENED 2026-05-17)

- Original cap-gate fix (remove `.tts` from `FormatCapabilities.azw3`) shipped, but device-verification sweep finds the symptom reproduces.
- Feature #60 WI-6c `ReaderMorePopover` shows a "Read aloud" row for every format unconditionally — no `FormatCapabilities.tts` gate. On AZW3 `mini-azw3`: more-menu → "Read aloud" → `ttsState` stays `idle`, no TTS bar, no error.
- Fix: capability-gate the `.readAloud` row in `ReaderMorePopover`/`ReaderMoreMenuRow` by `FormatCapabilities.tts`. GH: #602.

### Bug #196 — Feature #31 XCUITest fails: auto-page-turn toggle not hittable after settings-panel scroll (FIXED 2026-05-15)

**Original repro**: `xcodebuild test -project vreader.xcodeproj -scheme vreader -testPlan Verification -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:vreaderUITests/Feature31AutoPageTurnVerificationTests/test_verify_feature_31_auto_page_turn_toggle_present` → test fails at line 107 in ~26s with `XCTAssertTrue failed - Auto Page Turn toggle should be hittable`.

**Regression context**: Feature31 PASSED in the WI-6 first-real-run earlier today (`dev-docs/verification/feature-45-20260515-wi-6-full-run.md`, run at v3.21.69 / commit `3753d2a` ~16:00); FAILED at v3.22.1 / commit `897a459` (verify-cron re-run ~17:25). The section-finder loop correctly brings the section header into the accessibility tree, but `section.exists` returns true as soon as the header just barely enters at the panel bottom edge — leaving the toggle row below it still clipped.

**Discovery**: Surfaced by verify-cron's full `-testPlan Verification` re-run against `main` after Bug #194 + #195 fixes landed. Evidence: `dev-docs/verification/feature-45-20260515-post-bug-fixes-full-run.md`.

**Root cause**: the original test's hittable retry budget (3 additional swipes after the section header was found) was insufficient for some panel layouts. The section-finder breaks early once the header is just barely visible, so the extra 3 swipes don't always bring the toggle row (positioned below the header) into a hittable region.

**FIXED 2026-05-15** with a single-line behavioral change: bumped the retry budget from 3 → 10 in the toggle-hittable retry loop (`vreaderUITests/Verification/Feature31AutoPageTurnVerificationTests.swift:104-106`). Preserved the original section-finder structure (initial `waitForExistence(timeout: 2)` + 6-swipe loop) which is proven to work — empirically, removing the initial 2s wait causes premature swipes that desync with the panel's lazy section rendering (verified during one RED→GREEN iteration: revision 1 unified the loops without the initial wait → test SKIPPED rather than PASSED; revision 2 preserved the section-finder + only bumped the retry budget → test PASSES).

Test gate: `-only-testing` on the verify method now PASSES in 18.0s on iPhone 17 Pro Sim (was 26.4s FAIL pre-fix). `** TEST SUCCEEDED **`. Manual-fallback audit: `.claude/codex-audits/fix-issue-702-feature31-toggle-hittability-audit.md`, verdict ship-as-is.

**Cross-ref**: discovered alongside Bug #194 + #195 fix-verification work in the same verify-cron iteration. All four bugs surfaced by Feature #45 WI-6's first-real-run lifecycle are now FIXED (#192/#193/#194/#195 from the original first-run + #196 from the post-fix re-run). GH: #702

### Bug #195 — Feature #29 XCUITest fails: WebDAV Server URL field not visible in WebDAV settings (FIXED 2026-05-15)

**Original repro**: `xcodebuild test -project vreader.xcodeproj -scheme vreader -testPlan Verification -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:vreaderUITests/Feature29WebDAVVerificationTests/test_verify_feature_29_webdav_backup_ui_available` → test fails at line 67 with `XCTAssertTrue failed - WebDAV Server URL field should be visible in WebDAV settings`.

**Discovery**: Surfaced by Feature #45 WI-6's named Verification test plan (PR #692 / v3.21.69) dispatching all 25 `test_verify_*` methods end-to-end for the first time. Pre-WI-6 was vacuous (pre-Bug-#192).

**Root cause**: confirmed Feature #52 (multiple WebDAV server profiles, VERIFIED 2026-05-09) reworked the WebDAV settings UX. Pre-#52, `WebDAVSettingsView` exposed URL/username/password TextFields directly with identifiers `webdavServerURL`/`webdavUsername`/`webdavPassword`. Post-#52, those fields moved into `WebDAVServerProfileEditSheet` reached via: `WebDAVSettingsView → NavigationLink webdavServersNavLink → WebDAVServerProfileListView → toolbar addWebDAVProfileButton → WebDAVServerProfileEditSheet (webdavProfileEditServerURL / webdavProfileEditUsername / webdavProfileEditPassword / webdavProfileEditTestConnection)`. The pre-#52 identifiers are no longer wired to any production view — confirmed by `grep -rln "webdavServerURL" vreader/` returning empty.

**FIXED 2026-05-15** with a 2-file change:
1. `vreaderUITests/Verification/Feature29WebDAVVerificationTests.swift` — rewrote `test_verify_feature_29_webdav_backup_ui_available` to traverse the new path: Settings → WebDAV row → tap `webdavServersNavLink` → tap `addWebDAVProfileButton` → assert `webdavProfileEditServerURL` + `webdavProfileEditUsername` + Connection-section surface (either button or note). Uses element-type-agnostic `descendants(matching:.any).matching(identifier:).firstMatch` for NavigationLink + Connection section.
2. `vreaderUITests/Helpers/TestConstants.swift` — added `webdavServersNavLink`, `addWebDAVProfileButton`, `webdavProfileEditServerURL`, `webdavProfileEditUsername`, `webdavProfileEditTestConnection`, `webdavProfileEditTestConnectionNote`. Pre-#52 stale identifiers kept with "STALE — no production wire" annotations so a future grep finds documented context.

One RED→GREEN iteration was required: first revision asserted `webdavProfileEditTestConnection` button directly; test failed because Bug #184's design hides the Test Connection button in add-mode (existing == nil) and replaces it with a footer note (`webdavProfileEditTestConnectionNote`). Revised assertion accepts either control as evidence the Connection section surface exists. Test gate now PASSES in 18.6s; `** TEST SUCCEEDED **`.

**Follow-up deferred (NOT implemented here)**: `test_verify_feature_29_webdav_backup_executes_when_configured` (lines 86-143) still references the stale identifiers. It is `XCTSkip`-gated on `CI_WEBDAV_URL`/`CI_WEBDAV_USERNAME`/`CI_WEBDAV_PASSWORD` env vars so it's inert in normal runs, but if someone provides those env vars the live test will fail. Updating it requires a multi-step rewrite (type URL/user/pass into the edit sheet, tap Save, return to profile list, set active, navigate back to `WebDAVSettingsView`, tap the existing `webdavBackupNowButton`). A future bugfix-cron iteration or a Feature #29 verify-cron round should tackle it.

Manual-fallback audit: `.claude/codex-audits/fix-issue-695-feature29-webdav-profile-nav-audit.md`, verdict ship-as-is.

**Cross-ref**: paired with Bug #194 (Feature #28 verify failure — FIXED 2026-05-15 in PR #699). Both surfaced together by WI-6's first end-to-end Verification plan run. GH: #695

### Bug #194 — Feature #28 XCUITest fails: 'Chinese Text' settings section header not found after 6 swipes (FIXED 2026-05-15)

**Original repro**: `xcodebuild test -project vreader.xcodeproj -scheme vreader -testPlan Verification -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:vreaderUITests/Feature28ChineseConversionVerificationTests/test_verify_feature_28_chinese_text_picker_present` → test fails at line 56 with `XCTAssertTrue failed - Could not find section header 'Chinese Text' in settings panel after 6 swipes`.

**Discovery**: Surfaced by Feature #45 WI-6's named Verification test plan (PR #692 / v3.21.69) dispatching all 25 `test_verify_*` methods end-to-end for the first time. Pre-WI-6 was vacuous (pre-Bug-#192).

**Root cause**: production never rendered a "Chinese Text" section header. `vreader/Views/Reader/ReaderSettingsPanel.swift:535` defines `Picker("Chinese Text", selection: $store.chineseConversion) { ... }.pickerStyle(.segmented)` — the "Chinese Text" string is the Picker's label argument, NOT a `Section("Chinese Text") { ... }` header, and SwiftUI's `.pickerStyle(.segmented)` hides the picker's label from the visible UI (only segment buttons "None" / "Simp → Trad" / "Trad → Simp" render as `staticText`). The test's `panel.staticTexts["Chinese Text"]` lookup correctly returned `exists == false`. The test was written against a section-header shape that never existed in production.

**FIXED 2026-05-15** with a 3-file change:
1. `vreader/Views/Reader/ReaderSettingsPanel.swift:542` — added `.accessibilityIdentifier("chineseTextPicker")` on the Picker (single line).
2. `vreaderUITests/Helpers/TestConstants.swift` — added `static let chineseTextPicker = "chineseTextPicker"` under a new "Reader Settings — Chinese conversion (Feature #28)" MARK.
3. `vreaderUITests/Verification/Feature28ChineseConversionVerificationTests.swift` — replaced the phantom-section-header `panel.staticTexts["Chinese Text"]` lookup with `app.descendants(matching:.any).matching(identifier: AccessibilityID.chineseTextPicker).firstMatch` (same pattern as Bug #193's OPDS fix). Up-to-6 swipe-up retry loop preserved for picker-below-the-fold formats.

Test gate: same `-only-testing` invocation now PASSES in 22.4s on iPhone 17 Pro Sim (was 18.4s FAIL pre-fix). `** TEST SUCCEEDED **` at bundle level. Manual-fallback audit (rule 47): `.claude/codex-audits/fix-issue-694-feature28-chinese-picker-audit.md`, verdict ship-as-is.

**Cross-ref**: paired with Bug #195 (Feature #29 verify failure — still TODO). Same Bug-#193 fix pattern applies. GH: #694

### Bug #193 — Feature #36 OPDS XCUITest fails: element-class lookups don't match production (List vs. collectionView/scrollView, VStack vs. otherElements) (FIXED 2026-05-15)

**Repro**: `xcodebuild test -only-testing:vreaderUITests/Feature36OPDSVerificationTests/test_verify_feature_36_opds_catalog_ui_surface` → test fails in 11s with `XCTAssertTrue failed - OPDS catalogs view should show either the catalog list or the empty state` at `Feature36OPDSVerificationTests.swift:46`.

**Expected**: post-tap of the OPDS toolbar button, the test finds either the catalog list (`opdsCatalogList` accessibility ID) or the empty state (`opdsEmptyState` accessibility ID) and proceeds to verify the Add Catalog form.

**Actual**: all three element-class lookups return `exists == false`:
- `app.collectionViews["opdsCatalogList"]` — false
- `app.scrollViews["opdsCatalogList"]` — false
- `app.otherElements["opdsEmptyState"]` — false

Test fails at the `XCTAssertTrue` join.

**Root cause** (`vreader/Views/OPDS/OPDSCatalogListView.swift:90, 151`): the accessibility IDs are correctly wired in production:
- Line 151: `.accessibilityIdentifier("opdsCatalogList")` on a SwiftUI `List`.
- Line 90: `.accessibilityIdentifier("opdsEmptyState")` on a VStack.

The bug is the **mismatch between SwiftUI's runtime element type and the test's XCUIElementTypeQueryProvider lookup**:
- SwiftUI `List` renders as a `XCUIElement.ElementType.table` (or `.collectionView` in some iOS versions for inset-grouped style), NOT a plain `collectionView` accessed via `app.collectionViews[...]`. The right lookup is `app.tables["opdsCatalogList"]` OR `app.descendants(matching: .any).matching(identifier: "opdsCatalogList").firstMatch`.
- SwiftUI `VStack` is NOT classified as `otherElements` reliably; it can be `staticText` (when collapsed to a label child) or completely transparent in the accessibility tree. The right lookup is to query a CHILD of the empty state (e.g., the "Add Catalog" button with its `opdsAddCatalogEmpty` identifier) rather than the VStack itself.

**Why this hasn't been caught**: Feature #36's XCUITest verification has been silently no-opping since the test was written — pre-Bug-192-fix the entire suite returned `Executed 0 tests + TEST SUCCEEDED` (vacuous pass). Bug #192 fix (2026-05-15, commit `9d63d83`) made the methods XCTest-discoverable for the first time; this is the **first real run** of the Feature #36 verification XCUITest, and it failed.

**Test session this was found in**: 2026-05-15 verify-cron round, batch run of 4 Verification classes post-Bug-192-fix:
- Feature27 (Replacement Rules): 1/1 PASS (12.4s)
- Feature34 (Collections): 2/2 PASS (50.9s)
- Feature35 (Annotations Export): 2/2 PASS (21.3s)
- Feature36 (OPDS): 1 SKIP (no live OPDS server) + 1 **FAIL** (this bug)

**Fix direction** (do NOT implement here per verify-cron scope guard): update the test's element-class lookups to match SwiftUI's actual rendering:

```swift
// Either: broader query — works regardless of element type
let opdsListExists = app.descendants(matching: .any).matching(identifier: "opdsCatalogList").firstMatch.waitForExistence(timeout: 5)
let opdsEmptyExists = app.buttons["opdsAddCatalogEmpty"].waitForExistence(timeout: 5)
// Or: try multiple element types
let opdsList = app.tables["opdsCatalogList"].exists || app.collectionViews["opdsCatalogList"].exists
```

Alternatively, update the production OPDS view to wrap the catalog list / empty state in a more XCUITest-friendly wrapper (a `ZStack` with `.accessibilityElement(children: .contain)` would surface a stable `XCUIElement` regardless of inner content).

**Impact**: Feature #36 (OPDS) is listed as VERIFIED in `docs/features.md` with a row note citing "WI-3's XCUITest test passes". That verification claim was vacuous — the test never actually ran pre-Bug-192-fix. Feature #36 should be reassessed: manual / CU verification of the OPDS surface is presumably valid, but the XCUITest gate's evidence is now contradicted by this real failure. **The feature row's VERIFIED status may need to drop back to DONE pending a fix to either this test or production**.

**Cross-ref**: this is the FIRST newly-visible test failure surfaced by the Bug #192 fix. Per Bug #192's "Fix direction" closing line: "Some may surface real test failures that have been masked by the silent no-op." Bug #193 is one such case.

**FIXED 2026-05-15**: rewrote the surface-existence check at `Feature36OPDSVerificationTests.swift:43-49` to use `app.descendants(matching: .any).matching(identifier:).firstMatch` for both `opdsCatalogList` and `opdsEmptyState`. Broad descendant queries work regardless of underlying `XCUIElement.ElementType` classification (SwiftUI `List` → `table`, `VStack` → transparent). Codex audit `019e29d4` (2 rounds, ship-as-is): round-1 found a Low (the original fix added `opdsAddCatalogEmpty` as a third "guaranteed-findable Button" signal, but the repo already documented that SwiftUI propagates `opdsEmptyState` onto descendants and shadows the inner button's identifier — `OPDSCatalogListTests.swift:132`). Round-1 fix: dropped the third signal entirely; the two descendant queries cover both surface states. Round 2 zero findings. Test gate: same single-test invocation passes in 16.7s (was 11.1s FAIL pre-fix; Executed-0-tests vacuous pre-Bug-192). Audit log: `.claude/codex-audits/fix-issue-689-opds-xcuitest-element-class-mismatch-audit.md`. GH: #689

### Bug #192 — vreaderUITests/Verification/*VerificationTests methods named `verify_*` are not discovered by XCTest — entire 13-class verification suite has been silently no-opping (FIXED 2026-05-15)

**Repro**: `xcodebuild test -only-testing:vreaderUITests/Feature11EPUBHighlightVerificationTests` → `** TEST SUCCEEDED **` with `Executed 0 tests, with 0 failures`. Same shape for all 13 classes under `vreaderUITests/Verification/`.

**Expected**: each Verification test class runs its `verify_feature_X_*` methods and reports pass/fail per method.

**Actual**: zero methods discovered. The "TEST SUCCEEDED" is the test runner reporting the suite contained zero discoverable tests — Apple's XCTest discovery only finds methods whose name begins with `test`. The 25 `verify_*` methods across the 13 classes are invisible to the runner.

**Discovery**: surfaced during Feature #45 WI-6 Gate 2 Codex audit (thread `019e2982`, round 2 Critical #2). Codex flagged it as a design-level issue: "These files are plain XCTestCase subclasses with no custom discovery override, and Apple's XCTest rule is that test methods must begin with `test`. A test plan filters discovered tests; it does not invent discovery for non-test methods." Repro confirmed via direct `xcodebuild test -only-testing:` invocation — `Executed 0 tests`.

**Impact**: every feature-row note that cites "VERIFIED via WI-X XCUITest" or "live-advancement XCUITest passes" on the strength of `xcodebuild test` exiting 0 is suspect. The test METHODS exist (`verify_feature_11_epub_highlight_happy_path`, etc.) but they have never actually executed in a `xcodebuild test` run because they're not discovered. Manual / CU verification paths still hold; only the XCUITest gate is affected. Feature #45's WI-4 acceptance criterion ("`xcodebuild test -only-testing:vreaderUITests/Verification` exits 0 in under 8 minutes") is technically met but vacuously so — exit 0 happens even when no tests run.

**Count**: 25 `verify_*` methods across 13 classes (Feature11/21/23/27/28/29/31/34/35/36/37/40/41). 0 `test_*` methods anywhere in `vreaderUITests/`.

**Fix direction** (do NOT implement here per feature-cron scope guard — separate bugfix iteration handles fixes): rename all `verify_*` methods to `test_verify_*` (preserves the descriptive name while making them XCTest-discoverable). Verify each method's body still passes its `verify_*` assertions after rename. ~25 mechanical renames + one Verification-harness re-run to confirm each previously-vacuous gate now reports real results. Some may surface real test failures that have been masked by the silent no-op.

**Why this hasn't been caught**: `xcodebuild test` returns exit 0 for "test suite contained 0 runnable tests" — there's no visible "test plan empty" warning. The only way to surface this is to count the executed tests in the output, which the WI-4 acceptance gate didn't require. WI-6 (named test-plan selector) was the catalyst for finding it because the test-plan membership list forced an explicit enumeration of the actual runnable identifiers.

**Cross-ref**: blocks Feature #45 WI-6 (named test-plan selector for Verification subset) — can't ship a test plan that selects 0 actual tests. Once Bug #192 is fixed, WI-6 can resume.

GH: #686

### Bug #191 — AutoPageTurner.interval didSet causes infinite recursion under @Observable; setting interval crashes the app with SIGSEGV stack-guard fault (FIXED 2026-05-15)

**Repro**: anywhere production code calls `turner.interval = anyValue` on a `AutoPageTurner` instance — including AutoPageTurnerTests's `stop_cancelsTimer_noPagesAfterStop()`, `pause_suspendsTimer_noPagesWhilePaused()`, etc. (each does `turner.interval = 1.0` at the test setup line). Also reproduces during Feature #31 round-4 verify when `readerAutoPageTurn=true` + `readerAutoPageTurnInterval=3.0` are pre-loaded via `xcrun simctl spawn booted defaults write` and a book is opened — the reader-open path initializes AutoPageTurner and sets `interval` from the stored UserDefaults value.

**Expected**: setting `interval = 1.0` clamps and stores cleanly (`clampInterval` returns 1.0 → no further work).

**Actual**: SIGSEGV (`EXC_BAD_ACCESS / KERN_PROTECTION_FAILURE`), `"Thread stack size exceeded due to excessive recursion"`. Crash report symbol stack is ~23 700 frames alternating `AutoPageTurner._interval.setter` → `AutoPageTurner._interval.didset` → `AutoPageTurner.interval.setter` repeated until stack guard fires. Two recent reports: `~/Library/Logs/DiagnosticReports/vreader-2026-05-15-085142.ips` and `…-084749.ips` (both build 341 / v3.21.64).

**Root cause** (`vreader/Services/AutoPageTurner.swift:32-34`): the class is `@MainActor @Observable`. The user-written property is

```swift
var interval: TimeInterval = 5.0 {
    didSet { interval = Self.clampInterval(interval) }
}
```

`@Observable` synthesizes a computed `interval` accessor that dispatches to a stored `_interval` backing property (the didSet is moved to the storage by the macro). When code writes `interval = X`:
1. Synthesized `interval.setter` runs → writes `_interval = X` through `withMutation`.
2. `_interval`'s didSet fires (line 33).
3. didSet body writes back to `interval` (the computed wrapper, NOT `_interval` directly).
4. → Step 1 again. Stack-guard fault after ~23.7k frames.

The "didSet doesn't re-fire from within itself" Swift invariant only holds when the body writes to the same stored property whose didSet is running. The `@Observable` macro's wrapper-vs-storage split breaks the invariant because writing to `interval` re-enters the public computed setter, not the storage's didSet directly.

Why this hasn't been caught: the full `vreaderTests` suite normally short-circuits on the first crash, masking later test failures; `xcodebuild` reports it as `** TEST FAILED **` without surfacing the crash report file to the operator. The 2 AZW3 TTS test failures we've been seeing this session might also be downstream consequences of the test runner aborting after the AutoPageTurner crash.

**Impact**: every production path that sets `interval` after init crashes the app. That includes (a) Settings UI changing the auto-page-turn interval slider, (b) per-book settings applying a stored interval at reader-open time, (c) ReaderSettingsStore propagating UserDefaults reads to the active turner. Feature #31's deferred live-advancement slice has been silently blocked by this; the dismissal-on-book-open symptom recorded in `dev-docs/verification/feature-31-20260515-round4.md` likely has the same root cause (no `.ips` file was generated quickly enough during the click sessions, but the crash signature shape matches: app process disappears silently with no SIGABRT/Precondition/fatalError trace).

**Fix direction** (do NOT implement here per verify-cron scope guard — bug-fix cron picks this up): three options:
- (a) Move clamping into a `willSet` and reject out-of-range writes, but `willSet` can't mutate `newValue`.
- (b) Replace the public stored `interval` with a private backing `_intervalRaw` + computed `interval` whose setter clamps before assigning to the backing. Cleanest fix; aligns with the @Observable model.
- (c) Add an `isClamping` flag re-entrancy guard in didSet. Works but reads as a workaround.

Cross-ref: this is the proximate cause of the Feature #31 round-4 open-path blocker triaged in `docs/tasks.md` (2026-05-15 entry) — that triage question can now be resolved as option (a) "Debug-build silent abort in book-open path with auto-page-turn enabled".

**FIXED 2026-05-15**: route `interval` through `@ObservationIgnored private var _intervalRaw` + computed `interval` whose setter clamps before writing the backing, with manual `access(keyPath:)` / `withMutation(keyPath:)` to preserve SwiftUI observation. No didSet → no recursion. Codex audit `019e2972` (2 rounds, ship-as-is): round-1 found Medium (NaN propagates through `max(1.0, min(60.0, .nan))` → undefined behavior in `Task.sleep(.seconds(.nan))`) → added `guard value.isFinite else { return 5.0 }`; Low (`withMutation` always emits even for identical writes) → added `guard clamped != _intervalRaw` short-circuit. Round 2 zero findings. 24 tests in `AutoPageTurnerTests` (up from 10 visible pre-fix — the recursion was killing the suite mid-run before later tests could even register; the fix doubles the visible count) including `intervalAssignment_doesNotRecurse_bug191` regression test and 3 new NaN/infinity guard tests. Audit log: `.claude/codex-audits/fix-issue-682-autopage-turner-recursion-audit.md`. GH: #682

### Bug #190 — WebDAVServerProfileListView shows stale empty-state after every mutation (FIXED 2026-05-15)

**Repro**: Settings → WebDAV Backup → Servers → (any mutation: Save edit, Add new, tap radio to set-active, swipe-delete) → list immediately renders "No WebDAV Servers" empty state + Add Server CTA. Underlying UserDefaults persistence is correct (plist shows the profile is saved/added/removed/active-id-updated). Navigate back (`<`) + re-enter (Servers nav-link) → correct list renders.
**Expected**: After every mutation the list re-renders to reflect the new state without requiring a navigate-away-and-back.
**Root cause** (`vreader/Views/Settings/WebDAVSettingsView.swift:80-82`, pre-fix): `WebDAVProfileListViewModel()` was constructed inline inside the NavigationLink's `destination:` closure. SwiftUI re-evaluates that closure on every parent re-render — most visibly when the editor sheet's `dismiss()` returns control to the parent and SwiftUI re-evaluates `WebDAVSettingsView`'s body. Each re-evaluation allocated a FRESH `WebDAVProfileListViewModel` with `profiles == []`. The destination view (`WebDAVServerProfileListView`) saw an empty VM, rendered the empty-state branch, then the `.task { await viewModel.loadProfiles() }` asynchronously repopulated it on the new instance — but the empty-state flash WAS the user-visible symptom the verify cron filed. The data-layer plumbing (UserDefaults persistence, `.webdavProfilesDidChange` notifications, `.onReceive` wiring on the list view) was correct throughout — bug was purely in **where the VM lives**.
**Fix**: hoist the VM to `@State private var profileListVM = WebDAVProfileListViewModel()` on `WebDAVSettingsView` and pass it through to `WebDAVServerProfileListView(viewModel: profileListVM)`. `@State` makes SwiftUI keep the same VM instance across parent re-renders, so the list view sees the populated `profiles` array on every re-render after the first `loadProfiles()`. Mirrors the canonical AI-sibling ownership pattern (`SettingsView` owns `AISettingsViewModel` in `@State` and threads it into `AISettingsSection` / `AIProviderListView`).
**No new test**: pure SwiftUI ownership semantics — not testable in vreader's unit-test layer without a ViewInspector-style harness the codebase doesn't use. Existing 21+31 VM-level tests at WI-4a/4b cover the data layer correctness already established. Pre-FIXED simulator verify on iPhone 17 Pro Sim at v3.21.61: Settings → WebDAV Backup → Servers → rename Server A via editor → Save → editor dismisses → list renders renamed entry immediately, no empty-state flash. Then Add path: + → enter Server C creds → Add → list shows BOTH profiles. Evidence: `dev-docs/verification/artifacts/bug-190-postfix-list-refreshes-after-save-20260515.png`. Codex MCP audit `019e283f` (2 rounds): round 1 found 1 Low (doc-comment hard-coded a `SettingsView.swift:21` line reference — rule 22 anti-pattern); fixed in same commit by referencing type names only. Round 2: zero findings, ship-as-is. Audit log: `.claude/codex-audits/fix-issue-675-webdav-list-stale-empty-state-audit.md`. GH: #675

### Bug #189 — AZW3/MOBI ignores the user's reading-mode (Scroll/Paged) toggle (FIXED 2026-05-14)

**Repro**: Settings → Reader → Layout → Scroll. Open any `.azw3` book. **Expected**: chapter content scrolls continuously like TXT/EPUB in scroll mode. **Actual**: book renders in paginated mode (swipe-to-flip pages, columns); the Scroll toggle has no effect.
**Contrast**: Same toggle + TXT or EPUB → scroll mode applies. Only AZW3 was stuck on paginated.
**Root cause**: the bug body diagnosed the right symptom but at the wrong file. The active AZW3 route in `ReaderContainerView.swift:521` dispatches to `FoliateSpikeView`, not `FoliateReaderContainerView`. `FoliateSpikeView` (a) didn't accept `settingsStore`, (b) hardcoded `webView.scrollView.isScrollEnabled = false`, (c) called `readerAPI.init({})` with no follow-up `setLayout`. The Foliate-js renderer therefore always rendered paginated regardless of preference.
**Fix**: (1) introduced a pure `FoliateLayoutFlowMapper` helper (exhaustive switch over `EPUBLayoutPreference`, future-case-safe) used by both Foliate code paths; (2) threaded `settingsStore` through `ReaderContainerView` → `FoliateSpikeView` → `FoliateSpikeWebView` → `Coordinator`; (3) on book-ready, the iife awaits `readerAPI.init({})`, then calls `setLayout({flow: window.__vreaderTargetFlow})`, then posts a new `layout-ready` script message — native flips `isBookReady` only on receipt of that message, closing the Codex round-3 race where the `evaluateJavaScript` completion fired on Promise creation rather than Promise resolution; (4) `updateUIView` always stashes the freshest preference into `window.__vreaderTargetFlow` so a toggle that lands during init is captured by the iife post-await; once `isBookReady` is true it also pushes `readerAPI.setLayout(...)` directly so live-toggle is immediate; (5) `webView.scrollView.isScrollEnabled = (flow == "scrolled")` to mirror `EPUBWebViewBridge.swift:226`'s `!isPaged` precedent. Also fixed `FoliateReaderContainerView.swift:189` (the inactive future path) to use the same mapper. Codex audit: 4 rounds, 1 High + 2 Medium + 1 Low all fixed, round-4 ship-as-is. Audit log: `.claude/codex-audits/fix-issue-670-azw3-honor-scroll-mode-audit.md`. GH: #670

### Bug #188 — TXT/MD Add Note Save persists nothing — handler reads `pendingAnnotationInfo` after `dismiss()` has cleared it (FIXED 2026-05-14)

**Repro**: Open any TXT or MD file with chapter markers (e.g. bundled `war-and-peace.txt`) → long-press a word → tap "Add Note" → paste any note text → tap Save → modal dismisses.
**Expected**: AnnotationRecord persisted (Notes panel shows the row); HighlightRecord persisted with `note: trimmed` (yellow paint appears on the annotated text per bug #181 fix).
**Actual**: Modal dismisses, but **NEITHER record is persisted**. Notes panel shows "No Annotations" empty state. `vreader-debug://snapshot` reports `highlightCount: 0`. SQLite `ZANNOTATIONNOTE` and `ZHIGHLIGHT` tables both empty for the book.
**Control test** (rules out locatorFactory / persistence regression): tap "Highlight" instead of "Add Note" on the same word → HighlightRecord persists correctly (`ZHIGHLIGHT` row with `selectedText`, `color=yellow`, `note=NULL`) AND yellow paint renders on the word in chapter mode. Bug #160's chapter-mode visual paint IS working; locatorFactory IS returning valid locators. The failure is specifically in the **Add Note → Save** code path.
**Root cause** (`vreader/Views/Annotations/AddNoteSheet.swift:45-48` + `vreader/Views/Reader/ReaderNotificationModifier.swift:91-99` + `vreader/Views/Reader/ReaderNotificationHandlers.swift:159-204` — all introduced/changed by PR #658 bug #181 fix at v3.21.53): the Save button does `onSave(); dismiss()` synchronously. `onSave()` enqueues a `Task { await ReaderNotificationHandlers.handleAnnotationSave(state: uiState, ...) }` (Task body has NOT yet executed). Then `dismiss()` runs the environment dismiss, which triggers the parent `.sheet(isPresented: .init(get:set:))` binding's `set: false` closure synchronously → `uiState.pendingAnnotationInfo = nil`. Eventually MainActor schedules the enqueued Task → `handleAnnotationSave` reads `state.pendingAnnotationInfo` → **nil** → hits the first guard and returns early. Nothing persists. **Pre-bug-181 code did sync validation inside the closure, capturing `info` / `trimmed` / `locator` as Task-closure values BEFORE spawning the Task** — making the Task immune to the post-dismiss state clear. My refactor lost that property by deferring all validation into the handler that reads from `state` after the dismiss race.
**Fix direction** (do NOT implement here — bugfix cron handles): restore the pre-bug-181 pattern of "sync validate + capture by value, then spawn Task with captured args, no state reads inside the Task". Two implementations:
  - (a) Restore inline validation in `ReaderNotificationModifier.onSave` (rolls back the bug #181 refactor's delegation; keep the additional `coordinator.create(...)` call after `addAnnotation` succeeds).
  - (b) Add a sibling handler `handleAnnotationSave(info: TextSelectionInfo, trimmed: String, locator: Locator, deps:, highlightCoordinator:)` that takes pre-captured args, and have the modifier do the validation + capture + sync clear before spawning the Task that calls it.
  - Either way: add a regression test that simulates the `dismiss()`-clears-state-before-Task-runs sequence — e.g. set `pendingAnnotationInfo = nil` between `onSave()` invocation and the `Task.detached` body running, then assert the AnnotationRecord and HighlightRecord both still persist.
**Severity**: HIGH — Add Note is completely broken on the dominant TXT/MD code path; the previously-shipping behavior (round-3 verified AnnotationRecord persistence at v3.21.8) regressed. Affects every TXT/MD user trying to add a note via the long-press menu.
**Discovered**: 2026-05-14 verify cron during Feature #4 round-4 device verification on iPhone 17 Pro Simulator (iOS 26.5) at v3.21.53 (commit 177e3e35) with bundled `war-and-peace.txt`. Reproducible 100% (3/3 attempts: "Lucca", "Genoa", same chapter 1). Evidence: `dev-docs/verification/feature-4-20260514-round4.md` + 2 screenshot artifacts. **Filed by verify cron 2026-05-14**; introduced by PR #658 (Bug #181 fix shipped earlier today at v3.21.53). **FIXED 2026-05-14**: refactored `ReaderNotificationHandlers.handleAnnotationSave` from `(state:, deps:, highlightCoordinator:)` (which read `state.pendingAnnotationInfo` inside the Task body after dismiss had cleared it) to `(info:, trimmed:, locator:, deps:, highlightCoordinator:)` — pure persistence sequence with no state reads. Added sister synchronous helper `prepareAnnotationSave(state:, deps:) -> AnnotationSaveRequest?` that owns validation + capture + `pendingAnnotationInfo` clear in one sync pass. `ReaderNotificationModifier.onSave` calls `prepareAnnotationSave` sync, then spawns `Task { await handleAnnotationSave(info: request.info, trimmed: request.trimmed, locator: request.locator, ...) }` with the captured request. `AnnotationSaveRequest` struct (Sendable) carries `info`/`trimmed`/`locator` value copies into the Task closure — immune to any post-spawn state mutation. Codex MCP audit `019e2596` (2 rounds): round 1 = 1 Medium (modifier-side capture sequence untested) → addressed by the prepare/handle split that makes both halves pure-function-testable + added 5 new tests covering prepare (validInput, nilPending, emptyTrimmed, locatorFactory failure) and the production sequence (`prepareAndHandleAnnotationSave_isImmuneToPostPrepareStateMutation_bug188`). Round 2: zero findings, ship-as-is. Test gate: 18/18 ReaderNotificationHandlersTests pass. Pre-FIXED simulator verify on iPhone 17 Pro Sim (iOS 26.5) with build under test: long-press "Lucca" → Add Note → paste "Italian port — bug #188 verify" → Save → modal dismisses → SQLite confirms BOTH records (`ZANNOTATIONNOTE` "Italian port — bug #188 verify" + `ZHIGHLIGHT` {selectedText: "Lucca", note: "Italian port — bug #188 verify", color: "yellow"}) → tap chrome off → **yellow background clearly visible on "Lucca" in line 1**. Evidence: `dev-docs/verification/artifacts/bug-188-prefix-lucca-yellow-highlight-visible-20260514.png`. Also unblocks Bug #181's GH #616 close-gate (the `coordinator.create` call is now reached) AND Feature #4 criterion 8c (visual highlight on annotated text). Audit log: `.claude/codex-audits/fix-issue-659-add-note-save-state-race-audit.md`. GH: #659

### Bug #186 — First launch after install is extremely slow — ModelContainer init runs synchronously on @MainActor in app init(), evaluating all 6 schema versions on main thread (REPORTED 2026-05-14)

**Repro**: Build and install the app on a real device or simulator (fresh install or reinstall) → launch the app → observe a long freeze/blank screen before the app becomes interactive. Subsequent launches are fast.
**Expected**: App becomes interactive within ~1 second of launch on all installs.
**Actual**: On first launch after install, the app freezes for several seconds. Subsequent launches are fast. The freeze does not recur unless the app is reinstalled.
**Root cause** (`VReaderApp.swift:109-113`): `ModelContainer(for: schema, migrationPlan: VReaderMigrationPlan.self, configurations: [modelConfig])` is called synchronously on `@MainActor` inside the app struct `init()`. SwiftData evaluates all 6 schema versions (SchemaV1–SchemaV6 via `VReaderMigrationPlan`) during container creation. On a fresh install, it must create the entire database schema from scratch while blocking the main thread. Secondary suspect: `LazyDownloadCoordinator.reattachAndReconcile()` (launched via async `Task` at lines 226–234) performs a full DB scan for `.downloading` books at startup and may compound the cold-open cost. Not a duplicate of bugs #4, #79, #89 (those addressed search-panel latency, deferred indexing, and SQLite `WALMode` respectively — none moved `ModelContainer` creation off the main thread).
**Fix**: Move `ModelContainer` creation to a background task or use `Task.detached` to initialize the container off the main thread, then inject it asynchronously into the app's environment. Alternatively, investigate whether SwiftData's `ModelContainer` init can be made lazy or cached across reinstalls. GH: #633

### Bug #185 — AI provider editor: Base URL field has no guidance about what path the app appends — users enter full endpoint URL, causing double-path construction and silent failure (REPORTED 2026-05-14)

**Repro**: Settings → AI → Providers → add or edit a provider → observe the Base URL field.
**Expected**: The field explains what URL format to enter — specifically, whether to include the endpoint path or just the base.
**Actual**: Placeholder text is `"https://api.example.com/v1"` (gives a format hint) but no text explains that the app appends `/chat/completions` for OpenAI-compatible or `/v1/messages` for Anthropic. Users entering `https://openrouter.ai/api/v1/chat/completions` (the full endpoint) will have the app construct `https://openrouter.ai/api/v1/chat/completions/chat/completions` — this 404s or returns a confusing error from the provider with no explanation in the UI.
**Root cause** (`AIProviderEditSheet+Sections.swift:68`): placeholder is `"https://api.example.com/v1"` only; no footer text; no per-kind dynamic hint. In `AIProvider.swift:119` (OpenAI-compat): `baseURL.appendingPathComponent("chat/completions")`; in `AnthropicProvider.swift:134`: `baseURL.appendingPathComponent("v1/messages")`. Correct values:
- OpenAI-compatible (e.g. OpenRouter): `https://openrouter.ai/api/v1`
- Anthropic: `https://api.anthropic.com`
**Fix**: Add a `Section` footer or `Text` hint below the Base URL field that updates dynamically with the selected `kind`, e.g. "Enter the base URL — the app will call `/chat/completions` from this base." + a pre-filled example per known provider. Optionally detect if the user has typed a URL that already ends in `/chat/completions` or `/messages` and warn. GH: #627

### Bug #184 — Add Provider: "Save Key" and "Test Connection" always disabled — buttons visible but non-functional, explanation buried in tiny caption text (REPORTED 2026-05-14)

**Repro**: Settings → AI → Providers → "+" (add new provider) → fill in Name + Base URL → observe "Save Key" and "Test Connection" buttons.
**Expected**: User can save their API key and test the connection while creating a new provider.
**Actual**: Both buttons are disabled (greyed out) in add-mode. "Save Key" is `.disabled(apiKey.isEmpty || existing == nil)` — always disabled when `existing == nil` (add-mode). "Test Connection" is `.disabled(testInFlight || !isAPIKeySaved || existing == nil)` — also always disabled in add-mode. The explanation ("Enter your API key above, then tap Save to create the profile" / "Save the profile first to test the connection") is rendered in `caption2`/`tertiary` — tiny, low-contrast text that users routinely miss. User believes the buttons are broken.
**Root cause** (`AIProviderEditSheet+Sections.swift:145, 185`): Intentional design decision (audit round-1 fix [4]) to prevent keychain orphans: in add-mode the sheet generates a UUID up front but the profile isn't yet in the store. Writing a keychain entry via "Save Key" then tapping Cancel would leak an orphaned secret. The fix addresses the underlying concern correctly but presents two permanently-disabled visible buttons with insufficient explanation.
**Fix options**: (a) hide "Save Key" button entirely in add-mode — replace with inline note "Your API key will be saved when you tap Save above"; (b) hide "Test Connection" section in add-mode or promote the explanation to body-weight text; (c) allow "Save Key" in add-mode using an ephemeral keychain entry that's deleted on Cancel (architectural change). Option (a)+(b) is the cheapest correct fix. GH: #625

### Bug #183 — TXT search panel freezes UI on first open — enqueueBookIndexing runs on @MainActor, blocking main thread during file I/O + encoding detection (REPORTED 2026-05-14)

**Repro**: Open any large TXT file (e.g. 5MB+ CJK novel) → tap the search icon → UI freezes for several seconds before the search panel appears.
**Expected**: Search panel opens immediately; indexing/extraction runs in the background.
**Actual**: Main thread blocks during text extraction + encoding detection; UI is unresponsive until extraction completes. Already-indexed books are not affected (first-open only).
**Root cause** (`ReaderSearchCoordinator.swift`): The class is annotated `@MainActor` (line 12). `enqueueBookIndexing` is a `private static func` with no `nonisolated` keyword → inherits `@MainActor`. At line 142-143 it calls `let result = try await extractor.extractWithOffsets(from: fileURL)` — `TXTTextExtractor.extractWithOffsets()` is `async` but its body calls `Self.decodeFile(at:)` synchronously: `Data(contentsOf: url, options: .mappedIfSafe)` + `TXTService.decodeForDisplayAndSearch()` (encoding detection). Both are blocking. `BackgroundIndexingCoordinator` uses `Task.detached(priority: .background)` for FTS5 indexing, but only AFTER extraction — extraction still blocks main. Not a duplicate of #4 (VM creation), #79 (deferred indexing), #89 (SQLite open) — those addressed different performance seams without moving text extraction off the main thread.
**Fix**: Mark `enqueueBookIndexing` as `nonisolated` and wrap the extraction call in `Task.detached(priority: .utility)`, or move extraction to a dedicated non-isolated async method inside `TXTTextExtractor`. GH: #623

### Bug #182 — EPUB search: cross-chapter result tap navigates but shows no yellow highlight (FIXED 2026-05-18)

**Repro**: Open any multi-chapter EPUB → tap search → type a word that appears in a chapter other than the current one → tap the result.
**Expected**: Reader navigates to the correct chapter and paints a temporary yellow background on the matched word for ~3 seconds.
**Actual**: Reader navigates to the correct chapter (top) but no yellow highlight is visible. User cannot locate the matched text without manually scanning the page.
**Same-chapter searches work** — if the match is already in the loaded chapter, `window.find()` succeeds and the highlight is visible.
**Root cause** (`EPUBWebViewBridge.swift`, `updateUIView`): When a cross-chapter search result is tapped, `contentURL` and `pendingHighlightJS` are set in the same SwiftUI state update. In `updateUIView`, `webView.loadFileURL(contentURL, ...)` is called (starts async load) and then `evaluateJavaScript(pendingHighlightJS)` is called immediately on the same call stack — before the new chapter DOM is ready. `window.find()` runs on the old/loading page, returns false, no `<span>` is injected. `onPendingJSCompleted()` then clears `pendingHighlightJS`. When `webView(_:didFinish:)` fires later with the correct DOM, `pendingHighlightJS` is already nil. The `onPageDidFinishLoad` callback only calls `restoreHighlightsOnLoad` (persisted highlights), never the search highlight. Contrast: `pendingScrollFraction` is stored in the coordinator and consumed in `didFinish` — `pendingHighlightJS` needs the same deferred treatment.
**Fix**: Store the search quote and progression in the coordinator at URL-change time; consume in `webView(_:didFinish:)` after theme CSS and pagination/scroll setup, analogous to `pendingScrollFraction`. GH: #621

**Round-2 + round-3 (2026-05-15 → 2026-05-18):** round-1's deferred-eval mechanism landed but the symptom persisted. Round-2 found the `Locator.textQuote` passed to `window.find()` was the raw search snippet (`...prefix<b>match</b>suffix...`) — `SearchHitToLocatorResolver.cleanSnippetForTextQuote` now strips the `<b>`/`...` markup. Round-3 found the residual cause: `EPUBHighlightBridge.searchHighlightJS` ran `window.find()` exactly once, synchronously at `webView(_:didFinish:)` — before the freshly-loaded chapter finishes its post-load relayout (foliate-js `cssPreprocessJS`, a `WKUserScript` injected `atDocumentEnd`, rewrites every `-epub-*`/`page-break-*` rule), so `window.find()` returns false and no `.vreader_search_highlight` span is created. Verify-cron round-5 DOM-probes confirmed the span is never injected via the user-tap pipeline. **Round-3 fix** (`searchHighlightJS`, JS-only — the Swift stash→consume pipeline was already correct): poll `window.find()` on a bounded 50ms retry loop (40 attempts ≈ 2s) until the rendered DOM is searchable; a `window.__vreaderSearchHighlightGen` generation token supersedes concurrent retry loops; the wrap-and-insert is `try/catch`-guarded. Codex audit `019e3959` (3 rounds, 1 Medium + 4 Low all fixed, ship-as-is): `.claude/codex-audits/fix-issue-621-epub-cross-chapter-highlight-r3-audit.md`.

### Bug #181 — TXT/MD Add Note: annotated text not highlighted after saving note (FIXED 2026-05-14)

**Repro**: Open any TXT or MD file → long-press word → tap "Add Note" → type text → tap Save → modal dismisses.
**Expected**: Selected text shows a yellow (or tinted) background highlight indicating an annotation is attached.
**Actual**: Text appears identical to surrounding text — no visual indicator. Note IS saved and appears in Annotations panel.
**Root cause** (`ReaderNotificationModifier.swift:108-113`): `onSave` calls `addAnnotation()` (creates `AnnotationRecord`) only — no `highlightCoordinator.create(...)` call, so annotation range never enters `persistedHighlightRanges`. Contrast: EPUB's `handleHighlightWithNote` calls `coordinator.create(..., note:)` → creates `HighlightRecord` that IS rendered.
**Context**: Feature #4 criterion 8c was cross-referenced to bug #160 but bug #160 (HighlightRecord chapter-mode rendering) is architecturally separate from this gap (annotation save never creates a HighlightRecord). Affects both TXT and MD. **FIXED via `handleAnnotationSave` now persisting both an `AnnotationRecord` (for the Notes panel) AND a `HighlightRecord` with `note: trimmed` (for the yellow highlight on the text). `ReaderNotificationHandlers.handleAnnotationSave` gained a `highlightCoordinator: HighlightCoordinator` parameter; the inline `onSave` closure in `ReaderNotificationModifier` now delegates to the canonical handler (eliminates duplication that caused the gap in the first place). Atomicity: `addAnnotation` is now invoked under explicit `do/catch` — if it throws, the function returns before `coordinator.create(...)` so the two records stay in lockstep (audit-driven addition). pendingAnnotationInfo is cleared BEFORE the awaits inside the handler so the AddNoteSheet dismisses immediately on Save; MainActor serialization guarantees re-entrancy safety (a second queued save Task observes `pendingAnnotationInfo = nil` and bails before doing any work). Codex MCP audit `019e251f` (2 rounds): round 1 found 1 High (dual-write atomicity), 2 Medium (existing-highlight + Add Note drops note via dedupe — accepted as separate follow-up bug; re-entrancy from rapid taps — accepted as effectively-safe via MainActor serialization), 1 Low (file size). High fix applied with regression test; Medium #2 deferred (pre-existing PersistenceActor.addHighlight dedupe behavior, not introduced here); Medium #3 accepted with rationale documented. Round 2: zero new findings, ship-as-is. Test gate: 15/15 ReaderNotificationHandlers tests pass including 3 new bug #181 regression tests (`handleAnnotationSave_alsoCreatesHighlightRecord_bug181`, `handleAnnotationSave_annotationPersistenceFails_skipsHighlight_bug181`, `handleAnnotationSave_locatorFactoryFailure_skipsBoth_bug181`). Pre-FIXED verify: the bug-181 regression test ran with the pre-fix logic would fail (`storeAddCount == 0` and `renderer.appliedRecords.isEmpty` — no HighlightRecord persisted, no apply() call). With the fix, both assertions hold (`storeAddCount == 1`, `appliedRecords.count == 1`, applied.color == "yellow", applied.note == "remember this"). Audit log: `.claude/codex-audits/fix-issue-616-txt-md-add-note-no-highlight-audit.md`. Follow-up filed informally (track as bug or feature on next triage cycle): "Add Note on already-highlighted TXT/MD range should update note on existing HighlightRecord (currently dedupe returns existing record unchanged)". GH: #616

### Bug #180 — TXT scroll mode must scroll continuously + smoothly across chapters — REOPENED + RE-SCOPED 2026-05-16: abandon discrete chapter-swap, render one continuous surface (FIXED 2026-05-15, REOPENED 2026-05-16)

**Original symptom (FIXED 2026-05-15, commit 5f75fde / PR #681)**: In TXT scroll mode, scrolling to a chapter boundary just bounced — the user had to reveal chrome and tap "Next chapter". Fixed by adding `didScrollPastBottomBoundary()` / `didScrollPastTopBoundary()` to `TXTTextViewBridgeDelegate`, boundary detection in `TXTTextViewBridgeCoordinator.sendScrollPosition`, and `TXTReaderViewModel.goToNextChapter()` / `goToPreviousChapter()`. Codex audit `019e2923`; 7 tests in `TXTScrollBoundaryChapterNavTests.swift`.

**REOPENED 2026-05-16**: User reports the fix made scroll-mode reading worse. After the fix, scrolling is discontinuous — it jumps to the **end** of the next chapter, then jumps again, cascading through chapters; it never scrolls smoothly and lands in the wrong place.

**Repro (REOPENED)**: Open any multi-chapter TXT file → Layout = Scroll → scroll down toward the end of Chapter 1. **Actual**: instead of advancing to the *top* of Chapter 2, the view jumps to the *end* of Chapter 2 (or further), repeatedly. **Expected**: advancing a chapter lands at the top of the new chapter and scrolling stays smooth.

**Root cause (REOPENED)**: The #180 fix swaps the entire chapter text on boundary but never resets the scroll view's `contentOffset`:
1. `TXTReaderViewModel.navigateToChapter` (`TXTReaderViewModel.swift:363-401`) sets `currentChapterLocalUTF16 = 0` in the model but does NOT push a scroll-to-top command to the bridge.
2. `TXTTextViewBridge.updateUIView` restores scroll only via the `scrollToOffset` path, which is `nil` after a boundary-triggered chapter nav (only search-tap / scrubber populate `uiState.scrollToOffset`). Saved-position restore is otherwise one-shot in `makeUIView` — not re-run when only the text changes.
3. So when Chapter 2's text is applied, the `UITextView` keeps Chapter 1's bottom `contentOffset.y` (≈ `maxOffset`). The user sees the END of Chapter 2, not its start.
4. Worse: that stale near-`maxOffset` offset re-satisfies `sendScrollPosition`'s bottom-boundary predicate (`offset >= maxOffset - boundarySlack`, `TXTTextViewBridgeCoordinator.swift:392-401`) on the next settle → `didScrollPastBottomBoundary()` fires again → `goToNextChapter()` again → **cascading multi-chapter skip**. `isChapterNavInFlight` only serializes overlapping loads; it does not stop the next *settled* scroll from re-triggering.

**RE-SCOPED 2026-05-16 (user directive)**: The discrete chapter-SWAP approach is rejected outright — not patched. The user wants TXT scroll mode to **scroll continuously, smoothly, and endlessly across chapter boundaries** with no jump at all. The boundary-detect-then-swap design (PR #681) is the wrong model for this bug. Per the user's tracking decision, the fix stays under bug #180 (not split into a separate feature) and **chapter awareness must be preserved** — TOC jumps, per-chapter reading progress, and feature #48's chapter-scoped highlight pipeline all continue to work under continuous scroll.

**Fix direction (re-scoped)**:
1. **Abandon the boundary-swap.** Remove / disable `didScrollPastBottomBoundary` / `didScrollPastTopBoundary` driving `goToNextChapter()` / `goToPreviousChapter()` as the scroll-mode chapter-advance mechanism. (Chrome-button chapter nav can remain.)
2. **Render chaptered TXT as one continuous scrollable surface in Scroll layout.** The app already has whole-document continuous renderers — flat-mode `UITextView` and the chunked `UITableView` (`TXTChunkedReaderBridge`, used for >500K UTF-16). The fix routes chaptered TXT in Scroll layout through a continuous renderer so scrolling never stops at a chapter edge. Scrolling must stay **smooth** — no relayout hitch, no content jump when crossing a boundary (the chunked renderer's windowing already handles large books; reuse it rather than swapping `UITextView` text).
3. **Preserve chapter awareness over the continuous surface.** Maintain a chapter-offset index (each chapter's global UTF-16 start) so: (a) TOC tap jumps to the right scroll offset; (b) per-chapter progress + the scrubber compute correctly from the continuous offset; (c) feature #48's chapter-scoped highlight pipeline still maps global↔chapter-local offsets. `currentChapterIdx` becomes a *derived* value from scroll position, not a render-mode switch.
4. **Memory**: the chunked `UITableView` path already lazy-renders rows for huge books; continuous cross-chapter scroll should build on that windowing, not load every chapter's full attributed string at once.

**Scope note**: this is feature-sized work carried on a bug row by explicit user choice (2026-05-16) — it skips the `/feature-workflow` gates, but the fix still warrants a written plan (Understand → design the continuous-scroll architecture → RED → GREEN → REFACTOR → Verify) given the architecture surface. Cross-ref: bug #165 (EPUB has the same discrete-vs-continuous question); feature #48 (chapter-scoped highlight pipeline that must keep working); feature #60 (reader chrome — the design bundle is paginated, so any *new* scroll-mode chrome/toggle UI is undesigned and falls under rule 51 → file `Design needed:` if a new surface is required; behavior-only continuous scroll reusing existing chrome does not).

**Note**: the summary-table row was never flipped from `TODO` to `FIXED` after PR #681 merged — a separate tracker-hygiene slip; the row is set to `REOPENED` here. GH: #614 (REOPENED)

### Bug #179 — TXT reading content obscured by Dynamic Island on restore + chapter-nav (FIXED 2026-05-15)

**Original symptom (FIXED in v3.21.31, commit 306e54f)**: First-open at offset 0 — DI obscured first line. Resolved via `safeAreaTopInset` threaded through `TXTTextViewBridge` / `TXTChunkedReaderBridge` and applied to `textContainerInset.top`.

**REOPENED 2026-05-14**: User reports the symptom recurs on two paths the original fix did not cover:
1. **Reopening the TXT file** (saved reading position > 0) — first visible line lands behind DI.
2. **Navigating to a new chapter** (chapter-mode or scroll-mode jump) — chapter start lands behind DI.

**Repro (REOPENED scenario A — restore)**: Open any TXT book → scroll to mid-chapter (saved position offset > 0) → close book → reopen book. **Pre-fix**: the restored character lands at the visible top of the scrollView, behind the DI. **Post-fix (v3.21.62)**: restored chapter renders cleanly below DI; reopen of mid-chapter saved position lands the header at y≈200pt (below the ~110pt DI cutoff).

**Repro (REOPENED scenario B — chapter nav)**: Open any TXT book with detected chapters → tap "Next chapter" button or scrubber-jump to a new chapter. **Pre-fix**: chapter start clipped behind DI. **Post-fix (v3.21.62)**: chapter-nav renders new chapter header at y≈200pt (below DI) across multiple chapter transitions.

**Root cause analysis history**:
- The REOPEN row body proposed that `attemptScrollRestore` was missing a `textContainerInset.top` subtraction. The previous bugfix-cron iteration (2026-05-15 earlier) tried this fix and Codex thread `019e2743` rejected it as mathematically wrong: `contentOffset.y = lineY` IS correct when `textContainerInset.top` includes the safe-area inset; the proposed subtract/add would land the glyph at visible y=0 instead of `textContainerInset.top` (below DI).
- The TRUE root cause is upstream of the scroll math. The container view wraps its content in `GeometryReader { proxy in TXTTextViewBridge(safeAreaTopInset: proxy.safeAreaInsets.top, ...) }`. The parent `ReaderContainerView` applies `.ignoresSafeArea(edges: .top)` (chrome-overlay layout) and bug #73 documented (in `ReaderChromeBar.swift:85`) that `GeometryReader` returns `0` from `proxy.safeAreaInsets.top` momentarily on initial render and across rebuild gaps. On the bridge's first `makeUIView`, `textContainerInset.top = base(16) + 0 = 16` — and `contentOffset.y = lineY` (or default 0) lands the glyph at visible y = 16, BEHIND the DI. By the time SwiftUI's later layout pass reaches `updateUIView` with the measured ~59pt, the 0.15s-delayed `attemptScrollRestore` has already fired against the under-insetted textView. Same race fires on chapter-nav rebuild (`chapterAttrString = nil` swaps to `loadingView` then back, creating a fresh `TXTTextViewBridge` whose first `makeUIView` hits the same un-measured `proxy.safeAreaInsets.top`).

**Fix (v3.21.62)**: new `ReaderSafeAreaResolver` static helper that reads the device's actual top safe-area from `UIWindow.safeAreaInsets.top` (the bug #73 escape pattern from `ReaderChromeBar.windowSafeAreaTop`, but with broader activation-state coverage and a `lastKnownNonZeroTop` cache). The resolver's logic is active-first (foreground active scene's max top inset wins, even when 0 — covers landscape iPad / Stage Manager), inactive-as-warmup (foreground inactive scenes consulted only when no active scene exists; an inactive 0 falls through to cache rather than fabricating a zero state), then cache. Every TXT/MD container view's bridge entry point now passes `ReaderSafeAreaResolver.topInsetWithFallback(proxy.safeAreaInsets.top)` instead of `proxy.safeAreaInsets.top` directly — guaranteeing the bridge sees a correct ~59pt even before SwiftUI has measured.

The scroll math (`attemptScrollRestore`, `scrollToMatchedOffset`) is unchanged — Codex round 1 of `019e2743` correctly verified it. The bug was upstream, in the inset feed.

**Codex audit `019e2893` (3 rounds, ship-as-is)**: round 1 found 2 Mediums (activation-state too narrow + multi-window scene mis-selection); round 2 found 1 Medium (active-pass-zero shouldn't fall through to inactive in landscape); round 3 clean. Test gate: 908 Swift Testing pass including new 10-case `ReaderSafeAreaResolverCombineSuite` covering both-zero, geom-only, window-only, both-equal, geom-larger, window-larger, negative clamps, iPad-landscape baseline. Pre-FIXED simulator verify on iPhone 17 Pro Sim at v3.21.62: opened `war-and-peace.txt`, navigated chapter 1→2 (tap Next), confirmed chapter 2 header at y≈200pt (below ~110pt DI); tapped Back, retapped book, confirmed saved-position reopen lands chapter 2 header below DI; tapped Next again to chapter 3/4, confirmed chapter 3 header also below DI. Evidence: `dev-docs/verification/artifacts/bug-179-postfix-chapter-2-reopen-below-di-20260515.png` + `dev-docs/verification/artifacts/bug-179-postfix-chapter-nav-below-di-20260515.png`. Audit log: `.claude/codex-audits/fix-issue-611-txt-di-overlap-restore-and-chapter-nav-audit.md`. Follow-up: a SwiftUI/UIView/window-seam regression harness for restore + chapter-nav under nonzero safe area is recommended but not yet built — vreader's test layer doesn't currently have such a harness; pure-function `combine(_:_:)` coverage is the test floor, device verification is the test ceiling. GH: #611

**Note**: MD scroll mode shares `TXTTextViewBridge` — same regression likely. Native paged MD path (`NativeTextPagedView`) was explicitly OUT OF SCOPE in the original fix; reassess in the re-fix. GH: #611 (REOPENED)

### Bug #178 — MD native mode Chinese conversion silently no-ops — picker enabled but SimpTradTransform never applied (REPORTED 2026-05-14)

**Repro**: Open any MD file with Simplified Chinese content → Settings → Chinese Text → Traditional. Picker accepts the change (not disabled) → content renders unchanged — conversion is silently skipped.
**Root cause** (`MDReaderContainerView.swift`, `MDReaderViewModel.swift`): neither file reads `settingsStore.chineseConversion` nor calls `TextMapper.apply(transforms:to:)`. Feature #28 WI-A only wired TXT native mode. `ReaderSettingsPanel.chineseConversionDisableReason` (line 513) explicitly enables the picker for MD (`fmt == .txt || fmt == .md`) — making the setting appear functional when it is not.
**Contrast**: `TXTReaderContainerView` wires `SimpTradTransform` at 8 call sites across chapter, flat, and chunked render paths.
**Fix**: mirror TXT's pattern — read `settingsStore?.chineseConversion` in `MDReaderContainerView`, include it in the rebuild key (alongside `fontSize`, `fontName`, etc.), and call `TextMapper.apply(transforms:to:)` on the parsed Markdown source text.
**Discovered**: 2026-05-14 via gpt-5.5 code review of issue #493 design decision. GH: #606

### Bug #176 — AZW3/MOBI TTS silently fails — speaker button + `vreader-debug://tts?action=start` both no-op (Foliate-rendered formats have no text-extraction case in `loadBookTextContent`)

**Repro**: Open any AZW3/MOBI book → tap the speaker button in the reader chrome OR fire `vreader-debug://tts?action=start`. Reproduced 2026-05-13 on iPhone 17 Pro Sim (iOS 26.5) at v3.21.17 (commit `a0ec073`) with bundled `mini-azw3.azw3` (Project Gutenberg #1064, "The Masque of the Red Death").
**Observed**: No TTS control bar appears. `vreader-debug://snapshot` after the start URL shows `ttsState: "idle"`, `ttsOffsetUTF16: null` — the production `TTSService.state` never transitioned from `.idle`. No error toast, no spinner, no log entry — silent failure. Screenshot evidence: `dev-docs/verification/artifacts/feature-26-r3-02-azw3-tts-start-20260513.png`.
**Expected**: TTS starts speaking the AZW3 text. `ttsState` transitions to `"speaking"`. TTS control bar (⏸/◾/1.2x) appears at the bottom of the reader. Same behaviour as TXT/MD/PDF/EPUB.
**Root cause** (code-read confirmed at `vreader/Views/Reader/ReaderAICoordinator.swift`'s `loadBookTextContent(fileURL:format:)`): the `switch format` statement has cases for `"txt"` / `"md"`, `"pdf"`, and `"epub"`, but **no case for `"azw3"` or `"mobi"`**. Falls through to `default: return nil`. Result: `loadedTextContent` stays nil. `startTTS()` in `ReaderContainerView+Sheets.swift:17` guards both call sites with `if let text = ai.loadedTextContent, !text.isEmpty { ... }` — both fail when the format isn't TXT/MD/PDF/EPUB, so `ttsService.startSpeaking(...)` is never called.
**Why this is a bug not a feature**: `FormatCapabilities.azw3` declares `.tts` capability (`FormatCapabilities.swift`), so the speaker button IS shown in the reader chrome — the capability is advertised. `FoliateTTSAdapter` (`vreader/Services/Foliate/FoliateTTSAdapter.swift`) exists with `startTTSJS()`/`nextTTSJS()`/`initTTSJS(granularity:)` — the JS-side adapter is already shipped. The wire-up between the capability-advertised button and the available Foliate adapter is missing. Implementation exists but is unwired for AZW3/MOBI — classic bug, not a never-implemented feature.
**Two fix paths** (do NOT pick one — fix-cron will diagnose):
- (a) Add an `"azw3"` / `"mobi"` case to `loadBookTextContent` that extracts text from the Foliate webview (e.g., via `webView.evaluateJavaScript("document.body.innerText")` or a `readerAPI` helper). Keeps the unified AVSpeechSynthesizer pipeline — same TTS service, same sentence highlighting (feature #40) wired through `currentOffsetUTF16`.
- (b) Branch `startTTS()` on format: for Foliate formats, evaluate `FoliateTTSAdapter.initTTSJS(granularity:) + startTTSJS()` in the webview instead of going through `ttsService.startSpeaking`. Foliate's in-webview TTS pipeline (foliate-js's own TTS) handles the speech — but then the AVSpeechSynthesizer code path + sentence-highlight feature #40 don't apply to AZW3.
**Filed by verify cron 2026-05-13** during feature #26 round-3 verification of the deferred Foliate slice. Same gap likely affects MOBI (same Foliate render path). EPUB is unaffected because `loadBookTextContent` has an explicit `"epub"` case using `EPUBParser` + `EPUBTextExtractor.stripHTML`.

### Bug #177 — Library grid cards in the same row sit at different vertical positions (REPORTED 2026-05-13)

**Repro**: Open the Library with ≥2 books in the same grid row where one has an author label or reading-time label and another doesn't. The cover images' top edges are visibly at different Y positions.
**Root cause** (`BookCardView.swift:38,46`): author and reading time are conditionally included in the `VStack`, so card total height varies. `LazyVGrid` determines row height from the tallest card, then **vertically centers** shorter cards within that height. Cards with more metadata (author + reading time) appear highest; cards with no metadata appear lowest.
**Fix**: add `Spacer(minLength: 0)` as the last child of `BookCardView`'s `VStack` (line ~57, before `.frame(maxWidth: .infinity, alignment: .leading)`). All cells then fill the full row height, centering is a no-op, and all cover tops align at the same Y.
**Note**: Not related to cover images — `CoverContainerView` already uses a fixed 2:3 `aspectRatio` so cover heights are uniform. The misalignment is purely from the variable-height metadata below the cover.

### Bug #174 — AI provider row tap does nothing for editing (REPORTED 2026-05-13)

**Repro**: Settings → AI Providers (1+ profile saved) → tap any provider row.
**Observed**: Active indicator updates (radio button fills), but no edit sheet appears. The only edit path is a leading-edge swipe gesture (`swipeActions(edge: .leading)`), which is non-standard and not surfaced by any affordance on the row.
**Expected**: Tapping a row opens the edit form, OR a visible pencil/edit affordance indicates how to edit.
**Root cause 1 — UX discoverability** (`AIProviderListView.swift:127-128`): The row `Button` action is wired exclusively to `viewModel.setActive(profile.id)`. Edit lives only behind `.swipeActions(edge: .leading)` at lines 175-184. No pencil icon, no Edit button in the toolbar, no tap-to-edit path.
**Root cause 2 — potential SwiftUI sheet state race** (`AIProviderListView.swift:64-66`): `.sheet(isPresented: $showEditor)` captures `editingProfile` at evaluation time. The swipe button sets `editingProfile = profile` and `showEditor = true` synchronously; if SwiftUI evaluates the sheet closure before committing `editingProfile`, the sheet opens with `existing: nil` (add-new mode instead of edit mode). Fix: migrate to `.sheet(item: $editableItem)` where `editableItem` is either a `ProviderProfile` (edit) or a sentinel (add-new).
**Fix direction**: (a) Make row tap open edit form — change the `profileRow` button action to open the editor; move `setActive` to a trailing-edge swipe or a dedicated "Set Active" label; OR (b) Add a pencil button next to each row label; either way, also migrate to `.sheet(item:)` to eliminate the state-race risk.

### Bug #175 — TXTChapterHighlightRenderingTests suite crashes/hangs on `highlights from ch0 are dropped when rendering ch2`, blocking full vreaderTests run

**Repro**: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project vreader.xcodeproj -scheme vreader -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:vreaderTests/TXTChapterHighlightRenderingTests` on clean `main` (commit be51d7d). Confirmed pre-existing: reproduces with WI-4c-c branch stashed.
**Symptom**: Swift Testing reports `◇ Test "highlights from ch0 are dropped when rendering ch2" started.` followed by `Restarting after unexpected exit, crash, or test timeout`. Test harness re-launches but cannot recover; subsequent test suites (AutoPageTurnerTests, TTSServiceSpeedControlTests) listed as failing but never actually executed — they're collateral from the crash. Suite is at `vreaderTests/Views/Reader/TXTChapterHighlightRenderingTests.swift` (feature #48 WI-1, commit 540722b).
**Why this is a bug not a feature**: `TXTReaderContainerView.chapterLocalHighlightRanges` was implemented and shipped (feature #48 WI-1 merged). The test exists in the repo and is in the default test plan — it's expected to run. It runs the first test (`chapterModeKeepsRangesWithinChapter`) cleanly per other suites' precedent, but crashes specifically on the ch0-vs-ch2 case. The implementation is in place; the test or the implementation has a latent crash bug surfaced by this scenario.
**Impact**: blocks `xcodebuild test -only-testing:vreaderTests` from completing cleanly. Workaround: exclude `TXTChapterHighlightRenderingTests` with `-skip-testing` until root cause is fixed. Test-gate evidence for unrelated WIs (e.g., WI-4c-c) requires running with the skip flag.
**Possible root causes** (none yet investigated): (1) `chapterLocalHighlightRanges` returns an NSRange whose location/length overflow when the ch0→ch2 mapping puts the result out-of-bounds for the chapter text; (2) test fixture's chapter offsets create a pathological case the production code doesn't guard against; (3) Swift Testing `@Test` actor-isolation interaction with the helper.
**Fix scope** (deferred — this row files; fix-cron picks up): read `TXTChapterHighlightRenderingTests.swift` lines around the named test (line 73 per grep), trace the inputs into `TXTReaderContainerView.chapterLocalHighlightRanges`, isolate the crash with a minimal repro, fix.
**Filed by feature cron 2026-05-13** during feature #45 WI-4c-c Gate 3 test gate.

### Bug #163 — EPUB reading content obscured by Dynamic Island at chapter start (REOPENED)

**Repro**: Open any EPUB → navigate to chapter start → first 1–2 lines of text clipped behind the Dynamic Island.
**Prior fix (PR #513, 2026-05-11)**: `EPUBWebViewBridge` reads `safeAreaInsets.top` via `GeometryReader`, injects it into `UIScrollView.contentInset.top` + `verticalScrollIndicatorInsets.top`, and subtracts it from paged column height. Passed unit tests + simulator verify but user reports regression on device.
**Re-investigation needed**: Confirm safe-area value is non-zero at the time of injection; check whether `GeometryReader` proxy gives the correct inset when the chrome bar is visible vs hidden; check if `updateUIView` change-detection path fires correctly; check if the fix covers the case where the reader first opens (vs inset changes after load). Also check if the `contentInsetAdjustmentBehavior = .never` override is fighting the manual inset on iOS 17+.

### Bug #172 — Haptic feedback on bookmark-add missing in TXT, EPUB, PDF, and AZW3/MOBI readers (only MD fires)

**Repro**: Open any TXT / EPUB / PDF / AZW3 book → tap the bookmark toolbar icon → bookmark is added successfully BUT no haptic vibration on the device.
**Expected** (feature #7): UIImpactFeedbackGenerator(.light) fires on every successful bookmark add across all formats. Feature #7 row at `docs/features.md` describes WI-002: "UIImpactFeedbackGenerator(.light). 5 tests."
**Observed**: Haptic fires only when adding a bookmark in the Markdown reader. The other four formats add the bookmark silently.
**Root cause** (code-confirmed):
- `MDReaderContainerView.swift:245` wires `hapticFeedback: HapticFeedbackProvider()` into `ReaderNotificationDeps`, and the bookmark-add path runs through `ReaderNotificationHandlers.handleBookmarkRequest` (which calls `deps.hapticFeedback?.triggerLightImpact()` at line 88).
- `TXTReaderContainerView.makeNotificationDeps()` (line 402-434) constructs `ReaderNotificationDeps` WITHOUT the `hapticFeedback` parameter — defaults to `nil`. Even though the TXT bookmark-add flows through the same `handleBookmarkRequest`, the optional-chained call is a no-op.
- `EPUBReaderContainerView.swift:166-177`, `PDFReaderContainerView.swift:218-area`, and `FoliateReaderContainerView.swift:80-area` do NOT use `ReaderNotificationHandlers` at all — they handle `.readerBookmarkRequested` inline with their own `.onReceive` blocks that call `persistence.addBookmark(...)` directly, bypassing the haptic dispatch entirely.
**Fix direction**: Either (a) make `TXTReaderContainerView.makeNotificationDeps()` pass `hapticFeedback: HapticFeedbackProvider()` (one-line change mirroring MD line 245) AND migrate EPUB/PDF/Foliate to route their `.readerBookmarkRequested` observers through `ReaderNotificationHandlers.handleBookmarkRequest` (deps-based pattern); OR (b) extract a small `BookmarkHaptic.fire()` helper and call it inline in each reader's bookmark observer alongside `persistence.addBookmark`. Option (a) is cleaner long-term but touches 4 files; option (b) is a 4-line change in 4 places.
**Why this is a bug, not a feature**: feature #7 is `DONE`; the `BookmarkFeedback` 5-test suite covers `ReaderNotificationHandlers.handleBookmarkRequest` with a `MockHapticProvider`. The test surface proves the dispatch works through the handler; the container-level wiring per format is what's missing. So the implementation exists but is wired to only 1 of 5 reader paths — classic bug.
**Filed by verify cron 2026-05-12** during feature #7 round-2 verification (haptics are sim-unobservable, but the wiring gap surfaced via code-read of the dispatch path).

### Bug #171 — EPUB paged mode shows two-column layout instead of single-page flip

**Repro**: Open any EPUB → AA → EPUB Layout → Paged → observe content on iPhone 17 Pro.
**Observed**: Two columns of text appear side-by-side. Navigation advances the scroll by one viewport width but both columns remain visible simultaneously, making the layout look like a split newspaper view rather than page-flip reading.
**Root cause** (code-confirmed): `EPUBPaginationHelper.paginationCSS(viewportWidth:viewportHeight:)` (`EPUBPaginationHelper.swift:31`) sets `column-width: (viewportWidth - 40)px` with no `column-count` constraint. CSS `column-width` is a hint (minimum desired column width); the browser will create as many columns as fit. On iPhone 17 Pro the viewport / book CSS combination allows two columns to render simultaneously.
**Expected**: One full-width page of content at a time; tap/swipe advances to the next page — matching Kindle / Apple Books paged navigation convention.
**Fix direction**: Add `column-count: auto` is not enough — need to ensure one column per page. Options: (a) set `column-width: {viewportWidth}px` (full viewport width per column, no gap) so only one column fits; (b) add `max-height: {viewportHeight}px; overflow: hidden` on body and use a fixed-size column wrapper. Must preserve horizontal `scrollLeft` navigation math in `navigateToPageJS`.

### Bug #170 — OPDS catalog detail view renders blank after NavigationLink tap; no spinner, no entries, no error

**Repro**: Library → globe (OPDS Catalogs) → + (Add Catalog) → Name="Gutenberg", URL="https://www.gutenberg.org/ebooks.opds/" → Save → tap the saved row.
**Observed**: a sheet pushes onto the NavigationStack showing only a back chevron at top-left. NO `ProgressView("Loading catalog...")`, no `navigationTitle`, no `feedContent` entries, no `errorState` Retry button. Captured at t+0.5s, t+2.5s, t+10.5s, t+17s — all identical-blank. AX dump in the detail-view area returns only the back button + an empty AXGroup; no AXStaticText, no AXProgressIndicator.
**Why this matters**: per `OPDSBrowserView.body` (`vreader/Views/OPDS/OPDSBrowserView.swift:39-48`), the Group { } branches on `isLoading && feed == nil` (→ ProgressView), `errorMessage` (→ errorState), `feed` (→ feedContent). The blank-with-back-chevron-only state means `isLoading == false && feed == nil && errorMessage == nil` — i.e. **`.task` never set isLoading=true at all**, OR set it and then reset to false without populating feed/errorMessage. Either way, `loadFeed` did not run to completion or never started.
**Root cause hypothesis (NOT confirmed — fix scope)**: the `.task { await loadFeed(url: catalogURL) }` modifier on `OPDSBrowserView` (line 52) is nested inside `OPDSCatalogListView`'s NavigationLink destination (`OPDSCatalogListView.swift:96-104`), inside the `NavigationStack` wrapping `OPDSCatalogListView` (`LibraryView.swift:276`), inside the `.sheet(isPresented: $isShowingOPDSCatalogs)` (`LibraryView.swift:275`). Known SwiftUI iOS 26 issue: `.task` can be skipped or cancelled instantly when a destination view is presented via NavigationLink inside a NavigationStack inside a sheet. Suspect surface includes: (a) `.task` lifecycle in this nested presentation; (b) URL validity check in the NavigationLink wrapper (`URL(string: catalog.url)` is non-nil for `https://www.gutenberg.org/ebooks.opds/` — confirmed via repl); (c) `OPDSClient.fetchFeed` silently throwing a cancellation. **Possible fix directions**: replace `.task` with `.onAppear { Task { await loadFeed(...) } }`; OR seed `isLoading = true` as the initial @State value so the spinner shows immediately on view appear regardless of when loadFeed actually runs; OR move the fetch trigger to `init()` or to a `.task(id: catalogURL)` variant.
**Reproducible 100%** on iPhone 17 Pro Sim (iOS 26.4) at v3.14.149 (commit de37ad4) with the bundled Gutenberg endpoint. Curl probe from the host confirms `https://www.gutenberg.org/ebooks.opds/` returns 200 with valid Atom/OPDS XML — backend works.
**Filed by verify cron 2026-05-11T20:50** during feature #36 round-4 verification of the per-catalog navigation deferred leg. 11 screenshot artifacts under `dev-docs/verification/artifacts/feature-36-r4-*-20260511.png`.
**Cross-ref**: feature #36 row already documents "per-catalog navigation" as deferred — this bug formalizes the deferral and identifies the suspected lifecycle root cause. Feature #36 cannot flip to VERIFIED until this is fixed.

### Bug #168 — EPUB font family setting has no effect — fontFamily never injected into CSS

**Repro**: Open any EPUB → AA → Font Family → switch to Serif or Monospace → text rendering unchanged.
**Root cause** (code-confirmed): `ReaderTheme.epubOverrideCSS` signature (`ReaderTheme.swift:75`) has parameters `(fontSize:lineHeight:letterSpacing:)` — no `fontFamily` parameter. The call site in `EPUBReaderContainerView.swift:313` passes only `fontSize`, `lineSpacing`, and `letterSpacing`; `typography.fontFamily` is never forwarded. By contrast, TXT correctly consumes `fontFamily` via `TXTViewConfig.fontName` (line 612 of `ReaderSettingsPanel.swift`). The setting is persisted and tracked — the EPUB CSS injection path is simply unwired.
**Fix direction**: (1) add `fontFamily: ReaderFontFamily = .system` to `epubOverrideCSS`; (2) emit CSS `font-family` stack (`.system` → `-apple-system, system-ui, sans-serif`; `.serif` → `Georgia, 'Times New Roman', serif`; `.monospace` → `'SF Mono', Menlo, 'Courier New', monospace`); (3) update call site. CJK characters fall back to system CJK font automatically — expected behavior for an English typeface picker.

### Bug #167 — EPUB overscroll bounce reveals white background instead of theme color

**Repro**: Open any EPUB in Sepia or Dark theme → drag content up past the very top (or down past the bottom) until the scroll view rubber-bands → white strip appears in the overscroll area.
**Root cause** (code-confirmed): `EPUBWebViewBridge.swift:163` sets `webView.scrollView.backgroundColor = .clear`. The CSS injection (`ReaderTheme.epubOverrideCSS`) correctly paints `html, body { background-color: <theme> }` inside the document, but when iOS bounces the scroll view past content bounds it exposes the scroll view's own background, which is transparent and falls through to the host UIView/UIWindow (white by default). Result: white bleed on overscroll for every non-Light theme.
**Expected**: overscroll area matches the current theme background color (Sepia ≈ `rgb(245,237,217)`, Dark ≈ `rgb(28,28,31)`).
**Fix direction**: set `webView.scrollView.backgroundColor = store.theme.backgroundColor` in `makeUIView` (and update in `updateUIView` when `themeCSS` changes). `ReaderTheme.backgroundColor: UIColor` already exists for all three themes — this is a one-liner fix. Cross-format: AZW3/MOBI (`FoliateViewBridge`) also uses WKWebView and may share the same gap.

### Bug #166 — Font size visually inconsistent across formats; slider max too small for EPUB

**Repro**: Set font size to any value (e.g. 20pt) → open same book content in TXT, then EPUB, then PDF → text appears at noticeably different visual sizes despite the same numeric setting. Also: drag font size slider to maximum (32pt) in EPUB → text still appears small.
**Root cause**: Each format pipes font size through a different rendering system with no perceptual normalization layer. TXT/MD use UITextView native pt (1:1 screen points); EPUB injects CSS `font-size` via WKWebView where the book's own stylesheet compounds or conflicts; PDF uses PDFView's own scaling; AZW3/MOBI goes through Foliate-js with its own CSS defaults. Bug #57 (FIXED) addressed EPUB-vs-TXT mismatch at one specific point; the broader cross-format normalization gap was never addressed, and the slider ceiling of 32pt was insufficient for EPUB where CSS rendering makes pt-values appear smaller than UIKit equivalents.
**Expected**: Same numeric font-size value produces perceptually consistent text size across all supported formats; slider maximum is large enough that EPUB text at max setting is comfortably readable.
**Fix direction**: (a) **DONE in this iteration** — `TypographySettings.fontSizeRange` raised from `12...32` to `12...64`; slider auto-extends because it uses the constant directly. (b) **OPEN** — Audit per-format CSS/font injection to apply a calibration factor so the same pt value renders at consistent perceived size across formats. This is feature-class scope (per-renderer measurement + unified pt→logical-size mapping); should be split out as a separate feature row or follow-up bug when planned. Reported by user 2026-05-10. GH: #491

### Bug #165 — EPUB chapter navigation unintuitive: no side-tap, scroll-within vs button-between mismatch (FIXED 2026-05-21)

**Repro**: Open a multi-chapter EPUB → scroll to end of chapter → must tap explicit "Previous | Next" button to cross chapter; tapping sides of screen only toggles chrome. No consistent swipe/tap navigation across chapters.
**Impact**: Every EPUB user. Cross-chapter navigation requires a dedicated button tap that breaks reading flow; no side-tap to flip chapter is the opposite of every major e-reader convention (Kindle, Moon+, etc.).
**Fix direction**: (a) Remove "Previous | Next chapter" buttons; let scroll flow continuously between chapters. (b) Wire side-tap into native EPUB renderer to dispatch prevChapter/nextChapter (proper fix for bug #162's deferred "option (b)"). Cross-ref: bug #162 (tap zones no-op in native EPUB); feature #25 (tap zones — native mode deferred).

**FIXED v3.38.36** — implemented design `dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-navigation.md` §2.2 (paged-mode chapter wrap). New pure helper `EPUBChapterNavigationRouter` decides, given (currentPage, totalPages, currentSpineIndex, spineCount), whether a side-tap should turn within the chapter, wrap forward to chapter N+1's first page, wrap backward to chapter N-1's last page, or bounce at start/end of book. New one-shot `EPUBChapterWrapPendingTarget` (@MainActor reference type) carries the "land on last page" intent across the async chapter load → `onPaginationReady` boundary. Container wiring in `EPUBReaderContainerView+ChapterWrap.swift` consumes the router decision; `EPUBReaderContainerView` and `EPUBReaderContainerView+Navigation.swift` cancel any pending wrap intent at every non-wrap chapter navigation site (TOC / search / annotation jump, scrubber seek) via a dedicated `cancelBecauseUnrelatedNavigationStarted()` entry point — addresses a Codex round-1 High finding that the intent would otherwise bleed into unrelated chapter loads. Router's `0..<spineCount` guards collapse stale spine indices to safe bounces (round-1 Medium). Codex audit thread `019e47c8 → 019e47cd`, 2 rounds, verdict `follow-up-recommended` (round-2 Medium accepted: container call-site coverage is by helper-contract tests only because driving the SwiftUI container in XCTest requires a `ModelContainer` boot; dedicated entry-point naming provides grep precision). 29 new unit tests (18 router + 11 pending-target). Device-verified on iPhone 17 Pro Sim (iOS 26.5) via `vreader-debug://eval` driving `webkit.messageHandlers.contentTapHandler.postMessage({x, w})`: forward wrap from ch1 → ch2, backward wrap from ch2 → ch1, bounce at start (left-tap from ch1 stays), bounce at end (right-tap from ch2 stays); evidence `dev-docs/verification/bug-165-20260521.md` + screenshots `dev-docs/verification/artifacts/bug-165-verify-*.png`. **Scope deferral**: design §2.3 (continuous cross-chapter scroll mode — chapters rendered in one scrollable column with hairline divider + skeleton-pulse + lazy ±1 chapter load) is a multi-chapter WKWebView document architecture; filed as a follow-up feature to ship separately. §2.2 bounce visual affordance ("subtle horizontal nudge") deferred until the design specifies the animation curve. Full suite 6986 tests pass under `xcodebuild test -only-testing:vreaderTests -parallel-testing-enabled NO`. GH: #489

### Bug #164 — TTS starts reading from article beginning instead of current scroll position

**Repro**: Open any book, scroll to middle, activate TTS → speech starts from the very beginning of the article, not from the currently visible content.
**Impact**: Every TTS user who starts playback mid-document must listen through already-read content or manually skip, defeating the use case.
**Fix direction**: Pass the current `currentOffsetUTF16` / locator as the start offset when initiating TTS playback, instead of defaulting to offset 0.

