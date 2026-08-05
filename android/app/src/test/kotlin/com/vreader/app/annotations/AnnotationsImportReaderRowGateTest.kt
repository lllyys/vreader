package com.vreader.app.annotations

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import vreader.contracts.backup.BackupJson

/**
 * Feature #165 WI-3 — the PER-ROW validation gate (§8.3).
 *
 * Every case here is a **mixed file**: the hostile row sits next to a good sibling, and both the
 * skip and the survival are asserted. A gate tested with a single-bad-row file passes just as
 * happily on a reader that refuses every file, which is the failure mode this suite exists to
 * rule out.
 */
class AnnotationsImportReaderRowGateTest {

    /** A good highlight that must survive alongside whatever hostile row a test adds. */
    private val goodJson = BackupJson.encode(
        Fx.highlight(Fx.uuid(99), locator = Fx.locator(charOffset = 999), selectedText = "good"),
    )

    private fun highlightsFile(vararg rows: String) =
        """{"schemaVersion":3,"highlights":[${rows.joinToString(",")}],"bookmarks":[],"notes":[]}"""

    /** Parses a file holding [row] plus the good sibling; asserts the sibling survived alone. */
    private fun assertRowSkipped(row: String) {
        val p = Fx.ok(Fx.parse(highlightsFile(row, goodJson)))
        assertEquals("the hostile row must not import", 1, p.importable)
        assertEquals("the hostile row must be counted", 1, p.skipped)
        assertEquals(listOf(Fx.uuid(99)), Fx.highlightIds(p))
    }

    private fun assertRowKept(row: String) {
        val p = Fx.ok(Fx.parse(highlightsFile(row, goodJson)))
        assertEquals(2, p.importable)
        assertEquals(0, p.skipped)
    }

    // ---- 1. the id must be a real UUID (C-10, W19) -----------------------------------------

    @Test fun nonUuidId_isSkipped() {
        assertRowSkipped(BackupJson.encode(Fx.highlight("not-a-uuid")))
        assertRowSkipped(BackupJson.encode(Fx.highlight("")))
        assertRowSkipped(BackupJson.encode(Fx.highlight("x".repeat(10_000))))
    }

    @Test fun uuidFormsJavaAcceptsButTheContractDoesNot_areSkipped() {
        // `UUID.fromString` is famously lenient: it parses "1-1-1-1-1" and "0-0-0-0-0" happily,
        // which would let a hostile file set a primary key to an arbitrary short token.
        assertRowSkipped(BackupJson.encode(Fx.highlight("1-1-1-1-1")))
        assertRowSkipped(BackupJson.encode(Fx.highlight("00000000-0000-4000-8000-0000000000")))
        assertRowSkipped(BackupJson.encode(Fx.highlight(Fx.uuid(1) + "0")))
        assertRowSkipped(BackupJson.encode(Fx.highlight(" " + Fx.uuid(1))))
    }

    @Test fun uppercaseUuid_isKept_becauseIosWritesThem() {
        // Swift's `UUID.uuidString` is UPPERCASE, so an iOS-written archive is all-uppercase ids.
        // Rejecting them would break exactly the cross-platform case this feature exists for.
        val upper = "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE"
        val row = BackupJson.encode(Fx.highlight(upper, locator = Fx.locator(charOffset = 7)))
        assertRowKept(row)
    }

    // ---- 2. the book key must be canonical AND the target (C-1) -----------------------------

    @Test fun foreignBookRow_isSkipped_neverApplied() {
        assertRowSkipped(BackupJson.encode(Fx.highlight(Fx.uuid(1), bookKey = Fx.BOOK_B)))
    }

    @Test fun syntacticallyInvalidBookKey_isSkipped_evenWhenItMatchesTheTarget() {
        val bogus = "not-a-canonical-key"
        val row = BackupJson.encode(
            Fx.highlight(Fx.uuid(1), bookKey = bogus, locator = Fx.locator(Fx.BOOK_A), locatorJSON = "{}"),
        )
        val p = Fx.ok(Fx.parse(highlightsFile(row), targetBookKey = bogus))
        assertEquals(0, p.importable)
        assertEquals(1, p.skipped)
    }

    // ---- 3. locatorJSON: bounded, decodable, same book --------------------------------------

    @Test fun locatorJsonOverTheCap_isSkipped() {
        val fat = Fx.locator().copy(textQuote = "q".repeat(5_000))
        val json = BackupJson.encode(fat)
        assertTrue(json.length > AnnotationsImportReader.MAX_LOCATOR_JSON_CHARS)
        assertRowSkipped(BackupJson.encode(Fx.highlight(Fx.uuid(1), locatorJSON = json)))
    }

