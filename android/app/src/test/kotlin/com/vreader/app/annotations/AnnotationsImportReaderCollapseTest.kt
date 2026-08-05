package com.vreader.app.annotations

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import vreader.contracts.backup.BackupJson

/**
 * Feature #165 WI-3 — §6.4, the INTRA-FILE collapse (F-1…F-5) plus the already-present filter.
 *
 * This is the half that makes `preview.importable == applied` true by construction: the reader
 * hands the applier an envelope in which no two rows can collide with each other or with the
 * database, so every insert lands. WI-4 asserts the equality against a real Room apply; here the
 * *structural* guarantee it rests on is asserted directly (see
 * [emittedEnvelope_cannotCollideWithItselfOrTheDatabase]).
 *
 * Each rule has a dedicated test AND participates in [allFiveCollapseRulesAtOnce] — collapse rules
 * tested one at a time miss their interactions.
 */
class AnnotationsImportReaderCollapseTest {

    private fun profileKey(charOffset: Int) =
        profileKeyFor(Fx.BOOK_A, Fx.locator(charOffset = charOffset))

    // ---- F-1: same id twice within one kind → keep the first --------------------------------

    @Test fun f1_duplicateIdWithinOneKind_keepsTheFirstInFileOrder() {
        val text = Fx.envelopeJson(
            highlights = listOf(
                Fx.highlight(Fx.uuid(1), locator = Fx.locator(charOffset = 1), selectedText = "first"),
                Fx.highlight(Fx.uuid(1), locator = Fx.locator(charOffset = 2), selectedText = "second"),
            ),
        )
        val p = Fx.ok(Fx.parse(text))
        assertEquals(1, p.highlights)
        assertEquals(1, p.skipped)
        assertEquals("first", p.envelope.highlights.single().selectedText)
    }

    @Test fun f1_fileOrderDecidesTheSurvivor() {
        val a = Fx.highlight(Fx.uuid(1), locator = Fx.locator(charOffset = 1), selectedText = "first")
        val b = Fx.highlight(Fx.uuid(1), locator = Fx.locator(charOffset = 2), selectedText = "second")
        assertEquals("first", Fx.ok(Fx.parse(Fx.envelopeJson(highlights = listOf(a, b))))
            .envelope.highlights.single().selectedText)
        assertEquals("second", Fx.ok(Fx.parse(Fx.envelopeJson(highlights = listOf(b, a))))
            .envelope.highlights.single().selectedText)
    }

    // ---- F-2: same id across kinds → highlights → notes → bookmarks -------------------------

    @Test fun f2_sameIdAcrossKinds_keepsTheHighlight() {
        val id = Fx.uuid(1)
        val text = Fx.envelopeJson(
            highlights = listOf(Fx.highlight(id, locator = Fx.locator(charOffset = 1))),
            notes = listOf(Fx.note(id, locator = Fx.locator(charOffset = 2))),
            bookmarks = listOf(Fx.bookmark(id, locator = Fx.locator(charOffset = 3))),
        )
        val p = Fx.ok(Fx.parse(text))
        assertEquals(listOf(id), Fx.highlightIds(p))
        assertEquals(emptyList<String>(), Fx.noteIds(p))
        assertEquals(emptyList<String>(), Fx.bookmarkIds(p))
        assertEquals(2, p.skipped)
    }

    @Test fun f2_kindOrderIsNotesBeforeBookmarks() {
        val id = Fx.uuid(1)
        val text = Fx.envelopeJson(
            notes = listOf(Fx.note(id, locator = Fx.locator(charOffset = 2))),
            bookmarks = listOf(Fx.bookmark(id, locator = Fx.locator(charOffset = 3))),
        )
        val p = Fx.ok(Fx.parse(text))
        assertEquals(listOf(id), Fx.noteIds(p))
        assertEquals(emptyList<String>(), Fx.bookmarkIds(p))
    }

    // ---- F-3 / F-4: same position, different ids → keep the first ---------------------------

    @Test fun f3_twoHighlightsAtOnePosition_keepTheFirst() {
        val text = Fx.envelopeJson(
            highlights = listOf(
                Fx.highlight(Fx.uuid(1), locator = Fx.locator(charOffset = 5), selectedText = "first"),
                Fx.highlight(Fx.uuid(2), locator = Fx.locator(charOffset = 5), selectedText = "second"),
            ),
        )
        val p = Fx.ok(Fx.parse(text))
        assertEquals(listOf(Fx.uuid(1)), Fx.highlightIds(p))
        assertEquals("first", p.envelope.highlights.single().selectedText)
        assertEquals(1, p.skipped)
    }

