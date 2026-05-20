// Purpose: Feature #58 WI-6a — the design's scrollable time-window
// pill bar (`StatsTimeWindowBar` in `vreader-profile-stats.jsx`).
//
// Pinned to `dev-docs/designs/vreader-fidelity-v1/project/
// vreader-profile-stats.jsx` (`StatsTimeWindowBar`).
//
// Key decisions:
// - **One pill per `ReadingStatsWindow.allCases` case.** The shipped
//   enum has the 7 windows the WI-1 plan settled on (today / 7d / 30d /
//   90d / 180d / 365d / All). The design also defines a `Custom` pill;
//   per the D2-B resolution (GH #665 2026-05-20) the Custom range
//   picker is DEFERRED to WI-6b (blocked on GH #1058 needs-design), so
//   this bar renders only the enum-backed pills.
// - **Active pill background uses `theme.inkColor`**; inactive pills
//   are transparent — exactly the JSX formula (`background: active ?
//   t.ink : 'transparent'`).
// - **Each tap fires `onChange` even when the tapped pill is already
//   active** — deduplication is the caller's responsibility. The
//   design's web component also fires `onChange?(w.k)` unconditionally.
// - **Composition seams** (`windowsForTesting`, `isPillActiveForTesting`,
//   `selectWindowForTesting`) expose the render contract for unit
//   tests without driving a SwiftUI hit-test pass.
//
// @coordinates-with: ReadingDashboardView.swift, ReadingStatsModels.swift,
//   ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-profile-stats.jsx`

import SwiftUI

/// The design's scrollable time-window selector. One pill per
/// `ReadingStatsWindow` enum case; tapping a pill calls `onChange`.
struct StatsTimeWindowBar: View {

    private let theme: ReaderThemeV2
    private let value: ReadingStatsWindow
    private let onChange: (ReadingStatsWindow) -> Void

    init(
        theme: ReaderThemeV2,
        value: ReadingStatsWindow,
        onChange: @escaping (ReadingStatsWindow) -> Void
    ) {
        self.theme = theme
        self.value = value
        self.onChange = onChange
    }

    // MARK: - Testing seams

    /// The windows the bar renders, in order. Pinned to the WI-1 enum
    /// (`Custom` deferred to WI-6b — GH #1058).
    var windowsForTesting: [ReadingStatsWindow] { ReadingStatsWindow.allCases }

    /// Whether the given window is currently rendered as the active pill.
    func isPillActiveForTesting(_ window: ReadingStatsWindow) -> Bool {
        window == value
    }

    /// Simulate a pill tap — invokes `onChange` with the supplied window.
    func selectWindowForTesting(_ window: ReadingStatsWindow) {
        onChange(window)
    }

    // MARK: - Body

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(ReadingStatsWindow.allCases) { window in
                    pill(for: window)
                }
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
        let active = window == value
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
}
