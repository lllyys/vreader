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
    /// rooted at that directory. Bundle.url(forResource:withExtension:) finds
    /// loose files in any directory you point it at.
    private func makeFixtureBundle(name: String, ext: String, contents: String) throws -> Bundle {
        let path = fixtureBundleDir.appendingPathComponent("\(name).\(ext)")
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
        // Pre-set to dark so we can verify mode=light flips it back
        let pre = ReaderSettingsStore(defaults: defaults)
        pre.theme = .dark

        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        try await context.theme(mode: .light, fontSize: nil)

        let store = ReaderSettingsStore(defaults: defaults)
        XCTAssertEqual(store.theme, .light)
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

    // MARK: - snapshot

    @MainActor
    func test_snapshot_writesValidJSONWithDocumentedShape() async throws {
        // Pre-set theme so snapshot has something to encode
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

        XCTAssertEqual(snap.schemaVersion, 1)
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
        // partial lists fields whose nil means "not yet implemented"
        XCTAssertEqual(
            Set(snap.partial ?? []),
            Set(["currentBookId", "format", "position", "selection"])
        )

        // Cleanup
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
    func test_open_withNonNilPosition_throwsNotImplemented() async throws {
        // v0 rejects position rather than silently ignoring it. Repros that
        // depend on opening at a specific location fail loudly instead of
        // opening at the wrong place.
        let key = try await CollectionTestHelper.insertBook(
            persistence: persistence,
            title: "Openable",
            sha: String(repeating: "9", count: 64)
        )

        let context = RealDebugBridgeContext(
            persistence: persistence,
            importer: importer,
            userDefaults: defaults
        )
        do {
            try await context.open(bookId: key, position: "epubcfi(/6/4)")
            XCTFail("expected notImplemented for non-nil position")
        } catch DebugBridgeContextError.notImplemented(let cmd) {
            XCTAssertEqual(cmd, "open.position")
        } catch {
            XCTFail("expected notImplemented, got \(error)")
        }
    }

    @MainActor
    func test_open_nonNilPosition_doesNotPostNotification() async throws {
        // Verify the position-rejected case doesn't leak a partial side effect.
        let key = try await CollectionTestHelper.insertBook(
            persistence: persistence,
            title: "Openable",
            sha: String(repeating: "8", count: 64)
        )

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
            try await context.open(bookId: key, position: "p:42")
            XCTFail("expected throw")
        } catch DebugBridgeContextError.notImplemented {
            // expected
        }
        await fulfillment(of: [exp], timeout: 0.5)
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

#endif
