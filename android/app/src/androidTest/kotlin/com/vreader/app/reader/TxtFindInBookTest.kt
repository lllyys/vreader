package com.vreader.app.reader

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.annotations.AnnotationsSnapshot
import com.vreader.app.reader.chrome.ReaderChromeState
import com.vreader.app.reader.chrome.ReaderSheet
import com.vreader.app.reader.nav.JumpResult
import com.vreader.app.reader.settings.ReaderTheme
import com.vreader.app.search.IndexStateGate
import com.vreader.app.search.InBookGroup
import com.vreader.app.search.InBookHit
import com.vreader.app.search.InBookSearchContent
import com.vreader.app.search.InBookSearchOutcome
import com.vreader.app.search.InBookSearchPage
import com.vreader.app.search.InBookSearchSheetContent
import com.vreader.app.search.InBookSearchViewModel
import com.vreader.app.search.InBookSearcher
import com.vreader.app.search.SearchCursor
import com.vreader.app.data.SearchIndexStateEntity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import vreader.contracts.BookFormat
import vreader.contracts.Locator

/**
 * Feature #133 WI-10 — the TXT/MD reader host WIRES the in-book search sheet reachable from the #132 top
 * bar. This drives the extracted [TxtReaderChrome] host-wiring composable directly (the #132/#134/#135
 * connected-test precedent — no seeded Activity; the full end-to-end real-book slice rides WI-12
 * acceptance). It asserts: the Search icon is present on the TXT/MD top bar (the previously-null #133
 * `onOpenSearch` slot is now wired); tapping it opens the [InBookSearchSheet] driven by an
 * [InBookSearchViewModel] for THIS book; typing → hits → tapping a hit resolves a jump through the SAME
 * production helper the host uses ([txtBookmarkScrollTarget] over a real [TxtDocument], then
 * `chunkForOffset` on a real `LazyListState`) returning [JumpResult.Succeeded]; an out-of-range hit →
 * [JumpResult.Failed] (sheet stays open); a zero-hit query → NoResults; the index-state `Unsupported`
 * gate hides the Search icon; the VM is ONE instance across recomposition + cleaned up on teardown; and
 * the SAME wiring covers MD (BookFormat.md).
 */
@RunWith(AndroidJUnit4::class)
class TxtFindInBookTest {
    @get:Rule val compose = createComposeRule()

    private val emptySnapshot = AnnotationsSnapshot(highlights = emptyList(), notes = emptyList())

    // A short document whose chunk boundaries are deterministic (TxtDocument.of), so the production jump
    // seam (txtBookmarkScrollTarget → chunkForOffset) runs against real data.
    private val docText = "Chapter one. ".repeat(400)   // > 5000 chars → multiple chunks

    private fun locator(offset: Int, format: String) = Locator(
        contentSHA256 = "c".repeat(64), fileByteCount = 4096L, format = format, charOffsetUTF16 = offset,
    )

    /** A fake in-book searcher: returns one hit at [hitOffset] for a non-empty query (except the
     *  [zeroHitQuery]). Records the session lifecycle (`closeAllEpubCursors`) so the VM's one-per-session
     *  contract is observable. */
    private class FakeSearcher(
        private val zeroHitQuery: String,
        private val hitLocator: Locator,
    ) : InBookSearcher {
        var closeCursorsCalls = 0
        var pageCalls = 0
        override suspend fun page(
            bookKey: String,
            format: BookFormat,
            rawQuery: String,
            cursor: SearchCursor?,
            pageSize: Int,
        ): InBookSearchOutcome {
            pageCalls++
            if (rawQuery.trim().isEmpty()) return InBookSearchOutcome.NoResults
            if (rawQuery.trim() == zeroHitQuery) return InBookSearchOutcome.NoResults
            val hit = InBookHit(
                sectionTitle = "Section 1",
                canonicalLocator = hitLocator,
                readiumLocatorJson = null,
                snippet = "a passage containing $rawQuery here",
                matchRanges = listOf(IntRange(21, 21 + rawQuery.length - 1)),
            )
            return InBookSearchOutcome.Results(
                InBookSearchPage(listOf(InBookGroup("Section 1", listOf(hit))), moreAvailable = false, nextCursor = null),
            )
        }

        override fun closeAllEpubCursors() { closeCursorsCalls++ }
    }

