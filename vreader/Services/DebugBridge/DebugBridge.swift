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
        case .eval(let bridge, let js):
            try await context.eval(bridge: bridge, js: js)
        case .tts(let action):
            try await context.tts(action: action)
        case .search(let query, let index):
            try await context.search(query: query, index: index)
        }
    }
}

#endif
