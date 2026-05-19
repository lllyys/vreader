# Feature #68 — Reader chapter-start typography (drop-cap + in-text chapter heading)

**Status target:** `TODO` → `PLANNED` (this Gate-1 plan) → `IN PROGRESS` → `DONE` → `VERIFIED`
**GH:** #867 | **Priority:** Low | **Lineage:** v2 follow-on of feature #60 (VERIFIED) | **Design bundle:** `dev-docs/designs/vreader-fidelity-v1/`

---

## Revision history

| Rev | Date | Change |
|-----|------|--------|
| v1 | 2026-05-18 | Initial Gate-1 draft. Pending Gate-2 independent audit. |
| v2 | 2026-05-19 | Gate-2 audit revision (Codex `019e3bee`, verdict NEEDS-REVISION). Resolves 3 HIGH, 5 MEDIUM, 2 LOW round-1 findings. Headline changes: (1) synthetic TXT chapters get the drop-cap only — no injected heading, so the rendered string + all UTF-16 offsets are byte-identical in every TXT path; (2) native TXT/MD heading restyle keeps source casing — no character-changing uppercase; small-caps font feature considered and explicitly rejected for v1; (3) `MDRenderConfig` plumbing added through `MDReaderViewModel.open` → `MDFileLoader.load` → `parser.parse`; (4) MD scope narrowed to the leading document heading only; (5) WI-2/WI-3 marked sequential (shared `ReaderSettingsStore.swift` writer); (6) concrete EPUB/Foliate drop-cap selector `body > p:first-of-type` pinned; (7) up-front paged-mode verification gate + fallback added to WI-2/WI-3; (8) Foliate mapper path corrected; (9) `"前言"` provenance corrected. See §13 round-1 audit-trail table. |
| **v3** | **2026-05-19** | **Round-2 Gate-2 audit revision (verdict NEEDS-REVISION). Resolves 3 round-2 findings (2 MEDIUM, 1 LOW). Headline changes: (A) Finding 1 — the MD container call site was misidentified as `EPUBReaderContainerView.swift:134` (that is the EPUB reader). Corrected to `MDReaderContainerView.swift:116-119`; WI-3 retargeted and the full `MDReaderContainerView → MDReaderViewModel.open → MDFileLoader.load → parser.parse` path re-verified. (B) Finding 2 — MD has NO live theme re-render path (`MDReaderContainerView` calls `open` exactly once in a non-keyed `.task`; there is no `.task(id:)` keyed on theme and no `.onChange(of: theme)`; `renderedAttributedString` is assigned only inside `open`). The v2 acceptance contract was internally inconsistent (criterion 4 said "next open", criterion 7 / §11 said "live"). v3 picks the honest option: MD theme changes are verified after reopen; TXT/EPUB/Foliate remain live. Criterion 4, criterion 7, §11, §4.3 R10, WI-3 made consistent. (C) Finding 3 — §2 wrongly said `TXTChapterContentLoader` loads "from `startByte`"; it actually slices the decoded full text by `globalStartUTF16` + `textLengthUTF16`. §2 corrected to the real loader mechanism. See §14 round-2 audit-trail table. All v2 round-1 fixes preserved.** |

---

## 1. Problem

The committed v2 design (`dev-docs/designs/vreader-fidelity-v1/project/vreader-reader.jsx`) renders, at the start of every chapter, two typographic elements that **were never built in any VReader renderer**:

