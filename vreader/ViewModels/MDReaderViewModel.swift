// Purpose: ViewModel for the Markdown reader view. Manages reading state,
// debounced position persistence, session tracking, and rendered content.
//
// Key decisions:
// - @Observable + @MainActor for SwiftUI integration.
// - Debounced position save (2s delay) to avoid excessive writes.
// - Integrates ReadingSessionTracker for reading time tracking.
// - Uses protocol abstractions for testability (parser, persistence, tracker).
// - Reads file data, detects encoding, parses on background, displays on main.
// - Position uses canonical UTF-16 offsets over rendered text.
// - Empty document: totalProgression = nil (no division by zero).
//
// @coordinates-with: MDParserProtocol.swift, ReadingPositionPersisting.swift,
//   ReadingSessionTracker.swift, LocatorFactory.swift, TXTTextViewBridge.swift

import Foundation

/// ViewModel for the Markdown reader screen.
@Observable
@MainActor
final class MDReaderViewModel {

    // MARK: - Constants

    /// Debounce interval for position persistence (seconds).
    static let positionSaveDebounce: TimeInterval = 2.0

    /// Periodic flush interval for session duration (seconds).
    static let sessionFlushInterval: TimeInterval = 60.0

    // MARK: - Published State

    /// Rendered plain text (nil until open completes).
    private(set) var renderedText: String?

    /// Rendered attributed string for rich display (nil until open completes).
    private(set) var renderedAttributedString: NSAttributedString?

    /// Total rendered text length in UTF-16 code units.
    private(set) var renderedTextLengthUTF16: Int = 0

    /// Current scroll position as UTF-16 char offset.
    private(set) var currentOffsetUTF16: Int = 0

    /// Whether the file is currently loading.
    private(set) var isLoading = false

    /// Error message from the last failed operation.
    private(set) var errorMessage: String?

    /// Formatted session reading time (e.g., "5m").
    private(set) var sessionTimeDisplay: String?

    // MARK: - Computed State

    /// Total progression through the document (0.0 to 1.0). Nil for empty files.
    var totalProgression: Double? {
        guard renderedTextLengthUTF16 > 0 else { return nil }
        return Double(currentOffsetUTF16) / Double(renderedTextLengthUTF16)
    }

    // MARK: - Dependencies

    private let bookFingerprint: DocumentFingerprint
    private let bookFingerprintKey: String
    private let parser: any MDParserProtocol
    private let positionStore: any ReadingPositionPersisting
    private let sessionTracker: ReadingSessionTracker
    private let deviceId: String

    // MARK: - Private State

    private var debounceTask: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?
    private var segmentStartDate: Date?
    private var accumulatedActiveSeconds: TimeInterval = 0
    /// Generation counter to guard against open/close races.
    private var openGeneration: Int = 0

    // MARK: - Init

    init(
        bookFingerprint: DocumentFingerprint,
        parser: any MDParserProtocol,
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

    /// Opens the Markdown file, parses it, and restores the saved reading position.
    func open(url: URL) async {
        // Guard against re-open
        if renderedText != nil {
            await close()
        }

        openGeneration += 1
        let myGeneration = openGeneration

        isLoading = true
        errorMessage = nil

        // Stage 1: Read file data, detect encoding, and parse on background
        let config = MDRenderConfig.default
        let docInfo: MDDocumentInfo
        do {
            let fileURL = url
            let parser = self.parser
            docInfo = try await Task.detached {
                let data = try Data(contentsOf: fileURL)
                let result = try EncodingDetector.detect(data: data)
                return await parser.parse(text: result.text, config: config)
            }.value
        } catch {
            resetState()
            isLoading = false
            errorMessage = "Failed to open file."
            return
        }

        // Guard: another open() may have started while we were parsing
        guard myGeneration == openGeneration else { return }

        renderedText = docInfo.renderedText
        renderedAttributedString = docInfo.renderedAttributedString
        renderedTextLengthUTF16 = docInfo.renderedTextLengthUTF16
        currentOffsetUTF16 = 0

        // Stage 3: Restore saved position (non-fatal on failure)
        do {
            let savedLocator = try await positionStore.loadPosition(
                bookFingerprintKey: bookFingerprintKey
            )
            if let savedLocator, let savedOffset = savedLocator.charOffsetUTF16 {
                currentOffsetUTF16 = clampOffset(savedOffset)
            }
        } catch {
            currentOffsetUTF16 = 0
        }

        // Stage 4: Start reading session (rollback on failure)
        do {
            try sessionTracker.startSessionIfNeeded(bookFingerprint: bookFingerprint)
        } catch {
            renderedText = nil
            renderedAttributedString = nil
            renderedTextLengthUTF16 = 0
            currentOffsetUTF16 = 0
            isLoading = false
            errorMessage = "Failed to start reading session."
            return
        }
        segmentStartDate = Date()
        accumulatedActiveSeconds = 0

        // Stage 5: Update last opened (non-fatal)
        try? await positionStore.updateLastOpened(
            bookFingerprintKey: bookFingerprintKey,
            date: Date()
        )

        startPeriodicFlush()
        isLoading = false
    }

    /// Closes the reader, ending the session and flushing state.
    func close() async {
        // Invalidate generation so any in-flight open() becomes stale
        openGeneration += 1

        flushTask?.cancel()
        flushTask = nil
        debounceTask?.cancel()
        debounceTask = nil

        if renderedText != nil {
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
        resetState()
    }

    /// Called when the app moves to background while reader is open.
    func onBackground() {
        if renderedText != nil {
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
        guard renderedText != nil else { return }
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

        let lightLocator = makeLightLocator()
        sessionTracker.recordProgress(locator: lightLocator)

        updateTimeDisplays()
        debounceSavePosition()
    }

    // MARK: - Private: Position Persistence

    private func debounceSavePosition() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self, bookFingerprintKey, deviceId, positionStore] in
            do {
                try await Task.sleep(for: .seconds(Self.positionSaveDebounce))
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

    private func makeLightLocator() -> Locator {
        let progression: Double? = renderedTextLengthUTF16 > 0
            ? Double(currentOffsetUTF16) / Double(renderedTextLengthUTF16)
            : nil

        return LocatorFactory.mdPosition(
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

    private func makeLocator() -> Locator {
        let progression: Double? = renderedTextLengthUTF16 > 0
            ? Double(currentOffsetUTF16) / Double(renderedTextLengthUTF16)
            : nil

        return LocatorFactory.mdPosition(
            fingerprint: bookFingerprint,
            charOffsetUTF16: currentOffsetUTF16,
            totalProgression: progression,
            sourceText: renderedText
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

    // MARK: - Private: State Reset

    private func resetState() {
        renderedText = nil
        renderedAttributedString = nil
        renderedTextLengthUTF16 = 0
        currentOffsetUTF16 = 0
    }

    // MARK: - Private: Offset Clamping

    private func clampOffset(_ offset: Int) -> Int {
        min(max(offset, 0), renderedTextLengthUTF16)
    }
}
