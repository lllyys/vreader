package com.vreader.app.tts

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.util.Locale

/** Feature #121 WI-3 — TtsViewModel transport state machine (Started-keyed advance, gated Range,
 *  pause/resume + generation tokens, rate clamp, locale/voice policy). */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
class TtsViewModelTest {
    private val dispatcher = StandardTestDispatcher()
    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private class FakeEngine(
        var init: TtsInitResult = TtsInitResult.ok,
        var lang: TtsLanguageAvailability = TtsLanguageAvailability.available,
        var voiceList: List<TtsVoiceOption> = listOf(TtsVoiceOption("v1", Locale.US, "English", false, false)),
    ) : TtsEngine {
        val spoken = mutableListOf<TtsUtterance>()
        var stops = 0
        var lastRate = 1.0f
        var lastVoice: String? = "<unset>"
        var speakResult = true
        val flow = MutableSharedFlow<TtsProgress>(extraBufferCapacity = 64)
        override val progress = flow
        override suspend fun awaitInit() = init
        override fun speak(utterance: TtsUtterance): Boolean { spoken += utterance; return speakResult }
        override fun stop() { stops++ }
        override fun setRate(rate: Float): Boolean { lastRate = rate; return true }
        override fun setVoice(name: String?): Boolean { lastVoice = name; return true }
        override fun engines() = listOf(TtsEngineOption("e", "Engine"))
        override fun voices(locale: Locale?) = voiceList
        override fun isLanguageAvailable(locale: Locale) = lang
        override fun shutdown() {}
    }

    private fun sentences(n: Int) = (0 until n).map { TtsSentence(it, it * 10, it * 10 + 5, "S$it..") }

    private fun vm(engine: FakeEngine, window: Int = 3) = TtsViewModel(engine, Locale.US, window)

    @Test fun start_speaksWindow_andIsSpeaking() = runTest(dispatcher) {
        val e = FakeEngine(); val v = vm(e)
        v.start(sentences(5)); advanceUntilIdle()
        assertEquals(TtsPhase.speaking, v.state.value.phase)
        assertEquals(listOf(0, 1, 2), e.spoken.map { it.index })   // window of 3
        assertEquals(5, v.state.value.sentenceCount)
    }

    @Test fun started_advancesSentenceAndSpan() = runTest(dispatcher) {
        val e = FakeEngine(); val v = vm(e)
        v.start(sentences(5)); advanceUntilIdle()
        val g = e.spoken.first().generation
        e.flow.emit(TtsProgress.Started(g, 1)); advanceUntilIdle()
        assertEquals(1, v.state.value.sentenceIndex)
        assertEquals(10, v.state.value.charStart)    // sentence 1 starts at 1*10
    }

    @Test fun range_refinesCurrentSentence_ignoresWrongIndexAndStaleGen() = runTest(dispatcher) {
        val e = FakeEngine(); val v = vm(e)
        v.start(sentences(5)); advanceUntilIdle()
        val g = e.spoken.first().generation
        e.flow.emit(TtsProgress.Started(g, 0)); advanceUntilIdle()
        e.flow.emit(TtsProgress.Range(g, 0, 2, 4)); advanceUntilIdle()
        assertEquals(2, v.state.value.charStart)     // base 0 + 2
        assertEquals(4, v.state.value.charEnd)
        // a Range for a non-current index is ignored
        e.flow.emit(TtsProgress.Range(g, 3, 0, 1)); advanceUntilIdle()
        assertEquals(2, v.state.value.charStart)
        // a stale-generation Range is ignored
        e.flow.emit(TtsProgress.Range(g - 1, 0, 9, 9)); advanceUntilIdle()
        assertEquals(2, v.state.value.charStart)
    }

    @Test fun done_enqueuesNext_lastDoneGoesIdle() = runTest(dispatcher) {
        val e = FakeEngine(); val v = vm(e, window = 2)
        v.start(sentences(3)); advanceUntilIdle()      // queued 0,1
        val g = e.spoken.first().generation
        e.flow.emit(TtsProgress.Started(g, 0)); e.flow.emit(TtsProgress.Done(g, 0)); advanceUntilIdle()
        assertEquals(listOf(0, 1, 2), e.spoken.map { it.index })  // Done(0) enqueued 2
        e.flow.emit(TtsProgress.Started(g, 2)); e.flow.emit(TtsProgress.Done(g, 2)); advanceUntilIdle()
        assertEquals(TtsPhase.idle, v.state.value.phase)          // last sentence done → idle
    }