1. **In-text chapter heading** (`vreader-reader.jsx:333-343`) — a centered, uppercase, serif chapter title that sits *in the text flow* at the top of the first page of a chapter. It is rendered inside `PageContent` (the text block), distinct from the top-of-screen caption. Design styling:
   - `fontFamily: '"Source Serif 4", Georgia, serif'`
   - `fontSize: 13` (fixed px, not scaled with body size)
   - `color: t.sub` (the theme's secondary token — alpha-blended ink)
   - `letterSpacing: 2`, `textTransform: 'uppercase'`, `textAlign: 'center'`
   - `marginBottom: 18`, `marginTop: 8`, `fontWeight: 500`
   - Render condition: `pageIdx === 0 || page.chapter !== <previous page's chapter>` — i.e. only on the page where a chapter *begins*.

2. **Drop-cap** (`vreader-reader.jsx:383-390`) — a large oxblood first letter on the chapter's first paragraph, floated left so body text wraps around it. Design styling:
   - `fontFamily: '"Source Serif 4", Georgia, serif'`
   - `fontSize: fontSize * 2.6` (2.6× the body font size)
   - `lineHeight: 0.85`
   - `float: 'left'`, `marginRight: 6`, `marginTop: 4`
   - `color: theme.accent` (the oxblood accent token), `fontWeight: 600`
   - Render condition: `first` paragraph only (`i === 0` in `PageContent`'s paragraph map), and the drop-cap glyph is sliced off the body text so it is not double-rendered.

**What exists today and is NOT this feature:** the shipped `ChapterTitleOverlay` (`vreader/Views/Reader/TXTChapterOverlayViews.swift:19-39`) is a `.caption`-sized, `.secondary`-colored, single-line **top-of-screen caption bar**, TXT-only, shown only when chrome is visible. It corresponds to the design's *other* heading at `vreader-reader.jsx:154-164` (the absolutely-positioned `top: 54` element shown `chromeVisible ? '' : pageData.chapter`). It is a separate surface; this feature does not touch it and does not replace it.

**Informational — gap against feature #60's VERIFIED status:** feature #60 acceptance criterion (b) ("Reader matches the design's chrome + page layout pixel-close") was recorded `result: pass` in `dev-docs/verification/feature-60-20260516.md`, but these two in-text typographic elements were never implemented. #60's evidence overstated reader-layout coverage. **This is informational only** — #68 is the corrective follow-on. No action against #60's row is part of this plan; #68 simply completes the designed surface.

**User need:** chapter starts in the VReader reader look unfinished compared to the committed design — a flat run of body paragraphs with no typographic "chapter opens here" signal. The drop-cap and in-flow heading are the design's deliberate literary-typography cue. This feature delivers them.

---

## 2. Per-format scope decision (key design question #1)

**The design question:** for EPUB/AZW3/MOBI, the book's own packaged HTML almost always already contains its own chapter heading markup (`<h1>`, `<h2>`, etc.) and frequently its own publisher-styled drop-cap or styled first line. Does the design's in-text heading **duplicate** the book's own `<h1>`?

**Investigation findings (verified against the codebase, 2026-05-19):**

- The TXT renderer (`TXTReaderContainerView` → `TXTAttributedStringBuilder`) renders **plain text** — there is no native heading markup; a chapter is plain prose with, at most, a heading *line* of text. TXT chapter boundaries are known to the renderer via `TXTChapterIndex` / `TXTChapter` (`vreader/Services/TXT/TXTChapterIndex.swift`); the reader renders one chapter at a time in chapter mode (`TXTReaderViewModel.currentChapterText`).
- **Critical sub-finding — corrected in v3 (round-2 Finding 3).** For **regex-detected** TXT chapters, `TXTChapterIndexBuilder.buildWithRegex` records, for each `TXTChapter`, both a byte boundary (`startByte`) at the heading-line match *and* the UTF-16 boundary fields `globalStartUTF16` / `textLengthUTF16`. The chapter content is **not** loaded "from `startByte`": `TXTChapterContentLoader.loadChapter` (verified at `TXTChapterContentLoader.swift:29-49`) **decodes the full file once** into an `NSString` and then **slices that string** with `NSRange(location: chapter.globalStartUTF16, length: chapter.textLengthUTF16)`. Because the regex builder sets the chapter's UTF-16 start to the offset of the matched heading line itself, the sliced `currentChapterText` **already begins with the heading line as its first line of text**. The mechanism is *full-decode-then-UTF-16-slice*, not a byte-range read. (v2's §2 wrongly described a `startByte` load; the chapter-start conclusion was directionally right but the cited mechanism was wrong — this is now corrected.) The `TXTChapter.title` field is a trimmed copy of that same matched heading line (`TXTChapterIndexBuilder.swift:122-124`). **Provenance (confirmed correct in v2):** the special `"前言"` chapter is created **inside `buildWithRegex`** (`TXTChapterIndexBuilder.swift:158-174`) when matched content does *not* start at the file head — it is a *regex-path* artefact, not a `buildSynthetic` product. `buildSynthetic` (lines 199-249) **only ever fabricates `"Chapter N"` titles** (lines 211, 224-227, 240-243); it never produces `"前言"`. Both `"前言"` and `"Chapter N"` are titles that do **not** appear verbatim as the first line of the corresponding body text — they are *not in the body*.
- The MD renderer (`MDAttributedStringRenderer.render`) renders the **whole document** as one `NSAttributedString`; headings are `#`-prefixed Markdown lines, captured as `MDHeading{level, text, charOffsetUTF16}` (`MDTypes.swift:37-44`). **Verified:** `MDHeading` carries *only* `level`, `text`, and `charOffsetUTF16` — it does **not** encode whether a heading follows a thematic break. MD has **no chapter mode** — there is no `currentChapterText`; the entire file is one flow.
- The EPUB renderer (`EPUBWebViewBridge`) loads the book's own XHTML spine items into a `WKWebView`; theme is applied by injecting a `<style id="vreader-theme">` blob built by `ReaderThemeV2.epubOverrideCSS` (`vreader/Models/ReaderThemeV2+EPUBCSS.swift`). The book's own `<h1>`/`<hN>` headings are present in the DOM (the CSS even has an explicit `h1,h2,h3,h4,h5,h6 { font-size: revert … }` rule at lines 118-122 preserving them).
- The AZW3/MOBI renderer (`FoliateViewBridge`) renders the book's own HTML through Foliate-js; theme CSS is pushed via `readerAPI.setStyles(...)`, built by `FoliateStyleMapper.themeCSS` (`vreader/Services/Foliate/FoliateStyleMapper.swift` — note the **`Services/Foliate/`** path). Same as EPUB: the book's own heading markup is in the DOM.

**Decision — split the feature by what each format's content model supports:**

| Element | TXT | MD | EPUB | AZW3/MOBI | PDF |
|---|---|---|---|---|---|
| **In-text chapter heading** | **Restyle** the heading line that already exists at the chapter start (regex-detected chapters only). For **synthetic** chapters and the **`"前言"`** chapter — whose titles are *not* present in the body — **do nothing** (no injected heading; the top-of-screen `ChapterTitleOverlay` already names them). | **Restyle** the document's **leading** `#` heading only (first `MDHeading`, if it sits at offset 0). Post-thematic-break detection is **out of scope** — `MDHeading` does not encode break adjacency. Do **not** inject. | **Do NOT inject a VReader heading.** The book's own `<h1>` is the chapter heading. Untouched by v1. | Same as EPUB — Foliate renders the book's own headings; do not inject. | n/a — PDF is a fixed page raster; PDFKit renders the publisher's own layout. Out of scope. |
| **Drop-cap** | **Inject** via `NSAttributedString` attributes — TXT has no markup, so this is purely a VReader-applied effect on the first body paragraph. Attributes only — the rendered *string* is byte-identical to today. | **Inject** via `NSAttributedString` attributes on the first body paragraph after the document's leading heading (or the very first paragraph when there is no leading heading). Attributes only. | **Inject** via CSS `body > p:first-of-type::first-letter` on the spine document's first paragraph. | **Inject** via the same CSS rule pushed through Foliate `setStyles`. | n/a |

**Justification:** the design depicts a *single, restyled* heading and *one* drop-cap per chapter start. Injecting a VReader heading into EPUB/AZW3 would produce a **visible duplicate** next to the book's own `<h1>` — a regression, and a clear design-fidelity violation. Therefore:
- For TXT regex chapters / MD the heading already exists *as text content* and the correct move is to give the existing in-flow line the design's typographic treatment.
- For TXT synthetic / `"前言"` chapters the title is **not** in the body. v1 does **not** inject one — see §3.2 and the HIGH resolution in §13. The drop-cap still applies; the chapter's name is already shown by the top-of-screen overlay.
- For EPUB/AZW3 the heading exists *as DOM markup* and the correct move is CSS styling of the existing element, never injection.
- The drop-cap is genuinely *new* presentation in every reflowable format (no book ships a `::first-letter` we want to keep), so it is injected/applied in every reflowable format.

**The single most important v2 invariant:** in **every** TXT and MD code path, the feature changes only `NSAttributedString` **attributes** — never the backing string, never its UTF-16 length. No synthetic heading is ever prepended. Therefore every offset-based subsystem (positions, highlights, search, TTS ranges) sees a byte-identical string and is unaffected. See §9.

This keeps the feature "make the chapter start match the design" without inventing duplicate content. It is consistent with how feature #60 already treats EPUB headings (`h1,h2,…{font-size: revert}` deliberately preserves the book's own headings rather than overriding them).

---

## 3. Prior art / project precedent / rejected alternatives

### 3.1 Prior art we build on

| Pattern | Location | How #68 uses it |
|---|---|---|
| **Theme token surface** | `ReaderThemeV2` (`vreader/Models/ReaderThemeV2.swift`) — `accentColor` (oxblood: `0x8c2f2f` Paper, `0x7a3a1f` Sepia, `0xd6885a` Dark/OLED, `0xe8b465` Photo), `subColor` (alpha-blended ink), `inkColor`. | Drop-cap color = `theme.accentColor`; in-text heading color = `theme.subColor`. Both pulled from the existing V2 token set — no new color tokens. |
| **Serif typography registry** | `ReaderTypography` (`vreader/Services/ReaderTypography.swift`) — `body(for:size:)` returns a `UIFont`; `cssFontStack(for:)` returns a CSS stack. The `.sourceSerif4` case has a documented fallback chain to Georgia. | Heading + drop-cap need a *serif* face (`"Source Serif 4", Georgia, serif`) regardless of the user's body font choice. Use `ReaderTypography.body(for: .sourceSerif4, size:)` for attributed-string paths and `ReaderTypography.cssFontStack(for: .sourceSerif4)` for CSS paths. |
| **EPUB CSS injection blob** | `ReaderThemeV2.epubOverrideCSS` (`vreader/Models/ReaderThemeV2+EPUBCSS.swift`, 235 lines) builds the `<style id="vreader-theme">` blob; `EPUBWebViewBridge` injects/refreshes it. `cssColor(_:)` already renders `accentColor` (line 73). | Append a `body > p:first-of-type::first-letter` rule (drop-cap) to the existing blob, reusing the already-computed `accent` string. No new injection path — extend the existing one. |
| **Foliate CSS injection** | `FoliateStyleMapper.themeCSS` (`vreader/Services/Foliate/FoliateStyleMapper.swift`, 90 lines) builds the CSS; `FoliateViewBridge` pushes it via `readerAPI.setStyles`. All values sanitized through `FoliateJSEscaper`. | Add the same `::first-letter` rule. `themeCSS` currently has **no** accent parameter — WI-5 adds one. Reuse `FoliateJSEscaper.sanitizeCSSColor` for the accent. |
| **Off-main attributed-string build** | `TXTAttributedStringBuilder.build/buildSendable` (pure, `@Sendable`-safe, called from `Task.detached` in `TXTReaderContainerView`'s `.task(id: attrStringKey)`). MD: `MDAttributedStringRenderer.render` (pure, builds `MDDocumentInfo`), invoked via `parser.parse` inside `MDFileLoader.load`'s `Task.detached`. | Drop-cap + heading restyling are added inside / immediately after these pure builders so they run off the main thread. No new threading. |
| **`MDHeading` offset capture** | `MDAttributedStringRenderer.render` records every heading with `level + text + charOffsetUTF16` (`MDTypes.swift:37`), surfaced on `MDDocumentInfo.headings`. | The decorator reads `headings` to locate the leading heading and the first body paragraph after it — no re-parse. |
| **TXT chapter mode** | `TXTReaderViewModel.currentChapterText` / `currentChapterTitle` / `currentChapterIdx` / `chapterIndex`; `TXTReaderContainerView` builds the chapter attributed string per chapter via `.task(id: attrStringKey)` (verified at lines 277-311). The full-file decode + UTF-16 slice happens in `TXTChapterContentLoader.loadChapter`. | The drop-cap applies to the first paragraph of `currentChapterText`. The heading restyle applies to the chapter's first line (regex chapters). `attrStringKey` already keys on `currentChapterIdx` so a chapter swap rebuilds; it also keys on theme colors so a theme switch rebuilds. |
| **TXT live theme re-render** | `TXTReaderContainerView`'s `.task(id: attrStringKey)` re-fires whenever `attrStringKey` changes. `makeAttrStringKey` hashes `config.textColor` / `config.backgroundColor` (verified at `TXTReaderContainerView.swift:120-122`), so a theme switch re-runs the builder over the **already-held `currentChapterText`** — no file reopen. | This is the model WI-2 extends for TXT (hash the two new colors into the key). It is **also the model MD lacks** — see §4.3 and round-2 Finding 2: MD has no `.task(id:)` and re-renders only on `open`. |

### 3.2 Rejected alternatives

| Alternative | Why rejected |
|---|---|
| **Inject a VReader chapter heading into EPUB/AZW3 via CSS `::before` or a DOM node.** | The book's own `<h1>` is already there — this produces a visible duplicate. A user-visible regression; the design depicts one heading, not two. |
| **Inject a synthetic in-flow heading for TXT synthetic / `"前言"` chapters (v1's WI-2 proposal).** | **Rejected in v2 (HIGH audit finding).** v1 was internally inconsistent: §2/WI-2 proposed injecting an in-flow heading for chapters whose title is not in the body, while §7 R7 / §10 recommended *no* synthetic heading. Prepending a heading — even "display-only" — **changes the `NSAttributedString`'s backing string and its UTF-16 length**, so the `UITextView`'s offsets would no longer match `currentChapterText`; scroll-position mapping, highlight ranges, search hit ranges and TTS sentence ranges would all shift by the prepended length. v2 resolves this cleanly: **synthetic and `"前言"` chapters get the drop-cap only, no injected heading.** The `NSAttributedString.string` is byte-identical to today in every TXT path. The chapter's name is already presented by the top-of-screen `ChapterTitleOverlay`. The design's in-flow heading is meaningful only for *real* (regex-detected) chapter titles that exist as text in the chapter anyway. |
| **Uppercase the native TXT/MD heading text** (`headingText.uppercased()`). | **Rejected in v2 (HIGH audit finding).** v1 said "uppercase the heading text" while also claiming the rendered string is unchanged and offsets are stable — a contradiction. `NSAttributedString` has **no `text-transform`**; `String.uppercased()` *changes the characters* and can change UTF-16 length (e.g. German `ß` → `SS`, ligatures, some scripts), which would break the offset invariant for any heading line that is part of the body. v2 keeps **source casing** for native TXT/MD heading strings. The design's `textTransform: 'uppercase'` is honoured only on the CSS side (EPUB/AZW3, where it is a real CSS property) — and EPUB/AZW3 headings are out of scope for v1 anyway (§4.4), so no uppercase ships in v1 at all for headings. A small-caps / uppercase **font feature** via `UIFontDescriptor.FeatureSettings` (`kUpperCaseType` / `kCaseSensitiveLayoutType`) *would* preserve the underlying characters; it was considered and **rejected for v1** because (a) Source Serif 4 is not yet bundled and the Georgia fallback's small-caps feature coverage is inconsistent, (b) it adds a font-feature code path with its own tests for marginal fidelity gain. **v1 decision: native TXT/MD heading restyle = serif face + size + tracking + centering + `subColor`, source casing preserved, no case transform.** This is stated explicitly and every section is consistent with it. |
| **Render the in-text heading as a separate SwiftUI `Text` view overlaid on the TXT/MD `UITextView`.** | The design heading is *in the text flow* — body text must start *below* it and scroll with it. A SwiftUI overlay would not scroll with the content and would not reflow. For regex chapters the heading line is *already in the flow*; restyling its run is the correct, offset-preserving move. |
| **Drop-cap for TXT/MD via `NSTextAttachment`.** | An attachment is an inline atomic glyph box — it does **not** float; body text cannot wrap *around* it. The design wants a 2-3-line capital with text wrapping to its right. Attachments cannot do float-left wrap. Also, an attachment occupies one UTF-16 unit of `\u{FFFC}` — it would *change the string*, breaking the offset invariant. Rejected. |
| **Drop-cap for TXT/MD via TextKit exclusion paths (`NSTextContainer.exclusionPaths`).** | Exclusion paths would produce a true floated drop-cap, but: (a) the exclusion rect depends on the laid-out glyph size, known only after a layout pass — a chicken-and-egg problem; (b) it must be recomputed on every font-size / Dynamic Type / theme change and on chapter swap; (c) it interacts badly with the chunked renderer and the paged-mode `NativeTextPaginator`; (d) it is per-`UITextView` view state, not part of the `NSAttributedString`, so it does not survive the off-main build model. High complexity, high regression surface. **Rejected for v1.** |
| **Drop-cap for TXT/MD via a real floated capital.** | TextKit 1 (the TXT/MD stack) has no float primitive at all. Not possible. |
| **Drop-cap for TXT/MD via an oversized first-character run with a tuned negative `baselineOffset` + paragraph `firstLineHeadIndent`.** | This is the **recommended** approach (see §4). It does not produce a *true* multi-line wrap, but it produces a faithfully large, oxblood, serif initial at the paragraph start with the body's first line indented to clear it — a close approximation that is robust, layout-engine-native, survives off-main build, and needs no post-layout recomputation. **This is a per-format rendering decision the design (a web/CSS float) does not explicitly cover** — see §8. Per the Gate-2 auditor's explicit ruling, this is an acceptable engine-constraint implementation of an already-designed element and does **not** require a `needs-design` issue. |
| **Add a live MD theme re-render path (a `.task(id:)` or `.onChange(of: theme)` on `MDReaderContainerView`).** | **Considered and rejected for v1 (round-2 Finding 2).** TXT gets live theme switching for free because `TXTReaderContainerView` already holds `currentChapterText` and re-runs `TXTAttributedStringBuilder` via `.task(id: attrStringKey)`. MD has no equivalent: `MDReaderContainerView` calls `viewModel.open` exactly once in a non-keyed `.task` (verified at `MDReaderContainerView.swift:108-119`); `renderedAttributedString` is `private(set)` and assigned only inside `open`. Two ways to add a live path were evaluated. (1) **Re-decorate the held attributed string only** — the `MDChapterStartDecorator` runs on a held string, so re-decorating with new colors *is* cheap; but the MD body colors (blockquote / code-block backgrounds) come from `parser.parse` *inside* `MDFileLoader.load`, not from the decorator — a decorate-only re-run would update the drop-cap + heading and leave the body half-themed. (2) **Reopen the file on theme change** — a true live re-theme, but it re-reads + re-parses the file, is racey against the `openGeneration` guard, and would need careful scroll-position preservation. Neither is the "small add" the round-2 audit asked us to weigh — (1) is incorrect (half-themed) and (2) is a non-trivial reopen path. MD already lives with exactly this limitation for Chinese conversion: `MDReaderViewModel.swift:113-115` documents that MD live re-apply on a conversion toggle "requires a close + reopen cycle … applied at open time only." v3 keeps MD consistent with that: **MD theme changes apply on the next open.** TXT/EPUB/Foliate keep their live behavior. See §4.3, R10, criterion 4, criterion 7, §11. |
| **One giant cross-cutting PR touching all four renderers.** | Violates rule 47 WI sizing (1 PR per WI) and rule 48 (one writer per file/area). Split into per-renderer WIs. |
| **A new shared `ChapterStartTypography` service used by all renderers.** | The two render models (attributed string vs injected CSS) are too different to share rendering logic. The *values* (sizes, the 2.6× multiplier, the serif stack) are shared as constants (WI-1); the *rendering* stays per-renderer. |

### 3.3 Project-precedent notes

- Feature #60 is the direct lineage. Its plan (`dev-docs/plans/20260515-feature-60-visual-identity-v2.md`) and its WI-4 (EPUB CSS) / WI-5 (TXT+MD theme injection) established the exact files and patterns #68 extends. #68 is deliberately small — it is the chapter-start typography slice #60 missed.
- `ReaderTypography.swift`'s header explicitly anticipates downstream consumers; #68 is another such consumer.
- The codebase convention (rule 50 §9) caps files at ~300 lines. Verified line counts: `ReaderThemeV2+EPUBCSS.swift` = **235**, `MDAttributedStringRenderer.swift` = **457**, `FoliateStyleMapper.swift` = **90**, `TXTAttributedStringBuilder.swift` = **54**, `TXTViewConfig.swift` = **54**, `MDTypes.swift` = **90**, `TXTReaderContainerView.swift` = **862**, `MDReaderContainerView.swift` = **378**, `MDReaderViewModel.swift` = **265**, `MDFileLoader.swift` = **101**. The MD renderer is already well over budget — WI-3 must add its decoration logic as a **new file** (`MDChapterStartDecorator.swift`), not by growing the 457-line file. WI-4 adds ~16 lines to the 235-line EPUB-CSS file — acceptable.

---

## 4. Surface area (file-by-file)

### 4.1 New file — shared constants

**`vreader/Services/ChapterStartTypography.swift`** (NEW, ~65 lines)
A stateless `enum` namespace holding the design-pinned constants so all four renderers agree on the numbers and the values are unit-testable in one place.

```swift
enum ChapterStartTypography {
    /// Drop-cap size multiplier over body font size. Design: vreader-reader.jsx:386.
    static let dropCapScale: CGFloat = 2.6
    /// Drop-cap line-height multiplier. Design: :386 (lineHeight: 0.85).
    static let dropCapLineHeight: CGFloat = 0.85
    /// In-text chapter heading fixed point size. Design: :337 (fontSize: 13).
    static let headingFontSize: CGFloat = 13
    /// Heading tracking (letter-spacing) in points. Design: :337 (letterSpacing: 2).
    static let headingLetterSpacing: CGFloat = 2
    /// Heading space-below in points. Design: :339 (marginBottom: 18).
    static let headingSpacingAfter: CGFloat = 18
    /// Heading space-above in points. Design: :339 (marginTop: 8).
    static let headingSpacingBefore: CGFloat = 8
    /// Heading weight. Design: :339 (fontWeight: 500).
    static let headingFontWeight: UIFont.Weight = .medium
    /// Drop-cap weight. Design: :388 (fontWeight: 600).
    static let dropCapFontWeight: UIFont.Weight = .semibold

    /// CSS `font-size` for the EPUB/Foliate drop-cap `::first-letter` rule.
    static let dropCapCSSFontSizeEm: String = "2.6em"
    /// Whether `scalar` is eligible to be a drop-cap initial (letter/number,
    /// not whitespace/quote/punctuation/combining-mark; CJK ideographs
    /// excluded — see Risks R4).
    static func isDropCapEligible(_ scalar: Unicode.Scalar) -> Bool { ... }
}
```

This is a **foundational** WI — pure constants + one pure predicate, no behavior. **v2 note:** there is deliberately no uppercase/case-transform constant or helper — see §3.2.

### 4.2 TXT renderer

**`vreader/Services/TXT/TXTAttributedStringBuilder.swift`** (MODIFY, currently 54 lines)
Add an opt-in chapter-start variant of `build`. The current `build(text:config:)` and `buildSendable(text:config:)` stay **byte-for-byte untouched** (used by legacy full-text + chunked paths). Add:

```swift
/// Builds the attributed string for a chapter, applying the design's
/// chapter-start typography. CONTRACT: the returned string's backing
/// `.string` is IDENTICAL to `NSAttributedString(string: text, …).string`
/// — only attributes are added. No characters are inserted, removed, or
/// case-transformed.
/// - headingLineLength: UTF-16 length of the leading heading line that is
///   ALREADY part of `text` (regex-detected chapters). 0 means no heading
///   line is present in the body (synthetic / "前言" chapters) — those
///   chapters get the drop-cap only, with NO heading restyle and NO
///   injected heading.
static func buildChapterStart(
    text: String,
    config: TXTViewConfig,
    headingLineLength: Int
) -> NSAttributedString

static func buildChapterStartSendable(
    text: String, config: TXTViewConfig, headingLineLength: Int
) -> SendableAttributedString
```

**v2 change vs v1:** the `injectedHeading: String?` parameter is **removed** — synthetic chapters never receive an injected heading. The method *only* ever restyles an existing run or applies the drop-cap; it never grows the string.

- **Drop-cap run:** take the first drop-cap-eligible scalar of the first *body* paragraph (the paragraph starting at offset `headingLineLength`; offset 0 when `headingLineLength == 0`). Apply a serif font at `config.fontSize * ChapterStartTypography.dropCapScale` via `ReaderTypography.body(for: .sourceSerif4, size:)`, `foregroundColor = config.accentColor`, `dropCapFontWeight`, and a tuned negative `baselineOffset` so the oversized capital's top aligns with the body line. Set the first body paragraph's `NSMutableParagraphStyle.firstLineHeadIndent` to the rendered capital's advance width so the body's first line clears it. If the first eligible scalar cannot be found (empty paragraph, all-ineligible — see R4/R5), **skip the drop-cap** (no crash, no-op).
- **Heading run (regex chapters only, `headingLineLength > 0`):** over the UTF-16 range `0..<headingLineLength`, apply `ChapterStartTypography.headingFontSize` serif font at `headingFontWeight`, `.kern = headingLetterSpacing`, a centered `NSMutableParagraphStyle` with `paragraphSpacing = headingSpacingAfter` and `paragraphSpacingBefore = headingSpacingBefore`, `foregroundColor = config.chapterHeadingColor`. **The heading text characters are unchanged — no `.uppercased()`.**

`TXTViewConfig` needs two new fields so the builder has the accent + heading colors without a `ReaderThemeV2` dependency in the pure builder:

**`vreader/Views/Reader/TXTViewConfig.swift`** (MODIFY, currently 54 lines)
Add to `struct TXTViewConfig`:
```swift
/// Drop-cap color for the chapter-start initial. Defaults to a near-black
/// matching the existing `textColor` default for back-compat with
/// non-chapter call sites (tests/previews).
var accentColor: UIColor = UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1.0)
/// In-text chapter-heading color. Defaults to a mid-gray for back-compat.
var chapterHeadingColor: UIColor = UIColor(white: 0.4, alpha: 1.0)
```
Extend `renderingEquals` to compare both (so a theme switch triggers a rebuild).

**`vreader/Services/ReaderSettingsStore.swift`** (MODIFY — the `txtViewConfig` computed property, verified at lines ~207-228)
In the existing `txtViewConfig` computed property, set `c.accentColor = theme.accentColor` and `c.chapterHeadingColor = theme.subColor` (the store already exposes `theme` as `ReaderThemeV2`; `uiSecondaryTextColor` already returns `theme.subColor`). **Rule-48 note:** this file is *also* edited by WI-3's `mdRenderConfig` change — see §5: WI-2 and WI-3 are **sequential**, not parallel.

**`vreader/Views/Reader/TXTReaderContainerView.swift`** (MODIFY, currently 862 lines)
In the `.task(id: attrStringKey)` chapter-based branch (verified at lines 282-311), call `buildChapterStart` / `buildChapterStartSendable` instead of `build` / `buildSendable` when `viewModel.currentChapterText != nil`, passing `viewModel.currentChapterHeadingLineLength`. The legacy full-text and chunked branches keep calling plain `build` (no chapter boundaries → no chapter-start typography).
Extend `makeAttrStringKey` (verified signature at lines 112-122 — currently `hasText, textLen, wordCount, chIdx, chCount, config, chineseConversion`, and it currently hashes only `config.textColor` / `config.backgroundColor` at lines 120-122) so the key reflects the two new colors and the heading-line length, otherwise a theme switch or chapter swap that changes only those would not rebuild. Concretely: hash `config.accentColor` and `config.chapterHeadingColor` into the key string (alongside the existing `textColorHash` / `bgColorHash`), and add a `headingLineLength` component. `attrStringKey` already includes `chIdx` so a chapter swap rebuilds the index portion; the new component covers the case where two chapters share an index value across a re-open. **This is the seam that gives TXT live theme switching** — the `.task(id:)` re-fires on a key change and rebuilds over the already-held `currentChapterText`.

**`vreader/ViewModels/TXTReaderViewModel.swift`** (MODIFY — read-only computed addition)
Add one computed property:
```swift
/// For the current chapter: the UTF-16 length of the heading line that
/// is part of `currentChapterText` (regex-detected chapters), or 0 when
/// the chapter is synthetic / "前言" / has no leading heading line in its
/// body. Drives WI-2's buildChapterStart `headingLineLength` argument.
/// Pure derivation — see below; no persistence, no schema change.
var currentChapterHeadingLineLength: Int { ... }
```
**Derivation (zero-migration, the recommended path):** `TXTChapter` (verified — `Codable, Sendable, Equatable`, fields `index/title/startByte/endByte/globalStartUTF16/textLengthUTF16`) carries **no** `isSynthetic` flag, and adding one would mutate a `Codable`-persisted struct. Instead, derive at render time: take the first line of `currentChapterText` (up to the first `\n`), trim it; if it equals `currentChapterTitle` trimmed, the chapter is regex-detected and the heading-line length = that first line's UTF-16 length (excluding the newline — the restyle runs over the visible line). Otherwise return `0`. This is a pure function, fully unit-testable, and correctly returns `0` for both synthetic (`"Chapter N"`) and `"前言"` chapters because neither title appears verbatim as the body's first line. **v2 note:** the v1 §4.2 companion property `currentChapterInjectedHeading` is **removed** — nothing is ever injected. **v3 note:** this derivation is unaffected by the round-2 Finding 3 correction — the loader slices `currentChapterText` from `globalStartUTF16`, and the regex builder sets that start to the heading-line match, so the heading line *is* the body's first line; the derivation reads `currentChapterText` directly and never touches `startByte`.

### 4.3 MD renderer

**`vreader/Services/MD/MDChapterStartDecorator.swift`** (NEW, ~95 lines) — *new file because `MDAttributedStringRenderer.swift` is already 457 lines, well over the ~300-line budget (rule 50 §9).*
A pure helper that, given the `NSAttributedString` and `[MDHeading]` produced by `MDAttributedStringRenderer.render`, returns a decorated copy:
- Restyles the document's **leading** heading — `headings.first`, **only if its `charOffsetUTF16 == 0`** (it is the document's first block) — with the chapter-heading typography (serif, `headingFontSize`, tracked, centered, `subColor`, **source casing preserved — no uppercase**).
- Applies the drop-cap run to the first drop-cap-eligible character of the first **plain body paragraph** that follows that leading heading (or the very first paragraph when the document has no leading heading at offset 0). Skips list / code-block / blockquote first blocks (a drop-cap on a bullet is wrong).

```swift
enum MDChapterStartDecorator {
    /// Returns a copy of `attributed` with chapter-start typography applied:
    /// the leading heading restyled (only when it is the document's first
    /// block, charOffsetUTF16 == 0) and a drop-cap on the first body
    /// paragraph. CONTRACT: `decorate(...).string == attributed.string`
    /// — attributes only, never the backing string. No-op when the
    /// document is empty or has no body text. `config` carries the colors.
    static func decorate(
        _ attributed: NSAttributedString,
        headings: [MDHeading],
        config: MDRenderConfig
    ) -> NSAttributedString
}
```

**MD scope (v2 — narrowed per the round-1 MEDIUM audit finding):** v1 §2 promised heading styling "when a heading is first in the document **or follows a thematic break**". `MDHeading` carries only `level/text/charOffsetUTF16` — it does **not** record thematic-break adjacency, and `MDAttributedStringRenderer` emits a thematic break as a bare `"\n"` with no marker (verified at `MDAttributedStringRenderer.swift:63-67`). Implementing post-break detection would require extending renderer metadata. **v2 decision: v1 styles the leading document heading only.** Post-thematic-break heading styling is explicitly **deferred**; if wanted later it is a separate slice that first extends `MDHeading` (or emits a break marker). Every section of this plan now says "leading heading only".

**`vreader/Services/MD/MDTypes.swift`** (MODIFY, currently 90 lines)
Add to `struct MDRenderConfig`:
```swift
/// Drop-cap color for chapter-start typography. Defaults to .label.
var accentColor: UIColor = .label
/// Chapter-heading color for chapter-start typography. Defaults to .secondaryLabel.
var chapterHeadingColor: UIColor = .secondaryLabel
```
Extend the `==` operator (verified at `MDTypes.swift:79-89`) to include both fields in the UIKit branch.

**`vreader/Services/MD/MDAttributedStringRenderer.swift`** (NOT modified for the decorate call — see plumbing below)
v2 keeps `render` **pure and untouched** so the decorator stays independently testable and the 457-line file is not grown.

**MD config plumbing (v2 — resolves the round-1 HIGH audit finding; v3 — corrects the final call site per round-2 Finding 1).** Verified problem: `MDFileLoader.load` **hardcodes** `let config = MDRenderConfig.default` (`MDFileLoader.swift:47`) and passes it to `parser.parse` (`MDFileLoader.swift:60`); `MDReaderViewModel.open(url:chineseConversion:)` has **no render-config parameter** (`MDReaderViewModel.swift:114`). `ReaderSettingsStore.mdRenderConfig` exists and is theme-aware (`ReaderSettingsStore.swift:194-205`), but **nothing reads it** — verified, the only reference is its own declaration. So merely adding fields to `mdRenderConfig` would *not* reach rendering. v2/v3 add a config seam end-to-end:

1. **`MDReaderViewModel.open`** gains a parameter:
   `func open(url: URL, renderConfig: MDRenderConfig = .default, chineseConversion: ChineseConversionDirection = .none) async` — default `.default` keeps every existing test/preview call site compiling unchanged.
2. **`MDFileLoader.load`** gains a parameter and drops the hardcode:
   `static func load(url:, parser:, positionStore:, bookFingerprintKey:, renderConfig: MDRenderConfig = .default, chineseConversion: …) async throws -> MDLoadResult` — `MDFileLoader.swift:47`'s `let config = MDRenderConfig.default` becomes `let config = renderConfig`; that `config` already flows into `parser.parse(text:config:)` at `MDFileLoader.swift:60`.
3. **`MDReaderViewModel.open`** forwards `renderConfig` into `MDFileLoader.load` (alongside the existing `chineseConversion` forward at `MDReaderViewModel.swift:132-138`).
4. **The MD container view call site — `MDReaderContainerView.swift:116-119`** (v3 correction). The live `renderConfig` caller is **`MDReaderContainerView`**, *not* `EPUBReaderContainerView`. v2 §4.3 step 4 wrongly cited `EPUBReaderContainerView.swift:134` (`await viewModel.open(url: fileURL)`) as "the surface that hosts the MD reader" — that line is the **EPUB** reader opening `EPUBReaderViewModel` and is unrelated to MD. The actual MD open call is verified at `MDReaderContainerView.swift:116-119`:
   ```swift
   await viewModel.open(
       url: fileURL,
       chineseConversion: settingsStore?.chineseConversion ?? .none
   )
   ```
   inside `MDReaderContainerView`'s `.task` (the only `.task` in that view, lines 108-144, guarded by `if viewModel.renderedText == nil`). WI-3 changes **this** call to add `renderConfig: settingsStore?.mdRenderConfig ?? .default`. `MDReaderContainerView` already holds `settingsStore` as a `var settingsStore: ReaderSettingsStore?` property (verified at `MDReaderContainerView.swift:30`), so `settingsStore?.mdRenderConfig` is in scope at the call site with no new wiring. **Full re-verified path:** `MDReaderContainerView.task` (line 116) → `MDReaderViewModel.open` (`MDReaderViewModel.swift:114`) → `MDFileLoader.load` (`MDReaderViewModel.swift:132`) → `Task.detached` → `parser.parse(text:config:)` (`MDFileLoader.swift:60`). The `EPUBReaderContainerView.swift:134` call site is **not** touched by this feature (EPUB drop-cap is CSS-only, §4.4).
5. Because `parser.parse` already receives the live config, `MDAttributedStringRenderer.render` produces an attributed string with the theme colors — and `MDDocumentInfo.headings` is populated. The **decorator runs one level up, inside `MDReaderViewModel.open` after `MDFileLoader.load` returns** (chosen call site — see below): `renderedAttributedString = MDChapterStartDecorator.decorate(loadResult.documentInfo.renderedAttributedString, headings: loadResult.documentInfo.headings, config: renderConfig)`.

**Chosen decorate call site: `MDReaderViewModel.open`.** Rationale: (a) `MDFileLoader.load` runs the parse inside a `Task.detached` and returns a `Sendable` `MDLoadResult` — running the decorator after it returns keeps `MDFileLoader` a thin I/O+parse helper and avoids threading `UIColor`-bearing decoration into the detached closure beyond the config it already needs; (b) `MDReaderViewModel.open` already assigns `renderedAttributedString` from `loadResult.documentInfo.renderedAttributedString` at `MDReaderViewModel.swift:157` — the decorator slots in as a one-line wrap at exactly that assignment; (c) `renderedText` (`MDReaderViewModel.swift:156`) is assigned from the **undecorated** `documentInfo.renderedText` and stays byte-identical, so all UTF-16 offset math (positions, highlights, search) is unaffected — the decorator only changes attributes. **Note:** `MDChapterStartDecorator.decorate` must be `@Sendable`-safe or `@MainActor` callable; since it runs on `MDReaderViewModel` (`@MainActor`) after the detached load completes, no extra isolation work is needed.

**MD theme-change behavior (v3 — resolves round-2 Finding 2).** Verified: `MDReaderContainerView` opens the file exactly once. Its single `.task` (lines 108-144) is **not** keyed (`.task` with no `id:`), is guarded by `if viewModel.renderedText == nil`, and re-evaluation of `body` does not re-run it. The view's `.onChange` handlers (verified at lines 198-237) react to `epubLayout`, `typography.fontSize`, `autoPageTurn`, `autoPageTurnInterval`, and the two `ttsService` keys — **there is no `.onChange(of: settingsStore?.theme)`** (contrast `EPUBReaderContainerView.swift:318`, which does have one — for the Photo background, not for MD text). `renderedAttributedString` is `private(set)` and assigned **only** inside `MDReaderViewModel.open`. **Conclusion: MD has no live theme re-render path.** A theme switch with the MD reader open does **not** update MD colors today, and v1 adds no such path (the two ways to add one are both unsuitable — see the §3.2 rejected-alternatives row). Therefore **v3's contract for MD is: MD drop-cap / heading / body colors apply on the next open of the file.** This is consistent with MD's existing, documented Chinese-conversion limitation (`MDReaderViewModel.swift:113-115`: live re-apply "requires a close + reopen cycle … applied at open time only"). TXT keeps live theme switching (its `.task(id: attrStringKey)` re-fires — §4.2). EPUB/Foliate keep live theme switching (their CSS blob is re-injected on theme change by the bridge). Criterion 4, criterion 7, §11, R10, and the WI-3 verification tier are all written to this contract. A future "MD live re-theme" slice would add a keyed re-render to `MDReaderContainerView` and is explicitly **out of scope** (§12).

**`vreader/Services/ReaderSettingsStore.swift`** (MODIFY — the `mdRenderConfig` computed property, verified at lines 194-205)
Set `accentColor = theme.accentColor` and `chapterHeadingColor = theme.subColor` in the existing `MDRenderConfig(...)` initializer call. **Rule-48 note:** WI-2's `txtViewConfig` change is in the same file — WI-2 and WI-3 are **sequential** (§5).

### 4.4 EPUB renderer

**`vreader/Models/ReaderThemeV2+EPUBCSS.swift`** (MODIFY, currently 235 lines — adds ~16 lines)
In `epubOverrideCSS`, append a drop-cap rule to the returned `<style>` blob. The `accent` string is **already computed** in this function (`let accent = Self.cssColor(self.accentColor)`, verified at line 73 — currently used only by `a:link`). New rule:
```css
body > p:first-of-type::first-letter {
  font-family: <ReaderTypography.cssFontStack(for: .sourceSerif4)> !important;
  font-size: 2.6em !important;
  font-weight: 600 !important;
  line-height: 0.85 !important;
  float: left !important;
  margin-right: 0.06em !important;
  margin-top: 0.05em !important;
  color: <accent> !important;
}
```
**Selector decision (v2 — resolves the round-1 MEDIUM audit finding).** v1 proposed `p:first-of-type::first-letter`, which the auditor correctly flagged as too loose: `p:first-of-type` matches the first `<p>` *within every parent element*, so a spine document with several `<div>`/`<section>` wrappers gets **multiple** drop-caps. v2 pins the concrete strategy: **`body > p:first-of-type::first-letter`** — the child combinator restricts the match to a `<p>` that is a **direct child of `<body>`**, and `:first-of-type` then picks the first such top-level `<p>`. This yields exactly one drop-cap for the common EPUB shape (chapter content as top-level `<p>` siblings under `<body>`). Two shapes are explicitly in v1 scope and tested with fixtures (§6 WI-4): (1) flat top-level `<p>` children of `<body>`; (2) `<body>` whose first text content is wrapped in a single section element. For shape (2), v1 ships `body > p:first-of-type` as-is — it simply will not match a `<p>` nested inside the section, so that shape gets *no* drop-cap rather than a *wrong* one (a safe miss, not a regression). Deeper nested-markup support (e.g. `body > section > p:first-of-type`) is a deliberate follow-up, not a v1 "verify-and-maybe-fix". No heading injection — the existing `h1..h6 { font-size: revert }` rule (lines 118-122) keeps the book's own headings; v1 does not restyle EPUB headings (deferred — R8).

No change needed in `EPUBWebViewBridge.swift` or `EPUBReaderContainerView.swift` — they already inject and live-refresh whatever `epubOverrideCSS` returns; the extra rule rides the existing pipe. **v3 note:** `EPUBReaderContainerView.swift` is *not* touched by WI-3 either — round-2 Finding 1 corrected the misattribution that previously put an MD call site in this file.

### 4.5 AZW3 / MOBI (Foliate) renderer

**`vreader/Services/Foliate/FoliateStyleMapper.swift`** (MODIFY, currently 90 lines — adds ~14 lines)
*(v2 path correction — the file is at `vreader/Services/Foliate/`, NOT `vreader/Views/Reader/`. v1 §3.1's prior-art table referenced the wrong directory; corrected here and in §3.1.)*
`themeCSS` currently takes `fontSize, lineHeight, fontFamily, textColor, backgroundColor` (verified at lines 30-36) and has **no** accent parameter. Add one:
```swift
static func themeCSS(
    fontSize: Int, lineHeight: Double, fontFamily: String?,
    textColor: String?, backgroundColor: String?,
    accentColor: String?            // NEW — drop-cap color; rule omitted when nil
) -> String
```
When `accentColor` is non-nil and `FoliateJSEscaper.sanitizeCSSColor` accepts it, append a `body > p:first-of-type::first-letter { ... }` rule (same selector and declarations as §4.4) to `rules`, with `!important` on every declaration (matching the file's stated convention "All CSS rules use !important"). The accent goes through `FoliateJSEscaper.sanitizeCSSColor` exactly like `textColor` (verified pattern at lines 51-53). When `accentColor` is nil → no drop-cap rule (opt-out / back-compat).

**`vreader/Views/Reader/FoliateReaderContainerView.swift`** (MODIFY — the `themeCSS:` call, verified at lines 180-187)
Add `accentColor: Self.cssColor(store.theme.accentColor)` to the `FoliateStyleMapper.themeCSS(...)` call inside the `settingsStore.map { store in ... }` closure. `Self.cssColor` already exists in this file (verified at line 236, used for `inkColor`/`backgroundColor`).

No change in `FoliateViewBridge.swift` — it pushes whatever `themeCSS` returns via `readerAPI.setStyles`.

### 4.6 Files explicitly OUT of scope

- **`vreader/Views/Reader/TXTChapterOverlayViews.swift`** — the legacy `ChapterTitleOverlay` (top-of-screen caption, design `:154-164`). A *different* surface. Untouched. **v2 note:** for TXT synthetic / `"前言"` chapters this overlay is the *only* place the chapter name appears — by design (§3.2). The plan deliberately does not merge, replace, or restyle it.
- **`vreader/Views/Reader/EPUBReaderContainerView.swift`** — the EPUB reader container. **v3 note:** v2 wrongly cited `EPUBReaderContainerView.swift:134` as the MD open call site (round-2 Finding 1); it is the EPUB reader's own `await viewModel.open(url: fileURL)`. EPUB's drop-cap ships purely through the `epubOverrideCSS` blob (§4.4) — the container is not modified by any WI.
- **PDF renderer** (`PDFReaderHost`, PDFKit) — "PDF n/a". No reflowable text to decorate. No file touched.
- **`vreader/Views/Reader/TXTChunkedReaderBridge.swift`** and the large-file chunked path in `TXTReaderContainerView` — the chunked renderer is the fallback used *only when there is no chapter index*. With no chapter boundaries there is no "chapter start". Chunked path keeps calling plain `build`. Untouched.
- **`NativeTextPagedView` / `NativeTextPaginator` / `NativeTextPageNavigator`** (MD/TXT paged mode) — paged mode re-paginates an already-built `NSAttributedString`. `NativeTextPaginator` exposes `paginateAttributed(attributedText:viewportSize:)` (verified at line 80) and `NativeTextPagedView.applyContent` passes the full attributed text through `navigator.currentPageAttributedText(...)` (verified). Because the drop-cap + heading are *attributes inside that string*, paged mode renders them with **no code change**. **However** — `NativeTextPagedView`'s `UITextView` is non-scrollable (`isScrollEnabled = false`) with a fixed `textContainerInset` top of 16 (verified at `NativeTextPagedView.swift:89`), so an oversized negative-baseline glyph **can clip deterministically** at the top of the page. v2 therefore makes paged-mode an **up-front WI-2/WI-3 verification gate**, not a late check — see §5 and R3. No file touched *unless* the gate finds clipping, in which case the fallback (§R3) may adjust metrics or disable the drop-cap in paged mode.
- **`EPUBWebViewBridge.swift`, `FoliateViewBridge.swift`** — they transport CSS but do not build it; the CSS-builder changes (§4.4, §4.5) ride the existing injection pipes. No bridge code changes.
- **Search, highlights, bookmarks, TTS, position persistence** — #68 changes only *attributes* (TXT/MD) and *CSS* (EPUB/AZW3); the rendered *string* and its UTF-16 length are byte-identical in **every** path (no injection anywhere — v2), so every offset-based subsystem is unaffected. No file touched. (See §9.)
- **`Locator`, `DocumentFingerprint`, SwiftData models, `VReaderMigrationPlan`** — no persistence change; no schema field is added (TXT regex-vs-synthetic is derived at render time). No file touched.

---

## 5. Work-item sequencing

Six WIs. Each is one PR. Audit count (rule 47): **Large** feature by file-spread but small per-WI — 1 plan audit (this doc, Gate 2), 1 PR audit per WI; the two mechanical CSS WIs (WI-4, WI-5) share the "inject-a-CSS-rule" surface and **may batch under one audit**.

| WI | Title | Tier | Files | Est. PR size | Depends on |
|----|-------|------|-------|--------------|------------|
| **WI-1** | `ChapterStartTypography` shared constants | **Foundational** | NEW `ChapterStartTypography.swift` | ~65 LOC + ~80 LOC tests. **XS.** | — |
| **WI-2** | TXT chapter-start drop-cap + regex-heading restyle | **Behavioral** | MODIFY `TXTAttributedStringBuilder.swift`, `TXTViewConfig.swift`, `ReaderSettingsStore.swift` (`txtViewConfig`), `TXTReaderContainerView.swift`, `TXTReaderViewModel.swift` | ~130 LOC + ~160 LOC tests. **M.** | WI-1 |
| **WI-3** | MD chapter-start drop-cap + leading-heading restyle + `MDRenderConfig` plumbing | **Behavioral** | NEW `MDChapterStartDecorator.swift`; MODIFY `MDTypes.swift`, `MDReaderViewModel.swift`, `MDFileLoader.swift`, **`MDReaderContainerView.swift`** (the `viewModel.open` call at lines 116-119), `ReaderSettingsStore.swift` (`mdRenderConfig`) | ~140 LOC + ~160 LOC tests. **M.** | WI-1, **WI-2** (shared file) |
| **WI-4** | EPUB drop-cap CSS rule | **Behavioral** | MODIFY `ReaderThemeV2+EPUBCSS.swift` | ~20 LOC + ~55 LOC tests. **S.** | WI-1 |
| **WI-5** | AZW3/MOBI (Foliate) drop-cap CSS rule | **Behavioral** | MODIFY `FoliateStyleMapper.swift`, `FoliateReaderContainerView.swift` | ~25 LOC + ~60 LOC tests. **S.** | WI-1 |
| **WI-6** | Final integration verification + acceptance evidence | **Behavioral (final WI)** | No new product code — verification + `dev-docs/verification/feature-68-<YYYYMMDD>.md` + tracker flip | docs only | WI-2…WI-5 |

**v3 correction to the WI-3 file list:** v2's WI-3 row listed "the MD container call site" without naming the file, and §4.3 step 4 wrongly pointed at `EPUBReaderContainerView.swift`. The WI-3 container file is **`vreader/Views/Reader/MDReaderContainerView.swift`** — specifically the `viewModel.open(...)` call at lines 116-119. `EPUBReaderContainerView.swift` is **not** a WI-3 file.

**Sequencing rationale (v2 — corrected per the round-1 rule-48 MEDIUM finding):**
- WI-1 is foundational and first — no UI, unit tests only, no device verification (rule 47 Gate 5). WI-2…WI-5 all `import` its constants.
- **WI-2 and WI-3 are NOT a disjoint write set** — both modify `vreader/Services/ReaderSettingsStore.swift` (WI-2 the `txtViewConfig` computed property, WI-3 the `mdRenderConfig` computed property). v1 wrongly listed them as parallelizable. Under rule 48 (one writer per file) they are **sequential: WI-2 must merge before WI-3 starts**, and WI-3 rebases onto WI-2's `ReaderSettingsStore.swift` change. (Alternative considered: extract the shared `ReaderSettingsStore` config plumbing into a separate foundational slice — rejected as overkill: the two edits are ~2 lines each in two *different* computed properties; a straight serialization is simpler and the change windows are tiny.)
- **WI-4 and WI-5 are genuinely disjoint** from WI-2/WI-3 and from each other (EPUB-CSS file vs Foliate-mapper file vs Foliate-container file — no shared file). After WI-1 they may proceed in parallel with the WI-2→WI-3 chain.
- WI-2 and WI-3 are the genuinely hard ones (attributed-string drop-cap approximation). WI-4/WI-5 are mechanical CSS-string additions.
- WI-6 is the final WI: full acceptance pass across all four formats on the simulator, writes the evidence file that flips the row to `VERIFIED`. Its own WI because no single renderer WI exercises *all* acceptance criteria.

**Per-WI device-verification tier (rule 47 Gate 5):**
- **WI-1:** foundational — unit tests + audit only, no device verification.
- **WI-2 / WI-3:** behavioral — each requires a **slice verification** on the iPhone 17 Pro Simulator with a fixture of the relevant format (WI-2: a TXT with a regex-detectable TOC, a TXT with synthetic chapters, a TXT whose content precedes the first match so a `"前言"` chapter is produced; WI-3: an MD with a leading `#` heading, an MD with no leading heading, an MD whose first heading is *not* at offset 0). **v2 — mandatory paged-mode gate:** the slice verification for WI-2 and WI-3 **must** include paged mode (TXT paged and MD paged), specifically checking that the 2.6× drop-cap on the *first line of the page* is **not clipped** at the top of the non-scrollable `NativeTextPagedView` text container (top inset 16). This is verified *before* the WI is considered done, not deferred to WI-6. If clipping is observed, apply the R3 fallback in the same WI. **v3 — MD theme-change verification (WI-3):** because MD has no live theme re-render path (round-2 Finding 2), WI-3's slice verification for the theme-color path is performed by **switching the theme and then reopening the MD file**, and confirming the reopened render shows the new accent/heading colors. WI-3 must **not** claim live MD theme switching. (TXT's WI-2 slice verification *does* switch the theme live, with the reader open, because TXT's `.task(id: attrStringKey)` supports it.)
- **WI-4 / WI-5:** behavioral — slice verification with a fixture EPUB (WI-4) and the bundled `mini-azw3.azw3` (WI-5). Recorded in the PR description.
- **WI-6:** final WI — full end-to-end acceptance pass, evidence file required.

This feature is 6 WIs — within the rule-47 "consider splitting at 10+" guidance, no split needed.

---

## 6. Test catalogue

All tests follow rule 50 §8 (mirrored path, one test class per source file, `vreaderTests/<MirroringSourcePath>/<Name>Tests.swift`).

### WI-1 — `vreaderTests/Services/ChapterStartTypographyTests.swift` (NEW)
- Each constant equals the design-pinned value (`dropCapScale == 2.6`, `headingFontSize == 13`, `headingLetterSpacing == 2`, `headingSpacingAfter == 18`, `headingSpacingBefore == 8`, `dropCapLineHeight == 0.85`, `headingFontWeight == .medium`, `dropCapFontWeight == .semibold`).
- `dropCapCSSFontSizeEm == "2.6em"`.
- `isDropCapEligible`: true for `"A"`, `"a"`, `"7"`; false for `" "`, `"\n"`, `"\u{201C}"` (left double quote), `"\u{2018}"` (left single quote), `"\u{300}"` (combining grave), `"。"` (CJK full stop), `"中"` (CJK ideograph — pinned **false**, see R4).

### WI-2 — `vreaderTests/Services/TXT/TXTAttributedStringBuilderChapterStartTests.swift` (NEW)
- `buildChapterStart` with `headingLineLength > 0` (regex chapter): the leading run over `0..<headingLineLength` has the serif font at `headingFontSize`, `headingFontWeight`, `.kern == headingLetterSpacing`, a centered paragraph style with `paragraphSpacing == headingSpacingAfter` and `paragraphSpacingBefore == headingSpacingBefore`, `foregroundColor == config.chapterHeadingColor`.
- **`buildChapterStart` does NOT change the backing string** — `result.string == NSAttributedString(string: text, …).string` and `result.length == (text as NSString).length` for both `headingLineLength == 0` and `> 0`. (Pins the v2 offset invariant; pins that no uppercase transform occurred — the heading characters are byte-identical to `text`'s.)
- Drop-cap run: first eligible char of the first *body* paragraph (at offset `headingLineLength`) has serif font at `config.fontSize * 2.6`, `foregroundColor == config.accentColor`, weight `dropCapFontWeight`, a negative `baselineOffset`; the first body paragraph's `firstLineHeadIndent > 0`.
- `headingLineLength == 0` (synthetic / `"前言"` chapter): **no heading run is applied** (no run carries `headingFontSize`); the drop-cap is applied to the first eligible char of the paragraph at offset 0.
- First body paragraph starts with an *ineligible* char (`"\u{201C}Hello"`): drop-cap applied per the pinned R5 decision; no crash; no double-styling.
- Empty `text`, single-character `text`, `text` that is *only* a heading line with no body: no crash, no out-of-range, returns a sane string.
- `headingLineLength` larger than `text` length: clamped, no crash, no string mutation.
- The drop-cap is applied only to the **first** body paragraph, not subsequent paragraphs.
- `TXTViewConfig.renderingEquals` returns false when `accentColor` or `chapterHeadingColor` differs.

### WI-2 — `vreaderTests/ViewModels/TXTReaderViewModelChapterHeadingTests.swift` (NEW)
- `currentChapterHeadingLineLength`: returns the first-line UTF-16 length when `currentChapterText`'s first line trimmed equals `currentChapterTitle` trimmed (regex chapter); returns `0` when it does not.
- Returns `0` for a synthetic chapter (title `"Chapter 3"`, body first line is prose).
- Returns `0` for a `"前言"` chapter (title `"前言"`, body first line is the book's opening prose, not `"前言"`).
- CJK heading line: first-line/title match works for a `"第一章 …"`-style title that *is* the body's first line.

### WI-2 — `vreaderTests/Views/Reader/TXTReaderContainerViewChapterStartTests.swift` (NEW or extend the existing `TXTReaderContainerViewChineseConversionTests`)
- `makeAttrStringKey` changes when `config.accentColor` / `config.chapterHeadingColor` change (theme-switch live-rebuild trigger).
- `makeAttrStringKey` changes when the `headingLineLength` component changes.
- The legacy full-text key path (`hasText`/`textLen`/`config` only) is unchanged when the two new colors are at their defaults — no regression to non-chapter rendering.

### WI-3 — `vreaderTests/Services/MD/MDChapterStartDecoratorTests.swift` (NEW)
- `decorate` on a document with a leading `# Heading` at offset 0 then body: heading run restyled (serif, `headingFontSize`, `.kern`, centered, `config.chapterHeadingColor`, **characters unchanged — no uppercase**); first body-paragraph char gets the drop-cap run; **`decorated.string == input.string`** and equal length.
- `decorate` on a document with **no heading at offset 0** (body text first): no heading restyle; drop-cap applied to the first body paragraph.
- `decorate` on a document whose first heading is **not** at offset 0 (preceded by body text): **no heading restyle** (v2 leading-heading-only scope); the drop-cap goes on the genuine first body paragraph.
- `decorate` on an **empty** document and a **headings-only** document: no crash, no-op, string unchanged.
- Drop-cap not applied to a heading itself (the first body *paragraph*, not the heading line).
- First body block after the leading heading is a **list / code block / blockquote**: **no drop-cap** (skip — drop-cap only on a plain paragraph).
- `MDRenderConfig.==` distinguishes `accentColor` / `chapterHeadingColor`.
- Idempotency: `decorate(decorate(x))` equals `decorate(x)` in both string and attributes (decorator is single-application-safe).

### WI-3 — `vreaderTests/Services/MD/MDFileLoaderRenderConfigTests.swift` (NEW or extend the existing `MDFileLoader` tests)
- `MDFileLoader.load` with an explicit non-default `renderConfig` (custom `fontSize` / `accentColor`): the `MDDocumentInfo.renderedAttributedString` reflects that config (e.g. a non-default body font size). Pins the round-1 HIGH-finding fix — proves `MDRenderConfig` actually reaches `parser.parse` and is no longer hardcoded to `.default` at `MDFileLoader.swift:47`.
- `MDFileLoader.load` with no `renderConfig` argument: uses `.default` (back-compat — existing call sites compile and behave unchanged).

### WI-3 — `vreaderTests/ViewModels/MDReaderViewModelChapterStartTests.swift` (NEW or extend the existing `MDReaderViewModel` tests)
- After `open(url:renderConfig:)` with a leading-heading fixture: `renderedAttributedString` carries the decoration (heading run + drop-cap attributes present).
- `renderedText` (the plain string) is **byte-identical** to the undecorated `MDAttributedStringRenderer.render` output's `renderedText`, and `renderedTextLengthUTF16` is unchanged — proves search/highlight/position offset safety.
- `open` with the default `renderConfig` still loads and renders (back-compat).
- **MD theme-change-on-reopen (v3 — round-2 Finding 2):** calling `open(url:renderConfig:)` a second time with a *different* `renderConfig` (different `accentColor` / `chapterHeadingColor`, simulating a theme switch followed by a reopen) produces a `renderedAttributedString` whose decoration carries the new colors. This pins the **next-open** contract — there is no test asserting a live color change while the reader stays open, because MD has no such path.

### WI-4 — `vreaderTests/Models/ReaderThemeV2EPUBCSSChapterStartTests.swift` (NEW)
- `epubOverrideCSS` output contains `body > p:first-of-type::first-letter` (the exact pinned selector — asserts the child combinator, not bare `p:first-of-type`).
- The `::first-letter` rule contains `font-size: 2.6em`, `float: left`, `font-weight: 600`, `line-height: 0.85`, and the theme's accent color string (`rgb(140,47,47)` Paper, `rgb(214,136,90)` Dark, etc.).
- The drop-cap `color` differs per theme — at least Paper and Dark asserted.
- The existing `h1..h6 { font-size: revert }` rule is **still present** (no heading regression — proves EPUB book headings are not overridden).
- Existing `ReaderThemeV2+EPUBCSS` substring assertions (other test files) still pass.

### WI-5 — `vreaderTests/Services/Foliate/FoliateStyleMapperChapterStartTests.swift` (NEW or extend the existing `FoliateStyleMapperTests`)
- `themeCSS` with a non-nil `accentColor` emits `body > p:first-of-type::first-letter` with `2.6em` / `float:left` / `!important` on every declaration / the sanitized accent color.
- `themeCSS` with `accentColor: nil` emits **no** drop-cap rule (back-compat / opt-out).
- A malicious accent string (`"red; } body { display:none } /*"`) is neutralized by `FoliateJSEscaper.sanitizeCSSColor` — the injected rule cannot break out of its declaration (bridge-safety test, rule 47 Gate 4 concern).
- Existing `FoliateStyleMapper` font-size/line-height/color tests still pass with the new parameter present (added with a default or all call sites updated).

### Integration tests
- `vreaderTests/Integration/` — extend the existing TXT chapter integration test so opening a regex-TOC fixture in chapter mode and reading `chapterAttrString` shows the drop-cap + heading attributes on chapter 1 and on a mid-book chapter after `navigateToChapter`; and a synthetic-chapter fixture shows the drop-cap but **no** heading run.
- An MD render integration test confirming `MDReaderViewModel.renderedAttributedString` carries the decoration while `renderedText` is byte-identical to the undecorated render (search/highlight offset safety). The test drives the real `MDReaderContainerView → MDReaderViewModel.open → MDFileLoader.load → parser.parse` path with a theme-aware `renderConfig`.

### Audit-driven additions
- Partial/corrupt input: a chapter whose first paragraph is empty / all whitespace; a heading line that is all-whitespace; an MD heading with inline markup (`# **Bold** title`) — the restyle applies over the rendered run without crashing and without changing the string.
- TXT regex chapter whose first line trimmed *almost* equals the title but differs by trailing punctuation — `currentChapterHeadingLineLength` returns `0` (no false-positive heading restyle), drop-cap still applied.

---

## 7. Risks + mitigations

| # | Risk | Severity | Mitigation |
|---|------|----------|------------|
| R1 | **TXT/MD drop-cap is an approximation, not a true float.** TextKit 1 has no float primitive; the baseline-offset + `firstLineHeadIndent` approach makes the capital large and indents line 1, but body lines 2-3 do not wrap to the right of the capital as the design's CSS `float:left` does. | Medium | The §3.2 trade-off. The approximation is the standard attributed-string drop-cap and is visually close. **§8 documents this as a per-format rendering choice the design (a web float) does not explicitly cover.** Per the Gate-2 auditor's explicit ruling, this is an acceptable engine-constraint implementation of an already-designed element — **no `needs-design` issue is required**. WI-2/WI-3 ship the approximation; WI-6 surfaces it at acceptance. |
| R2 | **Heading duplication in EPUB/AZW3.** | High (if mishandled) | Designed out in §2: EPUB/AZW3 get **only the drop-cap**, never an injected heading. The existing `h1..h6 { font-size: revert }` rule is preserved (WI-4 test asserts it). EPUB/AZW3 heading restyle is explicitly **deferred** — see R8. |
| R3 | **Oversized capital clipped in paged mode.** `NativeTextPagedView`'s `UITextView` is non-scrollable (`isScrollEnabled = false`) with a fixed `textContainerInset` top of 16 (verified). A 2.6× capital with a negative `baselineOffset` on the *first line of a page* can be clipped deterministically at the container top. | Medium | **v2: up-front gate, not a late check.** WI-2 and WI-3 each include a **mandatory paged-mode slice verification** (TXT paged + MD paged) checking the first-line drop-cap is not clipped — done *before* the WI is accepted (§5). **Fallback decision, decided now:** if clipping is observed, the implementer (a) reduces the negative `baselineOffset` magnitude and/or adds `paragraphSpacingBefore`/`firstLineHeadIndent`-side top breathing room so the glyph's ascent stays within the line box, OR if that cannot fully clear it, (b) **disables the drop-cap in paged mode** (apply it only in scrolled mode) — a documented, test-pinned degradation rather than a clipped glyph. The choice is recorded in the WI PR. Scrolled mode is unaffected (the scroll view accommodates the ascent). |
| R4 | **CJK first character.** A CJK chapter whose first body character is an ideograph — a 2.6× CJK glyph as a "drop-cap" looks wrong and the serif Latin face has no CJK coverage. | Medium | `ChapterStartTypography.isDropCapEligible` returns **false** for CJK ideographs and CJK punctuation (pinned in WI-1 tests). When the first char is ineligible, **skip the drop-cap** for that chapter (the regex-heading restyle still applies). The design's drop-cap is a Latin-typography device; skipping for CJK is correct. |
| R5 | **Leading quotation mark.** Many chapters open with `"` or `'`. | Low-Medium | WI-1 `isDropCapEligible` excludes opening quotes. WI-2/WI-3 decision (pinned in tests): when the paragraph starts with an opening quote, **drop-cap the first *letter* after the quote** and keep the quote at body size (fidelity-preferred); if no letter follows within a small window, skip. The test pins the chosen behavior. The string is never modified — only the letter's run gets the drop-cap attributes. |
| R6 | **EPUB selector mis-targets nested markup.** | Medium | **v2: resolved up-front, not deferred.** The selector is pinned to **`body > p:first-of-type`** (child combinator → first top-level `<p>` directly under `<body>`), which yields exactly one drop-cap for the flat-`<p>` EPUB shape and *safely misses* (no drop-cap, not a wrong one) for section-wrapped first content. WI-4's tests cover both shapes with fixtures (§6). Deeper nested-markup support is an explicit follow-up slice, not a v1 verify-and-maybe-fix. |
| R7 | **Synthetic-chapter heading injection would change the rendered string length.** | — (eliminated) | **v2: this risk no longer exists.** v1 considered prepending a heading for synthetic/`"前言"` chapters; v2 **does not inject anything in any TXT path**. `buildChapterStart` only ever adds attributes; `NSAttributedString.string` is byte-identical to `currentChapterText` for synthetic, `"前言"`, and regex chapters alike. Synthetic/`"前言"` chapters get the drop-cap only; their name is shown by the top-of-screen `ChapterTitleOverlay`. No offset can shift. (See §3.2 and the §13 HIGH resolution.) |
| R8 | **Scope creep into EPUB/AZW3 in-text heading styling.** | Low | Explicitly deferred (§2, §4.4). v1 = drop-cap only for EPUB/AZW3; the book's own headings are left as the existing CSS leaves them. The design's tracked/centered heading on EPUB headings is a separate feature with its own design review (publisher heading markup varies too much to safely override). |
| R9 | **MD post-thematic-break heading styling promised but not deliverable.** v1 §2 promised it; `MDHeading` does not encode break adjacency. | Medium | **v2: scope narrowed.** v1 styles **only the leading document heading** (first `MDHeading` with `charOffsetUTF16 == 0`). Post-break detection is explicitly **deferred** and would first require extending `MDHeading` or emitting a thematic-break marker in `MDAttributedStringRenderer`. Every section now says "leading heading only" (see the §13 MEDIUM resolution). |
| R10 | **Theme switch does not refresh the chapter-start colors.** | Low (TXT/EPUB/Foliate) / accepted limitation (MD) | **TXT:** WI-2 hashes `accentColor` + `chapterHeadingColor` into `makeAttrStringKey` and compares them in `renderingEquals` → the `.task(id: attrStringKey)` re-fires and rebuilds the chapter over the held `currentChapterText` on a **live** theme switch. **EPUB/Foliate:** the colors are part of the CSS blob, which the bridge already re-injects on a **live** theme change. **MD (v3 — round-2 Finding 2):** MD has **no** live theme re-render path — `MDReaderContainerView` opens the file once in a non-keyed `.task` and has no `.onChange(of: theme)`; `renderedAttributedString` is assigned only inside `open` (verified `MDReaderContainerView.swift:108-119`, `MDReaderViewModel.swift:156-157`). MD colors therefore update **on the next open of the file**, not live — consistent with MD's existing Chinese-conversion limitation (`MDReaderViewModel.swift:113-115`). This is the v3 contract, not a defect: criterion 4 and criterion 7 are written to it, WI-3's verification switches the theme then reopens, and a live MD re-theme is out of scope (§12). Adding a live MD path was evaluated and rejected (§3.2 rejected-alternatives row). |
| R11 | **MD config plumbing miss.** Adding fields to `mdRenderConfig` without a plumbing seam would silently not reach rendering — `MDFileLoader.load` hardcodes `MDRenderConfig.default` and `MDReaderViewModel.open` has no config parameter (verified). | High (if mishandled) | **v2: resolved.** WI-3 adds a `renderConfig` parameter to `MDReaderViewModel.open` and to `MDFileLoader.load` (replacing the hardcoded `.default` at `MDFileLoader.swift:47`), forwards it to `parser.parse`, and runs `MDChapterStartDecorator.decorate` in `MDReaderViewModel.open` with the same caller-supplied config. **v3:** the live `renderConfig` caller is `MDReaderContainerView.swift:116-119` (corrected from v2's mis-cited `EPUBReaderContainerView.swift:134` — round-2 Finding 1). WI-3's `MDFileLoaderRenderConfigTests` pins that a non-default config actually reaches the rendered output (§6). (See the §13 HIGH resolution and the §14 round-2 table.) |
| R12 | **`Source Serif 4` binary not bundled.** `ReaderTypography` documents the `.otf` may not be bundled yet; the fallback chain returns Georgia. | Low | Expected and handled — the drop-cap/heading render in Georgia (still a serif). The font feature path was *not* taken (§3.2), so no small-caps coverage gap. WI-6 verification notes which face actually rendered. |

---

## 8. Rule 51 (design-fidelity) compliance

The drop-cap (`vreader-reader.jsx:383-390`) and the in-text chapter heading (`vreader-reader.jsx:333-343`) are **both present in the committed design bundle** `dev-docs/designs/vreader-fidelity-v1/`. The surface is therefore **designed** — this feature implements an existing design, it does not invent UI. Sizes, weights, colors (oxblood accent, sub token), spacing, and the 2.6× multiplier are all read directly from the JSX and pinned in `ChapterStartTypography` (WI-1).

**One per-format rendering decision the design does NOT explicitly cover** (flagged per the rule-51 anti-pattern "Gate-3 must reference the designed surface"):

- The design's drop-cap is a **CSS `float: left`** (web). For EPUB/AZW3 this maps to CSS `body > p:first-of-type::first-letter { float: left }` — fully designed, no decision. For **TXT/MD** there is no float primitive in TextKit 1; the renderer approximates with an oversized first-character run + `firstLineHeadIndent` (§3.2 R1). The approximation is a faithful *kind* match but not a pixel match — body lines 2-3 do not wrap around the capital.

**Gate-2 auditor's explicit ruling (Codex `019e3bee`), carried into v2/v3:** the non-floating TXT/MD drop-cap approximation **is acceptable** as an engine-constraint implementation of an already-designed element. It is the industry-standard attributed-string drop-cap and *is* the design's element rendered the closest way the TXT/MD engine allows — a rendering-engine constraint, not invented UI. **No `needs-design` issue is required** for this feature. v2/v3 therefore do **not** carry the v1 conditional "if the user judges the non-wrapping unacceptable, file a `needs-design` issue" — that conditional is removed. WI-2/WI-3 ship the approximation; WI-6 surfaces it to the user at acceptance as a normal review item.

**Two design-text properties deliberately NOT pixel-matched on the native (TXT/MD) heading path, with rationale:**
- `textTransform: 'uppercase'` — **not applied** to native TXT/MD heading strings. `NSAttributedString` has no `text-transform`; a true `String.uppercased()` changes characters and can change UTF-16 length, breaking the offset invariant for any heading line that is part of the chapter body. A small-caps/uppercase **font feature** preserves characters but was rejected for v1 (Source Serif 4 not bundled; Georgia-fallback feature coverage inconsistent; extra code path for marginal gain). v1 native headings keep **source casing**. (On EPUB/AZW3, `text-transform: uppercase` is a real CSS property and *could* be honoured — but EPUB/AZW3 headings are out of v1 scope entirely, so no uppercase ships in v1.)
- The design's drop-cap `float` (covered above).

**One design behavior deliberately NOT matched on the MD path, with rationale (v3):** the design implies the chapter-start typography tracks the active theme. On TXT and EPUB/AZW3 it does so **live** (the reader updates as the theme changes). On **MD** it tracks the theme **on the next open of the file**, not live — MD's container has no theme-keyed re-render path and adding one is out of v1 scope (§3.2, R10, §12). This is a fidelity gap *only* in the live-update timing; the rendered colors themselves are a faithful, measured implementation of the theme tokens once the file is (re)opened.

Everything else in this feature — sizes, weights, the accent/sub colors, tracking, centering, spacing — is a direct, measured implementation of the committed design.

---

## 9. Backward compatibility

- **No SwiftData schema change.** TXT regex-vs-synthetic is derived at render time by comparing `currentChapterText`'s first line to `currentChapterTitle` (§4.2); no field is added to `TXTChapter` or `TXTChapterIndex`. No `VReaderMigrationPlan` change. Persisted chapter indexes from older app versions decode unchanged.
- **No persisted-position / highlight / bookmark migration.** TXT/MD changes touch only `NSAttributedString` **attributes**; the rendered *string* and its UTF-16 length are **byte-identical to today in every path** — there is no injection anywhere in v2/v3 (the v1 synthetic-heading-injection path is removed). Every `Locator` (`charOffsetUTF16`), every highlight range, every search offset, every TTS sentence range stays valid. EPUB/AZW3 changes are CSS-only — the DOM and CFI space are untouched.
- **Older backups.** Backups carry positions/highlights as offsets and per-book theme/typography settings; none of those representations change. A backup taken before #68 restores identically after #68.
- **Per-book reader settings.** `ReaderThemeV2` and `TypographySettings` gain no new persisted fields. `TXTViewConfig`'s and `MDRenderConfig`'s new color fields are *runtime-computed* from the theme, never persisted.
- **MD `open` / `MDFileLoader.load` signature change.** Both gain a `renderConfig` parameter with a `.default` default value — every existing call site (tests, previews) compiles and behaves exactly as before; only the live MD container call site (`MDReaderContainerView.swift:116-119`) passes the theme-aware `store.mdRenderConfig`. Not an ABI surface (in-module Swift); a pure source-compatible additive change.
- **Opt-out / safe defaults.** `TXTViewConfig.accentColor`/`chapterHeadingColor` and `MDRenderConfig.accentColor`/`chapterHeadingColor` default to neutral values; `FoliateStyleMapper.themeCSS`'s new `accentColor` parameter omits the rule when nil. Any call site not wired through renders exactly as before. The new `buildChapterStart` is a separate method; the existing `build` (legacy full-text + chunked paths) is byte-for-byte unchanged.
- **Feature interaction.** A highlight painted over a drop-capped first letter: the highlight background attribute and the drop-cap font/color attributes coexist on the same run; the highlight still draws. WI-2/WI-3 tests include a highlight-over-drop-cap case. Chinese conversion (`SimpTradTransform`) runs *before* the builder/decorator (verified — applied at the source-text seam in both `MDFileLoader.load` and the TXT `.task` branch), so the drop-cap eligibility check sees the converted text — correct.

---

## 10. Acceptance criteria (for the features.md row + WI-6 evidence)

1. **TXT regex chapters** — opening a regex-TOC fixture in chapter mode shows, on each chapter's first page: a centered serif chapter heading (`subColor`, **source casing**, tracked) and an oxblood (`accentColor`) ~2.6× serif drop-cap on the first body paragraph. Mid-book chapters (after `navigateToChapter`) show the same.
2. **TXT synthetic / `"前言"` chapters** — a no-TOC fixture and a fixture whose content precedes the first match show the drop-cap on chapter starts; these chapters render with **no in-flow heading and no garbled/duplicated text** — the rendered chapter string is byte-identical to the undecorated text. Their chapter name remains visible via the top-of-screen `ChapterTitleOverlay`.
3. **MD** — a Markdown file with a leading `#` heading (at document offset 0) renders that heading in the chapter-heading style (serif, tracked, centered, `subColor`, source casing) and a drop-cap on the first body paragraph; a Markdown file with no leading heading still gets the drop-cap; an MD file whose first heading is *not* at offset 0 gets the drop-cap on the genuine first paragraph and **no** heading restyle.
4. **MD config plumbing** — opening (or reopening) an MD file after a theme change shows the MD drop-cap/heading colors for the active theme, proving `MDRenderConfig` reaches rendering through the new `MDReaderContainerView` (`.task` at 108-119) → `MDReaderViewModel.open` → `MDFileLoader.load` → `parser.parse` seam (verified at `MDReaderContainerView.swift:116-119`); `renderedText` is byte-identical to the undecorated render. **MD colors apply on the next open of the file, not live** — MD has no theme-keyed re-render path (round-2 Finding 2); switching the theme with the MD reader already open is *not* expected to recolor the open document.
5. **EPUB** — a fixture EPUB renders an oxblood `body > p:first-of-type::first-letter` drop-cap on the first top-level paragraph; exactly one drop-cap per spine document for the flat-`<p>` shape; the book's own `<h1>` headings are unchanged (no duplicate VReader heading).
6. **AZW3/MOBI** — the bundled `mini-azw3.azw3` renders the drop-cap via Foliate `setStyles`.
7. **All 5 themes** — the drop-cap color tracks the theme accent (Paper oxblood `#8c2f2f`, Dark/OLED warm `#d6885a`, Photo gold `#e8b465`, Sepia `#7a3a1f`) and the heading color tracks `subColor`. **For TXT, EPUB, and AZW3/MOBI, switching the theme with the reader open updates both colors live.** **For MD, the new theme's colors appear on the next open of the file** — MD has no live theme re-render path (round-2 Finding 2), so this criterion is verified for MD by switching the theme and reopening the document, and is verified live for the other three formats.
8. **CJK** — a CJK-titled chapter does not render a broken oversized-ideograph drop-cap (drop-cap skipped per R4); the regex-heading restyle still applies to the CJK heading line.
9. **Paged mode** — in TXT paged mode and MD paged mode, the drop-cap on the first line of a page is **not clipped** at the top of the page container (verified up-front in WI-2/WI-3 per the R3 gate; if the R3 fallback disabled the drop-cap in paged mode, that documented degradation is what WI-6 confirms instead).
10. **No regressions** — highlight persistence, search, position restore, TTS, and scrolled/paged mode are unaffected (the rendered string and all UTF-16 offsets are byte-identical); verified against the feature #3/#4/#11/#29/#44 regression sets at WI-6.

---

## 11. Verification plan (WI-6)

WI-6 runs the full acceptance pass on the iPhone 17 Pro Simulator and writes `dev-docs/verification/feature-68-<YYYYMMDD>.md` with, per acceptance criterion: the fixture used, the steps, the observed result, and a screenshot. Fixtures: a TXT with a regex-detectable TOC; a TXT with synthetic (no-TOC) chapters; a TXT whose content precedes the first heading match (produces a `"前言"` chapter); an MD with a leading `#` heading; an MD with no leading heading; an MD whose first heading is not at offset 0; a fixture EPUB (flat top-level `<p>`); the bundled `mini-azw3.azw3`. Paged mode is exercised for TXT and MD.

**Theme verification (v3 — split by what each format supports):**
- **TXT, EPUB, AZW3/MOBI:** each of the five themes is switched **live, with the reader open**, and the drop-cap (and TXT heading) colors are confirmed to update without reopening.
- **MD:** because MD has no live theme re-render path (round-2 Finding 2), the MD theme check is performed by switching the theme and then **reopening** the MD file; the reopened render is confirmed to show the active theme's accent/heading colors. WI-6 records explicitly that MD theme color updates on reopen, not live — this is the criterion-4 / criterion-7 contract, not a defect, and the evidence file must state it plainly so the row's `VERIFIED` status is honest about MD's behavior.

The regression sets named in criterion 10 are re-run. The evidence file is the artefact that flips the `features.md` row to `VERIFIED`.

---

## 12. Out of scope (explicit)

- EPUB/AZW3 in-text **heading** restyling (deferred — R8; publisher markup varies too much to safely override without its own design review).
- MD **post-thematic-break** heading styling (deferred — R9; `MDHeading` would first need to encode break adjacency).
- **Live MD theme re-rendering** with the reader open (deferred — R10 / round-2 Finding 2; `MDReaderContainerView` would need a theme-keyed re-render path, and a correct one must re-parse — see §3.2. v1's MD theme colors apply on the next open, matching MD's existing Chinese-conversion limitation).
- A **true floated** TXT/MD drop-cap with multi-line text wrap (deferred — R1; TextKit exclusion-path complexity, explicitly rejected for v1; the auditor confirmed the approximation needs no `needs-design` issue).
- PDF chapter-start typography (n/a — fixed page raster).
- Deep **nested-markup** EPUB drop-cap selectors beyond `body > p:first-of-type` (deferred — R6).
- A small-caps / uppercase **font-feature** treatment of native TXT/MD headings (rejected for v1 — §3.2/§8).

---

## 13. Gate-2 audit trail — round 1 (Codex `019e3bee` — NEEDS-REVISION → resolved in v2)

| # | Severity | Round-1 finding | v2 resolution | Round-2 status |
|---|----------|-----------------|---------------|----------------|
| 1 | HIGH | v1 internally inconsistent on synthetic TXT chapters — §2/WI-2 proposed injecting an in-flow heading; §7 R7 / §10 recommended none. A display-only prepended heading would also shift scroll/selection/highlight offsets. | **Synthetic-heading injection removed entirely.** `buildChapterStart`'s `injectedHeading` parameter and `TXTReaderViewModel.currentChapterInjectedHeading` are deleted. Synthetic/`"前言"` chapters get the **drop-cap only**, no heading. `buildChapterStart` only ever adds attributes — `NSAttributedString.string` is byte-identical to `currentChapterText` in every TXT path. §2 table, §3.2, §4.2, §6, R7 (now "eliminated"), §10 criterion 2 all made consistent. | Confirmed genuine by the round-2 audit. Preserved unchanged in v3. |
| 2 | HIGH | v1 said "uppercase the heading text" while claiming the rendered string + offsets stay identical — a contradiction; `NSAttributedString` has no `text-transform` and `String.uppercased()` can change UTF-16 length. | **No uppercase on native TXT/MD headings.** v1 keeps **source casing**. Small-caps/uppercase via `UIFontDescriptor` font features was considered and **explicitly rejected for v1** (Source Serif 4 not bundled; Georgia-fallback feature coverage inconsistent; extra code path). Decision stated explicitly in §3.2, §4.2, §4.3, §8; WI-2/WI-3 tests assert heading characters are byte-identical to source. | Confirmed genuine by the round-2 audit. Preserved unchanged in v3. |
| 3 | HIGH | WI-3 missed required MD config plumbing — `MDFileLoader.load` hardcodes `MDRenderConfig.default`; `MDReaderViewModel.open` has no render-config parameter, so new `mdRenderConfig` fields would never reach rendering. | **Plumbing added.** `renderConfig: MDRenderConfig` parameter added to `MDReaderViewModel.open` and `MDFileLoader.load` (replacing the hardcoded `.default` at `MDFileLoader.swift:47`), forwarded into `parser.parse`. The decorator runs in `MDReaderViewModel.open` with the caller-supplied config. Wiring spelled out in §4.3; new `MDFileLoaderRenderConfigTests` (§6) pins that a non-default config reaches the rendered output; R11 added. | The *plumbing seam* is confirmed genuine. The round-2 audit found the **final call site** in v2's §4.3 step 4 was mis-cited (`EPUBReaderContainerView.swift:134` is the EPUB reader). Corrected in v3 — see §14 Finding 1. |
| 4 | MEDIUM | MD scope inconsistent — §2 promised leading-OR-post-thematic-break heading styling; WI-3/acceptance only did the leading heading; `MDHeading` does not encode break adjacency. | **Scope narrowed to the leading document heading only** (first `MDHeading` with `charOffsetUTF16 == 0`). Post-break styling explicitly deferred (would need `MDHeading` extension / a break marker). §2 table, §4.3, §6, R9, §10 criterion 3, §12 all updated. | Confirmed genuine by the round-2 audit. Preserved unchanged in v3. |
| 5 | MEDIUM | WI parallelism rationale wrong — WI-2 and WI-3 both modify `ReaderSettingsStore.swift`, so they are not a disjoint write set under rule 48. | **WI-2 and WI-3 marked sequential** — WI-3 depends on WI-2 (verified: `txtViewConfig` and `mdRenderConfig` are both computed properties in `ReaderSettingsStore.swift`). §5 dependency column and rationale updated; WI-4/WI-5 confirmed genuinely disjoint and may still run parallel to the WI-2→WI-3 chain. | Confirmed genuine by the round-2 audit. Preserved unchanged in v3. |
| 6 | MEDIUM | EPUB/AZW3 `p:first-of-type::first-letter` selector too loose — multiple drop-caps in nested markup. | **Concrete selector pinned: `body > p:first-of-type::first-letter`** (child combinator → first top-level `<p>` directly under `<body>`). Two EPUB shapes named and tested with fixtures (flat top-level `<p>`; section-wrapped → safe miss). §4.4, §4.5, R6, §6 WI-4/WI-5 tests, §10 criterion 5 updated. Deeper nesting an explicit follow-up. | Confirmed genuine by the round-2 audit. Preserved unchanged in v3. |
| 7 | MEDIUM | Paged-mode clipping treated as a late verification concern, but `NativeTextPagedView` is a non-scrollable `UITextView` with fixed insets — deterministic clip possible. | **Up-front WI-2/WI-3 paged-mode verification gate added** (mandatory slice verification, before WI acceptance). **Fallback decided now** (R3): reduce negative `baselineOffset` / add top breathing room, or disable the drop-cap in paged mode (documented, test-pinned degradation). §5, R3, §10 criterion 9 updated. | Confirmed genuine by the round-2 audit. Preserved unchanged in v3. |
| 8 | LOW | Wrong Foliate mapper file path — it is `vreader/Services/Foliate/FoliateStyleMapper.swift`, not under `Views/Reader`. | **Path corrected** to `vreader/Services/Foliate/FoliateStyleMapper.swift` in §3.1 (prior-art table) and §4.5; §2 and §6 already used the correct path and were re-verified. | Confirmed genuine by the round-2 audit. Preserved unchanged in v3. |
| 9 | LOW | §2's TXT chapter-source description inaccurate — `"前言"` is added in the regex path when content precedes the first match, not by `buildSynthetic`. | **Provenance corrected.** §2 now states `"前言"` is created inside `buildWithRegex` (`TXTChapterIndexBuilder.swift:158-174`) for matched content that does not start at the file head; `buildSynthetic` only ever fabricates `"Chapter N"`. Both titles are absent from the body, so both correctly yield `headingLineLength == 0`. | The `"前言"`-provenance fix is confirmed genuine. The round-2 audit separately found §2 *still* mis-described the TXT *loading* mechanism (`startByte` vs UTF-16 slice). Corrected in v3 — see §14 Finding 3. |
| 10 | (confirmation) | Auditor confirmed rule 51 is NOT a blocker — the non-floating TXT/MD drop-cap approximation is an acceptable engine-constraint implementation; no `needs-design` issue required. | **§8 made accurate to that ruling.** v2 removes the v1 conditional "if the user judges the non-wrapping unacceptable, file a `needs-design` issue"; §8 now states plainly that no `needs-design` issue is required and the approximation ships as a normal WI-6 review item. R1 updated to match. | Confirmed genuine by the round-2 audit. Preserved unchanged in v3. |

---

## 14. Gate-2 audit trail — round 2 (NEEDS-REVISION → resolved in v3)

The round-2 independent Gate-2 audit confirmed every v2 round-1 fix as genuine (see the "Round-2 status" column in §13) and raised 3 new findings against v2. All 3 were re-verified against the codebase on 2026-05-19 — the auditor was correct on all 3 — and are resolved in v3 as follows.

| # | Severity | v2 location | Round-2 finding | Codebase re-verification | v3 resolution |
|---|----------|-------------|-----------------|--------------------------|---------------|
| 1 | MEDIUM | plan v2 §4.3 step 4 (≈line 260) | The claimed MD container seam is wrong. v2 cited `EPUBReaderContainerView.swift:134` as "the surface that hosts the MD reader"; that line is the **EPUB** reader opening `EPUBReaderViewModel`. The real MD open call is `MDReaderContainerView.swift:116-119`. v2's "verified end-to-end plumbing" claim is inaccurate at the final call site. | **Confirmed.** `EPUBReaderContainerView.swift:134` is `await viewModel.open(url: fileURL)` inside `EPUBReaderContainerView`'s `.task`, where `viewModel` is an `EPUBReaderViewModel` — the EPUB reader, unrelated to MD. The actual MD open call is `MDReaderContainerView.swift:116-119`: `await viewModel.open(url: fileURL, chineseConversion: settingsStore?.chineseConversion ?? .none)` inside `MDReaderContainerView`'s only `.task` (lines 108-144), where `viewModel` is an `MDReaderViewModel`. | **WI-3 retargeted to `MDReaderContainerView`.** §4.3 step 4 rewritten: the live `renderConfig` caller is `MDReaderContainerView.swift:116-119`; WI-3 adds `renderConfig: settingsStore?.mdRenderConfig ?? .default` to *that* call (`settingsStore` is already a property of `MDReaderContainerView`, line 30 — no new wiring). The full path `MDReaderContainerView.task → MDReaderViewModel.open → MDFileLoader.load → parser.parse` is re-verified and spelled out. §5 WI-3 file list now names `MDReaderContainerView.swift`; §4.6 records `EPUBReaderContainerView.swift` as not-a-WI-3-file; R11 and §13 row 3 corrected. |
| 2 | MEDIUM | plan v2 §10 (≈line 479) | The acceptance contract is internally inconsistent for MD theme changes. v2 criterion 4 said MD colors update "on the next open"; v2 criterion 7 and §11 required **live** theme switching with the reader open. MD has no theme-change reopen/re-render path — `MDReaderContainerView.swift:108-119` calls `open` only once in `.task`, and the change handlers are layout/font-size, not theme. | **Confirmed.** `MDReaderContainerView`'s single `.task` (lines 108-144) is **not** keyed (`.task` with no `id:`) and is guarded by `if viewModel.renderedText == nil` — it runs once. Its `.onChange` handlers (lines 198-237) cover `epubLayout`, `typography.fontSize`, `autoPageTurn`, `autoPageTurnInterval`, `ttsService` — there is **no** `.onChange(of: settingsStore?.theme)`. `renderedAttributedString` is `private(set)` and assigned only inside `MDReaderViewModel.open` (`MDReaderViewModel.swift:157`). MD genuinely has no live theme re-render path. (TXT does, via `.task(id: attrStringKey)`; EPUB/Foliate do, via CSS re-injection.) | **Contract narrowed for MD — one consistent decision applied everywhere.** Adding a live MD path was evaluated and rejected (a decorate-only re-run leaves the body half-themed; a correct re-theme must re-parse, i.e. reopen — §3.2 rejected-alternatives row). v3 picks the honest option: **MD chapter-start colors apply on the next open of the file** — consistent with MD's existing documented Chinese-conversion limitation (`MDReaderViewModel.swift:113-115`). TXT/EPUB/Foliate keep live switching. Applied consistently: criterion 4 (MD "next open"), criterion 7 (live for TXT/EPUB/AZW3, next-open for MD), §11 (TXT/EPUB/AZW3 verified live, MD verified by switch-then-reopen), R10 (rewritten per format), §4.3 (new "MD theme-change behavior" paragraph), §8 (new MD fidelity-gap note), §12 (live MD re-theme listed out of scope), WI-3 verification tier (§5) and the WI-3 `MDReaderViewModelChapterStartTests` (§6) — the MD test asserts the next-open contract, with no live-color-change test. |
| 3 | LOW | plan v2 §2 (≈line 52) | §2 still describes the TXT loading seam incorrectly. `TXTChapterContentLoader` does not load chapter text "from `startByte`"; it slices decoded full text by `globalStartUTF16` and `textLengthUTF16` (`TXTChapterContentLoader.swift:29-49`). The chapter-start conclusion is directionally right but the cited mechanism is wrong. | **Confirmed.** `TXTChapterContentLoader.loadChapter` (`TXTChapterContentLoader.swift:29-49`) decodes the full file once into `fullText` (an `NSString`), then slices it with `NSRange(location: chapter.globalStartUTF16, length: chapter.textLengthUTF16)`. It never reads a byte range and never references `startByte`. The file header itself states the "GH #30 rewrite … decodes full file once … then slices chapters by globalStartUTF16 + textLengthUTF16." | **§2 corrected to the real mechanism.** §2's TXT sub-finding now states: the regex builder records the chapter's UTF-16 start (`globalStartUTF16`) at the matched heading line, and `TXTChapterContentLoader` produces `currentChapterText` by **full-decode-then-UTF-16-slice** from that start (not a `startByte` byte-range read). The chapter-start conclusion (the heading line *is* the body's first line for regex chapters) is unchanged and now rests on the correct mechanism. §4.2's `currentChapterHeadingLineLength` derivation note updated to confirm it reads `currentChapterText` and never touches `startByte`. §3.1's "TXT chapter mode" prior-art row updated. |

**Round-1 fixes preserved (no regression).** v3 changes only the three artefacts the round-2 audit named: the MD container call site (§4.3 step 4, §5 WI-3 row, §4.6, R11), the MD theme-change contract (criterion 4, criterion 7, §11, R10, §4.3, §8, §12, §5/§6 WI-3), and §2's TXT loader-mechanism wording. Every v2 round-1 fix — synthetic-heading removal (Finding 1), no-uppercase (Finding 2), the `renderConfig` plumbing *seam* itself (Finding 3), MD leading-heading-only scope (Finding 4), WI-2/WI-3 sequencing (Finding 5), the `body > p:first-of-type` selector (Finding 6), the up-front paged-mode gate (Finding 7), the Foliate path (Finding 8), `"前言"` provenance (Finding 9), and the §8 rule-51 ruling (Finding 10) — is carried into v3 verbatim and unmodified.

---

### Critical Files for Implementation
- `/Users/ll/workspace/vreader/vreader/Views/Reader/MDReaderContainerView.swift`
- `/Users/ll/workspace/vreader/vreader/ViewModels/MDReaderViewModel.swift`
- `/Users/ll/workspace/vreader/vreader/Services/MD/MDFileLoader.swift`
- `/Users/ll/workspace/vreader/vreader/Services/TXT/TXTAttributedStringBuilder.swift`
- `/Users/ll/workspace/vreader/vreader/Services/ReaderSettingsStore.swift`
