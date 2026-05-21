// Purpose: `present` command handler for the vreader-debug:// scheme
// (Bug #253 verification harness sheet-presenter). Posts
// `.debugBridgePresentSheet`; the active reader's observer
// (ReaderContainerView, Bug #253 wiring) maps the (sheet, tab) to the
// SAME `@State` / `annotationsRoute` the chrome buttons set, so the
// presented sheet's rendered content becomes CU-free verifiable via
// `snapshot` + `eval`. DEBUG-only — entire file compiled out of Release.
//
// Split from RealDebugBridgeContext.swift for the 300-line LOC guideline
// (mirrors RealDebugBridgeContext+Provider.swift).
//
// @coordinates-with: DebugBridge.swift, DebugCommand.swift,
//   DebugBridgeNotifications.swift, ReaderContainerView+DebugBridgePresent.swift,
//   DebugPresentSheetEffect.swift, RealDebugBridgeContextTests.swift

#if DEBUG

import Foundation

extension RealDebugBridgeContext {

    /// Bug #253 — present a reader sheet from outside the chrome.
    ///
    /// Posts `.debugBridgePresentSheet` with `sheet` (the `SheetKind`
    /// rawValue) and optional `tab` (parser has already validated the tab
    /// against the sheet's vocabulary). `ReaderContainerView` observes the
    /// notification when a book is open; it resolves a `DebugPresentSheetEffect`
    /// and applies it by setting the SAME `@State` / `annotationsRoute` the
    /// chrome buttons set. If no reader is loaded, the URL is silently a
    /// no-op (the same posture as `tts` / `search` / `highlight`).
    ///
    /// `tab` is omitted from `userInfo` when nil so observers can fall back
    /// to each sheet's default tab without relying on a sentinel value.
    func present(sheet: DebugCommand.SheetKind, tab: String?) async throws {
        var userInfo: [AnyHashable: Any] = ["sheet": sheet.rawValue]
        if let tab {
            userInfo["tab"] = tab
        }
        NotificationCenter.default.post(
            name: .debugBridgePresentSheet,
            object: nil,
            userInfo: userInfo
        )
        log.info(
            "present: posted notification sheet=\(sheet.rawValue, privacy: .public) tab=\(tab ?? "nil", privacy: .public)"
        )
    }
}

#endif
