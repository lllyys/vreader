// Purpose: feature #131 WI-7a — the private sub-components of the bilingual setup sheet
// (BilingualSetupSheet.kt), split out to keep each file under the ~300-line bar (rule 50 §9): the
// preview strip, the 3-column language grid, the Paragraph-only Granularity control (round-4 H3),
// the Translation-engine strip (configured/unconfigured), the section label, and the per-language
// preview samples. Each is a faithful reproduction of the corresponding piece of
// `vreader-bilingual.jsx` (rule 51). `internal` so ONLY BilingualSetupSheetContent composes them.
//
// @coordinates-with: BilingualSetupSheet.kt, BilingualLanguages.kt, ReaderTheme.kt,
//   dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx
package com.vreader.app.bilingual

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.reader.settings.ReaderTheme
import com.vreader.app.ui.theme.VReaderFonts

/** The design's BilingualPreview: an English source line + a target-language translation with an accent left rule. */
@Composable
internal fun BilingualPreview(theme: ReaderTheme, language: BilingualLanguage) {
    val ink = theme.ink
    val sub = theme.ink.copy(alpha = 0.6f)
    val isRtl = language.script == BilingualScript.rtl
    val accentBorder = theme.accent.copy(alpha = 0.53f)
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(if (theme.isDark) Color.White.copy(alpha = 0.04f) else Color.White)
            .border(0.5.dp, theme.ink.copy(alpha = 0.10f), RoundedCornerShape(12.dp))
            .padding(14.dp)
            .testTag("bilingual-preview"),
    ) {
        Text(
            "It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.",
            color = ink, fontFamily = VReaderFonts.Serif, fontSize = 14.sp, lineHeight = (14 * 1.45).sp,
        )
        Box(
            Modifier
                .fillMaxWidth()
                .padding(top = 8.dp)
                .drawBehind {
                    val bw = 2.dp.toPx()
                    val x = if (isRtl) size.width - bw / 2f else bw / 2f
                    drawLine(accentBorder, Offset(x, 0f), Offset(x, size.height), bw)
                }
                .padding(start = if (isRtl) 0.dp else 14.dp, end = if (isRtl) 14.dp else 0.dp),
        ) {
            Text(
                PREVIEW_SAMPLES[language.key] ?: PREVIEW_SAMPLES.getValue("Chinese"),
                color = sub, fontFamily = VReaderFonts.Serif, fontSize = 13.sp, lineHeight = (13 * 1.55).sp,
                style = TextStyle(
                    textDirection = if (isRtl) TextDirection.Rtl else TextDirection.Ltr,
                    textAlign = if (isRtl) TextAlign.Right else TextAlign.Left,
                ),
            )
        }
    }
}

/**
 * The 3-column language grid over BILINGUAL_LANGS (design's `gridTemplateColumns: repeat(3,1fr)`).
 * A plain non-scrolling `Column` of 3-wide `Row`s (NOT a fixed-height `LazyVerticalGrid`) so every
 * tile composes + lays out fully inside the scrolling sheet — nothing clips at any font scale.
 */
