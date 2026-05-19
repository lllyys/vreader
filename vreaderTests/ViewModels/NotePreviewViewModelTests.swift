// Purpose: Tests for feature #55 WI-3 — `NotePreviewViewModel`, the
// `@Observable @MainActor` view model that consumes a `.readerHighlightTapped`
// event, looks the tapped highlight up via `HighlightLookup`, and publishes
// `NotePreviewContent` for the preview surfaces.
//
// Covers: handleTap with a found highlight publishes content; an unknown id
// leaves `presented` nil (deleted-race no-op); a throwing lookup does not
// crash; `dismiss` clears; the monotonic-tap-token out-of-order guard — a
// slow older lookup must NOT overwrite a newer tap's result; a tap after a
// dismiss does not resurrect a card.

import Testing
import Foundation
import CoreGraphics
@testable import vreader

// MARK: - Mock HighlightLookup

/// A `HighlightLookup` mock whose `highlight(withID:forBookWithKey:)` resolves
/// from a seeded table. Optionally gates the FIRST lookup behind a continuation
/// so the out-of-order test can hold an older tap mid-flight while a newer tap
/// completes — and can throw on demand.
private actor MockHighlightLookup: HighlightLookup {
    private var byID: [UUID: HighlightRecord] = [:]
    private var shouldThrow = false

    /// When set, the FIRST `highlight(...)` call awaits this gate before
    /// returning. Used to force out-of-order completion deterministically.
    private var firstCallGate: CheckedContinuation<Void, Never>?
    private var firstCallArmed = false
    private var firstCallSeen = false
    private var firstCallWaiter: CheckedContinuation<Void, Never>?

    func seed(_ record: HighlightRecord) {
        byID[record.highlightId] = record
    }

    func setThrowing(_ value: Bool) {
        shouldThrow = value
    }

    /// Arm the first-call gate. The first `highlight(...)` call will block
    /// until `releaseFirstCall()` is invoked.
    func armFirstCallGate() {
        firstCallArmed = true
    }

    /// Resume the gated first call.
    func releaseFirstCall() {
        firstCallGate?.resume()
        firstCallGate = nil
    }

    /// Suspends until the first gated call has actually entered `highlight(...)`.
    func awaitFirstCallEntered() async {
        if firstCallSeen { return }
        await withCheckedContinuation { firstCallWaiter = $0 }
    }

    func highlight(withID id: UUID, forBookWithKey key: String) async throws -> HighlightRecord? {
        if firstCallArmed {
            firstCallArmed = false
            firstCallSeen = true
            firstCallWaiter?.resume()
            firstCallWaiter = nil
            await withCheckedContinuation { firstCallGate = $0 }
        }
        if shouldThrow { throw NSError(domain: "test", code: 1) }
        return byID[id]
    }
}

// MARK: - Helpers

