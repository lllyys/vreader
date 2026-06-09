// Purpose: Orchestrator for the vreader-debug:// URL scheme (feature #44).
// Parses incoming URLs via DebugCommand, dispatches to a DebugBridgeContext
// implementation. Pure routing — does not own state or side effects so it can
// be unit-tested with mock contexts. DEBUG-only.

#if DEBUG

import Foundation

/// All side-effectful command handlers used by the debug bridge. Implementations
/// own real app state; the bridge itself stays a pure dispatcher.
///
/// Handlers throw on real failures (unknown fixture, missing resource, import
/// failure, etc.) so the bridge can record `lastError` for later inspection
/// via `snapshot`. A no-op success returns without throwing; callers that want
/// "swallow errors" semantics must catch explicitly.
@MainActor
protocol DebugBridgeContext {
    func reset() async throws
    func seed(fixture: String) async throws
    func open(bookId: String, position: String?) async throws
    func theme(mode: DebugCommand.ThemeMode, fontSize: Int?) async throws
    func settle(token: String) async throws
    /// Build a state snapshot and write it to `dest` (a basename, validated
    /// by the parser). `lastErrorMessage` is the bridge's lastError as a
    /// string at dispatch time — the previous command's failure reason, or
    /// nil if the previous command succeeded.
    func snapshot(dest: String, lastErrorMessage: String?) async throws
    /// Bug #1218 — write the active TXT reader's currently-rendered
    /// (post-conversion) text to `dest` (a parser-validated basename) as
    /// JSON. iOS 26 SwiftUI flattens the chunked TXT reader's inner cells
    /// into the container, whose accessibility VALUE is the load-bearing
    /// state probe, so CU-free XCUITest cannot read the rendered content
    /// directly. Mirrors `snapshot` — always writes a file (an
    /// `{"error": "no active reader"}` payload when no reader is presented),
    /// throwing only on a filesystem-write failure.
    func txtContent(dest: String) async throws
    func eval(bridge: String, js: String) async throws
    /// Feature #45 WI-4c-b — drive TTS from outside the reader.
    /// `action` is one of `"start"` / `"stop"`. The handler posts a
    /// notification observed by the active reader; if no reader is
    /// loaded, the action is a no-op (matches the parser's grammar
    /// guarantee but lets tests fire the URL without preconditions).
    func tts(action: String) async throws
    /// Bug #238 — drive the in-reader search sheet from outside.
    /// `query` runs the search; the optional `index` (0-indexed, ≥0)
    /// taps result N once results arrive. The handler posts a
    /// notification observed by the active reader. If no reader is
    /// loaded, the action is a no-op (matches `tts` / `theme`).
    func search(query: String, index: Int?) async throws
    /// Feature #77 — drive interlinear bilingual mode (enable/disable/status)
    /// on the active reader via `.debugBridgeBilingualCommand`. No-op when no
    /// reader is loaded (matches `search` / `tts`).
    func bilingual(action: DebugCommand.BilingualAction) async throws
    /// Bug #237 — create a highlight over a UTF-16 range in the active
    /// reader, bypassing the long-press + SelectionPopoverView gesture
    /// path that XCUITest cannot synthesize on iOS 26. The handler posts
    /// a notification observed by the active TXT/MD reader, which builds
    /// a Locator + persists the highlight + re-paints. If no reader is
    /// loaded, the action is a no-op (matches `tts` / `search`).
    func highlight(startUTF16: Int, endUTF16: Int, color: String?) async throws
    /// Bug #243 — configure an AI provider profile programmatically.
    /// `add` inserts a new `ProviderProfile`, saves its API key to the
    /// per-profile Keychain account, and optionally sets it active.
    /// `remove` deletes the profile with the given display name (and its
    /// keychain entry). `clear` wipes every profile + every keychain
    /// entry. Mutations propagate through `ProviderProfileStore`'s usual
    /// `.providerProfilesDidChange` notification, so any in-app picker
    /// resyncs without an additional bridge-level notification.
    func provider(action: DebugCommand.ProviderAction) async throws
    /// Bug #253 — present a reader sheet from outside the chrome so its
    /// rendered content becomes CU-free verifiable via `snapshot` + `eval`.
    /// The handler posts `.debugBridgePresentSheet`; the active reader's
    /// observer maps the `(sheet, tab, detent)` to the SAME `@State` / route
    /// the chrome buttons set (no parallel presentation logic). `detent`
    /// (Bug #256) is `ai`-only and, when supplied, sets the SAME
    /// `presentationDetents(selection:)` binding a user drag reaches — so the
    /// Translate-tab below-fold result card becomes CU-free capturable. If no
    /// reader is loaded, the action is a no-op (matches `tts` / `search` /
    /// `highlight`).
    func present(sheet: DebugCommand.SheetKind, tab: String?, detent: DebugCommand.SheetDetent?) async throws
    /// Bug #255 — fire an AI action on the *presented* AI sheet from outside
    /// the chrome so the AI-response-card render states become CU-free
    /// verifiable via `snapshot` + `eval`. The handler posts
    /// `.debugBridgeAIAction`; the AI panel's observer invokes the SAME
    /// view-model path the chrome buttons trigger (`runSummarize` /
    /// `sendMessage` / `translate`) — no parallel AI call. `scope` is
    /// summarize-only; `text` is the chat message / translate language
    /// override. If no AI sheet is presented, the action is a no-op (matches
    /// `present` / `tts` / `search`).
    func aiAction(action: DebugCommand.AIActionKind, scope: SummaryScope?, text: String?) async throws
    /// Bug #263 — seed synthetic `ReadingSession` rows so the reading
    /// dashboard (Feature #58) renders non-zero per-window totals CU-free.
    /// The handler inserts one session per bounded time band attached to
    /// `bookFingerprintKey` via the real persistence boundary (so the
    /// dashboard aggregator reads them through its normal SwiftData query),
    /// each lasting `secondsPerSession`, then refreshes the book's
    /// `ReadingStats` aggregate. NOT idempotent — each call ADDS another
    /// six-session spread (totals grow), so a verify run should `reset` first.
    func seedReadingSessions(bookFingerprintKey: String, secondsPerSession: Int) async throws
    /// Bug #267 — drive the active Foliate (AZW3/MOBI) reader to a fractional
    /// position so the harness can reach a *distinguishable non-start* position
    /// for the Bug #265 save→reopen→restore round-trip. The handler posts
    /// `.debugBridgeSeekFraction`; the live `FoliateBilingualContainerView`
    /// observer forwards it to the SAME `.foliateRequestSeekFraction` channel
    /// the bottom-chrome scrubber uses (`readerAPI.goToFraction`), injecting its
    /// own `fingerprintKey`. If no Foliate reader is loaded, the action is a
    /// no-op (matches `tts` / `search` / `present`). `fraction` is clamped to
    /// 0...1 by the parser.
    func seekFraction(fraction: Double) async throws
    /// Bug #271 — scroll the active presented sheet's scrollable content to a
    /// requested end so below-fold content becomes CU-free capturable. The
    /// handler posts `.debugBridgeScrollSheet`; the presented sheet's observer
    /// (today `TranslationResultCard`) maps the target to a `ScrollViewReader`
    /// `scrollTo(_:anchor:)` against its own top/bottom anchor — no parallel
    /// scroll logic. If no scrollable sheet observes it, the action is a no-op
    /// (matches `present` / `tts` / `search`).
    func scrollSheet(target: DebugCommand.ScrollTarget) async throws
    /// Bug #273 — drive `.readerNavigateToLocator` CU-free (the verification
    /// harness for feature #71 WI-8 continuous-mode navigation). The handler
    /// posts `.debugBridgeNavigateCommand`; the live `EPUBReaderContainerView`
    /// observer resolves `spineIndex` → href against `viewModel.metadata`,
    /// builds a `Locator`, and re-posts `.readerNavigateToLocator` — the SAME
    /// channel a TOC/bookmark/search tap uses. If no matching EPUB reader is
    /// loaded, the action is a no-op (matches `seek` / `search` / `present`).
    func navigate(spineIndex: Int, fraction: Double?) async throws
    /// Feature #74 — drive `.readerNavigateToLocator` for the active TXT/MD
    /// reader CU-free so the locate "bloom" can be asserted via the DEBUG
    /// snapshot's `landingBloomCount` / `landingBloomPeakIntensity` (the
    /// sub-second visual can't be captured on the virtual display). The handler
    /// resolves the `highlightIndex`-th persisted highlight for the active book
    /// (the same order the annotations sheet shows) and posts its saved
    /// `Locator` on `.readerNavigateToLocator` — the SAME channel a
    /// Notes/Highlights row tap uses, so the bloom fires on the real render
    /// path. No-op when no TXT/MD reader is presented or no Nth highlight
    /// exists (matches `navigate` / `seek` / `present`).
    func locate(highlightIndex: Int) async throws
    /// Feature #71 WI-6b — drive `EPUBContinuousScrollCoordinator.handleBoundarySignal`
    /// CU-free. The production `continuousScrollObserverJS` is rAF-throttled and
    /// rAF is paused on the headless/virtual-display test environment, so a
    /// synthetic touch scroll never triggers a boundary report; this posts the
    /// signal directly. The handler posts `.debugBridgeScrollBoundaryCommand`;
    /// the live `EPUBReaderContainerView` observer builds an
    /// `EPUBScrollBoundarySignal` and calls `coordinator.handleBoundarySignal`.
    /// If no matching continuous-mode EPUB reader is loaded, the action is a
    /// no-op (matches `navigate` / `seek` / `search`).
    func scrollBoundary(spineIndex: Int, near: DebugCommand.ScrollBoundaryEdge) async throws
    /// Feature #17 — drive PDF highlight CREATION CU-free so the
    /// selection-driven highlight → PDFAnnotation render + persist can be
    /// device-verified WITHOUT a real long-press-drag text selection. The
    /// handler posts `.debugBridgePDFHighlightCommand` carrying the page index,
    /// the normalized rect (as a 4-element `[Double]` `[x, y, w, h]`), and the
    /// optional color; the live `PDFReaderContainerView` observer builds a
    /// `ReaderSelectionEvent` with a `.pdf` anchor and calls the SAME
    /// `handleHighlightAction` the gesture uses (coordinator → `addHighlight`
    /// → `PDFAnnotationBridge.createHighlightFromAnchor`) so the annotation
    /// renders AND persists. If no PDF reader is loaded, no observer fires —
    /// the URL is silently a no-op (matches `highlight` / `navigate` / `seek`).
    func pdfHighlight(page: Int, rect: NormalizedRect, color: String?) async throws
    /// Feature #75 WI-5a — switch the active EPUB reader's layout preference
    /// CU-free so RTL / vertical-rl PAGED paging can be device-verified without
    /// driving the segmented `Picker(.segmented)` (untappable under XCUITest on
    /// iOS 26). The handler posts `.debugBridgeSetLayoutCommand`; the live
    /// `EPUBReaderContainerView` observer sets `settingsStore.epubLayout` — the
    /// SAME binding the picker drives. If no EPUB reader is presented, no
    /// observer fires — the URL is silently a no-op (matches `navigate` /
    /// `seek` / `present`).
    func setLayout(layout: DebugCommand.LayoutMode) async throws
    /// Feature #42/#75 — drive a page turn CU-free by posting the shared
    /// `.readerNextPage` / `.readerPreviousPage` notification every native reader
    /// host observes (Readium → `goForward`/`goBackward`; legacy EPUB/Foliate
    /// paged → their page nav). Synthetic swipes can't drive Readium's gesture
    /// recognizers, so this bus-level driver is the reliable CU-free page-nav
    /// path (incl. RTL / vertical-rl reading order). No-op when no reader is
    /// presented.
    func page(direction: DebugCommand.PageDirection) async throws
}

