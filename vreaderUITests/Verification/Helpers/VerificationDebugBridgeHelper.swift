// Purpose: Wraps vreader-debug:// URL commands sent via xcrun simctl openurl.
// Provides settle + snapshot integration for verification tests in feature #45.
//
// Key decisions:
// - All simctl calls use posix_spawn (available on all Darwin platforms) rather
//   than Foundation.Process (macOS-only) so the helper compiles for iOS SDK.
// - settleApp polls the app container for the sentinel file written by
//   RealDebugBridgeContext+Settle.swift rather than sleeping.
// - snapshotApp reads the DebugBridge JSON written by the app.
//
// @coordinates-with: RealDebugBridgeContext+Settle.swift,
//   RealDebugBridgeContext+Snapshot.swift, DebugFixtureCatalog.swift

import XCTest
import Foundation
import Darwin

/// Wraps vreader-debug:// URL commands for UITest verification flows.
/// Every method is a fire-and-observe call: the command is dispatched via
/// `xcrun simctl openurl booted`, then the caller waits on an observable
/// side effect (sentinel file or UI state change).
struct VerificationDebugBridgeHelper {
    let app: XCUIApplication

    // MARK: - Command dispatch

    /// Reset app state: clears SwiftData, wipes sandbox files.
    /// Fires `vreader-debug://reset` and returns immediately.
    func resetApp() {
        send(DebugCommand.resetURL)
    }

    /// Seed a fixture from the debug catalog into the app.
    /// Fires `vreader-debug://seed?fixture=<name>` and returns immediately.
    func seedFixture(named name: String) {
        guard let url = DebugCommand.seedURL(fixture: name) else {
            XCTFail("VerificationDebugBridgeHelper: could not construct seed URL for fixture '\(name)'")
            return
        }
        send(url)
    }

    /// Send a settle command and wait for the sentinel file.
    /// `vreader-debug://settle?token=<token>` causes the app to write
    /// `DebugBridge/ready-<token>.json` in its Caches directory.
    /// This method polls for that file up to `timeout` seconds.
    ///
    /// - Returns: `true` if the sentinel appeared within the timeout.
    @discardableResult
    func settleApp(token: String, timeout: TimeInterval = 15) -> Bool {
        guard let url = DebugCommand.settleURL(token: token) else {
            XCTFail("VerificationDebugBridgeHelper: could not construct settle URL")
            return false
        }
        send(url)

        // Poll for the app container sentinel file.
        guard let containerPath = appDataContainerPath() else {
            // Can't locate the container to poll the sentinel — brief wait
            // then signal failure so callers can decide whether to proceed.
            Thread.sleep(forTimeInterval: 2)
            return false
        }
        let sentinelPath = containerPath
            .appendingPathComponent("Library/Caches/DebugBridge")
            .appendingPathComponent("ready-\(token).json")

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: sentinelPath.path) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    /// Trigger a snapshot: fires `vreader-debug://snapshot?dest=<dest>` and
    /// returns immediately. The app writes a JSON file to its Caches/DebugBridge
    /// directory. Call `readSnapshot(dest:)` after a brief settle to read it.
    func snapshotApp(dest: String) {
        guard let url = DebugCommand.snapshotURL(dest: dest) else {
            XCTFail("VerificationDebugBridgeHelper: could not construct snapshot URL for dest '\(dest)'")
            return
        }
        send(url)
    }

    /// Fire `vreader-debug://tts?action=<action>` to drive the production
    /// AVSpeechSynthesizer without going through the readerTTSButton tap path
    /// (which fails under XCUITest because the audio session activation
    /// requirement breaks across the runner-test split — see feature #45
    /// WI-4c-b spike-0 evidence). Fire-and-observe: caller waits for
    /// `ttsControlBar` or snapshot to reflect the state change.
    func ttsAction(_ action: String) {
        guard let url = DebugCommand.ttsURL(action: action) else {
            XCTFail("VerificationDebugBridgeHelper: could not construct TTS URL for action '\(action)'")
            return
        }
        send(url)
    }

    /// Fire `vreader-debug://highlight?start=<int>&end=<int>[&color=<name>]`
    /// to create a highlight over a UTF-16 range in the active reader,
    /// bypassing the long-press + selection-popover gesture path that
    /// XCUITest cannot synthesize on iOS 26. The active reader's
    /// format-specific observer (TXT/MD: PR #1047, EPUB: PR for Bug #220 /
    /// GH #845) translates the offsets into a format-correct `Locator` +
    /// optional `AnnotationAnchor` and persists via `HighlightCoordinator`.
    /// Fire-and-observe: caller waits for the Highlights tab to reflect
    /// the new entry (the `highlightsEmptyState` element should disappear).
    /// No-op when no reader is presented.
    func highlight(start: Int, end: Int, color: String? = nil) {
        guard let url = DebugCommand.highlightURL(start: start, end: end, color: color) else {
            XCTFail(
                "VerificationDebugBridgeHelper: could not construct highlight URL for start=\(start) end=\(end)"
            )
            return
        }
        send(url)
    }

