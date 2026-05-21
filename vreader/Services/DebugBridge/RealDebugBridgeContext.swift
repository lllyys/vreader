// Purpose: Production handler set behind the vreader-debug:// URL scheme
// (feature #44 DebugBridge, WI-5). Owns dependencies on real app subsystems
// (PersistenceActor, BookImporting, plus active-reader hooks added in later
// WI-5 commits) so each command performs real work rather than logging.
// DEBUG-only.
//
// Composition: VReaderApp builds one of these with the same dependencies
// it injects into LibraryViewModel and stores it as a `let debugBridge`
// property. .onOpenURL captures the bridge by value and dispatches to
// it. There is no global indirection — the bridge is owned by the App.
//
// Per-command handlers split across extension files for the 300-line LOC
// guideline (feature #44 acceptance criterion (g)):
//   - reset, seed, open, theme — this file
//   - settle — RealDebugBridgeContext+Settle.swift
//   - snapshot — RealDebugBridgeContext+Snapshot.swift
//   - eval — RealDebugBridgeContext+Eval.swift
//   - provider — RealDebugBridgeContext+Provider.swift (Bug #243)

#if DEBUG

import Foundation
import OSLog

/// Errors specific to RealDebugBridgeContext. Generic errors from underlying
/// services (PersistenceActor, BookImporter) propagate as-is so callers see
/// the real cause via `DebugBridge.lastError`.
enum DebugBridgeContextError: Error, Equatable {
    case unknownFixture(String)
    case fixtureResourceMissing(String)
    case notImplemented(command: String)
    case bookNotFound(String)
    case noActiveReader
    case settleTimeout
    case evalUnsupported(format: String)
    case evalFailed(String)
    /// Feature #49 WI-7b: position string didn't match the format's expected
    /// shape. Carries the format + raw position + a human-readable reason.
    case invalidPosition(format: String, position: String, reason: String)
    /// Feature #49 WI-7b: awaitReader timed out waiting for a reader matching
    /// `fingerprintKey` to register after the open notification was posted.
    case openAwaitReaderTimeout(fingerprintKey: String)
    /// Bug #257: a `position` was supplied for a format whose host-side seek
    /// cannot honor the resolved position shape. Currently only EPUB — its
    /// navigate handler resolves the spine by `href`, not raw CFI, so a
    /// CFI-only seek would be a silent no-op. Failing loudly (rather than
    /// opening at the wrong place) preserves the bug's original "fail loudly"
    /// contract. TXT / MD (offset), PDF (page), and AZW3 (Foliate consumes
    /// CFI directly) all seek; EPUB does not yet.
    case seekUnsupportedForFormat(format: String, position: String)
}

/// Production DebugBridgeContext. Each handler is a thin wrapper over
/// existing app services so behavior matches what the user-facing UI does
/// (no parallel implementations to drift). Handlers added incrementally
/// across WI-5; un-implemented ones throw.
@MainActor
final class RealDebugBridgeContext: DebugBridgeContext {
    /// Internal so extension files (Settle/Snapshot/Eval) can reach it.
    let persistence: PersistenceActor
    private let importer: BookImporting
    /// Bundle that holds DEBUG fixture resources. Defaults to `Bundle.main`;
    /// tests inject a custom bundle so they don't depend on app installation.
    private let fixtureBundle: Bundle
    /// UserDefaults suite that backs reader settings. Defaults to `.standard`;
    /// tests inject a unique suite to avoid polluting global state. Internal
    /// so the +Snapshot extension can read it.
    let userDefaults: UserDefaults
    /// AI provider profile store. Defaults to the app-scoped singleton
    /// `ProviderProfileStore.shared` so the `provider` command mutates the
    /// same state Settings → AI reads. Tests inject a per-test instance with
    /// an isolated UserDefaults suite + no-op migrator. Internal so the
    /// `+Provider` extension can reach it.
    let providerStore: ProviderProfileStore
    /// Keychain for per-profile API keys (Bug #243). Internal so the
    /// `+Provider` extension can use it. Defaults to the production
    /// service identifier; tests inject a unique identifier per test to
    /// keep keys isolated.
    let keychain: KeychainService
    /// Internal so extension files (Settle/Snapshot/Eval) can log under the
    /// same category — keeps log lines indistinguishable from pre-split.
    let log = Logger(subsystem: "com.vreader.app", category: "DebugBridge")

