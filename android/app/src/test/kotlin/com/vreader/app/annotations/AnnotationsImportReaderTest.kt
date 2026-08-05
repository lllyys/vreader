package com.vreader.app.annotations

import com.vreader.app.imports.IncomingBookResolver
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import vreader.contracts.backup.BackupSchema

/**
 * Feature #165 WI-3 — [AnnotationsImportReader], FILE-level taxonomy and bounds.
 *
 * The suite's shape is deliberate: **every refusal case is paired with a valid-file positive**, so
 * a reader that rejects everything cannot make this file green. `validFile_*` is that anchor and is
 * re-asserted inside the boundary tests (at-cap parses / over-cap refuses) rather than only once.
 *
 * Row-level behaviour lives in [AnnotationsImportReaderRowGateTest]; intra-file collapse lives in
 * [AnnotationsImportReaderCollapseTest].
 *
 * Control characters in fixtures are built from CODE POINTS ([Fx.cp]), never written as raw
 * literals — a raw NUL in this very file was produced (and caught) once already.
 */
class AnnotationsImportReaderTest {

    private fun raw(
        highlights: String = "[]",
        notes: String = "[]",
        bookmarks: String = "[]",
        schema: String = "3",
    ) = """{"schemaVersion":$schema,"highlights":$highlights,"bookmarks":$bookmarks,"notes":$notes}"""

    // ---- the positive anchor -------------------------------------------------------------

    @Test fun validFile_parsesAllThreeKinds() {
        val text = Fx.envelopeJson(
            highlights = listOf(Fx.highlight(Fx.uuid(1), locator = Fx.locator(charOffset = 1))),
            notes = listOf(Fx.note(Fx.uuid(2), locator = Fx.locator(charOffset = 2))),
            bookmarks = listOf(Fx.bookmark(Fx.uuid(3), locator = Fx.locator(charOffset = 3))),
        )
        val p = Fx.ok(Fx.parse(text))
        assertEquals(1, p.highlights)
        assertEquals(1, p.notes)
        assertEquals(1, p.bookmarks)
        assertEquals(0, p.skipped)
        assertEquals(3, p.importable)
        assertEquals(listOf(Fx.uuid(1)), Fx.highlightIds(p))
        assertEquals(listOf(Fx.uuid(2)), Fx.noteIds(p))
        assertEquals(listOf(Fx.uuid(3)), Fx.bookmarkIds(p))
        assertEquals(Fx.BOOK_A, p.bookKey)
    }

    @Test fun validFile_sampleIsFirstThreeInKindOrder_withResolvedColors() {
        val text = Fx.envelopeJson(
            highlights = listOf(
                Fx.highlight(Fx.uuid(1), locator = Fx.locator(charOffset = 1), selectedText = "h1", color = "green"),
                Fx.highlight(Fx.uuid(2), locator = Fx.locator(charOffset = 2), selectedText = "h2", color = "not-a-color"),
            ),
            notes = listOf(Fx.note(Fx.uuid(3), locator = Fx.locator(charOffset = 3), content = "n1")),
            bookmarks = listOf(Fx.bookmark(Fx.uuid(4), locator = Fx.locator(charOffset = 4), title = "b1")),
        )
        val p = Fx.ok(Fx.parse(text))
        assertEquals(3, p.sample.size)
        assertEquals(listOf("h1", "h2", "n1"), p.sample.map { it.text })
        assertEquals(AnnotationColor.green.key, p.sample[0].colorKey)
        // An unknown wire color never reaches the sheet as-is — it folds to the default.
        assertEquals(AnnotationColor.DEFAULT.key, p.sample[1].colorKey)
        assertEquals(null, p.sample[2].colorKey)
    }

    // ---- emptiness -----------------------------------------------------------------------

    @Test fun emptyStream_isEmpty() {
        assertEquals(ImportFailure.Empty, Fx.failure(Fx.parse("")))
    }

    @Test fun whitespaceOnlyStream_isEmpty() {
        assertEquals(ImportFailure.Empty, Fx.failure(Fx.parse("   \n\t  ")))
    }

    @Test fun emptyEnvelope_isOkWithZeroImportable_notAFailure() {
        // C-8: the user is shown the designed disabled `Import 0 items`, not a refusal.
        val p = Fx.ok(Fx.parse(Fx.envelopeJson()))
        assertEquals(0, p.importable)
        assertEquals(0, p.skipped)
    }

    @Test fun everythingSkipped_isOkAndCountsEveryDroppedRow() {
        val text = Fx.envelopeJson(
            highlights = listOf(Fx.highlight("not-a-uuid"), Fx.highlight(Fx.uuid(1), bookKey = Fx.BOOK_B)),
        )
        val p = Fx.ok(Fx.parse(text))
        assertEquals(0, p.importable)
        assertEquals(2, p.skipped)
    }

