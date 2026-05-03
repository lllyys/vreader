# Feature #42: Foliate-js Unified Reader Engine

## Context

VReader currently has a custom EPUB WKWebView bridge (~921 LOC Swift + ~1314 LOC vendored JS) that loads extracted XHTML files, injects custom JS for pagination/selection/highlights, and handles progress via message handlers. Users want AZW3/MOBI support (Kindle books).

Instead of writing a native Swift AZW3 parser (~1130 LOC) AND maintaining the current EPUB bridge, we add Foliate-js — a battle-tested JS library that natively parses EPUB and MOBI/AZW3 and renders via a `<foliate-view>` web component.

**Delivery strategy: AZW3 first, EPUB migration second.**
- Stage 1: FoliateReaderHost for AZW3/MOBI only. EPUB stays on existing bridge. Zero risk to existing users.
- Stage 2: After AZW3 is stable with all features, migrate EPUB behind a feature flag. Validate parity before removing old bridge.

**PDF stays on PDFKit. TXT stays on UITextView.**

## Spike Findings (validated on real device)

1. **WKWebView blocks ES modules** on both `file://` and custom URL schemes — not usable
2. **IIFE bundle works** — esbuild bundles all Foliate-js into a single 278KB non-module script
3. **`loadHTMLString` + inline IIFE + base64 book handoff** — proven working on device:
   - `[bridge] JS bridge loaded` ✓
   - `[book-ready] "How to Make Anyone Fall in Love with You" — 65 sections` ✓
   - `[relocate] 0.1% sec:0/65 toc:Cover cfi:epubcfi(/6/2!/4/2)` ✓
4. **`WKURLSchemeHandler` + IIFE** — Readium validates this pattern (they deprecated GCDWebServer in favor of it). Not yet tested in our spike.
5. **Book delivery**: for production, serve book file via scheme handler (stream from disk). Base64 handoff won't scale to 100MB books.

## Architecture

```
ReaderContainerView
  ├── FoliateReaderHost (AZW3/MOBI now, EPUB later behind flag)
  │     └── FoliateReaderContainerView (SwiftUI shell)
  │           └── FoliateViewBridge (UIViewRepresentable)
  │                 └── WKWebView + WKURLSchemeHandler
  │                       ├── foliate-bundle.js (278KB IIFE, esbuild output)
  │                       └── <foliate-view> web component
  │                             ├── epub.js + mobi.js (parsers, bundled)
  │                             ├── paginator.js (CSS multi-column, bundled)
  │                             ├── overlayer.js (SVG highlights, bundled)
  │                             └── search.js / tts.js / progress.js (bundled)
  │
  ├── EPUBReaderHost (unchanged initially, replaced in Stage 2)
  ├── PDFReaderHost (unchanged — PDFKit)
  └── TXTReaderHost (unchanged — UITextView)

Shared (unchanged): Locator, Highlight, SearchService, TTSService, TOC, Position persistence
```

### JS Bundle Strategy

`foliate-host.js` is the **source file** (ES module with imports). `foliate-bundle.js` is the **build output** (single IIFE, no imports). They contain the same code — esbuild inlines all dependencies:

```bash
# Create stubs for unsupported formats, then bundle
echo 'export const makeComicBook = () => { throw new Error("not supported") }' > comic-book.js
echo 'export const makeFB2 = () => { throw new Error("not supported") }' > fb2.js
echo 'export const makePDF = () => { throw new Error("not supported") }' > pdf.js
npx esbuild foliate-host.js --bundle --format=iife --global-name=FoliateHost --outfile=foliate-bundle.js
rm comic-book.js fb2.js pdf.js
```
- Output: `foliate-bundle.js` (~278KB, zero imports)
- Loaded via `<script src="./foliate-bundle.js">` (not `type="module"`)

### Content Serving: WKURLSchemeHandler

Single host (`localhost`), path-based routing to avoid CORS:

