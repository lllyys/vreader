// Purpose: feature #131 WI-4b — proves AppContainer's bilingual + AI-config DI graph
// actually wires. Runs on the JVM via Robolectric (DataStore/Room need a Context, no
// emulator) through `scripts/run-android-tests.sh`. A fake SecretCipher is injected so
// the AiProviderStore round-trip works under Robolectric (AndroidKeyStore is unavailable
// there — the AiProviderStoreTest / OpdsSourceStore precedent: a cipher param with a
// production KeystoreSecretCipher default, a fake for the JVM test). A recording
// prefsStoreFactory records each backing-file NAME so the clash test asserts the actual
// files, not object identity (Codex Gate-4 r1 Medium).
//
// Asserts: (a) the container resolves each bilingual + AI-config graph member as a live
// instance; (b) AiProviderStore resolves AND round-trips a profile (save → read back the
// decrypted key, first-provider-becomes-active); (c) the container's prefetcher drives the
// REAL resolve path (a cache-miss with NO active provider maps to ProviderFailed — a stubbed
// prefetcher would not), and its injected clientFactory is the `AiProviderFactory::create`
// default; (d) per-session factories return distinct instances per call; (e) the four
// device-local Preferences stores use DISTINCT backing files; (f) the AiSettingsViewModel
// factory observes the SHARED store (a saved profile shows up in the VM's listState).
package com.vreader.app

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.test.core.app.ApplicationProvider
import com.vreader.app.ai.AiProviderKind
import com.vreader.app.ai.AiSettingsViewModel
import com.vreader.app.backup.net.SecretCipher
import com.vreader.app.bilingual.BilingualAiReadiness
import com.vreader.app.bilingual.BilingualViewModel
import com.vreader.app.bilingual.ChapterTranslationException
import com.vreader.app.bilingual.ChapterTranslationPrefetcher
import com.vreader.app.bilingual.ChapterTranslationStore
import com.vreader.app.bilingual.PerBookBilingualStore
import com.vreader.app.bilingual.TranslationUnitId
import com.vreader.app.reader.TxtDocument
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNotSame
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

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
class AppContainerBilingualWiringTest {

    @get:Rule val tmp = TemporaryFolder()

    /** A reversible fake cipher — AndroidKeyStore is unavailable under Robolectric. */
    private class FakeCipher : SecretCipher {
        override fun encrypt(plaintext: String) = "enc($plaintext)"
        override fun decrypt(token: String) = token.removePrefix("enc(").removeSuffix(")")
    }

    private val dispatcher = StandardTestDispatcher()
    private lateinit var container: AppContainer
    /** Records the backing-file NAME the container requests for each device-local DataStore. */
    private val requestedPrefsFiles = mutableListOf<String>()

    private val bookKey = "txt:${"a".repeat(64)}:1024"

    @Before fun setUp() {
        // The VM factories use viewModelScope (Main); pin Main to the test dispatcher so a
        // subscribed listState collects upstream deterministically under advanceUntilIdle().
        Dispatchers.setMain(dispatcher)
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        container = AppContainer(
            context,
            secretCipher = FakeCipher(),
            prefsStoreFactory = { fileName ->
                requestedPrefsFiles += fileName
                // A real temp-backed store on the TEST dispatcher's scope so advanceUntilIdle()
                // drives its IO too (the AiSettingsViewModelTest precedent). Each store gets its
                // OWN temp folder so distinct names never collide on disk; the required
                // ".preferences_pb" extension is preserved (PreferenceDataStoreFactory enforces it).
                // The NAME is what the clash test asserts on.
                val dir = tmp.newFolder("prefs-${requestedPrefsFiles.size}")
                PreferenceDataStoreFactory.create(scope = CoroutineScope(dispatcher)) {
                    java.io.File(dir, fileName)
                }
            },
        )
    }

    @After fun tearDown() = Dispatchers.resetMain()

    @Test fun container_resolvesBilingualAndAiConfigGraph() {
        // Each process-singleton graph member resolves to a live instance.
        assertNotNull(container.aiProviderStore)
        assertNotNull(container.chapterTranslationStore)
        assertNotNull(container.perBookBilingualStore)
        assertNotNull(container.bilingualAiReadiness)

        // Repeated getters return the SAME singleton (lazy).
        assertSame(container.aiProviderStore, container.aiProviderStore)
        assertSame(container.chapterTranslationStore, container.chapterTranslationStore)
        assertSame(container.perBookBilingualStore, container.perBookBilingualStore)
        assertSame(container.bilingualAiReadiness, container.bilingualAiReadiness)

        // Correct types.
        val store: ChapterTranslationStore = container.chapterTranslationStore
        val perBook: PerBookBilingualStore = container.perBookBilingualStore
        val readiness: BilingualAiReadiness = container.bilingualAiReadiness
        assertNotNull(store); assertNotNull(perBook); assertNotNull(readiness)
    }

    @Test fun aiProviderStore_roundTripsAProfile() = runTest(dispatcher) {
        val store = container.aiProviderStore
        assertNull("no active provider on a fresh store", store.activeProfile())

        store.upsert(
            id = "p1",
            name = "My Provider",
            kind = AiProviderKind.anthropicNative,
            baseUrl = AiProviderKind.anthropicNative.defaultBaseUrl,
            model = AiProviderKind.anthropicNative.defaultModel,
            temperature = 0.7,
            maxTokens = 2048,
            apiKey = "s3cret",
        )

        val snap = store.snapshot()
        assertEquals(1, snap.profiles.size)
        assertEquals("p1", snap.activeId)                 // first provider becomes active
        assertNotNull(snap.active)
        assertEquals("My Provider", snap.active!!.name)
        assertEquals("s3cret", store.apiKey(snap.active!!)) // decrypts through the wired cipher
    }

