// Purpose: feature #164 WI-7 — the export writer's contract, on the JVM against a real temp
// filesystem (nothing here needs an Android API, so it needs no emulator).
//
// The tests are written so that the obvious wrong implementations FAIL:
// - "atomic rename" proven by writing ONCE proves nothing, so the assertions are `no *.part
//   survives`, `a second same-day write leaves exactly one file`, AND the read-only-previous-export
//   case, which is the only end-state property that a direct write cannot satisfy;
// - "the filename is derived, never caller-supplied" is asserted structurally (the suspend `write`
//   takes exactly ONE value parameter, and it is the entry list) as well as behaviourally, because
//   a name parameter a caller could aim elsewhere is precisely the traversal input the design
//   removes;
// - the redaction claim is asserted against the BYTES ON DISK, driven through the SAME
//   `renderPayload` seam production wires (`DiagnosticsLogStore::exportText`) rather than by the
//   test pre-rendering the payload itself — otherwise the test proves one correct call sequence
//   instead of proving the writer cannot be handed raw text at all.
package com.vreader.app.diagnostics

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.File
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.time.Instant
import java.time.ZoneId
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.max

// Robolectric only for `android.util.Log`: the writer reports an un-prunable directory entry
// through VLog, which forwards to the platform log, and a plain JVM test throws
// "Method w in android.util.Log not mocked". Everything else here is real filesystem I/O.
@RunWith(RobolectricTestRunner::class)
class DiagnosticsExportWriterTest {

    @get:Rule val tmp = TemporaryFolder()

    private val utc = ZoneId.of("UTC")

    /** The diagnostics dir deliberately does NOT exist up front — the writer must create it. */
    private fun exportDir(): File = File(tmp.root, DiagnosticsExportWriter.DIRECTORY_NAME)

    /**
     * A writer whose payload is the entries' messages joined by newlines — enough structure to
     * assert bytes on, without pulling the store's full export format into every assertion. The
     * store-backed renderer (what production wires) is exercised by the redaction tests below.
     */
    private fun writerAt(iso: String, dir: File = exportDir(), zone: ZoneId = utc) =
        DiagnosticsExportWriter(
            dir = dir,
            renderPayload = { entries, _ -> entries.joinToString("\n") { it.message } },
            clock = { Instant.parse(iso).toEpochMilli() },
            // Unconfined: the write happens inline so the assertions see a settled filesystem.
            ioDispatcher = Dispatchers.Unconfined,
            zone = { zone },
        )

    private fun payload(text: String) = listOf(entry(text))

    // ------------------------------------------------------------------ directory + promotion

    @Test fun write_createsTheDiagnosticsDirectory_whenMissing() = runBlocking {
        val dir = exportDir()
        assertFalse("precondition: the dir must not pre-exist", dir.exists())

        val file = writerAt("2026-08-05T10:15:30Z", dir).write(payload("hello"))

        assertTrue("the writer creates filesDir/diagnostics", dir.isDirectory)
        assertTrue("the promoted export exists", file.isFile)
    }

    @Test fun write_leavesNoPartFileBehind() = runBlocking {
        val dir = exportDir()
        writerAt("2026-08-05T10:15:30Z", dir).write(payload("hello"))

        val names = dir.list()!!.toList()
        assertEquals("exactly one file survives a write: $names", 1, names.size)
        assertTrue(
            "no temp artifact survives the atomic promote: $names",
            names.none { it.endsWith(".part") },
        )
    }

    @Test fun write_derivesTheFileNameFromTheInjectedClock() = runBlocking {
        val first = writerAt("2026-08-05T10:15:30Z").write(payload("a"))
        assertEquals("vreader-log-2026-08-05.txt", first.name)

        val second = writerAt("2027-01-31T23:59:59Z").write(payload("b"))
        assertEquals("vreader-log-2027-01-31.txt", second.name)
    }

