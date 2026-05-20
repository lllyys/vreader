// Purpose: Bug #229 / GH #938 regression tests for
// `HighlightListViewModel.removeHighlight` — the Annotations-panel delete path
// must strip the live Foliate-js SVG overlay on AZW3/MOBI books by posting
// `.foliateRequestAnnotationJSDelete` (CFI-keyed) alongside the existing
// `.readerHighlightRemoved` (UUID-keyed) so the rendered annotation
// disappears without waiting for the next book reopen.
//
// Split from `HighlightListViewModelTests.swift` to keep each test file under
// the ~300-line guideline (`.claude/rules/50-codebase-conventions.md` §9) —
// the same per-concern split pattern the codebase already uses for
// `HighlightsSheet+Support.swift` / `HighlightsSheet+Export.swift`.
//
// @coordinates-with: HighlightListViewModel.swift, FoliateHighlightJSBridge.swift
//   (the in-reader-popover sibling — shape parity with this panel-delete path),
//   FoliateSpikeView.swift (the live observer that consumes the CFI userInfo),
//   ReaderNotifications.swift (the .foliateRequestAnnotationJSDelete contract)

import Testing
import Foundation
@testable import vreader

/// Bug #229 / GH #938: when the Annotations panel deletes a highlight on an
/// AZW3/MOBI book, the rendered Foliate-js SVG overlay must be stripped
/// without waiting for the next book reopen. The fix plumbs the deleted
/// record's `.epub` anchor CFI through `.foliateRequestAnnotationJSDelete`
/// (the existing dormant Foliate-coordinator hook) alongside the existing
/// `.readerHighlightRemoved`. Mirrors `FoliateHighlightJSBridge.delete`
/// — the in-reader popover's delete path — so the panel path and the
/// in-reader path converge on the same notification contract (same names,
/// same userInfo shape, same emission order).
@Suite("HighlightListViewModel - Foliate Overlay Strip (Bug #229)")
@MainActor
struct HighlightListViewModelFoliateOverlayStripTests {

    /// Collects posted notifications synchronously for assertion. Mirrors
    /// `FoliateHighlightJSBridgeTests.NotificationSpy` — same explicit `stop()`
    /// pattern (a `nonisolated deinit` cannot touch this @MainActor type's
    /// stored tokens under Swift 6).
    @MainActor
    private final class NotificationSpy {
        struct Captured {
            let name: Notification.Name
            let object: Any?
            let userInfo: [AnyHashable: Any]?
        }
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

        func stop() {
            tokens.forEach { NotificationCenter.default.removeObserver($0) }
            tokens.removeAll()
        }
    }

    private static let azw3Fingerprint = DocumentFingerprint(
        contentSHA256: "azw3_bug229_sha_0000000000000000000000000000000000000000000000",
        fileByteCount: 4096,
        format: .azw3
    )

