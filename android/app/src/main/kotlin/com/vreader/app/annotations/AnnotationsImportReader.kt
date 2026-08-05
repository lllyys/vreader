// Purpose: feature #165 WI-3 — THE untrusted-input boundary of annotation import. Turns the bytes
// of a SAF-picked file into an `ImportPreview` whose collapsed envelope is exactly what
// `restoreAnnotations` will insert, or into a typed `ImportFailure`. The file arrives from anywhere
// (a messaging app, a download, a malicious document provider) and is treated as hostile: rule 54.
//
// Key decisions:
//  - PURE. It is handed an already-open stream and the book's current annotation identity, so it
//    holds no `ContentResolver`, no Android type and no blocking-call surface of its own — every
//    provider call lives behind `BoundedCallGate` in the WI-4b controller (§8.1). That is also what
//    keeps it exhaustively testable on the JVM.
//  - It never inflates: at most MAX_IMPORT_JSON_BYTES are read (measured, never taken from a
//    declared size), at most MAX_IMPORT_ROWS rows are examined, nesting is bounded before any
//    recursive parse, and every field is bounded. The #155 `BookMagicSniffer` doctrine: bounded,
//    typed failure, degrade rather than crash.
//  - Two guarantees stated PRECISELY, because the useful version of each is narrower than the
//    slogan (Gate-4 round 1 caught both being overclaimed here):
//      * NO THROW covers malformed BYTES and ordinary stream `Exception`s. A stream that throws an
//        `Error` still propagates, deliberately — a VM-fatal error is not a file we can report on.
//      * TERMINATION holds for every input that makes progress: the byte cap ends an endlessly
//        productive stream, and a TOTAL (not consecutive) zero-read budget ends a stream that
//        spins without producing. It does NOT cover a `read` that simply never returns — that is
//        uninterruptible by construction and is bounded by WI-4b's `BoundedCallGate` around the
//        whole call, which is exactly why that boundary is a separate, separately-audited unit.
//  - TWO-TIER failure taxonomy (C-7). File-level corruption — unparseable, not an annotations
//    envelope, a schemaVersion the contract does not accept, or a cap breach — refuses the WHOLE
//    file. Row-level corruption skips THAT ROW and imports its valid siblings. A row that fails to
//    *decode* is row-level too: each row is decoded from its own JsonElement rather than as part of
//    one all-or-nothing envelope decode, so one bad timestamp cannot cost a user 400 highlights.
//  - Validation lives HERE, not in `restoreAnnotations` (D-7): that seam is shared with WebDAV
//    restore and must not be tightened underneath its existing caller. The envelope handed on is
//    already row-valid, so the repository's own gate becomes a redundant second line.
//  - The emitted envelope is COLLAPSED (§6.4 F-1…F-5) and already-present-filtered, so on an
//    unchanged database `preview.importable` equals the number of rows apply inserts. The count the
//    user approves is the count they get; `skipped` is one honest number covering every reason a
//    row will not land.
//  - Collapse registers a row's keys ONLY when the row is kept. A row dropped for a position
//    collision therefore does not consume its id, and a later legitimate row carrying that id at a
//    different position still imports.
//
// @coordinates-with AnnotationImportModels (the value types), AnnotationsImportApplier (WI-4,
// consumes `ImportPreview.envelope`), AnnotationsIoController (WI-4b, owns the bounded I/O and
// supplies the stream), IncomingBookResolver.sanitizeDisplayName (the shared name sanitizer).
package com.vreader.app.annotations

import com.vreader.app.imports.IncomingBookResolver
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.decodeFromJsonElement
import vreader.contracts.Identity
import vreader.contracts.Locator
import vreader.contracts.backup.BackupAnnotationsEnvelope
import vreader.contracts.backup.BackupBookmark
import vreader.contracts.backup.BackupHighlight
import vreader.contracts.backup.BackupJson
import vreader.contracts.backup.BackupNote
import vreader.contracts.backup.BackupSchema
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.time.Instant

/** Reads a picked `annotations.json` into the preview the user approves. */
object AnnotationsImportReader {

    /** Hard read ceiling. ~10 000 richly annotated rows with headroom; two orders of magnitude
     *  below #155's book cap, because this is text metadata, not a book. */
    const val MAX_IMPORT_JSON_BYTES = 2L * 1024 * 1024