    @Test fun locatorJsonJustUnderTheCap_isKept() {
        val quoteChars = AnnotationsImportReader.MAX_LOCATOR_JSON_CHARS -
            BackupJson.encode(Fx.locator(charOffset = 11).copy(textQuote = "")).length
        val locator = Fx.locator(charOffset = 11).copy(textQuote = "q".repeat(quoteChars))
        val json = BackupJson.encode(locator)
        assertTrue(json.length <= AnnotationsImportReader.MAX_LOCATOR_JSON_CHARS)
        assertRowKept(BackupJson.encode(Fx.highlight(Fx.uuid(1), locatorJSON = json)))
    }

    @Test fun undecodableLocatorJson_isSkipped() {
        assertRowSkipped(BackupJson.encode(Fx.highlight(Fx.uuid(1), locatorJSON = "not json")))
        assertRowSkipped(BackupJson.encode(Fx.highlight(Fx.uuid(1), locatorJSON = "{}")))
        assertRowSkipped(BackupJson.encode(Fx.highlight(Fx.uuid(1), locatorJSON = "[]")))
    }

    @Test fun deeplyNestedLocatorJson_isSkipped_withoutCrashing() {
        val nested = "[".repeat(2_000) + "]".repeat(2_000)
        assertTrue(nested.length <= AnnotationsImportReader.MAX_LOCATOR_JSON_CHARS)
        assertRowSkipped(BackupJson.encode(Fx.highlight(Fx.uuid(1), locatorJSON = nested)))
    }

    @Test fun locatorPointingAtADifferentBook_isSkipped() {
        // The row claims book A; its locator canonicalises to book B. R-3's persistence-boundary
        // guard, enforced here rather than by tightening `restoreAnnotations` (D-7).
        val row = Fx.highlight(Fx.uuid(1), bookKey = Fx.BOOK_A, locatorJSON = BackupJson.encode(Fx.locator(Fx.BOOK_B)))
        assertRowSkipped(BackupJson.encode(row))
    }

    // ---- 4. the locator must be structurally valid (C-9, W18) -------------------------------

    @Test fun negativeCharOffset_isSkipped() {
        assertRowSkipped(BackupJson.encode(Fx.highlight(Fx.uuid(1), locator = Fx.locator(charOffset = -5))))
    }

    @Test fun negativePage_isSkipped() {
        val bad = Fx.locator(charOffset = null).copy(page = -1)
        assertRowSkipped(BackupJson.encode(Fx.highlight(Fx.uuid(1), locator = bad)))
    }

    @Test fun invertedUtf16Range_isSkipped() {
        val bad = Fx.locator().copy(charRangeStartUTF16 = 10, charRangeEndUTF16 = 5)
        assertRowSkipped(BackupJson.encode(Fx.highlight(Fx.uuid(1), locator = bad)))
    }

    @Test fun halfARange_isSkipped() {
        val bad = Fx.locator().copy(charRangeStartUTF16 = 10, charRangeEndUTF16 = null)
        assertRowSkipped(BackupJson.encode(Fx.highlight(Fx.uuid(1), locator = bad)))
    }

    @Test fun progressionThatOverflowsToInfinity_isSkipped() {
        // `1e400` is legal JSON that becomes a non-finite Double. It must never reach
        // `profileKeyFor`, whose `canonicalJson()` throws on a non-finite progression — so the
        // structural gate has to run BEFORE any profile-key derivation.
        val p = requireNotNull(vreader.contracts.Identity.parseCanonicalKey(Fx.BOOK_A))
        val locatorJson = """{"contentSHA256":"${p.contentSHA256}","fileByteCount":${p.fileByteCount},""" +
            """"format":"${p.format.name}","progression":1e400}"""
        assertRowSkipped(BackupJson.encode(Fx.highlight(Fx.uuid(1), locatorJSON = locatorJson)))
    }

    // ---- 5. text fields are bounded, never truncated -----------------------------------------

    @Test fun fieldOverTheCap_isSkipped_neverTruncated() {
        val over = "t".repeat(AnnotationsImportReader.MAX_FIELD_CHARS + 1)
        assertRowSkipped(BackupJson.encode(Fx.highlight(Fx.uuid(1), selectedText = over)))
        assertRowSkipped(BackupJson.encode(Fx.highlight(Fx.uuid(2), note = over)))
        assertRowSkipped(BackupJson.encode(Fx.highlight(Fx.uuid(3), color = over)))

        val noteFile = """{"schemaVersion":3,"highlights":[],"bookmarks":[],"notes":[""" +
            BackupJson.encode(Fx.note(Fx.uuid(4), content = over)) + "]}"
        assertEquals(0, Fx.ok(Fx.parse(noteFile)).importable)

        val bmFile = """{"schemaVersion":3,"highlights":[],"notes":[],"bookmarks":[""" +
            BackupJson.encode(Fx.bookmark(Fx.uuid(5), title = over)) + "]}"
        assertEquals(0, Fx.ok(Fx.parse(bmFile)).importable)
    }

