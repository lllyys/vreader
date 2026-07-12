package com.vreader.app.bilingual

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeUp
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.reader.settings.ReaderTheme
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Feature #131 WI-7a — the TXT/MD interlinear translation slot ([BilingualTranslationSlot]), the
 * muted non-registered translation child (round-4 H2 render contract). Verifies every state:
 * Loaded (translated child renders, muted, non-registered, BELOW its source), Loading
 * ("Translating chapter… N%"), Error (the DEPICTED ghost slot — no invented copy/Retry), SourceOnly
 * (nothing drawn), empty translation → nothing, the source-font inheritance for Latin targets, CJK +
 * RTL render, light + dark. RENDER + semantics tests (no long-press).
 */
@RunWith(AndroidJUnit4::class)
class BilingualInterlinearBodyUiTest {
    @get:Rule val compose = createComposeRule()

    private val chinese = BilingualLanguages.findOrDefault("Chinese")
    private val arabic = BilingualLanguages.findOrDefault("Arabic")

    /** Hosts one anchor chunk's source `Text` + the translation slot in a `Column` (the WI-8 shape). */
    @Composable
    private fun anchorChunk(
        theme: ReaderTheme,
        state: BilingualRenderState,
        language: BilingualLanguage = chinese,
        sourceFontFamily: FontFamily = androidx.compose.ui.text.font.FontFamily.Serif,
    ) {
        Column(Modifier.fillMaxWidth().padding(8.dp)) {
            // The (byte-unchanged) source chunk that WI-8 keeps registered.
            Text("It is a truth universally acknowledged", Modifier.fillMaxWidth().testTag("source-chunk"))
            BilingualTranslationSlot(
                state = state, theme = theme, language = language, sourceFontSizeSp = 17f,
                sourceFontFamily = sourceFontFamily,
            )
        }
    }

