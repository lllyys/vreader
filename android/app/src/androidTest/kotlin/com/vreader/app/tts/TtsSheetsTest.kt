package com.vreader.app.tts

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.backup.BackupSurface
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.util.Locale

/** Feature #121 WI-4 — the speed + voice sheets. */
@RunWith(AndroidJUnit4::class)
class TtsSheetsTest {
    @get:Rule val compose = createComposeRule()

    @Test fun speedSheet_showsCurrentAndPicksPreset() {
        var picked: Float? = null
        compose.setContent { BackupSurface(darkOverride = false) { TtsSpeedSheet(rate = 1.0f, onRate = { picked = it }) } }
        compose.onNodeWithTag("speed-current").assertIsDisplayed()   // current rate, large
        compose.onNodeWithTag("speed-1.5×").performScrollTo().performClick()
        assertEquals(1.5f, picked)
    }

    @Test fun voiceSheet_rendersEnginesAndVoices_andSelects() {
        var selected: TtsVoiceOption? = null
        val state = TtsVoiceListState(
            engines = listOf(TtsEngineOption("g", "Google Speech")),
            selectedEngineId = "g",
            voices = listOf(
                TtsVoiceOption("v1", Locale.US, "English (US)", networkRequired = false, notInstalled = false),
                TtsVoiceOption("v2", Locale.UK, "English (UK)", networkRequired = false, notInstalled = true),
            ),
            selectedVoiceName = "v1",
        )
        compose.setContent { BackupSurface(darkOverride = false) { TtsVoiceSheet(state, onVoice = { selected = it }) } }
        compose.onNodeWithText("Google Speech").assertIsDisplayed()
        compose.onNodeWithTag("voice-v1").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("voice-v1").performClick()
        assertEquals("v1", selected?.name)
    }

    @Test fun voiceSheet_notInstalledTriggersInstall() {
        var install: TtsVoiceOption? = null
        val state = TtsVoiceListState(
            voices = listOf(TtsVoiceOption("v2", Locale.UK, "English (UK)", notInstalled = true)),
        )
        compose.setContent { BackupSurface(darkOverride = false) { TtsVoiceSheet(state, onInstall = { install = it }) } }
        compose.onNodeWithTag("voice-v2").performScrollTo().performClick()
        assertTrue(install?.name == "v2")
    }
}
