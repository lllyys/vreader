package com.vreader.app.reader.foliate

import android.util.Log
import android.view.View
import android.webkit.WebView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.data.Book
import com.vreader.app.reader.nav.FoliateTocProvider
import com.vreader.app.reader.nav.TocEntry
import com.vreader.app.reader.nav.foliateTocIndexFor
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.onSubscription
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import vreader.contracts.BookFormat
import vreader.contracts.Identity
import vreader.contracts.Locator
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Feature #140 WI-7 — the real-book connected round-trip: **the WI that proves a Contents tap
 * actually MOVES the reader.** Everything before it (WI-1…WI-6) is JVM-provable; motion is not.
 *
 * THE LOAD-BEARING ASSERTION IS A POSITION CHANGE, NEVER AN ACK. foliate's `view.goTo` catches a
 * failed resolution and returns `undefined` (`foliate-bundle.js:6874-6884`), so the shell shim acks
 * `ok:true` with nothing moved — an ack is not motion. `Azw3GoToSliceTest.kt`'s
 * `assertTrue(result is Succeeded || result == Timeout)` is that trap already living in this
 * codebase: it passes on total failure. No assertion in this file inspects an
 * [Azw3GoToResult]; every navigation claim is made against the position foliate *reports back* on a
 * later relocate, with [realBook_goToBogusHref_doesNOTChangePosition] as the negative control that
 * gives the positive assertion teeth (and which then proves its own observation window by driving a
 * REAL jump through the same document and watching it move).
 *
 * FIXTURE. `foliate-spike/book.azw3` is gitignored and absent from a fresh worktree; the real-book
 * cases [assumeTrue]-SKIP without it, and a skip exits 0 exactly like a pass (plan §9 R7 — the same
 * shape as bug #369). The lane brief stages it; the run log must show these tests RAN, with zero
 * skips.
 *
 * HOSTILE-PAYLOAD SCOPE (plan §5.4 stage 2). The two `pathologicalTocPayload_*` cases inject a
 * synthetic message through the shell's own `window.__vreaderPost`, so it rides the REAL
 * `addWebMessageListener` → [FoliateBridgePolicy.isTrustedMessage] → [FoliateMessageParser] path on
 * a REAL WebView's main thread — the only way to evidence the Kotlin bound on ART, whose stack
 * budget is not the JVM's. They prove the **payload** parses bounded and without overflow. They do
 * NOT prove, and must not be read as proving, that a pathological *book file* opens: foliate's own
 * recursive `assignIDs`/`flatten`/`serializeTOC` run inside `readerAPI.open()` before Kotlin sees
 * anything, a pre-existing exposure #140 characterizes rather than fixes (risk R13, follow-up F6).
 * Being fixture-independent, they run even when `book.azw3` is absent.
 *
 * Run ONE class per connected invocation, and never drive the emulator while it runs (rule 52).
 */
@RunWith(AndroidJUnit4::class)
class Azw3TocConnectedTest {

    private val inst get() = InstrumentationRegistry.getInstrumentation()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    private var document: Azw3Document? = null
    private val extraWebViews = CopyOnWriteArrayList<WebView>()

    /**
     * The latest position report, tagged with a monotonic sequence number. The tag is what lets an
     * assertion bind to ONE relocate EVENT rather than to whatever the latest sample happens to be:
     * a "the position changed" check and a "it landed in the tapped chapter" check made against two
     * different relocates would leave a hole for drift-then-settle to satisfy both (Gate-4 R1 #1).
     * Written only on the main thread (`onRelocate`), read from the instrumentation thread.
     */
    private data class Reported(val seq: Long, val relocate: FoliateMessage.Relocate)

    @Volatile private var reported: Reported? = null

    @After
    fun tearDown() {
        scope.cancel()
        inst.runOnMainSync {
            runCatching { document?.destroy() }
            extraWebViews.forEach { wv -> runCatching { wv.destroy() } }
        }
    }

    // ---- the real book -------------------------------------------------------------------------

    @Test
    fun realBook_bookReady_carriesANonEmptyToc_withRealLabels() {
        val doc = openRealBookOrSkip()
        val loaded = doc.state.value as Azw3DocState.Loaded
        assertTrue("book-ready delivered no TOC tree for the real AZW3", loaded.toc.isNotEmpty())

        val rows = rowsFor(loaded)
        Log.i(TAG, "real book TOC: ${loaded.toc.size} root nodes -> ${rows.size} rows; " +
            "first titles=${rows.take(8).map { it.title }}")
        assertTrue("the provider emitted no Contents rows from a non-empty tree", rows.size >= 2)
        assertTrue(
            "every row must be displayable + navigable (trimmed non-blank title, non-blank href)",
            rows.all { !it.title.isNullOrBlank() && !it.canonicalLocator.href.isNullOrBlank() },
        )
        assertTrue(
            "the labels look synthetic — a real NCX has more than one distinct chapter title",
            rows.mapNotNull { it.title }.toSet().size >= 2,
        )
        assertTrue(
            "every row must key to the book's own azw3 identity",
            rows.all { it.canonicalLocator.format == BookFormat.azw3.name },
        )
        // The end-to-end form of §5.2: a REAL row resolves to an Href, never a Fraction(0.0) that
        // would send every chapter tap to the start of the book while still acking ok:true.
        rows.forEach { row ->
            val target = FoliateGoToTarget.from(row.canonicalLocator)
            assertTrue(
                "row '${row.title}' resolved to $target, not an Href",
                target is FoliateGoToTarget.Href,
            )
        }
    }

    /**
     * MEASUREMENT (plan §9 R3), not a behavioural gate: the real fixture's TOC depth distribution is
     * an OPEN QUESTION at plan time. If it prints a single `depth 0` bucket the book's TOC is FLAT,
     * and the evidence file must say so plainly rather than implying hierarchical coverage — nesting
     * would then rest on the JVM suites plus #139's on-screen indentation verification.
     */
    @Test
    fun realBook_tocDepthHistogram_isLogged() {
        val doc = openRealBookOrSkip()
        val rows = rowsFor(doc.state.value as Azw3DocState.Loaded)
        assertTrue("no rows to measure — the real book yielded no Contents rows", rows.isNotEmpty())
        val histogram = rows.groupingBy { it.depth }.eachCount().toSortedMap()
        Log.i(TAG, "TOC DEPTH HISTOGRAM: rows=${rows.size} histogram=$histogram maxDepth=${rows.maxOf { it.depth }}")
        assertEquals("the histogram must account for every row", rows.size, histogram.values.sum())
    }

    /**
     * THE DISCRIMINATOR. Jump to a MIDDLE chapter and require the position foliate reports to have
     * MOVED — and moved FORWARD, which is what separates a real jump from the `Fraction(0.0)`
     * regression (that one lands at the book start, i.e. no change at all, while acking `ok:true`).
     * The pre-jump position is settled first, so drift cannot be mistaken for the jump.
     */
    @Test
    fun realBook_goToTocHref_CHANGES_theReportedPosition() {
        val doc = openRealBookOrSkip()
        val rows = rowsFor(doc.state.value as Azw3DocState.Loaded)
        val settled = settledReport()
        val before = settled.relocate
        // The opening chapter must be KNOWN, or "pick a row we are not already in" below is inert and
        // the whole test could be jumping to where the reader already stands.
        assertNotNull(
            "the opening relocate carried no tocHref — the current chapter is unknown, so the " +
                "avoid-the-opening-chapter guard would be inert",
            before.tocHref,
        )
        val target = pickMiddleRow(rows, avoidHref = before.tocHref)
        val targetHref = requireNotNull(target.canonicalLocator.href)
        assertTrue("the target row is the chapter the reader is already in", targetHref != before.tocHref)
        val beforeFraction = requireNotNull(before.fraction) { "no fraction in the pre-jump relocate" }
        Log.i(TAG, "jumping to '${target.title}' href=$targetHref from ${before.pos()}")

        runBlocking { withContext(Dispatchers.Main) { doc.goTo(target.canonicalLocator) } }

        // ONE relocate event, newer than the settled one, must satisfy ALL THREE predicates together.
        // Split across two events they would be satisfiable by drift-somewhere-else followed by a
        // later report of the target chapter (Gate-4 R1 #1); bound to one event they are not.
        val after = awaitReport(
            since = settled.seq,
            timeoutMs = RELOCATE_TIMEOUT_MS,
            what = "ONE relocate that moved, moved FORWARD, and reports the tapped chapter ($targetHref)",
        ) { r ->
            r.pos() != before.pos() && (r.fraction ?: Double.NEGATIVE_INFINITY) > beforeFraction &&
                r.tocHref == targetHref
        }
        Log.i(TAG, "post-jump position ${after.pos()} tocHref=${after.tocHref}")

        // Restated individually so the record says what was proven, not merely that a predicate held.
        assertTrue(
            "the reported position did not change — the chapter jump moved nothing " +
                "(before=${before.pos()} after=${after.pos()})",
            after.pos() != before.pos(),
        )
        val afterFraction = requireNotNull(after.fraction) { "no fraction in the post-jump relocate" }
        assertTrue(
            "the reader did not move FORWARD to the middle chapter — a landing at/behind the opening " +
                "position is the Fraction(0.0) failure shape (before=$beforeFraction after=$afterFraction)",
            afterFraction > beforeFraction,
        )
        assertEquals(
            "the position changed but landed outside the tapped chapter — that is drift, not a jump",
            targetHref, after.tocHref,
        )
    }

    /**
     * THE NEGATIVE CONTROL. An href no chapter carries must NOT move the reader — otherwise
     * "position changed" above could be drift, a late settle or a re-render rather than the jump.
     * The second half then drives a REAL row through the SAME document and — critically — the SAME
     * [OBSERVE_WINDOW_MS] budget the no-change verdict was reached under (Gate-4 R1 #3: a liveness
     * proof given a longer window would not prove the shorter one was long enough).
     */
    @Test
    fun realBook_goToBogusHref_doesNOTChangePosition() {
        val doc = openRealBookOrSkip()
        val rows = rowsFor(doc.state.value as Azw3DocState.Loaded)
        val settled = settledReport()
        val before = settled.relocate
        val identity = bookIdentity()
        val bogus = Locator(
            contentSHA256 = identity.contentSHA256,
            fileByteCount = identity.fileByteCount,
            format = BookFormat.azw3.name,
            href = "vreader-no-such-chapter-$NONCE.xhtml#nowhere",
        )

        val result = runBlocking { withContext(Dispatchers.Main) { doc.goTo(bogus) } }
        // Deliberately NOT asserted: foliate answers an unresolvable target with a fulfilled promise,
        // so the ack is a lie either way. Logged so the evidence file can quote what it actually said.
        Log.i(TAG, "bogus-href goTo acked $result (an ack is not motion — never assert on it)")

        val deadline = System.currentTimeMillis() + OBSERVE_WINDOW_MS
        while (System.currentTimeMillis() < deadline) {
            val now = reported!!.relocate
            assertEquals(
                "an unresolvable href moved the reader (before=${before.pos()} now=${now.pos()})",
                before.pos(), now.pos(),
            )
            Thread.sleep(POLL_MS)
        }

        // Liveness, under the SAME budget: a real chapter jump lands within OBSERVE_WINDOW_MS, so the
        // window above was long enough and the no-change verdict was earned rather than under-observed.
        val target = pickMiddleRow(rows, avoidHref = before.tocHref)
        val targetHref = requireNotNull(target.canonicalLocator.href)
        runBlocking { withContext(Dispatchers.Main) { doc.goTo(target.canonicalLocator) } }
        awaitReport(
            since = settled.seq,
            timeoutMs = OBSERVE_WINDOW_MS,
            what = "a REAL chapter jump to land within the same ${OBSERVE_WINDOW_MS}ms the bogus href " +
                "was observed for (control liveness)",
        ) { r -> r.pos() != before.pos() && r.tocHref == targetHref }
    }

    /** Criteria 4 + 5: the landing chapter is the tapped one, and the highlight follows it. */
    @Test
    fun realBook_goToTocHref_thenRelocateTocHref_matchesThatEntry() {
        val doc = openRealBookOrSkip()
        val rows = rowsFor(doc.state.value as Azw3DocState.Loaded)
        val settled = settledReport()
        val target = pickMiddleRow(rows, avoidHref = settled.relocate.tocHref)
        val targetHref = requireNotNull(target.canonicalLocator.href)

        runBlocking { withContext(Dispatchers.Main) { doc.goTo(target.canonicalLocator) } }

        val after = awaitReport(
            since = settled.seq,
            timeoutMs = RELOCATE_TIMEOUT_MS,
            what = "a relocate whose tocHref is the tapped entry's ($targetHref)",
        ) { r -> r.tocHref == targetHref }
        assertEquals("foliate reports a different chapter than the one tapped", targetHref, after.tocHref)

        val hrefs = rows.map { it.canonicalLocator.href }
        val index = foliateTocIndexFor(after.tocHref, hrefs)
        Log.i(TAG, "highlight index after jump = $index for href=$targetHref")
        assertTrue("the highlight fell back to row 0 instead of the tapped chapter", index > 0)
        // The contract is last-match-wins (a part and its first chapter legitimately share an href),
        // so the exact row to expect is the LAST one carrying the tapped href — asserting a plain
        // href match would be weaker than the contract the highlight actually promises.
        assertEquals(
            "the highlighted row is not the one foliateTocIndexFor's last-match-wins rule defines",
            hrefs.indexOfLast { it == targetHref }, index,
        )
    }

    /**
     * MEASUREMENT (plan §9 R5 / criterion 10) — the cost #139 taught us never to estimate: a desktop
     * number was ~100x wrong on device. `book-ready` parsing runs on the WebView callback (main)
     * thread, so the parse is re-timed THERE over a payload rebuilt from — and asserted equal to —
     * the real book's own tree. The flatten is timed on the provider's injected dispatcher.
     *
     * Timed in MICROseconds over [COST_SAMPLES] iterations, because a millisecond clock reports this
     * work as `0` and any ceiling against `0` is decoration (Gate-4 R1 #7). The ceiling is the ONE
     * principled number available: [MAIN_THREAD_BUDGET_US], ~3 dropped frames at 60 Hz — past that,
     * a book-ready parse is visible jank on the thread that paints.
     */
    @Test
    fun realBook_tocParseAndFlatten_areLogged_withElapsedMs() {
        val doc = openRealBookOrSkip()
        val loaded = doc.state.value as Azw3DocState.Loaded
        val raw = """{"name":"book-ready","detail":{"title":"t","sections":1,"toc":${tocJson(loaded.toc)}}}"""

        var parsed: FoliateMessage.BookReady? = null
        var parseUs = 0L
        inst.runOnMainSync {
            parsed = FoliateMessageParser.parse(raw) as? FoliateMessage.BookReady // warm the code path
            val start = System.nanoTime()
            repeat(COST_SAMPLES) { FoliateMessageParser.parse(raw) }
            parseUs = (System.nanoTime() - start) / 1_000 / COST_SAMPLES
        }
        assertNotNull("the rebuilt book-ready did not parse", parsed)
        assertEquals(
            "the timed payload is not the real book's tree — the measurement would be meaningless",
            loaded.toc, parsed!!.toc,
        )

        val book = bookIdentity()
        val provider = FoliateTocProvider(loaded.toc, book, Dispatchers.Default)
        val rows = runBlocking { provider.toc() } // warm
        val startFlatten = System.nanoTime()
        runBlocking { repeat(COST_SAMPLES) { provider.toc() } }
        val flattenUs = (System.nanoTime() - startFlatten) / 1_000 / COST_SAMPLES

        Log.i(
            TAG,
            "TIMINGS (mean of $COST_SAMPLES): rows=${rows.size} payloadBytes=${raw.length} " +
                "parseUs=$parseUs flattenUs=$flattenUs (main-thread budget ${MAIN_THREAD_BUDGET_US}us)",
        )
        assertTrue(
            "the on-device book-ready parse of the real TOC took ${parseUs}us — past the " +
                "${MAIN_THREAD_BUDGET_US}us main-thread budget it is visible jank at book open",
            parseUs < MAIN_THREAD_BUDGET_US,
        )
        assertTrue("the on-device TOC flatten took ${flattenUs}us", flattenUs < MAIN_THREAD_BUDGET_US)
    }

    // ---- hostile PAYLOADS through the production message channel (fixture-independent) -----------

    /**
     * A 200-deep TOC **payload** injected through the shell's own `__vreaderPost` is parsed on the
     * real WebView main thread without a `StackOverflowError`: the tree comes back clamped to
     * [FoliateTocParser.MAX_TOC_DEPTH] levels with the parent rows kept, and the message channel is
     * still alive afterwards. Scope: the payload, never a pathological book file (see the class doc).
     */
    @Test
    fun pathologicalTocPayload_200Deep_isParsedOnDeviceWithoutOverflow() {
        val shell = openShell()
        inject(shell, deepTocJs(depth = 200, title = "deep-payload"))

        val ready = awaitBookReady(shell, "deep-payload")
        var node = ready.toc.singleOrNull()
            ?: throw AssertionError("the deep payload yielded ${ready.toc.size} root nodes, expected 1")
        var levels = 1
        while (node.subitems.isNotEmpty()) {
            node = node.subitems.single()
            levels++
        }
        Log.i(TAG, "200-deep payload parsed on device to $levels levels (cap=${FoliateTocParser.MAX_TOC_DEPTH})")
        assertEquals(
            "the 200-deep payload was not clamped to the parser's depth bound",
            FoliateTocParser.MAX_TOC_DEPTH, levels,
        )
        assertChannelStillAlive(shell, "after-deep")
    }

    /**
     * A TOC **payload** over [FoliateTocParser.MAX_TOC_ENTRIES] is REJECTED WHOLE on device, never
     * truncated — a Contents list that silently stops at row N is worse than none, because the user
     * cannot tell it is incomplete. Scope: the payload, never a pathological book file.
     */
    @Test
    fun pathologicalTocPayload_overEntryCap_isRejectedOnDevice() {
        val shell = openShell()
        val count = FoliateTocParser.MAX_TOC_ENTRIES + 1
        inject(shell, flatTocJs(count = count, title = "over-cap-payload"))

        val ready = awaitBookReady(shell, "over-cap-payload")
        Log.i(TAG, "over-cap payload ($count entries) parsed on device to ${ready.toc.size} nodes")
        assertEquals("an over-cap TOC must be rejected whole, not truncated", 0, ready.toc.size)
        assertEquals("the rest of the message must still parse", 1, ready.sectionTotal)
        assertChannelStillAlive(shell, "after-overcap")
    }

    // ---- harness ---------------------------------------------------------------------------------

    private fun openRealBookOrSkip(): Azw3Document {
        val present = inst.context.assets.list("foliate-spike")?.contains("book.azw3") == true
        if (!present) {
            // LOUD, because a skip exits 0 exactly like a pass: the run log must make an unverified
            // WI-7 unmistakable to whoever reads it (plan R7 — bug #369's precedent).
            Log.e(TAG, "FIXTURE MISSING: androidTest assets foliate-spike/book.azw3 — every real-book " +
                "case in this class is SKIPPING and this run verifies NOTHING about the AZW3 TOC")
        }
        assumeTrue(
            "local-only foliate-spike/book.azw3 absent — WI-7 verifies NOTHING without it (plan R7)",
            present,
        )
        val file = realBookFile()
        lateinit var doc: Azw3Document
        inst.runOnMainSync {
            val wv = WebView(inst.targetContext).also(::forceViewport)
            doc = Azw3Document(wv, file, inst.targetContext)
            doc.onRelocate = { r -> reported = Reported((reported?.seq ?: 0L) + 1L, r) }
        }
        document = doc
        scope.launch { doc.run(restore = null) }
        awaitUntil(OPEN_TIMEOUT_MS, "the real book to reach Azw3DocState.Loaded") {
            doc.state.value is Azw3DocState.Loaded
        }
        return doc
    }

    /** Always re-staged from the TEST APK's assets: a cached copy could be a DIFFERENT book than the
     *  one this APK ships, which would silently decouple the evidence from the artifact under test. */
    private fun realBookFile(): File {
        val file = File(inst.targetContext.cacheDir, "wi7-book.azw3")
        inst.context.assets.open("foliate-spike/book.azw3").use { input ->
            file.outputStream().use { input.copyTo(it) }
        }
        return file
    }

    /** The book's REAL identity triple, so every row's locator is the one production would build. */
    private fun bookIdentity(): Book {
        val file = realBookFile()
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(1 shl 16)
            while (true) {
                val read = input.read(buffer)
                if (read <= 0) break
                digest.update(buffer, 0, read)
            }
        }
        val sha = digest.digest().joinToString("") { "%02x".format(it) }
        return Book(
            fingerprintKey = Identity.canonicalKey(BookFormat.azw3.name, sha, file.length()),
            title = "wi7-real-azw3",
            originalFormat = BookFormat.azw3,
            contentSHA256 = sha,
            fileByteCount = file.length(),
            addedAt = 0L,
        )
    }

    private fun rowsFor(loaded: Azw3DocState.Loaded): List<TocEntry> =
        runBlocking { FoliateTocProvider(loaded.toc, bookIdentity(), Dispatchers.Default).toc() }

    /** A row from the second half of the TOC whose href differs from [avoidHref] (criterion 4). */
    private fun pickMiddleRow(rows: List<TocEntry>, avoidHref: String?): TocEntry {
        assertTrue("the real book needs >= 2 TOC rows to jump between, had ${rows.size}", rows.size >= 2)
        val from = (rows.size / 2).coerceIn(1, rows.size - 1)
        return (from until rows.size).firstNotNullOfOrNull { rows[it].takeIf { r -> r.canonicalLocator.href != avoidHref } }
            ?: (rows.size - 1 downTo 1).firstNotNullOfOrNull { rows[it].takeIf { r -> r.canonicalLocator.href != avoidHref } }
            ?: throw AssertionError("every TOC row shares the opening chapter's href — nothing to jump to")
    }

    /**
     * The position foliate reports once it has HELD STILL for a continuous [SETTLE_HOLD_MS] — the
     * same window the negative control watches an unresolvable jump for, so "the reader was not
     * drifting before the jump" and "the reader does not move on its own" are established over the
     * same budget. A single unchanged sample is not enough: a delayed layout/settle relocate
     * arriving after it would be indistinguishable from the jump (Gate-4 R1 #2).
     */
    private fun settledReport(): Reported {
        awaitUntil(OPEN_TIMEOUT_MS, "the first relocate") { reported != null }
        val deadline = System.currentTimeMillis() + SETTLE_TIMEOUT_MS
        while (System.currentTimeMillis() < deadline) {
            val candidate = reported!!
            val holdUntil = System.currentTimeMillis() + SETTLE_HOLD_MS
            var held = true
            while (System.currentTimeMillis() < holdUntil) {
                Thread.sleep(POLL_MS)
                if (reported!!.relocate.pos() != candidate.relocate.pos()) {
                    held = false
                    break
                }
            }
            // Return the LATEST report, not `candidate`: an identical position re-reported during the
            // hold still advances the sequence, and a stale seq would let that report satisfy a later
            // "newer than the settled one" await.
            if (held) return reported!!
        }
        throw AssertionError(
            "the reported position never held still for ${SETTLE_HOLD_MS}ms within ${SETTLE_TIMEOUT_MS}ms " +
                "(last=${reported?.relocate?.pos()})",
        )
    }

    /**
     * Await ONE relocate EVENT newer than [since] that satisfies [predicate], and return it. Binding
     * a multi-part claim to a single event is what stops "it moved" and "it landed in chapter N"
     * from being satisfiable by two different relocates (Gate-4 R1 #1).
     */
    private fun awaitReport(
        since: Long,
        timeoutMs: Long,
        what: String,
        predicate: (FoliateMessage.Relocate) -> Boolean,
    ): FoliateMessage.Relocate {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            val snapshot = reported
            if (snapshot != null && snapshot.seq > since && predicate(snapshot.relocate)) {
                return snapshot.relocate
            }
            Thread.sleep(POLL_MS)
        }
        val last = reported
        throw AssertionError(
            "timed out after ${timeoutMs}ms waiting for $what; last report seq=${last?.seq} " +
                "pos=${last?.relocate?.pos()} tocHref=${last?.relocate?.tocHref}",
        )
    }

    private class Shell(val webView: WebView, val received: CopyOnWriteArrayList<FoliateMessage>)

    /** The real shell + bundle in a real WebView, with NO book opened — the payload probes need only
     *  the production message channel, so they stay fixture-independent. */
    private fun openShell(): Shell {
        lateinit var wv: WebView
        lateinit var bridge: FoliateBridge
        val received = CopyOnWriteArrayList<FoliateMessage>()
        inst.runOnMainSync {
            wv = WebView(inst.targetContext).also(::forceViewport)
            extraWebViews += wv
            val loader = FoliateAssetServer.loader(inst.targetContext, File(inst.targetContext.cacheDir, "wi7-absent"))
            bridge = FoliateBridge(wv, loader, scope)
        }
        // Subscribe BEFORE loading (the flow is hot) so `bridge-ready` can never be missed.
        scope.launch {
            bridge.messages.onSubscription { bridge.attach(); bridge.load() }.collect { received += it }
        }
        awaitUntil(OPEN_TIMEOUT_MS, "bridge-ready from the real shell") {
            received.any { it is FoliateMessage.BridgeReady }
        }
        return Shell(wv, received)
    }

    private fun inject(shell: Shell, js: String) =
        inst.runOnMainSync { shell.webView.evaluateJavascript(js, null) }

    private fun awaitBookReady(shell: Shell, title: String): FoliateMessage.BookReady {
        awaitUntil(PAYLOAD_TIMEOUT_MS, "the injected '$title' book-ready to cross the real bridge") {
            shell.received.any { it is FoliateMessage.BookReady && it.title == title }
        }
        return shell.received.filterIsInstance<FoliateMessage.BookReady>().first { it.title == title }
    }

    /** A trivial follow-up message must still arrive — a parse that overflowed would have taken the
     *  WebView message callback (and the app) with it. */
    private fun assertChannelStillAlive(shell: Shell, marker: String) {
        inject(shell, "window.__vreaderPost('book-ready',{title:'$marker',sections:1,toc:[{label:'ok',href:'ok.xhtml'}]})")
        val ready = awaitBookReady(shell, marker)
        assertEquals("the message channel did not survive the hostile payload", 1, ready.toc.size)
    }

    private fun forceViewport(wv: WebView) {
        val metrics = inst.targetContext.resources.displayMetrics
        val width = if (metrics.widthPixels > 0) metrics.widthPixels else 1080
        val height = if (metrics.heightPixels > 0) metrics.heightPixels else 1920
        wv.measure(
            View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY),
        )
        wv.layout(0, 0, width, height)
    }

    private fun awaitUntil(timeoutMs: Long, what: String, condition: () -> Boolean) {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (condition()) return
            Thread.sleep(POLL_MS)
        }
        throw AssertionError("timed out after ${timeoutMs}ms waiting for $what")
    }

    /** The reported position — the ONLY evidence of motion this file accepts. */
    private fun FoliateMessage.Relocate.pos(): Triple<String?, Double?, Int> =
        Triple(cfi, fraction, sectionIndex)

    /** Rebuild the wire `toc` array from a parsed tree, for the on-device parse measurement. */
    private fun tocJson(items: List<FoliateTocItem>): JsonArray = JsonArray(
        items.map { item ->
            JsonObject(
                mapOf(
                    "label" to JsonPrimitive(item.label),
                    "href" to JsonPrimitive(item.href),
                    "subitems" to tocJson(item.subitems),
                ),
            )
        },
    )

    private fun deepTocJs(depth: Int, title: String): String =
        "(function(){var root={label:'L0',href:'h0',subitems:[]};var cur=root;" +
            "for(var i=1;i<$depth;i++){var n={label:'L'+i,href:'h'+i,subitems:[]};cur.subitems.push(n);cur=n;}" +
            "window.__vreaderPost('book-ready',{title:'$title',sections:1,toc:[root]});})()"

    private fun flatTocJs(count: Int, title: String): String =
        "(function(){var t=[];for(var i=0;i<$count;i++){t.push({label:'c'+i,href:'h'+i+'.xhtml'});}" +
            "window.__vreaderPost('book-ready',{title:'$title',sections:1,toc:t});})()"

    private companion object {
        const val TAG = "Azw3TocWI7"
        const val POLL_MS = 200L
        const val OPEN_TIMEOUT_MS = 60_000L
        const val SETTLE_TIMEOUT_MS = 30_000L
        const val RELOCATE_TIMEOUT_MS = 30_000L
        const val PAYLOAD_TIMEOUT_MS = 30_000L
        /**
         * ONE window, used for both halves of the drift argument: how long the pre-jump position must
         * hold still, and how long an unresolvable jump is watched for movement. The negative
         * control's liveness half lands a REAL jump inside this same budget, which is what proves the
         * window is long enough (Gate-4 R1 #2/#3). Comfortably past the 3 s goTo ack budget.
         */
        const val SETTLE_HOLD_MS = 5_000L
        const val OBSERVE_WINDOW_MS = SETTLE_HOLD_MS
        /** Iterations the timings are averaged over — a millisecond clock reports this work as 0. */
        const val COST_SAMPLES = 20
        /** ~3 dropped frames at 60 Hz. The parse runs on the thread that paints, so this is the one
         *  non-arbitrary ceiling available for it; the flatten reuses it as a sanity bound. */
        const val MAIN_THREAD_BUDGET_US = 50_000L
        val NONCE = System.nanoTime()
    }
}