| URL | Source |
|---|---|
| `vreader-resource://localhost/index.html` | Reader HTML from bundle |
| `vreader-resource://localhost/foliate-bundle.js` | IIFE bundle from bundle |
| `vreader-resource://localhost/book/file` | Book file streamed from sandbox |

The scheme handler serves **any path** from the bundle root (not just `/foliate/*`), so `./foliate-bundle.js` relative to `/index.html` resolves correctly to `/foliate-bundle.js`.

Fallback if scheme handler fails: `loadHTMLString` + base64 book handoff (proven working, limited to ~50MB books).

### Bridge Protocol

**Swift → JS** (via evaluateJavaScript):
- `readerAPI.open(url)` — load book (scheme handler URL or File/Blob)
- `readerAPI.init({cfi})` — restore saved position
- `readerAPI.goTo(cfi)` — navigate to position
- `readerAPI.next()` / `prev()` — page turn
- `readerAPI.goToFraction(f)` — seek by book fraction
- `readerAPI.addAnnotation({value, color, type})` — add highlight
- `readerAPI.deleteAnnotation({value})` — remove highlight
- `readerAPI.search({query, ...})` — search
- `readerAPI.setStyles(css)` — theme CSS
- `readerAPI.setLayout({flow, margin, ...})` — layout config
- `readerAPI.initTTS(granularity)` — TTS init
- `readerAPI.tts.start/next/prev/setMark()` — TTS control

