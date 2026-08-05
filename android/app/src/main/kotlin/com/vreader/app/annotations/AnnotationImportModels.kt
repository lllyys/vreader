// Purpose: feature #165 WI-3 — the pure value types of the annotations-import boundary: the
// preview a user approves, the identity state that defines "already present", and the typed
// failure taxonomy. No Android dependency, no I/O — every one of these is constructed by
// `AnnotationsImportReader` from bytes that arrived through SAF from anywhere.
//
// Key decisions:
//  - The failure taxonomy is TWO-TIERED and the tier is a property of the case, not of the caller:
//    every value here is a FILE-level refusal (nothing is applied). ROW-level corruption never
//    produces an `ImportFailure` — it lands in `ImportPreview.skipped`, so a mixed file still
//    imports its good rows. C-7.
//  - `ImportFailure.userMessage` reuses the ALREADY-SHIPPED SAF-import copy verbatim
//    (`MainActivity.importFailureMessage`) and introduces NO new user-facing string. Rule 51: the
//    committed design (`vreader-annotation-import.jsx:477-484`) draws the error blob but supplies
//    no copy for it, and #155 set the precedent that a distinguishable-but-undesigned outcome
//    reports the generic shipped failure copy rather than a bespoke invented one. The consequence
//    is deliberate and stated: TooLarge / NotJson / UnsupportedSchema / TooManyRows are not
//    distinguishable to the user today.
//  - `ImportPreview.envelope` is the COLLAPSED, validated, already-present-filtered payload — the
//    exact input `restoreAnnotations` will be handed. It is `internal` so no UI layer can rebuild
//    a different envelope from the displayed counts: the number the user approves and the number
//    apply inserts are the same object's two views (§6.4, invariant A-11).
//
// @coordinates-with AnnotationsImportReader (the only producer), AnnotationsImportApplier (WI-4,
// the only consumer of `envelope`), AnnotationImportPreviewSheet (WI-5, renders the counts).
package com.vreader.app.annotations

import vreader.contracts.backup.BackupAnnotationsEnvelope

/**
 * One row of the designed "Preview · first three" list: the color dot plus the text this row
 * actually carries (a highlight's selected text, a note's content, a bookmark's title).
 *
 * [colorKey] is an ALREADY-RESOLVED [AnnotationColor.key], never the raw wire string — an unknown
 * provider-supplied color has been folded to [AnnotationColor.DEFAULT] before it reaches here, so
 * no unvalidated text can drive a rendering decision. Null for kinds that have no color.
 */
data class ImportPreviewRow(val colorKey: String?, val text: String)

/**
 * What the user is asked to approve. Every count describes the file AFTER validation, intra-file
 * collapse and the already-present filter, so on an unchanged database applying [envelope] inserts
 * exactly [importable] rows (§6.4).
 *
 * [fileName] is provider-controlled and is ALWAYS sanitized (§8.4) before it lands here.
 * [skipped] is one honest number covering every reason a row will not land: it decoded wrong, it
 * failed a validation gate, it collided with another row in the same file, or the database already
 * has it.
 */
data class ImportPreview(
    val fileName: String,
    val bookKey: String,
    val bookTitle: String,
    val highlights: Int,
    val notes: Int,
    val bookmarks: Int,
    val skipped: Int,
    val sample: List<ImportPreviewRow>,
    internal val envelope: BackupAnnotationsEnvelope,
) {
    /** Rows that WILL be inserted — the count the designed primary button names. */
    val importable: Int get() = highlights + notes + bookmarks
}

/**
 * A FILE-level refusal: nothing is applied, and the designed error blob is what the user sees.
 *
 * `Timeout`, `Busy` and `BookMissing` are produced by the I/O boundary (WI-4b) and the applier
 * (WI-4) rather than by the reader; they live here because the taxonomy is one shared vocabulary
 * for the whole feature, not per-layer.
 */
enum class ImportFailure {
    /** The document contained no bytes (or only whitespace). */
    Empty,

    /** Over `AnnotationsImportReader.MAX_IMPORT_JSON_BYTES` — measured, never trusted from the
     *  provider's declared size. */
    TooLarge,

    /** Not parseable as JSON at all, or nested past the depth bound. */
    NotJson,

    /** Valid JSON, but not an annotations envelope (not an object, no usable `schemaVersion`, or a
     *  missing/non-array `highlights`/`notes`/`bookmarks`). */
    NotAnAnnotationsFile,

    /** `schemaVersion` is outside `BackupSchema.ACCEPTED_SCHEMA_VERSIONS`. The contract promises
     *  BACKWARD compatibility only, so a newer file is refused whole rather than partially read. */
    UnsupportedSchema,

    /** More than `AnnotationsImportReader.MAX_IMPORT_ROWS` rows summed across the three kinds. */
    TooManyRows,

    /** The stream failed, misbehaved, or the read could not complete. */
    Unreadable,

    /** A bounded provider call passed its deadline (WI-4b). */
    Timeout,

    /** The app-wide abandoned-call budget is exhausted (WI-4b). */
    Busy,

    /** The target book is no longer in the library (WI-4, C-5b). */
    BookMissing,
    ;

    /**
     * Fixed user-facing text — never echoes a path, a provider detail or the file name (rule 50
     * §6). Both strings are the shipped SAF-import copy (`MainActivity.importFailureMessage`),
     * reused verbatim; see this file's header for why no new copy is introduced here.
     */
    val userMessage: String
        get() = when (this) {
            Unreadable, Timeout, Busy -> "Couldn't open the file"
            Empty, TooLarge, NotJson, NotAnAnnotationsFile,
            UnsupportedSchema, TooManyRows, BookMissing,
            -> "Import failed"
        }
}

/** The outcome of reading a picked annotations file. */
sealed interface ImportParseResult {
    /** The file is importable — possibly with `preview.importable == 0` (C-8), which the designed
     *  sheet renders as a disabled `Import 0 items` rather than as a failure. */
    data class Ok(val preview: ImportPreview) : ImportParseResult

    /** A file-level refusal; zero rows are applied. */
    data class Failed(val reason: ImportFailure) : ImportParseResult
}

/**
 * The target book's current annotation identity — what "already present" means when the reader
 * filters the file (§6.4).
 *
 * [ids] deliberately spans ALL THREE kinds in one set. Android stores highlights, notes and
 * bookmarks under three table-local primary keys, so the same UUID can legally exist as two rows;
 * iOS dedupes against one global `existingAnnotationIds`. Collapsing to a single set here restores
 * the iOS semantics on a schema that cannot express them (F-2).
 *
 * [ids] may be supplied in ANY letter case: the reader compares UUIDs case-insensitively, because
 * an iOS-written archive spells them uppercase while Android mints them lowercase, and the two are
 * the same annotation.
 */
data class ExistingAnnotationState(
    val ids: Set<String>,
    val highlightProfileKeys: Set<String>,
    val bookmarkProfileKeys: Set<String>,
) {
    companion object {
        /** A book with no annotations yet. */
        val EMPTY = ExistingAnnotationState(emptySet(), emptySet(), emptySet())
    }
}
