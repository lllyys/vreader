package com.vreader.app.reader.foliate

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import vreader.contracts.Locator

/**
 * Feature #135 WI-2 — the awaited AZW3/foliate goTo bridge.
 *
 * [FoliateGoToDispatcher] is the pure, WebView-free await-machinery: a goTo suspends on a
 * [CompletableDeferred] keyed by a request id, resolved when the matching [FoliateMessage.GoToAck]
 * arrives over the shared message flow. A fake `sendJs` records the injected JS (asserted JSON-escaped,
 * never `addJavascriptInterface`) and a fake message channel drives resolution — no real WebView / no
 * emulator. Virtual time (`runTest`) exercises the timeout path deterministically.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class FoliateGoToTest {

    /** A test harness wiring the dispatcher to a fake JS sink + the message flow it acks over. */
    private class Harness(scope: CoroutineScope) {
        val sent = mutableListOf<String>()
        val messages = MutableSharedFlow<FoliateMessage>(extraBufferCapacity = 64)
        val dispatcher = FoliateGoToDispatcher(
            sendJs = { sent += it },
            messages = messages,
            scope = scope,
        )

        /** Extract the request id the dispatcher minted for the Nth goTo call (from the injected JS). */
        fun requestIdOf(js: String): String =
            Regex(""""id"\s*:\s*"([^"]+)"""").find(js)?.groupValues?.get(1)
                ?: Regex("""["']([A-Za-z0-9_-]{4,})["']""").findAll(js).map { it.groupValues[1] }.first()
    }

    @Test
    fun ack_ok_resolvesSucceeded() = runTest {
        val h = Harness(backgroundScope)
        val result = async { h.dispatcher.goTo(FoliateGoToTarget.Cfi("/6/4!/4/2")) }
        runCurrent()
        assertEquals(1, h.sent.size)
        val id = h.requestIdOf(h.sent.first())
        h.messages.emit(FoliateMessage.GoToAck(id, ok = true, cfi = "/6/4!/4/2", fraction = 0.42))
        runCurrent()
        assertEquals(Azw3GoToResult.Succeeded("/6/4!/4/2", 0.42), result.await())
    }

    @Test
    fun ack_failure_resolvesFailed() = runTest {
        val h = Harness(backgroundScope)
        val result = async { h.dispatcher.goTo(FoliateGoToTarget.Fraction(0.5)) }
        runCurrent()
        val id = h.requestIdOf(h.sent.first())
        h.messages.emit(FoliateMessage.GoToAck(id, ok = false, cfi = null, fraction = null))
        runCurrent()
        assertEquals(Azw3GoToResult.Failed, result.await())
    }

    @Test
    fun noAck_timesOut() = runTest {
        val h = Harness(backgroundScope)
        val result = async { h.dispatcher.goTo(FoliateGoToTarget.Fraction(0.5), timeoutMs = 3_000) }
        runCurrent()
        advanceTimeBy(2_999)
        runCurrent()
        assertFalse("must not resolve before the timeout window elapses", result.isCompleted)
        advanceTimeBy(2)
        runCurrent()
        assertEquals(Azw3GoToResult.Timeout, result.await())
        // The timed-out entry must be removed so it can't leak / be resolved by a late stray ack.
        assertEquals(0, h.dispatcher.pendingCount())
    }

    @Test
    fun staleOrUnknownAckId_isIgnored() = runTest {
        val h = Harness(backgroundScope)
        val result = async { h.dispatcher.goTo(FoliateGoToTarget.Cfi("/2"), timeoutMs = 3_000) }
        runCurrent()
        val realId = h.requestIdOf(h.sent.first())
        // An ack for an id we never minted must not resolve the pending goTo.
        h.messages.emit(FoliateMessage.GoToAck("bogus-id", ok = true, cfi = "/2", fraction = 0.1))
        runCurrent()
        assertFalse("an unknown-id ack must not resolve the pending goTo", result.isCompleted)
        // The real ack still resolves it.
        h.messages.emit(FoliateMessage.GoToAck(realId, ok = true, cfi = "/2", fraction = 0.1))
        runCurrent()
        assertEquals(Azw3GoToResult.Succeeded("/2", 0.1), result.await())
    }

    @Test
    fun supersedingGoTo_cancelsPriorDeferred() = runTest {
        val h = Harness(backgroundScope)
        val first = async { h.dispatcher.goTo(FoliateGoToTarget.Cfi("/2"), timeoutMs = 60_000) }
        runCurrent()
        val firstId = h.requestIdOf(h.sent.first())
        // A second goTo supersedes the first: the first deferred is cancelled + removed.
        val second = async { h.dispatcher.goTo(FoliateGoToTarget.Cfi("/8"), timeoutMs = 60_000) }
        runCurrent()
        assertEquals(Azw3GoToResult.Superseded, first.await())
        // A late ack for the FIRST (now-removed) id is ignored; the SECOND still resolves.
        val secondId = h.requestIdOf(h.sent.last())
        assertTrue("second goTo minted a distinct id", secondId != firstId)
        h.messages.emit(FoliateMessage.GoToAck(firstId, ok = true, cfi = "/2", fraction = 0.1))
        h.messages.emit(FoliateMessage.GoToAck(secondId, ok = true, cfi = "/8", fraction = 0.6))
        runCurrent()
        assertEquals(Azw3GoToResult.Succeeded("/8", 0.6), second.await())
        assertEquals(0, h.dispatcher.pendingCount())
    }

    @Test
    fun injectedJs_isJsonEscaped_andCallsShimGoTo() = runTest {
        val h = Harness(backgroundScope)
        // A hostile CFI with a quote + newline must be neutralized by jsString (JSON-encoded) so it
        // cannot break out of the injected JS string literal.
        val hostile = "/6/4\"; evil()//\n"
        val job = async { h.dispatcher.goTo(FoliateGoToTarget.Cfi(hostile)) }
        runCurrent()
        val js = h.sent.first()
        // The raw hostile CFI must NOT appear verbatim — jsString JSON-encodes the `"` (→ \") and the
        // newline (→ \n), so the un-escaped break-out string is neutralized.
        assertFalse("raw un-escaped hostile CFI leaked into injected JS", js.contains(hostile))
        // Positively confirm both escapes landed: the quote as \" and the newline as the 2-char \n.
        assertTrue("hostile quote must be JSON-escaped to \\\"", js.contains("\\\""))
        assertTrue("newline must be JSON-escaped to \\n", js.contains("\\n"))
        assertFalse("literal newline leaked into injected JS", js.contains("\n"))
        // It routes through the shell shim entry (__vreaderGoTo), never addJavascriptInterface.
        assertTrue("goTo JS must call the shell shim entry", js.contains("__vreaderGoTo"))
        assertFalse("must never use addJavascriptInterface", js.contains("addJavascriptInterface"))
        job.cancel()
    }

    @Test
    fun azw3Target_derivesCfiFirstThenFraction() {
        val cfiLoc = locator(cfi = "/6/4!/4/2", progression = 0.3)
        assertEquals(FoliateGoToTarget.Cfi("/6/4!/4/2"), FoliateGoToTarget.from(cfiLoc))
        val fracOnly = locator(cfi = null, progression = 0.6)
        assertEquals(FoliateGoToTarget.Fraction(0.6), FoliateGoToTarget.from(fracOnly))
        // Neither cfi nor a finite fraction → null (nothing to jump to; caller degrades).
        assertNull(FoliateGoToTarget.from(locator(cfi = null, progression = null)))
    }

    // Azw3Document-level integration: the dispatcher wired to a fake channel maps the ack.
    @Test
    fun goToController_mapsAckToResult() = runTest {
        val h = Harness(backgroundScope)
        val controller = FoliateGoToController(h.dispatcher)
        val result = async { controller.goTo(locator(cfi = "/6/4!/4/2", progression = 0.3)) }
        runCurrent()
        val id = h.requestIdOf(h.sent.first())
        h.messages.emit(FoliateMessage.GoToAck(id, ok = true, cfi = "/6/4!/4/2", fraction = 0.31))
        runCurrent()
        assertEquals(Azw3GoToResult.Succeeded("/6/4!/4/2", 0.31), result.await())
    }

    @Test
    fun goToController_noJumpTarget_returnsFailedWithoutInjecting() = runTest {
        val h = Harness(backgroundScope)
        val controller = FoliateGoToController(h.dispatcher)
        val result = controller.goTo(locator(cfi = null, progression = null))
        assertEquals(Azw3GoToResult.Failed, result)
        assertTrue("no JS injected when there is nothing to jump to", h.sent.isEmpty())
    }

    private fun locator(cfi: String?, progression: Double?): Locator = Locator(
        contentSHA256 = "a".repeat(64),
        fileByteCount = 1024,
        format = "azw3",
        cfi = cfi,
        progression = progression,
    )
}
