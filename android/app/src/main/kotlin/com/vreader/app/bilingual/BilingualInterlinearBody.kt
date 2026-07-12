// Purpose: feature #131 WI-7a — the Compose render surface for the TXT/MD interlinear translation
// slot (the muted, NON-registered translation child that sits below its source chunk INSIDE the
// anchor chunk's wrapping `Column`, per the round-4 H2 render contract). WI-8 wires
// [BilingualTranslationSlot] into `TxtReaderActivity`'s `items(count = chunkCount, key = { it })`
// loop as the sibling child after the (byte-unchanged, still-registered) source `Text`, so
// lazy-index == chunk-index is preserved and only ONE lazy item exists per chunk.
//
// Faithful to the design's `BilingualPageContent` translation `<p>` (vreader-bilingual.jsx:200–277)
// + the offline bundle's loading/ghost states (vreader-bilingual-offline.jsx): a shared "slot shell"
// (accent left-border, indent) that every state inherits so the translation-slot rhythm is preserved;
// muted `t.sub` color; `fontSize*0.88`; RTL border/direction for Arabic. The content varies by
// [BilingualRenderState.phase]:
//   - Loaded     → the translated text(s), muted (design translation `<p>`).
//   - Loading    → a swept-gradient shimmer bar + "Translating chapter… N%" (offline bundle
//                  BilingualLoadingSlot copy per plan §210).
//   - Error      → the DEPICTED ghost slot (dim accent border + dashed line, NO inline copy —
//                  the offline bundle's `BilingualGhostSlot`). The PAGE-LEVEL Retry affordance
//                  (`BilingualPageBanner` "back online") is a chrome concern wired by WI-8; an
//                  INLINE per-slot Retry is NOT depicted anywhere, so it is NOT invented here
//                  (rule 51 — see the WI-7a HANDOFF's design-gate note).
//   - SourceOnly → NOTHING (silent source-only fallback, iOS Decision 2; the slot is not drawn).
//
// The translation is a PLAIN muted `Text`: it carries NO source-chunk registration (WI-8 owns the
// `registerChunk` loop; the translation simply never calls it), so it is never a source-selection
// anchor — while STAYING readable by TalkBack. It does NOT consume pointer events, so a swipe starting
// on the translation still scrolls the reader's LazyColumn. The long-press gesture-exclusion for the
// ancestor detector's nearest-source-chunk FALLBACK (`TxtSelectionController.hitAt`, :47–53) is WI-8's
// contracted responsibility (plan §280 — a source-side exclusion that suppresses selection while
// leaving scroll + accessibility intact). Pure function of state (rule 50 §12). NOT the EPUB render
// surface (WI-7b).
//
// @coordinates-with: BilingualRenderState.kt, BilingualLanguages.kt, ReaderTheme.kt,
//   reader/TxtReaderActivity.kt (WI-8), dev-docs/plans/…-feature-131-…interlinear.md (WI-7a §210)
package com.vreader.app.bilingual

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.material3.Text
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.platform.testTag
import com.vreader.app.reader.settings.ReaderTheme
import com.vreader.app.ui.theme.VReaderFonts

/**
 * The interlinear translation slot for ONE anchor chunk — the design's translation `<p>` and its
 * loading/ghost/source-only variants, wrapped in the shared slot shell (accent left-border + indent
 * per `BilingualPageContent`). Renders NOTHING when [state] is [BilingualRenderPhase.SourceOnly]
 * (silent source-only fallback) or when there is genuinely nothing to draw.
 *
 * @param state the host-neutral render state for the anchor chunk's translation unit.
 * @param theme the active reader theme (the design's `theme={t}` surface — light+dark).
 * @param language the target language (drives CJK font + RTL border/direction, per the design).
 * @param sourceFontSizeSp the source chunk's font size in sp; the translation renders at 0.88× it.
 * @param sourceFontFamily the ACTIVE source font family; the translation inherits it EXCEPT for
 *   CJK/RTL targets, which force the serif fallback (matching the design's per-script `translatedFF`).
 * @param modifier applied to the slot root.
 */
