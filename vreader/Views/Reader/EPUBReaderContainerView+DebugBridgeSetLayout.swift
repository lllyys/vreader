// Purpose: DEBUG-only wiring that switches the EPUB reader's layout preference
// from the `.debugBridgeSetLayoutCommand` notification (feature #75 WI-5a
// verification harness). XCUITest cannot tap the segmented `Picker(.segmented)`
// EPUB-layout control on iOS 26 (gh #576), and the `--reader-default-layout=`
// launch arg only pre-seeds the default before a book opens — it does NOT
// switch an already-open reader. So the `set-layout` DebugBridge command posts
// the target mode and this observer sets `settingsStore.epubLayout` — the SAME
// binding the picker drives, whose existing
// `.onChange(of: settingsStore?.epubLayout)` relayouts the reader (no parallel
// layout path). Unblocks feature #75's RTL / vertical-rl paged-paging device
// verification.
//
// Extracted to a `ViewModifier` so the trailing-closure type-inference stays
// out of `EPUBReaderContainerView`'s already-large body (mirrors
// `ReaderDebugBridgePresentObserver`). Entire file compiled out of Release.
//
// @coordinates-with: EPUBReaderContainerView.swift, DebugBridgeNotifications.swift,
//   RealDebugBridgeContext+SetLayout.swift, EPUBLayoutPreference.swift

#if DEBUG

import SwiftUI

/// Dedicated `ViewModifier` for the feature #75 WI-5a set-layout observer.
/// Maps the posted `"mode"` rawValue to `EPUBLayoutPreference` and hands it to
/// `onLayout`, which the host wires to `settingsStore.epubLayout`. An unknown
/// mode string (shouldn't happen — the parser validates it) is ignored.
struct EPUBReaderDebugBridgeSetLayoutObserver: ViewModifier {
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
