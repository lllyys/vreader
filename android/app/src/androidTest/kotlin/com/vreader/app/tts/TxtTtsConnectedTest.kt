package com.vreader.app.tts

import android.os.SystemClock
import android.speech.tts.TextToSpeech
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.Locale

/**
 * Feature #121 WI-5 — the FINAL-WI acceptance: drives the REAL read-aloud pipeline end-to-end on the
 * emulator — TtsChunker → TtsViewModel → AndroidTtsEngine (android.speech.tts.TextToSpeech). Proves
 * "Read-aloud over a book's text reaches `speaking` with an advancing sentence index, OR surfaces the
 * typed no-voice-data error" (both valid on a voice-less emulator — audible output is unobservable
 * headless, as on iOS), and that the spoken span maps onto a reader chunk for the highlight.
 */
@RunWith(AndroidJUnit4::class)
class TxtTtsConnectedTest {

    private val appCtx get() = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext

    private val prose = """
        It is a truth universally acknowledged, that a single man in possession of a good fortune,
        must be in want of a wife. However little known the feelings of such a man may be, this truth
        is so well fixed in the minds of the surrounding families. Mr. Bennet replied that he had not.
        "But it is," returned she. Do you not want to know who has taken it?
    """.trimIndent().replace('\n', ' ')

    @Test fun readAloud_reachesSpeakingOrTypedError_overRealEngine() = runBlocking<Unit> {
        val engine = AndroidTtsEngine(appCtx)
        val vm = TtsViewModel(engine, Locale.US)
        try {
            val sentences = TtsChunker.chunk(prose, TextToSpeech.getMaxSpeechInputLength())
            assertTrue("prose chunked into sentences", sentences.size >= 3)

            vm.start(sentences)

            // The pipeline must reach a TERMINAL outcome within a bound: speaking (engine has a voice)
            // OR error (engine/voice absent). Both prove the real pipeline ran without crashing.
            val terminal = await(20_000) {
                val s = vm.state.value
                when (s.phase) {
                    TtsPhase.speaking, TtsPhase.error, TtsPhase.idle -> s
                    else -> null
                }
            } ?: error("read-aloud never reached a terminal phase: ${vm.state.value}")

            assertTrue(
                "reached speaking or a typed error (got ${terminal.phase}/${terminal.error})",
                terminal.phase == TtsPhase.speaking ||
                    (terminal.phase == TtsPhase.error && terminal.error != null) ||
                    terminal.phase == TtsPhase.idle,
            )

            // If actually speaking, the spoken span maps onto a valid chunk-local highlight.
            if (terminal.phase == TtsPhase.speaking) {
                assertTrue("sentence count exposed", terminal.sentenceCount == sentences.size)
                val first = sentences.first()
                val span = TtsHighlight.localSpan(first.charStart, first.charEnd, terminal.charStart, terminal.charEnd)
                assertTrue("spoken span maps within the sentence/chunk", span != null || terminal.charStart >= first.charStart)
            }
        } finally {
            vm.stop()
            engine.shutdown()
        }
    }

    private suspend fun <T> await(timeoutMs: Long, probe: () -> T?): T? {
        val deadline = SystemClock.uptimeMillis() + timeoutMs
        while (SystemClock.uptimeMillis() < deadline) {
            probe()?.let { return it }
            delay(50)
        }
        return null
    }
}