/// Routes parsed `DebugCommand` values to a `DebugBridgeContext`.
/// Records the most recent error (parse failures) for debugging.
///
/// Concurrency: commands are serialized through a chained Task so that two
/// rapid `handle(_:)` calls cannot interleave. `@MainActor` alone wouldn't
/// guarantee this — actor methods are reentrant across `await` points, and
/// `.onOpenURL` callbacks spawn independent unstructured tasks.
@MainActor
final class DebugBridge {
    private let context: DebugBridgeContext
    private(set) var lastError: Error?
    /// Tail of the chain of in-flight command tasks. Each new `handle(_:)`
    /// awaits the previous task before processing, giving FIFO semantics.
    private var pendingTask: Task<Void, Never>?

    init(context: DebugBridgeContext) {
        self.context = context
    }

    /// Parse `url`, dispatch to the matching context method, serialized
    /// after any previously-enqueued command. Returns when this command
    /// (and the chain in front of it) has completed.
    /// Sets `lastError` on parse failure; clears it on successful dispatch.
    func handle(_ url: URL) async {
        let previous = pendingTask
        let next = Task<Void, Never> { @MainActor [weak self] in
            _ = await previous?.value
            await self?.process(url)
        }
        pendingTask = next
        await next.value
    }

    private func process(_ url: URL) async {
        do {
            let cmd = try DebugCommand.parse(url)
            try await dispatch(cmd)
            lastError = nil
        } catch {
            lastError = error
        }
    }

