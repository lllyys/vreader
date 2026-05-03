# Bug Tracker

Track bugs here. Tell the agent "fix bug #N" to start a fix.

## Rules

> **Binding for this file.** The rules and workflow below govern every change made to `docs/bugs.md`. AGENTS.md treats them as the authoritative bug-tracker workflow.

- **Bugs vs features**: If something was implemented but doesn't work correctly, it is a **bug** — track it here. If something was never implemented, it is a **feature** — track it in `docs/features.md`. Never mix them.
- **Partial implementations**: If something is partially implemented, the broken part is a bug here; the missing capability is a feature in `docs/features.md`. Link them.
- **Source of truth**: This **Summary table** is the single source of truth for bug status.
- **Open bug details**: Bugs with status TODO/IN PROGRESS/REOPENED should have an entry in `## Open Bug Details` with repro context. Move to archive on FIXED.
- **History**: Root causes, solutions, and lessons for FIXED bugs are archived in `archive/bugs-history.md`.

## How to use

1. Add bugs as you find them (fill in Summary and File/Area at minimum)
2. Tell the agent: "fix bug #N" — it will follow the workflow below
3. Agent updates Status when done

- **Bug fix workflow** (follow this order for every bug):
  1. **Understand**: Read the file/area, reproduce the symptom, identify root cause (not just location). Run `/codex-toolkit:bug-analyze`. If it is not a bug, move it to `docs/features.md`.
  2. **RED**: Write a failing test that proves the bug exists.
  3. **GREEN**: Minimal fix to make the test pass.
  4. **REFACTOR**: Clean up without changing behavior.
  5. **Verify**: Run tests, confirm the fix, check for regressions. Run `/codex-toolkit:audit-fix` on changed files.
  6. **Track**: Update status in the Summary table to FIXED.
  7. Do NOT commit unless explicitly requested.
  8. Record cause, solution, and lessons in `archive/bugs-history.md`. Remove the bug's entry from `## Open Bug Details`.
- **GitHub Issue closure** (post-merge finalizer — see `AGENTS.md` for full policy):
  - If the bug has a `GH: #N` in Notes, close the GitHub Issue only after:
    1. Status is FIXED in this file.
    2. Fix is merged to `main`.
    3. Closure comment posted with commit SHA, test evidence, and cause summary.
  - PRs use `Refs #N`, not `Fixes #N` (prevents premature auto-close).

## Statuses

- `TODO` — not started
- `IN PROGRESS` — being worked on
- `FIXED` — fix verified in working tree (not necessarily committed)
- `REOPENED` — previously fixed but regressed; link to original fix
- `DUPLICATE` — duplicate of another bug; note `DUPLICATE OF #N`
- `WONT FIX` — intentional behavior or out of scope

## Open Bug Detail

<!-- For each TODO/IN PROGRESS/REOPENED bug, add a short entry here.
     Max 6 lines per bug. Remove on FIXED (move to archive). -->

### Bug #110 — WebDAV Test Connection blocked by App Transport Security on Tailscale URL
- **Repro**: Settings → WebDAV Backup → enter `http://<machine>.tail-XXXXX.ts.net:8080` + creds → tap Test Connection
- **Expected**: HTTP 401 → "Authentication failed" (or success if creds valid)
- **Actual**: "Connection error: The resource could not be loaded because the App Transport Security policy requires the use of a secure connection." (request never leaves the device)
- **Root cause**: `project.yml` does not declare `NSAppTransportSecurity` exceptions. iOS ATS blocks HTTP to non-loopback hostnames. Localhost works because iOS treats loopback as exempt.
- **Impact**: Tailscale-fronted use case (documented in WebDAVSettingsView footer + companion repo `vreader-webdav-host`) is broken. Plain HTTP to Nutstore/NextCloud/Synology over their public hostnames also fails for the same reason.
- **Fix options**: (a) `NSAllowsLocalNetworking: YES` + per-domain `NSExceptionDomains` for `ts.net` — minimal exception, safest for App Store review; (b) `NSAllowsArbitraryLoads: YES` — broadest, but App Store may push back; (c) document HTTPS-only and ship with no ATS change. Recommend (a).
- **Screenshots**: `docs/assets/images/clipboard-1777788873034-qu9x-1777788873038-void.png`

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

