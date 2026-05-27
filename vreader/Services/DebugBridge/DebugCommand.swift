// Purpose: Parser and value type for the vreader-debug:// URL grammar
// (feature #44 DebugBridge). Pure value-type parsing, no OS dependencies.
// DEBUG-only — entire file compiled out of Release builds.

#if DEBUG

import Foundation

/// A command parsed from a `vreader-debug://` URL.
///
/// Grammar: `vreader-debug://<command>[?<params>]`
///
/// - `reset` — wipe library and reset settings.
/// - `seed?fixture=<name>` — seed a bundled fixture book.
/// - `open?bookId=<uuid>[&position=<value>]` — open a book at an optional
///   position. Position format depends on the book format; a future feature
///   #49 WI ships a `DebugPositionResolver` for native-mode TXT/EPUB/PDF.
///   The legacy `?cfi=<value>` parameter is rejected — feature #49 WI-0
///   reconciled the grammar to use `position` consistently across all formats.
/// - `theme?mode=<dark|light|paper|sepia|oled|photo>[&fontSize=<int>]` — set the
///   reader appearance. `light` is a backward-compatible alias for `paper`.
/// - `settle?token=<id>` — write `Caches/ready-<id>.json` after layout settles.
/// - `snapshot?dest=<file>` — write semantic state JSON to the app container.
/// - `eval?bridge=<name>&js=<base64>` — evaluate JS in the named webview bridge.
/// - `tts?action=<start|stop>` — drive TTS from outside the reader (Feature #45
///   WI-4c-b). XCUITest's gesture path cannot reliably activate
///   `AVSpeechSynthesizer`'s audio session, so verification tests fire this URL
///   after opening a book to bypass the play-button tap.
/// - `search?query=<str>[&index=<int>]` — drive the in-reader search sheet
///   (Bug #238 verification harness). `query` opens the search sheet and runs
///   the query; the optional `index` (0-indexed, ≥0) taps result N once
///   results arrive. The harness uses this to drive search-result-tap repros
///   (e.g. Bug #182 cross-chapter EPUB search highlight verification) without
///   computer-use. No-op when no reader is presented.
/// - `highlight?start=<int>&end=<int>[&color=<name>]` — create a highlight
///   over a UTF-16 range in the active TXT/MD reader (Bug #237 verification
///   harness). The harness uses this to bypass the long-press +
///   `SelectionPopoverView` gesture, which XCUITest cannot synthesize
///   reliably on iOS 26. `start` < `end` (inclusive-exclusive), both
///   non-negative. `color` is optional; one of `NamedHighlightColor`'s four
///   rawValues (`yellow` / `pink` / `green` / `blue`). No-op when no reader
///   is presented.
/// - `provider?action=add&name=<n>&kind=<k>&endpoint=<url>&apiKey=<k>[&model=<m>][&active=<bool>]`
///   — add an AI provider profile to `ProviderProfileStore` and save its
///   API key to Keychain (Bug #243 verification harness). The harness uses
///   this to configure an AI provider without driving Settings → AI through
///   CU, unlocking autonomous AI-feature verification (Feature #56 / #65 /
///   #69, Bug #93) regardless of CU availability. `kind` is one of
///   `openAICompatible` / `anthropicNative`; `endpoint` is the base URL;
///   `model` is optional (defaults to `kind.defaultModel`); `active=true`
///   sets this profile as active. The handler additionally auto-promotes
///   the first added profile to active so a single `add` URL leaves the
///   harness in a usable state.
/// - `provider?action=remove&name=<n>` — remove the profile with display
///   name `<n>` (case-sensitive). Deletes its per-profile Keychain entry
///   too. Idempotent — removing an unknown name is a no-op.
/// - `provider?action=clear` — wipe every profile + every per-profile
///   Keychain entry + clear active selection. Idempotent.
/// - `present?sheet=<toc|highlights|ai|settings|bookmarks>[&tab=<...>][&detent=<medium|large>]`
///   — present a reader sheet so its rendered content becomes CU-free
///   verifiable via `snapshot` + `eval` (Bug #253 verification harness).
///   The handler posts `.debugBridgePresentSheet`; the reader-host
///   observer maps `(sheet, tab, detent)` to the SAME `@State` / route the
///   chrome buttons set, so the harness drives the real presentation path. The
///   optional `tab` selects a sub-tab: `toc` → `contents`/`bookmarks`;
///   `highlights` → `all`/`highlights`/`notes`/`bookmarks`; `ai` →
///   `summarize`/`translate`/`chat`. `settings` and `bookmarks` take no
///   `tab` (`bookmarks` is itself the `TOCSheet` Bookmarks tab). The optional
///   `detent` (Bug #256) is `ai`-only — `detent=large` exposes the larger AI
///   sheet detent so the Translate-tab `.complete` result card
///   (`translationResultCard`), which renders below the `.medium` fold beneath
///   the tall ORIGINAL card, becomes capturable without a drag/scroll gesture;
///   it sets the SAME `presentationDetents(selection:)` binding a user drag
///   reaches. Rejected on non-`ai` sheets (they declare no `presentationDetents`).
///   No-op when no reader is presented (mirrors `tts` / `search` / `highlight`).
/// - `ai?action=<summarize|chat|translate>[&scope=<section|chapter|book>][&text=<...>]`
///   — fire the AI action the *presented* AI sheet exposes (Bug #255
///   verification harness). `present?sheet=ai` opens the panel; this fires
///   the action the chrome buttons trigger (Summarize tap / chat send /
///   translate), so the AI-response-card render states become CU-free
///   verifiable. The handler posts `.debugBridgeAIAction`; the AI panel's
///   observer invokes the SAME view-model path the button does — no
///   parallel AI call. `scope` is summarize-only and maps the URL-friendly
///   `book` → `SummaryScope.bookSoFar` (`section`/`chapter` map 1:1); a
///   `scope` on chat/translate is rejected. `text` is the chat message
///   (required for `chat`) or the translate target-language override
///   (optional for `translate`; absent → the panel's current target
///   language); ignored for `summarize`. No-op when no AI sheet is
///   presented (mirrors `present`).
/// - `scroll-sheet?to=<top|bottom>` — scroll the active presented sheet's
///   scrollable content to the requested end (Bug #271 verification harness).
///   `detent=large` (Bug #256) reveals the larger AI sheet, but on the
///   Translate tab the tall auto-extracted ORIGINAL card alone exceeds even
///   the `.large` height, so the accent translation card stays below the fold;
///   `to=bottom` drives the `TranslationResultCard` ScrollView's
///   `ScrollViewReader` to its bottom anchor so `simctl io screenshot` captures
///   the translation card without a drag gesture. `to=top` returns to the
///   ORIGINAL card. The handler posts `.debugBridgeScrollSheet`; the presented
///   sheet's observer maps it to a `scrollTo(_:anchor:)` — no parallel scroll
///   logic. Issued AFTER `ai?action=translate` completes (the result card only
///   exists in the `.complete` state), which is why it is a standalone command
///   rather than a `present` parameter. No-op when no scrollable sheet observes
///   it (mirrors `tts` / `search` / `present`). `#if DEBUG`-gated.
/// - `seed-sessions?book=<fingerprintKey>[&seconds=<n>]` — seed a
///   deterministic spread of synthetic `ReadingSession` rows so the reading
///   dashboard (Feature #58) renders non-zero per-window totals CU-free
///   (Bug #263 verification harness). The reading dashboard reads
///   `ReadingSession` records, but `seed?fixture=…` seeds only books, so the
///   dashboard otherwise renders all-zero data. The handler inserts one
///   session per bounded time band (now−1h / 3d / 15d / 60d / 120d / 300d)
///   attached to `book`, each lasting `seconds` (default 600, must be ≥1).
///   Because the dashboard windows nest, this produces strictly-increasing
///   per-window totals (today < 7d < 30d < 90d < 180d < all), so criteria
///   b (windows render correct totals), c (per-book table renders), and d
///   (sort persists) become exercisable. `book` need not match a real Book
///   row — an orphan key surfaces as the dashboard's "(deleted)" row.
enum DebugCommand: Equatable {
    case reset
    case seed(fixture: String)
    case open(bookId: String, position: String?)
    case theme(mode: ThemeMode, fontSize: Int?)
    case settle(token: String)
    case snapshot(dest: String)
    case eval(bridge: String, js: String)
    case tts(action: String)
    case search(query: String, index: Int?)
    case highlight(startUTF16: Int, endUTF16: Int, color: String?)
    case provider(action: ProviderAction)
    case present(sheet: SheetKind, tab: String?, detent: SheetDetent?)
    /// Bug #267 — `seek?fraction=<0...1>` drives the active Foliate (AZW3/MOBI)
    /// reader to a fractional position (`readerAPI.goToFraction`) so the
    /// harness can reach a distinguishable non-start position. `fraction` is
    /// clamped to 0...1; a non-finite value is rejected by the parser.
    case seekFraction(fraction: Double)
    case aiAction(action: AIActionKind, scope: SummaryScope?, text: String?)
    case seedSessions(bookFingerprintKey: String, secondsPerSession: Int)
    /// Bug #271 — `scroll-sheet?to=<top|bottom>` scrolls the active presented
    /// sheet's scrollable content so below-fold content becomes CU-free
    /// capturable. `detent=large` (Bug #256) reveals the larger AI sheet, but
    /// on the Translate tab the tall auto-extracted ORIGINAL card alone exceeds
    /// even the `.large` height, leaving the accent translation card below the
    /// fold; this command drives the `TranslationResultCard` ScrollView's
    /// `ScrollViewReader` to the requested end. Issued AFTER the translation
    /// completes (the result card only exists in the `.complete` state), which
    /// is why it is a standalone command rather than a `present` parameter.
    case scrollSheet(target: ScrollTarget)