    @Test fun write_resolvesToACanonicalChildOfTheDiagnosticsDirectory() = runBlocking {
        val dir = exportDir()
        val file = writerAt("2026-08-05T10:15:30Z", dir).write(payload("hello"))

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
     * The structural half of "the payload and the filename are DERIVED, never caller-supplied".
     * Behaviour alone cannot express it: an implementation that grew a `fileName` parameter and
     * honoured it would still pass every test above (none of them pass one). A suspend function
     * compiles to `write(args…, Continuation)`, so a second value parameter shows up here as a
     * third argument — and the first parameter being `List` (not `String`) is what pins the
     * redaction seam: raw text cannot be handed in at all.
     */
    @Test fun write_takesEntriesOnly_noCallerSuppliedTextOrFileName() {
        val writes = DiagnosticsExportWriter::class.java.declaredMethods.filter { it.name == "write" }
        assertEquals("exactly one `write` entry point: ${writes.map { it.toString() }}", 1, writes.size)

        val params = writes.single().parameterTypes
        assertEquals(
            "write(entries, continuation) — a caller-supplied filename or raw text would change " +
                "this shape: " + params.map { it.simpleName },
            2,
            params.size,
        )
        assertEquals(
            "the payload arrives as ENTRIES, so it cannot bypass the redacting renderer",
            List::class.java,
            params[0],
        )
        assertEquals(kotlin.coroutines.Continuation::class.java, params[1])
    }

    // ------------------------------------------------------------------ content fidelity

    @Test fun write_contentIsByteIdenticalUtf8() = runBlocking {
        val text = "vreader diagnostics — 2 entries\nline two"
        val file = writerAt("2026-08-05T10:15:30Z").write(payload(text))

        assertArrayEquals(
            "the bytes on disk are the UTF-8 encoding of the rendered payload, unchanged",
            text.toByteArray(StandardCharsets.UTF_8),
            file.readBytes(),
        )
        assertEquals(text, file.readText(StandardCharsets.UTF_8))
    }

    @Test fun write_cjkAndEmojiRoundTrip() = runBlocking {
        val text = "书名：红楼梦 — 章节 3\n日本語のログ\n한국어\n📖 emoji tail"
        val file = writerAt("2026-08-05T10:15:30Z").write(payload(text))

        assertEquals("CJK + astral-plane text round-trips through UTF-8", text, file.readText(StandardCharsets.UTF_8))
        assertArrayEquals(text.toByteArray(StandardCharsets.UTF_8), file.readBytes())
    }

    @Test fun write_emptyEntryListProducesAnEmptyFile() = runBlocking {
        val file = writerAt("2026-08-05T10:15:30Z").write(emptyList())

        assertTrue("an empty export is still a real file", file.isFile)
        assertEquals(0L, file.length())
    }

    // ------------------------------------------------------------------ pruning / overwrite

    @Test fun write_twiceOnTheSameDay_overwritesRatherThanAccumulating() = runBlocking {
        val dir = exportDir()
        writerAt("2026-08-05T01:00:00Z", dir).write(payload("first payload"))
        val second = writerAt("2026-08-05T23:00:00Z", dir).write(payload("second payload"))

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

        val file = writerAt("2026-08-05T10:15:30Z", dir).write(payload("current"))

        val names = dir.list()!!.toList()
        assertEquals("filesDir/diagnostics holds AT MOST ONE export: $names", 1, names.size)
        assertEquals(listOf(file.name), names)
        assertEquals("current", file.readText(StandardCharsets.UTF_8))
    }

    /**
     * A symlink pointing AT the promoted export has the same canonical path as the export itself,
     * so a prune that matched canonically would keep it — leaving two entries in a directory
     * documented to hold one, and a second name through which the file can be reached.
     */
    @Test fun write_prunesASymlinkAliasOfTheExport() = runBlocking {
        val dir = exportDir()
        dir.mkdirs()
        val real = File(dir, "vreader-log-2026-08-05.txt")
        real.writeText("previous export")
        Files.createSymbolicLink(File(dir, "alias.txt").toPath(), real.toPath())
        assertEquals(2, dir.list()!!.size)

        val file = writerAt("2026-08-05T10:15:30Z", dir).write(payload("current"))

        assertEquals(
            "the alias is an entry too and must be pruned: ${dir.list()!!.toList()}",
            listOf(file.name),
            dir.list()!!.toList(),
        )
        assertEquals("current", file.readText(StandardCharsets.UTF_8))
    }

    /**
     * An EMPTY stray directory is a directory entry like any other and must go, or "at most one"
     * quietly becomes "one export plus whatever accumulated". `deleteIfExists` removes an empty
     * directory and refuses a non-empty one, which is precisely the wanted split: never recursive.
     */
    @Test fun write_prunesAnEmptyStrayDirectory_butKeepsAndReportsANonEmptyOne() = runBlocking {
        val dir = exportDir()
        dir.mkdirs()
        File(dir, "empty-stray").mkdirs()
        val occupied = File(dir, "occupied-stray").apply { mkdirs() }
        File(occupied, "child.txt").writeText("not ours to erase")

        val file = writerAt("2026-08-05T10:15:30Z", dir).write(payload("current"))

        val names = dir.list()!!.toList().sorted()
        assertEquals("the empty stray directory is pruned: $names", listOf("occupied-stray", file.name).sorted(), names)
        assertTrue("a non-empty stray is retained, never recursively erased", File(occupied, "child.txt").exists())
    }

    /** Deleting a link must never delete what it points at (NOFOLLOW_LINKS). */
    @Test fun write_pruningALinkDoesNotTouchItsTargetOutsideTheDirectory() = runBlocking {
        val dir = exportDir()
        dir.mkdirs()
        val outside = File(tmp.root, "precious.txt")
        outside.writeText("must survive")
        Files.createSymbolicLink(File(dir, "escape.txt").toPath(), outside.toPath())

        writerAt("2026-08-05T10:15:30Z", dir).write(payload("current"))

        assertTrue("the link's target outside the export dir is untouched", outside.exists())
        assertEquals("must survive", outside.readText())
    }

    @Test fun write_acrossDays_stillLeavesExactlyOneExport() = runBlocking {
        val dir = exportDir()
        val day1 = writerAt("2026-08-05T10:00:00Z", dir).write(payload("day one"))
        assertTrue(day1.exists())

        val day2 = writerAt("2026-08-06T10:00:00Z", dir).write(payload("day two"))

        assertFalse("yesterday's export is pruned", day1.exists())
        assertEquals(listOf(day2.name), dir.list()!!.toList())
    }

    @Test fun write_isIdempotentAgainstAPreexistingFileOfTheSameName() = runBlocking {
        val dir = exportDir()
        dir.mkdirs()
        val collide = File(dir, "vreader-log-2026-08-05.txt")
        collide.writeText("stale content that must be replaced")

        val file = writerAt("2026-08-05T10:15:30Z", dir).write(payload("fresh"))

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

        val file = writerAt("2026-08-05T10:15:30Z", dir).write(payload("fresh payload"))

        assertEquals("fresh payload", file.readText(StandardCharsets.UTF_8))
        assertEquals(1, dir.list()!!.size)
    }

    // ------------------------------------------------------------------ concurrency

    /**
     * Overlapping exports are SERIALISED — asserted directly, by measuring how many calls are ever
     * inside the critical section at once.
     *
     * The first version of this test simply ran eight concurrent writes and checked that nothing
     * threw and one file remained; a mutation run proved it worthless — deleting the mutex left it
     * green, because the create/write/promote window closes too fast for the prune-deletes-another
     * -call's-`.part` race to land on demand. Measuring occupancy instead does not depend on
     * winning a race: `renderPayload` runs inside the guarded section, so it can count its own
     * concurrency and hold the section open long enough that any unserialised caller must overlap.
     */
    @Test fun write_concurrentExports_areSerialised() = runBlocking {
        val dir = exportDir()
        val inside = AtomicInteger(0)
        val peak = AtomicInteger(0)
        val writer = DiagnosticsExportWriter(
            dir = dir,
            renderPayload = { entries, _ ->
                val now = inside.incrementAndGet()
                peak.updateAndGet { max(it, now) }
                // Blocking is fine here: this runs on the IO dispatcher and the point is to hold
                // the section open, not to be fast.
                Thread.sleep(20)
                inside.decrementAndGet()
                entries.joinToString("\n") { it.message }
            },
            clock = { Instant.parse("2026-08-05T10:15:30Z").toEpochMilli() },
            ioDispatcher = Dispatchers.IO,
            zone = { utc },
        )

        // Any throw from a concurrent export also fails this test.
        val results = (1..8).map { i -> async { writer.write(payload("payload $i")) } }.awaitAll()

        assertEquals(
            "never more than one export inside the critical section at a time",
            1,
            peak.get(),
        )
        assertEquals(8, results.size)
        val names = dir.list()!!.toList()
        assertEquals("the directory holds exactly one export afterwards: $names", 1, names.size)
        assertTrue("no temp artifact survives: $names", names.none { it.endsWith(".part") })
        assertEquals("vreader-log-2026-08-05.txt", names.single())
    }

    // ------------------------------------------------------------------ timezone + stamp

    @Test fun write_fileNameUsesTheInjectedZone() = runBlocking {
        // 22:30 UTC on the 5th is already the 6th in Tokyo (+09:00) — the zone must decide.
        val tokyo = writerAt("2026-08-05T22:30:00Z", exportDir(), ZoneId.of("Asia/Tokyo")).write(payload("x"))
        assertEquals("vreader-log-2026-08-06.txt", tokyo.name)
    }

    /**
     * The payload's `generated:` stamp and the filename's date come from ONE clock reading, so an
     * export written across midnight cannot name one day and claim another in its text.
     */
    @Test fun write_payloadStampAndFileNameShareOneClockReading() = runBlocking {
        val readings = mutableListOf<Long>()
        val fixed = Instant.parse("2026-08-05T10:15:30Z").toEpochMilli()
        val writer = DiagnosticsExportWriter(
            dir = exportDir(),
            renderPayload = { _, generatedAt -> "generated:$generatedAt" },
            clock = { readings += fixed; fixed },
            ioDispatcher = Dispatchers.Unconfined,
            zone = { utc },
        )

        val file = writer.write(payload("ignored"))

        assertEquals("the clock is read exactly once per export", 1, readings.size)
        assertEquals("generated:$fixed", file.readText(StandardCharsets.UTF_8))
        assertEquals("vreader-log-2026-08-05.txt", file.name)
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
            val written = writerAt(iso).write(payload("payload"))
            assertEquals(
                "writer and viewer must name the same export identically at $iso",
                viewModel.exportFileName(millis),
                written.name,
            )
        }
    }

