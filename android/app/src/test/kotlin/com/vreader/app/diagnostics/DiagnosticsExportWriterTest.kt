// Purpose: feature #164 WI-7 — the export writer's contract, on the JVM against a real temp
// filesystem (no Android APIs are involved in writing a file, so this needs no emulator).
//
// The tests are written so that the obvious wrong implementations FAIL:
// - "atomic rename" proven by writing ONCE proves nothing, so the assertions are `no *.part
//   survives` AND `a second same-day write leaves exactly one file`;
// - "the filename is derived, never caller-supplied" is asserted structurally (the suspend
//   `write` has exactly ONE value parameter) as well as behaviourally (the name tracks the
//   injected clock), because a name parameter that a caller could aim elsewhere is precisely the
//   traversal input the design removes;
// - the redaction claim is asserted against the BYTES ON DISK through store -> writer, not against
//   `exportText`'s return value, so a writer that bypassed the store's redaction would be caught.
package com.vreader.app.diagnostics

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.nio.charset.StandardCharsets
import java.time.Instant
import java.time.ZoneId

class DiagnosticsExportWriterTest {

    @get:Rule val tmp = TemporaryFolder()

    private val utc = ZoneId.of("UTC")

    /** The diagnostics dir deliberately does NOT exist up front — the writer must create it. */
    private fun exportDir(): File = File(tmp.root, DiagnosticsExportWriter.DIRECTORY_NAME)

    private fun writerAt(iso: String, dir: File = exportDir(), zone: ZoneId = utc) =
        DiagnosticsExportWriter(
            dir = dir,
            clock = { Instant.parse(iso).toEpochMilli() },
            // Unconfined: the write must happen inline so the assertions see a settled filesystem.
            ioDispatcher = Dispatchers.Unconfined,
            zone = { zone },
        )

    // ------------------------------------------------------------------ directory + promotion

    @Test fun write_createsTheDiagnosticsDirectory_whenMissing() = runBlocking {
        val dir = exportDir()
        assertFalse("precondition: the dir must not pre-exist", dir.exists())

        val file = writerAt("2026-08-05T10:15:30Z").write("hello")

        assertTrue("the writer creates filesDir/diagnostics", dir.isDirectory)
        assertTrue("the promoted export exists", file.isFile)
    }

    @Test fun write_leavesNoPartFileBehind() = runBlocking {
        val dir = exportDir()
        writerAt("2026-08-05T10:15:30Z", dir).write("hello")

        val names = dir.list()!!.toList()
        assertEquals("exactly one file survives a write: $names", 1, names.size)
        assertTrue(
            "no temp artifact survives the atomic promote: $names",
            names.none { it.endsWith(".part") },
        )
    }

    @Test fun write_derivesTheFileNameFromTheInjectedClock() = runBlocking {
        val first = writerAt("2026-08-05T10:15:30Z").write("a")
        assertEquals("vreader-log-2026-08-05.txt", first.name)

        val second = writerAt("2027-01-31T23:59:59Z").write("b")
        assertEquals("vreader-log-2027-01-31.txt", second.name)
    }

    @Test fun write_resolvesToACanonicalChildOfTheDiagnosticsDirectory() = runBlocking {
        val dir = exportDir()
        val file = writerAt("2026-08-05T10:15:30Z", dir).write("hello")

        assertEquals(
            "the promoted file's canonical parent IS the diagnostics dir",
            dir.canonicalFile,
            file.canonicalFile.parentFile,
        )
        assertTrue(
            "the canonical path is inside the diagnostics dir",
            file.canonicalPath.startsWith(dir.canonicalPath + File.separator),
        )
    }

    /**
     * The structural half of "the filename is DERIVED, never caller-supplied". Behaviour alone
     * cannot express this: an implementation that grew a `fileName` parameter and honoured it would
     * still pass every test above (they never pass one). A suspend function compiles to
     * `write(String, Continuation)`, so a second value parameter shows up here as a third argument.
     */
    @Test fun write_takesNoCallerSuppliedFileName() {
        val writes = DiagnosticsExportWriter::class.java.declaredMethods.filter { it.name == "write" }
        assertEquals("exactly one `write` entry point: ${writes.map { it.toString() }}", 1, writes.size)

        val params = writes.single().parameterTypes
        assertEquals(
            "write(text, continuation) — a caller-supplied filename would add a parameter: " +
                params.map { it.simpleName },
            2,
            params.size,
        )
        assertEquals(String::class.java, params[0])
        assertEquals(kotlin.coroutines.Continuation::class.java, params[1])
    }

