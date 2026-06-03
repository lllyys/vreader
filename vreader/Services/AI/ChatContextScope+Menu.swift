// Purpose: The Chat scope-menu copy for each `ChatContextScope` — the one-line
// descriptor + token estimate shown in `ChatScopeMenu`, and the menu footer
// (spoiler-aware for Whole book). Feature #86 WI-3. Kept on the enum (not inlined
// in the view) so the strings are centralized and unit-testable, matching the
// committed #1455 design copy exactly.
//
// @coordinates-with: ChatContextScope.swift, ChatScopeMenu.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/design-notes/chat-ai-scope-sources.md`

import Foundation

extension ChatContextScope {
    /// The one-line descriptor under the scope's name in the menu.
    var menuDescription: String {
        switch self {
        case .section:   return "Just the passage you’re reading"
        case .chapter:   return "The whole current chapter"
        case .bookSoFar: return "Everything up to your page"
        case .wholeBook: return "Reads the entire book on demand"
        }
    }

    /// The trailing token estimate. Whole book is on-demand (retrieved), so it
    /// shows "On-demand" rather than a fixed count.
    var tokenEstimate: String {
        switch self {
        case .section:   return "~600 tokens"
        case .chapter:   return "~4.2k tokens"
        case .bookSoFar: return "~58k tokens"
        case .wholeBook: return "on-demand"   // matches the #1455 source string verbatim
        }
    }

    /// The menu footer for a given selected scope. Whole book is the one
    /// spoiler-aware scope, so it gets the spoiler caption; every other scope
    /// gets the cost caption.
    static func menuFooter(forSelected scope: ChatContextScope) -> String {
        scope.spoilerAware
            ? "Whole book can reference pages ahead of you — answers may contain spoilers."
            : "Larger scopes give fuller answers but cost more per message."
    }
}