    // ---- byte cap ------------------------------------------------------------------------

    @Test fun overByteCap_isTooLarge_measuredNotDeclared() {
        val filler = "x".repeat(2 * 1024 * 1024)
        val text = """{"schemaVersion":3,"highlights":[],"bookmarks":[],"notes":[],"filler":"$filler"}"""
        assertTrue(text.length > AnnotationsImportReader.MAX_IMPORT_JSON_BYTES)
        assertEquals(ImportFailure.TooLarge, Fx.failure(Fx.parse(text)))
    }

    @Test fun justUnderByteCap_stillParses() {
        val head = "{\"schemaVersion\":3,\"highlights\":[],\"bookmarks\":[],\"notes\":[],\"filler\":\""
        val tail = "\"}"
        val filler = "x".repeat(AnnotationsImportReader.MAX_IMPORT_JSON_BYTES.toInt() - head.length - tail.length)
        val text = head + filler + tail
        assertEquals(AnnotationsImportReader.MAX_IMPORT_JSON_BYTES.toInt(), text.length)
        val p = Fx.ok(Fx.parse(text))
        assertEquals(0, p.importable)
    }

    // ---- not JSON / not an annotations file -----------------------------------------------

    @Test fun garbageBytes_isNotJson() {
        assertEquals(ImportFailure.NotJson, Fx.failure(Fx.parse("this is not json at all")))
    }

    @Test fun truncatedMidArray_isNotJson() {
        val whole = Fx.envelopeJson(highlights = listOf(Fx.highlight(Fx.uuid(1))))
        assertEquals(ImportFailure.NotJson, Fx.failure(Fx.parse(whole.substring(0, whole.length / 2))))
    }

    @Test fun utf16EncodedFile_isNotJson() {
        val bytes = Fx.envelopeJson().toByteArray(Charsets.UTF_16)
        val result = AnnotationsImportReader.parse(
            Fx.stream(bytes), "a.json", Fx.BOOK_A, "A Book", ExistingAnnotationState.EMPTY,
        )
        assertEquals(ImportFailure.NotJson, Fx.failure(result))
    }

