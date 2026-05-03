# WI-6B: Markdown (.md) Reader — Implementation Plan (Revised)

**Status:** Revised after Codex architectural review
**Review thread:** `019cbed7-cbcf-7b53-9718-656dd66a5d93`

## 0. Review Response

This revision addresses all Critical/High findings from the Codex review:

1. **Offset contract conflict** (Critical): Resolved — MD offsets are formally over rendered text with explicit contract amendment rationale.
2. **TXTChunkedLoader reuse overclaim** (Critical): Corrected — MD loads fully, not chunked. ChunkedLoader only used for raw byte reading.
3. **Sequencing: contract spike not front-loaded** (Critical): Fixed — Task 0 is now a contract spike.
4. **Main-thread parsing risk** (High): Fixed — parsing runs on background task.
5. **Import before reader ready** (High): Fixed — import+reader ship in same commit; `ReaderContainerView` already shows "coming soon" for unsupported formats.
6. **Bridge regression risk** (High): Fixed — bridge hardening moved to Task 1 (before MD work).
7. **Existing negative tests** (High): Enumerated — 3 tests to update.
8. **Indexing contract for wordsRead** (High): Deferred — wordsRead removed from this WI's acceptance.
9. **Link policy** (Medium): Defined — `http`/`https` only.
10. **SPM integration** (Medium): Concrete steps added.
11. **Rendered text normalization** (High): Canonical rules defined with golden tests.
12. **LocatorFactory ambiguity** (Medium): Resolved — add `mdPosition`/`mdRange` aliases.
13. **Empty doc division by zero** (Medium): Guarded — `totalProgression = 0` for empty docs.
14. **Nested blockquote degradation** (Medium): Defined — flatten to single-level styling.

---

## 1. Executive Summary

Adds Markdown reading support to vreader. `.md` and `.markdown` files can be imported and read with rich rendering (headings, bold, italic, code, links, lists, blockquotes). Maximizes reuse of existing TXT infrastructure while adding a Markdown-to-`NSAttributedString` rendering layer.

---

## 2. Architecture Decisions

### 2.1 Rendering: `swift-markdown` AST to `NSAttributedString` in `UITextView`

| Option | Verdict | Reason |
|--------|---------|--------|
| A. TXT reader as-is | Rejected | No rich rendering |
| B. iOS `AttributedString(markdown:)` | Rejected | No headings, code blocks, lists |
| C. HTML + WKWebView | Rejected | Loses UTF-16 offset compat; WebView overhead |
| **D. `swift-markdown` + `NSAttributedString`** | **Selected** | Rich rendering; TextKit 1 offset mapping; Apple's parser |

### 2.2 Offset Contract: Rendered text offsets (Contract Amendment)

**Decision: MD offsets track the rendered `NSAttributedString` text, NOT the raw Markdown source.**

**Rationale (why this is NOT a contract violation):**

The master plan (Section 3.2, rule 5) says: "TXT paragraph joining/wrapping is display-only and must never change stored offsets." This rule exists because TXT display transforms (paragraph joining, line wrapping) are reversible visual changes — the content the user reads IS the raw source.

