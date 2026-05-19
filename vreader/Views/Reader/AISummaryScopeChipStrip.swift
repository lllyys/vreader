// Purpose: Feature #69 WI-5 — the AI Summarize tab's scope chip strip.
// Extracted from `AISummaryTabView.swift` so that file stays under the
// ~300-line guideline.
//
// The pill row of three scope chips (Section / Chapter / Book so far),
// rendered above the Summarize tab's state body. Mirrors the committed
// design `vreader-panels.jsx` `SummaryView`: each chip is a pill
// (`padding 6×12`, `borderRadius 100`, `fontSize 12 weight 500`); the
// active chip is filled `theme.accentColor` with white text, an
// inactive chip uses the neutral `0.06`-dark / `0.05`-light wash with
// `theme.inkColor` text.
//
// @coordinates-with: AISummaryTabView.swift, SummaryScope.swift,
//   ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`

#if canImport(UIKit)
import SwiftUI

/// The AI Summarize tab's scope chip strip — the design's pill row.
struct AISummaryScopeChipStrip: View {

    /// The scopes to render, in chip-strip order.
    let scopes: [SummaryScope]

    /// The currently-selected scope (its chip renders filled).
    let activeScope: SummaryScope

    /// Visual-identity-v2 theme tokens.
    let theme: ReaderThemeV2

    /// Invoked when a chip is tapped — passes the tapped scope.
    let onSelect: (SummaryScope) -> Void

    /// The accessibility identifier for a scope chip — also used by the
    /// XCUITest acceptance pass.
    static func chipIdentifier(_ scope: SummaryScope) -> String {
        "aiSummaryScopeChip.\(scope.rawValue)"
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(scopes, id: \.self) { scope in
                chip(for: scope)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 2)
        .accessibilityIdentifier("aiSummaryScopeStrip")
    }

    /// One scope chip — a pill button styled to the design.
    @ViewBuilder
    private func chip(for scope: SummaryScope) -> some View {
        let isActive = scope == activeScope
        Button { onSelect(scope) } label: {
            Text(scope.displayName)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(isActive ? Color.white : Color(theme.inkColor))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(
                        isActive
                            ? Color(theme.accentColor)
                            : Color(inactiveChipFill)
                    )
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(Self.chipIdentifier(scope))
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    /// The neutral chip wash for an inactive scope chip — design
    /// `SummaryView` (`rgba(255,255,255,0.06)` dark / `rgba(0,0,0,0.05)`
    /// light).
    private var inactiveChipFill: UIColor {
        theme.isDark
            ? UIColor.white.withAlphaComponent(0.06)
            : UIColor.black.withAlphaComponent(0.05)
    }
}
#endif