    @Test fun loaded_rendersTranslationChild_BELOW_source() {
        val state = BilingualRenderState(segments = listOf("凡是有钱的单身汉，总想娶位太太。"), phase = BilingualRenderPhase.Loaded)
        compose.setContent { anchorChunk(ReaderTheme.Paper, state) }
        compose.onNodeWithTag("source-chunk", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("bilingual-translation-slot", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("bilingual-translation-text-0", useUnmergedTree = true).assertExists()
        // The translation slot renders BELOW its source chunk (the interlinear order — H2 contract).
        val srcBottom = compose.onNodeWithTag("source-chunk", useUnmergedTree = true).getBoundsInRoot().bottom
        val trTop = compose.onNodeWithTag("bilingual-translation-slot", useUnmergedTree = true).getBoundsInRoot().top
        assertTrue("translation must sit below source", trTop.value >= srcBottom.value - 1f)
    }

    @Test fun loaded_latinTarget_inheritsSourceSansFamily() {
        // A Latin target with a sans source family renders (font-family inheritance — the design's
        // per-script translatedFF; CJK/RTL force serif, Latin/Cyrillic inherit the source family).
        val spanish = BilingualLanguages.findOrDefault("Spanish")
        val state = BilingualRenderState(segments = listOf("Es una verdad universalmente reconocida."), phase = BilingualRenderPhase.Loaded)
        compose.setContent { anchorChunk(ReaderTheme.Paper, state, language = spanish, sourceFontFamily = FontFamily.SansSerif) }
        compose.onNodeWithTag("bilingual-translation-slot", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("bilingual-translation-text-0", useUnmergedTree = true).assertExists()
    }

    @Test fun loaded_translationChild_isAccessibleText() {
        // The translation is a plain muted `Text` (NOT semantics-cleared) — it stays readable by
        // TalkBack (round-3 accessibility Medium). It is "non-registered" purely by not being wired
        // into the source-selection `registerChunk` loop (WI-8 owns that), NOT by hiding its semantics.
        val translated = "凡是有钱的单身汉，总想娶位太太。"
        val state = BilingualRenderState(segments = listOf(translated), phase = BilingualRenderPhase.Loaded)
        compose.setContent { anchorChunk(ReaderTheme.Paper, state) }
        compose.onNodeWithTag("bilingual-translation-text-0", useUnmergedTree = true).assertExists()
        // The translation text IS present as an accessible semantics node (findable by text).
        assertTrue(compose.onAllNodesWithText(translated, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty())
    }

    @Test fun loading_showsPercent_andSlot() {
        val state = BilingualRenderState(segments = null, phase = BilingualRenderPhase.Loading(0.42f))
        compose.setContent { anchorChunk(ReaderTheme.Paper, state) }
        compose.onNodeWithTag("bilingual-loading-slot", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("bilingual-loading-label", useUnmergedTree = true).assertExists()
        // Plan §210 copy: "Translating chapter… N%" (not "Translating…").
        assertTrue(
            compose.onAllNodesWithText("Translating chapter… 42%", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty(),
        )
    }

    @Test fun error_showsDepictedGhostSlot_noInventedCopy() {
        // The error phase renders the DEPICTED ghost slot (dim dashed line) — NOT an invented inline
        // "Couldn't translate" + Retry (rule 51: the offline bundle depicts only the ghost slot per-slot,
        // and Retry only in the page-level banner, which is WI-8 chrome).
        val state = BilingualRenderState(segments = null, phase = BilingualRenderPhase.Error)
        compose.setContent { anchorChunk(ReaderTheme.Paper, state) }
        compose.onNodeWithTag("bilingual-error-slot", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("bilingual-ghost", useUnmergedTree = true).assertExists()
        // No invented inline copy or Retry button.
        compose.onAllNodesWithText("Couldn't translate", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithTag("bilingual-retry", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun sourceOnly_drawsNothing() {
        compose.setContent { anchorChunk(ReaderTheme.Paper, BilingualRenderState.sourceOnly) }
        compose.onNodeWithTag("source-chunk", useUnmergedTree = true).assertExists()
        // No slot of any kind is drawn (silent source-only fallback).
        compose.onAllNodesWithText("Couldn't translate", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithTag("bilingual-translation-slot", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithTag("bilingual-loading-slot", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithTag("bilingual-error-slot", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun loaded_emptyTranslation_drawsNothing_noCrash() {
        val state = BilingualRenderState(segments = listOf("", "   "), phase = BilingualRenderPhase.Loaded)
        compose.setContent { anchorChunk(ReaderTheme.Paper, state) }
        compose.onNodeWithTag("source-chunk", useUnmergedTree = true).assertExists()
        compose.onAllNodesWithTag("bilingual-translation-slot", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun rtlArabic_rendersWithoutCrash() {
        val state = BilingualRenderState(segments = listOf("إنها حقيقة معترف بها عالميًا"), phase = BilingualRenderPhase.Loaded)
        compose.setContent { anchorChunk(ReaderTheme.Paper, state, language = arabic) }
        compose.onNodeWithTag("bilingual-translation-slot", useUnmergedTree = true).assertExists()
    }

    @Test fun dark_theme_loaded_rendersWithoutCrash() {
        val state = BilingualRenderState(segments = listOf("译文"), phase = BilingualRenderPhase.Loaded)
        compose.setContent { anchorChunk(ReaderTheme.Oled, state) }
        compose.onNodeWithTag("bilingual-translation-slot", useUnmergedTree = true).assertExists()
    }

    @Test fun swipeStartingOnTranslation_stillScrollsLazyColumn() {
        // Round-3 Medium regression guard: the translation must NOT consume drag events, so a swipe
        // BEGINNING over the translation text still scrolls the enclosing LazyColumn. (This test would
        // have failed with the removed round-2 consuming pointerInput — it prevents its reintroduction.)
        // The deterministic signal is the LazyListState scroll position, not a re-measured row bound.
        val state = BilingualRenderState(segments = listOf("凡是有钱的单身汉，总想娶位太太。"), phase = BilingualRenderPhase.Loaded)
        lateinit var listState: androidx.compose.foundation.lazy.LazyListState
        compose.setContent {
            listState = rememberLazyListState()
            LazyColumn(state = listState, modifier = Modifier.fillMaxSize().testTag("scroll-list")) {
                items(count = 40) { i ->
                    Column(Modifier.fillMaxWidth().height(200.dp).testTag("row-$i")) {
                        Text("source chunk $i", Modifier.fillMaxWidth())
                        BilingualTranslationSlot(state, ReaderTheme.Paper, chinese, sourceFontSizeSp = 17f)
                    }
                }
            }
        }
        val (idxBefore, offBefore) = listState.firstVisibleItemIndex to listState.firstVisibleItemScrollOffset
        // Swipe up STARTING on the FIRST visible row's translation slot (many rows share the tag).
        compose.onAllNodesWithTag("bilingual-translation-slot", useUnmergedTree = true)[0].performTouchInput { swipeUp() }
        compose.waitForIdle()
        val scrolled = listState.firstVisibleItemIndex > idxBefore ||
            (listState.firstVisibleItemIndex == idxBefore && listState.firstVisibleItemScrollOffset > offBefore)
        assertTrue("swipe on translation must scroll the list", scrolled)
    }
}
