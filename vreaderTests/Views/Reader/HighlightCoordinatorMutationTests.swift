// Purpose: Feature #64 WI-3 — tests for `HighlightCoordinator.changeColor`
// and `HighlightCoordinator.updateNote`, the two highlight mutations the
// unified highlight-action popover drives.
//
// Covers: a successful recolor → `.success` + the renderer repainted; a
// successful note save → `.success`; a `PersistenceError.recordNotFound`
// thrown by the persistence layer → `.notFound`; a generic throw →
// `.failed`; the EPUB href-capture race (R1-4) — `changeColor` for an EPUB
// renderer captures `currentHref` BEFORE the persistence `await` and calls
// `restoreAll(forHref:)` with the captured value, even when a racing
// chapter-nav mutates `currentHref` mid-await; a trimmed-empty note draft
// normalized to `nil` before persisting.

#if canImport(UIKit)
import Testing
import Foundation
@testable import vreader

// MARK: - Helpers

private let mutTestFP = DocumentFingerprint(
    contentSHA256: "mutation_test_sha_000000000000000000000000000000000000",
    fileByteCount: 100, format: .epub
)

private func mutLocator() -> Locator {
    Locator.validated(bookFingerprint: mutTestFP, href: "ch1.xhtml", progression: 0.5)!
}

private func mutRecord(
    id: UUID = UUID(), color: String = "yellow", note: String? = nil
) -> HighlightRecord {
    HighlightRecord(
        highlightId: id, locator: mutLocator(), anchor: nil, profileKey: "k",
        selectedText: "the passage", color: color, note: note,
        createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 2)
    )
}

// MARK: - Mock renderer

@MainActor
private final class MutMockRenderer: HighlightRenderer {
    var restoreCalls = 0
    var lastRestoreHref: String?
    var lastRestoredRecords: [HighlightRecord]?

    func apply(record: HighlightRecord) {}
    func remove(id: UUID) {}
    func restore(
        records: [HighlightRecord], forHref href: String?, using evaluator: ((String) -> Void)?
    ) {
        restoreCalls += 1
        lastRestoreHref = href
        lastRestoredRecords = records
    }
}

/// A chapter-scoped renderer fake mirroring the real `EPUBHighlightRenderer`'s
/// mutable chapter href. The injected race (see `MutMockPersistence.armRace`)
/// flips `currentHref` while the persistence `await` is in flight, so the test
/// can prove `changeColor` captured the pre-await value.
@MainActor
private final class MutMockEPUBRenderer: ChapterScopedHighlightRenderer {
    var currentHref: String?
    var currentChapterHref: String? { currentHref }
    var restoreCalls = 0
    var lastRestoreHref: String?

    func apply(record: HighlightRecord) {}
    func remove(id: UUID) {}
    func restore(
        records: [HighlightRecord], forHref href: String?, using evaluator: ((String) -> Void)?
    ) {
        restoreCalls += 1
        lastRestoreHref = href
    }
}

// MARK: - Mock persistence

