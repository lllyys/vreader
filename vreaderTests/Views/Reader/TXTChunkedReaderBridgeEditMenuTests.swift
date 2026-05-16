// Purpose: Feature #60 WI-7c3 — pins the contract change in
// `TXTChunkedReaderBridge.Coordinator.textView(_:editMenuForTextIn:
// suggestedActions:)`. Mirrors WI-7c2's
// `TXTTextViewBridgeEditMenuTests` for the chunked path. Pre-WI-7c3
// the chunked coordinator returned the legacy
// `TXTBridgeShared.buildReaderEditMenu` UIMenu with chunk-offset
// math; post-WI-7c3 it posts `.readerSelectionPopoverRequested` with
// the chunk-adjusted `TextSelectionInfo` and returns an empty
// `UIMenu(children: [])` so the WI-7c1 presenter takes over.
//
// **Chunk offset matters**: the chunked path renders multiple
// `UITextView`s side-by-side (one per chunk). Each textView's local
// NSRange must be translated to the document-global UTF-16 offset
// before downstream (highlight persistence, AI translate, etc.)
// resolves it. The chunk index is carried in `textView.tag`; the
// offset comes from `chunkStartOffsets[tag]`.

#if canImport(UIKit)
import Testing
import Foundation
import UIKit
@testable import vreader

@Suite(
    "Feature #60 WI-7c3 — TXTChunkedReaderBridge.Coordinator editMenuForTextIn",
    .serialized  // Shares NotificationCenter.default for
                 // .readerSelectionPopoverRequested with sibling
                 // WI-7c2 suite. Serialized within the suite to
                 // avoid intra-suite cross-fire; queue:nil
                 // synchronous delivery handles cross-suite.
)
@MainActor
struct TXTChunkedReaderBridgeEditMenuTests {

    private func makeTextView(text: String, chunkIndex: Int) -> UITextView {
        let tv = UITextView()
        tv.text = text
        tv.tag = chunkIndex
        return tv
    }