    // ------------------------------------------------------------------ end-to-end redaction

    /**
     * The leak assertion that matters — and it is driven through the SAME seam production wires:
     * the test hands the writer ENTRIES and the store's `exportText` renders them. A test that
     * pre-rendered the payload itself would prove only that one correct call sequence is safe,
     * while `write("password=…")` stayed a legal call.
     */
    @Test fun write_throughTheStoreRenderer_redactsBeforeTheBytesReachDisk() = runBlocking {
        val secret = "sup3r-s3cret-value-9d2f"
        val store = DiagnosticsLogStore(EmptySource)
        val writer = DiagnosticsExportWriter(
            dir = exportDir(),
            renderPayload = store::exportText,
            clock = { Instant.parse("2026-08-05T10:15:30Z").toEpochMilli() },
            ioDispatcher = Dispatchers.Unconfined,
            zone = { utc },
        )

        val file = writer.write(
            listOf(
                entry("WebDAV auth failed password=$secret"),
                entry("plain breadcrumb, nothing sensitive"),
            ),
        )
        val onDisk = file.readText(StandardCharsets.UTF_8)

        assertFalse("the seeded secret must NOT reach disk", onDisk.contains(secret))
        assertTrue(
            "the redaction placeholder must be present in the written bytes",
            onDisk.contains(DiagnosticsRedactor.PLACEHOLDER),
        )
        assertTrue("the non-sensitive breadcrumb survives", onDisk.contains("plain breadcrumb"))
    }