    @Test fun pause_stopsBumpsGeneration_staleStartedIgnored() = runTest(dispatcher) {
        val e = FakeEngine(); val v = vm(e)
        v.start(sentences(5)); advanceUntilIdle()
        val g = e.spoken.first().generation
        v.pause(); advanceUntilIdle()
        assertEquals(TtsPhase.paused, v.state.value.phase)
        assertTrue(e.stops >= 1)
        // a stale Started from the flushed queue (old generation) must NOT change state
        e.flow.emit(TtsProgress.Started(g, 4)); advanceUntilIdle()
        assertEquals(TtsPhase.paused, v.state.value.phase)
        assertEquals(0, v.state.value.sentenceIndex)
    }

    @Test fun play_resumesFromAnchor() = runTest(dispatcher) {
        val e = FakeEngine(); val v = vm(e)
        v.start(sentences(5)); advanceUntilIdle()
        val g0 = e.spoken.first().generation
        e.flow.emit(TtsProgress.Started(g0, 2)); advanceUntilIdle()   // advanced to sentence 2
        v.pause(); advanceUntilIdle()
        e.spoken.clear()
        v.play(); advanceUntilIdle()
        assertEquals(TtsPhase.speaking, v.state.value.phase)
        assertEquals(2, e.spoken.first().index)                       // resumes at the anchor (2)
    }

    @Test fun nextPrev_clampAndReQueue() = runTest(dispatcher) {
        val e = FakeEngine(); val v = vm(e)
        v.start(sentences(3)); advanceUntilIdle()
        v.next(); advanceUntilIdle()
        assertEquals(1, v.state.value.sentenceIndex)
        v.previous(); v.previous(); advanceUntilIdle()
        assertEquals(0, v.state.value.sentenceIndex)                  // clamped at 0
    }

    @Test fun setRate_clampsAndRejectsNonFinite() = runTest(dispatcher) {
        val e = FakeEngine(); val v = vm(e)
        v.setRate(3.0f); assertEquals(2.0f, v.state.value.rate)       // clamped to max
        v.setRate(0.1f); assertEquals(0.5f, v.state.value.rate)       // clamped to min
        v.setRate(Float.NaN); assertEquals(0.5f, v.state.value.rate)  // non-finite rejected (unchanged)
    }

    @Test fun languageMissing_failsNoVoiceData_withoutSpeaking() = runTest(dispatcher) {
        val e = FakeEngine(lang = TtsLanguageAvailability.missingData); val v = vm(e)
        v.start(sentences(3)); advanceUntilIdle()
        assertEquals(TtsPhase.error, v.state.value.phase)
        assertEquals(TtsErrorKind.noVoiceData, v.state.value.error)
        assertTrue(e.spoken.isEmpty())
    }

    @Test fun networkVoice_notAutoSelected() = runTest(dispatcher) {
        val e = FakeEngine(voiceList = listOf(
            TtsVoiceOption("net", Locale.US, "Net", networkRequired = true),
            TtsVoiceOption("embedded", Locale.US, "Embedded", networkRequired = false),
        ))
        val v = vm(e)
        v.start(sentences(2)); advanceUntilIdle()
        assertEquals("embedded", e.lastVoice)
    }

    @Test fun speakFailure_entersError() = runTest(dispatcher) {
        val e = FakeEngine().apply { speakResult = false }; val v = vm(e)
        v.start(sentences(3)); advanceUntilIdle()
        assertEquals(TtsPhase.error, v.state.value.phase)
        assertEquals(TtsErrorKind.speakFailed, v.state.value.error)
    }

    @Test fun failedEvent_isTerminal_noRevive() = runTest(dispatcher) {
        val e = FakeEngine(); val v = vm(e)
        v.start(sentences(5)); advanceUntilIdle()
        val g = e.spoken.first().generation
        e.flow.emit(TtsProgress.Failed(g, 1, TtsErrorKind.speakFailed)); advanceUntilIdle()
        assertEquals(TtsPhase.error, v.state.value.phase)
        // a stale same-(old)generation Started must NOT revive speaking (failTerminal bumped generation)
        e.flow.emit(TtsProgress.Started(g, 2)); advanceUntilIdle()
        assertEquals(TtsPhase.error, v.state.value.phase)
    }

    @Test fun installVoiceData_emitsIntent() = runTest(dispatcher) {
        val e = FakeEngine(); val v = vm(e)
        val seen = mutableListOf<TtsIntent>()
        val job = launch { v.intents.collect { seen += it } }
        advanceUntilIdle()                      // ensure the collector is subscribed (replay=0)
        v.installVoiceData(); advanceUntilIdle()
        assertTrue(seen.contains(TtsIntent.InstallVoiceData))
        job.cancel()
    }
}