@Composable
fun BilingualTranslationSlot(
    state: BilingualRenderState,
    theme: ReaderTheme,
    language: BilingualLanguage,
    sourceFontSizeSp: Float,
    modifier: Modifier = Modifier,
    sourceFontFamily: FontFamily = VReaderFonts.Serif,
) {
    when (val phase = state.phase) {
        BilingualRenderPhase.SourceOnly -> Unit // silent source-only fallback (iOS Decision 2)
        BilingualRenderPhase.Loaded -> {
            val segments = state.segments.orEmpty().filter { it.isNotBlank() }
            // An empty/whitespace-only translation is treated as source-only (nothing to draw).
            if (segments.isEmpty()) return
            SlotShell(theme, language, sourceFontSizeSp, modifier.testTag("bilingual-translation-slot")) {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    segments.forEachIndexed { i, seg ->
                        TranslationText(seg, theme, language, sourceFontSizeSp, sourceFontFamily, "bilingual-translation-text-$i")
                    }
                }
            }
        }
        is BilingualRenderPhase.Loading -> {
            SlotShell(theme, language, sourceFontSizeSp, modifier.testTag("bilingual-loading-slot")) {
                LoadingContent(theme, sourceFontSizeSp, phase.percent)
            }
        }
        // Error → the DEPICTED ghost slot (dim border + dashed line, NO inline copy/Retry — rule 51).
        BilingualRenderPhase.Error -> {
            SlotShell(theme, language, sourceFontSizeSp, modifier.testTag("bilingual-error-slot"), dim = true) {
                GhostContent(theme, sourceFontSizeSp)
            }
        }
    }
}

/**
 * The shared translation-slot shell: an accent left-border (or right, RTL) + indent, exactly the
 * design's `BilingualSlot` (vreader-bilingual-offline.jsx:53). [dim] uses the design's `33α` (ghost)
 * instead of the `55α` accent so the eye reads "slot is here" even when content is unavailable. Every
 * state inherits this so the slot rhythm is stable.
 */
@Composable
private fun SlotShell(
    theme: ReaderTheme,
    language: BilingualLanguage,
    sourceFontSizeSp: Float,
    modifier: Modifier = Modifier,
    dim: Boolean = false,
    content: @Composable () -> Unit,
) {
    val isRtl = language.script == BilingualScript.rtl
    val accentBorder = theme.accent.copy(alpha = if (dim) 0.33f else 0.55f)
    val indentDp = (sourceFontSizeSp * 0.7f).dp // design's `fontSize*0.7`
    val borderWidthPx = with(LocalDensity.current) { 2.dp.toPx() }
    Box(
        modifier
            .fillMaxWidth()
            .padding(top = 6.dp) // design's `margin: '6px 0 0'`
            .drawBehind {
                val x = if (isRtl) size.width - borderWidthPx / 2f else borderWidthPx / 2f
                drawLine(color = accentBorder, start = Offset(x, 0f), end = Offset(x, size.height), strokeWidth = borderWidthPx)
            }
            .padding(start = if (isRtl) 0.dp else indentDp, end = if (isRtl) indentDp else 0.dp),
    ) {
        content()
    }
}

