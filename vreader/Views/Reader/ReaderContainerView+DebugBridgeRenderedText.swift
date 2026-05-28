// Purpose: DEBUG-only wiring that surfaces the active TXT reader's rendered
// (post-Simp→Trad) text into the DebugBridge probe (bug #1218). iOS 26
// SwiftUI flattens the chunked TXT reader's inner cells into the container,
// whose accessibility VALUE is the load-bearing `restoredOffset:…` state
// probe, so CU-free XCUITest cannot read the rendered text content — which
// blocks Feature #28 (verifying Simp→Trad conversion is applied to reader
// content). `TXTReaderContainerView` posts the converted display text on
// `.debugBridgeRenderedTextChanged`; this observer writes it onto the active
// `DebugReaderProbeAdapter.renderedText` so the `txt-content` command can
// read it back.
//
// Factored into a dedicated `ViewModifier` (same precedent as
// `ReaderDebugBridgeSearchObserver` / `ReaderDebugBridgePresentObserver`) so
// adding the observer doesn't push `ReaderContainerView.body` over SwiftUI's
// type-inference budget. Entire file compiled out of Release via `#if DEBUG`.
//
// @coordinates-with ReaderContainerView.swift (the `.modifier(...)` attaches
//   this and writes `debugProbe?.renderedText`), TXTReaderContainerView.swift
//   (posts `.debugBridgeRenderedTextChanged`), DebugBridgeNotifications.swift,
//   RealDebugBridgeContext+TXTContent.swift (the consumer of
//   `currentRenderedText`).

#if DEBUG

import SwiftUI

/// Dedicated `ViewModifier` for the bug #1218 rendered-text observer. Mirrors
/// the `ReaderDebugBridgeSearchObserver` pattern — extracting the `.onReceive`
/// keeps the SwiftUI body inside the type-inference budget.
struct ReaderDebugBridgeRenderedTextObserver: ViewModifier {
    /// Called with the posted `(fingerprintKey, text)`. The host filters on a
    /// matching active-book key before writing the probe.
    let onText: (_ fingerprintKey: String, _ text: String) -> Void

    func body(content: Content) -> some View {
        content.onReceive(
            NotificationCenter.default.publisher(for: .debugBridgeRenderedTextChanged)
        ) { notification in
            guard let userInfo = notification.userInfo,
                  let key = userInfo["fingerprintKey"] as? String,
                  let text = userInfo["text"] as? String else { return }
            onText(key, text)
        }
    }
}

#endif