    // ------------------------------------------------------------------ content fidelity

    @Test fun write_contentIsByteIdenticalUtf8() = runBlocking {
        val text = "vreader diagnostics — 2 entries\nline two"
        val file = writerAt("2026-08-05T10:15:30Z").write(text)

        assertArrayEquals(
            "the bytes on disk are the UTF-8 encoding of the payload, unchanged",
            text.toByteArray(StandardCharsets.UTF_8),
            file.readBytes(),
        )
        assertEquals(text, file.readText(StandardCharsets.UTF_8))
    }

    @Test fun write_cjkAndEmojiRoundTrip() = runBlocking {
        val text = "书名：红楼梦 — 章节 3\n日本語のログ\n한국어\n📖 emoji tail"
        val file = writerAt("2026-08-05T10:15:30Z").write(text)

        assertEquals("CJK + astral-plane text round-trips through UTF-8", text, file.readText(StandardCharsets.UTF_8))
        assertArrayEquals(text.toByteArray(StandardCharsets.UTF_8), file.readBytes())
    }

    @Test fun write_emptyPayloadProducesAnEmptyFile() = runBlocking {
        val file = writerAt("2026-08-05T10:15:30Z").write("")

        assertTrue("an empty export is still a real file", file.isFile)
        assertEquals(0L, file.length())
    }

    // ------------------------------------------------------------------ pruning / overwrite

    @Test fun write_twiceOnTheSameDay_overwritesRatherThanAccumulating() = runBlocking {
        val dir = exportDir()
        writerAt("2026-08-05T01:00:00Z", dir).write("first payload")
        val second = writerAt("2026-08-05T23:00:00Z", dir).write("second payload")

        assertEquals(
            "the same-day write replaces, never accumulates: ${dir.list()!!.toList()}",
            1,
            dir.list()!!.size,
        )
        assertEquals("second payload", second.readText(StandardCharsets.UTF_8))
    }

    @Test fun write_prunesPriorExportsAndStaleTempFiles() = runBlocking {
        val dir = exportDir()
        dir.mkdirs()
        // A prior day's export, a crashed run's temp artifact, and an unrelated stray.
        File(dir, "vreader-log-2020-01-01.txt").writeText("older export")
        File(dir, "export-123.part").writeText("crashed mid-write")
        File(dir, "stray.txt").writeText("stray")

        val file = writerAt("2026-08-05T10:15:30Z", dir).write("current")

        val names = dir.list()!!.toList()
        assertEquals("filesDir/diagnostics holds AT MOST ONE export: $names", 1, names.size)
        assertEquals(listOf(file.name), names)
        assertEquals("current", file.readText(StandardCharsets.UTF_8))
    }

    @Test fun write_acrossDays_stillLeavesExactlyOneExport() = runBlocking {
        val dir = exportDir()
        val day1 = writerAt("2026-08-05T10:00:00Z", dir).write("day one")
        assertTrue(day1.exists())

        val day2 = writerAt("2026-08-06T10:00:00Z", dir).write("day two")

        assertFalse("yesterday's export is pruned", day1.exists())
        assertEquals(listOf(day2.name), dir.list()!!.toList())
    }

    @Test fun write_isIdempotentAgainstAPreexistingFileOfTheSameName() = runBlocking {
        val dir = exportDir()
        dir.mkdirs()
        val collide = File(dir, "vreader-log-2026-08-05.txt")
        collide.writeText("stale content that must be replaced")

        val file = writerAt("2026-08-05T10:15:30Z", dir).write("fresh")

        assertEquals(collide.canonicalPath, file.canonicalPath)
        assertEquals("fresh", file.readText(StandardCharsets.UTF_8))
        assertEquals(1, dir.list()!!.size)
    }

