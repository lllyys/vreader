package com.vreader.app.annotations

import android.database.sqlite.SQLiteConstraintException
import com.vreader.app.annotations.ApplierHarness.Companion.env
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Feature #165 WI-4 — C-5b (the target book is gone) and the boundary of what may be REPORTED as
 * `BookMissing`.
 *
 * C-5b has two layers and they are separated here MECHANICALLY, because a test that only ever
 * reaches the `findBook` pre-check proves nothing about the foreign-key mapping that actually
 * closes the race:
 *  - the **layer-1** discriminator seeds the parent only in the ANNOTATIONS store, so the insert
 *    would have succeeded and the reported failure carries **no cause**;
 *  - the **layer-2** test seeds it only in the LIBRARY store, so the pre-check passes and the
 *    reported failure's cause is **SQLite's own [SQLiteConstraintException]**.
 * Neither outcome is reachable by the other layer, so removing either layer turns exactly one of
 * these tests red.
 */
@RunWith(RobolectricTestRunner::class)
class AnnotationsImportApplierBookMissingTest {

    private lateinit var h: ApplierHarness

    @Before fun setUp() = runBlocking {
        h = ApplierHarness()
        h.seedBook()
    }

    @After fun tearDown() = h.close()

    private fun oneRowPreview(harness: ApplierHarness) = harness.previewOf(
        env(highlights = listOf(Fx.highlight(Fx.uuid(1), locator = Fx.locator(charOffset = 1)))),
    )

    private fun reasonOf(result: Result<RestoreAnnotationsReport>): ImportFailure =
        (result.exceptionOrNull() as? AnnotationImportFailedException)?.reason
            ?: error("expected a typed import failure, got ${result.exceptionOrNull()}")

    private fun withSplitStores(body: suspend (ApplierHarness) -> Unit) = runBlocking {
        val s = ApplierHarness(splitStores = true)
        try {
            body(s)
        } finally {
            s.close()
        }
    }

    // ---- layer 1: the pre-check -------------------------------------------------------------------

    @Test fun layer1_parentDeletedWhileTheSheetWasOpen_isBookMissing_andNothingIsWritten() =
        runBlocking {
            val preview = oneRowPreview(h)
            h.deleteLibraryBook()

            assertEquals(ImportFailure.BookMissing, reasonOf(h.applier.apply(preview)))
            assertEquals(0, h.snapshot().size)
        }

    /**
     * The layer-1 discriminator, and the exact mirror of the layer-2 one: here the annotations
     * store HAS the parent, so the insert would have succeeded — only the pre-check can refuse, and
     * the reported failure carries NO cause because no database error was ever raised. Delete the
     * pre-check and this test goes red (a row lands) while the layer-2 test stays green.
     */
    @Test fun layer1_isTheRefusal_evenWhenTheInsertItselfWouldHaveSucceeded() = withSplitStores { s ->
        s.seedAnnotationsParent()    // the write would be accepted...
        // ...but `findBook` reads the library store, which has no such book.
        val result = s.applier.apply(oneRowPreview(s))

        val failure = result.exceptionOrNull() as? AnnotationImportFailedException
            ?: error("expected a typed import failure, got ${result.exceptionOrNull()}")
        assertEquals(ImportFailure.BookMissing, failure.reason)
        assertNull("layer 1 refuses before any database error exists", failure.cause)
        assertEquals(0, s.snapshot().size)
    }

    // ---- layer 2: the foreign-key mapping, reached only after the pre-check passed ----------------

    @Test fun layer2_parentLostAfterTheCheck_mapsTheForeignKeyViolationToBookMissing() =
        withSplitStores { s ->
            s.seedLibraryBook()          // layer 1 PASSES — findBook resolves
            // ...but the annotations store has no parent row, so the insert raises SQLite's error.
            val result = s.applier.apply(oneRowPreview(s))

            val failure = result.exceptionOrNull() as? AnnotationImportFailedException
                ?: error("the SQLite constraint failure escaped untyped: ${result.exceptionOrNull()}")
            assertEquals(ImportFailure.BookMissing, failure.reason)
            // The discriminator: layer 1 cannot produce this cause, so this test cannot be
            // satisfied by the pre-check having fired.
            assertTrue(
                "layer 2 must be the layer that fired",
                failure.cause is SQLiteConstraintException,
            )
            assertEquals(0, s.snapshot().size)
        }

    @Test fun layer2_control_theSameRigWithAParentPresent_appliesNormally() = withSplitStores { s ->
        s.seedBook()   // both stores — proves the split rig fails for the FK and nothing else
        assertEquals(1, s.applier.apply(oneRowPreview(s)).getOrThrow().appliedTotal)
        assertEquals(1, s.snapshot().size)
    }

    /**
     * The observable half of the atomicity claim: a lost parent leaves the store exactly as it was.
     * Note honestly what this does NOT prove — every row in one apply shares one `bookKey`, so the
     * missing parent fails the FIRST insert and this passes with or without the restore's
     * `@Transaction` (measured). Proving the transaction itself needs a fault-injection seam on the
     * DAO, which this work item may not write; see the applier's header.
     */
    @Test fun layer2_theFailureIsTotal_noImportedRowSurvives_andOtherBooksAreUntouched() =
        withSplitStores { s ->
            s.seedLibraryBook(Fx.BOOK_A)         // the import target: layer 1 passes
            s.seedAnnotationsParent(Fx.BOOK_B)   // an unrelated book that DOES exist where we write
            s.repo.restoreAnnotations(
                env(
                    highlights = listOf(
                        Fx.highlight(Fx.uuid(9), Fx.BOOK_B, Fx.locator(Fx.BOOK_B, charOffset = 1)),
                    ),
                ),
                setOf(Fx.BOOK_B),
            )
            val before = s.snapshot()
            assertEquals(1, before.size)

            val result = s.applier.apply(
                s.previewOf(
                    env(
                        highlights = listOf(
                            Fx.highlight(Fx.uuid(1), locator = Fx.locator(charOffset = 1)),
                            Fx.highlight(Fx.uuid(2), locator = Fx.locator(charOffset = 2)),
                        ),
                        notes = listOf(Fx.note(Fx.uuid(3), locator = Fx.locator(charOffset = 3))),
                        bookmarks = listOf(Fx.bookmark(Fx.uuid(4), locator = Fx.locator(charOffset = 4))),
                    ),
                ),
            )

            assertEquals(ImportFailure.BookMissing, reasonOf(result))
            assertEquals("a lost parent leaves the store exactly as it was", before, s.snapshot())
        }

    // ---- the boundary of the BookMissing label ----------------------------------------------------

    @Test fun apply_anUnexpectedDatabaseFailure_isNotMislabelledAsBookMissing() = runBlocking {
        // A non-constraint database error: the table is gone, which is nothing like "the book was
        // deleted". Relabelling it `BookMissing` would tell the user something they cannot act on.
        // (Closing the database would NOT do — Room silently re-opens an in-memory store empty,
        // which manufactures the very foreign-key failure this test must avoid.)
        h.annotationsDb.openHelper.writableDatabase.execSQL("DROP TABLE highlights")
        val result = h.applier.apply(oneRowPreview(h))

        assertTrue(result.isFailure)
        assertFalse(
            "only a lost parent may be reported as BookMissing",
            result.exceptionOrNull() is AnnotationImportFailedException,
        )
    }
}
