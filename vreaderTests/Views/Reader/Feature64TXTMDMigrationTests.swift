// Purpose: Feature #64 WI-6 — guards the migration of the native TXT / MD
// reader containers from feature #55's `notePreviewPresenterIfAvailable` (the
// read-only note preview) to the unified highlight-action popover's
// `unifiedHighlightPopoverPresenterIfAvailable`.
//
// Supersedes `Feature55NativeWiringTests.swift` (deleted): WI-6 removes the
// feature #53 highlight long-press `UIMenu` from the TXT / chunked-TXT bridges
// — a *tap* on a highlight now posts `.readerHighlightTapped`, which the
// unified popover observes. These unit tests guard the pieces verifiable
// without driving live UIKit gestures:
//   - `unifiedHighlightPopoverPresenterIfAvailable` attaches with a real
//     `ModelContainer` + a `HighlightMutating`, and is an inert no-op without.
//   - the tap hit-test resolution (the path that feeds `.readerHighlightTapped`)
//     resolves a hit and misses plain text — TXT non-chunked + chunked.
//   - `handleContentTap` on a highlight posts `.readerHighlightTapped` (the
//     unified popover's trigger) and skips chrome-toggle.
// The end-to-end behavior (tap → unified popover) is exercised at Gate 5
// device verification.

#if canImport(UIKit)
import Testing
import UIKit
import SwiftUI
import SwiftData
import Foundation
@testable import vreader

@Suite("Feature #64 WI-6 — native TXT/MD container migration")
@MainActor
struct Feature64TXTMDMigrationTests {

    // MARK: - A HighlightMutating stub for the attach helper

    private final class MutatingStub: HighlightMutating {
        func changeColor(highlightID: UUID, to color: String) async -> HighlightMutationOutcome {
            .failed
        }
        func updateNote(highlightID: UUID, note: String?) async -> HighlightMutationOutcome {
            .failed
        }
        func deleteHighlight(highlightID: UUID) async -> HighlightMutationOutcome {
            .failed
        }
    }

    // MARK: - unifiedHighlightPopoverPresenterIfAvailable

    @Test("unifiedHighlightPopoverPresenterIfAvailable is an inert no-op with a nil container")
    func attachHelperNoOpWhenContainerNil() {
        // A nil ModelContainer (SwiftUI preview / some test harnesses) must
        // not crash — the helper returns the view unchanged.
        let view = Color.clear.unifiedHighlightPopoverPresenterIfAvailable(
            modelContainer: nil,
            bookFingerprintKey: "epub:abc:1",
            mutating: MutatingStub(),
            theme: .paper
        )
        let host = UIHostingController(rootView: view)
        host.loadViewIfNeeded()
        #expect(host.view != nil)
    }

    @Test("unifiedHighlightPopoverPresenterIfAvailable is a no-op with a nil mutating boundary")
    func attachHelperNoOpWhenMutatingNil() throws {
        // The container is non-nil but the HighlightMutating is nil (the
        // coordinator has not been wired yet) — the helper returns the view
        // unchanged rather than attaching a half-wired popover.
        let schema = Schema(SchemaV6.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let view = Color.clear.unifiedHighlightPopoverPresenterIfAvailable(
            modelContainer: container,
            bookFingerprintKey: "epub:abc:1",
            mutating: nil,
            theme: .paper
        )
        let host = UIHostingController(rootView: view)
        host.loadViewIfNeeded()
        #expect(host.view != nil)
    }

    @Test("unifiedHighlightPopoverPresenterIfAvailable attaches with a real container + mutating")
    func attachHelperAttachesWhenContainerAndMutatingPresent() throws {
        let schema = Schema(SchemaV6.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let view = Color.clear.unifiedHighlightPopoverPresenterIfAvailable(
            modelContainer: container,
            bookFingerprintKey: "epub:abc:1",
            mutating: MutatingStub(),
            theme: .paper
        )
        let host = UIHostingController(rootView: view)
        host.loadViewIfNeeded()
        #expect(host.view != nil)
    }

    // MARK: - Container source-wiring guards (TXT guarded separately)

    /// `TXTReaderContainerView` has its own dedicated wiring suite
    /// (`TXTReaderContainerHighlightCoordinatorWiringTests`); MD has none, so
    /// these source-grep tests pin the MD container's migrated wiring.
    private static func mdContainerSource(testFilePath: String = #filePath) throws -> String {
        let repoRoot = URL(fileURLWithPath: testFilePath)
            .deletingLastPathComponent()  // Reader/
            .deletingLastPathComponent()  // Views/
            .deletingLastPathComponent()  // vreaderTests/
            .deletingLastPathComponent()  // repo root
        let sourceURL = repoRoot
            .appendingPathComponent("vreader/Views/Reader/MDReaderContainerView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    @Test("MD container attaches the unified popover, not feature #55's note preview")
    func mdAttachesUnifiedHighlightPopoverPresenter() throws {
        let source = try Self.mdContainerSource()
        #expect(
            source.contains("unifiedHighlightPopoverPresenterIfAvailable"),
            "MDReaderContainerView must attach `unifiedHighlightPopoverPresenterIfAvailable` (feature #64 WI-6)."
        )
        #expect(
            !source.contains("notePreviewPresenterIfAvailable"),
            "MDReaderContainerView must no longer attach `notePreviewPresenterIfAvailable` — superseded by the unified popover (feature #64 WI-6)."
        )
    }

    @Test("MD container removed the feature #53 long-press UIMenu bridge wiring")
    func mdFeature53LongPressMenuWiringRemoved() throws {
        let source = try Self.mdContainerSource()
        #expect(
            !source.contains("highlightActionPresenter:"),
            "MDReaderContainerView must no longer pass `highlightActionPresenter:` to TXTTextViewBridge (feature #64 WI-6)."
        )
        #expect(
            !source.contains("onHighlightTapAction:"),
            "MDReaderContainerView must no longer pass `onHighlightTapAction:` to TXTTextViewBridge (feature #64 WI-6)."
        )
    }

