// Purpose: Declares what each BookFormat can do at runtime.
// A context-aware factory accounts for EPUB complexity.
//
// @coordinates-with: BookFormat.swift — convenience `capabilities` property

/// Feature flags describing what a format's reader engine supports.
struct FormatCapabilities: OptionSet, Sendable, Hashable {
    let rawValue: UInt16

    static let textSelection    = FormatCapabilities(rawValue: 1 << 0)
    static let highlights       = FormatCapabilities(rawValue: 1 << 1)
    static let bookmarks        = FormatCapabilities(rawValue: 1 << 2)
    static let search           = FormatCapabilities(rawValue: 1 << 3)
    static let tts              = FormatCapabilities(rawValue: 1 << 4)
    static let nativePagination = FormatCapabilities(rawValue: 1 << 5)
    static let unifiedReflow    = FormatCapabilities(rawValue: 1 << 6)
    static let toc              = FormatCapabilities(rawValue: 1 << 7)
    static let annotations      = FormatCapabilities(rawValue: 1 << 8)
    /// Bug #156 / GH #456 (initial gate) + bug #157 / GH #461 (TXT
    /// regression-fix): marks formats whose reader host wires
    /// `AutoPageTurner` end-to-end *and* renders pages so the timer's
    /// `nextPage()` call actually advances the visible content.
    /// Currently only **MD** — `MDReaderContainerView` calls
    /// `updatePaginationIfNeeded()` from `.task` + `.onChange(epubLayout)`
    /// + `.onChange(fontSize)` and renders via `pagedReaderContent`
    /// (line 278) which observes `pageNavigator.currentPage`.
    /// TXT was previously included via the `reflowableBase` preset,
    /// but bug #157 confirmed `TXTReaderContainerView.updatePaginationIfNeeded()`
    /// is defined-but-never-called and there is no paged renderer that
    /// observes `pageNavigator.currentPage` — so the toggle silently
    /// no-op'd for every TXT file. Removed from the TXT capability set
    /// to match the bug #156 / EPUB-PDF-AZW3 capability-gate pattern.
    /// `ReaderSettingsPanel.autoPageTurnSection` keys off this flag
    /// to hide the toggle for formats that would silently no-op.
    static let autoPageTurn     = FormatCapabilities(rawValue: 1 << 9)

    // MARK: - Presets

    /// Capabilities shared by every format.
    private static let universal: FormatCapabilities = [.search, .bookmarks]

    /// Base capabilities for reflowable text formats (TXT, MD).
    /// `.autoPageTurn` is intentionally excluded — only MD has end-to-end
    /// AutoPageTurner wiring (bug #157 / GH #461). Add it back to TXT only
    /// when `TXTReaderContainerView` calls `updatePaginationIfNeeded()` and
    /// has a paged renderer mirroring `MDReaderContainerView.pagedReaderContent`.
    private static let reflowableBase: FormatCapabilities = [
        .textSelection, .highlights, .tts,
        .nativePagination, .unifiedReflow, .annotations,
    ]

    // MARK: - Context-Aware Factory

    /// Returns the capability set for `format`, optionally considering
    /// whether an EPUB has complex layout (fixed-layout, heavy CSS, SVG pages).
    ///
    /// - Parameters:
    ///   - format: The book format.
    ///   - isComplexEPUB: When `true` the EPUB loses `.unifiedReflow`.
    ///     Ignored for non-EPUB formats.
    /// - Returns: The resolved capability set.
    static func capabilities(
        for format: BookFormat,
        isComplexEPUB: Bool = false
    ) -> FormatCapabilities {
        switch format {
        case .txt:
            return universal.union(reflowableBase)

        case .md:
            // MD adds `.toc` (heading-derived) and `.autoPageTurn`
            // (bug #157 — only MD has end-to-end paged renderer +
            // AutoPageTurner wiring; see `reflowableBase` doc comment).
            return universal.union(reflowableBase).union([.toc, .autoPageTurn])

        case .epub:
            var caps: FormatCapabilities = [
                .textSelection, .highlights, .tts,
                .nativePagination, .toc, .annotations,
            ]
            caps.formUnion(universal)
            if !isComplexEPUB {
                caps.insert(.unifiedReflow)
            }
            return caps

        case .pdf:
            var caps: FormatCapabilities = [
                .textSelection, .highlights,
                .nativePagination, .annotations,
            ]
            caps.formUnion(universal)
            // PDF never gets TTS or unifiedReflow.
            return caps

        case .azw3:
            // Same as simple EPUB: Foliate-js provides full feature parity.
            var caps: FormatCapabilities = [
                .textSelection, .highlights, .tts,
                .nativePagination, .toc, .annotations, .unifiedReflow,
            ]
            caps.formUnion(universal)
            return caps
        }
    }
}
