// Purpose: ViewModel for the Markdown reader view. Manages reading state,
// position persistence (via ReaderPositionService), session tracking, and rendered content.
//
// Key decisions:
// - @Observable + @MainActor for SwiftUI integration.
// - Position persistence delegated to ReaderPositionService (WI-008c).
// - File loading delegated to MDFileLoader (WI-008c).
// - Lifecycle operations (session, flush, time display) delegated to ReaderLifecycleHelper (R6).
// - Uses protocol abstractions for testability (parser, persistence, tracker).
// - Position uses canonical UTF-16 offsets over rendered text.
// - Empty document: totalProgression = nil (no division by zero).
//
// @coordinates-with: MDFileLoader.swift, ReaderLifecycleHelper.swift,
//   ReaderPositionService.swift, MDParserProtocol.swift,
//   ReadingPositionPersisting.swift, ReadingSessionTracker.swift,
//   LocatorFactory.swift, TXTTextViewBridge.swift

import Foundation

/// ViewModel for the Markdown reader screen.
@Observable
@MainActor
final class MDReaderViewModel {

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

    /// Formatted session reading time (e.g., "5m"). Delegated to lifecycle helper.
    var sessionTimeDisplay: String? { lifecycle.sessionTimeDisplay }

    // MARK: - Computed State

    /// Total progression through the document (0.0 to 1.0). Nil for empty files.
    var totalProgression: Double? {
        guard renderedTextLengthUTF16 > 0 else { return nil }
        return Double(currentOffsetUTF16) / Double(renderedTextLengthUTF16)
    }

    // MARK: - Dependencies

    let bookFingerprint: DocumentFingerprint
    let bookFingerprintKey: String
    let lifecycle: ReaderLifecycleHelper
    private let parser: any MDParserProtocol
    private let positionStore: any ReadingPositionPersisting
    private let sessionTracker: ReadingSessionTracker
    private let positionService: ReaderPositionService

    // MARK: - Private State

    /// Generation counter to guard against open/close races.
    private var openGeneration: Int = 0
    /// True after open() completes position restore. Guards close() from saving
    /// stale position 0 when close() races with an in-progress open().
    private var isOpenComplete = false

    // MARK: - Init

    init(
        bookFingerprint: DocumentFingerprint,
        parser: any MDParserProtocol,
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
            positionStore: positionStore
        )
    }

    // MARK: - Lifecycle

    /// Opens the Markdown file, parses it, and restores the saved reading position.
    ///
    /// Bug #178 / GH #606: `chineseConversion` (default `.none`) is forwarded
    /// to `MDFileLoader.load` which applies `SimpTradTransform` to the source
    /// text before Markdown parsing. Pass `settingsStore?.chineseConversion`
    /// from the call site. Live re-apply on conversion-toggle is deferred
    /// (would require a close + reopen cycle); for now the conversion is
    /// applied at open time only.
    ///
    /// Feature #68: `renderConfig` (default `.default`) is forwarded to
    /// `MDFileLoader.load` so the rendered attributed string picks up the
    /// theme-aware body colors, and is also used to run
    /// `MDChapterStartDecorator` over the result (drop-cap + leading-heading
    /// restyle). Pass `settingsStore?.mdRenderConfig` from the call site.
    /// MD has no live theme re-render path — the chapter-start colors apply
    /// on the next open of the file, consistent with the Chinese-conversion
    /// limitation above.
    func open(
        url: URL,
        renderConfig: MDRenderConfig = .default,
        chineseConversion: ChineseConversionDirection = .none
    ) async {
        guard !isLoading else { return }

        // Guard against re-open
        if renderedText != nil {
            await close()
        }

        openGeneration += 1
        let myGeneration = openGeneration
        isOpenComplete = false

        isLoading = true
        errorMessage = nil

        // Stage 1+2: Read, parse, and restore position (via MDFileLoader)
        let loadResult: MDLoadResult
        do {
            loadResult = try await MDFileLoader.load(
                url: url,
                parser: parser,
                positionStore: positionStore,
                bookFingerprintKey: bookFingerprintKey,
                renderConfig: renderConfig,
                chineseConversion: chineseConversion
            )
        } catch is CancellationError {
            resetState()
            isLoading = false
            return
        } catch {
            resetState()
            isLoading = false
            errorMessage = "Failed to open file."
            return
        }

        // Guard: another open() may have started while we were loading
        guard myGeneration == openGeneration else {
            isLoading = false
            return
        }

        renderedText = loadResult.documentInfo.renderedText
        // Feature #68: apply the chapter-start typography (drop-cap +
        // leading-heading restyle). The decorator only adds attributes —
        // `renderedText` above stays the byte-identical undecorated
        // string, so all UTF-16 offset math (positions/highlights/search)
        // is unaffected.
        #if canImport(UIKit)
        renderedAttributedString = MDChapterStartDecorator.decorate(
            loadResult.documentInfo.renderedAttributedString,
            headings: loadResult.documentInfo.headings,
            config: renderConfig
        )
        #else
        renderedAttributedString = loadResult.documentInfo.renderedAttributedString
        #endif
        renderedTextLengthUTF16 = loadResult.documentInfo.renderedTextLengthUTF16
        currentOffsetUTF16 = loadResult.restoredOffsetUTF16

        // PERFORMANCE: Show content immediately — session/lastOpened are non-blocking
        isOpenComplete = true
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
        // Invalidate generation so any in-flight open() becomes stale
        openGeneration += 1

        let locator = (renderedText != nil && isOpenComplete) ? makeLocator() : nil
        await lifecycle.close(locator: locator)

        resetState()
    }

    /// Called when the app moves to background while reader is open.
    /// Awaits the position save to guarantee it completes before iOS suspends.
    func onBackground() async {
        let locator = renderedText != nil ? makeLocator() : nil
        await lifecycle.onBackground(locator: locator)
    }

    /// Called when the app returns to foreground with reader open.
    func onForeground() {
        guard renderedText != nil else { return }
        if let error = lifecycle.onForeground() {
            errorMessage = error
        }
    }

    // MARK: - Position Updates

    /// Called when the scroll position changes. Offset is in UTF-16 code units.
    func updateScrollPosition(charOffsetUTF16: Int) {
        let clamped = clampOffset(charOffsetUTF16)
        currentOffsetUTF16 = clamped

        lifecycle.recordProgressAndScheduleSave(locator: makeLocator())
    }

    // MARK: - Locator Construction

    func makeLocator() -> Locator {
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

    // MARK: - Private: State Reset

    private func resetState() {
        renderedText = nil
        renderedAttributedString = nil
        renderedTextLengthUTF16 = 0
        currentOffsetUTF16 = 0
        isOpenComplete = false
    }

    // MARK: - Private: Offset Clamping

    private func clampOffset(_ offset: Int) -> Int {
        min(max(offset, 0), renderedTextLengthUTF16)
    }
}

// MARK: - TXTTextViewBridgeDelegate Conformance

#if canImport(UIKit)
extension MDReaderViewModel: TXTTextViewBridgeDelegate {
    func scrollPositionDidChange(topCharOffsetUTF16: Int) {
        updateScrollPosition(charOffsetUTF16: topCharOffsetUTF16)
    }

    func selectionDidChange(utf16Range: UTF16Range) {
        // MD reader does not support selection tracking yet
    }
}
#endif
