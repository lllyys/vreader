# Comprehensive Manual Testing Guide: Feature #42 -- Foliate-js Unified Reader Engine (Stage 1: AZW3/MOBI)

**Last updated:** 2026-03-26
**Scope:** Stage 1 only -- AZW3/MOBI format support via Foliate-js. EPUB, PDF, and TXT readers are unchanged.
**Test device:** Real iPhone required (WKWebView + WKURLSchemeHandler behavior differs on simulator).
**Simulator alternative:** iPhone 17 Pro (Dynamic Island -- catches safe area issues).

---

## Quick Checklist (with Priority)

Priority: **P0** = must pass before merge, **P1** = should pass, **P2** = nice to have

### P0 — Critical Path (must pass)

- [ ] **1.1** Import .azw3 file → appears in library with AZW3 badge
- [ ] **2.1** Open AZW3 → FoliateReaderHost loads, book renders
- [ ] **3.1** Page turns work (swipe/tap)
- [ ] **3.2** Paginated layout renders correctly
- [ ] **4.1** Close → reopen → position restored via CFI
- [ ] **9.1** Corrupt file → clear error, no crash
- [ ] **9.2** DRM file → clear error, no crash
- [ ] **11.1** EPUB reader still works (regression)
- [ ] **11.2** PDF reader still works (regression)
- [ ] **11.3** TXT reader still works (regression)

### P1 — Important Features

- [ ] **1.2** Import .mobi → normalized to azw3
- [ ] **1.3** Import .azw → normalized to azw3
- [ ] **1.5** DRM-protected → error message on open
- [ ] **1.6** Large book (>50MB) → loads without crash
- [ ] **2.2** Scheme handler serves JS bundle + book correctly
- [ ] **3.4** Text renders legibly
- [ ] **3.5** Images display correctly
- [ ] **3.6** TOC populates and navigates
- [ ] **3.7** Progress bar shows correct position
- [ ] **4.2** Background → foreground → position preserved
- [ ] **4.3** Force quit → reopen → position restored
- [ ] **5.1** Select text → Highlight button appears
- [ ] **5.2** Create highlight → persists
- [ ] **6.1** Search finds text in AZW3
- [ ] **6.2** Tap search result → navigates to position
- [ ] **8.1** Font size change updates reader
- [ ] **8.2** Theme change (light/dark) updates reader
- [ ] **9.9** Offline → still works
- [ ] **10.1** Tap content → chrome toggles
- [ ] **10.4** Back to library works

### P2 — Edge Cases & Polish

- [ ] **1.4** Import .prc → normalized to azw3
- [ ] **1.7** Library shows correct format icon
- [ ] **1.8** Duplicate detection works
- [ ] **2.3** Loading indicator shown during parse
- [ ] **2.4** Metadata (title, sections) shown after load
- [ ] **3.3** Scrolled layout works (if toggle exists)
- [ ] **4.4** Close triggers final position save
- [ ] **5.3** Copy text works
- [ ] **5.4** Highlight visible in annotations list
- [ ] **5.5** Highlights restore on reopen
- [ ] **6.3** Empty search results handled
- [ ] **7.1** TTS reads aloud
- [ ] **7.2** Word highlighting tracks speech
- [ ] **7.3** TTS controls (pause/resume/stop)
- [ ] **8.3** Line spacing change
- [ ] **9.3** Unsupported MOBI variant → error
- [ ] **9.4** Missing book file → error
- [ ] **9.5** Missing JS bundle → error
- [ ] **9.6** WebView crash → auto-reload
- [ ] **9.7** Book file deleted while reading → error
- [ ] **9.8** Navigation policy blocks non-http URLs
- [ ] **10.2** Bottom overlay shows session time
- [ ] **10.3** Bookmark creation works
- [ ] **11.4** Mixed format library (all types coexist)
- [ ] **12.1** Long TOC chapter names
- [ ] **12.2** CJK text renders correctly
- [ ] **12.3** RTL text renders correctly
- [ ] **12.4** Image-heavy books
- [ ] **12.5** Empty book (0 sections)
- [ ] **12.6** Special characters in filename
- [ ] **12.7** External link → opens Safari (http/https only)
- [ ] **12.8** Rapid page turns don't crash
- [ ] **12.9** Orientation change handled
- [ ] **12.10** JS injection safety (special chars in metadata)
- [ ] **12.11** Multiple open/close cycles (no memory leak)
- [ ] **12.12** Concurrent format opens (no cross-contamination)
- [ ] **13.1** Position not lost on accidental dismiss
- [ ] **13.2** Position saved during background task
- [ ] **13.3** No data loss on error

---

## Prerequisites

### Environment

- Xcode installed, project builds cleanly.
- Test device running iOS 17+.
- VReader app installed on device via Xcode (Debug build, so `webView.isInspectable = true`).

### Test Files

Prepare these files in the Files app or a cloud drive accessible from the device:

