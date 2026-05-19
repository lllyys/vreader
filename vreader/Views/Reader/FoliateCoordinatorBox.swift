// Purpose: Feature #57 — a per-reader handle that lets `ReaderContainerView`
// reach the live `FoliateSpikeView.Coordinator` for AZW3/MOBI TTS text
// extraction.
//
// `FoliateSpikeWebView` (the `UIViewRepresentable`) is private and creates
// its `Coordinator` in `makeCoordinator()`; SwiftUI gives the parent no
// direct handle to it. The TTS path needs to call the Coordinator's
// `extractPlainText()` once the book has rendered. This box is the seam:
// the host owns it as `@State`, passes it down to `FoliateSpikeView`, and
// `makeCoordinator()` assigns the live Coordinator into it.
//
// Why a box and not a global registry: convention 3 (reader bridges
// receive data via `@State` ownership in the host, not global stores).
// Unlike the DEBUG-only `DebugReaderRegistry`, this is production-safe,
// per-reader, and not a singleton — promoting `DebugReaderRegistry` to a
// Release symbol would also break `verify-release-no-debugbridge.sh`.
//
// The coordinator is held `weak`: the box must not extend the
// Coordinator's lifetime (box → coordinator → webView → ... → box would
// leak the whole reader).

import Foundation

/// Feature #57: per-reader reference box giving `ReaderContainerView` a
/// handle to the live `FoliateSpikeView.Coordinator` for TTS text
/// extraction. `@MainActor` — assigned in `makeCoordinator()` and read
/// from the `@MainActor` `startTTS()` path. The coordinator is held
/// `weak` so the box never leaks the reader.
@MainActor
final class FoliateCoordinatorBox {
    weak var coordinator: FoliateSpikeView.Coordinator?

    init() {}
}
