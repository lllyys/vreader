// Purpose: DEBUG-only wiring that presents a reader sheet from the
// `.debugBridgePresentSheet` notification (Bug #253 verification harness).
// The observer in ReaderContainerView calls `handleDebugBridgePresentSheet`,
// which resolves a `DebugPresentSheetEffect` and applies it by setting the
// SAME `@State` / `annotationsRoute` the chrome buttons set — so the harness
// drives the real presentation path (no parallel sheet-presentation logic)
// and the presented sheet's rendered content becomes CU-free verifiable via
// `snapshot` + `eval`.
//
// Entire file compiled out of Release builds via `#if DEBUG`.
//
// @coordinates-with: ReaderContainerView.swift, DebugPresentSheetEffect.swift,
//   AnnotationsSheetRoute.swift, RealDebugBridgeContext+Present.swift,
//   DebugBridgeNotifications.swift

#if DEBUG

import SwiftUI
import OSLog

/// Dedicated `ViewModifier` for the Bug #253 present-sheet observer. Mirrors
/// the `ReaderDebugBridgeSearchObserver` pattern — extracting the `.onReceive`
/// keeps the SwiftUI body inside the type-inference budget.
struct ReaderDebugBridgePresentObserver: ViewModifier {
    let onCommand: (_ sheet: String, _ tab: String?) -> Void

    func body(content: Content) -> some View {
        content.onReceive(
            NotificationCenter.default.publisher(for: .debugBridgePresentSheet)
        ) { notification in
            guard let sheet = notification.userInfo?["sheet"] as? String else { return }
            let tab = notification.userInfo?["tab"] as? String
            onCommand(sheet, tab)
        }
    }
}

extension ReaderContainerView {

    /// Handle a `.debugBridgePresentSheet` notification by presenting the
    /// requested sheet through the SAME `@State` / route the chrome buttons
    /// set. Resolves a `DebugPresentSheetEffect` from the `(sheet, tab)` and:
    ///
    /// - `.annotations(route)` → sets `annotationsRoute` (the bottom-chrome
    ///   Contents/Notes buttons set this too).
    /// - `.ai(initialTab)` → sets `aiInitialTab` + `showAIPanel = true`,
    ///   gated on `resolvedAICoordinator.isAIAvailable` (the chrome's AI
    ///   gate). `ensureAIReady()` runs via the `.onChange(of: showAIPanel)`
    ///   already wired on the body (the same path the chrome AI tap takes).
    /// - `.settings` → sets `showSettings = true` (the Display chrome button).
    ///
    /// An unrecognized `sheet` string (shouldn't happen — the parser
    /// validates `SheetKind`) is ignored. No-op when no reader is presented
    /// — `.onReceive` only delivers to a mounted view, so callers see the
    /// same posture as `tts` / `search` / `highlight`.
    @MainActor
    func handleDebugBridgePresentSheet(sheet: String, tab: String?) {
        let log = Logger(subsystem: "com.vreader.app", category: "DebugBridge")
        guard let kind = DebugCommand.SheetKind(rawValue: sheet) else {
            log.error("present observer: unknown sheet=\(sheet, privacy: .public)")
            return
        }
        log.info(
            "present observer: sheet=\(sheet, privacy: .public) tab=\(tab ?? "nil", privacy: .public)"
        )

        let effect = DebugPresentSheetEffect.resolve(sheet: kind, tab: tab)
        switch effect {
        case .annotations(let route):
            annotationsRoute = route
        case .ai(let initialTab):
            // Mirror the chrome's AI gate (`onAI` in
            // `readerToolbarActionObservers`) — a no-op when AI isn't
            // configured rather than presenting an empty sheet.
            guard resolvedAICoordinator.isAIAvailable else {
                log.info("present observer: AI sheet requested but AI unavailable — no-op")
                return
            }
            // Gate-4 round-1 M1: this is a selectionless cold open (no
            // text-selection drives it), so mirror the production
            // selectionless-translate path (`ReaderOpenAITranslateObserver`):
            // ensure the AI VMs exist, then clear stale Translate-tab state
            // when opening on `.translate`. Without the reset, a prior
            // selection's translated text + result would still be visible —
            // which would corrupt the very verification this command exists
            // to enable. Summarize / Chat carry no stale-translate concern,
            // so the reset is scoped to the translate tab to match production.
            ensureAIReady()
            if initialTab == .translate {
                resolvedAICoordinator.translationViewModel?.reset()
            }
            aiInitialTab = initialTab
            showAIPanel = true
        case .settings:
            showSettings = true
        }
    }
}

#endif
