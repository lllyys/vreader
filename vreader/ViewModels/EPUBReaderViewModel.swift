// Purpose: ViewModel for the EPUB reader view. Manages reading state,
// debounced position persistence, session tracking, and navigation.
//
// Key decisions:
// - @Observable + @MainActor for SwiftUI integration.
// - Debounced position save (2s delay) to avoid excessive writes.
// - Integrates ReadingSessionTracker for reading time tracking.
// - Active reading time excludes background/pause intervals.
// - Uses protocol abstractions for testability (parser, persistence, tracker).
// - Staged error handling: parser failure aborts, position/timestamp failures are non-fatal.
//
// @coordinates-with: EPUBParserProtocol.swift, ReadingPositionPersisting.swift,
//   ReadingSessionTracker.swift, LocatorFactory.swift

import Foundation

/// ViewModel for the EPUB reader screen.
@Observable
@MainActor
final class EPUBReaderViewModel {

    // MARK: - Constants

    /// Debounce interval for position persistence (seconds).
    static let positionSaveDebounce: TimeInterval = 2.0

    /// Periodic flush interval for session duration (seconds).
    static let sessionFlushInterval: TimeInterval = 60.0

    // MARK: - Published State

    /// Current EPUB metadata (nil until open completes).
    private(set) var metadata: EPUBMetadata?

    /// Current reading position.
    private(set) var currentPosition: EPUBPosition?

    /// Whether the EPUB is currently loading.
    private(set) var isLoading = false

    /// Error message from the last failed operation.
    private(set) var errorMessage: String?

    /// Formatted session reading time (e.g., "5m").
    private(set) var sessionTimeDisplay: String?

    // Note: totalTimeDisplay and speedDisplay are deferred to WI-7
    // when cumulative reading stats are available from ReadingStats.

    /// Current spine item index for navigation display.
    var currentSpineIndex: Int {
        guard let position = currentPosition, let metadata else { return 0 }
        return metadata.spineItems.firstIndex(where: { $0.href == position.href }) ?? 0
    }

    // MARK: - Dependencies

    private let bookFingerprint: DocumentFingerprint
    private let bookFingerprintKey: String
    private let parser: any EPUBParserProtocol
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

    // MARK: - Init

    init(
        bookFingerprint: DocumentFingerprint,
        parser: any EPUBParserProtocol,
        positionStore: any ReadingPositionPersisting,
        sessionTracker: ReadingSessionTracker,
        deviceId: String
    ) {
        self.bookFingerprint = bookFingerprint
        self.bookFingerprintKey = bookFingerprint.canonicalKey
        self.parser = parser
        self.positionStore = positionStore
        self.sessionTracker = sessionTracker
        self.deviceId = deviceId
    }

    // MARK: - Lifecycle

    /// Opens the EPUB file and restores the saved reading position.
    func open(url: URL) async {
        isLoading = true
        errorMessage = nil

        // Stage 1: Parse EPUB
        let meta: EPUBMetadata
        do {
            meta = try await parser.open(url: url)
        } catch {
            isLoading = false
            errorMessage = (error as? EPUBParserError).map(describeParserError)
                ?? "Failed to open book."
            return
        }

        metadata = meta

        // Stage 2: Restore saved position (non-fatal on failure)
        do {
            let savedLocator = try await positionStore.loadPosition(
                bookFingerprintKey: bookFingerprintKey
            )
            if let savedLocator,
               let href = savedLocator.href,
               meta.spineItems.contains(where: { $0.href == href }) {
                currentPosition = EPUBPosition(
                    href: href,
                    progression: savedLocator.progression ?? 0,
                    totalProgression: savedLocator.totalProgression ?? 0,
                    cfi: savedLocator.cfi
                )
            } else if let firstSpine = meta.spineItems.first {
                currentPosition = EPUBPosition(
                    href: firstSpine.href,
                    progression: 0,
                    totalProgression: 0,
                    cfi: nil
                )
            }
        } catch {
            // Position restore failed — start from beginning
            if let firstSpine = meta.spineItems.first {
                currentPosition = EPUBPosition(
                    href: firstSpine.href,
                    progression: 0,
                    totalProgression: 0,
                    cfi: nil
                )
            }
        }

        // Stage 3: Start reading session (rollback parser + state on failure)
        do {
            try sessionTracker.startSessionIfNeeded(bookFingerprint: bookFingerprint)
        } catch {
            metadata = nil
            currentPosition = nil
            await parser.close()
            isLoading = false
            errorMessage = "Failed to start reading session."
            return
        }
        segmentStartDate = Date()
        accumulatedActiveSeconds = 0

        // Stage 4: Update last opened (non-fatal)
        try? await positionStore.updateLastOpened(
            bookFingerprintKey: bookFingerprintKey,
            date: Date()
        )

        // Start periodic session flush
        startPeriodicFlush()

        isLoading = false
    }

