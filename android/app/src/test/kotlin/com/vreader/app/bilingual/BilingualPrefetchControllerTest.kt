// Purpose: feature #131 WI-6 — controller-direct regression tests for BilingualPrefetchController's
// LAUNCH LIFECYCLE (Gate-4 r2/r3): (1) an EAGER dispatcher (Dispatchers.Main.immediate analog —
// UnconfinedTestDispatcher runs the body at launch) must not hit the `lateinit self`
// before-initialization race even when the seam returns WITHOUT suspending; (2) a dispatch made
// after the scope is already cancelled must not leak the unit into inFlightUnits / prefetchTasks
// (the lazy job never starts, so its catch/finally never fire — start() handles cleanup).
// Drives the controller directly (no VM/DataStore) over a plain MutableStateFlow. Shared fake
// resolver/seam: BilingualPrefetchFakes.kt.
package com.vreader.app.bilingual

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class BilingualPrefetchControllerTest {

    private fun txtUnit(idx: Int) =
        TranslationUnitId(TranslationUnitId.Kind.txtDocSegmentWindow, idx.toString())

    // ── an EAGER (immediate) dispatcher must not trip the lateinit-self race on a non-suspending
    //    seam return (Gate-4 r2 High-1 regression: LAZY + register-then-start makes this safe). ──

    @Test fun eagerDispatcher_nonSuspendingResult_noLateinitCrash() = runTest {
        val eager = UnconfinedTestDispatcher(testScheduler)
        val scope = CoroutineScope(eager)
        val state = MutableStateFlow(BilingualUiState(enabled = true))
        val provider = FakeTextProvider().apply {
            units = listOf(txtUnit(0), txtUnit(1)); containing = txtUnit(0)
        }
        val fake = FakePrefetching()   // no `pending` → the seam returns WITHOUT suspending
        val controller = BilingualPrefetchController(scope, fake, provider, state, generationOf = { 0 })

        controller.onPositionChanged(charOffsetUtf16 = 5)   // eager: the body runs synchronously here
        advanceUntilIdle()

        // No UninitializedPropertyAccessException, current+next committed, nothing left in flight.
        assertTrue(state.value.translationsByUnit.containsKey(txtUnit(0)))
        assertTrue(state.value.translationsByUnit.containsKey(txtUnit(1)))
        assertTrue(state.value.inFlightUnits.isEmpty())
        assertEquals(1, fake.completed[txtUnit(0)])
        scope.cancel()
    }

    // ── a dispatch AFTER the scope is cancelled leaves NO leaked in-flight / registry entry
    //    (Gate-4 r3 Medium: the lazy job never starts; start()==false triggers explicit cleanup). ──

    @Test fun dispatchAfterScopeCancelled_noLeak() = runTest {
        val eager = UnconfinedTestDispatcher(testScheduler)
        val scope = CoroutineScope(eager)
        val state = MutableStateFlow(BilingualUiState(enabled = true))
        val provider = FakeTextProvider().apply {
            units = listOf(txtUnit(0), txtUnit(1)); containing = txtUnit(0)
        }
        val fake = FakePrefetching()
        val controller = BilingualPrefetchController(scope, fake, provider, state, generationOf = { 0 })

        scope.cancel()   // the VM's onCleared analog — the scope is dead before the dispatch
        controller.onPositionChanged(charOffsetUtf16 = 5)
        advanceUntilIdle()

        assertTrue("no leaked in-flight marker after a post-cancel dispatch", state.value.inFlightUnits.isEmpty())
        assertFalse("the seam was never invoked (job never started)", fake.prefetchInvocations.contains(txtUnit(0)))
    }
}
