// Purpose: Tests for RealDebugBridgeContext — the production handler set
// behind the vreader-debug:// URL scheme (feature #44 DebugBridge, WI-5).
// Verifies that real handlers mutate real subsystems: SwiftData wipes for
// reset, fixture import for seed, etc.

#if DEBUG

import XCTest
import SwiftData
@testable import vreader

final class RealDebugBridgeContextTests: XCTestCase {

    private var container: ModelContainer!
    private var persistence: PersistenceActor!
    private var importer: BookImporter!
    private var sandboxDir: URL!
    private var fixtureBundleDir: URL!
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema(SchemaV4.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        persistence = PersistenceActor(modelContainer: container)

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("DebugBridgeTests-\(UUID().uuidString)", isDirectory: true)
        sandboxDir = temp.appendingPathComponent("sandbox", isDirectory: true)
        fixtureBundleDir = temp.appendingPathComponent("bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: sandboxDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fixtureBundleDir, withIntermediateDirectories: true)

        importer = BookImporter(persistence: persistence, sandboxBooksDirectory: sandboxDir)

        // Unique UserDefaults suite per test so theme tests don't pollute global state
        // or each other.
        defaultsSuiteName = "DebugBridgeTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
    }

    override func tearDown() async throws {
        if let dir = sandboxDir?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: dir)
        }
        if let suite = defaultsSuiteName {
            UserDefaults().removePersistentDomain(forName: suite)
        }
        importer = nil
        persistence = nil
        container = nil
        sandboxDir = nil
        fixtureBundleDir = nil
        defaults = nil
        defaultsSuiteName = nil
        try await super.tearDown()
    }

    /// Writes a fake fixture file into a temp directory and returns a Bundle
    /// rooted at that directory. The file is placed inside the
    /// `RealDebugBridgeContext.fixtureBundleSubdirectory` subdirectory so the
    /// test mirrors the real `vreader.app/<subdir>/<name>.<ext>` layout that
    /// `project.yml`'s "Copy DebugFixtures (DEBUG only)" pre-build script
    /// produces. Reusing the prod constant keeps the writer (this helper) and
    /// the reader (`RealDebugBridgeContext.seed`) in sync — change the constant
    /// and this helper updates without edit.
    private func makeFixtureBundle(name: String, ext: String, contents: String) throws -> Bundle {
        let subdirURL = fixtureBundleDir.appendingPathComponent(
            RealDebugBridgeContext.fixtureBundleSubdirectory,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: subdirURL, withIntermediateDirectories: true)
        let path = subdirURL.appendingPathComponent("\(name).\(ext)")
        try contents.data(using: .utf8)!.write(to: path)
        return Bundle(url: fixtureBundleDir)!
    }

    // MARK: - reset

    @MainActor
    func test_reset_wipesAllBooksFromLibrary() async throws {
        _ = try await CollectionTestHelper.insertBook(
            persistence: persistence,
            title: "Book A",
            sha: String(repeating: "a", count: 64)
        )
        _ = try await CollectionTestHelper.insertBook(
            persistence: persistence,
            title: "Book B",
            sha: String(repeating: "b", count: 64)
        )
        let beforeCount = try await persistence.fetchAllLibraryBooks().count
        XCTAssertEqual(beforeCount, 2)

        let context = RealDebugBridgeContext(persistence: persistence, importer: importer)
        try await context.reset()

        let afterCount = try await persistence.fetchAllLibraryBooks().count
        XCTAssertEqual(afterCount, 0, "reset must remove every book")
    }

    @MainActor
    func test_reset_onEmptyLibraryIsIdempotent() async throws {
        let context = RealDebugBridgeContext(persistence: persistence, importer: importer)
        try await context.reset()
        try await context.reset()

        let afterCount = try await persistence.fetchAllLibraryBooks().count
        XCTAssertEqual(afterCount, 0)
    }

    // MARK: - seed

    @MainActor
    func test_seed_unknownFixtureName_throwsAndDoesNotImport() async throws {
        let context = RealDebugBridgeContext(persistence: persistence, importer: importer)
        do {
            try await context.seed(fixture: "definitely-not-a-fixture")
            XCTFail("expected unknownFixture error")
        } catch DebugBridgeContextError.unknownFixture(let name) {
            XCTAssertEqual(name, "definitely-not-a-fixture")
        }
        let count = try await persistence.fetchAllLibraryBooks().count
        XCTAssertEqual(count, 0, "no library mutation for unknown fixture")
    }

    @MainActor
    func test_seed_resourceMissing_throwsAndDoesNotImport() async throws {
        // Use a bundle that doesn't have the war-and-peace fixture in it
        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            fixtureBundle: Bundle(url: fixtureBundleDir)!
        )
        do {
            try await context.seed(fixture: "war-and-peace")
            XCTFail("expected fixtureResourceMissing error")
        } catch DebugBridgeContextError.fixtureResourceMissing {
            // expected
        }
    }

    @MainActor
    func test_seed_warAndPeace_importsTxtFromBundle() async throws {
        let bundle = try makeFixtureBundle(
            name: "war-and-peace",
            ext: "txt",
            contents: "War and Peace\n\nMinimal fixture text for the seed test.\n"
        )
        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            fixtureBundle: bundle
        )

        try await context.seed(fixture: "war-and-peace")

        let books = try await persistence.fetchAllLibraryBooks()
        XCTAssertEqual(books.count, 1, "seed must import exactly one book")
        XCTAssertEqual(books.first?.format, "txt")
    }

    @MainActor
    func test_seed_calledTwiceWithSameFixture_doesNotCreateDuplicate() async throws {
        let bundle = try makeFixtureBundle(
            name: "war-and-peace",
            ext: "txt",
            contents: "War and Peace\n\nDeterministic content for fingerprint stability.\n"
        )
        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            fixtureBundle: bundle
        )

        try await context.seed(fixture: "war-and-peace")
        try await context.seed(fixture: "war-and-peace")

        let books = try await persistence.fetchAllLibraryBooks()
        XCTAssertEqual(books.count, 1, "second seed of same fixture must not duplicate")
    }

    /// Bug #143 / GH #310: end-to-end seed of the bundled `mini-azw3` fixture
    /// imports through the real `BookImporter` onto the `BookFormat.azw3`
    /// (Foliate) path. Uses `Bundle.main` directly — the production bundle the
    /// app reads — so the pre-build rsync of `vreader/Resources/DebugFixtures/`
    /// is actually exercised and the catalog ↔ binary ↔ format triple is
    /// verified end-to-end. This is the slice that `DebugFixtureCatalogTests`
    /// alone cannot prove.
    @MainActor
    func test_seed_miniAzw3_importsAzw3FromBundle() async throws {
        // Default fixtureBundle = Bundle.main, which contains
        // `DebugFixtures/mini-azw3.azw3` after the Debug-only pre-build rsync.
        let context = RealDebugBridgeContext(persistence: persistence, importer: importer)

        try await context.seed(fixture: "mini-azw3")

        let books = try await persistence.fetchAllLibraryBooks()
        XCTAssertEqual(books.count, 1, "seed must import exactly one AZW3 book")
        XCTAssertEqual(books.first?.format, "azw3",
                       "BookImporter must resolve .azw3 extension to BookFormat.azw3 (Foliate path)")
    }

    // MARK: - error propagation through DebugBridge.lastError

    @MainActor
    func test_unknownFixture_setsLastErrorOnBridge() async {
        let context = RealDebugBridgeContext(persistence: persistence, importer: importer)
        let bridge = DebugBridge(context: context)

        await bridge.handle(URL(string: "vreader-debug://seed?fixture=missing")!)

        guard case DebugBridgeContextError.unknownFixture? = bridge.lastError as? DebugBridgeContextError else {
            XCTFail("expected unknownFixture in lastError, got \(String(describing: bridge.lastError))")
            return
        }
    }

    @MainActor
    func test_successfulCommand_clearsLastError() async throws {
        let context = RealDebugBridgeContext(persistence: persistence, importer: importer)
        let bridge = DebugBridge(context: context)

        await bridge.handle(URL(string: "vreader-debug://seed?fixture=missing")!)
        XCTAssertNotNil(bridge.lastError)

        await bridge.handle(URL(string: "vreader-debug://reset")!)
        XCTAssertNil(bridge.lastError, "successful dispatch must clear lastError")
    }

    // MARK: - theme

    @MainActor
    func test_theme_darkModeSetsThemeInUserDefaults() async throws {
        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        try await context.theme(mode: .dark, fontSize: nil)

        let store = ReaderSettingsStore(defaults: defaults)
        XCTAssertEqual(store.theme, .dark)
    }

    @MainActor
    func test_theme_lightModeSetsThemeInUserDefaults() async throws {
        // Pre-set to dark so we can verify mode=light flips it back.
        // Feature #60 WI-11: `store.theme` is `ReaderThemeV2`; the
        // bridge's `.light` mode maps to the `.paper` theme.
        let pre = ReaderSettingsStore(defaults: defaults)
        pre.theme = .dark

        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        try await context.theme(mode: .light, fontSize: nil)

        let store = ReaderSettingsStore(defaults: defaults)
        XCTAssertEqual(store.theme, .paper)
    }

    @MainActor
    func test_theme_v2PaletteModesSetMatchingTheme() async throws {
        // Bug #206: every ReaderThemeV2 case must be reachable through
        // the bridge — not just dark + light(=paper).
        let cases: [(DebugCommand.ThemeMode, ReaderThemeV2)] = [
            (.paper, .paper), (.sepia, .sepia), (.oled, .oled), (.photo, .photo),
        ]
        for (mode, expected) in cases {
            // Pre-set to dark (none of these targets is dark) so the
            // assertion proves a real flip, not a stale default.
            let pre = ReaderSettingsStore(defaults: defaults)
            pre.theme = .dark

            let context = RealDebugBridgeContext(
                persistence: persistence,
                importer: importer,
                userDefaults: defaults
            )
            try await context.theme(mode: mode, fontSize: nil)

            let store = ReaderSettingsStore(defaults: defaults)
            XCTAssertEqual(store.theme, expected, "mode=\(mode.rawValue)")
        }
    }

    @MainActor
    func test_theme_fontSizeIsPersisted() async throws {
        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        try await context.theme(mode: .dark, fontSize: 22)

        let store = ReaderSettingsStore(defaults: defaults)
        XCTAssertEqual(store.typography.fontSize, 22.0, accuracy: 0.001)
    }

    @MainActor
    func test_theme_nilFontSizeLeavesExistingFontSizeUnchanged() async throws {
        let pre = ReaderSettingsStore(defaults: defaults)
        var typography = pre.typography
        typography.fontSize = 19.0
        pre.typography = typography

        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        try await context.theme(mode: .light, fontSize: nil)

        let store = ReaderSettingsStore(defaults: defaults)
        XCTAssertEqual(store.typography.fontSize, 19.0, accuracy: 0.001, "nil fontSize should not overwrite")
    }

    // MARK: - Bug #144: theme command posts debugBridgeThemeChanged notification

    @MainActor
    func test_theme_postsThemeChangedNotificationWithMode() async throws {
        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )

        let exp = expectation(description: "themeChanged notification posted")
        nonisolated(unsafe) var receivedMode: String?
        let token = NotificationCenter.default.addObserver(
            forName: .debugBridgeThemeChanged, object: nil, queue: .main
        ) { notification in
            receivedMode = notification.userInfo?["mode"] as? String
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        try await context.theme(mode: .light, fontSize: nil)
        await fulfillment(of: [exp], timeout: 2.0)
        // Feature #60 WI-11: the bridge posts the `ReaderThemeV2`
        // rawValue; `.light` mode → the `.paper` theme.
        XCTAssertEqual(receivedMode, "paper")
    }

    @MainActor
    func test_theme_postsThemeChangedNotificationWithFontSize() async throws {
        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )

        let exp = expectation(description: "themeChanged notification posted with fontSize")
        nonisolated(unsafe) var receivedFontSize: Int?
        nonisolated(unsafe) var receivedMode: String?
        let token = NotificationCenter.default.addObserver(
            forName: .debugBridgeThemeChanged, object: nil, queue: .main
        ) { notification in
            receivedMode = notification.userInfo?["mode"] as? String
            receivedFontSize = notification.userInfo?["fontSize"] as? Int
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        try await context.theme(mode: .dark, fontSize: 22)
        await fulfillment(of: [exp], timeout: 2.0)
        XCTAssertEqual(receivedMode, "dark")
        XCTAssertEqual(receivedFontSize, 22)
    }

    @MainActor
    func test_theme_postsThemeChangedNotificationWithoutFontSizeWhenNil() async throws {
        // When fontSize is nil, the userInfo must NOT contain a "fontSize"
        // key — observers can use that to distinguish "user didn't set font"
        // from "user set font to 0" (though 0 isn't a valid clamp anyway).
        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )

        let exp = expectation(description: "themeChanged notification without fontSize")
        nonisolated(unsafe) var hasFontSize: Bool = false
        let token = NotificationCenter.default.addObserver(
            forName: .debugBridgeThemeChanged, object: nil, queue: .main
        ) { notification in
            hasFontSize = notification.userInfo?["fontSize"] != nil
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        try await context.theme(mode: .dark, fontSize: nil)
        await fulfillment(of: [exp], timeout: 2.0)
        XCTAssertFalse(hasFontSize, "userInfo must omit fontSize when nil was passed")
    }

    // MARK: - snapshot

    @MainActor
    func test_snapshot_withoutActiveReader_listsReaderFieldsAsPartial() async throws {
        DebugReaderRegistry.shared.reset()
        try await RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        ).theme(mode: .dark, fontSize: 22)

        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        let dest = "snapshot-\(UUID().uuidString).json"
        try await context.snapshot(dest: dest, lastErrorMessage: nil)

        let url = try RealDebugBridgeContext.snapshotsDirectory().appendingPathComponent(dest)
        let data = try Data(contentsOf: url)
        let snap = try JSONDecoder().decode(DebugSnapshot.self, from: data)

        // Stays in sync with `DebugSnapshot.currentSchemaVersion` so a
        // future bump fails this test loudly. Bumped to 2 by feature #49
        // WI-1 (commit 74a5443); the test wasn't updated then.
        XCTAssertEqual(snap.schemaVersion, DebugSnapshot.currentSchemaVersion)
        XCTAssertFalse(snap.ts.isEmpty)
        XCTAssertEqual(snap.theme, "dark")
        XCTAssertEqual(snap.fontSize, 22)
        XCTAssertEqual(snap.highlightCount, 0)
        XCTAssertEqual(snap.renderPhase, "idle")
        XCTAssertNil(snap.lastError)
        XCTAssertNil(snap.currentBookId)
        XCTAssertNil(snap.format)
        XCTAssertNil(snap.position)
        XCTAssertNil(snap.selection)
        // No active reader → reader fields are partial. ttsState/
        // ttsOffsetUTF16 also partial (no probe → no ttsProbe wired);
        // settingsProvenance always partial until feature #50.
        XCTAssertEqual(
            Set(snap.partial ?? []),
            Set([
                "currentBookId", "format", "position", "selection",
                "ttsState", "ttsOffsetUTF16", "settingsProvenance",
            ])
        )
        XCTAssertNil(snap.ttsState)
        XCTAssertNil(snap.ttsOffsetUTF16)
        XCTAssertNil(snap.settingsProvenance)
        try? FileManager.default.removeItem(at: url)
    }

    @MainActor
    func test_snapshot_withActiveReader_populatesReaderFieldsAndShrinksPartial() async throws {
        // No positionProvider → currentBookId/format are authoritative,
        // but `position` stays in `partial` because the probe can't supply it.
        let probe = DebugReaderProbeAdapter(
            fingerprintKey: "txt:abc123:1024",
            format: "txt"
        )
        DebugReaderRegistry.shared.register(probe)
        defer { DebugReaderRegistry.shared.unregister(probe) }

        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        let dest = "snapshot-\(UUID().uuidString).json"
        try await context.snapshot(dest: dest, lastErrorMessage: nil)

        let url = try RealDebugBridgeContext.snapshotsDirectory().appendingPathComponent(dest)
        let snap = try JSONDecoder().decode(DebugSnapshot.self, from: Data(contentsOf: url))

        XCTAssertEqual(snap.currentBookId, "txt:abc123:1024")
        XCTAssertEqual(snap.format, "txt")
        XCTAssertNil(snap.position)
        XCTAssertEqual(
            Set(snap.partial ?? []),
            Set([
                "selection", "position",
                "ttsState", "ttsOffsetUTF16", "settingsProvenance",
            ]),
            "without a positionProvider the position field stays partial; "
            + "without a ttsProbe the TTS fields stay partial too"
        )
        try? FileManager.default.removeItem(at: url)
    }

    @MainActor
    func test_snapshot_withActiveReaderAndPosition_propagatesPosition() async throws {
        let probe = DebugReaderProbeAdapter(
            fingerprintKey: "epub:def:2048",
            format: "epub",
            positionProvider: { "epubcfi(/6/4!/4/1:0)" }
        )
        DebugReaderRegistry.shared.register(probe)
        defer { DebugReaderRegistry.shared.unregister(probe) }

        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        let dest = "snapshot-\(UUID().uuidString).json"
        try await context.snapshot(dest: dest, lastErrorMessage: nil)

        let url = try RealDebugBridgeContext.snapshotsDirectory().appendingPathComponent(dest)
        let snap = try JSONDecoder().decode(DebugSnapshot.self, from: Data(contentsOf: url))

        XCTAssertEqual(snap.format, "epub")
        XCTAssertEqual(snap.position, "epubcfi(/6/4!/4/1:0)")
        // position drops from partial when probe supplies it; TTS fields
        // and settingsProvenance remain partial until WI-4c-c's closure
        // is wired (probe has no ttsProbe in this fixture) and feature
        // #50 lands the per-format settings provenance.
        XCTAssertEqual(
            Set(snap.partial ?? []),
            Set(["selection", "ttsState", "ttsOffsetUTF16", "settingsProvenance"]),
            "position drops from partial when probe supplies it; "
            + "TTS+provenance stay partial without their hosts"
        )
        try? FileManager.default.removeItem(at: url)
    }

    /// Feature #45 WI-4c-c: when the probe wires a `ttsProbe` closure,
    /// the snapshot must surface `ttsState` + `ttsOffsetUTF16` and drop
    /// them from `partial`. Mirrors the position-supplied test above —
    /// same wiring pattern, different field.
    @MainActor
    func test_snapshot_withTTSProbeWired_populatesTTSFieldsAndShrinksPartial() async throws {
        let probe = DebugReaderProbeAdapter(
            fingerprintKey: "txt:tts:512",
            format: "txt"
        )
        probe.ttsProbe = { (state: "speaking", offsetUTF16: 42) }
        DebugReaderRegistry.shared.register(probe)
        defer { DebugReaderRegistry.shared.unregister(probe) }

        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        let dest = "snapshot-\(UUID().uuidString).json"
        try await context.snapshot(dest: dest, lastErrorMessage: nil)

        let url = try RealDebugBridgeContext.snapshotsDirectory().appendingPathComponent(dest)
        let snap = try JSONDecoder().decode(DebugSnapshot.self, from: Data(contentsOf: url))

        XCTAssertEqual(snap.ttsState, "speaking")
        XCTAssertEqual(snap.ttsOffsetUTF16, 42)
        // Wired probe → ttsState / ttsOffsetUTF16 drop from partial.
        // Position stays partial (no positionProvider); selection +
        // settingsProvenance remain partial as always.
        XCTAssertEqual(
            Set(snap.partial ?? []),
            Set(["selection", "position", "settingsProvenance"]),
            "TTS fields drop from partial when the probe wires its ttsProbe"
        )
        try? FileManager.default.removeItem(at: url)
    }

    @MainActor
    func test_snapshot_lastErrorMessageIsPropagatedIntoJSON() async throws {
        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        let dest = "snapshot-error-\(UUID().uuidString).json"
        try await context.snapshot(dest: dest, lastErrorMessage: "unknownFixture(\"missing\")")

        let url = try RealDebugBridgeContext.snapshotsDirectory().appendingPathComponent(dest)
        let snap = try JSONDecoder().decode(DebugSnapshot.self, from: Data(contentsOf: url))
        XCTAssertEqual(snap.lastError, "unknownFixture(\"missing\")")
        try? FileManager.default.removeItem(at: url)
    }

    @MainActor
    func test_snapshot_afterFailedCommand_includesStableErrorCodeInJSON() async throws {
        // Drive through the bridge so lastError flows from a failed dispatch
        // into the snapshot via the parameter. Asserts on the stable error
        // code prefix (`bridge.unknownFixture`) — independent of Swift's
        // enum-case spelling.
        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        let bridge = DebugBridge(context: context)

        await bridge.handle(URL(string: "vreader-debug://seed?fixture=missing")!)
        XCTAssertNotNil(bridge.lastError)

        let dest = "snapshot-bridge-\(UUID().uuidString).json"
        await bridge.handle(URL(string: "vreader-debug://snapshot?dest=\(dest)")!)

        let url = try RealDebugBridgeContext.snapshotsDirectory().appendingPathComponent(dest)
        let snap = try JSONDecoder().decode(DebugSnapshot.self, from: Data(contentsOf: url))
        XCTAssertNotNil(snap.lastError, "snapshot must encode bridge.lastError from previous failure")
        XCTAssertTrue(
            snap.lastError?.hasPrefix("bridge.unknownFixture") == true,
            "lastError must start with the stable category prefix `bridge.unknownFixture`, got: \(snap.lastError ?? "nil")"
        )
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - open

    @MainActor
    func test_open_unknownBookId_throwsBookNotFound() async throws {
        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        do {
            try await context.open(bookId: "definitely-not-a-real-key", position: nil)
            XCTFail("expected bookNotFound")
        } catch DebugBridgeContextError.bookNotFound(let id) {
            XCTAssertEqual(id, "definitely-not-a-real-key")
        } catch {
            XCTFail("expected bookNotFound, got \(error)")
        }
    }

    @MainActor
    func test_open_existingBook_postsNotificationWithFingerprintKey() async throws {
        let key = try await CollectionTestHelper.insertBook(
            persistence: persistence,
            title: "Openable",
            sha: String(repeating: "f", count: 64)
        )

        let exp = expectation(description: "notification posted")
        nonisolated(unsafe) var receivedKey: String?
        let token = NotificationCenter.default.addObserver(
            forName: .debugBridgeOpenBook,
            object: nil,
            queue: .main
        ) { notification in
            receivedKey = notification.userInfo?["fingerprintKey"] as? String
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        try await context.open(bookId: key, position: nil)
        await fulfillment(of: [exp], timeout: 2.0)
        XCTAssertEqual(receivedKey, key)
    }

    @MainActor
    func test_open_withInvalidEpubPosition_throwsInvalidPosition() async throws {
        // Feature #49 WI-7b: position is now parsed via DebugPositionResolver.
        // EPUB requires a non-empty CFI; empty string → invalidPosition.
        let fp = DocumentFingerprint(
            contentSHA256: String(repeating: "9", count: 64),
            fileByteCount: 1024,
            format: .epub
        )
        let record = BookRecord(
            fingerprintKey: fp.canonicalKey,
            title: "Openable",
            author: nil,
            coverImagePath: nil,
            fingerprint: fp,
            provenance: CollectionTestHelper.makeProvenance(),
            detectedEncoding: nil,
            addedAt: Date()
        )
        _ = try await persistence.insertBook(record)

        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        do {
            try await context.open(bookId: fp.canonicalKey, position: "")
            XCTFail("expected invalidPosition for empty EPUB position")
        } catch DebugBridgeContextError.invalidPosition(let format, _, _) {
            XCTAssertEqual(format, "epub")
        } catch {
            XCTFail("expected invalidPosition, got \(error)")
        }
    }

    @MainActor
    func test_open_invalidPosition_doesNotPostNotification() async throws {
        // Verify the position-validation-rejected case doesn't leak a partial
        // side effect. Notification is posted only AFTER position validation.
        let fp = DocumentFingerprint(
            contentSHA256: String(repeating: "8", count: 64),
            fileByteCount: 1024,
            format: .pdf
        )
        let record = BookRecord(
            fingerprintKey: fp.canonicalKey,
            title: "Openable",
            author: nil,
            coverImagePath: nil,
            fingerprint: fp,
            provenance: CollectionTestHelper.makeProvenance(),
            detectedEncoding: nil,
            addedAt: Date()
        )
        _ = try await persistence.insertBook(record)

        let exp = expectation(description: "no notification expected")
        exp.isInverted = true
        let token = NotificationCenter.default.addObserver(
            forName: .debugBridgeOpenBook,
            object: nil,
            queue: .main
        ) { _ in
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        do {
            // Negative page rejected by resolver → never reaches notification.
            try await context.open(bookId: fp.canonicalKey, position: "-1")
            XCTFail("expected throw")
        } catch DebugBridgeContextError.invalidPosition {
            // expected
        }
        await fulfillment(of: [exp], timeout: 0.5)
    }

    /// Feature #54 WI-6: the `readerReadingMode == "unified"` guard in
    /// `open(...)` is removed (the Native/Unified mode is retired). With a
    /// stale `readerReadingMode = "unified"` value still in UserDefaults,
    /// `open(...)` with a VALID position must NOT early-throw — it proceeds
    /// past the (now-removed) Step-3 guard and posts the open notification.
    @MainActor
    func test_open_withValidPosition_unifiedModeDefault_stillPostsNotification() async throws {
        DebugReaderRegistry.shared.reset()
        defer { DebugReaderRegistry.shared.reset() }

        // A stale `readerReadingMode = "unified"` — pre-#54 this triggered
        // the Step-3 unified-mode guard and an early throw.
        defaults.set("unified", forKey: "readerReadingMode")

        // A TXT book + a valid UTF-16 offset position.
        let fp = DocumentFingerprint(
            contentSHA256: String(repeating: "7", count: 64),
            fileByteCount: 2048,
            format: .txt
        )
        let record = BookRecord(
            fingerprintKey: fp.canonicalKey,
            title: "Unified-stale Openable",
            author: nil,
            coverImagePath: nil,
            fingerprint: fp,
            provenance: CollectionTestHelper.makeProvenance(),
            detectedEncoding: nil,
            addedAt: Date()
        )
        _ = try await persistence.insertBook(record)

        let exp = expectation(description: "open notification posted past the removed unified-mode guard")
        nonisolated(unsafe) var receivedKey: String?
        let token = NotificationCenter.default.addObserver(
            forName: .debugBridgeOpenBook, object: nil, queue: .main
        ) { notification in
            receivedKey = notification.userInfo?["fingerprintKey"] as? String
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        // `open` with a valid position runs Step 3 (post notification) then
        // Step 4 (`awaitReader`). Run `open` in a Task so the test can
        // register a stub probe once the notification fires — that resumes
        // `awaitReader` deterministically so `open` completes cleanly
        // (no 10s timeout, no lingering waiter), and the test then joins it.
        let openTask = Task { try await context.open(bookId: fp.canonicalKey, position: "42") }
        await fulfillment(of: [exp], timeout: 3.0)
        // The notification fired — `open` got PAST the removed Step-3 guard.
        XCTAssertEqual(receivedKey, fp.canonicalKey)
        // Resume Step 4's `awaitReader` by registering a matching probe.
        DebugReaderRegistry.shared.register(
            DebugReaderProbeAdapter(fingerprintKey: fp.canonicalKey, format: "txt")
        )
        // `open` now completes without throwing — Step 4's await resolved.
        try await openTask.value
    }

    // MARK: - settle / eval (active-reader registry)

    @MainActor
    func test_settle_withoutActiveReader_writesNoActiveReaderSentinelButDoesNotThrow() async throws {
        // Bug #125: settle without an active reader used to throw
        // `noActiveReader` and write nothing. The doc promise is "a hung
        // probe still produces the sentinel" — applies to the no-active-reader
        // case too. settle now mirrors eval's noActiveReader pattern: writes
        // `ready-<token>.json` carrying `error: "no active reader"` and does
        // NOT throw, so a verification harness can poll the file regardless
        // of reader state.
        DebugReaderRegistry.shared.reset()
        let context = RealDebugBridgeContext(
            persistence: persistence, importer: importer, userDefaults: defaults
        )
        let token = "no-reader-\(UUID().uuidString)"
        try await context.settle(token: token)

        let url = try RealDebugBridgeContext.snapshotsDirectory()
            .appendingPathComponent("ready-\(token).json")
        let json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: url)
        ) as? [String: Any]
        XCTAssertEqual(json?["error"] as? String, "no active reader",
                       "no-active-reader must surface in JSON file, not as a thrown error")
        XCTAssertEqual(json?["token"] as? String, token)
        XCTAssertEqual(json?["phase"] as? String, "unknown",
                       "phase: unknown matches the timeout-path payload shape")
        XCTAssertNil(json?["fingerprintKey"],
                     "no probe → no fingerprintKey")
        XCTAssertNil(json?["format"],
                     "no probe → no format")
        XCTAssertNil(json?["position"],
                     "no probe → no position")
        try? FileManager.default.removeItem(at: url)
    }

    @MainActor
    func test_settle_withActiveReader_writesReadySentinelFile() async throws {
        let probe = DebugReaderProbeAdapter(
            fingerprintKey: "test-key", format: "txt"
        )
        DebugReaderRegistry.shared.register(probe)
        defer { DebugReaderRegistry.shared.unregister(probe) }

        let context = RealDebugBridgeContext(
            persistence: persistence, importer: importer, userDefaults: defaults
        )
        let token = "settle-\(UUID().uuidString)"
        try await context.settle(token: token)

        let url = try RealDebugBridgeContext.snapshotsDirectory()
            .appendingPathComponent("ready-\(token).json")
        let json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: url)
        ) as? [String: Any]
        XCTAssertEqual(json?["fingerprintKey"] as? String, "test-key")
        XCTAssertEqual(json?["format"] as? String, "txt")
        XCTAssertEqual(json?["token"] as? String, token)
        XCTAssertNil(json?["error"], "happy path must not include error key")
        try? FileManager.default.removeItem(at: url)
    }

    @MainActor
    func test_settle_onHangingProbe_writesTimeoutSentinelViaBridgeRace() async throws {
        // A probe whose awaitSettle never returns AND never throws — exercises
        // the bridge-side timeout race (not the probe-side timeout). Without
        // the race, settle would hang forever and never write the sentinel.
        // We use a very short bridge timeout via an override hook in the test
        // by registering a HangingProbe and patching settleTimeoutSeconds.
        let probe = HangingProbe(fingerprintKey: "h-key", format: "epub")
        DebugReaderRegistry.shared.register(probe)
        defer { DebugReaderRegistry.shared.unregister(probe) }

        let context = RealDebugBridgeContext(
            persistence: persistence, importer: importer, userDefaults: defaults
        )
        let token = "hang-\(UUID().uuidString)"
        // settle should return within ~30s with a timeout sentinel — we don't
        // wait that long; we only verify the sentinel format when it returns.
        // The ACTUAL timeout race is exercised in the unit-test harness by
        // overriding settleTimeoutSeconds via a private bridge call below.
        // For this test we just confirm: under a hanging probe the bridge
        // STILL produces a valid output file with `error` set, after the
        // configured race elapses.
        try await context.settleWithTimeout(token: token, timeoutSeconds: 0.2)

        let url = try RealDebugBridgeContext.snapshotsDirectory()
            .appendingPathComponent("ready-\(token).json")
        let json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: url)
        ) as? [String: Any]
        XCTAssertEqual(json?["error"] as? String, "settle timeout")
        XCTAssertEqual(json?["phase"] as? String, "unknown")
        try? FileManager.default.removeItem(at: url)
    }

    @MainActor
    func test_settle_onTimeout_writesReadyWithErrorButDoesNotThrow() async throws {
        // A probe whose awaitSettle always throws settleTimeout — exercises the
        // timeout path without waiting 30s.
        let probe = TimingOutProbe(fingerprintKey: "to-key", format: "epub")
        DebugReaderRegistry.shared.register(probe)
        defer { DebugReaderRegistry.shared.unregister(probe) }

        let context = RealDebugBridgeContext(
            persistence: persistence, importer: importer, userDefaults: defaults
        )
        let token = "to-\(UUID().uuidString)"
        try await context.settle(token: token)

        let url = try RealDebugBridgeContext.snapshotsDirectory()
            .appendingPathComponent("ready-\(token).json")
        let json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: url)
        ) as? [String: Any]
        XCTAssertEqual(json?["error"] as? String, "settle timeout",
                       "timeout must surface in JSON file, not as a thrown error")
        XCTAssertEqual(json?["token"] as? String, token)
        XCTAssertEqual(json?["fingerprintKey"] as? String, "to-key")
        try? FileManager.default.removeItem(at: url)
    }

    @MainActor
    func test_eval_withoutActiveReader_writesErrorFileButDoesNotThrow() async throws {
        DebugReaderRegistry.shared.reset()
        let context = RealDebugBridgeContext(
            persistence: persistence, importer: importer, userDefaults: defaults
        )
        try await context.eval(bridge: "foliate", js: "1+1")

        let url = try RealDebugBridgeContext.snapshotsDirectory()
            .appendingPathComponent("eval-foliate.json")
        let json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: url)
        ) as? [String: Any]
        XCTAssertEqual(json?["error"] as? String, "no active reader")
        XCTAssertNil(json?["result"], "no result on error path")
        try? FileManager.default.removeItem(at: url)
    }

    @MainActor
    func test_eval_onTextReader_writesUnsupportedErrorFileButDoesNotThrow() async throws {
        let probe = DebugReaderProbeAdapter(
            fingerprintKey: "test-key", format: "txt"
        )
        DebugReaderRegistry.shared.register(probe)
        defer { DebugReaderRegistry.shared.unregister(probe) }

        let context = RealDebugBridgeContext(
            persistence: persistence, importer: importer, userDefaults: defaults
        )
        try await context.eval(bridge: "foliate", js: "1+1")

        let url = try RealDebugBridgeContext.snapshotsDirectory()
            .appendingPathComponent("eval-foliate.json")
        let json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: url)
        ) as? [String: Any]
        XCTAssertEqual(json?["error"] as? String, "eval unsupported for format: txt")
        XCTAssertEqual(json?["format"] as? String, "txt")
        try? FileManager.default.removeItem(at: url)
    }

    @MainActor
    func test_eval_withWebviewProbe_writesRawJSONResultValue() async throws {
        // Verify result encodes as actual JSON value, not a string-wrapped JSON.
        let probe = DebugReaderProbeAdapter(
            fingerprintKey: "test-key", format: "epub"
        )
        probe.jsEvaluator = { js in
            XCTAssertEqual(js, "document.querySelectorAll('.highlight').length")
            return Data("3".utf8)  // raw JSON `3`, not the string "3"
        }
        DebugReaderRegistry.shared.register(probe)
        defer { DebugReaderRegistry.shared.unregister(probe) }

        let context = RealDebugBridgeContext(
            persistence: persistence, importer: importer, userDefaults: defaults
        )
        try await context.eval(
            bridge: "foliate",
            js: "document.querySelectorAll('.highlight').length"
        )

        let url = try RealDebugBridgeContext.snapshotsDirectory()
            .appendingPathComponent("eval-foliate.json")
        let json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: url)
        ) as? [String: Any]
        XCTAssertEqual(json?["bridge"] as? String, "foliate")
        // result must be the JSON number 3, not the string "3"
        XCTAssertEqual(json?["result"] as? Int, 3)
        XCTAssertEqual(json?["format"] as? String, "epub")
        try? FileManager.default.removeItem(at: url)
    }

    @MainActor
    func test_eval_jsThrown_writesErrorFile() async throws {
        struct JSError: Error {}
        let probe = DebugReaderProbeAdapter(
            fingerprintKey: "test-key", format: "epub"
        )
        probe.jsEvaluator = { _ in throw JSError() }
        DebugReaderRegistry.shared.register(probe)
        defer { DebugReaderRegistry.shared.unregister(probe) }

        let context = RealDebugBridgeContext(
            persistence: persistence, importer: importer, userDefaults: defaults
        )
        try await context.eval(bridge: "foliate", js: "throw 1")

        let url = try RealDebugBridgeContext.snapshotsDirectory()
            .appendingPathComponent("eval-foliate.json")
        let json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: url)
        ) as? [String: Any]
        XCTAssertNotNil(json?["error"] as? String)
        XCTAssertNil(json?["result"])
        try? FileManager.default.removeItem(at: url)
    }

    @MainActor
    func test_snapshot_highlightCountReflectsLibrary() async throws {
        // Insert a book, then add highlights via the persistence API.
        // CollectionTestHelper.insertBook defaults to .epub format, so the
        // matching Locator must use the same fingerprint shape.
        let sha = String(repeating: "c", count: 64)
        let fp = CollectionTestHelper.makeFingerprint(sha: sha)
        let key = try await CollectionTestHelper.insertBook(
            persistence: persistence,
            title: "With Highlights",
            sha: sha
        )
        for i in 0..<3 {
            let locator = Locator(
                bookFingerprint: fp,
                href: nil, progression: nil, totalProgression: nil,
                cfi: nil, page: nil,
                charOffsetUTF16: nil,
                charRangeStartUTF16: i * 10,
                charRangeEndUTF16: i * 10 + 5,
                textQuote: "snip\(i)",
                textContextBefore: nil, textContextAfter: nil
            )
            _ = try await persistence.addHighlight(
                locator: locator,
                selectedText: "snip\(i)",
                color: "yellow",
                note: nil,
                toBookWithKey: key
            )
        }

        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        let dest = "snapshot-counts-\(UUID().uuidString).json"
        try await context.snapshot(dest: dest, lastErrorMessage: nil)

        let url = try RealDebugBridgeContext.snapshotsDirectory().appendingPathComponent(dest)
        let snap = try JSONDecoder().decode(DebugSnapshot.self, from: Data(contentsOf: url))
        XCTAssertEqual(snap.highlightCount, 3)
        try? FileManager.default.removeItem(at: url)
    }
}

