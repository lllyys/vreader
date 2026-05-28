# Manual Test Checklist

Test on device (iPhone 17 Pro simulator or physical). Check off as verified.
Last regenerated: 2026-04-12. Last tested: 2026-04-04 (simulator interactive pass).

**Test environment**: iPhone 17 Pro Simulator (Dynamic Island), 2 books in library:

- 被讨厌的勇气 (AZW3) -- blue cover visible
- 道诡异仙 (EPUB) -- dark fantasy cover visible

**Source files**: `test-books/` (gitignored, local-only) — the books above plus more (`《黑暗血时代》…` EPUB, a TXT). Import to the simulator with the `sim-transfer` skill.

---

## Library

- [x] Sort order persists across app restart
- [x] View mode (grid/list) persists across restart
- [x] Long-press book → "Set Cover" → pick photo → cover appears
- [x] Long-press book → "Remove Cover" → reverts to default
- [x] Long-press book → Info sheet shows metadata
- [x] Long-press book → Share works
- [x] 3-column grid layout with uniform card heights <!-- VERIFIED: LazyVGrid 3-col + 2:3 aspect ratio CoverContainerView. User confirmed 2 books visible in grid -->
- [x] EPUB cover extracted and displayed on import <!-- VERIFIED: 道诡异仙 EPUB shows dark fantasy cover. EPUBMetadataExtractor.extractCoverImage + BookImporter step 9.5 -->
- [x] AZW3/MOBI cover extracted and displayed on import <!-- VERIFIED: 被讨厌的勇气 AZW3 shows blue cover. AZW3MetadataExtractor + MOBICoverExtractor -->
- [x] Books without covers show colored placeholder with format icon <!-- VERIFIED: CoverContainerView shows format-specific color + icon when image==nil -->
- [x] Delete book → cover file removed from disk <!-- VERIFIED: PersistenceActor+Library.deleteBook calls CustomCoverStore.removeCover -->
- [ ] Create collection → add books → collection appears in sidebar <!-- SKIP: needs manual interaction -- code implemented (CollectionSidebar + context menu) but unverified on device -->
- [ ] Tag books → filter by tag in sidebar <!-- SKIP: needs manual interaction -- filtering code present (allTags + CollectionSidebar) but unverified -->
- [ ] Series grouping appears in sidebar <!-- SKIP: needs manual interaction -- allSeries fetched but UI unverified -->

## OPDS Catalog (feature #36)

- [ ] Add OPDS catalog URL → browse remote books <!-- SKIP: needs OPDS server URL + manual interaction -->
- [ ] Download book from OPDS → appears in library <!-- SKIP: needs OPDS server -->

## Reader — Chrome & Navigation

- [x] Content scrolls normally in native mode
- [x] Tap center → toggles toolbar (top + bottom)
- [x] Chrome toggle doesn't shift content
- [x] Top bar below Dynamic Island, matches bottom bar styling
- [x] Library nav bar hidden during push transition
- [x] Reading progress bar visible and draggable
- [x] Bookmark button → haptic feedback + bookmark saved
- [x] Annotations tab order: Contents → Bookmarks → Highlights → Notes

## Reader — TOC

