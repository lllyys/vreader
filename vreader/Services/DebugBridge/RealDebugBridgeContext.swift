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
    /// Feature #49 WI-7b: opening at a specific position is only supported
    /// in native-mode for now. Unified-renderer mode (TXT/MD/EPUB through
    /// the unified text renderer) doesn't have a stable seek API yet.
    case openPositionUnsupportedInUnifiedMode(format: String)
    /// Feature #49 WI-7b: awaitReader timed out waiting for a reader matching
    /// `fingerprintKey` to register after the open notification was posted.
    case openAwaitReaderTimeout(fingerprintKey: String)
}

/// Production DebugBridgeContext. Each handler is a thin wrapper over
/// existing app services so behavior matches what the user-facing UI does
/// (no parallel implementations to drift). Handlers added incrementally
/// across WI-5; un-implemented ones throw.
@MainActor
final class RealDebugBridgeContext: DebugBridgeContext {
    private let persistence: PersistenceActor
    private let importer: BookImporting
    /// Bundle that holds DEBUG fixture resources. Defaults to `Bundle.main`;
    /// tests inject a custom bundle so they don't depend on app installation.
    private let fixtureBundle: Bundle
    /// UserDefaults suite that backs reader settings. Defaults to `.standard`;
    /// tests inject a unique suite to avoid polluting global state.
    private let userDefaults: UserDefaults
    private let log = Logger(subsystem: "com.vreader.app", category: "DebugBridge")

    init(
        persistence: PersistenceActor,
        importer: BookImporting,
        fixtureBundle: Bundle = .main,
        userDefaults: UserDefaults = .standard
    ) {
        self.persistence = persistence
        self.importer = importer
        self.fixtureBundle = fixtureBundle
        self.userDefaults = userDefaults
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

    // MARK: - Stubs (filled in by later WI-5 commits)

    private func notImplemented(_ command: String) -> Error {
        log.notice("\(command, privacy: .public): not yet implemented")
        return DebugBridgeContextError.notImplemented(command: command)
    }

    /// Verify the book exists and post a notification for LibraryView to
    /// push it onto the navigation stack. Throws `bookNotFound` if no book
    /// in the library has the given fingerprint key.
    ///
    /// Position handling: v0 only supports nil position. A non-nil position
    /// throws `notImplemented` rather than silently ignoring the parameter,
    /// so repros that depend on opening at a specific location fail loudly
    /// instead of opening at the wrong place. v1 will resolve position to
    /// a Locator and pass it to the reader.
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
            } catch let DebugPositionResolverError.formatUnsupported(format) {
                throw DebugBridgeContextError.openPositionUnsupportedInUnifiedMode(format: format)
            }