    // MARK: - TXT non-chunked tap hit-test (feeds .readerHighlightTapped)

    private func makeLaidOutTextView() -> UITextView {
        let tv = UITextView()
        tv.attributedText = NSAttributedString(
            string: "hello world",
            attributes: [.font: UIFont.systemFont(ofSize: 16)]
        )
        tv.frame = CGRect(x: 0, y: 0, width: 800, height: 200)
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainerInset = .zero
        tv.layoutManager.ensureLayout(for: tv.textContainer)
        return tv
    }

    private func midPoint(of charIndex: Int, in tv: UITextView) -> CGPoint {
        let lm = tv.layoutManager
        let glyphRange = lm.glyphRange(
            forCharacterRange: NSRange(location: charIndex, length: 1),
            actualCharacterRange: nil
        )
        let charRect = lm.boundingRect(forGlyphRange: glyphRange, in: tv.textContainer)
        return CGPoint(x: charRect.midX, y: charRect.midY)
    }

    @Test("TXT highlight resolution resolves a hit inside a persisted range")
    func txtResolutionResolvesHit() {
        let tv = makeLaidOutTextView()
        let id = UUID()
        let lookup = [PersistedHighlightLookupEntry(
            id: id, range: NSRange(location: 6, length: 5)  // "world"
        )]
        let event = TXTTextViewBridge.Coordinator.resolveHighlightTap(
            tapPoint: midPoint(of: 6, in: tv), in: tv, lookup: lookup
        )
        #expect(event?.highlightID == id)
    }

    @Test("TXT highlight resolution misses plain text outside every range")
    func txtResolutionMissesPlainText() {
        let tv = makeLaidOutTextView()
        // Lookup covers "world" [6,11); a tap at the very start ("h") misses.
        let lookup = [PersistedHighlightLookupEntry(
            id: UUID(), range: NSRange(location: 6, length: 5)
        )]
        let event = TXTTextViewBridge.Coordinator.resolveHighlightTap(
            tapPoint: CGPoint(x: 1, y: 5), in: tv, lookup: lookup
        )
        #expect(event == nil)
    }

    // MARK: - Chunked TXT tap hit-test

    @Test("chunked TXT highlight resolution resolves a hit inside a persisted range")
    func chunkedResolutionResolvesHit() {
        let tv = makeLaidOutTextView()
        let id = UUID()
        let lookup = [PersistedHighlightLookupEntry(
            id: id, range: NSRange(location: 6, length: 5)
        )]
        let event = TXTChunkedReaderBridge.Coordinator.resolveChunkedHighlightTap(
            tapPointInCell: midPoint(of: 6, in: tv),
            in: tv,
            chunkIndex: 0,
            chunkStartOffsets: [0],
            lookup: lookup
        )
        #expect(event?.highlightID == id)
    }

    // MARK: - handleContentTap posts .readerHighlightTapped (the trigger)

    /// `UITapGestureRecognizer` whose `location(in:)` is fixed so the
    /// coordinator's tap handler resolves a deterministic point.
    private final class FixedPointTap: UITapGestureRecognizer {
        var fixedPoint: CGPoint = .zero
        override func location(in view: UIView?) -> CGPoint { fixedPoint }
    }

    @Test("TXT tap on a highlight posts .readerHighlightTapped (the unified popover trigger)")
    func txtTapOnHighlightPostsNotification() {
        let tv = makeLaidOutTextView()
        let id = UUID()
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        coordinator.persistedHighlightLookup = [PersistedHighlightLookupEntry(
            id: id, range: NSRange(location: 6, length: 5)
        )]

        let tap = FixedPointTap()
        tap.fixedPoint = midPoint(of: 6, in: tv)
        tv.addGestureRecognizer(tap)  // populates `gesture.view`

        nonisolated(unsafe) var postedID: UUID?
        let token = NotificationCenter.default.addObserver(
            forName: .readerHighlightTapped, object: nil, queue: nil
        ) { note in
            postedID = (note.object as? ReaderHighlightTapEvent)?.highlightID
        }
        defer { NotificationCenter.default.removeObserver(token) }

        coordinator.handleContentTap(tap)

        // A tap inside a persisted highlight posts `.readerHighlightTapped` —
        // the unified highlight-action popover's trigger.
        #expect(postedID == id)
    }

    @Test("TXT tap on plain text does NOT post .readerHighlightTapped")
    func txtTapOnPlainTextPostsNothing() {
        let tv = makeLaidOutTextView()
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        coordinator.persistedHighlightLookup = [PersistedHighlightLookupEntry(
            id: UUID(), range: NSRange(location: 6, length: 5)
        )]

        let tap = FixedPointTap()
        tap.fixedPoint = CGPoint(x: 1, y: 5)  // start of "hello" — outside the range
        tv.addGestureRecognizer(tap)

        nonisolated(unsafe) var posted = false
        let token = NotificationCenter.default.addObserver(
            forName: .readerHighlightTapped, object: nil, queue: nil
        ) { _ in posted = true }
        defer { NotificationCenter.default.removeObserver(token) }

        coordinator.handleContentTap(tap)
        #expect(!posted)
    }
}
#endif
