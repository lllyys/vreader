// Purpose: feature #132 WI-4 — the review-sheet's card model. A sealed type over the two card kinds
// the Android annotations design depicts (`HighlightCard` / `StandaloneNoteCard`; the `BookmarkCard`
// kind arrives with #135). Each case exposes a stable [id], the round-trippable [locator] (the
// jump-to-annotation target), and the [displayText] the card renders — so the sheet's nullable
// `onJumpToAnnotation` callback (§review-sheet-contract) carries everything a host needs to navigate
// without re-reaching into the record types. Pure value type (no Android runtime), JVM-testable.
package com.vreader.app.annotations

import vreader.contracts.Locator

/**
 * A single reviewable annotation for the review sheet. Two kinds — a [Highlight] (a highlighted quote,
 * optionally with an attached note) and a standalone [Note] — mirroring the design's `HighlightCard` /
 * `StandaloneNoteCard`. [id] is stable (the record's UUID), [locator] is the jump target, [displayText]
 * is the card's primary text.
 */
sealed interface AnnotationItem {
    val id: String
    val locator: Locator
    val displayText: String

    /** A highlighted quote (the design's `HighlightCard`; may carry an attached [HighlightRecord.note]). */
    data class Highlight(val record: HighlightRecord) : AnnotationItem {
        override val id: String get() = record.id
        override val locator: Locator get() = record.locator
        override val displayText: String get() = record.selectedText
    }

    /** A standalone note (the design's `StandaloneNoteCard`). */
    data class Note(val record: NoteRecord) : AnnotationItem {
        override val id: String get() = record.id
        override val locator: Locator get() = record.locator
        override val displayText: String get() = record.content
    }
}