| File               | Purpose                                 | Source                                  |
| ------------------ | --------------------------------------- | --------------------------------------- |
| `test-book.azw3`   | DRM-free AZW3, medium size (\~2-10MB)   | Calibre conversion or Project Gutenberg |
| `test-book.mobi`   | DRM-free MOBI file                      | Calibre or free MOBI download           |
| `test-book.azw`    | DRM-free AZW file (Kindle format 8)     | Rename a `.azw3` to `.azw`              |
| `test-book.prc`    | DRM-free PRC file (Kindle PDB variant)  | Rename a `.mobi` to `.prc`              |
| `drm-book.azw3`    | DRM-protected AZW3 from Kindle purchase | Amazon purchase (do NOT strip DRM)      |
| `large-book.azw3`  | Large AZW3 (>50MB, ideally \~80-100MB)  | Calibre with many images                |
| `corrupt.azw3`     | Truncated/corrupted AZW3                | Take a valid `.azw3`, truncate to 1KB   |
| `cjk-book.azw3`    | AZW3 with Chinese/Japanese text         | Calibre conversion of CJK source        |
| `image-heavy.azw3` | AZW3 with many inline images            | Calibre conversion of illustrated book  |
| `test-epub.epub`   | Known-working EPUB (regression)         | Any previously tested EPUB              |
| `test.pdf`         | Known-working PDF (regression)          | Any previously tested PDF               |
| `test.txt`         | Known-working TXT (regression)          | Any previously tested TXT               |

### Workspace Reset

Before starting a fresh test pass:

1. Delete VReader from device (removes all data).
2. Reinstall from Xcode.
3. Verify library is empty.

---

## 1. Import Testing

### 1.1 Import AZW3 from Files App

**Steps:**

1. Open VReader.
2. Tap the import button ("+") in the library.
3. Select `test-book.azw3` from the Files app picker.
4. Wait for import to complete.

**Expected:**

- Import succeeds without error.
- Book appears in library with title (extracted from metadata or filename).
- Library item shows format badge "AZW3" (or the format icon for AZW3).
- `book.format` in the model is `"azw3"` (the `BookFormat.azw3.rawValue`).
- The fingerprint key starts with `azw3:` (e.g., `azw3:<sha256>:<byteCount>`).
- File is copied to `Application Support/ImportedBooks/<fingerprintKey>.azw3`.

### 1.2 Import MOBI File (Normalized to AZW3)

**Steps:**

1. Tap import, select `test-book.mobi`.
2. Wait for import.

**Expected:**

- Import succeeds.
- `BookFormat.azw3.fileExtensions` includes "mobi", so `resolveFormat()` returns `.azw3`.
- Book format stored as `"azw3"` in the database.
- The fingerprint key prefix is `azw3:`.
- Book appears in library.
- The sandbox file is saved with `.azw3` extension (since `BookFormat.azw3.fileExtensions.first` is `"azw3"`).

**Note:** The actual file content is MOBI -- Foliate-js handles both MOBI and AZW3 natively.

### 1.3 Import AZW File (Normalized to AZW3)

**Steps:**

1. Tap import, select `test-book.azw`.

**Expected:**

- Same as 1.2 -- format resolves to `.azw3`.
- Fingerprint key prefix `azw3:`.

### 1.4 Import PRC File (Normalized to AZW3)

**Steps:**

1. Rename a valid `.mobi` file to `test-book.prc`.
2. Tap import, select `test-book.prc`.

**Expected:**

- `BookFormat.azw3.fileExtensions` includes "prc", so `resolveFormat()` returns `.azw3`.
- Book format stored as `"azw3"` in the database.
- Fingerprint key prefix `azw3:`.
- Book opens successfully via `FoliateReaderHost`.

### 1.5 Import DRM-Protected AZW3

**Steps:**

1. Tap import, select `drm-book.azw3`.

**Expected:**

- Import itself may succeed (the importer does not check DRM at import time).
- When opening the book (see section 2), Foliate-js will fail to parse it.
- An error message should appear. Acceptable messages:
  - "This file is DRM-protected. VReader can only open DRM-free files."
  - "Could not open this file. It may be corrupted."
  - Any clear message from the `error` message handler.
- The app does NOT crash.

### 1.6 Import Very Large Book (>50MB)

**Steps:**

1. Tap import, select `large-book.azw3` (\~80-100MB).
2. Wait for import to complete.

**Expected:**

- Import completes (may take several seconds for hash computation).
- Book appears in library.
- Opening the book (see section 2) shows a loading indicator.
- Book eventually renders (may take 2-5 seconds for Foliate-js ZIP parsing).
- No memory crash -- the scheme handler uses `Data(contentsOf:options:.mappedIfSafe)`.

### 1.7 Library Format Display

**Steps:**

1. After importing an AZW3 book, examine the library grid/list view.

**Expected:**

- The book entry shows the correct format indicator for AZW3.
- Book cover displays if metadata contains cover art; otherwise default placeholder.
- Long-press context menu works (Info, Share, Delete).
- Info sheet shows format as "AZW3".

