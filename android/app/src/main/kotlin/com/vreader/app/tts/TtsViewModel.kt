// Purpose: feature #121 WI-3 (#110 Phase 3) — the read-aloud transport state machine over an injected
// TtsEngine. Sentence advance is driven by Started (fires on every engine); Range only refines the
// CURRENT sentence's highlight span (the WI-2 cross-flow-ordering contract — an out-of-order/stale
// Range is ignored). Pause = engine.stop() + retain the anchor; resume re-speaks from it. A generation
// token bumps BEFORE any stop that flushes the queue, so a flushed-queue callback is discarded; a
// startToken guards the suspending start() against re-entrancy / stop-during-init.
package com.vreader.app.tts

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.util.Locale

class TtsViewModel(
    private val engine: TtsEngine,
    private val readLocale: Locale = Locale.getDefault(),
    queueWindow: Int = 3,
) : ViewModel() {

    private val window = queueWindow.coerceAtLeast(1)

    private val _state = MutableStateFlow(TtsUiState())
    val state: StateFlow<TtsUiState> = _state.asStateFlow()

    private val _intents = MutableSharedFlow<TtsIntent>(extraBufferCapacity = 4)
    val intents: SharedFlow<TtsIntent> = _intents.asSharedFlow()

    private var sentences: List<TtsSentence> = emptyList()
    private var generation = 0L          // bumped before any queue-flushing stop
    private var startToken = 0L          // guards the suspending start() against re-entrancy / stop
    private var current = 0              // the resume anchor / current sentence
    private var enqueuedThrough = -1     // highest index handed to the engine this generation

    init {
        viewModelScope.launch { engine.progress.collect { onProgress(it) } }
    }

    /** Begin read-aloud over [sentences]. Awaits init, checks the read language, picks an embedded
     *  voice, applies the rate, and enqueues the first window. A missing/unsupported language surfaces
     *  the typed error instead of speaking. Re-entrancy + stop-during-init safe via [startToken]. */
    fun start(sentences: List<TtsSentence>): kotlinx.coroutines.Job {
        val token = ++startToken      // bumped SYNCHRONOUSLY so a stop() racing before the coroutine
        generation++; engine.stop()   // runs is visible to the token checks below; stop playback now
        return viewModelScope.launch {
        if (token != startToken) return@launch       // a stop()/newer start() raced in before we ran
        this@TtsViewModel.sentences = sentences
        if (sentences.isEmpty()) { _state.value = _state.value.copy(phase = TtsPhase.idle, sentenceCount = 0, sentenceIndex = 0); return@launch }
        if (engine.awaitInit() != TtsInitResult.ok) { if (token == startToken) fail(TtsErrorKind.initFailed); return@launch }
        if (token != startToken) return@launch       // superseded by a newer start()/stop()
        when (engine.isLanguageAvailable(readLocale)) {
            TtsLanguageAvailability.missingData -> { fail(TtsErrorKind.noVoiceData); return@launch }
            TtsLanguageAvailability.notSupported -> { fail(TtsErrorKind.languageNotSupported); return@launch }
            TtsLanguageAvailability.available -> Unit
        }
        if (token != startToken) return@launch
        val voices = engine.voices(readLocale)
        val chosen = voices.firstOrNull { !it.networkRequired && !it.notInstalled } ?: voices.firstOrNull { !it.networkRequired }
        val accepted = chosen != null && engine.setVoice(chosen.name)   // never auto-select a network voice
        engine.setRate(_state.value.rate)
        current = 0
        _state.value = _state.value.copy(
            phase = TtsPhase.speaking, sentenceIndex = 0, sentenceCount = sentences.size, error = null,
            voiceLabel = if (accepted) chosen!!.label else "",
            engineLabel = engine.engines().firstOrNull()?.label ?: "",
            charStart = sentences[0].charStart, charEnd = sentences[0].charEnd,
        )
        restartFromCurrent()
        }
    }

    fun play() {
        if (_state.value.phase != TtsPhase.paused || sentences.isEmpty()) return
        _state.value = _state.value.copy(phase = TtsPhase.speaking, error = null)
        restartFromCurrent()
    }

    fun pause() {
        if (_state.value.phase != TtsPhase.speaking) return
        generation++; engine.stop()   // bump BEFORE stop so flushed-queue callbacks are stale
        _state.value = _state.value.copy(phase = TtsPhase.paused)  // keep `current` as the resume anchor
    }

    fun stop() {
        startToken++                   // cancel any in-flight start()
        generation++; engine.stop()
        current = 0
        _state.value = _state.value.copy(phase = TtsPhase.idle, sentenceIndex = 0, charStart = 0, charEnd = 0)
    }

    fun next() = seek(current + 1)
    fun previous() = seek(current - 1)

    private fun seek(to: Int) {
        if (sentences.isEmpty()) return
        current = to.coerceIn(0, sentences.lastIndex)
        val s = sentences[current]
        _state.value = _state.value.copy(sentenceIndex = current, charStart = s.charStart, charEnd = s.charEnd)
        if (_state.value.phase == TtsPhase.speaking) restartFromCurrent() else generation++
    }

    fun setRate(rate: Float) {
        if (!rate.isFinite()) return
        val clamped = rate.coerceIn(MIN_RATE, MAX_RATE)
        engine.setRate(clamped)
        _state.value = _state.value.copy(rate = clamped)
    }

    fun selectVoice(option: TtsVoiceOption) {
        if (!engine.setVoice(option.name)) return   // engine rejected it — keep prior state
        _state.value = _state.value.copy(voiceLabel = option.label)
        if (_state.value.phase == TtsPhase.speaking) restartFromCurrent()
    }

    fun installVoiceData() { _intents.tryEmit(TtsIntent.InstallVoiceData) }
    fun openSystemTts() { _intents.tryEmit(TtsIntent.OpenSystemTts) }

    /** Snapshot the engine/voice options for the voice sheet (read locale). */
    fun voiceListState(): TtsVoiceListState {
        val engines = engine.engines()
        val voices = engine.voices(readLocale)
        return TtsVoiceListState(
            engines = engines, selectedEngineId = engines.firstOrNull()?.id,
            voices = voices, selectedVoiceName = voices.firstOrNull { it.label == _state.value.voiceLabel }?.name,
        )
    }

    // ── engine progress ─────────────────────────────────────────────

    private fun onProgress(p: TtsProgress) {
        if (p.generation != generation) return  // stale (flushed queue / superseded start)
        when (p) {
            is TtsProgress.Started -> {
                current = p.index
                val s = sentences.getOrNull(p.index) ?: return
                _state.value = _state.value.copy(phase = TtsPhase.speaking, sentenceIndex = p.index, charStart = s.charStart, charEnd = s.charEnd)
            }
            is TtsProgress.Range -> {
                // gate by the CURRENT sentence — an out-of-order/stale Range is ignored (WI-2 contract).
                if (p.index != current) return
                val base = sentences.getOrNull(p.index) ?: return
                val cs = (base.charStart + p.charStart).coerceIn(base.charStart, base.charEnd)
                val ce = (base.charStart + p.charEnd).coerceIn(cs, base.charEnd)
                _state.value = _state.value.copy(charStart = cs, charEnd = ce)
            }
            is TtsProgress.Done -> {
                // Refill on ANY same-generation Done (not tied to `current`) so a dropped Started can't
                // stall the queue; finish when the last sentence completes.
                val nextToQueue = enqueuedThrough + 1
                if (nextToQueue <= sentences.lastIndex) speakOne(nextToQueue)
                else if (p.index >= sentences.lastIndex) _state.value = _state.value.copy(phase = TtsPhase.idle)
            }
            is TtsProgress.Failed -> failTerminal(p.kind)
        }
    }

    // ── queueing ────────────────────────────────────────────────────

    /** Bump the generation FIRST (invalidate stale callbacks), stop, then enqueue [current..+window). */
    private fun restartFromCurrent() {
        generation++
        engine.stop()
        enqueuedThrough = current - 1
        val last = minOf(current + window - 1, sentences.lastIndex)
        for (i in current..last) if (!speakOne(i)) return
    }

    /** Enqueue one utterance; on an engine ERROR, fail terminally (don't advance the bookkeeping). */
    private fun speakOne(index: Int): Boolean {
        val s = sentences.getOrNull(index) ?: return true
        if (!engine.speak(TtsUtterance(generation, index, s.text))) { failTerminal(TtsErrorKind.speakFailed); return false }
        if (index > enqueuedThrough) enqueuedThrough = index
        return true
    }

    private fun fail(kind: TtsErrorKind) { _state.value = _state.value.copy(phase = TtsPhase.error, error = kind) }

    /** A terminal failure: invalidate the queue (gen++), stop the engine, surface the error — so later
     *  same-(old)generation callbacks can't revive `speaking` or refill. */
    private fun failTerminal(kind: TtsErrorKind) {
        generation++; engine.stop()
        _state.value = _state.value.copy(phase = TtsPhase.error, error = kind)
    }

    override fun onCleared() {
        engine.shutdown()
        super.onCleared()
    }

    private companion object {
        const val MIN_RATE = 0.5f
        const val MAX_RATE = 2.0f
    }
}
