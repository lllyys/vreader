// Purpose: feature #129 WI-4 (#110 Phase 3) — the pure `ReaderSettings → Compose TextStyle` mapping
// the TXT/MD reader body applies: font size in sp, line height = fontSize × lineSpacing (the Display
// sheet's multiplier semantics), the active theme's ink color, the chosen serif/sans family
// (VReaderFonts design approximations), and — feature #156 WI-1 — the designed JUSTIFIED body
// alignment. Pure value types (JVM-unit-testable, TxtDisplaySettingsTest).
// MD headings scale relative to this body size via MarkdownRenderer's em-relative heading SpanStyles.
//
// Key decisions:
//   • Justify is a DEFAULT, not a setting — no new control (rule 51; iOS #92/#95 took the same shape).
//   • `chunkTextAlign` keeps a Markdown heading chunk unjustified in the SCROLL body only; paged mode
//     renders a whole page slice as one Text with one paragraph alignment (a stated known limitation).
//   • Alignment is applied after line breaking, so adding it here cannot move a paged page boundary —
//     proved, not assumed, by TxtPaginatorTest + the connected TxtJustificationConnectedTest.
//
// @coordinates-with: TxtReaderActivity.kt (threads bodyTextStyle into the body Text),
//   TxtReaderBody.kt (both bodies merge this style; the scroll body applies chunkTextAlign per chunk),
//   MarkdownRenderer.kt (em-relative heading sizes use the body size as their base; `isHeadingChunk`
//   is the predicate chunkTextAlign selects on),
//   ReaderSettings.kt (the value type + clamped ranges this maps from).
package com.vreader.app.reader.settings

import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.sp
import com.vreader.app.ui.theme.VReaderFonts

/**
 * Feature #156 WI-1 — the designed body alignment (`vreader-reader.jsx:380` renders the reader body
 * `<p>` with `textAlign: 'justify'`, as do nine further committed artboards). Justify-by-DEFAULT, with
 * no control: iOS shipped the same shape in #92/#95 and explicitly rejected an alignment toggle as
 * undesigned UI, so there is no setting to mirror (rule 51 — the Display sheet's control set is
 * unchanged).
 *
 * Reach, measured not assumed: Compose maps `TextAlign.Justify` to `StaticLayout`'s
 * `JUSTIFICATION_MODE_INTER_WORD`, which distributes slack into SPACE RUNS.
 *   • Latin, in the shipped reader: 13 of 13 justifiable lines collapse from a 134px ragged spread onto
 *     a 9px band at 95.7% of the measure, with every line break unchanged.
 *   • Real CJK (`黑暗血时代.txt`), in the shipped reader: 0 of 4 justifiable lines move, 0px — space-free
 *     prose has nothing to stretch. CJK justification is OUT of scope here, recorded as a measured fact
 *     and pinned by a characterisation test so a toolchain change that fixes it fails loudly.
 * (WI-0's spike reported Latin lines landing hard on the measure rather than 95.7% of it; that gap is a
 * property of its bare composition — the shipped host merges the Material text style, which is
 * layout-affecting — and is re-probed on every connected run rather than assumed.)
 */
private val BODY_TEXT_ALIGN = TextAlign.Justify

/** The Compose [FontFamily] for a [ReaderFontFamily] (Source Serif 4 / Inter → platform serif/sans). */
fun ReaderFontFamily.composeFontFamily(): FontFamily = when (this) {
    ReaderFontFamily.Serif -> VReaderFonts.Serif
    ReaderFontFamily.Sans -> VReaderFonts.Sans
}

/**
 * The TXT/MD reader body text style for these settings: `fontSize` in sp, `lineHeight` =
 * fontSize × lineSpacing (18sp × 1.5 = 27sp at the defaults), the theme's ink, the chosen family.
 * Assumes clamped inputs (the [ReaderSettingsStore] clamps on read AND write).
 */
fun ReaderSettings.bodyTextStyle(): TextStyle = TextStyle(
    color = theme.ink,
    fontFamily = fontFamily.composeFontFamily(),
    fontWeight = FontWeight.Normal,
    fontSize = fontSizeSp.sp,
    lineHeight = (fontSizeSp * lineSpacing).sp,
    textAlign = BODY_TEXT_ALIGN,
)

/**
 * Feature #156 WI-1 — the body alignment for ONE rendered chunk in the SCROLL body: prose justifies
 * (the alignment [bodyTextStyle] already carries), a Markdown heading chunk stays natural.
 *
 * Why a heading is excluded: a one-line heading is untouched anyway (no engine justifies a paragraph's
 * last line), but a heading long enough to WRAP would be stretched flush on both edges and read as body
 * prose. iOS guarded the same class in #92 (`TXTChapterStartDecorator` sets an explicit `.center`).
 *
 * Scope is scroll-only by construction: paged mode renders a whole page slice — potentially several
 * chunks — as ONE `Text`, which carries a single paragraph alignment, so a paged page containing a
 * wrapping heading justifies it (plan §5.2b, a stated known limitation pinned by a characterisation
 * test). Alignment does not move line breaks, so applying this per chunk cannot desynchronise the
 * paginator's phase-1 measurement from the phase-2 render.
 *
 * Deliberately a plain function rather than the plan's `ReaderSettings.chunkTextAlign` receiver form:
 * the scroll render seam ([com.vreader.app.reader.TxtBody]) receives a `TextStyle`, never a
 * `ReaderSettings`, and the proposed receiver was unused — threading settings in purely to satisfy the
 * signature would widen the change for no behaviour.
 */
fun chunkTextAlign(isHeadingChunk: Boolean): TextAlign =
    if (isHeadingChunk) TextAlign.Start else BODY_TEXT_ALIGN
