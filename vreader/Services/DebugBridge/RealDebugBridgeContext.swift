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
        guard let url = fixtureBundle.url(
            forResource: entry.resourceName,
            withExtension: entry.resourceExtension
        ) else {
            throw DebugBridgeContextError.fixtureResourceMissing("\(entry.resourceName).\(entry.resourceExtension)")
        }
        let result = try await importer.importFile(at: url, source: .localCopy)
        log.info("seed: imported \(entry.name, privacy: .public) → key=\(result.fingerprintKey, privacy: .public) duplicate=\(result.isDuplicate)")
    }

    // MARK: - Stubs (filled in by later WI-5 commits)

    private func notImplemented(_ command: String) -> Error {
        log.notice("\(command, privacy: .public): not yet implemented")
        return DebugBridgeContextError.notImplemented(command: command)
    }

    func open(bookId: String, position: String?) async throws {
        throw notImplemented("open")
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

    func settle(token: String) async throws {
        throw notImplemented("settle")
    }

    /// Build a state snapshot and write the JSON to
    /// `Library/Caches/DebugBridge/{dest}` in the app container.
    /// `dest` is a parser-validated basename (`[A-Za-z0-9._-]{1,64}`,
    /// no slashes, no dot-only sequences). Path traversal is structurally
    /// impossible.
    ///
    /// V0 fields filled in: ts, theme, fontSize, highlightCount, renderPhase
    /// ("idle"), lastError, schemaVersion, partial.
    /// Reader-derived fields (currentBookId, format, position, selection)
    /// are listed in `partial` so consumers know nil ≠ "no value" — they
    /// land when the active-reader registry ships in a later WI-5 commit.
    func snapshot(dest: String, lastErrorMessage: String?) async throws {
        let store = ReaderSettingsStore(defaults: userDefaults)
        let highlightCount = try await totalHighlightCount()

        let snap = DebugSnapshot(
            schemaVersion: DebugSnapshot.currentSchemaVersion,
            ts: ISO8601DateFormatter().string(from: Date()),
            currentBookId: nil,
            format: nil,
            position: nil,
            theme: themeName(from: store.theme),
            fontSize: Int(store.typography.fontSize),
            selection: nil,
            highlightCount: highlightCount,
            renderPhase: "idle",
            lastError: lastErrorMessage,
            partial: ["currentBookId", "format", "position", "selection"]
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

    func eval(bridge: String, js: String) async throws {
        throw notImplemented("eval")
    }
}

#endif
