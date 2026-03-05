// Purpose: ViewModel for the library view. Manages book list, sorting,
// view mode, deletion, and pull-to-refresh with throttling.
//
// Key decisions:
// - @Observable + @MainActor for SwiftUI integration.
// - Uses LibraryPersisting protocol for testability.
// - Pull-to-refresh throttled to minimum 5s interval (configurable for tests).
// - Sort applied locally after fetch for responsiveness.
// - Books stored as [LibraryBookItem] (value types, not @Model).
//
// @coordinates-with: LibraryPersisting.swift, LibraryBookItem.swift

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

    /// Minimum interval between refreshes.
    private let throttleInterval: TimeInterval

    /// Timestamp of last successful refresh. Only updated on success
    /// so that failed refreshes don't block retry.
    private var lastRefreshTime: Date?

    // MARK: - Init

    init(persistence: any LibraryPersisting, throttleInterval: TimeInterval = 5.0) {
        self.persistence = persistence
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
                : (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Imports files from the given URLs. Stub for WI-6+ implementation.
    func importFiles(_ urls: [URL]) async {
        // TODO: Delegate to BookImporter pipeline
    }

    /// Toggles between grid and list view modes.
    func toggleViewMode() {
        viewMode = viewMode == .grid ? .list : .grid
    }

    /// Clears the current error message.
    func clearError() {
        errorMessage = nil
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
