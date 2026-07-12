// Purpose: feature #131 WI-7a — the bilingual setup sheet (the FIRST-enable half-sheet), a faithful
// reproduction of `vreader-bilingual.jsx`'s `BilingualSetupSheet` (lines 27–156) with the round-4 H3
// granularity divergence: header; a preview strip (BilingualPreview); a language grid over
// BILINGUAL_LANGS (glyph tiles, selected accent); a Granularity segmented control DESCOPED to
// Paragraph-ONLY in v1 ("Translate after each ¶"; NO Sentence option — round-4 H3, tracked by the
// sentence design gate); a Translation-engine strip (configured: "Claude · with this book's context"
// + "Change…"; unconfigured: "No AI provider configured" + "Bilingual mode needs an AI provider to
// translate." + "Set up"); the "Turn on bilingual mode" CTA. NO Style control, no provider/model
// card, no term-overrides, no cost footer (those belong to the AI-Providers sheet, WI-AIP — §3).
//
// The sub-components (preview / grid / granularity / engine / label / samples) live in
// BilingualSetupSheetParts.kt (split to keep both files under the ~300-line bar — rule 50 §9).
//
// The `aiConfigured` flag comes from `BilingualAiReadiness.resolve` (BilingualUiState.aiConfigured).
// The "Set up"/"Change…" CTA exposes an [onSetUp] callback; WI-9 routes it to the Variant A
// ReaderAiProvidersSheet. Here it renders + fires the callback only (that routing is out of scope).
//
// Rule 51: reproduces ONLY what the bundle depicts. Renders in the ACTIVE reader theme (light+dark).
// Pure function of state + callbacks (rule 50 §12); content extracted for direct UI testing.
//
// @coordinates-with: BilingualSetupSheetParts.kt, BilingualLanguages.kt, TranslationGranularity.kt,
//   BilingualUiState.kt, ReaderTheme.kt,
//   dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx,
//   dev-docs/plans/…-feature-131-…interlinear.md (WI-7a §204)
package com.vreader.app.bilingual

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.reader.settings.ReaderTheme
import com.vreader.app.ui.theme.VReaderFonts

/**
 * The first-enable bilingual setup half-sheet. [selectedLanguage] is the current target; selecting a
 * tile fires [onSelectLanguage]. [aiConfigured] drives the engine strip (true → "Claude…"+Change…;
 * false → "No AI provider configured"+Set up). [onSetUp] fires when the engine CTA is tapped (WI-9
 * routes it). [onTurnOn] fires the "Turn on bilingual mode" CTA. [onDismiss] dismisses the sheet.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BilingualSetupSheet(
    theme: ReaderTheme,
    selectedLanguage: BilingualLanguage,
    aiConfigured: Boolean,
    onSelectLanguage: (BilingualLanguage) -> Unit,
    onSetUp: () -> Unit,
    onTurnOn: () -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = theme.background,
        modifier = modifier.testTag("bilingual-setup-sheet"),
    ) {
        BilingualSetupSheetContent(
            theme = theme,
            selectedLanguage = selectedLanguage,
            aiConfigured = aiConfigured,
            onSelectLanguage = onSelectLanguage,
            onSetUp = onSetUp,
            onTurnOn = onTurnOn,
        )
    }
}

/** The setup sheet's content, extracted from the [ModalBottomSheet] wrapper for direct UI testing. */
@Composable
fun BilingualSetupSheetContent(
    theme: ReaderTheme,
    selectedLanguage: BilingualLanguage,
    aiConfigured: Boolean,
    onSelectLanguage: (BilingualLanguage) -> Unit,
    onSetUp: () -> Unit,
    onTurnOn: () -> Unit,
) {
    val ink = theme.ink
    val sub = theme.ink.copy(alpha = 0.6f)
    Column(
        Modifier
            .fillMaxWidth()
            .background(theme.background)
            .testTag("bilingual-setup-content"),
    ) {
        // The design's `Sheet` chrome: a centered serif title with a bottom rule (matching the
        // TocContentsSheet/ReaderSettingsSheet Android reproduction). ModalBottomSheet supplies the
        // drag grabber + scrim-tap dismiss (the sheet's close affordance on Android).
        Text(
            "Bilingual mode",
            Modifier.fillMaxWidth().padding(horizontal = 22.dp, vertical = 12.dp).testTag("bilingual-setup-title"),
            color = ink, fontFamily = VReaderFonts.Serif, fontSize = 18.sp, fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
        )
        Box(Modifier.fillMaxWidth().height(0.5.dp).background(theme.ink.copy(alpha = 0.08f)))

        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 22.dp)
                .padding(top = 8.dp, bottom = 28.dp),
        ) {

        // Preview strip (design's BilingualPreview).
        BilingualPreview(theme = theme, language = selectedLanguage)

        // Target language grid.
        BilingualSectionLabel("Target language", sub, topPadding = 22.dp)
        LanguageGrid(theme = theme, selected = selectedLanguage, onSelect = onSelectLanguage)

        // Granularity — Paragraph ONLY in v1 (round-4 H3). NO Sentence option.
        BilingualSectionLabel("Granularity", sub, topPadding = 22.dp)
        ParagraphOnlyGranularity(theme = theme)

        // Translation engine strip.
        BilingualSectionLabel("Translation engine", sub, topPadding = 22.dp)
        EngineStrip(theme = theme, aiConfigured = aiConfigured, onSetUp = onSetUp)

        // CTA.
        Box(
            Modifier
                .fillMaxWidth()
                .padding(top = 22.dp)
                .clip(RoundedCornerShape(14.dp))
                .background(theme.accent)
                .clickable(onClick = onTurnOn)
                .testTag("bilingual-turn-on")
                .padding(vertical = 14.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text("Turn on bilingual mode", color = Color.White, fontFamily = VReaderFonts.Sans, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        }
        } // end scrollable body Column
    }
}
