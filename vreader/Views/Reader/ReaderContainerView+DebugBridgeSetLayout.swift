// Purpose: DEBUG-only wiring that switches the EPUB layout preference from the
// `.debugBridgeSetLayoutCommand` notification (feature #75 verification harness),
// attached at the DISPATCHER (`ReaderContainerView`) so it reaches EVERY EPUB
// engine. It sets the shared `settingsStore.epubLayout`, which both hosts read
// reactively:
//   • legacy `EPUBReaderContainerView` — its `.onChange(of: epubLayout)` injects
//     / removes the pagination CSS live;
//   • Readium `ReadiumEPUBHost` — its `.onChange(of: epubLayout)` re-renders the
//     navigator with a recomputed `EPUBPreferences(scroll:)`.
//
// Replaces the earlier host-scoped `EPUBReaderDebugBridgeSetLayoutObserver`
// (feature #75 WI-5a), which only reached the legacy host (the Readium host is a
// different view, so a host-scoped observer never fired under the Readium
// engine). XCUITest can't tap the segmented layout Picker on iOS 26 (gh #576),
// and the `--reader-default-layout=` launch arg only pre-seeds the default
// before a book opens; this switches an already-open reader on any engine.
//
// Extracted to a `ViewModifier` so the trailing-closure type-inference stays out
// of `ReaderContainerView`'s already-large body (mirrors the sibling
// `ReaderDebugBridge{Search,Present,RenderedText}Observer`). Compiled out of
// Release.
//
// @coordinates-with: ReaderContainerView.swift, DebugBridgeNotifications.swift,
//   RealDebugBridgeContext+SetLayout.swift, EPUBLayoutPreference.swift

#if DEBUG

import SwiftUI

/// Dispatcher-level set-layout observer (feature #75). Maps the posted `"mode"`
/// rawValue to `EPUBLayoutPreference` and hands it to `onLayout`, which the
/// dispatcher wires to `settingsStore.epubLayout`. An unknown mode string
/// (shouldn't happen — the parser validates it) is ignored.
struct ReaderDebugBridgeSetLayoutObserver: ViewModifier {
    let onLayout: (EPUBLayoutPreference) -> Void

    func body(content: Content) -> some View {
        content.onReceive(
            NotificationCenter.default.publisher(for: .debugBridgeSetLayoutCommand)
        ) { notification in
            guard let mode = notification.userInfo?["mode"] as? String,
                  let layout = EPUBLayoutPreference(rawValue: mode) else { return }
            onLayout(layout)
        }
    }
}

#endif
