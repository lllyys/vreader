// Purpose: ViewModel for the TXT reader view. Manages reading state,
// debounced position persistence, session tracking, and word count estimation.
//
// Key decisions:
// - @Observable + @MainActor for SwiftUI integration.
// - Debounced position save (2s delay) to avoid excessive writes.
// - Integrates ReadingSessionTracker for reading time tracking.
// - Active reading time excludes background/pause intervals.
// - Uses protocol abstractions for testability (service, persistence, tracker).
// - Staged error handling: service failure aborts, position/timestamp failures non-fatal.
// - Position uses canonical UTF-16 offsets matching TXTOffsetMapper conventions.
// - wordsRead estimated via Section 9.6 normative formula.
//
// @coordinates-with: TXTServiceProtocol.swift, ReadingPositionPersisting.swift,
//   ReadingSessionTracker.swift, LocatorFactory.swift, TXTTextViewBridge.swift

import Foundation

/// ViewModel for the TXT reader screen.
@Observable
@MainActor
final class TXTReaderViewModel {

    // MARK: - Constants

    /// Debounce interval for position persistence (seconds).
    static let positionSaveDebounce: TimeInterval = 2.0

    /// Periodic flush interval for session duration (seconds).
    static let sessionFlushInterval: TimeInterval = 60.0

    // MARK: - Published State

    /// Decoded text content (nil until open completes).
    private(set) var textContent: String?

    /// Total text length in UTF-16 code units.
    private(set) var totalTextLengthUTF16: Int = 0

    /// Total word count from metadata.
    private(set) var totalWordCount: Int = 0

    /// Current scroll position as UTF-16 char offset.
    private(set) var currentOffsetUTF16: Int = 0

    /// Start of current selection in UTF-16 offsets (nil if no selection).
    private(set) var currentSelectionStart: Int?

    /// End of current selection in UTF-16 offsets (nil if no selection).
    private(set) var currentSelectionEnd: Int?

    /// Whether the file is currently loading.
    private(set) var isLoading = false

    /// Error message from the last failed operation.
    private(set) var errorMessage: String?

    /// Formatted session reading time (e.g., "5m").
    private(set) var sessionTimeDisplay: String?

    // MARK: - Computed State

    /// Total progression through the document (0.0 to 1.0). Nil for empty files.
    var totalProgression: Double? {
        guard totalTextLengthUTF16 > 0 else { return nil }
        return Double(currentOffsetUTF16) / Double(totalTextLengthUTF16)
    }

    /// Estimated words read based on Section 9.6 normative formula.
    /// `wordsRead = round((abs(endOffsetUTF16 - startOffsetUTF16) / totalLen) * totalWords)`
    /// Clamped to [0, totalWordCount]. Nil if no content loaded or empty.
    var estimatedWordsRead: Int? {
        guard textContent != nil, totalTextLengthUTF16 > 0, totalWordCount > 0 else {
            return nil
        }
        let startOffset = 0 // Reading always starts from beginning
        let fraction = Double(abs(currentOffsetUTF16 - startOffset)) / Double(totalTextLengthUTF16)
        let raw = (fraction * Double(totalWordCount)).rounded()
        return min(max(Int(raw), 0), totalWordCount)
    }

    // MARK: - Dependencies

