// Purpose: Feature #42 WI-7 photo/custom-background compositing for the Readium
// EPUB host. Extracted from `ReadiumEPUBHost.swift` for the 300-line budget.
// Layers the legacy `ThemeBackgroundView` (decorative image + theme color)
// behind the navigator in a `ZStack` — mirroring the legacy `ReaderContainerView`
// (`ZStack { if useCustomBackground { ThemeBackgroundView }; reader }`) — and
// drives the transparent-navigator decision so the composited layer shows
// through the rendered text. Normal themes (no custom background, or
// enabled-but-no-image) keep the unchanged opaque theme-color path.
//
// @coordinates-with ReadiumEPUBHost.swift, ThemeBackgroundView.swift,
//   ThemeBackgroundStore.swift, ReadiumEPUBReaderViewModel+Mapping.swift

#if canImport(UIKit)
import SwiftUI

extension ReadiumEPUBHost {

    /// True when the decorative background should show THROUGH the navigator —
    /// custom background enabled AND an image stored for the theme. Pure decision
    /// shared with the preferences mapping (`shouldRenderTransparentBackground`).
    var shouldRenderTransparentBackground: Bool {
        ReadiumEPUBReaderViewModel.shouldRenderTransparentBackground(
            useCustomBackground: settingsStore.useCustomBackground,
            hasBackgroundImage: hasBackgroundImage
        )
    }

    /// Wraps the reader content in a `ZStack` with `ThemeBackgroundView` behind
    /// it (when a custom background is enabled), and tracks whether an image is
    /// stored for the theme. The reload triggers mirror `ThemeBackgroundView`'s
    /// own: appear + theme / custom-background toggle / revision change.
    @ViewBuilder
    func backgroundComposited(_ content: some View) -> some View {
        ZStack {
            if settingsStore.useCustomBackground {
                ThemeBackgroundView(settingsStore: settingsStore)
            }
            content
        }
        .onAppear { reloadHasBackgroundImage() }
        .onChange(of: settingsStore.theme) { _, _ in reloadHasBackgroundImage() }
        .onChange(of: settingsStore.useCustomBackground) { _, _ in reloadHasBackgroundImage() }
        .onChange(of: settingsStore.customBackgroundRevision) { _, _ in reloadHasBackgroundImage() }
    }

    private func reloadHasBackgroundImage() {
        hasBackgroundImage =
            ThemeBackgroundStore.loadBackground(for: settingsStore.theme.rawValue) != nil
    }
}

#endif
