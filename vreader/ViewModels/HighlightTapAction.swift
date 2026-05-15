// Purpose: Action emitted by HighlightActionPresenting after the user
// resolves the inline menu shown on a highlight tap (Feature #53 / GH #596).
//
// WI-1 ships .delete only — matches the row's minimum acceptance criterion
// ("at minimum a Delete option"). Future cases (editColor, addNote, copy)
// extend the menu; HighlightCoordinator.handleTapAction(_:highlightID:)
// switches exhaustively so adding a case is a compile-time prompt to wire
// it everywhere.
//
// @coordinates-with: HighlightActionPresenter.swift,
//   HighlightCoordinator.swift, ReaderNotifications.swift

import Foundation

enum HighlightTapAction: Sendable, Equatable {
    case delete
}