    /// Render an error as a stable string for the snapshot's `lastError`
    /// field. Format is `"category: detail"`; consumers may pin on the
    /// category prefix without depending on Swift's enum-case spelling.
    /// Categories: `parse.<kind>`, `bridge.<kind>`, `unknown`.
    /// `nonisolated` so tests can call without hopping to MainActor.
    nonisolated static func stableErrorMessage(for error: Error) -> String {
        switch error {
        case let e as DebugCommandError:
            switch e {
            case .invalidScheme:
                return "parse.invalidScheme"
            case .unknownCommand(let host):
                return "parse.unknownCommand: \(host)"
            case .missingParam(let name):
                return "parse.missingParam: \(name)"
            case .invalidParam(let name, let reason):
                return "parse.invalidParam: \(name) (\(reason))"
            }
        case let e as DebugBridgeContextError:
            switch e {
            case .unknownFixture(let name):
                return "bridge.unknownFixture: \(name)"
            case .fixtureResourceMissing(let name):
                return "bridge.fixtureResourceMissing: \(name)"
            case .notImplemented(let cmd):
                return "bridge.notImplemented: \(cmd)"
            case .bookNotFound(let id):
                return "bridge.bookNotFound: \(id)"
            case .noActiveReader:
                return "bridge.noActiveReader"
            case .settleTimeout:
                return "bridge.settleTimeout"
            case .evalUnsupported(let fmt):
                return "bridge.evalUnsupported: \(fmt)"
            case .evalFailed(let msg):
                return "bridge.evalFailed: \(msg)"
            case .invalidPosition(let format, let position, let reason):
                return "bridge.invalidPosition: \(format) \(position) — \(reason)"
            case .openAwaitReaderTimeout(let key):
                return "bridge.openAwaitReaderTimeout: \(key)"
            case .seekUnsupportedForFormat(let format, let position):
                return "bridge.seekUnsupportedForFormat: \(format) \(position)"
            case .invalidFingerprintKey(let key):
                return "bridge.invalidFingerprintKey: \(key)"
            }
        default:
            return "unknown: \(String(describing: type(of: error)))"
        }
    }

