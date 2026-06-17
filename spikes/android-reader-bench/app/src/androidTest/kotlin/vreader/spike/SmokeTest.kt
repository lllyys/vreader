package vreader.spike

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Spike B WI-1: proves an Android instrumentation test RUNS on the
 * emulator (the ADR-flagged-UNVERIFIED "can the cron drive an Android
 * device" question). The full CJK reader benchmark builds on this lane.
 */
@RunWith(AndroidJUnit4::class)
class SmokeTest {
    @Test
    fun runsOnDevice() {
        val ctx = InstrumentationRegistry.getInstrumentation().targetContext
        assertEquals("vreader.spike", ctx.packageName)
        assertTrue("minSdk respected on device", android.os.Build.VERSION.SDK_INT >= 26)
    }
}