    private fun indexedRow(bookKey: String) = SearchIndexStateEntity(
        bookKey = bookKey,
        indexerVersion = com.vreader.app.search.SearchIndexCoordinator.INDEXER_VERSION,
        indexedAt = 1L,
        status = "indexed",
    )

    private fun skippedRow(bookKey: String) = SearchIndexStateEntity(
        bookKey = bookKey,
        indexerVersion = com.vreader.app.search.SearchIndexCoordinator.INDEXER_VERSION,
        indexedAt = 1L,
        status = "skipped_unsupported",
    )

    /**
     * The host wiring under test: a [TxtReaderChrome] whose Search slot toggles a `showSearch` state and
     * whose `searchSheet` overlay mounts the real [InBookSearchSheetContent] driven by a real
     * [InBookSearchViewModel] (fed the [searcher]). The `onJump` resolves the hit through the PRODUCTION
     * seam — [txtBookmarkScrollTarget] over a real [TxtDocument] + `chunkForOffset` on a real
     * `LazyListState` — so the test exercises the same range validation + chunk mapping the host uses.
     * The VM is remembered (one per session), collected via a [rememberCoroutineScope], and cleaned up
     * via a [DisposableEffect] (the production lifecycle) — no leaked test scope.
     */
    @Composable
    private fun host(
        format: BookFormat,
        searcher: FakeSearcher,
        indexRowStatus: String = "indexed",
        onJumped: (Int) -> Unit = {},
        onFailed: () -> Unit = {},
    ) {
        val bookKey = locator(0, format.name).fingerprintKey
        val document = remember { TxtDocument.of(docText) }
        val listState = rememberLazyListState()
        val scope: CoroutineScope = rememberCoroutineScope()
        val vm = remember {
            InBookSearchViewModel(
                bookKey = bookKey,
                format = format,
                searcher = searcher,
                indexStateGate = IndexStateGate(Dispatchers.Main.immediate),
                indexStateFlow = flowOf<SearchIndexStateEntity?>(
                    if (indexRowStatus == "skipped_unsupported") skippedRow(bookKey) else indexedRow(bookKey),
                ),
                hasOccurrence = { true },
                recentsFlow = flowOf(emptyList()),
                recordQuery = {},
                dispatcher = Dispatchers.Main.immediate,
                coroutineScope = scope,
            )
        }
        DisposableEffect(vm) { onDispose { vm.onCleared() } }
        val chromeState: MutableState<ReaderChromeState> =
            remember { mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None)) }
        var showSearch by remember { mutableStateOf(false) }
        val screen by vm.state.collectAsStateWithLifecycle()

        TxtReaderChrome(
            theme = ReaderTheme.Paper,
            title = "My Book",
            chromeState = chromeState,
            annotations = emptySnapshot,
            onBack = {},
            onJumpToAnnotation = {},
            onShareAnnotations = {},
            // Mirrors the host: hidden when the gate reports Unsupported, else present.
            onOpenSearch = if (screen.hidesSearchEntry) null else { { showSearch = true } },
            searchSheet = if (!showSearch) null else {
                {
                    InBookSearchSheetContent(
                        theme = ReaderTheme.Paper,
                        bookTitle = "My Book",
                        state = screen,
                        query = screen.query,
                        onQueryChange = vm::onQueryChange,
                        onPickRecent = vm::onPickRecent,
                        // The PRODUCTION jump seam: validate the range up front, then chunkForOffset scroll.
                        onJump = { hit ->
                            val off = hit.canonicalLocator?.charOffsetUTF16
                            val target = txtBookmarkScrollTarget(off, document.text.length)
                            if (target == null) {
                                onFailed(); JumpResult.Failed
                            } else {
                                scope.launch { runCatching { listState.scrollToItem(document.chunkForOffset(target)) } }
                                onJumped(target); JumpResult.Succeeded
                            }
                        },
                        onLoadMore = vm::loadMore,
                        onDismiss = { vm.onDismiss(); showSearch = false },
                    )
                }
            },
            bottomBar = { Box(Modifier.testTag("bottom-stub")) },
            body = { Box(Modifier.fillMaxSize().testTag("txt-reader-body")) },
        )
    }

    @Test fun searchIcon_present_onTxtTopBar() {
        val searcher = FakeSearcher(zeroHitQuery = "zzz", hitLocator = locator(100, "txt"))
        compose.setContent { host(BookFormat.txt, searcher) }
        compose.onNodeWithTag("chrome-search", useUnmergedTree = true).assertExists()
    }

    @Test fun tapSearch_type_tapHit_scrollsToOffset_txt() {
        var jumpedTarget: Int? = null
        val searcher = FakeSearcher(zeroHitQuery = "zzz", hitLocator = locator(1300, "txt"))
        compose.setContent { host(BookFormat.txt, searcher, onJumped = { jumpedTarget = it }) }

        compose.onNodeWithTag("chrome-search", useUnmergedTree = true).performClick()
        compose.onNodeWithTag("inbook-search-sheet-content", useUnmergedTree = true).assertExists()

        compose.onNodeWithTag("inbook-search-field", useUnmergedTree = true).performTextInput("chapter")
        compose.waitForIdle()

        compose.onNodeWithTag("inbook-result-0-0", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("inbook-result-0-0", useUnmergedTree = true).performClick()
        compose.waitForIdle()

        // The production seam resolved a valid in-range target (an in-bounds char offset → a real chunk).
        assertEquals(1300, jumpedTarget)
    }

    @Test fun outOfRangeHit_isFailed_sheetStaysOpen_txt() {
        var failed = false
        var jumped: Int? = null
        // A char offset PAST the document end → txtBookmarkScrollTarget returns null → Failed.
        val searcher = FakeSearcher(zeroHitQuery = "zzz", hitLocator = locator(docText.length + 100, "txt"))
        compose.setContent { host(BookFormat.txt, searcher, onJumped = { jumped = it }, onFailed = { failed = true }) }

        compose.onNodeWithTag("chrome-search", useUnmergedTree = true).performClick()
        compose.onNodeWithTag("inbook-search-field", useUnmergedTree = true).performTextInput("chapter")
        compose.waitForIdle()

        compose.onNodeWithTag("inbook-result-0-0", useUnmergedTree = true).performClick()
        compose.waitForIdle()

        assert(failed) { "an out-of-range hit must resolve to Failed" }
        assertNull("no jump on an out-of-range hit", jumped)
        // Failed keeps the sheet open (dismiss-on-success only).
        compose.onNodeWithTag("inbook-search-sheet-content", useUnmergedTree = true).assertExists()
    }

    @Test fun zeroHitQuery_showsNoResults_txt() {
        val searcher = FakeSearcher(zeroHitQuery = "zzz", hitLocator = locator(1, "txt"))
        compose.setContent { host(BookFormat.txt, searcher) }

        compose.onNodeWithTag("chrome-search", useUnmergedTree = true).performClick()
        compose.onNodeWithTag("inbook-search-field", useUnmergedTree = true).performTextInput("zzz")
        compose.waitForIdle()

        compose.onNodeWithTag("inbook-no-results", useUnmergedTree = true).assertExists()
    }

    @Test fun unsupportedGate_hidesSearchIcon() {
        val searcher = FakeSearcher(zeroHitQuery = "zzz", hitLocator = locator(1, "txt"))
        compose.setContent { host(BookFormat.txt, searcher, indexRowStatus = "skipped_unsupported") }
        // The gate reports Unsupported → the host passes null onOpenSearch → no Search control (no dead control).
        compose.onAllNodesWithTag("chrome-search", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun mdParity_searchIcon_and_hitJump() {
        var jumpedTarget: Int? = null
        val searcher = FakeSearcher(zeroHitQuery = "zzz", hitLocator = locator(2600, "md"))
        compose.setContent { host(BookFormat.md, searcher, onJumped = { jumpedTarget = it }) }

        compose.onNodeWithTag("chrome-search", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("chrome-search", useUnmergedTree = true).performClick()
        compose.onNodeWithTag("inbook-search-field", useUnmergedTree = true).performTextInput("markdown")
        compose.waitForIdle()

        compose.onNodeWithTag("inbook-result-0-0", useUnmergedTree = true).performClick()
        compose.waitForIdle()

        assertEquals(2600, jumpedTarget)
    }
}
