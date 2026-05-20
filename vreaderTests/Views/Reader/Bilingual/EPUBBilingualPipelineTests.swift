// Purpose: Feature #56 WI-10 — pin the parser + pipeline glue that
// converts a raw `bilingualEnumerate` message payload into a
// `[BilingualBlock]` value array, and that maps cached translations
// onto a `[String: String]` table keyed by `data-vreader-bid`.
//
// The pipeline glue is the testable seam between the EPUB
// WKWebView (which posts a JS `[{bid, text}]` payload) and
// `BilingualReadingViewModel.translationsByUnit` (which stores
// the ordered translated segments). The View-layer wiring that
// invokes the pipeline lives in `EPUBReaderContainerView+Bilingual`
// and is exercised at slice-verification time, not here.
//
// @coordinates-with: EPUBBilingualPipeline.swift, EPUBBilingualJS.swift,
//   BilingualReadingViewModel.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-10)

import Testing
@testable import vreader

@Suite("Feature #56 WI-10 — EPUBBilingualPipeline")
struct EPUBBilingualPipelineTests {

    // MARK: - Message parsing

    @Test("parseEnumerateMessage decodes a {bid, text}[] payload")
    func parseValidPayload() {
        let body: Any = [
            ["bid": "b1", "text": "Hello world"],
            ["bid": "b2", "text": "Bonjour"]
        ]
        let blocks = EPUBBilingualPipeline.parseEnumerateMessage(body)
        #expect(blocks.count == 2)
        #expect(blocks[0].bid == "b1")
        #expect(blocks[0].text == "Hello world")
        #expect(blocks[1].bid == "b2")
        #expect(blocks[1].text == "Bonjour")
    }

    @Test("parseEnumerateMessage tolerates a non-array body")
    func parseNonArrayPayload() {
        let body: Any = "not an array"
        let blocks = EPUBBilingualPipeline.parseEnumerateMessage(body)
        #expect(blocks.isEmpty)
    }

    @Test("parseEnumerateMessage drops malformed entries")
    func parseMalformedEntries() {
        // Mix valid + malformed: a valid entry, a missing-text entry,
        // a missing-bid entry, a non-dict entry, and another valid
        // entry. The parser must keep both valid entries and drop the
        // rest without throwing.
        let body: Any = [
            ["bid": "b1", "text": "Hello"],
            ["bid": "b2"],
            ["text": "orphan"],
            "string-not-dict",
            ["bid": "b3", "text": "World"]
        ]
        let blocks = EPUBBilingualPipeline.parseEnumerateMessage(body)
        #expect(blocks.count == 2)
        #expect(blocks.map(\.bid) == ["b1", "b3"])
    }

    @Test("parseEnumerateMessage drops entries with empty bid or text")
    func parseEmptyFieldsDropped() {
        let body: Any = [
            ["bid": "", "text": "Hello"],
            ["bid": "b2", "text": ""],
            ["bid": "b3", "text": "World"]
        ]
        let blocks = EPUBBilingualPipeline.parseEnumerateMessage(body)
        #expect(blocks.count == 1)
        #expect(blocks[0].bid == "b3")
    }

    // MARK: - Translation lookup

    @Test("translationsByBid emits an empty map when no translations are cached")
    func translationsByBidEmpty() {
        let blocks = [
            BilingualBlock(bid: "b1", text: "Hello"),
            BilingualBlock(bid: "b2", text: "World")
        ]
        let table = EPUBBilingualPipeline.translationsByBid(
            blocks: blocks, translatedSegments: nil)
        #expect(table.isEmpty)
    }

    @Test("translationsByBid maps each block to its translation by index")
    func translationsByBidMapsByIndex() {
        let blocks = [
            BilingualBlock(bid: "b1", text: "Hello"),
            BilingualBlock(bid: "b2", text: "World")
        ]
        let table = EPUBBilingualPipeline.translationsByBid(
            blocks: blocks, translatedSegments: ["Bonjour", "Monde"])
        #expect(table.count == 2)
        #expect(table["b1"] == "Bonjour")
        #expect(table["b2"] == "Monde")
    }

    @Test("translationsByBid truncates extra translation segments")
    func translationsByBidTruncatesExtras() {
        // The translation array is N elements but the enumerate
        // payload had only 2 blocks. The pipeline maps the first 2
        // and drops the rest — a renderer can never inject without
        // a matching bid.
        let blocks = [
            BilingualBlock(bid: "b1", text: "Hello"),
            BilingualBlock(bid: "b2", text: "World")
        ]
        let table = EPUBBilingualPipeline.translationsByBid(
            blocks: blocks,
            translatedSegments: ["Bonjour", "Monde", "Extra"]
        )
        #expect(table.count == 2)
        #expect(table["b1"] == "Bonjour")
        #expect(table["b2"] == "Monde")
        #expect(!table.keys.contains("b3"))
    }

    @Test("translationsByBid pads short translation arrays with no entry")
    func translationsByBidShortArrayPartialMap() {
        // The translation array is shorter than the enumerate payload
        // — the renderer should inject what it has and leave the rest
        // as source-only (silent-source-fallback semantics).
        let blocks = [
            BilingualBlock(bid: "b1", text: "Hello"),
            BilingualBlock(bid: "b2", text: "World"),
            BilingualBlock(bid: "b3", text: "Goodbye")
        ]
        let table = EPUBBilingualPipeline.translationsByBid(
            blocks: blocks,
            translatedSegments: ["Bonjour", "Monde"]
        )
        #expect(table.count == 2)
        #expect(table["b1"] == "Bonjour")
        #expect(table["b2"] == "Monde")
        #expect(table["b3"] == nil)
    }
}
