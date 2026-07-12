package com.vreader.app.bilingual

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.reader.settings.ReaderTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Feature #131 WI-7a — the bilingual setup sheet content ([BilingualSetupSheetContent]). Verifies:
 * the Granularity control shows Paragraph ONLY (no Sentence option — round-4 H3), NO Style control;
 * the language grid renders + selection fires the callback; the engine strip switches on
 * `aiConfigured` (configured → "Change…" / unconfigured → "Set up" + "Turn on" CTA); the unconfigured
 * "Set up" CTA fires `onSetUp`; light + dark render without crash. RENDER + click tests.
 */
@RunWith(AndroidJUnit4::class)
class BilingualSetupSheetUiTest {
    @get:Rule val compose = createComposeRule()

    private val chinese = BilingualLanguages.findOrDefault("Chinese")

    @Test fun granularity_showsParagraphOnly_noSentenceOption() {
        compose.setContent {
            BilingualSetupSheetContent(
                theme = ReaderTheme.Paper, selectedLanguage = chinese, aiConfigured = true,
                onSelectLanguage = {}, onSetUp = {}, onTurnOn = {},
            )
        }
        compose.onNodeWithTag("bilingual-granularity", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("granularity-paragraph", useUnmergedTree = true).assertExists()
        // The Sentence option is NOT rendered in v1 (H3).
        compose.onAllNodesWithText("Sentence", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun noStyleControl_present() {
        compose.setContent {
            BilingualSetupSheetContent(
                theme = ReaderTheme.Paper, selectedLanguage = chinese, aiConfigured = true,
                onSelectLanguage = {}, onSetUp = {}, onTurnOn = {},
            )
        }
        // Style was descoped for v1 — no Style label/section anywhere.
        compose.onAllNodesWithText("Style", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun languageGrid_renders_andSelectionFires() {
        var selected: BilingualLanguage? = null
        compose.setContent {
            BilingualSetupSheetContent(
                theme = ReaderTheme.Paper, selectedLanguage = chinese, aiConfigured = true,
                onSelectLanguage = { selected = it }, onSetUp = {}, onTurnOn = {},
            )
        }
        compose.onNodeWithTag("bilingual-language-grid", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("bilingual-lang-Japanese", useUnmergedTree = true).performClick()
        assertEquals("Japanese", selected?.key)
    }

    @Test fun engineStrip_configured_showsChange() {
        compose.setContent {
            BilingualSetupSheetContent(
                theme = ReaderTheme.Paper, selectedLanguage = chinese, aiConfigured = true,
                onSelectLanguage = {}, onSetUp = {}, onTurnOn = {},
            )
        }
        compose.onNodeWithTag("bilingual-engine-strip", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("Claude · with this book's context", useUnmergedTree = true).assertExists()
        assertTrue(compose.onAllNodesWithText("Change…", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty())
    }

    @Test fun engineStrip_unconfigured_showsSetUp_andCtaFires() {
        var setUp = false
        compose.setContent {
            BilingualSetupSheetContent(
                theme = ReaderTheme.Paper, selectedLanguage = chinese, aiConfigured = false,
                onSelectLanguage = {}, onSetUp = { setUp = true }, onTurnOn = {},
            )
        }
        compose.onNodeWithText("No AI provider configured", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("engine-cta", useUnmergedTree = true).performClick()
        assertTrue(setUp)
    }

    @Test fun turnOnCta_fires() {
        var turnedOn = false
        compose.setContent {
            BilingualSetupSheetContent(
                theme = ReaderTheme.Paper, selectedLanguage = chinese, aiConfigured = true,
                onSelectLanguage = {}, onSetUp = {}, onTurnOn = { turnedOn = true },
            )
        }
        compose.onNodeWithTag("bilingual-turn-on", useUnmergedTree = true).performClick()
        assertTrue(turnedOn)
    }

    @Test fun preview_renders_andReactsToLanguageSelection() {
        compose.setContent {
            var lang by remember { mutableStateOf(chinese) }
            BilingualSetupSheetContent(
                theme = ReaderTheme.Paper, selectedLanguage = lang, aiConfigured = true,
                onSelectLanguage = { lang = it }, onSetUp = {}, onTurnOn = {},
            )
        }
        compose.onNodeWithTag("bilingual-preview", useUnmergedTree = true).assertExists()
        // Switching to Spanish re-renders the preview with the Spanish sample (design's BilingualPreview).
        compose.onNodeWithTag("bilingual-lang-Spanish", useUnmergedTree = true).performClick()
        assertTrue(
            compose.onAllNodesWithText(
                "Es una verdad universalmente reconocida que un hombre soltero en posesión de una buena fortuna necesita una esposa.",
                useUnmergedTree = true,
            ).fetchSemanticsNodes().isNotEmpty(),
        )
    }

    @Test fun dark_theme_rendersWithoutCrash() {
        compose.setContent {
            BilingualSetupSheetContent(
                theme = ReaderTheme.Oled, selectedLanguage = chinese, aiConfigured = false,
                onSelectLanguage = {}, onSetUp = {}, onTurnOn = {},
            )
        }
        compose.onNodeWithTag("bilingual-setup-content", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("granularity-paragraph", useUnmergedTree = true).assertExists()
    }
}
