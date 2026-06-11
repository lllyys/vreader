// Purpose: Feature #61 WI-3 / Feature #56 WI-8 — the host-side effect
// a reader More-menu row resolves to. `ReaderMoreMenuRow` is the
// popover-presentation model (label / icon / notification / trailing
// control); this enum is the reader-host routing model — it names
// what `ReaderContainerView` does when a row is tapped, decoupled
// from the `@State` mutation so the routing decision is unit-testable
// without a SwiftUI render path.
//
// It pins feature #61's behavior change: `.bookDetails` now resolves
// to `.presentBookDetails` (the dedicated Book Details sheet),
// replacing the feature-#60 WI-6c interim that routed the row to the
// reader settings panel. Feature #56 WI-8 adds `.toggleBilingual`
// (or `.presentAIProviderSettings` when bilingual is unavailable) and
// `.presentReTranslatePicker`.
//
// @coordinates-with: ReaderMoreMenuRow.swift, ReaderContainerView+Sheets.swift,
//   BookDetailsRouteTests.swift, BilingualReadingViewModel.swift

import Foundation

/// The reader-host effect a `ReaderMoreMenuRow` tap triggers. Case
/// names describe the *host action*, not the menu row — e.g.
/// `presentAnnotationsExport` records that the Export-annotations row
/// reuses the annotations panel rather than opening a dedicated export
/// sheet. `ReaderContainerView.handleMoreMenuAction(_:)` switches on
/// this; `BookDetailsRouteTests` pins the row → effect mapping.
enum ReaderMoreMenuEffect: Hashable {
    /// Start or stop text-to-speech read-aloud.
    case toggleReadAloud
    /// Flip the auto-page-turn setting.
    case toggleAutoPageTurn
    /// Toggle bilingual mode for the active book (feature #56 WI-8).
    /// Hosts route to `BilingualReadingViewModel.setEnabled(...)`.
    case toggleBilingual
    /// Feature #99: re-open the bilingual setup sheet edit-framed
    /// ("Translation settings"). Like `.toggleBilingual`, the actual
    /// presentation lives in the per-format hosts (they observe the
    /// keyed `.readerMoreTranslationSettings` directly) — the container
    /// treats this effect as a no-op.
    case presentTranslationSettings
    /// Open the per-chapter re-translation picker sheet (feature #56
    /// WI-8 — design §#864). Visible only while bilingual mode is on.
    case presentReTranslatePicker
    /// Present the dedicated Book Details sheet (feature #61).
    case presentBookDetails
    /// Present the system share sheet for the book file.
    case presentShareSheet
    /// Open the annotations panel on its Highlights tab — the export
    /// affordance lives there; the row has no dedicated export sheet.
    case presentAnnotationsExport

    /// Resolves the host effect for a tapped More-menu row. Exhaustive
    /// over `ReaderMoreMenuRow` so a future row forces a decision here.
    ///
    /// Note: the bilingual row's `.unavailable` state needs a different
    /// host action ("open AI provider Settings") than the `.on`/`.off`
    /// states. The row-only signature can't see bilingual state, so it
    /// maps to `.toggleBilingual` here; the host's
    /// `handleMoreMenuAction(_:)` dispatches to AI Settings when the
    /// VM is in `.unavailable`.
    init(row: ReaderMoreMenuRow) {
        switch row {
        case .readAloud:           self = .toggleReadAloud
        case .autoTurnPages:       self = .toggleAutoPageTurn
        case .bilingual:           self = .toggleBilingual
        case .translationSettings: self = .presentTranslationSettings
        case .reTranslateChapter:  self = .presentReTranslatePicker
        case .bookDetails:         self = .presentBookDetails
        case .shareBook:           self = .presentShareSheet
        case .exportAnnotations:   self = .presentAnnotationsExport
        }
    }
}