    /// Bug #273 — `navigate?spine=<N>[&fraction=<0...1>]` drives
    /// `.readerNavigateToLocator` CU-free (the verification harness for feature
    /// #71 WI-8 continuous-mode navigation, which the `search` driver cannot
    /// exercise in continuous mode). `spine` (required, ≥0) is the target spine
    /// index; `fraction` (optional, finite, clamped 0...1) is the intra-chapter
    /// landing position (absent ⇒ chapter start). The handler posts
    /// `.debugBridgeNavigateCommand`; the live `EPUBReaderContainerView` observer
    /// resolves the index → href + builds the `Locator` + re-posts
    /// `.readerNavigateToLocator`.
    case navigate(spineIndex: Int, fraction: Double?)

    /// Feature #71 WI-6b — `scroll-boundary?spine=<N>&near=<top|bottom>` drives
    /// `EPUBContinuousScrollCoordinator.handleBoundarySignal(_:)` CU-free. The
    /// production `continuousScrollObserverJS` is rAF-throttled and rAF is paused
    /// on the headless/virtual-display test environment, so a synthetic touch
    /// scroll never triggers a boundary report; this command posts a boundary
    /// signal directly. `spine` (required, ≥0) is the visible spine index; `near`
    /// is which materialized-doc boundary the viewport is near (`top` ⇒ extend
    /// backward, `bottom` ⇒ extend forward). The handler posts
    /// `.debugBridgeScrollBoundaryCommand`; the live `EPUBReaderContainerView`
    /// observer builds an `EPUBScrollBoundarySignal` and calls
    /// `coordinator.handleBoundarySignal` — bypassing the rAF observer.
    case scrollBoundary(spineIndex: Int, near: ScrollBoundaryEdge)