    /** Rows summed across the three kinds; over it the file is refused whole (C-7 tier 1). */
    const val MAX_IMPORT_ROWS = 10_000

    /** Per text field (`selectedText` / `note` / `content` / `title` / `color`). Over it the ROW
     *  fails — never a silent truncation, which would mutate the user's own content. */
    const val MAX_FIELD_CHARS = 10_000

    /** Bounds the inner `locatorJSON` before it reaches a second decode pass. */
    const val MAX_LOCATOR_JSON_CHARS = 4_096

    /**
     * Bracket-nesting ceiling, enforced by a flat scan BEFORE any recursive parse — of the document
     * and of every inner `locatorJSON`. A JSON parser recurses, so 2 MiB of `[` is a StackOverflow,
     * which is an `Error` no `catch (Exception)` converts into a typed failure. The real envelope
     * nests three deep; anything near this bound is already not a file we wrote.
     */
    const val MAX_JSON_DEPTH = 64

    /** The designed preview list is "first three" (`vreader-annotation-import.jsx:496`). */
    const val MAX_SAMPLE_ROWS = 3

    /**
     * TOTAL zero-length reads tolerated across one parse before the stream is declared broken.
     * `read(b, 0, n > 0)` returning 0 violates the `InputStream` contract and a naive loop spins on
     * it forever. The budget is cumulative rather than consecutive on purpose: a *consecutive*
     * counter is reset by a single productive byte, so a stream alternating 1 024 zero reads with
     * one byte would starve the loop indefinitely while never approaching the byte cap.
     */
    private const val MAX_ZERO_READS = 1_024

    private const val READ_CHUNK_BYTES = 8 * 1024

    private val UUID_FORM =
        Regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")

    /**
     * Reads at most [MAX_IMPORT_JSON_BYTES] from [input], decodes the annotations envelope,
     * validates every row against [targetBookKey], collapses intra-file duplicates and drops rows
     * [existing] already has.
     *
     * [fileName] is provider-controlled and is sanitized here as well as at the I/O boundary —
     * sanitization is idempotent, and an untrusted string that reaches a pixel must not depend on
     * one caller remembering. Does not close [input]; its owner does (a bounded call may have to
     * close it off-deadline).
     *
     * Returns a typed [ImportParseResult] for every malformed shape and every ordinary stream
     * failure. See this file's header for the exact limits of the no-throw and termination
     * guarantees — in particular, a `read` that never returns is WI-4b's `BoundedCallGate` to
     * bound, not this function's.
     */
    fun parse(
        input: InputStream,
        fileName: String,
        targetBookKey: String,
        bookTitle: String,
        existing: ExistingAnnotationState,
    ): ImportParseResult = try {
        read(input, fileName, targetBookKey, bookTitle, existing)
    } catch (e: Exception) {
        // The blanket net exists so a shape nobody anticipated degrades instead of crashing the
        // reader activity. Every ANTICIPATED shape is refused by a named branch below, so this arm
        // firing at all is a defect signal, not routine flow. `Error` is deliberately NOT caught
        // here — a StackOverflow is not a file we can report on, and MAX_JSON_DEPTH is what keeps
        // one off this path in the first place.
        ImportParseResult.Failed(ImportFailure.Unreadable)
    }