    init(
        persistence: PersistenceActor,
        importer: BookImporting,
        fixtureBundle: Bundle = .main,
        userDefaults: UserDefaults = .standard,
        providerStore: ProviderProfileStore = .shared,
        keychain: KeychainService = KeychainService()
    ) {
        self.persistence = persistence
        self.importer = importer
        self.fixtureBundle = fixtureBundle
        self.userDefaults = userDefaults
        self.providerStore = providerStore
        self.keychain = keychain
    }

    /// Wipe every book from the library. Idempotent — succeeds on an empty
    /// library.
    func reset() async throws {
        let books = try await persistence.fetchAllLibraryBooks()
        for book in books {
            try await persistence.deleteBook(fingerprintKey: book.fingerprintKey)
        }
        NotificationCenter.default.post(name: .debugBridgeLibraryChanged, object: nil)
        log.info("reset: removed \(books.count) book(s)")
    }

    /// Import a bundled fixture book by name. Idempotent — if a book with
    /// the same fingerprint already exists in the library, the importer's
    /// duplicate detection short-circuits and seed succeeds without creating
    /// a duplicate.
    /// Throws `DebugBridgeContextError.unknownFixture` for an unknown name,
    /// `DebugBridgeContextError.fixtureResourceMissing` if the bundle is
    /// missing the file, and propagates `ImportError` from the importer
    /// for actual import failures.
    func seed(fixture: String) async throws {
        guard let entry = DebugFixtureCatalog.find(name: fixture) else {
            throw DebugBridgeContextError.unknownFixture(fixture)
        }
        // Bug #124: the DebugFixtures Run Script in `project.yml` copies fixtures
        // into `vreader.app/DebugFixtures/<name>.<ext>`. `Bundle.url(forResource:
        // withExtension:)` only searches the bundle root, so we must point it at
        // the subdirectory explicitly. The constant matches what the Run Script
        // writes (and what `Self.fixtureBundleSubdirectory` documents) — keeping
        // the two in sync is mechanical.
        guard let url = fixtureBundle.url(
            forResource: entry.resourceName,
            withExtension: entry.resourceExtension,
            subdirectory: Self.fixtureBundleSubdirectory
        ) else {
            throw DebugBridgeContextError.fixtureResourceMissing("\(entry.resourceName).\(entry.resourceExtension)")
        }
        let result = try await importer.importFile(at: url, source: .localCopy)
        NotificationCenter.default.post(name: .debugBridgeLibraryChanged, object: nil)
        log.info("seed: imported \(entry.name, privacy: .public) → key=\(result.fingerprintKey, privacy: .public) duplicate=\(result.isDuplicate)")
    }

    /// Subdirectory under the fixture bundle that the build phase copies
    /// fixtures into. See `project.yml`'s "Copy DebugFixtures (DEBUG only)"
    /// pre-build script for the writer side. Internal so tests can use the
    /// same constant when staging fixture files. `nonisolated` so non-MainActor
    /// callers (e.g. DebugFixtureCatalogTests, which runs on a default actor)
    /// can read it without an isolation hop.
    nonisolated static let fixtureBundleSubdirectory = "DebugFixtures"