    /// Closes the reader, ending the session and flushing state.
    func close() async {
        // Stop periodic flush
        flushTask?.cancel()
        flushTask = nil

        // Cancel pending debounced save
        debounceTask?.cancel()
        debounceTask = nil

        // Save final position immediately
        if let position = currentPosition {
            let locator = makeLocator(from: position)
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

        // End reading session
        sessionTracker.endSessionIfNeeded()

        // Close parser
        await parser.close()

        // Release state to free memory
        metadata = nil
        currentPosition = nil
    }

    /// Called when the app moves to background while reader is open.
    func onBackground() {
        // Save current position immediately (best-effort) before potential kill
        if let position = currentPosition {
            let locator = makeLocator(from: position)
            Task { [bookFingerprintKey, deviceId, positionStore] in
                try? await positionStore.savePosition(
                    bookFingerprintKey: bookFingerprintKey,
                    locator: locator,
                    deviceId: deviceId
                )
            }
        }

        // Accumulate active time from current segment before pausing
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
        do {
            try sessionTracker.startSessionIfNeeded(bookFingerprint: bookFingerprint)
        } catch {
            // Non-fatal: session tracking failure should not block reading
            errorMessage = "Failed to resume reading session."
        }
        segmentStartDate = Date()
        startPeriodicFlush()
    }

    // MARK: - Position Updates

    /// Called by the EPUB renderer when the reading position changes.
    func updatePosition(_ position: EPUBPosition) {
        currentPosition = position

        let locator = makeLocator(from: position)
        sessionTracker.recordProgress(locator: locator)

        // Update time displays
        updateTimeDisplays()

        // Debounced persistence
        debounceSavePosition(locator: locator)
    }

    // MARK: - Navigation

    /// Navigates to a specific spine item by index.
    func navigateToSpine(index: Int) {
        guard let metadata, index >= 0, index < metadata.spineItems.count else { return }
        let item = metadata.spineItems[index]
        let position = EPUBPosition(
            href: item.href,
            progression: 0,
            totalProgression: estimateTotalProgression(spineIndex: index),
            cfi: nil
        )
        updatePosition(position)
    }

    /// Navigates to the next spine item.
    func navigateNext() {
        navigateToSpine(index: currentSpineIndex + 1)
    }

    /// Navigates to the previous spine item.
    func navigatePrevious() {
        navigateToSpine(index: currentSpineIndex - 1)
    }

    // MARK: - Private: Position Persistence

    private func debounceSavePosition(locator: Locator) {
        debounceTask?.cancel()
        debounceTask = Task { [weak self, bookFingerprintKey, deviceId, positionStore] in
            do {
                try await Task.sleep(for: .seconds(Self.positionSaveDebounce))
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

    // MARK: - Private: Locator Construction

    private func makeLocator(from position: EPUBPosition) -> Locator {
        LocatorFactory.epub(
            fingerprint: bookFingerprint,
            href: position.href,
            progression: position.progression,
            totalProgression: position.totalProgression,
            cfi: position.cfi
        ) ?? Locator(
            bookFingerprint: bookFingerprint,
            href: position.href,
            progression: position.progression,
            totalProgression: position.totalProgression,
            cfi: position.cfi,
            page: nil,
            charOffsetUTF16: nil,
            charRangeStartUTF16: nil,
            charRangeEndUTF16: nil,
            textQuote: nil,
            textContextBefore: nil,
            textContextAfter: nil
        )
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
                    // Non-fatal: periodic flush failure is logged but doesn't interrupt reading
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

    // MARK: - Private: Navigation Helpers

    private func estimateTotalProgression(spineIndex: Int) -> Double {
        guard let metadata, metadata.spineCount > 1 else { return 0 }
        return Double(spineIndex) / Double(metadata.spineCount - 1)
    }

    // MARK: - Private: Error Description

    private func describeParserError(_ error: EPUBParserError) -> String {
        switch error {
        case .fileNotFound: return "The book file could not be found."
        case .invalidFormat: return "This file is not a valid EPUB."
        case .parsingFailed: return "The book could not be read."
        case .notOpen: return "No book is currently open."
        case .alreadyOpen: return "A book is already open."
        case .resourceNotFound: return "A book resource could not be loaded."
        }
    }
}
