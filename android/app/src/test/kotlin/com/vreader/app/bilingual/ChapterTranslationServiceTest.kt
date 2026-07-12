// Purpose: feature #131 WI-3 — RED-first JVM tests for ChapterTranslationService,
// the segment→chunk→translate→decode→cache pipeline, against a FAKE AiClient (no
// network). Covers both cachedTranslation overloads (incl. the expectedSegmentCount
// zero-provider divergence restore — H2), translate, and translatePreSegmented,
// with the dual-cancellation contract (native CancellationException AND typed
// ChapterTranslationError.Cancelled mapped to Cancelled BEFORE generic AiError
// mapping — M2), per-chunk graceful degrade (not cached on partial), and
// ensureActive-before-write. Uses a real ChapterTranslationStore over an in-memory
// FakeDao (the WI-2 store test's precedent) so the cache read/write seam is exercised.
package com.vreader.app.bilingual

import com.vreader.app.ai.AiError
import com.vreader.app.ai.AiProviderKind
import com.vreader.app.ai.AiProviderProfile
import com.vreader.app.ai.AiResponse
import com.vreader.app.data.ChapterTranslationDao
import com.vreader.app.data.ChapterTranslationEntity
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

// Robolectric-run so the bundled android.icu extended-grapheme BreakIterator used by
// TranslationChunker (API 24+) is present under the JVM — the plain stub android.jar
// throws "not mocked" (same pattern as TranslationChunkerTest).
@RunWith(RobolectricTestRunner::class)
class ChapterTranslationServiceTest {

    // ── fixtures ──────────────────────────────────────────────

    private class FakeDao : ChapterTranslationDao {
        val rows = LinkedHashMap<String, ChapterTranslationEntity>()
        var upsertCount = 0
        override suspend fun getByLookupKey(key: String): ChapterTranslationEntity? = rows[key]
        override suspend fun upsert(row: ChapterTranslationEntity) { upsertCount++; rows[row.lookupKey] = row }
        override suspend fun deleteByLookupKey(key: String) { rows.remove(key) }
        override suspend fun count(): Int = rows.size
    }

    private val bookKey = "epub:${"a".repeat(64)}:2048"
    private val unit = TranslationUnitId(TranslationUnitId.Kind.txtDocSegmentWindow, "0")
    private val lang = "zh-Hans"
    private val promptVersion = "bilingual-v1|g=paragraph"

    private val profile = AiProviderProfile(
        id = "prof-1",
        name = "Test",
        kind = AiProviderKind.openAiCompatible,
        baseUrl = "https://example.test",
        model = "gpt-test",
        temperature = 0.3,
        maxTokens = 1024,
        encryptedApiKey = "enc",
    )

    private fun service(
        client: FakeAiClient,
        store: ChapterTranslationStore,
        maxCharsPerChunk: Int = 6000,
    ) = ChapterTranslationService(
        aiClient = client,
        store = store,
        promptVersion = promptVersion,
        maxCharsPerChunk = maxCharsPerChunk,
    )

    private fun store(dao: FakeDao = FakeDao()) = ChapterTranslationStore(dao)

    /** Two paragraphs separated by a blank line → two segments. */
    private val twoParagraphSource = "Alpha paragraph one.\n\nBeta paragraph two."

    private fun seedRow(
        dao: FakeDao,
        segments: List<String>,
        sourceParagraphCount: Int = segments.size,
        unitStorageKey: String = unit.storageKey,
    ) {
        val row = CachedTranslation(
            bookKey = bookKey,
            unitStorageKey = unitStorageKey,
            targetLanguage = lang,
            promptVersion = promptVersion,
            translatedSegments = segments,
            sourceParagraphCount = sourceParagraphCount,
            createdAt = 100L,
        )
        dao.rows[row.lookupKey] = row.let {
            ChapterTranslationEntity(
                lookupKey = it.lookupKey,
                bookKey = it.bookKey,
                unitStorageKey = it.unitStorageKey,
                targetLanguage = it.targetLanguage,
                promptVersion = it.promptVersion,
                translatedJson = FakeAiClient.encodeJsonArray(segments),
                sourceParagraphCount = sourceParagraphCount,
                createdAt = it.createdAt,
            )
        }
    }

