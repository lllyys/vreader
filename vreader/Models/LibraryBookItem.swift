// Purpose: Lightweight value type for library display. Combines book metadata
// with reading stats for cross-boundary transfer to the view layer.
//
// Key decisions:
// - Sendable + Identifiable for safe use in SwiftUI views and across actors.
// - id is fingerprintKey for stable list identity.
// - Includes computed properties for formatted reading time and speed.
// - Does not include full fingerprint (not needed for library display).

import Foundation

/// Lightweight value type combining Book metadata and ReadingStats for library display.
struct LibraryBookItem: Sendable, Identifiable, Equatable, Hashable {
    var id: String { fingerprintKey }

    let fingerprintKey: String
    let title: String
    let author: String?
    let coverImagePath: String?
    let format: String
    let fileByteCount: Int64
    let addedAt: Date
    let lastOpenedAt: Date?
    let isFavorite: Bool
    let totalReadingSeconds: Int
    var lastReadAt: Date?
    let averagePagesPerHour: Double?
    let averageWordsPerMinute: Double?
    /// File-presence state (feature #47). Drives row UI: cloud icon for
    /// `.remoteOnly`, spinner for `.downloading`, retry CTA for `.failed`.
    let fileState: BookFileState
    /// Server-side blob path on the WebDAV backup (feature #47). Nil for
    /// books that have never been backed up.
    let blobPath: String?
    /// Names of `BookCollection`s this book belongs to (feature #34).
    /// Drives library filter (`LibraryFilter.collection(name).matches(_:)`)
    /// when the user selects a collection in the sidebar. Bug #155.
    let collectionNames: [String]

    /// Fractional reading progress in `[0, 1]`, or `nil` when the book
    /// has never been opened / no reading position is recorded yet.
    /// Projected from `ReadingPosition.locator.totalProgression`
    /// (feature #60 WI-8). Drives the grid-card progress strip /
    /// finished checkmark and the list-row progress ring.
    let progressFraction: Double?

    /// Indexing-produced total page count (`Book.totalPageCount`). `nil`
    /// for books not yet indexed, or reflowable formats without a fixed
    /// pagination. Drives the Book Details sheet's Pages row (feature #61).
    let totalPageCount: Int?

    /// Explicit memberwise init with feature-#47 + bug-#155 defaults so
    /// existing call sites that pre-date `fileState`/`blobPath`/`collectionNames`
    /// continue to compile; new call sites pass the persisted values through.
    /// `progressFraction` and `totalPageCount` default to `nil` for the
    /// same back-compat reason.
    init(
        fingerprintKey: String,
        title: String,
        author: String?,
        coverImagePath: String?,
        format: String,
        fileByteCount: Int64,
        addedAt: Date,
        lastOpenedAt: Date?,
        isFavorite: Bool,
        totalReadingSeconds: Int,
        lastReadAt: Date? = nil,
        averagePagesPerHour: Double?,
        averageWordsPerMinute: Double?,
        fileState: BookFileState = .local,
        blobPath: String? = nil,
        collectionNames: [String] = [],
        progressFraction: Double? = nil,
        totalPageCount: Int? = nil
    ) {
        self.fingerprintKey = fingerprintKey
        self.title = title
        self.author = author
        self.coverImagePath = coverImagePath
        self.format = format
        self.fileByteCount = fileByteCount
        self.addedAt = addedAt
        self.lastOpenedAt = lastOpenedAt
        self.isFavorite = isFavorite
        self.totalReadingSeconds = totalReadingSeconds
        self.lastReadAt = lastReadAt
        self.averagePagesPerHour = averagePagesPerHour
        self.averageWordsPerMinute = averageWordsPerMinute
        self.fileState = fileState
        self.blobPath = blobPath
        self.collectionNames = collectionNames
        self.progressFraction = progressFraction
        self.totalPageCount = totalPageCount
    }

    // MARK: - Reading-progress state (feature #60 WI-8)

    /// Three-way reading-progress state the Library card + row render,
    /// mirroring the design's `progress === 0 / 0 < p < 1 / p === 1`
    /// branches in `vreader-library.jsx`. Centralised here so the grid
    /// card and the list row agree on the boundary rules and the
    /// classification is unit-testable without a SwiftUI render.
    enum ReadingProgressState: Sendable, Equatable {
        /// Never opened, or no position recorded. The card shows no
        /// progress strip; the row shows the format chip alone.
        case notStarted
        /// Partially read — associated value is the progress fraction,
        /// strictly between 0 and 1.
        case inProgress(Double)
        /// Fully read (`progressFraction >= 1`). The card shows the
        /// finished checkmark; the row shows the "Finished" label.
        case finished
    }

    /// Classifies `progressFraction` into `ReadingProgressState`.
    /// `nil`, non-finite (NaN / ∞), zero, or negative fractions are
    /// `.notStarted`; `>= 1.0` is `.finished` (tolerating rounding
    /// drift past 1); anything strictly between is `.inProgress`. The
    /// view layer reads this rather than re-deriving the boundaries.
    var readingProgressState: ReadingProgressState {
        guard let fraction = progressFraction,
              fraction.isFinite, fraction > 0 else { return .notStarted }
        if fraction >= 1.0 { return .finished }
        return .inProgress(fraction)
    }

    // MARK: - File-state helpers (feature #47 WI-5)

    /// True when the row's bytes are local and the reader can open
    /// directly. Drives the Share menu visibility, the row tap target,
    /// and the reader-open gate.
    var isReadable: Bool { fileState == .local }

    /// True when tapping the row should kick off a lazy download.
    /// `.remoteOnly` and `.failed` qualify; `.downloading` does not
    /// (already in flight); `.missingRemote` does not (server lost
    /// the blob — needs re-upload, not re-download).
    var needsDownload: Bool { fileState.canDownload }

    /// True when the Share menu should be visible. Omitted for any
    /// non-`.local` row — sharing a remote-only book has no bytes to
    /// share, and sharing a downloading row would block on the
    /// transfer with no useful UX.
    var canShare: Bool { isReadable }

    // MARK: - Computed Display Properties

    /// Formatted reading time string, or nil if zero reading time.
    var formattedReadingTime: String? {
        ReadingTimeFormatter.formatReadingTime(totalSeconds: totalReadingSeconds)
    }

    /// Formatted speed string, or nil if insufficient data.
    var formattedSpeed: String? {
        ReadingTimeFormatter.formatSpeed(
            averagePagesPerHour: averagePagesPerHour,
            averageWordsPerMinute: averageWordsPerMinute,
            totalReadingSeconds: totalReadingSeconds
        )
    }

    /// Uppercased format badge label (e.g. "EPUB", "PDF", "TXT").
    var formatBadge: String {
        ReadingTimeFormatter.formatBadgeLabel(format: format)
    }

    /// Sandbox file URL for the imported book.
    /// Uses the same convention as BookImporter: fingerprintKey with colons replaced
    /// by underscores, stored under Application Support/ImportedBooks/.
    var resolvedFileURL: URL {
        ImportedBookFileURL.resolve(fingerprintKey: fingerprintKey, format: format)
    }

    /// SF Symbol name for the book's format.
    var formatIcon: String {
        switch format.lowercased() {
        case "epub": return "book.fill"
        case "pdf": return "doc.fill"
        case "txt": return "doc.text.fill"
        case "md": return "doc.richtext.fill"
        case "azw3": return "book.fill"
        default: return "doc.fill"
        }
    }
}
