// Purpose: Feature #58 WI-6a/WI-6b — the design's scrollable time-window
// pill bar (`StatsTimeWindowBar` in `vreader-profile-stats.jsx` /
// `ExtendedTimeWindowBar` in `stats-followups-artboards.jsx`).
//
// Pinned to `dev-docs/designs/vreader-fidelity-v1/project/
// vreader-profile-stats.jsx` (`StatsTimeWindowBar`) and the WI-6b extension
// in `stats-followups-artboards.jsx` (`ExtendedTimeWindowBar`).
//
// Key decisions:
// - **One pill per `ReadingStatsWindow.allCases` case** + a trailing
//   `Custom` pill (WI-6b). The Custom pill carries a settings glyph and,
//   when active, an inline summary of the applied range (e.g.
//   `Custom · May 1 – May 15`) — exactly the design's `ExtendedTimeWindowBar`
//   shape.
// - **Active pill background uses `theme.inkColor`**; inactive pills
//   are transparent — exactly the JSX formula (`background: active ?
//   t.ink : 'transparent'`).
// - **Each tap fires `onChange` even when the tapped pill is already
//   active** — deduplication is the caller's responsibility. The
//   design's web component also fires `onChange?(w.k)` unconditionally.
// - **Tapping Custom fires `onCustomTap` whether or not Custom is
//   currently active** — so the picker can be reopened to revise an
//   applied range (the design's "Custom · May 1 – May 15" pill is a
//   re-entry point to the picker, not just a state indicator).
// - **Composition seams** (`windowsForTesting`, `isPillActiveForTesting`,
//   `selectWindowForTesting`, `selectCustomForTesting`) expose the
//   render contract for unit tests without driving a SwiftUI hit-test pass.
//
// @coordinates-with: ReadingDashboardView.swift, ReadingStatsModels.swift,
//   ReadingStatsCustomRange.swift, StatsCustomRangePicker.swift,
//   ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-profile-stats.jsx`,
//   `dev-docs/designs/vreader-fidelity-v1/project/stats-followups-artboards.jsx`

import SwiftUI

/// The design's scrollable time-window selector. One pill per
/// `ReadingStatsWindow` enum case + a trailing Custom pill; tapping a pill
/// calls the matching handler.
struct StatsTimeWindowBar: View {

    private let theme: ReaderThemeV2
    private let value: ReadingStatsWindow
    /// The applied custom range, or nil when no Custom range is active.
    private let customRange: ReadingStatsCustomRange?
    private let onChange: (ReadingStatsWindow) -> Void
    private let onCustomTap: () -> Void

    init(
        theme: ReaderThemeV2,
        value: ReadingStatsWindow,
        customRange: ReadingStatsCustomRange? = nil,
        onChange: @escaping (ReadingStatsWindow) -> Void,
        onCustomTap: @escaping () -> Void = {}
    ) {
        self.theme = theme
        self.value = value
        self.customRange = customRange
        self.onChange = onChange
        self.onCustomTap = onCustomTap
    }

    // MARK: - Testing seams

    /// The enum windows the bar renders, in order. (The Custom pill is
    /// always present in addition to these — see `customRangeForTesting`.)
    var windowsForTesting: [ReadingStatsWindow] { ReadingStatsWindow.allCases }

    /// Whether the given enum window is rendered as the active pill. Always
    /// false when a custom range is active — only the Custom pill is active
    /// in that mode.
    func isPillActiveForTesting(_ window: ReadingStatsWindow) -> Bool {
        guard customRange == nil else { return false }
        return window == value
    }

    /// Whether the Custom pill is rendered active (i.e. a custom range
    /// is currently applied).
    var isCustomPillActiveForTesting: Bool { customRange != nil }

    /// The label rendered on the Custom pill. Plain "Custom" when no range
    /// is applied; "Custom · <summary>" when one is.
    func customPillLabelForTesting(calendar: Calendar = .current) -> String {
        guard let range = customRange else { return "Custom" }
        let label = range.summaryLabel(calendar: calendar)
        return label.isEmpty ? "Custom" : "Custom · \(label)"
    }

    /// Simulate an enum-pill tap.
    func selectWindowForTesting(_ window: ReadingStatsWindow) {
        onChange(window)
    }

    /// Simulate a Custom-pill tap.
    func selectCustomForTesting() {
        onCustomTap()
    }

    // MARK: - Body

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(ReadingStatsWindow.allCases) { window in
                    pill(for: window)
                }
                customPill
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 4)
        }
        .background(
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(Color(theme.ruleColor))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        )
        .accessibilityIdentifier("statsTimeWindowBar")
    }

    @ViewBuilder
    private func pill(for window: ReadingStatsWindow) -> some View {
        let active = customRange == nil && window == value
        Button {
            onChange(window)
        } label: {
            Text(window.label)
                .font(.system(size: 12.5, weight: active ? .semibold : .medium))
                .foregroundStyle(active
                    ? Color(theme.paperColor)
                    : Color(theme.inkColor))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(active ? Color(theme.inkColor) : .clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("statsTimeWindowPill-\(window.rawValue)")
        .accessibilityLabel(window.label)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    /// The trailing Custom pill — settings glyph + label, with an inline
    /// range summary when a range is applied. Pinned to
    /// `ExtendedTimeWindowBar` in `stats-followups-artboards.jsx`.
    @ViewBuilder
    private var customPill: some View {
        let active = customRange != nil
        let summary = customRange?.summaryLabel(calendar: .current) ?? ""
        Button {
            onCustomTap()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(active
                        ? Color(theme.paperColor)
                        : Color(theme.subColor))
                Text("Custom")
                    .font(.system(size: 12.5, weight: .semibold))
                if active && !summary.isEmpty {
                    Text("·")
                        .opacity(0.55)
                        .font(.system(size: 12.5, weight: .medium))
                    Text(summary)
                        .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                }
            }
            .foregroundStyle(active
                ? Color(theme.paperColor)
                : Color(theme.inkColor))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(active ? Color(theme.inkColor) : .clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("statsTimeWindowPill-custom")
        .accessibilityLabel(active && !summary.isEmpty ? "Custom range, \(summary)" : "Custom range")
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