    /**
     * The assertion that actually distinguishes temp-then-rename from writing straight into the
     * live name. "No `.part` survives" does NOT: an implementation that never made one passes it
     * too. The promote is a DIRECTORY operation (rename), so it replaces a previous export whatever
     * that file's own mode is; a direct `writeBytes` into the live name opens the file for writing
     * and fails. Same end state on the happy path, different behaviour here — which is the whole
     * reason the export is promoted rather than written in place.
     */
    @Test fun write_replacesAPreviousExportWhoseFileModeIsNotWritable() = runBlocking {
        val dir = exportDir()
        dir.mkdirs()
        val previous = File(dir, "vreader-log-2026-08-05.txt")
        previous.writeText("yesterday's export, left read-only")
        assertTrue("precondition: the mode change must take", previous.setWritable(false, false))
        assertFalse("precondition: the previous export is not writable", previous.canWrite())

        val file = writerAt("2026-08-05T10:15:30Z", dir).write("fresh payload")

        assertEquals("fresh payload", file.readText(StandardCharsets.UTF_8))
        assertEquals(1, dir.list()!!.size)
    }

    // ------------------------------------------------------------------ timezone

    @Test fun write_fileNameUsesTheInjectedZone() = runBlocking {
        // 22:30 UTC on the 5th is already the 6th in Tokyo (+09:00) — the zone must decide.
        val tokyo = writerAt("2026-08-05T22:30:00Z", exportDir(), ZoneId.of("Asia/Tokyo")).write("x")
        assertEquals("vreader-log-2026-08-06.txt", tokyo.name)
    }

    /**
     * The writer derives the on-disk name; [DiagnosticsViewModel.exportFileName] derives the label
     * the share flow shows for the same instant. They are separate code paths (the ViewModel is not
     * in this WI's write-set), so this differential oracle pins them together instead of trusting
     * that two hand-written formatters agree.
     */
    @Test fun write_fileNameAgreesWithTheViewModelsExportFileName() = runBlocking {
        val instants = listOf(
            "2026-08-05T10:15:30Z",
            "2026-01-01T00:00:00Z",
            "2026-12-31T23:59:59Z",
            "2027-02-28T12:00:00Z",
        )
        val viewModel = DiagnosticsViewModel(
            store = DiagnosticsLogStore(EmptySource),
            clock = { 0L },
            zone = { utc },
        )
        for (iso in instants) {
            val millis = Instant.parse(iso).toEpochMilli()
            val written = writerAt(iso).write("payload")
            assertEquals(
                "writer and viewer must name the same export identically at $iso",
                viewModel.exportFileName(millis),
                written.name,
            )
        }
    }

    // ------------------------------------------------------------------ end-to-end redaction

    /**
     * The leak assertion that matters: store -> writer -> BYTES ON DISK. Asserting on
     * `exportText`'s return value would pass even for a writer that re-derived its payload from the
     * raw entries and bypassed redaction entirely.
     */
    @Test fun write_exportedBytesCarryThePlaceholderAndNotTheSecret() = runBlocking {
        val secret = "sup3r-s3cret-value-9d2f"
        val store = DiagnosticsLogStore(
            SeededSource(
                entry("WebDAV auth failed password=$secret"),
                entry("plain breadcrumb, nothing sensitive"),
            ),
        )
        val entries = store.load()
        assertEquals(2, entries.size)

        val file = writerAt("2026-08-05T10:15:30Z").write(store.exportText(entries, generatedAt = 0L))
        val onDisk = file.readText(StandardCharsets.UTF_8)

        assertFalse("the seeded secret must NOT reach disk", onDisk.contains(secret))
        assertTrue(
            "the redaction placeholder must be present in the written bytes",
            onDisk.contains(DiagnosticsRedactor.PLACEHOLDER),
        )
        assertTrue("the non-sensitive breadcrumb survives", onDisk.contains("plain breadcrumb"))
    }

    // ------------------------------------------------------------------ helpers

    private fun entry(message: String) = DiagnosticsLogEntry(
        timeMillis = 1_700_000_000_000L,
        level = DiagnosticsLevel.WARN,
        category = "Sync",
        message = message,
    )

    private object EmptySource : DiagnosticsLogSource {
        override suspend fun recentEntries(sinceMillis: Long?, limit: Int) =
            SourceResult.Available(emptyList())
    }

    private class SeededSource(private vararg val entries: DiagnosticsLogEntry) : DiagnosticsLogSource {
        override suspend fun recentEntries(sinceMillis: Long?, limit: Int) =
            SourceResult.Available(entries.toList())
    }
}