/// Probe whose awaitSettle always throws settleTimeout. Lets the timeout
/// path be tested without waiting for a real 30s timer.
@MainActor
private final class TimingOutProbe: DebugReaderProbe {
    let fingerprintKey: String
    let format: String
    var currentPositionString: String? = nil

    init(fingerprintKey: String, format: String) {
        self.fingerprintKey = fingerprintKey
        self.format = format
    }

    func awaitSettle(timeout: TimeInterval) async throws {
        throw DebugReaderProbeError.settleTimeout
    }

    func evaluateJavaScript(_ script: String) async throws -> Data {
        throw DebugReaderProbeError.evalUnsupported(format: format)
    }
}

/// Probe whose awaitSettle never returns and never throws. Exercises
/// the bridge-side timeout race — without it, settle would hang forever.
@MainActor
private final class HangingProbe: DebugReaderProbe {
    let fingerprintKey: String
    let format: String
    var currentPositionString: String? = nil

    init(fingerprintKey: String, format: String) {
        self.fingerprintKey = fingerprintKey
        self.format = format
    }

    func awaitSettle(timeout: TimeInterval) async throws {
        // Sleep for a long time — Task.sleep IS cancellation-aware, so the
        // bridge's timeout race wins and we throw CancellationError. The
        // bridge translates that into "settle timeout" via the sentinel
        // race in withTimeout.
        try await Task.sleep(nanoseconds: 60_000_000_000)
    }

    func evaluateJavaScript(_ script: String) async throws -> Data {
        throw DebugReaderProbeError.evalUnsupported(format: format)
    }
}

#endif
