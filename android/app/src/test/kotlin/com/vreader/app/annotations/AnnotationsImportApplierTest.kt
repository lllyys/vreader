package com.vreader.app.annotations

import com.vreader.app.annotations.ApplierHarness.Companion.env
import com.vreader.app.annotations.ApplierHarness.Companion.profileKeyAt
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import vreader.contracts.backup.BackupJson

/**
 * Feature #165 WI-4 — [AnnotationsImportApplier]'s merge semantics over a REAL in-memory Room
 * database with a seeded parent `BookEntity`: A-3 (rows land field-for-field), A-4 (idempotent),
 * A-5 (never overwrite), A-6 (foreign-book rows skipped), A-8 (row-level failures drop siblings-
 * intact), C-3 (same-position highlight collapses) and C-4 (same-position note does NOT — the
 * documented limitation, asserted so a future unique index trips this test).
 *
 * `existingState` is tested here too: it is the input that makes the READER's already-present
 * filter agree with what the database will actually accept, so a gap in it shows up as the
 * `preview.importable == applied` divergence [AnnotationsImportApplierInvariantTest] asserts.
 */
@RunWith(RobolectricTestRunner::class)
class AnnotationsImportApplierTest {

    private lateinit var h: ApplierHarness

    @Before fun setUp() = runBlocking {
        h = ApplierHarness()
        h.seedBook()
    }

    @After fun tearDown() = h.close()

    // ---- existingState — what "already present" means -------------------------------------------

    @Test fun existingState_onABookWithNoAnnotations_isEmpty() = runBlocking {
        assertEquals(ExistingAnnotationState.EMPTY, h.applier.existingState(Fx.BOOK_A))
    }

    @Test fun existingState_spansAllThreeKindsForIds_butOnlyHighlightsAndBookmarksForPositions() =
        runBlocking {
            h.repo.restoreAnnotations(
                env(
                    highlights = listOf(Fx.highlight(Fx.uuid(1), locator = Fx.locator(charOffset = 1))),
                    notes = listOf(Fx.note(Fx.uuid(2), locator = Fx.locator(charOffset = 2))),
                    bookmarks = listOf(Fx.bookmark(Fx.uuid(3), locator = Fx.locator(charOffset = 3))),
                ),
                setOf(Fx.BOOK_A),
            )

            val state = h.applier.existingState(Fx.BOOK_A)
            // ONE global id set across the three kinds — iOS's `existingAnnotationIds` semantics
            // restored on a schema with three table-local primary keys (D-12).
            assertEquals(setOf(Fx.uuid(1), Fx.uuid(2), Fx.uuid(3)), state.ids)
            assertEquals(setOf(profileKeyAt(1)), state.highlightProfileKeys)
            assertEquals(setOf(profileKeyAt(3)), state.bookmarkProfileKeys)
            // F-5 / C-4: a note's POSITION is not a dedupe key in either direction.
            assertFalse(profileKeyAt(2) in state.highlightProfileKeys)
            assertFalse(profileKeyAt(2) in state.bookmarkProfileKeys)
        }

    /**
     * The two halves of the state have DIFFERENT scopes, and the asymmetry is load-bearing: each
     * table's primary key is the id alone, so ids collide library-wide, while a `profileKey` embeds
     * its own `bookKey` and therefore cannot. Scoping the ids to the target book is the Gate-4
     * round-1 defect — it previewed another book's UUID as importable and delivered nothing.
     */
    @Test fun existingState_positionKeysAreScopedToTheBook_butIdsAreLibraryWide() = runBlocking {
        h.seedBook(Fx.BOOK_B)
        h.repo.restoreAnnotations(
            env(
                highlights = listOf(
                    Fx.highlight(Fx.uuid(1), Fx.BOOK_B, Fx.locator(Fx.BOOK_B, charOffset = 1)),
                ),
                notes = listOf(Fx.note(Fx.uuid(2), Fx.BOOK_B, Fx.locator(Fx.BOOK_B, charOffset = 2))),
                bookmarks = listOf(
                    Fx.bookmark(Fx.uuid(3), Fx.BOOK_B, Fx.locator(Fx.BOOK_B, charOffset = 3)),
                ),
            ),
            setOf(Fx.BOOK_B),
        )
        assertEquals(3, h.snapshot().size)

        val state = h.applier.existingState(Fx.BOOK_A)
        assertEquals(
            "a UUID spent on ANY book cannot be re-inserted under this one",
            setOf(Fx.uuid(1), Fx.uuid(2), Fx.uuid(3)),
            state.ids,
        )
        assertTrue(state.highlightProfileKeys.isEmpty())
        assertTrue(state.bookmarkProfileKeys.isEmpty())
    }

