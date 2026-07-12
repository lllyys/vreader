// Purpose: feature #131 WI-4a — RED-first JVM tests for ChapterTranslationPrefetcher,
// against a REAL AiProviderStore (temp DataStore + a reversible/throwing fake cipher,
// the AiProviderStoreTest precedent), a FAKE clientFactory, and a real
// ChapterTranslationService over an in-memory FakeDao. Covers: snapshot-consistent
// profile+key resolution; the injected factory being used; the AiRequest built from
// the profile; the M3 blank-model → kind.defaultModel regression; the #306 cache-hit
// with NO active provider; a no-provider miss → ProviderFailed; prefetchDirect 1:1;
// cachedDirect restoring with ZERO provider calls; and a cipher-throw mapping to
// ProviderFailed (not a crash). Robolectric-run for the ICU segmenter/chunker.
package com.vreader.app.bilingual

import com.vreader.app.ai.AiClient
import com.vreader.app.ai.AiProviderKind
import com.vreader.app.ai.AiProviderProfile
import com.vreader.app.ai.AiProviderStore
import com.vreader.app.ai.AiRequest
import com.vreader.app.backup.net.SecretCipher
import com.vreader.app.data.ChapterTranslationDao
import com.vreader.app.data.ChapterTranslationEntity
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class ChapterTranslationPrefetcherTest {

    @get:Rule val tmp = TemporaryFolder()

    // ── fixtures ──────────────────────────────────────────────

    private val bookKey = "txt:${"a".repeat(64)}:1024"
    private val lang = "zh-Hans"
    private val promptVersion = "bilingual-v1|g=paragraph"
    private val unit = TranslationUnitId(TranslationUnitId.Kind.txtDocSegmentWindow, "0")

    /** A reversible fake cipher; toggle [throwOnDecrypt] to simulate a keystore failure. */
    private class FakeCipher(var throwOnDecrypt: Boolean = false) : SecretCipher {
        override fun encrypt(plaintext: String) = "enc($plaintext)"
        override fun decrypt(token: String): String {
            if (throwOnDecrypt) throw IllegalStateException("keystore unavailable")
            return token.removePrefix("enc(").removeSuffix(")")
        }
    }

    /** An in-memory ChapterTranslationDao (the WI-3 test's precedent). */
    private class FakeDao : ChapterTranslationDao {
        val rows = LinkedHashMap<String, ChapterTranslationEntity>()
        override suspend fun getByLookupKey(key: String): ChapterTranslationEntity? = rows[key]
        override suspend fun upsert(row: ChapterTranslationEntity) { rows[row.lookupKey] = row }
        override suspend fun deleteByLookupKey(key: String) { rows.remove(key) }
        override suspend fun count(): Int = rows.size
    }

    /** A deterministic ChapterTextProvider with fixed segments (no TxtDocument dependency). */
    private class FakeTextProvider(private val segments: List<String>) : ChapterTextProvider {
        override fun units() = listOf(TranslationUnitId(TranslationUnitId.Kind.txtDocSegmentWindow, "0"))
        override fun sourceSegments(unit: TranslationUnitId) = segments
        override fun sourceText(unit: TranslationUnitId) = segments.joinToString("\n\n")
        override fun unitContaining(charOffsetUtf16: Int) = units().first()
        override fun unitAfter(unit: TranslationUnitId): TranslationUnitId? = null
    }

    private lateinit var dataStore: DataStore<Preferences>
    private lateinit var cipher: FakeCipher
    private lateinit var store: AiProviderStore
    private lateinit var dao: FakeDao

    @Before fun setUp() {
        dataStore = PreferenceDataStoreFactory.create { tmp.newFile("ai.preferences_pb") }
        cipher = FakeCipher()
        store = AiProviderStore(dataStore, cipher)
        dao = FakeDao()
    }

    private suspend fun addActiveProfile(
        id: String = "p1",
        model: String = "gpt-test",
        key: String = "s3cret",
        kind: AiProviderKind = AiProviderKind.openAiCompatible,
    ): AiProviderProfile =
        store.upsert(id, "Provider", kind, kind.defaultBaseUrl, model, 0.3, 1024, key)

    /** The service factory: a real service over the shared dao, bound to the passed client. */
    private fun serviceFactory(): (AiClient) -> ChapterTranslationService = { client ->
        ChapterTranslationService(client, ChapterTranslationStore(dao), promptVersion)
    }

    private fun prefetcher(
        segments: List<String>,
        clientFactory: (AiProviderProfile, String) -> AiClient,
    ) = ChapterTranslationPrefetcher(
        bookKey = bookKey,
        textProvider = FakeTextProvider(segments),
        store = store,
        serviceFactory = serviceFactory(),
        clientFactory = clientFactory,
    )

    private fun lookupKeyFor(unit: TranslationUnitId) =
        CachedTranslation.lookupKey(bookKey, unit.storageKey, lang, promptVersion)

    private fun seedCache(unit: TranslationUnitId, segments: List<String>, sourceCount: Int) {
        dao.rows[lookupKeyFor(unit)] = ChapterTranslationEntity(
            lookupKey = lookupKeyFor(unit),
            bookKey = bookKey,
            unitStorageKey = unit.storageKey,
            targetLanguage = lang,
            promptVersion = promptVersion,
            translatedJson = FakeAiClient.encodeJsonArray(segments),
            sourceParagraphCount = sourceCount,
            createdAt = 1L,
        )
    }

    // ── snapshot-consistent profile + key + injected factory ──

    @Test fun prefetch_usesActiveProfileKeyAndInjectedFactory() = runTest {
        addActiveProfile(key = "s3cret")
        val factoryCalls = mutableListOf<Pair<AiProviderProfile, String>>()
        val client = FakeAiClient.translating()
        val pf = prefetcher(listOf("Alpha.", "Beta.")) { profile, apiKey ->
            factoryCalls.add(profile to apiKey)
            client
        }

        val result = pf.prefetch(unit, lang)

        assertEquals(1, factoryCalls.size)                        // the injected factory was used
        assertEquals("p1", factoryCalls[0].first.id)              // resolved active profile
        assertEquals("s3cret", factoryCalls[0].second)            // snapshot-consistent decrypted key
        assertEquals(listOf("T:Alpha.", "T:Beta."), result.segments)
        assertTrue(client.callCount >= 1)                         // it actually translated
    }

    // ── the AiRequest is built from the profile (temperature / maxTokens carried through) ──

    @Test fun prefetch_buildsRequestFromProfile() = runTest {
        addActiveProfile(model = "gpt-test")
        val client = FakeAiClient.translating()
        prefetcher(listOf("Alpha.")) { _, _ -> client }.prefetch(unit, lang)

        val request: AiRequest = client.requests.first()
        assertEquals("gpt-test", request.model)                  // profile model
        assertEquals(0.3, request.temperature, 0.0)              // profile temperature
        assertEquals(1024, request.maxTokens)                    // profile maxTokens
    }

    // ── M3: blank model → kind.defaultModel ──

    @Test fun prefetch_blankModel_fallsBackToDefaultModel() = runTest {
        addActiveProfile(model = "", kind = AiProviderKind.openAiCompatible)   // blank model
        val client = FakeAiClient.translating()
        prefetcher(listOf("Alpha.")) { _, _ -> client }.prefetch(unit, lang)

        assertEquals(
            AiProviderKind.openAiCompatible.defaultModel,
            client.requests.first().model,
        )
    }

    @Test fun prefetch_blankModel_anthropic_fallsBackToItsDefault() = runTest {
        addActiveProfile(model = "  ", kind = AiProviderKind.anthropicNative)
        val client = FakeAiClient.translating()
        prefetcher(listOf("Alpha.")) { _, _ -> client }.prefetch(unit, lang)

        assertEquals(
            AiProviderKind.anthropicNative.defaultModel,
            client.requests.first().model,
        )
    }

    // ── #306: a cache HIT still returns with NO active provider ──

    @Test fun prefetch_cacheHitWithNoProvider_stillReturns() = runTest {
        // No profile added → no active provider. Seed a 2-segment cache row.
        seedCache(unit, listOf("cachedA", "cachedB"), sourceCount = 2)
        var factoryCalled = false
        val pf = prefetcher(listOf("Alpha.", "Beta.")) { _, _ -> factoryCalled = true; FakeAiClient.translating() }

        val result = pf.prefetch(unit, lang)
        assertEquals(listOf("cachedA", "cachedB"), result.segments)
        assertTrue(result.fromCache)
        assertTrue("no provider was built for a cache hit", !factoryCalled)
    }

    // ── cache-FIRST: a hit with an ACTIVE provider must NOT build a client or decrypt ──

    @Test fun prefetch_cacheHitWithActiveProvider_neverBuildsClient() = runTest {
        addActiveProfile(key = "s3cret")
        cipher.throwOnDecrypt = true                          // a broken cipher must NOT sink a cache hit
        seedCache(unit, listOf("hitA", "hitB"), sourceCount = 2)
        var factoryCalled = false
        val pf = prefetcher(listOf("Alpha.", "Beta.")) { _, _ -> factoryCalled = true; FakeAiClient.translating() }

        val result = pf.prefetch(unit, lang)                 // must NOT throw despite the broken cipher
        assertEquals(listOf("hitA", "hitB"), result.segments)
        assertTrue(result.fromCache)
        assertTrue("cache-first: no client built on a hit", !factoryCalled)
    }

    @Test fun prefetchDirect_cacheHitWithActiveProvider_neverBuildsClient() = runTest {
        addActiveProfile(key = "s3cret")
        cipher.throwOnDecrypt = true
        seedCache(unit, listOf("dA", "dB"), sourceCount = 2)
        var factoryCalled = false
        val pf = prefetcher(listOf("x")) { _, _ -> factoryCalled = true; FakeAiClient.translating() }

        val out = pf.prefetchDirect(unit, listOf("Enum1.", "Enum2."), lang)
        assertEquals(listOf("dA", "dB"), out)
        assertTrue("cache-first: no client built on a direct hit", !factoryCalled)
    }

    // ── a cache MISS with no active provider → ProviderFailed (not a crash) ──

    @Test fun prefetch_missWithNoProvider_isProviderFailed() = runTest {
        val pf = prefetcher(listOf("Alpha.")) { _, _ -> fail("factory must not be called"); throw AssertionError() }
        try {
            pf.prefetch(unit, lang)
            fail("a no-provider cache miss must throw")
        } catch (e: ChapterTranslationException) {
            assertTrue(e.error is ChapterTranslationError.ProviderFailed)
        }
    }

    // ── prefetchDirect translates the passed segments 1:1 ──

    @Test fun prefetchDirect_translatesGivenSegments1to1() = runTest {
        addActiveProfile()
        val client = FakeAiClient.translating()
        val pf = prefetcher(listOf("ignored")) { _, _ -> client }

        val out = pf.prefetchDirect(unit, listOf("Enum1.", "Enum2.", "Enum3."), lang)
        assertEquals(listOf("T:Enum1.", "T:Enum2.", "T:Enum3."), out)
    }

    @Test fun prefetchDirect_cacheHitWithNoProvider_returnsCached() = runTest {
        seedCache(unit, listOf("dA", "dB"), sourceCount = 2)
        val pf = prefetcher(listOf("x")) { _, _ -> fail("no provider"); throw AssertionError() }

        val out = pf.prefetchDirect(unit, listOf("Enum1.", "Enum2."), lang)   // count 2 matches
        assertEquals(listOf("dA", "dB"), out)
    }

    @Test fun prefetchDirect_missWithNoProvider_isProviderFailed() = runTest {
        val pf = prefetcher(listOf("x")) { _, _ -> fail("no provider"); throw AssertionError() }
        try {
            pf.prefetchDirect(unit, listOf("Enum1.", "Enum2."), lang)
            fail("a no-provider direct miss must throw")
        } catch (e: ChapterTranslationException) {
            assertTrue(e.error is ChapterTranslationError.ProviderFailed)
        }
    }

    // ── cachedDirect restores from cache with ZERO provider calls ──

    @Test fun cachedDirect_restoresWithZeroProviderCalls() = runTest {
        addActiveProfile()                                   // a provider IS active — must still not be called
        seedCache(unit, listOf("rA", "rB"), sourceCount = 2)
        var factoryCalled = false
        val pf = prefetcher(listOf("x")) { _, _ -> factoryCalled = true; FakeAiClient.translating() }

        val restored = pf.cachedDirect(unit, expectedCount = 2, targetLanguage = lang)
        assertNotNull(restored)
        assertEquals(listOf("rA", "rB"), restored!!.segments)
        assertTrue(restored.fromCache)
        assertTrue("cachedDirect must never build a provider client", !factoryCalled)
    }

    @Test fun cachedDirect_countMismatch_returnsNull() = runTest {
        seedCache(unit, listOf("rA", "rB"), sourceCount = 2)
        val pf = prefetcher(listOf("x")) { _, _ -> FakeAiClient.translating() }
        assertNull(pf.cachedDirect(unit, expectedCount = 3, targetLanguage = lang))   // 3 != stored 2
    }

    @Test fun cachedDirect_miss_returnsNull() = runTest {
        val pf = prefetcher(listOf("x")) { _, _ -> FakeAiClient.translating() }
        assertNull(pf.cachedDirect(unit, expectedCount = 2, targetLanguage = lang))
    }

    // ── cipher throw while resolving the key → ProviderFailed, never a crash ──

    @Test fun prefetch_cipherThrow_mapsToProviderFailed() = runTest {
        addActiveProfile(key = "s3cret")
        cipher.throwOnDecrypt = true                          // keystore/cipher failure on decrypt
        val pf = prefetcher(listOf("Alpha.")) { _, _ -> fail("factory must not be reached"); throw AssertionError() }
        try {
            pf.prefetch(unit, lang)
            fail("a cipher failure must surface as a typed error, not a crash")
        } catch (e: ChapterTranslationException) {
            assertTrue(e.error is ChapterTranslationError.ProviderFailed)
        }
    }
}
