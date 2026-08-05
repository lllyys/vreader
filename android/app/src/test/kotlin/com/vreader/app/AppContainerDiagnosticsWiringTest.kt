// Purpose: feature #164 WI-7 — proves the diagnostics capture floor is actually WIRED into the
// running application, and does it in a way that FAILS when the wiring is removed.
//
// "Verified by finding the call site" is not a gate: nothing fails when the call disappears, so a
// later refactor can delete `VLog.install(...)` from `VReaderApp.onCreate()` and every test in the
// repo stays green while the shipped app captures nothing. This test therefore never calls
// `VLog.install` itself — it lets Robolectric build the real `VReaderApp` (the manifest's
// `android:name=".VReaderApp"`, so `onCreate` runs exactly as it does on device), emits a log
// through the production facade, and asserts the entry landed in THAT application's ring. Delete
// the install call and the assertion goes red. That is the actual regression risk.
//
// Robolectric (not the emulator) because everything needed here is a Context + the app object; the
// AppContainerBilingualWiringTest precedent.
package com.vreader.app

import androidx.test.core.app.ApplicationProvider
import com.vreader.app.diagnostics.DiagnosticsCategory
import com.vreader.app.diagnostics.DiagnosticsExportWriter
import com.vreader.app.diagnostics.DiagnosticsLevel
import com.vreader.app.diagnostics.DiagnosticsLogStore
import com.vreader.app.diagnostics.SourceResult
import com.vreader.app.diagnostics.VLog
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.File
import java.util.UUID

@RunWith(RobolectricTestRunner::class)
class AppContainerDiagnosticsWiringTest {

    private val app: VReaderApp get() = ApplicationProvider.getApplicationContext()

    /**
     * THE falsifiable wiring assertion. No `VLog.install` here on purpose: the only thing that can
     * have installed a sink is [VReaderApp.onCreate], so a hit in the container's ring proves the
     * production call ran. A unique nonce per run keeps the assertion from passing on a stale entry.
     */
    @Test fun vlogEmission_landsInTheContainersRing_withoutTheTestInstallingASink() {
        val nonce = "wiring-probe-${UUID.randomUUID()}"

        VLog.w(DiagnosticsCategory.LIBRARY, "AppContainerDiagnosticsWiringTest", nonce)

        val captured = runBlocking { app.container.diagnosticsRing.recentEntries(limit = 500) }
        val entries = (captured as SourceResult.Available).entries
        val hit = entries.singleOrNull { it.message.contains(nonce) }

        assertNotNull(
            "VReaderApp.onCreate must install the ring as VLog's sink — a VLog.w() call has to " +
                "reach container.diagnosticsRing without this test installing anything. " +
                "Captured ${entries.size} entries.",
            hit,
        )
        assertEquals(DiagnosticsLevel.WARN, hit!!.level)
        assertEquals(DiagnosticsCategory.LIBRARY.tag, hit.category)
        assertTrue(
            "the origin is preserved as a message prefix",
            hit.message.startsWith("[AppContainerDiagnosticsWiringTest] "),
        )
    }

    /** The whole export path is reachable from the container, as lazily-built process singletons. */
    @Test fun container_resolvesTheDiagnosticsGraphAsSingletons() {
        val container = app.container

        assertNotNull(container.diagnosticsRing)
        assertNotNull(container.diagnosticsStore)
        assertNotNull(container.diagnosticsExportWriter)

        assertSame(container.diagnosticsRing, container.diagnosticsRing)
        assertSame(container.diagnosticsStore, container.diagnosticsStore)
        assertSame(container.diagnosticsExportWriter, container.diagnosticsExportWriter)

        val store: DiagnosticsLogStore = container.diagnosticsStore
        val writer: DiagnosticsExportWriter = container.diagnosticsExportWriter
        assertNotNull(store); assertNotNull(writer)

        // The viewer's VM is per-screen, never a singleton (the container's house convention).
        assertNotSame(container.diagnosticsViewModel(), container.diagnosticsViewModel())
    }

    /**
     * Pins the writer's directory to `filesDir/diagnostics`. That path is the SAME string the
     * FileProvider's `@xml/diagnostics_paths` grants; if the writer ever wrote elsewhere, the share
     * flow would silently start returning null on device.
     */
    @Test fun exportWriter_writesUnderFilesDirDiagnostics() {
        val written = runBlocking { app.container.diagnosticsExportWriter.write("probe payload") }

        val expected = File(app.filesDir, DiagnosticsExportWriter.DIRECTORY_NAME).canonicalFile
        assertEquals(
            "the export must land in the directory @xml/diagnostics_paths grants",
            expected,
            written.canonicalFile.parentFile,
        )
        assertEquals("probe payload", written.readText())
    }

    /** The store the container hands the viewer reads through the wired sources, not a fresh one. */
    @Test fun diagnosticsStore_readsTheContainersRing() {
        val nonce = "store-probe-${UUID.randomUUID()}"
        app.container.diagnosticsRing.record(
            level = DiagnosticsLevel.INFO,
            category = DiagnosticsCategory.LIBRARY.tag,
            message = nonce,
            at = System.currentTimeMillis(),
        )

        val entries = runBlocking { app.container.diagnosticsStore.load() }

        assertTrue(
            "an entry recorded on the container's ring must be visible through the container's store",
            entries.any { it.message.contains(nonce) },
        )
    }
}
