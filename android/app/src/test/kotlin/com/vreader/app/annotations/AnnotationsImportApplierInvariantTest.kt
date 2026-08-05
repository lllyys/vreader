package com.vreader.app.annotations

import com.vreader.app.annotations.ApplierHarness.Companion.env
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import vreader.contracts.Locator
import vreader.contracts.backup.BackupJson

/**
 * Feature #165 WI-4 — the two claims that can only be proven where the reader and the database
 * meet.
 *
 * **A-11 (`preview.importable == applied`).** Asserted by driving the REAL
 * [AnnotationsImportReader] over real bytes and then applying the resulting preview to a real
 * in-memory Room database — once per input class the reader can produce, not just the happy path.
 * A clean-file-only assertion is the version of this test that passes while wrong.
 *
 * C-5b (the target book is gone) lives next door in `AnnotationsImportApplierBookMissingTest`.
 */
@RunWith(RobolectricTestRunner::class)
class AnnotationsImportApplierInvariantTest {

    private lateinit var h: ApplierHarness

    @Before fun setUp() = runBlocking {
        h = ApplierHarness()
        h.seedBook()
    }

    @After fun tearDown() = h.close()

    /** Reader → applier, exactly as WI-4b will call them: state, parse, apply. */
    private suspend fun importFile(text: String): Pair<ImportPreview, RestoreAnnotationsReport> {
        val preview = Fx.ok(Fx.parse(text, h.applier.existingState(Fx.BOOK_A)))
        return preview to h.applier.apply(preview).getOrThrow()
    }

    private fun assertPreviewMatchesApply(
        preview: ImportPreview,
        report: RestoreAnnotationsReport,
    ) = assertEquals(
        "the number the user approves must be the number they get",
        preview.importable,
        report.appliedTotal,
    )

    // ---- A-11, one case per input class the reader can emit ---------------------------------------

    @Test fun importableEqualsApplied_onACleanFile_withCjkContentSurvivingVerbatim() = runBlocking {
        val text = Fx.envelopeJson(
            highlights = listOf(
                Fx.highlight(Fx.uuid(1), locator = Fx.locator(charOffset = 1), selectedText = "黑暗血时代"),
            ),
            notes = listOf(Fx.note(Fx.uuid(2), locator = Fx.locator(charOffset = 2), content = "道诡异仙")),
            bookmarks = listOf(Fx.bookmark(Fx.uuid(3), locator = Fx.locator(charOffset = 3))),
        )
        val (preview, report) = importFile(text)

        assertEquals(3, preview.importable)
        assertPreviewMatchesApply(preview, report)
        assertEquals("黑暗血时代", h.repo.allHighlights().single().selectedText)
        assertEquals("道诡异仙", h.repo.allNotes().single().content)
    }

    /** The §6.4 fixture that fires F-1…F-5 at once — the only shape that catches a collapse regression. */
    private fun hostileDuplicateFile() = Fx.envelopeJson(
        highlights = listOf(
            Fx.highlight(Fx.uuid(1), locator = Fx.locator(charOffset = 1), selectedText = "h1"),
            Fx.highlight(Fx.uuid(1), locator = Fx.locator(charOffset = 2), selectedText = "h2-dupId"),
            Fx.highlight(Fx.uuid(2), locator = Fx.locator(charOffset = 1), selectedText = "h3-dupPos"),
            Fx.highlight(Fx.uuid(3), locator = Fx.locator(charOffset = 3), selectedText = "h4"),
        ),
        notes = listOf(
            Fx.note(Fx.uuid(3), locator = Fx.locator(charOffset = 4), content = "n1-crossKindDupId"),
            Fx.note(Fx.uuid(4), locator = Fx.locator(charOffset = 5), content = "n2"),
            Fx.note(Fx.uuid(5), locator = Fx.locator(charOffset = 5), content = "n3-samePosOk"),
        ),
        bookmarks = listOf(
            Fx.bookmark(Fx.uuid(6), locator = Fx.locator(charOffset = 6), title = "b1"),
            Fx.bookmark(Fx.uuid(7), locator = Fx.locator(charOffset = 6), title = "b2-dupPos"),
            Fx.bookmark(Fx.uuid(4), locator = Fx.locator(charOffset = 7), title = "b3-crossKindDupId"),
        ),
    )

    @Test fun importableEqualsApplied_onTheHostileDuplicateFile_andTheSurvivingRowsAreTheFirstOnes() =
        runBlocking {
            val (preview, report) = importFile(hostileDuplicateFile())

            assertEquals(5, preview.importable)
            assertEquals(5, preview.skipped)
            assertPreviewMatchesApply(preview, report)
            // The row SET, not the count: 10 rows in, the 5 first-occurrences out.
            assertEquals(setOf(Fx.uuid(1), Fx.uuid(3)), h.repo.allHighlights().map { it.id }.toSet())
            assertEquals(setOf(Fx.uuid(4), Fx.uuid(5)), h.repo.allNotes().map { it.id }.toSet())
            assertEquals(setOf(Fx.uuid(6)), h.repo.allBookmarks().map { it.id }.toSet())
            assertEquals(listOf("h1", "h4"), h.repo.allHighlights().sortedBy { it.id }.map { it.selectedText })
        }

