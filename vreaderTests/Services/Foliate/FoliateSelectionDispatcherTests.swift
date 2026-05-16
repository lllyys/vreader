// Purpose: Bug #201 / GH #739 — pins the cross-boundary contract for
// the Foliate selection → action-sheet bridge.
//
// The bug is that `FoliateSpikeView.Coordinator.handleMessage` registers
// `"selection"` in its WKScriptMessageHandler list but has no
// `case "selection":` branch — falls through to `default: break` (no-op),
// so long-pressing text in AZW3/MOBI brings up iOS's default WKWebView
// menu (Copy/Look Up/…) instead of vreader's Highlight action.
//
// The fix is a `case "selection":` that parses via
// `FoliateMessageParser.parseSelection` and posts a notification the
// outer view consumes. `FoliateSelectionDispatcher` is the pure-logic
// helper that builds the `userInfo` payload — testable in isolation
// without WKWebView, NotificationCenter wiring, or SwiftUI.

import Testing
import Foundation
import CoreGraphics
@testable import vreader

@Suite("Bug #201 — FoliateSelectionDispatcher payload contract")
struct FoliateSelectionDispatcherTests {

    private func makeEvent(
        cfi: String = "epubcfi(/6/4!/4/2)",
        text: String = "the rapidity of the infection",
        sectionIndex: Int = 0
    ) -> FoliateSelectionEvent {
        FoliateSelectionEvent(
            cfi: cfi,
            text: text,
            rect: CGRect(x: 10, y: 20, width: 100, height: 18),
            sectionIndex: sectionIndex
        )
    }

    // MARK: - Happy path

    @Test("Builds userInfo with cfi, text, fingerprintKey, sectionIndex")
    func happyPath() {
        let event = makeEvent()
        let info = FoliateSelectionDispatcher.notificationUserInfo(
            event: event,
            fingerprintKey: "azw3:abc123:2048"
        )
        #expect(info != nil)
        #expect(info?["cfi"] as? String == "epubcfi(/6/4!/4/2)")
        #expect(info?["text"] as? String == "the rapidity of the infection")
        #expect(info?["fingerprintKey"] as? String == "azw3:abc123:2048")
        #expect(info?["sectionIndex"] as? Int == 0)
    }

    // MARK: - Missing identity → bail

    @Test("Returns nil when fingerprintKey is missing")
    func missingFingerprintKey() {
        // FoliateSpikeView's coordinator carries `fingerprintKey: String?`;
        // it can legitimately be nil (preview / test harnesses). When
        // nil, the dispatcher must NOT emit a notification — the outer
        // view cannot route the highlight without an identity.
        let info = FoliateSelectionDispatcher.notificationUserInfo(
            event: makeEvent(),
            fingerprintKey: nil
        )
        #expect(info == nil)
    }

    @Test("Returns nil when fingerprintKey is empty")
    func emptyFingerprintKey() {
        // Empty-string identity is meaningless for routing. Treat it
        // the same as nil rather than letting it propagate downstream.
        let info = FoliateSelectionDispatcher.notificationUserInfo(
            event: makeEvent(),
            fingerprintKey: ""
        )
        #expect(info == nil)
    }

    // MARK: - Edge cases on event content

    @Test("Empty selection text still routes (caller decides)")
    func emptyTextRoutes() {
        // An empty-text event is a parser-side decision; the dispatcher
        // is pure and routes whatever the parser accepted. (In practice
        // `FoliateMessageParser.parseSelection` already rejects
        // collapsed selections, so empty text is unlikely upstream.)
        let info = FoliateSelectionDispatcher.notificationUserInfo(
            event: makeEvent(text: ""),
            fingerprintKey: "azw3:abc:1"
        )
        #expect(info != nil)
        #expect(info?["text"] as? String == "")
    }

    @Test("Long CJK selection round-trips intact")
    func cjkText() {
        let cjk = "围栏内大约有半英亩荒地"
        let info = FoliateSelectionDispatcher.notificationUserInfo(
            event: makeEvent(text: cjk),
            fingerprintKey: "azw3:abc:1"
        )
        #expect(info?["text"] as? String == cjk)
    }

    @Test("Non-zero sectionIndex preserved")
    func nonZeroSection() {
        let info = FoliateSelectionDispatcher.notificationUserInfo(
            event: makeEvent(sectionIndex: 7),
            fingerprintKey: "azw3:abc:1"
        )
        #expect(info?["sectionIndex"] as? Int == 7)
    }

    // MARK: - Notification name shape

    @Test("Notification name is the documented stable identifier")
    func notificationName() {
        // Stable across the cross-format pipeline so observers
        // (FoliateSpikeView+Selection modifier, future Codex audit
        // checks) can match on the raw string without importing Foundation.
        #expect(Notification.Name.foliateSelectionDetected.rawValue
                == "vreader.foliateSelectionDetected")
    }
}
