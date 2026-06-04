# Feature #92 — Justified text alignment for the TXT reader

**Status**: WI-1 merged (v3.53.1). WI-2 (paged) DEFERRED — verification-blocked
(render-extension leaks off-page selection; clean fixes need interactive
device verification). Feature `IN PROGRESS`.
**Row**: `docs/features.md` #92 (Medium, TODO)
**Author**: claude
**Date**: 2026-06-05

---

## Problem

TXT body text is left/natural-aligned, so the right edge is ragged. For CJK
(which wraps per full-width character) the gap before the right inset can be
up to ~1 full-width cell, which reads as **uneven left/right margins** even
though all three TXT render paths use SYMMETRIC horizontal insets. The user
reported it on a large CJK book: *"txt, the padding on left and right is not
same wide."* Triage investigation (`docs/features.md` #92) confirmed it is NOT
a padding bug — the insets are symmetric (`left:16 right:16`,
`lineFragmentPadding = 0`) on the non-chunked / chunked / paged paths. The
perceived asymmetry is the **ragged right edge of non-justified text**:
`TXTAttributedStringBuilder.build` (`:45`) builds an `NSMutableParagraphStyle`
with `lineSpacing` but no `alignment`, so it defaults to `.natural` (left).

CJK readers conventionally justify both margins flush. This feature sets
`paragraphStyle.alignment = .justified` so lines fill to the right margin.

---

## Surface area

### In scope

#### 1. `vreader/Services/TXT/TXTAttributedStringBuilder.swift` — the single seam

`build(text:config:)` (the pure, off-main, `@Sendable`-safe builder) is the
ONE place every plain-TXT render path constructs its paragraph style. Add a
single line after `paragraphStyle.lineSpacing = config.lineSpacing`:

```swift
// Feature #92: justify so both margins are flush (CJK reader convention).
// TextKit only justifies non-terminal lines — the last line of each
// paragraph stays natural-aligned automatically (no awkward stretched
// final line). Justification adjusts intra-line spacing only; it does NOT
// move line-break positions, so page boundaries (line-count-based) are
// unchanged (see Risks → paginator stability).
paragraphStyle.alignment = .justified
```

That is the entire production change. Every consumer of `build` inherits it:

- **Non-chunked** — `TXTTextViewBridge.swift:437` → `build` → `UITextView`.
- **Chunked** (>500K UTF-16) — `TXTChunkedReaderBridge.swift:1042` → `build`.
- **Paged** — `TXTReaderContainerView` builds via
  `buildChapterStart` / `buildSendable` (`:587/602/673`), passes the
  attributed string to `NativeTextPagedView`; `repaginatePagedChapter` slices
  pages with `NativeTextPaginator.paginateAttributed(attributedText:)`
  (`TXTReaderContainerView+Paged.swift:153`) — the SAME attributed string for
  pagination AND render, so both are justified and consistent.
