// Purpose: Custom typeface-preview pill toggle for the Reader Settings
// panel (feature #66 WI-2). Replaces the native segmented `Picker` in
// the panel's font-family section with the design bundle's segmented
// pill (`dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`,
// "Font" section): a 12 pt-radius tinted track holding equal-width
// 10 pt-radius option buttons, each rendered in its own typeface, with
// the selected button raised on a white (light) / `#3a3530` (dark)
// fill plus a soft shadow.
//
// Key decisions:
// - **Behavior-preserving re-skin.** The pill presents *exactly* the
//   option set the current `fontFamilySection` segmented picker
//   presents — the three historical `ReaderFontFamily` cases
//   (`.system` / `.serif` / `.monospace`). It does NOT reduce to the
//   design's 2 options: a font-set reduction needs a legacy-value
//   mapping + a persisted-value policy and is out of scope (feature
//   #66 plan §2 / Gate-2 round-1 High finding 1).
// - **Accessibility**: a custom pill carries no innate picker
//   semantics, so the toggle is backed by
//   `.accessibilityRepresentation { Picker(...) }` — VoiceOver / Switch
//   Control see a genuine native picker. 44 pt minimum hit target
//   (feature #66 plan risk 1).
// - **Out-of-set tolerance**: the bound `TypographySettings.fontFamily`
//   is the 5-case enum, so a persisted `.sourceSerif4` / `.inter` can
//   arrive. `isSelected` simply returns false for every in-set pill in
//   that case — no crash, no forced reset.
// - Theme-tinted: the track / fill / ink read the active
//   `ReaderThemeV2` so contrast holds across all 5 sheet surfaces
//   (feature #66 plan risk 3).
//
// @coordinates-with: vreader/Views/Reader/ReaderSettingsPanel.swift,
//   vreader/Models/TypographySettings.swift, vreader/Models/ReaderThemeV2.swift

import SwiftUI

/// A custom typeface-preview pill toggle mirroring the design's
/// segmented "Font" pill.
struct TypefacePillToggle: View {

    /// One pill option — a `ReaderFontFamily`, its label, and the
    /// SwiftUI `Font` used to render the label in its own typeface.
    struct Option: Equatable {
        let family: ReaderFontFamily
        let label: String
        /// The preview font for the option's label, at the pill's
        /// label point size.
        let previewFont: Font
    }

    /// The pill's option set — the current `fontFamilySection`
    /// segmented picker's three options, in its declaration order
    /// (`vreader/Views/Reader/ReaderSettingsPanel.swift`). Faithful
    /// re-skin: NOT the design's 2 options, NOT all 5
    /// `ReaderFontFamily` cases (feature #66 plan §2).
    static let options: [Option] = [
        Option(family: .system, label: "System", previewFont: .system(size: pillLabelSize)),
        Option(family: .serif, label: "Serif",
               previewFont: .system(size: pillLabelSize, design: .serif)),
        Option(family: .monospace, label: "Monospace",
               previewFont: .system(size: pillLabelSize, design: .monospaced)),
    ]

    /// The pill label point size — the design's `fontSize: 15`.
    private static let pillLabelSize: CGFloat = 15

    /// The bound font-family selection.
    @Binding var selection: ReaderFontFamily
    /// VoiceOver label for the picker (e.g. "Font family").
    let accessibilityLabel: String
    /// The active reader theme — drives track / fill / ink contrast.
    var theme: ReaderThemeV2 = .default

    init(
        selection: Binding<ReaderFontFamily>,
        accessibilityLabel: String,
        theme: ReaderThemeV2 = .default
    ) {
        self._selection = selection
        self.accessibilityLabel = accessibilityLabel
        self.theme = theme
    }

    // MARK: - Selection logic (testable)

    /// Whether `family` is the bound selection. Returns false for an
    /// out-of-set bound value (a persisted `.sourceSerif4` / `.inter`).
    func isSelected(_ family: ReaderFontFamily) -> Bool {
        selection == family
    }

    /// Selects `family` — writes it through the binding.
    func select(_ family: ReaderFontFamily) {
        if selection != family { selection = family }
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.options, id: \.family) { option in
                pill(for: option)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(trackFill)
        )
        .accessibilityRepresentation {
            Picker(accessibilityLabel, selection: $selection) {
                ForEach(Self.options, id: \.family) { option in
                    Text(option.label).tag(option.family)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(accessibilityLabel)
        }
    }

    @ViewBuilder
    private func pill(for option: Option) -> some View {
        let selected = isSelected(option.family)
        Button {
            select(option.family)
        } label: {
            Text(option.label)
                .font(option.previewFont)
                .fontWeight(selected ? .semibold : .medium)
                .foregroundStyle(Color(theme.inkColor))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(selected ? selectedFill : Color.clear)
                        .shadow(
                            color: selected ? .black.opacity(0.08) : .clear,
                            radius: 1, x: 0, y: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }

    /// The track's subtle fill — the design's
    /// `t.isDark ? rgba(255,255,255,0.06) : rgba(0,0,0,0.05)`.
    private var trackFill: Color {
        theme.isDark
            ? Color.white.opacity(0.06)
            : Color.black.opacity(0.05)
    }

    /// The selected pill's raised fill — the design's
    /// `t.isDark ? '#3a3530' : '#fff'`.
    private var selectedFill: Color {
        theme.isDark
            ? Color(red: 0x3a / 255, green: 0x35 / 255, blue: 0x30 / 255)
            : Color.white
    }
}