Markdown is fundamentally different: the raw source contains structural markup (`#`, `**`, `` ` ``, `>`, `-`) that the user does NOT read. Markdown syntax removal is semantic parsing, not a display transform. The rendered text IS the content — analogous to how an EPUB's content is the rendered HTML, not the raw XHTML/CSS source.

**Formal contract for `.md` format:**

1. `Locator.charOffsetUTF16` = UTF-16 offset into the **rendered plain text** (Markdown syntax stripped, list bullets/numbers materialized).
2. `Locator.charRangeStartUTF16` / `charRangeEndUTF16` = ranges in rendered text.
3. `totalProgression` = `charOffsetUTF16 / renderedTextLengthUTF16`. For empty documents, `totalProgression = 0`.
4. Quote/context extraction operates on rendered text.
5. Search indexing (future WI-10) indexes rendered text. `sourceUnitId` format deferred to WI-10.
6. `bookFingerprint.format == .md` is the discriminator. Locator restore checks format and applies the correct offset domain.

**What this means for LocatorFactory/Restorer:**
- Add `mdPosition()` and `mdRange()` aliases that delegate to the same logic as `txtPosition()`/`txtRange()`.
- `LocatorRestorer` already dispatches by `bookFingerprint.format`; add `.md` case that reuses the TXT restore path.
- No renaming of existing TXT APIs.

### 2.3 Canonical Rendered Text Normalization

To ensure offset stability across renderer versions, define these normalization rules:

1. **Headings**: Rendered as heading text + `\n`. No `#` characters.
2. **Paragraphs**: Rendered as paragraph text + `\n`.
3. **Bold/italic**: Rendered as inner text (no `*`/`_` characters).
4. **Code spans**: Rendered as code text (no backticks).
5. **Code blocks**: Rendered as code content + `\n`. No fence markers.
6. **Links**: Rendered as link text (no `[]()`). URL stored as NSAttributedString `.link` attribute.
7. **Lists**: Rendered as `\u{2022} item text\n` (unordered) or `N. item text\n` (ordered). Nested items prepend `\t` per level.
8. **Blockquotes**: Rendered as quote text with paragraph indent. No `>` characters. Nested blockquotes flatten to single-level styling.
9. **Thematic breaks**: Rendered as `\n` (empty line separator).
10. **Images**: Rendered as alt text or empty string.

**Golden tests**: Each normalization rule has a test that asserts the exact `.string` output of the rendered `NSAttributedString`. These tests pin the text content and catch any renderer changes that would break offset stability.

### 2.4 File Loading: Encoding detection reuse, NOT chunked loading

**Decision: MD reuses `EncodingDetector` for encoding detection. `TXTChunkedLoader` is NOT used for rendering.**

Markdown AST construction requires the complete document — chunked loading provides no benefit. The loading path is:

1. Read full file data into memory.
2. Detect encoding via `EncodingDetector.detect(data:)`.
3. Decode to `String`.
4. Parse Markdown and render `NSAttributedString` on a **background task**.
5. Hand off the rendered content to the main actor for display.

For typical Markdown files (<1MB), this is negligible. For very large files (>5MB — rare for Markdown), the full-document parse is still acceptable since `swift-markdown` processes text at >100MB/s.

### 2.5 Background Parsing

**Decision: Markdown parsing and `NSAttributedString` construction run off the main thread.**

The `MDParserProtocol.parse()` method is `async` and runs on a detached task. Only the final `NSAttributedString` assignment to the view happens on `@MainActor`. This prevents UI stalls on large documents.

```
open(url:) on @MainActor
  → Task.detached {
      read file data
      detect encoding
      decode string
      parse Markdown → NSAttributedString
    }
  → back to @MainActor: set renderedContent, restore scroll position
```

### 2.6 Format Distinction: Extension-based only

`.md` and `.markdown` extensions trigger Markdown import. `.txt` files are never auto-detected as Markdown.

### 2.7 Feature Scope (CommonMark baseline)

**Supported:** Headings (H1-H6), bold, italic, code spans, code blocks (fenced + indented), links, unordered lists, ordered lists, blockquotes (single-level), thematic breaks, paragraphs.

**Not supported (deferred):** Tables, task lists, footnotes, math, images, nested blockquotes (flatten to single level).

**Link interaction policy:**
- Only `http://` and `https://` URLs are tappable.
- Other schemes (file://, javascript://, etc.) are rendered as styled text but not interactive.
- Relative links (e.g., `./other.md`) are rendered as text, not tappable.
- `UITextView` delegate's `shouldInteractWith` enforces this.

### 2.8 ViewModel Pattern

`MDReaderViewModel` is `@Observable @MainActor`, following `EPUBReaderViewModel`:
- Protocol abstractions: `MDParserProtocol`, `ReadingPositionPersisting`, `ReadingSessionTracker`.
- Debounced position save (2s).
- Periodic session flush (60s).
- Background/foreground lifecycle.

---

## 3. Reuse Inventory

| Component | Reuse | Notes |
|---|---|---|
| `BookFormat.md` | Direct | Remove V1 restriction |
| `DocumentFingerprint` | Direct | Works with `.md` |
| `Locator` TXT fields | Direct | Same fields, rendered-text domain |
| `LocatorFactory.txtPosition/txtRange` | Alias | Add `mdPosition`/`mdRange` aliases |
| `EncodingDetector` | Direct | Same pipeline |
| `TXTChunkedLoader` | **Not used** | MD loads fully |
| `TXTOffsetMapper` | Direct | NSRange <-> UTF-16, scroll <-> char offset |
| `TXTTextViewBridge` | **Extend** | Accept `NSAttributedString` directly |
| `ReadingSessionTracker` | Direct | Format-agnostic |
| `ReadingPositionPersisting` | Direct | Format-agnostic |
| `ReadingTimeFormatter` | Direct | Format-agnostic |
| `QuoteRecovery` | Direct | Works on rendered text |
| `ReaderContainerView` | Modify | Add `case "md"` dispatch |

---

## 4. File Plan

### 4.1 New Files

| File | Purpose | LOC |
|---|---|---|
| `vreader/Services/MD/MDParserProtocol.swift` | Protocol definition | ~30 |
| `vreader/Services/MD/MDParser.swift` | Production impl (async, background parsing) | ~80 |
| `vreader/Services/MD/MDTypes.swift` | `MDDocumentInfo`, `MDRenderConfig`, `MDHeading` | ~45 |
| `vreader/Services/MD/MDAttributedStringRenderer.swift` | `MarkupWalker` → `NSAttributedString` | ~250 |
| `vreader/Services/MD/MDMetadataExtractor.swift` | Title from first H1, fallback to filename | ~45 |
| `vreader/ViewModels/MDReaderViewModel.swift` | ViewModel (lifecycle, debounce, session) | ~250 |
| `vreader/Views/Reader/MDReaderContainerView.swift` | SwiftUI container | ~80 |
| `vreaderTests/Services/MD/MDAttributedStringRendererTests.swift` | Renderer + golden normalization tests | ~250 |
| `vreaderTests/Services/MD/MDMetadataExtractorTests.swift` | Title extraction tests | ~60 |
| `vreaderTests/Services/MD/MockMDParser.swift` | Mock for ViewModel tests | ~40 |
| `vreaderTests/ViewModels/MDReaderViewModelTests.swift` | ViewModel tests | ~250 |
| `vreaderTests/Fixtures/sample.md` | Markdown fixture | ~50 |
| `vreaderTests/Fixtures/sample-empty.md` | Empty fixture | 0 |

### 4.2 Modified Files

| File | Change |
|---|---|
| `BookFormat.swift` | Add `.md` to `importableFormats`, flip `isImportableV1` |
| `BookImporter.swift` | Add `.md` to encoding detection branch + extractor map |
| `LocatorFactory.swift` | Add `mdPosition()` and `mdRange()` aliases |
| `TXTTextViewBridge.swift` | Accept optional `NSAttributedString`; add link delegate |
| `ReaderContainerView.swift` | Add `case "md"` dispatch |
| `LibraryBookItem.swift` | Add `case "md"` format icon |

### 4.3 Tests to Update

| Test | Current Assertion | New Assertion |
|---|---|---|
| `BookFormatTests.importableFormatsExcludesMarkdown` | `!importable.contains(.md)` | `importable.contains(.md)` |
| `BookFormatTests.mdIsNotImportable` | `.isImportableV1 == false` | `.isImportableV1 == true` (rename test) |
| `BookImporterTests.mdFormatThrows` | expects `unsupportedFormat` | expects successful import (rename test) |

---

## 5. Dependency: `swift-markdown`

- **Repository**: `https://github.com/apple/swift-markdown.git`
- **Version pin**: `0.5.0` (exact, for offset stability)
- **License**: Apache 2.0
- **Module**: `Markdown` — provides `Document`, `MarkupWalker`, all node types
- **Transitive deps**: `swift-cmark` (bundled C library)

**SPM integration steps:**
1. Xcode → File → Add Package Dependencies → paste URL
2. Set version to "Exact: 0.5.0"
3. Add `Markdown` framework to `vreader` target
4. Verify build: `DEVELOPER_DIR=... xcodebuild build -scheme vreader ...`
5. Commit `Package.resolved` with project changes

---

## 6. Task Breakdown

### Task 0: Contract Spike (front-loaded risk reduction)

**Goal**: Prove that rendered-text offsets are stable and round-trip correctly before committing to the architecture.

1. Add `swift-markdown` SPM dependency.
2. Write a standalone test that:
   - Parses a Markdown fixture to `NSAttributedString` using a minimal renderer.
   - Extracts the `.string` property (rendered text).
   - Constructs a `Locator` with a UTF-16 offset into the rendered text.
   - Verifies quote extraction works on rendered text.
   - Verifies the same Markdown source produces the same rendered text on re-parse (determinism).
3. Write a golden test that pins the exact `.string` output for a known fixture.

**Exit criteria**: Deterministic rendering confirmed. Offset round-trip proven. If this fails, fall back to raw-source offsets (Option 1 from review).

### Task 1: Bridge Hardening (TXT regression prevention)

**Goal**: Extend `TXTTextViewBridge` to accept `NSAttributedString` without breaking TXT.

**RED:**
- Test: bridge with `attributedText: nil` renders plain text exactly as before (golden string compare).
- Test: bridge with `attributedText` set renders that attributed string.
- Test: link tap on `https://` URL is allowed.
- Test: link tap on `javascript:` URL is blocked.
- Test: scroll-to-offset works identically with attributed text.

**GREEN:**
- Add `attributedText: NSAttributedString?` optional to `TXTTextViewBridge`.
- In `applyText()`: if `attributedText` is non-nil, use it directly; else build from `text` + config (existing behavior).
- Add `textView(_:shouldInteractWith:in:interaction:)` → allow only `http`/`https`.

**Gate**: Run ALL existing TXT tests. Zero regressions.

### Task 2: MD Types + Protocol + Metadata Extractor (parallel group)

**RED:**
- Test: `MDDocumentInfo` stores rendered text, attributed string, headings, title.
- Test: `MDRenderConfig` has font size, line spacing, text color.
- Test: metadata extractor returns first H1 as title.
- Test: no H1 → filename as title.
- Test: empty file → "Untitled".
- Test: H1 after content → still finds first H1.
- Test: title >255 chars truncated.

**GREEN:**
- `MDParserProtocol` with `func parse(text: String, config: MDRenderConfig) async -> MDDocumentInfo`.
- `MDDocumentInfo` with `renderedText: String`, `renderedAttributedString: NSAttributedString`, `headings: [MDHeading]`, `title: String?`.
- `MDRenderConfig` with `fontSize: CGFloat`, `lineSpacing: CGFloat`, `textColor: UIColor`.
- `MDMetadataExtractor` using `swift-markdown` `Document` → find first `Heading` with level 1.

### Task 3: Attributed String Renderer

**RED (golden normalization tests):**
- Test: `"Hello world"` → `"Hello world\n"` (plain paragraph).
- Test: `"# Title"` → `"Title\n"` with H1 font size (2x body).
- Test: `"## Sub"` through `"###### H6"` → decreasing sizes.
- Test: `"**bold**"` → `"bold"` with `.traitBold`.
- Test: `"*italic*"` → `"italic"` with `.traitItalic`.
- Test: `"***both***"` → `"both"` with bold+italic.
- Test: `` "`code`" `` → `"code"` with monospace font.
- Test: fenced code block → content with monospace + background attribute.
- Test: `"[text](https://x.com)"` → `"text"` with `.link` attribute.
- Test: `"- item"` → `"\u{2022} item\n"` with bullet.
- Test: `"1. item"` → `"1. item\n"` with number.
- Test: `"> quote"` → `"quote\n"` with indent + muted color.
- Test: `"---"` → `"\n"` (separator).
- Test: nested lists have `\t` prefix per level.
- Test: nested blockquote flattens to single-level styling.
- Test: empty document → empty `NSAttributedString`.
- Test: CJK headings/body render correctly.
- Test: emoji renders correctly with proper UTF-16 length.

**GREEN:**
- `MDAttributedStringRenderer` as `MarkupWalker`.
- Font sizing: H1=2.0x, H2=1.6x, H3=1.3x, H4=1.1x, H5=1.0x, H6=0.9x.
- Traits: bold `.traitBold`, italic `.traitItalic`, combined.
- Code: monospace at 0.9x, blocks add `.backgroundColor`.
- Links: `.link` attribute with URL.
- Lists: bullet/number prefix with paragraph indent.
- Blockquotes: head indent + `.foregroundColor` muted.
- Thematic break: `\n`.

### Task 4: LocatorFactory + Import Enablement

**RED:**
- Test: `LocatorFactory.mdPosition()` creates valid locator with `.md` fingerprint.
- Test: `LocatorFactory.mdRange()` creates valid locator with char range.
- Test: `BookFormat.importableFormats` includes `.md`.
- Test: `BookFormat.md.isImportableV1 == true`.
- Test: importing a `.md` file succeeds (update existing `mdFormatThrows` test).
- Test: encoding detection runs for `.md` files.
- Test: binary masquerade `.md` rejected.

**GREEN:**
- Add `mdPosition()` and `mdRange()` to `LocatorFactory` (delegate to `txtPosition`/`txtRange` internals).
- Flip `BookFormat`: add `.md` to `importableFormats`, `isImportableV1 = true`.
- In `BookImporter`: add `.md` to encoding detection branch (`format == .txt || format == .md`).
- Add `MDMetadataExtractor` to extractors map.

### Task 5: MDReaderViewModel

**RED:**
- Test: `open(url:)` parses Markdown and sets `renderedContent`.
- Test: `open(url:)` starts reading session.
- Test: `open(url:)` restores saved position.
- Test: `open(url:)` with empty file → empty rendered content, no error.
- Test: `close()` ends session, saves position, cancels debounce.
- Test: `updateScrollPosition()` debounces position save (2s).
- Test: `onBackground()` pauses session, saves position immediately.
- Test: `onForeground()` resumes session (surfaces error on failure).
- Test: position restore falls back to offset 0 on failure.
- Test: parse failure → user-facing error message.
- Test: session time display updates.
- Test: empty document → `totalProgression = 0` (no division by zero).

**GREEN:**
- `MDReaderViewModel` following `EPUBReaderViewModel` pattern.
- `open()`: read data → detect encoding → decode → parse on background → restore position → start session.
- Position: map scroll offset via `TXTOffsetMapper` → `LocatorFactory.mdPosition()` → debounce save.
- `totalProgression`: `guard renderedTextLength > 0 else { return 0 }; return Double(offset) / Double(renderedTextLength)`.

### Task 6: Container View + Dispatch

- Create `MDReaderContainerView` (SwiftUI container wiring ViewModel to bridge).
- Add `case "md"` to `ReaderContainerView.body`.
- Add `case "md"` to `LibraryBookItem.formatIcon` (`"doc.richtext.fill"`).

### Task 7: Integration Tests

- Import `.md` → open → scroll → close → reopen → position restores.
- CJK Markdown offset round-trip.
- Empty `.md` import and open.
- Locator canonical hash stable for `.md`.
- Reading session lifecycle correct for `.md`.

---

## 7. Reading Speed (Deferred)

`wordsRead` computation requires the indexing pipeline (WI-10) to populate `Book.totalWordCount` and `Book.totalTextLengthUTF16` from rendered text. Until indexing is implemented:

- Reading duration tracking works immediately (via `ReadingSessionTracker`).
- `sessionTimeDisplay` shows session time.
- `wordsRead` and `wpm` are nil / not displayed.
- This matches the same behavior EPUB has when `totalWordCount` is not yet available.

---

## 8. Edge Cases

| Edge Case | Behavior |
|---|---|
| Empty `.md` file | Import succeeds, reader shows empty view, `totalProgression = 0` |
| Only syntax (`# \n**\n---`) | Renders minimal content |
| No headings | Title from filename |
| Large `.md` (>5MB) | Full load + background parse, no UI stall |
| 10K-char code block | Monospace rendering, background parse |
| Deeply nested lists (5+) | `\t` prefix per level, no crash |
| Raw HTML tags | Rendered as plain text (visible, not interpreted) |
| YAML frontmatter | Rendered as text/thematic break, not metadata |
| Windows line endings | Normalized by `swift-markdown` parser |
| Content change (external edit) | Quote recovery fallback via `QuoteRecovery` |
| Relative links | Styled as link text, not tappable |
| `javascript:` links | Blocked by `shouldInteractWith` delegate |
| Binary masquerade `.md` | Rejected by `EncodingDetector` |
| Surrogate pairs / emoji in headings | Correct UTF-16 offset tracking (golden tests) |
| Nested blockquotes | Flatten to single-level styling |

---

## 9. Acceptance Criteria

1. `.md` / `.markdown` files importable from Files app and share sheet.
2. Library shows MD format badge and `doc.richtext.fill` icon.
3. Rich rendering: headings, bold, italic, code, links, lists, blockquotes, thematic breaks.
4. Reading position saves (debounced) and restores on reopen, surviving app restart.
5. Reading sessions track correctly (duration, start/end locators).
6. UTF-16 offsets round-trip exactly through Locator save/restore.
7. Quote recovery works on content change.
8. 5MB Markdown files render without UI stall (background parsing).
9. UTF-8 / UTF-16 / legacy encodings detected correctly.
10. Empty `.md` files handled gracefully.
11. All existing TXT / EPUB / PDF tests pass unchanged (except 3 updated MD-negative tests).
12. All new code covered by tests. `ut` passes.
13. Only `http`/`https` links are tappable.
14. Golden normalization tests pin rendered text output.

---

## 10. Sequencing

```
Task 0: Contract Spike (SPM + determinism proof)
    │
    ▼
Task 1: Bridge Hardening (TXT backward compat gate)
    │
    ├────────────────────────┐
    ▼                        ▼
Task 2: Types/Protocol/     Task 3: Renderer
        Metadata Extractor          (golden tests)
    │                        │
    ├────────────────────────┘
    ▼
Task 4: LocatorFactory + Import Enablement
    │
    ▼
Task 5: MDReaderViewModel
    │
    ▼
Task 6: Container + Dispatch
    │
    ▼
Task 7: Integration Tests
```

**Critical path**: Task 0 → Task 1 → Task 3 → Task 5 → Task 6 → Task 7.

Estimated effort: 3-4 days.
