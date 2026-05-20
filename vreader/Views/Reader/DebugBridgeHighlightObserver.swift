// Purpose: DEBUG-only shared `ViewModifier` + helpers for the Bug #237
// highlight-driver observer used by TXTReaderContainerView and
// MDReaderContainerView. Centralized here so the per-format extensions
// don't duplicate the `.onReceive` boilerplate or the selected-text
// extraction logic.
//
// Entire file compiled out of Release builds via `#if DEBUG`.
//
// @coordinates-with TXTReaderContainerView+DebugBridgeHighlight.swift,
//   MDReaderContainerView+DebugBridgeHighlight.swift,
//   DebugBridgeNotifications.swift, LocatorFactory.swift

#if DEBUG

import SwiftUI
import Foundation

/// Shared `ViewModifier` for the highlight-driver observer. Mirrors the
/// pattern established by `ReaderDebugBridgeSearchObserver`.
///
/// `onCommand` receives the parsed parameters from the notification's
/// userInfo:
///   - `startUTF16` / `endUTF16` — the UTF-16 range (parser validated as
///     `start >= 0`, `end > start`).
///   - `color` — optional NamedHighlightColor rawValue; nil means
///     fall back to `DebugBridgeHighlightObserver.defaultColor`.
///
/// Format scoping: the modifier is only attached inside TXT and MD format
/// hosts (see `TXTReaderContainerView+DebugBridgeHighlight.swift` and
/// `MDReaderContainerView+DebugBridgeHighlight.swift`). EPUB / PDF / AZW3
/// don't register it — a stray URL fired while they're mounted is silently
/// a no-op (audit Round-1 High #2 fix).
struct DebugBridgeHighlightObserver: ViewModifier {
    let onCommand: (_ startUTF16: Int, _ endUTF16: Int, _ color: String?) -> Void

    func body(content: Content) -> some View {
        content.onReceive(
            NotificationCenter.default.publisher(for: .debugBridgeHighlightCommand)
        ) { notification in
            guard let start = notification.userInfo?["start"] as? Int,
                  let end = notification.userInfo?["end"] as? Int else { return }
            let color = notification.userInfo?["color"] as? String
            onCommand(start, end, color)
        }
    }
}

extension DebugBridgeHighlightObserver {

    /// Default highlight color when the URL omits `color=`. Matches the
    /// production gesture path's fallback in
    /// `ReaderNotificationModifier.resolveHighlightColor`.
    static let defaultColor = "yellow"

    /// Extracts the selected text the highlight should carry, matching what
    /// the production gesture path passes into
    /// `HighlightCoordinator.create(selectedText:)`.
    ///
    /// Sources to consult, in order:
    ///   - For TXT continuous mode and MD: `continuousSource` + the
    ///     locator's `charRangeStartUTF16`/`charRangeEndUTF16` (already
    ///     in document-global coordinates).
    ///   - For TXT chapter mode: `chapterSource` + the original
    ///     chapter-local offsets (the locator's range is now in
    ///     document-global coordinates; the chapter source can't be
    ///     indexed with those — hence the separate chapter-local
    ///     start/end inputs).
    ///   - If neither source is available (loading state, very early
    ///     observer fire), returns "" — matches the gesture-path
    ///     fallback for the same condition.
    static func extractSelectedText(
        locator: Locator,
        continuousSource: String?,
        chapterSource: String?,
        chapterLocalStart: Int?,
        chapterLocalEnd: Int?
    ) -> String {
        if let chapterSource, let start = chapterLocalStart, let end = chapterLocalEnd {
            return substringFromUTF16(chapterSource, from: start, to: end) ?? ""
        }
        if let continuousSource,
           let start = locator.charRangeStartUTF16,
           let end = locator.charRangeEndUTF16 {
            return substringFromUTF16(continuousSource, from: start, to: end) ?? ""
        }
        return ""
    }

    /// UTF-16 offset → Swift substring. Snaps to scalar boundaries so a
    /// surrogate pair half doesn't get split. Returns nil when the
    /// range is out of bounds.
    private static func substringFromUTF16(
        _ string: String,
        from start: Int,
        to end: Int
    ) -> String? {
        let utf16 = string.utf16
        guard start >= 0, end > start, end <= utf16.count else { return nil }
        let startIndex = String.Index(utf16Offset: start, in: string)
        let endIndex = String.Index(utf16Offset: end, in: string)
        guard startIndex < endIndex else { return nil }
        return String(string[startIndex ..< endIndex])
    }
}

#endif