    // ── cachedTranslation(sourceText, …) ──────────────────────

    @Test fun cachedTranslation_hit_returnsRow_zeroClientCalls() = runTest {
        val dao = FakeDao()
        seedRow(dao, listOf("译1", "译2"))
        val client = FakeAiClient.translating()
        val svc = service(client, store(dao))

        val result = svc.cachedTranslation(bookKey, unit, twoParagraphSource, lang, TranslationGranularity.paragraph)

        assertEquals(listOf("译1", "译2"), result?.segments)
        assertTrue(result!!.fromCache)
        assertEquals("cache hit makes ZERO client calls", 0, client.callCount)
    }

    @Test fun cachedTranslation_miss_returnsNull() = runTest {
        val client = FakeAiClient.translating()
        val svc = service(client, store())
        assertNull(svc.cachedTranslation(bookKey, unit, twoParagraphSource, lang, TranslationGranularity.paragraph))
        assertEquals(0, client.callCount)
    }

    @Test fun cachedTranslation_countMismatch_returnsNull_unlessAccepted() = runTest {
        val dao = FakeDao()
        // Stored count 3, but the source segments to 2 → strict staleness → miss.
        seedRow(dao, listOf("a", "b", "c"), sourceParagraphCount = 3)
        val client = FakeAiClient.translating()
        val svc = service(client, store(dao))

        assertNull(
            "strict count mismatch is a miss",
            svc.cachedTranslation(bookKey, unit, twoParagraphSource, lang, TranslationGranularity.paragraph),
        )
        // acceptCountMismatch=true serves it anyway (self-healing consumers).
        val accepted = svc.cachedTranslation(
            bookKey, unit, twoParagraphSource, lang, TranslationGranularity.paragraph, acceptCountMismatch = true,
        )
        assertEquals(listOf("a", "b", "c"), accepted?.segments)
        assertEquals(0, client.callCount)
    }

    // ── cachedTranslation(expectedSegmentCount, …) — H2 zero-provider restore ──

    @Test fun cachedTranslationByCount_hit_onStoredCountMatch_noProvider() = runTest {
        val dao = FakeDao()
        seedRow(dao, listOf("译1", "译2"), sourceParagraphCount = 2)
        val client = FakeAiClient.translating()
        val svc = service(client, store(dao))

        val result = svc.cachedTranslation(bookKey, unit, expectedSegmentCount = 2, targetLanguage = lang)

        assertEquals(listOf("译1", "译2"), result?.segments)
        assertTrue(result!!.fromCache)
        assertEquals("restores with zero provider calls and no source text", 0, client.callCount)
    }

    @Test fun cachedTranslationByCount_null_onStoredCountMismatch() = runTest {
        val dao = FakeDao()
        seedRow(dao, listOf("译1", "译2", "译3"), sourceParagraphCount = 3)
        val client = FakeAiClient.translating()
        val svc = service(client, store(dao))

        assertNull(svc.cachedTranslation(bookKey, unit, expectedSegmentCount = 2, targetLanguage = lang))
        assertEquals(0, client.callCount)
    }

    // ── translate: miss → translate + write ───────────────────

    @Test fun translate_miss_translatesAndWritesCache() = runTest {
        val dao = FakeDao()
        val client = FakeAiClient.translating()
        val svc = service(client, store(dao))

        val result = svc.translate(bookKey, unit, twoParagraphSource, lang, profile)

        assertEquals(listOf("T:Alpha paragraph one.", "T:Beta paragraph two."), result.segments)
        assertTrue("miss is not fromCache", !result.fromCache)
        assertTrue("at least one client call", client.callCount >= 1)
        // A full-success translate writes the canonical row with the source count.
        val stored = dao.rows.values.single()
        assertEquals(2, stored.sourceParagraphCount)
        assertEquals("""["T:Alpha paragraph one.","T:Beta paragraph two."]""", stored.translatedJson)
    }

