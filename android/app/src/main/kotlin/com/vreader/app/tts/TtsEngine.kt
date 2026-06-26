// Purpose: feature #121 WI-1 (#110 Phase 3) — the TTS engine seam. The ViewModel depends on THIS,
// not android.speech.tts.TextToSpeech, so the transport state machine is unit-testable with a fake.
// The production implementation is AndroidTtsEngine (WI-2). Engine SWITCHING is not a setter here —
// setEngineByPackageName is deprecated; the VM switches engines by recreating via a factory.
package com.vreader.app.tts

import kotlinx.coroutines.flow.Flow
import java.util.Locale

interface TtsEngine {
    /** Await engine init (the OnInitListener bridged to a suspend). */
    suspend fun awaitInit(): TtsInitResult

    /** Enqueue ONE utterance (QUEUE_ADD). Returns true on the engine's SUCCESS, false on ERROR. */
    fun speak(utterance: TtsUtterance): Boolean

    /** Stop + flush the queue (Android TTS has no true pause — the VM models pause as stop+anchor). */
    fun stop()

    /** Set the speech rate. The caller pre-clamps to a finite 0.5..2.0; returns the engine status. */
    fun setRate(rate: Float): Boolean

    /** Select a voice by name (null = engine default). Returns the engine status. */
    fun setVoice(name: String?): Boolean

    /** Engine progress (start / range-refine / done / failed), each stamped with its generation. */
    val progress: Flow<TtsProgress>

    /** The installed TTS engines. */
    fun engines(): List<TtsEngineOption>

    /** Voices, optionally filtered to [locale]. */
    fun voices(locale: Locale?): List<TtsVoiceOption>

    /** A language's availability (the production engine maps the raw TextToSpeech codes; the VM never
     *  sees Android constants). */
    fun isLanguageAvailable(locale: Locale): TtsLanguageAvailability

    /** Release the engine (stop + shutdown). */
    fun shutdown()
}

/** Builds a [TtsEngine] (optionally for a specific engine package). Engine switching = recreate. */
interface TtsEngineFactory {
    suspend fun create(enginePackage: String? = null): TtsEngine
}