    @Test fun importableEqualsApplied_whenRowsFailTheReadersGate() = runBlocking {
        val text = Fx.envelopeJson(
            highlights = listOf(
                Fx.highlight(Fx.uuid(1), locator = Fx.locator(charOffset = 1)),
                Fx.highlight("not-a-uuid", locator = Fx.locator(charOffset = 2)),
                Fx.highlight(Fx.uuid(2), locator = Fx.locator(charOffset = -5)),
                Fx.highlight(Fx.uuid(3), Fx.BOOK_B, Fx.locator(Fx.BOOK_B, charOffset = 1)),
            ),
            notes = listOf(
                Fx.note(Fx.uuid(4), locator = Fx.locator(charOffset = 4), content = "x".repeat(10_001)),
                Fx.note(Fx.uuid(5), locator = Fx.locator(charOffset = 5)),
            ),
            bookmarks = listOf(Fx.bookmark(Fx.uuid(6), locator = Fx.locator(charOffset = 6))),
        )
        val (preview, report) = importFile(text)

        assertEquals(3, preview.importable)
        assertEquals(4, preview.skipped)
        assertPreviewMatchesApply(preview, report)
        assertEquals(setOf(Fx.uuid(1), Fx.uuid(5), Fx.uuid(6)), h.snapshot().let { s ->
            (s.highlights.map { it.id } + s.notes.map { it.id } + s.bookmarks.map { it.id }).toSet()
        })
    }

    /**
     * The case that ties `existingState` to the reader. Every key the database enforces has a
     * colliding row here: an id already used by each kind, a highlight position, a bookmark
     * position, and a cross-kind id reuse. Under-report any one of them and the reader keeps a row
     * the insert then IGNOREs — `importable` exceeds `applied` and this test goes red.
     */
    @Test fun importableEqualsApplied_againstAPopulatedDatabase() = runBlocking {
        h.repo.restoreAnnotations(
            env(
                highlights = listOf(Fx.highlight(Fx.uuid(10), locator = Fx.locator(charOffset = 1))),
                notes = listOf(Fx.note(Fx.uuid(11), locator = Fx.locator(charOffset = 2))),
                bookmarks = listOf(Fx.bookmark(Fx.uuid(12), locator = Fx.locator(charOffset = 3))),
            ),
            setOf(Fx.BOOK_A),
        )

        val text = Fx.envelopeJson(
            highlights = listOf(
                Fx.highlight(Fx.uuid(10), locator = Fx.locator(charOffset = 9)),   // id already present
                Fx.highlight(Fx.uuid(20), locator = Fx.locator(charOffset = 1)),   // position already present
                Fx.highlight(Fx.uuid(21), locator = Fx.locator(charOffset = 5)),   // survives
            ),
            notes = listOf(
                Fx.note(Fx.uuid(11), locator = Fx.locator(charOffset = 9)),        // id already present
                Fx.note(Fx.uuid(10), locator = Fx.locator(charOffset = 8)),        // cross-kind id reuse
                Fx.note(Fx.uuid(22), locator = Fx.locator(charOffset = 2)),        // same spot as a note: survives
            ),
            bookmarks = listOf(
                Fx.bookmark(Fx.uuid(12), locator = Fx.locator(charOffset = 9)),    // id already present
                Fx.bookmark(Fx.uuid(23), locator = Fx.locator(charOffset = 3)),    // position already present
                Fx.bookmark(Fx.uuid(24), locator = Fx.locator(charOffset = 7)),    // survives
            ),
        )
        val (preview, report) = importFile(text)

        assertEquals(3, preview.importable)
        assertEquals(6, preview.skipped)
        assertPreviewMatchesApply(preview, report)
        assertEquals(6, h.snapshot().size)
        assertEquals(setOf(Fx.uuid(10), Fx.uuid(21)), h.repo.allHighlights().map { it.id }.toSet())
        assertEquals(setOf(Fx.uuid(11), Fx.uuid(22)), h.repo.allNotes().map { it.id }.toSet())
        assertEquals(setOf(Fx.uuid(12), Fx.uuid(24)), h.repo.allBookmarks().map { it.id }.toSet())
    }