    @Test fun translate_cacheHit_returnsCached_zeroClientCalls() = runTest {
        val dao = FakeDao()
        seedRow(dao, listOf("译1", "译2"), sourceParagraphCount = 2)
        val client = FakeAiClient.translating()
        val svc = service(client, store(dao))

        val result = svc.translate(bookKey, unit, twoParagraphSource, lang, profile)

        assertEquals(listOf("译1", "译2"), result.segments)
        assertTrue(result.fromCache)
        assertEquals(0, client.callCount)
    }

    @Test fun translate_bypassCacheRead_reTranslatesEvenWithFreshRow() = runTest {
        val dao = FakeDao()
        seedRow(dao, listOf("stale1", "stale2"), sourceParagraphCount = 2)
        val client = FakeAiClient.translating()
        val svc = service(client, store(dao))

        val result = svc.translate(bookKey, unit, twoParagraphSource, lang, profile, bypassCacheRead = true)

        assertEquals(listOf("T:Alpha paragraph one.", "T:Beta paragraph two."), result.segments)
        assertTrue(client.callCount >= 1)
    }

    @Test fun translate_staleCountMismatch_reTranslates() = runTest {
        val dao = FakeDao()
        // stored count 3 but source segments to 2 → stale → re-translate.
        seedRow(dao, listOf("s1", "s2", "s3"), sourceParagraphCount = 3)
        val client = FakeAiClient.translating()
        val svc = service(client, store(dao))

        val result = svc.translate(bookKey, unit, twoParagraphSource, lang, profile)

        assertEquals(listOf("T:Alpha paragraph one.", "T:Beta paragraph two."), result.segments)
        assertTrue("stale row triggers a real translate", client.callCount >= 1)
        assertEquals("row replaced with the fresh count", 2, dao.rows.values.single().sourceParagraphCount)
    }

    @Test fun translate_emptySource_returnsEmpty_noWrite() = runTest {
        val dao = FakeDao()
        val client = FakeAiClient.translating()
        val svc = service(client, store(dao))

        val result = svc.translate(bookKey, unit, "   \n\n   ", lang, profile)

        assertTrue(result.segments.isEmpty())
        assertEquals(0, client.callCount)
        assertTrue("no row written for an empty source", dao.rows.isEmpty())
    }

    // ── translate: decode-fail → per-segment fallback ─────────

    @Test fun translate_decodeFail_perSegmentFallback() = runTest {
        val dao = FakeDao()
        // First (whole-chunk) call returns a bad blob → decode fails → per-segment retries.
        val client = FakeAiClient { request, index ->
            if (index == 0) {
                AiResponse("this is not a json array")
            } else {
                val src = FakeAiClient.extractSources(FakeAiClient.userText(request)).single()
                AiResponse(FakeAiClient.encodeJsonArray(listOf("PS:$src")))
            }
        }
        val svc = service(client, store(dao))

        val result = svc.translate(bookKey, unit, twoParagraphSource, lang, profile)

        assertEquals(listOf("PS:Alpha paragraph one.", "PS:Beta paragraph two."), result.segments)
        // 1 whole-chunk attempt + 2 per-segment retries.
        assertEquals(3, client.callCount)
        assertEquals("full success is cached", 1, dao.rows.size)
    }

    // ── translate: one-chunk-fail graceful degrade, NOT cached ─

    @Test fun translate_oneChunkFails_thatChunkSourceOnly_othersTranslated_notCached() = runTest {
        val dao = FakeDao()
        // Budget 20 → each ~20-char paragraph is its own WHOLE chunk (no sub-split).
        // First chunk's provider call throws; second succeeds.
        val client = FakeAiClient { request, index ->
            if (index == 0) throw AiError.Http(500)
            val src = FakeAiClient.extractSources(FakeAiClient.userText(request)).single()
            AiResponse(FakeAiClient.encodeJsonArray(listOf("T:$src")))
        }
        val svc = service(client, store(dao), maxCharsPerChunk = 20)

        val result = svc.translate(bookKey, unit, twoParagraphSource, lang, profile)

        // Failed chunk → source-only ("") for its segment; the other is translated.
        assertEquals("", result.segments[0])
        assertEquals("T:Beta paragraph two.", result.segments[1])
        assertTrue("a partial degrade is NOT cached", dao.rows.isEmpty())
    }

