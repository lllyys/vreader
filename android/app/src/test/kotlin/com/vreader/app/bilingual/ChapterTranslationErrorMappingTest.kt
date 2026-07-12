// Purpose: feature #131 WI-1 — RED-first JVM tests for ChapterTranslationError +
// its AiError -> ChapterTranslationError mapper. Offline->Offline,
// Timeout->TimedOut, cancellation->Cancelled, everything else->ProviderFailed.
package com.vreader.app.bilingual

import com.vreader.app.ai.AiError
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CancellationException

class ChapterTranslationErrorMappingTest {

    @Test fun offline_mapsToOffline() {
        assertEquals(ChapterTranslationError.Offline, ChapterTranslationError.from(AiError.Offline))
    }

    @Test fun timeout_mapsToTimedOut() {
        assertEquals(ChapterTranslationError.TimedOut, ChapterTranslationError.from(AiError.Timeout))
    }

    @Test fun auth401_mapsToProviderFailed() {
        val mapped = ChapterTranslationError.from(AiError.Auth401)
        assertTrue(mapped is ChapterTranslationError.ProviderFailed)
    }

    @Test fun rateLimited_mapsToProviderFailed() {
        assertTrue(ChapterTranslationError.from(AiError.RateLimited429) is ChapterTranslationError.ProviderFailed)
    }

    @Test fun http_mapsToProviderFailed_withMessage() {
        val mapped = ChapterTranslationError.from(AiError.Http(503))
        assertTrue(mapped is ChapterTranslationError.ProviderFailed)
        assertTrue((mapped as ChapterTranslationError.ProviderFailed).message.isNotEmpty())
    }

    @Test fun decode_mapsToProviderFailed() {
        assertTrue(ChapterTranslationError.from(AiError.Decode("bad")) is ChapterTranslationError.ProviderFailed)
    }

    @Test fun stream_mapsToProviderFailed() {
        assertTrue(ChapterTranslationError.from(AiError.Stream("abrupt")) is ChapterTranslationError.ProviderFailed)
    }

    @Test fun insecureUrl_mapsToProviderFailed() {
        assertTrue(ChapterTranslationError.from(AiError.InsecureUrl) is ChapterTranslationError.ProviderFailed)
    }

    @Test fun config_mapsToProviderFailed() {
        assertTrue(ChapterTranslationError.from(AiError.Config("bad")) is ChapterTranslationError.ProviderFailed)
    }

    @Test fun cancellation_mapsToCancelled() {
        assertEquals(ChapterTranslationError.Cancelled, ChapterTranslationError.from(CancellationException("stopped")))
    }

    @Test fun genericThrowable_mapsToProviderFailed() {
        val mapped = ChapterTranslationError.from(RuntimeException("boom"))
        assertTrue(mapped is ChapterTranslationError.ProviderFailed)
        assertTrue((mapped as ChapterTranslationError.ProviderFailed).message.isNotEmpty())
    }
}