    private fun read(
        input: InputStream,
        fileName: String,
        targetBookKey: String,
        bookTitle: String,
        existing: ExistingAnnotationState,
    ): ImportParseResult {
        val bytes = when (val outcome = readBounded(input)) {
            is ReadOutcome.Failed -> return ImportParseResult.Failed(outcome.reason)
            is ReadOutcome.Bytes -> outcome.value
        }
        val text = decodeUtf8(bytes)
        if (text.isBlank()) return ImportParseResult.Failed(ImportFailure.Empty)

        if (exceedsDepth(text)) return ImportParseResult.Failed(ImportFailure.NotJson)
        val root = parseOrNull(text) ?: return ImportParseResult.Failed(ImportFailure.NotJson)
        val obj = root as? JsonObject
            ?: return ImportParseResult.Failed(ImportFailure.NotAnAnnotationsFile)

        val schemaVersion = intValue(obj["schemaVersion"])
            ?: return ImportParseResult.Failed(ImportFailure.NotAnAnnotationsFile)
        if (schemaVersion !in BackupSchema.ACCEPTED_SCHEMA_VERSIONS) {
            return ImportParseResult.Failed(ImportFailure.UnsupportedSchema)
        }

        val highlights = obj["highlights"] as? JsonArray
            ?: return ImportParseResult.Failed(ImportFailure.NotAnAnnotationsFile)
        val notes = obj["notes"] as? JsonArray
            ?: return ImportParseResult.Failed(ImportFailure.NotAnAnnotationsFile)
        val bookmarks = obj["bookmarks"] as? JsonArray
            ?: return ImportParseResult.Failed(ImportFailure.NotAnAnnotationsFile)

        val rowCount = highlights.size.toLong() + notes.size + bookmarks.size
        if (rowCount > MAX_IMPORT_ROWS) return ImportParseResult.Failed(ImportFailure.TooManyRows)

        val collapse = Collapse(existing)
        // Fixed kind order — highlights → notes → bookmarks — is what makes cross-kind id collapse
        // (F-2) deterministic rather than dependent on which array the file happens to list first.
        val keptHighlights = highlights.mapNotNull { keepHighlight(it, targetBookKey, collapse) }
        val keptNotes = notes.mapNotNull { keepNote(it, targetBookKey, collapse) }
        val keptBookmarks = bookmarks.mapNotNull { keepBookmark(it, targetBookKey, collapse) }

        val kept = keptHighlights.size + keptNotes.size + keptBookmarks.size
        return ImportParseResult.Ok(
            ImportPreview(
                fileName = IncomingBookResolver.sanitizeDisplayName(fileName, format = null),
                bookKey = targetBookKey,
                bookTitle = bookTitle,
                highlights = keptHighlights.size,
                notes = keptNotes.size,
                bookmarks = keptBookmarks.size,
                skipped = (rowCount - kept).toInt(),
                sample = sample(keptHighlights, keptNotes, keptBookmarks),
                envelope = BackupAnnotationsEnvelope(
                    schemaVersion = schemaVersion,
                    highlights = keptHighlights,
                    bookmarks = keptBookmarks,
                    notes = keptNotes,
                ),
            ),
        )
    }

    // ---- bounded read -------------------------------------------------------------------------

    private sealed interface ReadOutcome {
        class Bytes(val value: ByteArray) : ReadOutcome
        class Failed(val reason: ImportFailure) : ReadOutcome
    }

    private fun readBounded(input: InputStream): ReadOutcome {
        val sink = ByteArrayOutputStream()
        val chunk = ByteArray(READ_CHUNK_BYTES)
        var total = 0L
        var zeroReads = 0
        while (true) {
            val n = try {
                input.read(chunk, 0, chunk.size)
            } catch (e: Exception) {
                return ReadOutcome.Failed(ImportFailure.Unreadable)
            }
            if (n < 0) break
            if (n == 0) {
                if (++zeroReads > MAX_ZERO_READS) {
                    return ReadOutcome.Failed(ImportFailure.Unreadable)
                }
                continue
            }
            total += n
            if (total > MAX_IMPORT_JSON_BYTES) return ReadOutcome.Failed(ImportFailure.TooLarge)
            sink.write(chunk, 0, n)
        }
        return ReadOutcome.Bytes(sink.toByteArray())
    }

    /** UTF-8 with a leading BOM tolerated. Malformed sequences become U+FFFD rather than throwing;
     *  the JSON parse then refuses the file, which is the correct outcome for non-UTF-8 input. */
    private fun decodeUtf8(bytes: ByteArray): String {
        val hasBom = bytes.size >= 3 &&
            bytes[0] == 0xEF.toByte() && bytes[1] == 0xBB.toByte() && bytes[2] == 0xBF.toByte()
        val offset = if (hasBom) 3 else 0
        return String(bytes, offset, bytes.size - offset, Charsets.UTF_8)
    }

    // ---- structural guards ---------------------------------------------------------------------

    /** True when [text] nests deeper than [MAX_JSON_DEPTH]. Brackets inside string literals do not
     *  count, and a backslash escape never ends a string. */
    private fun exceedsDepth(text: String): Boolean {
        var depth = 0
        var inString = false
        var escaped = false
        for (ch in text) {
            if (inString) {
                when {
                    escaped -> escaped = false
                    ch == '\\' -> escaped = true
                    ch == '"' -> inString = false
                }
                continue
            }
            when (ch) {
                '"' -> inString = true
                '{', '[' -> if (++depth > MAX_JSON_DEPTH) return true
                '}', ']' -> depth--
            }
        }
        return false
    }

