// Purpose: Tests for `AccentColor` — the three-stop oxblood token for
// Feature #60's visual identity (WI-3). One restrained hue applied
// across chrome (buttons, selection emphasis, primary actions).

import Testing
import Foundation
@testable import vreader

@Suite("AccentColor — Feature #60 WI-3")
struct AccentColorTests {

    /// Three named stops pinned to the design bundle's exact values per
    /// the row description in `docs/features.md` row #60:
    /// `#8c2f2f` (light) / `#d6885a` (warm-dark) / `#e8b465` (photo).
    /// Each stop is the accent color for the named context. If these
    /// drift, the visual identity drifts.
    @Test
    func threeStops_matchDesignHexValues() {
        #expect(AccentColor.light.hex == "#8c2f2f")
        #expect(AccentColor.warmDark.hex == "#d6885a")
        #expect(AccentColor.photo.hex == "#e8b465")
    }

    /// Sendable conformance is compile-time enforced via this generic
    /// helper. If `AccentColor` is later changed to a class or absorbs a
    /// non-Sendable property, this will fail to compile.
    @Test
    func sendable_conformance_isAvailable() {
        func requireSendable<T: Sendable>(_ value: T) -> T { value }
        let accent = AccentColor.light
        let echoed = requireSendable(accent)
        #expect(echoed.hex == accent.hex)
    }

    /// Pins the "exactly three stops" contract. A future fourth case
    /// would silently miss the hex-value test (which only asserts the
    /// three named stops). This test forces the author of a fourth
    /// stop to extend both `allCases` and the exhaustive-switch
    /// helper below, surfacing the change at review time.
    @Test
    func allCases_containsExactlyThreeStops() {
        let cases = AccentColor.allCases
        #expect(cases.count == 3)
        #expect(Set(cases) == [.light, .warmDark, .photo])
    }

    /// Compile-time exhaustiveness check — the switch will fail to
    /// compile if a future case is added without updating this
    /// helper. The body asserts only that each case yields a
    /// non-empty hex string; the real value is the compiler check.
    @Test
    func exhaustiveSwitch_handlesEveryStop() {
        func label(for accent: AccentColor) -> String {
            switch accent {
            case .light:    return accent.hex
            case .warmDark: return accent.hex
            case .photo:    return accent.hex
            }
        }
        for accent in AccentColor.allCases {
            #expect(!label(for: accent).isEmpty)
        }
    }
}
