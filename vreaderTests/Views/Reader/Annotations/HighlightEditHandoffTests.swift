// Purpose: Feature #1121 WI-1 — tests for the pure Edit-handoff routing
// (`HighlightEditHandoff`) + the `ReaderHighlightTapEvent.openInEditMode` flag
// that carries the auto-open-in-editing intent through the popover pipeline.

#if canImport(UIKit)
import Testing
import Foundation
import CoreGraphics
@testable import vreader

@Suite("HighlightEditHandoff (Feature #1121)")
struct HighlightEditHandoffTests {

    // MARK: - Routing

    @Test("a highlight item → a ReaderHighlightEditRequest for that id/book/token")
    func highlightRoutesToEditRequest() {
        let record = makeHighlightRecord(note: "note")
        let token = UUID()
        let action = HighlightEditHandoff.action(
            for: .highlight(record), bookFingerprintKey: "book-key", token: token)
        #expect(action == .requestHighlightEdit(ReaderHighlightEditRequest(
            highlightID: record.highlightId, bookFingerprintKey: "book-key", token: token)))
    }

    @Test("a standalone item → the standalone-note editor route")
    func standaloneRoutesToNoteEditor() {
        let record = makeAnnotationRecord()
        let action = HighlightEditHandoff.action(
            for: .standalone(record), bookFingerprintKey: "book-key", token: UUID())
        #expect(action == .openStandaloneNote(annotationID: record.annotationId))
    }

    // MARK: - ReaderHighlightTapEvent.openInEditMode

    @Test("openInEditMode defaults false — a normal tap is unchanged")
    func openInEditModeDefaultsFalse() {
        let event = ReaderHighlightTapEvent(highlightID: UUID(), sourceRect: .zero)
        #expect(event.openInEditMode == false)
    }

    @Test("Equatable distinguishes the edit-mode flag")
    func equalityIncludesFlag() {
        let id = UUID()
        let reading = ReaderHighlightTapEvent(highlightID: id, sourceRect: .zero)
        let editing = ReaderHighlightTapEvent(highlightID: id, sourceRect: .zero, openInEditMode: true)
        #expect(reading != editing)
        #expect(reading == ReaderHighlightTapEvent(highlightID: id, sourceRect: .zero, openInEditMode: false))
    }

    // MARK: - ReaderHighlightEditRequest single-flight identity

    @Test("requests with different tokens are distinct (single-flight supersession)")
    func requestTokenDistinguishes() {
        let id = UUID()
        let r1 = ReaderHighlightEditRequest(highlightID: id, bookFingerprintKey: "k", token: UUID())
        let r2 = ReaderHighlightEditRequest(highlightID: id, bookFingerprintKey: "k", token: UUID())
        #expect(r1 != r2)
    }
}
#endif
