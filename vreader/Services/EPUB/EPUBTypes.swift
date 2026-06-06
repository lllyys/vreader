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
    /// Cover image href relative to OPF directory (nil if no cover found).
    let coverImageHref: String?

    init(
        title: String,
        author: String?,
        language: String?,
        readingDirection: ReadingDirection,
        layout: EPUBLayout,
        spineItems: [EPUBSpineItem],
        coverImageHref: String? = nil
    ) {
        self.title = title
        self.author = author
        self.language = language
        self.readingDirection = readingDirection
        self.layout = layout
        self.spineItems = spineItems
        self.coverImageHref = coverImageHref
    }

    /// Total number of spine items (chapters/sections).
    var spineCount: Int { spineItems.count }

    /// Returns a copy with spine item titles resolved from nav/NCX data. (bug #74)
    /// Titles from the navigation document override "Section N" fallbacks.
    /// Resolves nav-doc titles onto the spine. Bug #321: this is only invoked
    /// when a real nav doc exists (`navTitles` non-empty), so an un-nav'd spine
    /// item must NOT keep the synthetic "Section N" placeholder `EPUBParser`
    /// assigned at OPF-parse time — it is nil-titled here so
    /// `TOCBuilder.fromSpineItems` skips it, leaving the Contents list to reflect
    /// the publisher's nav-doc TOC alone (no interleaved "Section N" pollution).
    /// A nav-LESS EPUB never calls this, so its placeholders survive (TOC stays
    /// navigable).
    func withResolvedTitles(_ navTitles: [String: String]) -> EPUBMetadata {
        let resolved = spineItems.map { item -> EPUBSpineItem in
            if let navTitle = navTitles[item.href] {
                return EPUBSpineItem(id: item.id, href: item.href, title: navTitle, index: item.index)
            }
            return EPUBSpineItem(id: item.id, href: item.href, title: nil, index: item.index)
        }
        return EPUBMetadata(
            title: title, author: author, language: language,
            readingDirection: readingDirection, layout: layout, spineItems: resolved,
            coverImageHref: coverImageHref
        )
    }
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
