// Purpose: `set-layout` command handler for the vreader-debug:// scheme
// (feature #75 WI-5a verification harness — switch the active EPUB reader's
// layout preference CU-free so RTL / vertical-rl PAGED paging can be
// device-verified). Feature #75's reading-direction paging only manifests in
// PAGED mode, but XCUITest cannot tap the segmented `Picker(.segmented)` layout
// control on iOS 26 (gh #576), and the `--reader-default-layout=` launch arg
// only pre-seeds the default before a book opens — it does NOT switch an
// already-open reader. This command posts `.debugBridgeSetLayoutCommand`
// carrying the target mode; the live `EPUBReaderContainerView` observer sets
// `settingsStore.epubLayout` — the SAME binding the picker drives, whose
// existing `.onChange(of: settingsStore?.epubLayout)` relayouts the reader (no
// parallel layout path). DEBUG-only — entire file compiled out of Release.
//
// Split from RealDebugBridgeContext.swift for the 300-line LOC guideline
// (mirrors RealDebugBridgeContext+Navigate.swift / +Seek.swift).
//
// @coordinates-with: DebugBridge.swift, DebugCommand.swift,
//   DebugBridgeNotifications.swift, EPUBReaderContainerView.swift
//   (the .debugBridgeSetLayoutCommand observer), RealDebugBridgeContextTests.swift

#if DEBUG

import Foundation

extension RealDebugBridgeContext {

    /// Feature #75 WI-5a — switch the active EPUB reader's layout preference.
    ///
    /// Posts `.debugBridgeSetLayoutCommand` carrying the target `mode`
    /// (`paged` / `scroll`, the `LayoutMode` rawValue). The live
    /// `EPUBReaderContainerView` observes it and sets `settingsStore.epubLayout`
    /// to `EPUBLayoutPreference(rawValue: mode)` — the SAME binding the segmented
    /// picker drives, whose `.onChange` relayouts the reader. If no EPUB reader
    /// is presented the URL is silently a no-op (the same posture as
    /// `navigate` / `seek` / `present`).
    func setLayout(layout: DebugCommand.LayoutMode) async throws {
        NotificationCenter.default.post(
            name: .debugBridgeSetLayoutCommand,
            object: nil,
            userInfo: ["mode": layout.rawValue]
        )
        log.info("set-layout: posted setLayoutCommand mode=\(layout.rawValue, privacy: .public)")
    }
}

#endif
