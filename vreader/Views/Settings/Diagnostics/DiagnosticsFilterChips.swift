// Purpose: Feature #96 WI-2 — the two chip rows under the viewer nav bar
// (design `DiagFilterBar`): a level row (All / Errors / Debug / Info, each with
// a count) and a horizontally-scrollable category row. Active chip = inverted
// ink pill (HighlightsSheet vocabulary); the Errors chip takes the error tint
// when active so a filtered list is legible at a glance.
//
// Pinned to `dev-docs/designs/vreader-fidelity-v1/project/vreader-diagnostics.jsx`.
//
// @coordinates-with: DiagnosticsLogView.swift, DiagnosticsLogViewModel.swift,
//   DiagnosticsLevelStyle.swift

import SwiftUI

/// One filter chip — a pill with an optional count. Active chips invert to the
/// `tint` (or theme ink) fill; inactive chips are an outlined `sub` pill.
struct DiagnosticsChip: View {
    let theme: ReaderThemeV2
    let label: String
    let count: Int?
    let isActive: Bool
    /// An override fill for the active state (the Errors chip's error tint).
    var activeTint: Color?
    let action: () -> Void

    private var activeFill: Color { activeTint ?? Color(theme.inkColor) }

    private var foreground: Color {
        guard isActive else { return Color(theme.subColor) }
        if activeTint != nil { return .white }
        // Inverted-ink pill: foreground is the sheet surface.
        return Color(theme.isDark ? UIColor(white: 0.1, alpha: 1) : theme.sheetSurfaceColor)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label)
                    .font(.system(size: 12.5, weight: .semibold))
                if let count {
                    Text("\(count)")
                        .font(.system(size: 12.5, weight: .medium))
                        .opacity(0.55)
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(isActive ? activeFill : Color.clear)
            )
            .overlay(
                Capsule().stroke(
                    isActive ? Color.clear : Color(theme.ruleColor),
                    lineWidth: 0.5
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("diagnosticsChip_\(label)")
    }
}

/// The level + category chip rows.
struct DiagnosticsFilterBar: View {
    @Bindable var viewModel: DiagnosticsLogViewModel
    let theme: ReaderThemeV2

    private var errorTint: Color {
        DiagnosticsLevelTint.error.color(isDark: theme.isDark, neutral: Color(theme.subColor))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Level row.
            HStack(spacing: 7) {
                ForEach(DiagnosticsLevelFilter.allCases, id: \.self) { filter in
                    DiagnosticsChip(
                        theme: theme,
                        label: filter.label,
                        count: viewModel.count(for: filter),
                        isActive: viewModel.levelFilter == filter,
                        activeTint: (filter == .errors && viewModel.levelFilter == .errors) ? errorTint : nil,
                        action: { viewModel.levelFilter = filter }
                    )
                }
            }

            // Category row — scrollable; "All" + the present categories.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    DiagnosticsChip(
                        theme: theme,
                        label: "All",
                        count: nil,
                        isActive: viewModel.categoryFilter == nil,
                        action: { viewModel.categoryFilter = nil }
                    )
                    ForEach(viewModel.categories, id: \.self) { category in
                        DiagnosticsChip(
                            theme: theme,
                            label: category,
                            count: nil,
                            isActive: viewModel.categoryFilter == category,
                            action: { viewModel.categoryFilter = category }
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(theme.ruleColor))
                .frame(height: 0.5)
        }
    }
}
