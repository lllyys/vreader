// Purpose: Testable value-type view model for the reader Book Details
// sheet (feature #61). Maps a `LibraryBookItem` DTO to display-ready
// strings. A plain struct (no `@Observable`) so the formatting logic is
// unit-testable without SwiftUI — mirrors the `BookInfoViewModel`
// precedent.
//
// @coordinates-with: LibraryBookItem.swift, BookDetailsSheet.swift,
//   FileSizeFormatter.swift

import Foundation

/// Display-ready projection of a book for the reader's Book Details sheet.
struct BookDetailsViewModel {
    let title: String
    /// Author, or "Unknown Author" when the book has no author.
    let author: String
    /// Human-readable format label ("EPUB", "PDF", "Markdown", …).
    let formatDisplay: String
    /// Formatted file size, or "Unknown" when the byte count is zero.
    let fileSizeDisplay: String
    /// `nil` when the book has no usable page count — reflowable formats
    /// may not have one (`Book.totalPageCount` is optional), and a
    /// zero/negative count is treated the same as absent. The sheet omits
    /// the Pages row when this is `nil`.
    let pagesDisplay: String?
    /// Middle-truncated fingerprint key for the metadata row.
    let fingerprintDisplay: String
    /// The full, untruncated fingerprint key — the copy-button payload.
    let fingerprintFull: String
    /// Readable file location for the metadata row.
    let locationDisplay: String
    /// Collection memberships — the design's tag chips.
    let tags: [String]
    /// `true` when the title is long enough to need the multi-line
    /// long-title layout (heuristic on Character count).
    let isLongTitle: Bool
    /// `true` when the book has an extracted cover image.
    let hasCover: Bool

    init(book: LibraryBookItem) {
        self.title = book.title
        self.author = book.author ?? "Unknown Author"
        self.formatDisplay = Self.displayFormat(book.format)
        self.fileSizeDisplay = book.fileByteCount > 0
            ? FileSizeFormatter.format(byteCount: book.fileByteCount)
            : "Unknown"
        self.pagesDisplay = book.totalPageCount.flatMap { $0 > 0 ? String($0) : nil }
        self.fingerprintFull = book.fingerprintKey
        self.fingerprintDisplay = Self.truncateFingerprint(book.fingerprintKey)
        self.locationDisplay = "ImportedBooks/\(book.resolvedFileURL.lastPathComponent)"
        self.tags = book.collectionNames
        self.isLongTitle = book.title.count > Self.longTitleThreshold
        self.hasCover = book.coverImagePath != nil
    }

    // MARK: - Private

    /// Titles longer than this (in Characters) render in the multi-line
    /// long-title layout.
    private static let longTitleThreshold = 32

    private static func displayFormat(_ format: String) -> String {
        switch format.lowercased() {
        case "md": return "Markdown"
        default: return format.uppercased(with: Locale(identifier: "en_US_POSIX"))
        }
    }

    /// Middle-truncates a long fingerprint key (`format:sha256:bytes`) to
    /// `prefix…suffix` so it fits one metadata row. Short keys are
    /// returned unchanged.
    private static func truncateFingerprint(_ key: String) -> String {
        guard key.count > 28 else { return key }
        return "\(key.prefix(14))…\(key.suffix(8))"
    }
}
