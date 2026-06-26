// Purpose: feature #121 WI-1 (#110 Phase 3) — pure value types for TTS read-aloud (design #1797,
// vreader-tts.jsx). No Android runtime here; these back the chunker, the engine seam, and the
// ViewModel so the transport logic is unit-testable without android.speech.tts.TextToSpeech.
package com.vreader.app.tts

import java.util.Locale

/** Transport phase (the design's bar states). */
enum class TtsPhase { idle, speaking, paused, error }

/** Why read-aloud is unavailable. `noVoiceData`/`languageNotSupported` come from a language check;
 *  `speakFailed` from a speak/setVoice ERROR or an onError callback; `initFailed` from engine init. */
enum class TtsErrorKind { initFailed, noVoiceData, languageNotSupported, speakFailed }

/** One sentence to speak. [generation] is a monotonic token (bumped on every start/pause/stop/next)
 *  so a callback from a flushed queue is discarded even when the sentence index is reused (resume from
 *  the same sentence). [charStart]/[charEnd] index the RAW book text (UTF-16), so the spoken span maps
 *  back to a TxtDocument chunk for highlight; invariant: `bookText.substring(charStart, charEnd) == text`. */
data class TtsSentence(val index: Int, val charStart: Int, val charEnd: Int, val text: String)

/** An utterance handed to the engine — a sentence stamped with the current generation. */
data class TtsUtterance(val generation: Long, val index: Int, val text: String) {
    init { require(generation >= 0 && index >= 0) { "generation/index must be non-negative" } }

    /** The Android utterance id: "<generation>:<index>", parsed back in progress callbacks. */
    val utteranceId: String get() = "$generation:$index"

    companion object {
        /** Parse an utterance id, rejecting anything not "<g>:<i>" with non-negative g and i — so a
         *  malformed/hostile callback id ("-1:-3", "a:b", "1:2:3") can't push bad state into the VM. */
        fun parse(id: String?): Pair<Long, Int>? {
            val parts = id?.split(':') ?: return null
            if (parts.size != 2) return null
            val g = parts[0].toLongOrNull()?.takeIf { it >= 0 } ?: return null
            val i = parts[1].toIntOrNull()?.takeIf { it >= 0 } ?: return null
            return g to i
        }
    }
}

/** Progress events from the engine. Every case carries the [generation] so a stale-queue callback is
 *  unambiguously ignored by the ViewModel. */
sealed interface TtsProgress {
    val generation: Long
    data class Started(override val generation: Long, val index: Int) : TtsProgress
    data class Range(override val generation: Long, val index: Int, val charStart: Int, val charEnd: Int) : TtsProgress
    data class Done(override val generation: Long, val index: Int) : TtsProgress
    data class Failed(override val generation: Long, val index: Int?, val kind: TtsErrorKind) : TtsProgress
}

/** A selectable on-device TTS engine (Google, Samsung, …). */
data class TtsEngineOption(val id: String, val label: String)

/** A selectable voice. [networkRequired] voices are listed but never auto-selected; [notInstalled]
 *  voices need a system voice-data install. */
data class TtsVoiceOption(
    val name: String,
    val locale: Locale,
    val label: String,
    val networkRequired: Boolean = false,
    val notInstalled: Boolean = false,
)

/** Engine init outcome. */
enum class TtsInitResult { ok, failed }

/** A language's availability on the selected engine — the domain mapping of the raw
 *  `TextToSpeech.isLanguageAvailable` codes (kept out of the ViewModel). */
enum class TtsLanguageAvailability { available, missingData, notSupported }
