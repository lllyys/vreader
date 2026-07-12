package com.vreader.app.bilingual

import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.reader.settings.ReaderTheme
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Feature #131 WI-7a — the "EN ↔ <glyph>" bilingual pill ([BilingualPill]). Verifies it renders the
 * EN chip + the target-language glyph, updates the glyph per language, and renders in light + dark
 * without crash. RENDER tests.
 */
@RunWith(AndroidJUnit4::class)
class BilingualPillUiTest {
    @get:Rule val compose = createComposeRule()

    @Test fun rendersEnChipAndTargetGlyph() {
        compose.setContent { BilingualPill(theme = ReaderTheme.Paper, language = BilingualLanguages.findOrDefault("Chinese")) }
        compose.onNodeWithTag("bilingual-pill", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("EN", useUnmergedTree = true).assertExists()
        assertTrue(compose.onAllNodesWithText("中", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty())
    }

    @Test fun glyph_tracksLanguage() {
        compose.setContent { BilingualPill(theme = ReaderTheme.Paper, language = BilingualLanguages.findOrDefault("Japanese")) }
        assertTrue(compose.onAllNodesWithText("日", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty())
        compose.onAllNodesWithText("中", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun dark_theme_rendersWithoutCrash() {
        compose.setContent { BilingualPill(theme = ReaderTheme.Oled, language = BilingualLanguages.findOrDefault("French")) }
        compose.onNodeWithTag("bilingual-pill", useUnmergedTree = true).assertExists()
    }
}
