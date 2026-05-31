// Purpose: Tests for DebugFixtureCatalog — the static list of fixture books
// available to the vreader-debug://seed command (feature #44 DebugBridge).
// Verifies catalog entries by name, format, unknown-name behavior, and that
// every catalog row resolves to a real bundle resource.

#if DEBUG

import XCTest
@testable import vreader

final class DebugFixtureCatalogTests: XCTestCase {

    func test_all_returnsKnownFixtureNames() {
        let names = DebugFixtureCatalog.all().map { $0.name }
        XCTAssertEqual(Set(names), [
            "war-and-peace", "mini-epub3", "mini-azw3", "mini-markdown",
            "multi-chapter-epub", "multi-page-pdf",
            "mini-epub2", "mini-rtl", "mini-cjk", "mini-cjk-vlong",
        ])
    }

    /// Feature #42 WI-13: the Readium Phase-1 acceptance corpus — EPUB2 / RTL /
    /// CJK. Each must resolve to a real `.epub` bundle resource (the
    /// `test_all_entriesResolveInTheTestBundle` gate enforces presence; these
    /// pin the name/format/resource shape).
    func test_find_readiumAcceptanceCorpus_returnsEPUBFixtures() throws {
        for name in ["mini-epub2", "mini-rtl", "mini-cjk"] {
            let entry = try XCTUnwrap(
                DebugFixtureCatalog.find(name: name),
                "catalog should contain the \(name) acceptance fixture"
            )
            XCTAssertEqual(entry.name, name)
            XCTAssertEqual(entry.format, .epub)
            XCTAssertEqual(entry.resourceName, name)
            XCTAssertEqual(entry.resourceExtension, "epub")
        }
    }

    /// Feature #70 WI-4: the MD fixture added so the `.md` reader path is
    /// automatable for the cross-format calibration acceptance pass.
    func test_find_miniMarkdown_returnsMDFixture() throws {
        let entry = try XCTUnwrap(DebugFixtureCatalog.find(name: "mini-markdown"))
        XCTAssertEqual(entry.name, "mini-markdown")
        XCTAssertEqual(entry.format, .md)
        XCTAssertEqual(entry.resourceName, "mini-markdown")
        XCTAssertEqual(entry.resourceExtension, "md")
    }

    func test_find_miniEpub3_returnsEPUBFixture() throws {
        let entry = try XCTUnwrap(DebugFixtureCatalog.find(name: "mini-epub3"))
        XCTAssertEqual(entry.name, "mini-epub3")
        XCTAssertEqual(entry.format, .epub)
        XCTAssertEqual(entry.resourceName, "mini-epub3")
        XCTAssertEqual(entry.resourceExtension, "epub")
    }

    func test_find_miniAzw3_returnsAZW3Fixture() throws {
        let entry = try XCTUnwrap(DebugFixtureCatalog.find(name: "mini-azw3"))
        XCTAssertEqual(entry.name, "mini-azw3")
        XCTAssertEqual(entry.format, .azw3)
        XCTAssertEqual(entry.resourceName, "mini-azw3")
        XCTAssertEqual(entry.resourceExtension, "azw3")
    }

    func test_find_byName_returnsMatchingFixture() throws {
        let entry = try XCTUnwrap(DebugFixtureCatalog.find(name: "war-and-peace"))
        XCTAssertEqual(entry.name, "war-and-peace")
        XCTAssertEqual(entry.format, .txt)
        XCTAssertEqual(entry.resourceName, "war-and-peace")
        XCTAssertEqual(entry.resourceExtension, "txt")
    }

    func test_find_unknownName_returnsNil() {
        XCTAssertNil(DebugFixtureCatalog.find(name: "definitely-not-a-fixture"))
    }

    func test_find_emptyName_returnsNil() {
        XCTAssertNil(DebugFixtureCatalog.find(name: ""))
    }

    func test_all_entriesHaveDistinctNames() {
        let names = DebugFixtureCatalog.all().map { $0.name }
        XCTAssertEqual(names.count, Set(names).count, "fixture names must be unique")
    }

    func test_all_entriesHaveValidFormatAndResource() {
        for fixture in DebugFixtureCatalog.all() {
            XCTAssertFalse(fixture.name.isEmpty, "name empty for \(fixture)")
            XCTAssertFalse(fixture.resourceName.isEmpty, "resourceName empty for \(fixture)")
            XCTAssertFalse(fixture.resourceExtension.isEmpty, "resourceExtension empty for \(fixture)")
        }
    }

    /// Every catalog entry must resolve to a real bundle resource.
    /// This is the gate that prevents catalog/bundle drift — adding a row
    /// without dropping the file fails this test. It also doubles as a
    /// regression gate for bug #124: the lookup must use the same
    /// `subdirectory:` argument the production handler uses, so a future
    /// regression in either place fails this test.
    func test_all_entriesResolveInTheTestBundle() {
        // The DEBUG main bundle (when running tests) contains the app's
        // bundled resources. DebugFixtures are copied into the
        // `DebugFixtures/` subdirectory by `project.yml`'s pre-build
        // script — see `RealDebugBridgeContext.fixtureBundleSubdirectory`
        // for the single source of truth.
        for fixture in DebugFixtureCatalog.all() {
            let url = Bundle.main.url(
                forResource: fixture.resourceName,
                withExtension: fixture.resourceExtension,
                subdirectory: RealDebugBridgeContext.fixtureBundleSubdirectory
            )
            XCTAssertNotNil(
                url,
                "fixture \(fixture.name) declares \(fixture.resourceName).\(fixture.resourceExtension) under \(RealDebugBridgeContext.fixtureBundleSubdirectory)/ but the bundle has no such file"
            )
        }
    }
}

#endif
