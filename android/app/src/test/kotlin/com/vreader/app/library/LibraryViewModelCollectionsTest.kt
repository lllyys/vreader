package com.vreader.app.library

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.vreader.app.data.BookEntity
import com.vreader.app.data.BookImporter
import com.vreader.app.data.CollectionRepository
import com.vreader.app.data.LibraryRepository
import com.vreader.app.data.VReaderDatabase
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.File

/**
 * Feature #127 WI-3 — [LibraryViewModel] collections filtering. Selecting a collection chip filters the
 * grid to that collection's members (flatMapLatest, race-free); "All" shows everything; deleting the
 * selected collection resets the selection to "All". Robolectric + in-memory Room (the LibraryViewModelTest
 * precedent: real-time runBlocking, Room Flow emits on its own executor).
 */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
class LibraryViewModelCollectionsTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private lateinit var db: VReaderDatabase
    private lateinit var collections: CollectionRepository
    private lateinit var vm: LibraryViewModel
    private val key1 = "epub:${"a".repeat(64)}:1"
    private val key2 = "epub:${"b".repeat(64)}:2"

    @Before fun setUp() {
        Dispatchers.setMain(Dispatchers.Unconfined)
        db = Room.inMemoryDatabaseBuilder(context, VReaderDatabase::class.java).build()
        val repository = LibraryRepository(db.bookDao(), db.readingPositionDao())
        collections = CollectionRepository(db.collectionDao())
        val importer = BookImporter(File(context.cacheDir, "b-${System.nanoTime()}"), repository, Dispatchers.Unconfined)
        runBlocking {
            db.bookDao().upsert(BookEntity(key1, "Alpha", "epub", "a".repeat(64), 1L, null, null, 1L, null))
            db.bookDao().upsert(BookEntity(key2, "Beta", "epub", "b".repeat(64), 2L, null, null, 2L, null))
        }
        vm = LibraryViewModel(repository, importer, collections, context.contentResolver, Dispatchers.Unconfined)
    }

    @After fun tearDown() { db.close(); Dispatchers.resetMain() }

    /** Await a uiState whose book titles (sorted) match [expected]. */
    private fun awaitTitles(vararg expected: String): List<String> = runBlocking {
        val want = expected.sorted()
        withTimeout(3_000) { vm.uiState.map { it.books.map { b -> b.title }.sorted() }.first { it == want } }
    }

    @Test fun selectingChip_filtersToMembers_andAllResets() = runBlocking {
        val fic = collections.createCollection("Fiction").getOrThrow()
        collections.assign(key1, fic.id)
        // "All" shows both.
        assertEquals(listOf("Alpha", "Beta"), awaitTitles("Alpha", "Beta"))
        // selecting Fiction filters to its single member.
        vm.selectCollection(fic.id)
        assertEquals(listOf("Alpha"), awaitTitles("Alpha"))
        // back to "All".
        vm.selectCollection(null)
        assertEquals(listOf("Alpha", "Beta"), awaitTitles("Alpha", "Beta"))
    }

    @Test fun deletingSelectedCollection_resetsToAll() = runBlocking {
        val fic = collections.createCollection("Fiction").getOrThrow()
        collections.assign(key1, fic.id)
        vm.selectCollection(fic.id)
        awaitTitles("Alpha")
        // delete the selected collection → the VM resets the selection to "All" and shows everything.
        collections.delete(fic.id)
        withTimeout(3_000) { vm.selectedCollectionId.first { it == null } }
        assertNull(vm.selectedCollectionId.value)
        assertEquals(listOf("Alpha", "Beta"), awaitTitles("Alpha", "Beta"))
    }

    @Test fun switchingSelection_doesNotLeakPreviousMembership() = runBlocking {
        val a = collections.createCollection("A").getOrThrow()
        val b = collections.createCollection("B").getOrThrow()
        collections.assign(key1, a.id) // A = {Alpha}
        collections.assign(key2, b.id) // B = {Beta}
        vm.selectCollection(a.id)
        assertEquals("A → only Alpha", listOf("Alpha"), awaitTitles("Alpha"))
        vm.selectCollection(b.id)
        // flatMapLatest cancels A's flow → B shows only Beta, never the stale Alpha.
        assertEquals("B → only Beta (no leak from A)", listOf("Beta"), awaitTitles("Beta"))
    }

    @Test fun createCollectionAndAssign_createsTheCollection_andAddsTheBook() = runBlocking {
        vm.createCollectionAndAssign("Fiction", key1)
        val col = withTimeout(3_000) { vm.collections.first { list -> list.any { it.name == "Fiction" } } }.first { it.name == "Fiction" }
        val members = withTimeout(3_000) { collections.observeBookKeysInCollection(col.id).first { it.contains(key1) } }
        assertTrue("the new collection contains the assigned book", members.contains(key1))
    }

    @Test fun createCollectionAndAssign_duplicateName_doesNotCreateASecond() = runBlocking {
        collections.createCollection("Fiction").getOrThrow()
        vm.createCollectionAndAssign("FICTION", key1) // case-folded duplicate → rejected (event)
        val count = withTimeout(3_000) { vm.collections.first { it.isNotEmpty() } }.count { it.name.equals("fiction", ignoreCase = true) }
        assertEquals("the duplicate did not create a second collection", 1, count)
    }
}