### 1.8 Duplicate Detection

**Steps:**

1. Import `test-book.azw3` again (same file, already imported).

**Expected:**

- `ImportResult.isDuplicate` is `true`.
- App handles gracefully -- either shows a "book already exists" message or focuses the existing library entry.
- No duplicate entry in library.

---

## 2. Reader Opening

### 2.1 Open AZW3 Book -- Happy Path

**Steps:**

1. Tap an imported AZW3 book in the library.

**Expected:**

- `ReaderContainerView.nativeReaderView` dispatches to `FoliateReaderHost` (case `"azw3"`).
- `FoliateReaderHost` shows "Opening book..." `ProgressView` while loading.
- `FoliateReaderViewModel` is created with the correct `DocumentFingerprint`.
- `FoliateViewBridge.makeUIView` creates a `WKWebView` with `FoliateURLSchemeHandler`.
- The WebView loads `vreader-resource://localhost/index.html`.
- `FoliateURLSchemeHandler` serves `foliate-reader.html` from the app bundle.
- The HTML loads `./foliate-bundle.js` via `vreader-resource://localhost/foliate-bundle.js`.
- JS posts `bridge-ready` message.
- JS fetches book file via `vreader-resource://localhost/book/file`.
- Book parses successfully; JS posts `book-ready` with title and section count.
- Loading indicator disappears.
- Book content renders in the `<foliate-view>` web component.

**Verification (Debug build with Safari Web Inspector):**

1. Connect device to Mac.
2. Safari > Develop > [Device] > [WebView].
3. Console should show no errors.
4. `readerAPI` should be defined in the JS console.

### 2.2 Scheme Handler Serves Resources Correctly

**Steps:**

1. Open an AZW3 book.
2. In Safari Web Inspector, check Network tab.

**Expected:**

- `vreader-resource://localhost/index.html` -- 200, `text/html`.
- `vreader-resource://localhost/foliate-bundle.js` -- 200, `application/javascript`.
- `vreader-resource://localhost/book/file` -- 200, `application/octet-stream`.
- All responses have `Access-Control-Allow-Origin: *` header.
- No 404 errors in the console.

### 2.3 Loading Indicator

**Steps:**

1. Open an AZW3 book.
2. Observe the screen immediately after tapping.

**Expected:**

- `FoliateReaderHost` shows `ProgressView("Opening book...")` initially.
- Once `FoliateReaderViewModel` is created, `FoliateReaderContainerView` shows its own `loadingView` (centered spinner with "Opening book..." text).
- After `book-ready`, the loading view disappears and content appears.
- The loading view has `accessibilityIdentifier("foliateReaderLoading")`.
- Content view has `accessibilityIdentifier("foliateReaderContent")`.

### 2.4 Metadata After Load

**Steps:**

1. Open an AZW3 book and wait for it to load.

**Expected:**

- `viewModel.isLoading` becomes `false`.
- `viewModel.errorMessage` is `nil`.
- Bottom overlay shows TOC label (if the book has TOC entries).
- Progress starts at a position near the beginning (0% or the restored position).

---

## 3. Reading Experience

### 3.1 Page Turns (Paginated Mode)

**Steps:**

1. Open an AZW3 book (default layout is `"paginated"`).
2. Tap the right edge of the screen.
3. Tap the left edge of the screen.
4. Swipe left (forward).
5. Swipe right (backward).

**Expected:**

- Tapping right edge or swiping left advances to the next page.
- Tapping left edge or swiping right goes to the previous page.
- On each page turn, a `relocate` message is posted by Foliate-js.
- `viewModel.currentProgress` updates.
- `viewModel.currentCFI` updates.
- `viewModel.currentTOCLabel` updates when crossing section boundaries.
- Tapping the center of the screen toggles the chrome overlay (not a page turn).

### 3.2 Paginated Layout Rendering

**Steps:**

1. Open an AZW3 book in paginated mode.

**Expected:**

- Content is divided into pages that fit the screen.
- No horizontal scrollbar visible.
- Text does not overflow the viewport.
- `webView.scrollView.isScrollEnabled` is `false` (set in `FoliateViewBridge`).
- Page breaks occur at natural word boundaries (no mid-word breaks).

### 3.3 Scrolled Layout (If Toggle Exists)

**Steps:**

1. Open an AZW3 book.
2. Open reader settings.
3. Toggle to scrolled/continuous layout (if the setting exists).

**Expected:**

- Content reflows to a continuous scroll.
- `FoliateViewBridge.updateUIView` detects the `layoutFlow` change.
- JS `readerAPI.setLayout({flow: 'scrolled'})` is called.
- Vertical scrolling works normally.
- Position updates continue to fire via `relocate`.

### 3.4 Text Rendering Quality

**Steps:**

1. Open an AZW3 book and read several pages.

**Expected:**