**JS → Swift** (via webkit.messageHandlers):
- `bridge-ready` — JS loaded, ready to open book
- `book-ready` — metadata + TOC parsed {title, author, sections, layout, toc}
- `relocate` — position changed {cfi, fraction, sectionIndex, sectionTotal, tocLabel, tocHref}
- `selection` — text selected {cfi, text, rect, index}
- `tap` — content tapped → post `.readerContentTapped` notification
- `annotation-show` — highlight tapped {value, index}
- `create-overlay` — section loaded, ready for highlights {index}
- `section-load` — section DOM loaded {index}
- `tts-text` — text + word ranges for speech (NOT SSML — AVSpeechSynthesizer doesn't consume SSML)
- `search-result` — search hit {cfi, excerpt}
- `search-progress` / `search-done` — search status
- `external-link` — external URL clicked {href}
- `error` — parse/render error {message, type}

**JS → Swift notification mapping:**
| JS Event | Swift Action |
|---|---|
| `tap` | Post `.readerContentTapped` notification |
| `relocate` | ViewModel.updatePosition() → ReaderPositionService.save() |
| `selection` | Post `.readerSelectionChanged` with ReaderSelectionEvent |
| `annotation-show` | Post `.readerHighlightTapped` with CFI |
| `external-link` | UIApplication.shared.open(URL) |
| `error` | ViewModel.errorMessage = msg |

### Locator Contract for Foliate-js Formats

Both EPUB (via Foliate) and AZW3 use the same `Locator` fields:

| Use Case | Required Fields | Optional Fields |
|---|---|---|
| **Reading position** | `bookFingerprint`, `cfi`, `totalProgression` | `href` (TOC section), `progression` (within section) |
| **Bookmark** | `bookFingerprint`, `cfi`, `totalProgression` | `textQuote` (context) |
| **Highlight** | `bookFingerprint`, `cfi` | `textQuote`, `textContextBefore`, `textContextAfter` |
| **Search result** | `bookFingerprint`, `cfi` | `textQuote` (matched text) |

**Example locators:**
```
// AZW3 reading position
Locator(bookFingerprint: fp, cfi: "epubcfi(/6/14!/4/2/1:0)", totalProgression: 0.23, href: "Chapter 5")

// EPUB highlight
Locator(bookFingerprint: fp, cfi: "epubcfi(/6/8!/4/2/3:5,/6/8!/4/2/3:42)", textQuote: "selected text")

// AZW3 bookmark
Locator(bookFingerprint: fp, cfi: "epubcfi(/6/4!/4/2)", totalProgression: 0.05)
```

`Locator.cfi` is the **authoritative position**. `progression`/`totalProgression` are for progress display. `href` is for TOC label display. All fields except `bookFingerprint` and `cfi` are best-effort.

**Fake CFI stability:** Foliate-js generates deterministic fake CFIs for MOBI based on section index + DOM path. Same file content → same CFIs. Fallback if CFI resolution fails: `goToFraction(totalProgression)`.

### Format Identity: Normalize to `.azw3`

All Kindle-family extensions (`.azw3`, `.azw`, `.mobi`, `.prc`) are normalized to `BookFormat.azw3` at import time. The `book.format` string stored in SwiftData is always `"azw3"`. Dispatch, capabilities, analytics, and persistence all use one consistent format identity.

### Highlight Migration: Accept Loss

Existing EPUB highlights use the current bridge's anchor format (`serializedRange` with XPath-based DOM references). Foliate-js uses CFI-based positions with SVG overlayer rendering. The two anchor systems are incompatible. Old highlights remain in the database (viewable in annotations list) but won't render in-page after EPUB switches to Foliate-js (Stage 2). No migration code.

### Feature Flag (Stage 2 only)

Only needed when migrating EPUB to Foliate-js:
- `ReaderSettingsStore.useFoliateForEPUB: Bool` (default: false initially)
- `ReaderContainerView` checks flag for `"epub"` dispatch → `FoliateReaderHost` or `EPUBReaderHost`
- `"azw3"` always goes to `FoliateReaderHost` (no flag needed)
- Remove flag + old bridge after parity verified

**EPUB migration go/no-go criteria:**
- [ ] All 65 sections of test AZW3 render correctly (validates the engine)
- [ ] Open 5 different EPUBs via flag → all render, paginate, theme correctly
- [ ] Highlights create + persist + restore across app restart
- [ ] Search finds text and navigates to results
- [ ] TTS reads with word tracking
- [ ] TOC displays and navigates
- [ ] Position saves and restores (CFI-based)
- [ ] No crash on DRM-protected files (clear error message)
- [ ] Performance: book open <2s, page turn <100ms on iPhone 15

### TTS: Text + Ranges, Not SSML

`AVSpeechSynthesizer` takes `AVSpeechUtterance(string:)`, not SSML. The integration:

1. Swift calls `readerAPI.initTTS('word')`
2. Foliate-js TTS walker segments text into blocks with word boundaries
3. JS posts `tts-text` with `{text: "paragraph text", ranges: [{start, end, mark}...]}` (plain text + word offsets)
4. Swift creates `AVSpeechUtterance(string: text)`
5. On `AVSpeechSynthesizerDelegate.speechSynthesizer(_:willSpeakRangeOfSpeechString:)`: map character range to mark, call `readerAPI.tts.setMark(mark)` → JS highlights word
6. On utterance finish: call `readerAPI.tts.next()` for next block

**Modify:** `foliate-host.js` — extract plain text from Foliate-js TTS output, post text + word ranges instead of raw SSML. `TTSService.swift` — accept text + ranges input.

### EPUB Search: FTS5 Hit → Foliate Navigation

For EPUB (when migrated to Foliate-js in Stage 2):

1. User searches → `SearchService.search(query)` → FTS5 returns hits with `sourceUnitId: "epub:<href>"`
2. `SearchHitToLocatorResolver` creates `Locator(href: href, textQuote: snippet)`
3. Reader receives `.readerNavigateToLocator` notification
4. FoliateReaderContainerView calls `readerAPI.search({query: snippet, index: sectionIndex})` to find and highlight the exact text in Foliate-js
5. Or: use `view.goTo(href)` to navigate to the section, then `view.select({text: snippet})` to highlight

For AZW3 (no FTS5 index):
1. Use Foliate-js built-in search: `readerAPI.search({query})`
2. Results stream via `search-result` message handler
3. Navigate via `readerAPI.goTo(cfi)`

### Failure Modes

| Failure | Detection | User-Facing | Cleanup |
|---|---|---|---|
| DRM-protected AZW3 | Foliate-js `error` event with parse failure | Alert: "This file is DRM-protected. VReader can only open DRM-free files." | None needed |
| Corrupt/truncated file | Foliate-js `error` event | Alert: "Could not open this file. It may be corrupted." | None needed |
| Unsupported MOBI variant | Foliate-js `error` event | Alert: "This file format is not supported." | None needed |
| JS bundle fails to load | No `bridge-ready` after 10s | Alert: "Reader failed to initialize." + retry button | None needed |
| Scheme handler 404 | JS `fetch()` fails → `error` event | Alert with error details | None needed |
| WKWebView crash | `webContentProcessDidTerminate` delegate | Auto-reload WebView, restore position from saved Locator | Re-create WKWebView |
| App backgrounded | `scenePhase` / `willResignActive` | Save position immediately (flush debounce) | None |
| App foregrounded | `scenePhase` / `didBecomeActive` | Verify WebView is alive, reload if terminated | Re-create if needed |
| Book file deleted while reading | Scheme handler returns 404 | Alert: "Book file is no longer available." | Close reader |

## Work Items

### Stage 1: AZW3/MOBI Support (EPUB unchanged)

#### Phase 0: Spike Validation (DONE)
- [x] All spike items completed and validated on real device

#### Phase 1: Foundation (partially DONE)

**WI-1: BookFormat + Import (DONE in spike)**
- [x] `BookFormat.azw3`, `FormatCapabilities`, importer, metadata extractor stub
- [ ] Normalize `.mobi`/`.azw`/`.prc` to `.azw3` at import time (currently dispatch handles raw strings)
- [ ] Tests

**WI-2: Foliate-js Bundle (DONE in spike)**
- [x] Vendored JS files, foliate-host.js, foliate-reader.html, foliate-bundle.js
- [ ] Add esbuild build script for reproducible rebuilds
- [ ] Pin foliate-js to specific commit

**WI-3: Production Content Serving**
- [x] Fix scheme handler routing: serve any bundle resource at root level
- [ ] Test scheme handler serving IIFE bundle as `<script src>` (not module)
- [ ] Test scheme handler serving book file via `fetch()` from JS
- [ ] Fallback path: `loadHTMLString` + base64 (proven, for books <50MB)

#### Phase 2: Core Rendering

**WI-4: FoliateViewBridge + Coordinator** (~380 LOC)
- `FoliateViewBridge.swift` — UIViewRepresentable, WKWebView + scheme handler, loads once
- `FoliateViewCoordinator.swift` — message handlers → callbacks, navigation delegate

**WI-5: FoliateReaderViewModel** (~240 LOC)
- Maps `relocate` → `Locator(cfi:, totalProgression:, href:)`
- Reuses `ReaderPositionService`, `ReaderLifecycleHelper`

#### Phase 3: Container + Integration

**WI-6: FoliateReaderContainerView** (~510 LOC)
- Main container + Highlights extension + Navigation extension
- Composes FoliateViewBridge + progress bar + overlays

**WI-7: FoliateHighlightRenderer** (~80 LOC)
- `addAnnotation`/`deleteAnnotation` via JS evaluator
- Restore on `create-overlay` event

**WI-8: Host + Dispatch**
- `FoliateReaderHost` in ReaderFormatHosts.swift
- Dispatch: `"azw3"` → `FoliateReaderHost` (EPUB unchanged)

#### Phase 4: Features

**WI-9: TOC** — convert Foliate-js `book.toc` tree → `[TOCEntry]`
**WI-10: Search** — Foliate-js built-in search for AZW3 (stream results via message handler)
**WI-11: TTS** — Foliate-js text/ranges → `AVSpeechUtterance` (not SSML)
**WI-12: Theme/Layout** — map ReaderSettingsStore → `setStyles()`/`setLayout()`

**Phase 4 prerequisite:** freeze bridge contracts (WI-4 message handler payloads + readerAPI shape) before starting parallel work.

### Stage 2: EPUB Migration (after Stage 1 is stable)

**WI-14: Feature flag** — `useFoliateForEPUB` toggle
**WI-15: EPUB via Foliate** — dispatch `"epub"` → `FoliateReaderHost` when flag on
**WI-16: FTS5 search → Foliate navigation** — map search hits to CFI/goTo
**WI-17: Parity validation** — run go/no-go checklist
**WI-18: Delete old bridge** — remove ~2100 LOC + old FoliateJS/ + spike view + feature flag

## New Files Summary

| File | LOC (est.) | Status |
|---|---|---|
| `foliate-bundle.js` | ~278KB | Done (esbuild output) |
| `foliate-host.js` | ~230 | Done (source for bundle) |
| `foliate-reader.html` | ~30 | Done |
| `FoliateURLSchemeHandler.swift` | ~190 | Done (routing fixed) |
| `FoliateSpikeView.swift` | ~250 | Done (throwaway) |
| `AZW3MetadataExtractor` | ~10 | Done (stub) |
| `FoliateViewBridge.swift` | ~180 | TODO |
| `FoliateViewCoordinator.swift` | ~200 | TODO |
| `FoliateReaderViewModel.swift` | ~240 | TODO |
| `FoliateReaderContainerView.swift` | ~280 | TODO |
| `FoliateReaderContainerView+Highlights.swift` | ~130 | TODO |
| `FoliateReaderContainerView+Navigation.swift` | ~100 | TODO |
| `FoliateHighlightRenderer.swift` | ~80 | TODO |
| **Total new Swift** | **~1,700** | |
| **Total deleted Swift (Stage 2)** | **~2,100** | |
| **Net** | **-400 LOC** | |

## Risks

1. **WKURLSchemeHandler + IIFE** — not yet tested together. Readium validates the pattern. Fallback: `loadHTMLString` + base64 (proven). Last resort: GCDWebServer.
2. **Foliate-js ZIP performance** — zip.js without web workers. Large EPUBs (~50MB+) may take 2-3s. Show loading indicator.
3. **Position migration (Stage 2)** — existing EPUB positions lack CFI. First open uses `goToFraction()` approximation.
4. **SVG overlay appearance** — different from CSS Highlight API. May need CSS tuning.
5. **foliate-js updates** — vendored + bundled. Pin to commit, document rebuild procedure.
6. **EPUB parity gap** — risk that Foliate-js renders some EPUBs differently than current bridge. Feature flag + go/no-go checklist mitigates.

## Verification

1. **Unit tests:** FoliateURLSchemeHandler routing, FoliateViewCoordinator message dispatch, FoliateReaderViewModel locator construction
2. **Integration tests:** Open AZW3 → relocate events → position persistence → highlight create/restore
3. **Manual tests (Stage 1):**
   - Import + open DRM-free .azw3 → renders, paginates, highlights work
   - Import + open DRM-free .mobi → renders
   - DRM .azw3 → clear error message
   - Large book → loading indicator, then renders
   - Paged ↔ scrolled toggle
   - Theme switching
   - TTS with word tracking
   - Search + result navigation
   - TOC navigation
   - Highlights persist across app restart
4. **Manual tests (Stage 2):**
   - Open existing EPUB (flag on) → renders, position approximately restored
   - Open existing EPUB (flag off) → legacy bridge, no regression
   - Run go/no-go checklist before removing old bridge
5. **Regression:** PDF and TXT readers unaffected
6. **Device test:** Always verify on real iPhone