    @Test fun f4_twoBookmarksAtOnePosition_keepTheFirst() {
        val text = Fx.envelopeJson(
            bookmarks = listOf(
                Fx.bookmark(Fx.uuid(1), locator = Fx.locator(charOffset = 5), title = "first"),
                Fx.bookmark(Fx.uuid(2), locator = Fx.locator(charOffset = 5), title = "second"),
            ),
        )
        val p = Fx.ok(Fx.parse(text))
        assertEquals(listOf(Fx.uuid(1)), Fx.bookmarkIds(p))
        assertEquals(1, p.skipped)
    }

    // ---- F-5: same position notes BOTH survive ----------------------------------------------

    @Test fun f5_twoNotesAtOnePosition_bothSurvive() {
        // `Entities.kt` has no unique index on notes BY DESIGN — "a reader may keep several notes
        // at one spot" (C-4). Collapsing them here would silently destroy a legitimate row.
        val text = Fx.envelopeJson(
            notes = listOf(
                Fx.note(Fx.uuid(1), locator = Fx.locator(charOffset = 5), content = "first"),
                Fx.note(Fx.uuid(2), locator = Fx.locator(charOffset = 5), content = "second"),
            ),
        )
        val p = Fx.ok(Fx.parse(text))
        assertEquals(listOf(Fx.uuid(1), Fx.uuid(2)), Fx.noteIds(p))
        assertEquals(2, p.importable)
        assertEquals(0, p.skipped)
    }

    // ---- the already-present filter -----------------------------------------------------------

    @Test fun rowsTheDatabaseAlreadyHasById_areDropped() {
        val existing = ExistingAnnotationState(setOf(Fx.uuid(1)), emptySet(), emptySet())
        val text = Fx.envelopeJson(
            highlights = listOf(
                Fx.highlight(Fx.uuid(1), locator = Fx.locator(charOffset = 1)),
                Fx.highlight(Fx.uuid(2), locator = Fx.locator(charOffset = 2)),
            ),
        )
        val p = Fx.ok(Fx.parse(text, existing))
        assertEquals(listOf(Fx.uuid(2)), Fx.highlightIds(p))
        assertEquals(1, p.skipped)
    }

    @Test fun anExistingIdBlocksAnIncomingRowOfADifferentKind() {
        // Android's three tables have table-local primary keys, so nothing in the schema stops one
        // UUID from becoming both a highlight and a note. `ids` is deliberately cross-kind (F-2).
        val existing = ExistingAnnotationState(setOf(Fx.uuid(1)), emptySet(), emptySet())
        val text = Fx.envelopeJson(notes = listOf(Fx.note(Fx.uuid(1))))
        val p = Fx.ok(Fx.parse(text, existing))
        assertEquals(0, p.importable)
        assertEquals(1, p.skipped)
    }

    @Test fun anExistingHighlightPositionBlocksAnIncomingHighlight() {
        val existing = ExistingAnnotationState(emptySet(), setOf(profileKey(5)), emptySet())
        val text = Fx.envelopeJson(
            highlights = listOf(
                Fx.highlight(Fx.uuid(1), locator = Fx.locator(charOffset = 5)),
                Fx.highlight(Fx.uuid(2), locator = Fx.locator(charOffset = 6)),
            ),
        )
        val p = Fx.ok(Fx.parse(text, existing))
        assertEquals(listOf(Fx.uuid(2)), Fx.highlightIds(p))
    }

    @Test fun anExistingBookmarkPositionBlocksAnIncomingBookmark() {
        val existing = ExistingAnnotationState(emptySet(), emptySet(), setOf(profileKey(5)))
        val text = Fx.envelopeJson(
            bookmarks = listOf(
                Fx.bookmark(Fx.uuid(1), locator = Fx.locator(charOffset = 5)),
                Fx.bookmark(Fx.uuid(2), locator = Fx.locator(charOffset = 6)),
            ),
        )
        val p = Fx.ok(Fx.parse(text, existing))
        assertEquals(listOf(Fx.uuid(2)), Fx.bookmarkIds(p))
    }