- Text is legible at the current font size.
- Paragraphs have proper spacing.
- Indentation (if present in the source) is preserved.
- No garbled characters or encoding issues.
- Links within the book are visually distinct (underlined or colored).

### 3.5 Image Display

**Steps:**

1. Open `image-heavy.azw3`.
2. Navigate to pages with inline images.

**Expected:**

- Images render within the page.
- Images scale to fit the viewport width (no horizontal overflow).
- Images are legible (not excessively compressed).
- Pages with images still paginate correctly (no overlapping content).

### 3.6 TOC Population

**Steps:**

1. Open an AZW3 book.
2. Tap the chrome bar to show controls.
3. Open the Annotations/Contents panel (the TOC tab).

**Expected:**

- TOC entries populate from Foliate-js `book.toc` data.
- Entries show chapter titles (not generic "Section N").
- Hierarchical TOC items show proper indentation.
- Tapping a TOC entry navigates to that chapter (via `FoliateSearchAdapter.goToResultJS`).
- After navigation, the progress bar and TOC label update.

### 3.7 Progress Bar

**Steps:**

1. Open an AZW3 book.
2. Tap center to show chrome.
3. Navigate forward through several pages.
4. Observe the progress indicator.

**Expected:**

- Bottom overlay shows progress (driven by `viewModel.currentProgress`).
- Progress increases as you read forward.
- TOC label in the bottom overlay matches the current section.
- Session time display shows elapsed reading time (e.g., "5m").

---

## 4. Position Persistence

### 4.1 Close and Reopen -- Position Restored via CFI

**Steps:**

1. Open an AZW3 book.
2. Navigate to approximately 30% through the book.
3. Note the current TOC label and progress percentage.
4. Go back to the library (dismiss the reader).
5. Reopen the same book.

**Expected:**

- `FoliateReaderHost.task` loads saved position via `persistence.loadPosition(bookFingerprintKey:)`.
- `lastLocationCFI` is set to the saved CFI string.
- `FoliateViewBridge` passes `lastLocationCFI` to the coordinator.
- After `bridge-ready`, the coordinator calls `readerAPI.init({cfi})` to restore position.
- The book opens at approximately the same position (same page/section).
- Progress percentage matches (within \~1% tolerance due to layout differences).
- TOC label matches the section you were reading.

### 4.2 Background and Return -- Position Preserved

**Steps:**

1. Open an AZW3 book and navigate to a specific position.
2. Press Home or switch to another app (background the app).
3. Wait 5-10 seconds.
4. Return to VReader.

**Expected:**

- On background (`scenePhase == .background`), `viewModel.onBackground()` is called.
- Position is saved immediately (flush debounce).
- A background task (`UIApplication.shared.beginBackgroundTask`) ensures save completes.
- On return (`scenePhase == .active`), `viewModel.onForeground()` is called.
- If the WebView was terminated by iOS, it reloads and restores position.
- Content is at the same position as before backgrounding.

### 4.3 Force Quit and Reopen

**Steps:**

1. Open an AZW3 book and navigate to a specific position.
2. Wait at least 2 seconds (debounce interval for position save).
3. Force quit VReader (swipe up from app switcher).
4. Relaunch VReader.
5. Open the same book.

**Expected:**

- Position was saved by the debounce timer before force quit (if you waited >2s).
- Book reopens at the last debounced save position.
- If force quit happened within 2s of the last navigation, position may be slightly behind.

### 4.4 Close Triggers Final Save

**Steps:**

1. Open an AZW3 book.
2. Navigate to a new position.
3. Immediately go back to library (within <2s, before debounce fires).
4. Reopen the book.

**Expected:**

- `FoliateReaderContainerView.onDisappear` calls `viewModel.close()`.
- Close flushes the pending save via `lifecycle.close(locator:)`.
- A background task ensures the save completes even if the view is deallocated.
- Position is restored on next open.

---

## 5. Highlights

### 5.1 Text Selection and Highlight Action Sheet

**Steps:**

1. Open an AZW3 book.
2. Long-press on a word to start text selection.
3. Adjust selection handles if needed.

**Expected:**

- Foliate-js detects the selection and posts a `selection` message.
- `FoliateViewCoordinator` parses the `FoliateSelectionEvent` (CFI, text, rect, section index).
- `handleSelection()` in the container sets `pendingSelectionEvent` and shows the `confirmationDialog`.
- Dialog shows three buttons: "Highlight", "Copy", "Cancel".

### 5.2 Create Highlight

**Steps:**

1. Select text (as above).
2. Tap "Highlight" in the action sheet.

**Expected:**

- `FoliateHighlightRenderer.addAnnotationJS(cfi:color:)` generates JS.
- The JS calls `readerAPI.addAnnotation({value: '<CFI>', color: 'yellow'})`.
- The highlight appears visually in the reader (SVG overlay from Foliate-js).
- The `pendingSelectionEvent` is cleared.

**Note:** Full persistence to SwiftData is marked as TODO in the current code (`FoliateReaderContainerView.swift` line 129). Verify the current state of this implementation.

