package com.vreader.app.reader

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
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
 * TXT reader render (feature #111 WI-2) — instrumented Compose UI test. Imports the
 * bundled sample.txt through the real WI-4 pipeline, launches TxtReaderActivity, and
 * asserts the decoded text renders in the LazyColumn body.
 */
@RunWith(AndroidJUnit4::class)
class TxtReaderActivityTest {
    @get:Rule val compose = createEmptyComposeRule()

    @Test
    fun opensStoredTxt_rendersDecodedText() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val appContext = instrumentation.targetContext
        val app = appContext.applicationContext as VReaderApp

        val staged = File(appContext.cacheDir, "sample-${System.nanoTime()}.txt")
        instrumentation.context.assets.open("sample.txt").use { input ->
            staged.outputStream().use { output -> input.copyTo(output) }
        }
        val book = runBlocking {
            app.container.importer.importStream("content://test/sample.txt", "sample.txt", staged.inputStream())
        }

        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(appContext, book.fingerprintKey),
        ).use {
            compose.waitUntil(5_000) {
                compose.onAllNodesWithText("quick brown fox", substring = true)
                    .fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithText("quick brown fox", substring = true).assertIsDisplayed()
        }
    }
}