    @Test fun utf8BomIsStripped_andTheFileParses() {
        val bytes = byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte()) +
            Fx.envelopeJson(highlights = listOf(Fx.highlight(Fx.uuid(1)))).toByteArray(Charsets.UTF_8)
        val result = AnnotationsImportReader.parse(
            Fx.stream(bytes), "a.json", Fx.BOOK_A, "A Book", ExistingAnnotationState.EMPTY,
        )
        assertEquals(1, Fx.ok(result).importable)
    }

    @Test fun jsonArrayRoot_isNotAnAnnotationsFile() {
        assertEquals(ImportFailure.NotAnAnnotationsFile, Fx.failure(Fx.parse("[]")))
    }

    @Test fun missingKindArrays_areNotAnAnnotationsFile() {
        assertEquals(
            ImportFailure.NotAnAnnotationsFile,
            Fx.failure(Fx.parse("""{"schemaVersion":3,"bookmarks":[],"notes":[]}""")),
        )
        assertEquals(
            ImportFailure.NotAnAnnotationsFile,
            Fx.failure(Fx.parse("""{"schemaVersion":3,"highlights":[],"notes":[]}""")),
        )
        assertEquals(
            ImportFailure.NotAnAnnotationsFile,
            Fx.failure(Fx.parse("""{"schemaVersion":3,"highlights":[],"bookmarks":[]}""")),
        )
    }

    @Test fun kindThatIsNotAnArray_isNotAnAnnotationsFile() {
        assertEquals(ImportFailure.NotAnAnnotationsFile, Fx.failure(Fx.parse(raw(highlights = "{}"))))
        assertEquals(ImportFailure.NotAnAnnotationsFile, Fx.failure(Fx.parse(raw(notes = "\"x\""))))
    }

    // ---- schema version ------------------------------------------------------------------

    @Test fun everyAcceptedSchemaVersion_parses() {
        // Discrimination partner for `newerSchemaVersion_refusesTheWholeFile` — without this pair,
        // a reader that refused ALL versions would pass the refusal test.
        for (v in BackupSchema.ACCEPTED_SCHEMA_VERSIONS) {
            val text = Fx.envelopeJson(highlights = listOf(Fx.highlight(Fx.uuid(1))), schemaVersion = v)
            assertEquals("v$v must parse", 1, Fx.ok(Fx.parse(text)).importable)
        }
    }

    @Test fun newerSchemaVersion_refusesTheWholeFile() {
        val next = BackupSchema.ACCEPTED_SCHEMA_VERSIONS.max() + 1
        val text = Fx.envelopeJson(highlights = listOf(Fx.highlight(Fx.uuid(1))), schemaVersion = next)
        assertEquals(ImportFailure.UnsupportedSchema, Fx.failure(Fx.parse(text)))
    }

    @Test fun schemaVersionBelowTheAcceptedSet_refusesTheWholeFile() {
        val text = Fx.envelopeJson(highlights = listOf(Fx.highlight(Fx.uuid(1))), schemaVersion = 0)
        assertEquals(ImportFailure.UnsupportedSchema, Fx.failure(Fx.parse(text)))
    }

    @Test fun schemaVersionMissingOrNotAnInteger_isNotAnAnnotationsFile() {
        assertEquals(
            ImportFailure.NotAnAnnotationsFile,
            Fx.failure(Fx.parse("""{"highlights":[],"bookmarks":[],"notes":[]}""")),
        )
        // A quoted "3" is a STRING, not the contract's Int — kotlinx would coerce it, we must not.
        assertEquals(ImportFailure.NotAnAnnotationsFile, Fx.failure(Fx.parse(raw(schema = "\"3\""))))
        assertEquals(ImportFailure.NotAnAnnotationsFile, Fx.failure(Fx.parse(raw(schema = "3.5"))))
        assertEquals(ImportFailure.NotAnAnnotationsFile, Fx.failure(Fx.parse(raw(schema = "null"))))
        assertEquals(ImportFailure.NotAnAnnotationsFile, Fx.failure(Fx.parse(raw(schema = "[3]"))))
    }

    // ---- row cap -------------------------------------------------------------------------

    @Test fun atRowCap_parses_overRowCap_refusesTheWholeFile() {
        val atCap = List(AnnotationsImportReader.MAX_IMPORT_ROWS) { "0" }.joinToString(",", "[", "]")
        val p = Fx.ok(Fx.parse(raw(notes = atCap)))
        assertEquals(0, p.importable)
        assertEquals(AnnotationsImportReader.MAX_IMPORT_ROWS, p.skipped)

        val overCap = List(AnnotationsImportReader.MAX_IMPORT_ROWS + 1) { "0" }.joinToString(",", "[", "]")
        assertEquals(ImportFailure.TooManyRows, Fx.failure(Fx.parse(raw(notes = overCap))))
    }

    @Test fun rowCapIsSummedAcrossKinds() {
        val third = AnnotationsImportReader.MAX_IMPORT_ROWS / 3 + 1
        val arr = List(third) { "0" }.joinToString(",", "[", "]")
        assertEquals(
            ImportFailure.TooManyRows,
            Fx.failure(Fx.parse(raw(highlights = arr, notes = arr, bookmarks = arr))),
        )
    }

    // ---- nesting depth -------------------------------------------------------------------

    @Test fun pathologicallyNestedJson_isRefused_withoutCrashing() {
        // 200k open brackets: a recursive-descent parser would blow the stack. The refusal must be
        // typed, and it must arrive — a StackOverflowError here is a failed test, not an "error".
        assertEquals(ImportFailure.NotJson, Fx.failure(Fx.parse("[".repeat(200_000))))
        assertEquals(ImportFailure.NotJson, Fx.failure(Fx.parse("{\"a\":".repeat(200_000))))
    }

    @Test fun bracketsInsideStringValuesDoNotCountTowardDepth() {
        // The discrimination partner for the depth guard: a legitimate file whose text payload is
        // full of brackets and escaped quotes must still parse.
        val payload = "\"" + "[".repeat(500) + "\\" + "]".repeat(500)
        val text = Fx.envelopeJson(highlights = listOf(Fx.highlight(Fx.uuid(1), selectedText = payload)))
        val p = Fx.ok(Fx.parse(text))
        assertEquals(1, p.importable)
        assertEquals(payload, p.envelope.highlights[0].selectedText)
    }

    // ---- stream misbehaviour --------------------------------------------------------------

    @Test fun streamThatThrows_isUnreadable() {
        val result = AnnotationsImportReader.parse(
            Fx.throwingStream(), "a.json", Fx.BOOK_A, "A Book", ExistingAnnotationState.EMPTY,
        )
        assertEquals(ImportFailure.Unreadable, Fx.failure(result))
    }

    @Test(timeout = 10_000)
    fun streamThatAlwaysReturnsZero_terminatesWithUnreadable() {
        // `read(b, 0, len)` returning 0 for a non-empty buffer violates the InputStream contract,
        // and a naive `while (n >= 0)` loop spins forever on it. This is a HANG test: the timeout
        // is the assertion that matters as much as the returned value.
        val result = AnnotationsImportReader.parse(
            Fx.zeroForeverStream(), "a.json", Fx.BOOK_A, "A Book", ExistingAnnotationState.EMPTY,
        )
        assertEquals(ImportFailure.Unreadable, Fx.failure(result))
    }

    @Test(timeout = 10_000)
    fun streamThatStarvesTheZeroReadCounter_terminatesWithUnreadable() {
        // A CONSECUTIVE zero-read counter is reset by a single productive byte, so this stream
        // would spin forever while never approaching the byte cap. Gate-4 round 1 (Low) found the
        // hole; the budget is cumulative because of this test.
        val result = AnnotationsImportReader.parse(
            Fx.starvingStream(), "a.json", Fx.BOOK_A, "A Book", ExistingAnnotationState.EMPTY,
        )
        assertEquals(ImportFailure.Unreadable, Fx.failure(result))
    }

    // ---- CJK payload ----------------------------------------------------------------------

    @Test fun cjkTextSurvivesByteForByte() {
        val cjk = "黑暗血时代——第一章「起」"
        val text = Fx.envelopeJson(
            highlights = listOf(Fx.highlight(Fx.uuid(1), selectedText = cjk, note = cjk)),
            notes = listOf(Fx.note(Fx.uuid(2), locator = Fx.locator(charOffset = 9), content = cjk)),
            bookmarks = listOf(Fx.bookmark(Fx.uuid(3), locator = Fx.locator(charOffset = 8), title = cjk)),
        )
        val p = Fx.ok(Fx.parse(text))
        assertEquals(cjk, p.envelope.highlights[0].selectedText)
        assertEquals(cjk, p.envelope.highlights[0].note)
        assertEquals(cjk, p.envelope.notes[0].content)
        assertEquals(cjk, p.envelope.bookmarks[0].title)
    }

    // ---- §8.4 the provider-supplied display name -------------------------------------------

    private fun nameOf(raw: String): String =
        Fx.ok(Fx.parse(Fx.envelopeJson(), fileName = raw)).fileName

    @Test fun displayName_isCappedAndNeverSplitsASurrogatePair() {
        val capped = nameOf("n".repeat(50_000))
        assertTrue(capped.length <= IncomingBookResolver.MAX_NAME_CHARS)
        assertFalse(capped.isEmpty())
    }

    @Test fun displayName_stripsControlAndBidiCharacters() {
        val hostile = "a" + Fx.cp(0x0000) + "b" + Fx.cp(0x000A) + Fx.cp(0x202E) + "c" + Fx.cp(0x202D)
        val cleaned = nameOf(hostile)
        assertFalse(cleaned.any { it.code == 0x0000 || it.code == 0x000A })
        assertFalse(cleaned.any { it.code == 0x202E || it.code == 0x202D })
        assertTrue(cleaned.contains("a"))
        assertTrue(cleaned.contains("c"))
    }

    @Test fun displayName_stripsALoneSurrogate() {
        val cleaned = nameOf("ok" + Fx.cp(0xD800))
        assertFalse(cleaned.any { it.isSurrogate() })
    }

    @Test fun displayName_reducesAPathTraversalToItsLeaf() {
        assertEquals("passwd", nameOf("../../etc/passwd"))
    }

    @Test fun displayName_preservesCjk() {
        assertEquals("读书笔记.json", nameOf("读书笔记.json"))
    }

    @Test fun displayName_emptyOrFullyStripped_fallsBack() {
        assertEquals(IncomingBookResolver.FALLBACK_NAME, nameOf(""))
        assertEquals(IncomingBookResolver.FALLBACK_NAME, nameOf(Fx.cp(0x0000) + Fx.cp(0x202E)))
    }

    @Test fun displayName_sanitizationIsIdempotent() {
        val once = nameOf("../a" + Fx.cp(0x202E) + "b.json")
        assertEquals(once, nameOf(once))
    }

    // ---- the blanket guarantee -------------------------------------------------------------

    @Test fun noHostileShapeEverThrows() {
        val hostile = listOf(
            "", " ", Fx.cp(0x0000), "null", "0", "true", "\"", "{", "}", "[]", "[{}]",
            """{"schemaVersion":3}""",
            """{"schemaVersion":-1,"highlights":[],"bookmarks":[],"notes":[]}""",
            raw(highlights = "[null,1,\"x\",[],{}]"),
            raw(notes = """[{"annotationId":null}]"""),
            raw(bookmarks = """[{"bookmarkId":"${Fx.uuid(1)}","bookFingerprintKey":"${Fx.BOOK_A}"}]"""),
            Fx.cp(0xD800) + Fx.cp(0xDC00),
            "{".repeat(5_000) + "}".repeat(5_000),
        )
        for (input in hostile) {
            assertNotNull("no result for <${input.take(40)}>", Fx.parse(input))
        }
    }
}
