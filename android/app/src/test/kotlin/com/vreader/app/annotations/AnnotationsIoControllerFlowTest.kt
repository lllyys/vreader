package com.vreader.app.annotations

import com.vreader.app.imports.IncomingBookResolver
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import vreader.contracts.backup.BackupJson
import java.io.ByteArrayInputStream
import java.util.concurrent.atomic.AtomicReference

/**
 * Feature #165 WI-4b — the non-parked half of [AnnotationsIoController]: the five ordered steps
 * of §8.1 as ordinary behaviour (admission, bounded query, size preflight, bounded open, bounded
 * transfer), plus §8.4's name sanitization at the boundary.
 *
 * The park cases live in `AnnotationsIoControllerTest` (A-12); these are the cases that say what
 * the boundary does when the provider is merely *wrong* rather than hostile-and-parked.
 */
@RunWith(RobolectricTestRunner::class)
class AnnotationsIoControllerFlowTest {

    private val rig = ControllerRig()

    @After
    fun tearDown() = rig.close()

    // ---- step 2: the size preflight, which exists to avoid opening at all -----------------------

    @Test
    fun aDeclaredSizeOverTheCapRefusesWithoutEverOpening() = runBlocking {
        rig.port.meta = SafMetadata("huge.json", AnnotationsImportReader.MAX_IMPORT_JSON_BYTES + 1)

        assertEquals(ImportParseResult.Failed(ImportFailure.TooLarge), preview())

        assertEquals("the whole point of a preflight is that no fd is ever opened", 0, rig.port.openInputCallCount)
    }

    @Test
    fun aDeclaredSizeExactlyAtTheCapStillOpens() = runBlocking {
        rig.port.meta = SafMetadata("edge.json", AnnotationsImportReader.MAX_IMPORT_JSON_BYTES)
        rig.port.inputFactory = { TrackingInputStream(envelopeJson().toByteArray()) }

        assertTrue(preview() is ImportParseResult.Ok)
        assertEquals(1, rig.port.openInputCallCount)
    }

    @Test
    fun aLyingDeclaredSizeIsCaughtByTheMeasuredRead() = runBlocking {
        // The provider claims 10 bytes and delivers well past the cap. The failure must be the
        // reader's TYPED TooLarge — if the post-open guard fired first the reader's blanket catch
        // would relabel it `Unreadable`, and the user would be told the wrong thing.
        val oversize = ByteArray((AnnotationsImportReader.MAX_IMPORT_JSON_BYTES + 4_096L).toInt()) { '.'.code.toByte() }
        rig.port.meta = SafMetadata("liar.json", 10L)
        rig.port.inputFactory = { ByteArrayInputStream(oversize) }

        assertEquals(ImportParseResult.Failed(ImportFailure.TooLarge), preview())
    }

    // ---- §8.4: the provider's display name is attacker-controlled text --------------------------

    @Test
    fun aHostileDisplayNameIsSanitizedBeforeItCanReachThePreview() = runBlocking {
        val bidi = String(Character.toChars(0x202E)) + String(Character.toChars(0x202D))
        val nul = String(Character.toChars(0))
        val hostile = "../../etc/" + bidi + nul + "x".repeat(50_000) + ".json"
        rig.port.meta = SafMetadata(hostile, null)
        rig.port.inputFactory = { TrackingInputStream(envelopeJson().toByteArray()) }

        val name = (preview() as ImportParseResult.Ok).preview.fileName

        assertFalse("no path separator survives", name.contains('/'))
        assertFalse("no bidi override survives", name.contains(String(Character.toChars(0x202E))))
        assertFalse("no control character survives", name.any { it.code in 0..0x1F })
        assertTrue("bounded", name.length <= IncomingBookResolver.MAX_NAME_CHARS)
    }

    /**
     * The assertion above is an END-TO-END property, and it holds even if this boundary stops
     * sanitizing — `AnnotationsImportReader` sanitizes again downstream (measured: deleting the
     * controller's call reddened nothing). This one pins THIS boundary's own §8.4 guarantee, by
     * observing the string it hands the reader: `ImportPreview` must never be constructible from
     * the raw provider name, whoever builds it.
     */
    @Test
    fun theFileNameHandedToTheReaderIsAlreadySanitized() = runBlocking {
        val seen = AtomicReference<String>()
        rig.parser = AnnotationsParser { _, fileName, _, _, _ ->
            seen.set(fileName)
            ImportParseResult.Failed(ImportFailure.Empty)
        }
        rig.port.meta = SafMetadata("../../etc/passwd" + String(Character.toChars(0x202E)), null)
        rig.port.inputFactory = { TrackingInputStream(envelopeJson().toByteArray()) }

        preview()

        assertEquals("passwd", seen.get())
    }