            // Step 3: unified-mode guard (per v3 plan Round-2 audit fix #3).
            // Native-mode has reader-host seek paths; unified-mode (the unified
            // text renderer that may consolidate TXT/MD/EPUB) doesn't have a
            // stable seek API. Reject early so verification flows fail loudly.
            let store = ReaderSettingsStore(defaults: userDefaults)
            if store.readingMode == .unified,
               let format = BookFormat(rawValue: book.format) {
                let caps = FormatCapabilities.capabilities(for: format)
                // Only formats whose unified-mode path supports seek are exempt.
                // Today: PDF stays native-only; TXT/MD/EPUB unified mode lacks
                // seek; AZW3 only renders in native (Foliate spike).
                _ = caps  // capability table currently has no seek bit; gate by mode alone.
                throw DebugBridgeContextError.openPositionUnsupportedInUnifiedMode(format: book.format)
            }
        } else {
            resolvedPosition = nil
        }

        // Step 4: post notification — opens the reader. Library navigation
        // observes `.debugBridgeOpenBook` and pushes the matching book.
        NotificationCenter.default.post(
            name: .debugBridgeOpenBook,
            object: nil,
            userInfo: ["fingerprintKey": bookId]
        )
        log.info("open: posted notification for \(bookId, privacy: .public)")

        // Step 5: when a position was supplied, await the reader to register
        // and then dispatch the seek. The actual seek implementation lives in
        // per-format hosts (feature #50 WI-7b's host-side seekStrategy).
        // For now, we just resolve the await — host-side seek wiring is a
        // follow-up that consumes `resolvedPosition`.
        if resolvedPosition != nil {
            do {
                let probe = try await DebugReaderRegistry.shared.awaitReader(
                    fingerprintKey: bookId,
                    timeout: 10.0
                )
                log.info("open: awaitReader resolved for \(probe.fingerprintKey, privacy: .public)")
                // Seek dispatch deferred to feature #50 (per-format hosts populate
                // a seek strategy on the probe; the bridge calls it here).
            } catch DebugReaderRegistryError.awaitReaderTimeout(let key) {
                throw DebugBridgeContextError.openAwaitReaderTimeout(fingerprintKey: key)
            }
        }
    }

    /// Set reader theme + optional font size. Mutates a transient
    /// ReaderSettingsStore whose `didSet` observers persist to
    /// UserDefaults; the change takes effect when the next reader opens.
    /// (A live reader's @State store won't see the update until
    /// reopen — out of scope for v0.)
    func theme(mode: DebugCommand.ThemeMode, fontSize: Int?) async throws {
        let store = ReaderSettingsStore(defaults: userDefaults)
        let target: ReaderTheme = (mode == .dark) ? .dark : .light
        if store.theme != target {
            store.theme = target
        }
        if let fontSize {
            var typography = store.typography
            typography.fontSize = Double(fontSize)
            store.typography = typography
        }
        log.info("theme: mode=\(target.rawValue, privacy: .public) fontSize=\(fontSize.map(String.init) ?? "unchanged", privacy: .public)")
    }

    /// Wait for the active reader to settle, then write
    /// `Caches/DebugBridge/ready-<token>.json` with the current state.
    /// On settle timeout OR when no reader is presented, writes a sentinel
    /// file with `error: <reason>` rather than throwing — the host-side
    /// waiter always has a file to inspect after its own timeout expires.
    ///
    /// The timeout is enforced by the bridge, not just the probe — a
    /// probe that hangs instead of throwing settleTimeout still produces
    /// the sentinel. Throws only on infrastructure failures (file write).
    func settle(token: String) async throws {
        try await settleWithTimeout(token: token, timeoutSeconds: Self.settleTimeoutSeconds)
    }

    /// Internal test seam — same logic as `settle` but accepts a custom
    /// timeout so tests can exercise the race without waiting 30s.
    func settleWithTimeout(token: String, timeoutSeconds: TimeInterval) async throws {
        // Bug #125: when no reader is registered we still write a sentinel —
        // the verification harness has no way to distinguish "URL accepted but
        // hung" from "URL accepted but no probe to settle on" without a file
        // on disk. Mirror eval's noActiveReader pattern: write the sentinel
        // with error="no active reader" and return without throwing.
        guard let probe = DebugReaderRegistry.shared.current else {
            try writeReadySentinel(
                token: token,
                probe: nil,
                error: "no active reader"
            )
            log.error("settle: ready-\(token, privacy: .public).json with error=no active reader")
            return
        }
        var settleError: String?
        do {
            try await withTimeout(seconds: timeoutSeconds) {
                try await probe.awaitSettle(timeout: timeoutSeconds)
            }
        } catch DebugReaderProbeError.settleTimeout {
            settleError = "settle timeout"
        } catch SettleTimeoutSentinel.timedOut {
            settleError = "settle timeout"
        } catch {
            settleError = String(describing: error)
        }

        try writeReadySentinel(token: token, probe: probe, error: settleError)
        if let err = settleError {
            log.error("settle: ready-\(token, privacy: .public).json with error=\(err, privacy: .public)")
        } else {
            log.info("settle: wrote ready-\(token, privacy: .public).json")
        }
    }

    /// Writes the `ready-<token>.json` sentinel. Probe-shaped fields
    /// (`fingerprintKey`, `format`, `position`) are only included when a
    /// probe was registered — for the no-active-reader case the keys are
    /// omitted so they read as `null` in JSON, matching `DebugSnapshot`'s
    /// "field is partial / unavailable" convention. When `error` is
    /// present, `phase: "unknown"` is also set per the existing
    /// timeout-path shape.
    private func writeReadySentinel(
        token: String,
        probe: DebugReaderProbe?,
        error: String?
    ) throws {
        var payload: [String: Any] = [
            "token": token,
            "ts": ISO8601DateFormatter().string(from: Date())
        ]
        if let probe {
            payload["fingerprintKey"] = probe.fingerprintKey
            payload["format"] = probe.format
            payload["position"] = probe.currentPositionString as Any
        }
        if let error {
            payload["error"] = error
            payload["phase"] = "unknown"  // probe doesn't yet report a render phase
        }
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
        let outputURL = try Self.snapshotsDirectory()
            .appendingPathComponent("ready-\(token).json")
        try data.write(to: outputURL, options: .atomic)
    }

    /// Race a MainActor-isolated operation against a timer; whichever
    /// finishes first wins, the loser is cancelled. Used to bound
    /// settle's awaitSettle even if a probe hangs without honoring its
    /// own timeout parameter. MainActor-isolated by construction so the
    /// operation can capture `@MainActor` references (the probe).
    private func withTimeout(
        seconds: TimeInterval,
        operation: @escaping @MainActor () async throws -> Void
    ) async throws {
        let work = Task { @MainActor in try await operation() }
        let timer = Task {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            work.cancel()
        }
        defer { timer.cancel() }
        do {
            try await work.value
        } catch is CancellationError {
            throw SettleTimeoutSentinel.timedOut
        }
    }

    /// Internal sentinel — leaks to caller only as `settleError = "settle timeout"`.
    private enum SettleTimeoutSentinel: Error {
        case timedOut
    }

    /// Default settle timeout. Not URL-configurable in v0; harness can
    /// shorten by triggering its own timeout if needed.
    static let settleTimeoutSeconds: TimeInterval = 30.0

    /// Build a state snapshot and write the JSON to
    /// `Library/Caches/DebugBridge/{dest}` in the app container.
    /// `dest` is a parser-validated basename (`[A-Za-z0-9._-]{1,64}`,
    /// no slashes, no dot-only sequences). Path traversal is structurally
    /// impossible.
    ///
    /// Reader-derived fields (currentBookId, format, position) are
    /// populated from `DebugReaderRegistry.shared.current` when a reader
    /// is presented. Without an active reader they remain nil and stay
    /// in the `partial` array. `selection` always stays in `partial` —
    /// selection probe lands when readers expose their selection state.
    func snapshot(dest: String, lastErrorMessage: String?) async throws {
        let store = ReaderSettingsStore(defaults: userDefaults)
        let highlightCount = try await totalHighlightCount()
        let probe = DebugReaderRegistry.shared.current

        // Build `partial` dynamically. A reader-derived field stays
        // partial when the probe can't supply a value:
        // - currentBookId/format require a probe at all
        // - position additionally requires the probe to have wired a
        //   positionProvider (default adapter has none)
        // - selection is always partial in v0
        var partial: [String] = ["selection"]
        if probe == nil {
            partial.append(contentsOf: ["currentBookId", "format", "position"])
        } else if probe?.currentPositionString == nil {
            partial.append("position")
        }

        let snap = DebugSnapshot(
            schemaVersion: DebugSnapshot.currentSchemaVersion,
            ts: ISO8601DateFormatter().string(from: Date()),
            currentBookId: probe?.fingerprintKey,
            format: probe?.format,
            position: probe?.currentPositionString,
            theme: themeName(from: store.theme),
            fontSize: Int(store.typography.fontSize),
            selection: nil,
            highlightCount: highlightCount,
            renderPhase: "idle",
            lastError: lastErrorMessage,
            partial: partial
        )

        let data = try DebugSnapshot.encoder.encode(snap)
        let outputURL = try Self.snapshotsDirectory().appendingPathComponent(dest)
        try data.write(to: outputURL, options: .atomic)
        log.info("snapshot: wrote \(data.count) bytes to \(dest, privacy: .public)")
    }

    /// Output directory in the app container — readable from the host via
    /// `xcrun simctl get_app_container <udid> com.vreader.app data`.
    /// Created on first call; idempotent.
    static func snapshotsDirectory() throws -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DebugBridge", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func themeName(from theme: ReaderTheme) -> String {
        switch theme {
        case .light: return "light"
        case .sepia: return "sepia"
        case .dark: return "dark"
        }
    }

    private func totalHighlightCount() async throws -> Int {
        try await persistence.countAllHighlights()
    }

    /// Evaluate JS in the active reader's webview and ALWAYS write
    /// `Caches/DebugBridge/eval-<bridge>.json` — happy path with `result`
    /// (raw JSON value), error path with `error` string. Throws only on
    /// infrastructure failures (filesystem write); failure modes the
    /// caller cares about (no reader, unsupported format, JS exception)
    /// land in the JSON file so the host-side waiter has output to read.
    func eval(bridge: String, js: String) async throws {
        let probe = DebugReaderRegistry.shared.current
        let outputURL = try Self.snapshotsDirectory()
            .appendingPathComponent("eval-\(bridge).json")

        guard let probe else {
            try Self.writeEvalError(
                outputURL: outputURL,
                bridge: bridge,
                fingerprintKey: nil,
                format: nil,
                error: "no active reader"
            )
            log.error("eval: noActiveReader → eval-\(bridge, privacy: .public).json")
            return
        }

        do {
            let resultData = try await probe.evaluateJavaScript(js)
            // Splice raw JSON value into the result field — JSONSerialization
            // accepts pre-encoded JSON via re-decoding to its native type.
            let resultValue = try JSONSerialization.jsonObject(
                with: resultData,
                options: [.fragmentsAllowed]
            )
            let payload: [String: Any] = [
                "bridge": bridge,
                "ts": ISO8601DateFormatter().string(from: Date()),
                "fingerprintKey": probe.fingerprintKey,
                "format": probe.format,
                "result": resultValue
            ]
            let out = try JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
            )
            try out.write(to: outputURL, options: .atomic)
            log.info("eval: wrote eval-\(bridge, privacy: .public).json")
        } catch DebugReaderProbeError.evalUnsupported(let fmt) {
            try Self.writeEvalError(
                outputURL: outputURL,
                bridge: bridge,
                fingerprintKey: probe.fingerprintKey,
                format: probe.format,
                error: "eval unsupported for format: \(fmt)"
            )
            log.error("eval: unsupported format \(fmt, privacy: .public)")
        } catch {
            try Self.writeEvalError(
                outputURL: outputURL,
                bridge: bridge,
                fingerprintKey: probe.fingerprintKey,
                format: probe.format,
                error: String(describing: error)
            )
            log.error("eval: failed: \(String(describing: error), privacy: .public)")
        }
    }

    private static func writeEvalError(
        outputURL: URL,
        bridge: String,
        fingerprintKey: String?,
        format: String?,
        error: String
    ) throws {
        var payload: [String: Any] = [
            "bridge": bridge,
            "ts": ISO8601DateFormatter().string(from: Date()),
            "error": error
        ]
        if let k = fingerprintKey { payload["fingerprintKey"] = k }
        if let f = format { payload["format"] = f }
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: outputURL, options: .atomic)
    }
}

#endif
