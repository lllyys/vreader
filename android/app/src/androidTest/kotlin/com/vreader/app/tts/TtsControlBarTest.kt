package com.vreader.app.tts

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Feature #121 WI-4 — the TTS control bar: transport states + callbacks + the error layout. */
@RunWith(AndroidJUnit4::class)
class TtsControlBarTest {
    @get:Rule val compose = createComposeRule()

    @Test fun speaking_showsStatusAndTransportCallbacks() {
        var pp = false; var nx = false; var pv = false; var st = false
        compose.setContent {
            TtsControlBar(
                TtsUiState(phase = TtsPhase.speaking, sentenceIndex = 1, sentenceCount = 5, voiceLabel = "English"),
                onPlayPause = { pp = true }, onNext = { nx = true }, onPrevious = { pv = true }, onStop = { st = true },
            )
        }
        compose.onNodeWithText("READING ALOUD").assertIsDisplayed()
        compose.onNodeWithText("2 / 5").assertIsDisplayed()
        compose.onNodeWithTag("tts-playpause").performClick()
        compose.onNodeWithTag("tts-next").performClick()
        compose.onNodeWithTag("tts-prev").performClick()
        compose.onNodeWithTag("tts-stop").performClick()
        assertTrue(pp && nx && pv && st)
    }

    @Test fun paused_showsPausedStatus() {
        compose.setContent { TtsControlBar(TtsUiState(phase = TtsPhase.paused, sentenceCount = 3)) }
        compose.onNodeWithText("PAUSED").assertIsDisplayed()
    }

    @Test fun error_showsInstallAndSystemCtas() {
        var install = false; var system = false
        compose.setContent {
            TtsControlBar(
                TtsUiState(phase = TtsPhase.error, error = TtsErrorKind.noVoiceData),
                onInstallVoice = { install = true }, onSystemTts = { system = true },
            )
        }
        compose.onNodeWithTag("tts-error").assertIsDisplayed()
        compose.onNodeWithTag("tts-install-voice").performClick()
        compose.onNodeWithTag("tts-system").performClick()
        assertTrue(install && system)
    }

    @Test fun speedAndVoiceChips_fireCallbacks() {
        var speed = false; var voice = false
        compose.setContent {
            TtsControlBar(
                TtsUiState(phase = TtsPhase.speaking, sentenceCount = 2, rate = 1.5f, voiceLabel = "English"),
                onSpeed = { speed = true }, onVoice = { voice = true },
            )
        }
        compose.onNodeWithText("1.5×").assertIsDisplayed()   // the speed chip
        compose.onNodeWithTag("tts-speed").performClick()
        compose.onNodeWithTag("tts-voice").performClick()
        assertTrue(speed && voice)
    }
}
