# Manual Testing Guide: AZW3/MOBI (Kindle) Support

**Last updated:** 2026-03-26
**Scope:** AZW3/MOBI format support. EPUB, PDF, and TXT readers are unchanged.
**Test device:** Real iPhone recommended. Simulator: iPhone 17 Pro.

---

## Quick Checklist

Priority: **P0** = must pass before merge, **P1** = should pass, **P2** = nice to have

### P0 — Critical Path

- [ ] **1.1** Import .azw3 file → appears in library with AZW3 badge
- [ ] **2.1** Open AZW3 book → book renders with text visible
- [ ] **3.1** Page turns work (swipe left/right or tap edges)
- [ ] **3.2** Paginated layout renders correctly (text in columns)
- [ ] **4.1** Close book → reopen → position restored
- [ ] **9.1** Corrupt file → clear error message, no crash
- [ ] **9.2** DRM file → clear error message, no crash
- [ ] **11.1** EPUB reader still works (regression)
- [ ] **11.2** PDF reader still works (regression)
- [ ] **11.3** TXT reader still works (regression)

### P1 — Important Features

- [ ] **1.2** Import .mobi file → appears as AZW3 format in library
- [ ] **1.3** Import .azw file → appears as AZW3 format in library
- [ ] **1.5** DRM-protected book → error message when opening
- [ ] **1.6** Large book (>50MB) → loads without crash
- [ ] **3.4** Text renders legibly with correct fonts
- [ ] **3.5** Images in book display correctly
- [ ] **3.6** Table of contents populates and tapping entries navigates
- [ ] **3.7** Progress bar shows correct reading position
- [ ] **4.2** Switch to another app → return → position preserved
- [ ] **4.3** Force quit app → reopen book → position restored
- [ ] **5.1** Long press text → selection handles appear → Highlight button shown
- [ ] **5.2** Tap Highlight → highlight created and visible
- [ ] **6.1** Search for text → results appear with excerpts
- [ ] **6.2** Tap search result → reader navigates to that position
- [ ] **8.1** Change font size in settings → reader updates
- [ ] **8.2** Switch light/dark theme → reader updates
- [ ] **9.9** Airplane mode → book still opens and reads (all local)
- [ ] **10.1** Tap center of page → toolbar toggles on/off
- [ ] **10.4** Tap back button → returns to library

### P2 — Edge Cases & Polish

- [ ] **1.4** Import .prc file → appears as AZW3 format
- [ ] **1.7** Library shows correct book icon for AZW3
- [ ] **1.8** Import same book twice → duplicate detected
- [ ] **2.3** Loading spinner shown while book is parsing
- [ ] **2.4** Book title and chapter count shown after loading
- [ ] **3.3** Scrolled layout works (if toggle available in settings)
- [ ] **4.4** Closing reader triggers position save (no data loss)
- [ ] **5.3** Long press text → Copy works
- [ ] **5.4** Created highlight visible in Annotations panel
- [ ] **5.5** Close and reopen book → highlights restored in-page
- [ ] **6.3** Search for nonexistent text → "no results" handled gracefully
- [ ] **7.1** Start TTS → text reads aloud
- [ ] **7.2** During TTS → current word highlighted
- [ ] **7.3** TTS controls (pause/resume/stop) work
- [ ] **8.3** Change line spacing → reader updates
- [ ] **9.3** Unsupported file format → clear error message
- [ ] **9.4** Delete book file from Files while reading → error message
- [ ] **9.9** No network → app works normally (no online dependency)
- [ ] **10.2** Bottom bar shows reading time for current session
- [ ] **10.3** Bookmark button works
- [ ] **11.4** Library with mixed formats (EPUB + AZW3 + PDF + TXT) displays correctly
- [ ] **12.1** Book with very long chapter names → TOC doesn't break
- [ ] **12.2** Book with Chinese/Japanese/Korean text → renders correctly
- [ ] **12.3** Book with Arabic/Hebrew (RTL) text → reads right-to-left
- [ ] **12.4** Book with many images → no crash, images load
- [ ] **12.5** Book with 0 readable sections → error message, not blank screen
- [ ] **12.6** Book file with special characters in name (spaces, CJK, etc.) → imports fine
- [ ] **12.7** Tap link in book content → opens Safari for http/https links
- [ ] **12.8** Rapidly turn pages 20+ times → no crash or freeze
- [ ] **12.9** Rotate device → reader adapts to new orientation
- [ ] **12.10** Book with special characters in title/author → displays correctly, no garbled text
- [ ] **12.11** Open and close the same book 10 times → no slowdown or memory warning
- [ ] **12.12** Open AZW3, go back, open PDF, go back, open TXT → all work independently
- [ ] **13.1** Swipe to dismiss reader accidentally → position was already saved
- [ ] **13.2** Switch apps during reading → position saved before backgrounding
- [ ] **13.3** Error opening a book → other books unaffected

