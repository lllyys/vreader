// Purpose: feature #129 WI-2 (#110 Phase 3), extended by feature #137 WI-2 — the designed "Display"
// settings sheet (vreader-panels.jsx ReaderSettingsSheet): a Theme 5-swatch row, a Layout (Paged/
// Scroll) segmented toggle, a Font serif/sans toggle, and Size / Line-spacing / Margin sliders. The
// sheet renders in the ACTIVE theme's colors (the design's `theme={t}` surface), so Dark/OLED/Photo
// look right. Pure function of [ReaderSettings] + callbacks; the content is extracted
// ([ReaderSettingsSheetContent]) for direct UI testing (the #127 precedent). Design order is Theme ·
// Layout · Font · Size · Line-spacing · Margin; Brightness (device-brightness) is omitted per #129
// scope (a tracked follow-up). The Layout toggle (#137 WI-2) reports selection via [onLayout] — the
// host threads it to ReaderSettingsStore.setLayout, mirroring the Theme control's onTheme wiring.
package com.vreader.app.reader.settings

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.ui.theme.VReaderFonts
import kotlin.math.roundToInt

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReaderSettingsSheet(
    settings: ReaderSettings,
    onTheme: (ReaderTheme) -> Unit,
    onLayout: (ReaderLayout) -> Unit,
    onFontFamily: (ReaderFontFamily) -> Unit,
    onFontSize: (Float) -> Unit,
    onLineSpacing: (Float) -> Unit,
    onMargin: (Float) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = settings.theme.background,   // the sheet renders in the active theme
        modifier = Modifier.testTag("display-sheet"),
    ) {
        ReaderSettingsSheetContent(settings, onTheme, onLayout, onFontFamily, onFontSize, onLineSpacing, onMargin)
    }
}

/** The sheet content (extracted for direct UI testing). Colors derive from the active [ReaderSettings.theme]. */
@Composable
fun ReaderSettingsSheetContent(
    settings: ReaderSettings,
    onTheme: (ReaderTheme) -> Unit,
    onLayout: (ReaderLayout) -> Unit,
    onFontFamily: (ReaderFontFamily) -> Unit,
    onFontSize: (Float) -> Unit,
    onLineSpacing: (Float) -> Unit,
    onMargin: (Float) -> Unit,
) {
    val theme = settings.theme
    val ink = theme.ink
    val sub = theme.ink.copy(alpha = 0.6f)
    val accent = theme.accent
    val sliderColors = SliderDefaults.colors(thumbColor = accent, activeTrackColor = accent, inactiveTrackColor = ink.copy(alpha = 0.18f))

    Column(Modifier.background(theme.background).padding(horizontal = 18.dp).testTag("display-sheet-content")) {
        Text(
            "Display",
            Modifier.padding(bottom = 14.dp),
            color = ink, fontFamily = VReaderFonts.Serif, fontSize = 18.sp, fontWeight = FontWeight.SemiBold,
        )

        SectionLabel("Theme", sub)
        Row(Modifier.fillMaxWidth().padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            ReaderTheme.entries.forEach { swatch ->
                ThemeSwatch(swatch, selected = theme == swatch, ringColor = accent, labelColor = sub, onClick = { onTheme(swatch) }, modifier = Modifier.weight(1f))
            }
        }

        SectionLabel("Layout", sub, topPadding = 22.dp)
        LayoutSegmentedToggle(current = settings.layout, isDark = theme.isDark, ink = ink, onSelect = onLayout)

        SectionLabel("Font", sub, topPadding = 22.dp)
        FontSegmentedToggle(selected = settings.fontFamily, isDark = theme.isDark, ink = ink, onSelect = onFontFamily)

        SectionLabel("Size", sub, topPadding = 22.dp)
        Slider(
            value = settings.fontSizeSp,
            onValueChange = { onFontSize(it.roundToInt().toFloat()) },
            valueRange = ReaderSettings.MIN_FONT_SIZE..ReaderSettings.MAX_FONT_SIZE,
            colors = sliderColors,
            modifier = Modifier.testTag("size-slider"),
        )

        SectionLabel("Line spacing", sub, topPadding = 6.dp)
        Slider(
            value = settings.lineSpacing,
            onValueChange = onLineSpacing,
            valueRange = ReaderSettings.MIN_LINE_SPACING..ReaderSettings.MAX_LINE_SPACING,
            colors = sliderColors,
            modifier = Modifier.testTag("spacing-slider"),
        )

        SectionLabel("Margin", sub, topPadding = 6.dp)
        Slider(
            value = settings.marginDp,
            onValueChange = onMargin,
            valueRange = ReaderSettings.MIN_MARGIN..ReaderSettings.MAX_MARGIN,
            colors = sliderColors,
            modifier = Modifier.testTag("margin-slider").padding(bottom = 24.dp),
        )
    }
}

