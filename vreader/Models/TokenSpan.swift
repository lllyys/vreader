// Purpose: Token-to-offset mapping for search hit navigation.
// Stores the position of every indexed token occurrence for locator resolution.
//
// Key decisions:
// - sourceUnitId uses canonical per-format encoding:
//   EPUB: "epub:<href>", PDF: "pdf:page:<N>", TXT: "txt:segment:<N>"
// - Offsets are UTF-16 code units within the source unit's text.
// - Sendable + Equatable for safe cross-actor transfer and testing.
//
// @coordinates-with SearchIndexStore.swift, SearchHitToLocatorResolver.swift

import Foundation

/// A token occurrence with its position in a source unit.
struct TokenSpan: Sendable, Equatable {
    /// Canonical key of the book (from DocumentFingerprint.canonicalKey).
    let bookFingerprintKey: String

    /// Normalized (lowercased, diacritic-folded) token text.
    let normalizedToken: String

    /// Start offset in UTF-16 code units within the source unit.
    let startOffsetUTF16: Int

    /// End offset in UTF-16 code units within the source unit (exclusive).
    let endOffsetUTF16: Int

    /// Canonical source unit identifier:
    /// - EPUB: "epub:<href>"
    /// - PDF: "pdf:page:<zero-based-page-index>"
    /// - TXT: "txt:segment:<zero-based-segment-index>"
    let sourceUnitId: String
}
