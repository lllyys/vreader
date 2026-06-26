package com.vreader.app.opds.ui

import com.vreader.app.data.Book
import com.vreader.app.opds.OpdsEntry
import com.vreader.app.opds.OpdsError
import com.vreader.app.opds.OpdsFeed
import com.vreader.app.opds.OpdsLink
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import vreader.contracts.BookFormat

/** Feature #120 WI-3 — OpdsBrowseViewModel: feed split, download→in-library, errors, pagination. */
@OptIn(ExperimentalCoroutinesApi::class)
class OpdsBrowseViewModelTest {
    private val dispatcher = StandardTestDispatcher()
    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private fun acq(href: String) = OpdsLink(rel = "http://opds-spec.org/acquisition", href = href, type = "application/epub+zip")
    private fun nav(href: String) = OpdsLink(rel = "subsection", href = href, type = "application/atom+xml")
    private fun bookEntry(id: String, title: String, href: String) =
        OpdsEntry(title = title, id = id, author = "Author", links = listOf(acq(href)))
    private fun navEntry(title: String, href: String) = OpdsEntry(title = title, id = title, links = listOf(nav(href)))
    private fun feed(entries: List<OpdsEntry>, base: String, next: String? = null) = OpdsFeed(
        title = "Catalog", id = "i", entries = entries, baseUrl = base,
        links = next?.let { listOf(OpdsLink(rel = "next", href = it, type = "application/atom+xml")) } ?: emptyList(),
    )

    private fun book(sourceUri: String) = Book(
        fingerprintKey = "epub:${sourceUri.hashCode()}:1", title = "T", originalFormat = BookFormat.epub,
        contentSHA256 = "x", fileByteCount = 1, sourceUri = sourceUri, addedAt = 0,
    )

    private fun vm(
        fetch: suspend (String) -> OpdsFeed,
        import: suspend (OpdsEntry, String?) -> Book = { _, _ -> book("opds://x") },
        library: MutableStateFlow<List<Book>> = MutableStateFlow(emptyList()),
        d: CoroutineDispatcher = dispatcher,
    ) = OpdsBrowseViewModel("Standard Ebooks", "https://se.org/opds",
        { url -> fetch(url) }, { e, b -> import(e, b) }, library, d)

    @Test fun open_splitsNavAndAcquisition() = runTest(dispatcher) {
        val v = vm(fetch = {
            feed(listOf(navEntry("By author", "https://se.org/authors"), bookEntry("b1", "Middlemarch", "https://se.org/mm.epub")), "https://se.org/opds")
        })
        advanceUntilIdle()
        assertEquals(OpdsBrowsePhase.feed, v.state.value.phase)
        assertEquals(listOf("By author"), v.state.value.navRows.map { it.title })
        assertEquals(listOf("Middlemarch"), v.state.value.entries.map { it.title })
        assertEquals(OpdsItemState.remote, v.state.value.entries.single().state)
        assertEquals("EPUB", v.state.value.entries.single().format)
    }

    @Test fun download_flipsToLibrary() = runTest(dispatcher) {
        val href = "https://se.org/mm.epub"
        val v = vm(
            fetch = { feed(listOf(bookEntry("b1", "Middlemarch", href)), "https://se.org/opds") },
            import = { _, _ -> book("opds://$href") },
        )
        advanceUntilIdle()
        val key = v.state.value.entries.single().key
        v.download(key); advanceUntilIdle()
        assertEquals(OpdsItemState.library, v.state.value.entries.single().state)
    }

    @Test fun download_failure_marksFailed() = runTest(dispatcher) {
        val v = vm(
            fetch = { feed(listOf(bookEntry("b1", "M", "https://se.org/m.epub")), "https://se.org/opds") },
            import = { _, _ -> throw OpdsError.NotABook("html") },
        )
        advanceUntilIdle()
        val key = v.state.value.entries.single().key
        v.download(key); advanceUntilIdle()
        assertEquals(OpdsItemState.failed, v.state.value.entries.single().state)
        assertTrue(v.state.value.entries.single().failMessage!!.isNotBlank())
    }

    @Test fun existingSourceUri_showsInLibraryUpfront() = runTest(dispatcher) {
        val href = "https://se.org/mm.epub"
        val v = vm(
            fetch = { feed(listOf(bookEntry("b1", "Middlemarch", href)), "https://se.org/opds") },
            library = MutableStateFlow(listOf(book("opds://$href"))),
        )
        advanceUntilIdle()
        assertEquals(OpdsItemState.library, v.state.value.entries.single().state)
    }

    @Test fun error_offline_auth_notfound() = runTest(dispatcher) {
        for ((e, expected) in listOf(
            OpdsError.Network("x") to OpdsBrowseError.offline,
            OpdsError.Http(401) to OpdsBrowseError.auth,
            OpdsError.Http(404) to OpdsBrowseError.notfound,
        )) {
            val v = vm(fetch = { throw e })
            advanceUntilIdle()
            assertEquals(OpdsBrowsePhase.error, v.state.value.phase)
            assertEquals(expected, v.state.value.errorKind)
        }
    }

    @Test fun loadMore_appendsNextPage() = runTest(dispatcher) {
        var page = 0
        val v = vm(fetch = { url ->
            page++
            if (url.contains("p2")) feed(listOf(bookEntry("b2", "Walden", "https://se.org/w.epub")), "https://se.org/opds")
            else feed(listOf(bookEntry("b1", "Middlemarch", "https://se.org/mm.epub")), "https://se.org/opds", next = "https://se.org/opds?p2")
        })
        advanceUntilIdle()
        assertEquals(1, v.state.value.entries.size)
        assertTrue(v.state.value.canLoadMore)
        v.loadMore(); advanceUntilIdle()
        assertEquals(listOf("Middlemarch", "Walden"), v.state.value.entries.map { it.title })
    }

    @Test fun loadMore_dedupesDuplicateAcrossPages() = runTest(dispatcher) {
        val v = vm(fetch = { url ->
            if (url.contains("p2"))
                feed(listOf(bookEntry("b1", "Middlemarch", "https://se.org/mm.epub"), bookEntry("b2", "Walden", "https://se.org/w.epub")), "https://se.org/opds")
            else
                feed(listOf(bookEntry("b1", "Middlemarch", "https://se.org/mm.epub")), "https://se.org/opds", next = "https://se.org/opds?p2")
        })
        advanceUntilIdle()
        v.loadMore(); advanceUntilIdle()
        // b1 appears on both pages → deduped to a single row
        assertEquals(listOf("Middlemarch", "Walden"), v.state.value.entries.map { it.title })
    }

    @Test fun nonImportableAcquisition_isNotShownAsBook() = runTest(dispatcher) {
        // a buy-only entry (acquisition link but not auto-importable) is not a downloadable book row
        val buyOnly = OpdsEntry(title = "Paid Book", id = "p1", links = listOf(
            OpdsLink(rel = "http://opds-spec.org/acquisition/buy", href = "https://se.org/buy", type = "application/epub+zip")))
        val v = vm(fetch = { feed(listOf(buyOnly, bookEntry("b1", "Free", "https://se.org/f.epub")), "https://se.org/opds") })
        advanceUntilIdle()
        assertEquals(listOf("Free"), v.state.value.entries.map { it.title })
    }

    @Test fun empty_feed_showsEmpty() = runTest(dispatcher) {
        val v = vm(fetch = { feed(emptyList(), "https://se.org/opds") })
        advanceUntilIdle()
        assertEquals(OpdsBrowsePhase.empty, v.state.value.phase)
    }
}
