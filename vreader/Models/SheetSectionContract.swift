// Purpose: Feature #60 visual-identity v2 (WI-10) — the section
// contract for the 5 re-skinned app sheets. Each sheet's section list
// + ordering is pinned here from the committed design bundle so the
// WI-10 composition tests can assert "each re-skinned sheet contains
// the expected sections in the expected order" without a SwiftUI
// render path.
//
// Section sets are pinned to `dev-docs/designs/vreader-fidelity-v1/
// project/vreader-panels.jsx`:
//   - `ReaderSettingsSheet` ("Display")
//   - `TOCSheet`
//   - `HighlightsSheet` ("Annotations")
//   - `AISheet`
//   - `SettingsSheet` ("Settings")
//
// Key decisions:
// - **The contract is data, not a render assertion.** A composition
//   test pins the design's section order; the re-skinned views read
//   the same contract for their section headers, so the design spec
//   has one home (the same pattern as `LibraryCardTokens`).
// - **Foundation-only enum** — compiles in the test target without
//   SwiftUI.
//
// @coordinates-with: ReaderSettingsPanel.swift, TOCSheet.swift,
//   HighlightsSheet.swift, AIReaderPanel.swift, SettingsView.swift,
//   SheetReSkinSnapshotTests.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`

import Foundation

/// The 5 app sheets re-skinned in feature #60 WI-10. Each case carries
/// its design title and ordered section list.
enum ReaderSheetKind: String, CaseIterable, Sendable {
    /// Reader display settings — design `ReaderSettingsSheet`.
    case display
    /// Table of contents + bookmarks — design `TOCSheet`.
    case tableOfContents
    /// Highlights / notes — design `HighlightsSheet`.
    case annotations
    /// AI assistant — design `AISheet`.
    case aiAssistant
    /// App settings — design `SettingsSheet`.
    case appSettings

    /// The sheet's design title. The TOC sheet's title is the book
    /// title at runtime — the design shows a sample ("Pride and
    /// Prejudice"); `nil` here means "set at runtime". The AI sheet
    /// draws a custom header instead of the standard title bar, so its
    /// chrome title is `nil`.
    var designTitle: String? {
        switch self {
        case .display:         return "Display"
        case .tableOfContents: return nil    // runtime: the book title
        case .annotations:     return "Annotations"
        case .aiAssistant:     return nil    // custom sparkle header
        case .appSettings:     return "Settings"
        }
    }

    /// The ordered section labels for this sheet, pinned to the design
    /// bundle. The composition test asserts the re-skinned view's
    /// section headers match this list exactly.
    var sections: [String] {
        switch self {
        case .display:
            // `ReaderSettingsSheet`: a brightness slider, then the
            // labelled Theme / Font / Size / Line spacing / Margin
            // sections (`SectionLabel`s).
            return ["Brightness", "Theme", "Font", "Size",
                    "Line spacing", "Margin"]
        case .tableOfContents:
            // `TOCSheet`: a Contents / Bookmarks tab pair.
            return ["Contents", "Bookmarks"]
        case .annotations:
            // `HighlightsSheet`: the All / Highlights / Notes /
            // Bookmarks filter-chip row.
            return ["All", "Highlights", "Notes", "Bookmarks"]
        case .aiAssistant:
            // `AISheet`: the Summarize / Chat / Translate tab triple.
            return ["Summarize", "Chat", "Translate"]
        case .appSettings:
            // `SettingsSheet`: the four grouped `SectionLabel`s. Note —
            // the app's `SettingsView` declares Cloud & Sync / Reading
            // / About itself and delegates the "AI" group to the
            // feature-#50 `AISettingsSection` composite (which
            // internally sub-divides). This contract is the design's
            // four-group spec; `SettingsView.sectionsForTesting`
            // reports only the three directly-declared groups.
            return ["Cloud & Sync", "AI", "Reading", "About"]
        }
    }
}