### 5.3 Copy Text

**Steps:**

1. Select text.
2. Tap "Copy" in the action sheet.

**Expected:**

- Selected text is copied to `UIPasteboard.general`.
- Can paste the text in another app (e.g., Notes).
- `pendingSelectionEvent` is cleared.

### 5.4 Highlight Visibility in Annotations List

**Steps:**

1. Create a highlight (if persistence is implemented).
2. Open the Annotations panel.
3. Check the Highlights tab.

**Expected:**

- Highlight appears in the list with the selected text excerpt.
- Highlight has a CFI-based anchor (not XPath).
- Tapping the highlight entry navigates back to that position in the book.

### 5.5 Highlight Restoration on Reopen

**Steps:**

1. Create highlights in an AZW3 book.
2. Close the book.
3. Reopen it.

**Expected:**

- On each `create-overlay` event (section loaded), `handleCreateOverlay(sectionIndex:)` is called.
- Currently a no-op placeholder (WI-7 implementation pending).
- Once implemented: saved highlights should be queried and restored via `FoliateHighlightRenderer.restoreAllJS`.

---

## 6. Search

### 6.1 Search in AZW3 Book

**Steps:**

1. Open an AZW3 book.
2. Open the search panel (from chrome bar).
3. Type a search query.

**Expected:**

- AZW3 uses Foliate-js built-in search (not FTS5 index).
- `FoliateSearchAdapter.searchJS(query:)` generates JS: `readerAPI.search({query: '...'})`.
- Search results stream via `search-result` message handler.
- Results appear in the search results list with excerpts.
- `search-progress` messages update a progress indicator (if implemented).
- `search-done` message indicates search completion.

### 6.2 Navigate to Search Result

**Steps:**

1. Perform a search (as above).
2. Tap a search result.

**Expected:**

- `navigateToSearchResult(cfi:)` is called.
- `FoliateSearchAdapter.goToResultJS(cfi:)` generates JS: `readerAPI.goTo('<CFI>')`.
- JS is posted via `.foliateEvaluateJS` notification.
- The reader navigates to the result position.
- The matched text is visible on screen.

### 6.3 Search with No Results

**Steps:**

1. Search for a string that does not exist in the book (e.g., "xyznonexistent12345").

**Expected:**

- No `search-result` messages arrive.
- `search-done` fires.
- UI shows "No results" or equivalent empty state.
- No crash or error.

---

## 7. TTS (Text-to-Speech)

### 7.1 Start TTS

**Steps:**

1. Open an AZW3 book.
2. Tap the speaker/TTS icon (from chrome bar).

**Expected:**

- `readerAPI.initTTS('word')` is called.
- Foliate-js TTS walker segments text and posts `tts-text` messages.
- `AVSpeechSynthesizer` speaks the text aloud.
- TTS control bar appears at the bottom.

### 7.2 Word Highlighting During TTS

**Steps:**

1. Start TTS.
2. Observe the reader while speech plays.

**Expected:**

- As each word is spoken, `AVSpeechSynthesizerDelegate.speechSynthesizer(_:willSpeakRangeOfSpeechString:)` fires.
- Character range is mapped to a mark.
- `readerAPI.tts.setMark(mark)` is called.
- The current word is visually highlighted in the reader.

### 7.3 TTS Controls

**Steps:**

1. Start TTS.
2. Tap pause.
3. Tap play.
4. Tap stop.

**Expected:**

- Pause halts speech immediately.
- Play resumes from where it paused.
- Stop ends speech, `ttsService.state` returns to `.idle`, control bar disappears.

---

## 8. Theme and Layout

### 8.1 Font Size Change

**Steps:**

1. Open an AZW3 book.
2. Open reader settings.
3. Increase font size.
4. Decrease font size.

**Expected:**

- `FoliateViewBridge.updateUIView` detects `themeCSS` change.
- `readerAPI.setStyles(css)` is called with updated font size.
- Text re-renders at the new size.
- Pagination recalculates (different number of words per page).
- Position is approximately maintained (same content visible).

### 8.2 Theme (Light/Dark) Change

**Steps:**

1. Open an AZW3 book in light mode.
2. Change to dark mode (system or reader settings).

**Expected:**

- `FoliateStyleMapper.themeCSS` generates CSS with `textColor` and `backgroundColor`.
- `readerAPI.setStyles(css)` is called.
- Background and text colors update in the reader.
- Text remains legible with sufficient contrast.

### 8.3 Line Spacing Change

**Steps:**

1. Open reader settings.
2. Adjust line spacing.

**Expected:**

- Theme CSS includes updated `line-height` value.
- Text re-renders with new spacing.
- Pagination recalculates.

---

## 9. Error Handling

### 9.1 Corrupt/Truncated File

**Steps:**

1. Import `corrupt.azw3` (a valid AZW3 file truncated to \~1KB).
2. Open it from the library.

**Expected:**

