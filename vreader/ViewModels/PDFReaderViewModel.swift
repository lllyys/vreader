// Purpose: ViewModel for the PDF reader. Manages page tracking, debounced
// position persistence, session tracking, and pages-per-hour metrics.
//
// Key decisions:
// - @Observable + @MainActor for SwiftUI integration.
// - Debounced position save (2s), periodic session flush (60s).
// - Page-based position using Locator.page (zero-based index).
// - Tracks distinct pages visited via Set<Int> for pagesRead.
// - Password flow: needsPassword drives UI, bridge callbacks confirm.
// - Empty PDF (0 pages): totalProgression = nil.
//
// @coordinates-with: ReadingPositionPersisting.swift,
//   ReadingSessionTracker.swift, LocatorFactory.swift, PDFViewBridge.swift

import Foundation

/// ViewModel for the PDF reader screen.
@Observable
@MainActor
final class PDFReaderViewModel {

    // MARK: - Constants

    /// Debounce interval for position persistence (seconds).
    static let positionSaveDebounce: TimeInterval = 2.0

    /// Periodic flush interval for session duration (seconds).
    static let sessionFlushInterval: TimeInterval = 60.0

    // MARK: - Published State

    /// Current page index (zero-based).
    private(set) var currentPageIndex: Int = 0

    /// Total number of pages in the PDF.
    private(set) var totalPages: Int = 0

    /// Whether the PDF document has been loaded.
    private(set) var isDocumentLoaded: Bool = false

    /// Whether the document requires a password to open.
    private(set) var needsPassword: Bool = false

    /// Whether the file is currently loading.
    private(set) var isLoading: Bool = false

    /// Error message from the last failed operation.
    private(set) var errorMessage: String?

    /// Formatted session reading time (e.g., "5m").
    private(set) var sessionTimeDisplay: String?

    /// Number of distinct pages visited in the current session.
    private(set) var distinctPagesVisited: Int = 0

    // MARK: - Computed State

    /// Total progression through the document (0.0 to 1.0). Nil for empty PDFs.
    var totalProgression: Double? {
        guard totalPages > 0 else { return nil }
        return Double(currentPageIndex) / Double(max(totalPages - 1, 1))
    }

    /// Display string for current page (1-based) / total.
    var pageIndicator: String {
        if totalPages == 0 {
            return "0 / 0"
        }
        return "\(currentPageIndex + 1) / \(totalPages)"
    }

    /// Current pages per hour based on session data. Nil if insufficient data.
    var pagesPerHour: Double? {
        guard distinctPagesVisited > 0 else { return nil }
        var total = accumulatedActiveSeconds
        if let start = segmentStartDate {
            total += Date().timeIntervalSince(start)
        }
        return calculatePagesPerHour(
            pagesRead: distinctPagesVisited,
            durationSeconds: Int(total)
        )
    }

    // MARK: - Dependencies

    private let bookFingerprint: DocumentFingerprint
    private let bookFingerprintKey: String
    private let positionStore: any ReadingPositionPersisting
    private let sessionTracker: ReadingSessionTracker
    private let deviceId: String

    // MARK: - Private State

    private var debounceTask: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?
    /// Date when the current active segment started (reset on resume).
    private var segmentStartDate: Date?
    /// Accumulated active reading seconds (excluding paused time).
    private var accumulatedActiveSeconds: TimeInterval = 0
    /// Set of distinct page indices visited in the current session.
    private var visitedPages: Set<Int> = []

    // MARK: - Init

    init(
        bookFingerprint: DocumentFingerprint,
        positionStore: any ReadingPositionPersisting,
        sessionTracker: ReadingSessionTracker,
        deviceId: String
    ) {
        self.bookFingerprint = bookFingerprint
        self.bookFingerprintKey = bookFingerprint.canonicalKey
        self.positionStore = positionStore
        self.sessionTracker = sessionTracker
        self.deviceId = deviceId
    }

    // MARK: - Document Lifecycle (called by bridge)

    /// Called when the PDFView successfully loads the document.
    func documentDidLoad(totalPages: Int) {
        self.totalPages = max(0, totalPages)
        self.isDocumentLoaded = true
        self.isLoading = false
        self.needsPassword = false
    }

    /// Called when the document requires a password.
    func documentNeedsPassword() {
        needsPassword = true
        isLoading = false
    }

    /// Called when the user submits a correct password.
    func passwordAccepted(totalPages: Int) {
        needsPassword = false
        errorMessage = nil
        documentDidLoad(totalPages: totalPages)
    }

    /// Called when the submitted password is rejected.
    func passwordRejected() {
        errorMessage = "Incorrect password. Please try again."
    }

    /// Marks the document as loading (called before bridge starts).
    func beginLoading() {
        isLoading = true
        errorMessage = nil
    }

    /// Called when the document fails to load from the bridge.
    func documentDidFailToLoad(error: String) {
        isLoading = false
        errorMessage = error
    }

    /// Starts the reading session. Call after documentDidLoad.
    func startSession() throws {
        try sessionTracker.startSessionIfNeeded(bookFingerprint: bookFingerprint)
        segmentStartDate = Date()
        accumulatedActiveSeconds = 0
        visitedPages = []
        distinctPagesVisited = 0
        startPeriodicFlush()
    }