    @Test fun positionSetsDoNotLeakAcrossKinds() {
        // A highlight at position P must not block a NOTE or a BOOKMARK at position P — they are
        // different unique indexes (Entities.kt:102 vs :167) and notes have none at all.
        val existing = ExistingAnnotationState(emptySet(), setOf(profileKey(5)), emptySet())
        val text = Fx.envelopeJson(
            notes = listOf(Fx.note(Fx.uuid(1), locator = Fx.locator(charOffset = 5))),
            bookmarks = listOf(Fx.bookmark(Fx.uuid(2), locator = Fx.locator(charOffset = 5))),
        )
        val p = Fx.ok(Fx.parse(text, existing))
        assertEquals(2, p.importable)
        assertEquals(0, p.skipped)
    }

    // ---- UUID identity is case-insensitive (Gate-4 round 2) -------------------------------------

    private fun upper(n: Int) = Fx.uuid(n).replace("4000", "4A0A").uppercase()
    private fun lower(n: Int) = upper(n).lowercase()

    @Test fun oneUuidInTwoCasings_collapsesWithinAKind_keepingTheFirstWireSpelling() {
        // Uppercase ids are ACCEPTED (Swift's UUID.uuidString is uppercase), so a file can spell
        // one logical annotation two ways. Comparing verbatim would import it twice.
        val text = Fx.envelopeJson(
            highlights = listOf(
                Fx.highlight(upper(1), locator = Fx.locator(charOffset = 1), selectedText = "first"),
                Fx.highlight(lower(1), locator = Fx.locator(charOffset = 2), selectedText = "second"),
            ),
        )
        val p = Fx.ok(Fx.parse(text))
        assertEquals(1, p.importable)
        assertEquals(1, p.skipped)
        // The survivor keeps the bytes the file gave it — identity folding is for comparison only.
        assertEquals(listOf(upper(1)), Fx.highlightIds(p))
    }

    @Test fun oneUuidInTwoCasings_collapsesAcrossKinds() {
        val text = Fx.envelopeJson(
            highlights = listOf(Fx.highlight(upper(1), locator = Fx.locator(charOffset = 1))),
            notes = listOf(Fx.note(lower(1), locator = Fx.locator(charOffset = 2))),
            bookmarks = listOf(Fx.bookmark(upper(1), locator = Fx.locator(charOffset = 3))),
        )
        val p = Fx.ok(Fx.parse(text))
        assertEquals(listOf(upper(1)), Fx.highlightIds(p))
        assertEquals(emptyList<String>(), Fx.noteIds(p))
        assertEquals(emptyList<String>(), Fx.bookmarkIds(p))
    }

    @Test fun anExistingIdBlocksTheSameUuidSpelledDifferently() {
        val existing = ExistingAnnotationState(setOf(lower(1)), emptySet(), emptySet())
        val text = Fx.envelopeJson(highlights = listOf(Fx.highlight(upper(1))))
        assertEquals(0, Fx.ok(Fx.parse(text, existing)).importable)

        val flipped = ExistingAnnotationState(setOf(upper(1)), emptySet(), emptySet())
        val lowerFile = Fx.envelopeJson(highlights = listOf(Fx.highlight(lower(1))))
        assertEquals(0, Fx.ok(Fx.parse(lowerFile, flipped)).importable)
    }

    @Test fun genuinelyDifferentUuids_stillBothImport() {
        // Discrimination partner: case folding must not collapse distinct ids.
        val text = Fx.envelopeJson(
            highlights = listOf(
                Fx.highlight(upper(1), locator = Fx.locator(charOffset = 1)),
                Fx.highlight(upper(2), locator = Fx.locator(charOffset = 2)),
            ),
        )
        assertEquals(2, Fx.ok(Fx.parse(text)).importable)
    }

    // ---- interactions --------------------------------------------------------------------------

