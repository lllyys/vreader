package com.vreader.app.reader

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * Instrumented EPUB-open test (feature #106 WI-5) — runs on the emulator because
 * the Readium open path needs the real Android runtime (not Robolectric). Copies
 * the bundled minimal EPUB fixture into app-private storage, opens it, and asserts
 * the parsed metadata. This is the Gate-5 Android lane (`connectedDebugAndroidTest`
 * via scripts/run-android-verify.sh).
 *
 * Real-books-first exception: a hand-authored 1.5KB EPUB is the deterministic
 * tiny-structure fixture (exact title + single-spine) a 13–18MB real book can't
 * give cheaply, and it must ship as a committed test asset (no gitignored
 * test-books/ on an instrumented run).
 */
@RunWith(AndroidJUnit4::class)
class BookOpenerTest {
    @Test
    fun open_minimalEpub_readsMetadata() = runBlocking {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val appContext = instrumentation.targetContext
        val testContext = instrumentation.context

        // Stage the fixture (in the TEST apk's assets) into the APP's storage.
        val epub = File(appContext.cacheDir, "wi5-minimal.epub")
        testContext.assets.open("minimal.epub").use { input ->
            epub.outputStream().use { output -> input.copyTo(output) }
        }

        val metadata = BookOpener(appContext).readMetadata(epub)

        assertEquals("Minimal Test Book", metadata.title)
        assertTrue("at least one spine item", metadata.readingOrderCount >= 1)
    }

    @Test
    fun open_missingFile_throwsTyped() = runBlocking {
        val appContext = InstrumentationRegistry.getInstrumentation().targetContext
        val missing = File(appContext.cacheDir, "does-not-exist-${System.nanoTime()}.epub")
        var threw = false
        try {
            BookOpener(appContext).readMetadata(missing)
        } catch (e: BookOpenException) {
            threw = true
        }
        assertTrue("a missing file surfaces a typed BookOpenException", threw)
    }
}

