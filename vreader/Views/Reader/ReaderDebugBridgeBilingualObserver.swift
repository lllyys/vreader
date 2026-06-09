// Purpose: Feature #77 — DEBUG-only observer for `.debugBridgeBilingualCommand`.
// Each per-format bilingual host (`*+Bilingual` extensions) applies this modifier
// with closures that enable / disable interlinear bilingual mode (bypassing the
// setup sheet) or write a status readout — so the loading shimmer + translation
// flow is verifiable CU-free (the setup-sheet + provider gates are not
// idb-reliable). Mirrors `ReaderDebugBridgeSearchObserver` (Bug #238).
//
// Entire file compiled out of Release builds via `#if DEBUG`.
//
// @coordinates-with: RealDebugBridgeContext.swift, DebugBridgeNotifications.swift,
//   EPUBReaderContainerView+Bilingual.swift, ReadiumEPUBHost+Bilingual.swift,
//   FoliateBilingualContainerView, BilingualReadingViewModel.swift

#if DEBUG

import SwiftUI

struct ReaderDebugBridgeBilingualObserver: ViewModifier {
    /// Enable bilingual, bypassing the setup sheet. `lang` / `granularity` are
    /// the command's optional values (nil keeps the persisted/default).
    let onEnable: (_ lang: String?, _ granularity: String?) -> Void
    let onDisable: () -> Void
    /// Write a readout to `Caches/DebugBridge/<dest>`.
    let onStatus: (_ dest: String) -> Void

    func body(content: Content) -> some View {
        content.onReceive(
            NotificationCenter.default.publisher(for: .debugBridgeBilingualCommand)
        ) { notification in
            switch notification.userInfo?["action"] as? String {
            case "enable":
                onEnable(notification.userInfo?["lang"] as? String,
                         notification.userInfo?["granularity"] as? String)
            case "disable":
                onDisable()
            case "status":
                onStatus(notification.userInfo?["dest"] as? String ?? "bilingual-status.json")
            default:
                break
            }
        }
    }
}

#endif