    @Test fun fieldExactlyAtTheCap_isKept() {
        val atCap = "t".repeat(AnnotationsImportReader.MAX_FIELD_CHARS)
        assertRowKept(BackupJson.encode(Fx.highlight(Fx.uuid(1), selectedText = atCap)))
    }

    // ---- 6. an unknown color folds to the default, it does not fail the row -------------------

    @Test fun unknownColor_keepsTheRow() {
        assertRowKept(BackupJson.encode(Fx.highlight(Fx.uuid(1), color = "chartreuse")))
    }

    // ---- rows that do not even decode are ROW-level, not file-level ---------------------------

    @Test fun rowWithAMalformedTimestamp_isSkipped_siblingsSurvive() {
        val bad = """{"highlightId":"${Fx.uuid(1)}","bookFingerprintKey":"${Fx.BOOK_A}",""" +
            """"locatorJSON":"{}","selectedText":"x","color":"yellow",""" +
            """"createdAt":"not-a-date","updatedAt":"2026-08-05T10:00:00Z"}"""
        assertRowSkipped(bad)
    }

    @Test fun rowMissingRequiredFields_isSkipped_siblingsSurvive() {
        assertRowSkipped("""{"highlightId":"${Fx.uuid(1)}"}""")
        assertRowSkipped("null")
        assertRowSkipped("42")
        assertRowSkipped("[]")
    }

    // ---- the SHARED gate is reached by all three kinds, not only highlights --------------------
    // Gate-4 round 1 (Medium): every case above drives `validLocator` through `keepHighlight`
    // only, so a mutation bypassing it inside `keepNote`/`keepBookmark` would have survived.

    private val goodNote = BackupJson.encode(
        Fx.note(Fx.uuid(98), locator = Fx.locator(charOffset = 998), content = "good"),
    )
    private val goodBookmark = BackupJson.encode(
        Fx.bookmark(Fx.uuid(97), locator = Fx.locator(charOffset = 997), title = "good"),
    )

    private fun notesFile(vararg rows: String) =
        """{"schemaVersion":3,"highlights":[],"bookmarks":[],"notes":[${rows.joinToString(",")}]}"""

    private fun bookmarksFile(vararg rows: String) =
        """{"schemaVersion":3,"highlights":[],"notes":[],"bookmarks":[${rows.joinToString(",")}]}"""

    private fun assertNoteSkipped(row: String, why: String) {
        val p = Fx.ok(Fx.parse(notesFile(row, goodNote)))
        assertEquals(why, 1, p.importable)
        assertEquals(why, listOf(Fx.uuid(98)), Fx.noteIds(p))
    }

    private fun assertBookmarkSkipped(row: String, why: String) {
        val p = Fx.ok(Fx.parse(bookmarksFile(row, goodBookmark)))
        assertEquals(why, 1, p.importable)
        assertEquals(why, listOf(Fx.uuid(97)), Fx.bookmarkIds(p))
    }

    private val fatLocatorJson = BackupJson.encode(Fx.locator().copy(textQuote = "q".repeat(5_000)))

    @Test fun theSharedIdentityAndLocatorGateAppliesToNotes() {
        assertNoteSkipped(BackupJson.encode(Fx.note("not-a-uuid")), "non-uuid id")
        assertNoteSkipped(BackupJson.encode(Fx.note("1-1-1-1-1")), "lenient uuid form")
        assertNoteSkipped(BackupJson.encode(Fx.note(Fx.uuid(1), bookKey = Fx.BOOK_B)), "foreign book")
        assertNoteSkipped(BackupJson.encode(Fx.note(Fx.uuid(2), locatorJSON = "not json")), "undecodable locator")
        assertNoteSkipped(
            BackupJson.encode(Fx.note(Fx.uuid(3), locatorJSON = BackupJson.encode(Fx.locator(Fx.BOOK_B)))),
            "locator points at another book",
        )
        assertNoteSkipped(
            BackupJson.encode(Fx.note(Fx.uuid(4), locator = Fx.locator(charOffset = -5))),
            "structurally invalid locator",
        )
        assertNoteSkipped(BackupJson.encode(Fx.note(Fx.uuid(5), locatorJSON = fatLocatorJson)), "locator over cap")
    }

