// Purpose: feature #131 WI-7a — the "EN ↔ 中" bilingual pill shown in the reader top chrome when
// bilingual mode is on, a faithful reproduction of `vreader-bilingual.jsx`'s `BilingualPill`
// (lines 282–305): an accent-tinted pill holding a white-on-accent "EN" square, a muted "↔", and
// the target-language glyph. WI-8/WI-9 place it in the top chrome next to the title; WI-7a provides
// the reusable composable + its light/dark rendering. Pure function of state (rule 50 §12).
//
// @coordinates-with: BilingualLanguages.kt, ReaderTheme.kt,
//   dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx
package com.vreader.app.bilingual

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.reader.settings.ReaderTheme
import com.vreader.app.ui.theme.VReaderFonts

/**
 * The bilingual "EN ↔ <glyph>" pill. [language] supplies the target glyph. Renders in the active
 * [theme] (the accent-tinted pill on either light or dark chrome).
 */
@Composable
fun BilingualPill(
    theme: ReaderTheme,
    language: BilingualLanguage,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier
            .clip(RoundedCornerShape(100.dp))
            .background(theme.accent.copy(alpha = 0.10f)) // design's `${t.accent}1a`
            .padding(start = 4.dp, end = 8.dp, top = 2.dp, bottom = 2.dp)
            .testTag("bilingual-pill"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        // The white-on-accent "EN" chip.
        Box(
            Modifier.size(16.dp).clip(RoundedCornerShape(8.dp)).background(theme.accent),
            contentAlignment = Alignment.Center,
        ) {
            Text("EN", color = Color.White, fontFamily = VReaderFonts.Sans, fontSize = 9.sp, fontWeight = FontWeight.Bold)
        }
        Text("↔", color = theme.accent.copy(alpha = 0.7f), fontSize = 9.sp)
        Text(
            language.glyph,
            color = theme.accent,
            fontFamily = VReaderFonts.Serif,
            fontSize = 12.sp,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.testTag("bilingual-pill-glyph"),
        )
    }
}
