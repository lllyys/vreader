// Purpose: Feature #64 WI-4 — tests for `FoliateHighlightJSBridge`, the
// pure-logic helper that posts the Foliate recolor / delete JS-notification
// pairs for the unified highlight-action popover.
//
// Foliate (AZW3/MOBI) has no `HighlightRenderer` conformer — its highlight
// visuals are driven entirely by `NotificationCenter` messages keyed on CFI.
// This bridge owns the "extract the CFI from a record's `.epub` anchor +
// post the right notifications" logic so it is unit-testable with a
// NotificationCenter spy, no `WKWebView`.
//
// Covers: recolor → posts `.foliateRequestAnnotationJSDelete` then
// `.foliateRequestAnnotationJSCreate` with the CFI + the new color +
// fingerprintKey; delete → posts BOTH `.readerHighlightRemoved` (UUID) and
// `.foliateRequestAnnotationJSDelete` (CFI); a record with a non-`.epub`
// anchor (legacy/corrupt) → no JS post, no crash.

#if canImport(UIKit)
import Testing
import Foundation
@testable import vreader

@Suite("FoliateHighlightJSBridge")
struct FoliateHighlightJSBridgeTests {

    private let fingerprint = DocumentFingerprint(
        contentSHA256: "foliate_bridge_sha_00000000000000000000000000000000000",
        fileByteCount: 100, format: .azw3
    )