    @Test
    fun aCjkDisplayNameSurvivesIntact() = runBlocking {
        rig.port.meta = SafMetadata("书签.json", null)
        rig.port.inputFactory = { TrackingInputStream(envelopeJson().toByteArray()) }

        assertEquals("书签.json", (preview() as ImportParseResult.Ok).preview.fileName)
    }

    @Test
    fun aNullDisplayNameFallsBackRatherThanFailing() = runBlocking {
        rig.port.meta = SafMetadata(null, null)
        rig.port.inputFactory = { TrackingInputStream(envelopeJson().toByteArray()) }

        assertEquals(
            IncomingBookResolver.FALLBACK_NAME,
            (preview() as ImportParseResult.Ok).preview.fileName,
        )
    }

    // ---- provider misbehaviour that is not a park ----------------------------------------------

    @Test
    fun aProviderThatRefusesToOpenIsUnreadable() = runBlocking {
        rig.port.inputFactory = { null }

        assertEquals(ImportParseResult.Failed(ImportFailure.Unreadable), preview())
    }

    @Test
    fun aProviderThatThrowsOnQueryIsUnreadable() = runBlocking {
        rig.port.failWith = IllegalStateException("hostile provider")

        assertEquals(ImportParseResult.Failed(ImportFailure.Unreadable), preview())
    }

    @Test
    fun aProviderThatRefusesTheExportDestinationIsUnreadable() = runBlocking {
        rig.port.outputFactory = { null }

        val error = export().exceptionOrNull()
        assertTrue(error is AnnotationImportFailedException)
        assertEquals(ImportFailure.Unreadable, (error as AnnotationImportFailedException).reason)
    }

    // ---- export: the bytes, and the close-once discipline ---------------------------------------

    @Test
    fun exportWritesTheContractBytesAndClosesTheSinkExactlyOnce() = runBlocking {
        val sink = TrackingOutputStream()
        rig.port.outputFactory = { sink }
        seedOneHighlight()

        val written = export()

        assertEquals(1, written.getOrNull())
        assertTrue(sink.text().contains(Fx.uuid(1)))
        assertEquals("an attacker-supplied sink need not tolerate a second close", 1, sink.closeCount)
    }

    /**
     * For a SAF descriptor `close()` is where the write is COMMITTED, so a throwing close means
     * the file was not saved. Reporting success there would tell the user a file exists that does
     * not — and a quiet close (the round-1 shape) did exactly that (Gate-4 round 1, High).
     */
    @Test
    fun anExportWhoseDestinationThrowsOnCloseIsNotReportedAsSaved() = runBlocking {
        rig.port.outputFactory = { TrackingOutputStream(throwOnClose = true) }
        seedOneHighlight()

        val error = export().exceptionOrNull()

        assertTrue("expected a typed failure, got a success", error is AnnotationImportFailedException)
        assertEquals(ImportFailure.Unreadable, (error as AnnotationImportFailedException).reason)
    }

    @Test
    fun exportOfABookWithNoAnnotationsStillWritesTheValidEmptyEnvelope() = runBlocking {
        val sink = TrackingOutputStream()
        rig.port.outputFactory = { sink }

        assertEquals(0, export().getOrNull())
        assertTrue(sink.text().contains("schemaVersion"))
    }

    // ---- the whole boundary, both directions, in one pass ---------------------------------------

    @Test
    fun exportedBytesReadBackThroughPreviewAndApplyLandAsOneRow() = runBlocking {
        val sink = TrackingOutputStream()
        rig.port.outputFactory = { sink }
        seedOneHighlight()
        assertEquals(1, export().getOrNull())

        // A second book imports the same file — a fresh store would collide on the id, so use the
        // exported bytes against the SAME book after wiping the row.
        rig.store.repo.removeHighlight(Fx.uuid(1))
        rig.port.inputFactory = { ByteArrayInputStream(sink.text().toByteArray()) }

        val parsed = preview()
        val previewed = (parsed as ImportParseResult.Ok).preview
        assertEquals(1, previewed.importable)

        val report = rig.controller.apply(previewed).getOrNull()
        assertNotNull(report)
        assertEquals("the number the user approves is the number they get", 1, report!!.appliedTotal)
    }

    // ---- helpers --------------------------------------------------------------------------------

    private suspend fun preview(): ImportParseResult = withContext(Dispatchers.Default) {
        rig.controller.preview(rig.uri, Fx.BOOK_A, "A Book")
    }

    private suspend fun export(): Result<Int> = withContext(Dispatchers.Default) {
        rig.controller.export(rig.uri, Fx.BOOK_A)
    }

    private suspend fun seedOneHighlight() {
        rig.store.seedBook()
        rig.store.repo.restoreAnnotations(
            ApplierHarness.env(highlights = listOf(Fx.highlight(Fx.uuid(1)))),
            setOf(Fx.BOOK_A),
        )
    }

    /** A minimal well-formed, empty annotations envelope, at the version the contract ships. */
    private fun envelopeJson(): String = BackupJson.encode(ApplierHarness.env())
}
