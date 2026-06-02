// Purpose: Feature #82 — the 3-gate readiness progress row at the top of the
// in-reader AI readiness sheet. Doubles as the explainer ("why am I still
// seeing Set up?") by showing exactly which gates remain. Three user-facing
// steps (Turn on AI · Allow data · Add provider) map to the four
// `BilingualAIReadiness` requirements — the API-key gate rides inside the
// provider gate (a saved provider always carries a key to be "ready").
//
// Pure value-driven (no observation) — the container passes the cached gate
// bools from `ReaderAIProvidersFlow`.
//
// Layout pinned to `dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-readiness.jsx`
// (`ReadinessTracker`).
//
// @coordinates-with: ReaderAIReadinessView.swift, ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-readiness.jsx`

import SwiftUI

/// The connected three-gate progress row. Each step is `done` / `active`
/// (first not-done) / `todo`.
struct ReadinessTracker: View {

    let theme: ReaderThemeV2
    /// Gate 1 — `aiAssistant` flag.
    let aiOn: Bool
    /// Gate 2 — AI consent granted.
    let consentOn: Bool
    /// Gate 3 — an active provider WITH a key (gates 3+4 collapsed).
    let providerReady: Bool

    /// `RDY_GREEN` from the design — "satisfied".
    private var doneColor: Color { Color(red: 0.227, green: 0.416, blue: 0.353) }

    private struct Step { let label: String; let done: Bool }

    private var steps: [Step] {
        [Step(label: "Turn on AI", done: aiOn),
         Step(label: "Allow data", done: consentOn),
         Step(label: "Add provider", done: providerReady)]
    }

    var body: some View {
        let steps = self.steps
        let activeIdx = steps.firstIndex(where: { !$0.done }) ?? steps.count
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                stepCell(step, index: index, activeIdx: activeIdx)
                if index < steps.count - 1 {
                    Rectangle()
                        .fill(step.done ? doneColor : Color(theme.ruleColor))
                        .frame(height: 1.5)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 11)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("readinessTracker")
    }

    @ViewBuilder
    private func stepCell(_ step: Step, index: Int, activeIdx: Int) -> some View {
        let isActive = index == activeIdx
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(step.done
                          ? doneColor
                          : (isActive ? Color(theme.accentColor) : Color(theme.ruleColor).opacity(0.4)))
                    .frame(width: 24, height: 24)
                if step.done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white)
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isActive ? Color.white : Color(theme.subColor))
                }
            }
            Text(step.label)
                .font(.system(size: 10.5, weight: step.done || isActive ? .semibold : .regular))
                .foregroundStyle(step.done || isActive ? Color(theme.inkColor) : Color(theme.subColor))
                .fixedSize()
        }
        .frame(width: 78)
    }
}