    @Test("editMenuForTextIn returns an empty UIMenu (suppresses iOS default + suggested actions)")
    func returnsEmptyMenu() {
        let coordinator = TXTChunkedReaderBridge.Coordinator(delegate: nil)
        coordinator.chunkStartOffsets = [0, 100, 200]
        let tv = makeTextView(text: "Hello World", chunkIndex: 0)
        let range = NSRange(location: 0, length: 5)

        let menu = coordinator.textView(tv, editMenuForTextIn: range, suggestedActions: [])

        #expect(menu != nil)
        #expect(menu?.children.isEmpty == true,
                "WI-7c3: TXT chunked bridge must return an empty UIMenu after long-press — the SelectionPopoverView sheet replaces the in-textview menu.")
    }

    @Test("editMenuForTextIn posts .readerSelectionPopoverRequested with chunk-adjusted TextSelectionInfo")
    func postsPopoverRequestWithChunkOffset() {
        // Chunk 2 starts at document UTF-16 offset 200; selecting
        // local range (6, 5) → "World" in "Hello World" must
        // translate to global offsets (206, 211).
        let coordinator = TXTChunkedReaderBridge.Coordinator(delegate: nil)
        coordinator.chunkStartOffsets = [0, 100, 200]
        let tv = makeTextView(text: "Hello World", chunkIndex: 2)
        let range = NSRange(location: 6, length: 5)

        nonisolated(unsafe) var received: TextSelectionInfo?
        let observer = NotificationCenter.default.addObserver(
            forName: .readerSelectionPopoverRequested, object: nil, queue: nil
        ) { note in
            received = note.object as? TextSelectionInfo
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        _ = coordinator.textView(tv, editMenuForTextIn: range, suggestedActions: [])

        #expect(received?.selectedText == "World")
        #expect(received?.startUTF16 == 206,
                "Chunk offset 200 + local 6 = global 206")
        #expect(received?.endUTF16 == 211,
                "Chunk offset 200 + local 6 + length 5 = global 211")
    }

    @Test("editMenuForTextIn with chunk index 0 (no offset) posts correct global range")
    func chunkZeroOffset() {
        // Sanity: the first chunk has offset 0 — the post should
        // mirror the local range exactly (not double-add).
        let coordinator = TXTChunkedReaderBridge.Coordinator(delegate: nil)
        coordinator.chunkStartOffsets = [0, 100]
        let tv = makeTextView(text: "Hello World", chunkIndex: 0)
        let range = NSRange(location: 0, length: 5)

        nonisolated(unsafe) var received: TextSelectionInfo?
        let observer = NotificationCenter.default.addObserver(
            forName: .readerSelectionPopoverRequested, object: nil, queue: nil
        ) { note in
            received = note.object as? TextSelectionInfo
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        _ = coordinator.textView(tv, editMenuForTextIn: range, suggestedActions: [])

        #expect(received?.selectedText == "Hello")
        #expect(received?.startUTF16 == 0)
        #expect(received?.endUTF16 == 5)
    }

    @Test("editMenuForTextIn with zero-length range posts nothing AND returns the empty menu")
    func zeroLengthRange() {
        let coordinator = TXTChunkedReaderBridge.Coordinator(delegate: nil)
        coordinator.chunkStartOffsets = [0, 100]
        let tv = makeTextView(text: "Hello", chunkIndex: 0)
        let range = NSRange(location: 2, length: 0)

        nonisolated(unsafe) var fired = false
        let observer = NotificationCenter.default.addObserver(
            forName: .readerSelectionPopoverRequested, object: nil, queue: nil
        ) { _ in fired = true }
        defer { NotificationCenter.default.removeObserver(observer) }

        let menu = coordinator.textView(tv, editMenuForTextIn: range, suggestedActions: [])

        #expect(menu != nil)
        #expect(menu?.children.isEmpty == true)
        #expect(!fired,
                "Zero-length range (caret placement) must not post — popover is for selections.")
    }

    @Test("editMenuForTextIn with tag out of range falls back to offset 0 (defensive)")
    func tagOutOfRange() {
        // If textView.tag exceeds chunkStartOffsets count (shouldn't
        // happen in practice but defensively pinned by the existing
        // implementation), the offset falls back to 0 — the post
        // should use the raw local range without a wrong chunk
        // shift.
        let coordinator = TXTChunkedReaderBridge.Coordinator(delegate: nil)
        coordinator.chunkStartOffsets = [0, 100]
        let tv = makeTextView(text: "Hello", chunkIndex: 99)  // out of range
        let range = NSRange(location: 0, length: 5)

        nonisolated(unsafe) var received: TextSelectionInfo?
        let observer = NotificationCenter.default.addObserver(
            forName: .readerSelectionPopoverRequested, object: nil, queue: nil
        ) { note in
            received = note.object as? TextSelectionInfo
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        _ = coordinator.textView(tv, editMenuForTextIn: range, suggestedActions: [])

        #expect(received?.selectedText == "Hello")
        #expect(received?.startUTF16 == 0,
                "Out-of-range tag falls back to offset 0 (no spurious shift).")
        #expect(received?.endUTF16 == 5)
    }

    @Test("editMenuForTextIn with negative tag falls back to offset 0 (does NOT crash)")
    func negativeTag() {
        // Codex Gate 4 round 1 (Low): textView.tag is Int and
        // could in principle be negative; the previous bounds
        // check only protected the high side. Clamping on both
        // ends prevents a negative-index subscript crash. In
        // production `cellForRowAt` always sets a non-negative
        // tag — but pinning the defensive behavior here guards
        // against a future regression where the tag isn't
        // pre-initialized.
        let coordinator = TXTChunkedReaderBridge.Coordinator(delegate: nil)
        coordinator.chunkStartOffsets = [0, 100]
        let tv = makeTextView(text: "Hello", chunkIndex: -1)
        let range = NSRange(location: 0, length: 5)

        nonisolated(unsafe) var received: TextSelectionInfo?
        let observer = NotificationCenter.default.addObserver(
            forName: .readerSelectionPopoverRequested, object: nil, queue: nil
        ) { note in
            received = note.object as? TextSelectionInfo
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        _ = coordinator.textView(tv, editMenuForTextIn: range, suggestedActions: [])

        #expect(received?.selectedText == "Hello")
        #expect(received?.startUTF16 == 0,
                "Negative tag falls back to offset 0 (no negative-index crash).")
        #expect(received?.endUTF16 == 5)
    }
}
#endif