/** The muted translation text — the design's translation `<p>` (t.sub, 0.88×, per-script font, RTL). */
@Composable
private fun TranslationText(
    text: String,
    theme: ReaderTheme,
    language: BilingualLanguage,
    sourceFontSizeSp: Float,
    sourceFontFamily: FontFamily,
    testTag: String,
) {
    val sub = theme.ink.copy(alpha = 0.6f) // the design's `t.sub`
    val isCjkOrRtl = language.script == BilingualScript.cjk || language.script == BilingualScript.rtl
    // Match the design's `translatedFF`: CJK/RTL → the (serif) CJK fallback; otherwise inherit the
    // active source family so a sans reader keeps sans for Latin/Cyrillic translations.
    val fontFamily = if (isCjkOrRtl) VReaderFonts.Serif else sourceFontFamily
    val isRtl = language.script == BilingualScript.rtl
    Text(
        text = text,
        // The translation is a PLAIN muted `Text`: it is "non-registered" purely by NOT calling the
        // source-selection `registerChunk` (WI-8 owns the chunk loop), so it is never a selection
        // anchor — no semantics clearing is needed, and clearing would hide the translation from
        // TalkBack (round-3 Medium). We also do NOT consume pointer/drag events, so a swipe starting
        // on the translation still scrolls the reader's LazyColumn (round-2 High). The long-press
        // gesture-exclusion for the ancestor detector's nearest-source-chunk FALLBACK
        // (`TxtSelectionController.hitAt`, :47–53) is WI-8's contracted responsibility (plan §280): a
        // source-side gate that suppresses selection while leaving scroll + accessibility intact.
        modifier = Modifier
            .fillMaxWidth()
            .testTag(testTag),
        color = sub,
        fontFamily = fontFamily,
        fontSize = (sourceFontSizeSp * 0.88f).sp, // design's `fontSize*0.88`
        lineHeight = (sourceFontSizeSp * 0.88f * 1.55f).sp, // design's `lineHeight: 1.55`
        style = TextStyle(
            textDirection = if (isRtl) TextDirection.Rtl else TextDirection.Ltr,
            textAlign = if (isRtl) TextAlign.Right else TextAlign.Left,
        ),
    )
}

/**
 * The loading state — the offline bundle's `BilingualLoadingSlot`: a swept-gradient shimmer bar +
 * "Translating chapter… N%" (plan §210 copy). The animated sweep offset is read in the DRAW phase
 * (a `Brush` recomputed via `drawBehind`), so the shimmer animates without recomposing the slot.
 */
@Composable
private fun LoadingContent(theme: ReaderTheme, sourceFontSizeSp: Float, percent: Int) {
    val sub = theme.ink.copy(alpha = 0.6f)
    val base = theme.ink.copy(alpha = if (theme.isDark) 0.06f else 0.05f)
    val hi = theme.ink.copy(alpha = if (theme.isDark) 0.14f else 0.12f)
    val transition = rememberInfiniteTransition(label = "bilingual-shimmer")
    // A single 0..1 sweep phase; read ONLY inside drawBehind (draw phase) → no recomposition.
    val phase = transition.animateFloat(
        initialValue = 0f, targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1400), RepeatMode.Restart),
        label = "bilingual-shimmer-phase",
    )
    Column(verticalArrangement = Arrangement.spacedBy(5.dp), modifier = Modifier.padding(vertical = 3.dp)) {
        Text(
            text = "Translating chapter… $percent%",
            modifier = Modifier.testTag("bilingual-loading-label"),
            color = sub, fontFamily = VReaderFonts.Sans, fontSize = (sourceFontSizeSp * 0.72f).sp, fontWeight = FontWeight.Medium,
        )
        listOf(0.92f, 0.54f).forEach { widthFraction ->
            Box(
                Modifier
                    .fillMaxWidth(widthFraction)
                    .height((sourceFontSizeSp * 0.7f).dp)
                    .drawBehind {
                        val w = size.width
                        val start = (phase.value * 2f - 1f) * w
                        drawRoundRect(
                            brush = Brush.horizontalGradient(listOf(base, hi, base), startX = start, endX = start + w),
                            cornerRadius = androidx.compose.ui.geometry.CornerRadius(3.dp.toPx()),
                        )
                    },
            )
        }
    }
}

/**
 * The DEPICTED ghost slot content (offline bundle `BilingualGhostSlot`): a single dim dashed line at
 * one translation-line height, NO copy. The page-level banner (WI-8 chrome) carries the explanation +
 * the depicted Retry — the per-slot slot never invents copy or a button (rule 51).
 */
@Composable
private fun GhostContent(theme: ReaderTheme, sourceFontSizeSp: Float) {
    val dash = theme.ink.copy(alpha = if (theme.isDark) 0.16f else 0.18f)
    Box(
        Modifier
            .fillMaxWidth()
            .height((sourceFontSizeSp * 0.88f * 1.55f).dp) // one translation line
            .testTag("bilingual-ghost")
            .drawBehind {
                val y = size.height / 2f
                drawLine(
                    color = dash, start = Offset(0f, y), end = Offset(size.width, y), strokeWidth = 1.dp.toPx(),
                    pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 6f)),
                )
            },
    )
}