    // ── translate: all-chunks-fail → throw ────────────────────

    @Test fun translate_allChunksFail_throws() = runTest {
        val dao = FakeDao()
        val client = FakeAiClient { _, _ -> throw AiError.Http(503) }
        val svc = service(client, store(dao), maxCharsPerChunk = 1)

        try {
            svc.translate(bookKey, unit, twoParagraphSource, lang, profile)
            fail("all-chunks-fail must throw")
        } catch (e: ChapterTranslationException) {
            assertTrue(e.error is ChapterTranslationError.ProviderFailed)
        }
        assertTrue("no row on total failure", dao.rows.isEmpty())
    }

    // ── translate: cancellation (dual: native + typed) ────────

    @Test fun translate_nativeCancellation_mapsToCancelled_noWrite() = runTest {
        val dao = FakeDao()
        val client = FakeAiClient { _, _ -> throw CancellationException("stop") }
        val svc = service(client, store(dao), maxCharsPerChunk = 1)

        try {
            svc.translate(bookKey, unit, twoParagraphSource, lang, profile)
            fail("native cancellation must surface as Cancelled")
        } catch (e: ChapterTranslationException) {
            assertEquals(ChapterTranslationError.Cancelled, e.error)
        }
        assertTrue("no cache write on cancellation", dao.rows.isEmpty())
    }

    @Test fun translate_typedCancelledFromChunk_mapsToCancelled_noWrite_notDegraded() = runTest {
        val dao = FakeDao()
        // A chunk throws the TYPED Cancelled (wrapped) — must abort, NOT degrade.
        val client = FakeAiClient { _, _ ->
            throw ChapterTranslationException(ChapterTranslationError.Cancelled)
        }
        val svc = service(client, store(dao), maxCharsPerChunk = 1)

        try {
            svc.translate(bookKey, unit, twoParagraphSource, lang, profile)
            fail("typed Cancelled from a chunk must abort")
        } catch (e: ChapterTranslationException) {
            assertEquals(ChapterTranslationError.Cancelled, e.error)
        }
        assertTrue("typed cancel does NOT degrade-and-cache", dao.rows.isEmpty())
    }

    @Test fun translate_cancelBeforeWrite_ensureActive_noRow() = runTest {
        // All chunks succeed, but the coroutine is cancelled right before the write:
        // ensureActive() before the Room upsert must throw → no row.
        val dao = FakeDao()
        val job = Job()
        val client = FakeAiClient { request, _ ->
            // Cancel the surrounding scope AFTER the (single) chunk resolves so the
            // pre-write ensureActive() trips.
            job.cancel()
            val srcs = FakeAiClient.extractSources(FakeAiClient.userText(request))
            AiResponse(FakeAiClient.encodeJsonArray(srcs.map { "T:$it" }))
        }
        val svc = service(client, store(dao))

        try {
            kotlinx.coroutines.withContext(job) {
                svc.translate(bookKey, unit, twoParagraphSource, lang, profile)
            }
            fail("cancel-before-write must throw")
        } catch (e: ChapterTranslationException) {
            assertEquals(ChapterTranslationError.Cancelled, e.error)
        } catch (e: CancellationException) {
            // Also acceptable — the point is no row was written.
        }
        assertTrue("ensureActive-before-write prevented the row", dao.rows.isEmpty())
    }