/// A `HighlightPersisting` mock whose mutation methods can succeed, throw a
/// distinct `PersistenceError.recordNotFound`, or throw a generic error. It
/// records the last color/note persisted and, optionally, mutates an
/// injected EPUB renderer's `currentHref` from inside `updateHighlightColor`
/// to simulate a chapter-nav racing the persistence `await`.
private actor MutMockPersistence: HighlightPersisting {
    enum Mode: Sendable { case success, recordNotFound, genericFailure }

    private var mode: Mode = .success
    private(set) var lastColor: String?
    private(set) var lastNoteWasSet = false
    private(set) var lastNote: String?
    private var stored: [UUID: HighlightRecord] = [:]
    /// When true, the mutation itself succeeds but the post-mutation
    /// `fetchHighlights` throws — the "read failure after a successful write"
    /// path that must map to `.failed`, not `.notFound`.
    private var fetchThrowsAfterMutation = false

    /// When set, `updateHighlightColor` flips this renderer's `currentHref`
    /// to `raceHref` before returning — the racing chapter-nav.
    private var raceRenderer: MutMockEPUBRenderer?
    private var raceHref: String?

    func setMode(_ m: Mode) { mode = m }
    func setFetchThrowsAfterMutation(_ value: Bool) { fetchThrowsAfterMutation = value }
    func seed(_ record: HighlightRecord) { stored[record.highlightId] = record }

    func armRace(renderer: MutMockEPUBRenderer, toHref href: String) {
        raceRenderer = renderer
        raceHref = href
    }

    func addHighlight(
        locator: Locator, selectedText: String, color: String,
        note: String?, toBookWithKey key: String
    ) async throws -> HighlightRecord {
        fatalError("unused in WI-3 mutation tests")
    }

    func addHighlight(
        locator: Locator, anchor: AnnotationAnchor?, selectedText: String,
        color: String, note: String?, toBookWithKey key: String
    ) async throws -> HighlightRecord {
        fatalError("unused in WI-3 mutation tests")
    }

    private(set) var removeCallCount = 0

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
            if var rec = stored[highlightId] {
                rec = HighlightRecord(
                    highlightId: rec.highlightId, locator: rec.locator, anchor: rec.anchor,
                    profileKey: rec.profileKey, selectedText: rec.selectedText,
                    color: rec.color, note: note, createdAt: rec.createdAt,
                    updatedAt: Date(timeIntervalSince1970: 999)
                )
                stored[highlightId] = rec
            }
        }
    }

    func updateHighlightColor(highlightId: UUID, color: String) async throws {
        // Simulate a racing chapter-nav mutating the renderer's currentHref
        // while this persistence call is in flight.
        if let renderer = raceRenderer, let href = raceHref {
            await MainActor.run { renderer.currentHref = href }
        }
        switch mode {
        case .recordNotFound:
            throw PersistenceError.recordNotFound("Highlight \(highlightId)")
        case .genericFailure:
            throw NSError(domain: "test", code: 99)
        case .success:
            lastColor = color
            if var rec = stored[highlightId] {
                rec = HighlightRecord(
                    highlightId: rec.highlightId, locator: rec.locator, anchor: rec.anchor,
                    profileKey: rec.profileKey, selectedText: rec.selectedText,
                    color: color, note: rec.note, createdAt: rec.createdAt,
                    updatedAt: Date(timeIntervalSince1970: 999)
                )
                stored[highlightId] = rec
            }
        }
    }

    func fetchHighlights(forBookWithKey key: String) async throws -> [HighlightRecord] {
        if fetchThrowsAfterMutation { throw NSError(domain: "test", code: 7) }
        return Array(stored.values)
    }
}

// MARK: - Tests

@Suite("HighlightCoordinator mutations")
struct HighlightCoordinatorMutationTests {

    // MARK: changeColor

    @Test @MainActor func changeColor_success_returnsSuccessAndRepaints() async {
        let renderer = MutMockRenderer()
        let persistence = MutMockPersistence()
        let record = mutRecord(color: "yellow")
        await persistence.seed(record)
        let coordinator = HighlightCoordinator(
            renderer: renderer, persistence: persistence, bookFingerprintKey: "book-1"
        )

        let outcome = await coordinator.changeColor(highlightID: record.highlightId, to: "pink")

        guard case let .success(returned) = outcome else {
            Issue.record("expected .success, got \(outcome)")
            return
        }
        #expect(returned.color == "pink")
        #expect(await persistence.lastColor == "pink")
        #expect(renderer.restoreCalls == 1)
    }

    @Test @MainActor func changeColor_recordNotFound_returnsNotFound() async {
        let renderer = MutMockRenderer()
        let persistence = MutMockPersistence()
        await persistence.setMode(.recordNotFound)
        let coordinator = HighlightCoordinator(
            renderer: renderer, persistence: persistence, bookFingerprintKey: "book-1"
        )
        let outcome = await coordinator.changeColor(highlightID: UUID(), to: "pink")
        #expect(outcome == .notFound)
        // No repaint when the record is gone.
        #expect(renderer.restoreCalls == 0)
    }

    @Test @MainActor func changeColor_genericFailure_returnsFailed() async {
        let renderer = MutMockRenderer()
        let persistence = MutMockPersistence()
        await persistence.setMode(.genericFailure)
        let coordinator = HighlightCoordinator(
            renderer: renderer, persistence: persistence, bookFingerprintKey: "book-1"
        )
        let outcome = await coordinator.changeColor(highlightID: UUID(), to: "pink")
        #expect(outcome == .failed)
        #expect(renderer.restoreCalls == 0)
    }

    /// R1-5: a read failure AFTER a successful color write must surface as
    /// `.failed`, not `.notFound` — the write landed; only the re-fetch broke.
    /// Treating it as `.notFound` would wrongly dismiss the popover and the
    /// page repaint would not be driven.
    @Test @MainActor func changeColor_refetchThrowsAfterSuccess_returnsFailed() async {
        let renderer = MutMockRenderer()
        let persistence = MutMockPersistence()
        let record = mutRecord(color: "yellow")
        await persistence.seed(record)
        await persistence.setFetchThrowsAfterMutation(true)
        let coordinator = HighlightCoordinator(
            renderer: renderer, persistence: persistence, bookFingerprintKey: "book-1"
        )
        let outcome = await coordinator.changeColor(highlightID: record.highlightId, to: "pink")
        #expect(outcome == .failed)
        // The repaint cannot be driven without the re-fetched records.
        #expect(renderer.restoreCalls == 0)
    }

