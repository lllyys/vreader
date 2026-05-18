// Purpose: Feature #63 WI-1 — the testable callback contract for the
// re-skinned search sheet. The v2 re-skin replaces the system
// `.searchable` bar + NavigationStack toolbar with a custom in-sheet
// chrome; this value type holds the two host callbacks (`onNavigate`,
// `onCancel`) so `SearchView`'s wiring is verifiable without rendering
// the SwiftUI view.
//
// Key decisions:
// - Pure value type — no SwiftUI dependency, no `@MainActor` rendering
//   needed. The view constructs one from its `onNavigate` / `onDismiss`
//   inputs and calls `navigate(to:)` / `cancel()` from button actions.
// - `navigate(to:)` forwards the result's `Locator` — the
//   behavior-preserving guard that result-tap navigation is unchanged.
//
// @coordinates-with: SearchView.swift, SearchBar.swift,
//   SearchResult (SearchService.swift), Locator.swift

import Foundation

/// The search sheet's host callbacks, bundled for testable wiring.
struct SearchViewActions {
    /// Dismisses the search sheet (the "Cancel" button).
    let onCancel: () -> Void
    /// Navigates the reader to a tapped result's position.
    let onNavigate: (Locator) -> Void

    /// Runs the dismiss closure — wired to the custom bar's "Cancel".
    func cancel() {
        onCancel()
    }

    /// Forwards the tapped result's `Locator` to the navigation closure.
    /// Preserves the v1 result-tap → reader-navigation behavior exactly.
    func navigate(to result: SearchResult) {
        onNavigate(result.locator)
    }
}