    /**
     * Every annotation table's PRIMARY KEY is the id ALONE (`Entities.kt` — `highlightId`, `noteId`,
     * `bookmarkId`), so it is unique across the whole LIBRARY, not per book. An incoming row whose
     * UUID is already used by a DIFFERENT book's annotation cannot be inserted — Room IGNOREs it —
     * so a state that only knew about the target book's ids would preview it as importable and
     * deliver nothing.
     */
    @Test fun importableEqualsApplied_whenAnIncomingIdIsAlreadyUsedByAnotherBooksAnnotation() =
        runBlocking {
            h.seedBook(Fx.BOOK_B)
            h.repo.restoreAnnotations(
                env(
                    highlights = listOf(
                        Fx.highlight(Fx.uuid(30), Fx.BOOK_B, Fx.locator(Fx.BOOK_B, charOffset = 1)),
                    ),
                    notes = listOf(Fx.note(Fx.uuid(31), Fx.BOOK_B, Fx.locator(Fx.BOOK_B, charOffset = 2))),
                    bookmarks = listOf(
                        Fx.bookmark(Fx.uuid(32), Fx.BOOK_B, Fx.locator(Fx.BOOK_B, charOffset = 3)),
                    ),
                ),
                setOf(Fx.BOOK_B),
            )

            val text = Fx.envelopeJson(
                highlights = listOf(
                    Fx.highlight(Fx.uuid(30), locator = Fx.locator(charOffset = 1)),  // B's highlight id
                    Fx.highlight(Fx.uuid(40), locator = Fx.locator(charOffset = 2)),  // survives
                ),
                notes = listOf(
                    Fx.note(Fx.uuid(31), locator = Fx.locator(charOffset = 3)),       // B's note id
                    Fx.note(Fx.uuid(41), locator = Fx.locator(charOffset = 4)),       // survives
                ),
                bookmarks = listOf(
                    Fx.bookmark(Fx.uuid(32), locator = Fx.locator(charOffset = 5)),   // B's bookmark id
                    Fx.bookmark(Fx.uuid(42), locator = Fx.locator(charOffset = 6)),   // survives
                ),
            )
            val (preview, report) = importFile(text)

            assertEquals(3, preview.importable)
            assertEquals(3, preview.skipped)
            assertPreviewMatchesApply(preview, report)
            // B's rows are untouched and A gained exactly the three non-colliding rows.
            assertEquals(setOf(Fx.uuid(30), Fx.uuid(40)), h.repo.allHighlights().map { it.id }.toSet())
            assertEquals(setOf(Fx.uuid(31), Fx.uuid(41)), h.repo.allNotes().map { it.id }.toSet())
            assertEquals(setOf(Fx.uuid(32), Fx.uuid(42)), h.repo.allBookmarks().map { it.id }.toSet())
        }

    @Test fun importableEqualsApplied_onAReImportOfTheSameBytes() = runBlocking {
        val text = hostileDuplicateFile()
        val (first, firstReport) = importFile(text)
        assertPreviewMatchesApply(first, firstReport)
        val after = h.snapshot()

        val (second, secondReport) = importFile(text)
        assertEquals("everything is already present", 0, second.importable)
        assertEquals(10, second.skipped)
        assertPreviewMatchesApply(second, secondReport)
        assertEquals(after, h.snapshot())
    }

    @Test fun importableEqualsApplied_whenEveryRowIsSkipped_andWhenTheEnvelopeIsEmpty() = runBlocking {
        val allBad = Fx.envelopeJson(
            highlights = listOf(Fx.highlight("not-a-uuid", locator = Fx.locator(charOffset = 1))),
            notes = listOf(Fx.note(Fx.uuid(1), Fx.BOOK_B, Fx.locator(Fx.BOOK_B))),
        )
        val (preview, report) = importFile(allBad)
        assertEquals(0, preview.importable)
        assertEquals(2, preview.skipped)
        assertPreviewMatchesApply(preview, report)

        val (empty, emptyReport) = importFile(Fx.envelopeJson())
        assertEquals(0, empty.importable)
        assertPreviewMatchesApply(empty, emptyReport)
        assertEquals(0, h.snapshot().size)
    }

    // ---- the applier's own scoping duty ----------------------------------------------------------

    @Test fun apply_isARealMergeNotAReplace_theEnvelopeIsScopedToThePreviewsBook() = runBlocking {
        // A preview whose envelope smuggles a foreign row: the applier must scope the restore to
        // preview.bookKey, so the foreign row is skipped rather than reaching a foreign parent.
        h.seedBook(Fx.BOOK_B)
        val smuggled = h.previewOf(
            env(
                highlights = listOf(
                    Fx.highlight(Fx.uuid(1), locator = Fx.locator(charOffset = 1)),
                    Fx.highlight(Fx.uuid(2), Fx.BOOK_B, Fx.locator(Fx.BOOK_B, charOffset = 1)),
                ),
            ),
        )
        val report = h.applier.apply(smuggled).getOrThrow()

        assertEquals(1, report.highlights.applied)
        assertEquals(1, report.highlights.skipped)
        assertEquals(listOf(Fx.uuid(1)), h.repo.allHighlights().map { it.id })
        // The preview promised 2 and the database took 1 — the applier must not silently claim 2.
        assertEquals(2, smuggled.importable)
        assertEquals(1, report.appliedTotal)
    }

    @Test fun apply_doesNotDependOnBackupJsonReEncoding_theStoredLocatorRoundTrips() = runBlocking {
        val locator = Fx.locator(charOffset = 42, href = "chapter-3.xhtml", progression = 0.5)
        val text = Fx.envelopeJson(
            highlights = listOf(Fx.highlight(Fx.uuid(1), locator = locator)),
        )
        val (preview, report) = importFile(text)
        assertPreviewMatchesApply(preview, report)
        assertEquals(locator, h.repo.allHighlights().single().locator)
        assertEquals(
            locator,
            BackupJson.decode<Locator>(preview.envelope.highlights.single().locatorJSON),
        )
    }
}