    /// Which AI action the `ai` command fires (Bug #255 — verification
    /// harness AI-action driver). The handler posts `.debugBridgeAIAction`;
    /// the AI panel's observer invokes the SAME view-model path the chrome
    /// buttons trigger (`AISummaryTabView.runSummarize` /
    /// `AIChatView.sendMessage` / `TranslationPanel.translate`), so there is
    /// no parallel AI call.
    ///
    /// - `summarize` — runs the Summarize tab's summary at the selected
    ///   `scope` over the full book text.
    /// - `chat` — sends a chat message (`text`) on the Chat tab.
    /// - `translate` — runs the Translate tab's translation (optional `text`
    ///   overrides the target language).
    enum AIActionKind: String, Equatable, CaseIterable {
        case summarize
        case chat
        case translate
    }

    /// Reader theme selector for the `theme` command.
    ///
    /// Feature #60 WI-11 migrated the reader to `ReaderThemeV2`'s
    /// 5-theme palette (paper / sepia / dark / oled / photo). `light`
    /// is retained as a backward-compatible alias for `paper` so older
    /// `mode=light` callers and verification scripts keep working.
    enum ThemeMode: String, Equatable, CaseIterable {
        case dark
        case light
        case paper
        case sepia
        case oled
        case photo
    }

    /// Local URL-grammar selector for the `provider?kind=…` parameter.
    /// The handler maps this 1:1 to the in-app `ProviderKind` enum.
    /// Kept local (mirroring `ThemeMode`) so this file stays a pure
    /// value-type parser with no AI-feature imports.
    enum ProviderActionKind: String, Equatable, CaseIterable {
        case openAICompatible
        case anthropicNative
    }

    /// Which reader sheet the `present` command opens (Bug #253 —
    /// verification harness sheet-presenter). The handler posts
    /// `.debugBridgePresentSheet`; the reader-host observer maps each
    /// case (and the optional `tab`) to the SAME `@State` / route the
    /// chrome buttons set, so the harness drives the real presentation
    /// path. Kept local (mirroring `ThemeMode` / `ProviderActionKind`)
    /// so this file stays a pure value-type parser with no View-layer
    /// imports.
    ///
    /// - `toc` — the navigation sheet (`TOCSheet`: Contents + Bookmarks).
    /// - `highlights` — the review sheet (`HighlightsSheet`: All /
    ///   Highlights / Notes / Bookmarks).
    /// - `ai` — the AI assistant panel (`AIReaderPanel`: Summarize /
    ///   Translate / Chat).
    /// - `settings` — the reader settings panel (`ReaderSettingsPanel`).
    /// - `bookmarks` — a top-level alias for the `TOCSheet` Bookmarks tab.
    enum SheetKind: String, Equatable, CaseIterable {
        case toc
        case highlights
        case ai
        case settings
        case bookmarks

        /// The set of valid `tab` values for this sheet, or `nil` when the
        /// sheet takes no `tab` parameter (settings has no tabs; bookmarks
        /// is itself a tab selector). Kept as literal string allowlists —
        /// same posture as the `highlight` `color` allowlist — so the
        /// parser stays free of View-layer enum imports. The reader-host
        /// observer maps these strings to the concrete tab enums
        /// (`TOCSheetTab` / `HighlightsSheetFilter` / `AIReaderTab`).
        var allowedTabs: Set<String>? {
            switch self {
            case .toc:        return ["contents", "bookmarks"]
            case .highlights: return ["all", "highlights", "notes", "bookmarks"]
            case .ai:         return ["summarize", "translate", "chat"]
            case .settings:   return nil
            case .bookmarks:  return nil
            }
        }

        /// Whether this sheet honors a `detent` parameter. Only the AI sheet
        /// (`AIReaderPanel`) declares `presentationDetents`; the others use a
        /// single default-height presentation, so a `detent` on them is a
        /// caller bug the parser rejects (Bug #256). Kept on `SheetKind` so the
        /// parser stays free of View-layer presentation imports.
        var supportsDetent: Bool {
            switch self {
            case .ai:                                   return true
            case .toc, .highlights, .settings, .bookmarks:
                return false
            }
        }
    }

