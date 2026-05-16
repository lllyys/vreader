// Purpose: Tests for shared TXT bridge functions extracted in WI-002.
// Validates postSelectionNotification and buildReaderEditMenu.

import Testing
import Foundation
import UIKit
@testable import vreader

@Suite("TXTBridgeShared")
struct TXTBridgeSharedTests {

    // MARK: - postSelectionNotification

    @Test @MainActor func postSelectionNotificationPostsCorrectInfo() async {
        let tv = UITextView()
        tv.text = "Hello World"
        let range = NSRange(location: 0, length: 5)

        var received: TextSelectionInfo?
        let observer = NotificationCenter.default.addObserver(
            forName: .readerHighlightRequested, object: nil, queue: .main
        ) { note in
            received = note.object as? TextSelectionInfo
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        TXTBridgeShared.postSelectionNotification(
            .readerHighlightRequested, from: tv, range: range
        )

        #expect(received != nil)
        #expect(received?.selectedText == "Hello")
        #expect(received?.startUTF16 == 0)
        #expect(received?.endUTF16 == 5)
    }

    @Test @MainActor func postSelectionNotificationWithChunkOffset() async {
        let tv = UITextView()
        tv.text = "World"
        let range = NSRange(location: 0, length: 5)

        var received: TextSelectionInfo?
        let observer = NotificationCenter.default.addObserver(
            forName: .readerAnnotationRequested, object: nil, queue: .main
        ) { note in
            received = note.object as? TextSelectionInfo
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        TXTBridgeShared.postSelectionNotification(
            .readerAnnotationRequested, from: tv, range: range, chunkOffset: 1000
        )

        #expect(received != nil)
        #expect(received?.selectedText == "World")
        #expect(received?.startUTF16 == 1000)
        #expect(received?.endUTF16 == 1005)
    }

    @Test @MainActor func postSelectionNotificationIgnoresOutOfBoundsRange() {
        let tv = UITextView()
        tv.text = "Hi"
        let range = NSRange(location: 0, length: 999)

        var received: TextSelectionInfo?
        let observer = NotificationCenter.default.addObserver(
            forName: .readerHighlightRequested, object: nil, queue: .main
        ) { note in
            received = note.object as? TextSelectionInfo
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        TXTBridgeShared.postSelectionNotification(
            .readerHighlightRequested, from: tv, range: range
        )

        #expect(received == nil)
    }

    @Test @MainActor func postSelectionNotificationIgnoresEmptyText() {
        let tv = UITextView()
        tv.text = ""
        let range = NSRange(location: 0, length: 0)

        var received: TextSelectionInfo?
        let observer = NotificationCenter.default.addObserver(
            forName: .readerHighlightRequested, object: nil, queue: .main
        ) { note in
            received = note.object as? TextSelectionInfo
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        TXTBridgeShared.postSelectionNotification(
            .readerHighlightRequested, from: tv, range: range
        )

        // Empty range — should still post (empty selection is valid for position marking)
        // But text is empty so range.location + range.length (0) <= nsText.length (0) passes
        #expect(received != nil)
        #expect(received?.selectedText == "")
    }

    // MARK: - postSelectionNotification on .readerSelectionPopoverRequested (WI-7c2 / WI-7c5a)

    /// Feature #60 WI-7c2: the TXT non-chunked bridge swaps its
    /// `editMenuForTextIn` from `buildReaderEditMenu` to a single
    /// `postSelectionNotification(.readerSelectionPopoverRequested, ...)`
    /// + empty UIMenu return.
    ///
    /// WI-7c5a contract change: on `.readerSelectionPopoverRequested`
    /// the helper now delegates to `SelectionPopoverRequest.post`, so
    /// `notification.object` is a typed `SelectionPopoverRequestPayload`
    /// (tokenless when no `requestToken` is passed). Pin that the
    /// presenter-facing shape — readable via
    /// `SelectionPopoverRequest.payload(from:)` — arrives intact, and
    /// that a TXT producer leaves `requestToken` nil.
    @Test @MainActor func postSelectionNotificationOnPopoverRequestRoundTrips() async {
        let tv = UITextView()
        tv.text = "Hello World"
        let range = NSRange(location: 6, length: 5)

        nonisolated(unsafe) var received: SelectionPopoverRequestPayload?
        // queue: nil → synchronous in-thread delivery on the same
        // thread that posts. The post is `@MainActor`, observer set
        // up on MainActor, so the observer body runs synchronously
        // inside the post call. No runloop drain, no cross-fire
        // with other tests on the same notification name.
        let observer = NotificationCenter.default.addObserver(
            forName: .readerSelectionPopoverRequested, object: nil, queue: nil
        ) { note in
            received = SelectionPopoverRequest.payload(from: note)
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        TXTBridgeShared.postSelectionNotification(
            .readerSelectionPopoverRequested, from: tv, range: range
        )

        #expect(received != nil,
                "WI-7c5a: posting on .readerSelectionPopoverRequested must carry a SelectionPopoverRequestPayload so the presenter can parse it.")
        #expect(received?.selection.selectedText == "World")
        #expect(received?.selection.startUTF16 == 6)
        #expect(received?.selection.endUTF16 == 11)
        #expect(received?.requestToken == nil,
                "A TXT producer passes no requestToken — the token is EPUB-only (WI-7c5b).")
    }

    /// Feature #60 WI-7c5a / Codex Gate 4 round 1 (Low): pin the
    /// `requestToken` pass-through. No production TXT/MD caller
    /// passes a token today (the token is EPUB-only), so without
    /// this test a future regression in the helper's delegation to
    /// `SelectionPopoverRequest.post(selection:requestToken:)` would
    /// go uncaught.
    @Test @MainActor func postSelectionNotificationPassesThroughRequestToken() async {
        let tv = UITextView()
        tv.text = "Hello World"
        let range = NSRange(location: 6, length: 5)

        nonisolated(unsafe) var received: SelectionPopoverRequestPayload?
        let observer = NotificationCenter.default.addObserver(
            forName: .readerSelectionPopoverRequested, object: nil, queue: nil
        ) { note in
            received = SelectionPopoverRequest.payload(from: note)
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let requestToken = UUID()
        TXTBridgeShared.postSelectionNotification(
            .readerSelectionPopoverRequested,
            from: tv,
            range: range,
            requestToken: requestToken
        )

        #expect(received?.selection.selectedText == "World")
        #expect(received?.requestToken == requestToken,
                "WI-7c5a: postSelectionNotification must forward requestToken into the posted payload.")
    }

    // MARK: - buildReaderEditMenu

    @Test @MainActor func buildReaderEditMenuIncludesTranslateWhenAvailable() {
        let tv = UITextView()
        tv.text = "Hello World"
        let range = NSRange(location: 0, length: 5)

        let menu = TXTBridgeShared.buildReaderEditMenu(
            range: range, textView: tv, suggestedActions: [],
            isAITranslateAvailable: true
        )

        #expect(menu != nil)
        // Two inline menus: annotation (Highlight + Add Note) and lookup (Define + Translate).
        let children = menu!.children
        #expect(children.count == 2)
        if let annotationMenu = children.first as? UIMenu {
            #expect(annotationMenu.children.count == 2)
            #expect((annotationMenu.children.first as? UIAction)?.title == "Highlight")
            #expect((annotationMenu.children.last as? UIAction)?.title == "Add Note")
        }
        if let lookupMenu = children.last as? UIMenu {
            #expect(lookupMenu.children.count == 2)
            // Define is always present; Translate appears when AI is available.
            let titles = lookupMenu.children.compactMap { ($0 as? UIAction)?.title }
            #expect(titles.contains(DictionaryLookup.defineMenuTitle))
            #expect(titles.contains(DictionaryLookup.translateMenuTitle))
        }
    }

    @Test @MainActor func buildReaderEditMenuOmitsTranslateWhenAIUnavailable() {
        // Bug #90: when AI consent is revoked, the Translate action must NOT
        // appear in the text-selection edit menu.
        let tv = UITextView()
        tv.text = "Hello World"
        let range = NSRange(location: 0, length: 5)

        let menu = TXTBridgeShared.buildReaderEditMenu(
            range: range, textView: tv, suggestedActions: [],
            isAITranslateAvailable: false
        )

        #expect(menu != nil)
        let children = menu!.children
        #expect(children.count == 2)
        if let lookupMenu = children.last as? UIMenu {
            #expect(lookupMenu.children.count == 1, "Lookup menu must contain only Define when AI is unavailable")
            let titles = lookupMenu.children.compactMap { ($0 as? UIAction)?.title }
            #expect(titles == [DictionaryLookup.defineMenuTitle])
            #expect(!titles.contains(DictionaryLookup.translateMenuTitle))
        }
    }

    @Test @MainActor func buildReaderEditMenuPassesThroughSuggestedActionsForEmptyRange() {
        let tv = UITextView()
        tv.text = "Hello"
        let range = NSRange(location: 0, length: 0)
        let suggested = [UIAction(title: "Copy") { _ in }]

        let menu = TXTBridgeShared.buildReaderEditMenu(
            range: range, textView: tv, suggestedActions: suggested
        )

        #expect(menu != nil)
        #expect(menu!.children.count == 1) // only suggested, no custom
    }

    // MARK: - postContentTappedNotification

    @Test @MainActor func postContentTappedNotificationPostsCorrectName() {
        var received = false
        let observer = NotificationCenter.default.addObserver(
            forName: .readerContentTapped, object: nil, queue: .main
        ) { _ in
            received = true
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        TXTBridgeShared.postContentTappedNotification()

        #expect(received == true)
    }
}
