// Purpose: Feature #67 WI-4 — SwiftUI `Color` bridge for the
// Foundation-only `RGBComponents` design data. Kept off
// `SettingsRowPalette.swift` (and its test file) so that file stays
// SwiftUI-free and compiles in test contexts that don't link UIKit.
//
// @coordinates-with: SettingsRowPalette.swift, SettingsView.swift,
//   SettingsIconRow.swift, AISettingsSection.swift

import SwiftUI

extension RGBComponents {
    /// SwiftUI `Color` derived from the Foundation-only RGB triple, so
    /// row callers can feed an `iconBackground:` without bridging in
    /// each call site.
    var color: Color {
        Color(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0
        )
    }
}