    /// Which sheet detent the `present` command requests (Bug #256 —
    /// verification harness below-fold reveal). Only the AI sheet honors this
    /// (it declares `presentationDetents([.medium, .large])`). On the Translate
    /// tab the tall auto-extracted ORIGINAL card fills the visible `.medium`
    /// area, pushing `TranslationResultCard` (`.complete` result, a11y id
    /// `translationResultCard`) below the fold; `detent=large` exposes the
    /// larger detent so `simctl io screenshot` / `eval` can capture the result
    /// card without a drag/scroll gesture (CU-free). The handler posts the
    /// rawValue in `.debugBridgePresentSheet`'s `userInfo`; the reader-host
    /// observer maps it to the SAME `presentationDetents(selection:)` binding a
    /// user drag reaches — no parallel presentation logic. Absent → the default
    /// `.medium` presentation is left untouched.
    ///
    /// Kept local (mirroring `ThemeMode` / `SheetKind`) so this file stays a
    /// pure value-type parser with no SwiftUI `PresentationDetent` import.
    enum SheetDetent: String, Equatable, CaseIterable {
        case medium
        case large
    }

    /// Which end the `scroll-sheet` command drives the active presented sheet's
    /// scrollable content to (Bug #271 — below-fold content reveal). The
    /// handler posts the rawValue in `.debugBridgeScrollSheet`'s `userInfo`; the
    /// presented sheet's observer (today `TranslationResultCard`) maps it to a
    /// `ScrollViewReader` `scrollTo(_:anchor:)` against its own top/bottom
    /// anchor — no parallel scroll logic. `bottom` reveals the accent
    /// translation card sitting below the tall ORIGINAL card; `top` returns to
    /// the ORIGINAL card.
    ///
    /// Kept local (mirroring `ThemeMode` / `SheetKind` / `SheetDetent`) so this
    /// file stays a pure value-type parser with no SwiftUI import.
    enum ScrollTarget: String, Equatable, CaseIterable {
        case top
        case bottom
    }

    /// Which materialized-doc boundary the `scroll-boundary` command reports the
    /// viewport is near (feature #71 WI-6b — CU-free continuous-scroll boundary
    /// driver). `top` ⇒ the viewport is within the prefetch margin of the TOP of
    /// the materialized window (extend backward); `bottom` ⇒ near the BOTTOM
    /// (extend forward). The handler posts the rawValue in
    /// `.debugBridgeScrollBoundaryCommand`'s `userInfo`; the
    /// `EPUBReaderContainerView` observer maps it to the
    /// `EPUBScrollBoundarySignal`'s `nearTopBoundary` / `nearBottomBoundary`
    /// flags + `intraFraction` (0.0 at top, 1.0 at bottom).
    ///
    /// Kept local (mirroring `ThemeMode` / `ScrollTarget`) so this file stays a
    /// pure value-type parser with no reader-layer import.
    enum ScrollBoundaryEdge: String, Equatable, CaseIterable {
        case top
        case bottom
    }

    /// Discriminated action carried by `provider`. `add` carries every
    /// field needed to materialize a `ProviderProfile` plus an `active`
    /// flag (`true` → set as active on insert). `remove` keys on display
    /// name (the harness produces names; UUIDs aren't useful at the URL
    /// boundary). `clear` wipes every profile.
    enum ProviderAction: Equatable {
        case add(
            name: String,
            kind: ProviderActionKind,
            endpoint: URL,
            apiKey: String,
            model: String?,
            active: Bool
        )
        case remove(name: String)
        case clear
    }
}

/// Errors produced by `DebugCommand.parse(_:)`.
enum DebugCommandError: Error, Equatable {
    case invalidScheme
    case unknownCommand(String)
    case missingParam(String)
    case invalidParam(String, reason: String)
}

extension DebugCommand {

    /// Expected URL scheme. The URL host names the command.
    static let scheme = "vreader-debug"

