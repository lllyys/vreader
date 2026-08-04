package com.vreader.app.reader

import androidx.compose.runtime.BroadcastFrameClock
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.snapshots.Snapshot
import com.vreader.app.data.Book
import com.vreader.app.reader.nav.TocEntry
import com.vreader.app.reader.nav.TocProvider
import com.vreader.app.reader.nav.TxtMdTocProvider
import com.vreader.app.reader.nav.txtTocIndexFor
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import vreader.contracts.BookFormat
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

/**
 * Feature #139 WI-7 — the host-side TOC wiring seams of [TxtReaderActivity], driven as the host drives
 * them (real Compose state, a real [BroadcastFrameClock], the REAL [TxtMdTocProvider]):
 *
 *  - [awaitTocScanGate] / [runTxtTocScan] — the §4.5 readiness gate. The three gate tests are the JVM
 *    half of the plan's §7a Gate-4 focus: **every value the gate observes must actually re-emit.** They
 *    mutate the same `mutableStateOf` handles the host creates (`pagedBodyMounted` at the host's
 *    `remember(s.document)`, `pagedOffset` likewise) and assert the suspended gate wakes. A gate built on
 *    `TxtPageNavigator.index` — a plain `var`, NOT Compose state — cannot pass
 *    `pagedMode_scanWaitsForFirstSettledPage`, because nothing would ever re-emit.
 *  - the pre-scan posture: until the scan publishes, the host hands the chrome an EMPTY list, which is
 *    exactly `ReaderChromeScaffold`'s hide-the-Contents-control signal.
 *  - [txtTocEntryOffsets] / [txtTocJumpTarget] — the highlight key and the jump target, over entries the
 *    REAL provider produced from real text (not hand-built `TocEntry`s).
 *
 * The composition-level wiring (the control actually appearing, a tapped row navigating, the live
 * highlight) is `TxtTocConnectedTest` — Compose UI testing is not available to this source set.
 */
class TxtTocHostWiringTest {

    // ---- fixtures ------------------------------------------------------------------------------

    private val sha = "c".repeat(64)

    private fun book(format: BookFormat = BookFormat.txt, bytes: Long = 4096L) = Book(
        fingerprintKey = "${format.name}:$sha:$bytes",
        title = "A Book",
        originalFormat = format,
        contentSHA256 = sha,
        fileByteCount = bytes,
        addedAt = 0L,
    )

    /** Three rule-3 ("Chapter N …") headings — the enabled English chapter rule, ≥2 matches so
     *  detection has a winner. */
    private val chapteredText = buildString {
        append("Front matter that is not a heading.\n")
        append("Chapter 1 The Beginning\n")
        append("Body of the first chapter.\n")
        append("Chapter 2 The Middle\n")
        append("Body of the second chapter.\n")
        append("Chapter 3 The End\n")
        append("Body of the third chapter.\n")
    }

    /** CJK chapters (rule 1) — proves the offsets the jump uses are UTF-16 code-unit offsets into the
     *  raw decoded text, which is what `txtBookmarkLocator` / the chunk-scroll seam consume. */
    private val cjkText = buildString {
        // Body lines deliberately start with a non-marker character: rule 1 also fires on a line
        // BEGINNING with 楔子 / 正文 / 序章, so a careless "正文内容…" body line would itself be detected
        // as a heading and the fixture would silently assert the wrong thing.
        append("这是一段导语，不是标题。\n")
        append("第一章 起点\n")
        append("随便写几句内容。\n")
        append("第二章 转折\n")
        append("又是一些内容。\n")
    }

    /** Plain prose — deliberately matches NO enabled rule (no Chapter+digit, no leading digit, no
     *  bracket/star marker, no Prologue/Epilogue word). */
    private val proseText = buildString {
        repeat(40) { append("The quick brown fox jumps over the lazy dog again and again.\n") }
    }

    private val markdownText = """
        # Top level
        Some body text.
        ## Nested one
        More body text.
        ### Nested two
        Even more body text.
    """.trimIndent()

    private fun providerFor(text: String, format: BookFormat = BookFormat.txt) =
        TxtMdTocProvider(text = text, book = book(format), format = format, dispatcher = Dispatchers.Default)

    /** Counts `toc()` calls so a gate that fires more than once (or not at all) is visible. */
    private class CountingProvider(private val delegate: TocProvider) : TocProvider {
        val calls = AtomicInteger(0)
        override suspend fun toc(): List<TocEntry> {
            calls.incrementAndGet()
            return delegate.toc()
        }
    }

    // ---- gate harness --------------------------------------------------------------------------

    private val clock = BroadcastFrameClock()
    private val job = Job()
    private val scope = CoroutineScope(Dispatchers.Default + job + clock)

    @After fun cancelScope() { job.cancel() }