    /// Verify the book exists and post a notification for LibraryView to
    /// push it onto the navigation stack. Throws `bookNotFound` if no book
    /// in the library has the given fingerprint key.
    ///
    /// Position handling (Bug #257): when `position` is supplied it is parsed
    /// per-format via `DebugPositionResolver`, then — after the reader
    /// registers and settles — the handler posts `.readerNavigateToLocator`
    /// carrying a `Locator` built from the resolved position. This is the SAME
    /// production navigation path that TOC / search / restore use; there is no
    /// parallel DEBUG-only seek. Fully wired for TXT / MD (UTF-16 offset) and
    /// PDF (page); EPUB / AZW3 carry only a CFI (the webview navigate handlers
    /// also need an `href` / Foliate-search hook) so a CFI-only seek is a
    /// best-effort no-op for those formats — see `seekActiveReader`.
    func open(bookId: String, position: String?) async throws {
        // Step 1: book lookup — validate before any side effect (the v3 plan's
        // "validate before posting notification" rule, Round-2 audit fix #3).
        let books = try await persistence.fetchAllLibraryBooks()
        guard let book = books.first(where: { $0.fingerprintKey == bookId }) else {
            throw DebugBridgeContextError.bookNotFound(bookId)
        }

        // Step 2: position parse + format check (only when caller supplied
        // a position). Resolver returns typed DebugPosition or throws
        // invalidPositionForFormat → wrap as bridge-level invalidPosition.
        let resolvedPosition: DebugPosition?
        if let position {
            do {
                resolvedPosition = try DebugPositionResolver.resolve(position, format: book.format)
            } catch let DebugPositionResolverError.invalidPositionForFormat(format, raw, reason) {
                throw DebugBridgeContextError.invalidPosition(
                    format: format,
                    position: raw,
                    reason: reason
                )
            } catch let DebugPositionResolverError.unknownFormat(format) {
                throw DebugBridgeContextError.invalidPosition(
                    format: format,
                    position: position,
                    reason: "Unknown book format."
                )
            }
            // Note: `DebugPositionResolver.resolve` handles every BookFormat
            // directly and never throws `formatUnsupported`, so there is no
            // `catch` arm for it. Feature #54 retired the Native/Unified
            // reading mode, so there is also no longer a unified-mode seek
            // guard here — every format takes its native seek path.
        } else {
            resolvedPosition = nil
        }

        // Step 2b (Bug #257, Codex audit round 1 Medium): reject EPUB `position`
        // up front rather than open at offset 0 and silently drop the seek. The
        // EPUB navigate handler resolves the spine by `href`; a CFI-only seek
        // would no-op. Failing here (before opening) keeps the bug's original
        // "fail loudly instead of opening at the wrong place" contract. AZW3
        // takes the Foliate CFI path (which DOES seek), so only EPUB is gated.
        if case .epubCFI = resolvedPosition, let position {
            throw DebugBridgeContextError.seekUnsupportedForFormat(
                format: book.format,
                position: position
            )
        }

        // Step 3: post notification — opens the reader. Library navigation
        // observes `.debugBridgeOpenBook` and pushes the matching book.
        NotificationCenter.default.post(
            name: .debugBridgeOpenBook,
            object: nil,
            userInfo: ["fingerprintKey": bookId]
        )
        log.info("open: posted notification for \(bookId, privacy: .public)")

        // Step 4: when a position was supplied, await the reader to register,
        // wait for it to settle, then dispatch the seek (Bug #257). The seek
        // reuses the production `.readerNavigateToLocator` path — the same one
        // TOC / search / restore drive — so there is no parallel seek impl to
        // drift from the user-facing behavior.
        if let resolvedPosition {
            do {
                let probe = try await DebugReaderRegistry.shared.awaitReader(
                    fingerprintKey: bookId,
                    timeout: 10.0
                )
                log.info("open: awaitReader resolved for \(probe.fingerprintKey, privacy: .public)")
                // Wait for the reader to reach a settled render state before
                // navigating — a TXT/MD reader that hasn't laid out yet drops
                // a `scrollToOffset` write, and a webview reader can't accept
                // a CFI before its first paint. The adapter's settleStrategy
                // (EPUB/AZW3 = webview didFinish/relocate; TXT/MD/PDF = 100ms
                // layout-commit fallback) decides what "settled" means.
                try await probe.awaitSettle(timeout: 10.0)
                // `LibraryBookItem` carries only the canonical key string;
                // parse it back into a `DocumentFingerprint` for the locator.
                // `bookId == book.fingerprintKey` (the lookup matched on it),
                // so this parse only fails on a structurally malformed key,
                // which `fetchAllLibraryBooks` would not have produced.
                if let fingerprint = DocumentFingerprint(canonicalKey: bookId) {
                    seekActiveReader(to: resolvedPosition, fingerprint: fingerprint)
                } else {
                    log.error("open: could not parse fingerprint from key \(bookId, privacy: .public); seek skipped")
                }
            } catch DebugReaderRegistryError.awaitReaderTimeout(let key) {
                throw DebugBridgeContextError.openAwaitReaderTimeout(fingerprintKey: key)
            } catch DebugReaderProbeError.settleTimeout {
                // Settle timed out — surface as the await-reader timeout so the
                // harness sees a single "reader never came ready" failure shape
                // rather than two distinct error vocabularies.
                throw DebugBridgeContextError.openAwaitReaderTimeout(fingerprintKey: bookId)
            }
        }
    }

