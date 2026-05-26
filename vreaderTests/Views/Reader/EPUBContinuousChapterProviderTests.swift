// Purpose: Feature #71 WI-6a — tests for EPUBContinuousChapterProvider, the
// testable factory that maps a spine index to a rewritten EPUBChapterBody
// (the closure the WI-6b continuous-scroll coordinator is built with). Uses a
// stub parser so no real EPUB archive is needed.
//
// @coordinates-with: EPUBContinuousChapterProvider.swift,
//   EPUBChapterBodyRewriter.swift, EPUBParserProtocol.swift, EPUBTypes.swift

import Testing
import Foundation
@testable import vreader

@MainActor
@Suite("EPUBContinuousChapterProvider (Feature #71 WI-6a)")
struct EPUBContinuousChapterProviderTests {

    /// Minimal EPUBParserProtocol stub: returns canned XHTML keyed by href.
    final class StubParser: EPUBParserProtocol, @unchecked Sendable {
        var contentByHref: [String: String] = [:]
        private(set) var requestedHrefs: [String] = []

        func open(url: URL) async throws -> EPUBMetadata {
            EPUBMetadata(title: "", author: nil, language: nil,
                         readingDirection: .ltr, layout: .reflowable,
                         spineItems: [], coverImageHref: nil)
        }
        func close() async {}
        func contentForSpineItem(href: String) async throws -> String {
            requestedHrefs.append(href)
            return contentByHref[href] ?? "<html><body><p>missing</p></body></html>"
        }
        func resourceBaseURL() async throws -> URL { URL(fileURLWithPath: "/tmp") }
        func extractedRootURL() async throws -> URL { URL(fileURLWithPath: "/tmp") }
        var isOpen: Bool { get async { true } }
    }

    private func makeProvider(_ parser: StubParser, hrefs: [String]) -> EPUBContinuousChapterProvider {
        let items = hrefs.enumerated().map { idx, href in
            EPUBSpineItem(id: href, href: href, title: nil, index: idx)
        }
        return EPUBContinuousChapterProvider(
            spineItems: items,
            parser: parser,
            resourceBaseAbsolutePrefix: "file:///book/",
            linkedStylesheetLoader: { _ in nil }
        )
    }

    @Test("body(spineIndex:) fetches the index's href, rewrites it, tags the spine index")
    func bodyForIndexRewritesHref() async throws {
        let parser = StubParser()
        parser.contentByHref["ch1.xhtml"] = "<html><body><p>Chapter One body.</p></body></html>"
        parser.contentByHref["ch2.xhtml"] = "<html><body><p>Chapter Two body.</p></body></html>"
        let provider = makeProvider(parser, hrefs: ["ch1.xhtml", "ch2.xhtml"])

        let body = try await provider.body(spineIndex: 1)
        #expect(body.spineIndex == 1)
        #expect(body.href == "ch2.xhtml")
        #expect(body.bodyHTML.contains("Chapter Two body."))
        #expect(parser.requestedHrefs == ["ch2.xhtml"])  // fetched the right href
    }

    @Test("out-of-range spine index throws (no parser fetch)")
    func outOfRangeThrows() async {
        let parser = StubParser()
        let provider = makeProvider(parser, hrefs: ["ch1.xhtml"])
        await #expect(throws: EPUBContinuousChapterProvider.ProviderError.spineIndexOutOfRange(5)) {
            _ = try await provider.body(spineIndex: 5)
        }
        #expect(parser.requestedHrefs.isEmpty)
    }

    @Test("negative spine index throws")
    func negativeIndexThrows() async {
        let parser = StubParser()
        let provider = makeProvider(parser, hrefs: ["ch1.xhtml"])
        await #expect(throws: EPUBContinuousChapterProvider.ProviderError.spineIndexOutOfRange(-1)) {
            _ = try await provider.body(spineIndex: -1)
        }
    }

    @Test("empty spine throws for index 0")
    func emptySpineThrows() async {
        let parser = StubParser()
        let provider = makeProvider(parser, hrefs: [])
        await #expect(throws: EPUBContinuousChapterProvider.ProviderError.spineIndexOutOfRange(0)) {
            _ = try await provider.body(spineIndex: 0)
        }
    }

    @Test("makeClosure() returns a (Int) async throws -> EPUBChapterBody usable as the coordinator's provider")
    func makeClosureProducesBody() async throws {
        let parser = StubParser()
        parser.contentByHref["a.xhtml"] = "<html><body><p>Alpha.</p></body></html>"
        let provider = makeProvider(parser, hrefs: ["a.xhtml"])
        let closure = provider.makeClosure()
        let body = try await closure(0)
        #expect(body.spineIndex == 0)
        #expect(body.href == "a.xhtml")
    }
}
