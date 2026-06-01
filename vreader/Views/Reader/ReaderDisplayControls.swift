// Purpose: Themed control primitives for the Reader Display panel that honor
// the per-theme `ReaderThemeV2.controlTrack` token (Bug #298 / GH #1329). iOS
// gives no public API for a `UISwitch` OFF-track color or a `UISegmentedControl`
// unselected-trough color, and SwiftUI's `.tint(accent)` only colors the
// ON / selected state — so the inactive surface fell through to `.systemFill`
// (~1.19:1 over the cream sheet, "no track"). These two primitives draw the
// inactive surface with `controlTrack` (light family = ink@30%, dark = white@16%
// per the landed design `control-track-token.md`), while keeping native
// accessibility intact:
//   • `ControlTrackToggleStyle` re-publishes itself as a real `Toggle` via
//     `.accessibilityRepresentation`, so the switch trait / value / UI-test
//     hooks survive the custom visual.
//   • `ThemedSegmentedPicker` wraps a real `UISegmentedControl`, so each segment
//     stays an accessible element addressable by its title (the existing
//     XCUITest segment taps keep working) — only the trough + pill colors change.
//
// @coordinates-with: ReaderSettingsPanel.swift, ReaderThemeV2.swift (controlTrack)

import SwiftUI
import UIKit

// MARK: - Toggle

/// A `ToggleStyle` whose OFF track uses the theme's `controlTrack` token (the
/// ON track keeps the accent). The knob is the standard white pill. Visual is
/// custom because UIKit exposes no OFF-track color; accessibility is delegated
/// back to a real `Toggle` so the switch semantics (and XCUITest toggling)
/// are unchanged.
struct ControlTrackToggleStyle: ToggleStyle {
    let theme: ReaderThemeV2

    /// Honors `.disabled(...)` at the call site — a non-interactive toggle must
    /// not flip on tap.
    @Environment(\.isEnabled) private var isEnabled

    // Standard iOS switch metrics; the switch column gets a 44pt-tall hit area.
    private let trackWidth: CGFloat = 51
    private let trackHeight: CGFloat = 31
    private let knobDiameter: CGFloat = 27
    private let minHitTarget: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 8)
            ZStack {
                Capsule()
                    .fill(Color(configuration.isOn ? theme.accentColor : theme.controlTrack))
                    .frame(width: trackWidth, height: trackHeight)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.18), radius: 1, x: 0, y: 1)
                    .frame(width: knobDiameter, height: knobDiameter)
                    .offset(x: configuration.isOn ? (trackWidth - knobDiameter) / 2 - 2
                                                   : -(trackWidth - knobDiameter) / 2 + 2)
            }
            .frame(minHeight: minHitTarget)
            .animation(.easeInOut(duration: 0.18), value: configuration.isOn)
        }
        // Native `Toggle` flips when the whole row is tapped, not just the
        // switch — match that, with a ≥44pt target, and respect `isEnabled`.
        .contentShape(Rectangle())
        .onTapGesture { if isEnabled { configuration.isOn.toggle() } }
        // Keep native switch accessibility (trait + value) and UI-test hooks.
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

// MARK: - Segmented control

/// A segmented control whose unselected trough uses `controlTrack` and whose
/// selected pill stays the design's elevated light pill (`#fffdf7` light /
/// `#3a3530` dark — per `control-track-token.md`, no new token). Wraps a real
/// `UISegmentedControl`, so native per-segment accessibility is preserved.
struct ThemedSegmentedPicker<Value: Hashable>: UIViewRepresentable {
    /// Segment titles in render order, paired with the value each selects.
    let options: [(title: String, value: Value)]
    @Binding var selection: Value
    let theme: ReaderThemeV2
    /// Optional container accessibility label (mirrors the SwiftUI
    /// `Picker`'s `.accessibilityLabel`).
    var accessibilityLabel: String?
    /// Optional accessibility identifier set DIRECTLY on the
    /// `UISegmentedControl` (so XCUITest queries by id still resolve — a SwiftUI
    /// `.accessibilityIdentifier` modifier on a representable can land on the
    /// host wrapper instead of the backing view).
    var accessibilityIdentifier: String?

    /// Honors `.disabled(...)` applied at the call site — the environment flag
    /// is read here and pushed to `UISegmentedControl.isEnabled`, which a
    /// representable does not pick up automatically.
    @Environment(\.isEnabled) private var isEnabled

    /// Selected-pill fill — the design's elevated light pill. Not a token: the
    /// design explicitly keeps the existing elevated pill (it reads by floating
    /// on the darker `controlTrack` trough, not by its own color shift).
    private var selectedPill: UIColor {
        theme.isDark
            ? UIColor(red: 0x3a / 255, green: 0x35 / 255, blue: 0x30 / 255, alpha: 1)
            : UIColor(red: 0xff / 255, green: 0xfd / 255, blue: 0xf7 / 255, alpha: 1)
    }

    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl(items: options.map(\.title))
        // `.noSegment` (-1) when `selection` isn't among `options` (or empty),
        // rather than falsely showing segment 0 selected.
        control.selectedSegmentIndex = options.firstIndex { $0.value == selection }
            ?? UISegmentedControl.noSegment
        control.addTarget(
            context.coordinator,
            action: #selector(Coordinator.valueChanged(_:)),
            for: .valueChanged
        )
        applyColors(to: control)
        control.accessibilityLabel = accessibilityLabel
        control.accessibilityIdentifier = accessibilityIdentifier
        control.isEnabled = isEnabled
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateUIView(_ control: UISegmentedControl, context: Context) {
        context.coordinator.parent = self
        reconcileSegments(control)
        // Sync selection — falls to `.noSegment` when `selection` is absent so
        // the UI never shows a stale/unbound selected segment.
        let target = options.firstIndex { $0.value == selection }
            ?? UISegmentedControl.noSegment
        if control.selectedSegmentIndex != target {
            control.selectedSegmentIndex = target
        }
        applyColors(to: control)
        control.accessibilityLabel = accessibilityLabel
        control.accessibilityIdentifier = accessibilityIdentifier
        control.isEnabled = isEnabled
    }

    /// Rebuilds the segment titles only when `options` actually changed (count
    /// or any title), so a dynamic `options` array can't leave stale segments.
    /// The three current call sites pass static arrays, so this is normally a
    /// no-op — it keeps the generic component correct under reconfiguration.
    private func reconcileSegments(_ control: UISegmentedControl) {
        let current = (0..<control.numberOfSegments).map { control.titleForSegment(at: $0) }
        let wanted = options.map { Optional($0.title) }
        guard current != wanted else { return }
        control.removeAllSegments()
        for (index, option) in options.enumerated() {
            control.insertSegment(withTitle: option.title, at: index, animated: false)
        }
    }

    private func applyColors(to control: UISegmentedControl) {
        control.backgroundColor = theme.controlTrack
        control.selectedSegmentTintColor = selectedPill
        control.setTitleTextAttributes([.foregroundColor: theme.inkColor], for: .normal)
        control.setTitleTextAttributes(
            [.foregroundColor: theme.inkColor], for: .selected
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: ThemedSegmentedPicker

        init(_ parent: ThemedSegmentedPicker) { self.parent = parent }

        @objc func valueChanged(_ sender: UISegmentedControl) {
            let index = sender.selectedSegmentIndex
            guard parent.options.indices.contains(index) else { return }
            parent.selection = parent.options[index].value
        }
    }
}
