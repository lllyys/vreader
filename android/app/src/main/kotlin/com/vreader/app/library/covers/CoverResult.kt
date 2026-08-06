// Purpose: feature #152 — the shared vocabulary every cover extractor speaks. Landed by WI-3
// because it is the first extractor to ship; WI-4 (EPUB) and WI-5 (PDF) implement the same
// interface, and WI-6's `CoverExtractors` routes a `BookFormat` to one of them.
//
// Key decisions:
// - **`None` and `Failed` are DIFFERENT outcomes, and the split is load-bearing.** `CoverCoordinator`
//   stamps `coverExtractorVersion` only on a definite outcome: `None` is memoised (the book is known
//   to carry no art, so it is never parsed again), while `Failed` leaves the version NULL so the book
//   is retried on the next pass. Conflating them either blinds a book whose file was momentarily
//   unreadable, or re-parses every art-less book on every app start — the exact cost the memoisation
//   exists to prevent.
// - **The line is CONTENT vs ACCESS, not exception type.** `None` = the file was reachable and
//   structurally parsed and yields no cover (truncated, malformed, out of range, undecodable
//   payload). `Failed` = the file could not be accessed at all (missing, permission, device I/O on
//   open). See `MobiCoverParser` for where the boundary is drawn in practice.
// - **No extractor throws.** Every implementation converts its failures into one of these three
//   values, so a single hostile book can never kill the app-scope backfill for the whole library.
//
// @coordinates-with: MobiCoverExtractor.kt, MobiCoverParser.kt
package com.vreader.app.library.covers

import android.graphics.Bitmap
import java.io.File

/** The outcome of attempting to extract a book's embedded cover. */
sealed interface CoverResult {

    /**
     * Cover art was found and decoded.
     *
     * The bitmap is BORROWED by every consumer: it is read, never recycled, and never retained
     * after the call returns. It may be a live bitmap owned by the source (Readium's cover service
     * hands back its own retained field), so recycling it would corrupt that source's state.
     */
    @JvmInline
    value class Art(val bitmap: Bitmap) : CoverResult

    /** Reachable and structurally parsed; this book carries no usable art. Memoise — never retry. */
    data object None : CoverResult

    /** The file could not be accessed at all. Retry on a later pass. */
    data object Failed : CoverResult
}

/** Extracts embedded cover art from one book file. Implementations never throw. */
fun interface CoverExtractor {
    suspend fun extract(file: File): CoverResult
}
