// Purpose: Three-stop oxblood/warm accent palette pinned to Feature
// #60's visual identity (WI-3 foundational types). One restrained hue
// per context — applied across chrome (buttons, selection emphasis,
// primary actions) so the visual identity stays coherent across the
// app instead of drifting per-screen.
//
// Stops per `docs/features.md` row #60:
//   `.light`    → `#8c2f2f` (oxblood, default chrome accent)
//   `.warmDark` → `#d6885a` (warm rose, dark-mode chrome accent)
//   `.photo`    → `#e8b465` (photo-frame highlight, used on imagery)
//
// Key decisions:
// - Modeled as an enum, not a static struct of colors, so adding a
//   fourth stop in a future iteration is a compiler-enforced churn.
// - Hex is exposed as a string and resolved to a `Color` / `UIColor`
//   at the call site, mirroring how `NamedHighlightColor.hex` works.
//   Keeping this layer SwiftUI-free lets the type compile in test
//   targets without importing SwiftUI just to assert hex values.
// - Sendable conformance is explicit (and tested compile-time) so
//   future additions can't quietly leak a reference type.
//
// @coordinates-with: SelectionPopover view (WI-4), NavBar/chrome
//   (WI-1), highlight glow renderer (WI-2)

import Foundation

enum AccentColor: Sendable, CaseIterable {
    case light
    case warmDark
    case photo

    var hex: String {
        switch self {
        case .light:    return "#8c2f2f"
        case .warmDark: return "#d6885a"
        case .photo:    return "#e8b465"
        }
    }
}