- `FoliateReaderContainerView` shows loading, then switches to error view.
- Foliate-js posts an `error` message when it fails to parse the file.
- `viewModel.handleError(message)` sets `errorMessage` and `isLoading = false`.
- Error view shows an exclamation triangle icon and the error message.
- Error view has `accessibilityIdentifier("foliateReaderError")`.
- App does NOT crash.

### 9.2 DRM-Protected Book (Error on Open)

**Steps:**

1. Import a DRM-protected AZW3 (from Amazon Kindle).
2. Open it.

**Expected:**

- Foliate-js cannot parse DRM content.
- An `error` message is posted.
- Clear error message is displayed (ideally mentioning DRM).
- App does NOT crash.

### 9.3 Unsupported MOBI Variant

**Steps:**

1. Obtain a MOBI file using an older or unusual MOBI format variant (e.g., KF6-only or PalmDOC).
2. Import and open it.

**Expected:**

- Foliate-js attempts to parse the file.
- If the variant is unsupported, Foliate-js posts an `error` event.
- `FoliateViewCoordinator.handleMessage` routes to `onError`.
- Error view displays: "This file format is not supported." or a Foliate-js parse error message.
- App does NOT crash.

### 9.4 Missing Book File

**Steps:**

1. Import an AZW3 book.
2. Manually delete the file from the app sandbox (via Xcode device manager or a file browser).
3. Try to open the book from the library.

**Expected:**

- `FoliateURLSchemeHandler.serveBookFile` checks `FileManager.default.fileExists`.
- Returns 404 with message "Book file not found".
- JS `fetch()` fails, triggers `error` event.
- Error view displays with a clear message.

### 9.5 JS Bundle Missing from App Bundle

**Steps:**

- This is a build configuration issue. Verify by checking that `foliate-bundle.js` and `foliate-reader.html` are included in the Xcode "Copy Bundle Resources" build phase.

**Expected:**

- If missing, `FoliateURLSchemeHandler` returns 404 for `/foliate-bundle.js`.
- Reader HTML loads but the `<script>` tag fails.
- `window.onerror` catches the error and posts it via `error` message handler.
- OR: `readerAPI` is undefined, and the inline script posts `"readerAPI not found after bundle load"`.

### 9.6 WebView Process Crash

**Steps:**

1. Open an AZW3 book.
2. Open many other apps to pressure memory.
3. Return to VReader.

**Expected:**

- If the WebView process was terminated by iOS, `webContentProcessDidTerminate` fires.
- The coordinator or container should detect this and reload.
- Position is restored from the last saved locator.

### 9.7 Book File Deleted While Reading

**Steps:**

1. Open an AZW3 book and start reading.
2. While the reader is open, use Xcode's device file browser (or another tool) to delete the book file from the app sandbox (`Application Support/ImportedBooks/<key>.azw3`).
3. Navigate to a new section in the reader (to trigger a re-fetch of the book data, if applicable).

**Expected:**

- If the book data is already loaded in Foliate-js memory, reading continues normally for the current session.
- If Foliate-js needs to re-read the file (e.g., for a new section), the scheme handler returns 404.
- An error event fires and the error view displays "Book file is no longer available." or similar.
- The reader does NOT crash.
- Closing and reopening the library entry should also show an error.

### 9.8 Navigation Policy Blocks External URLs

**Steps:**

1. Open an AZW3 book.
2. In Safari Web Inspector, evaluate: `window.location.href = "https://example.com"`.

**Expected:**

- `FoliateViewCoordinator.shouldAllowNavigation(to:)` rejects the URL.
- Only `vreader-resource://`, `blob://`, and `about:blank` are allowed.
- The WebView stays on the reader page.
- No external navigation occurs.

### 9.9 Network Offline

**Steps:**

1. Enable Airplane Mode.
2. Open an imported AZW3 book.

**Expected:**

- Everything works normally -- all resources are local.
- Scheme handler serves from the app bundle and sandbox.
- No network requests are needed.
- External links tapped in the book content will fail to open (expected).

---

## 10. Chrome and Navigation UI

### 10.1 Chrome Toggle

**Steps:**

1. Open an AZW3 book.
2. Tap the center of the screen.
3. Tap center again.

**Expected:**

- First tap: chrome overlay appears (top bar + bottom overlay).
- Second tap: chrome overlay hides.
- Content does NOT shift or resize during toggle.
- Chrome toggle is animated (0.2s ease-in-out).

### 10.2 Bottom Overlay Content

**Steps:**

1. Open an AZW3 book, show chrome.

**Expected:**

- Bottom overlay shows:
  - TOC label for current section (from `viewModel.currentTOCLabel`).
  - Progress bar/percentage (from `viewModel.currentProgress`).
  - Session time (from `viewModel.sessionTimeDisplay`).
- Overlay has `accessibilityIdentifier("foliateBottomOverlay")`.

### 10.3 Bookmark

**Steps:**

