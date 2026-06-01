// Purpose: `page` command handler for the vreader-debug:// scheme (feature
// #42/#75 verification harness — drive a page turn CU-free). Posts the shared
// `.readerNextPage` / `.readerPreviousPage` notification that every native
// reader host already observes:
//   • Readium (`ReadiumEPUBHost+Body`) → coordinator `goForward` / `goBackward`;
//   • legacy EPUB (`EPUBReaderContainerView`) → `handleSideTapNext/Previous`;
//   • Foliate (AZW3/MOBI) + TXT/MD/PDF paged → their own observers.
// XCUITest / synthetic idb swipes can't reliably drive Readium's own gesture
// recognizers (the navigator owns its content controller), so this bus-level
// driver is the reliable CU-free path to verify reading-order page navigation —
// including RTL / vertical-rl, where "next" advances in reading order regardless
// of screen edge. DEBUG-only — entire file compiled out of Release.
//
// Split from RealDebugBridgeContext.swift for the 300-line LOC guideline
// (mirrors RealDebugBridgeContext+Navigate.swift / +SetLayout.swift).
//
// @coordinates-with: DebugBridge.swift, DebugCommand.swift,
//   ReaderNotifications.swift (.readerNextPage / .readerPreviousPage),
//   ReadiumEPUBHost+Body.swift, EPUBReaderContainerView.swift,
//   RealDebugBridgeContextTests.swift

#if DEBUG

import Foundation

extension RealDebugBridgeContext {

    /// Feature #42/#75 — drive a reading-order page turn for the active reader.
    ///
    /// Posts `.readerNextPage` (for `.next`) or `.readerPreviousPage` (for
    /// `.prev`) — the SAME notifications a side-tap / swipe produces, so the
    /// active host advances through its real navigation path (no parallel page
    /// logic). If no reader is presented, no host observes it — the URL is
    /// silently a no-op (the same posture as `navigate` / `seek` / `set-layout`).
    func page(direction: DebugCommand.PageDirection) async throws {
        let name: Notification.Name = direction == .next ? .readerNextPage : .readerPreviousPage
        NotificationCenter.default.post(name: name, object: nil)
        log.info("page: posted \(name.rawValue, privacy: .public) (dir=\(direction.rawValue, privacy: .public))")
    }
}

#endif