@Composable
private fun SectionLabel(text: String, color: Color, topPadding: Dp = 0.dp) {
    Text(
        text,
        Modifier.padding(top = topPadding),
        color = color, fontFamily = VReaderFonts.Sans, fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
    )
}

/** A theme swatch: the theme's background with a serif "Aa" in its ink; the selected one gets an accent ring. */
@Composable
private fun ThemeSwatch(
    theme: ReaderTheme,
    selected: Boolean,
    ringColor: Color,
    labelColor: Color,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier.testTag("theme-${theme.name}").clickable { onClick() }, horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            Modifier
                .fillMaxWidth()
                .aspectRatio(1f)
                .clip(RoundedCornerShape(12.dp))
                .background(theme.background)
                .then(
                    if (selected) Modifier.border(2.5.dp, ringColor, RoundedCornerShape(12.dp))
                    else Modifier.border(0.5.dp, theme.ink.copy(alpha = 0.18f), RoundedCornerShape(12.dp))
                ),
            contentAlignment = Alignment.Center,
        ) {
            Text("Aa", color = theme.ink, fontFamily = VReaderFonts.Serif, fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
        }
        Text(
            theme.displayName,
            Modifier.padding(top = 6.dp),
            color = labelColor, fontSize = 11.sp,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
        )
    }
}

/**
 * The Layout Paged/Scroll segmented toggle (feature #137 WI-2) — the same segmented-track shape as
 * [FontSegmentedToggle] (the design's `t.isDark ? '#3a3530' : '#fff'` selected fill), each segment a
 * [LayoutGlyph] pictogram + its label (vreader-panels.jsx `:112`/`:197`). Each segment carries the
 * `selected` semantics flag so the current [ReaderSettings.layout] reads back as the chosen segment.
 */
@Composable
private fun LayoutSegmentedToggle(current: ReaderLayout, isDark: Boolean, ink: Color, onSelect: (ReaderLayout) -> Unit) {
    val trackBg = ink.copy(alpha = if (isDark) 0.06f else 0.05f)
    val selectedFill = if (isDark) Color(0xFF3A3530) else Color.White
    Row(
        Modifier.fillMaxWidth().padding(top = 10.dp).clip(RoundedCornerShape(12.dp)).background(trackBg).padding(3.dp),
        horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        // Design order: Paged then Scroll.
        listOf(ReaderLayout.Paged to "Paged", ReaderLayout.Scroll to "Scroll").forEach { (layout, label) ->
            val isOn = layout == current
            Row(
                Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(10.dp))
                    .background(if (isOn) selectedFill else Color.Transparent)
                    .clickable { onSelect(layout) }
                    .testTag("layout-${layout.name.lowercase()}")
                    .semantics { selected = isOn }
                    .padding(vertical = 10.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                LayoutGlyph(layout = layout, color = ink)
                Text(label, color = ink, fontFamily = VReaderFonts.Sans, fontSize = 14.sp, fontWeight = if (isOn) FontWeight.SemiBold else FontWeight.Medium)
            }
        }
    }
}

/**
 * The inline Paged/Scroll pictogram (vreader-panels.jsx `LayoutGlyph` `:197`): paged = a two-page
 * open book (two ruled rectangles), scroll = a single stacked-lines page with side scroll chevrons.
 * A 16×14 viewBox mapped to Compose draw ops in the [color] ink.
 */