    /**
     * The claim that makes redaction structural rather than a wiring convention: even handed a
     * renderer that dumps raw messages, the writer redacts before the bytes land. Without the
     * unconditional pass in `write`, an injected renderer is a complete bypass of the one egress
     * barrier this feature has.
     */
    @Test fun write_redactsEvenWhenTheInjectedRendererDoesNot() = runBlocking {
        val secret = "rogue-renderer-s3cret-77af"
        val writer = DiagnosticsExportWriter(
            dir = exportDir(),
            // A deliberately naive renderer — the shape a future caller could plausibly write.
            renderPayload = { entries, _ -> entries.joinToString("\n") { it.message } },
            clock = { Instant.parse("2026-08-05T10:15:30Z").toEpochMilli() },
            ioDispatcher = Dispatchers.Unconfined,
            zone = { utc },
        )

        val onDisk = writer.write(payload("token refresh failed password=$secret")).readText(StandardCharsets.UTF_8)

        assertFalse("no renderer may put an unredacted secret on disk", onDisk.contains(secret))
        assertTrue(onDisk.contains(DiagnosticsRedactor.PLACEHOLDER))
    }

    /**
     * The unconditional pass must not rewrite the store's already-redacted export, or the shipped
     * payload would differ from what the viewer showed. `redact` is documented idempotent per
     * message; this pins the property for the whole assembled payload — headers, timestamps,
     * level/category prefixes and indented continuations included — over THIS app's category
     * vocabulary, which is the bounded domain the claim is made for (see the sibling test for what
     * happens outside it).
     */
    @Test fun storeExportText_isAFixedPointOfTheRedactor() {
        val store = DiagnosticsLogStore(EmptySource)
        val rendered = store.exportText(
            listOf(
                entry("WebDAV auth failed password=sup3r-s3cret"),
                entry("Authorization: Bearer abc.def.ghi"),
                entry("apiKey=zzz9 and x-auth-token=qqq1"),
                entry("upload failed\n\tat Foo.bar(secret=nested-one)"),
                entry("nothing sensitive at all"),
                entry(""),
            ),
            generatedAt = 1_700_000_000_000L,
        )

        assertEquals(
            "redacting the store's export again must change nothing",
            rendered,
            DiagnosticsRedactor.redact(rendered),
        )
    }

