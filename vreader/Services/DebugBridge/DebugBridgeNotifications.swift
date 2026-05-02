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
}

#endif
