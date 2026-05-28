// Purpose: Feature #42 Phase 1 WI-1 smoke test — proves the Readium Swift
// Toolkit links into the test/app target and that a real EPUB opens through
// the Readium 3.x opening flow (AssetRetriever → PublicationOpener with
// DefaultPublicationParser). This is a genuine open (no mock): it parses the
// bundled `mini-epub3.epub` DebugFixture and asserts the resulting
// Publication exposes a non-empty reading order (spine) and a metadata title.
//
// WI-1 is dependency + smoke only: no dispatch change, no feature flag, no
// reader host. Those land in later WIs.
//
// @coordinates-with: project.yml (Readium SPM dependency)

#if DEBUG

import Testing
import Foundation
import ReadiumShared
import ReadiumStreamer
@testable import vreader

@Suite("ReadiumOpenSmoke")
struct ReadiumOpenSmokeTests {

    /// Resolves the bundled `mini-epub3.epub` DebugFixture (DEBUG-only — copied
    /// into the app bundle's `DebugFixtures/` subdirectory by project.yml's
    /// pre-build script; the test target is hosted in the app, so `Bundle.main`
    /// resolves to the app bundle). Mirrors the `mini-azw3` fixture precedent
    /// in MOBIMetadataParserTests.
    private func miniEPUBURL() throws -> URL {
        try #require(
            Bundle.main.url(
                forResource: "mini-epub3",
                withExtension: "epub",
                subdirectory: RealDebugBridgeContext.fixtureBundleSubdirectory
            ),
            "mini-epub3.epub must be bundled under DebugFixtures/ in DEBUG builds"
        )
    }

    /// Copies the fixture to a fresh temp file so Readium opens a plain on-disk
    /// file URL (independent of bundle-resource read constraints). Returns the
    /// temp file's `FileURL` (an `AbsoluteURL`).
    private func tempFixtureFileURL() throws -> FileURL {
        let src = try miniEPUBURL()
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("readium-smoke-\(UUID().uuidString).epub")
        try FileManager.default.copyItem(at: src, to: tmp)
        return try #require(FileURL(url: tmp), "temp fixture path must form a FileURL")
    }

    /// Builds the canonical Readium 3.x opener (matches the toolkit TestApp's
    /// `Readium` wiring): a DefaultHTTPClient feeding an AssetRetriever and a
    /// DefaultPublicationParser. No GCDWebServer adapter, no LCP.
    private func makeOpener() -> (AssetRetriever, PublicationOpener) {
        let httpClient = DefaultHTTPClient()
        let assetRetriever = AssetRetriever(httpClient: httpClient)
        let opener = PublicationOpener(
            parser: DefaultPublicationParser(
                httpClient: httpClient,
                assetRetriever: assetRetriever,
                pdfFactory: DefaultPDFDocumentFactory()
            )
        )
        return (assetRetriever, opener)
    }

    // MARK: - Happy path

    @Test func opensBundledEPUB_yieldsReadingOrderAndTitle() async throws {
        let fileURL = try tempFixtureFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.url) }

        let (assetRetriever, opener) = makeOpener()

        let asset = try await assetRetriever.retrieve(url: fileURL).get()
        let publication = try await opener.open(
            asset: asset,
            allowUserInteraction: false
        ).get()

        // Proves the toolkit linked + parsed a real EPUB: spine + title present.
        #expect(!publication.readingOrder.isEmpty,
                "Readium must parse a non-empty reading order (spine) from mini-epub3")
        let title = publication.metadata.title
        #expect(title?.isEmpty == false,
                "Readium must surface a non-empty metadata title (mini-epub3 has dc:title)")
        #expect(title == "VReader Mini EPUB Fixture",
                "mini-epub3's dc:title must round-trip through Readium's metadata")
    }

    // MARK: - Edge case — nonexistent file fails cleanly (no crash)

    @Test func opensMissingFile_failsWithoutCrashing() async throws {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("readium-smoke-missing-\(UUID().uuidString).epub")
        let fileURL = try #require(FileURL(url: missing))
        let (assetRetriever, _) = makeOpener()

        let result = await assetRetriever.retrieve(url: fileURL)
        switch result {
        case .success:
            Issue.record("Retrieving a nonexistent EPUB must not succeed")
        case .failure:
            break // expected — error surfaced, no crash
        }
    }
}

#endif