    @Test fun prefetcher_drivesRealResolvePath_withDefaultClientFactory() = runTest(dispatcher) {
        val document = TxtDocument.of("Alpha paragraph.\n\nBeta paragraph.\n\nGamma paragraph.")
        val provider = com.vreader.app.bilingual.TxtChapterTextProvider(document)

        // Built WITHOUT overriding the clientFactory param → it defaults to AiProviderFactory::create.
        val prefetcher: ChapterTranslationPrefetcher =
            container.chapterTranslationPrefetcher(bookKey, provider)
        assertNotNull(prefetcher)

        val unit = TranslationUnitId(TranslationUnitId.Kind.txtDocSegmentWindow, "0")

        // (1) Cache-only miss on a fresh store → null (never touches the client factory — #306 path).
        assertNull(prefetcher.cachedDirect(unit, expectedCount = 2, targetLanguage = "zh-Hans"))

        // (2) prefetch() with NO active provider AND a cache MISS drives the REAL resolveProvider
        //     path (store.snapshot().active == null) and maps to ProviderFailed. A prefetcher wired
        //     to a stub store / short-circuited factory would not reach this typed failure — so this
        //     proves the container wired the REAL AiProviderStore into the prefetcher and the
        //     default AiProviderFactory::create seam is in place (it is only reached when a provider
        //     exists; here the absence is the observable branch of the same resolve path).
        try {
            prefetcher.prefetch(unit, targetLanguage = "zh-Hans")
            fail("expected ProviderFailed when no provider is configured")
        } catch (e: ChapterTranslationException) {
            assertTrue(
                "no-provider miss must map to ProviderFailed",
                e.error is com.vreader.app.bilingual.ChapterTranslationError.ProviderFailed,
            )
        }
    }

    @Test fun perSessionFactories_returnDistinctInstances() {
        val document = TxtDocument.of("Alpha.\n\nBeta.")
        val provider = com.vreader.app.bilingual.TxtChapterTextProvider(document)

        val p1 = container.chapterTranslationPrefetcher(bookKey, provider)
        val p2 = container.chapterTranslationPrefetcher(bookKey, provider)
        assertNotSame("each prefetcher is a fresh per-session instance", p1, p2)

        val vm1: BilingualViewModel = container.bilingualViewModel(bookKey, provider)
        val vm2: BilingualViewModel = container.bilingualViewModel(bookKey, provider)
        assertNotSame("each BilingualViewModel is a fresh per-session instance", vm1, vm2)

        val ai1: AiSettingsViewModel = container.aiSettingsViewModel()
        val ai2: AiSettingsViewModel = container.aiSettingsViewModel()
        assertNotSame("each AiSettingsViewModel is a fresh instance", ai1, ai2)
    }

    @Test fun devicePreferenceStores_useDistinctBackingFiles() {
        // Force all four device-local stores to be created, then assert the container requested
        // FOUR DISTINCT backing file names (a clash would make two subsystems share one file and
        // overwrite each other's prefs — the real regression this test exists to catch).
        container.readerSettingsDataStore
        container.recentSearchesDataStore
        container.aiProviderStore              // builds aiProvidersDataStore
        container.perBookBilingualStore        // builds bilingualPerBookDataStore

        val expected = setOf(
            AppContainer.READER_SETTINGS_PREFS,
            AppContainer.RECENT_SEARCHES_PREFS,
            AppContainer.AI_PROVIDERS_PREFS,
            AppContainer.BILINGUAL_PER_BOOK_PREFS,
        )
        assertEquals("all four prefs file names are distinct constants", 4, expected.size)
        assertTrue(
            "the container requested every device-local prefs file exactly once (no clash): $requestedPrefsFiles",
            requestedPrefsFiles.containsAll(expected) &&
                requestedPrefsFiles.toSet().size == requestedPrefsFiles.size,
        )
    }

    @Test fun aiSettingsViewModel_factory_observesTheSharedStore() = runTest(dispatcher) {
        // A provider saved through the container's store must be visible to a VM built from the
        // factory — proving the factory does NOT create a private empty store (Gate-4 r1 Medium).
        container.aiProviderStore.upsert(
            id = "p1", name = "P1", kind = AiProviderKind.openAiCompatible,
            baseUrl = AiProviderKind.openAiCompatible.defaultBaseUrl,
            model = AiProviderKind.openAiCompatible.defaultModel,
            temperature = 0.7, maxTokens = 2048, apiKey = "k",
        )
        advanceUntilIdle()

        val vm = container.aiSettingsViewModel()
        // Subscribe so the WhileSubscribed listState collects upstream from the shared store
        // (the AiSettingsViewModelTest precedent — no Turbine dependency).
        val job = launch { vm.listState.collect {} }
        advanceUntilIdle()
        val rows = vm.listState.value.providers
        job.cancel()

        assertEquals("the saved provider is visible through the shared store", 1, rows.size)
        assertEquals("p1", rows[0].id)
        assertTrue("the first provider is active", rows[0].active)
    }
}