    /// Parse a URL into a `DebugCommand`, or throw a `DebugCommandError`.
    ///
    /// Validates scheme, command name, and required/typed parameters. Empty-string
    /// values for required params are treated as missing.
    static func parse(_ url: URL) throws -> DebugCommand {
        guard url.scheme == scheme else {
            throw DebugCommandError.invalidScheme
        }
        guard let host = url.host, !host.isEmpty else {
            throw DebugCommandError.unknownCommand("")
        }
        // A test-control URL has no meaningful path. Reject `vreader-debug://settle/extra/path?token=x`
        // so a typo never silently dispatches the wrong command.
        guard url.path.isEmpty || url.path == "/" else {
            throw DebugCommandError.unknownCommand(host)
        }
        let params = try queryParams(url)

        switch host {
        case "reset":
            return .reset

        case "seed":
            let fixture = try requireParam("fixture", in: params)
            return .seed(fixture: fixture)

        case "open":
            let bookId = try requireParam("bookId", in: params)
            // Parameter is named `position` to match the documented grammar
            // and the public `DebugCommand.open(bookId:position:)` shape.
            // Reject the legacy `cfi` parameter explicitly so any caller still
            // using the old grammar gets a clear error rather than silently
            // opening at the start (feature #49 WI-0 grammar reconciliation).
            if params["cfi"] != nil {
                throw DebugCommandError.invalidParam(
                    "cfi",
                    reason: "Use 'position' — 'cfi' was renamed in feature #49 WI-0 grammar reconciliation"
                )
            }
            let position = nonEmpty(params["position"])
            return .open(bookId: bookId, position: position)

        case "theme":
            let modeRaw = try requireParam("mode", in: params)
            guard let mode = ThemeMode(rawValue: modeRaw) else {
                let valid = ThemeMode.allCases.map(\.rawValue).joined(separator: "|")
                throw DebugCommandError.invalidParam("mode", reason: "expected \(valid), got \(modeRaw)")
            }
            let fontSize: Int?
            if let raw = nonEmpty(params["fontSize"]) {
                guard let parsed = Int(raw) else {
                    throw DebugCommandError.invalidParam("fontSize", reason: "expected integer, got \(raw)")
                }
                fontSize = parsed
            } else {
                fontSize = nil
            }
            return .theme(mode: mode, fontSize: fontSize)

        case "settle":
            let token = try requireParam("token", in: params)
            try validateBasename(token, paramName: "token")
            return .settle(token: token)

        case "snapshot":
            let dest = try requireParam("dest", in: params)
            try validateBasename(dest, paramName: "dest")
            return .snapshot(dest: dest)

        case "eval":
            let bridge = try requireParam("bridge", in: params)
            // bridge becomes a filename ("eval-<bridge>.json"); validate as
            // a basename to prevent path traversal in the eval output path.
            try validateBasename(bridge, paramName: "bridge")
            let encoded = try requireParam("js", in: params)
            guard let data = Data(base64Encoded: encoded),
                  let js = String(data: data, encoding: .utf8) else {
                throw DebugCommandError.invalidParam("js", reason: "not valid base64-encoded UTF-8")
            }
            return .eval(bridge: bridge, js: js)

        case "tts":
            let action = try requireParam("action", in: params)
            // Restrict to the documented action set so typos surface as
            // invalidParam (not as silent no-ops in the dispatcher).
            guard action == "start" || action == "stop" else {
                throw DebugCommandError.invalidParam(
                    "action",
                    reason: "expected start|stop, got \(action)"
                )
            }
            return .tts(action: action)

        case "search":
            // Bug #238: verification harness search-driver. `query` opens
            // the search sheet + runs the query; optional `index` (0-indexed,
            // ≥0) taps result N. `index` without `query` is rejected — they
            // go together (the harness cannot meaningfully tap a result
            // before running a query). The empty-value rejection on `index`
            // matches `requireParam`'s posture on the other commands.
            let query = try requireParam("query", in: params)
            let index: Int?
            if let rawIndex = params["index"] {
                guard !rawIndex.isEmpty else {
                    throw DebugCommandError.invalidParam(
                        "index",
                        reason: "expected non-negative integer, got empty value"
                    )
                }
                guard let parsed = Int(rawIndex) else {
                    throw DebugCommandError.invalidParam(
                        "index",
                        reason: "expected non-negative integer, got \(rawIndex)"
                    )
                }
                guard parsed >= 0 else {
                    throw DebugCommandError.invalidParam(
                        "index",
                        reason: "must be ≥ 0, got \(parsed)"
                    )
                }
                index = parsed
            } else {
                index = nil
            }
            return .search(query: query, index: index)

        case "highlight":
            // Bug #237: verification harness highlight-creator. Builds a
            // highlight over a UTF-16 range in the active TXT/MD reader,
            // bypassing the long-press + SelectionPopoverView gesture
            // (which XCUITest cannot synthesize on iOS 26). Range is
            // inclusive-exclusive (`[start, end)`), both non-negative,
            // start < end (a zero-length range is rejected — the user
            // gesture path requires `selectedRange.length > 0` too).
            // Color is optional; defaults to "yellow" downstream. When
            // present, must be one of NamedHighlightColor's four rawValues.
            let startRaw = try requireParam("start", in: params)
            guard let parsedStart = Int(startRaw) else {
                throw DebugCommandError.invalidParam(
                    "start",
                    reason: "expected non-negative integer, got \(startRaw)"
                )
            }
            guard parsedStart >= 0 else {
                throw DebugCommandError.invalidParam(
                    "start",
                    reason: "must be ≥ 0, got \(parsedStart)"
                )
            }
            let endRaw = try requireParam("end", in: params)
            guard let parsedEnd = Int(endRaw) else {
                throw DebugCommandError.invalidParam(
                    "end",
                    reason: "expected non-negative integer, got \(endRaw)"
                )
            }
            guard parsedEnd >= 0 else {
                throw DebugCommandError.invalidParam(
                    "end",
                    reason: "must be ≥ 0, got \(parsedEnd)"
                )
            }
            guard parsedEnd > parsedStart else {
                throw DebugCommandError.invalidParam(
                    "end",
                    reason: "must be > start (got start=\(parsedStart) end=\(parsedEnd))"
                )
            }
            let color: String?
            if let rawColor = params["color"] {
                guard !rawColor.isEmpty else {
                    throw DebugCommandError.invalidParam(
                        "color",
                        reason: "expected one of yellow|pink|green|blue, got empty value"
                    )
                }
                // Allowlist — NamedHighlightColor.rawValue cases (feature #60
                // WI-7c). Keeping the allowlist literal here rather than
                // referencing the type avoids a release/debug coupling
                // (parser is pure-value; presenter type lives elsewhere).
                let validColors: Set<String> = ["yellow", "pink", "green", "blue"]
                guard validColors.contains(rawColor) else {
                    throw DebugCommandError.invalidParam(
                        "color",
                        reason: "expected one of yellow|pink|green|blue, got \(rawColor)"
                    )
                }
                color = rawColor
            } else {
                color = nil
            }
            return .highlight(startUTF16: parsedStart, endUTF16: parsedEnd, color: color)

        case "provider":
            // Bug #243: verification harness AI-provider-setup. Three sub-actions:
            // - add: insert a new profile + save its API key. Carries every
            //   field needed to materialize a ProviderProfile.
            // - remove: delete the profile with the given display name + drop
            //   its keychain entry. Idempotent.
            // - clear: wipe every profile + every keychain entry + clear active.
            //
            // The parser validates the URL grammar (which params are required
            // for which action). The handler does the actual store/keychain
            // mutations.
            let actionRaw = try requireParam("action", in: params)
            switch actionRaw {
            case "add":
                let name = try requireParam("name", in: params)
                let kindRaw = try requireParam("kind", in: params)
                guard let kind = ProviderActionKind(rawValue: kindRaw) else {
                    let valid = ProviderActionKind.allCases.map(\.rawValue).joined(separator: "|")
                    throw DebugCommandError.invalidParam(
                        "kind",
                        reason: "expected \(valid), got \(kindRaw)"
                    )
                }
                let endpointRaw = try requireParam("endpoint", in: params)
                // Mirror the production add-provider preflight (see
                // `AISettingsViewModel.validateBaseURL`): require a parseable
                // URL with a `host` (rejects opaque forms like `https:foo`),
                // and require `https` except for localhost loopback
                // (`http://localhost` / `http://127.0.0.1`). Stops the harness
                // from inserting profiles the runtime providers would reject.
                // Round-1 Codex audit Medium finding.
                guard let endpoint = URL(string: endpointRaw),
                      let scheme = endpoint.scheme?.lowercased(),
                      let host = endpoint.host?.lowercased(), !host.isEmpty else {
                    throw DebugCommandError.invalidParam(
                        "endpoint",
                        reason: "expected absolute http(s) URL with a host, got \(endpointRaw)"
                    )
                }
                let isLocalhost = host == "localhost" || host == "127.0.0.1"
                if scheme != "https" && !(scheme == "http" && isLocalhost) {
                    throw DebugCommandError.invalidParam(
                        "endpoint",
                        reason: "expected https (or http for localhost/127.0.0.1), got \(scheme)://\(host)"
                    )
                }
                let apiKey = try requireParam("apiKey", in: params)
                let model = nonEmpty(params["model"])
                let active: Bool
                if let rawActive = params["active"] {
                    guard !rawActive.isEmpty else {
                        throw DebugCommandError.invalidParam(
                            "active",
                            reason: "expected true|false, got empty value"
                        )
                    }
                    guard let parsedBool = Bool(rawActive) else {
                        throw DebugCommandError.invalidParam(
                            "active",
                            reason: "expected true|false, got \(rawActive)"
                        )
                    }
                    active = parsedBool
                } else {
                    active = false
                }
                return .provider(action: .add(
                    name: name,
                    kind: kind,
                    endpoint: endpoint,
                    apiKey: apiKey,
                    model: model,
                    active: active
                ))

            case "remove":
                let name = try requireParam("name", in: params)
                return .provider(action: .remove(name: name))

            case "clear":
                return .provider(action: .clear)

            default:
                throw DebugCommandError.invalidParam(
                    "action",
                    reason: "expected add|remove|clear, got \(actionRaw)"
                )
            }

        case "present":
            // Bug #253: verification harness sheet-presenter. `sheet` names
            // which reader sheet to present; optional `tab` selects a sub-tab
            // (validated against the sheet's vocabulary). The handler posts
            // `.debugBridgePresentSheet`; the reader-host observer maps the
            // (sheet, tab) to the SAME `@State` / route the chrome buttons
            // set — no parallel presentation logic.
            let sheetRaw = try requireParam("sheet", in: params)
            guard let sheet = SheetKind(rawValue: sheetRaw) else {
                let valid = SheetKind.allCases.map(\.rawValue).joined(separator: "|")
                throw DebugCommandError.invalidParam(
                    "sheet",
                    reason: "expected \(valid), got \(sheetRaw)"
                )
            }
            let tab: String?
            if let rawTab = params["tab"] {
                guard !rawTab.isEmpty else {
                    throw DebugCommandError.invalidParam(
                        "tab",
                        reason: "expected a non-empty tab value, got empty value"
                    )
                }
                // Reject a `tab` for sheets that take none (settings /
                // bookmarks) so a typo surfaces rather than silently no-op.
                guard let allowed = sheet.allowedTabs else {
                    throw DebugCommandError.invalidParam(
                        "tab",
                        reason: "sheet '\(sheetRaw)' takes no tab parameter"
                    )
                }
                guard allowed.contains(rawTab) else {
                    let valid = allowed.sorted().joined(separator: "|")
                    throw DebugCommandError.invalidParam(
                        "tab",
                        reason: "expected \(valid) for sheet '\(sheetRaw)', got \(rawTab)"
                    )
                }
                tab = rawTab
            } else {
                tab = nil
            }
            // Bug #256: optional `detent` (AI sheet only). Reject it on sheets
            // that don't declare `presentationDetents` so a typo surfaces
            // rather than silently no-op (same posture as the `tab` rejection
            // on settings/bookmarks). Empty `detent=` is a caller bug.
            let detent: SheetDetent?
            if let rawDetent = params["detent"] {
                guard sheet.supportsDetent else {
                    throw DebugCommandError.invalidParam(
                        "detent",
                        reason: "sheet '\(sheetRaw)' takes no detent parameter (only 'ai' supports detents)"
                    )
                }
                guard !rawDetent.isEmpty else {
                    let valid = SheetDetent.allCases.map(\.rawValue).joined(separator: "|")
                    throw DebugCommandError.invalidParam(
                        "detent",
                        reason: "expected \(valid), got empty value"
                    )
                }
                guard let parsedDetent = SheetDetent(rawValue: rawDetent) else {
                    let valid = SheetDetent.allCases.map(\.rawValue).joined(separator: "|")
                    throw DebugCommandError.invalidParam(
                        "detent",
                        reason: "expected \(valid), got \(rawDetent)"
                    )
                }
                detent = parsedDetent
            } else {
                detent = nil
            }
            return .present(sheet: sheet, tab: tab, detent: detent)

        case "ai":
            // Bug #255: verification harness AI-action driver. Extracted to a
            // helper to keep this already-large parser switch readable.
            return try parseAICommand(params)

        case "seed-sessions":
            // Bug #263: verification harness reading-session seeder. `book` is
            // the fingerprint key the synthetic sessions attach to (required,
            // non-empty). `seconds` is each session's durationSeconds (optional;
            // defaults to 600; must be a positive integer — a zero/negative
            // duration would seed sessions the aggregator clamps to 0, defeating
            // the purpose of producing non-zero totals).
            let book = try requireParam("book", in: params)
            let secondsPerSession: Int
            if let rawSeconds = params["seconds"] {
                guard !rawSeconds.isEmpty else {
                    throw DebugCommandError.invalidParam(
                        "seconds",
                        reason: "expected a positive integer, got empty value"
                    )
                }
                guard let parsed = Int(rawSeconds) else {
                    throw DebugCommandError.invalidParam(
                        "seconds",
                        reason: "expected a positive integer, got \(rawSeconds)"
                    )
                }
                guard parsed >= 1 else {
                    throw DebugCommandError.invalidParam(
                        "seconds",
                        reason: "must be ≥ 1, got \(parsed)"
                    )
                }
                secondsPerSession = parsed
            } else {
                secondsPerSession = 600
            }
            return .seedSessions(bookFingerprintKey: book, secondsPerSession: secondsPerSession)

        case "seek":
            // Bug #267: drive the active Foliate reader to a fractional
            // position. `fraction` is required; must be a finite number; it is
            // clamped to 0...1 (a verifier passing 0.5 reaches mid-book even if
            // it slightly overshoots, rather than erroring).
            let rawFraction = try requireParam("fraction", in: params)
            guard let parsed = Double(rawFraction), parsed.isFinite else {
                throw DebugCommandError.invalidParam(
                    "fraction",
                    reason: "expected a finite number in 0...1, got \(rawFraction)"
                )
            }
            return .seekFraction(fraction: min(max(parsed, 0), 1))

        case "navigate":
            // Bug #273: drive `.readerNavigateToLocator` CU-free — the
            // verification harness for feature #71 WI-8 continuous-mode
            // navigation. `spine` is required and must be a non-negative
            // integer (the observer additionally range-checks against the
            // loaded spine count). `fraction` is optional; when present it must
            // be a finite number and is clamped to 0...1 (mirrors `seek`).
            let rawSpine = try requireParam("spine", in: params)
            guard let spine = Int(rawSpine), spine >= 0 else {
                throw DebugCommandError.invalidParam(
                    "spine",
                    reason: "expected a non-negative integer, got \(rawSpine)"
                )
            }
            let fraction: Double?
            if let rawFraction = params["fraction"] {
                guard !rawFraction.isEmpty else {
                    throw DebugCommandError.invalidParam(
                        "fraction",
                        reason: "expected a finite number in 0...1, got empty value"
                    )
                }
                guard let parsedFraction = Double(rawFraction), parsedFraction.isFinite else {
                    throw DebugCommandError.invalidParam(
                        "fraction",
                        reason: "expected a finite number in 0...1, got \(rawFraction)"
                    )
                }
                fraction = min(max(parsedFraction, 0), 1)
            } else {
                fraction = nil
            }
            return .navigate(spineIndex: spine, fraction: fraction)

        case "scroll-boundary":
            // Feature #71 WI-6b: drive `handleBoundarySignal` CU-free. `spine` is
            // required and must be a non-negative integer (same validation as
            // `navigate`'s `spine`). `near` is required; one of top|bottom (mirrors
            // the ScrollTarget allowlist posture) — anything else is a caller bug
            // the parser rejects rather than silently no-op.
            let rawSpine = try requireParam("spine", in: params)
            guard let spine = Int(rawSpine), spine >= 0 else {
                throw DebugCommandError.invalidParam(
                    "spine",
                    reason: "expected a non-negative integer, got \(rawSpine)"
                )
            }
            let nearRaw = try requireParam("near", in: params)
            guard let near = ScrollBoundaryEdge(rawValue: nearRaw) else {
                let valid = ScrollBoundaryEdge.allCases.map(\.rawValue).joined(separator: "|")
                throw DebugCommandError.invalidParam("near", reason: "expected \(valid), got \(nearRaw)")
            }
            return .scrollBoundary(spineIndex: spine, near: near)

        case "scroll-sheet":
            // Bug #271: scroll the active presented sheet's scrollable content.
            // `to` is required; one of top|bottom (mirrors the SheetDetent
            // allowlist posture). Empty `to=` is treated as missing by
            // requireParam — same as every other command.
            let toRaw = try requireParam("to", in: params)
            guard let target = ScrollTarget(rawValue: toRaw) else {
                let valid = ScrollTarget.allCases.map(\.rawValue).joined(separator: "|")
                throw DebugCommandError.invalidParam("to", reason: "expected \(valid), got \(toRaw)")
            }
            return .scrollSheet(target: target)

        default:
            throw DebugCommandError.unknownCommand(host)
        }
    }

