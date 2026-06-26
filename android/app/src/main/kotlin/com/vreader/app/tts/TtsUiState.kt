// Purpose: feature #121 WI-3 (#110 Phase 3) — UI state + one-shot intents for the TTS transport
// (design vreader-tts.jsx: status row, transport, speed/voice chips, error layout). Stateless
// composables (WI-4) render a pure function of TtsUiState.
package com.vreader.app.tts

import java.util.Locale

/** The control-bar state. */
data class TtsUiState(
    val phase: TtsPhase = TtsPhase.idle,
    val sentenceIndex: Int = 0,
    val sentenceCount: Int = 0,
    val charStart: Int = 0,           // spoken span in the RAW book text (for the reader highlight)
    val charEnd: Int = 0,
    val rate: Float = 1.0f,
    val voiceLabel: String = "",
    val engineLabel: String = "",
    val error: TtsErrorKind? = null,
) {
    // Locale.ROOT so a comma-decimal locale never renders "1,25×".
    val rateLabel: String get() = "${String.format(Locale.ROOT, "%.2f", rate).trimEnd('0').trimEnd('.')}×"
    /** 0..1 progress through the book's sentences (for the bar's progress line). */
    val progressFraction: Float get() = if (sentenceCount <= 1) 0f else (sentenceIndex.toFloat() / (sentenceCount - 1)).coerceIn(0f, 1f)
}

/** One-shot side effects the Activity performs (the VM stays platform-free). */
sealed interface TtsIntent {
    data object InstallVoiceData : TtsIntent
    data object OpenSystemTts : TtsIntent
}

/** Voice-picker sheet state. */
data class TtsVoiceListState(
    val engines: List<TtsEngineOption> = emptyList(),
    val selectedEngineId: String? = null,
    val voices: List<TtsVoiceOption> = emptyList(),
    val selectedVoiceName: String? = null,
)