1. Open an AZW3 book.
2. Show chrome.
3. Tap the bookmark button.

**Expected:**

- `.readerBookmarkRequested` notification is posted.
- `FoliateReaderContainerView` handles it:
  - Gets current locator from `viewModel.currentLocator()`.
  - Persists bookmark via `PersistenceActor.addBookmark`.
- Haptic feedback plays.
- Bookmark appears in the Annotations panel (Bookmarks tab).

### 10.4 Back to Library

**Steps:**

1. Open an AZW3 book.
2. Show chrome.
3. Tap back/close button.

**Expected:**

- `onDisappear` fires, calling `viewModel.close()`.
- Position is saved.
- Session tracker records the session.
- Reader view is dismissed.
- Library view appears.

---

## 11. Regression Testing

### 11.1 EPUB Reader (Unchanged)

**Steps:**

1. Import and open `test-epub.epub`.

**Expected:**

- Dispatches to `EPUBReaderHost` (case `"epub"`).
- Uses existing `EPUBReaderContainerView` (NOT Foliate-js).
- All EPUB features work: pagination, highlights, search, TOC, TTS.
- No behavioral change from before Feature #42.

### 11.2 PDF Reader (Unchanged)

**Steps:**

1. Import and open `test.pdf`.

**Expected:**

- Dispatches to `PDFReaderHost` (case `"pdf"`).
- Uses `PDFReaderContainerView` with PDFKit.
- All PDF features work.

### 11.3 TXT Reader (Unchanged)

**Steps:**

1. Import and open `test.txt`.

**Expected:**

- Dispatches to `TXTReaderHost` (case `"txt"`).
- Uses `TXTReaderContainerView`.
- All TXT features work.

### 11.4 Library Mixed Formats

**Steps:**

1. Import one book of each format: EPUB, PDF, TXT, AZW3.
2. Open each from the library.
3. Verify each opens in the correct reader.

**Expected:**

- Format dispatch in `ReaderContainerView.nativeReaderView` correctly routes each format.
- No cross-contamination between reader engines.
- Library sort and filter work with mixed formats.

---

## 12. Edge Cases

### 12.1 Very Long Chapter Names in TOC

**Steps:**

1. Open a book with long chapter names (>80 characters).

**Expected:**

- TOC entries truncate gracefully in the UI (no layout overflow).
- Bottom overlay TOC label truncates with `lineLimit(1)`.

### 12.2 CJK Text (Chinese/Japanese/Korean)

**Steps:**

1. Open `cjk-book.azw3`.

**Expected:**

- Chinese/Japanese/Korean characters render correctly.
- Text selection works with CJK characters.
- Search works with CJK queries.
- TTS reads CJK text (if the system TTS voice supports it).

### 12.3 RTL Text (Arabic/Hebrew)

**Steps:**

1. Open an AZW3 with Arabic or Hebrew text (if available).

**Expected:**

- Text flows right-to-left.
- Page turns are reversed (swipe right = forward in RTL).
- Or: Foliate-js handles RTL layout internally.

### 12.4 Books with Many Images

**Steps:**

1. Open `image-heavy.azw3`.
2. Navigate through image-heavy sections.

**Expected:**

- Images load without crashing.
- Memory usage remains reasonable.
- Pagination handles pages with mixed text and images.
- No blank pages where images should be.

### 12.5 Empty Book (0 Sections)

**Steps:**

1. If possible, create an AZW3 with no content sections.
2. Import and open it.

**Expected:**

- Foliate-js either shows an empty view or posts an error.
- App does NOT crash.
- The user sees some feedback (blank page or error message).

### 12.6 Special Characters in Filename

**Steps:**

1. Rename a valid AZW3 to `book (1) [copy] & friends.azw3`.
2. Import it.

**Expected:**

- Import succeeds.
- The filename is not used for the sandbox path (fingerprint key is used instead).
- Book title may come from the filename if metadata extraction returns nil.
- No path traversal or encoding issues.

### 12.7 External Link Tapped

**Steps:**

1. Open an AZW3 book that contains external HTTP links.
2. Tap an external link.

**Expected:**

- `onExternalLink` callback fires.
- URL scheme is validated (only `http`, `https`, `mailto` allowed).
- `UIApplication.shared.open(url)` opens the link in Safari/Mail.
- Invalid schemes (e.g., `javascript:`, `file:`) are silently ignored.

### 12.8 Rapid Page Turns

**Steps:**

1. Open an AZW3 book.
2. Tap the right edge rapidly (10+ times in quick succession).

**Expected:**

- Pages advance smoothly without crashes.
- `relocate` events fire for each page.
- Position save debounce prevents excessive writes (2-second interval).
- No UI freezes or unresponsive states.

### 12.9 Orientation Change

**Steps:**

1. Open an AZW3 book in portrait.
2. Rotate to landscape.
3. Rotate back to portrait.

**Expected:**

- Content re-paginates for the new viewport size.
- Reading position is approximately maintained.
- No layout artifacts or blank pages.
- Chrome overlay repositions correctly.