    @Test fun translate_cancellationInsideUpsert_propagates_notSwallowed() = runTest {
        // Cancellation observed WHILE the Room upsert suspends must propagate — a bare
        // runCatching in writeCache would swallow it (Gate-4 Medium). All chunks
        // succeed, but the DAO's upsert throws CancellationException.
        val dao = object : ChapterTranslationDao {
            val rows = LinkedHashMap<String, ChapterTranslationEntity>()
            override suspend fun getByLookupKey(key: String): ChapterTranslationEntity? = rows[key]
            override suspend fun upsert(row: ChapterTranslationEntity) {
                throw CancellationException("cancelled mid-upsert")
            }
            override suspend fun deleteByLookupKey(key: String) { rows.remove(key) }
            override suspend fun count(): Int = rows.size
        }
        val client = FakeAiClient.translating()
        val svc = service(client, ChapterTranslationStore(dao))

        try {
            svc.translate(bookKey, unit, twoParagraphSource, lang, profile)
            fail("cancellation inside upsert must propagate, not be swallowed")
        } catch (e: CancellationException) {
            // Correct — cancellation is cancellation-transparent.
        }
        assertTrue("no row written when the upsert is cancelled", dao.rows.isEmpty())
    }

    @Test fun translate_upsertFailure_isNonFatal_translationStillReturned() = runTest {
        // A NON-cancellation store-write failure must NOT fail the translation — the
        // caller still gets the freshly translated text (rule 50 §6).
        val dao = object : ChapterTranslationDao {
            val rows = LinkedHashMap<String, ChapterTranslationEntity>()
            override suspend fun getByLookupKey(key: String): ChapterTranslationEntity? = rows[key]
            override suspend fun upsert(row: ChapterTranslationEntity) { throw RuntimeException("disk full") }
            override suspend fun deleteByLookupKey(key: String) { rows.remove(key) }
            override suspend fun count(): Int = rows.size
        }
        val client = FakeAiClient.translating()
        val svc = service(client, ChapterTranslationStore(dao))

        val result = svc.translate(bookKey, unit, twoParagraphSource, lang, profile)

        assertEquals(listOf("T:Alpha paragraph one.", "T:Beta paragraph two."), result.segments)
        assertTrue("a write failure leaves no cached row but returns the translation", dao.rows.isEmpty())
    }

    // ── AiError mapping ───────────────────────────────────────

    @Test fun translate_configError_mapsToProviderFailed() = runTest {
        val client = FakeAiClient { _, _ -> throw AiError.Config("bad base url") }
        val svc = service(client, store(), maxCharsPerChunk = 1)
        try {
            svc.translate(bookKey, unit, twoParagraphSource, lang, profile)
            fail("Config error must throw")
        } catch (e: ChapterTranslationException) {
            assertTrue(e.error is ChapterTranslationError.ProviderFailed)
        }
    }

    @Test fun translate_insecureUrl_mapsToProviderFailed() = runTest {
        val client = FakeAiClient { _, _ -> throw AiError.InsecureUrl }
        val svc = service(client, store(), maxCharsPerChunk = 1)
        try {
            svc.translate(bookKey, unit, twoParagraphSource, lang, profile)
            fail("InsecureUrl must throw")
        } catch (e: ChapterTranslationException) {
            assertTrue(e.error is ChapterTranslationError.ProviderFailed)
        }
    }

    @Test fun translate_offline_mapsToOffline() = runTest {
        val client = FakeAiClient { _, _ -> throw AiError.Offline }
        val svc = service(client, store(), maxCharsPerChunk = 1)
        try {
            svc.translate(bookKey, unit, twoParagraphSource, lang, profile)
            fail("Offline must throw")
        } catch (e: ChapterTranslationException) {
            assertEquals(ChapterTranslationError.Offline, e.error)
        }
    }

    @Test fun translate_timeout_mapsToTimedOut() = runTest {
        val client = FakeAiClient { _, _ -> throw AiError.Timeout }
        val svc = service(client, store(), maxCharsPerChunk = 1)
        try {
            svc.translate(bookKey, unit, twoParagraphSource, lang, profile)
            fail("Timeout must throw")
        } catch (e: ChapterTranslationException) {
            assertEquals(ChapterTranslationError.TimedOut, e.error)
        }
    }

    // ── very-long-chapter N-of-M ──────────────────────────────