    /// Builds an `.epub`-anchored highlight record (AZW3/MOBI highlights store
    /// the `.epub` anchor because Foliate-js is CFI-based).
    private func epubAnchoredRecord(
        cfi: String = "epubcfi(/6/4!/4/2/2)",
        fingerprint: DocumentFingerprint = azw3Fingerprint
    ) -> HighlightRecord {
        let anchor = AnnotationAnchor.epub(
            href: "chapter1.xhtml",
            cfi: cfi,
            serializedRange: EPUBSerializedRange(
                startContainerPath: "/html/body/p[1]/text()",
                startOffset: 0,
                endContainerPath: "/html/body/p[1]/text()",
                endOffset: 10
            )
        )
        let locator = LocatorFactory.epub(
            fingerprint: fingerprint,
            href: "chapter1.xhtml",
            progression: 0.25
        )!
        return HighlightRecord(
            highlightId: UUID(),
            locator: locator,
            anchor: anchor,
            profileKey: "\(locator.bookFingerprint.canonicalKey):\(locator.canonicalHash)",
            selectedText: "passage",
            color: "yellow",
            note: nil,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
    }

    /// Builds a `.text`-anchored highlight record (the TXT/MD path — for the
    /// negative branch where the JS strip must be skipped).
    private func textAnchoredRecord(
        fingerprint: DocumentFingerprint = wi9TXTFingerprint
    ) -> HighlightRecord {
        let anchor = AnnotationAnchor.text(sourceUnitId: "u1", startUTF16: 0, endUTF16: 5)
        let locator = makeTXTRangeLocator(fingerprint: fingerprint, start: 0, end: 5)
        return HighlightRecord(
            highlightId: UUID(),
            locator: locator,
            anchor: anchor,
            profileKey: "\(locator.bookFingerprint.canonicalKey):\(locator.canonicalHash)",
            selectedText: "passage",
            color: "yellow",
            note: nil,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
    }

    @Test("AZW3/MOBI (.epub anchor) panel-delete posts .readerHighlightRemoved THEN .foliateRequestAnnotationJSDelete with the record's CFI + fingerprintKey")
    func epubAnchoredPanelDelete_postsRemovedAndJSDelete() async {
        let spy = NotificationSpy([
            .readerHighlightRemoved,
            .foliateRequestAnnotationJSDelete,
        ])
        defer { spy.stop() }

        let store = MockHighlightStore()
        let bookKey = Self.azw3Fingerprint.canonicalKey
        let record = epubAnchoredRecord(cfi: "epubcfi(/6/4!/8)")
        await store.seed(record, forBookWithKey: bookKey)

        let vm = HighlightListViewModel(
            bookFingerprintKey: bookKey,
            store: store,
            totalTextLengthUTF16: nil
        )
        await vm.loadHighlights()
        #expect(vm.highlights.count == 1)

        await vm.removeHighlight(highlightId: record.highlightId)

        #expect(vm.highlights.isEmpty)

        // Ordering matters — the fix mirrors `FoliateHighlightJSBridge.delete`,
        // which emits `.readerHighlightRemoved` (panel/list sync) BEFORE
        // `.foliateRequestAnnotationJSDelete` (SVG overlay strip). Verifying
        // the exact sequence prevents a future reorder from silently breaking
        // path parity between the panel-delete and in-reader-delete paths.
        #expect(spy.captured.count == 2)
        #expect(spy.captured.map(\.name) == [
            .readerHighlightRemoved,
            .foliateRequestAnnotationJSDelete,
        ])

        // .readerHighlightRemoved (UUID — panel/list sync) is posted unchanged.
        let removed = spy.captured[0]
        #expect(removed.object as? String == record.highlightId.uuidString)

        // .foliateRequestAnnotationJSDelete (CFI — strips the SVG overlay)
        // carries the CFI from the captured record's .epub anchor and the
        // book's fingerprintKey (Foliate Coordinator filters on fingerprintKey
        // to scope concurrent readers).
        let jsDelete = spy.captured[1]
        #expect(jsDelete.userInfo?["cfi"] as? String == "epubcfi(/6/4!/8)")
        #expect(jsDelete.userInfo?["fingerprintKey"] as? String == bookKey)
    }

    @Test("the CFI must be captured BEFORE persistence delete (a post-hoc fetch would miss it)")
    func cfiCapturedBeforeDelete() async {
        let spy = NotificationSpy([.foliateRequestAnnotationJSDelete])
        defer { spy.stop() }

        let store = MockHighlightStore()
        let bookKey = Self.azw3Fingerprint.canonicalKey
        let record = epubAnchoredRecord(cfi: "epubcfi(/6/4!/12)")
        await store.seed(record, forBookWithKey: bookKey)

        let vm = HighlightListViewModel(
            bookFingerprintKey: bookKey,
            store: store,
            totalTextLengthUTF16: nil
        )
        await vm.loadHighlights()

        await vm.removeHighlight(highlightId: record.highlightId)

        // Persistence holds nothing after the delete.
        let remaining = try? await store.fetchHighlights(forBookWithKey: bookKey)
        #expect(remaining?.isEmpty == true)
        // But the overlay-strip notification still carried the CFI — i.e. the
        // VM captured the record from its in-memory `highlights` (or via a
        // pre-delete fetch) BEFORE deleting, not after.
        let jsDelete = spy.captured.first { $0.name == .foliateRequestAnnotationJSDelete }
        #expect(jsDelete?.userInfo?["cfi"] as? String == "epubcfi(/6/4!/12)")
    }

    @Test("non-.epub-anchored record (TXT path) posts ONLY .readerHighlightRemoved — no JS overlay strip")
    func nonEpubAnchoredPanelDelete_postsRemovedOnlyNoJS() async {
        let spy = NotificationSpy([
            .readerHighlightRemoved,
            .foliateRequestAnnotationJSDelete,
        ])
        defer { spy.stop() }

        let store = MockHighlightStore()
        let bookKey = wi9TXTFingerprint.canonicalKey
        let record = textAnchoredRecord()
        await store.seed(record, forBookWithKey: bookKey)

        let vm = HighlightListViewModel(
            bookFingerprintKey: bookKey,
            store: store,
            totalTextLengthUTF16: nil
        )
        await vm.loadHighlights()

        await vm.removeHighlight(highlightId: record.highlightId)

        let removed = spy.captured.filter { $0.name == .readerHighlightRemoved }
        let jsDelete = spy.captured.filter { $0.name == .foliateRequestAnnotationJSDelete }
        #expect(removed.count == 1)
        #expect(removed.first?.object as? String == record.highlightId.uuidString)
        // A TXT highlight has no CFI — the Foliate JS strip is skipped.
        // The TXT bridge observes `.readerHighlightRemoved` and handles its
        // own cleanup.
        #expect(jsDelete.isEmpty)
    }

