// Purpose: Tests for `HighlightTapAction` enum (Feature #53 / GH #596).
// WI-1 ships `.delete` only. Future cases extend the menu builder and the
// coordinator switch; this suite ensures the switch stays exhaustive.
//
// @coordinates-with: HighlightTapAction.swift, HighlightCoordinator.swift

import Testing
@testable import vreader

@Suite("HighlightTapAction")
struct HighlightTapActionTests {

    @Test
    func tapAction_delete_equalsItself() {
        #expect(HighlightTapAction.delete == HighlightTapAction.delete)
    }

    /// Exhaustive-switch guard: if a future case is added without updating
    /// `HighlightCoordinator.handleTapAction(_:highlightID:)`, this test
    /// won't catch it — but adding a case here without a matching arm in
    /// the production switch becomes a compile error. Tracked here so
    /// reviewers see the exhaustiveness contract.
    @Test
    func tapAction_isExhaustivelySwitchable() {
        let action = HighlightTapAction.delete
        let result: String
        switch action {
        case .delete: result = "delete"
        }
        #expect(result == "delete")
    }
}