    @Test fun translate_veryLongChapter_multipleChunks_allSegmentsTranslatedInOrder() = runTest {
        val dao = FakeDao()
        // 6 short paragraphs, budget forces several chunks; every segment must
        // come back in source order.
        val paras = (1..6).map { "Paragraph number $it here." }
        val source = paras.joinToString("\n\n")
        val client = FakeAiClient.translating()
        val svc = service(client, store(dao), maxCharsPerChunk = 30) // ~1 paragraph/chunk

        val result = svc.translate(bookKey, unit, source, lang, profile)

        assertEquals(paras.map { "T:$it" }, result.segments)
        assertTrue("multiple provider calls for a long chapter", client.callCount >= 2)
        assertEquals(6, dao.rows.values.single().sourceParagraphCount)
    }

    // ── translatePreSegmented ─────────────────────────────────

    @Test fun translatePreSegmented_fullSuccess_cachesUnderEnumerateCount() = runTest {
        val dao = FakeDao()
        val client = FakeAiClient.translating()
        val svc = service(client, store(dao))
        val segments = listOf("Block one", "Block two", "Block three")

        val translated = svc.translatePreSegmented(bookKey, unit, segments, lang, profile)

        assertEquals(listOf("T:Block one", "T:Block two", "T:Block three"), translated)
        val stored = dao.rows.values.single()
        assertEquals("cached under the ENUMERATE's count", 3, stored.sourceParagraphCount)
        // The cached row restores via the zero-provider count overload.
        val client2 = FakeAiClient.translating()
        val svc2 = service(client2, store(dao))
        val restored = svc2.cachedTranslation(bookKey, unit, expectedSegmentCount = 3, targetLanguage = lang)
        assertEquals(translated, restored?.segments)
        assertEquals(0, client2.callCount)
    }

    @Test fun translatePreSegmented_partialDegrade_notCached() = runTest {
        val dao = FakeDao()
        // 2 blocks (9 chars each), budget 9 → each its own chunk (no sub-split);
        // first fails, second succeeds.
        val client = FakeAiClient { request, index ->
            if (index == 0) throw AiError.Http(500)
            val src = FakeAiClient.extractSources(FakeAiClient.userText(request)).single()
            AiResponse(FakeAiClient.encodeJsonArray(listOf("T:$src")))
        }
        val svc = service(client, store(dao), maxCharsPerChunk = 9)

        val translated = svc.translatePreSegmented(bookKey, unit, listOf("Block one", "Block two"), lang, profile)

        assertEquals("", translated[0])
        assertEquals("T:Block two", translated[1])
        assertTrue("a partial pre-segmented degrade is NOT cached", dao.rows.isEmpty())
    }

    @Test fun translatePreSegmented_allFail_throws() = runTest {
        val dao = FakeDao()
        val client = FakeAiClient { _, _ -> throw AiError.Http(503) }
        val svc = service(client, store(dao), maxCharsPerChunk = 1)
        try {
            svc.translatePreSegmented(bookKey, unit, listOf("Block one", "Block two"), lang, profile)
            fail("all-fail must throw")
        } catch (e: ChapterTranslationException) {
            assertTrue(e.error is ChapterTranslationError.ProviderFailed)
        }
        assertTrue(dao.rows.isEmpty())
    }

    @Test fun translatePreSegmented_empty_returnsEmpty_noCall() = runTest {
        val client = FakeAiClient.translating()
        val svc = service(client, store())
        assertTrue(svc.translatePreSegmented(bookKey, unit, emptyList(), lang, profile).isEmpty())
        assertEquals(0, client.callCount)
    }

    @Test fun translatePreSegmented_typedCancelledFromChunk_abortsNoWrite() = runTest {
        val dao = FakeDao()
        val client = FakeAiClient { _, _ -> throw ChapterTranslationException(ChapterTranslationError.Cancelled) }
        val svc = service(client, store(dao), maxCharsPerChunk = 9)
        try {
            svc.translatePreSegmented(bookKey, unit, listOf("Block one", "Block two"), lang, profile)
            fail("typed Cancelled aborts pre-segmented")
        } catch (e: ChapterTranslationException) {
            assertEquals(ChapterTranslationError.Cancelled, e.error)
        }
        assertTrue(dao.rows.isEmpty())
    }
}