    /**
     * The document as a JSON tree, or null when it is not JSON.
     *
     * Catches `Exception`, deliberately NOT `Throwable` — and that is what makes [exceedsDepth]
     * load-bearing rather than decorative. `runCatching` here would swallow the StackOverflowError
     * a deeply nested document provokes and quietly report `NotJson`, so the guard could be
     * deleted with every test still green while the reader was one unlucky stack size away from
     * an unrecoverable crash. Mutation testing found exactly that; the fix is here, not in a test.
     */
    private fun parseOrNull(text: String): JsonElement? = try {
        BackupJson.DEFAULT.parseToJsonElement(text)
    } catch (e: Exception) {
        null
    }

    /** The element as an Int, or null when it is absent, a string, a float, or anything else. A
     *  quoted `"3"` must NOT satisfy the contract's `Int` field, though kotlinx would coerce it. */
    private fun intValue(element: JsonElement?): Int? {
        val primitive = element as? JsonPrimitive ?: return null
        if (primitive.isString) return null
        return primitive.content.toIntOrNull()
    }

    // ---- per-row gate + collapse -----------------------------------------------------------------

    private class Collapse(existing: ExistingAnnotationState) {
        private val ids = existing.ids.mapTo(HashSet()) { identityKey(it) }
        private val highlightKeys = HashSet(existing.highlightProfileKeys)
        private val bookmarkKeys = HashSet(existing.bookmarkProfileKeys)

        /** Keys are registered only on a KEPT row, so a row dropped for a position collision does
         *  not burn its id for a later, non-colliding row that carries the same one. */
        fun keepHighlight(id: String, profileKey: String): Boolean {
            if (identityKey(id) in ids || profileKey in highlightKeys) return false
            ids.add(identityKey(id))
            highlightKeys.add(profileKey)
            return true
        }

        /** Notes have no unique index by design (C-4 / F-5): id-only, never position. */
        fun keepNote(id: String): Boolean = ids.add(identityKey(id))

        fun keepBookmark(id: String, profileKey: String): Boolean {
            if (identityKey(id) in ids || profileKey in bookmarkKeys) return false
            ids.add(identityKey(id))
            bookmarkKeys.add(profileKey)
            return true
        }

        companion object {
            /**
             * A UUID's IDENTITY, for collapse purposes only — the wire spelling is never altered.
             *
             * Uppercase ids are accepted because Swift's `UUID.uuidString` is uppercase, so an
             * iOS-written archive is all-uppercase. Comparing those verbatim would let one logical
             * UUID appear twice in a file under two spellings and survive both F-1 and F-2, and
             * would let a differently-cased id slip past the already-present filter — the exact
             * cross-platform case this feature exists for is what makes the hole reachable.
             * Gate-4 round 2 found it.
             *
             * `lowercase()` without a Locale is the locale-INDEPENDENT overload, which keeps the
             * collapse a pure function of the bytes (a Turkish default locale must not change
             * which rows import). Hex digits contain no dotted/dotless I in any case.
             */
            fun identityKey(id: String): String = id.lowercase()
        }
    }

    private fun keepHighlight(el: JsonElement, bookKey: String, collapse: Collapse): BackupHighlight? {
        val row = decodeRow<BackupHighlight>(el) ?: return null
        if (!within(row.selectedText) || !within(row.note) || !within(row.color)) return null
        if (!storableInstants(row.createdAt, row.updatedAt)) return null
        val locator = validLocator(row.highlightId, row.bookFingerprintKey, row.locatorJSON, bookKey)
            ?: return null
        return if (collapse.keepHighlight(row.highlightId, profileKeyFor(bookKey, locator))) row else null
    }

    private fun keepNote(el: JsonElement, bookKey: String, collapse: Collapse): BackupNote? {
        val row = decodeRow<BackupNote>(el) ?: return null
        if (!within(row.content)) return null
        if (!storableInstants(row.createdAt, row.updatedAt)) return null
        validLocator(row.annotationId, row.bookFingerprintKey, row.locatorJSON, bookKey) ?: return null
        return if (collapse.keepNote(row.annotationId)) row else null
    }

