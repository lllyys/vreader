// Purpose: Bug #207 / GH #765 — pins the dispatch contract that
// fans an array of `HighlightRecord`s out as per-CFI
// `.foliateRequestAnnotationJSCreate` notifications.
//
// The router lives between the SwiftUI restore modifier (which
// has `@Environment(\.modelContext)` and queries persistence) and
// the FoliateSpikeView Coordinator's existing
// `.foliateRequestAnnotationJSCreate` observer (which holds the
// live WKWebView). Keeping the fan-out in a pure-logic helper —
// rather than inline in the modifier — lets the contract be tested
// without SwiftUI / WKWebView / NotificationCenter globals.

#if canImport(UIKit)
import Testing
import Foundation
@testable import vreader

@MainActor
@Suite("Bug #207 — FoliateHighlightRestoreDispatcher fans HighlightRecords out as per-CFI notifications")
struct FoliateHighlightRestoreDispatcherTests {

    /// Builds a HighlightRecord with an EPUB anchor carrying the
    /// given CFI. Other fields are stubs — the dispatcher cares
    /// only about anchor.cfi + color + the surrounding fingerprintKey.
    private func makeEpubHighlight(
        cfi: String,
        color: String = "yellow"
    ) -> HighlightRecord {
        let fp = DocumentFingerprint(
            contentSHA256: String(repeating: "a", count: 64),
            fileByteCount: 1024,
            format: .azw3
        )
        let locator = Locator(
            bookFingerprint: fp,
            href: nil, progression: nil, totalProgression: nil,
            cfi: cfi,
            page: nil, charOffsetUTF16: nil,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let anchor = AnnotationAnchor.epub(
            href: "",
            cfi: cfi,
            serializedRange: EPUBSerializedRange(
                startContainerPath: "",
                startOffset: 0,
                endContainerPath: "",
                endOffset: 0
            )
        )
        return HighlightRecord(
            highlightId: UUID(),
            locator: locator,
            anchor: anchor,
            profileKey: fp.canonicalKey,
            selectedText: "stub",
            color: color,
            note: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    /// Builds a HighlightRecord with a TEXT anchor (no CFI). Used to
    /// prove the dispatcher skips non-Foliate-compatible highlights
    /// rather than throwing.
    private func makeTextHighlight() -> HighlightRecord {
        let fp = DocumentFingerprint(
            contentSHA256: String(repeating: "b", count: 64),
            fileByteCount: 1024,
            format: .txt
        )
        let locator = Locator(
            bookFingerprint: fp,
            href: nil, progression: nil, totalProgression: nil,
            cfi: nil, page: nil, charOffsetUTF16: 0,
            charRangeStartUTF16: 0, charRangeEndUTF16: 5,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let anchor = AnnotationAnchor.text(
            sourceUnitId: "chapter-0",
            startUTF16: 0,
            endUTF16: 5
        )
        return HighlightRecord(
            highlightId: UUID(),
            locator: locator,
            anchor: anchor,
            profileKey: fp.canonicalKey,
            selectedText: "stub",
            color: "yellow",
            note: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    /// Isolated notification center so concurrent test traffic
    /// doesn't cross-fire into our observers.
    private func makeIsolatedCenter() -> NotificationCenter {
        NotificationCenter()
    }

    @Test("dispatches one .foliateRequestAnnotationJSCreate per EPUB-anchored highlight")
    func dispatchesPerHighlight() {
        let center = makeIsolatedCenter()
        var received: [[String: Any]] = []
        let token = center.addObserver(
            forName: .foliateRequestAnnotationJSCreate,
            object: nil,
            queue: nil
        ) { note in
            if let info = note.userInfo as? [String: Any] {
                received.append(info)
            }
        }
        defer { center.removeObserver(token) }

        let highlights = [
            makeEpubHighlight(cfi: "epubcfi(/6/4!/4/2)", color: "yellow"),
            makeEpubHighlight(cfi: "epubcfi(/6/6!/4/2)", color: "pink"),
            makeEpubHighlight(cfi: "epubcfi(/6/8!/4/2)", color: "green"),
        ]
        let dispatched = FoliateHighlightRestoreDispatcher.dispatch(
            highlights: highlights,
            fingerprintKey: "azw3:abc:1",
            notificationCenter: center
        )

        #expect(dispatched == 3)
        #expect(received.count == 3)
        #expect(received.compactMap { $0["cfi"] as? String }.sorted() ==
                ["epubcfi(/6/4!/4/2)", "epubcfi(/6/6!/4/2)", "epubcfi(/6/8!/4/2)"])
        #expect(received.compactMap { $0["color"] as? String }.sorted() ==
                ["green", "pink", "yellow"])
        let keys = Set(received.compactMap { $0["fingerprintKey"] as? String })
        #expect(keys == ["azw3:abc:1"])
    }

    @Test("skips non-EPUB-anchored highlights (text anchor)")
    func skipsNonEpubAnchors() {
        // A book that's been read in multiple formats may have
        // text-anchored highlights on its record (from a TXT cousin
        // of the same content). The dispatcher must not crash —
        // those anchors can't be routed through Foliate.
        let center = makeIsolatedCenter()
        var receivedCount = 0
        let token = center.addObserver(
            forName: .foliateRequestAnnotationJSCreate,
            object: nil,
            queue: nil
        ) { _ in receivedCount += 1 }
        defer { center.removeObserver(token) }

        let highlights = [
            makeTextHighlight(),
            makeEpubHighlight(cfi: "epubcfi(/6/4!/4/2)"),
            makeTextHighlight(),
        ]
        let dispatched = FoliateHighlightRestoreDispatcher.dispatch(
            highlights: highlights,
            fingerprintKey: "azw3:abc:1",
            notificationCenter: center
        )

        #expect(dispatched == 1)
        #expect(receivedCount == 1)
    }

    @Test("empty CFI is skipped (cannot paint without a CFI)")
    func skipsEmptyCFI() {
        // Defense-in-depth: even though parser/observer also reject
        // empty CFIs, the dispatcher should not waste an
        // evaluateJavaScript round-trip on a no-op.
        let center = makeIsolatedCenter()
        var receivedCount = 0
        let token = center.addObserver(
            forName: .foliateRequestAnnotationJSCreate,
            object: nil,
            queue: nil
        ) { _ in receivedCount += 1 }
        defer { center.removeObserver(token) }

        let highlights = [
            makeEpubHighlight(cfi: ""),
            makeEpubHighlight(cfi: "   "),  // whitespace-only
            makeEpubHighlight(cfi: "epubcfi(/6/4!/4/2)"),
        ]
        let dispatched = FoliateHighlightRestoreDispatcher.dispatch(
            highlights: highlights,
            fingerprintKey: "azw3:abc:1",
            notificationCenter: center
        )

        #expect(dispatched == 1)
        #expect(receivedCount == 1)
    }

    @Test("empty highlight list dispatches nothing")
    func emptyList() {
        let center = makeIsolatedCenter()
        var receivedCount = 0
        let token = center.addObserver(
            forName: .foliateRequestAnnotationJSCreate,
            object: nil,
            queue: nil
        ) { _ in receivedCount += 1 }
        defer { center.removeObserver(token) }

        let dispatched = FoliateHighlightRestoreDispatcher.dispatch(
            highlights: [],
            fingerprintKey: "azw3:abc:1",
            notificationCenter: center
        )

        #expect(dispatched == 0)
        #expect(receivedCount == 0)
    }

    @Test("empty fingerprintKey skips dispatch entirely")
    func emptyFingerprintKey() {
        // Mirrors FoliateSelectionDispatcher's identity guard:
        // empty-string identity means "can't route" — drop rather
        // than emit garbage notifications.
        let center = makeIsolatedCenter()
        var receivedCount = 0
        let token = center.addObserver(
            forName: .foliateRequestAnnotationJSCreate,
            object: nil,
            queue: nil
        ) { _ in receivedCount += 1 }
        defer { center.removeObserver(token) }

        let dispatched = FoliateHighlightRestoreDispatcher.dispatch(
            highlights: [makeEpubHighlight(cfi: "epubcfi(/6/4!/4/2)")],
            fingerprintKey: "",
            notificationCenter: center
        )

        #expect(dispatched == 0)
        #expect(receivedCount == 0)
    }
}
#endif