    /// Bug #257: drive the active reader to `position` by posting the
    /// production `.readerNavigateToLocator` notification with a `Locator`
    /// built from the resolved position + the opened book's fingerprint.
    ///
    /// Every reader container observes `.readerNavigateToLocator` and seeks via
    /// the field that matches its format: TXT / MD use `charOffsetUTF16`, PDF
    /// uses `page`, AZW3 (Foliate) uses `cfi` (`navigateToSearchResult(cfi:)`).
    /// EPUB is rejected before this point (`seekUnsupportedForFormat`) because
    /// its handler resolves the spine by `href`, not raw CFI — so every
    /// `DebugPosition` that reaches here maps to a field its host consumes.
    private func seekActiveReader(to position: DebugPosition, fingerprint: DocumentFingerprint) {
        guard let locator = position.locator(bookFingerprint: fingerprint) else {
            log.error("open: could not build a Locator for resolved position \(String(describing: position), privacy: .public)")
            return
        }
        NotificationCenter.default.post(
            name: .readerNavigateToLocator,
            object: locator
        )
        log.info("open: posted navigate-to-locator seek for resolved position")
    }

    /// Set reader theme + optional font size. Mutates a transient
    /// ReaderSettingsStore whose `didSet` observers persist to
    /// UserDefaults; the change takes effect when the next reader opens.
    /// (A live reader's @State store won't see the update until
    /// reopen — out of scope for v0.)
    func theme(mode: DebugCommand.ThemeMode, fontSize: Int?) async throws {
        let store = ReaderSettingsStore(defaults: userDefaults)
        // Feature #60 WI-11: `store.theme` is `ReaderThemeV2`'s 5-theme
        // palette. `ThemeMode` maps 1:1 to `ReaderThemeV2`, with `.light`
        // kept as a backward-compatible alias for `.paper` (bug #206).
        let target: ReaderThemeV2
        switch mode {
        case .dark:  target = .dark
        case .light: target = .paper
        case .paper: target = .paper
        case .sepia: target = .sepia
        case .oled:  target = .oled
        case .photo: target = .photo
        }
        if store.theme != target {
            store.theme = target
        }
        if let fontSize {
            var typography = store.typography
            typography.fontSize = Double(fontSize)
            store.typography = typography
        }
        // Bug #144: this short-lived store wrote to UserDefaults but
        // didn't propagate to the active reader's @State-owned settings
        // store. Post a notification so live readers can re-apply the
        // new theme without an app relaunch.
        var userInfo: [AnyHashable: Any] = ["mode": target.rawValue]
        if let fontSize {
            userInfo["fontSize"] = fontSize
        }
        NotificationCenter.default.post(
            name: .debugBridgeThemeChanged,
            object: nil,
            userInfo: userInfo
        )
        log.info("theme: mode=\(target.rawValue, privacy: .public) fontSize=\(fontSize.map(String.init) ?? "unchanged", privacy: .public)")
    }

