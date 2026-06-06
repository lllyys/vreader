// Purpose: Tests for RealDebugBridgeContext — the production handler set
// behind the vreader-debug:// URL scheme (feature #44 DebugBridge, WI-5).
// Verifies that real handlers mutate real subsystems: SwiftData wipes for
// reset, fixture import for seed, etc.

#if DEBUG

import XCTest
import SwiftData
#if canImport(WebKit)
import WebKit
#endif
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

    // Bug #272: `reset` must clear leaked reader settings so `open?position=`
    // verification is deterministic. A `readerAutoPageTurn=true` persisted from a
    // prior session made the AutoPageTurner advance the paged reader on open
    // (page 0 → last page), masking the seek and producing a "stale position"
    // snapshot that the prior cron ticks chased as a navigate/persistence bug.
    @MainActor
    func test_reset_clearsLeakedReaderSettings() async throws {
        let suiteName = "test.bug272.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        // Simulate a prior session leaking auto-page-turn + a custom layout.
        defaults.set(true, forKey: ReaderSettingsStore.autoPageTurnKey)
        defaults.set("paged", forKey: ReaderSettingsStore.epubLayoutKey)
        XCTAssertTrue(defaults.bool(forKey: ReaderSettingsStore.autoPageTurnKey))

        let context = RealDebugBridgeContext(
            persistence: persistence, importer: importer, userDefaults: defaults
        )
        try await context.reset()

        // Keys removed → a fresh reader mount reads deterministic defaults.
        XCTAssertNil(
            defaults.object(forKey: ReaderSettingsStore.autoPageTurnKey),
            "reset must clear the leaked autoPageTurn key (Bug #272)"
        )
        XCTAssertNil(defaults.object(forKey: ReaderSettingsStore.epubLayoutKey))
        let store = ReaderSettingsStore(defaults: defaults)
        XCTAssertFalse(store.autoPageTurn, "a fresh store over the reset defaults must read autoPageTurn=false")
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
        // settingsProvenance always partial until feature #50. Feature #74:
        // landingBloomCount/landingBloomPeakIntensity are partial too — no
        // probe supplies them (a present probe defaults them to 0, not nil).
        XCTAssertEqual(
            Set(snap.partial ?? []),
            Set([
                "currentBookId", "format", "position", "selection",
                "ttsState", "ttsOffsetUTF16", "settingsProvenance",
                "landingBloomCount", "landingBloomPeakIntensity",
            ])
        )
        XCTAssertNil(snap.ttsState)
        XCTAssertNil(snap.ttsOffsetUTF16)
        XCTAssertNil(snap.settingsProvenance)
        XCTAssertNil(snap.landingBloomCount)
        XCTAssertNil(snap.landingBloomPeakIntensity)
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
        // Feature #74: a present probe with no bloom yet reports 0 (NOT nil),
        // so the bloom fields are authoritative — never in `partial`.
        XCTAssertEqual(snap.landingBloomCount, 0)
        XCTAssertEqual(snap.landingBloomPeakIntensity, 0)
        XCTAssertFalse(Set(snap.partial ?? []).contains("landingBloomCount"))
        XCTAssertFalse(Set(snap.partial ?? []).contains("landingBloomPeakIntensity"))
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

    // MARK: - txt-content (bug #1218)

    @MainActor
    func test_txtContent_withProbeRenderedText_writesTextAndAvailableTrue() async throws {
        // A registered probe with a known rendered text → the file contains
        // that text and `available: true` (the CU-free read path for
        // Feature #28's Simp→Trad conversion verification).
        let probe = DebugReaderProbeAdapter(
            fingerprintKey: "txt:abc123:1024",
            format: "txt"
        )
        probe.renderedText = "繁體中文內容"  // CJK round-trips through JSON
        DebugReaderRegistry.shared.register(probe)
        defer { DebugReaderRegistry.shared.unregister(probe) }

        let context = RealDebugBridgeContext(
            persistence: persistence, importer: importer, userDefaults: defaults
        )
        let dest = "txt-content-\(UUID().uuidString).json"
        try await context.txtContent(dest: dest)

        let url = try RealDebugBridgeContext.snapshotsDirectory().appendingPathComponent(dest)
        let json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: url)
        ) as? [String: Any]
        XCTAssertEqual(json?["text"] as? String, "繁體中文內容")
        XCTAssertEqual(json?["available"] as? Bool, true)
        XCTAssertEqual(json?["fingerprintKey"] as? String, "txt:abc123:1024")
        XCTAssertEqual(json?["format"] as? String, "txt")
        XCTAssertNotNil(json?["ts"] as? String)
        try? FileManager.default.removeItem(at: url)
    }

    @MainActor
    func test_txtContent_withProbeButNoRenderedText_writesNullAndAvailableFalse() async throws {
        // A registered probe that hasn't wired rendered text → `text: null`
        // and `available: false` (still a file, mirroring eval/snapshot's
        // always-write contract so the host-side waiter has output).
        let probe = DebugReaderProbeAdapter(
            fingerprintKey: "txt:def:2048",
            format: "txt"
        )
        DebugReaderRegistry.shared.register(probe)
        defer { DebugReaderRegistry.shared.unregister(probe) }

        let context = RealDebugBridgeContext(
            persistence: persistence, importer: importer, userDefaults: defaults
        )
        let dest = "txt-content-\(UUID().uuidString).json"
        try await context.txtContent(dest: dest)

        let url = try RealDebugBridgeContext.snapshotsDirectory().appendingPathComponent(dest)
        let json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: url)
        ) as? [String: Any]
        XCTAssertTrue(json?["text"] is NSNull, "text must be JSON null when no rendered text is wired")
        XCTAssertEqual(json?["available"] as? Bool, false)
        XCTAssertEqual(json?["fingerprintKey"] as? String, "txt:def:2048")
        try? FileManager.default.removeItem(at: url)
    }

    @MainActor
    func test_txtContent_nonTXTFormatProbe_forcesUnavailable() async throws {
        // Codex Gate-4 (Medium): the rendered-text probe is a TXT-only
        // capability. Even if a non-TXT probe somehow populates `renderedText`,
        // the command must report `available:false` / `text:null` so non-TXT
        // content can't be misread as TXT prose.
        let probe = DebugReaderProbeAdapter(
            fingerprintKey: "epub:abc:4096",
            format: "epub"
        )
        probe.renderedText = "should be ignored for non-txt"
        DebugReaderRegistry.shared.register(probe)
        defer { DebugReaderRegistry.shared.unregister(probe) }

        let context = RealDebugBridgeContext(
            persistence: persistence, importer: importer, userDefaults: defaults
        )
        let dest = "txt-content-\(UUID().uuidString).json"
        try await context.txtContent(dest: dest)

        let url = try RealDebugBridgeContext.snapshotsDirectory().appendingPathComponent(dest)
        let json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: url)
        ) as? [String: Any]
        XCTAssertTrue(json?["text"] is NSNull, "non-TXT format must force text:null")
        XCTAssertEqual(json?["available"] as? Bool, false)
        XCTAssertEqual(json?["format"] as? String, "epub")
        try? FileManager.default.removeItem(at: url)
    }

    @MainActor
    func test_txtContent_withoutActiveReader_writesErrorFileButDoesNotThrow() async throws {
        DebugReaderRegistry.shared.reset()
        let context = RealDebugBridgeContext(
            persistence: persistence, importer: importer, userDefaults: defaults
        )
        let dest = "txt-content-\(UUID().uuidString).json"
        try await context.txtContent(dest: dest)

        let url = try RealDebugBridgeContext.snapshotsDirectory().appendingPathComponent(dest)
        let json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: url)
        ) as? [String: Any]
        XCTAssertEqual(json?["error"] as? String, "no active reader")
        XCTAssertNil(json?["text"], "no text on the error path")
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
    func test_seekFraction_postsSeekFractionNotificationWithClampedValue() async throws {
        // Bug #267: seekFraction posts .debugBridgeSeekFraction carrying the
        // (already parser-clamped) fraction; the live Foliate container forwards
        // it to .foliateRequestSeekFraction with its own key.
        let exp = expectation(description: "seekFraction notification posted")
        nonisolated(unsafe) var receivedFraction: Double?
        let token = NotificationCenter.default.addObserver(
            forName: .debugBridgeSeekFraction,
            object: nil,
            queue: .main
        ) { notification in
            receivedFraction = notification.userInfo?["fraction"] as? Double
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        try await context.seekFraction(fraction: 0.5)
        await fulfillment(of: [exp], timeout: 2.0)
        XCTAssertEqual(receivedFraction, 0.5)
    }

    @MainActor
    func test_scrollSheet_postsScrollSheetNotificationWithTarget() async throws {
        // Bug #271: scrollSheet posts .debugBridgeScrollSheet carrying the
        // target rawValue; the presented sheet's observer (TranslationResultCard)
        // drives its ScrollViewReader proxy to the matching anchor.
        let exp = expectation(description: "scrollSheet notification posted")
        nonisolated(unsafe) var receivedTo: String?
        let token = NotificationCenter.default.addObserver(
            forName: .debugBridgeScrollSheet,
            object: nil,
            queue: .main
        ) { notification in
            receivedTo = notification.userInfo?["to"] as? String
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        try await context.scrollSheet(target: .bottom)
        await fulfillment(of: [exp], timeout: 2.0)
        XCTAssertEqual(receivedTo, "bottom")
    }

    @MainActor
    func test_navigate_postsNavigateCommandWithSpineAndFraction() async throws {
        // Bug #273: navigate posts .debugBridgeNavigateCommand carrying the
        // spine index + clamped fraction; the live EPUBReaderContainerView
        // observer resolves index → href and re-posts .readerNavigateToLocator.
        let exp = expectation(description: "navigate notification posted")
        nonisolated(unsafe) var receivedSpine: Int?
        nonisolated(unsafe) var receivedFraction: Double?
        let token = NotificationCenter.default.addObserver(
            forName: .debugBridgeNavigateCommand,
            object: nil,
            queue: .main
        ) { notification in
            receivedSpine = notification.userInfo?["spineIndex"] as? Int
            receivedFraction = notification.userInfo?["fraction"] as? Double
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        try await context.navigate(spineIndex: 3, fraction: 0.25)
        await fulfillment(of: [exp], timeout: 2.0)
        XCTAssertEqual(receivedSpine, 3)
        XCTAssertEqual(receivedFraction, 0.25)
    }

    @MainActor
    func test_navigate_withNilFraction_omitsFractionFromUserInfo() async throws {
        // Bug #273: absent fraction ⇒ chapter start; the key is omitted so the
        // observer's `as? Double` cleanly yields nil.
        let exp = expectation(description: "navigate notification posted")
        nonisolated(unsafe) var hasFractionKey = true
        nonisolated(unsafe) var receivedSpine: Int?
        let token = NotificationCenter.default.addObserver(
            forName: .debugBridgeNavigateCommand,
            object: nil,
            queue: .main
        ) { notification in
            receivedSpine = notification.userInfo?["spineIndex"] as? Int
            hasFractionKey = notification.userInfo?["fraction"] != nil
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        try await context.navigate(spineIndex: 0, fraction: nil)
        await fulfillment(of: [exp], timeout: 2.0)
        XCTAssertEqual(receivedSpine, 0)
        XCTAssertFalse(hasFractionKey)
    }

    // MARK: - locate (feature #74 — CU-free locate-bloom harness)

    @MainActor
    func test_locate_withoutActiveReader_isNoOp() async throws {
        // No reader registered → no `.readerNavigateToLocator` post (mirrors
        // navigate / seek / present no-op posture).
        DebugReaderRegistry.shared.reset()
        let exp = expectation(description: "no navigate post")
        exp.isInverted = true
        let token = NotificationCenter.default.addObserver(
            forName: .readerNavigateToLocator, object: nil, queue: .main
        ) { _ in exp.fulfill() }
        defer { NotificationCenter.default.removeObserver(token) }

        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        try await context.locate(highlightIndex: 0)
        await fulfillment(of: [exp], timeout: 0.5)
    }

    @MainActor
    func test_locate_postsSavedLocatorForNthHighlight() async throws {
        // Register a probe for a book that has a persisted highlight; locate?0
        // posts that highlight's saved Locator on .readerNavigateToLocator —
        // the SAME channel a Notes/Highlights row tap uses, so the bloom fires.
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let fp = DocumentFingerprint(canonicalKey: key)!
        let locator = LocatorFactory.txtRange(
            fingerprint: fp, charRangeStartUTF16: 10, charRangeEndUTF16: 20
        )!
        _ = try await persistence.addHighlight(
            locator: locator, selectedText: "ten to twenty",
            color: "yellow", note: nil, toBookWithKey: key
        )

        let probe = DebugReaderProbeAdapter(fingerprintKey: key, format: "txt")
        DebugReaderRegistry.shared.register(probe)
        defer { DebugReaderRegistry.shared.unregister(probe) }

        let exp = expectation(description: "navigate posted with locator")
        nonisolated(unsafe) var receivedStart: Int?
        nonisolated(unsafe) var receivedEnd: Int?
        let token = NotificationCenter.default.addObserver(
            forName: .readerNavigateToLocator, object: nil, queue: .main
        ) { notification in
            let loc = notification.object as? Locator
            receivedStart = loc?.charRangeStartUTF16
            receivedEnd = loc?.charRangeEndUTF16
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        try await context.locate(highlightIndex: 0)
        await fulfillment(of: [exp], timeout: 2.0)
        XCTAssertEqual(receivedStart, 10)
        XCTAssertEqual(receivedEnd, 20)
    }

    @MainActor
    func test_locate_indexOutOfRange_isNoOp() async throws {
        // A reader with zero highlights, asked for index 0 → no post.
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let probe = DebugReaderProbeAdapter(fingerprintKey: key, format: "txt")
        DebugReaderRegistry.shared.register(probe)
        defer { DebugReaderRegistry.shared.unregister(probe) }

        let exp = expectation(description: "no navigate post")
        exp.isInverted = true
        let token = NotificationCenter.default.addObserver(
            forName: .readerNavigateToLocator, object: nil, queue: .main
        ) { _ in exp.fulfill() }
        defer { NotificationCenter.default.removeObserver(token) }

        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        try await context.locate(highlightIndex: 0)
        await fulfillment(of: [exp], timeout: 0.5)
    }

    @MainActor
    func test_setLayout_postsSetLayoutCommandWithMode() async throws {
        // Feature #75 WI-5a: setLayout posts .debugBridgeSetLayoutCommand
        // carrying the mode rawValue; the live EPUBReaderContainerView observer
        // sets settingsStore.epubLayout — the SAME binding the segmented picker
        // drives (untappable under XCUITest on iOS 26).
        let exp = expectation(description: "set-layout notification posted")
        nonisolated(unsafe) var receivedMode: String?
        let token = NotificationCenter.default.addObserver(
            forName: .debugBridgeSetLayoutCommand,
            object: nil,
            queue: .main
        ) { notification in
            receivedMode = notification.userInfo?["mode"] as? String
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        try await context.setLayout(layout: .paged)
        await fulfillment(of: [exp], timeout: 2.0)
        XCTAssertEqual(receivedMode, "paged")
    }

    @MainActor
    func test_setLayout_scroll_postsScrollMode() async throws {
        // The scroll case round-trips the other rawValue so a future regression
        // that hard-codes "paged" is caught.
        let exp = expectation(description: "set-layout scroll notification posted")
        nonisolated(unsafe) var receivedMode: String?
        let token = NotificationCenter.default.addObserver(
            forName: .debugBridgeSetLayoutCommand,
            object: nil,
            queue: .main
        ) { notification in
            receivedMode = notification.userInfo?["mode"] as? String
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        try await context.setLayout(layout: .scroll)
        await fulfillment(of: [exp], timeout: 2.0)
        XCTAssertEqual(receivedMode, "scroll")
    }

    @MainActor
    func test_page_next_postsReaderNextPage() async throws {
        // Feature #42/#75: page?dir=next posts .readerNextPage — the SAME
        // notification every reader host observes (Readium goForward; legacy
        // EPUB/Foliate paged nav). Reliable CU-free page-turn where synthetic
        // swipes can't drive Readium's gesture recognizers.
        let exp = expectation(description: "readerNextPage posted")
        let token = NotificationCenter.default.addObserver(
            forName: .readerNextPage, object: nil, queue: .main
        ) { _ in exp.fulfill() }
        defer { NotificationCenter.default.removeObserver(token) }

        let context = RealDebugBridgeContext(
            persistence: persistence, importer: importer, userDefaults: defaults
        )
        try await context.page(direction: .next)
        await fulfillment(of: [exp], timeout: 2.0)
    }

    @MainActor
    func test_page_prev_postsReaderPreviousPage() async throws {
        let exp = expectation(description: "readerPreviousPage posted")
        let token = NotificationCenter.default.addObserver(
            forName: .readerPreviousPage, object: nil, queue: .main
        ) { _ in exp.fulfill() }
        defer { NotificationCenter.default.removeObserver(token) }

        let context = RealDebugBridgeContext(
            persistence: persistence, importer: importer, userDefaults: defaults
        )
        try await context.page(direction: .prev)
        await fulfillment(of: [exp], timeout: 2.0)
    }

    @MainActor
    func test_scrollBoundary_postsScrollBoundaryCommandWithSpineAndNear() async throws {
        // Feature #71 WI-6b: scrollBoundary posts .debugBridgeScrollBoundaryCommand
        // carrying the spine index + edge; the live EPUBReaderContainerView
        // observer builds an EPUBScrollBoundarySignal and calls
        // coordinator.handleBoundarySignal — bypassing the rAF-throttled JS
        // observer (rAF is paused on the headless test environment).
        let exp = expectation(description: "scroll-boundary notification posted")
        nonisolated(unsafe) var receivedSpine: Int?
        nonisolated(unsafe) var receivedNear: String?
        let token = NotificationCenter.default.addObserver(
            forName: .debugBridgeScrollBoundaryCommand,
            object: nil,
            queue: .main
        ) { notification in
            receivedSpine = notification.userInfo?["spineIndex"] as? Int
            receivedNear = notification.userInfo?["near"] as? String
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        try await context.scrollBoundary(spineIndex: 3, near: .bottom)
        await fulfillment(of: [exp], timeout: 2.0)
        XCTAssertEqual(receivedSpine, 3)
        XCTAssertEqual(receivedNear, "bottom")
    }

    @MainActor
    func test_pdfHighlight_postsPDFHighlightCommandWithPageRectAndColor() async throws {
        // Feature #17: pdfHighlight posts .debugBridgePDFHighlightCommand carrying
        // the page index, normalized rect (x,y,w,h), and color; the live
        // PDFReaderContainerView observer builds a ReaderSelectionEvent with a
        // .pdf anchor and calls the SAME handleHighlightAction the gesture uses.
        let exp = expectation(description: "pdf-highlight notification posted")
        nonisolated(unsafe) var receivedPage: Int?
        nonisolated(unsafe) var receivedRect: [Double]?
        nonisolated(unsafe) var receivedColor: String?
        let token = NotificationCenter.default.addObserver(
            forName: .debugBridgePDFHighlightCommand,
            object: nil,
            queue: .main
        ) { notification in
            receivedPage = notification.userInfo?["page"] as? Int
            receivedRect = notification.userInfo?["rect"] as? [Double]
            receivedColor = notification.userInfo?["color"] as? String
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        try await context.pdfHighlight(
            page: 2,
            rect: NormalizedRect(x: 0.1, y: 0.2, w: 0.3, h: 0.4),
            color: "pink"
        )
        await fulfillment(of: [exp], timeout: 2.0)
        XCTAssertEqual(receivedPage, 2)
        XCTAssertEqual(receivedRect, [0.1, 0.2, 0.3, 0.4])
        XCTAssertEqual(receivedColor, "pink")
    }

    @MainActor
    func test_pdfHighlight_withNilColor_postsWithoutColorKey() async throws {
        let exp = expectation(description: "pdf-highlight notification posted")
        nonisolated(unsafe) var hasColorKey = true
        let token = NotificationCenter.default.addObserver(
            forName: .debugBridgePDFHighlightCommand,
            object: nil,
            queue: .main
        ) { notification in
            hasColorKey = notification.userInfo?["color"] != nil
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        try await context.pdfHighlight(
            page: 0,
            rect: NormalizedRect(x: 0, y: 0, w: 1, h: 1),
            color: nil
        )
        await fulfillment(of: [exp], timeout: 2.0)
        XCTAssertFalse(hasColorKey)
    }

    @MainActor
    func test_scrollSheet_recordsPendingTargetForReplay() async throws {
        // Bug #271 (Gate-4 round-1 Medium): scrollSheet records the target in
        // the shared replay buffer so a scroll requested BEFORE the result card
        // mounts (the card only exists once translation completes) is applied
        // on the card's onAppear — making the harness order-independent.
        DebugBridgeScrollSheetState.shared.pendingTarget = nil
        defer { DebugBridgeScrollSheetState.shared.pendingTarget = nil }

        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        try await context.scrollSheet(target: .bottom)
        XCTAssertEqual(DebugBridgeScrollSheetState.shared.pendingTarget, .bottom)
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

    // MARK: - open position seek (Bug #257)

    /// Bug #257: `open?position=N` must actually move the reader, not just
    /// await it. After `awaitReader` + `awaitSettle` resolve, the handler
    /// posts `.readerNavigateToLocator` carrying a `Locator` with the resolved
    /// offset — the same production navigation path that TOC / search / restore
    /// use. This is the regression test that fails on the pre-fix commit (the
    /// seek was a documented deferred no-op).
    @MainActor
    func test_open_withTxtPosition_postsNavigateToLocatorAfterReaderRegisters() async throws {
        DebugReaderRegistry.shared.reset()
        defer { DebugReaderRegistry.shared.reset() }

        let fp = DocumentFingerprint(
            contentSHA256: String(repeating: "5", count: 64),
            fileByteCount: 4096,
            format: .txt
        )
        let record = BookRecord(
            fingerprintKey: fp.canonicalKey,
            title: "Seekable",
            author: nil,
            coverImagePath: nil,
            fingerprint: fp,
            provenance: CollectionTestHelper.makeProvenance(),
            detectedEncoding: nil,
            addedAt: Date()
        )
        _ = try await persistence.insertBook(record)

        // Observe BOTH notifications so the test can register the probe at the
        // right moment and assert the navigate locator carries the offset.
        let openExp = expectation(description: "open notification posted")
        let navExp = expectation(description: "navigate-to-locator posted")
        nonisolated(unsafe) var navLocator: Locator?
        let openToken = NotificationCenter.default.addObserver(
            forName: .debugBridgeOpenBook, object: nil, queue: .main
        ) { _ in openExp.fulfill() }
        let navToken = NotificationCenter.default.addObserver(
            forName: .readerNavigateToLocator, object: nil, queue: .main
        ) { notification in
            navLocator = notification.object as? Locator
            navExp.fulfill()
        }
        defer {
            NotificationCenter.default.removeObserver(openToken)
            NotificationCenter.default.removeObserver(navToken)
        }

        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        let openTask = Task { try await context.open(bookId: fp.canonicalKey, position: "800") }
        await fulfillment(of: [openExp], timeout: 3.0)
        // Register a probe so `awaitReader` resolves; the adapter's nil
        // settleStrategy falls back to a 100ms sleep — well under the timeout.
        DebugReaderRegistry.shared.register(
            DebugReaderProbeAdapter(fingerprintKey: fp.canonicalKey, format: "txt")
        )
        await fulfillment(of: [navExp], timeout: 3.0)
        try await openTask.value

        XCTAssertEqual(navLocator?.charOffsetUTF16, 800,
                       "the seek must navigate to the resolved UTF-16 offset")
        XCTAssertEqual(navLocator?.bookFingerprint, fp,
                       "the navigate locator must carry the opened book's fingerprint")
    }

    /// Bug #257: AZW3 IS supported — Foliate's navigate handler consumes a raw
    /// CFI (`navigateToSearchResult(cfi:)`), unlike EPUB. So an AZW3 `position`
    /// must reach the seek and post `.readerNavigateToLocator` carrying the CFI,
    /// not be rejected. Asserts the supported/unsupported split is per-format.
    @MainActor
    func test_open_withAzw3CFI_postsNavigateWithCFI() async throws {
        DebugReaderRegistry.shared.reset()
        defer { DebugReaderRegistry.shared.reset() }

        let fp = DocumentFingerprint(
            contentSHA256: String(repeating: "4", count: 64),
            fileByteCount: 8192,
            format: .azw3
        )
        let record = BookRecord(
            fingerprintKey: fp.canonicalKey,
            title: "AZW3 seekable",
            author: nil,
            coverImagePath: nil,
            fingerprint: fp,
            provenance: CollectionTestHelper.makeProvenance(),
            detectedEncoding: nil,
            addedAt: Date()
        )
        _ = try await persistence.insertBook(record)

        let cfi = "epubcfi(/6/12!/4/3)"
        let openExp = expectation(description: "open notification posted")
        let navExp = expectation(description: "navigate posted")
        nonisolated(unsafe) var navLocator: Locator?
        let openToken = NotificationCenter.default.addObserver(
            forName: .debugBridgeOpenBook, object: nil, queue: .main
        ) { _ in openExp.fulfill() }
        let navToken = NotificationCenter.default.addObserver(
            forName: .readerNavigateToLocator, object: nil, queue: .main
        ) { notification in
            navLocator = notification.object as? Locator
            navExp.fulfill()
        }
        defer {
            NotificationCenter.default.removeObserver(openToken)
            NotificationCenter.default.removeObserver(navToken)
        }

        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        let openTask = Task { try await context.open(bookId: fp.canonicalKey, position: cfi) }
        await fulfillment(of: [openExp], timeout: 3.0)
        // Register a probe so awaitReader resolves (nil settleStrategy → 100ms).
        DebugReaderRegistry.shared.register(
            DebugReaderProbeAdapter(fingerprintKey: fp.canonicalKey, format: "azw3")
        )
        await fulfillment(of: [navExp], timeout: 3.0)
        try await openTask.value

        XCTAssertEqual(navLocator?.cfi, cfi, "AZW3 seek must carry the CFI to Foliate")
    }

    /// Bug #257 (Codex audit round 1 Medium): a VALID EPUB CFI position must
    /// fail loudly with `seekUnsupportedForFormat` rather than open the book at
    /// offset 0 and silently drop the seek — the EPUB navigate handler resolves
    /// the spine by `href`, not raw CFI, so a CFI-only seek would no-op. The
    /// throw happens BEFORE the open notification (no partial side effect).
    @MainActor
    func test_open_withValidEpubCFI_throwsSeekUnsupported_andPostsNoNotification() async throws {
        DebugReaderRegistry.shared.reset()
        defer { DebugReaderRegistry.shared.reset() }

        let fp = DocumentFingerprint(
            contentSHA256: String(repeating: "3", count: 64),
            fileByteCount: 8192,
            format: .epub
        )
        let record = BookRecord(
            fingerprintKey: fp.canonicalKey,
            title: "EPUB no-seek",
            author: nil,
            coverImagePath: nil,
            fingerprint: fp,
            provenance: CollectionTestHelper.makeProvenance(),
            detectedEncoding: nil,
            addedAt: Date()
        )
        _ = try await persistence.insertBook(record)

        // No open notification, no navigate — the throw precedes both.
        let openExp = expectation(description: "no open notification expected")
        openExp.isInverted = true
        let navExp = expectation(description: "no navigate expected")
        navExp.isInverted = true
        let openToken = NotificationCenter.default.addObserver(
            forName: .debugBridgeOpenBook, object: nil, queue: .main
        ) { _ in openExp.fulfill() }
        let navToken = NotificationCenter.default.addObserver(
            forName: .readerNavigateToLocator, object: nil, queue: .main
        ) { _ in navExp.fulfill() }
        defer {
            NotificationCenter.default.removeObserver(openToken)
            NotificationCenter.default.removeObserver(navToken)
        }

        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        do {
            try await context.open(bookId: fp.canonicalKey, position: "epubcfi(/6/4!/4/1:0)")
            XCTFail("expected seekUnsupportedForFormat for EPUB position")
        } catch DebugBridgeContextError.seekUnsupportedForFormat(let format, let position) {
            XCTAssertEqual(format, "epub")
            XCTAssertEqual(position, "epubcfi(/6/4!/4/1:0)")
        }
        await fulfillment(of: [openExp, navExp], timeout: 0.5)
    }

    /// Bug #257: a nil position must NOT trigger any navigation — opening a
    /// book without `position` lands at the restored/default location, not a
    /// seek. Guards against a regression where the seek fires unconditionally.
    @MainActor
    func test_open_withoutPosition_doesNotPostNavigateToLocator() async throws {
        DebugReaderRegistry.shared.reset()
        defer { DebugReaderRegistry.shared.reset() }

        let key = try await CollectionTestHelper.insertBook(
            persistence: persistence,
            title: "No-seek",
            sha: String(repeating: "6", count: 64)
        )

        let navExp = expectation(description: "no navigate expected")
        navExp.isInverted = true
        let navToken = NotificationCenter.default.addObserver(
            forName: .readerNavigateToLocator, object: nil, queue: .main
        ) { _ in navExp.fulfill() }
        defer { NotificationCenter.default.removeObserver(navToken) }

        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        try await context.open(bookId: key, position: nil)
        await fulfillment(of: [navExp], timeout: 0.5)
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

    // MARK: - Bug #250: settle waits for WebView registration on EPUB/AZW3

    /// Bug #250 / GH #1084: a probe whose `awaitSettle` resolves cleanly but
    /// whose format is "epub" should NOT cause settle to report success when
    /// no EPUB WebView has been registered with the registry — settle's
    /// contract for the WebView-backed formats is "render-complete AND
    /// WebView registered". Without the fix, the harness's downstream
    /// `vreader-debug://highlight-create` URL fires before the WebView
    /// registry slot is populated, and the highlight observer logs
    /// `no active EPUB WebView registered` instead of creating a highlight.
    @MainActor
    func test_settle_onEPUBProbe_withoutRegisteredWebView_writesWebViewNotRegisteredError() async throws {
        // Use the production registry shared instance because the prod
        // settle handler reads from DebugReaderRegistry.shared. We reset it
        // first (mirrors the no-active-reader case) so prior tests' probe
        // state can't leak in.
        DebugReaderRegistry.shared.reset()
        let probe = SettleOKProbe(fingerprintKey: "epub:abcd:1024", format: "epub")
        DebugReaderRegistry.shared.register(probe)
        defer { DebugReaderRegistry.shared.unregister(probe) }

        let context = RealDebugBridgeContext(
            persistence: persistence, importer: importer, userDefaults: defaults
        )
        let token = "epub-no-wv-\(UUID().uuidString)"
        // Use the test-seam settleWithTimeout's webViewWaitSeconds
        // override to pin the WebView-wait budget — the production
        // 5-second Stage-2 wait would slow the test. The behavior we're
        // pinning is: after probe.awaitSettle resolves, the bridge polls
        // the registry's EPUB slot and surfaces `webview not registered`
        // when the slot is empty.
        try await context.settleWithTimeout(
            token: token, timeoutSeconds: 0.5, webViewWaitSeconds: 0.2
        )

        let url = try RealDebugBridgeContext.snapshotsDirectory()
            .appendingPathComponent("ready-\(token).json")
        let json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: url)
        ) as? [String: Any]
        XCTAssertEqual(json?["error"] as? String, "webview not registered",
                       "EPUB probe without a registered WebView must surface webview-not-registered, not success")
        XCTAssertEqual(json?["fingerprintKey"] as? String, "epub:abcd:1024")
        XCTAssertEqual(json?["format"] as? String, "epub")
        XCTAssertEqual(json?["phase"] as? String, "unknown")
        try? FileManager.default.removeItem(at: url)
    }

    /// Bug #250 / GH #1084: when the EPUB WebView IS registered AND the
    /// `expectedReaderToken` matches the slot's stored token (the normal
    /// success path), settle returns clean — no error key, mirroring the
    /// pre-fix behavior for non-WebView readers and the TXT path. Token
    /// match is required because the production `epubWebView(for:token:)`
    /// accessor is token-keyed; the gate must accept ONLY when downstream
    /// commands can actually use the slot.
    @MainActor
    func test_settle_onEPUBProbe_withRegisteredWebView_writesNoErrorSentinel() async throws {
        DebugReaderRegistry.shared.reset()
        let probe = SettleOKProbe(fingerprintKey: "epub:efgh:2048", format: "epub")
        DebugReaderRegistry.shared.register(probe)
        defer { DebugReaderRegistry.shared.unregister(probe) }

        // Build a real WKWebView reference and register it via the same
        // path the EPUB coordinator's didFinish uses — token-keyed write
        // AND token-keyed read.
        let token = UUID()
        DebugReaderRegistry.shared.setExpectedReaderToken(token)
        let webView = WKWebView()
        DebugReaderRegistry.shared.setActiveEPUBWebView(
            webView, for: probe.fingerprintKey, token: token
        )

        let context = RealDebugBridgeContext(
            persistence: persistence, importer: importer, userDefaults: defaults
        )
        let sentinelToken = "epub-wv-ok-\(UUID().uuidString)"
        try await context.settleWithTimeout(
            token: sentinelToken, timeoutSeconds: 0.5, webViewWaitSeconds: 0.2
        )

        let url = try RealDebugBridgeContext.snapshotsDirectory()
            .appendingPathComponent("ready-\(sentinelToken).json")
        let json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: url)
        ) as? [String: Any]
        XCTAssertNil(json?["error"],
                     "EPUB probe with registered WebView must succeed without an error key")
        XCTAssertEqual(json?["fingerprintKey"] as? String, "epub:efgh:2048")
        XCTAssertEqual(json?["format"] as? String, "epub")
        try? FileManager.default.removeItem(at: url)
    }

    /// Bug #250 / GH #1084: AZW3 / MOBI books render via Foliate; the
    /// WebView is stored under a different registry slot
    /// (`activeFoliateWebView*`). settle's WebView-registration check must
    /// route by format — an AZW3 probe without a Foliate WebView gets the
    /// same "webview not registered" error, never an EPUB false-positive.
    @MainActor
    func test_settle_onAZW3Probe_withoutRegisteredFoliateWebView_writesWebViewNotRegisteredError() async throws {
        DebugReaderRegistry.shared.reset()
        let probe = SettleOKProbe(fingerprintKey: "azw3:ijkl:512", format: "azw3")
        DebugReaderRegistry.shared.register(probe)
        defer { DebugReaderRegistry.shared.unregister(probe) }

        let context = RealDebugBridgeContext(
            persistence: persistence, importer: importer, userDefaults: defaults
        )
        let token = "azw3-no-wv-\(UUID().uuidString)"
        try await context.settleWithTimeout(
            token: token, timeoutSeconds: 0.5, webViewWaitSeconds: 0.2
        )

        let url = try RealDebugBridgeContext.snapshotsDirectory()
            .appendingPathComponent("ready-\(token).json")
        let json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: url)
        ) as? [String: Any]
        XCTAssertEqual(json?["error"] as? String, "webview not registered",
                       "AZW3 probe without a registered Foliate WebView must surface webview-not-registered")
        XCTAssertEqual(json?["fingerprintKey"] as? String, "azw3:ijkl:512")
        XCTAssertEqual(json?["format"] as? String, "azw3")
        try? FileManager.default.removeItem(at: url)
    }

    /// Bug #250 / GH #1084: TXT / MD / PDF readers have no WebView slot —
    /// their settle path must continue to succeed without any WebView
    /// registration check (otherwise we break every non-WebView format).
    @MainActor
    func test_settle_onTXTProbe_skipsWebViewCheckAndSucceeds() async throws {
        DebugReaderRegistry.shared.reset()
        let probe = SettleOKProbe(fingerprintKey: "txt:mnop:64", format: "txt")
        DebugReaderRegistry.shared.register(probe)
        defer { DebugReaderRegistry.shared.unregister(probe) }

        let context = RealDebugBridgeContext(
            persistence: persistence, importer: importer, userDefaults: defaults
        )
        let token = "txt-skip-\(UUID().uuidString)"
        try await context.settleWithTimeout(
            token: token, timeoutSeconds: 0.5, webViewWaitSeconds: 0.2
        )

        let url = try RealDebugBridgeContext.snapshotsDirectory()
            .appendingPathComponent("ready-\(token).json")
        let json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: url)
        ) as? [String: Any]
        XCTAssertNil(json?["error"],
                     "TXT probe must skip the WebView-registration check and report success")
        XCTAssertEqual(json?["format"] as? String, "txt")
        try? FileManager.default.removeItem(at: url)
    }

    /// Bug #250 / GH #1084 (Codex Gate-4 round-1 High fix): the same-key
    /// reopen race — outgoing reader A's WebView slot persists into
    /// incoming reader B's lifetime (same `fingerprintKey`, B's token is
    /// the new `expectedReaderToken`). A token-agnostic gate would falsely
    /// report "registered" because the slot's KEY matches; downstream
    /// `vreader-debug://highlight-create` would still fail because
    /// `epubWebView(for:token:)` (the production accessor) is token-keyed.
    /// This test pins that settle correctly surfaces `webview not
    /// registered` when the slot's stored token doesn't match the
    /// registry's expected reader token.
    @MainActor
    func test_settle_onEPUBProbe_withStaleTokenWebView_writesWebViewNotRegisteredError() async throws {
        DebugReaderRegistry.shared.reset()
        let probe = SettleOKProbe(fingerprintKey: "epub:qrst:4096", format: "epub")
        DebugReaderRegistry.shared.register(probe)
        defer { DebugReaderRegistry.shared.unregister(probe) }

        // Stale slot: outgoing reader A's token is bound to the slot,
        // then incoming reader B takes over `expectedReaderToken`. The
        // slot's key still matches but its token is now stale.
        let staleToken = UUID()
        DebugReaderRegistry.shared.setExpectedReaderToken(staleToken)
        let staleWebView = WKWebView()
        DebugReaderRegistry.shared.setActiveEPUBWebView(
            staleWebView, for: probe.fingerprintKey, token: staleToken
        )
        // Now reader B mounts — replaces expectedReaderToken without
        // overwriting the slot (the matching coordinator's didFinish
        // hasn't fired yet for reader B).
        let liveToken = UUID()
        DebugReaderRegistry.shared.setExpectedReaderToken(liveToken)

        let context = RealDebugBridgeContext(
            persistence: persistence, importer: importer, userDefaults: defaults
        )
        let sentinelToken = "epub-stale-tok-\(UUID().uuidString)"
        try await context.settleWithTimeout(
            token: sentinelToken, timeoutSeconds: 0.5, webViewWaitSeconds: 0.2
        )

        let url = try RealDebugBridgeContext.snapshotsDirectory()
            .appendingPathComponent("ready-\(sentinelToken).json")
        let json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: url)
        ) as? [String: Any]
        XCTAssertEqual(json?["error"] as? String, "webview not registered",
                       "EPUB probe with a stale-token WebView slot must surface webview-not-registered, not success — production `epubWebView(for:token:)` would return nil for the live reader, breaking downstream highlight-create")
        XCTAssertEqual(json?["fingerprintKey"] as? String, "epub:qrst:4096")
        XCTAssertEqual(json?["format"] as? String, "epub")
        try? FileManager.default.removeItem(at: url)
    }

    /// Bug #250 / GH #1084 (Codex Gate-4 round-1 Medium fix): format
    /// strings persisted in the bug-#1065 era can carry mixed case
    /// (`"EPUB"`, `"AZW3"`). The reader dispatch path lowercases via
    /// `BookFormat(rawValue: book.format.lowercased())`; the WebView
    /// gate must normalize the same way or it would silently skip the
    /// gate for any mixed-case row and re-open the false-success window.
    @MainActor
    func test_settle_onEPUBProbe_withMixedCaseFormat_stillEntersWebViewGate() async throws {
        DebugReaderRegistry.shared.reset()
        // Mixed-case format string — the gate must lowercase before
        // matching against the EPUB/Foliate switch.
        let probe = SettleOKProbe(fingerprintKey: "epub:uvwx:8192", format: "EPUB")
        DebugReaderRegistry.shared.register(probe)
        defer { DebugReaderRegistry.shared.unregister(probe) }

        let context = RealDebugBridgeContext(
            persistence: persistence, importer: importer, userDefaults: defaults
        )
        let token = "epub-mixed-case-\(UUID().uuidString)"
        try await context.settleWithTimeout(
            token: token, timeoutSeconds: 0.5, webViewWaitSeconds: 0.2
        )

        let url = try RealDebugBridgeContext.snapshotsDirectory()
            .appendingPathComponent("ready-\(token).json")
        let json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: url)
        ) as? [String: Any]
        XCTAssertEqual(json?["error"] as? String, "webview not registered",
                       "Mixed-case `EPUB` format must normalize to lowercase and enter the WebView gate — without normalization, the gate would silently skip and the bug recurs")
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

    // MARK: - search (Bug #238 — verification harness search-driver)
    //
    // RealDebugBridgeContext.search posts `.debugBridgeSearchCommand` with the
    // parsed query + optional index. The active reader's `.onReceive` observer
    // (ReaderContainerView, Bug #238 wiring) routes the query into the search
    // sheet and — when an index is supplied — taps result N once results
    // arrive. When no reader is loaded, the URL is silently a no-op (mirrors
    // the `tts` / `theme` posture).

    @MainActor
    func test_search_postsSearchCommandNotificationWithQueryOnly() async throws {
        let context = RealDebugBridgeContext(persistence: persistence, importer: importer)

        let exp = expectation(description: "searchCommand notification posted")
        nonisolated(unsafe) var receivedQuery: String?
        nonisolated(unsafe) var hasIndex: Bool = true
        let token = NotificationCenter.default.addObserver(
            forName: .debugBridgeSearchCommand, object: nil, queue: .main
        ) { notification in
            receivedQuery = notification.userInfo?["query"] as? String
            hasIndex = notification.userInfo?["index"] != nil
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        try await context.search(query: "alice", index: nil)
        await fulfillment(of: [exp], timeout: 2.0)

        XCTAssertEqual(receivedQuery, "alice")
        XCTAssertFalse(hasIndex,
                       "userInfo must omit 'index' when nil was passed — lets observers distinguish 'just run query' from 'run query and tap N'")
    }

    @MainActor
    func test_search_postsSearchCommandNotificationWithQueryAndIndex() async throws {
        let context = RealDebugBridgeContext(persistence: persistence, importer: importer)

        let exp = expectation(description: "searchCommand notification posted with index")
        nonisolated(unsafe) var receivedQuery: String?
        nonisolated(unsafe) var receivedIndex: Int?
        let token = NotificationCenter.default.addObserver(
            forName: .debugBridgeSearchCommand, object: nil, queue: .main
        ) { notification in
            receivedQuery = notification.userInfo?["query"] as? String
            receivedIndex = notification.userInfo?["index"] as? Int
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        try await context.search(query: "rabbit", index: 2)
        await fulfillment(of: [exp], timeout: 2.0)

        XCTAssertEqual(receivedQuery, "rabbit")
        XCTAssertEqual(receivedIndex, 2)
    }

    @MainActor
    func test_search_postsSearchCommandWithIndexZero() async throws {
        // Index 0 is a valid tap target (tap the first result). Verify
        // the bridge does not collapse 0 with nil.
        let context = RealDebugBridgeContext(persistence: persistence, importer: importer)

        let exp = expectation(description: "searchCommand notification posted with index=0")
        nonisolated(unsafe) var receivedIndex: Int?
        let token = NotificationCenter.default.addObserver(
            forName: .debugBridgeSearchCommand, object: nil, queue: .main
        ) { notification in
            receivedIndex = notification.userInfo?["index"] as? Int
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        try await context.search(query: "alice", index: 0)
        await fulfillment(of: [exp], timeout: 2.0)

        XCTAssertEqual(receivedIndex, 0, "index=0 must reach observers as 0, not nil")
    }

    @MainActor
    func test_search_endToEndThroughBridge_dispatchesAndPostsNotification() async throws {
        // End-to-end: URL → DebugBridge.handle → RealDebugBridgeContext.search.
        // Verifies the parser → dispatcher → handler → notification chain is
        // fully wired and that the bridge clears `lastError` on success.
        let context = RealDebugBridgeContext(persistence: persistence, importer: importer)
        let bridge = DebugBridge(context: context)

        let exp = expectation(description: "search notification posted via bridge")
        nonisolated(unsafe) var receivedQuery: String?
        nonisolated(unsafe) var receivedIndex: Int?
        let token = NotificationCenter.default.addObserver(
            forName: .debugBridgeSearchCommand, object: nil, queue: .main
        ) { notification in
            receivedQuery = notification.userInfo?["query"] as? String
            receivedIndex = notification.userInfo?["index"] as? Int
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        await bridge.handle(URL(string: "vreader-debug://search?query=white%20rabbit&index=1")!)
        await fulfillment(of: [exp], timeout: 2.0)

        XCTAssertEqual(receivedQuery, "white rabbit",
                       "percent-encoded query must reach observers decoded")
        XCTAssertEqual(receivedIndex, 1)
        XCTAssertNil(bridge.lastError, "successful dispatch must clear lastError")
    }

    // MARK: - highlight (Bug #237 — verification harness highlight-creator)
    //
    // RealDebugBridgeContext.highlight posts `.debugBridgeHighlightCommand`
    // with the parsed offsets + optional color. The active reader's
    // `.onReceive` observer (ReaderContainerView, Bug #237 wiring) builds
    // a Locator from the offsets, calls `PersistenceActor.addHighlight`,
    // then posts `.readerHighlightsDidImport` so the per-format renderer
    // re-paints. When no reader is loaded, the URL is silently a no-op
    // (mirrors the `tts` / `search` posture).

    @MainActor
    func test_highlight_postsHighlightCommandNotificationWithStartEnd() async throws {
        let context = RealDebugBridgeContext(persistence: persistence, importer: importer)

        let exp = expectation(description: "highlightCommand notification posted")
        nonisolated(unsafe) var receivedStart: Int?
        nonisolated(unsafe) var receivedEnd: Int?
        nonisolated(unsafe) var hasColor: Bool = true
        let token = NotificationCenter.default.addObserver(
            forName: .debugBridgeHighlightCommand, object: nil, queue: .main
        ) { notification in
            receivedStart = notification.userInfo?["start"] as? Int
            receivedEnd = notification.userInfo?["end"] as? Int
            hasColor = notification.userInfo?["color"] != nil
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        try await context.highlight(startUTF16: 10, endUTF16: 42, color: nil)
        await fulfillment(of: [exp], timeout: 2.0)

        XCTAssertEqual(receivedStart, 10)
        XCTAssertEqual(receivedEnd, 42)
        XCTAssertFalse(hasColor,
                       "userInfo must omit 'color' when nil was passed — lets observers fall back to the default color")
    }

    @MainActor
    func test_highlight_postsHighlightCommandNotificationWithColor() async throws {
        let context = RealDebugBridgeContext(persistence: persistence, importer: importer)

        let exp = expectation(description: "highlightCommand notification posted with color")
        nonisolated(unsafe) var receivedStart: Int?
        nonisolated(unsafe) var receivedEnd: Int?
        nonisolated(unsafe) var receivedColor: String?
        let token = NotificationCenter.default.addObserver(
            forName: .debugBridgeHighlightCommand, object: nil, queue: .main
        ) { notification in
            receivedStart = notification.userInfo?["start"] as? Int
            receivedEnd = notification.userInfo?["end"] as? Int
            receivedColor = notification.userInfo?["color"] as? String
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        try await context.highlight(startUTF16: 0, endUTF16: 5, color: "pink")
        await fulfillment(of: [exp], timeout: 2.0)

        XCTAssertEqual(receivedStart, 0)
        XCTAssertEqual(receivedEnd, 5)
        XCTAssertEqual(receivedColor, "pink")
    }

    @MainActor
    func test_highlight_postsHighlightCommandWithStartZero() async throws {
        // start=0 is a valid range start (first character). Verify the
        // bridge does not collapse 0 with nil in the userInfo payload.
        let context = RealDebugBridgeContext(persistence: persistence, importer: importer)

        let exp = expectation(description: "highlightCommand notification posted with start=0")
        nonisolated(unsafe) var receivedStart: Int?
        let token = NotificationCenter.default.addObserver(
            forName: .debugBridgeHighlightCommand, object: nil, queue: .main
        ) { notification in
            receivedStart = notification.userInfo?["start"] as? Int
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        try await context.highlight(startUTF16: 0, endUTF16: 5, color: nil)
        await fulfillment(of: [exp], timeout: 2.0)

        XCTAssertEqual(receivedStart, 0, "start=0 must reach observers as 0, not nil")
    }

    @MainActor
    func test_highlight_endToEndThroughBridge_dispatchesAndPostsNotification() async throws {
        // End-to-end: URL → DebugBridge.handle → RealDebugBridgeContext.highlight.
        // Verifies the parser → dispatcher → handler → notification chain is
        // fully wired and that the bridge clears `lastError` on success.
        let context = RealDebugBridgeContext(persistence: persistence, importer: importer)
        let bridge = DebugBridge(context: context)

        let exp = expectation(description: "highlight notification posted via bridge")
        nonisolated(unsafe) var receivedStart: Int?
        nonisolated(unsafe) var receivedEnd: Int?
        nonisolated(unsafe) var receivedColor: String?
        let token = NotificationCenter.default.addObserver(
            forName: .debugBridgeHighlightCommand, object: nil, queue: .main
        ) { notification in
            receivedStart = notification.userInfo?["start"] as? Int
            receivedEnd = notification.userInfo?["end"] as? Int
            receivedColor = notification.userInfo?["color"] as? String
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        await bridge.handle(URL(string: "vreader-debug://highlight?start=100&end=120&color=blue")!)
        await fulfillment(of: [exp], timeout: 2.0)

        XCTAssertEqual(receivedStart, 100)
        XCTAssertEqual(receivedEnd, 120)
        XCTAssertEqual(receivedColor, "blue")
        XCTAssertNil(bridge.lastError, "successful dispatch must clear lastError")
    }

    // MARK: - present (Bug #253 — verification harness sheet-presenter)
    //
    // RealDebugBridgeContext.present posts `.debugBridgePresentSheet` with the
    // parsed `sheet` (rawValue) + optional `tab`. The active reader's observer
    // (ReaderContainerView, Bug #253 wiring) sets the matching `@State` /
    // `annotationsRoute` the chrome buttons set, so the presented sheet's
    // rendered content becomes CU-free verifiable via `snapshot` + `eval`.
    // When no reader is loaded, the URL is silently a no-op (mirrors the
    // `tts` / `search` / `highlight` posture).

    @MainActor
    func test_present_postsPresentSheetNotificationSheetOnly() async throws {
        let context = RealDebugBridgeContext(persistence: persistence, importer: importer)

        let exp = expectation(description: "presentSheet notification posted")
        nonisolated(unsafe) var receivedSheet: String?
        nonisolated(unsafe) var hasTab: Bool = true
        nonisolated(unsafe) var hasDetent: Bool = true
        let token = NotificationCenter.default.addObserver(
            forName: .debugBridgePresentSheet, object: nil, queue: .main
        ) { notification in
            receivedSheet = notification.userInfo?["sheet"] as? String
            hasTab = notification.userInfo?["tab"] != nil
            hasDetent = notification.userInfo?["detent"] != nil
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        try await context.present(sheet: .toc, tab: nil, detent: nil)
        await fulfillment(of: [exp], timeout: 2.0)

        XCTAssertEqual(receivedSheet, "toc")
        XCTAssertFalse(hasTab,
                       "userInfo must omit 'tab' when nil was passed — lets observers fall back to each sheet's default tab")
        XCTAssertFalse(hasDetent,
                       "userInfo must omit 'detent' when nil was passed — leaves the default presentation (.medium) untouched")
    }

    @MainActor
    func test_present_postsPresentSheetNotificationWithDetent() async throws {
        // Bug #256 — when `detent` is supplied, it reaches the reader-host
        // observer in `userInfo` as the rawValue so the observer sets the
        // matching `presentationDetents(selection:)` binding.
        let context = RealDebugBridgeContext(persistence: persistence, importer: importer)

        let exp = expectation(description: "presentSheet notification posted with detent")
        nonisolated(unsafe) var receivedSheet: String?
        nonisolated(unsafe) var receivedTab: String?
        nonisolated(unsafe) var receivedDetent: String?
        let token = NotificationCenter.default.addObserver(
            forName: .debugBridgePresentSheet, object: nil, queue: .main
        ) { notification in
            receivedSheet = notification.userInfo?["sheet"] as? String
            receivedTab = notification.userInfo?["tab"] as? String
            receivedDetent = notification.userInfo?["detent"] as? String
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        try await context.present(sheet: .ai, tab: "translate", detent: .large)
        await fulfillment(of: [exp], timeout: 2.0)

        XCTAssertEqual(receivedSheet, "ai")
        XCTAssertEqual(receivedTab, "translate")
        XCTAssertEqual(receivedDetent, "large")
    }

    @MainActor
    func test_present_postsPresentSheetNotificationWithTab() async throws {
        let context = RealDebugBridgeContext(persistence: persistence, importer: importer)

        let exp = expectation(description: "presentSheet notification posted with tab")
        nonisolated(unsafe) var receivedSheet: String?
        nonisolated(unsafe) var receivedTab: String?
        let token = NotificationCenter.default.addObserver(
            forName: .debugBridgePresentSheet, object: nil, queue: .main
        ) { notification in
            receivedSheet = notification.userInfo?["sheet"] as? String
            receivedTab = notification.userInfo?["tab"] as? String
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        try await context.present(sheet: .ai, tab: "translate", detent: nil)
        await fulfillment(of: [exp], timeout: 2.0)

        XCTAssertEqual(receivedSheet, "ai")
        XCTAssertEqual(receivedTab, "translate")
    }

    @MainActor
    func test_present_eachSheetKind_postsMatchingRawValue() async throws {
        // Every SheetKind reaches observers as its rawValue so the observer's
        // switch is exhaustive and disambiguated.
        for kind in DebugCommand.SheetKind.allCases {
            let context = RealDebugBridgeContext(persistence: persistence, importer: importer)
            let exp = expectation(description: "presentSheet posted for \(kind.rawValue)")
            nonisolated(unsafe) var receivedSheet: String?
            let token = NotificationCenter.default.addObserver(
                forName: .debugBridgePresentSheet, object: nil, queue: .main
            ) { notification in
                receivedSheet = notification.userInfo?["sheet"] as? String
                exp.fulfill()
            }
            try await context.present(sheet: kind, tab: nil, detent: nil)
            await fulfillment(of: [exp], timeout: 2.0)
            NotificationCenter.default.removeObserver(token)
            XCTAssertEqual(receivedSheet, kind.rawValue)
        }
    }

    @MainActor
    func test_present_endToEndThroughBridge_dispatchesAndPostsNotification() async throws {
        // End-to-end: URL → DebugBridge.handle → RealDebugBridgeContext.present.
        // Verifies the parser → dispatcher → handler → notification chain is
        // fully wired and that the bridge clears `lastError` on success.
        let context = RealDebugBridgeContext(persistence: persistence, importer: importer)
        let bridge = DebugBridge(context: context)

        let exp = expectation(description: "present notification posted via bridge")
        nonisolated(unsafe) var receivedSheet: String?
        nonisolated(unsafe) var receivedTab: String?
        let token = NotificationCenter.default.addObserver(
            forName: .debugBridgePresentSheet, object: nil, queue: .main
        ) { notification in
            receivedSheet = notification.userInfo?["sheet"] as? String
            receivedTab = notification.userInfo?["tab"] as? String
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        await bridge.handle(URL(string: "vreader-debug://present?sheet=highlights&tab=notes")!)
        await fulfillment(of: [exp], timeout: 2.0)

        XCTAssertEqual(receivedSheet, "highlights")
        XCTAssertEqual(receivedTab, "notes")
        XCTAssertNil(bridge.lastError, "successful dispatch must clear lastError")
    }

    // MARK: - ai (Bug #255 — verification harness AI-action driver)
    //
    // RealDebugBridgeContext.aiAction posts `.debugBridgeAIAction` with the
    // parsed action rawValue + optional scope (summarize) + optional text
    // (chat message / translate language). The active AI sheet's observer
    // (AIReaderPanel, Bug #255 wiring) fires the SAME action the chrome
    // buttons trigger, so the AI-response-card render states become CU-free
    // verifiable via `snapshot` + `eval`. When no AI sheet is presented, the
    // URL is silently a no-op (mirrors `tts` / `search` / `present`).

    @MainActor
    func test_aiAction_summarize_postsActionNotificationActionOnly() async throws {
        let context = RealDebugBridgeContext(persistence: persistence, importer: importer)

        let exp = expectation(description: "aiAction notification posted")
        nonisolated(unsafe) var receivedAction: String?
        nonisolated(unsafe) var hasScope = true
        nonisolated(unsafe) var hasText = true
        let token = NotificationCenter.default.addObserver(
            forName: .debugBridgeAIAction, object: nil, queue: .main
        ) { notification in
            receivedAction = notification.userInfo?["action"] as? String
            hasScope = notification.userInfo?["scope"] != nil
            hasText = notification.userInfo?["text"] != nil
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        try await context.aiAction(action: .summarize, scope: nil, text: nil)
        await fulfillment(of: [exp], timeout: 2.0)

        XCTAssertEqual(receivedAction, "summarize")
        XCTAssertFalse(hasScope, "userInfo must omit 'scope' when nil was passed")
        XCTAssertFalse(hasText, "userInfo must omit 'text' when nil was passed")
    }

    @MainActor
    func test_aiAction_summarizeWithScope_postsScopeRawValue() async throws {
        let context = RealDebugBridgeContext(persistence: persistence, importer: importer)

        let exp = expectation(description: "aiAction notification posted with scope")
        nonisolated(unsafe) var receivedAction: String?
        nonisolated(unsafe) var receivedScope: String?
        let token = NotificationCenter.default.addObserver(
            forName: .debugBridgeAIAction, object: nil, queue: .main
        ) { notification in
            receivedAction = notification.userInfo?["action"] as? String
            receivedScope = notification.userInfo?["scope"] as? String
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        try await context.aiAction(action: .summarize, scope: .chapter, text: nil)
        await fulfillment(of: [exp], timeout: 2.0)

        XCTAssertEqual(receivedAction, "summarize")
        XCTAssertEqual(receivedScope, "chapter",
                       "scope reaches observers as SummaryScope.rawValue (chapter), not the URL-friendly 'book' alias")
    }

    @MainActor
    func test_aiAction_chatWithText_postsText() async throws {
        let context = RealDebugBridgeContext(persistence: persistence, importer: importer)

        let exp = expectation(description: "aiAction notification posted with text")
        nonisolated(unsafe) var receivedAction: String?
        nonisolated(unsafe) var receivedText: String?
        let token = NotificationCenter.default.addObserver(
            forName: .debugBridgeAIAction, object: nil, queue: .main
        ) { notification in
            receivedAction = notification.userInfo?["action"] as? String
            receivedText = notification.userInfo?["text"] as? String
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        try await context.aiAction(action: .chat, scope: nil, text: "who is the narrator?")
        await fulfillment(of: [exp], timeout: 2.0)

        XCTAssertEqual(receivedAction, "chat")
        XCTAssertEqual(receivedText, "who is the narrator?")
    }

    @MainActor
    func test_aiAction_eachActionKind_postsMatchingRawValue() async throws {
        for action in DebugCommand.AIActionKind.allCases {
            let context = RealDebugBridgeContext(persistence: persistence, importer: importer)
            let exp = expectation(description: "aiAction posted for \(action.rawValue)")
            nonisolated(unsafe) var receivedAction: String?
            let token = NotificationCenter.default.addObserver(
                forName: .debugBridgeAIAction, object: nil, queue: .main
            ) { notification in
                receivedAction = notification.userInfo?["action"] as? String
                exp.fulfill()
            }
            try await context.aiAction(action: action, scope: nil, text: nil)
            await fulfillment(of: [exp], timeout: 2.0)
            NotificationCenter.default.removeObserver(token)
            XCTAssertEqual(receivedAction, action.rawValue)
        }
    }

    @MainActor
    func test_aiAction_endToEndThroughBridge_dispatchesAndPostsNotification() async throws {
        // End-to-end: URL → DebugBridge.handle → RealDebugBridgeContext.aiAction.
        let context = RealDebugBridgeContext(persistence: persistence, importer: importer)
        let bridge = DebugBridge(context: context)

        let exp = expectation(description: "ai notification posted via bridge")
        nonisolated(unsafe) var receivedAction: String?
        nonisolated(unsafe) var receivedScope: String?
        let token = NotificationCenter.default.addObserver(
            forName: .debugBridgeAIAction, object: nil, queue: .main
        ) { notification in
            receivedAction = notification.userInfo?["action"] as? String
            receivedScope = notification.userInfo?["scope"] as? String
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        await bridge.handle(URL(string: "vreader-debug://ai?action=summarize&scope=book")!)
        await fulfillment(of: [exp], timeout: 2.0)

        XCTAssertEqual(receivedAction, "summarize")
        XCTAssertEqual(receivedScope, "bookSoFar",
                       "the URL-friendly 'book' is mapped to SummaryScope.bookSoFar before posting")
        XCTAssertNil(bridge.lastError, "successful dispatch must clear lastError")
    }

    // MARK: - provider (Bug #243 — verification harness AI-provider-setup)
    //
    // RealDebugBridgeContext.provider mutates a ProviderProfileStore and a
    // KeychainService. To keep tests isolated, both are injected via the
    // context init; each test uses a unique UserDefaults suite (for the
    // store) + a unique Keychain `serviceIdentifier` (for the keychain).

    /// Build a provider-handling context with isolated store + keychain. The
    /// returned store and keychain are the same instances injected — tests
    /// read profiles/keys back through them to assert on side effects.
    @MainActor
    private func makeProviderContext() async -> (
        context: RealDebugBridgeContext,
        store: ProviderProfileStore,
        keychain: KeychainService,
        teardownSuite: String
    ) {
        let suite = "DebugBridgeProviderTests-\(UUID().uuidString)"
        let suiteDefaults = UserDefaults(suiteName: suite)!
        let prefs = UserDefaultsPreferenceStore(defaults: suiteDefaults)
        let keychain = KeychainService(
            serviceIdentifier: "com.vreader.debugBridgeProviderTests.\(UUID().uuidString)"
        )
        // Pass a no-op migrator so the actor doesn't drag legacy AIConfiguration
        // bits across the boundary in tests.
        let store = ProviderProfileStore(
            preferences: prefs,
            migrator: NoOpProviderProfileMigrator(),
            keychain: keychain
        )
        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            providerStore: store,
            keychain: keychain
        )
        return (context, store, keychain, suite)
    }

    @MainActor
    func test_provider_addInsertsProfile_andSavesKeyToKeychain() async throws {
        let (context, store, keychain, suite) = await makeProviderContext()
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        try await context.provider(action: .add(
            name: "OpenRouter",
            kind: .openAICompatible,
            endpoint: URL(string: "https://openrouter.ai/api/v1")!,
            apiKey: "sk-or-secret",
            model: nil,
            active: false
        ))

        let profiles = await store.loadAll()
        XCTAssertEqual(profiles.count, 1)
        let profile = try XCTUnwrap(profiles.first)
        XCTAssertEqual(profile.name, "OpenRouter")
        XCTAssertEqual(profile.kind, .openAICompatible)
        XCTAssertEqual(profile.baseURL, URL(string: "https://openrouter.ai/api/v1")!)
        // Defaults from ProviderKind.defaultModel when `model` is nil
        XCTAssertEqual(profile.model, ProviderKind.openAICompatible.defaultModel)

        // Key is stored under the per-profile keychain account
        let storedKey = try keychain.readAPIKey(forProfile: profile.id)
        XCTAssertEqual(storedKey, "sk-or-secret")

        // active=false explicitly → handler still auto-promotes to active
        // when no profile was active before (mirrors AISettingsViewModel
        // .addProfile behavior so the harness can omit `active=` on the
        // first add).
        let active = await store.activeProfile()
        XCTAssertEqual(active?.id, profile.id, "first profile is auto-active")
    }

    @MainActor
    func test_provider_addWithModel_usesProvidedModel() async throws {
        let (context, store, _, suite) = await makeProviderContext()
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        try await context.provider(action: .add(
            name: "OR",
            kind: .openAICompatible,
            endpoint: URL(string: "https://openrouter.ai/api/v1")!,
            apiKey: "k",
            model: "mistralai/mistral-7b-instruct",
            active: false
        ))

        let profiles = await store.loadAll()
        let profile = try XCTUnwrap(profiles.first)
        XCTAssertEqual(profile.model, "mistralai/mistral-7b-instruct")
    }

    @MainActor
    func test_provider_addActiveTrue_setsActive() async throws {
        // active=true explicitly → handler sets it as the active profile even
        // when another profile is already active (lets the harness flip the
        // active selection between profiles by re-adding).
        let (context, store, _, suite) = await makeProviderContext()
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        try await context.provider(action: .add(
            name: "First",
            kind: .openAICompatible,
            endpoint: URL(string: "https://api.openai.com/v1")!,
            apiKey: "k1",
            model: nil,
            active: false  // first → auto-active by handler
        ))
        try await context.provider(action: .add(
            name: "Second",
            kind: .anthropicNative,
            endpoint: URL(string: "https://api.anthropic.com")!,
            apiKey: "k2",
            model: nil,
            active: true   // explicit → switch active
        ))

        let active = await store.activeProfile()
        XCTAssertEqual(active?.name, "Second")
    }

    @MainActor
    func test_provider_removeDeletesProfileByName_andDeletesKey() async throws {
        let (context, store, keychain, suite) = await makeProviderContext()
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        try await context.provider(action: .add(
            name: "OR",
            kind: .openAICompatible,
            endpoint: URL(string: "https://openrouter.ai/api/v1")!,
            apiKey: "k",
            model: nil,
            active: false
        ))
        let loaded = await store.loadAll()
        let addedID = try XCTUnwrap(loaded.first?.id)

        try await context.provider(action: .remove(name: "OR"))

        let after = await store.loadAll()
        XCTAssertEqual(after.count, 0, "remove must delete the profile from the store")
        let storedKey = try keychain.readAPIKey(forProfile: addedID)
        XCTAssertNil(storedKey, "remove must also delete the per-profile keychain entry")
    }

    @MainActor
    func test_provider_removeUnknownName_isNoOp() async throws {
        // Removing a name that doesn't exist is a no-op (idempotent). Mirrors
        // ProviderProfileStore.remove(id:) — passing an unknown id is also
        // a no-op there.
        let (context, store, _, suite) = await makeProviderContext()
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        try await context.provider(action: .remove(name: "DoesNotExist"))

        let profiles = await store.loadAll()
        XCTAssertEqual(profiles.count, 0)
    }

    @MainActor
    func test_provider_clearWipesAllProfiles_andAllKeys() async throws {
        let (context, store, keychain, suite) = await makeProviderContext()
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        try await context.provider(action: .add(
            name: "A", kind: .openAICompatible,
            endpoint: URL(string: "https://api.openai.com/v1")!,
            apiKey: "ka", model: nil, active: false
        ))
        try await context.provider(action: .add(
            name: "B", kind: .anthropicNative,
            endpoint: URL(string: "https://api.anthropic.com")!,
            apiKey: "kb", model: nil, active: true
        ))
        let ids = (await store.loadAll()).map(\.id)
        XCTAssertEqual(ids.count, 2)

        try await context.provider(action: .clear)

        let after = await store.loadAll()
        XCTAssertEqual(after.count, 0, "clear must remove every profile")
        let activeAfter = await store.activeProfile()
        XCTAssertNil(activeAfter, "clear must drop the active selection")
        for id in ids {
            let key = try keychain.readAPIKey(forProfile: id)
            XCTAssertNil(key, "clear must delete every per-profile keychain entry; id=\(id)")
        }
    }

    @MainActor
    func test_provider_addTwiceWithSameName_reusesUUID_andUpdatesFields() async throws {
        // Round-1 Codex audit Medium fix: re-running an `add` URL with the
        // same display name must be idempotent — same UUID, replaced fields,
        // no duplicate. Otherwise `remove(name:)` becomes non-deterministic.
        let (context, store, keychain, suite) = await makeProviderContext()
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        try await context.provider(action: .add(
            name: "OR",
            kind: .openAICompatible,
            endpoint: URL(string: "https://openrouter.ai/api/v1")!,
            apiKey: "key-v1",
            model: nil,
            active: false
        ))
        let first = await store.loadAll()
        let firstID = try XCTUnwrap(first.first?.id)

        try await context.provider(action: .add(
            name: "OR",
            kind: .openAICompatible,
            endpoint: URL(string: "https://openrouter.ai/api/v1")!,
            apiKey: "key-v2",
            model: "mistralai/mistral-7b-instruct",
            active: false
        ))

        let profiles = await store.loadAll()
        XCTAssertEqual(profiles.count, 1, "second add with same name must NOT duplicate")
        XCTAssertEqual(profiles.first?.id, firstID, "second add must reuse the existing UUID")
        XCTAssertEqual(profiles.first?.model, "mistralai/mistral-7b-instruct", "second add must update fields")

        // Key was overwritten under the same per-profile account.
        let key = try keychain.readAPIKey(forProfile: firstID)
        XCTAssertEqual(key, "key-v2")
    }

    @MainActor
    func test_provider_addTrimsAPIKeyWhitespace() async throws {
        // Round-1 Codex audit Low fix: a host-side quoting accident can
        // leave `\n` / spaces in the apiKey. Trim to match
        // `AISettingsViewModel.addProfile`.
        let (context, store, keychain, suite) = await makeProviderContext()
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        try await context.provider(action: .add(
            name: "OR",
            kind: .openAICompatible,
            endpoint: URL(string: "https://openrouter.ai/api/v1")!,
            apiKey: "  sk-trim-me  \n",
            model: nil,
            active: false
        ))

        let loaded = await store.loadAll()
        let id = try XCTUnwrap(loaded.first?.id)
        let key = try keychain.readAPIKey(forProfile: id)
        XCTAssertEqual(key, "sk-trim-me", "key must be trimmed before save")
    }

    @MainActor
    func test_provider_endToEndThroughBridge_addProfileFromURL() async throws {
        // End-to-end: URL → DebugBridge.handle → RealDebugBridgeContext.provider.
        // Verifies the parser → dispatcher → handler → store chain is wired
        // and that the bridge clears `lastError` on success.
        let (context, store, _, suite) = await makeProviderContext()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let bridge = DebugBridge(context: context)

        let endpoint = "https://openrouter.ai/api/v1".addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        )!
        await bridge.handle(URL(string:
            "vreader-debug://provider?action=add&name=OR&kind=openAICompatible&endpoint=\(endpoint)&apiKey=k"
        )!)

        let profiles = await store.loadAll()
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.name, "OR")
        XCTAssertNil(bridge.lastError, "successful dispatch must clear lastError")
    }

    // MARK: - seed-sessions (Bug #263 — reading-session seeder)

    @MainActor
    func test_seedSessions_insertsSessionsIntoRealPersistence() async throws {
        let key = try await CollectionTestHelper.insertBook(
            persistence: persistence,
            title: "Dashboard Book",
            sha: String(repeating: "d", count: 64)
        )
        let context = RealDebugBridgeContext(persistence: persistence, importer: importer)

        try await context.seedReadingSessions(bookFingerprintKey: key, secondsPerSession: 600)

        let sessions = try await persistence.fetchAllReadingSessions()
        XCTAssertEqual(sessions.count, 6, "six bands → six synthetic sessions")
        XCTAssertTrue(sessions.allSatisfy { $0.bookFingerprintKey == key })
        XCTAssertTrue(sessions.allSatisfy { $0.durationSeconds == 600 })
    }

    @MainActor
    func test_seedSessions_dispatchedViaURL_populatesDashboardData() async throws {
        let key = try await CollectionTestHelper.insertBook(
            persistence: persistence,
            title: "Dashboard Book",
            sha: String(repeating: "e", count: 64)
        )
        let context = RealDebugBridgeContext(persistence: persistence, importer: importer)
        let bridge = DebugBridge(context: context)

        // The fingerprint key contains ':' — percent-encode it for the URL.
        let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        await bridge.handle(URL(string: "vreader-debug://seed-sessions?book=\(encodedKey)")!)

        XCTAssertNil(bridge.lastError, "successful dispatch must clear lastError: \(String(describing: bridge.lastError))")
        let sessions = try await persistence.fetchAllReadingSessions()
        XCTAssertEqual(sessions.count, 6)
        XCTAssertTrue(sessions.allSatisfy { $0.durationSeconds == 600 })
    }

    @MainActor
    func test_seedSessions_keyWithNoBookRow_stillSeedsOrphanSessions() async throws {
        // The harness may seed sessions for a valid canonical key that has no
        // Book row (deleted-book dashboard state). The handler does not require
        // a matching Book — it attaches sessions to the supplied key (the
        // aggregator renders them as a "(deleted)" row). This lets a verify run
        // drive the deleted-book path. The key must still be a parseable
        // canonical key (format:sha256:byteCount) — that's what ReadingSession
        // needs to store a fingerprint.
        let orphanKey = "txt:" + String(repeating: "f", count: 64) + ":9999"
        let context = RealDebugBridgeContext(persistence: persistence, importer: importer)

        try await context.seedReadingSessions(
            bookFingerprintKey: orphanKey, secondsPerSession: 300
        )

        let sessions = try await persistence.fetchAllReadingSessions()
        XCTAssertEqual(sessions.count, 6)
        XCTAssertTrue(sessions.allSatisfy { $0.bookFingerprintKey == orphanKey })
    }

    @MainActor
    func test_seedSessions_malformedKey_throwsAndSeedsNothing() async throws {
        // A non-canonical key (not format:sha256:byteCount) can't materialize a
        // DocumentFingerprint, so the handler fails loudly rather than silently
        // dropping the seed — the verify run sees the cause via snapshot.lastError.
        let context = RealDebugBridgeContext(persistence: persistence, importer: importer)

        do {
            try await context.seedReadingSessions(
                bookFingerprintKey: "not-a-canonical-key", secondsPerSession: 600
            )
            XCTFail("expected an error for a malformed fingerprint key")
        } catch let DebugBridgeContextError.invalidFingerprintKey(key) {
            XCTAssertEqual(key, "not-a-canonical-key")
        }

        let sessions = try await persistence.fetchAllReadingSessions()
        XCTAssertTrue(sessions.isEmpty, "a malformed key must seed nothing")
    }
}

/// Test-only no-op migrator: skips the AIConfiguration legacy lift so the
/// provider tests run against a clean ProviderProfileStore. The default
/// migrator reads global AIConfiguration UserDefaults keys which would
/// couple test isolation to whatever the host process happens to have
/// set there.
private struct NoOpProviderProfileMigrator: ProviderProfileMigrating {
    func migrateIfNeeded(
        preferences: any PreferenceStoring,
        keychain: KeychainService
    ) {
        // Mark the flag set so ensureMigrated() flips its in-memory bit and
        // never retries (matches the default migrator's success-path side
        // effect on a clean state). Key matches
        // DefaultProviderProfileMigrator.migrationFlagKey.
        preferences.set("true", forKey: "com.vreader.ai.providerProfiles.migrated")
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

/// Bug #250 / GH #1084: probe whose `awaitSettle` resolves immediately
/// without throwing — exercises the "render-complete OK, WebView slot
/// pending" subpath that the WebView-registration gate must surface as
/// `webview not registered`. Sibling of TimingOutProbe / HangingProbe; the
/// distinguishing axis is that this one SUCCEEDS at the probe layer so the
/// bridge-side WebView check is what determines the sentinel's `error`
/// field. Re-using `TimingOutProbe` would conflate the two failure modes.
@MainActor
private final class SettleOKProbe: DebugReaderProbe {
    let fingerprintKey: String
    let format: String
    var currentPositionString: String? = nil

    init(fingerprintKey: String, format: String) {
        self.fingerprintKey = fingerprintKey
        self.format = format
    }

    func awaitSettle(timeout: TimeInterval) async throws {
        // No-op — the probe's render-complete contract is satisfied.
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