    @Test("nil-anchor highlight (legacy / pre-anchor record) posts ONLY .readerHighlightRemoved")
    func nilAnchoredPanelDelete_postsRemovedOnlyNoJS() async {
        let spy = NotificationSpy([
            .readerHighlightRemoved,
            .foliateRequestAnnotationJSDelete,
        ])
        defer { spy.stop() }

        let store = MockHighlightStore()
        let bookKey = Self.azw3Fingerprint.canonicalKey
        let locator = LocatorFactory.epub(
            fingerprint: Self.azw3Fingerprint,
            href: "chapter1.xhtml",
            progression: 0.1
        )!
        let record = HighlightRecord(
            highlightId: UUID(),
            locator: locator,
            anchor: nil,  // legacy / pre-anchor record
            profileKey: "\(locator.bookFingerprint.canonicalKey):\(locator.canonicalHash)",
            selectedText: "passage",
            color: "yellow",
            note: nil,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        await store.seed(record, forBookWithKey: bookKey)

        let vm = HighlightListViewModel(
            bookFingerprintKey: bookKey,
            store: store,
            totalTextLengthUTF16: nil
        )
        await vm.loadHighlights()

        await vm.removeHighlight(highlightId: record.highlightId)

        // .readerHighlightRemoved is posted unconditionally for panel/list
        // sync; the JS strip is skipped (no CFI to plumb). A reopen repaints
        // from persistence — the record is gone, so the overlay clears then.
        let removed = spy.captured.filter { $0.name == .readerHighlightRemoved }
        let jsDelete = spy.captured.filter { $0.name == .foliateRequestAnnotationJSDelete }
        #expect(removed.count == 1)
        #expect(removed.first?.object as? String == record.highlightId.uuidString)
        #expect(jsDelete.isEmpty)
    }

    @Test("an empty CFI string on an .epub anchor (corrupt) posts ONLY .readerHighlightRemoved — never a no-op JS post")
    func emptyCfiAnchoredPanelDelete_postsRemovedOnlyNoJS() async {
        let spy = NotificationSpy([
            .readerHighlightRemoved,
            .foliateRequestAnnotationJSDelete,
        ])
        defer { spy.stop() }

        let store = MockHighlightStore()
        let bookKey = Self.azw3Fingerprint.canonicalKey
        let locator = LocatorFactory.epub(
            fingerprint: Self.azw3Fingerprint,
            href: "chapter1.xhtml",
            progression: 0.1
        )!
        let record = HighlightRecord(
            highlightId: UUID(),
            locator: locator,
            anchor: .epub(
                href: "chapter1.xhtml",
                cfi: "",  // corrupt / empty
                serializedRange: EPUBSerializedRange(
                    startContainerPath: "", startOffset: 0,
                    endContainerPath: "", endOffset: 0
                )
            ),
            profileKey: "\(locator.bookFingerprint.canonicalKey):\(locator.canonicalHash)",
            selectedText: "passage",
            color: "yellow",
            note: nil,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        await store.seed(record, forBookWithKey: bookKey)

        let vm = HighlightListViewModel(
            bookFingerprintKey: bookKey,
            store: store,
            totalTextLengthUTF16: nil
        )
        await vm.loadHighlights()
        await vm.removeHighlight(highlightId: record.highlightId)

        let removed = spy.captured.filter { $0.name == .readerHighlightRemoved }
        let jsDelete = spy.captured.filter { $0.name == .foliateRequestAnnotationJSDelete }
        #expect(removed.count == 1)
        // Mirrors `FoliateHighlightJSBridge.cfi(from:)` — empty CFI is treated
        // as no CFI; never emit a notification the observer would reject.
        #expect(jsDelete.isEmpty)
    }

    @Test("persistence delete failure: no .readerHighlightRemoved, no .foliateRequestAnnotationJSDelete — error path stays atomic")
    func deleteFailure_postsNothing() async {
        let spy = NotificationSpy([
            .readerHighlightRemoved,
            .foliateRequestAnnotationJSDelete,
        ])
        defer { spy.stop() }

        let store = MockHighlightStore()
        let bookKey = Self.azw3Fingerprint.canonicalKey
        let record = epubAnchoredRecord()
        await store.seed(record, forBookWithKey: bookKey)
        // Configure the store to fail on `removeHighlight`.
        await store.setRemoveError(WI9TestError.mockFailure)

        let vm = HighlightListViewModel(
            bookFingerprintKey: bookKey,
            store: store,
            totalTextLengthUTF16: nil
        )
        await vm.loadHighlights()

        await vm.removeHighlight(highlightId: record.highlightId)

        // The record stays in the VM's list (the persistence delete threw).
        #expect(vm.highlights.contains(where: { $0.highlightId == record.highlightId }))
        #expect(vm.errorMessage != nil)
        // Neither notification is posted — the error path must be atomic so
        // the Foliate overlay does not strip a highlight that is still in
        // persistence.
        #expect(spy.captured.isEmpty)
    }
}
