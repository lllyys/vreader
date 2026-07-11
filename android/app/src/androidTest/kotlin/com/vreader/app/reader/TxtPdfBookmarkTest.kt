package com.vreader.app.reader

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.VReaderApp
import kotlinx.coroutines.runBlocking
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * Feature #135 WI-7 — the TXT/MD host bookmark wiring lit up: the top-bar bookmark TOGGLE now RENDERS (WI-5's
 * [chrome-bookmark-toggle] filling the top-bar slot), where before WI-7 the host passed null and the slot
 * stayed absent. A RENDER assertion (not a gesture — render/click chrome tests are not emulator-flaky; only
 * long-press/selection is), so it rides the connected gate cheaply. The toggle/list-tap/scroll-to-offset
 * behaviors are covered by the JVM host-helper suite + ride WI-9 acceptance.
 */
@RunWith(AndroidJUnit4::class)
class TxtPdfBookmarkTest {
    @get:Rule val compose = createEmptyComposeRule()

    @Test
    fun txtHost_rendersTopBarBookmarkToggle() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val appContext = instrumentation.targetContext
        val app = appContext.applicationContext as VReaderApp

        val staged = File(appContext.cacheDir, "bookmark-txt-${System.nanoTime()}.txt")
        instrumentation.context.assets.open("sample.txt").use { input ->
            staged.outputStream().use { output -> input.copyTo(output) }
        }
        val book = runBlocking {
            app.container.importer.importStream("content://test/sample.txt", "sample.txt", staged.inputStream())
        }

        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(appContext, book.fingerprintKey),
        ).use {
            // The bookmark toggle appears once the reader chrome renders (WI-7 wired the non-null toggle).
            compose.waitUntil(5_000) {
                compose.onAllNodesWithTag("chrome-bookmark-toggle").fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithTag("chrome-bookmark-toggle").assertIsDisplayed()
        }
    }
}
