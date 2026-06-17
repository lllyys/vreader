// Purpose: ViewModel for the EPUB reader view. Manages reading state,
// position persistence (via ReaderPositionService), session tracking, navigation.
//
// Key decisions:
// - @Observable + @MainActor for SwiftUI integration.
// - Position persistence delegated to ReaderPositionService (WI-008b).
// - File loading delegated to EPUBFileLoader (WI-008b).
// - Lifecycle operations (session, flush, time display) delegated to ReaderLifecycleHelper (R6).
// - Uses protocol abstractions for testability (parser, persistence, tracker).
// - Staged error handling: parser failure aborts, position/timestamp failures are non-fatal.
//
// @coordinates-with: EPUBFileLoader.swift, ReaderLifecycleHelper.swift,
//   ReaderPositionService.swift, EPUBParserProtocol.swift,
//   ReadingPositionPersisting.swift, ReadingSessionTracker.swift,
//   LocatorFactory.swift

import Foundation

/// ViewModel for the EPUB reader screen.
@Observable
@MainActor
final class EPUBReaderViewModel {

    // MARK: - Published State

    /// Current EPUB metadata (nil until open completes).
    private(set) var metadata: EPUBMetadata?

    /// Current reading position.
    private(set) var currentPosition: EPUBPosition?

    /// Whether the EPUB is currently loading.
    private(set) var isLoading = false

    /// Error message from the last failed operation.
    private(set) var errorMessage: String?

    /// Formatted session reading time (e.g., "5m"). Delegated to lifecycle helper.
    var sessionTimeDisplay: String? { lifecycle.sessionTimeDisplay }

    /// Feature #101: combined time readout passthrough ("12m read · 6h 40m
    /// total"). nil until the book totals attach — the chrome pins pages.
    var timeReadoutDisplay: String? { lifecycle.timeReadoutDisplay }

    // Note: totalTimeDisplay and speedDisplay are deferred to WI-7
    // when cumulative reading stats are available from ReadingStats.

    /// Current spine item index for navigation display.
    var currentSpineIndex: Int {
        guard let position = currentPosition, let metadata else { return 0 }
        return metadata.spineItems.firstIndex(where: { $0.href == position.href }) ?? 0
    }

    // MARK: - Dependencies

    private let bookFingerprint: DocumentFingerprint
    let bookFingerprintKey: String
    let lifecycle: ReaderLifecycleHelper
    private let parser: any EPUBParserProtocol
    private let positionStore: any ReadingPositionPersisting
    private let sessionTracker: ReadingSessionTracker
    private let positionService: ReaderPositionService

    // MARK: - Init

    init(
        bookFingerprint: DocumentFingerprint,
        parser: any EPUBParserProtocol,
        positionStore: any ReadingPositionPersisting,
        sessionTracker: ReadingSessionTracker,
        deviceId: String,
        positionSaveDebounceNs: UInt64 = 2_000_000_000
    ) {
        self.bookFingerprint = bookFingerprint
        self.bookFingerprintKey = bookFingerprint.canonicalKey
        self.parser = parser
        self.positionStore = positionStore
        self.sessionTracker = sessionTracker
        let posService = ReaderPositionService(
            bookFingerprintKey: bookFingerprint.canonicalKey,
            deviceId: deviceId,
            persistence: positionStore,
            debounceNanoseconds: positionSaveDebounceNs
        )
        self.positionService = posService
        self.lifecycle = ReaderLifecycleHelper(
            bookFingerprint: bookFingerprint,
            positionService: posService,
            sessionTracker: sessionTracker,
            positionStore: positionStore,
            statsStore: positionStore as? PersistenceActor
        )
    }

    // MARK: - Lifecycle

    /// Opens the EPUB file and restores the saved reading position.
    func open(url: URL) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        // Stage 1+2: Parse EPUB and restore position (via EPUBFileLoader)
        let loadResult: EPUBLoadResult
        do {
            loadResult = try await EPUBFileLoader.load(
                url: url,
                parser: parser,
                positionStore: positionStore,
                bookFingerprintKey: bookFingerprintKey
            )
        } catch {
            isLoading = false
            errorMessage = (error as? EPUBParserError).map(describeParserError)
                ?? "Failed to open book."
            return
        }

        metadata = loadResult.metadata
        currentPosition = loadResult.initialPosition

        // PERFORMANCE: Show content immediately — session/lastOpened are non-blocking
        isLoading = false

        // Stage 3: Start reading session (fire-and-forget, non-fatal)
        do {
            try lifecycle.beginSession()
        } catch {
            // Session failure is non-fatal — user can still read
        }

        // Stage 4: Update last opened (fire-and-forget)
        Task { await lifecycle.updateLastOpened() }
    }

    /// Closes the reader, ending the session and flushing state.
    /// Order is load-bearing (bugs #34, #45): saveNow → recordProgress → end → stats → notify.
    func close() async {
        let locator = currentPosition.map { makeLocator(from: $0) }
        await lifecycle.close(locator: locator)

        await parser.close()
        metadata = nil
        currentPosition = nil
    }

    /// Called when the app moves to background while reader is open.
    /// Awaits the position save to guarantee it completes before iOS suspends.
    func onBackground() async {
        let locator = currentPosition.map { makeLocator(from: $0) }
        await lifecycle.onBackground(locator: locator)
    }

    /// Called when the app returns to foreground with reader open.
    func onForeground() {
        if let error = lifecycle.onForeground() {
            errorMessage = error
        }
    }

    // MARK: - Position Updates

    /// Called by the EPUB renderer when the reading position changes.
    func updatePosition(_ position: EPUBPosition) {
        currentPosition = position
        let locator = makeLocator(from: position)
        lifecycle.recordProgressAndScheduleSave(locator: locator)
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

    // MARK: - Locator Construction

    /// Returns the locator for the current reading position.
    func makeCurrentLocator() -> Locator? {
        guard let position = currentPosition else { return nil }
        return makeLocator(from: position)
    }

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
        ).repairedForCanonicalization()   // #109 WI-2: the validated factory
        // returns nil only on a non-finite progression; repair (not recreate as
        // invalid) so an out-of-range value never reaches persistence as a
        // colliding key. The persistence boundary repairs again as backstop.
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