@Composable
private fun LayoutGlyph(layout: ReaderLayout, color: Color) {
    Canvas(Modifier.size(width = 16.dp, height = 14.dp).testTag("layout-glyph-${layout.name.lowercase()}")) {
        val sx = size.width / 16f
        val sy = size.height / 14f
        fun px(x: Float) = x * sx
        fun py(y: Float) = y * sy
        val stroke1_2 = 1.2f * sx
        val stroke0_8 = 0.8f * sx
        val faint = color.copy(alpha = 0.55f)
        if (layout == ReaderLayout.Paged) {
            // Two page rectangles (the open-book spread).
            drawRoundRect(
                color = color, topLeft = Offset(px(0.5f), py(1.5f)),
                size = Size(px(6.5f), py(11f)), cornerRadius = CornerRadius(px(0.5f)),
                style = Stroke(width = stroke1_2),
            )
            drawRoundRect(
                color = color, topLeft = Offset(px(9f), py(1.5f)),
                size = Size(px(6.5f), py(11f)), cornerRadius = CornerRadius(px(0.5f)),
                style = Stroke(width = stroke1_2),
            )
            // Faint text lines on each page.
            listOf(
                Triple(2f, 5f, 4f), Triple(2f, 7.5f, 4f), Triple(2f, 10f, 3f),
                Triple(10.5f, 5f, 4f), Triple(10.5f, 7.5f, 4f), Triple(10.5f, 10f, 3f),
            ).forEach { (x, y, w) ->
                drawLine(faint, Offset(px(x), py(y)), Offset(px(x + w), py(y)), stroke0_8)
            }
        } else {
            // Single scrolling page.
            drawRoundRect(
                color = color, topLeft = Offset(px(2.5f), py(0.5f)),
                size = Size(px(11f), py(13f)), cornerRadius = CornerRadius(px(1f)),
                style = Stroke(width = stroke1_2),
            )
            // Text lines.
            val stroke0_9 = 0.9f * sx
            listOf(Triple(5f, 3f, 6f), Triple(5f, 5.5f, 6f), Triple(5f, 8f, 6f), Triple(5f, 10.5f, 4f)).forEach { (x, y, w) ->
                drawLine(color, Offset(px(x), py(y)), Offset(px(x + w), py(y)), stroke0_9)
            }
            // Scroll chevrons on both sides.
            val chevron = color.copy(alpha = 0.45f)
            val strokeChevron = 1f * sx
            drawLine(chevron, Offset(px(0.7f), py(4f)), Offset(px(2.3f), py(5.6f)), strokeChevron, cap = StrokeCap.Round)
            drawLine(chevron, Offset(px(0.7f), py(10f)), Offset(px(2.3f), py(8.4f)), strokeChevron, cap = StrokeCap.Round)
            drawLine(chevron, Offset(px(15.3f), py(4f)), Offset(px(13.7f), py(5.6f)), strokeChevron, cap = StrokeCap.Round)
            drawLine(chevron, Offset(px(15.3f), py(10f)), Offset(px(13.7f), py(8.4f)), strokeChevron, cap = StrokeCap.Round)
        }
    }
}

/** The Font serif/sans segmented toggle — dedicated (the design's `t.isDark ? '#3a3530' : '#fff'` fill). */
@Composable
private fun FontSegmentedToggle(selected: ReaderFontFamily, isDark: Boolean, ink: Color, onSelect: (ReaderFontFamily) -> Unit) {
    val trackBg = ink.copy(alpha = if (isDark) 0.06f else 0.05f)
    val selectedFill = if (isDark) Color(0xFF3A3530) else Color.White
    Row(
        Modifier.fillMaxWidth().padding(top = 10.dp).clip(RoundedCornerShape(12.dp)).background(trackBg).padding(3.dp),
        horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        listOf(
            ReaderFontFamily.Serif to ("Source Serif" to VReaderFonts.Serif),
            ReaderFontFamily.Sans to ("Inter" to VReaderFonts.Sans),
        ).forEach { (family, labelFont) ->
            val (label, font) = labelFont
            val isOn = family == selected
            Box(
                Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(10.dp))
                    .background(if (isOn) selectedFill else Color.Transparent)
                    .clickable { onSelect(family) }
                    .testTag("font-${family.name.lowercase()}")
                    .padding(vertical = 10.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(label, color = ink, fontFamily = font, fontSize = 15.sp, fontWeight = if (isOn) FontWeight.SemiBold else FontWeight.Medium)
            }
        }
    }
}
