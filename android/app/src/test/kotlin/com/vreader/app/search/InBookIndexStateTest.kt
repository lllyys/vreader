package com.vreader.app.search

import com.vreader.app.data.SearchIndexStateEntity
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test
import vreader.contracts.BookFormat

/**
 * Feature #133 WI-7 — the per-book index-state → in-book-search UI-state gate.
 *
 * Maps a book's FTS [SearchIndexStateEntity] (evaluated at the current [SearchIndexCoordinator.INDEXER_VERSION])
 * + its [BookFormat] + whether it has any matching occurrence into an [InBookIndexState] so TXT/MD search never
 * shows a false "no results" while the index is still building. EPUB bypasses the gate entirely (Readium
 * searches the live publication — its FTS row presence/absence is irrelevant, it never enters Indexing).
 *
 * Pure JVM — no Robolectric needed (no android.icu here; the string vocabulary is exact). The staleness
 * predicate MIRRORS [SearchIndexCoordinator.isEligible]: a MISSING row or a row at an OLD indexerVersion is
 * still-working (Indexing — the coordinator will (re-)index it, so it settles); a current-version `failed`
 * row is retryable (Failed); a current-version `indexed`/`skipped_unsupported` row is settled. A CURRENT-
 * version UNEXPECTED status (`indexing`, a typo) is NOT eligible for re-index by the coordinator, so it can
 * never settle — mapping it to Indexing would spin the UI forever (Gate-4 High), so it surfaces as the
 * recoverable Failed terminal instead.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class InBookIndexStateTest {

    private val txtKey = "txt:${"a".repeat(64)}:1234"
    private val mdKey = "md:${"b".repeat(64)}:5678"
    private val epubKey = "epub:${"c".repeat(64)}:9012"
    // A book key whose byteCount segment carries CJK — the mapping must ignore key content entirely.
    private val cjkKey = "txt:${"d".repeat(64)}:关于编程"
    private val version = SearchIndexCoordinator.INDEXER_VERSION

    private fun state(key: String, status: String, ver: Int = version) =
        SearchIndexStateEntity(bookKey = key, indexerVersion = ver, indexedAt = 0L, status = status)

    // ---- Case 1: TXT/MD missing / in-progress / stale-version → Indexing (not a false NoResults) ----

    @Test fun txt_missingRow_isIndexing() {
        assertEquals(
            InBookIndexState.Indexing,
            IndexStateGate.evaluate(BookFormat.txt, null, hasOccurrence = false),
        )
    }

    @Test fun md_missingRow_isIndexing() {
        assertEquals(
            InBookIndexState.Indexing,
            IndexStateGate.evaluate(BookFormat.md, null, hasOccurrence = false),
        )
    }

    @Test fun txt_indexedButStaleVersion_isIndexing() {
        // A row at an OLD indexerVersion still needs re-indexing (mirrors SearchIndexCoordinator.isEligible).
        val stale = state(txtKey, "indexed", ver = version - 1)
        assertEquals(InBookIndexState.Indexing, IndexStateGate.evaluate(BookFormat.txt, stale, hasOccurrence = true))
    }

    @Test fun txt_skippedButStaleVersion_isIndexing() {
        // Even skipped_unsupported at an old version is not settled — it will be re-attempted.
        val stale = state(txtKey, "skipped_unsupported", ver = version - 1)
        assertEquals(InBookIndexState.Indexing, IndexStateGate.evaluate(BookFormat.txt, stale, hasOccurrence = false))
    }

    @Test fun txt_staleVersionUnexpectedStatus_isIndexing() {
        // A STALE-version row (whatever its status) WILL be re-indexed by the coordinator, so it settles →
        // hold as Indexing.
        for (bogus in listOf("indexing", "faild", "pending", "")) {
            assertEquals(
                "stale-version status='$bogus' will be re-indexed → Indexing",
                InBookIndexState.Indexing,
                IndexStateGate.evaluate(BookFormat.txt, state(txtKey, bogus, ver = version - 1), hasOccurrence = false),
            )
        }
    }

    @Test fun txt_currentVersionUnexpectedStatus_isFailed_notIndexingForever() {
        // Gate-4 High: a CURRENT-version non-`failed`, non-settled status is NOT eligible for re-index by
        // SearchIndexCoordinator.isEligible (which retries only missing / stale-version / exactly `failed`),
        // so it can NEVER settle. Mapping it to Indexing would spin the UI forever waiting for an emission
        // that can't come — surface the recoverable Failed terminal instead.
        for (bogus in listOf("indexing", "faild", "pending", "")) {
            assertEquals(
                "current-version status='$bogus' is a stuck terminal → Failed (recoverable), never Indexing",
                InBookIndexState.Failed,
                IndexStateGate.evaluate(BookFormat.txt, state(txtKey, bogus), hasOccurrence = false),
            )
        }
    }

    // ---- Case 2: TXT/MD indexed (current version) + 0 occurrences → NoResults (definitive) ----

    @Test fun txt_indexedZeroOccurrences_isNoResults() {
        assertEquals(
            InBookIndexState.NoResults,
            IndexStateGate.evaluate(BookFormat.txt, state(txtKey, "indexed"), hasOccurrence = false),
        )
    }

    @Test fun md_indexedZeroOccurrences_isNoResults() {
        assertEquals(
            InBookIndexState.NoResults,
            IndexStateGate.evaluate(BookFormat.md, state(mdKey, "indexed"), hasOccurrence = false),
        )
    }

    // ---- Case 3: TXT/MD indexed (current version) + >0 occurrences → Ready (results flow) ----

    @Test fun txt_indexedWithOccurrences_isReady() {
        assertEquals(
            InBookIndexState.Ready,
            IndexStateGate.evaluate(BookFormat.txt, state(txtKey, "indexed"), hasOccurrence = true),
        )
    }

    // ---- Case 4: skipped_unsupported (current version) → Unsupported hidden-icon flag ----

    @Test fun txt_skippedUnsupported_isUnsupported() {
        val s = IndexStateGate.evaluate(BookFormat.txt, state(txtKey, "skipped_unsupported"), hasOccurrence = false)
        assertEquals(InBookIndexState.Unsupported, s)
        assertEquals("caller hides the Search entry", true, s.hidesSearchEntry)
    }

    @Test fun onlyUnsupported_hidesSearchEntry() {
        // No other state hides the icon — Indexing/NoResults/Ready/Failed all keep the entry visible.
        assertEquals(false, InBookIndexState.Ready.hidesSearchEntry)
        assertEquals(false, InBookIndexState.Indexing.hidesSearchEntry)
        assertEquals(false, InBookIndexState.NoResults.hidesSearchEntry)
        assertEquals(false, InBookIndexState.Failed.hidesSearchEntry)
        assertEquals(true, InBookIndexState.Unsupported.hidesSearchEntry)
    }

    // ---- Case 5: failed (any version) → Failed (retryable) ----

    @Test fun txt_failed_isFailed() {
        assertEquals(
            InBookIndexState.Failed,
            IndexStateGate.evaluate(BookFormat.txt, state(txtKey, "failed"), hasOccurrence = false),
        )
    }

    @Test fun txt_failedStaleVersion_isIndexing() {
        // A STALE-version row is re-indexed by the coordinator regardless of its status (isEligible returns
        // eligible on a version mismatch BEFORE it looks at status), so a stale `failed` row WILL settle →
        // Indexing (the faithful mirror), not the current-version-`failed` retryable terminal.
        assertEquals(
            InBookIndexState.Indexing,
            IndexStateGate.evaluate(BookFormat.txt, state(txtKey, "failed", ver = version - 1), hasOccurrence = false),
        )
    }

    // ---- Case 7: EPUB never enters Indexing regardless of the FTS row ----

    @Test fun epub_alwaysReady_regardlessOfRow() {
        // EPUB searches Readium live; its FTS-index row is irrelevant. Whatever the row, EPUB is Ready — never
        // Indexing, never NoResults-by-index, never Unsupported-by-index.
        val rows = listOf<SearchIndexStateEntity?>(
            null,
            state(epubKey, "indexed"),
            state(epubKey, "failed"),
            state(epubKey, "skipped_unsupported"),
            state(epubKey, "indexed", ver = version - 1),
            state(epubKey, "indexing"),
        )
        for (row in rows) {
            assertEquals(
                "EPUB must bypass the gate for row=$row",
                InBookIndexState.Ready,
                IndexStateGate.evaluate(BookFormat.epub, row, hasOccurrence = false),
            )
        }
    }

    // ---- PDF/AZW3: no FTS index, no Readium publication → Unsupported (defensive) ----

    @Test fun pdfAndAzw3_areUnsupported() {
        for (fmt in listOf(BookFormat.pdf, BookFormat.azw3)) {
            assertEquals(
                "format=$fmt has no in-book search",
                InBookIndexState.Unsupported,
                IndexStateGate.evaluate(fmt, null, hasOccurrence = false),
            )
        }
    }

    // ---- CJK book key: the mapping ignores key content ----

    @Test fun cjkBookKey_indexedZero_isNoResults() {
        assertEquals(
            InBookIndexState.NoResults,
            IndexStateGate.evaluate(BookFormat.txt, state(cjkKey, "indexed"), hasOccurrence = false),
        )
    }

    // ---- Case 6: a held query re-runs on settle — the observed Flow re-emits Indexing → NoResults/Ready ----

    @Test fun observe_txt_reEmitsWhenIndexSettles_toNoResults() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val rows = MutableStateFlow<SearchIndexStateEntity?>(null)   // starts missing → Indexing
        val gate = IndexStateGate(dispatcher)
        val seen = mutableListOf<InBookIndexState>()
        val job = launch(dispatcher) {
            gate.observe(BookFormat.txt, txtKey, hasOccurrence = { false }, indexStateFlow = rows).toList(seen)
        }
        advanceUntilIdle()
        assertEquals("held query first sees Indexing", listOf(InBookIndexState.Indexing), seen)

        rows.value = state(txtKey, "indexed")   // the coordinator settles the book with no matches
        advanceUntilIdle()
        assertEquals(
            "on settle the gate re-emits the definitive NoResults so the held query un-gates",
            listOf(InBookIndexState.Indexing, InBookIndexState.NoResults),
            seen,
        )
        job.cancel()
    }

    @Test fun observe_txt_reEmitsWhenIndexSettles_toReady() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val rows = MutableStateFlow<SearchIndexStateEntity?>(null)
        val gate = IndexStateGate(dispatcher)
        val seen = mutableListOf<InBookIndexState>()
        val job = launch(dispatcher) {
            // A held query WOULD match once the index exists → hasOccurrence flips true on settle.
            gate.observe(
                BookFormat.txt,
                txtKey,
                hasOccurrence = { rows.value?.status == "indexed" },
                indexStateFlow = rows,
            ).toList(seen)
        }
        advanceUntilIdle()

        rows.value = state(txtKey, "indexed")
        advanceUntilIdle()
        assertEquals(listOf(InBookIndexState.Indexing, InBookIndexState.Ready), seen)
        job.cancel()
    }

    @Test fun observe_epub_firstEmissionIsReady_neverIndexing() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val rows = MutableStateFlow<SearchIndexStateEntity?>(null)   // EPUB with no FTS row
        val gate = IndexStateGate(dispatcher)
        val first = gate.observe(BookFormat.epub, epubKey, hasOccurrence = { false }, indexStateFlow = rows).first()
        assertEquals("EPUB never enters Indexing even with a missing FTS row", InBookIndexState.Ready, first)
    }

    // ---- Flow-guarantee invariants (Gate-4 Low: assert the promises made in the KDoc) ----

    @Test fun observe_nonFts_neverSubscribesToTheIndexStateFlow() = runTest {
        // EPUB/PDF/AZW3 short-circuit to a single mapped state and MUST NOT subscribe to the FTS flow (they
        // do not use the FTS index). A subscription-counting flow proves it: the underlying flow's collector
        // is never invoked.
        val dispatcher = StandardTestDispatcher(testScheduler)
        val gate = IndexStateGate(dispatcher)
        for ((fmt, key, expected) in listOf(
            Triple(BookFormat.epub, epubKey, InBookIndexState.Ready),
            Triple(BookFormat.pdf, "pdf:${"e".repeat(64)}:42", InBookIndexState.Unsupported),
            Triple(BookFormat.azw3, "azw3:${"f".repeat(64)}:99", InBookIndexState.Unsupported),
        )) {
            var subscriptions = 0
            val counting = kotlinx.coroutines.flow.flow<SearchIndexStateEntity?> {
                subscriptions++
                emit(null)
            }
            val states = gate.observe(fmt, key, hasOccurrence = { false }, indexStateFlow = counting).toList()
            assertEquals("format=$fmt emits exactly its one mapped state", listOf(expected), states)
            assertEquals("format=$fmt must NOT subscribe to the FTS index-state flow", 0, subscriptions)
        }
    }

    @Test fun observe_hasOccurrence_calledOnlyForIndexedRow() = runTest {
        // hasOccurrence() is an FTS COUNT query — it must be consulted ONLY for a settled-`indexed` TXT/MD
        // row, never for missing / stale / failed / skipped / unexpected rows.
        val dispatcher = StandardTestDispatcher(testScheduler)
        val gate = IndexStateGate(dispatcher)
        var calls = 0
        val occ: suspend () -> Boolean = { calls++; true }

        // A stream of non-indexed rows: missing → failed → skipped → unexpected. None may query occurrences.
        val nonIndexed = listOf<SearchIndexStateEntity?>(
            null,
            state(txtKey, "failed"),
            state(txtKey, "skipped_unsupported"),
            state(txtKey, "indexing"),
        )
        for (row in nonIndexed) {
            gate.observe(BookFormat.txt, txtKey, hasOccurrence = occ, indexStateFlow = MutableStateFlow(row)).first()
        }
        assertEquals("occurrence check must be skipped for every non-indexed row", 0, calls)

        // A settled-indexed row DOES consult it exactly once.
        gate.observe(BookFormat.txt, txtKey, hasOccurrence = occ, indexStateFlow = MutableStateFlow(state(txtKey, "indexed"))).first()
        assertEquals("indexed row consults the occurrence check once", 1, calls)
    }

    @Test fun observe_cancellingScope_stopsCollecting() = runTest {
        // Cancelling the collecting scope must stop the gate's Flow (structured-concurrency propagation — a
        // superseded query from WI-8's flatMapLatest must not keep the old index-state subscription alive).
        val dispatcher = StandardTestDispatcher(testScheduler)
        val rows = MutableStateFlow<SearchIndexStateEntity?>(null)
        val gate = IndexStateGate(dispatcher)
        val seen = mutableListOf<InBookIndexState>()
        val job = launch(dispatcher) {
            gate.observe(BookFormat.txt, txtKey, hasOccurrence = { false }, indexStateFlow = rows).toList(seen)
        }
        advanceUntilIdle()
        assertEquals(listOf(InBookIndexState.Indexing), seen)

        job.cancel()
        advanceUntilIdle()
        // After cancellation a new row emission is NOT observed by the cancelled collector.
        rows.value = state(txtKey, "indexed")
        advanceUntilIdle()
        assertEquals("cancelled collector receives no further emissions", listOf(InBookIndexState.Indexing), seen)
    }
}
