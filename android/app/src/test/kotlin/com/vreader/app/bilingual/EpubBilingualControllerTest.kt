// Purpose: feature #131 WI-7b — RED-first JVM tests for EpubBilingualController (the single
// owner of an EPUB unit: enumerate → cachedDirect | prefetchDirect → session-token-guarded
// commit → inject, all under a Mutex, on a fake evaluateJavascript). Covers the Medium-1
// single-owner sequence + the race contract: a stale session token discards silently (no
// commit, no inject, NO errorUnit); cachedDirect restores with ZERO provider calls; a cache
// miss uses prefetchDirect (count-divergence direct path); the probe-gated re-apply re-injects
// only when the DOM is missing decorations; clear removes decorations + is idempotent; an empty
// enumeration is source-only (no inject, no crash); a translate failure is source-only (no
// errorUnit); the committed translation publishes ONCE into VM render state (single writer).
// Robolectric-run for the ICU segmenter behind the real ChapterTranslationService.
package com.vreader.app.bilingual

import com.vreader.app.ai.AiClient
import com.vreader.app.ai.AiProviderKind
import com.vreader.app.ai.AiProviderProfile
import com.vreader.app.ai.AiProviderStore
import com.vreader.app.backup.net.SecretCipher
import com.vreader.app.data.ChapterTranslationDao
import com.vreader.app.data.ChapterTranslationEntity
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class EpubBilingualControllerTest {

    @get:Rule val tmp = TemporaryFolder()

    private val bookKey = "epub:${"a".repeat(64)}:2048"
    private val lang = "zh-Hans"
    private val promptVersion = "bilingual-v1|g=paragraph"
    private val unit = TranslationUnitId(TranslationUnitId.Kind.epubHref, "OEBPS/ch1.xhtml")

    private class FakeCipher : SecretCipher {
        override fun encrypt(plaintext: String) = "enc($plaintext)"
        override fun decrypt(token: String) = token.removePrefix("enc(").removeSuffix(")")
    }

    private class FakeDao : ChapterTranslationDao {
        val rows = LinkedHashMap<String, ChapterTranslationEntity>()
        override suspend fun getByLookupKey(key: String): ChapterTranslationEntity? = rows[key]
        override suspend fun upsert(row: ChapterTranslationEntity) { rows[row.lookupKey] = row }
        override suspend fun deleteByLookupKey(key: String) { rows.remove(key) }
        override suspend fun count(): Int = rows.size
    }

    /**
     * A scriptable evaluateJavascript that simulates a resource DOM: `enumScript` returns a
     * fixed `[{id,text}]` array; `injectScript` records the injected id→translation map + a
     * decoration count; `clearScript` empties it; `decorationCountScript` returns the current
     * count. Records the ordered script "kinds" so a test can assert the sequence.
     */
    private class FakeWebView(private val enumJson: String) {
        var decorations: Int = 0
        var lastInjectedCount: Int = 0
        val evalKinds = mutableListOf<String>()

        suspend fun eval(js: String): String? {
            return when {
                js.contains("out.push({ id: bid") -> { evalKinds.add("enum"); enumJson }
                js.contains("return count;") -> {
                    evalKinds.add("inject")
                    // Count the entries in the injected `ids` array (the number of translated
                    // blocks). The real inject returns a JS count of injected decorations.
                    val idsJson = js.substringAfter("var ids = ").substringBefore(";").trim()
                    val n = org.json.JSONArray(idsJson).length()
                    lastInjectedCount = n
                    decorations = n
                    n.toString()
                }
                js.contains("removeChild") -> { evalKinds.add("clear"); decorations = 0; "0" }
                js.contains("return document.querySelectorAll('.vreader-bilingual") &&
                    !js.contains("removeChild") -> { evalKinds.add("probe"); decorations.toString() }
                js.contains("vreader-bilingual-style") -> { evalKinds.add("style"); null }
                else -> { evalKinds.add("other"); null }
            }
        }
    }

    private lateinit var dataStore: DataStore<Preferences>
    private lateinit var store: AiProviderStore
    private lateinit var dao: FakeDao
    private var providerCalls = 0

    @Before fun setUp() {
        dataStore = PreferenceDataStoreFactory.create { tmp.newFile("ai.preferences_pb") }
        store = AiProviderStore(dataStore, FakeCipher())
        dao = FakeDao()
        providerCalls = 0
    }

    private suspend fun addActiveProfile() {
        store.upsert("p1", "Provider", AiProviderKind.openAiCompatible,
            AiProviderKind.openAiCompatible.defaultBaseUrl, "gpt-test", 0.3, 1024, "s3cret")
    }

    /** A provider client that counts every chat() (so a test can assert ZERO provider calls).
     *  [onChat] fires inside the translate step (before the controller's post-translate token
     *  re-check) so a race test can bump the session mid-flight. */
    private var onChat: (() -> Unit)? = null
    private fun countingClient(): AiClient = FakeAiClient { request, _ ->
        providerCalls += 1
        onChat?.invoke()
        val sources = FakeAiClient.extractSources(FakeAiClient.userText(request))
        com.vreader.app.ai.AiResponse(FakeAiClient.encodeJsonArray(sources.map { "T:$it" }))
    }

    private fun serviceFactory(): (AiClient) -> ChapterTranslationService = { client ->
        ChapterTranslationService(client, ChapterTranslationStore(dao), promptVersion)
    }

    private fun prefetcher(): ChapterTranslationPrefetcher = ChapterTranslationPrefetcher(
        bookKey = bookKey,
        textProvider = EpubChapterTextProvider(listOf(unit.value)),
        store = store,
        serviceFactory = serviceFactory(),
        clientFactory = { _, _ -> countingClient() },
    )

    private fun seedCache(segments: List<String>, sourceCount: Int) {
        val key = CachedTranslation.lookupKey(bookKey, unit.storageKey, lang, promptVersion)
        dao.rows[key] = ChapterTranslationEntity(
            lookupKey = key, bookKey = bookKey, unitStorageKey = unit.storageKey,
            targetLanguage = lang, promptVersion = promptVersion,
            translatedJson = FakeAiClient.encodeJsonArray(segments),
            sourceParagraphCount = sourceCount, createdAt = 1L,
        )
    }

    private val enumTwoBlocks =
        """{"doc":"file:///OEBPS/ch1.xhtml","blocks":[{"id":"b1","text":"Alpha."},{"id":"b2","text":"Beta."}]}"""

    private fun controller(
        web: FakeWebView,
        committed: MutableList<Pair<TranslationUnitId, List<String>>> = mutableListOf(),
    ) = EpubBilingualController(
        evaluateJavascript = { web.eval(it) },
        prefetcher = prefetcher(),
        onEpubBlocksEnumerated = { u, segs -> committed.add(u to segs) },
    )

    // ── cache restore = ZERO provider calls (recreation path) ──

    @Test fun apply_restoresFromCache_withZeroProviderCalls() = runTest {
        seedCache(listOf("译文1", "译文2"), sourceCount = 2)
        val web = FakeWebView(enumTwoBlocks)
        val committed = mutableListOf<Pair<TranslationUnitId, List<String>>>()
        controller(web, committed).apply(unit, lang)

        assertEquals("cache restore hits — no provider", 0, providerCalls)
        assertEquals("injected both decorations", 2, web.lastInjectedCount)
        assertEquals("committed once into VM render state", listOf(unit to listOf("译文1", "译文2")), committed)
        assertTrue("enum ran before inject", web.evalKinds.indexOf("enum") < web.evalKinds.indexOf("inject"))
    }

    // ── cache miss → prefetchDirect (count-divergence direct path) ──

    @Test fun apply_onCacheMiss_translatesViaPrefetchDirect() = runTest {
        addActiveProfile()
        val web = FakeWebView(enumTwoBlocks)
        val committed = mutableListOf<Pair<TranslationUnitId, List<String>>>()
        controller(web, committed).apply(unit, lang)

        assertTrue("provider was called for the miss", providerCalls > 0)
        assertEquals("1:1 direct translation of the enumerated blocks", listOf("T:Alpha.", "T:Beta."), committed.single().second)
        assertEquals(2, web.lastInjectedCount)
    }

    // ── race: a stale session token discards silently ──

    @Test fun apply_staleSessionAfterTranslate_discards_noInject_noCommit() = runTest {
        addActiveProfile()
        val web = FakeWebView(enumTwoBlocks)
        val committed = mutableListOf<Pair<TranslationUnitId, List<String>>>()
        val c = controller(web, committed)
        // Bump the session DURING the translate step (before the controller's post-translate
        // token re-check) — a navigator recreate / language change racing the in-flight apply.
        onChat = { c.bumpSession() }
        c.apply(unit, lang)

        // The inject eval never ran (the guard returned right after translate).
        assertFalse("no inject after a stale-token discard", web.evalKinds.contains("inject"))
        assertEquals("no decorations injected on a stale apply", 0, web.decorations)
        assertTrue("nothing committed to VM render state on a stale apply", committed.isEmpty())
    }

    // ── empty enumeration = source-only, no crash ──

    @Test fun apply_emptyEnumeration_isSourceOnly_noInject() = runTest {
        seedCache(listOf("译文1"), sourceCount = 1)
        val web = FakeWebView("[]")
        val committed = mutableListOf<Pair<TranslationUnitId, List<String>>>()
        controller(web, committed).apply(unit, lang)

        assertFalse("no inject when there are no leaf blocks", web.evalKinds.contains("inject"))
        assertTrue("nothing committed", committed.isEmpty())
        assertEquals("no provider call on an empty resource", 0, providerCalls)
    }

    // ── translate failure = source-only, NO errorUnit ──

    @Test fun apply_noProviderAndCacheMiss_isSourceOnly_noCrash() = runTest {
        // No active profile AND no cache → prefetchDirect throws ProviderFailed → source-only.
        val web = FakeWebView(enumTwoBlocks)
        val committed = mutableListOf<Pair<TranslationUnitId, List<String>>>()
        controller(web, committed).apply(unit, lang)

        assertFalse("no inject when translate failed", web.evalKinds.contains("inject"))
        assertTrue("no commit on a translate failure (source-only)", committed.isEmpty())
    }

    // ── clear removes decorations + is idempotent ──

    @Test fun clear_removesDecorations_isIdempotent() = runTest {
        seedCache(listOf("译文1", "译文2"), sourceCount = 2)
        val web = FakeWebView(enumTwoBlocks)
        val c = controller(web)
        c.apply(unit, lang)
        assertEquals(2, web.decorations)
        c.clear()
        assertEquals("clear removed all decorations", 0, web.decorations)
        c.clear()   // idempotent — no crash on a clean DOM
        assertEquals(0, web.decorations)
    }

    // ── probe-gated re-apply: skips when DOM already has the decorations ──

    @Test fun reapplyIfNeeded_skipsWhenDomHasDecorations() = runTest {
        seedCache(listOf("译文1", "译文2"), sourceCount = 2)
        val web = FakeWebView(enumTwoBlocks)
        val c = controller(web)
        c.apply(unit, lang)
        val callsAfterApply = web.evalKinds.count { it == "inject" }
        c.reapplyIfNeeded(unit, lang, expectedCount = 2)   // DOM already has 2 → probe, no re-inject
        assertEquals("no re-inject when the DOM already has the decorations",
            callsAfterApply, web.evalKinds.count { it == "inject" })
        assertTrue("the probe ran", web.evalKinds.contains("probe"))
    }

    @Test fun reapplyIfNeeded_reinjectsWhenDomLostDecorations() = runTest {
        seedCache(listOf("译文1", "译文2"), sourceCount = 2)
        val web = FakeWebView(enumTwoBlocks)
        val c = controller(web)
        c.apply(unit, lang)
        web.decorations = 0   // simulate a recreate/href-change that dropped the decorations
        c.reapplyIfNeeded(unit, lang, expectedCount = 2)
        assertEquals("re-injected after the DOM lost decorations", 2, web.decorations)
    }

    // ── WI-9 finding (b): a mid-book language change reconciles the CURRENT resource ──

    /** reconcileLanguageChange bumps the session AND re-injects the current resource for the new language
     *  UNCONDITIONALLY (even when the DOM already has the old-language decorations — a probe would wrongly
     *  skip it), reaping the old-language decorations via the full re-enumerate/re-inject. */
    @Test fun reconcileLanguageChange_bumpsSession_reinjectsCurrentResource() = runTest {
        seedCache(listOf("译文1", "译文2"), sourceCount = 2)
        val web = FakeWebView(enumTwoBlocks)
        val committed = mutableListOf<Pair<TranslationUnitId, List<String>>>()
        val c = controller(web, committed)
        c.apply(unit, lang)
        val sessionBefore = c.currentSession
        val injectsBefore = web.evalKinds.count { it == "inject" }
        // A language change while the DOM STILL has the old decorations — a probe-gated reapply would skip,
        // but reconcile must re-inject unconditionally so the visible DOM reconciles (finding b).
        c.reconcileLanguageChange(unit, lang)
        assertTrue("the session was bumped (old in-flight applies invalidated)", c.currentSession > sessionBefore)
        assertTrue("reconcile re-injected the current resource",
            web.evalKinds.count { it == "inject" } > injectsBefore)
        // the reconciled resource re-committed into VM render state (the pill/state stays honest).
        assertEquals("re-committed the reconciled unit", unit, committed.last().first)
    }
}
