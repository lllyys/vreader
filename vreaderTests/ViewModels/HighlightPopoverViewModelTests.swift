// Purpose: Feature #64 WI-1 — tests for `HighlightPopoverViewModel`, the
// `@Observable @MainActor` view model behind the unified highlight-action
// popover. Consumes a `.readerHighlightTapped` event, looks the tapped
// highlight up via `HighlightLookup`, and publishes a `HighlightPopoverContent`.
//
// Covers: handleTap publishes content for a found highlight (with `chapter`
// carried); an unknown id leaves `presented` nil (deleted-race no-op); a
// throwing lookup does not crash; `dismiss` clears; the monotonic-tap-token
// out-of-order guard (slow older lookup must not overwrite a newer tap, even
// on the throw path); a dismiss mid-flight suppresses a stale lookup;
// `refreshPresented` rebuilds with a mutated record preserving rect + chapter.

import Testing
import Foundation
import CoreGraphics
@testable import vreader

// MARK: - Mock HighlightLookup (file-scoped — distinct from #55's test mock)

/// A `HighlightLookup` mock resolving from a seeded table, with an arm-able
/// gate so the out-of-order tests can hold an older lookup mid-flight while a
/// newer tap completes. Mirrors the proven #55 `NotePreviewViewModelTests` mock.
private actor PopoverLookupMock: HighlightLookup {
    private var byID: [UUID: HighlightRecord] = [:]
    private var shouldThrow = false

    private var firstCallGate: CheckedContinuation<Void, Never>?
    private var firstCallArmed = false
    private var firstCallSeen = false
    private var firstCallWaiter: CheckedContinuation<Void, Never>?
    private var firstCallThrows = false

    func seed(_ record: HighlightRecord) { byID[record.highlightId] = record }
    func setThrowing(_ value: Bool) { shouldThrow = value }

    /// Arm the first-call gate; the first `highlight(...)` call blocks until
    /// `releaseFirstCall()`. `throwsOnRelease` makes that gated call throw.
    func armFirstCallGate(throwsOnRelease: Bool = false) {
        firstCallArmed = true
        firstCallThrows = throwsOnRelease
    }

    func releaseFirstCall() {
        firstCallGate?.resume()
        firstCallGate = nil
    }

    /// Suspends until the gated first call has actually entered `highlight(...)`.
    func awaitFirstCallEntered() async {
        if firstCallSeen { return }
        await withCheckedContinuation { firstCallWaiter = $0 }
    }

    func highlight(withID id: UUID, forBookWithKey key: String) async throws -> HighlightRecord? {
        var throwAfterGate = false
        if firstCallArmed {
            firstCallArmed = false
            firstCallSeen = true
            throwAfterGate = firstCallThrows
            firstCallWaiter?.resume()
            firstCallWaiter = nil
            await withCheckedContinuation { firstCallGate = $0 }
        }
        if throwAfterGate || shouldThrow { throw NSError(domain: "test", code: 1) }
        return byID[id]
    }
}

// MARK: - Helpers

private let popoverTestFP = DocumentFingerprint(
    contentSHA256: "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
    fileByteCount: 1024, format: .epub
)