    private let bookFingerprint: DocumentFingerprint
    private let bookFingerprintKey: String
    private let txtService: any TXTServiceProtocol
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
        txtService: any TXTServiceProtocol,
        positionStore: any ReadingPositionPersisting,
        sessionTracker: ReadingSessionTracker,
        deviceId: String
    ) {
        self.bookFingerprint = bookFingerprint
        self.bookFingerprintKey = bookFingerprint.canonicalKey
        self.txtService = txtService
        self.positionStore = positionStore
        self.sessionTracker = sessionTracker
        self.deviceId = deviceId
    }

    // MARK: - Lifecycle

    /// Opens the TXT file and restores the saved reading position.
    func open(url: URL) async {
        // Guard against re-open: close previous state first
        if textContent != nil {
            await close()
        }

        isLoading = true
        errorMessage = nil

        // Stage 1: Load and decode TXT
        let meta: TXTFileMetadata
        do {
            meta = try await txtService.open(url: url)
        } catch {
            resetState()
            isLoading = false
            errorMessage = (error as? TXTServiceError).map(describeServiceError)
                ?? "Failed to open file."
            return
        }

        textContent = meta.text
        totalTextLengthUTF16 = meta.totalTextLengthUTF16
        totalWordCount = meta.totalWordCount
        currentOffsetUTF16 = 0

        // Stage 2: Restore saved position (non-fatal on failure)
        do {
            let savedLocator = try await positionStore.loadPosition(
                bookFingerprintKey: bookFingerprintKey
            )
            if let savedLocator, let savedOffset = savedLocator.charOffsetUTF16 {
                currentOffsetUTF16 = clampOffset(savedOffset)
            }
        } catch {
            // Position restore failed — start from beginning
            currentOffsetUTF16 = 0
        }

        // Stage 3: Start reading session (rollback on failure)
        do {
            try sessionTracker.startSessionIfNeeded(bookFingerprint: bookFingerprint)
        } catch {
            textContent = nil
            totalTextLengthUTF16 = 0
            totalWordCount = 0
            currentOffsetUTF16 = 0
            await txtService.close()
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
        flushTask?.cancel()
        flushTask = nil
        debounceTask?.cancel()
        debounceTask = nil

        // Save final position immediately
        if textContent != nil {
            let locator = makeLocator()
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
        await txtService.close()
        resetState()
    }

    /// Called when the app moves to background while reader is open.
    func onBackground() {
        if textContent != nil {
            let locator = makeLocator()
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
        guard textContent != nil else { return }
        do {
            try sessionTracker.startSessionIfNeeded(bookFingerprint: bookFingerprint)
        } catch {
            errorMessage = "Failed to resume reading session."
        }
        segmentStartDate = Date()
        startPeriodicFlush()
    }

    // MARK: - Position Updates

    /// Called when the scroll position changes. Offset is in UTF-16 code units.
    func updateScrollPosition(charOffsetUTF16: Int) {
        let clamped = clampOffset(charOffsetUTF16)
        currentOffsetUTF16 = clamped

        // Use lightweight locator (no quote extraction) for transient progress updates
        let lightLocator = makeLightLocator()
        sessionTracker.recordProgress(locator: lightLocator)

        updateTimeDisplays()

        // Defer full locator construction to debounced persistence (avoids quote extraction on every scroll)
        debounceSavePosition()
    }

    // MARK: - Selection

    /// Called when the user's text selection changes.
    func updateSelection(startUTF16: Int, endUTF16: Int) {
        currentSelectionStart = startUTF16
        currentSelectionEnd = endUTF16
    }

    /// Clears the current selection.
    func clearSelection() {
        currentSelectionStart = nil
        currentSelectionEnd = nil
    }

    // MARK: - Private: Position Persistence

    private func debounceSavePosition() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self, bookFingerprintKey, deviceId, positionStore] in
            do {
                try await Task.sleep(for: .seconds(Self.positionSaveDebounce))
                // Construct full locator (with quote/context) only after debounce fires
                guard let locator = await self?.makeLocator() else { return }
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

    /// Lightweight locator without quote/context extraction (for transient progress).
    private func makeLightLocator() -> Locator {
        let progression = totalTextLengthUTF16 > 0
            ? Double(currentOffsetUTF16) / Double(totalTextLengthUTF16)
            : 0.0

        return LocatorFactory.txtPosition(
            fingerprint: bookFingerprint,
            charOffsetUTF16: currentOffsetUTF16,
            totalProgression: progression
        ) ?? Locator(
            bookFingerprint: bookFingerprint,
            href: nil, progression: nil, totalProgression: progression,
            cfi: nil, page: nil,
            charOffsetUTF16: currentOffsetUTF16,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
    }

    /// Full locator with quote/context extraction (for persistence).
    private func makeLocator() -> Locator {
        let progression = totalTextLengthUTF16 > 0
            ? Double(currentOffsetUTF16) / Double(totalTextLengthUTF16)
            : 0.0

        return LocatorFactory.txtPosition(
            fingerprint: bookFingerprint,
            charOffsetUTF16: currentOffsetUTF16,
            totalProgression: progression,
            sourceText: textContent
        ) ?? Locator(
            bookFingerprint: bookFingerprint,
            href: nil, progression: nil, totalProgression: progression,
            cfi: nil, page: nil,
            charOffsetUTF16: currentOffsetUTF16,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
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
                    // Non-fatal: periodic flush failure doesn't interrupt reading
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

    // MARK: - Private: State Reset

    private func resetState() {
        textContent = nil
        totalTextLengthUTF16 = 0
        totalWordCount = 0
        currentOffsetUTF16 = 0
        currentSelectionStart = nil
        currentSelectionEnd = nil
    }

    // MARK: - Private: Offset Clamping

    private func clampOffset(_ offset: Int) -> Int {
        min(max(offset, 0), totalTextLengthUTF16)
    }

    // MARK: - Private: Error Description

    private func describeServiceError(_ error: TXTServiceError) -> String {
        switch error {
        case .fileNotFound: return "The file could not be found."
        case .encodingDetectionFailed: return "Could not detect file encoding."
        case .decodingFailed: return "The file could not be decoded."
        case .notOpen: return "No file is currently open."
        case .alreadyOpen: return "A file is already open."
        }
    }
}