@MainActor
private func makeRecord(
    id: UUID = UUID(),
    note: String?,
    color: String = "yellow",
    fp: DocumentFingerprint
) -> HighlightRecord {
    let locator = Locator(
        bookFingerprint: fp,
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

private let testFP = DocumentFingerprint(
    contentSHA256: "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
    fileByteCount: 1024, format: .epub
)

private func tapEvent(for id: UUID, rect: CGRect = CGRect(x: 1, y: 2, width: 30, height: 14))
    -> ReaderHighlightTapEvent {
    ReaderHighlightTapEvent(highlightID: id, sourceRect: rect)
}

// MARK: - Tests

@Suite("NotePreviewViewModel")
@MainActor
struct NotePreviewViewModelTests {

    @Test func handleTap_foundHighlight_publishesContent() async {
        let lookup = MockHighlightLookup()
        let record = makeRecord(note: "my note body", fp: testFP)
        await lookup.seed(record)

        let vm = NotePreviewViewModel(persistence: lookup, bookFingerprintKey: "book-1")
        await vm.handleTap(tapEvent(for: record.highlightId))

        #expect(vm.presented?.id == record.highlightId)
        #expect(vm.presented?.note == "my note body")
        #expect(vm.presented?.isEmpty == false)
    }

    @Test func handleTap_noteNilHighlight_publishesEmptyContent() async {
        let lookup = MockHighlightLookup()
        let record = makeRecord(note: nil, fp: testFP)
        await lookup.seed(record)

        let vm = NotePreviewViewModel(persistence: lookup, bookFingerprintKey: "book-1")
        await vm.handleTap(tapEvent(for: record.highlightId))

        // A note-less highlight still acknowledges the tap — the empty state.
        #expect(vm.presented?.id == record.highlightId)
        #expect(vm.presented?.isEmpty == true)
    }

    @Test func handleTap_unknownID_leavesPresentedNil() async {
        let lookup = MockHighlightLookup()  // nothing seeded
        let vm = NotePreviewViewModel(persistence: lookup, bookFingerprintKey: "book-1")
        await vm.handleTap(tapEvent(for: UUID()))
        #expect(vm.presented == nil)
    }

    @Test func handleTap_lookupThrows_doesNotCrashAndPresentedNil() async {
        let lookup = MockHighlightLookup()
        await lookup.setThrowing(true)
        let vm = NotePreviewViewModel(persistence: lookup, bookFingerprintKey: "book-1")
        await vm.handleTap(tapEvent(for: UUID()))
        #expect(vm.presented == nil)
    }

    @Test func dismiss_clearsPresented() async {
        let lookup = MockHighlightLookup()
        let record = makeRecord(note: "note", fp: testFP)
        await lookup.seed(record)
        let vm = NotePreviewViewModel(persistence: lookup, bookFingerprintKey: "book-1")
        await vm.handleTap(tapEvent(for: record.highlightId))
        #expect(vm.presented != nil)

        vm.dismiss()
        #expect(vm.presented == nil)
    }

    @Test func handleTap_secondTap_replacesFirst() async {
        let lookup = MockHighlightLookup()
        let first = makeRecord(note: "first note", fp: testFP)
        let second = makeRecord(note: "second note", fp: testFP)
        await lookup.seed(first)
        await lookup.seed(second)
        let vm = NotePreviewViewModel(persistence: lookup, bookFingerprintKey: "book-1")

        await vm.handleTap(tapEvent(for: first.highlightId))
        #expect(vm.presented?.id == first.highlightId)
        await vm.handleTap(tapEvent(for: second.highlightId))
        #expect(vm.presented?.id == second.highlightId)
    }

    /// The core out-of-order guard: an OLDER tap whose lookup is slow must NOT
    /// overwrite a NEWER tap's already-published result.
    @Test func handleTap_outOfOrder_olderSlowLookupDoesNotOverwriteNewer() async {
        let lookup = MockHighlightLookup()
        let older = makeRecord(note: "OLD note", fp: testFP)
        let newer = makeRecord(note: "NEW note", fp: testFP)
        await lookup.seed(older)
        await lookup.seed(newer)
        let vm = NotePreviewViewModel(persistence: lookup, bookFingerprintKey: "book-1")

        // Arm the gate so the FIRST lookup (the older tap) blocks mid-flight.
        await lookup.armFirstCallGate()
        let olderTask = Task { await vm.handleTap(tapEvent(for: older.highlightId)) }
        await lookup.awaitFirstCallEntered()  // older tap is now suspended in the lookup

        // The newer tap runs to completion while the older is parked.
        await vm.handleTap(tapEvent(for: newer.highlightId))
        #expect(vm.presented?.id == newer.highlightId)

        // Release the older tap — its result must be discarded (token stale).
        await lookup.releaseFirstCall()
        await olderTask.value

        #expect(vm.presented?.id == newer.highlightId)
        #expect(vm.presented?.note == "NEW note")
    }

    /// A `handleTap` whose lookup is in flight when `dismiss()` is called must
    /// not resurrect a card after the dismiss.
    @Test func handleTap_inFlightThenDismiss_doesNotResurrect() async {
        let lookup = MockHighlightLookup()
        let record = makeRecord(note: "should not appear", fp: testFP)
        await lookup.seed(record)
        let vm = NotePreviewViewModel(persistence: lookup, bookFingerprintKey: "book-1")

        await lookup.armFirstCallGate()
        let tapTask = Task { await vm.handleTap(tapEvent(for: record.highlightId)) }
        await lookup.awaitFirstCallEntered()

        // Dismiss while the lookup is parked.
        vm.dismiss()
        // Release the parked lookup — it must NOT publish (token bumped by dismiss).
        await lookup.releaseFirstCall()
        await tapTask.value

        #expect(vm.presented == nil)
    }
}