    private func epubAnchorRecord(
        id: UUID = UUID(), cfi: String = "epubcfi(/6/4!/4/2/2)", color: String = "yellow"
    ) -> HighlightRecord {
        let anchor = AnnotationAnchor.epub(
            href: "", cfi: cfi,
            serializedRange: EPUBSerializedRange(
                startContainerPath: "", startOffset: 0, endContainerPath: "", endOffset: 0
            )
        )
        let locator = Locator.validated(bookFingerprint: fingerprint, cfi: cfi)!
        return HighlightRecord(
            highlightId: id, locator: locator, anchor: anchor, profileKey: "k",
            selectedText: "passage", color: color, note: nil,
            createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 2)
        )
    }

    private func textAnchorRecord(id: UUID = UUID()) -> HighlightRecord {
        let anchor = AnnotationAnchor.text(sourceUnitId: "u1", startUTF16: 0, endUTF16: 5)
        let locator = Locator.validated(bookFingerprint: fingerprint, charOffsetUTF16: 0)!
        return HighlightRecord(
            highlightId: id, locator: locator, anchor: anchor, profileKey: "k",
            selectedText: "passage", color: "yellow", note: nil,
            createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 2)
        )
    }

    /// Collects posted notifications synchronously for assertion. Observers
    /// are torn down by an explicit `stop()` (called from the test) rather
    /// than a `deinit` — a `nonisolated deinit` cannot touch this
    /// `@MainActor`-isolated type's stored tokens under Swift 6.
    @MainActor
    private final class NotificationSpy {
        struct Captured { let name: Notification.Name; let object: Any?; let userInfo: [AnyHashable: Any]? }
        private(set) var captured: [Captured] = []
        private var tokens: [NSObjectProtocol] = []

        init(_ names: [Notification.Name]) {
            for name in names {
                let token = NotificationCenter.default.addObserver(
                    forName: name, object: nil, queue: nil
                ) { [weak self] note in
                    self?.captured.append(
                        Captured(name: name, object: note.object, userInfo: note.userInfo)
                    )
                }
                tokens.append(token)
            }
        }

        /// Removes every observer. Each test calls this via `defer` so the
        /// global `NotificationCenter` is not left with stale observers.
        func stop() {
            tokens.forEach { NotificationCenter.default.removeObserver($0) }
            tokens.removeAll()
        }
    }

    // MARK: - Recolor

    @Test @MainActor func recolor_postsDeleteThenCreateWithCFIAndColor() {
        let spy = NotificationSpy([
            .foliateRequestAnnotationJSDelete, .foliateRequestAnnotationJSCreate
        ])
        defer { spy.stop() }
        let record = epubAnchorRecord(cfi: "epubcfi(/6/4!/8)", color: "yellow")
        let bridge = FoliateHighlightJSBridge()

        bridge.recolor(record: record, to: "pink", fingerprintKey: "book-key")

        #expect(spy.captured.count == 2)
        // Delete first, create second — Foliate-js replaces an annotation by
        // delete-then-create.
        #expect(spy.captured[0].name == .foliateRequestAnnotationJSDelete)
        #expect(spy.captured[1].name == .foliateRequestAnnotationJSCreate)

        let deleteInfo = spy.captured[0].userInfo
        #expect(deleteInfo?["cfi"] as? String == "epubcfi(/6/4!/8)")
        #expect(deleteInfo?["fingerprintKey"] as? String == "book-key")

        let createInfo = spy.captured[1].userInfo
        #expect(createInfo?["cfi"] as? String == "epubcfi(/6/4!/8)")
        #expect(createInfo?["color"] as? String == "pink")
        #expect(createInfo?["fingerprintKey"] as? String == "book-key")
    }

    @Test @MainActor func recolor_nonEPUBAnchor_postsNothing() {
        let spy = NotificationSpy([
            .foliateRequestAnnotationJSDelete, .foliateRequestAnnotationJSCreate
        ])
        defer { spy.stop() }
        let record = textAnchorRecord()
        let bridge = FoliateHighlightJSBridge()

        // A legacy/corrupt record whose anchor is not `.epub` — recolor still
        // "succeeds" upstream, but the JS repaint is skipped (no crash).
        bridge.recolor(record: record, to: "blue", fingerprintKey: "book-key")

        #expect(spy.captured.isEmpty)
    }

    @Test @MainActor func recolor_nilAnchor_postsNothing() {
        let spy = NotificationSpy([
            .foliateRequestAnnotationJSDelete, .foliateRequestAnnotationJSCreate
        ])
        defer { spy.stop() }
        let locator = Locator.validated(bookFingerprint: fingerprint, cfi: "x")!
        let record = HighlightRecord(
            highlightId: UUID(), locator: locator, anchor: nil, profileKey: "k",
            selectedText: "p", color: "yellow", note: nil,
            createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 2)
        )
        let bridge = FoliateHighlightJSBridge()
        bridge.recolor(record: record, to: "green", fingerprintKey: "book-key")
        #expect(spy.captured.isEmpty)
    }

    // MARK: - Delete

    @Test @MainActor func delete_postsRemovedAndJSDeleteWithCFI() {
        let spy = NotificationSpy([
            .readerHighlightRemoved, .foliateRequestAnnotationJSDelete
        ])
        defer { spy.stop() }
        let id = UUID()
        let record = epubAnchorRecord(id: id, cfi: "epubcfi(/6/10!/2)")
        let bridge = FoliateHighlightJSBridge()

        bridge.delete(record: record, fingerprintKey: "book-key")

        #expect(spy.captured.count == 2)
        // .readerHighlightRemoved keeps the panel/list in sync (UUID string);
        // .foliateRequestAnnotationJSDelete strips the SVG overlay (CFI).
        let removed = spy.captured.first { $0.name == .readerHighlightRemoved }
        #expect(removed?.object as? String == id.uuidString)

        let jsDelete = spy.captured.first { $0.name == .foliateRequestAnnotationJSDelete }
        #expect(jsDelete?.userInfo?["cfi"] as? String == "epubcfi(/6/10!/2)")
        #expect(jsDelete?.userInfo?["fingerprintKey"] as? String == "book-key")
    }

    /// A delete on a non-`.epub`-anchored record still posts
    /// `.readerHighlightRemoved` (so the panel updates) but skips the JS
    /// overlay strip — the record reopens repainted from persistence.
    @Test @MainActor func delete_nonEPUBAnchor_postsRemovedOnlyNoJS() {
        let spy = NotificationSpy([
            .readerHighlightRemoved, .foliateRequestAnnotationJSDelete
        ])
        defer { spy.stop() }
        let id = UUID()
        let record = textAnchorRecord(id: id)
        let bridge = FoliateHighlightJSBridge()

        bridge.delete(record: record, fingerprintKey: "book-key")

        let removed = spy.captured.filter { $0.name == .readerHighlightRemoved }
        let jsDelete = spy.captured.filter { $0.name == .foliateRequestAnnotationJSDelete }
        #expect(removed.count == 1)
        #expect(removed.first?.object as? String == id.uuidString)
        #expect(jsDelete.isEmpty)
    }
}
#endif
