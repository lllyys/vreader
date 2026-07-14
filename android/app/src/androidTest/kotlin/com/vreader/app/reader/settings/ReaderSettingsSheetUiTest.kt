package com.vreader.app.reader.settings

import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performSemanticsAction
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Feature #129 WI-2 — the designed "Display" `ReaderSettingsSheetContent`: a theme swatch reports its
 * theme, the font toggle reports its family, the size slider reports a value, and all 5 themes + 3
 * sliders render. Renders the content composable directly (the #127 sheet-test precedent).
 *
 * Feature #137 WI-2 — extends the sheet with the designed Layout (Paged/Scroll) segmented control
 * (between Theme and Font, vreader-panels.jsx): selecting a segment reports it via [onLayout], the
 * current [ReaderSettings.layout] is reflected as the selected segment, and both glyph-bearing options
 * render.
 */
@RunWith(AndroidJUnit4::class)
class ReaderSettingsSheetUiTest {
    @get:Rule val compose = createComposeRule()
    private val defaults = ReaderSettings()

    private fun render(
        settings: ReaderSettings = defaults,
        onTheme: (ReaderTheme) -> Unit = {},
        onLayout: (ReaderLayout) -> Unit = {},
        onFont: (ReaderFontFamily) -> Unit = {},
        onSize: (Float) -> Unit = {},
        onSpacing: (Float) -> Unit = {},
        onMargin: (Float) -> Unit = {},
    ) = compose.setContent {
        ReaderSettingsSheetContent(settings, onTheme, onLayout, onFont, onSize, onSpacing, onMargin)
    }

    @Test fun tappingThemeSwatch_reportsTheTheme() {
        var picked: ReaderTheme? = null
        render(onTheme = { picked = it })
        compose.onNodeWithTag("theme-Dark", useUnmergedTree = true).performClick()
        assertEquals(ReaderTheme.Dark, picked)
    }

    @Test fun tappingFontToggle_reportsTheFamily() {
        var family: ReaderFontFamily? = null
        render(onFont = { family = it })
        compose.onNodeWithTag("font-sans", useUnmergedTree = true).performClick()
        assertEquals(ReaderFontFamily.Sans, family)
    }

    @Test fun draggingSizeSlider_reportsTheValue() {
        var size: Float? = null
        render(onSize = { size = it })
        compose.onNodeWithTag("size-slider").performSemanticsAction(SemanticsActions.SetProgress) { it(22f) }
        assertEquals(22f, size!!, 1e-3f)
    }

    @Test fun rendersAllFiveThemesAndThreeSliders() {
        render()
        compose.onNodeWithText("Display").assertExists()
        ReaderTheme.entries.forEach { compose.onNodeWithTag("theme-${it.name}", useUnmergedTree = true).assertExists() }
        compose.onNodeWithText("OLED", useUnmergedTree = true).assertExists()   // displayName (not "Oled")
        compose.onNodeWithTag("size-slider").assertExists()
        compose.onNodeWithTag("spacing-slider").assertExists()
        compose.onNodeWithTag("margin-slider").assertExists()
    }

    // ── Feature #137 WI-2 — the Layout (Paged/Scroll) segmented control ──────────────────────────

    @Test fun rendersLayoutControlWithBothOptions() {
        render()
        compose.onNodeWithText("Layout").assertExists()
        compose.onNodeWithTag("layout-paged", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("layout-scroll", useUnmergedTree = true).assertExists()
        // Both segments carry their label text (design order: Paged then Scroll).
        compose.onNodeWithText("Paged", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("Scroll", useUnmergedTree = true).assertExists()
    }

    @Test fun tappingPaged_reportsPaged() {
        var picked: ReaderLayout? = null
        render(onLayout = { picked = it })
        compose.onNodeWithTag("layout-paged", useUnmergedTree = true).performClick()
        assertEquals(ReaderLayout.Paged, picked)
    }

    @Test fun tappingScroll_reportsScroll() {
        var picked: ReaderLayout? = null
        // Start from Paged so tapping Scroll is a real change.
        render(settings = defaults.copy(layout = ReaderLayout.Paged), onLayout = { picked = it })
        compose.onNodeWithTag("layout-scroll", useUnmergedTree = true).performClick()
        assertEquals(ReaderLayout.Scroll, picked)
    }

    @Test fun currentLayoutIsReflectedAsSelectedSegment() {
        // Default layout = Scroll → the Scroll segment is selected.
        render()
        compose.onNodeWithTag("layout-scroll", useUnmergedTree = true).assertIsSelected()
        compose.onNodeWithTag("layout-paged", useUnmergedTree = true).assertIsNotSelected()
    }

    @Test fun pagedSettingIsReflectedAsSelectedSegment() {
        render(settings = defaults.copy(layout = ReaderLayout.Paged))
        compose.onNodeWithTag("layout-paged", useUnmergedTree = true).assertIsSelected()
        compose.onNodeWithTag("layout-scroll", useUnmergedTree = true).assertIsNotSelected()
    }
}
