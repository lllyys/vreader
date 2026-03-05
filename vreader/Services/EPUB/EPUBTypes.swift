// Purpose: Value types for EPUB document structure.
// Used for cross-boundary transfer between the parser and view layers.
//
// Key decisions:
// - All types are Sendable for safe cross-actor transfer.
// - EPUBSpineItem includes href for locator construction.
// - EPUBMetadata mirrors the subset of metadata needed by the reader.
// - ReadingDirection supports RTL for Arabic/Hebrew EPUBs.

import Foundation

/// Direction of reading progression for the publication.
enum ReadingDirection: String, Codable, Sendable {
    case ltr
    case rtl
    case auto
}

/// Layout type for EPUB rendering.
enum EPUBLayout: String, Codable, Sendable {
    case reflowable
    case fixedLayout = "fixed"
}

/// Metadata extracted from an EPUB publication.
struct EPUBMetadata: Sendable, Equatable {
    let title: String
    let author: String?
    let language: String?
    let readingDirection: ReadingDirection
    let layout: EPUBLayout
    let spineItems: [EPUBSpineItem]

    /// Total number of spine items (chapters/sections).
    var spineCount: Int { spineItems.count }
}

/// A single item in the EPUB spine (reading order).
struct EPUBSpineItem: Sendable, Equatable, Identifiable {
    let id: String
    /// Resource href within the EPUB container.
    let href: String
    /// Display title for TOC navigation (may be nil for untitled sections).
    let title: String?
    /// Zero-based index in the spine.
    let index: Int
}

/// Represents the current reading position reported by the EPUB renderer.
struct EPUBPosition: Sendable, Equatable {
    /// Spine item href.
    let href: String
    /// Progress within the current spine item (0.0...1.0), clamped.
    let progression: Double
    /// Progress across the entire publication (0.0...1.0), clamped.
    let totalProgression: Double
    /// EPUB CFI string, if available.
    let cfi: String?

    init(href: String, progression: Double, totalProgression: Double, cfi: String?) {
        self.href = href
        self.progression = progression.isFinite ? min(max(progression, 0), 1) : 0
        self.totalProgression = totalProgression.isFinite ? min(max(totalProgression, 0), 1) : 0
        self.cfi = cfi
    }
}