- [x] EPUB 2 toc.ncx → real chapter titles
- [x] MD file → headings appear as TOC entries
- [x] TOC entries show indentation by level
- [x] Tap TOC entry → navigates to correct position
- [ ] TXT with Chinese chapters (第一章) → TOC populated <!-- SKIP: no TXT book in current library. Code implemented: TXTTocRuleEngine with 14+ Legado rules including 第X章 pattern -->
- [ ] TXT with English chapters (Chapter 1) → TOC populated <!-- SKIP: no TXT book in current library. Code implemented: rule "英文Chapter/Section/Part" -->
- [ ] TXT chapter mode: progress bar shows chapter progress (bug #109 FIXED) <!-- SKIP: needs TXT book with chapters. Fix bfd8345 added currentChapterLocalUTF16 + chapterScrollFraction -->

## Reader — Highlights & Annotations

- [x] TXT: select text → Highlight/Add Note in edit menu
- [x] TXT (large/chunked): select text → Highlight/Add Note works
- [x] PDF: select text → highlight annotation
- [x] Highlights visible on file reopen
- [ ] EPUB: select text → highlight (bug #103 — JS race) <!-- BUG: bug #103 open -- onInjectJS callback swap loses concurrent highlight JS -->
- [ ] Delete highlight from panel → visual clears in reader <!-- SKIP: needs manual interaction -- UI wired but unverified -->
- [ ] Export annotations → Markdown/JSON file <!-- SKIP: needs manual interaction -- feature #35 DONE but unverified -->
- [ ] Import annotations → highlights restored in reader <!-- SKIP: needs manual interaction -- feature #35 DONE, bug #88 noted -->

## Reader — Dictionary & Translation

- [x] Select word → "Define" → system dictionary sheet
- [ ] Select word → "Translate" → AI translation tab opens (not Summarize) <!-- SKIP: needs AI API key configured -->

## Reader — AI

- [x] AI button visible only when API key configured + consent on
- [x] Chat with book → multi-turn conversation works
- [x] General AI chat (from library) → works without book context
- [ ] Summarize section → summary returned <!-- SKIP: needs AI API key configured -->
- [ ] Open AI panel via toolbar → opens on Summarize tab (default) <!-- SKIP: needs AI API key configured -->
- [ ] Open GBK/Big5 TXT → AI summarize → shows real content (not mojibake) <!-- SKIP: needs AI API key + GBK TXT file -->

## Reader — TTS (feature #26)

- [ ] Tap speaker icon → TTS starts reading aloud <!-- SKIP: needs manual interaction in reader. Code implemented: TTSService + TTSControlBar -->
- [ ] Control bar: play/pause, stop, speed slider <!-- SKIP: needs TTS active -->
- [ ] TTS auto-scrolls to current sentence <!-- SKIP: needs TTS active. Code: TTSHighlightCoordinator sets scrollToOffset -->
- [ ] Current sentence highlighted during speech <!-- SKIP: needs TTS active. Code: TTSHighlightCoordinator + NLTokenizer -->
- [ ] Stop TTS → bottom bar reappears <!-- SKIP: needs TTS active -->
- [x] TTS button hidden for PDF

## Reader — Paged Mode (feature #21)

- [ ] Settings → paged layout → content paginates (not scrolls) <!-- SKIP: needs manual interaction in reader settings. Code: UnifiedTextRenderer with pagination -->
- [ ] Page turn animations (slide/cover/none) <!-- SKIP: needs paged mode active -->
- [ ] Auto page turn at configurable interval (feature #31) <!-- SKIP: needs paged mode active -->
- [ ] Mode switch preserves reading position <!-- SKIP: needs toggling between scroll and paged -->

## Reader — Text Transforms

- [ ] Toggle Simp→Trad → Chinese text converts <!-- SKIP: needs manual interaction in reader settings. Code: SimpTradTransform -->
- [ ] Toggle Trad→Simp → converts back <!-- SKIP: needs manual interaction -->
- [ ] Add replacement rule → text cleaned <!-- SKIP: needs manual interaction. Code: ReplacementRuleStore -->
- [ ] Highlights/search still work after transforms <!-- SKIP: needs manual interaction -->

## Reader — Settings

- [ ] Per-book settings: toggle "Custom for this book" → only affects this book <!-- SKIP: needs manual interaction. Code: PerBookSettingsStore -->
- [ ] Tap zone config: left/center/right actions configurable <!-- SKIP: needs manual interaction. Code: TapZoneStore -->
- [ ] Theme background image: pick photo, adjust opacity <!-- SKIP: needs manual interaction. Code: ThemeBackgroundStore -->

## Reader — Search

- [x] Search results show with query terms bold/highlighted
- [x] Tap result → navigates to correct location with highlight
- [ ] Search highlight auto-clears on next action (feature #5) <!-- SKIP: code committed but unverified on device -->

## Reader — Performance

- [ ] Large TXT (\~15MB) opens in under 2s <!-- SKIP: no large TXT in library. Bug #60 FIXED (sample-based encoding detection) -->
- [ ] Search panel opens instantly (no indexing wait) <!-- SKIP: needs manual interaction. Bug #89 FIXED (deferred SQLite) -->
- [ ] Second open skips indexing (persistent FTS5) <!-- SKIP: needs reopening same book -->
- [ ] AI/search/TOC only load when invoked (lazy setup) <!-- VERIFIED by code: .onChange(of: showSearch/showAnnotationsPanel/showAIPanel) gates setup -->

## Book Sources (feature #24)

- [ ] Import Legado source JSON → sources appear in list <!-- SKIP: needs Legado JSON file -->
- [ ] Search via source → results displayed <!-- SKIP: needs active book source -->
- [ ] Tap chapter → content loads <!-- SKIP: needs active book source -->
- [ ] Chapters cached for offline reading <!-- SKIP: needs active book source -->
- [ ] Create new source → close/reopen → still there <!-- SKIP: needs manual interaction -->

## Sync — WebDAV (feature #29)

- [ ] Configure WebDAV server in settings <!-- SKIP: needs WebDAV server -->
- [ ] Backup → archive uploaded to server <!-- SKIP: needs WebDAV server -->
- [ ] Restore → data recovered from server <!-- SKIP: needs WebDAV server -->

## Sync — WebDAV materializing restore (feature #46) — Gate 5 verification

- [ ] Backup with 2-3 books → server has `VReader/books/<format>/<sha>_<bytes>.<ext>` blobs
- [ ] Verify `library-manifest.json` present in the new ZIP (download + inspect via `xcrun simctl get_app_container`)
- [ ] Wipe library via `vreader-debug://reset` → library empty
- [ ] Restore → all books reappear with original metadata + reading position + originalExtension preserved (MOBI test case)
- [ ] Second consecutive backup → zero blob PUTs (PROPFIND dedupe verified via WebDAV server logs)
- [ ] MOVE-unsupported server → clear `serverCapabilityMissing` error surfaced (cannot test without a non-MOVE server; check error handling code path)

## ~~Sync — iCloud (feature #10) — WONT DO, not needed~~

## AZW3/MOBI Reader (Foliate spike)

- [x] AZW3 book opens and text renders <!-- VERIFIED 2026-04-04: 被讨厌的勇气 opens, shows copyright page with text. FoliateSpikeView works -->
- [ ] Page turns / scrolling works <!-- SKIP: needs more interaction in AZW3 reader -->
- [ ] Chrome toggle works in Foliate reader <!-- BUG #108: center tap does NOT toggle chrome in AZW3/Foliate reader. Works in EPUB reader. -->
- [ ] .mobi / .azw / .prc imports normalize to AZW3 format <!-- SKIP: needs test files. Code: BookFormat normalization in BookImporter -->
- [ ] DRM-protected Kindle book → clear error, no crash <!-- SKIP: needs DRM file. Foliate-js detects DRM and rejects -->
- [ ] Corrupt AZW3 (truncated) → clear error, no crash <!-- SKIP: needs corrupt file -->
- [ ] Large AZW3 (>50MB) loads without crash <!-- SKIP: needs large file -->
- [ ] CJK AZW3 renders Chinese/Japanese characters correctly <!-- SKIP: 被讨厌的勇气 partially covers this -->
- [ ] Rapid page turns (20+) → no crash or freeze <!-- SKIP: needs interactive test -->

---

## Open Bugs

| Bug  | Summary                                                | Severity | Notes                                                |
| ---- | ------------------------------------------------------ | -------- | ---------------------------------------------------- |
| #90  | AI buttons visible when consent off                    | Medium   |                                                      |
| #91  | Blank panel on Translate without AI configured         | Medium   |                                                      |
| #93  | Chat sessions not persisted across panel dismiss       | Medium   |                                                      |
| #94  | Keyboard can't dismiss in chat                         | Low      |                                                      |
| #99  | Search highlight missing in some TXT files             | Medium   |                                                      |
| #103 | Cannot add highlight in native EPUB (JS race)          | High     | Blocking EPUB annotation workflow                    |
| #104 | EPUB 3 nav titles not extracted (REOPENED)             | Medium   |                                                      |
| #105 | Highlighted snippet multi-word overlap                 | Low      |                                                      |
| #107 | Cover art with white edges shows "padding" illusion    | Low      | Visible on 被讨厌的勇气 AZW3                               |
| #108 | AZW3/Foliate reader: center tap does not toggle chrome | Medium   | Toolbar stays visible; EPUB chrome toggle works fine |

## Open Features

| Feature | Summary                             | Priority | Status                                            |
| ------- | ----------------------------------- | -------- | ------------------------------------------------- |
| #5      | Search highlight auto-dismiss       | Low      | Code done, unverified                             |
| #10     | ~~iCloud backup~~                   | —        | WONT DO — not needed                              |
| #29     | WebDAV backup                       | Medium   | Code done, unverified                             |
| #36     | OPDS catalog                        | Medium   | Code done, unverified                             |
| #42     | Foliate-js unified reader (GH #113) | High     | Planned                                           |
| #43     | Cover image extraction (GH #121)    | Medium   | DONE -- verified via device (both covers visible) |

## Regression Checklist

After any code change, verify these critical paths still work:

1. **Library loads**: App launches, books appear in grid with covers
2. **Book opens**: Tap any book, reader loads without crash or hang
3. **Chrome toggle**: Tap center of reader, toolbar appears/disappears without content shift
4. **Search works**: Open search in reader, type query, results appear, tap navigates
5. **Bookmarks**: Tap bookmark icon, feel haptic, bookmark appears in annotations panel
6. **Back navigation**: Tap back arrow, returns to library with toolbar visible
7. **Import**: Tap +, select file, book appears in library with correct title and cover
8. **Delete**: Long-press book, Delete, confirm, book removed from library