    // ---- A-3: the rows actually land, field for field --------------------------------------------

    @Test fun apply_mergesEveryKind_preservingIdTimestampsColorTextAndLocator() = runBlocking {
        val locH = Fx.locator(charOffset = 11)
        val locN = Fx.locator(charOffset = 12)
        val locB = Fx.locator(charOffset = 13)
        val report = h.applier.apply(
            h.previewOf(
                env(
                    highlights = listOf(
                        Fx.highlight(
                            Fx.uuid(1), locator = locH, selectedText = "选中的文字",
                            color = "green", note = "inline",
                        ),
                    ),
                    notes = listOf(Fx.note(Fx.uuid(2), locator = locN, content = "note body")),
                    bookmarks = listOf(Fx.bookmark(Fx.uuid(3), locator = locB, title = "第一章")),
                ),
            ),
        ).getOrThrow()

        assertEquals(3, report.appliedTotal)

        val stored = h.repo.highlightsForBook(Fx.BOOK_A).single()
        assertEquals(Fx.uuid(1), stored.id)
        assertEquals(Fx.BOOK_A, stored.bookKey)
        assertEquals("选中的文字", stored.selectedText)
        assertEquals(AnnotationColor.from("green"), stored.color)
        assertEquals("inline", stored.note)
        assertEquals(locH, stored.locator)
        assertEquals(Fx.T0.toEpochMilli(), stored.createdAt)
        assertEquals(Fx.T0.toEpochMilli(), stored.updatedAt)

        val note = h.repo.allNotes().single()
        assertEquals(Fx.uuid(2), note.id)
        assertEquals("note body", note.content)
        assertEquals(locN, note.locator)

        val bookmark = h.repo.allBookmarks().single()
        assertEquals(Fx.uuid(3), bookmark.id)
        assertEquals("第一章", bookmark.title)
        assertEquals(locB, bookmark.locator)
        assertEquals(Fx.T0.toEpochMilli(), bookmark.createdAt)
    }

    // ---- A-4: idempotency is deep equality, not a zero count -------------------------------------

    @Test fun apply_isIdempotent_secondRunAppliesZeroAndMutatesNothing() = runBlocking {
        val preview = h.previewOf(
            env(
                highlights = listOf(
                    Fx.highlight(Fx.uuid(1), locator = Fx.locator(charOffset = 1)),
                    Fx.highlight(Fx.uuid(2), locator = Fx.locator(charOffset = 2)),
                ),
                notes = listOf(Fx.note(Fx.uuid(3), locator = Fx.locator(charOffset = 3))),
                bookmarks = listOf(Fx.bookmark(Fx.uuid(4), locator = Fx.locator(charOffset = 4))),
            ),
        )
        assertEquals(4, h.applier.apply(preview).getOrThrow().appliedTotal)

        val before = h.snapshot()
        assertEquals(4, before.size)

        val second = h.applier.apply(preview).getOrThrow()
        assertEquals(0, second.appliedTotal)
        // Deep equality — a run that deleted everything and re-inserted nothing also applies 0.
        assertEquals(before, h.snapshot())
    }

    // ---- A-5: the existing row wins (C-2) ---------------------------------------------------------

    @Test fun apply_neverOverwritesAnExistingRow_sameUuidDifferentContent() = runBlocking {
        val original = Fx.highlight(
            Fx.uuid(1), locator = Fx.locator(charOffset = 1),
            selectedText = "original", color = "yellow", note = "keep me",
        )
        h.applier.apply(h.previewOf(env(highlights = listOf(original)))).getOrThrow()

        val mutated = original.copy(
            selectedText = "REPLACED", color = "red", note = null,
            updatedAt = Fx.T0.plusSeconds(9_999),
        )
        val report = h.applier.apply(h.previewOf(env(highlights = listOf(mutated)))).getOrThrow()

        assertEquals(0, report.appliedTotal)
        assertEquals(1, report.highlights.skipped)
        val stored = h.repo.highlightsForBook(Fx.BOOK_A).single()
        assertEquals("original", stored.selectedText)
        assertEquals("keep me", stored.note)
        assertEquals(AnnotationColor.from("yellow"), stored.color)
        assertEquals(Fx.T0.toEpochMilli(), stored.updatedAt)
    }

