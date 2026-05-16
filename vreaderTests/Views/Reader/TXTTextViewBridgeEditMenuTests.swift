// Purpose: Feature #60 WI-7c2 — pins the contract change in
// `TXTTextViewBridge.Coordinator.textView(_:editMenuForTextIn:
// suggestedActions:)`. Pre-WI-7c2, the coordinator returned the
// legacy `TXTBridgeShared.buildReaderEditMenu` UIMenu (Highlight /
// Add Note / Define / Translate). Post-WI-7c2 (this PR), it posts
// `.readerSelectionPopoverRequested` to the WI-7c1 presenter and
// returns an empty `UIMenu(children: [])` to suppress the iOS
// surface — the SwiftUI `SelectionPopoverView` sheet now replaces
// the in-textview menu.
//
// Pinned slices:
// 1. Return value is a UIMenu with zero visible elements (iOS shows
//    nothing in place of the old menu).
// 2. Side-effect: `.readerSelectionPopoverRequested` fires with the
//    correct `TextSelectionInfo` payload so the presenter sheet can
//    appear.

#if canImport(UIKit)
import Testing
import Foundation
import UIKit
@testable import vreader

@Suite(
    "Feature #60 WI-7c2 — TXTTextViewBridge.Coordinator editMenuForTextIn",
    .serialized  // Tests in this suite share NotificationCenter.default for
                 // .readerSelectionPopoverRequested. Serialized execution
                 // avoids cross-fire (test A's post arriving at test B's
                 // observer).
)
@MainActor
struct TXTTextViewBridgeEditMenuTests {

    private func makeTextView(text: String) -> UITextView {
        let tv = UITextView()
        tv.text = text
        return tv
    }

    @Test("editMenuForTextIn returns an empty UIMenu (suppresses iOS default + suggested actions)")
    func returnsEmptyMenu() {
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        let tv = makeTextView(text: "Hello World")
        let range = NSRange(location: 0, length: 5)

        let menu = coordinator.textView(tv, editMenuForTextIn: range, suggestedActions: [])

        // The legacy implementation returned a UIMenu with at least
        // 2 sub-menus (annotation + lookup). The WI-7c2 contract is
        // "return an empty menu" — count of children must be 0 so
        // iOS doesn't render anything in place of the old menu.
        // The SwiftUI SelectionPopoverView sheet (WI-7c1) takes over
        // as the visual surface.
        #expect(menu != nil)
        #expect(menu?.children.isEmpty == true,
                "WI-7c2: TXT non-chunked bridge must return an empty UIMenu after long-press — the SelectionPopoverView sheet replaces the in-textview menu.")
    }

    @Test("editMenuForTextIn posts .readerSelectionPopoverRequested with the selection's TextSelectionInfo")
    func postsPopoverRequest() {
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        let tv = makeTextView(text: "Hello World")
        let range = NSRange(location: 6, length: 5)

        // queue: nil → synchronous in-thread delivery. The
        // coordinator's textView call runs on MainActor; the
        // observer body executes synchronously inside the post
        // call (no runloop drain). This makes cross-fire with
        // sibling tests on the same notification name impossible.
        nonisolated(unsafe) var received: TextSelectionInfo?
        let observer = NotificationCenter.default.addObserver(
            forName: .readerSelectionPopoverRequested, object: nil, queue: nil
        ) { note in
            received = note.object as? TextSelectionInfo
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        _ = coordinator.textView(tv, editMenuForTextIn: range, suggestedActions: [])

        #expect(received?.selectedText == "World")
        #expect(received?.startUTF16 == 6)
        #expect(received?.endUTF16 == 11)
    }

    @Test("editMenuForTextIn with zero-length range posts nothing AND returns the empty menu")
    func zeroLengthRange() {
        // Edge case: iOS may invoke editMenuForTextIn with a
        // zero-length range (cursor placement, not selection).
        // The post-WI-7c2 implementation must NOT post in that
        // case (no popover for cursor placement) AND still return
        // the empty UIMenu so iOS doesn't fall back to the legacy
        // surface either.
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        let tv = makeTextView(text: "Hello")
        let range = NSRange(location: 2, length: 0)

        nonisolated(unsafe) var fired = false
        let observer = NotificationCenter.default.addObserver(
            forName: .readerSelectionPopoverRequested, object: nil, queue: nil
        ) { _ in fired = true }
        defer { NotificationCenter.default.removeObserver(observer) }

        let menu = coordinator.textView(tv, editMenuForTextIn: range, suggestedActions: [])

        #expect(menu != nil)
        #expect(menu?.children.isEmpty == true,
                "Zero-length range still returns empty menu — never reverts to the legacy UIMenu.")
        #expect(!fired,
                "Zero-length range must not post .readerSelectionPopoverRequested — popover is for selections, not cursor placement.")
    }
}
#endif
