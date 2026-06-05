// Purpose: The pure, view-state resolver for the Chat composer's send disc
// (Feature #87 WI-1). The 32px send button morphs in place between three looks
// — disabled / send / stop — and this enum + resolver capture that decision so
// it is unit-testable without rendering the view (kept out of the VM to avoid
// view-state leaking into the model).
//
// @coordinates-with: AIChatView+Composer.swift, AIChatViewModel.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/design-notes/stop-control-87.md`

import Foundation

/// The three resting looks of the composer's send disc, per the #87 design.
/// - `.disabled` — neutral disc, muted arrow, not pressable (no input / composer disabled).
/// - `.send` — accent disc, white `arrow.up`; submits the draft.
/// - `.stop` — accent disc, white `square.fill` + sweeping ring; aborts the in-flight request.
enum ComposerSendState: Equatable, Sendable {
    case disabled
    case send
    case stop

    /// Resolves the send-disc state from the composer's inputs. A request in
    /// flight always wins (the disc shows Stop even with no draft / a disabled
    /// composer); otherwise an empty draft or a disabled composer is `.disabled`;
    /// otherwise `.send`.
    static func resolve(
        isLoading: Bool,
        hasInput: Bool,
        isComposerDisabled: Bool
    ) -> ComposerSendState {
        if isLoading { return .stop }
        if !hasInput || isComposerDisabled { return .disabled }
        return .send
    }
}
