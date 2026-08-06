// Purpose: feature #142 WI-3 — the one-shot `evalForResult` machinery behind the WI-5 selection-anchor
// probe. `WebView.evaluateJavascript` hands its ValueCallback whatever the page produced, whenever the
// page produces it — which is the whole hazard: a page that never answers leaks the callback forever,
// and a page that answers after the reader is gone mutates dead UI state (the #165 WI-7 defect class).
//
// [FoliateEvalDispatcher] is the pure, WebView-free half: a fake `sendJs` captures the callback so a
// test can answer late, twice, or not at all, and `runTest` virtual time drives the timeout
// deterministically. No emulator, no Robolectric.
package com.vreader.app.reader.foliate

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class FoliateEvalDispatcherTest {

    /** Records the injected JS and parks each ValueCallback so the test answers on its own schedule. */
    private class Harness(scope: CoroutineScope) {
        val sent = mutableListOf<String>()
        val callbacks = mutableListOf<(String?) -> Unit>()
        val received = mutableListOf<String?>()
        val dispatcher = FoliateEvalDispatcher(
            sendJs = { js, cb -> sent += js; callbacks += cb },
            scope = scope,
        )

        fun eval(js: String = PROBE, timeoutMs: Long = 1_000L) =
            dispatcher.eval(js, timeoutMs) { received += it }
    }

    private companion object {
        const val PROBE = "(function(){return JSON.stringify({x:1})})()"
        const val TIMEOUT = 1_000L
    }

    // ---- the happy path ----------------------------------------------------------------------

    @Test
    fun answer_isDeliveredVerbatim_exactlyOnce() = runTest {
        val h = Harness(backgroundScope)
        h.eval()
        runCurrent()
        assertEquals(listOf(PROBE), h.sent)
        h.callbacks.single().invoke("\"{x:1}\"")
        runCurrent()
        assertEquals(listOf<String?>("\"{x:1}\""), h.received)
    }

    @Test
    fun malformedJson_isPassedThroughVerbatim_theDispatcherNeverParses() {
        // Shaping the result is the CALLER's job (WI-5 maps it to an anchor). A dispatcher that tried to
        // parse would have to invent an error channel; instead the caller sees exactly what the page
        // said and decides. Pinned so a later "helpful" parse is a visible behaviour change.
        runTest {
            val h = Harness(backgroundScope)
            h.eval()
            runCurrent()
            h.callbacks.single().invoke("{oops")
            runCurrent()
            assertEquals(listOf<String?>("{oops"), h.received)
        }
    }

    @Test
    fun jsNullAndUndefinedAndNativeNull_allNormalizeToNull() = runTest {
        // evaluateJavascript JSON-encodes the result, so a JS `null`/`undefined` arrives as the literal
        // four/nine-character string. Callers must not have to know that.
        for (raw in listOf("null", "undefined", null)) {
            val h = Harness(backgroundScope)
            h.eval()
            runCurrent()
            h.callbacks.single().invoke(raw)
            runCurrent()
            assertEquals("raw [$raw] must normalize to null", listOf<String?>(null), h.received)
        }
    }

    @Test
    fun anEmptyStringAnswer_isNotNull() = runTest {
        // "" is a real JS answer (an empty string result), distinct from "no answer". It must survive.
        val h = Harness(backgroundScope)
        h.eval()
        runCurrent()
        h.callbacks.single().invoke("")
        runCurrent()
        assertEquals(listOf<String?>(""), h.received)
    }

    // ---- the page never answers ---------------------------------------------------------------

    @Test
    fun noAnswerWithinBudget_deliversNullExactlyOnce() = runTest {
        val h = Harness(backgroundScope)
        h.eval(timeoutMs = TIMEOUT)
        runCurrent()
        assertEquals("nothing may be delivered before the budget elapses", emptyList<String?>(), h.received)
        advanceTimeBy(TIMEOUT + 1)
        runCurrent()
        assertEquals(listOf<String?>(null), h.received)
    }

    @Test
    fun anAnswerArrivingAfterTheTimeout_isIgnored() = runTest {
        val h = Harness(backgroundScope)
        h.eval(timeoutMs = TIMEOUT)
        runCurrent()
        advanceTimeBy(TIMEOUT + 1)
        runCurrent()
        h.callbacks.single().invoke("\"late\"")
        runCurrent()
        assertEquals("the timeout already settled this probe", listOf<String?>(null), h.received)
    }

    @Test
    fun anAnswer_cancelsTheTimeout_soNoSecondNullArrives() = runTest {
        val h = Harness(backgroundScope)
        h.eval(timeoutMs = TIMEOUT)
        runCurrent()
        h.callbacks.single().invoke("\"early\"")
        runCurrent()
        advanceTimeBy(TIMEOUT * 10)
        runCurrent()
        assertEquals(listOf<String?>("\"early\""), h.received)
    }

    // ---- the page answers twice -----------------------------------------------------------------

    @Test
    fun aDoubleAnswer_isDeliveredOnce() = runTest {
        val h = Harness(backgroundScope)
        h.eval()
        runCurrent()
        val cb = h.callbacks.single()
        cb.invoke("\"first\"")
        cb.invoke("\"second\"")
        runCurrent()
        assertEquals(listOf<String?>("\"first\""), h.received)
    }

    // ---- teardown ------------------------------------------------------------------------------

    @Test
    fun anAnswerAfterTeardown_isDropped() = runTest {
        // The #165 WI-7 class: a callback that fires into a finished host. Dropped, not delivered-null —
        // a null would still drive the caller's "no anchor" branch and touch dead state.
        val h = Harness(backgroundScope)
        h.eval()
        runCurrent()
        h.dispatcher.teardown()
        h.callbacks.single().invoke("\"late\"")
        runCurrent()
        assertEquals(emptyList<String?>(), h.received)
    }

    @Test
    fun teardown_cancelsPendingTimeouts_soNoLateNullArrives() = runTest {
        val h = Harness(backgroundScope)
        h.eval(timeoutMs = TIMEOUT)
        runCurrent()
        h.dispatcher.teardown()
        advanceTimeBy(TIMEOUT * 10)
        runCurrent()
        assertEquals(emptyList<String?>(), h.received)
    }

    @Test
    fun evalAfterTeardown_injectsNoJs_andNeverCallsBack() = runTest {
        val h = Harness(backgroundScope)
        h.dispatcher.teardown()
        h.eval()
        runCurrent()
        advanceTimeBy(TIMEOUT * 10)
        runCurrent()
        assertEquals("no JS may reach a torn-down WebView", emptyList<String>(), h.sent)
        assertEquals(emptyList<String?>(), h.received)
    }

    @Test
    fun teardown_isIdempotent() = runTest {
        val h = Harness(backgroundScope)
        h.eval()
        runCurrent()
        h.dispatcher.teardown()
        h.dispatcher.teardown()
        runCurrent()
        assertEquals(0, h.dispatcher.pendingCount())
        assertEquals(emptyList<String?>(), h.received)
    }

    // ---- concurrency + bookkeeping ---------------------------------------------------------------

    @Test
    fun concurrentProbes_resolveIndependently_inTheirOwnOrder() = runTest {
        // Rapid re-selection fires a second probe before the first answers; neither may steal the
        // other's result (a single-slot design would).
        val h = Harness(backgroundScope)
        h.eval(js = "probeA")
        h.eval(js = "probeB")
        runCurrent()
        assertEquals(listOf("probeA", "probeB"), h.sent)
        h.callbacks[1].invoke("\"B\"")
        h.callbacks[0].invoke("\"A\"")
        runCurrent()
        assertEquals(listOf<String?>("\"B\"", "\"A\""), h.received)
    }

    @Test
    fun oneProbeTimingOut_doesNotSettleTheOther() = runTest {
        val h = Harness(backgroundScope)
        h.eval(js = "probeA", timeoutMs = 100)
        h.eval(js = "probeB", timeoutMs = 10_000)
        runCurrent()
        advanceTimeBy(101)
        runCurrent()
        assertEquals(listOf<String?>(null), h.received)
        assertEquals(1, h.dispatcher.pendingCount())
        h.callbacks[1].invoke("\"B\"")
        runCurrent()
        assertEquals(listOf<String?>(null, "\"B\""), h.received)
    }

    @Test
    fun pendingCount_tracksInFlightProbes_andReachesZeroOnEveryExitPath() = runTest {
        val h = Harness(backgroundScope)
        assertEquals(0, h.dispatcher.pendingCount())
        h.eval(timeoutMs = TIMEOUT)
        h.eval(timeoutMs = TIMEOUT)
        runCurrent()
        assertEquals(2, h.dispatcher.pendingCount())
        h.callbacks[0].invoke("\"done\"")
        runCurrent()
        assertEquals(1, h.dispatcher.pendingCount())
        advanceTimeBy(TIMEOUT + 1)
        runCurrent()
        assertEquals("a timed-out probe must not leak a pending entry", 0, h.dispatcher.pendingCount())
    }

    @Test
    fun aNestedEvalFromWithinACallback_isAdmitted() = runTest {
        // The callback runs while the dispatcher is settling the entry it belongs to; re-entering must
        // not corrupt the bookkeeping (a ConcurrentModificationException on the pending set would).
        val h = Harness(backgroundScope)
        h.dispatcher.eval("outer", TIMEOUT) { first ->
            h.received += first
            h.dispatcher.eval("inner", TIMEOUT) { h.received += it }
        }
        runCurrent()
        h.callbacks[0].invoke("\"outer-result\"")
        runCurrent()
        assertEquals(listOf("outer", "inner"), h.sent)
        h.callbacks[1].invoke("\"inner-result\"")
        runCurrent()
        assertEquals(listOf<String?>("\"outer-result\"", "\"inner-result\""), h.received)
        assertEquals(0, h.dispatcher.pendingCount())
    }

    @Test
    fun aSettledProbe_leavesTheRegistry_soTheCallerLambdaIsUnreachable() = runTest {
        // The registry entry is the ONLY strong reference to the caller's lambda: the callback the
        // WebView parks captures a Long id and the dispatcher, never the entry (see the class's
        // RETENTION note). So "removed from the registry" IS "the lambda — and the popover VM it
        // captured — is unreachable", even though the WebView keeps its own callback until the page
        // answers. This test pins the registry half; the capture half is structural, and the two
        // late-answer tests below prove the parked callback can no longer reach onResult.
        val h = Harness(backgroundScope)
        h.eval()
        runCurrent()
        assertEquals(1, h.dispatcher.pendingCount())
        h.callbacks.single().invoke("\"x\"")
        runCurrent()
        assertEquals(0, h.dispatcher.pendingCount())
    }

    @Test
    fun aStaleCallback_cannotSettleALaterProbe() = runTest {
        // Ids must not be recycled: were they, the WebView callback parked by a timed-out probe would
        // land on whatever probe now occupies its slot and deliver a stale anchor to a live selection.
        val h = Harness(backgroundScope)
        h.eval(js = "first", timeoutMs = TIMEOUT)
        runCurrent()
        advanceTimeBy(TIMEOUT + 1)
        runCurrent()
        assertEquals(listOf<String?>(null), h.received)

        h.eval(js = "second", timeoutMs = TIMEOUT)
        runCurrent()
        // The FIRST probe's parked callback finally fires — it must not settle the second probe.
        h.callbacks[0].invoke("\"stale\"")
        runCurrent()
        assertEquals(listOf<String?>(null), h.received)
        assertEquals("the second probe must still be in flight", 1, h.dispatcher.pendingCount())
        h.callbacks[1].invoke("\"fresh\"")
        runCurrent()
        assertEquals(listOf<String?>(null, "\"fresh\""), h.received)
    }

    @Test
    fun aStaleCallback_cannotSettleAProbeIssuedAfterTeardown() = runTest {
        // Same hazard across a teardown boundary (the reader recreated after render-process death:
        // teardown, then a fresh dispatcher-less-of-history). This dispatcher refuses post-teardown
        // probes outright, so the assertion is that nothing at all reaches the caller.
        val h = Harness(backgroundScope)
        h.eval(js = "first")
        runCurrent()
        h.dispatcher.teardown()
        h.eval(js = "second")
        runCurrent()
        h.callbacks[0].invoke("\"stale\"")
        runCurrent()
        assertEquals(listOf("first"), h.sent)
        assertEquals(emptyList<String?>(), h.received)
    }

    @Test
    fun aZeroTimeout_stillSettlesRatherThanHanging() = runTest {
        val h = Harness(backgroundScope)
        h.eval(timeoutMs = 0)
        runCurrent()
        assertTrue("a 0 ms budget must settle immediately", h.received.isNotEmpty())
        assertNull(h.received.single())
        assertEquals(0, h.dispatcher.pendingCount())
    }
}
