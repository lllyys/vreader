package com.vreader.app.reader.foliate

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import vreader.contracts.Locator
import java.io.File

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
    fun cancelledGoTo_clearsPending_andLateAckIsIgnored() = runTest {
        val h = Harness(backgroundScope)
        val job = async { h.dispatcher.goTo(FoliateGoToTarget.Cfi("/2"), timeoutMs = 60_000) }
        runCurrent()
        assertEquals(1, h.dispatcher.pendingCount())
        val id = h.requestIdOf(h.sent.first())
        // Cancel the caller while it is suspended in await(): the pending entry must be cleared in the
        // finally block so a cancelled goTo does NOT leak a request a late/stale ack could resolve.
        job.cancel()
        runCurrent()
        assertEquals("cancelled goTo must clear its pending entry", 0, h.dispatcher.pendingCount())
        // A late ack for the cancelled id must be a no-op (nothing to resolve).
        h.messages.emit(FoliateMessage.GoToAck(id, ok = true, cfi = "/2", fraction = 0.1))
        runCurrent()
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

    // ---------------------------------------------------------------------------------------------
    // Feature #140 WI-3 — the href navigation leg. THE defect this section exists to prevent: iOS's
    // FoliateTOCConverter gives Foliate TOC rows `progression = 0.0`, harmless there because iOS's
    // navigationTarget has no progression leg. Android's `from()` DOES. A faithful port would make
    // every chapter tap resolve to Fraction(0.0), jump to the START of the book, ack ok:true and
    // dismiss the sheet — green tests on a completely broken feature. Precedence cfi → href →
    // progression is defense 1 (defense 2 is WI-2's `progression = null`, and the tests below must
    // NOT depend on it).
    // ---------------------------------------------------------------------------------------------

    @Test
    fun from_hrefOnlyLocator_yieldsHrefTarget() {
        val loc = locator(cfi = null, progression = null, href = "text/part0007.html")
        assertEquals(FoliateGoToTarget.Href("text/part0007.html"), FoliateGoToTarget.from(loc))
    }

    @Test
    fun from_prefersCfiOverHref() {
        val loc = locator(cfi = "/6/4!/4/2", progression = null, href = "text/part0007.html")
        assertEquals(FoliateGoToTarget.Cfi("/6/4!/4/2"), FoliateGoToTarget.from(loc))
        // A BLANK cfi is not a cfi — the href must then win (the cfi leg already filters blanks).
        val blankCfi = locator(cfi = "   ", progression = null, href = "text/part0007.html")
        assertEquals(FoliateGoToTarget.Href("text/part0007.html"), FoliateGoToTarget.from(blankCfi))
    }

    @Test
    fun from_prefersHrefOverProgression() {
        // §5.2 defense 1 — THE regression test. Any progression value, finite or not, must lose.
        for (progression in listOf(0.0, 0.6, 1.0, -0.0, Double.NaN, Double.POSITIVE_INFINITY)) {
            val loc = locator(cfi = null, progression = progression, href = "text/part0012.html")
            assertEquals(
                "href must win over progression=$progression",
                FoliateGoToTarget.Href("text/part0012.html"),
                FoliateGoToTarget.from(loc),
            )
        }
    }

    @Test
    fun from_hrefWithProgressionZero_stillYieldsHref() {
        // The EXACT iOS-shaped TOC locator: href + progression 0.0 (FoliateTOCConverter's value).
        // If precedence regressed, this resolves to Fraction(0.0) and EVERY chapter tap lands on
        // page 1 of the book while the shim still acks ok:true. Assert Href, and assert explicitly
        // that it is NOT the start-of-book fraction.
        val iosShaped = locator(cfi = null, progression = 0.0, href = "text/part0012.html#ch12")
        val target = FoliateGoToTarget.from(iosShaped)
        assertEquals(FoliateGoToTarget.Href("text/part0012.html#ch12"), target)
        assertNotEquals(
            "an href-bearing TOC locator must never resolve to the start of the book",
            FoliateGoToTarget.Fraction(0.0),
            target,
        )
        assertFalse("must not be a Fraction target at all", target is FoliateGoToTarget.Fraction)
    }

    @Test
    fun from_blankHref_fallsThroughToProgression() {
        for (blank in listOf("", "   ", "\t", "\n")) {
            val withProgression = locator(cfi = null, progression = 0.42, href = blank)
            assertEquals(
                "a blank href must not be jumpable; the progression takes over",
                FoliateGoToTarget.Fraction(0.42),
                FoliateGoToTarget.from(withProgression),
            )
            // Blank href + nothing else → nothing to jump to.
            assertNull(FoliateGoToTarget.from(locator(cfi = null, progression = null, href = blank)))
        }
    }

    @Test
    fun from_noCfiNoHrefNoProgression_yieldsNull() {
        // Unchanged contract: the caller degrades (no JS injected) rather than jumping somewhere.
        assertNull(FoliateGoToTarget.from(locator(cfi = null, progression = null, href = null)))
        // A non-finite progression is still not a jump target.
        assertNull(FoliateGoToTarget.from(locator(cfi = null, progression = Double.NaN, href = null)))
        assertNull(
            FoliateGoToTarget.from(locator(cfi = null, progression = Double.POSITIVE_INFINITY, href = null)),
        )
    }

    @Test
    fun from_tocShapedLocator_alwaysResolves() {
        // Moved here from WI-2 (Gate-2 R1 Medium) — self-contained: the fixtures are built inline and
        // depend on nothing from the TOC provider. A TOC-shaped locator is href-bearing, cfi-free and
        // (per WI-2) progression-free; EVERY realistic AZW3 href shape must resolve to a jumpable Href
        // carrying the href BYTE-FOR-BYTE.
        val tocHrefs = listOf(
            "text/part0001.html",
            "text/part0007.html#ch12",                 // fragment
            "OEBPS/chapter.xhtml?src=toc&i=2",         // query
            "kindle:pos:fid:0001:off:0000000000",      // KF8 position URI
            "filepos:0000012345",                      // MOBI6 filepos
            "文本/第十二章.xhtml#锚点",                    // CJK path + CJK fragment
            "text/part%200003.html",                   // percent-encoded space, must stay encoded
            "text/ch 4.xhtml",                         // literal space
            "#top",                                    // fragment-only
            "../images/../text/part0002.html",         // dot segments, must not be normalized
        )
        for (href in tocHrefs) {
            val loc = locator(cfi = null, progression = null, href = href)
            val target = FoliateGoToTarget.from(loc)
            assertEquals("TOC-shaped locator must resolve to an Href for '$href'", FoliateGoToTarget.Href(href), target)
            // And it must resolve identically when the row DOES carry iOS's progression 0.0 —
            // i.e. this invariant does not lean on WI-2's `progression = null`.
            val withIosProgression = locator(cfi = null, progression = 0.0, href = href)
            assertEquals(FoliateGoToTarget.Href(href), FoliateGoToTarget.from(withIosProgression))
        }
    }

    @Test
    fun gotoJs_hrefIsJsonEscaped_quotesBackslashesScriptTagsNeutralized() = runTest {
        val h = Harness(backgroundScope)
        // A hostile book-derived href: a quote + a backslash + a newline + a script-tag close, i.e.
        // every classic break-out from an injected JS string literal.
        val hostile = "part\"; evil()//\n\\x </script><script>evil()</script>"
        val job = async { h.dispatcher.goTo(FoliateGoToTarget.Href(hostile), timeoutMs = 60_000) }
        runCurrent()
        val js = h.sent.single()
        // The load-bearing property: the href is ONE well-formed JSON string literal whose decoded
        // value is byte-for-byte the original. If any character broke out of the literal, the tail
        // would no longer parse and this call throws.
        assertEquals("hostile href must survive escaping intact inside its literal", hostile, decodedHrefArgument(js))
        // The raw un-escaped payload never appears verbatim, and no raw control char leaks.
        assertFalse("raw un-escaped hostile href leaked into injected JS", js.contains(hostile))
        assertFalse("literal newline leaked into injected JS", js.contains("\n"))
        assertTrue("hostile quote must be JSON-escaped to \\\"", js.contains("\\\""))
        assertTrue("backslash must be JSON-escaped to \\\\", js.contains("\\\\"))
        // Routed through the shell shim, never addJavascriptInterface — and never a raw eval sink.
        assertTrue("goTo JS must call the shell shim entry", js.contains("__vreaderGoTo"))
        assertFalse("must never use addJavascriptInterface", js.contains("addJavascriptInterface"))
        job.cancel()
    }

    @Test
    fun gotoJs_hrefWithFragmentQueryOrNonAscii_isPassedThroughUNCHANGED() = runTest {
        // The bundle does its own `decodeURI` on the href (foliate-bundle.js), and WI-4's
        // current-chapter matching is BYTE-EXACT, so ANY tidying here — trimming, normalizing,
        // re-encoding, dropping a fragment — breaks navigation and/or chapter highlighting later.
        val hrefs = listOf(
            "text/part0007.html#ch12",
            "text/part0007.html#ch12b",
            "OEBPS/chapter.xhtml?src=toc&i=2#anchor",
            "文本/第十二章.xhtml#锚点",
            "text/pa rt.html",                  // interior space
            " text/part0001.html ",             // LEADING + TRAILING space — not blank, must NOT be trimmed
            "text/part%200003.html",            // already percent-encoded
            "text/part0003.html%23notafragment",
            "../text/./part0002.html",          // dot segments
            "TEXT/PART0004.HTML",               // case must be preserved
            "text/part0005.html#",              // empty fragment still distinct from no fragment
        )
        for (href in hrefs) {
            val h = Harness(backgroundScope)
            val job = async { h.dispatcher.goTo(FoliateGoToTarget.Href(href), timeoutMs = 60_000) }
            runCurrent()
            assertEquals("href must reach the shim byte-for-byte: '$href'", href, decodedHrefArgument(h.sent.single()))
            job.cancel()
            runCurrent()
        }
    }

    @Test
    fun gotoJs_kf8PosUriHref_survivesEscapingByteForByte() = runTest {
        // The real KF8 shape a Kindle TOC emits — colons are structural, not separators to split on.
        val kf8 = "kindle:pos:fid:0001:off:0000000000"
        val h = Harness(backgroundScope)
        val job = async { h.dispatcher.goTo(FoliateGoToTarget.Href(kf8), timeoutMs = 60_000) }
        runCurrent()
        val js = h.sent.single()
        assertEquals(kf8, decodedHrefArgument(js))
        // Two KF8 hrefs differing ONLY in the :off: segment must stay distinct through the seam.
        val other = "kindle:pos:fid:0001:off:0000000123"
        val h2 = Harness(backgroundScope)
        val job2 = async { h2.dispatcher.goTo(FoliateGoToTarget.Href(other), timeoutMs = 60_000) }
        runCurrent()
        assertNotEquals(decodedHrefArgument(js), decodedHrefArgument(h2.sent.single()))
        job.cancel()
        job2.cancel()
    }

    @Test
    fun gotoJs_hrefTarget_callsReaderApiGoTo_notGoToFraction() = runTest {
        val h = Harness(backgroundScope)
        val job = async { h.dispatcher.goTo(FoliateGoToTarget.Href("text/part0007.html"), timeoutMs = 60_000) }
        runCurrent()
        val js = h.sent.single()
        // Kotlin half: an Href target carries an `href` key ONLY — never a fraction (which would send
        // the shim down goToFraction and, for 0.0, to the start of the book).
        assertTrue("injected JS must carry the href key", js.contains("{href:"))
        assertFalse("an Href target must never inject a fraction", js.contains("fraction"))
        assertFalse("an Href target must never inject a cfi", js.contains("cfi"))
        job.cancel()

        // Shell half: the shim's href branch calls readerAPI.goTo (which resolves an href through
        // book.resolveHref), NOT goToFraction. Statically asserted against the SHIPPED asset.
        val html = readerHtml()
        val hrefBranch = Regex("""else\s+if\s*\(\s*target\.href\s*!=\s*null\s*\)\s*\{([^}]*)}""")
            .find(html)?.groupValues?.get(1)
            ?: error("reader.html has no `else if (target.href != null)` branch in __vreaderGoTo")
        assertTrue(
            "the shim's href branch must call readerAPI.goTo(target.href); got: $hrefBranch",
            Regex("""readerAPI\.goTo\(\s*target\.href\s*\)""").containsMatchIn(hrefBranch),
        )
        assertFalse("the href branch must NOT call goToFraction", hrefBranch.contains("goToFraction"))
        // The pre-existing branches are untouched and the precedence cfi → href → fraction also
        // holds inside the shim (a target carrying both must never fall to the fraction leg).
        val cfiAt = html.indexOf("target.cfi != null")
        val hrefAt = html.indexOf("target.href != null")
        val fractionAt = html.indexOf("target.fraction != null")
        assertTrue("shim must still branch on target.cfi first", cfiAt in 0 until hrefAt)
        assertTrue("shim must branch on target.href before target.fraction", hrefAt in 0 until fractionAt)
        assertTrue(
            "the cfi branch must still call readerAPI.goTo(target.cfi)",
            Regex("""readerAPI\.goTo\(\s*target\.cfi\s*\)""").containsMatchIn(html),
        )
        assertTrue(
            "the fraction branch must still call readerAPI.goToFraction(target.fraction)",
            Regex("""readerAPI\.goToFraction\(\s*target\.fraction\s*\)""").containsMatchIn(html),
        )
    }

    @Test
    fun hrefGoTo_awaitsAck_andSupersedeStillApplies() = runTest {
        val h = Harness(backgroundScope)
        val first = async { h.dispatcher.goTo(FoliateGoToTarget.Href("text/part0007.html"), timeoutMs = 60_000) }
        runCurrent()
        assertEquals(1, h.sent.size)
        // An href goTo SUSPENDS until foliate's relocate acks — it must not return at injection time
        // (a fire-and-forget jump would dismiss the Contents sheet before anything moved).
        assertFalse("an href goTo must not resolve before its ack arrives", first.isCompleted)
        assertEquals(1, h.dispatcher.pendingCount())
        val firstId = h.requestIdOf(h.sent.first())

        // A second (href) goTo supersedes the first, exactly as for cfi/fraction targets.
        val second = async { h.dispatcher.goTo(FoliateGoToTarget.Href("text/part0008.html"), timeoutMs = 60_000) }
        runCurrent()
        assertEquals(Azw3GoToResult.Superseded, first.await())
        val secondId = h.requestIdOf(h.sent.last())
        assertTrue("the superseding goTo minted a distinct id", secondId != firstId)
        // A late ack for the superseded id must NOT resolve the live one.
        h.messages.emit(FoliateMessage.GoToAck(firstId, ok = true, cfi = "/6/4", fraction = null))
        runCurrent()
        assertFalse("a stale ack must not resolve the live href goTo", second.isCompleted)
        h.messages.emit(FoliateMessage.GoToAck(secondId, ok = true, cfi = "/8/2", fraction = null))
        runCurrent()
        assertEquals(Azw3GoToResult.Succeeded("/8/2", null), second.await())
        assertEquals(0, h.dispatcher.pendingCount())
    }

    @Test
    fun hrefGoTo_ackFalse_resolvesFailed_andTimeoutStillApplies() = runTest {
        // An unresolvable href acks ok:false → Failed, so the caller keeps the sheet open rather
        // than pretending the jump landed.
        val h = Harness(backgroundScope)
        val failed = async { h.dispatcher.goTo(FoliateGoToTarget.Href("nope.html"), timeoutMs = 60_000) }
        runCurrent()
        h.messages.emit(FoliateMessage.GoToAck(h.requestIdOf(h.sent.first()), ok = false, cfi = null, fraction = null))
        runCurrent()
        assertEquals(Azw3GoToResult.Failed, failed.await())

        // And a silent shim (dead bundle / wedged renderer) still times out rather than hanging.
        val h2 = Harness(backgroundScope)
        val timedOut = async { h2.dispatcher.goTo(FoliateGoToTarget.Href("text/part0001.html"), timeoutMs = 3_000) }
        runCurrent()
        advanceTimeBy(3_001)
        runCurrent()
        assertEquals(Azw3GoToResult.Timeout, timedOut.await())
        assertEquals(0, h2.dispatcher.pendingCount())
    }

    @Test
    fun goToController_hrefOnlyLocator_injectsAnHrefJump() = runTest {
        // End of the Kotlin path: the controller the AZW3 document actually calls resolves a
        // TOC-shaped locator to an href jump (not "no jumpable target", and not a fraction).
        val h = Harness(backgroundScope)
        val controller = FoliateGoToController(h.dispatcher)
        val result = async { controller.goTo(locator(cfi = null, progression = null, href = "text/part0007.html")) }
        runCurrent()
        assertEquals("the controller must have injected a jump", 1, h.sent.size)
        assertEquals("text/part0007.html", decodedHrefArgument(h.sent.single()))
        h.messages.emit(
            FoliateMessage.GoToAck(h.requestIdOf(h.sent.first()), ok = true, cfi = "/6/4!/2", fraction = null),
        )
        runCurrent()
        assertEquals(Azw3GoToResult.Succeeded("/6/4!/2", null), result.await())
    }

    /**
     * Decode the `{href: "..."}` argument out of the injected JS. Deliberately parses the literal as
     * JSON rather than string-matching: if the href escaped its string literal (an unescaped quote,
     * a raw newline, a truncation), the remaining text is no longer one well-formed JSON string and
     * this throws — which is the property the escaping seam exists to guarantee.
     */
    private fun decodedHrefArgument(js: String): String {
        val marker = "{href:"
        assertTrue("injected JS carries no href argument: $js", js.contains(marker))
        val literal = js.substringAfter(marker).substringBeforeLast("})}catch(e){}")
        return Json.decodeFromString(String.serializer(), literal)
    }

    /** The SHIPPED shell page (not the androidTest spike copy, which has diverged). */
    private fun readerHtml(): String {
        // Gradle runs JVM tests with the module dir (android/app) as CWD; fall back to an upward walk.
        val candidates = listOf(
            "src/main/assets/foliate/reader.html",
            "app/src/main/assets/foliate/reader.html",
            "android/app/src/main/assets/foliate/reader.html",
        )
        val file = candidates.map { File(it) }.firstOrNull { it.exists() }
            ?: error("reader.html not found from CWD=${File(".").absolutePath} (tried $candidates)")
        return file.readText()
    }

    private fun locator(cfi: String?, progression: Double?, href: String? = null): Locator = Locator(
        contentSHA256 = "a".repeat(64),
        fileByteCount = 1024,
        format = "azw3",
        href = href,
        cfi = cfi,
        progression = progression,
    )
}