    // MARK: - Helpers

    /// Parse the `ai` command's `(action, scope, text)` (Bug #255). `action`
    /// names which AI action to fire on the presented AI sheet; `scope` is
    /// summarize-only (maps the URL-friendly `book` → `SummaryScope.bookSoFar`,
    /// rejected for chat/translate); `text` is the chat message (required for
    /// chat) or the translate target-language override (optional, ignored for
    /// summarize). The handler posts `.debugBridgeAIAction`; the AI panel's
    /// observer invokes the SAME view-model path the chrome buttons trigger —
    /// no parallel AI call.
    private static func parseAICommand(_ params: [String: String]) throws -> DebugCommand {
        let actionRaw = try requireParam("action", in: params)
        guard let action = AIActionKind(rawValue: actionRaw) else {
            let valid = AIActionKind.allCases.map(\.rawValue).joined(separator: "|")
            throw DebugCommandError.invalidParam(
                "action",
                reason: "expected \(valid), got \(actionRaw)"
            )
        }

        // `scope` is only meaningful for summarize (the Summarize tab's scope
        // chips). Reject it on chat/translate so a typo surfaces rather than
        // silently dropping the scope.
        let scope: SummaryScope?
        if let rawScope = params["scope"] {
            guard action == .summarize else {
                throw DebugCommandError.invalidParam(
                    "scope",
                    reason: "scope is only valid for action=summarize, got action=\(actionRaw)"
                )
            }
            guard !rawScope.isEmpty else {
                throw DebugCommandError.invalidParam(
                    "scope",
                    reason: "expected one of section|chapter|book, got empty value"
                )
            }
            // The URL uses the friendly `book`; map it to the
            // `SummaryScope.bookSoFar` case. `section`/`chapter` map 1:1.
            switch rawScope {
            case "section": scope = .section
            case "chapter": scope = .chapter
            case "book":    scope = .bookSoFar
            default:
                throw DebugCommandError.invalidParam(
                    "scope",
                    reason: "expected one of section|chapter|book, got \(rawScope)"
                )
            }
        } else {
            scope = nil
        }

        // `text` is required for chat (the message to send) and optional for
        // translate (target-language override). It is meaningless for
        // summarize (the scope chip drives it) — accepted but ignored, so the
        // handler doesn't need a separate guard.
        let text: String?
        if action == .chat {
            // requireParam treats empty as missing — chat with no message has
            // nothing to send (the VM's sendMessage ignores empties).
            text = try requireParam("text", in: params)
        } else {
            text = nonEmpty(params["text"])
        }
        return .aiAction(action: action, scope: scope, text: text)
    }