@Composable
internal fun LanguageGrid(theme: ReaderTheme, selected: BilingualLanguage, onSelect: (BilingualLanguage) -> Unit) {
    Column(
        Modifier.fillMaxWidth().padding(top = 10.dp).testTag("bilingual-language-grid"),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        BilingualLanguages.ALL.chunked(3).forEach { rowLangs ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                rowLangs.forEach { lang ->
                    LanguageTile(theme = theme, lang = lang, active = lang.key == selected.key, onSelect = onSelect, modifier = Modifier.weight(1f))
                }
                // Pad a short final row so the tiles stay a fixed 1/3 width (the design's grid columns).
                repeat(3 - rowLangs.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

/** One language tile — the design's glyph-square + label button (selected accent). */
@Composable
private fun LanguageTile(theme: ReaderTheme, lang: BilingualLanguage, active: Boolean, onSelect: (BilingualLanguage) -> Unit, modifier: Modifier = Modifier) {
    val ink = theme.ink
    val tileBg = when {
        active && theme.isDark -> theme.accent.copy(alpha = 0.15f)
        active -> theme.accent.copy(alpha = 0.08f)
        theme.isDark -> Color.White.copy(alpha = 0.04f)
        else -> Color.White
    }
    Row(
        modifier
            .clip(RoundedCornerShape(12.dp))
            .background(tileBg)
            .then(
                if (active) Modifier.border(1.5.dp, theme.accent, RoundedCornerShape(12.dp))
                else Modifier.border(0.5.dp, theme.ink.copy(alpha = 0.14f), RoundedCornerShape(12.dp))
            )
            .clickable { onSelect(lang) }
            .testTag("bilingual-lang-${lang.key}")
            .padding(horizontal = 10.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(
            Modifier
                .size(22.dp)
                .clip(RoundedCornerShape(6.dp))
                .background(if (active) theme.accent else theme.ink.copy(alpha = if (theme.isDark) 0.08f else 0.06f)),
            contentAlignment = Alignment.Center,
        ) {
            Text(lang.glyph, color = if (active) Color.White else ink, fontFamily = VReaderFonts.Serif, fontSize = if (lang.script == BilingualScript.cjk) 13.sp else 11.sp, fontWeight = FontWeight.Bold)
        }
        Text(lang.key, color = ink, fontSize = 12.sp, fontWeight = if (active) FontWeight.SemiBold else FontWeight.Medium, maxLines = 1)
    }
}

/**
 * The Granularity control — Paragraph ONLY in v1 (round-4 H3). The design's segmented control shows
 * a Sentence option too, but the v1 render/cache path is paragraph-exclusive; per the plan the
 * Sentence option is NOT rendered in v1 (a documented divergence, sentence design-gated). We render
 * the SINGLE depicted Paragraph segment (selected), matching the design's paragraph tab styling.
 */
@Composable
internal fun ParagraphOnlyGranularity(theme: ReaderTheme) {
    val ink = theme.ink
    val sub = theme.ink.copy(alpha = 0.6f)
    val trackBg = theme.ink.copy(alpha = if (theme.isDark) 0.06f else 0.05f)
    val selectedFill = if (theme.isDark) Color(0xFF3A3530) else Color.White
    Row(
        Modifier
            .fillMaxWidth()
            .padding(top = 10.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(trackBg)
            .padding(3.dp)
            .testTag("bilingual-granularity"),
    ) {
        Column(
            Modifier
                .weight(1f)
                .clip(RoundedCornerShape(10.dp))
                .background(selectedFill)
                .testTag("granularity-paragraph")
                .padding(vertical = 10.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text("Paragraph", color = ink, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            Text("Translate after each ¶", color = sub, fontSize = 10.5.sp, modifier = Modifier.padding(top = 1.dp))
        }
    }
}

/**
 * The Translation-engine strip. Configured: "Claude · with this book's context" + a "Change…" pill.
 * Unconfigured: "No AI provider configured" + "Bilingual mode needs an AI provider to translate." +
 * an accent "Set up" pill. Both fire [onSetUp] (WI-9 routes it to the AI-Providers sheet).
 */
@Composable
internal fun EngineStrip(theme: ReaderTheme, aiConfigured: Boolean, onSetUp: () -> Unit) {
    val ink = theme.ink
    val sub = theme.ink.copy(alpha = 0.6f)
    val stripBg = if (aiConfigured) {
        if (theme.isDark) Color.White.copy(alpha = 0.04f) else Color.White
    } else {
        theme.accent.copy(alpha = 0.06f)
    }
    val stripBorder = if (aiConfigured) theme.ink.copy(alpha = 0.10f) else theme.accent.copy(alpha = 0.33f)
    Row(
        Modifier
            .fillMaxWidth()
            .padding(top = 8.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(stripBg)
            .border(0.5.dp, stripBorder, RoundedCornerShape(12.dp))
            .padding(horizontal = 14.dp, vertical = 12.dp)
            .testTag("bilingual-engine-strip"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // The design's gradient sparkle avatar (configured) / muted disc (unconfigured). We render a
        // solid accent disc for configured, a muted disc for unconfigured (the depicted two states).
        Box(
            Modifier
                .size(28.dp)
                .clip(RoundedCornerShape(14.dp))
                .background(if (aiConfigured) theme.accent else theme.ink.copy(alpha = 0.08f)),
            contentAlignment = Alignment.Center,
        ) {
            Text("✦", color = if (aiConfigured) Color.White else sub, fontSize = 13.sp)
        }
        Column(Modifier.weight(1f)) {
            Text(
                if (aiConfigured) "Claude · with this book's context" else "No AI provider configured",
                color = ink, fontSize = 13.5.sp, fontWeight = FontWeight.SemiBold,
                modifier = Modifier.testTag("engine-headline"),
            )
            Text(
                if (aiConfigured) "Translations cached per paragraph, one page ahead." else "Bilingual mode needs an AI provider to translate.",
                color = sub, fontSize = 11.5.sp, modifier = Modifier.padding(top = 1.dp),
            )
        }
        val ctaBg = if (aiConfigured) theme.ink.copy(alpha = if (theme.isDark) 0.08f else 0.06f) else theme.accent
        val ctaFg = if (aiConfigured) ink else Color.White
        Box(
            Modifier
                .clip(RoundedCornerShape(100.dp))
                .background(ctaBg)
                .clickable(onClick = onSetUp)
                .testTag("engine-cta")
                .padding(horizontal = 11.dp, vertical = 5.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(if (aiConfigured) "Change…" else "Set up", color = ctaFg, fontSize = 11.5.sp, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
internal fun BilingualSectionLabel(text: String, color: Color, topPadding: Dp = 0.dp) {
    Text(
        text,
        Modifier.padding(top = topPadding),
        color = color, fontFamily = VReaderFonts.Sans, fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
    )
}

/** The design's per-language preview samples (BilingualPreview `samples`). */
internal val PREVIEW_SAMPLES: Map<String, String> = mapOf(
    "Chinese" to "凡是有钱的单身汉，总想娶位太太，这已经成了一条举世公认的真理。",
    "Japanese" to "相当な財産を持っている独身の男性は妻を欲しがっているに違いない、というのは世間一般に認められた真理である。",
    "Korean" to "재산이 많은 독신 남성에게 아내가 필요하다는 것은 누구나 인정하는 진리이다.",
    "Spanish" to "Es una verdad universalmente reconocida que un hombre soltero en posesión de una buena fortuna necesita una esposa.",
    "French" to "C'est une vérité universellement reconnue qu'un homme célibataire possédant une bonne fortune doit avoir besoin d'une épouse.",
    "German" to "Es ist eine allgemein anerkannte Wahrheit, dass ein lediger Mann im Besitz eines schönen Vermögens nach einer Frau verlangen muss.",
    "Italian" to "È una verità universalmente riconosciuta che uno scapolo in possesso di un buon patrimonio debba volere una moglie.",
    "Arabic" to "إنها حقيقة معترف بها عالميًا أن الرجل الأعزب الذي يملك ثروة جيدة لا بد أن يكون بحاجة إلى زوجة.",
    "Russian" to "Общеизвестно, что холостой мужчина, обладающий приличным состоянием, должен иметь желание жениться.",
)
