// Purpose: Feature #67 WI-6 — the design's `PillSwitch`, a compact
// 34×20 capsule toggle used as the trailing control of the AI-section
// `SettingsToggleRow`s (design #1068, Variant A).
//
// Pinned to the committed design bundle at
// `dev-docs/designs/vreader-fidelity-v1/project/vreader-retranslate.jsx`
// (`PillSwitch`).
//
// Key decisions:
// - **A `ToggleStyle`, not a bare `Button`.** Rendering the pill as a
//   `ToggleStyle` applied to a real SwiftUI `Toggle` means VoiceOver
//   treats it as a switch (correct on/off semantics + value), and any
//   `.accessibilityIdentifier` on the `Toggle` attaches to the real
//   actionable control — not a decorative container. The whole capsule
//   stays the tap target via the `Toggle`'s label-less hit area.
// - **Theme-aware off color.** The design's off track is a translucent
//   black on light themes, translucent white on dark themes; the on
//   track is the fixed design green `#3a6a5a`.
// - `resolvedTrackColor(isOn:)` exposes the resolved track color so the
//   composition test pins the design colors without a render path (the
//   `SettingsIconRow.resolvedTitleColorForTesting` precedent).
//
// @coordinates-with: SettingsRowStyle.swift, SettingsToggleRow.swift,
//   AISettingsSection.swift, ReaderThemeV2.swift, PillSwitchTests.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-retranslate.jsx`

import SwiftUI

/// Layout metrics for `PillSwitch`, pinned to the design `PillSwitch`
/// (`vreader-retranslate.jsx`). Off the view type so the composition
/// test can assert them directly.
enum PillSwitchMetrics {
    /// Track width — design `width: 34`.
    static let trackWidth: CGFloat = 34
    /// Track height — design `height: 20`.
    static let trackHeight: CGFloat = 20
    /// Knob diameter — design `width/height: 16`.
    static let knobSize: CGFloat = 16
    /// Knob inset from the track edge — design `top: 2`, `left: 2`.
    static let knobInset: CGFloat = 2
}

/// Fixed colors for `PillSwitch`, pinned to the design.
enum PillSwitchColors {
    /// On-track fill — design `#3a6a5a`.
    static let onTrack = Color(
        .sRGB,
        red: 0x3a / 255.0, green: 0x6a / 255.0, blue: 0x5a / 255.0,
        opacity: 1
    )

    /// Off-track fill for the given theme — design
    /// `theme.isDark ? rgba(255,255,255,0.12) : rgba(0,0,0,0.12)`.
    static func offTrack(for theme: ReaderThemeV2) -> Color {
        let channel: Double = theme.isDark ? 1 : 0
        return Color(.sRGB, red: channel, green: channel, blue: channel, opacity: 0.12)
    }

    /// The resolved track color for an on/off state under a theme.
    static func track(isOn: Bool, theme: ReaderThemeV2) -> Color {
        isOn ? onTrack : offTrack(for: theme)
    }
}

/// The design's compact capsule toggle, expressed as a `ToggleStyle` so
/// it carries native switch accessibility semantics.
struct PillSwitchStyle: ToggleStyle {
    let theme: ReaderThemeV2

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(PillSwitchColors.track(isOn: configuration.isOn, theme: theme))
                    .frame(width: PillSwitchMetrics.trackWidth,
                           height: PillSwitchMetrics.trackHeight)
                Circle()
                    .fill(.white)
                    .frame(width: PillSwitchMetrics.knobSize,
                           height: PillSwitchMetrics.knobSize)
                    .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                    .padding(.horizontal, PillSwitchMetrics.knobInset)
            }
            .animation(.easeInOut(duration: 0.15), value: configuration.isOn)
        }
        .buttonStyle(.plain)
    }
}

/// A convenience view that renders a label-less `Toggle` styled with
/// `PillSwitchStyle` — the design's compact capsule switch. Use this as
/// the trailing control of a `SettingsToggleRow`.
///
/// Backed by a real `Toggle`, so VoiceOver announces it as a switch with
/// an on/off value (not a "selected button"), and a caller-supplied
/// `.accessibilityIdentifier` lands on the actionable control.
struct PillSwitch: View {

    @Binding private var isOn: Bool
    private let theme: ReaderThemeV2

    init(isOn: Binding<Bool>, theme: ReaderThemeV2) {
        self._isOn = isOn
        self.theme = theme
    }

    /// The track color the switch will render — exposed for the
    /// composition test (the on/off + theme-aware off-color contract).
    var resolvedTrackColorForTesting: Color {
        PillSwitchColors.track(isOn: isOn, theme: theme)
    }

    /// Flips the bound value — exposed so the binding test exercises the
    /// same mutation the control's action performs.
    func toggleForTesting() {
        isOn.toggle()
    }

    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(PillSwitchStyle(theme: theme))
    }
}
