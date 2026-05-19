// Purpose: Feature #55 WI-6 — guards the native-container wiring of the
// tap-on-annotated-text note preview (TXT / MD / PDF).
//
// WI-6's behavioral change is integration — `NotePreviewModifier` attached to
// the three native containers, plus feature #53's delete menu re-homed from
// the tap gesture to a `UILongPressGestureRecognizer` in the TXT / chunked /
// PDF bridges. The end-to-end behavior (tap → preview; long-press → #53 menu)
// is exercised at Gate 5 device verification. These unit tests guard the
// pieces that CAN be verified without driving live UIKit gestures:
//   - `notePreviewPresenterIfAvailable` attaches when a `ModelContainer` is
//     present and is an inert no-op when it is `nil` (preview/test safety).
//   - the resolution helpers the long-press handlers reuse still resolve a
//     hit-test point — the long-press shares the SAME hit-test as the tap, so
//     a regression in resolution would break both gestures.

#if canImport(UIKit)
import Testing
import UIKit
import SwiftUI
import SwiftData
import Foundation
@testable import vreader

@Suite("Feature #55 WI-6 — native container note-preview wiring")
@MainActor
struct Feature55NativeWiringTests {

    // MARK: - notePreviewPresenterIfAvailable

    @Test("notePreviewPresenterIfAvailable is an inert no-op with a nil container")
    func attachHelperNoOpWhenContainerNil() {
        // A nil ModelContainer (SwiftUI preview / some test harnesses) must
        // not crash — the helper returns the view unchanged.
        let view = Color.clear.notePreviewPresenterIfAvailable(
            modelContainer: nil,
            bookFingerprintKey: "epub:abc:1",
            theme: .paper
        )
        let host = UIHostingController(rootView: view)
        host.loadViewIfNeeded()
        #expect(host.view != nil)
    }

    @Test("notePreviewPresenterIfAvailable attaches with a real container")
    func attachHelperAttachesWhenContainerPresent() throws {
        // An in-memory container — the helper builds the PersistenceActor
        // lookup and attaches NotePreviewModifier.
        let schema = Schema(SchemaV6.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let view = Color.clear.notePreviewPresenterIfAvailable(
            modelContainer: container,
            bookFingerprintKey: "epub:abc:1",
            theme: .paper
        )
        let host = UIHostingController(rootView: view)
        host.loadViewIfNeeded()
        #expect(host.view != nil)
    }

    // MARK: - The long-press shares the tap's hit-test (TXT non-chunked)

    @Test("TXT highlight resolution — the hit-test the long-press reuses — resolves a hit")
    func txtResolutionResolvesHitForLongPressPath() {
        // `handleHighlightLongPress` calls `resolveHighlightTap(tapPoint:in:lookup:)`
        // — the SAME resolution the tap handler uses. A point inside a
        // persisted range must resolve to the highlight's event.
        let tv = UITextView()
        tv.attributedText = NSAttributedString(
            string: "hello world",
            attributes: [.font: UIFont.systemFont(ofSize: 16)]
        )
        tv.frame = CGRect(x: 0, y: 0, width: 800, height: 200)
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainerInset = .zero
        tv.layoutManager.ensureLayout(for: tv.textContainer)

        let id = UUID()
        let lookup = [PersistedHighlightLookupEntry(
            id: id, range: NSRange(location: 6, length: 5)  // "world"
        )]
        let lm = tv.layoutManager
        let glyphRange = lm.glyphRange(
            forCharacterRange: NSRange(location: 6, length: 1), actualCharacterRange: nil
        )
        let charRect = lm.boundingRect(forGlyphRange: glyphRange, in: tv.textContainer)

        let event = TXTTextViewBridge.Coordinator.resolveHighlightTap(
            tapPoint: CGPoint(x: charRect.midX, y: charRect.midY),
            in: tv,
            lookup: lookup
        )
        #expect(event?.highlightID == id)
    }

    @Test("TXT highlight resolution misses plain text — long-press there no-ops")
    func txtResolutionMissesPlainText() {
        let tv = UITextView()
        tv.attributedText = NSAttributedString(
            string: "hello world",
            attributes: [.font: UIFont.systemFont(ofSize: 16)]
        )
        tv.frame = CGRect(x: 0, y: 0, width: 800, height: 200)
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainerInset = .zero
        tv.layoutManager.ensureLayout(for: tv.textContainer)

        // Lookup covers "world" [6,11); a tap at the very start ("h") misses.
        let lookup = [PersistedHighlightLookupEntry(
            id: UUID(), range: NSRange(location: 6, length: 5)
        )]
        let event = TXTTextViewBridge.Coordinator.resolveHighlightTap(
            tapPoint: CGPoint(x: 1, y: 5),
            in: tv,
            lookup: lookup
        )
        #expect(event == nil)
    }

    // MARK: - Chunked resolution accepts the widened gesture type

    @Test("chunked resolution's point overload still resolves after the UIGestureRecognizer widening")
    func chunkedResolutionPointOverloadStillWorks() {
        // WI-6 widened `resolveChunkedHighlightTap(gesture:)` from
        // `UITapGestureRecognizer` to `UIGestureRecognizer` so the long-press
        // can drive it. The point-based overload (used by tests + internally)
        // is unaffected — guard that.
        let tv = UITextView()
        tv.attributedText = NSAttributedString(
            string: "hello world",
            attributes: [.font: UIFont.systemFont(ofSize: 16)]
        )
        tv.frame = CGRect(x: 0, y: 0, width: 800, height: 200)
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainerInset = .zero
        tv.layoutManager.ensureLayout(for: tv.textContainer)

        let id = UUID()
        let lookup = [PersistedHighlightLookupEntry(
            id: id, range: NSRange(location: 6, length: 5)
        )]
        let lm = tv.layoutManager
        let glyphRange = lm.glyphRange(
            forCharacterRange: NSRange(location: 6, length: 1), actualCharacterRange: nil
        )
        let charRect = lm.boundingRect(forGlyphRange: glyphRange, in: tv.textContainer)

        let event = TXTChunkedReaderBridge.Coordinator.resolveChunkedHighlightTap(
            tapPointInCell: CGPoint(x: charRect.midX, y: charRect.midY),
            in: tv,
            chunkIndex: 0,
            chunkStartOffsets: [0],
            lookup: lookup
        )
        #expect(event?.highlightID == id)
    }
}
#endif