    /// R1-5: a color write that succeeds but whose record is genuinely gone
    /// on a clean re-fetch (no fetch error) → `.notFound`.
    @Test @MainActor func changeColor_recordGoneOnCleanRefetch_returnsNotFound() async {
        let renderer = MutMockRenderer()
        let persistence = MutMockPersistence()
        // Nothing seeded — the write "succeeds" (mock mode .success) but the
        // re-fetch returns an empty list with no matching id.
        let coordinator = HighlightCoordinator(
            renderer: renderer, persistence: persistence, bookFingerprintKey: "book-1"
        )
        let outcome = await coordinator.changeColor(highlightID: UUID(), to: "pink")
        #expect(outcome == .notFound)
        #expect(renderer.restoreCalls == 0)
    }

    /// R1-4: for an EPUB renderer, `changeColor` must capture `currentHref`
    /// BEFORE the persistence `await` and call `restoreAll(forHref:)` with the
    /// captured value — so a racing chapter-nav that mutates `currentHref`
    /// mid-await cannot repaint the wrong chapter.
    @Test @MainActor func changeColor_epub_capturesHrefBeforeAwait() async {
        let renderer = MutMockEPUBRenderer()
        renderer.currentHref = "chapter-3.xhtml"  // the chapter on screen at tap
        let persistence = MutMockPersistence()
        let record = mutRecord(color: "yellow")
        await persistence.seed(record)
        // Arm the race: the persistence call flips currentHref to a different
        // chapter while it is in flight.
        await persistence.armRace(renderer: renderer, toHref: "chapter-9.xhtml")
        let coordinator = HighlightCoordinator(
            renderer: renderer, persistence: persistence, bookFingerprintKey: "book-1"
        )

        let outcome = await coordinator.changeColor(highlightID: record.highlightId, to: "blue")

        guard case .success = outcome else {
            Issue.record("expected .success, got \(outcome)")
            return
        }
        #expect(renderer.restoreCalls == 1)
        // The repaint must use the href captured at call time, NOT the
        // chapter-9 value the race wrote during the await.
        #expect(renderer.lastRestoreHref == "chapter-3.xhtml")
    }

    /// For a non-EPUB renderer, `changeColor` passes `forHref: nil` — the
    /// TXT/MD/PDF renderers ignore the href.
    @Test @MainActor func changeColor_nonEPUB_passesNilHref() async {
        let renderer = MutMockRenderer()
        let persistence = MutMockPersistence()
        let record = mutRecord()
        await persistence.seed(record)
        let coordinator = HighlightCoordinator(
            renderer: renderer, persistence: persistence, bookFingerprintKey: "book-1"
        )
        _ = await coordinator.changeColor(highlightID: record.highlightId, to: "green")
        #expect(renderer.lastRestoreHref == nil)
    }

    // MARK: updateNote

    @Test @MainActor func updateNote_success_returnsSuccessNoRepaint() async {
        let renderer = MutMockRenderer()
        let persistence = MutMockPersistence()
        let record = mutRecord(note: "old note")
        await persistence.seed(record)
        let coordinator = HighlightCoordinator(
            renderer: renderer, persistence: persistence, bookFingerprintKey: "book-1"
        )

        let outcome = await coordinator.updateNote(
            highlightID: record.highlightId, note: "new note"
        )

        guard case let .success(returned) = outcome else {
            Issue.record("expected .success, got \(outcome)")
            return
        }
        #expect(returned.note == "new note")
        // A note edit is invisible on the page — no reader-surface repaint.
        #expect(renderer.restoreCalls == 0)
    }

    @Test @MainActor func updateNote_recordNotFound_returnsNotFound() async {
        let renderer = MutMockRenderer()
        let persistence = MutMockPersistence()
        await persistence.setMode(.recordNotFound)
        let coordinator = HighlightCoordinator(
            renderer: renderer, persistence: persistence, bookFingerprintKey: "book-1"
        )
        let outcome = await coordinator.updateNote(highlightID: UUID(), note: "n")
        #expect(outcome == .notFound)
    }

    @Test @MainActor func updateNote_genericFailure_returnsFailed() async {
        let renderer = MutMockRenderer()
        let persistence = MutMockPersistence()
        await persistence.setMode(.genericFailure)
        let coordinator = HighlightCoordinator(
            renderer: renderer, persistence: persistence, bookFingerprintKey: "book-1"
        )
        let outcome = await coordinator.updateNote(highlightID: UUID(), note: "n")
        #expect(outcome == .failed)
    }