### Bug #88 — Imported annotations not visually highlighted
- **Repro**: Import annotations JSON, check if highlights are rendered in reader
- **Expected**: Imported highlights visible in the reader
- **Actual**: DB records created but reader doesn't refresh visual highlights
- **Root cause**: Import writes to DB but no notification to reader to re-render
- **Fix**: Added `.readerHighlightsDidImport` notification; all format containers observe and call `coordinator.restoreAll()`


## Summary

| #  | Summary                                                                                               | File/Area  | Severity | Status   | Notes                                                                                                                                                                                              |
| -- | ----------------------------------------------------------------------------------------------------- | ---------- | -------- | -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1  | CJK search returns no results                                                                         | Search/*  | High     | FIXED    | FTS5 tokenization + encoding + race condition (0d48d0a)                                                                                                                                            |
| 2  | The search results are incomplete; only a few results are shown.                                      | Search/*  | High     | FIXED    | FTS5 returned 1 hit per segment; now expands to all occurrences via span map                                                                                                                       |
| 3  | Progress cannot be saved. Each time the TXT file is opened, it starts from the beginning.             | Reader/*  | High     | FIXED    | TXTTextViewBridge delegate was nil; wired ViewModel as delegate                                                                                                                                    |
| 4  | The performance of text search is poor. I have to wait for a while each time I open the search panel. | Reader/*  | Medium   | FIXED    | SearchViewModel created before indexing; panel opens instantly, index builds in background                                                                                                         |
| 5  | The performance of the text page is poor. I have to wait for a while each time I open a TXT book.     | TXT/*     | Medium   | FIXED    | NSAttributedString now built on background thread via TXTAttributedStringBuilder; UI shows spinner until ready                                                                                     |
| 6  | The reading settings do not take effect.                                                              | Reader/*  | High     | FIXED    | settingsStore was created but never passed to reader host/container views; now wired through TXT and MD readers                                                                                    |
| 7  | Scrolling performance is poor in the TXT reader.                                                      | TXT/*     | Medium   | FIXED    | Enabled allowsNonContiguousLayout + throttled scroll callbacks to \~10fps with end-of-scroll flush                                                                                                 |
| 8  | There is nothing displayed on the reading panel.                                                      | Reader/*  | Medium   | FIXED    | Annotations panel had placeholder views; wired real BookmarkListView, HighlightListView, AnnotationListView, TOCListView with PersistenceActor                                                     |
| 9  | The theme does not work in EPUB.                                                                      | EPUB/*    | High     | FIXED    | Threaded settingsStore into EPUB host/container/bridge; inject CSS via evaluateJavaScript on page load + live theme switch                                                                         |
| 10 | Theme changes do not take effect in TXT without font size change or reopen.                           | TXT/*     | High     | FIXED    | configChanged in TXTTextViewBridge now compares textColor, backgroundColor, letterSpacing (was only fontSize/fontName/lineSpacing)                                                                 |
| 11 | Opening a large TXT file causes very poor scrolling; nearly impossible to scroll.                     | TXT/*     | Medium   | FIXED    | Background attributed string build + allowsNonContiguousLayout + scroll throttling; main thread no longer blocks on NSAttributedString creation                                                    |
| 12 | The toolbar cannot be hidden while reading.                                                           | Reader/*  | Medium   | FIXED    | Added isChromeVisible toggle; tap content to show/hide nav bar + status bar                                                                                                                        |
| 13 | Large CJK TXT file (9.5MB) still has poor scrolling performance                                       | TXT/*     | High     | FIXED    | UITextView can't handle 9.5MB attributed string; switched to UITableView chunked renderer (TXTChunkedReaderBridge) for files > 500K UTF-16 units                                                   |
| 14 | App startup and library page loading is too slow                                                      | Library/* | Medium   | FIXED    | Added isInitialLoad state to LibraryViewModel; LibraryView shows ProgressView during initial fetch instead of empty state flash                                                                    |
| 15 | Observation tracking feedback loop — UITextView infinite layout invalidation, CPU 100%, app frozen    | Reader/*  | Critical | FIXED    | viewModel.currentOffsetUTF16 read in body created observation cycle; replaced with @State initialRestoreOffset + hasRestoredPosition one-shot flag                                                 |
| 16 | Large CJK TXT file can't remember reading progress in chunked reader                                  | TXT/*     | High     | FIXED    | Same observation cycle as #15; fixed by capturing offset once after open, passing to bridge as fixed @State value                                                                                  |
| 17 | Scrolling stuck and rebounds every time in TXT reader                                                 | Reader/*  | High     | FIXED    | Same root cause as #15 — restoreOffset re-applied on every scroll; removed updateUIView restore block, made restore one-shot in makeUIView only                                                    |
| 18 | Failed to create 1206x0 image slot                                                                    | Library/* | Low      | WONT FIX | CoreGraphics cosmetic log noise from UIKit snapshot of zero-height cell during transitions; no user-visible impact                                                                                 |
| 19 | All TXT files cannot remember reading progress                                                        | Reader/*  | High     | FIXED    | asyncAfter(0.15s) in makeUIView allows layout pass before scroll restore; was using async which ran before view had a valid frame                                                                  |
| 20 | EPUB cannot hide the toolbar                                                                          | EPUB/*    | Medium   | FIXED    | WKWebView consumed tap events; added JS click handler + contentTapHandler WKScriptMessage + NotificationCenter                                                                                     |
| 21 | TXT needs two clicks to hide toolbar                                                                  | TXT/*     | Medium   | FIXED    | UITextView consumed first tap; added UITapGestureRecognizer with shouldRecognizeSimultaneously + NotificationCenter                                                                                |
| 22 | Black padding at top after hiding toolbar                                                             | Reader/*  | Medium   | FIXED    | Added conditional .ignoresSafeArea(edges: .top) when chrome is hidden                                                                                                                              |
| 23 | All TXT files cannot remember reading progress (regression of #19)                                    | Reader/*  | High     | FIXED    | Three fixes: scenePhase wiring, isOpenComplete race guard, scroll restore retry with frame-validity check                                                                                          |
| 24 | Position save lost intermittently after reinstall (regression of #19/#23)                             | Reader/*  | Critical | FIXED    | onBackground() fire-and-forget Task raced with process suspension; made async + beginBackgroundTask; added scenePhase to EPUB/PDF                                                                  |
| 25 | Position still drifts/resets on reopen (regression of #24)                                            | Reader/*  | Critical | FIXED    | TextKit 1 mode switch relayout resets contentOffset to 0; ghost scrollViewDidScroll overwrites saved position; suppressed with flag+time guards                                                    |
| 26 | Position visually resets to top despite correct save (regression of #25)                              | Reader/*  | Critical | FIXED    | Suppress guards blocked bad saves but didn't re-apply visual position; added Phase 2 restore at t+0.8s after TextKit relayout settles                                                              |
| 27 | Content flashes at beginning then jumps to saved position (UX)                                        | TXT/*     | Medium   | FIXED    | UITextView visible during 0.8s restore delay; hide with alpha=0 until Phase 2 completes, then fade in                                                                                              |
| 28 | All the search results are the same                                                                   | Search/*  | High     | FIXED    | FTS5 snippet() is per-row; expanded occurrences shared same snippet; added source_texts table + per-occurrence snippet extraction                                                                 |
| 29 | After changing font size, theme changes to different pattern                                          | TXT/*     | Medium   | FIXED    | attrStringKey excluded color properties; theme changes didn't trigger NSAttributedString rebuild; added color hashes to key                                                                        |
| 30 | Reading settings bar too long, covering content                                                       | Reader/*  | Low      | FIXED    | Settings sheet presentationDetents included .large; constrained to .medium only                                                                                                                    |
| 31 | Cannot add bookmarks, contents, highlights, or notes                                                  | Reader/*  | High     | FIXED    | No bookmark creation path; added NotificationCenter-based bookmark via toolbar button + modelContainer passthrough to all container views                                                          |
| 32 | Cannot hide top and bottom bars in PDF files                                                          | PDF/*     | Medium   | FIXED    | PDFView internal gestures consumed taps; added UITapGestureRecognizer with shouldRecognizeSimultaneously + .readerContentTapped notification                                                       |
| 33 | TXT files do not show reading time or remaining time                                                  | TXT/*     | Low      | FIXED    | No bottom overlay in TXT reader; added txtBottomOverlay showing progress % and session time                                                                                                        |
| 34 | Sorting by reading time and last read is unavailable                                                  | Library/* | Medium   | FIXED    | ReadingStats.recompute(from:) never called; wired into all 4 ViewModel close() methods via PersistenceActor+Stats extension                                                                        |
| 35 | Bottom bar does not share theme with top bar                                                          | Reader/*  | Low      | FIXED    | Overlays used .ultraThinMaterial (system theme); replaced with theme-matched colors + .toolbarColorScheme for nav bar                                                                              |
| 36 | Cannot jump to searched location when tapped                                                          | Reader/*  | High     | FIXED    | onNavigate was a no-op stub; wired via .readerNavigateToLocator notification to all 4 format container views                                                                                       |
| 37 | Theme/font changes take time to apply                                                                 | TXT/*     | Medium   | FIXED    | Loading spinner shown during settings-driven rebuild; changed to keep old content visible, only show spinner for initial load                                                                      |
| 38 | Slow position restore on file reopen                                                                  | TXT/*     | Low      | FIXED    | Fixed 0.8s Phase 2 delay; added ensureLayout() for synchronous TextKit layout, reduced total to \~0.3s                                                                                             |
| 39 | Bottom bar cannot be hidden when tapped                                                               | Reader/*  | Medium   | FIXED    | isChromeVisible only controlled nav bar; added local isChromeVisible to all container views, gated bottom overlays on it                                                                           |
| 40 | Search navigation jumps to wrong location                                                             | Reader/*  | High     | FIXED    | Missing ensureLayout in search scroll path + missing match range in Locator; added ensureLayout + populated charRangeStart/End in resolver                                                         |
| 41 | Slow position restore after reopening file (regression of #38)                                        | TXT/*     | Low      | FIXED    | Phase 2 delay 0.15s + fade-in 0.15s; reduced Phase 2 to 0.05s, removed animation                                                                                                                   |
| 42 | Bookmarks cannot be edited or navigated                                                               | Reader/*  | High     | FIXED    | No-op onNavigate in annotations panel; wired all tabs + added bookmark rename via context menu + alert                                                                                             |
| 43 | Search result not highlighted when navigated                                                          | Reader/*  | Medium   | FIXED    | v2: TXT scrollViewDidScroll cleared highlight during programmatic scroll — added isProgrammaticScroll guard. EPUB/PDF: added search highlight via JS injection and PDFKit findString respectively. |
| 44 | Cannot manually highlight or add notes                                                                | Reader/*  | High     | FIXED    | No edit menu for text selection; added Highlight/Add Note to UITextView edit menu via editMenuForTextIn + NotificationCenter to container views                                                    |
| 45 | Books sorted by "Last Read" shows stale order                                                         | Library/* | Medium   | FIXED    | v5: recomputeStats() now always sets lastReadAt=Date() — sessions <5s were discarded leaving nil; DB now correct on refresh/restart                                                                |
| 46 | Manual highlight saves record but content not highlighted                                             | Reader/*  | Medium   | FIXED    | No visual feedback on save; added immediate highlightRange set in .readerHighlightRequested handler (3s auto-clear)                                                                                |
| 47 | App crashes after navigating to search result or bookmark then tapping screen                         | Reader/*  | Critical | FIXED    | v12: HighlightingLayoutManager.drawBackground() — zero text storage mutation for highlights; decouples highlight visualization from text storage                                                   |
| 48 | Highlight/note edit menu missing in large TXT files (chunked reader)                                  | TXT/*     | High     | FIXED    | TXTChunkedReaderBridge lacked UITextViewDelegate; added conformance + editMenuForTextIn with chunk offset translation                                                                              |
| 49 | Annotation note input too narrow for long text                                                        | Reader/*  | Low      | FIXED    | .alert TextField is single-line; replaced with .sheet + AddNoteSheet using TextEditor for multi-line input                                                                                         |
| 50 | Highlight/annotation navigation fails silently when tapped in panel                                   | Reader/*  | High     | FIXED    | LocatorFactory.txtRange didn't set charOffsetUTF16; added it + fallback to charRangeStartUTF16 in navigation handlers                                                                              |
| 51 | Annotation notes don't show the original annotated text                                               | Reader/*  | Medium   | FIXED    | locator.textQuote already had the text; added display in AnnotationRowView as italicized quote above note content                                                                                  |
| 52 | Large CJK TXT annotation panel navigation fails (chunked reader)                                      | TXT/*     | High     | FIXED    | Added scrollToOffset to chunked bridge + scrollToGlobalOffset with binary search chunk mapping + updateUIView handler                                                                              |
| 53 | Highlight visual not applied in large CJK TXT (chunked reader)                                        | TXT/*     | Medium   | FIXED    | Added highlightRange to chunked bridge + applyHighlight with global-to-local range conversion + 3s auto-clear timer                                                                                |
| 54 | Highlight disappears in large CJK TXT after selecting other text and canceling                        | TXT/*     | Medium   | FIXED    | v2: Distinguish temporary (search) vs persistent (user) highlights — only auto-clear temporary; persistent keeps activeHighlight state indefinitely                                                |
| 55 | Highlights not visible when file is reopened                                                          | Reader/*  | Medium   | FIXED    | Fetch highlights from DB on file open; pass as persistedHighlights to bridges; baked into attributed string via buildHighlightedString                                                             |
| 56 | PDF crash after adding highlight and reopening                                                        | PDF/*     | High     | FIXED    | v1: isValidRect guard. v2: SchemaV2 migration crash — changed `anchor: AnnotationAnchor?` to `anchorData: Data?` with safe @Transient getter                                                       |
| 57 | EPUB and TXT font sizes render differently at same setting value                                      | Reader/*  | Medium   | FIXED    | EPUB CSS: `body * { font-size: inherit !important }` with `h1-h6 { font-size: revert !important }`                                                                                                 |
| 58 | EPUB reading position only chapter-level, not intra-chapter scroll offset                             | EPUB/*    | Medium   | FIXED    | Pass restored progression as seekScrollFraction on EPUB load                                                                                                                                       |
| 59 | Gap between progress bar and bottom bar                                                               | Reader/*  | Low      | FIXED    | VStack(spacing: 0) on all 4 format containers                                                                                                                                                      |
| 60 | Large TXT files (\~15MB) very slow to open                                                            | TXT/*     | High     | FIXED    | Sample-based encoding detection (8KB) before full decode; word count deferred to background Task                                                                                                    |
| 61 | Search is slow in large TXT files (\~15MB)                                                            | Search/*  | High     | FIXED    | Persisted segment offsets restored via `restoreSegmentOffsets()` on reopen; search indexing deferred to on-demand                                                                                   |
| 62 | Content shifts down when top bar reappears                                                            | Reader/*  | Medium   | FIXED    | v3: replaced system nav bar with custom `ReaderChromeBar` overlay — floats on top, no safe area change, content never moves                                                                        |
| 63 | Progress bar unresponsive (can't scroll or toggle) in Native mode                                     | Reader/*  | High     | FIXED    | `TapZoneModifier` now uses VStack with `bottomInset: 100` exclusion zone + `allowsHitTesting(false)` so Slider receives touches                                                                    |
| 64 | All files and all formats are slow to load                                                            | Reader/*  | High     | FIXED    | Deferred 5 eager `.task` blocks: AI setup/text → on AI invoke; search → on search open; TOC → on annotations open; rules → unified only                                                            |
| 65 | Empty state description text not visible in UI test                                                   | Library/* | Low      | FIXED    | Test string stale after MD format was added; updated to include "Markdown"                                                                                                                         |
| 66 | Annotations panel tab placeholders not found in UI test                                               | Reader/*  | Low      | FIXED    | Tests had old placeholder text; updated 4 strings to match real ContentUnavailableView text                                                                                                        |
| 67 | Swipe-to-delete not working in list mode UI test                                                      | Library/* | Medium   | FIXED    | findFirstRow() only checked app.buttons; added app.cells fallback for iOS 26 List rendering                                                                                                        |
| 68 | Toolbar buttons hidden at large Dynamic Type sizes (xxxLarge, AX5)                                    | Library/* | Medium   | FIXED    | Tests used .exists (no wait); replaced with waitForExistence(timeout: 5) for toolbar rendering                                                                                                     |
| 69 | PDF reader placeholder not appearing in UI test                                                       | PDF/*     | Medium   | FIXED    | PDF reader fully implemented; tests now verify pdfReaderContainer instead of stale placeholder                                                                                                     |
| 70 | Cannot scroll content in native mode — all formats                                                    | Reader/*  | High     | FIXED    | Removed `.tapZoneOverlay()` from native path — bridges already handle taps via UITapGestureRecognizer                                                                                              |
| 71 | Reader top bar looks ugly — buttons small, inconsistent with bottom bar                               | Reader/*  | Medium   | FIXED    | 44pt height, 20pt icons, 44x44 touch targets, theme backgroundColor at 0.92 opacity — matches bottom bar |
| 72 | Library navigation bar visible during reader loading transition                                       | Reader/*  | Low      | FIXED    | v3: Replace NavigationLink with Button + isPushingReader flag — hides toolbar before push animation starts. GH: #29 |
| 73 | Reader top bar hidden behind Dynamic Island                                                           | Reader/*  | High     | FIXED    | Replaced GeometryReader insets with UIWindowScene safe area lookup — immune to parent ignoresSafeArea |
| 74 | EPUB TOC shows "Section XXX" instead of real chapter titles                                           | EPUB/*    | Medium   | FIXED    | Parse EPUB 3 nav.xhtml + EPUB 2 toc.ncx for real titles; `withResolvedTitles()` applies to spine items |
| 75 | Sort preference not remembered across restarts                                                        | Library/* | Medium   | FIXED    | Wired `PreferenceStore` into LibraryViewModel init; persist sortOrder/viewMode on change, restore on creation |
| 76 | Annotations panel tab order — Contents should be before Bookmarks                                    | Reader/*  | Low      | FIXED    | Swapped enum case order: Contents first, Bookmarks second. Default tab → .toc |
| 77 | Cannot add highlight in native EPUB                                                                   | EPUB/*    | High     | FIXED    | JS buffering in EPUBHighlightRenderer; deliverOrBuffer flushes on callback set. Callback swap race documented but low-impact |
| 78 | Highlight visual persists after deletion                                                              | Reader/*  | Medium   | FIXED    | Added `.readerHighlightRemoved` notification; EPUB: injects removeHighlightJS; TXT/MD: re-fetches persistedHighlightRanges |
| 79 | Search panel slow to open — deferred setup delay                                                      | Reader/*  | Medium   | FIXED    | Split setup: `prepareService()` eagerly creates store+service+VM on reader open; indexing still deferred |
| 80 | Cannot set custom book cover via context menu                                                         | Library/* | Medium   | FIXED    | Separate `isShowingCoverPicker` state + 0.3s delay for context menu dismissal before picker presents |
| 81 | Tap zones do nothing in native mode                                                                   | Reader/*  | High     | FIXED    | Center tap works via bridge handlers; left/right zones only functional in unified paged mode (by design) |
| 82 | Paged mode still scrolls instead of paginating                                                        | Reader/*  | High     | FIXED    | Split guard: isPagedMode=false destroys navigator; isPagedMode=true with nil attrText preserves it |
| 83 | TXT TOC not detected for some files                                                                   | Reader/*  | Medium   | FIXED    | Enabled 6 more rules (9,10,13,14,20,23) — now 14/25 enabled by default |
| 84 | Per-book settings affect all books instead of one                                                     | Reader/*  | Medium   | FIXED    | Added applyResolvedSettings() + .task on book open to load/apply per-book overrides |
| 85 | Cannot add books to collections                                                                       | Library/* | Medium   | FIXED    | Added "Add to Collection" submenu to book context menu with collection picker |
| 86 | Tags never shown in collection sidebar                                                                | Library/* | Medium   | FIXED    | Added fetchAllTags()/fetchAllSeriesNames(); LibraryView now loads and passes real data |
| 87 | PDF highlights still visible after deletion                                                           | PDF/*     | Medium   | FIXED    | PDFReaderContainerView now delegates highlightRemoved to HighlightCoordinator (R4b audit fix) |
| 88 | Imported annotations not visually highlighted                                                         | Reader/*  | Medium   | FIXED    | Added .readerHighlightsDidImport notification; all containers call coordinator.restoreAll() |
| 89 | Books still slow to open                                                                              | Reader/*  | Critical | FIXED    | GH: #16. Root cause: SearchCoordinator SQLite open on @MainActor (500ms-2s). Also: chapter-based TXT, EPUB cache, deferred highlights/session |
| 90 | AI buttons visible when consent is off                                                                | AI/*      | Medium   | TODO     | AIReaderAvailability only checks feature flag + API key, not consent |
| 91 | Blank panel when tapping Translate without AI configured                                              | AI/*      | Medium   | TODO     | No guard for missing API key/consent before presenting AI panel |
| 92 | AI only reads book title, not selected section                                                        | AI/*      | High     | FIXED    | BookContentCache now uses TXTService encoding detection instead of UTF-8 only |
| 93 | Chat sessions not persisted across panel dismiss                                                      | AI/*      | Medium   | TODO     | Multi-turn chat history lost when AI panel closes |
| 94 | Keyboard cannot be dismissed while chatting                                                            | AI/*      | Low      | TODO     | AIChatView input field missing dismiss gesture/toolbar |
| 95 | "Translate" opens Summarize panel instead of Translation                                              | AI/*      | High     | FIXED    | AIReaderPanel accepts initialTab parameter; translate handler passes .translate |
| 96 | TTS no sound and no error indication                                                                  | TTS/*     | High     | FIXED    | Added AVAudioSession.setCategory(.playback) before speaking |
| 97 | TTS control bar overlaps bottom bar                                                                   | Reader/*  | Medium   | FIXED    | Pass ttsService to format containers; hide bottom overlay when TTS active |
| 98 | Text Transforms fail (simp/trad or replacement)                                                       | Reader/*  | Medium   | FIXED    | sourceText storage + didSet on activeTransforms re-applies; all 3 load methods store sourceText |
| 99 | Search results not highlighted in some TXT files                                                      | Search/*  | Medium   | TODO     | Highlight navigation fails for specific encoding/chunking cases |
| 100| Book source cannot be saved                                                                           | BookSrc/* | High     | FIXED    | Added explicit modelContext.save() after insert in BookSourceListView |
| 101| Imported book sources not visible, search button grey                                                 | BookSrc/* | High     | FIXED    | Added BookSource + ContentReplacementRule to SchemaV3.models |

| 102| EPUB fails to load chapter content                                                                    | EPUB/*    | High     | FIXED    | Selective extraction only pre-extracts first chapter; added ensureChapterExtracted() before setting contentURL |
| 103| Cannot add highlight in native EPUB (JS dropped when onInjectJS is nil)                               | EPUB/*    | High     | TODO     | Race between .task callback setup and highlight creation; restoreHighlightsOnLoad swap loses concurrent JS. Bug #77 RED tests document this. |
| 104| EPUB 3 nav titles not extracted (shows "Section N" instead of real titles)                             | EPUB/*    | Medium   | REOPENED | Bug #74 marked FIXED but EPUBParserTests.epub3NavTitlesExtracted still fails. withResolvedTitles() may not parse nav.xhtml correctly. |
| 105| Highlighted snippet multi-word overlap not handled                                                     | Search/*  | Low      | TODO     | HighlightedSnippetTests.multiWordQuery_overlappingMatches_handled fails. Bold run count is 1, expected >=2 for overlapping matches. |
| 106| AZW3 reader stuck on "Opening book" — loading never completes                                         | Foliate/* | High     | FIXED    | Switched to loadHTMLString+base64 (WKURLSchemeHandler fetch broken on device). GH: #115 |
| 107| Cover images with light/white edges show visible "padding" in library grid                             | Library/* | Low      | TODO     | Cover art with white areas at edges blends into white page background, creating illusion of padding. Need auto-crop or contrast treatment. |
| 108| AZW3/Foliate reader: center tap does not toggle chrome                                                 | Foliate/* | Medium   | TODO     | Toolbar stays visible on center tap in FoliateSpikeView. EPUB chrome toggle works. WKWebView may consume tap. |
| 109| TXT chapter mode: progress bar shows book progress instead of chapter progress                         | TXT/*     | Medium   | FIXED    | Fixed in bfd8345. Added currentChapterLocalUTF16 to TXTReaderViewModel; bridge stores local offset, persistence converts to global. 4 new tests. GH: #31 |
| 110| WebDAV Test Connection blocked by App Transport Security on Tailscale URL                              | Backup/*  | High     | TODO     | iOS ATS rejects plain HTTP to `*.ts.net` (and any non-loopback host). Test Connection on Tailscale URL fails with "The resource could not be loaded because the App Transport Security policy requires the use of a secure connection." Backup feature unusable over Tailscale despite being a documented use case. Fix: add NSAppTransportSecurity exception in project.yml (NSAllowsLocalNetworking + per-domain exception for `.ts.net`, OR NSAllowsArbitraryLoads with App Store-review caveat). GH: #136 |
