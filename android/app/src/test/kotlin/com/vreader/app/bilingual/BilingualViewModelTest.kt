// Purpose: feature #131 WI-5 — RED-first JVM tests for the BilingualViewModel STATE CORE
// (setters + first-enable setup-sheet + aiConfigured + generation bump on disable/language).
// The prefetch trigger + single-flight are WI-6 (stubbed here). Follows the project
// ViewModel-test convention: Dispatchers.setMain(StandardTestDispatcher) + runTest(dispatcher)
// + advanceUntilIdle() + asserting on state.value (the AiChatViewModelTest precedent; the repo
// has no Turbine dependency, so StateFlow is asserted directly on its .value after draining
// the test dispatcher). Fakes: a fake AiProviderSnapshot provider + a fake readiness + a fake
// ChapterTranslationPrefetcher seam (held for WI-6, unused by WI-5 logic).
package com.vreader.app.bilingual

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.test.core.app.ApplicationProvider
import com.vreader.app.ai.AiProviderKind
import com.vreader.app.ai.AiProviderProfile
import com.vreader.app.ai.AiProviderSnapshot
import com.vreader.app.ai.AiProviderStore
import com.vreader.app.backup.net.SecretCipher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
class BilingualViewModelTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val dispatcher = StandardTestDispatcher()

    private val bookKey = "epub:abc:100"

    private lateinit var storeDataStore: DataStore<Preferences>
    private lateinit var perBookStore: PerBookBilingualStore

    private val cipher = object : SecretCipher {
        override fun encrypt(plaintext: String) = "enc($plaintext)"
        override fun decrypt(token: String) = token.removePrefix("enc(").removeSuffix(")")
    }
    private lateinit var aiStore: AiProviderStore
    private lateinit var readiness: BilingualAiReadiness

    // A controllable snapshot provider — the injected seam (Medium-4). WI-6 wires the real one.
    private var currentSnapshot = AiProviderSnapshot(emptyList(), activeId = null)
    private val snapshotProvider: suspend () -> AiProviderSnapshot = { currentSnapshot }

    // A fake prefetcher seam held by the VM for WI-6; WI-5 never invokes it.
    private lateinit var prefetcher: ChapterTranslationPrefetcher

    @Before fun setUp() {
        Dispatchers.setMain(dispatcher)
        val file = java.io.File(context.cacheDir, "vm-bilingual-${System.nanoTime()}.preferences_pb")
        storeDataStore = PreferenceDataStoreFactory.create(scope = CoroutineScope(dispatcher)) { file }
        perBookStore = PerBookBilingualStore(storeDataStore)

        aiStore = AiProviderStore(
            PreferenceDataStoreFactory.create(scope = CoroutineScope(dispatcher)) {
                java.io.File(context.cacheDir, "vm-ai-${System.nanoTime()}.preferences_pb")
            },
            cipher,
        )
        readiness = BilingualAiReadiness(aiStore)
        prefetcher = ChapterTranslationPrefetcher(
            bookKey = bookKey,
            textProvider = EmptyTextProvider,
            store = aiStore,
            serviceFactory = { throw IllegalStateException("WI-5 must not build a service") },
            clientFactory = { _, _ -> throw IllegalStateException("WI-5 must not build a client") },
        )
    }

    @After fun tearDown() = Dispatchers.resetMain()

    private fun makeVM() = BilingualViewModel(
        bookKey = bookKey,
        store = perBookStore,
        prefetcher = prefetcher,
        snapshotProvider = snapshotProvider,
        readiness = readiness,
        dispatcher = dispatcher,
    )

    private fun profile(id: String, key: String) = AiProviderProfile(
        id = id, name = "P", kind = AiProviderKind.openAiCompatible, baseUrl = "https://x/", model = "m",
        encryptedApiKey = cipher.encrypt(key),
    )

    private fun configureActiveProvider() {
        currentSnapshot = AiProviderSnapshot(listOf(profile("p1", "s3cret")), activeId = "p1")
    }

    // ── first enable raises the setup sheet ──

    @Test fun firstEnable_raisesSetupSheet() = runTest(dispatcher) {
        val vm = makeVM()
        advanceUntilIdle()
        assertFalse("off by default", vm.state.value.enabled)
        assertFalse("no sheet at rest", vm.state.value.needsSetupSheet)

        vm.setEnabled(on = true); advanceUntilIdle()
        assertTrue(vm.state.value.enabled)
        assertTrue("first enable raises the setup sheet", vm.state.value.needsSetupSheet)
    }

    // ── re-enabling an already-persisted-enabled book does NOT re-raise the sheet ──

    @Test fun reEnablePersistedEnabled_doesNotRaiseSheet() = runTest(dispatcher) {
        // Seed the store: the book is ALREADY enabled on disk from a prior session.
        perBookStore.write(bookKey, PerBookBilingualConfig(enabled = true, targetLanguage = "Chinese", granularity = TranslationGranularity.paragraph))

        val vm = makeVM()
        advanceUntilIdle()
        assertTrue("hydrated as enabled", vm.state.value.enabled)
        assertFalse("hydration does NOT raise the sheet", vm.state.value.needsSetupSheet)

        // And an explicit re-enable AFTER hydration must not raise it either (Gate-4 Low —
        // the was-off→on transition is computed from the HYDRATED state, not the default).
        vm.setEnabled(on = true); advanceUntilIdle()
        assertFalse("re-enabling an already-enabled book does NOT raise the sheet", vm.state.value.needsSetupSheet)
    }

    // ── a setter racing the initial hydration read still observes the hydrated state (Gate-4 Medium-1) ──

    @Test fun setterRacingHydration_doesNotClobberPersistedState() = runTest(dispatcher) {
        // Seed the store enabled/French, so hydration would flip a default-constructed state.
        perBookStore.write(bookKey, PerBookBilingualConfig(enabled = true, targetLanguage = "French", granularity = TranslationGranularity.paragraph))

        val vm = makeVM()
        // Fire a setter IMMEDIATELY, before draining the dispatcher — it races hydration.
        vm.setTargetLanguage("German")
        advanceUntilIdle()

        // The setter must win the FINAL state (it ran after hydration under the mutation lock),
        // and hydration must NOT have clobbered it back to French.
        assertTrue("enabled preserved from hydration", vm.state.value.enabled)
        assertEquals("German", vm.state.value.targetLanguage.key)
        assertEquals("German", perBookStore.read(bookKey).targetLanguage)
    }

    // ── rapid setters persist in call order — no older config wins the last DataStore write (Gate-4 Medium-2) ──

    @Test fun rapidSetters_persistInCallOrder() = runTest(dispatcher) {
        val vm = makeVM()
        advanceUntilIdle()
        vm.setEnabled(on = true)
        vm.setTargetLanguage("French")
        vm.setTargetLanguage("Russian")            // the LAST call must be the persisted value
        advanceUntilIdle()
        assertEquals("Russian", vm.state.value.targetLanguage.key)
        assertEquals("Russian", perBookStore.read(bookKey).targetLanguage)
        assertTrue(perBookStore.read(bookKey).enabled)
    }

    // ── disable clears shaped translation state + bumps generation ──

    @Test fun disable_clearsShapedState_bumpsGeneration() = runTest(dispatcher) {
        val vm = makeVM()
        advanceUntilIdle()
        vm.setEnabled(on = true); advanceUntilIdle()
        val genBefore = vm.generation

        // Simulate WI-6 having populated shaped render state (test-only seam).
        vm.debugSeedShapedState()
        assertTrue(vm.state.value.translationsByUnit.isNotEmpty())

        vm.setEnabled(on = false); advanceUntilIdle()
        assertFalse(vm.state.value.enabled)
        assertTrue("shaped translations cleared on disable", vm.state.value.translationsByUnit.isEmpty())
        assertTrue(vm.state.value.inFlightUnits.isEmpty())
        assertTrue(vm.state.value.unavailableUnits.isEmpty())
        assertNull(vm.state.value.errorUnit)
        assertTrue("generation bumps on disable", vm.generation > genBefore)
    }

    // ── a language change resets: clears shaped state + bumps generation ──

    @Test fun languageChange_resetsShapedState_bumpsGeneration() = runTest(dispatcher) {
        val vm = makeVM()
        advanceUntilIdle()
        vm.setEnabled(on = true); advanceUntilIdle()
        vm.debugSeedShapedState()
        val genBefore = vm.generation

        vm.setTargetLanguage("Japanese"); advanceUntilIdle()
        assertEquals("Japanese", vm.state.value.targetLanguage.key)
        assertTrue("a language change clears translations (they are re-keyed)", vm.state.value.translationsByUnit.isEmpty())
        assertTrue(vm.state.value.inFlightUnits.isEmpty())
        assertNull(vm.state.value.errorUnit)
        assertTrue("generation bumps on a language change", vm.generation > genBefore)
        // And it persisted:
        assertEquals("Japanese", perBookStore.read(bookKey).targetLanguage)
    }

    // ── aiConfigured true when the readiness gate passes ──

    @Test fun aiConfigured_true_whenReady() = runTest(dispatcher) {
        configureActiveProvider()
        val vm = makeVM()
        vm.refreshAiConfigured(); advanceUntilIdle()
        assertTrue(vm.state.value.aiConfigured)
    }

    // ── aiConfigured false when there is no active provider ──

    @Test fun aiConfigured_false_whenNoProvider() = runTest(dispatcher) {
        currentSnapshot = AiProviderSnapshot(emptyList(), activeId = null)
        val vm = makeVM()
        vm.refreshAiConfigured(); advanceUntilIdle()
        assertFalse(vm.state.value.aiConfigured)
    }

    // ── setters persist through the store (round-trip) ──

    @Test fun setters_roundTripThroughStore() = runTest(dispatcher) {
        val vm = makeVM()
        advanceUntilIdle()
        vm.setEnabled(on = true); advanceUntilIdle()
        vm.setTargetLanguage("French"); advanceUntilIdle()

        val onDisk = perBookStore.read(bookKey)
        assertTrue(onDisk.enabled)
        assertEquals("French", onDisk.targetLanguage)
        assertEquals(TranslationGranularity.paragraph, onDisk.granularity)
    }

    // ── granularity stays paragraph in v1 ──

    @Test fun granularity_staysParagraph() = runTest(dispatcher) {
        val vm = makeVM()
        advanceUntilIdle()
        vm.setEnabled(on = true); advanceUntilIdle()
        assertEquals(TranslationGranularity.paragraph, vm.state.value.granularity)
        assertEquals(TranslationGranularity.paragraph, perBookStore.read(bookKey).granularity)
    }

    // ── dismissSetupSheet lowers the flag ──

    @Test fun dismissSetupSheet_lowersFlag() = runTest(dispatcher) {
        val vm = makeVM()
        advanceUntilIdle()
        vm.setEnabled(on = true); advanceUntilIdle()
        assertTrue(vm.state.value.needsSetupSheet)
        vm.dismissSetupSheet(); advanceUntilIdle()
        assertFalse(vm.state.value.needsSetupSheet)
    }

    // ── no `style` field on the UI state ──

    @Test fun uiState_noStyleField() {
        val members = BilingualUiState::class.members.map { it.name }.toSet()
        assertFalse("BilingualUiState must NOT carry a `style` field", members.contains("style"))
    }

    /** A no-op text provider — the prefetcher seam is never invoked by WI-5. */
    private object EmptyTextProvider : ChapterTextProvider {
        override fun units(): List<TranslationUnitId> = emptyList()
        override fun sourceSegments(unit: TranslationUnitId): List<String> = emptyList()
        override fun sourceText(unit: TranslationUnitId): String = ""
        override fun unitContaining(charOffsetUtf16: Int): TranslationUnitId? = null
        override fun unitAfter(unit: TranslationUnitId): TranslationUnitId? = null
    }
}
