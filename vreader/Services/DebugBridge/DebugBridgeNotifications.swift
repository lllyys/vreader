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
    /// - `"detent"`: String? — optional sheet detent (Bug #256), one of
    ///   `DebugCommand.SheetDetent`'s rawValues (`medium` / `large`),
    ///   validated by the parser. `ai`-only (the parser rejects it on every
    ///   other sheet). Present only when the bridge command included the
    ///   `detent=` parameter; the observer sets the AI sheet's
    ///   `presentationDetents(_:selection:)` binding to it (the SAME binding a
    ///   user drag reaches) so the Translate-tab below-`.medium`-fold result
    ///   card (`translationResultCard`) becomes CU-free capturable. Absent →
    ///   the observer resets the binding to the default `.medium`.
    static let debugBridgePresentSheet = Notification.Name("vreader.debugBridge.presentSheet")

    /// Posted by RealDebugBridgeContext.aiAction to fire an AI action on the
    /// *presented* AI sheet from outside the chrome (Bug #255 verification
    /// harness). `present?sheet=ai` opens the panel; this fires the action
    /// the chrome buttons trigger (Summarize tap / chat send / translate),
    /// so the AI-response-card render states become CU-free verifiable via
    /// `snapshot` + `eval`. `AIReaderPanel`'s observer invokes the SAME
    /// view-model path the button does — `AISummaryTabView.runSummarize` /
    /// `AIChatView.sendMessage` / `TranslationPanel.translate` — there is no
    /// parallel AI call. The observer lives in `AIReaderPanel` (not
    /// `ReaderContainerView`) because the panel holds the locator / full
    /// text / chapter bounds / format the action needs. If no AI sheet is
    /// presented, observers don't fire — the URL is silently a no-op
    /// (mirrors `present` / `tts` / `search`).
    ///
    /// userInfo:
    /// - `"action"`: String — one of `DebugCommand.AIActionKind`'s rawValues
    ///   (`summarize` / `chat` / `translate`), validated by the parser.
    /// - `"scope"`: String? — summarize-only; a `SummaryScope` rawValue
    ///   (`section` / `chapter` / `bookSoFar`). The parser maps the
    ///   URL-friendly `book` to `bookSoFar` before posting. Present only when
    ///   the bridge command included `scope=`.
    /// - `"text"`: String? — the chat message (chat) or translate
    ///   target-language override (translate). Present only when the bridge
    ///   command included a non-empty `text=`.
    static let debugBridgeAIAction = Notification.Name("vreader.debugBridge.aiAction")

    /// Posted by RealDebugBridgeContext.seekFraction (Bug #267) to drive the
    /// active Foliate (AZW3/MOBI) reader to a fractional position so the
    /// harness can reach a *distinguishable non-start* position for Bug #265's
    /// save→reopen→restore round-trip. The live `FoliateBilingualContainerView`
    /// observer re-posts `.foliateRequestSeekFraction` (the SAME channel the
    /// bottom-chrome scrubber uses → `readerAPI.goToFraction`) with its own
    /// `fingerprintKey` injected, because the spike's seek observer filters by
    /// key. If no Foliate reader is loaded, no observer fires — the URL is
    /// silently a no-op (mirrors `present` / `tts` / `search`).
    ///
    /// userInfo:
    /// - `"fraction"`: Double — the target reading fraction, clamped 0...1 by
    ///   the parser.
    static let debugBridgeSeekFraction = Notification.Name("vreader.debugBridge.seekFraction")

    /// Posted by RealDebugBridgeContext.scrollSheet (Bug #271) to scroll the
    /// active presented sheet's scrollable content to a requested end so
    /// below-fold content becomes CU-free capturable. Today the only observer
    /// is `TranslationResultCard` (Feature #65 row-11 verification): its
    /// `ScrollViewReader` proxy scrolls to its top / bottom anchor. `detent=large`
    /// (Bug #256) reveals the larger AI sheet, but the tall ORIGINAL card alone
    /// exceeds even the `.large` height, so the accent translation card needs a
    /// scroll to come into view. Issued AFTER `ai?action=translate` completes
    /// (the result card only exists in the `.complete` state). If no scrollable
    /// sheet observes it, no observer fires — the URL is silently a no-op
    /// (mirrors `present` / `tts` / `search`).
    ///
    /// userInfo:
    /// - `"to"`: String — one of `DebugCommand.ScrollTarget`'s rawValues
    ///   (`top` / `bottom`), validated by the parser.
    static let debugBridgeScrollSheet = Notification.Name("vreader.debugBridge.scrollSheet")

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