    /// Read the snapshot JSON written by `vreader-debug://snapshot?dest=<dest>`.
    /// Returns the parsed dictionary, or nil if the file is absent or malformed.
    func readSnapshot(dest: String) -> [String: Any]? {
        guard let containerPath = appDataContainerPath() else { return nil }
        let snapshotPath = containerPath
            .appendingPathComponent("Library/Caches/DebugBridge")
            .appendingPathComponent(dest)
        guard let data = try? Data(contentsOf: snapshotPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    // MARK: - Feature #42 WI-13 additions (Readium acceptance corpus)

    /// Open a book by its fingerprint key. Fires
    /// `vreader-debug://open?bookId=<key>[&position=<pos>]` and returns
    /// immediately; caller settles after.
    func open(bookId: String, position: String? = nil) {
        guard let url = DebugCommand.openURL(bookId: bookId, position: position) else {
            XCTFail("VerificationDebugBridgeHelper: could not construct open URL for '\(bookId)'")
            return
        }
        send(url)
    }

    /// Apply a reader theme + optional font size. Fires
    /// `vreader-debug://theme?mode=<mode>[&fontSize=<int>]`.
    func theme(mode: String, fontSize: Int? = nil) {
        guard let url = DebugCommand.themeURL(mode: mode, fontSize: fontSize) else {
            XCTFail("VerificationDebugBridgeHelper: could not construct theme URL for '\(mode)'")
            return
        }
        send(url)
    }

    /// Run a search + optionally tap result N. Fires
    /// `vreader-debug://search?query=<q>[&index=<n>]`.
    func search(query: String, index: Int? = nil) {
        guard let url = DebugCommand.searchURL(query: query, index: index) else {
            XCTFail("VerificationDebugBridgeHelper: could not construct search URL for '\(query)'")
            return
        }
        send(url)
    }

    /// Evaluate `js` against the active reader's JS bridge (e.g. `epub` for
    /// the Readium/legacy EPUB spine). Fires
    /// `vreader-debug://eval?bridge=<bridge>&js=<base64>`. The app writes the
    /// result to `DebugBridge/eval-<bridge>.json`; read it via `readEval`.
    /// `js` MUST be a single expression — the eval seam wraps it, so
    /// statement forms (`var`, function bodies) raise a JS syntax error.
    func eval(bridge: String, js: String) {
        let b64 = Data(js.utf8).base64EncodedString()
        var c = URLComponents()
        c.scheme = "vreader-debug"
        c.host = "eval"
        c.queryItems = [
            URLQueryItem(name: "bridge", value: bridge),
            URLQueryItem(name: "js", value: b64),
        ]
        guard let url = c.url else {
            XCTFail("VerificationDebugBridgeHelper: could not construct eval URL")
            return
        }
        send(url)
    }

    /// Read the eval result JSON written by `eval(bridge:js:)`. Returns the
    /// parsed dictionary (`result` holds the JS value, or `error` a JS
    /// exception), or nil if absent/malformed.
    func readEval(bridge: String) -> [String: Any]? {
        guard let containerPath = appDataContainerPath() else { return nil }
        let path = containerPath
            .appendingPathComponent("Library/Caches/DebugBridge")
            .appendingPathComponent("eval-\(bridge).json")
        guard let data = try? Data(contentsOf: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    // MARK: - URL construction

    enum DebugCommand {
        static var resetURL: URL { URL(string: "vreader-debug://reset")! }

        static func seedURL(fixture: String) -> URL? {
            var c = URLComponents()
            c.scheme = "vreader-debug"
            c.host = "seed"
            c.queryItems = [URLQueryItem(name: "fixture", value: fixture)]
            return c.url
        }

        static func settleURL(token: String) -> URL? {
            var c = URLComponents()
            c.scheme = "vreader-debug"
            c.host = "settle"
            c.queryItems = [URLQueryItem(name: "token", value: token)]
            return c.url
        }

        static func snapshotURL(dest: String) -> URL? {
            var c = URLComponents()
            c.scheme = "vreader-debug"
            c.host = "snapshot"
            c.queryItems = [URLQueryItem(name: "dest", value: dest)]
            return c.url
        }

        static func ttsURL(action: String) -> URL? {
            var c = URLComponents()
            c.scheme = "vreader-debug"
            c.host = "tts"
            c.queryItems = [URLQueryItem(name: "action", value: action)]
            return c.url
        }

        static func highlightURL(start: Int, end: Int, color: String?) -> URL? {
            var c = URLComponents()
            c.scheme = "vreader-debug"
            c.host = "highlight"
            var items = [
                URLQueryItem(name: "start", value: String(start)),
                URLQueryItem(name: "end", value: String(end)),
            ]
            if let color {
                items.append(URLQueryItem(name: "color", value: color))
            }
            c.queryItems = items
            return c.url
        }

        static func openURL(bookId: String, position: String?) -> URL? {
            var c = URLComponents()
            c.scheme = "vreader-debug"
            c.host = "open"
            var items = [URLQueryItem(name: "bookId", value: bookId)]
            if let position {
                items.append(URLQueryItem(name: "position", value: position))
            }
            c.queryItems = items
            return c.url
        }

        static func themeURL(mode: String, fontSize: Int?) -> URL? {
            var c = URLComponents()
            c.scheme = "vreader-debug"
            c.host = "theme"
            var items = [URLQueryItem(name: "mode", value: mode)]
            if let fontSize {
                items.append(URLQueryItem(name: "fontSize", value: String(fontSize)))
            }
            c.queryItems = items
            return c.url
        }

        static func searchURL(query: String, index: Int?) -> URL? {
            var c = URLComponents()
            c.scheme = "vreader-debug"
            c.host = "search"
            var items = [URLQueryItem(name: "query", value: query)]
            if let index {
                items.append(URLQueryItem(name: "index", value: String(index)))
            }
            c.queryItems = items
            return c.url
        }
    }

    // MARK: - Private

    private func send(_ url: URL) {
        simctl(["openurl", "booted", url.absoluteString], captureOutput: false)
    }

    /// Resolves the booted simulator's data container for the app via
    /// `xcrun simctl get_app_container booted com.vreader.app data`.
    private func appDataContainerPath() -> URL? {
        guard let output = simctl(
            ["get_app_container", "booted", "com.vreader.app", "data"],
            captureOutput: true
        ) else { return nil }
        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Invokes `xcrun simctl <arguments>` via posix_spawn.
    /// Returns captured stdout when `captureOutput` is true, nil when false or on failure.
    @discardableResult
    private func simctl(_ arguments: [String], captureOutput: Bool) -> String? {
        let xcrun = "/usr/bin/xcrun"
        let allArgs = [xcrun, "simctl"] + arguments

        // Build null-terminated C string array
        var cArgs = allArgs.map { strdup($0) }
        cArgs.append(nil)
        defer { cArgs.forEach { free($0) } }

        if captureOutput {
            // Pipe stdout to a temp file, read it back
            let tmpPath = "/tmp/vreader-simctl-\(Int(Date().timeIntervalSince1970)).txt"
            let tmpFile = tmpPath.withCString { fopen($0, "w") }
            guard let tmpFile else { return nil }
            var fileActions: posix_spawn_file_actions_t?
            posix_spawn_file_actions_init(&fileActions)
            posix_spawn_file_actions_adddup2(&fileActions, fileno(tmpFile), STDOUT_FILENO)
            posix_spawn_file_actions_addopen(&fileActions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)

            var pid: pid_t = 0
            let status = posix_spawn(&pid, xcrun, &fileActions, nil, &cArgs, nil)
            posix_spawn_file_actions_destroy(&fileActions)
            fclose(tmpFile)
            guard status == 0 else { return nil }
            var wstatus: Int32 = 0
            waitpid(pid, &wstatus, 0)
            // Manual WIFEXITED / WEXITSTATUS — Swift can't use these as C macros
            let exited = (wstatus & 0x7f) == 0
            let exitCode = (wstatus >> 8) & 0xff
            guard exited, exitCode == 0 else { return nil }
            return (try? String(contentsOfFile: tmpPath, encoding: .utf8))
        } else {
            var fileActions: posix_spawn_file_actions_t?
            posix_spawn_file_actions_init(&fileActions)
            posix_spawn_file_actions_addopen(&fileActions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0)
            posix_spawn_file_actions_addopen(&fileActions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)

            var pid: pid_t = 0
            let status = posix_spawn(&pid, xcrun, &fileActions, nil, &cArgs, nil)
            posix_spawn_file_actions_destroy(&fileActions)
            guard status == 0 else { return nil }
            var wstatus: Int32 = 0
            waitpid(pid, &wstatus, 0)
            return nil
        }
    }
}
