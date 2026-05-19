// Purpose: Feature #64 WI-1 — tests for `HighlightPopoverAction`, the single
// enum the unified highlight-action popover view emits.
//
// Pins the case set + `Equatable` semantics (including the `changeColor`
// associated `NamedHighlightColor` and the `saveNote` string payload) so the
// modifier's action-routing tests have a stable contract to assert against.

import Testing
import Foundation
@testable import vreader

@Suite("HighlightPopoverAction")
struct HighlightPopoverActionTests {

    @Test func changeColor_carriesNamedColor() {
        let action = HighlightPopoverAction.changeColor(.pink)
        #expect(action == .changeColor(.pink))
        #expect(action != .changeColor(.green))
    }

    @Test func saveNote_carriesPayload() {
        #expect(HighlightPopoverAction.saveNote("hello") == .saveNote("hello"))
        #expect(HighlightPopoverAction.saveNote("hello") != .saveNote("world"))
    }

    @Test func saveNote_emptyPayloadDistinctFromNonEmpty() {
        #expect(HighlightPopoverAction.saveNote("") != .saveNote(" "))
    }

    @Test func valuelessCases_equateBySelf() {
        #expect(HighlightPopoverAction.beginEdit == .beginEdit)
        #expect(HighlightPopoverAction.cancelEdit == .cancelEdit)
        #expect(HighlightPopoverAction.copy == .copy)
        #expect(HighlightPopoverAction.share == .share)
        #expect(HighlightPopoverAction.requestDelete == .requestDelete)
        #expect(HighlightPopoverAction.confirmDelete == .confirmDelete)
    }

    @Test func distinctCases_differ() {
        #expect(HighlightPopoverAction.beginEdit != .cancelEdit)
        #expect(HighlightPopoverAction.copy != .share)
        #expect(HighlightPopoverAction.requestDelete != .confirmDelete)
        #expect(HighlightPopoverAction.changeColor(.yellow) != .beginEdit)
        #expect(HighlightPopoverAction.saveNote("x") != .beginEdit)
    }
}