    /**
     * Outside this app's own vocabulary the two passes CAN differ, and the difference runs in the
     * safe direction. A logcat-sourced entry carries a third-party TAG as its category; the store
     * redacts message bodies and inserts that tag raw, so a credential-shaped tag survives the
     * store and is caught by the writer. Asserted rather than left as a caveat, so the shipped
     * behaviour is pinned either way.
     */
    @Test fun writerPass_alsoRedactsACredentialShapedThirdPartyCategory() = runBlocking {
        val store = DiagnosticsLogStore(EmptySource)
        val hostile = DiagnosticsLogEntry(
            timeMillis = 1_700_000_000_000L,
            level = DiagnosticsLevel.WARN,
            category = "apiKey=leaky-tag-1234",   // a tag from some other app's logging, not ours
            message = "harmless body",
        )

        val storeOutput = store.exportText(listOf(hostile), generatedAt = 1_700_000_000_000L)
        assertTrue("precondition: the store passes a raw category through", storeOutput.contains("leaky-tag-1234"))

        val writer = DiagnosticsExportWriter(
            dir = exportDir(),
            renderPayload = store::exportText,
            clock = { Instant.parse("2026-08-05T10:15:30Z").toEpochMilli() },
            ioDispatcher = Dispatchers.Unconfined,
            zone = { utc },
        )
        val onDisk = writer.write(listOf(hostile)).readText(StandardCharsets.UTF_8)

        assertFalse("the writer's pass catches what the store's per-message pass cannot", onDisk.contains("leaky-tag-1234"))
        assertTrue(onDisk.contains(DiagnosticsRedactor.PLACEHOLDER))
        assertTrue("the body is untouched", onDisk.contains("harmless body"))
    }

    /** Every name the writer derives must satisfy the predicate the share guard applies. */
    @Test fun derivedFileNames_satisfyTheExportNamePredicate() = runBlocking {
        for (iso in listOf("2026-08-05T10:15:30Z", "2026-01-01T00:00:00Z", "2099-12-31T23:59:59Z")) {
            val name = writerAt(iso).write(payload("x")).name
            assertTrue("$name must be recognised as an export", DiagnosticsExportWriter.isExportFileName(name))
        }
        for (bogus in listOf("raw.txt", "vreader-log.txt", "vreader-log-2026-8-5.txt", "vreader-log-2026-08-05.txt.part", "")) {
            assertFalse("$bogus must NOT be recognised as an export", DiagnosticsExportWriter.isExportFileName(bogus))
        }
    }

    /** The same claim for a multi-line (stack-trace shaped) message, which the store indents. */
    @Test fun write_throughTheStoreRenderer_redactsInsideMultiLineMessages() = runBlocking {
        val secret = "multiline-s3cret-4a1b"
        val store = DiagnosticsLogStore(EmptySource)
        val writer = DiagnosticsExportWriter(
            dir = exportDir(),
            renderPayload = store::exportText,
            clock = { Instant.parse("2026-08-05T10:15:30Z").toEpochMilli() },
            ioDispatcher = Dispatchers.Unconfined,
            zone = { utc },
        )

        val file = writer.write(listOf(entry("upload failed\n\tat Foo.bar(password=$secret)")))

        assertFalse(file.readText(StandardCharsets.UTF_8).contains(secret))
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
}