    /// Restores saved position. Returns the page index to navigate to, or nil.
    func restorePosition() async -> Int? {
        do {
            let savedLocator = try await positionStore.loadPosition(
                bookFingerprintKey: bookFingerprintKey
            )
            if let savedLocator, let savedPage = savedLocator.page {
                let clamped = clampPage(savedPage)
                currentPageIndex = clamped
                return clamped
            }
        } catch {
            // Position restore failed — start from page 0
        }
        return nil
    }

    /// Updates the lastOpenedAt timestamp for this book.
    func updateLastOpened() async {
        try? await positionStore.updateLastOpened(
            bookFingerprintKey: bookFingerprintKey,
            date: Date()
        )
    }

    /// Closes the reader, ending the session and flushing state.
    func close() async {
        flushTask?.cancel()
        flushTask = nil
        debounceTask?.cancel()
        debounceTask = nil

        if isDocumentLoaded {
            let locator = makeCurrentLocator()
            sessionTracker.recordProgress(locator: locator)

            do {
                try await positionStore.savePosition(
                    bookFingerprintKey: bookFingerprintKey,
                    locator: locator,
                    deviceId: deviceId
                )
            } catch {
                errorMessage = "Failed to save reading position on close."
            }
        }

        sessionTracker.endSessionIfNeeded()
    }

    /// Called when the app moves to background while reader is open.
    func onBackground() {
        if isDocumentLoaded {
            let locator = makeCurrentLocator()
            Task { [bookFingerprintKey, deviceId, positionStore] in
                try? await positionStore.savePosition(
                    bookFingerprintKey: bookFingerprintKey,
                    locator: locator,
                    deviceId: deviceId
                )
            }
        }

        if let start = segmentStartDate {
            accumulatedActiveSeconds += Date().timeIntervalSince(start)
            segmentStartDate = nil
        }

        sessionTracker.pause()
        flushTask?.cancel()
        flushTask = nil
    }

    /// Called when the app returns to foreground with reader open.
    func onForeground() {
        guard isDocumentLoaded else { return }
        do {
            try sessionTracker.startSessionIfNeeded(bookFingerprint: bookFingerprint)
        } catch {
            errorMessage = "Failed to resume reading session."
        }
        segmentStartDate = Date()
        startPeriodicFlush()
    }

    // MARK: - Page Changes (called by bridge)

    /// Called when the visible page changes in PDFView.
    func pageDidChange(to pageIndex: Int) {
        guard isDocumentLoaded else { return }

        let clamped = clampPage(pageIndex)
        currentPageIndex = clamped

        // Track distinct pages visited
        visitedPages.insert(clamped)
        distinctPagesVisited = visitedPages.count

        // Record progress on session tracker
        let locator = makeCurrentLocator()
        sessionTracker.recordProgress(locator: locator)

        updateTimeDisplays()
        debounceSavePosition()
    }

    // MARK: - Locator Construction (internal for testing)

    /// Constructs a Locator for the current page position.
    func makeCurrentLocator() -> Locator {
        let progression = totalProgression

        return LocatorFactory.pdf(
            fingerprint: bookFingerprint,
            page: currentPageIndex,
            totalProgression: progression
        ) ?? Locator(
            bookFingerprint: bookFingerprint,
            href: nil, progression: nil, totalProgression: progression,
            cfi: nil, page: currentPageIndex,
            charOffsetUTF16: nil,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
    }

    // MARK: - Pages Per Hour Calculation (internal for testing)

    /// Calculates pages per hour from raw values.
    /// Returns nil if duration < 60 seconds.
    func calculatePagesPerHour(pagesRead: Int, durationSeconds: Int) -> Double? {
        guard durationSeconds >= 60, pagesRead > 0 else { return nil }
        let hours = Double(durationSeconds) / 3600.0
        return Double(pagesRead) / hours
    }

    // MARK: - Private: Position Persistence

    private func debounceSavePosition() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self, bookFingerprintKey, deviceId, positionStore] in
            do {
                try await Task.sleep(for: .seconds(Self.positionSaveDebounce))
                guard let self, !Task.isCancelled else { return }
                let locator = self.makeCurrentLocator()
                try await positionStore.savePosition(
                    bookFingerprintKey: bookFingerprintKey,
                    locator: locator,
                    deviceId: deviceId
                )
            } catch is CancellationError {
                // Expected when debounce is reset
            } catch {
                await MainActor.run {
                    self?.errorMessage = "Failed to save reading position."
                }
            }
        }
    }

    // MARK: - Private: Session Time Tracking

    private func startPeriodicFlush() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(Self.sessionFlushInterval))
                    try self?.sessionTracker.periodicFlush()
                    self?.updateTimeDisplays()
                } catch is CancellationError {
                    break
                } catch {
                    // Non-fatal
                }
            }
        }
    }

    private func updateTimeDisplays() {
        var total = accumulatedActiveSeconds
        if let start = segmentStartDate {
            total += Date().timeIntervalSince(start)
        }
        let sessionSeconds = Int(total)
        sessionTimeDisplay = ReadingTimeFormatter.formatReadingTime(totalSeconds: sessionSeconds)
    }

    // MARK: - Private: Page Clamping

    private func clampPage(_ page: Int) -> Int {
        guard totalPages > 0 else { return 0 }
        return min(max(page, 0), totalPages - 1)
    }
}
