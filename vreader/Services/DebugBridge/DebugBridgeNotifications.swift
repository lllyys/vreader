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

    /// Posted by RealDebugBridgeContext.search to drive the in-reader search
    /// sheet (Bug #238 verification harness). The active reader's observer
    /// opens the search sheet, sets `SearchViewModel.query`, and — when the
    /// optional `"index"` key is present — taps result N once results arrive
    /// (re-firing `.readerNavigateToLocator` then dismissing the sheet).
    ///
    /// The harness uses this URL family to reach search-result-tap repros
    /// (e.g. Bug #182 cross-chapter EPUB search highlight) without
    /// computer-use. If no reader is loaded, observers don't fire — the URL
    /// is silently a no-op (the same `tts` / `theme` posture).
    ///
    /// userInfo:
    /// - `"query"`: String — the search query (validated non-empty by parser;
    ///   percent-encoded values reach observers already decoded).
    /// - `"index"`: Int? — optional tap target (0-indexed, ≥0), present only
    ///   when the bridge command included the `index=` parameter. When
    ///   absent, observers run the query only.
    static let debugBridgeSearchCommand = Notification.Name("vreader.debugBridge.searchCommand")

    /// Posted by RealDebugBridgeContext.highlight to create a highlight in
    /// the active reader, bypassing the long-press + SelectionPopoverView
    /// gesture path (Bug #237 verification harness — XCUITest cannot
    /// synthesize the long-press → text-selection sequence on iOS 26).
    ///
    /// The active reader's observer builds a `Locator` from the offsets,
    /// calls `PersistenceActor.addHighlight`, then posts
    /// `.readerHighlightsDidImport` so the per-format renderer (TXT / MD /
    /// EPUB / PDF) re-paints. If no reader is loaded, observers don't
    /// fire — the URL is silently a no-op (mirrors `tts` / `search`).
    ///
    /// Range semantics are inclusive-exclusive — `[start, end)` — matching
    /// how `Locator.charRangeStartUTF16` / `charRangeEndUTF16` are used by
    /// the gesture path. Parser enforces `start >= 0`, `end > start`.
    ///
    /// userInfo:
    /// - `"start"`: Int — UTF-16 range start (≥ 0).
    /// - `"end"`: Int — UTF-16 range end (> start).
    /// - `"color"`: String? — optional NamedHighlightColor rawValue
    ///   (`yellow` / `pink` / `green` / `blue`). Present only when the
    ///   bridge command included the `color=` parameter; observers fall
    ///   back to `"yellow"` when absent.
    static let debugBridgeHighlightCommand = Notification.Name("vreader.debugBridge.highlightCommand")

    /// Posted by RealDebugBridgeContext.present to present a reader sheet
    /// from outside the chrome (Bug #253 verification harness). The active
    /// reader's observer (`ReaderContainerView`, Bug #253 wiring) maps the
    /// `(sheet, tab)` to the SAME `@State` / `annotationsRoute` the chrome
    /// buttons set — `TOCSheet` (Contents/Bookmarks), `HighlightsSheet`
    /// (All/Highlights/Notes/Bookmarks), `AIReaderPanel` (Summarize/
    /// Translate/Chat), or the reader settings panel — so the harness drives
    /// the real presentation path and the presented sheet's rendered content
    /// becomes CU-free verifiable via `snapshot` + `eval`. The AI sheet is
    /// gated on `resolvedAICoordinator.isAIAvailable` (matches the chrome's
    /// AI gate); when AI isn't configured the URL is a no-op for the AI sheet.
    /// If no reader is loaded, observers don't fire — the URL is silently a
    /// no-op (the same `tts` / `search` / `highlight` posture).
    ///
    /// userInfo:
    /// - `"sheet"`: String — one of `DebugCommand.SheetKind`'s rawValues
    ///   (`toc` / `highlights` / `ai` / `settings` / `bookmarks`), validated
    ///   by the parser.
    /// - `"tab"`: String? — optional sub-tab, validated by the parser against
    ///   the sheet's vocabulary. Present only when the bridge command included
    ///   the `tab=` parameter; observers fall back to each sheet's default tab
    ///   when absent.
    static let debugBridgePresentSheet = Notification.Name("vreader.debugBridge.presentSheet")

    // Note: the `provider` command (Bug #243) does NOT have a bridge-specific
    // notification. The handler mutates `ProviderProfileStore` directly and
    // the store posts `.providerProfilesDidChange` itself; any in-app picker
    // / settings VM subscribed to that notification picks up the change
    // without a separate bridge layer. Adding a duplicate
    // `.debugBridgeProviderCommand` would couple Settings-side observers to
    // a DEBUG-only symbol — strictly worse than reusing the existing
    // production-grade notification.
}

#endif
