package com.vreader.app.stats

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.vreader.app.data.LibraryRepository
import com.vreader.app.data.VReaderDatabase
import com.vreader.app.stats.clock.DateClock
import com.vreader.app.stats.clock.DateSegment
import com.vreader.app.stats.clock.ElapsedClock
import com.vreader.app.stats.clock.SystemDateClock
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.time.Clock
import java.time.ZoneId

/** Feature #122 WI-2 — StatsViewModel.inReaderStats math (the VM's unique logic; the dashboard flow is
 *  covered by ReadingStatsRepositoryTest). */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
class StatsViewModelTest {
    private val dispatcher = StandardTestDispatcher()
    private class FixedDate(private val today: String) : DateClock {
        private val d = SystemDateClock(Clock.systemUTC(), ZoneId.of("UTC"))
        override fun today() = today
        override fun nowEpochMillis() = 0L
        override fun localDate(epochMillis: Long) = d.localDate(epochMillis)
        override fun splitByLocalDate(s: Long, e: Long): List<DateSegment> = d.splitByLocalDate(s, e)
    }
    private lateinit var db: VReaderDatabase
    private lateinit var repo: ReadingStatsRepository
    private lateinit var vm: StatsViewModel

    @Before fun setUp() {
        Dispatchers.setMain(dispatcher)
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext(), VReaderDatabase::class.java)
            .allowMainThreadQueries().build()
        repo = ReadingStatsRepository(db.readingStatsDao(), LibraryRepository(db.bookDao(), db.readingPositionDao()), FixedDate("2026-06-27"))
        val tracker = ReadingTimeTracker(repo, ElapsedClock { 0 }, FixedDate("2026-06-27"))
        vm = StatsViewModel(repo, tracker)
    }
    @After fun tearDown() { Dispatchers.resetMain(); db.close() }

    @Test fun inReaderStats_computesLeftTotalAndPace() = runTest(dispatcher) {
        repo.recordMinutes("b1", "2026-06-27", 30)
        // 46000 words / 230 wpm = 200 min total; at 50% read → 100 min left
        val s = vm.inReaderStats("b1", fraction = 0.5f, wordCount = 46_000)
        assertEquals(30, s.bookTotalMinutes)
        assertEquals(100, s.timeLeftMinutes)
        assertEquals(230, s.pace)
    }

    @Test fun inReaderStats_zeroWordCount_noPaceNoLeft() = runTest(dispatcher) {
        val s = vm.inReaderStats("b1", fraction = 0.0f, wordCount = 0)
        assertEquals(0, s.timeLeftMinutes)
        assertNull(s.pace)
    }

    @Test fun selectWindow_doesNotCrash() = runTest(dispatcher) {
        vm.selectWindow(StatsWindow.year)   // window-scoped totals are covered by ReadingStatsRepositoryTest
    }
}
