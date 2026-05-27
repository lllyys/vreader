// Purpose: `navigate` command handler for the vreader-debug:// scheme (Bug #273
// verification harness — drive `.readerNavigateToLocator` CU-free so feature
// #71 WI-8's EPUB continuous-mode navigation can be device-verified). The
// `search` driver navigates locators in *paged* EPUB but not in *continuous*
// mode, and there is no other CU-free path to a TOC/bookmark/locator jump, so
// this command posts `.debugBridgeNavigateCommand` carrying the target spine
// index (+ optional intra-chapter fraction). The live `EPUBReaderContainerView`
// observer resolves the index → href against `viewModel.metadata`, builds a
// `Locator` with the active book's fingerprint, and re-posts
// `.readerNavigateToLocator` — re-entering the SAME WI-8 handler a real
// TOC/bookmark/search tap hits (no parallel navigation path). DEBUG-only —
// entire file compiled out of Release.
//
// Split from RealDebugBridgeContext.swift for the 300-line LOC guideline
// (mirrors RealDebugBridgeContext+Seek.swift / +ScrollSheet.swift).
//
// @coordinates-with: DebugBridge.swift, DebugCommand.swift,
//   DebugBridgeNotifications.swift, EPUBReaderContainerView.swift
//   (the .debugBridgeNavigateCommand observer), RealDebugBridgeContextTests.swift

#if DEBUG

import Foundation

extension RealDebugBridgeContext {

    /// Bug #273 — drive `.readerNavigateToLocator` for the active EPUB reader.
    ///
    /// Posts `.debugBridgeNavigateCommand` carrying the target `spineIndex`
    /// (and, when supplied, the clamped intra-chapter `fraction`). The live
    /// `EPUBReaderContainerView` observes it, maps the index to its spine
    /// `href`, builds a `Locator` with the open book's fingerprint, and re-posts
    /// `.readerNavigateToLocator` so the WI-8 continuous-scroll coordinator (or
    /// the legacy paged path) performs the jump. If no matching EPUB reader is
    /// loaded the URL is silently a no-op (the same posture as
    /// `seek` / `search` / `present`).
    func navigate(spineIndex: Int, fraction: Double?) async throws {
        var userInfo: [String: Any] = ["spineIndex": spineIndex]
        if let fraction { userInfo["fraction"] = fraction }
        NotificationCenter.default.post(
            name: .debugBridgeNavigateCommand,
            object: nil,
            userInfo: userInfo
        )
        log.info(
            "navigate: posted navigateCommand spine=\(spineIndex, privacy: .public) fraction=\(fraction.map { String($0) } ?? "nil", privacy: .public)"
        )
    }
}

#endif