    // settle/settleWithTimeout/settleTimeoutSeconds → +Settle.swift
    // snapshot/snapshotsDirectory → +Snapshot.swift
    // eval → +Eval.swift
    // provider → +Provider.swift

    /// Feature #45 WI-4c-b — drive TTS from outside the active reader.
    ///
    /// Posts `.debugBridgeTTSCommand` with `action` ∈ {"start","stop"} (the
    /// parser has already validated the alphabet). `ReaderContainerView`
    /// observes the notification when a book is open; if no reader is
    /// loaded, the URL is silently a no-op — matching the same posture as
    /// `theme` (the URL succeeds; the live view applies it if present).
    /// Errors from the synthesizer's audio session don't surface here —
    /// they show up in `snapshot.tts.state` (.idle if start failed).
    func tts(action: String) async throws {
        NotificationCenter.default.post(
            name: .debugBridgeTTSCommand,
            object: nil,
            userInfo: ["action": action]
        )
        log.info("tts: posted notification action=\(action, privacy: .public)")
    }

    /// Bug #238 — drive the in-reader search sheet from outside the chrome.
    ///
    /// Posts `.debugBridgeSearchCommand` with `query` and optional `index`
    /// (parser has already validated query non-empty and index ≥ 0 when
    /// present). `ReaderContainerView` observes the notification when a
    /// book is open; it opens the search sheet, sets `SearchViewModel.query`,
    /// and — when an index is supplied — taps result N once results arrive.
    /// If no reader is loaded, the URL is silently a no-op (the same posture
    /// as `tts` / `theme`).
    ///
    /// `index` is omitted from `userInfo` when nil so observers can
    /// distinguish "just run the query" from "run query and tap N".
    func search(query: String, index: Int?) async throws {
        var userInfo: [AnyHashable: Any] = ["query": query]
        if let index {
            userInfo["index"] = index
        }
        NotificationCenter.default.post(
            name: .debugBridgeSearchCommand,
            object: nil,
            userInfo: userInfo
        )
        log.info(
            "search: posted notification query=\(query, privacy: .public) index=\(index.map(String.init) ?? "nil", privacy: .public)"
        )
    }

    /// Bug #237 — create a highlight over a UTF-16 range in the active reader,
    /// bypassing the long-press + `SelectionPopoverView` gesture path that
    /// XCUITest cannot synthesize on iOS 26.
    ///
    /// Posts `.debugBridgeHighlightCommand` with `start` / `end` (parser has
    /// already validated `start >= 0` and `end > start`) and optional `color`
    /// (parser has already validated it as one of the four
    /// `NamedHighlightColor` rawValues when present). `ReaderContainerView`
    /// observes the notification when a book is open; it builds a `Locator`
    /// from the offsets, calls `PersistenceActor.addHighlight`, then posts
    /// `.readerHighlightsDidImport` so the per-format renderer re-paints.
    /// If no reader is loaded, the URL is silently a no-op (the same posture
    /// as `tts` / `search`).
    ///
    /// `color` is omitted from `userInfo` when nil so observers can fall
    /// back to the default ("yellow") without relying on a sentinel value.
    func highlight(startUTF16: Int, endUTF16: Int, color: String?) async throws {
        var userInfo: [AnyHashable: Any] = [
            "start": startUTF16,
            "end": endUTF16,
        ]
        if let color {
            userInfo["color"] = color
        }
        NotificationCenter.default.post(
            name: .debugBridgeHighlightCommand,
            object: nil,
            userInfo: userInfo
        )
        log.info(
            "highlight: posted notification start=\(startUTF16) end=\(endUTF16) color=\(color ?? "nil", privacy: .public)"
        )
    }
}

#endif
