// Purpose: Composition tests for PillSwitch — the design's 34×20 capsule
// toggle (`vreader-retranslate.jsx` `PillSwitch`, re-used by the AI-section
// toggle rows in feature #67 WI-6 per design #1068).
//
// COMPOSITION assertions, not pixel snapshots: the switch builds on/off for
// every theme, the resolved track color matches the design (#3a6a5a on; the
// theme-aware translucent off-color), and the bound value flips on tap.

import Testing
import SwiftUI
import Foundation
@testable import vreader

@Suite("PillSwitch composition — feature #67 WI-6")
@MainActor
struct PillSwitchTests {

    // MARK: - Builds

    @Test func buildsOn() {
        let view = PillSwitch(isOn: .constant(true), theme: .paper)
        _ = view.body
    }

    @Test func buildsOff() {
        let view = PillSwitch(isOn: .constant(false), theme: .paper)
        _ = view.body
    }

    @Test func buildsForEveryTheme() {
        for theme in ReaderThemeV2.allCases {
            _ = PillSwitch(isOn: .constant(true), theme: theme).body
            _ = PillSwitch(isOn: .constant(false), theme: theme).body
        }
    }

    // MARK: - Track color (design `vreader-retranslate.jsx` PillSwitch)

    @Test func onTrackColorIsTheDesignGreen() {
        // Design: on → `#3a6a5a`.
        let view = PillSwitch(isOn: .constant(true), theme: .paper)
        assertColor(view.resolvedTrackColorForTesting, rgb: (0x3a, 0x6a, 0x5a))
    }

    @Test func offTrackColorIsTranslucentBlackOnLightThemes() {
        // Design: off, light theme → `rgba(0,0,0,0.12)`.
        for theme in [ReaderThemeV2.paper, .sepia] {
            let view = PillSwitch(isOn: .constant(false), theme: theme)
            assertColor(view.resolvedTrackColorForTesting,
                        rgb: (0, 0, 0), alpha: 0.12)
        }
    }

    @Test func offTrackColorIsTranslucentWhiteOnDarkThemes() {
        // Design: off, dark theme → `rgba(255,255,255,0.12)`.
        for theme in [ReaderThemeV2.dark, .oled, .photo] {
            let view = PillSwitch(isOn: .constant(false), theme: theme)
            assertColor(view.resolvedTrackColorForTesting,
                        rgb: (255, 255, 255), alpha: 0.12)
        }
    }

    // MARK: - Metrics (design `PillSwitch`)

    @Test func metricsMatchTheDesign() {
        // Design: 34×20 track, radius 10, 16pt knob, knob inset 2,
        // on-offset 16.
        #expect(PillSwitchMetrics.trackWidth == 34)
        #expect(PillSwitchMetrics.trackHeight == 20)
        #expect(PillSwitchMetrics.knobSize == 16)
        #expect(PillSwitchMetrics.knobInset == 2)
    }

    // MARK: - Binding

    @Test func tapTogglesTheBoundValue() {
        // The switch is a control; toggling its action flips the binding.
        var stored = false
        let binding = Binding<Bool>(get: { stored }, set: { stored = $0 })
        let view = PillSwitch(isOn: binding, theme: .paper)
        view.toggleForTesting()
        #expect(stored == true)
        view.toggleForTesting()
        #expect(stored == false)
    }

    // MARK: - Helper

    private func assertColor(
        _ color: Color,
        rgb expected: (Int, Int, Int),
        alpha expectedAlpha: CGFloat? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(Int((r * 255).rounded()) == expected.0, "red", sourceLocation: sourceLocation)
        #expect(Int((g * 255).rounded()) == expected.1, "green", sourceLocation: sourceLocation)
        #expect(Int((b * 255).rounded()) == expected.2, "blue", sourceLocation: sourceLocation)
        if let expectedAlpha {
            #expect(abs(a - expectedAlpha) < 0.01, "alpha", sourceLocation: sourceLocation)
        }
    }
}
