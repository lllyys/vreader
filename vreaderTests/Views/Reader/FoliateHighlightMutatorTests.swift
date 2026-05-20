// Purpose: Feature #64 WI-9 — tests for `FoliateHighlightMutator`, the
// `HighlightMutating` conformer that wires the unified highlight-action
// popover to the Foliate (AZW3/MOBI) container.
//
// Foliate has no `HighlightRenderer` conformer, so it cannot reuse
// `HighlightCoordinator` (which requires one). `FoliateHighlightMutator`
// composes two pieces: it persists the color / note / delete via
// `HighlightPersisting` (returning the same typed `HighlightMutationOutcome`
// as `HighlightCoordinator` — `.success` / `.notFound` / `.failed`), and it
// repaints the live WKWebView overlay via `FoliateHighlightJSBridge` (the
// CFI-keyed `.foliateRequestAnnotationJS*` notification pair).
//
// Covers, with a fake `HighlightPersisting` + a `NotificationCenter` spy:
//   - changeColor → persists the color, re-fetches, posts the recolor JS pair
//     (delete-then-create), returns `.success(record)`.
//   - changeColor on a deleted record → `.notFound`, no JS post.
//   - changeColor with a generic persistence failure → `.failed`, no JS post.
//   - updateNote → persists the note, returns `.success`, NO JS post (a note
//     is not drawn on the page).
//   - updateNote whitespace-only draft → normalized to nil.
//   - deleteHighlight → persists the removal, posts `.readerHighlightRemoved`
//     + the JS overlay-strip, returns `.success(record)`.
//   - deleteHighlight on an already-gone record → `.notFound`, no posts.

#if canImport(UIKit)
import Testing
import Foundation
@testable import vreader

@Suite("Feature #64 WI-9 — FoliateHighlightMutator")
@MainActor
struct FoliateHighlightMutatorTests {

    private static let fingerprint = DocumentFingerprint(
        contentSHA256: "foliate_mutator_sha_0000000000000000000000000000000000",
        fileByteCount: 100, format: .azw3
    )
    private static let bookKey = fingerprint.canonicalKey