---

## Test Files to Prepare

| File | Purpose | How to Get |
|------|---------|-----------|
| `test-book.azw3` | DRM-free AZW3, 2-10MB | Calibre conversion or Project Gutenberg |
| `test-book.mobi` | DRM-free MOBI | Project Gutenberg MOBI download |
| `test-book.azw` | DRM-free AZW | Rename a .azw3 to .azw |
| `test-book.prc` | DRM-free PRC | Rename a .mobi to .prc |
| `drm-book.azw3` | DRM-protected Kindle book | Amazon Kindle purchase (don't strip DRM) |
| `large-book.azw3` | Large book >50MB | Calibre conversion with many images |
| `corrupt.azw3` | Corrupt file | Truncate a valid .azw3 to 1KB |
| `cjk-book.azw3` | Chinese/Japanese text | Calibre conversion of CJK source |
| `test.epub` | Known-working EPUB | Any previously tested EPUB |
| `test.pdf` | Known-working PDF | Any PDF |
| `test.txt` | Known-working TXT | Any text file |

Save these in the Files app or a cloud drive accessible from the test device.

---

## Detailed Test Steps

### 1. Import Testing

#### 1.1 Import AZW3 from Files App

1. Open VReader
2. Tap "+" (import) in the library
3. Select `test-book.azw3` from Files
4. Wait for import

**Pass if:** Book appears in library with title and AZW3 format badge. No error.

#### 1.2 Import MOBI (Normalized to AZW3)

1. Tap import, select `test-book.mobi`

**Pass if:** Book appears in library as AZW3 format (not MOBI). Import succeeds.

#### 1.3 Import AZW (Normalized to AZW3)

1. Tap import, select `test-book.azw`

**Pass if:** Same as 1.2 — appears as AZW3.

#### 1.4 Import PRC (Normalized to AZW3)

1. Tap import, select `test-book.prc`

**Pass if:** Same as 1.2 — appears as AZW3.

#### 1.5 Import DRM-Protected AZW3

1. Tap import, select `drm-book.azw3`
2. Tap to open the book

**Pass if:** Error message appears (e.g., "This file is DRM-protected" or "Could not open"). App does NOT crash.

#### 1.6 Import Large Book (>50MB)

1. Import `large-book.azw3`
2. Open it

**Pass if:** Loading indicator shown. Book eventually renders. No crash or memory warning.

#### 1.7 Library Format Display

1. Import one of each: .azw3, .epub, .pdf, .txt

**Pass if:** Each book shows the correct format badge/icon in the library grid.

#### 1.8 Duplicate Detection

1. Import `test-book.azw3` twice

**Pass if:** Second import is rejected or warns about duplicate.

---

### 2. Reader Opening

#### 2.1 Open AZW3 — Happy Path

1. Tap an imported AZW3 book in the library

**Pass if:** Loading indicator appears briefly, then book text is visible and readable.

#### 2.3 Loading Indicator

1. Open a medium-sized AZW3 book

**Pass if:** A spinner or "Loading..." text appears while the book is being parsed.

#### 2.4 Metadata After Load

1. Open an AZW3 book
2. Check if the title is shown in the toolbar/header

**Pass if:** Book title is displayed (either from file metadata or filename).

---

### 3. Reading Experience

#### 3.1 Page Turns

1. Open a book
2. Swipe left to go to next page
3. Swipe right to go to previous page
4. Tap the right edge of the screen
5. Tap the left edge

**Pass if:** Each action advances or goes back one page.

#### 3.2 Paginated Layout

1. Open a book in paginated mode

**Pass if:** Text is laid out in page-sized columns. No horizontal scrollbar. Text doesn't overflow.

#### 3.3 Scrolled Layout

1. If a layout toggle exists, switch to scrolled mode

**Pass if:** Book content scrolls vertically in a continuous flow.

#### 3.4 Text Rendering

1. Open a book with varied formatting (bold, italic, headings)

**Pass if:** Text is legible. Bold/italic/headings render distinctly. Font size is comfortable.

#### 3.5 Image Display

1. Open a book with inline images

**Pass if:** Images display at appropriate size. Not stretched or cropped. Text wraps around them.

#### 3.6 TOC (Table of Contents)

1. Open a book
2. Open the TOC panel (if available)

**Pass if:** Chapter list populates with chapter names. Tapping a chapter navigates to it.

#### 3.7 Progress Bar

1. Read to roughly the middle of a book

**Pass if:** Progress bar or percentage shows approximately 50%. Updates as you read.

---

### 4. Position Persistence

#### 4.1 Close and Reopen

1. Read to a specific position (note the page/chapter)
2. Go back to library
3. Reopen the same book

**Pass if:** Book opens at the same position you left off.

#### 4.2 Background and Return

1. Read to a position
2. Switch to another app (Home button or app switcher)
3. Return to VReader

**Pass if:** Still at the same position. No re-loading.

#### 4.3 Force Quit

1. Read to a position
2. Force quit VReader (swipe up from app switcher)
3. Relaunch VReader and open the book

**Pass if:** Position is approximately restored (may be off by a page).

#### 4.4 Close Triggers Save

1. Read for at least 30 seconds
2. Go back to library

**Pass if:** Next open restores position (confirms save happened on close).

---

### 5. Highlights

#### 5.1 Text Selection

1. Long press on a word in the book
2. Drag selection handles to select a phrase

**Pass if:** Selection handles appear. Action menu shows "Highlight" and "Copy" options.

#### 5.2 Create Highlight

1. Select text
2. Tap "Highlight"

**Pass if:** Selected text is highlighted with a colored overlay.

#### 5.3 Copy Text

1. Select text
2. Tap "Copy"

**Pass if:** Text copied to clipboard. Paste it elsewhere to verify.

#### 5.4 Annotations List

1. Create a highlight
2. Open the Annotations panel

**Pass if:** The highlight appears in the list with the highlighted text.

#### 5.5 Highlight Restoration

1. Create a highlight
2. Close the book
3. Reopen

**Pass if:** The highlight is still visible at the same position.

---

### 6. Search

#### 6.1 Search in AZW3

1. Open the search function
2. Type a word you know is in the book

**Pass if:** Results appear with text excerpts showing the word in context.

#### 6.2 Navigate to Result

1. Search for a word
2. Tap a result

**Pass if:** Reader navigates to the page containing that text.

#### 6.3 No Results

1. Search for a nonsense string like "xyzzy12345"

**Pass if:** "No results" message (or empty list). No crash.

---

### 7. TTS (Text-to-Speech)

#### 7.1 Start TTS

1. Start text-to-speech playback

**Pass if:** The app reads the text aloud using the device voice.

#### 7.2 Word Highlighting

1. During TTS playback, watch the screen

**Pass if:** The currently spoken word is highlighted or underlined.

#### 7.3 TTS Controls

1. Pause, resume, and stop TTS

**Pass if:** Each control works as expected.

---

### 8. Theme and Layout

#### 8.1 Font Size

1. Open reader settings
2. Change font size (larger or smaller)

**Pass if:** Text in the reader updates to the new size immediately.

#### 8.2 Theme Change

1. Switch between light and dark theme

**Pass if:** Reader background and text color change accordingly.

#### 8.3 Line Spacing

1. Change line spacing in settings

**Pass if:** Text in the reader reflects the new spacing.

---

### 9. Error Handling

#### 9.1 Corrupt File

1. Import and open `corrupt.azw3` (truncated to 1KB)

**Pass if:** Error message appears. App does not crash.

#### 9.2 DRM-Protected

1. Import and open a DRM-protected Kindle book

**Pass if:** Clear error message. App does not crash.

#### 9.3 Unsupported Format

1. Rename a .jpg to .azw3 and import it

**Pass if:** Error on import or on open. No crash.

#### 9.4 Missing Book File

1. Open a book, then delete its source file from Files while reading

**Pass if:** Error message appears. App does not crash.

#### 9.9 Offline

1. Enable airplane mode
2. Open an already-imported AZW3 book

**Pass if:** Book opens and reads normally (everything is local).

---

### 10. Chrome and Navigation

#### 10.1 Chrome Toggle

1. Tap the center of the page content

**Pass if:** Toolbar and bottom bar toggle visibility.

#### 10.2 Bottom Overlay

1. Read for a few minutes
2. Show the bottom bar

**Pass if:** Session reading time is displayed.

#### 10.3 Bookmark

1. Tap the bookmark button

**Pass if:** Bookmark is created at current position.

#### 10.4 Back to Library

1. Tap the back button

**Pass if:** Returns to library. Book position is saved.

---

### 11. Regression Testing

#### 11.1 EPUB

1. Open a previously working EPUB book

**Pass if:** Renders and behaves exactly as before. No changes.

#### 11.2 PDF

1. Open a previously working PDF

**Pass if:** Renders normally. Page navigation works.

#### 11.3 TXT

1. Open a previously working TXT file

**Pass if:** Renders normally. Chapter detection works.

#### 11.4 Mixed Library

1. Have EPUB, AZW3, PDF, and TXT books in the library

**Pass if:** All display correctly in the library grid. Each opens in its correct reader.

---

### 12. Edge Cases

#### 12.1 Long Chapter Names
Open a book with very long chapter titles. **Pass if:** TOC doesn't overflow or crash.

#### 12.2 CJK Text
Open `cjk-book.azw3`. **Pass if:** Chinese/Japanese characters render correctly.

#### 12.3 RTL Text
Open a book with Arabic/Hebrew text. **Pass if:** Text reads right-to-left.

#### 12.4 Image-Heavy Book
Open a book with many images. **Pass if:** Images load. No crash.

#### 12.5 Empty Book
Open a book with no readable content. **Pass if:** Error message, not a blank screen.

#### 12.6 Special Filename
Import a file named `书籍 (copy).azw3`. **Pass if:** Imports successfully.

#### 12.7 External Links
Tap a hyperlink in book content. **Pass if:** Opens Safari for http/https links. Does not open tel:/sms: links.

#### 12.8 Rapid Page Turns
Tap next page 20+ times rapidly. **Pass if:** No crash or freeze.

#### 12.9 Orientation Change
Rotate the device while reading. **Pass if:** Layout adapts.

#### 12.10 Special Characters in Metadata
Open a book with quotes or ampersands in title. **Pass if:** Title displays correctly.

#### 12.11 Memory Stability
Open and close the same book 10 times. **Pass if:** No slowdown or memory warnings.

#### 12.12 Concurrent Formats
Open AZW3, go back, open PDF, go back, open TXT. **Pass if:** Each reader works independently.

---

### 13. Data Safety

#### 13.1 Accidental Dismiss
Swipe to dismiss reader. **Pass if:** Position was saved.

#### 13.2 Background Save
Switch apps while reading. **Pass if:** Position saved before backgrounding.

#### 13.3 Error Isolation
Fail to open one book. **Pass if:** Other books still open normally.
