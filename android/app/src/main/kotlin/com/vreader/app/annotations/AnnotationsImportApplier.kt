// Purpose: feature #165 WI-4 — the APPLY half of annotation import. Two jobs, both narrow:
//   1. `existingState` reads the target book's current annotation identity, which is the input that
//      lets `AnnotationsImportReader` drop rows the database would have refused. It is the reason
//      `preview.importable == applied` can be true by construction (§6.4, A-11) rather than by hope.
//   2. `apply` hands the preview's ALREADY-COLLAPSED envelope to the shared, UUID-preserving
//      `AnnotationsRepository.restoreAnnotations` seam, scoped to the one book the launching
//      surface chose (C-1), and turns a lost parent book into a typed `ImportFailure.BookMissing`.
//
// Key decisions:
//  - NO VALIDATION HAPPENS HERE (D-7). The reader owns the untrusted boundary and `restoreAnnotations`
//    keeps its own gate for its WebDAV-restore caller. This class adds no third policy — the envelope
//    it applies is the exact object the user approved, never one rebuilt from the displayed counts.
//  - C-5b IS TWO LAYERS, AND THE SECOND IS THE ONE THAT HOLDS. `findBook` immediately before applying
//    is check-then-act: it narrows the window, it does not close it. What closes it is mapping the
//    transaction's `SQLiteConstraintException` to the SAME typed failure, so every interleaving —
//    including a delete that lands between the check and the insert — reports `BookMissing` instead
//    of throwing an Android database exception out of a coroutine.
//  - ATOMICITY COMES FROM `@Transaction`, NOT FROM THIS CLASS — and the tests here do NOT prove it.
//    Removing `@Transaction` from `AnnotationDao.restoreAnnotationEntities` leaves this whole suite
//    green (measured). That is a TEST GAP, not redundancy: the cases these tests cover all have the
//    parent already absent before the first insert, which fails uniformly because every row in one
//    apply shares one `bookKey`. A partial apply is still reachable without the transaction —
//    cancellation between two inserts, a non-constraint failure after an early one, or a parent
//    deleted and recreated mid-loop. Closing that gap needs a fault-injection seam on the DAO,
//    which is outside this work item's write set; it is a named follow-up, not a settled claim.
//  - MAPPING ONLY THE CONSTRAINT CASE IS DELIBERATE. SQLite's `ON CONFLICT` clause does not apply to
//    FOREIGN KEY constraints, so of everything the IGNORE-based restore inserts can raise, the lost
//    parent is the only constraint failure that can escape at all; a unique-index or primary-key
//    collision is absorbed as a `-1` and counted `skipped`. Any OTHER database error is returned as
//    ITSELF, never relabelled: reporting "the book is gone" for a full disk would be a lie the user
//    cannot act on.
//  - `CancellationException` is rethrown, never captured into a `Result`. A blanket `runCatching`
//    here would swallow cancellation and break structured concurrency around the apply.
//  - `existingState` never throws on a corrupt stored row: the repository already drops rows whose
//    `locatorJSON` will not decode, and a stored locator that cannot produce a `profileKey` is
//    skipped rather than propagated. KNOWN RESIDUAL, stated rather than hidden: a corrupt row is
//    invisible to this read in BOTH of its dedupe identities — its primary-key id AND its stored
//    UNIQUE-INDEX key (`(profileKey, anchorKey)` for a highlight, `(bookKey, profileKey)` for a
//    bookmark; the database enforces those columns as stored, whether or not `locatorJSON` still
//    decodes). An incoming row colliding with either is previewed as importable and then IGNOREd at
//    insert. It is bounded and non-destructive (nothing is overwritten or lost, the returned report
//    is authoritative, and the divergence is logged at warn), but it is a genuine hole in the A-11
//    equality. Closing it needs DAO projections that read raw ids and raw unique-index columns
//    WITHOUT decoding `locatorJSON`; `AnnotationDao`/`AnnotationsRepository` are outside this work
//    item's write set, so it is a named follow-up. §6.4's TOCTOU paragraph is the same class of
//    residual approached from the other side.
//
// @coordinates-with AnnotationsImportReader (produces the preview this applies), AnnotationImportModels
// (`ImportPreview` / `ImportFailure` / `ExistingAnnotationState`), AnnotationsRepository
// (`restoreAnnotations`, `annotationsForBook`, `allBookmarks`), LibraryRepository (`findBook`),
// AnnotationsIoController (WI-4b, the only production caller).
package com.vreader.app.annotations

import android.database.sqlite.SQLiteConstraintException
import com.vreader.app.data.LibraryRepository
import com.vreader.app.diagnostics.DiagnosticsCategory
import com.vreader.app.diagnostics.VLog
import vreader.contracts.Locator
import kotlin.coroutines.cancellation.CancellationException

/**
 * A FILE-level apply refusal, carried inside `Result.failure` so the caller can render the designed
 * error blob from [reason] without string matching. [cause] is retained for diagnostics — for
 * `BookMissing` it distinguishes the pre-check (null) from the mapped foreign-key violation.
 */
class AnnotationImportFailedException(
    val reason: ImportFailure,
    cause: Throwable? = null,
) : Exception("annotation import failed: $reason", cause)

/** Rows this restore actually inserted, summed across the three kinds — the A-11 left-hand side. */
val RestoreAnnotationsReport.appliedTotal: Int
    get() = highlights.applied + notes.applied + bookmarks.applied