    private func dispatch(_ cmd: DebugCommand) async throws {
        switch cmd {
        case .reset:
            try await context.reset()
        case .seed(let fixture):
            try await context.seed(fixture: fixture)
        case .open(let bookId, let position):
            try await context.open(bookId: bookId, position: position)
        case .theme(let mode, let fontSize):
            try await context.theme(mode: mode, fontSize: fontSize)
        case .settle(let token):
            try await context.settle(token: token)
        case .snapshot(let dest):
            // Pass the bridge's current lastError so snapshot can encode it.
            // After this call returns successfully, process() clears lastError
            // — the snapshot captures the state at dispatch time.
            let msg = lastError.map { Self.stableErrorMessage(for: $0) }
            try await context.snapshot(dest: dest, lastErrorMessage: msg)
        case .txtContent(let dest):
            try await context.txtContent(dest: dest)
        case .eval(let bridge, let js):
            try await context.eval(bridge: bridge, js: js)
        case .tts(let action):
            try await context.tts(action: action)
        case .search(let query, let index):
            try await context.search(query: query, index: index)
        case .bilingual(let action):
            try await context.bilingual(action: action)
        case .highlight(let start, let end, let color):
            try await context.highlight(startUTF16: start, endUTF16: end, color: color)
        case .provider(let action):
            try await context.provider(action: action)
        case .present(let sheet, let tab, let detent):
            try await context.present(sheet: sheet, tab: tab, detent: detent)
        case .aiAction(let action, let scope, let text):
            try await context.aiAction(action: action, scope: scope, text: text)
        case .seedSessions(let bookFingerprintKey, let secondsPerSession):
            try await context.seedReadingSessions(
                bookFingerprintKey: bookFingerprintKey,
                secondsPerSession: secondsPerSession
            )
        case .seekFraction(let fraction):
            try await context.seekFraction(fraction: fraction)
        case .scrollSheet(let target):
            try await context.scrollSheet(target: target)
        case .navigate(let spineIndex, let fraction):
            try await context.navigate(spineIndex: spineIndex, fraction: fraction)
        case .locate(let highlightIndex):
            try await context.locate(highlightIndex: highlightIndex)
        case .scrollBoundary(let spineIndex, let near):
            try await context.scrollBoundary(spineIndex: spineIndex, near: near)
        case .pdfHighlight(let page, let rect, let color):
            try await context.pdfHighlight(page: page, rect: rect, color: color)
        case .setLayout(let layout):
            try await context.setLayout(layout: layout)
        case .page(let direction):
            try await context.page(direction: direction)
        }
    }
}

#endif
