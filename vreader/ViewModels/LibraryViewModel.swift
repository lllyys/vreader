// Purpose: ViewModel for the library view. Manages book list, sorting,
// view mode, deletion, import wiring, and pull-to-refresh with throttling.
//
// Key decisions:
// - @Observable + @MainActor for SwiftUI integration.
// - Uses LibraryPersisting protocol for testability.
// - Uses BookImporting protocol for import testability.
// - Pull-to-refresh throttled to minimum 5s interval (configurable for tests).
// - Sort applied locally after fetch for responsiveness.
// - Books stored as [LibraryBookItem] (value types, not @Model).
// - Import processes all URLs, collects first error, reloads books after all imports.
//
// @coordinates-with: LibraryPersisting.swift, LibraryBookItem.swift, BookImporting.swift

import Foundation

/// View mode for the library display.
enum LibraryViewMode: String, Sendable {
    case grid
    case list
}

/// ViewModel for the library screen.
@Observable
@MainActor
final class LibraryViewModel {
    // MARK: - Published State

    /// Current list of books, sorted by current sort order.
    private(set) var books: [LibraryBookItem] = []

    /// Current view mode (grid or list).
    var viewMode: LibraryViewMode = .grid

    /// Current sort order. Changing triggers re-sort.
    var sortOrder: LibrarySortOrder = .title {
        didSet {
            if oldValue != sortOrder {
                books = Self.sorted(unsortedBooks, by: sortOrder)
            }
        }
    }

    /// Whether a refresh is in progress.
    private(set) var isRefreshing = false

    /// Error message from the last failed operation, if any.
    private(set) var errorMessage: String?

    /// Whether the library is empty.
    var isEmpty: Bool { books.isEmpty }

    // MARK: - Private

    /// Unsorted backing store for re-sorting without re-fetch.
    private var unsortedBooks: [LibraryBookItem] = []

    /// Persistence layer (injected for testability).
    private let persistence: any LibraryPersisting

    /// Book importer (injected for testability). Nil means import is a no-op.
    private let importer: (any BookImporting)?

    /// Minimum interval between refreshes.
    private let throttleInterval: TimeInterval

    /// Timestamp of last successful refresh. Only updated on success
    /// so that failed refreshes don't block retry.
    private var lastRefreshTime: Date?

    // MARK: - Init

    init(
        persistence: any LibraryPersisting,
        importer: (any BookImporting)? = nil,
        throttleInterval: TimeInterval = 5.0
    ) {
        self.persistence = persistence
        self.importer = importer
        self.throttleInterval = throttleInterval
    }

    // MARK: - Actions

    /// Loads all books from persistence and applies current sort order.
    func loadBooks() async {
        do {
            let fetched = try await persistence.fetchAllLibraryBooks()
            unsortedBooks = fetched
            books = Self.sorted(fetched, by: sortOrder)
            errorMessage = nil
        } catch {
            errorMessage = error is CancellationError
                ? nil
                : ErrorMessageAuditor.sanitize(error)
        }
    }

    /// Refreshes the book list, throttled to prevent rapid consecutive calls.
    /// Re-entrant calls (while already refreshing) are dropped.
    func refresh() async {
        // Re-entrancy guard: if already refreshing, skip.
        guard !isRefreshing else { return }

        // Throttle check
        if let last = lastRefreshTime,
           Date().timeIntervalSince(last) < throttleInterval {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        await loadBooks()
        // Only record refresh time on success to allow retry on failure.
        if errorMessage == nil {
            lastRefreshTime = Date()
        }
    }

    /// Deletes a book by fingerprint key.
    func deleteBook(fingerprintKey: String) async {
        do {
            try await persistence.deleteBook(fingerprintKey: fingerprintKey)
            unsortedBooks.removeAll { $0.fingerprintKey == fingerprintKey }
            books.removeAll { $0.fingerprintKey == fingerprintKey }
            errorMessage = nil
        } catch {
            errorMessage = ErrorMessageAuditor.sanitize(error)
        }
    }

    /// Imports files from the given URLs via the BookImporter pipeline.
    /// Processes all URLs sequentially, collecting the first error encountered.
    /// Reloads the book list after all imports complete.
    func importFiles(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        guard let importer else {
            // No importer configured — nothing to do.
            // This is expected only in tests using ViewModel without import wiring.
            return
        }

        var firstError: (any Error)?

        for url in urls {
            do {
                _ = try await importer.importFile(at: url, source: .filesApp)
            } catch is CancellationError {
                // Don't surface cancellation as user-facing error
                continue
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        await loadBooks()

        if let error = firstError {
            errorMessage = ErrorMessageAuditor.sanitize(error)
        }
    }

    /// Toggles between grid and list view modes.
    func toggleViewMode() {
        viewMode = viewMode == .grid ? .list : .grid
    }

    /// Clears the current error message.
    func clearError() {
        errorMessage = nil
    }

    /// Sets an error message from external callers (e.g., file importer failures).
    func setError(_ message: String) {
        errorMessage = message
    }

    // MARK: - Sorting

    /// Sorts books by the given sort order.
    private static func sorted(
        _ books: [LibraryBookItem],
        by order: LibrarySortOrder
    ) -> [LibraryBookItem] {
        switch order {
        case .title:
            return books.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .addedAt:
            return books.sorted { $0.addedAt > $1.addedAt }
        case .lastReadAt:
            return books.sorted { lhs, rhs in
                switch (lhs.lastReadAt, rhs.lastReadAt) {
                case let (l?, r?): return l > r
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return false
                }
            }
        case .totalReadingTime:
            return books.sorted { $0.totalReadingSeconds > $1.totalReadingSeconds }
        }
    }
}
