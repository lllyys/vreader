package com.vreader.app.annotations

import vreader.contracts.Identity
import vreader.contracts.Locator
import vreader.contracts.backup.BackupAnnotationsEnvelope
import vreader.contracts.backup.BackupBookmark
import vreader.contracts.backup.BackupHighlight
import vreader.contracts.backup.BackupJson
import vreader.contracts.backup.BackupNote
import vreader.contracts.backup.BackupSchema
import java.io.ByteArrayInputStream
import java.io.IOException
import java.io.InputStream
import java.time.Instant

/**
 * Feature #165 WI-3 — shared fixtures for the `AnnotationsImportReader` suites.
 *
 * Every hostile control character is built from a CODE POINT (`0x0000.toChar()`), never written as
 * a raw literal: a sibling lane found that writing such literals through a file-writing tool can
 * emit real NUL bytes into the source, silently, with the tests still passing for the wrong reason.
 */
internal object Fx {

    val BOOK_A = "epub:" + "a".repeat(64) + ":1000"
    val BOOK_B = "txt:" + "b".repeat(64) + ":2000"

    val T0: Instant = Instant.parse("2026-08-05T10:00:00Z")

    /** A well-formed v4 UUID string, distinct per [n]. */
    fun uuid(n: Int): String = "00000000-0000-4000-8000-" + n.toString().padStart(12, '0')

    /** A locator whose `fingerprintKey` equals [bookKey] by construction. */
    fun locator(
        bookKey: String = BOOK_A,
        charOffset: Int? = 1,
        href: String? = null,
        progression: Double? = null,
    ): Locator {
        val p = requireNotNull(Identity.parseCanonicalKey(bookKey)) { "bad fixture key $bookKey" }
        return Locator(
            contentSHA256 = p.contentSHA256,
            fileByteCount = p.fileByteCount,
            format = p.format.name,
            href = href,
            progression = progression,
            charOffsetUTF16 = charOffset,
        )
    }

    fun highlight(
        id: String,
        bookKey: String = BOOK_A,
        locator: Locator = locator(bookKey),
        selectedText: String = "selected",
        color: String = "yellow",
        note: String? = null,
        locatorJSON: String = BackupJson.encode(locator),
    ) = BackupHighlight(
        highlightId = id,
        bookFingerprintKey = bookKey,
        locatorJSON = locatorJSON,
        selectedText = selectedText,
        color = color,
        note = note,
        createdAt = T0,
        updatedAt = T0,
    )

    fun note(
        id: String,
        bookKey: String = BOOK_A,
        locator: Locator = locator(bookKey),
        content: String = "content",
        locatorJSON: String = BackupJson.encode(locator),
    ) = BackupNote(
        annotationId = id,
        bookFingerprintKey = bookKey,
        locatorJSON = locatorJSON,
        content = content,
        createdAt = T0,
        updatedAt = T0,
    )

    fun bookmark(
        id: String,
        bookKey: String = BOOK_A,
        locator: Locator = locator(bookKey),
        title: String? = "title",
        locatorJSON: String = BackupJson.encode(locator),
    ) = BackupBookmark(
        bookmarkId = id,
        bookFingerprintKey = bookKey,
        locatorJSON = locatorJSON,
        title = title,
        createdAt = T0,
        updatedAt = T0,
    )

    /** The real contract text for an envelope built from typed rows. */
    fun envelopeJson(
        highlights: List<BackupHighlight> = emptyList(),
        notes: List<BackupNote> = emptyList(),
        bookmarks: List<BackupBookmark> = emptyList(),
        schemaVersion: Int = BackupSchema.CURRENT_SCHEMA_VERSION,
    ): String = BackupJson.encode(
        BackupAnnotationsEnvelope(
            schemaVersion = schemaVersion,
            highlights = highlights,
            bookmarks = bookmarks,
            notes = notes,
        ),
    )

    fun stream(text: String): InputStream = ByteArrayInputStream(text.toByteArray(Charsets.UTF_8))

    fun stream(bytes: ByteArray): InputStream = ByteArrayInputStream(bytes)

    /** Parses [text] as one book-A import against an empty database. */
    fun parse(
        text: String,
        existing: ExistingAnnotationState = ExistingAnnotationState.EMPTY,
        fileName: String = "annotations.json",
        targetBookKey: String = BOOK_A,
    ): ImportParseResult = AnnotationsImportReader.parse(
        input = stream(text),
        fileName = fileName,
        targetBookKey = targetBookKey,
        bookTitle = "A Book",
        existing = existing,
    )

    fun ok(result: ImportParseResult): ImportPreview =
        (result as? ImportParseResult.Ok)?.preview
            ?: error("expected Ok, got $result")

    fun failure(result: ImportParseResult): ImportFailure =
        (result as? ImportParseResult.Failed)?.reason
            ?: error("expected Failed, got $result")

    /** The surviving highlight ids of an `Ok` result, in emitted order. */
    fun highlightIds(preview: ImportPreview): List<String> =
        preview.envelope.highlights.map { it.highlightId }

    fun noteIds(preview: ImportPreview): List<String> =
        preview.envelope.notes.map { it.annotationId }

    fun bookmarkIds(preview: ImportPreview): List<String> =
        preview.envelope.bookmarks.map { it.bookmarkId }

    /** A single code point as a String — never a raw control-character literal in source. */
    fun cp(code: Int): String = String(Character.toChars(code))

    /**
     * A stream that yields one byte after every [zerosPerByte] contract-violating zero reads, and
     * never ends. It defeats a CONSECUTIVE zero-read counter (each byte resets it) while never
     * approaching the byte cap — the starvation shape a total budget is needed for.
     */
    fun starvingStream(zerosPerByte: Int = 1_024): InputStream = object : InputStream() {
        private var sinceByte = 0
        override fun read(): Int = 0x20
        override fun read(b: ByteArray, off: Int, len: Int): Int {
            if (sinceByte < zerosPerByte) {
                sinceByte++
                return 0
            }
            sinceByte = 0
            b[off] = 0x20
            return 1
        }
    }

    /** A stream whose first read throws — the "provider died mid-transfer" shape. */
    fun throwingStream(): InputStream = object : InputStream() {
        override fun read(): Int = throw IOException("boom")
        override fun read(b: ByteArray, off: Int, len: Int): Int = throw IOException("boom")
    }

    /**
     * A stream that forever returns 0 from a non-empty read — a contract violation a hostile or
     * buggy provider can produce, and an infinite spin for any naive `while (n >= 0)` loop.
     */
    fun zeroForeverStream(): InputStream = object : InputStream() {
        override fun read(): Int = 0
        override fun read(b: ByteArray, off: Int, len: Int): Int = 0
    }
}