    private fun keepBookmark(el: JsonElement, bookKey: String, collapse: Collapse): BackupBookmark? {
        val row = decodeRow<BackupBookmark>(el) ?: return null
        if (!within(row.title)) return null
        if (!storableInstants(row.createdAt, row.updatedAt)) return null
        val locator = validLocator(row.bookmarkId, row.bookFingerprintKey, row.locatorJSON, bookKey)
            ?: return null
        return if (collapse.keepBookmark(row.bookmarkId, profileKeyFor(bookKey, locator))) row else null
    }

    /** Each row is decoded from its OWN element, so one bad row is a skip and not a lost file.
     *  `Exception` only, for [parseOrNull]'s reason. */
    private inline fun <reified T> decodeRow(el: JsonElement): T? = try {
        BackupJson.DEFAULT.decodeFromJsonElement<T>(el)
    } catch (e: Exception) {
        null
    }

    private fun within(value: String?): Boolean = (value?.length ?: 0) <= MAX_FIELD_CHARS

    /**
     * Both timestamps must survive the epoch-millis conversion the persistence path performs.
     *
     * `Instant` spans years ±1 000 000 000, but the Room columns are epoch millis and
     * `restoreAnnotations` calls `toEpochMilli()` on every kept row — which THROWS
     * `ArithmeticException` outside the `Long` millisecond range. Without this gate a row bearing
     * `"+1000000000-12-31T23:59:59Z"` decodes cleanly, passes every other check, is counted in
     * `importable`, and then blows up the apply for the WHOLE file. That is a worse preview/apply
     * divergence than inserting fewer rows: the user approves N and receives an error. Gate-4
     * round 1 found it; the fix belongs here, at the boundary, not in the shared restore seam.
     */
    private fun storableInstants(createdAt: Instant, updatedAt: Instant): Boolean = try {
        createdAt.toEpochMilli()
        updatedAt.toEpochMilli()
        true
    } catch (e: ArithmeticException) {
        false
    }

    /**
     * §8.3 — the row's identity and position gate. Order is load-bearing: the structural
     * `validate()` runs BEFORE any caller derives a profile key, because `profileKeyFor` hashes
     * `canonicalJson()`, which throws on a non-finite progression.
     */
    private fun validLocator(
        id: String,
        rowBookKey: String,
        locatorJSON: String,
        targetBookKey: String,
    ): Locator? {
        if (!UUID_FORM.matches(id)) return null
        if (rowBookKey != targetBookKey) return null
        if (Identity.parseCanonicalKey(rowBookKey) == null) return null
        if (locatorJSON.length > MAX_LOCATOR_JSON_CHARS) return null
        if (exceedsDepth(locatorJSON)) return null
        val locator = decodeLocator(locatorJSON) ?: return null
        if (locator.fingerprintKey != rowBookKey) return null
        if (locator.validate() != null) return null
        return locator
    }

    private fun decodeLocator(json: String): Locator? = try {
        BackupJson.decode<Locator>(json)
    } catch (e: Exception) {
        null
    }

    // ---- the designed sample --------------------------------------------------------------------

    private fun sample(
        highlights: List<BackupHighlight>,
        notes: List<BackupNote>,
        bookmarks: List<BackupBookmark>,
    ): List<ImportPreviewRow> {
        val rows = ArrayList<ImportPreviewRow>(MAX_SAMPLE_ROWS)
        for (h in highlights) {
            if (rows.size == MAX_SAMPLE_ROWS) return rows
            // The wire color is provider-controlled; resolve it to a known palette key here so no
            // unvalidated string can drive the sheet's dot (the restore path's own fallback).
            rows.add(
                ImportPreviewRow(
                    (AnnotationColor.from(h.color) ?: AnnotationColor.DEFAULT).key,
                    h.selectedText,
                ),
            )
        }
        for (n in notes) {
            if (rows.size == MAX_SAMPLE_ROWS) return rows
            rows.add(ImportPreviewRow(null, n.content))
        }
        for (b in bookmarks) {
            if (rows.size == MAX_SAMPLE_ROWS) return rows
            rows.add(ImportPreviewRow(null, b.title.orEmpty()))
        }
        return rows
    }
}
