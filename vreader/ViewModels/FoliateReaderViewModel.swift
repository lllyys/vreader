// Purpose: ViewModel for the Foliate-js reader (AZW3/MOBI, later EPUB).
// Manages reading state, position persistence, and maps Foliate-js bridge events
// to the shared Locator model.
//
// Key decisions:
// - @Observable + @MainActor for SwiftUI integration (same pattern as EPUB/PDF/TXT VMs).
// - Maps FoliateRelocateEvent -> Locator for position persistence.
// - Locator.cfi is the authoritative position field.
// - totalProgression is best-effort (from relocate event fraction).
// - Composes ReaderLifecycleHelper for session tracking, position save/restore.
//
// @coordinates-with: FoliateViewCoordinator.swift, FoliateTypes.swift,
//   ReaderPositionService.swift, ReaderLifecycleHelper.swift,
//   Locator.swift, DocumentFingerprint.swift

import Foundation

/// ViewModel for the Foliate-js based reader (AZW3/MOBI formats).
@Observable
@MainActor
final class FoliateReaderViewModel {

    // MARK: - Published State

    /// Identity of the book being read.
    let bookFingerprint: DocumentFingerprint

    /// Canonical persistence key for position save/load and bookmarks.
    let bookFingerprintKey: String

    /// Whether the book is currently loading.
    private(set) var isLoading = true

    /// Error message from the last failed operation.
    private(set) var errorMessage: String?

    /// Current EPUB CFI string from the most recent relocate event.
    private(set) var currentCFI: String?

    /// Current book-level reading progress (0.0 to 1.0).
    private(set) var currentProgress: Double = 0

    /// Human-readable TOC label for the current section.
    private(set) var currentTOCLabel: String?

    /// Formatted session reading time (e.g., "5m"), forwarded from lifecycle helper.
    var sessionTimeDisplay: String? { lifecycle.sessionTimeDisplay }

    /// Feature #101: combined time readout passthrough ("12m read · 6h 40m
    /// total"). nil until the book totals attach — the chrome pins pages.
    var timeReadoutDisplay: String? { lifecycle.timeReadoutDisplay }

    // MARK: - Dependencies

    let lifecycle: ReaderLifecycleHelper

    // MARK: - Init

    init(
        bookFingerprint: DocumentFingerprint,
        positionStore: any ReadingPositionPersisting,
        sessionTracker: ReadingSessionTracker,
        deviceId: String,
        positionSaveDebounceNs: UInt64 = 2_000_000_000
    ) {
        self.bookFingerprint = bookFingerprint
        self.bookFingerprintKey = bookFingerprint.canonicalKey
        let posService = ReaderPositionService(
            bookFingerprintKey: bookFingerprint.canonicalKey,
            deviceId: deviceId,
            persistence: positionStore,
            debounceNanoseconds: positionSaveDebounceNs
        )
        self.lifecycle = ReaderLifecycleHelper(
            bookFingerprint: bookFingerprint,
            positionService: posService,
            sessionTracker: sessionTracker,
            positionStore: positionStore,
            statsStore: positionStore as? PersistenceActor
        )
    }

    // MARK: - Private State

    /// Last tocHref from a relocate event, used to populate Locator.href.
    private var lastTOCHref: String?

    // MARK: - Lifecycle

    /// Begins the reading session and updates last-opened timestamp.
    func open() async {
        do {
            try lifecycle.beginSession()
        } catch {
            errorMessage = "Failed to start reading session."
        }
        await lifecycle.updateLastOpened()
    }

    /// Closes the reading session and saves the final position.
    func close() async {
        await lifecycle.close(locator: currentLocator())
    }

    /// Saves position on background.
    func onBackground() async {
        await lifecycle.onBackground(locator: currentLocator())
    }

    /// Resumes session on foreground.
    func onForeground() {
        if let msg = lifecycle.onForeground() {
            errorMessage = msg
        }
    }

    // MARK: - Bridge Event Handlers

    /// Called when Foliate-js sends a `relocate` event.
    func handleRelocate(_ event: FoliateRelocateEvent) {
        currentCFI = event.cfi
        currentProgress = event.fraction.isFinite ? min(max(event.fraction, 0), 1) : 0
        currentTOCLabel = event.tocLabel
        lastTOCHref = event.tocHref

        // Schedule debounced position save via lifecycle helper.
        if let locator = currentLocator() {
            lifecycle.recordProgressAndScheduleSave(locator: locator)
        }
    }

    /// Called when Foliate-js sends a `book-ready` event.
    func handleBookReady(_ title: String, sections: Int) {
        isLoading = false
        errorMessage = nil
    }

    /// Called when Foliate-js sends an `error` event.
    func handleError(_ message: String) {
        errorMessage = message
        isLoading = false
    }

    // MARK: - Locator Construction

    /// Returns a Locator for the current reading position, or nil if no position is known.
    func currentLocator() -> Locator? {
        guard let cfi = currentCFI else { return nil }
        return Locator.validated(
            bookFingerprint: bookFingerprint,
            href: lastTOCHref,
            totalProgression: currentProgress,
            cfi: cfi
        )
    }
}
