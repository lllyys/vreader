// Purpose: Bug #253 — the reader-host effect a DebugBridge `present`
// command resolves to. Mirrors `ReaderMoreMenuEffect` / `AnnotationsSheetRoute`:
// a pure value type that names what `ReaderContainerView` does when a
// `.debugBridgePresentSheet` notification arrives, decoupled from the
// `@State` mutation so the routing decision is unit-testable without a
// SwiftUI render path.
//
// The fidelity invariant this type pins: `present?sheet=X[&tab=Y]` resolves
// to the SAME `annotationsRoute` / `showAIPanel` / `showSettings` the
// production chrome buttons set (see `ReaderContainerView.readerToolbarActionObservers`
// and `AnnotationsSheetRoute.route(forChromeButton:)`). The harness drives
// the real presentation path — there is no parallel sheet-presentation logic.
//
// DEBUG-only — the DebugBridge harness is compiled out of Release.
//
// @coordinates-with: RealDebugBridgeContext+Present.swift, DebugCommand.swift,
//   ReaderContainerView+DebugBridgePresent.swift, AnnotationsSheetRoute.swift,
//   AIReaderPanel.swift, DebugPresentSheetEffectTests.swift

#if DEBUG

import Foundation

/// The reader-host presentation effect a DebugBridge `present` command
/// triggers. Case names describe the *host action*; the reader-host
/// observer switches on this and sets the matching `@State`.
enum DebugPresentSheetEffect: Equatable {
    /// Present an annotations sheet (`TOCSheet` / `HighlightsSheet`) on the
    /// given route — i.e. set `ReaderContainerView.annotationsRoute`. Reuses
    /// the same `AnnotationsSheetRoute` the bottom-chrome Contents/Notes
    /// buttons set.
    case annotations(AnnotationsSheetRoute)
    /// Present the AI assistant panel (`AIReaderPanel`) on the given initial
    /// tab — i.e. set `aiInitialTab` + `showAIPanel = true`. The observer
    /// gates this on `resolvedAICoordinator.isAIAvailable` (matches the
    /// chrome's AI gate).
    case ai(initialTab: AIReaderTab)
    /// Present the reader settings panel (`ReaderSettingsPanel`) — i.e. set
    /// `showSettings = true`.
    case settings

    /// Resolve the host effect for a `present` command's `(sheet, tab)`.
    ///
    /// The parser has already validated `tab` against the sheet's lowercase
    /// vocabulary (`contents` / `summarize` / …); the view-layer tab enums
    /// (`TOCSheetTab` / `HighlightsSheetFilter` / `AIReaderTab`) have
    /// capitalized rawValues (`Contents` / `Summarize`), so the mapping is an
    /// explicit lowercase→enum switch rather than `init(rawValue:)` (a
    /// rawValue init would silently miss every multi-word/capitalized case).
    /// The `default` arms only fire for the no-tab case (each sheet's
    /// documented default) — an out-of-vocabulary string never reaches this
    /// function. `bookmarks` is a top-level alias for the `TOCSheet` Bookmarks
    /// tab (the "leave the page" navigation surface).
    static func resolve(sheet: DebugCommand.SheetKind, tab: String?) -> DebugPresentSheetEffect {
        switch sheet {
        case .toc:
            return .annotations(.toc(initialTab: tocTab(from: tab)))
        case .highlights:
            return .annotations(.highlights(initialFilter: highlightsFilter(from: tab)))
        case .ai:
            return .ai(initialTab: aiTab(from: tab))
        case .settings:
            return .settings
        case .bookmarks:
            return .annotations(.toc(initialTab: .bookmarks))
        }
    }

    /// Map a validated lowercase `tab` to `TOCSheetTab`.
    ///
    /// The no-tab default delegates to the production chrome routing helper
    /// (`AnnotationsSheetRoute.route(forChromeButton: .contents)`) so the
    /// default `present?sheet=toc` resolves to exactly what the Contents
    /// chrome button sets — one source of truth, no drift (Gate-4 round-1 L1).
    /// Only the explicit `bookmarks` sub-tab (a debug-only selector the chrome
    /// reaches via the TOC sheet's own segmented control, not a chrome button)
    /// is constructed locally.
    private static func tocTab(from tab: String?) -> TOCSheetTab {
        switch tab {
        case "bookmarks":
            return .bookmarks
        case "contents":
            return .contents
        default:
            // Default == the Contents chrome button's route.
            if case .toc(let initialTab) = AnnotationsSheetRoute.route(forChromeButton: .contents) {
                return initialTab
            }
            return .contents
        }
    }

    /// Map a validated lowercase `tab` to `HighlightsSheetFilter`.
    ///
    /// The no-tab default delegates to the production chrome routing helper
    /// (`AnnotationsSheetRoute.route(forChromeButton: .notes)`) so the default
    /// `present?sheet=highlights` resolves to exactly what the Notes chrome
    /// button sets (Gate-4 round-1 L1). The explicit filters
    /// (`highlights` / `notes` / `bookmarks`) are debug-only selectors the
    /// chrome reaches via the sheet's own chip row, so they're local.
    private static func highlightsFilter(from tab: String?) -> HighlightsSheetFilter {
        switch tab {
        case "highlights":
            return .highlights
        case "notes":
            return .notes
        case "bookmarks":
            return .bookmarks
        case "all":
            return .all
        default:
            // Default == the Notes chrome button's route.
            if case .highlights(let filter) = AnnotationsSheetRoute.route(forChromeButton: .notes) {
                return filter
            }
            return .all
        }
    }

    /// Map a validated lowercase `tab` to `AIReaderTab`. Default: `.summarize`.
    private static func aiTab(from tab: String?) -> AIReaderTab {
        switch tab {
        case "translate": return .translate
        case "chat":      return .chat
        case "summarize": return .summarize
        default:          return .summarize
        }
    }
}

#endif