    // ---- A-6: a foreign book's rows are skipped, never applied, never a constraint failure --------

    @Test fun apply_foreignBookRows_areSkipped_neverApplied_andNeverThrow() = runBlocking {
        h.seedBook(Fx.BOOK_B)
        val result = h.applier.apply(
            h.previewOf(
                env(
                    highlights = listOf(
                        Fx.highlight(Fx.uuid(1), locator = Fx.locator(charOffset = 1)),
                        Fx.highlight(Fx.uuid(2), Fx.BOOK_B, Fx.locator(Fx.BOOK_B, charOffset = 1)),
                    ),
                    notes = listOf(Fx.note(Fx.uuid(3), Fx.BOOK_B, Fx.locator(Fx.BOOK_B, charOffset = 2))),
                    bookmarks = listOf(
                        Fx.bookmark(Fx.uuid(4), Fx.BOOK_B, Fx.locator(Fx.BOOK_B, charOffset = 3)),
                    ),
                ),
            ),
        )
        val report = result.getOrThrow()

        assertEquals(1, report.highlights.applied)
        assertEquals(1, report.highlights.skipped)
        assertEquals(1, report.notes.skipped)
        assertEquals(1, report.bookmarks.skipped)
        // B's tables stay empty — the FK was never even offered a foreign parent.
        assertEquals(listOf(Fx.uuid(1)), h.repo.allHighlights().map { it.id })
        assertTrue(h.repo.allNotes().isEmpty())
        assertTrue(h.repo.allBookmarks().isEmpty())
    }

    // ---- A-8: a row the REPOSITORY gate rejects drops alone ---------------------------------------

    @Test fun apply_rowsFailingTheRepositoryGate_areDropped_validSiblingsStillApply() = runBlocking {
        val report = h.applier.apply(
            h.previewOf(
                env(
                    highlights = listOf(
                        Fx.highlight(Fx.uuid(1), locator = Fx.locator(charOffset = 1)),
                        Fx.highlight(Fx.uuid(2), locatorJSON = "{not-valid-json"),
                        Fx.highlight(
                            Fx.uuid(3),
                            locatorJSON = BackupJson.encode(Fx.locator(Fx.BOOK_B)),
                        ),
                        Fx.highlight(Fx.uuid(4), locator = Fx.locator(charOffset = 4)),
                    ),
                ),
            ),
        ).getOrThrow()

        assertEquals(2, report.highlights.applied)
        assertEquals(2, report.highlights.failed)
        assertEquals(setOf(Fx.uuid(1), Fx.uuid(4)), h.repo.allHighlights().map { it.id }.toSet())
    }

    // ---- C-3 / C-4: position collapse applies to highlights, NOT to notes ------------------------

    @Test fun apply_samePositionHighlightWithADifferentUuid_isSkippedNotDuplicated() = runBlocking {
        val at7 = Fx.locator(charOffset = 7)
        h.applier.apply(h.previewOf(env(highlights = listOf(Fx.highlight(Fx.uuid(1), locator = at7)))))
            .getOrThrow()

        val report = h.applier
            .apply(h.previewOf(env(highlights = listOf(Fx.highlight(Fx.uuid(2), locator = at7)))))
            .getOrThrow()

        assertEquals(0, report.highlights.applied)
        assertEquals(1, report.highlights.skipped)
        assertEquals(listOf(Fx.uuid(1)), h.repo.allHighlights().map { it.id })
    }

    @Test fun apply_samePositionNoteWithADifferentUuid_isCreated_theDocumentedLimitation() =
        runBlocking {
            val at8 = Fx.locator(charOffset = 8)
            val report = h.applier.apply(
                h.previewOf(
                    env(
                        notes = listOf(
                            Fx.note(Fx.uuid(1), locator = at8, content = "first"),
                            Fx.note(Fx.uuid(2), locator = at8, content = "second"),
                        ),
                    ),
                ),
            ).getOrThrow()

            // C-4 is a KNOWN limitation, asserted so adding a unique index trips this test rather
            // than silently changing what a user's import produces.
            assertEquals(2, report.notes.applied)
            assertEquals(setOf(Fx.uuid(1), Fx.uuid(2)), h.repo.allNotes().map { it.id }.toSet())
        }
}