    private static func queryParams(_ url: URL) throws -> [String: String] {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = comps.queryItems else {
            return [:]
        }
        var seen: Set<String> = []
        var out: [String: String] = [:]
        for item in items {
            // Reject duplicate keys explicitly. `?fixture=a&fixture=b` is almost always
            // a caller bug; silently using the last value masks it.
            if !seen.insert(item.name).inserted {
                throw DebugCommandError.invalidParam(item.name, reason: "duplicate parameter")
            }
            out[item.name] = item.value ?? ""
        }
        return out
    }

    private static func requireParam(_ name: String, in params: [String: String]) throws -> String {
        guard let raw = params[name], !raw.isEmpty else {
            throw DebugCommandError.missingParam(name)
        }
        return raw
    }

    private static func nonEmpty(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

    /// Maximum length for filename-like parameters (`token`, `dest`).
    static let basenameMaxLength = 64

    /// Validate a parameter as a safe filename basename. The bridge writes
    /// real files with these values, so this is the right place to stop
    /// path traversal (`..`), separators (`/`), control characters, and
    /// dot-only sequences (`.`, `..`, `...`) before they reach the
    /// filesystem.
    ///
    /// Allowed: `[A-Za-z0-9._-]`, length 1..=64, with at least one char
    /// outside the dot-only set.
    private static func validateBasename(_ value: String, paramName: String) throws {
        guard value.count <= basenameMaxLength else {
            throw DebugCommandError.invalidParam(
                paramName,
                reason: "exceeds \(basenameMaxLength) characters"
            )
        }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        if value.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            throw DebugCommandError.invalidParam(
                paramName,
                reason: "must match [A-Za-z0-9._-]"
            )
        }
        // Reject pure-dot sequences (".", "..", "...", etc.). They pass the
        // character-class check but trip path-traversal in any handler that
        // does `base.appendingPathComponent(value)`.
        if value.allSatisfy({ $0 == "." }) {
            throw DebugCommandError.invalidParam(
                paramName,
                reason: "dot-only basenames are not allowed"
            )
        }
    }
}

#endif