@MainActor
private func makeRecord(
    id: UUID = UUID(),
    note: String?,
    color: String = "yellow"
) -> HighlightRecord {
    let locator = Locator(
        bookFingerprint: popoverTestFP,
        href: "ch1.xhtml", progression: 0.5, totalProgression: nil,
        cfi: "/6/4", page: nil,
        charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
        textQuote: nil, textContextBefore: nil, textContextAfter: nil
    )
    return HighlightRecord(
        highlightId: id, locator: locator, anchor: nil, profileKey: "key",
        selectedText: "the passage", color: color, note: note,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

private func tapEvent(for id: UUID, rect: CGRect = CGRect(x: 1, y: 2, width: 30, height: 14))
    -> ReaderHighlightTapEvent {
    ReaderHighlightTapEvent(highlightID: id, sourceRect: rect)
}

// MARK: - Tests

@Suite("HighlightPopoverViewModel")
@MainActor
struct HighlightPopoverViewModelTests {

    @Test func handleTap_foundHighlight_publishesContentWithChapter() async {
        let lookup = PopoverLookupMock()
        let record = makeRecord(note: "my note body")
        await lookup.seed(record)

        let vm = HighlightPopoverViewModel(persistence: lookup, bookFingerprintKey: "book-1")
        await vm.handleTap(tapEvent(for: record.highlightId), chapter: "Chapter 1")

        #expect(vm.presented?.id == record.highlightId)
        #expect(vm.presented?.note == "my note body")
        #expect(vm.presented?.isEmpty == false)
        #expect(vm.presented?.chapter == "Chapter 1")
    }

    @Test func handleTap_noteNilHighlight_publishesEmptyContent() async {
        let lookup = PopoverLookupMock()
        let record = makeRecord(note: nil)
        await lookup.seed(record)

        let vm = HighlightPopoverViewModel(persistence: lookup, bookFingerprintKey: "book-1")
        await vm.handleTap(tapEvent(for: record.highlightId), chapter: nil)

        #expect(vm.presented?.id == record.highlightId)
        #expect(vm.presented?.isEmpty == true)
        #expect(vm.presented?.chapter == nil)
    }

    @Test func handleTap_unknownID_leavesPresentedNil() async {
        let lookup = PopoverLookupMock()  // nothing seeded
        let vm = HighlightPopoverViewModel(persistence: lookup, bookFingerprintKey: "book-1")
        await vm.handleTap(tapEvent(for: UUID()), chapter: nil)
        #expect(vm.presented == nil)
    }

    @Test func handleTap_lookupThrows_doesNotCrashAndPresentedNil() async {
        let lookup = PopoverLookupMock()
        await lookup.setThrowing(true)
        let vm = HighlightPopoverViewModel(persistence: lookup, bookFingerprintKey: "book-1")
        await vm.handleTap(tapEvent(for: UUID()), chapter: nil)
        #expect(vm.presented == nil)
    }

    @Test func dismiss_clearsPresented() async {
        let lookup = PopoverLookupMock()
        let record = makeRecord(note: "note")
        await lookup.seed(record)
        let vm = HighlightPopoverViewModel(persistence: lookup, bookFingerprintKey: "book-1")
        await vm.handleTap(tapEvent(for: record.highlightId), chapter: nil)
        #expect(vm.presented != nil)

        vm.dismiss()
        #expect(vm.presented == nil)
    }

    @Test func handleTap_secondTap_replacesFirst() async {
        let lookup = PopoverLookupMock()
        let first = makeRecord(note: "first note")
        let second = makeRecord(note: "second note")
        await lookup.seed(first)
        await lookup.seed(second)
        let vm = HighlightPopoverViewModel(persistence: lookup, bookFingerprintKey: "book-1")

        await vm.handleTap(tapEvent(for: first.highlightId), chapter: nil)
        #expect(vm.presented?.id == first.highlightId)
        await vm.handleTap(tapEvent(for: second.highlightId), chapter: nil)
        #expect(vm.presented?.id == second.highlightId)
    }

    /// The core out-of-order guard: an OLDER tap whose lookup is slow must NOT
    /// overwrite a NEWER tap's already-published result.
    @Test func handleTap_outOfOrder_olderSlowLookupDoesNotOverwriteNewer() async {
        let lookup = PopoverLookupMock()
        let older = makeRecord(note: "OLD note")
        let newer = makeRecord(note: "NEW note")
        await lookup.seed(older)
        await lookup.seed(newer)
        await lookup.armFirstCallGate()
        let vm = HighlightPopoverViewModel(persistence: lookup, bookFingerprintKey: "book-1")

        // Start the older tap; it blocks inside the gated lookup.
        async let olderTap: Void = vm.handleTap(tapEvent(for: older.highlightId), chapter: nil)
        await lookup.awaitFirstCallEntered()

        // The newer tap runs to completion while the older one is parked.
        await vm.handleTap(tapEvent(for: newer.highlightId), chapter: nil)
        #expect(vm.presented?.id == newer.highlightId)

        // Release the older lookup — its stale token must suppress its result.
        await lookup.releaseFirstCall()
        await olderTap
        #expect(vm.presented?.id == newer.highlightId)
    }

    /// The out-of-order guard on the throw path: a slow older lookup that
    /// throws after a newer tap published must not clear the newer result.
    @Test func handleTap_outOfOrder_olderSlowThrowDoesNotClearNewer() async {
        let lookup = PopoverLookupMock()
        let newer = makeRecord(note: "NEW note")
        await lookup.seed(newer)
        await lookup.armFirstCallGate(throwsOnRelease: true)
        let vm = HighlightPopoverViewModel(persistence: lookup, bookFingerprintKey: "book-1")

        async let olderTap: Void = vm.handleTap(tapEvent(for: UUID()), chapter: nil)
        await lookup.awaitFirstCallEntered()

        await vm.handleTap(tapEvent(for: newer.highlightId), chapter: nil)
        #expect(vm.presented?.id == newer.highlightId)

        await lookup.releaseFirstCall()
        await olderTap
        // The stale throwing lookup must not wipe the newer card.
        #expect(vm.presented?.id == newer.highlightId)
    }

    /// A dismiss issued while a lookup is in flight must suppress that lookup's
    /// result so it cannot resurrect a card after the user dismissed.
    @Test func dismiss_midFlight_suppressesStaleLookup() async {
        let lookup = PopoverLookupMock()
        let record = makeRecord(note: "note")
        await lookup.seed(record)
        await lookup.armFirstCallGate()
        let vm = HighlightPopoverViewModel(persistence: lookup, bookFingerprintKey: "book-1")

        async let tap: Void = vm.handleTap(tapEvent(for: record.highlightId), chapter: nil)
        await lookup.awaitFirstCallEntered()

        vm.dismiss()  // bumps the token while the lookup is parked

        await lookup.releaseFirstCall()
        await tap
        #expect(vm.presented == nil)
    }

    @Test func refreshPresented_rebuildsWithMutatedRecordPreservingRectAndChapter() async {
        let lookup = PopoverLookupMock()
        let record = makeRecord(note: "old note", color: "yellow")
        await lookup.seed(record)
        let vm = HighlightPopoverViewModel(persistence: lookup, bookFingerprintKey: "book-1")

        let rect = CGRect(x: 5, y: 6, width: 40, height: 16)
        await vm.handleTap(tapEvent(for: record.highlightId, rect: rect), chapter: "Chapter 7")
        #expect(vm.presented?.colorName == "yellow")
        #expect(vm.presented?.note == "old note")

        // Simulate a successful recolor + note save persisting elsewhere.
        let mutated = makeRecord(id: record.highlightId, note: "new note", color: "pink")
        vm.refreshPresented(with: mutated)

        #expect(vm.presented?.id == record.highlightId)
        #expect(vm.presented?.colorName == "pink")
        #expect(vm.presented?.note == "new note")
        // The sourceRect and chapter from the original tap are preserved.
        #expect(vm.presented?.sourceRect == rect)
        #expect(vm.presented?.chapter == "Chapter 7")
    }

    @Test func refreshPresented_noOpWhenNothingPresented() async {
        let lookup = PopoverLookupMock()
        let vm = HighlightPopoverViewModel(persistence: lookup, bookFingerprintKey: "book-1")
        let record = makeRecord(id: UUID(), note: "n")
        vm.refreshPresented(with: record)
        #expect(vm.presented == nil)
    }
}
