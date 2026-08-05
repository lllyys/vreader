# Feature #156 — Android justified text alignment (TXT/MD + EPUB)

**Status**: Gate 1 (plan) → Gate 2 (independent audit pending)
**Row**: `docs/features.md` #156 (Medium, TODO) — parity phase 4, box **G6**
**Platform**: `android-app` (rule 40 → bumps `android/version.properties`, tags `android/vX.Y.Z`)
**Slug**: android-justified-text
**iOS parity**: #92 (TXT, VERIFIED v3.53.1) + #95 (EPUB, VERIFIED v3.60.0)

---

## 0. Two premises in the row are FALSE — read this section first

The tracker row for #156 says:

> iOS ships justification for TXT (#92) and EPUB (#95) **as a Display-sheet control**. **Scope**: a
> justify toggle in the existing `ReaderSettingsSheet` … Reuses #129's committed Display sheet →
> **rule-51-clean**.

Both emphasised claims are wrong, verified against the source:

### 0.1 — iOS did NOT ship a Display-sheet control. It shipped justify-BY-DEFAULT.

Both iOS features explicitly **rejected** the toggle and deferred it as `needs-design`:

- `dev-docs/plans/20260605-feature-92-txt-justified-text.md:79-82` — "**An alignment SETTING**
  (Left/Justified toggle in the Display panel) — that is NEW UI → `needs-design` (rule 51).
  Explicitly deferred. This slice is justify-by-default only (a pure rendering attribute, no chrome
  — rule 51 N/A…)".
- `dev-docs/plans/20260605-feature-92-txt-justified-text.md:122-123` — "**Rejected — an alignment
  toggle setting**: new UI → `needs-design` (rule 51). Deferred."
- `dev-docs/plans/20260609-feature-95-epub-justify.md:15-20` — "**Scope (default-justify is Rule 51
  N/A** — pure rendering attribute, no new UI) … An explicit Left/Justified *toggle* in the Display
  panel would be NEW UI → `needs-design` (deferred, out of scope — exactly as #92 noted)."
- `dev-docs/plans/20260609-feature-95-epub-justify.md:79` — files-out-of-scope: "Any Display-panel
  UI / Left↔Justified toggle (needs-design, deferred)."

The iOS production change is literally one paragraph-style line
(`paragraphStyle.alignment = .justified`) plus a CSS/preferences default. **There is no iOS
alignment control to reach parity with.** Building an Android toggle would be Android *ahead* of
iOS on an undesigned surface, not parity.

### 0.2 — Adding a toggle to `ReaderSettingsSheet` is NOT rule-51-clean.

See §1. The committed design's Display sheet has no alignment control.

**Consequence for this plan**: the scope is **justify-by-default across the reflowable readers, with
no new UI**. This is the iOS-parity shape, the rule-51-clean shape, and the smaller change. The
orchestrator must accept this scope correction (§13, Q1) before Gate 2 — or, if a toggle is genuinely
wanted, file `needs-design` first and treat it as a separate follow-up feature.

---

## 1. Rule 51 verdict (checked, not assumed)

**Verdict: justify-by-default is DESIGN-BACKED and rule-51 clean. A justify TOGGLE is NOT designed
and would require a `needs-design` filing.**

Evidence, artboard by artboard (the only committed bundle is `dev-docs/designs/vreader-fidelity-v1/`):

**(a) The Display sheet has no alignment control.** `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx:61-186`
is the entire `ReaderSettingsSheet` artboard. Its controls, in order, are exactly:

| Design line | Control |
|---|---|
| `:69-72` | Brightness slider |
| `:74-108` | Theme (5 swatches) |
| `:110-135` | Layout (Paged / Scroll segmented) |
| `:137-158` | Font (Source Serif / Inter segmented) |
| `:160-166` | Size slider (13–26) |
| `:168-174` | Line spacing slider (1.3–2.0) |
| `:176-182` | Margin slider (16–48) |

There is no Alignment / Justify / Text-align section, and no other bundle depicts one — an
exhaustive grep for `justified` / `text-align` / `alignment` across `dev-docs/designs/` returns only
`alignItems`/`justifyContent` CSS-layout noise plus the three prose hits quoted below. Per rule 51's
"What 'designed' means" test, a justify toggle fails criterion 2 → **filing required if pursued**.

**(b) The designed reader body IS justified.** The committed reader artboard renders body paragraphs
with `textAlign: 'justify'`:

- `dev-docs/designs/vreader-fidelity-v1/project/vreader-reader.jsx:380` — `textAlign: 'justify', hyphens: 'auto'`
  (the reader's body `<p>` style, alongside `textIndent`, the theme ink, and the drop cap).
- `.../bilingual-suite-artboards.jsx:103` — same, for the bilingual reader body.
- `.../highlight-landing-artboards.jsx:178, 336, 513, 532, 572, 580, 588` — seven more body-text
  artboards, all `textAlign: 'justify'`.
- `.../ai-readiness-artboards.jsx:34` — same.
- `.../design-notes/reader-navigation.md:83` — the chrome-animation note reasons *about* justified
  body text as a given: "**Justified text** won't reflow mid-page because we're animating a clip
  region, not a width."

So the design does not merely permit justification — it **specifies** it as the reader's body
rendering, in ten places across five artboards, and a design note depends on it. Shipping
justify-by-default moves Android *toward* the committed design; the current natural/left alignment is
the deviation. This is rule 51's "pure code change with no visible delta"? No — it *is* a visible
delta, but it is a **depicted** one, which is what the rule requires. No `needs-design` filing is
required for the default.

**`needs-design` filing decision**: **not required for the scope in this plan** (no new chrome, no
new control, no new state). It becomes required *the moment* anyone re-scopes #156 to include the
toggle. Because rule 51 forbids conditional deferrals ("if/when" phrasing is prohibited — see the
rule's Anti-patterns table and the #114/#122 precedent), this plan does **not** write "file one if we
later want a toggle." Instead: the toggle is **removed from scope outright** as a wrong-premise item
(§0.1 — iOS has no such control either), so there is no deferred design blocker to track. If the
orchestrator overrides §13 Q1 and wants the toggle, the filing is unconditional and immediate at that
moment, and #156 does not proceed to Gate 3 until the bundle lands.

---

## 2. Problem

Android reader text is natural/left-aligned in every format (`grep -ri justif android/` → 0 hits,
re-confirmed on this branch), so the right margin is ragged. The perceived defect is identical to the
one users reported on iOS twice ("the padding on left and right is not same wide", "the right padding
is wider than the left") — it is **not** a padding bug; the insets are symmetric on Android too
(`ReaderSettings.marginDp` is applied as symmetric horizontal padding). The ragged right edge of
unjustified text reads as an asymmetric margin, especially for CJK where a full-width cell that does
not fit leaves up to one character of white space before the right inset.

The fix is the same rendering attribute iOS applied — with the important caveat that **Android's two
justification engines behave very differently from iOS's, and both are weaker for CJK** (§4).

---

## 3. Wiring claims — every one verified, with `file:line`

Rule 47's Gate-2 bar makes an unverified wiring claim a **High** finding. Every claim this plan
relies on was checked by opening the file. Claims are marked ✅ verified / ⚠️ verified-and-
**contradicts** a common assumption.

| # | Claim | Evidence |
|---|---|---|
| W1 ✅ | `ReaderSettings` is the single display value type; it has **no** alignment field today | `android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettings.kt:20-27` (fields: theme, fontFamily, fontSizeSp, lineSpacing, marginDp, layout) |
| W2 ✅ | `bodyTextStyle()` is the single `ReaderSettings → Compose TextStyle` seam for TXT/MD, and it sets **no** `textAlign` | `.../settings/ReaderTextStyles.kt:29-35` |
| W3 ✅ | The TXT/MD host threads `bodyTextStyle()` into **both** render paths — paged and scroll | `.../reader/TxtReaderActivity.kt:865` (`TxtPagedBody(textStyle = displaySettings.bodyTextStyle(), …)`) and `:901` (`TxtBody(… textStyle = displaySettings.bodyTextStyle(), …)`) |
| W4 ✅ | Phase-1 pagination measurement and phase-2 render use the **same** merged style, so a `textAlign` added at the `bodyTextStyle()` seam reaches both | `.../reader/TxtReaderBody.kt:203-206` — `val effectiveStyle = LocalTextStyle.current.merge(textStyle)`, with the header comment "BOTH phase-1 measurement AND phase-2 render MUST use this identical style"; measurer built at `:209-211`; consumed at `:362` (`style = effectiveStyle`) and rendered at `:789-792` / `:994` |
| W5 ✅ | `toEpubPreferences()` is the single `ReaderSettings → EpubPreferences` seam, and it sets **no** `textAlign` and **no** `publisherStyles` | `.../reader/EpubPreferencesMapper.kt:37-44` (sets exactly fontSize, fontFamily, lineHeight, pageMargins, backgroundColor, textColor) |
| W6 ✅ | The EPUB host applies those prefs at open **and** live on every settings change | `.../reader/ReaderActivity.kt:241-243` (`initialPrefs = EpubPreferences(scroll=…) + current.toEpubPreferences()`, passed as `initialPreferences` at `:253`) and `:754-757` (`observeDisplaySettings` → `nav.submitPreferences(prefs)`) |
| W7 ✅ | Readium 3.3.0's Kotlin `EpubPreferences` really does expose `textAlign`, `publisherStyles`, `hyphens` | `javap` on `readium-navigator-3.3.0.aar` → `public final TextAlign getTextAlign()`, `public final Boolean getPublisherStyles()`, `public final Boolean getHyphens()` |
| W8 ✅ | `TextAlign.JUSTIFY` exists in that enum | `javap org/readium/r2/navigator/preferences/TextAlign` → `CENTER, JUSTIFY, START, END, LEFT, RIGHT` |
| W9 ⚠️ | **`publisherStyles` is never set anywhere in the app** — not in the mapper, not in `EpubNavigatorFragment.Configuration`, not via `EpubDefaults` | Repo-wide grep for `publisherStyles`/`EpubDefaults` across `android/app/src/main/kotlin` → **zero** hits; the only navigator config is `.../ReaderActivity.kt:257-260`, which sets only `selectionActionModeCallback` |
| W10 ⚠️ | ReadiumCSS applies `--USER__textAlign` **only** when `readium-advanced-on` is present (i.e. `publisherStyles = false`) | The shipped stylesheet inside the aar, `assets/readium/readium-css/ReadiumCSS-after.css`: `:root[style*=readium-advanced-on][style*="--USER__textAlign"]{text-align:var(--USER__textAlign)}` |
| W11 ⚠️ | **The same gate covers `--USER__lineHeight`** — so #129's EPUB line-spacing slider is very likely a no-op today (a pre-existing latent defect, §11 R4) | same file: `:root[style*=readium-advanced-on][style*="--USER__lineHeight"]{line-height:var(--USER__lineHeight)!important}` |
| W12 ⚠️ | For a **CJK** publication ReadiumCSS **disables `text-align` entirely** | `assets/readium/readium-css/cjk-horizontal/ReadiumCSS-after.css` contains **0** occurrences of `USER__textAlign` (grep -c = 0), and the bundled `readium-css/ReadMe.md:53-60` states for CJK-horizontal: "**Disabled user settings: `text-align`; `hyphens`; paragraphs' indent; `word-spacing`; `letter-spacing`**" |
| W13 ⚠️ | Readium picks that CJK stylesheet from the publication **language** | `javap -c Layout$Companion` → calls `LanguageKt.isCjk(Language)` then selects `Stylesheets.CjkHorizontal` / `CjkVertical`; `javap -c LanguageKt` → matches `zh`, `ja`, `ko` (+ `zh-hant`/`zh-tw` for vertical) |
| W14 ⚠️ | Our **real CJK test EPUB triggers exactly that path** | `test-books/books/epub/道诡异仙 - 狐尾的笔.epub` → `OEBPS/content.opf` declares `<dc:language>zh-CN</dc:language>` and no `page-progression-direction` → `isCjk` true, ltr → **CjkHorizontal** |
| W15 ✅ | The other real EPUB is Latin and will take the Default stylesheet | `test-books/books/epub/The Half Second - Li Xiaolai.epub` → `<dc:language>en</dc:language>` |
| W16 ⚠️ | Compose maps `TextAlign.Justify` to a **boolean** inter-word justification flag; there is no inter-character path | `javap -c androidx/compose/ui/text/AndroidParagraph` (ui-text-android 1.9.0) — `TextStyle.getTextAlign()` compared against `TextAlign.Companion.getJustify()`, result stored as `iconst_1`/`iconst_0` into the `justificationMode` slot; `StaticLayoutFactoryImpl` then calls `StaticLayoutFactory26.setJustificationMode(builder, mode)`. `1` = `LineBreaker.JUSTIFICATION_MODE_INTER_WORD` |
| W17 ✅ | The AZW3 (foliate) reader has a live CSS-injection seam that already receives `ReaderSettings` | `.../reader/Azw3DisplayCss.kt:33-70` (`foliateDisplayCss()`), injected at `.../reader/Azw3ReaderActivity.kt:394` — `LaunchedEffect(holder, displaySettings) { holder.document.setStyles(displaySettings.foliateDisplayCss()) }` |
| W18 ✅ | The Display sheet **is** production-reachable (rule 47 Gate-5) from both hosts | `.../reader/chrome/ReaderBottomChrome.kt:149` renders the "Display" (Aa) slot; the sheet is opened at `.../reader/ReaderActivity.kt:1071` (EPUB) and `.../reader/TxtReaderActivity.kt:979` (TXT/MD). User path: **Library → tap a book → tap centre to show chrome → bottom bar "Display"**. (Relevant even though this plan adds no control — Gate 5 still needs a production path to *observe* the change, and a settings change is the natural trigger.) |
| W19 ✅ | Settings persist as a versioned JSON blob with `ignoreUnknownKeys`, so **no** new persisted field is needed for a default-only change | `.../settings/ReaderSettingsStore.kt:24-31` (`ReaderSettingsState`), `:35` (`Json { ignoreUnknownKeys = true; encodeDefaults = true }`) |
| W20 ✅ | MD is rendered by the **same** host and the same `bodyTextStyle`, one `Text` per chunk, with headings emitted as a `SpanStyle` inside a heading-only chunk | `.../reader/TxtReaderBody.kt:198` (`val isMarkdown = format == BookFormat.md`), `:973` (`mapper.renderedText(i)`), `:994` (`Text(`); heading detection + span at `.../reader/MarkdownRenderer.kt:64-73` |

**Nothing in this plan asserts that a component "is wired" without a line number above.**

---

## 4. The three engines are genuinely different — and CJK is where they break

This is the substance of the feature, not a footnote.

### 4.1 The routing table (what actually renders what)

| Format | Host | Justification mechanism | Line-break owner |
|---|---|---|---|
| TXT, MD | `TxtReaderActivity` → `TxtReaderBody` (scroll) / `TxtPagedBody` (paged) | Compose `TextStyle.textAlign = TextAlign.Justify` → Android `StaticLayout` `JUSTIFICATION_MODE_INTER_WORD` (W16) | Android `LineBreaker` |
| EPUB | `ReaderActivity` → Readium `EpubNavigatorFragment` | `EpubPreferences.textAlign = TextAlign.JUSTIFY` → ReadiumCSS `--USER__textAlign` → WebView CSS `text-align: justify` | Chromium |
| AZW3/MOBI | `Azw3ReaderActivity` → foliate-js in a WebView | injected CSS (`foliateDisplayCss()`, W17) → `text-align: justify` | Chromium |
| PDF | `PdfReaderActivity` | **none — fixed layout, no reflow** | n/a |

Three different engines, three different last-line and CJK behaviours. Treating them as one
"add justify" change is precisely the mistake this section exists to prevent.

### 4.2 The last line

All three engines leave a paragraph's **last line** unjustified by default, so there is no stretched
final line. This is not something we implement — it is the engines' default, and it matches what iOS
got from TextKit (`dev-docs/plans/20260605-feature-92-txt-justified-text.md:109-112`: "`.justified`
justifies all lines EXCEPT the last line of each paragraph … so no stretched-final-line artifact").

- **Compose / `StaticLayout`**: `JUSTIFICATION_MODE_INTER_WORD` never stretches the final line of a
  paragraph.
- **CSS (EPUB + AZW3)**: `text-align: justify` leaves the last line to `text-align-last`, which
  defaults to `auto` → start-aligned. ReadiumCSS goes further and *explicitly* forces
  `text-align-last: auto !important` (`ReadiumCSS-after.css`, the
  `:not(blockquote):not(figcaption) p, body, li` rule) so a book that set `text-align-last: justify`
  cannot produce a stretched final line under our override.

**Where Android's paged TXT renderer differs from iOS's, and in our favour**: iOS #92's WI-2 was
DEFERRED because the iOS paged renderer draws each page from an isolated `attributedSubstring`, so a
mid-paragraph page-bottom line is a *substring-terminal* line TextKit refuses to justify
(`20260605-feature-92-txt-justified-text.md:140-146`). Android's paged path does not have that shape:
`TxtReaderBody` measures with `effectiveStyle` over the chunk and cuts pages at line boundaries (W4),
and phase-2 renders the same text — so whether the page-bottom line is treated as terminal depends on
whether the rendered slice ends the paragraph. **This must be observed, not assumed** — it is
acceptance criterion AC-3 and a named Gate-5 observation, not a claim (§11 R3).

### 4.3 CJK — the crux, and the reason this feature may not deliver its headline

**Both engines fail to justify space-free CJK, for two independent reasons.**

**(a) TXT/MD (Compose).** `TextAlign.Justify` compiles to `JUSTIFICATION_MODE_INTER_WORD` (W16).
Inter-word justification distributes slack **into space runs**. Chinese prose has no spaces, so there
is nothing to stretch and the predicted result is **zero visible change** on
`test-books/books/txt/黑暗血时代.txt` (14 MB CJK). Android added
`JUSTIFICATION_MODE_INTER_CHARACTER` in API 36, but **Compose 1.x does not expose it** — the bytecode
stores a boolean, not a mode (W16) — and `minSdk = 26` (`android/app/build.gradle.kts:30`) means most
of the install base could not use it anyway.

**(b) EPUB (Readium).** ReadiumCSS *deliberately disables* `text-align` for CJK-horizontal
publications (W12), and our real CJK EPUB declares `zh-CN` so it takes exactly that stylesheet
(W13, W14). Setting `EpubPreferences.textAlign = JUSTIFY` will emit the CSS variable and the
CJK stylesheet will simply contain no rule that reads it. Predicted result: **zero visible change**.

**Why iOS's #95 verification does not contradict this.** #95's row records "Readium-paged CJK `<p>`
compute `text-align:justify`". The most likely explanation is that the CJK book exercised there did
not declare a `zh`/`ja`/`ko` `dc:language`, so Readium fell back to the Default stylesheet. That is a
hypothesis about a different platform's evidence, so this plan does **not** rely on it — it is listed
as open question Q3 (§13) and, either way, the Android behaviour is determined by W12–W14, which were
read from the artifacts we actually ship.

**What this means for scope.** Latin books get real, visible justification on all engines. CJK books —
the motivating case in both iOS reports — very likely get nothing. That is a legitimate outcome for
this feature *provided it is stated up front and measured*, rather than discovered at Gate 5b after
the row has been called DONE. Hence **WI-0 is a measurement spike that runs before any production
code** (§9), and AC-5 is written as a *recorded observation*, not a pass/fail (§12). If WI-0 confirms
the CJK no-op, the deliverable is a tracked follow-up feature for CJK justification (custom
inter-character layout for TXT/MD; a non-ReadiumCSS injection route for EPUB) — filed in the same
session, not deferred conditionally.

**Real-books-first compliance** (AGENTS.md, binding): every CJK claim above is anchored to
`test-books/books/txt/黑暗血时代.txt` and `test-books/books/epub/道诡异仙 - 狐尾的笔.epub`, both real
books already in the repo's fixture set. No synthetic CJK fixture is used for verification. §10 names
the one narrow exception (CI unit tests cannot read the gitignored `test-books/`).

---

## 5. Surface area (file-by-file, with signatures)

### In scope

**5.1 `android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderTextStyles.kt`** — the TXT/MD seam (W2).

```kotlin
fun ReaderSettings.bodyTextStyle(): TextStyle = TextStyle(
    color = theme.ink,
    fontFamily = fontFamily.composeFontFamily(),
    fontWeight = FontWeight.Normal,
    fontSize = fontSizeSp.sp,
    lineHeight = (fontSizeSp * lineSpacing).sp,
    textAlign = TextAlign.Justify,          // feature #156 — the designed body alignment
)
```

One added property. Because W3/W4 hold, this reaches the scroll body, the paged body's phase-2
render, **and** phase-1 pagination measurement, with no host edits. The file's `Purpose:` header and
its `@coordinates-with` list must be updated in the same commit (rule 22).

**5.2 A heading-aware alignment for MD** — same file plus `.../reader/TxtReaderBody.kt`.

A Markdown *heading* is its own chunk (W20), rendered by the same per-chunk `Text`. A one-line
heading is unaffected (last-line rule), but a **wrapping** heading would be justified — visually
wrong, and the exact class iOS guarded against (`TXTChapterStartDecorator` sets an explicit `.center`
on a fresh style; #92's plan pins it with `chapterStartBodyIsJustifiedHeadingCentered`). Proposed
seam — a pure, JVM-testable function next to `bodyTextStyle()`:

```kotlin
/** Body alignment for a rendered chunk: prose justifies; a Markdown heading chunk stays natural. */
fun ReaderSettings.chunkTextAlign(isHeadingChunk: Boolean): TextAlign =
    if (isHeadingChunk) TextAlign.Start else TextAlign.Justify
```

`MarkdownRenderer` already knows whether a chunk matched `ATX` (`MarkdownRenderer.kt:64-66`); the WI
exposes that as a boolean on `MarkdownRendered` (additive field) and the MD render branch
(`TxtReaderBody.kt:973`, `:994`) applies `style = effectiveStyle.copy(textAlign = …)`. **Note**: a
`copy()` at the render site would break the W4 determinism contract if phase-1 measured a different
alignment — but alignment does not move line breaks (§11 R1), and phase-1 measures the *same*
`effectiveStyle`, so the invariant to pin is "line breaks identical under any `textAlign`", which is
test T5. This is called out explicitly for the Gate-2 auditor as the riskiest single decision in the
plan.

**5.3 `android/app/src/main/kotlin/com/vreader/app/reader/EpubPreferencesMapper.kt`** — the EPUB seam (W5).

```kotlin
fun ReaderSettings.toEpubPreferences(): EpubPreferences = EpubPreferences(
    fontSize = fontSizeSp / REFERENCE_FONT_SIZE_SP,
    fontFamily = fontFamily.toReadiumFontFamily(),
    lineHeight = lineSpacing.toDouble(),
    pageMargins = marginDp / REFERENCE_MARGIN_DP,
    backgroundColor = ReadiumColor(theme.background.toArgb()),
    textColor = ReadiumColor(theme.ink.toArgb()),
    textAlign = ReadiumTextAlign.JUSTIFY,   // feature #156
    publisherStyles = false,                // REQUIRED: gates --USER__textAlign AND --USER__lineHeight (W10/W11)
)
```

`publisherStyles = false` is **load-bearing, not cosmetic** — without it ReadiumCSS emits the
variable and no rule consumes it (W10). It is also the fix for the pre-existing #129 `lineHeight`
no-op (W11), which makes this WI a behaviour change *beyond* alignment: line spacing will start
working on EPUB, the advanced-settings heading type-scale kicks in
(`:root[style*=readium-advanced-on] h1{font-size:1.75rem!important}` …), and paragraph font sizes are
flattened to `1rem`. **That is a bigger visual delta than "justify" and must be verified and
disclosed, not smuggled in.** It is why WI-2 is its own PR with its own Gate-5 slice (§9).

Two behaviours come free and match the design: ReadiumCSS auto-enables `hyphens: auto` when
`--USER__textAlign: justify` (`ReadiumCSS-after.css`, the `textAlign: justify body{hyphens:auto}`
rule) — exactly the design's `hyphens: 'auto'` at `vreader-reader.jsx:380`; and it scopes the
override to `:not(blockquote):not(figcaption) p, body, li`, so blockquotes and figure captions keep
their own alignment.

**5.4 `android/app/src/main/kotlin/com/vreader/app/reader/Azw3DisplayCss.kt`** — the AZW3 seam (W17), **pending Q2**.

One appended rule in the existing deterministic list, mirroring iOS's `FoliateStyleMapper` leg of #95:

```kotlin
"p:not([style*=text-align]):not([align]):not([class*=center]):not([class*=right]) " +
    "{ text-align: justify !important; }",
```

The guards are the *same heuristics* iOS shipped, with iOS's own caveat carried over verbatim: they
skip the common intentional-alignment cases but not verse-as-`<p>`, blockquote inner prose, or
faux-headings with an unusual class (`20260609-feature-95-epub-justify.md:115-120`). Scoped to `<p>`
only — #95's Gate-2 round 2 dropped `li` to resolve a guard-asymmetry Medium
(`20260609-feature-95-epub-justify.md:157`); repeating that mistake would re-earn the finding.

### Files explicitly OUT of scope

- **`ReaderSettingsSheet.kt` / `ReaderSettings.kt` / `ReaderSettingsStore.kt`** — no new control, no
  new persisted field, no new store setter (§0, §1). W19 confirms nothing needs to change here.
- **PDF** (`PdfReaderActivity`) — fixed-layout raster pages, no reflow, no text alignment concept.
- **Bilingual interlinear** (`BilingualTxtAnchors.kt`, `LazyTxtChapterTextProvider.kt`) — the
  bilingual composer builds its own blocks; whether they inherit `bodyTextStyle` is a WI-1
  implementation observation, not a target. iOS took the same posture
  (`20260605-feature-92-txt-justified-text.md:87-94`: "Either outcome is acceptable — no bilingual
  regression either way"). If WI-1 finds bilingual blocks visibly regressed, that is a WI-1 blocker,
  not a silent acceptance.
- **`hyphens` for TXT/MD** — Compose exposes `ParagraphStyle.hyphens`, and hyphenation would reduce
  Latin justification gaps, but it is a separate opinionated typographic choice. iOS rejected it for
  the same reason (`20260605-feature-92-txt-justified-text.md:118-121`). EPUB gets it free from
  ReadiumCSS (§5.3) — that asymmetry is accepted and documented (§11 R5).
- **Any CJK-specific justification mechanism** — out of scope by construction; it is the follow-up
  feature WI-0 decides the need for (§4.3, §13 Q4).
- **iOS paths** — cross-platform write isolation (rule 48): this is an `android-app` change and
  touches no `vreader/`, `vreaderTests/`, `*.xcodeproj`, or `project.yml`.

---

## 6. Prior art, precedent, and rejected alternatives

**Prior art / precedent**

- **iOS #92** — single-seam change at the one builder every TXT path routes through. Android's
  `bodyTextStyle()` (W2/W3) is the exact analog, and Android is *better* positioned because
  `effectiveStyle` provably feeds both measure and render (W4).
- **iOS #95** — `EPUBPreferences.textAlign = .justify` on the Readium engine plus guarded CSS on the
  WebView engines. §5.3/§5.4 mirror both legs. #95's Gate-2 lessons (per-selector `:not()` chaining,
  `!important` being load-bearing, `p`-only scope) are pre-applied here rather than re-discovered.
- **#129** — established `bodyTextStyle()` / `toEpubPreferences()` / `foliateDisplayCss()` as the
  three per-engine mapping seams and pinned each with a JVM test
  (`ReaderSettingsStoreTest`, `EpubPreferencesMappingTest`, `Azw3DisplayCssTest`). #156 adds one
  property per seam and one assertion per test file — the cheapest possible shape.
- **The design bundle** — ten artboards specify justified body text (§1b). This is not an invented
  default.
- **Industry convention** — Apple Books, Kindle, and Readium's own reference apps justify body text
  by default; ReadiumCSS ships an auto-hyphenation companion rule for exactly that combination.

**Rejected alternatives**

| Rejected | Why |
|---|---|
| **A justify toggle in the Display sheet** (the row's literal scope) | Not designed (§1a) → rule-51 blocker; and it is *not* iOS parity — iOS explicitly rejected the same control twice (§0.1). Would ship undesigned chrome to match a feature that does not exist on iOS. |
| **A per-book alignment setting** | Strictly more UI than the rejected global toggle; also unpersisted anywhere today (W19). |
| **`body { text-align: justify }` for EPUB/AZW3** | Too broad — justifies headings and layout wrappers. #95 rejected it (`20260609-feature-95-epub-justify.md:88-89`). Readium's own scoped rule is better. |
| **Raw injected user-CSS for EPUB instead of `EpubPreferences.textAlign`** | Readium exposes a first-class typed preference (W7/W8); string-injecting CSS leaves the supported API and would still be subject to the same `advanced-on` gate. #95 rejected it for the same reason (`:93-95`). |
| **Leaving `publisherStyles` unset and hoping `textAlign` applies** | Verified impossible (W9/W10). This is the single most likely way to ship a green test and a zero-pixel change. |
| **CJK-only or script-detecting justification** | iOS rejected script detection as complexity for marginal benefit (`20260605-...:113-117`). Here it is worse than marginal — it is *inverted*: the engines cannot justify CJK at all (§4.3), so detection would gate the feature off for exactly the books that need it. |
| **Custom `AndroidView` + `TextView` with `JUSTIFICATION_MODE_INTER_CHARACTER` for CJK TXT** | Would work only on API 36+ (`minSdk = 26`), and would mean abandoning the Compose text stack that `ChunkTextMapper`, selection, highlight washes, TTS spans, find, and the #137/#138 paginator are all built on. Disproportionate for #156; it is the candidate design for the CJK follow-up feature (§13 Q4). |
| **Bundling `hyphens: auto` for TXT/MD** | Separate typographic decision; keeps this diff to one property per seam. |

---

## 7. Work-item sequencing

Four WIs, one PR each. **WI-0 gates the rest** — it is deliberately a measurement, not code, because
the plan's central risk is that the feature is a no-op on the books it was filed for (§4.3), and
because this repo has already paid for a plan that rested on an unmeasured assumption (the #139
desktop-JVM-vs-on-target 100× miss).

| WI | Tier | Scope | Est. PR size | Gate-5 requirement |
|---|---|---|---|---|
| **WI-0** | **foundational** (measurement spike; **no production code**) | On the emulator, with the two real CJK fixtures, determine empirically: (a) does `TextAlign.Justify` change CJK TXT rendering? (b) does `EpubPreferences.textAlign = JUSTIFY` + `publisherStyles = false` change the `zh-CN` EPUB's computed `text-align`? Record both in the WI's PR body. | tiny (a throwaway connected test + a `document.querySelector` evaluation; nothing merged to `main` beyond the recorded finding) | none (no behaviour change) — but the emulator run itself is the deliverable |
| **WI-1** | **behavioral** | §5.1 + §5.2 — TXT/MD justify at the `bodyTextStyle()` seam, MD heading exclusion, pagination-invariance proof. Re-run the #137/#138 paged connected suites as regression (the row calls this out). | small–medium | required: real TXT, **both** layouts (Scroll and Paged), via Library → book → Display |
| **WI-2** | **behavioral** | §5.3 — EPUB `textAlign = JUSTIFY` **+ `publisherStyles = false`**, including the disclosed side effects (line-height starts applying, advanced type scale engages). | small (2 properties) / large blast radius | required: **both** real EPUBs (`en` and `zh-CN`), scroll and paged overflow |
| **WI-3** | **behavioral**, **FINAL** — *pending Q2* | §5.4 — AZW3 foliate CSS justify. Completes the reflowable set and matches iOS #95's Foliate leg. Flips the row to `DONE`. | small | required: real AZW3 from `test-books/books/azw3/` |

If Q2 (§13) excludes AZW3, WI-2 becomes the final WI and the row's `DONE` flip moves there — but then
Android ships EPUB justified and AZW3 ragged, which is a visible inconsistency inside one app and a
parity gap against iOS #95. The recommendation is to include it.

**Why not one WI**: WI-2's `publisherStyles = false` is a much larger visual change than the other
two combined (§5.3) and deserves its own audit and its own Gate-5 slice. Bundling it with a one-line
Compose property would hide it under a small diff — the same reasoning that made #92 split WI-1/WI-2.

---

## 8. Test catalogue

JVM unit tests (fast, CI-safe) + connected tests (emulator) + Gate-5 observation. Existing files are
extended rather than created, per the rule-55 "new files are awkward" guidance.

### JVM (`android/app/src/test/kotlin/...`)

| # | Test | File | Asserts |
|---|---|---|---|
| T1 | `bodyTextStyle_isJustified` | `.../settings/TxtDisplaySettingsTest.kt` (existing) | `bodyTextStyle().textAlign == TextAlign.Justify` |
| T2 | `bodyTextStyle_keepsSizeFamilyLineHeightWithJustify` | same | adding alignment dropped no existing property (the #92 `buildPreservesLineSpacingAndFontWithJustify` analog) |
| T3 | `chunkTextAlign_headingIsNotJustified` | same | `chunkTextAlign(isHeadingChunk = true) == TextAlign.Start`; `false → Justify` |
| T4 | `markdownRendered_flagsHeadingChunks` | `.../reader/MarkdownRendererTest.kt` (existing) | `# H1` → heading flag true; a bullet chunk and a prose chunk → false; **empty chunk** → false, no crash |
| T6 | `toEpubPreferences_setsJustifyAndDisablesPublisherStyles` | `.../reader/EpubPreferencesMappingTest.kt` (existing) | `textAlign == TextAlign.JUSTIFY` **and** `publisherStyles == false` — the two are asserted **together**, because either alone is inert |
| T7 | `foliateDisplayCss_justifiesGuardedParagraphs` | `.../reader/Azw3DisplayCssTest.kt` (existing) | the emitted CSS contains the `p:not(...)` justify rule; contains no `h1..h6` justify; output stays byte-deterministic for equal settings (the file's existing contract) |
| T8 | edge matrix on T1/T6 | both | min/max font size, min/max line spacing, all 5 themes, both families → alignment is invariant (justify is orthogonal to every other setting) |

### JVM — the discriminating test

| # | Test | File | Asserts |
|---|---|---|---|
| **T5** | `lineBreaksIdenticalUnderJustify` | `.../reader/paged/ComposeLineMeasurerTest.kt` or `TxtPaginatorTest.kt` | Measure the **same** text at the **same** width with `textAlign = Start` vs `Justify` through the real measurer seam → **identical line count and identical per-line char ranges**. This is the Android port of iOS's `paginationBoundariesUnchangedByJustification` and is what protects saved reading positions, page boundaries, and the #137/#138 windowed paginator. Runs on **CJK, Latin, and mixed** input. |

### Connected (`android/app/src/androidTest/kotlin/...`, emulator)

| # | Test | File | Asserts |
|---|---|---|---|
| C1 | `txtBody_rendersJustified_scrollAndPaged` | `TxtDisplaySettingsUiTest.kt` (existing) | after opening a real TXT through the production path, the rendered body's `TextLayoutResult` reports `textAlign == Justify`, in **both** layouts |
| C2 | `mdHeading_isNotJustified` | same | a wrapping MD heading's layout reports a non-justify alignment while the following prose reports justify |
| C3 | `pagedPageBoundaries_unchanged` | `TxtPagedWindowedConnectedTest.kt` (existing, extended) | the paged index over a real book yields the same page count / boundaries as before the change (regression, per the row's explicit "re-run the #137/#138 paged connected suites") |
| C4 | `epub_computedTextAlign_isJustify` | `EpubDisplaySettingsConnectedTest.kt` (existing) | **evaluates the DOM**, not the preference object: `getComputedStyle(p).textAlign === 'justify'` on the Latin EPUB. See the "passes while wrong" note below — the existing test in this file asserts only that "navigator accepted a background color" (`:47`), which is exactly the shape that cannot catch this class. |
| C5 | `epub_cjk_computedTextAlign_observed` | same | the **same** DOM evaluation on the `zh-CN` EPUB, recorded as an **observation** (§12 AC-5), not asserted to a fixed value until WI-0 establishes the truth |
| C6 | `azw3_computedTextAlign_isJustify` | a foliate connected test (existing AZW3 suite) | same DOM evaluation through the foliate bridge |

Connected-test discipline from prior Android features (durable, learned the hard way): **one test
class per connected run** (a comma-separated `class=A,B` fast-fails with `tests=0`); connected tests
merged compile-only during earlier WIs are **unverified until actually run**, so budget a re-run pass
before any `VERIFIED` flip; never drive the emulator while an instrumentation run is in flight
(rule 52 Cause D).

### What could pass while wrong — per acceptance criterion

The brief asked for this explicitly, and it is the highest-value part of the catalogue for a
rendering feature. For each criterion: the test that goes **green on a broken implementation**, and
the assertion that actually discriminates.

| Criterion | Green-on-broken (do **not** rely on) | Discriminating assertion |
|---|---|---|
| **AC-1** TXT/MD prose is justified | `assertEquals(TextAlign.Justify, settings.bodyTextStyle().textAlign)` — passes even if no host consumes `bodyTextStyle`, and even if Compose renders it as a no-op | **C1**: read `textAlign` back off the **`TextLayoutResult` of the rendered body** on the emulator, in both layouts. Better still, the Gate-5 screenshot (§12) — a per-line right-edge x-coordinate comparison is the only thing that proves a glyph moved. |
| **AC-2** MD headings not justified | `chunkTextAlign(true) == Start` (pure function; says nothing about the render site wiring) | **C2**: a **wrapping** (≥2-line) heading in the rendered output. A one-line heading passes under *both* the correct and the broken implementation, because the last-line rule already leaves it alone — a single-line heading test is worthless here. |
| **AC-3** Paged page boundaries unchanged | "the paged suite still passes" — it would also pass if justify were silently dropped | **T5** (per-line char ranges, both alignments, CJK+Latin) **and C3** (real-book page count/boundaries). T5 is the one that fails loudly if a future Compose version ever makes justification affect breaking. |
| **AC-4** EPUB prose is justified | `assertEquals(TextAlign.JUSTIFY, prefs.textAlign)` — **this is the trap**: it passes with `publisherStyles` unset, i.e. when ReadiumCSS emits the variable and no rule consumes it (W10). It also passes on the CJK book where the rule does not exist at all (W12). | **C4**: `getComputedStyle(p).textAlign` in the WebView DOM. Pair with **T6** asserting `textAlign` **and** `publisherStyles` in one test so neither can drift alone. |
| **AC-5** CJK behaviour | Any test asserting the *setting* — every one of them passes while zero CJK glyphs move (§4.3) | **WI-0 + C5**: measured on-target against the two real CJK books, and recorded as a finding. This criterion is deliberately an **observation**, not a pass/fail (§12). |
| **AC-6** Line spacing still works on EPUB (new — WI-2 side effect) | the existing `EpubDisplaySettingsConnectedTest` asserting the navigator "accepted" a value (`:47`) — it accepts values it never renders | computed `line-height` in the DOM before vs after a line-spacing change. This is how W11 would have been caught in #129. |

The pattern is one sentence: **for a rendering feature, assert the render, not the setting.** "The
setting persisted" and "the composable recomposed" both pass without a single glyph moving.

---

## 9. Gate-5 verification plan (production reachability)

Rule 47's binding clause: a behavioral WI must be exercised through a **production entry point in a
release-configured build**, and the evidence file must name the user-visible path.

**The path (verified, W18)**: *Library → tap a book → tap centre to reveal chrome → bottom bar
"Display" (Aa) → adjust a setting → observe the body*. `ReaderBottomChrome.kt:149` renders the slot;
`ReaderActivity.kt:1071` and `TxtReaderActivity.kt:979` open the sheet. No DEBUG launcher, no
`src/debug/` source set, no direct composable invocation is used as the entry point.

Per WI: emulator (`scripts/run-android-verify.sh`, `ANDROID_SERIAL=emulator-5554`), real books from
`test-books/books/` pushed to the device, and a **screenshot** per format — because a right-edge
alignment change is a pixel fact and no semantic assertion substitutes for looking at it. The
evidence file for the final WI is `dev-docs/verification/feature-156-<YYYYMMDD>.md` per
`dev-docs/verification/SCHEMA.md`, and it must record the CJK observation (§12 AC-5) whichever way it
lands.

Operational notes carried from prior Android verifications: the connected task wipes
`/sdcard/Android/data/<pkg>/` at run end, so **re-push the fixture books every run**; clear stale
`adb shell` processes and cycle `adb kill-server/start-server` before a connected run; start the
emulator detached from a foreground call, never inside a backgrounded task.

---

## 10. Fixtures — real books first

AGENTS.md is binding here. Every verification fixture is a **real** book already in the repo:

| Purpose | Fixture |
|---|---|
| CJK TXT (the motivating case, 14 MB) | `test-books/books/txt/黑暗血时代.txt` |
| CJK EPUB (`zh-CN` → CjkHorizontal, W14) | `test-books/books/epub/道诡异仙 - 狐尾的笔.epub` |
| Latin EPUB (`en` → Default stylesheet, W15) | `test-books/books/epub/The Half Second - Li Xiaolai.epub` |
| AZW3 (WI-3) | the existing real book under `test-books/books/azw3/` |

**Stated exceptions** (the only synthetic inputs, each justified against the rule's allowed cases):

1. **JVM unit tests T1–T8** use inline string literals. Exception: *"it's a CI unit test (which can't
   read the gitignored `test-books/`)"*. These test pure mapping functions; no real-book structure is
   involved.
2. **MD** has **no real book in `test-books/`** (the fixture set is `azw3/`, `epub/`, `txt/` only).
   Exception: *"the format has no real book"*. MD verification therefore uses a small hand-written
   `.md` containing a deliberately **long, wrapping** heading plus CJK and Latin prose — the wrapping
   heading is the specific structure C2 needs and is not something a real book would reliably supply.

---

## 11. Risks + mitigations

| # | Risk | Likelihood | Mitigation |
|---|---|---|---|
| **R1** | Justification shifts line breaks → page boundaries drift → saved positions land on the wrong page | Low (justification is applied *after* line breaking in both `StaticLayout` and CSS) | **Not assumed — proven** by T5 (per-line char ranges identical, both alignments, CJK+Latin+mixed) and C3 (real-book page count). This is the iOS #92 precedent; the difference is Android's paged index is a persisted structure, so drift would be worse. |
| **R2** | **The feature is a visible no-op on CJK** — the books it was filed for | **High** (predicted by W12–W14 + W16) | WI-0 measures it **before** production code (§7); AC-5 is an observation, not a pass (§12); a CJK follow-up feature is filed in the same session if confirmed (§13 Q4). This is the plan's headline risk and it is surfaced, not buried. |
| **R3** | Paged TXT page-bottom mid-paragraph lines stay ragged (the defect that DEFERRED iOS #92 WI-2) | Unknown — Android's paged path differs structurally (§4.2) | Explicitly an **observation** in WI-1's Gate-5, not an assumption either way. If it reproduces, it is documented as a known limitation exactly as iOS did (cosmetic, one line per page) — **not** silently fixed by extending the rendered range, which is precisely what leaked off-page text into iOS's selection surface (`20260605-...:148-160`) and would be far worse on Android where paged selection/highlights/bookmarks are all live. |
| **R4** | **`publisherStyles = false` changes far more than alignment** — line-height starts applying (W11), the advanced type scale engages, paragraph font sizes flatten to `1rem` | **Certain**, by construction | WI-2 is its own PR, its own audit, its own Gate-5 slice on **both** EPUBs, with before/after screenshots. AC-6 explicitly verifies line spacing now works. The change is disclosed in the PR body as "this also fixes a latent #129 defect", not presented as a pure justify change. |
| **R5** | Cross-engine divergence: EPUB auto-hyphenates under justify, TXT/MD and AZW3 do not → Latin looks smoother on EPUB | Medium (cosmetic) | Accepted and documented, exactly as iOS accepted it (`20260609-...:121-125`). `hyphens` for the other engines is a named follow-up, deliberately unbundled (§5, out of scope). |
| **R6** | Latin justification looks gappy on short lines without hyphenation (TXT/MD, AZW3) | Medium (cosmetic) | Standard justified-without-hyphenation behaviour; matches Apple Books / Kindle defaults and the committed design. Accepted, as on iOS (`20260605-...:222`). |
| **R7** | AZW3 CSS guards are heuristics — verse-as-`<p>`, blockquote inner prose, faux-headings with unusual classes get force-justified | Medium | Carried over from #95 with its caveats intact (§5.4); Gate-5 runs on a real AZW3 with headings/epigraphs and narrows the selector if a real regression shows, before `VERIFIED`. |
| **R8** | A future Compose version changes `TextAlign.Justify` semantics (e.g. exposes inter-character) | Low, but it is a *desirable* change we would want to notice | T5 fails loudly if breaking changes; the WI-0 measurement is re-runnable and its method is recorded. |
| **R9** | Bilingual interlinear blocks inherit justify and look wrong | Low | WI-1 observes it on the real CJK TXT with bilingual on; a visible regression blocks WI-1 (it does not get accepted silently). |
| **R10** | The MD heading `copy(textAlign = …)` at the render site diverges from the phase-1 measured style (W4's determinism contract) | Low | T5 proves alignment does not affect breaking, which is exactly the invariant that makes the divergence safe; called out to the Gate-2 auditor as the riskiest single decision (§5.2). |

---

## 12. Acceptance criteria

1. **AC-1** — TXT and MD **prose** renders justified (flush right margin) in **both** Scroll and Paged
   layouts, on a real book, reached through the production Display path.
2. **AC-2** — A **wrapping** Markdown heading is **not** justified; the prose following it is.
3. **AC-3** — Paged pagination is **byte-identical** before and after: same page count, same per-page
   character ranges (T5 + C3). No saved-position drift.
4. **AC-4** — EPUB body paragraphs compute `text-align: justify` **in the DOM** on the Latin real
   EPUB, in both scroll and paged overflow, at open **and** after a live settings change.
5. **AC-5** — **CJK is measured and recorded, not promised.** The evidence file states, for both
   `黑暗血时代.txt` and `道诡异仙 - 狐尾的笔.epub`, whether justification is visibly applied, with a
   screenshot each. If it is not (the predicted outcome, §4.3), the criterion is met by the
   **recorded finding plus a filed follow-up feature** — not by a claim that CJK justifies.
6. **AC-6** — EPUB line spacing demonstrably applies after `publisherStyles = false` (computed
   `line-height` changes with the slider), and no theme/font/size/margin regression is introduced.
7. **AC-7** — AZW3 prose renders justified while headings do not (WI-3, pending Q2).
8. **AC-8** — Rule 51: zero new UI. `ReaderSettingsSheet.kt` is untouched; the Display sheet's control
   set is unchanged from `vreader-panels.jsx:61-186`.

---

## 13. Open questions the orchestrator must resolve BEFORE Gate 2

**Q1 — Scope correction (blocking).** The row specifies a Display-sheet toggle. §0 shows that premise
is false on both counts (iOS has no such control; the control is not designed). This plan proceeds on
**justify-by-default, no new UI**. Confirm — or, if a toggle is genuinely wanted, file the
`needs-design` issue immediately and unconditionally (rule 51: no "if/when"), mark the row
`BLOCKED: needs-design (#N)`, and #156 does not enter Gate 3 until the bundle lands. The row text
should be corrected either way, since it currently misstates what iOS shipped.

**Q2 — Is AZW3 in scope?** The row says "TXT/MD + EPUB". But AZW3 is the third reflowable reader, its
CSS seam already receives `ReaderSettings` (W17), iOS #95 covered the Foliate leg, and the change is
one rule plus one JVM assertion. Excluding it ships an app where EPUB is justified and AZW3 is ragged.
**Recommendation: include (WI-3).**

**Q3 — iOS #95's CJK evidence.** #95's row claims a device-verified CJK EPUB computing
`text-align: justify` on Readium. W12–W14 say that should be impossible for a publication Readium
classifies as CJK. Either the iOS book lacked a `zh` `dc:language` (most likely), or iOS's Readium
version behaves differently. This does not block #156 — the Android behaviour is determined by the
artifacts we ship — but it is worth a 10-minute check, because if iOS #95's CJK claim is unfounded
then the iOS row overstates its verification and should be annotated.

**Q4 — CJK follow-up.** If WI-0 confirms the predicted CJK no-op, a follow-up feature is needed
(inter-character justification for TXT/MD via a custom text layer on API 36+; a non-ReadiumCSS
injection route for CJK EPUB). Should that be filed pre-emptively at Gate 2, or after WI-0 returns
data? **Recommendation: file after WI-0**, so the row states a measured fact rather than a prediction
— but file it in the **same session** WI-0 lands, not "later".

**Q5 — Bump tier.** `minor` (new user-visible capability) on `android/version.properties`, tagged
`android/vX.Y.Z` (rule 40). Confirm no docs-sync trigger fires: no new service, schema, notification,
or environment key — `docs/architecture.md` and `README.md` likely need no edit, but the WI-2
`publisherStyles` behaviour change is worth one line if the architecture doc describes the EPUB
preference mapping.

---

## 14. Backward compatibility

- **No persistence change.** No new `ReaderSettings` field, no new `ReaderSettingsState` key, no new
  store setter, no DataStore migration (W19). An existing install's persisted JSON decodes unchanged.
- **No offset / locator change.** Alignment is a render-time attribute in all three engines. Backing
  text, character offsets, EPUB locators, highlights, bookmarks, notes, TTS ranges, and the find index
  are untouched — and page boundaries are proven unchanged by T5/C3 (R1).
- **No backup-format impact.** Display settings are device-local and were never backed up (#129's
  design); `annotations.json` / `collections.json` / the backup sections are unaffected.
- **No contract impact.** Nothing under `contracts/` changes; this is a rendering default, not a
  cross-platform contract (ADR-0001).
- **Existing books** re-render justified on next open. Nothing migrates.
- **The one real behaviour change beyond alignment** is WI-2's `publisherStyles = false` (R4) — EPUB
  typography will visibly shift for existing users because settings that were silently inert start
  applying. It is a fix, but it is a visible one and belongs in the PR body and the release note.

---

## 15. Revision history

- **v1 (2026-08-05)** — initial plan. Notable Gate-1 findings, all verified against source rather
  than inherited from the row:
  1. The row's "iOS ships it as a Display-sheet control" is **false** — iOS shipped justify-by-default
     and explicitly rejected the toggle as `needs-design`, twice (§0.1).
  2. The row's "reuses #129's committed Display sheet → rule-51-clean" is **false for a toggle** — the
     designed sheet (`vreader-panels.jsx:61-186`) has no alignment control (§1a). It is **true for the
     default** — ten committed artboards specify `textAlign: 'justify'` body text (§1b). Scope
     corrected accordingly; no `needs-design` filing required for the corrected scope.
  3. `publisherStyles` is never set (W9) and ReadiumCSS gates `--USER__textAlign` behind it (W10) —
     so the obvious one-line EPUB change would have shipped a green test and zero pixels moved.
  4. The same gate covers `--USER__lineHeight` (W11) — **#129's EPUB line-spacing slider is very
     likely inert today**, a pre-existing latent defect this feature incidentally fixes.
  5. ReadiumCSS **disables `text-align` for CJK publications** (W12, quoting the shipped ReadMe), and
     our real CJK EPUB declares `zh-CN` so it takes that path (W13/W14).
  6. Compose maps `TextAlign.Justify` to **inter-word** justification only (W16), which is a no-op on
     space-free CJK.
  7. (5) and (6) together mean the feature is predicted to be a **visible no-op on CJK — the case it
     was filed for**. WI-0 is a measurement spike placed *before* any production code so this is
     discovered at Gate 1/3, not at Gate 5b.
