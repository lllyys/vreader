// Purpose: Feature #64 WI-1 — tests for `HighlightPopoverMode`,
// `HighlightPopoverForm`, and `HighlightMutationOutcome`.
//
// These are simple value enums; the tests pin `Equatable` semantics so the
// presenter's outcome routing (`.success` → refresh, `.notFound` → dismiss,
// `.failed` → stay open) and the card's mode transitions stay assertable.

import Testing
import Foundation
@testable import vreader

@Suite("HighlightPopoverMode")
struct HighlightPopoverModeTests {

    @Test func mode_casesAreDistinct() {
        #expect(HighlightPopoverMode.reading != .editing)
        #expect(HighlightPopoverMode.editing != .confirmingDelete)
        #expect(HighlightPopoverMode.reading != .confirmingDelete)
    }

    @Test func mode_sameCaseEquates() {
        #expect(HighlightPopoverMode.reading == .reading)
        #expect(HighlightPopoverMode.editing == .editing)
        #expect(HighlightPopoverMode.confirmingDelete == .confirmingDelete)
    }

    @Test func form_casesAreDistinct() {
        #expect(HighlightPopoverForm.card != .sheet)
    }

    @Test func form_sameCaseEquates() {
        #expect(HighlightPopoverForm.card == .card)
        #expect(HighlightPopoverForm.sheet == .sheet)
    }
}

@Suite("HighlightMutationOutcome")
struct HighlightMutationOutcomeTests {

    private func makeRecord(note: String? = nil, color: String = "yellow") -> HighlightRecord {
        let fingerprint = DocumentFingerprint(
            contentSHA256: String(repeating: "a", count: 64),
            fileByteCount: 100,
            format: .txt
        )
        let locator = Locator.validated(
            bookFingerprint: fingerprint, charOffsetUTF16: 0
        )!
        return HighlightRecord(
            highlightId: UUID(),
            locator: locator,
            anchor: nil,
            profileKey: "p",
            selectedText: "text",
            color: color,
            note: note,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
    }

    @Test func success_equatesWhenRecordEqual() {
        let record = makeRecord(note: "n")
        #expect(HighlightMutationOutcome.success(record) == .success(record))
    }

    @Test func success_differsWhenRecordDiffers() {
        #expect(
            HighlightMutationOutcome.success(makeRecord(color: "pink"))
                != .success(makeRecord(color: "blue"))
        )
    }

    @Test func notFound_andFailed_areDistinct() {
        #expect(HighlightMutationOutcome.notFound != .failed)
        #expect(HighlightMutationOutcome.notFound == .notFound)
        #expect(HighlightMutationOutcome.failed == .failed)
    }

    @Test func success_differsFromNotFoundAndFailed() {
        let outcome = HighlightMutationOutcome.success(makeRecord())
        #expect(outcome != .notFound)
        #expect(outcome != .failed)
    }
}