    /// R1-5: a read failure AFTER a successful note write surfaces as
    /// `.failed`, not `.notFound`.
    @Test @MainActor func updateNote_refetchThrowsAfterSuccess_returnsFailed() async {
        let renderer = MutMockRenderer()
        let persistence = MutMockPersistence()
        let record = mutRecord(note: "old")
        await persistence.seed(record)
        await persistence.setFetchThrowsAfterMutation(true)
        let coordinator = HighlightCoordinator(
            renderer: renderer, persistence: persistence, bookFingerprintKey: "book-1"
        )
        let outcome = await coordinator.updateNote(highlightID: record.highlightId, note: "new")
        #expect(outcome == .failed)
    }

    /// R1-5: a note write that succeeds but whose record is gone on a clean
    /// re-fetch → `.notFound`.
    @Test @MainActor func updateNote_recordGoneOnCleanRefetch_returnsNotFound() async {
        let renderer = MutMockRenderer()
        let persistence = MutMockPersistence()
        let coordinator = HighlightCoordinator(
            renderer: renderer, persistence: persistence, bookFingerprintKey: "book-1"
        )
        let outcome = await coordinator.updateNote(highlightID: UUID(), note: "n")
        #expect(outcome == .notFound)
    }

    /// A trimmed-empty draft (nil / "" / "   " / "\n\n") is normalized to
    /// `nil` before persisting — so a note "cleared" to whitespace stores as
    /// no note, and the popover flips to the empty state.
    @Test(arguments: [nil, "", "   ", "\n\n", "\t \n"])
    @MainActor func updateNote_trimmedEmptyDraft_persistsNil(_ draft: String?) async {
        let renderer = MutMockRenderer()
        let persistence = MutMockPersistence()
        let record = mutRecord(note: "had a note")
        await persistence.seed(record)
        let coordinator = HighlightCoordinator(
            renderer: renderer, persistence: persistence, bookFingerprintKey: "book-1"
        )

        let outcome = await coordinator.updateNote(highlightID: record.highlightId, note: draft)

        guard case let .success(returned) = outcome else {
            Issue.record("expected .success, got \(outcome)")
            return
        }
        #expect(await persistence.lastNoteWasSet == true)
        #expect(await persistence.lastNote == nil)
        #expect(returned.note == nil)
    }

    @Test @MainActor func updateNote_realNoteNotNormalized() async {
        let renderer = MutMockRenderer()
        let persistence = MutMockPersistence()
        let record = mutRecord(note: nil)
        await persistence.seed(record)
        let coordinator = HighlightCoordinator(
            renderer: renderer, persistence: persistence, bookFingerprintKey: "book-1"
        )
        _ = await coordinator.updateNote(highlightID: record.highlightId, note: "  real note  ")
        // Whitespace is preserved on a non-empty note — only an all-whitespace
        // draft normalizes to nil.
        #expect(await persistence.lastNote == "  real note  ")
    }

    // MARK: deleteHighlight (Feature #64 WI-4)

    @Test @MainActor func deleteHighlight_success_returnsSuccessAndRemoves() async {
        let renderer = MutMockRenderer()
        let persistence = MutMockPersistence()
        let record = mutRecord()
        await persistence.seed(record)
        let coordinator = HighlightCoordinator(
            renderer: renderer, persistence: persistence, bookFingerprintKey: "book-1"
        )
        let outcome = await coordinator.deleteHighlight(highlightID: record.highlightId)
        guard case let .success(returned) = outcome else {
            Issue.record("expected .success, got \(outcome)")
            return
        }
        #expect(returned.highlightId == record.highlightId)
        #expect(await persistence.removeCallCount == 1)
    }

    /// A delete on a highlight that no longer exists → `.notFound` (the
    /// up-front fetch finds no matching record).
    @Test @MainActor func deleteHighlight_recordGone_returnsNotFound() async {
        let renderer = MutMockRenderer()
        let persistence = MutMockPersistence()  // nothing seeded
        let coordinator = HighlightCoordinator(
            renderer: renderer, persistence: persistence, bookFingerprintKey: "book-1"
        )
        let outcome = await coordinator.deleteHighlight(highlightID: UUID())
        #expect(outcome == .notFound)
        #expect(await persistence.removeCallCount == 0)
    }

    /// A generic persistence failure on the remove call → `.failed`.
    @Test @MainActor func deleteHighlight_removeThrowsGeneric_returnsFailed() async {
        let renderer = MutMockRenderer()
        let persistence = MutMockPersistence()
        let record = mutRecord()
        await persistence.seed(record)
        await persistence.setMode(.genericFailure)
        let coordinator = HighlightCoordinator(
            renderer: renderer, persistence: persistence, bookFingerprintKey: "book-1"
        )
        // The up-front fetch also fails under .genericFailure → .failed.
        let outcome = await coordinator.deleteHighlight(highlightID: record.highlightId)
        #expect(outcome == .failed)
    }
}
#endif
