// Purpose: DEBUG-only notification names used by the DebugBridge to drive
// reader navigation from the vreader-debug:// URL scheme (feature #44).
// Defined here (not in ReaderNotifications.swift) so the symbols are gated
// by #if DEBUG and never appear in Release builds.

#if DEBUG

import Foundation

extension Notification.Name {
    /// Posted by RealDebugBridgeContext.open. LibraryView observes this and
    /// pushes a `LibraryBookItem` onto its NavigationStack path.
    ///
    /// userInfo:
    /// - `"fingerprintKey"`: String — the book's canonical key
    /// - `"position"`: String? — optional position hint (CFI / page / UTF-16 offset).
    ///   v0 ignores this; v1 will resolve to a Locator before opening.
    static let debugBridgeOpenBook = Notification.Name("vreader.debugBridge.openBook")

    /// Posted by RealDebugBridgeContext after any command that mutates the
    /// SwiftData library (reset, seed). LibraryView observes this and
    /// refreshes its in-memory books array so the new state is reflected
    /// in the UI without requiring an app relaunch.
    /// No userInfo.
    static let debugBridgeLibraryChanged = Notification.Name("vreader.debugBridge.libraryChanged")

    /// Posted by RealDebugBridgeContext.theme after writing UserDefaults
    /// so an active reader's `@State`-owned `ReaderSettingsStore` can
    /// re-theme without an app relaunch (bug #144). The bridge command
    /// updates the persistent default; this notification gives live
    /// readers a chance to pick up the change too.
    ///
    /// userInfo:
    /// - `"mode"`: String — always a canonical `ReaderThemeV2` rawValue
    ///   (`paper`/`sepia`/`dark`/`oled`/`photo`). `RealDebugBridgeContext.theme`
    ///   maps the URL's `ThemeMode` to `ReaderThemeV2` before posting, so
    ///   the legacy `mode=light` alias arrives here already resolved to
    ///   `"paper"` (bug #206; Feature #60 WI-11 migrated to `ReaderThemeV2`).
    /// - `"fontSize"`: Int? — optional new font size, present only when
    ///   the bridge command included a fontSize parameter.
    static let debugBridgeThemeChanged = Notification.Name("vreader.debugBridge.themeChanged")

    /// Posted by RealDebugBridgeContext.tts to drive the active reader's
    /// `TTSService` from outside (Feature #45 WI-4c-b). XCUITest's gesture
    /// path cannot reliably activate `AVSpeechSynthesizer`'s audio session,
    /// so verification tests fire `vreader-debug://tts?action=start` after
    /// opening a book to bypass the play-button tap.
    ///
    /// If no reader is loaded, observers don't fire — the URL is a no-op.
    /// The bridge layer doesn't enforce active-reader presence; that's a
    /// presentation concern owned by `ReaderContainerView`.
    ///
    /// userInfo:
    /// - `"action"`: String — "start" or "stop" (validated by parser).
    static let debugBridgeTTSCommand = Notification.Name("vreader.debugBridge.ttsCommand")
}

#endif