/** Applies an approved [ImportPreview] to the library's annotation store. */
class AnnotationsImportApplier(
    private val repo: AnnotationsRepository,
    private val library: LibraryRepository,
) {

    /**
     * The target book's current annotation identity — what "already present" means to the reader
     * (§6.4).
     *
     * [ExistingAnnotationState.ids] spans ALL THREE kinds AND THE WHOLE LIBRARY, for two different
     * reasons that happen to point the same way:
     *  - across KINDS, because Android's three tables have table-local primary keys, so one UUID can
     *    legally exist as a highlight and a note at once while iOS dedupes against a single global
     *    id set — collapsing here restores the iOS semantics (D-12);
     *  - across BOOKS, because each table's primary key is the id ALONE (`Entities.kt`), so it is
     *    unique library-wide. A UUID already spent on ANOTHER book's annotation cannot be inserted
     *    under this book either: Room IGNOREs it and the row silently fails to land. Scoping this
     *    set to the target book previewed such a row as importable and delivered nothing — a real
     *    `preview.importable == applied` divergence, found by Gate-4 round 1.
     *
     * Position keys stay scoped to [bookKey]. That is an optimisation rather than a policy: a
     * `profileKey` is `"$bookKey:<hash>"`, so another book's key could never collide anyway.
     *
     * Position keys are collected for highlights and bookmarks ONLY — those are the kinds carrying a
     * unique index. Notes have none by design (C-4 / F-5), so a note's position must not become a
     * dedupe key or the importer would drop rows the database would have accepted.
     *
     * Cost, stated because it is not free: three full-table reads that decode every locator and
     * materialise every highlight's text and every note's body just to collect ids, so preview cost
     * scales with the WHOLE annotation library rather than with this book. It runs once, when the
     * sheet is built, and the cheap per-book alternative is exactly what produced the divergence
     * above — so this is the correct trade today. The real fix is a DAO projection selecting ids
     * library-wide and dedupe columns for the target book only; that seam is outside this work
     * item's write set and is a named follow-up.
     */
    suspend fun existingState(bookKey: String): ExistingAnnotationState {
        val highlights = repo.allHighlights()
        val notes = repo.allNotes()
        val bookmarks = repo.allBookmarks()

        val ids = HashSet<String>(highlights.size + notes.size + bookmarks.size)
        for (highlight in highlights) ids.add(highlight.id)
        for (note in notes) ids.add(note.id)
        for (bookmark in bookmarks) ids.add(bookmark.id)

        val highlightProfileKeys = HashSet<String>()
        for (highlight in highlights) {
            if (highlight.bookKey != bookKey) continue
            profileKeyOrNull(bookKey, highlight.locator)?.let(highlightProfileKeys::add)
        }
        val bookmarkProfileKeys = HashSet<String>()
        for (bookmark in bookmarks) {
            if (bookmark.bookKey != bookKey) continue
            profileKeyOrNull(bookKey, bookmark.locator)?.let(bookmarkProfileKeys::add)
        }

        return ExistingAnnotationState(ids, highlightProfileKeys, bookmarkProfileKeys)
    }

    /**
     * Applies [preview]'s collapsed envelope, scoped to `setOf(preview.bookKey)` so a row for any
     * other book is counted `skipped` rather than reaching a foreign parent (C-1 / C-5a). Rows keep
     * their backed-up UUIDs and both timestamps, and an id already present is skipped, never
     * overwritten (I-1 / C-2) — a repeated apply of the same preview inserts nothing (C-11).
     *
     * Returns [ImportFailure.BookMissing] wrapped in [AnnotationImportFailedException] when the
     * target book is gone (C-5b, both layers). The restore runs inside one `@Transaction`, so that
     * failure is total: zero rows land and nothing already stored is disturbed.
     */
    suspend fun apply(preview: ImportPreview): Result<RestoreAnnotationsReport> {
        // Layer 1 — cheap, and it keeps the common "the book was deleted while the sheet was open"
        // case from ever opening a write transaction. It does NOT close the race; layer 2 does.
        if (library.findBook(preview.bookKey) == null) {
            return Result.failure(AnnotationImportFailedException(ImportFailure.BookMissing))
        }

        return try {
            val report = repo.restoreAnnotations(preview.envelope, setOf(preview.bookKey))
            warnOnDivergence(preview, report)
            Result.success(report)
        } catch (e: SQLiteConstraintException) {
            // Layer 2 — the parent vanished after the check. The only constraint SQLite can raise
            // out of the IGNORE-based restore is the foreign key (see this file's header).
            Result.failure(AnnotationImportFailedException(ImportFailure.BookMissing, e))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /**
     * §6.4's honest residual. The preview is computed against a snapshot the user then reads at
     * leisure; the database can move underneath it. The REPORT is authoritative, so a divergence is
     * not an error — but it is worth a breadcrumb, and a divergence on an idle database means the
     * collapse or [existingState] has a hole. Counts only: no user content reaches the log.
     */
    private fun warnOnDivergence(preview: ImportPreview, report: RestoreAnnotationsReport) {
        val applied = report.appliedTotal
        if (applied != preview.importable) {
            VLog.w(
                DiagnosticsCategory.PERSISTENCE, TAG,
                "annotation import applied $applied of ${preview.importable} previewed rows " +
                    "(the store changed since the preview was built)",
            )
        }
    }

    /** `profileKeyFor` hashes `canonicalJson()`, which throws on a structurally impossible locator. */
    private fun profileKeyOrNull(bookKey: String, locator: Locator): String? = try {
        profileKeyFor(bookKey, locator)
    } catch (e: Exception) {
        null
    }

    private companion object {
        const val TAG = "AnnotationsImportApplier"
    }
}