    private func epubAnchorRecord(
        id: UUID, cfi: String = "epubcfi(/6/4!/4/2/2)",
        color: String = "yellow", note: String? = nil
    ) -> HighlightRecord {
        let anchor = AnnotationAnchor.epub(
            href: "", cfi: cfi,
            serializedRange: EPUBSerializedRange(
                startContainerPath: "", startOffset: 0, endContainerPath: "", endOffset: 0
            )
        )
        let locator = Locator.validated(bookFingerprint: Self.fingerprint, cfi: cfi)!
        return HighlightRecord(
            highlightId: id, locator: locator, anchor: anchor, profileKey: "k",
            selectedText: "passage", color: color, note: note,
            createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 2)
        )
    }

    // MARK: - Fake HighlightPersisting

    /// A `HighlightPersisting` fake whose mutation methods succeed, throw a
    /// distinct `PersistenceError.recordNotFound`, or throw a generic error.
    /// Mirrors the WI-3 `MutMockPersistence` shape.
    private actor FakePersistence: HighlightPersisting {
        enum Mode: Sendable { case success, recordNotFound, genericFailure }

        private var mode: Mode = .success
        private var stored: [UUID: HighlightRecord] = [:]
        private(set) var lastColor: String?
        private(set) var lastNote: String?
        private(set) var lastNoteWasSet = false
        private(set) var removeCallCount = 0
        /// When true, the mutation itself succeeds but the post-mutation
        /// `fetchHighlights` throws — the R1-5 "read failure after a
        /// successful write" path, which must map to `.failed`, NOT `.notFound`.
        private var fetchThrowsAfterMutation = false
        /// IDs the mutation still writes to `stored` but `fetchHighlights`
        /// excludes — simulates a concurrent deletion racing the mutation's
        /// `await`, so the clean re-fetch misses the record → `.notFound`.
        private var droppedFromFetch: Set<UUID> = []

        func setMode(_ m: Mode) { mode = m }
        func seed(_ record: HighlightRecord) { stored[record.highlightId] = record }
        func setFetchThrowsAfterMutation(_ value: Bool) { fetchThrowsAfterMutation = value }
        func dropFromFetch(_ id: UUID) { droppedFromFetch.insert(id) }

        func addHighlight(
            locator: Locator, selectedText: String, color: String,
            note: String?, toBookWithKey key: String
        ) async throws -> HighlightRecord { fatalError("unused") }

        func addHighlight(
            locator: Locator, anchor: AnnotationAnchor?, selectedText: String,
            color: String, note: String?, toBookWithKey key: String
        ) async throws -> HighlightRecord { fatalError("unused") }

        func removeHighlight(highlightId: UUID) async throws {
            switch mode {
            case .recordNotFound:
                throw PersistenceError.recordNotFound("Highlight \(highlightId)")
            case .genericFailure:
                throw NSError(domain: "test", code: 99)
            case .success:
                removeCallCount += 1
                stored[highlightId] = nil
            }
        }

        func updateHighlightNote(highlightId: UUID, note: String?) async throws {
            switch mode {
            case .recordNotFound:
                throw PersistenceError.recordNotFound("Highlight \(highlightId)")
            case .genericFailure:
                throw NSError(domain: "test", code: 99)
            case .success:
                lastNoteWasSet = true
                lastNote = note
                if let rec = stored[highlightId] {
                    stored[highlightId] = HighlightRecord(
                        highlightId: rec.highlightId, locator: rec.locator, anchor: rec.anchor,
                        profileKey: rec.profileKey, selectedText: rec.selectedText,
                        color: rec.color, note: note, createdAt: rec.createdAt,
                        updatedAt: Date(timeIntervalSince1970: 999)
                    )
                }
            }
        }

        func updateHighlightColor(highlightId: UUID, color: String) async throws {
            switch mode {
            case .recordNotFound:
                throw PersistenceError.recordNotFound("Highlight \(highlightId)")
            case .genericFailure:
                throw NSError(domain: "test", code: 99)
            case .success:
                lastColor = color
                if let rec = stored[highlightId] {
                    stored[highlightId] = HighlightRecord(
                        highlightId: rec.highlightId, locator: rec.locator, anchor: rec.anchor,
                        profileKey: rec.profileKey, selectedText: rec.selectedText,
                        color: color, note: rec.note, createdAt: rec.createdAt,
                        updatedAt: Date(timeIntervalSince1970: 999)
                    )
                }
            }
        }

        func fetchHighlights(forBookWithKey key: String) async throws -> [HighlightRecord] {
            if case .genericFailure = mode { throw NSError(domain: "test", code: 77) }
            if fetchThrowsAfterMutation { throw NSError(domain: "test", code: 77) }
            return stored.values.filter { !droppedFromFetch.contains($0.highlightId) }
        }
    }

    // MARK: - NotificationCenter spy

    /// Collects posted notifications synchronously on a *caller-supplied*
    /// `NotificationCenter`. Each test passes its own isolated center (NOT
    /// `.default`) so concurrently-running tests cannot cross-pollinate posts
    /// — the Bug #225 class. Torn down by an explicit `stop()` (a `nonisolated
    /// deinit` cannot touch this `@MainActor` type's stored tokens under
    /// Swift 6).
    private final class NotificationSpy {
        struct Captured { let name: Notification.Name; let object: Any? }
        private(set) var captured: [Captured] = []
        private let center: NotificationCenter
        private var tokens: [NSObjectProtocol] = []

        init(center: NotificationCenter, names: [Notification.Name]) {
            self.center = center
            for name in names {
                tokens.append(center.addObserver(
                    forName: name, object: nil, queue: nil
                ) { [weak self] note in
                    self?.captured.append(Captured(name: name, object: note.object))
                })
            }
        }
        func stop() {
            tokens.forEach { center.removeObserver($0) }
            tokens.removeAll()
        }
        func count(_ name: Notification.Name) -> Int {
            captured.filter { $0.name == name }.count
        }
    }

    /// Builds a mutator whose `FoliateHighlightJSBridge` posts onto the given
    /// isolated `NotificationCenter` — so the test's `NotificationSpy` sees
    /// ONLY this mutator's posts.
    private func makeMutator(
        persistence: FakePersistence, center: NotificationCenter
    ) -> FoliateHighlightMutator {
        FoliateHighlightMutator(
            persistence: persistence,
            bookFingerprintKey: Self.bookKey,
            jsBridge: FoliateHighlightJSBridge(notificationCenter: center)
        )
    }

    // MARK: - changeColor

    @Test("changeColor persists the color, posts the recolor JS pair, returns .success")
    func changeColorSuccessPersistsAndRepaints() async {
        let id = UUID()
        let persistence = FakePersistence()
        await persistence.seed(epubAnchorRecord(id: id, color: "yellow"))
        // Isolated center — concurrently-running tests must not see each other's posts.
        let center = NotificationCenter()
        let mutator = makeMutator(persistence: persistence, center: center)

        let spy = NotificationSpy(center: center, names: [
            .foliateRequestAnnotationJSDelete, .foliateRequestAnnotationJSCreate
        ])
        defer { spy.stop() }

        let outcome = await mutator.changeColor(highlightID: id, to: "pink")

        // The color is persisted.
        #expect(await persistence.lastColor == "pink")
        // The post-mutation record is returned on `.success`.
        if case let .success(record) = outcome {
            #expect(record.highlightId == id)
            #expect(record.color == "pink")
        } else {
            Issue.record("expected .success, got \(outcome)")
        }
        // The Foliate overlay is repainted via the recolor JS pair
        // (delete-then-create).
        #expect(spy.count(.foliateRequestAnnotationJSDelete) == 1)
        #expect(spy.count(.foliateRequestAnnotationJSCreate) == 1)
    }

    @Test("changeColor on a deleted record returns .notFound and posts no JS")
    func changeColorRecordNotFound() async {
        let persistence = FakePersistence()
        await persistence.setMode(.recordNotFound)
        // Isolated center — concurrently-running tests must not see each other's posts.
        let center = NotificationCenter()
        let mutator = makeMutator(persistence: persistence, center: center)

        let spy = NotificationSpy(center: center, names: [
            .foliateRequestAnnotationJSDelete, .foliateRequestAnnotationJSCreate
        ])
        defer { spy.stop() }

        let outcome = await mutator.changeColor(highlightID: UUID(), to: "pink")
        #expect(outcome == .notFound)
        #expect(spy.captured.isEmpty)
    }

    @Test("changeColor with a generic persistence failure returns .failed and posts no JS")
    func changeColorGenericFailure() async {
        let persistence = FakePersistence()
        await persistence.setMode(.genericFailure)
        // Isolated center — concurrently-running tests must not see each other's posts.
        let center = NotificationCenter()
        let mutator = makeMutator(persistence: persistence, center: center)

        let spy = NotificationSpy(center: center, names: [
            .foliateRequestAnnotationJSDelete, .foliateRequestAnnotationJSCreate
        ])
        defer { spy.stop() }

        let outcome = await mutator.changeColor(highlightID: UUID(), to: "pink")
        #expect(outcome == .failed)
        #expect(spy.captured.isEmpty)
    }

    // MARK: - updateNote

    @Test("updateNote persists the note, returns .success, posts NO JS")
    func updateNoteSuccessNoRepaint() async {
        let id = UUID()
        let persistence = FakePersistence()
        await persistence.seed(epubAnchorRecord(id: id))
        // Isolated center — concurrently-running tests must not see each other's posts.
        let center = NotificationCenter()
        let mutator = makeMutator(persistence: persistence, center: center)

        let spy = NotificationSpy(center: center, names: [
            .foliateRequestAnnotationJSDelete, .foliateRequestAnnotationJSCreate,
            .readerHighlightRemoved
        ])
        defer { spy.stop() }

        let outcome = await mutator.updateNote(highlightID: id, note: "a thought")
        #expect(await persistence.lastNote == "a thought")
        if case let .success(record) = outcome {
            #expect(record.highlightId == id)
        } else {
            Issue.record("expected .success, got \(outcome)")
        }
        // A note is not drawn on the page — no overlay repaint.
        #expect(spy.captured.isEmpty)
    }

    @Test("updateNote normalizes a whitespace-only draft to nil")
    func updateNoteWhitespaceNormalizedToNil() async {
        let id = UUID()
        let persistence = FakePersistence()
        await persistence.seed(epubAnchorRecord(id: id))
        // Isolated center — concurrently-running tests must not see each other's posts.
        let center = NotificationCenter()
        let mutator = makeMutator(persistence: persistence, center: center)

        _ = await mutator.updateNote(highlightID: id, note: "   \n  ")
        #expect(await persistence.lastNoteWasSet == true)
        #expect(await persistence.lastNote == nil)
    }

    // MARK: - deleteHighlight

    @Test("deleteHighlight persists the removal, posts removed + JS-strip, returns .success")
    func deleteHighlightSuccess() async {
        let id = UUID()
        let persistence = FakePersistence()
        await persistence.seed(epubAnchorRecord(id: id, cfi: "epubcfi(/6/10!/2)"))
        // Isolated center — concurrently-running tests must not see each other's posts.
        let center = NotificationCenter()
        let mutator = makeMutator(persistence: persistence, center: center)

        let spy = NotificationSpy(center: center, names: [
            .readerHighlightRemoved, .foliateRequestAnnotationJSDelete
        ])
        defer { spy.stop() }

        let outcome = await mutator.deleteHighlight(highlightID: id)

        #expect(await persistence.removeCallCount == 1)
        if case let .success(record) = outcome {
            #expect(record.highlightId == id)
        } else {
            Issue.record("expected .success, got \(outcome)")
        }
        // `.readerHighlightRemoved` keeps the panel in sync; the JS-strip
        // clears the SVG overlay.
        #expect(spy.count(.readerHighlightRemoved) == 1)
        #expect(spy.count(.foliateRequestAnnotationJSDelete) == 1)
        // The removal posts `.readerHighlightRemoved` exactly once (the bridge
        // owns that post — the mutator must not double-fire it).
    }

    @Test("deleteHighlight on an already-gone record returns .notFound and posts nothing")
    func deleteHighlightAlreadyGone() async {
        // The fake has no seeded record — the up-front fetch finds nothing.
        let persistence = FakePersistence()
        // Isolated center — concurrently-running tests must not see each other's posts.
        let center = NotificationCenter()
        let mutator = makeMutator(persistence: persistence, center: center)

        let spy = NotificationSpy(center: center, names: [
            .readerHighlightRemoved, .foliateRequestAnnotationJSDelete
        ])
        defer { spy.stop() }

        let outcome = await mutator.deleteHighlight(highlightID: UUID())
        #expect(outcome == .notFound)
        #expect(await persistence.removeCallCount == 0)
        #expect(spy.captured.isEmpty)
    }

    // MARK: - R1-5 fetch discipline (highest-risk WI — fenced explicitly)

    @Test("changeColor: write succeeds then the re-fetch throws → .failed, not .notFound")
    func changeColorWriteSucceedsThenFetchThrows() async {
        let id = UUID()
        let persistence = FakePersistence()
        await persistence.seed(epubAnchorRecord(id: id))
        // The color write succeeds; only the post-mutation fetch throws.
        await persistence.setFetchThrowsAfterMutation(true)
        let center = NotificationCenter()
        let mutator = makeMutator(persistence: persistence, center: center)
        let spy = NotificationSpy(center: center, names: [
            .foliateRequestAnnotationJSDelete, .foliateRequestAnnotationJSCreate
        ])
        defer { spy.stop() }

        let outcome = await mutator.changeColor(highlightID: id, to: "pink")
        // A read failure after a successful write is a generic failure — NOT
        // a deleted-record race (R1-5).
        #expect(outcome == .failed)
        #expect(await persistence.lastColor == "pink")  // the write DID land
        #expect(spy.captured.isEmpty)                   // no repaint on failure
    }

    @Test("changeColor: write succeeds then a clean re-fetch misses the record → .notFound")
    func changeColorWriteSucceedsThenCleanFetchMisses() async {
        let id = UUID()
        let persistence = FakePersistence()
        await persistence.seed(epubAnchorRecord(id: id))
        // The write succeeds, but a concurrent deletion drops the record from
        // the fetch set — a clean fetch with no match.
        await persistence.dropFromFetch(id)
        let center = NotificationCenter()
        let mutator = makeMutator(persistence: persistence, center: center)
        let spy = NotificationSpy(center: center, names: [
            .foliateRequestAnnotationJSDelete, .foliateRequestAnnotationJSCreate
        ])
        defer { spy.stop() }

        let outcome = await mutator.changeColor(highlightID: id, to: "pink")
        #expect(outcome == .notFound)
        #expect(spy.captured.isEmpty)
    }

    @Test("updateNote: write succeeds then the re-fetch throws → .failed, not .notFound")
    func updateNoteWriteSucceedsThenFetchThrows() async {
        let id = UUID()
        let persistence = FakePersistence()
        await persistence.seed(epubAnchorRecord(id: id))
        await persistence.setFetchThrowsAfterMutation(true)
        let center = NotificationCenter()
        let mutator = makeMutator(persistence: persistence, center: center)

        let outcome = await mutator.updateNote(highlightID: id, note: "a thought")
        #expect(outcome == .failed)
        #expect(await persistence.lastNote == "a thought")  // the write DID land
    }

    @Test("deleteHighlight: up-front fetch throws → .failed, the remove is not attempted")
    func deleteHighlightFetchThrows() async {
        let id = UUID()
        let persistence = FakePersistence()
        await persistence.seed(epubAnchorRecord(id: id))
        // The up-front fetch throws before the remove is reached.
        await persistence.setFetchThrowsAfterMutation(true)
        let center = NotificationCenter()
        let mutator = makeMutator(persistence: persistence, center: center)
        let spy = NotificationSpy(center: center, names: [
            .readerHighlightRemoved, .foliateRequestAnnotationJSDelete
        ])
        defer { spy.stop() }

        let outcome = await mutator.deleteHighlight(highlightID: id)
        // A fetch failure up front is `.failed` — and the removal must NOT be
        // attempted (the record was never confirmed to exist).
        #expect(outcome == .failed)
        #expect(await persistence.removeCallCount == 0)
        #expect(spy.captured.isEmpty)
    }

    @Test("deleteHighlight: the remove throws recordNotFound after a successful fetch → .notFound")
    func deleteHighlightRemoveRecordNotFound() async {
        let id = UUID()
        let persistence = FakePersistence()
        await persistence.seed(epubAnchorRecord(id: id))
        // The up-front fetch finds the record, but `removeHighlight` then
        // throws `recordNotFound` — a concurrent deletion between the two.
        await persistence.setMode(.recordNotFound)
        let center = NotificationCenter()
        let mutator = makeMutator(persistence: persistence, center: center)
        let spy = NotificationSpy(center: center, names: [
            .readerHighlightRemoved, .foliateRequestAnnotationJSDelete
        ])
        defer { spy.stop() }

        let outcome = await mutator.deleteHighlight(highlightID: id)
        #expect(outcome == .notFound)
        #expect(spy.captured.isEmpty)  // no overlay strip on a notFound race
    }
}
#endif