    private fun awaitTrue(timeoutMs: Long = 5_000, predicate: () -> Boolean): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (predicate()) return true
            Thread.sleep(5)
        }
        return predicate()
    }

    /** True when [predicate] held for the whole window (the "it did NOT fire" assertion). */
    private fun heldFor(windowMs: Long = 300, predicate: () -> Boolean): Boolean {
        val deadline = System.currentTimeMillis() + windowMs
        while (System.currentTimeMillis() < deadline) {
            if (!predicate()) return false
            Thread.sleep(5)
        }
        return predicate()
    }

    /** Produce exactly one frame, once the gate has actually parked on the frame clock. */
    private fun produceFrame() {
        assertTrue("the gate parked on the frame clock", awaitTrue { clock.hasAwaiters })
        clock.sendFrame(0L)
    }

    private fun publishState(): AtomicReference<List<TocEntry>?> = AtomicReference(null)

    // ---- the §4.5 readiness gate ---------------------------------------------------------------

    @Test fun scrollMode_scanWaitsForFirstFrame() {
        val pagedBodyMounted = mutableStateOf(false)   // scroll body
        val pagedOffset = mutableStateOf(-1)
        val provider = CountingProvider(providerFor(chapteredText))
        val published = publishState()

        scope.launch { runTxtTocScan(provider, pagedBodyMounted, pagedOffset) { published.set(it) } }

        // No frame yet → the scan has not even been ASKED for (it must stay off the first-paint path).
        assertTrue(
            "the scan must not start before the first frame",
            heldFor { published.get() == null && provider.calls.get() == 0 },
        )

        produceFrame()

        assertTrue("a frame releases the scroll-mode gate", awaitTrue { published.get() != null })
        assertEquals(3, published.get()!!.size)
    }

    @Test fun pagedMode_scanWaitsForFirstSettledPage() {
        val pagedBodyMounted = mutableStateOf(true)    // paged body
        val pagedOffset = mutableStateOf(-1)           // no settled page published yet
        val provider = CountingProvider(providerFor(chapteredText))
        val published = publishState()

        scope.launch { runTxtTocScan(provider, pagedBodyMounted, pagedOffset) { published.set(it) } }
        produceFrame()

        // A frame alone is NOT enough in paged mode — the paged body has not published a page.
        assertTrue(
            "the paged gate holds until the first settled page",
            heldFor { published.get() == null && provider.calls.get() == 0 },
        )

        // The paged body's onSaveSourceOffset callback publishes page 0's start offset. This is
        // Compose state, so the gate's snapshotFlow re-evaluates — the whole point of NOT using
        // TxtPageNavigator.index (a plain `var`, which would never re-emit).
        pagedOffset.value = 0
        Snapshot.sendApplyNotifications()

        assertTrue("the first settled page releases the paged gate", awaitTrue { published.get() != null })
        assertEquals(3, published.get()!!.size)
    }

    @Test fun pagedMode_gateReleasesIfBodyFlipsToScrollMidWait() {
        val pagedBodyMounted = mutableStateOf(true)
        val pagedOffset = mutableStateOf(-1)           // and it never publishes one
        val provider = CountingProvider(providerFor(chapteredText))
        val published = publishState()

        scope.launch { runTxtTocScan(provider, pagedBodyMounted, pagedOffset) { published.set(it) } }
        produceFrame()
        assertTrue("still parked in paged mode", heldFor { published.get() == null })

        // A bilingual toggle / layout change unmounts the paged body mid-wait. The scan must NOT be
        // stranded for the rest of the session (Gate-2 R4 HIGH).
        pagedBodyMounted.value = false
        Snapshot.sendApplyNotifications()

        assertTrue("a flip to scroll releases the gate", awaitTrue { published.get() != null })
    }

    @Test fun scanIsKeyedOnDocument_notOnEveryRecomposition() {
        val pagedBodyMounted = mutableStateOf(true)
        val pagedOffset = mutableStateOf(-1)
        val provider = CountingProvider(providerFor(chapteredText))
        val publishes = AtomicInteger(0)

        scope.launch { runTxtTocScan(provider, pagedBodyMounted, pagedOffset) { publishes.incrementAndGet() } }
        produceFrame()
        pagedOffset.value = 0
        Snapshot.sendApplyNotifications()
        assertTrue(awaitTrue { publishes.get() == 1 })

        // Every further change to the state the gate observed — page turns, a layout flip — is a
        // recomposition-level event. ONE scan per document: the gate terminates, it does not keep
        // collecting and re-publishing.
        repeat(6) { i ->
            pagedOffset.value = i + 1
            pagedBodyMounted.value = i % 2 == 0
            Snapshot.sendApplyNotifications()
            Thread.sleep(10)
        }
        assertTrue("the scan ran exactly once", heldFor { provider.calls.get() == 1 && publishes.get() == 1 })
    }

    // ---- the pre-scan posture ------------------------------------------------------------------

    @Test fun preScanState_passesEmptyEntries_soContentsStaysHidden() {
        val pagedBodyMounted = mutableStateOf(false)
        val pagedOffset = mutableStateOf(-1)
        // The host's `remember(s.document) { mutableStateOf(emptyList()) }` — what TxtReaderChrome reads.
        val entries = mutableStateOf(emptyList<TocEntry>())

        scope.launch { runTxtTocScan(providerFor(chapteredText), pagedBodyMounted, pagedOffset) { entries.value = it } }

        // Pre-scan the host is byte-identical to today: an empty list, which is exactly
        // ReaderChromeScaffold's "hide the Contents control" signal.
        assertTrue("pre-scan entries are empty", heldFor { entries.value.isEmpty() })
        produceFrame()
        assertTrue("the scan publishes the chapters", awaitTrue { entries.value.isNotEmpty() })
    }

    @Test fun zeroDetectedHeadings_keepsContentsControlHidden() {
        val pagedBodyMounted = mutableStateOf(false)
        val pagedOffset = mutableStateOf(-1)
        val provider = CountingProvider(providerFor(proseText))
        val entries = mutableStateOf(emptyList<TocEntry>())

        scope.launch { runTxtTocScan(provider, pagedBodyMounted, pagedOffset) { entries.value = it } }
        produceFrame()

        // The scan RAN (so this is not a false pass from a stuck gate) and found nothing → the list
        // stays empty → the Contents control stays hidden. No empty sheet is ever reachable.
        assertTrue("the scan ran", awaitTrue { provider.calls.get() == 1 })
        assertTrue("prose with no chapter markers yields no TOC", heldFor { entries.value.isEmpty() })
    }

    // ---- highlight key + jump target -----------------------------------------------------------

    @Test fun jumpTargetIsEntryCharOffsetUtf16() {
        val entries = runBlocking { providerFor(chapteredText).toc() }
        assertEquals(3, entries.size)

        // Each entry's offset is the heading line's start in the RAW decoded text.
        assertEquals(chapteredText.indexOf("Chapter 1"), entries[0].canonicalLocator.charOffsetUTF16)
        assertEquals(chapteredText.indexOf("Chapter 2"), entries[1].canonicalLocator.charOffsetUTF16)
        assertEquals(chapteredText.indexOf("Chapter 3"), entries[2].canonicalLocator.charOffsetUTF16)

        // The jump target IS that offset — no re-derivation, no page, no chunk index.
        assertEquals(
            entries[1].canonicalLocator.charOffsetUTF16,
            txtTocJumpTarget(entries, 1, chapteredText.length),
        )
        // Out-of-range row indices degrade to null → the sheet stays open (rule 51), never a crash.
        assertNull(txtTocJumpTarget(entries, -1, chapteredText.length))
        assertNull(txtTocJumpTarget(entries, entries.size, chapteredText.length))
        assertNull(txtTocJumpTarget(emptyList(), 0, chapteredText.length))
        // An offset at/past EOF (an empty document) is out of range, exactly like a bookmark's.
        assertNull(txtTocJumpTarget(entries, 0, 0))
    }

    @Test fun jumpTargetIsUtf16Offset_forCjkChapters() {
        val entries = runBlocking { providerFor(cjkText).toc() }
        assertEquals(2, entries.size)
        assertEquals(cjkText.indexOf("第一章"), txtTocJumpTarget(entries, 0, cjkText.length))
        assertEquals(cjkText.indexOf("第二章"), txtTocJumpTarget(entries, 1, cjkText.length))
    }

    @Test fun entryOffsetsFeedTheCurrentChapterHighlight() {
        val entries = runBlocking { providerFor(chapteredText).toc() }
        val offsets = txtTocEntryOffsets(entries)
        assertEquals(entries.map { it.canonicalLocator.charOffsetUTF16 }, offsets)

        // The live reading position resolves to the last chapter at-or-before it (WI-5's contract).
        assertEquals(0, txtTocIndexFor(0, offsets))                       // before chapter 1 → row 0
        assertEquals(0, txtTocIndexFor(offsets[0], offsets))              // exactly at chapter 1
        assertEquals(1, txtTocIndexFor(offsets[1] + 3, offsets))          // inside chapter 2
        assertEquals(2, txtTocIndexFor(chapteredText.length, offsets))    // past the last heading
        assertEquals(-1, txtTocIndexFor(0, txtTocEntryOffsets(emptyList())))
    }

    @Test fun markdownEntriesCarryHeadingDepth() {
        val entries = runBlocking { providerFor(markdownText, BookFormat.md).toc() }
        assertEquals(listOf(0, 1, 2), entries.map { it.depth })
        assertEquals(listOf("Top level", "Nested one", "Nested two"), entries.map { it.title })
        // TXT stays flat (plan §4.3) — the indentation the sheet renders is MD-only.
        assertEquals(listOf(0, 0, 0), runBlocking { providerFor(chapteredText).toc() }.map { it.depth })
    }
}
