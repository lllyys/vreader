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
//   - gesture arbitration (Gate-4 audit fix): the long-press recognizer is
//     named, gated by a highlight hit-test in `gestureRecognizerShouldBegin`,
//     and denied simultaneous recognition against the native text-selection
//     long-press — so a long-press on a highlight opens ONLY #53's menu and a
//     long-press on plain text falls through to native selection.

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

    // MARK: - Gesture arbitration (Gate-4 audit fix — long-press isolation)

    // WI-6's first cut added the long-press recognizer with an unconditional
    // `shouldRecognizeSimultaneouslyWith == true`, so a long-press on a
    // highlight fired BOTH #53's delete menu AND UITextView/PDFView's native
    // text selection. The fix: a named recognizer + a hit-test in
    // `gestureRecognizerShouldBegin` + a name-aware simultaneity policy.
    // These tests pin that arbitration.

    @Test("simultaneousRecognitionAllowed denies the highlight long-press, allows everything else")
    func simultaneityPolicyDeniesHighlightLongPressOnly() {
        // The highlight long-press must be mutually exclusive with the
        // native selection long-press; the tap recognizer (and any unnamed
        // recognizer) keeps the legacy "always simultaneous" answer.
        #expect(
            TXTBridgeShared.simultaneousRecognitionAllowed(
                for: TXTBridgeShared.highlightLongPressName
            ) == false
        )
        #expect(TXTBridgeShared.simultaneousRecognitionAllowed(for: nil) == true)
        #expect(
            TXTBridgeShared.simultaneousRecognitionAllowed(
                for: "some.other.recognizer"
            ) == true
        )
    }

    @Test("TXT coordinator gestureRecognizerShouldBegin lets non-highlight recognizers begin")
    func txtShouldBeginPassesThroughForNonHighlightRecognizers() {
        // A recognizer that is NOT the named highlight long-press (e.g. the
        // content-tap recognizer) keeps UIKit's default begin behavior —
        // `gestureRecognizerShouldBegin` returns true without hit-testing.
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        let tap = UITapGestureRecognizer()
        #expect(coordinator.gestureRecognizerShouldBegin(tap) == true)
    }

    @Test("TXT coordinator gestureRecognizerShouldBegin blocks the highlight long-press with an empty lookup")
    func txtShouldBeginBlocksHighlightLongPressWhenNoHighlights() {
        // The named highlight long-press must NOT begin when there are no
        // persisted highlights — a long-press on plain text falls through
        // to UITextView's native selection instead of engaging #53's menu.
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        coordinator.persistedHighlightLookup = []
        let longPress = UILongPressGestureRecognizer()
        longPress.name = TXTBridgeShared.highlightLongPressName
        #expect(coordinator.gestureRecognizerShouldBegin(longPress) == false)
    }

    @Test("chunked coordinator gestureRecognizerShouldBegin lets non-highlight recognizers begin")
    func chunkedShouldBeginPassesThroughForNonHighlightRecognizers() {
        let coordinator = TXTChunkedReaderBridge.Coordinator(delegate: nil)
        let tap = UITapGestureRecognizer()
        #expect(coordinator.gestureRecognizerShouldBegin(tap) == true)
    }

    @Test("chunked coordinator gestureRecognizerShouldBegin blocks the highlight long-press with an empty lookup")
    func chunkedShouldBeginBlocksHighlightLongPressWhenNoHighlights() {
        let coordinator = TXTChunkedReaderBridge.Coordinator(delegate: nil)
        coordinator.persistedHighlightLookup = []
        let longPress = UILongPressGestureRecognizer()
        longPress.name = TXTBridgeShared.highlightLongPressName
        #expect(coordinator.gestureRecognizerShouldBegin(longPress) == false)
    }

    @Test("PDF coordinator gestureRecognizerShouldBegin lets non-highlight recognizers begin")
    func pdfShouldBeginPassesThroughForNonHighlightRecognizers() {
        let coordinator = PDFViewBridge.Coordinator()
        let tap = UITapGestureRecognizer()
        #expect(coordinator.gestureRecognizerShouldBegin(tap) == true)
    }

    @Test("PDF coordinator gestureRecognizerShouldBegin blocks the highlight long-press with no PDFView")
    func pdfShouldBeginBlocksHighlightLongPressWhenNoRenderer() {
        // With no attached PDFView (and therefore no renderer/annotations),
        // the named highlight long-press must not begin — a long-press on
        // the page falls through to PDFKit's native text selection.
        let coordinator = PDFViewBridge.Coordinator()
        let longPress = UILongPressGestureRecognizer()
        longPress.name = TXTBridgeShared.highlightLongPressName
        #expect(coordinator.gestureRecognizerShouldBegin(longPress) == false)
    }

    // MARK: - The WI-6 behavior swap itself (tap → notification; long-press → menu)

    // The core WI-6 change: a tap on a highlight posts `.readerHighlightTapped`
    // (the #55 note preview) and must NOT present feature #53's delete menu;
    // the menu is re-homed to the long-press. These coordinator-level tests
    // drive `handleContentTap` / `handleHighlightLongPress` directly with a
    // fake presenter so a future regression that reintroduces menu-on-tap is
    // caught — closing the round-2 Low test-seam finding.

    /// Records every `present(...)` call so the test can assert the menu was
    /// (or was not) shown without driving a live `UIEditMenuInteraction`.
    @MainActor
    final class SpyHighlightActionPresenter: HighlightActionPresenting {
        private(set) var presentCallCount = 0
        private(set) var lastEvent: ReaderHighlightTapEvent?
        func present(
            for event: ReaderHighlightTapEvent,
            in view: UIView,
            completion: @escaping @MainActor (HighlightTapAction?) -> Void
        ) {
            presentCallCount += 1
            lastEvent = event
            // Do not deliver an action — the test only cares that the menu
            // would have been presented, not what the user picks.
        }
    }

    /// `UITapGestureRecognizer` whose `location(in:)` is fixed so the
    /// coordinator's gesture handlers resolve a deterministic point.
    final class FixedPointTap: UITapGestureRecognizer {
        var fixedPoint: CGPoint = .zero
        override func location(in view: UIView?) -> CGPoint { fixedPoint }
    }

    /// `UILongPressGestureRecognizer` with a fixed point + a forced `state`
    /// so `handleHighlightLongPress` (which gates on `.began`) can run.
    final class FixedPointLongPress: UILongPressGestureRecognizer {
        var fixedPoint: CGPoint = .zero
        private var forcedState: UIGestureRecognizer.State = .began
        override var state: UIGestureRecognizer.State {
            get { forcedState }
            set { forcedState = newValue }
        }
        override func location(in view: UIView?) -> CGPoint { fixedPoint }
    }

    /// Builds a laid-out UITextView + a lookup covering "world", returning
    /// the textView, the highlight id, the lookup, and a point inside it.
    private func makeHighlightedTextViewFixture() -> (
        textView: UITextView, id: UUID,
        lookup: [PersistedHighlightLookupEntry], hitPoint: CGPoint
    ) {
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
            forCharacterRange: NSRange(location: 6, length: 1),
            actualCharacterRange: nil
        )
        let charRect = lm.boundingRect(forGlyphRange: glyphRange, in: tv.textContainer)
        return (tv, id, lookup, CGPoint(x: charRect.midX, y: charRect.midY))
    }

    @Test("TXT tap on a highlight posts .readerHighlightTapped and does NOT present the #53 menu")
    func txtTapOnHighlightPostsNotificationOnly() async {
        let fixture = makeHighlightedTextViewFixture()
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        coordinator.persistedHighlightLookup = fixture.lookup
        let spy = SpyHighlightActionPresenter()
        coordinator.highlightActionPresenter = spy
        coordinator.onHighlightTapAction = { _, _ in }

        let tap = FixedPointTap()
        tap.fixedPoint = fixture.hitPoint
        fixture.textView.addGestureRecognizer(tap)  // populates `gesture.view`

        nonisolated(unsafe) var postedID: UUID?
        let token = NotificationCenter.default.addObserver(
            forName: .readerHighlightTapped, object: nil, queue: nil
        ) { note in
            postedID = (note.object as? ReaderHighlightTapEvent)?.highlightID
        }
        defer { NotificationCenter.default.removeObserver(token) }

        coordinator.handleContentTap(tap)

        // Tap fires the #55 preview notification, NOT #53's delete menu.
        #expect(postedID == fixture.id)
        #expect(spy.presentCallCount == 0)
    }

    @Test("TXT long-press on a highlight presents the #53 menu (the re-homed delete path)")
    func txtLongPressOnHighlightPresentsMenu() {
        let fixture = makeHighlightedTextViewFixture()
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        coordinator.persistedHighlightLookup = fixture.lookup
        let spy = SpyHighlightActionPresenter()
        coordinator.highlightActionPresenter = spy
        coordinator.onHighlightTapAction = { _, _ in }

        let longPress = FixedPointLongPress()
        longPress.fixedPoint = fixture.hitPoint
        longPress.name = TXTBridgeShared.highlightLongPressName
        fixture.textView.addGestureRecognizer(longPress)

        coordinator.handleHighlightLongPress(longPress)

        // The long-press is the path that opens #53's delete menu.
        #expect(spy.presentCallCount == 1)
        #expect(spy.lastEvent?.highlightID == fixture.id)
    }

    @Test("TXT long-press in the .changed state does not present (only .began fires the menu)")
    func txtLongPressNonBeganStateDoesNotPresent() {
        let fixture = makeHighlightedTextViewFixture()
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        coordinator.persistedHighlightLookup = fixture.lookup
        let spy = SpyHighlightActionPresenter()
        coordinator.highlightActionPresenter = spy
        coordinator.onHighlightTapAction = { _, _ in }

        let longPress = FixedPointLongPress()
        longPress.fixedPoint = fixture.hitPoint
        longPress.name = TXTBridgeShared.highlightLongPressName
        longPress.state = .changed  // continuation events must not re-fire
        fixture.textView.addGestureRecognizer(longPress)

        coordinator.handleHighlightLongPress(longPress)
        #expect(spy.presentCallCount == 0)
    }
}
#endif