- **Chapter-start** (feature #68) — `buildChapterStart` calls `build` for the
  base, so its body paragraphs inherit `.justified`. The heading line is
  re-styled by `TXTChapterStartDecorator` which creates a FRESH paragraph
  style with explicit `style.alignment = .center`
  (`TXTChapterStartDecorator.swift:83-84`), so the centered chapter title is
  UNAFFECTED. The drop-cap body paragraph copies the base style via
  `mutableCopy()` (`:250`), so it stays `.justified`.

### Files OUT of scope

- `NativeTextPaginator.paginate(text:font:)` (`:56`, the non-attributed
  overload that builds its own measurement style) — NOT on the TXT paged path
  (which uses `paginateAttributed`). Justification doesn't move line breaks,
  so even measurement code that stayed `.natural` would compute identical
  breaks; no change needed.
- **MD reader** — uses a separate renderer (`MDAttributedStringRenderer`), not
  `TXTAttributedStringBuilder`. Out of scope (the feature is TXT-specific;
  MD justification would be its own row).
- **An alignment SETTING** (Left/Justified toggle in the Display panel) —
  that is NEW UI → `needs-design` (rule 51). Explicitly deferred. This slice
  is justify-by-default only (a pure rendering attribute, no chrome — rule 51
  N/A, confirmed in the row's triage record).
- Persistence / positions / highlights / search / TTS — untouched (see
  Backward compat).

### Bilingual note

`BilingualAttributedStringComposer` composes interlinear source+translation
blocks; if it routes a block through `build` it inherits `.justified` (a
consistent, harmless improvement). Implementation will confirm whether
bilingual blocks go through `build`; if they use a bespoke paragraph style,
bilingual justification is a documented non-goal of this slice (the user's
report is the plain reader). Either outcome is acceptable — no bilingual
regression either way (justification can't break offsets).

---

## Prior art / project precedent / rejected alternatives

- **Single-seam precedent**: feature #68 (chapter-start typography) and the
  font-size/line-spacing config already flow through
  `TXTAttributedStringBuilder.build`; #92 adds one paragraph-style property at
  the same seam, so all three layout modes get it without per-path edits.
- **Backing-string invariant**: feature #68's CONTRACT — `buildChapterStart`
  "only ever ADDS attributes; the backing string is byte-identical" — is the
  reason positions/highlights/search/TTS are safe. `alignment` is likewise a
  paragraph ATTRIBUTE; it changes glyph x-positions but never the backing
  string or character offsets.
- **TextKit last-line behavior**: `.justified` justifies all lines EXCEPT the
  last line of each paragraph (and single-line paragraphs), which TextKit
  leaves natural — so no stretched-final-line artifact. This is standard
  ebook-reader behavior (Apple Books / Kindle justify by default).
- **Rejected — CJK-only justification** (detect script, justify only if
  predominantly CJK): adds script-detection complexity for marginal benefit;
  Latin justification is the dominant ebook convention too. The Latin
  "gappy short line" risk is mild and accepted (see Risks). Keeping it
  unconditional matches the triage scope (`set alignment = .justified`).
- **Rejected — enabling `hyphenationFactor`** to tighten Latin justification:
  hyphenation is a separate, opinionated typographic choice (some users
  dislike hyphens), and is N/A for CJK (the reported case). Out of scope;
  could be a future enhancement.
- **Rejected — an alignment toggle setting**: new UI → `needs-design`
  (rule 51). Deferred.

---

## Work-item sequencing

**Two WIs** (Gate-4 impl audit revealed the paged path needs separate work —
see the paged-terminal-line finding below).

- **WI-1 — justify TXT body at the builder seam** — *behavioral*. 1 source
  line + tests. Covers the **non-chunked (scroll)** and **chunked** paths
  fully: scroll renders the whole chapter in one `UITextView` (only true
  paragraph-terminal lines stay natural — correct); chunked splits at NEWLINE
  boundaries (`TXTTextChunker`), so each chunk ends at a paragraph end and its
  visible terminal lines are correctly natural. **This is the user's reported
  case** — a large CJK book in scroll mode uses the chunked path (>500K UTF-16)
  and justifies cleanly. PR → row `IN PROGRESS`. Patch bump.
- **WI-2 — justify paged-mode page-terminal lines** — *behavioral, FINAL WI*.
  **Status: DEFERRED (verification-blocked) — see the WI-2 attempt below.**
  The paged renderer (`NativeTextPagedView`) draws each page from an isolated
  `attributedSubstring` (`NativeTextPageNavigator.currentPageAttributedText`),
  so TextKit treats each page's last visible line as a substring-terminal line
  and leaves it unjustified even when the paragraph continues onto the next
  page (WI-1 Gate-4 Medium). PR → row `DONE`. Minor bump (completes the feature).

  **WI-2 attempt 1 (2026-06-05) — render-extension approach, ABANDONED.**
  Added `currentPageRenderAttributedText(from:)` that extends the rendered
  substring to the page's paragraph end (next newline), so the page-bottom
  line becomes a non-terminal soft-wrap TextKit justifies; the page-sized
  container clips the off-page overflow. Unit tests green (range logic). But
  the **WI-2 Gate-4 audit (Codex `019e9434`) found a Medium**: the rendered
  `UITextView` stays `isSelectable`, so the off-page overflow is hidden
  *visually* (clip) but NOT *semantically* — long-press-drag / Select-All /
  copy can reach next-page text, and any selection→offset logic that assumes
  "rendered text == page range" breaks once a selection crosses
  `currentPageCharRange.length`. The approach was abandoned (never merged) to
  avoid regressing paged-mode selection/copy (a feature users rely on;
  Bug #215 shows this rendering area is fragile).

  **Two viable WI-2 approaches (both need INTERACTIVE device verification):**
  1. **Selection-clamped overflow** — keep the render-extension, but make
     `NativePagedContainer` the textView's `UITextViewDelegate` and clamp
     `selectedTextRange` to the exact page range in `textViewDidChangeSelection`
     (with a recursion guard). Verify on-device: justified page-bottom line +
     selection/Select-All/copy never reach off-page text + no janky snap.
  2. **Shared-layout custom render** — render the page from the paginator's
     full-chapter `NSLayoutManager` (page-internal lines are justified in the
     full layout) via a non-selectable drawing layer, with a separate exact-
     page selection surface. Heavier but semantically clean.

  **Why DEFERRED, not done now**: both approaches require interactive
  selection-behavior verification (long-press-drag at the page boundary,
  Select-All, copy) that is NOT unit-testable and needs idb gesture driving +
  screenshot inspection on a real paged TXT. Shipping either blind risks a
  paged-mode selection/copy regression. WI-1 already delivered the user's
  reported case (large-CJK scroll/chunked). WI-2 is the cosmetic remainder
  (one page-bottom line per page in paged mode only).

> **Why split, not one big WI**: WI-1 is a safe, tested, strictly-improving
> change that lands the user's actual case now; WI-2 is a focused rendering
> rearchitecture with its own risk profile and test. Bundling them would mix a
> one-line builder change with a layout-engine change under one audit.

---

## Test catalogue

`vreaderTests/Services/TXT/TXTAttributedStringBuilderTests.swift` (extend):

| Test | Asserts |
|---|---|
| `buildAppliesJustifiedAlignment` | `build(text:config:)` → first-char `.paragraphStyle.alignment == .justified` |
| `buildJustifiesCJKAndLatin` (param: CJK + Latin + mixed text) | alignment is `.justified` regardless of script |
| `buildHandlesEmptyStringNoCrash` (edge: "") | `build` returns a `length == 0` string without crashing (an empty `NSAttributedString` has no character index to read `.paragraphStyle` from, so this asserts no-crash only — split from the single-char case per Gate-2 Low) |
| `buildJustifiesSingleChar` (param: "a", "字") | first-char `.paragraphStyle.alignment == .justified` (the attribute is set even though TextKit renders a single line natural) |
| `buildPreservesLineSpacingAndFontWithJustify` | adding alignment didn't drop `lineSpacing` / font / color attributes |

`vreaderTests/Services/TXT/TXTAttributedStringBuilderChapterStartTests.swift`
(existing `headingIsCentered` test at `:87` must still pass — regression
guard that the decorator's explicit `.center` heading survives the base
`.justified`). Add:

| Test | Asserts |
|---|---|
| `chapterStartBodyIsJustifiedHeadingCentered` | after `buildChapterStart`, the heading paragraph is `.center` AND a body paragraph (past the heading) is `.justified` |

`vreaderTests/Views/Reader/` (paginator stability — the triage's core worry):

| Test | Asserts |
|---|---|
| `paginationBoundariesUnchangedByJustification` | paginate the SAME text+viewport with a `.natural` vs `.justified` attributed string via `NativeTextPaginator.paginateAttributed` → identical page count + identical per-page character ranges (proves justification doesn't drift page boundaries) |

---

## Risks + mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| **Page-boundary drift** in the paged reader (saved positions land on the wrong page) | Very low | Justification adjusts intra-line spacing only; line breaks are determined by the line-breaking pass BEFORE alignment, so breaks (and thus line count / page boundaries) are identical. Pinned by `paginationBoundariesUnchangedByJustification`. The paged path uses `paginateAttributed` with the same justified string for measure + render. |
| **Latin/mixed text looks gappy** (large inter-word gaps on short lines) | Medium (cosmetic) | Accepted, documented limitation. This is standard justified-without-hyphenation behavior and matches Apple Books/Kindle defaults. The reported case (CJK) justifies cleanly (full-width cells). A future `hyphenationFactor` enhancement could tighten Latin — out of scope. |
| **Highlight / selection rects shift** | Low (correct by construction) | Highlights are anchored by CHARACTER RANGE, not pixel rect; TextKit recomputes glyph rects from the justified layout, so a highlight still covers its characters (at justified positions). Offsets/search/TTS use the backing string, which is unchanged. |
| **Paged-mode page-bottom line ragged** (page breaks mid-paragraph → the isolated `attributedSubstring`'s terminal line isn't justified) | Certain in paged mode (Gate-4 Medium) | **WI-2 (DEFERRED, verification-blocked)** — the naive render-extension fix leaks off-page text into the selection surface (WI-2 Gate-4 Medium); the clean fixes (selection-clamp or shared-layout custom render) need interactive device verification. Until WI-2: paged is a strict improvement under WI-1 (most lines justified; only each page's bottom mid-paragraph line ragged). |
| **Chunked hard-split fallback** (a very long no-newline line is bisected mid-paragraph → that fragment's terminal line ragged) | Low / rare (Gate-4 Low) | Normal chunked splits are at NEWLINE boundaries (paragraph ends → correctly natural). Only pathological single-line TXT hits the hard split. Documented limitation; not worth special-casing. |
| **A TXT path that does NOT route through `build`** stays ragged | Low | **Code audit** confirms each plain-TXT path routes through `build` today (`:437`, `:1042`, `:587/602/673`); the builder-seam + chapter-start + paginator-stability tests pin the seam behavior (they do not directly instantiate each bridge — per Gate-2 Low). |
| **Chapter-start heading loses its centering** | Low | The decorator sets `.center` on a fresh style explicitly (`:83-84`); regression-guarded by the existing `:87` test + the new `chapterStartBodyIsJustifiedHeadingCentered`. |

---

## Backward compat

- **No persistence / schema / offset change.** `alignment` is a render-time
  paragraph attribute; the backing string and all character offsets are
  unchanged, so saved reading positions (`charOffsetUTF16` locators),
  highlights, bookmarks, search indices, and TTS ranges all resolve exactly
  as before — and to the same on-screen page (line breaks unchanged).
- **Existing TXT books** re-render justified on next open; no migration.
- **Rule 51**: justify-by-default is a pure rendering attribute, no new chrome
  / control → N/A (confirmed in the row's triage record). An alignment toggle
  would be new UI → deferred to `needs-design`.

---

## Revision history

- **v1 (2026-06-05)** — initial plan. Gate-2 audit (Codex `019e9418`,
  `gpt-5.4`/high) → **READY TO BUILD**, zero Critical/High/Medium; 2 Low:
  (a) the empty/single-char test conflated two cases → split into
  `buildHandlesEmptyStringNoCrash` + `buildJustifiesSingleChar`; (b) "Tests
  assert each" overstated coverage → reworded the risk row to "code audit
  confirms each path". Both fixed in-plan. Gate 2 passes.
- **v2 (2026-06-05)** — WI-1 (builder) implemented + tested (63 tests incl.
  `justificationDoesNotChangePageBoundaries`). Gate-4 impl audit (Codex
  `019e9420`) → **block-recommended**: 1 Medium (paged mode renders each page
  from an isolated `attributedSubstring`, so the page-bottom mid-paragraph
  line is a substring-terminal line and stays unjustified) + 1 Low (chunked
  hard-split bisects a paragraph). Both are about rendering SPLIT text in
  isolation. Resolution: **split the feature into 2 WIs** — WI-1 (builder)
  correctly covers scroll + chunked (the user's CJK case splits at newlines);
  WI-2 fixes paged via a shared TextKit layout. The Low (chunked hard-split)
  is a documented pathological-input limitation. WI-1 is now an INTERMEDIATE
  WI (row → `IN PROGRESS`, not `DONE`).
- **v3 (2026-06-05)** — WI-1 merged (v3.53.1, PR #1506). WI-2 attempt 1
  (render-extension) implemented + unit-tested but **abandoned** after its
  Gate-4 audit (Codex `019e9434`) found the extended-but-clipped render text
  stays selectable → off-page text leaks into selection/copy. WI-2 marked
  **DEFERRED (verification-blocked)**: the two clean approaches
  (selection-clamped overflow / shared-layout custom render) need interactive
  on-device selection verification not feasible CU-free here. Feature stays at
  `IN PROGRESS` (WI-1 delivered the user's reported case; WI-2 is the cosmetic
  paged-mode remainder). See the WI-2 section for the full write-up.