    @Test fun aPositionCollisionDoesNotConsumeTheDroppedRowsId() {
        // H2 loses to H1 on position. Its id must stay AVAILABLE, or H3 — a legitimate row at a
        // different position — would be dropped for colliding with a row that never existed.
        val text = Fx.envelopeJson(
            highlights = listOf(
                Fx.highlight(Fx.uuid(1), locator = Fx.locator(charOffset = 5)),
                Fx.highlight(Fx.uuid(2), locator = Fx.locator(charOffset = 5)),
                Fx.highlight(Fx.uuid(2), locator = Fx.locator(charOffset = 6)),
            ),
        )
        val p = Fx.ok(Fx.parse(text))
        assertEquals(listOf(Fx.uuid(1), Fx.uuid(2)), Fx.highlightIds(p))
        assertEquals(6, decodeOffset(p.envelope.highlights[1].locatorJSON))
        assertEquals(1, p.skipped)
    }

    /** The §6.4 fixture that fires every rule at once; the surviving SET is asserted, not counts. */
    private fun allFiveFixture() = Fx.envelopeJson(
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

    @Test fun allFiveCollapseRulesAtOnce_yieldTheExactSurvivingSet() {
        val p = Fx.ok(Fx.parse(allFiveFixture()))
        assertEquals(listOf(Fx.uuid(1), Fx.uuid(3)), Fx.highlightIds(p))
        assertEquals(listOf(Fx.uuid(4), Fx.uuid(5)), Fx.noteIds(p))
        assertEquals(listOf(Fx.uuid(6)), Fx.bookmarkIds(p))
        assertEquals(listOf("h1", "h4"), p.envelope.highlights.map { it.selectedText })
        assertEquals(listOf("n2", "n3-samePosOk"), p.envelope.notes.map { it.content })
        assertEquals(5, p.importable)
        assertEquals(5, p.skipped)
        assertEquals(10, p.importable + p.skipped)
    }

    @Test fun collapseIsAPureFunctionOfTheBytes() {
        val text = allFiveFixture()
        val a = Fx.ok(Fx.parse(text))
        val b = Fx.ok(Fx.parse(text))
        assertEquals(a.envelope, b.envelope)
        assertEquals(a.sample, b.sample)
        assertEquals(a.importable, b.importable)
        assertEquals(a.skipped, b.skipped)
    }

    // ---- the structural guarantee behind `preview.importable == applied` -----------------------

    @Test fun emittedEnvelope_cannotCollideWithItselfOrTheDatabase() {
        val existing = ExistingAnnotationState(
            ids = setOf(Fx.uuid(90)),
            highlightProfileKeys = setOf(profileKey(90)),
            bookmarkProfileKeys = setOf(profileKey(91)),
        )
        val p = Fx.ok(Fx.parse(allFiveFixture(), existing))
        val env = p.envelope

        val allIds = env.highlights.map { it.highlightId } +
            env.notes.map { it.annotationId } +
            env.bookmarks.map { it.bookmarkId }
        assertEquals("ids must be globally unique across the three kinds", allIds.size, allIds.toSet().size)
        assertTrue("no emitted id may already exist", allIds.none { it in existing.ids })

        val hKeys = env.highlights.map { profileKeyOf(it.locatorJSON) }
        assertEquals("highlight positions must be unique", hKeys.size, hKeys.toSet().size)
        assertTrue(hKeys.none { it in existing.highlightProfileKeys })

        val bKeys = env.bookmarks.map { profileKeyOf(it.locatorJSON) }
        assertEquals("bookmark positions must be unique", bKeys.size, bKeys.toSet().size)
        assertTrue(bKeys.none { it in existing.bookmarkProfileKeys })

        assertTrue(env.highlights.all { it.bookFingerprintKey == Fx.BOOK_A })
        assertTrue(env.notes.all { it.bookFingerprintKey == Fx.BOOK_A })
        assertTrue(env.bookmarks.all { it.bookFingerprintKey == Fx.BOOK_A })
        assertEquals(p.importable, env.highlights.size + env.notes.size + env.bookmarks.size)
    }

    @Test fun theFilesSchemaVersionIsPreservedInTheEmittedEnvelope() {
        val text = Fx.envelopeJson(highlights = listOf(Fx.highlight(Fx.uuid(1))), schemaVersion = 1)
        assertEquals(1, Fx.ok(Fx.parse(text)).envelope.schemaVersion)
    }

    private fun profileKeyOf(locatorJSON: String) =
        profileKeyFor(Fx.BOOK_A, BackupJson.decode<vreader.contracts.Locator>(locatorJSON))

    private fun decodeOffset(locatorJSON: String): Int =
        BackupJson.decode<vreader.contracts.Locator>(locatorJSON).charOffsetUTF16 ?: -1
}