### 12.10 Book Metadata with Special Characters (JS Injection Safety)

**Steps:**

1. Use Calibre to create an AZW3 with a title containing: `Test'; alert('xss');//`
2. Import and open the book.

**Expected:**

- `FoliateJSEscaper.escapeForJSString` sanitizes the title before any JS interpolation.
- Backslashes, single quotes, and newlines are escaped.
- No JavaScript injection occurs -- the title displays as literal text.
- The reader opens normally without JS errors.
- In Safari Web Inspector, verify no unexpected `alert()` dialogs.

### 12.11 Multiple Open/Close Cycles (Memory Leak Check)

**Steps:**

1. Open an AZW3 book.
2. Read a few pages.
3. Go back to library.
4. Repeat steps 1-3 at least 10 times.

**Expected:**

- Memory usage (visible in Xcode Instruments) does not grow unboundedly.
- `WeakScriptMessageHandler` pattern breaks the WKUserContentController retain cycle.
- Each `onDisappear` properly calls `viewModel.close()`.
- No accumulated WKWebView instances.

### 12.12 Concurrent Format Opens

**Steps:**

1. Open an AZW3 book.
2. Quickly go back and open an EPUB book.
3. Quickly go back and open the AZW3 book again.

**Expected:**

- Each reader host creates its own isolated ViewModel and bridge.
- No cross-contamination of state between the Foliate-js reader and the EPUB reader.
- Position for each book is saved independently.
- No crashes from rapid view lifecycle changes.

---

## 13. Dirty State and Data-Loss Checks

### 13.1 Position Not Lost on Accidental Dismiss

**Steps:**

1. Open an AZW3 book and read to page \~50.
2. Swipe down from the top edge (iOS dismiss gesture).

**Expected:**

- `onDisappear` fires and saves position.
- Reopening restores to the same position.

### 13.2 Position Save During Background Task

**Steps:**

1. Read to a position.
2. Press Home.
3. Wait 30 seconds.
4. Return.

**Expected:**

- Position was saved during the background transition.
- `UIApplication.shared.beginBackgroundTask` ensured the save completed.
- Content is at the same position.

### 13.3 No Data Loss on Error

**Steps:**

1. Read a book and create bookmarks/highlights.
2. Open a corrupt AZW3 file.
3. Dismiss the error.
4. Reopen the previously working book.

**Expected:**

- The error from the corrupt file does NOT affect other books.
- All bookmarks and highlights for the working book are preserved.
- Position for the working book is restored.

---

## Regression Checklist

Run after all tests pass. Each item should be checked on a real device.

### Existing Formats (no regression)

- [ ] EPUB import + open + read -- no change from pre-Feature-42 behavior
- [ ] PDF import + open + read -- no change
- [ ] TXT import + open + read -- no change
- [ ] MD import + open + read -- no change
- [ ] Library mixed formats -- open each, verify correct reader dispatched

### AZW3/MOBI Import

- [ ] AZW3 import works
- [ ] MOBI file imports as AZW3 format
- [ ] AZW file imports as AZW3 format
- [ ] PRC file imports as AZW3 format
- [ ] Duplicate detection works for re-imported AZW3
- [ ] Library shows correct format badge for AZW3

### AZW3 Core Reading

- [ ] AZW3 opens in Foliate-js reader (not EPUB reader)
- [ ] AZW3 paginated reading works (page turns, swipes)
- [ ] AZW3 text renders legibly (fonts, paragraphs, images)
- [ ] AZW3 CJK text renders correctly
- [ ] AZW3 position saves and restores across close/reopen
- [ ] AZW3 position saves on background and restores on foreground
- [ ] Force quit + reopen restores position (after 2s debounce)

### AZW3 Features

- [ ] AZW3 bookmarks create and persist
- [ ] AZW3 TOC displays and navigates
- [ ] AZW3 search returns results and navigates to them
- [ ] AZW3 text selection works (copy + highlight dialog)
- [ ] AZW3 highlights create (visual SVG overlay)
- [ ] Chrome toggle works in AZW3 reader
- [ ] Theme/font/line-spacing changes apply in AZW3 reader
- [ ] TTS plays and highlights words (if implemented)

### AZW3 Error Handling

- [ ] AZW3 DRM file shows error (no crash)
- [ ] AZW3 corrupt/truncated file shows error (no crash)
- [ ] Unsupported MOBI variant shows error (no crash)
- [ ] Missing book file shows error (no crash)
- [ ] WebView process crash recovers gracefully
- [ ] Offline mode works (all resources local)

### Safety and Stability

- [ ] No memory leaks on repeated open/close of AZW3 reader (10+ cycles)
- [ ] No JS injection from malicious book metadata
- [ ] Navigation policy blocks external URLs in WebView
- [ ] Safari Web Inspector shows no JS errors during normal reading
- [ ] External links open in Safari (http/https/mailto only)