    @Test fun theSharedIdentityAndLocatorGateAppliesToBookmarks() {
        assertBookmarkSkipped(BackupJson.encode(Fx.bookmark("not-a-uuid")), "non-uuid id")
        assertBookmarkSkipped(BackupJson.encode(Fx.bookmark("1-1-1-1-1")), "lenient uuid form")
        assertBookmarkSkipped(BackupJson.encode(Fx.bookmark(Fx.uuid(1), bookKey = Fx.BOOK_B)), "foreign book")
        assertBookmarkSkipped(BackupJson.encode(Fx.bookmark(Fx.uuid(2), locatorJSON = "not json")), "undecodable locator")
        assertBookmarkSkipped(
            BackupJson.encode(Fx.bookmark(Fx.uuid(3), locatorJSON = BackupJson.encode(Fx.locator(Fx.BOOK_B)))),
            "locator points at another book",
        )
        assertBookmarkSkipped(
            BackupJson.encode(Fx.bookmark(Fx.uuid(4), locator = Fx.locator(charOffset = -5))),
            "structurally invalid locator",
        )
        assertBookmarkSkipped(
            BackupJson.encode(Fx.bookmark(Fx.uuid(5), locatorJSON = fatLocatorJson)),
            "locator over cap",
        )
    }

    // ---- timestamps that decode but cannot be STORED -------------------------------------------

    /** `Instant.MAX`'s second: a legal ISO instant that overflows `toEpochMilli()`. */
    private val extremeInstant = "+1000000000-12-31T23:59:59Z"

    private fun retime(rowJson: String, field: String, value: String): String {
        val from = """"$field":"2026-08-05T10:00:00Z""""
        assertTrue("fixture drift: $rowJson has no $field to replace", rowJson.contains(from))
        return rowJson.replace(from, """"$field":"$value"""")
    }

    @Test fun anInstantThatCannotBecomeEpochMillis_isSkippedForEveryKind() {
        // Gate-4 round 1 (High): such a row decodes cleanly and passes every other gate, so it
        // would be COUNTED as importable and then make `restoreAnnotations.toEpochMilli()` throw —
        // the user approves N and receives an error. Guard the fixture first: if a JDK ever made
        // this convertible, the test must say so rather than silently prove nothing.
        val parsed = java.time.Instant.parse(extremeInstant)
        assertTrue(
            "fixture must actually overflow toEpochMilli()",
            runCatching { parsed.toEpochMilli() }.isFailure,
        )

        val h = BackupJson.encode(Fx.highlight(Fx.uuid(1), locator = Fx.locator(charOffset = 1)))
        assertRowSkipped(retime(h, "createdAt", extremeInstant))
        assertRowSkipped(retime(h, "updatedAt", extremeInstant))

        val n = BackupJson.encode(Fx.note(Fx.uuid(1), locator = Fx.locator(charOffset = 1)))
        assertNoteSkipped(retime(n, "createdAt", extremeInstant), "created overflows")
        assertNoteSkipped(retime(n, "updatedAt", extremeInstant), "updated overflows")

        val b = BackupJson.encode(Fx.bookmark(Fx.uuid(1), locator = Fx.locator(charOffset = 1)))
        assertBookmarkSkipped(retime(b, "createdAt", extremeInstant), "created overflows")
        assertBookmarkSkipped(retime(b, "updatedAt", extremeInstant), "updated overflows")
    }

    @Test fun anOrdinaryPastTimestamp_isKept() {
        // Discrimination partner: the gate must reject only UNSTORABLE instants, not old ones.
        val h = BackupJson.encode(Fx.highlight(Fx.uuid(1), locator = Fx.locator(charOffset = 1)))
        assertRowKept(retime(h, "createdAt", "1970-01-01T00:00:00Z"))
    }

    // ---- A-8: the mixed file, asserted by identity not by count -------------------------------

    @Test fun mixedFile_appliesExactlyTheGoodRows() {
        val good1 = Fx.highlight(Fx.uuid(10), locator = Fx.locator(charOffset = 10))
        val good2 = Fx.highlight(Fx.uuid(11), locator = Fx.locator(charOffset = 11))
        val badId = Fx.highlight("nope", locator = Fx.locator(charOffset = 12))
        val badOffset = Fx.highlight(Fx.uuid(13), locator = Fx.locator(charOffset = -1))
        val badBook = Fx.highlight(Fx.uuid(14), locatorJSON = BackupJson.encode(Fx.locator(Fx.BOOK_B)))

        val text = Fx.envelopeJson(highlights = listOf(badId, good1, badOffset, good2, badBook))
        val p = Fx.ok(Fx.parse(text))

        assertEquals(2, p.importable)
        assertEquals(3, p.skipped)
        assertEquals(listOf(Fx.uuid(10), Fx.uuid(11)), Fx.highlightIds(p))
    }
}
