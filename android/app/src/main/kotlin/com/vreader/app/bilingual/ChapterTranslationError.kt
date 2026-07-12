// Purpose: feature #131 WI-1 - the user-facing failure taxonomy for a bilingual
// chapter translation, plus the mapper from the AI client's transport-level
// AiError. The bilingual layer surfaces four coarse outcomes (Offline / TimedOut
// / ProviderFailed / Cancelled) rather than the full AiError set, so the reader
// UI can present a small, actionable set of states.
//
// Mapping (mirroring the iOS ChapterTranslationError contract):
// - AiError.Offline    -> Offline
// - AiError.Timeout    -> TimedOut
// - CancellationException (coroutine cancellation) -> Cancelled
// - everything else (Auth401/RateLimited429/Http/Decode/Stream/InsecureUrl/
//   Config, and any non-AiError throwable) -> ProviderFailed(message)
//
// @coordinates-with: com.vreader.app.ai.AiError,
//   dev-docs/plans/20260710-feature-131-android-bilingual.md (WI-1)
package com.vreader.app.bilingual

import com.vreader.app.ai.AiError
import java.util.concurrent.CancellationException

/** The coarse outcome of a bilingual chapter-translation attempt. */
sealed class ChapterTranslationError {

    /** No network / the provider couldn't be reached. */
    object Offline : ChapterTranslationError()

    /** The provider took too long to respond. */
    object TimedOut : ChapterTranslationError()

    /** The provider returned an error (auth, rate-limit, HTTP, decode, ...). */
    data class ProviderFailed(val message: String) : ChapterTranslationError()

    /** The user (or a lifecycle event) cancelled the translation. */
    object Cancelled : ChapterTranslationError()

    companion object {
        /** Maps any [Throwable] raised during translation to a [ChapterTranslationError]. */
        fun from(error: Throwable): ChapterTranslationError = when (error) {
            is CancellationException -> Cancelled
            is AiError.Offline -> Offline
            is AiError.Timeout -> TimedOut
            else -> ProviderFailed(error.message ?: "translation failed")
        }
    }
}
