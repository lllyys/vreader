package com.vreader.app.data

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** Feature #122 WI-1 — ReadingStatsDao portable increment + read primitives (in-memory Room). */
@RunWith(RobolectricTestRunner::class)
class ReadingStatsDaoTest {
    private lateinit var db: VReaderDatabase
    private lateinit var dao: ReadingStatsDao

    @Before fun setUp() {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext(), VReaderDatabase::class.java)
            .allowMainThreadQueries().build()
        dao = db.readingStatsDao()
    }

    @After fun tearDown() = db.close()

    @Test fun addMinutes_insertsThenIncrements() = runBlocking {
        dao.addMinutes("2026-06-27", "b1", 5)
        dao.addMinutes("2026-06-27", "b1", 3)   // UPSERT-free increment
        assertEquals(8, dao.rowsSince("2026-06-27").single { it.bookKey == "b1" }.minutes)
    }

    @Test fun addMinutes_zeroDeltaIsNoOp() = runBlocking {
        dao.addMinutes("2026-06-27", "b1", 0)
        assertTrue(dao.allRows().isEmpty())
    }

    @Test fun rowsSince_filtersByDate() = runBlocking {
        dao.addMinutes("2026-06-25", "b1", 10)
        dao.addMinutes("2026-06-27", "b1", 4)
        assertEquals(listOf(4), dao.rowsSince("2026-06-26").map { it.minutes })
    }

    @Test fun perDateAndPerBookAreDistinctRows() = runBlocking {
        dao.addMinutes("2026-06-27", "b1", 5)
        dao.addMinutes("2026-06-27", "b2", 7)
        dao.addMinutes("2026-06-28", "b1", 2)
        assertEquals(3, dao.allRows().size)
    }

    @Test fun activeDatesSince_distinctDescending() = runBlocking {
        dao.addMinutes("2026-06-25", "b1", 1)
        dao.addMinutes("2026-06-27", "b1", 1)
        dao.addMinutes("2026-06-27", "b2", 1)   // same date, different book → one distinct date
        assertEquals(listOf("2026-06-27", "2026-06-25"), dao.activeDatesSince("2026-06-01"))
    }
}
