// Purpose: Feature #56 WI-11 — pin the parser + pipeline glue that
// converts a raw Foliate `bilingualEnumerate` message payload into
// a `[BilingualBlock]` value array, and that maps cached translations
// onto a `[String: String]` table keyed by `data-vreader-bid`.
//
// The Foliate enumerate JS emits the same `{bid, text}` payload
// shape the EPUB renderer does — the pipeline glue is reused
// structurally (same `BilingualBlock` value type from WI-10) but
// gets its own pipeline namespace so the format-specific test
// invariants do not cross-contaminate.
//
// @coordinates-with: FoliateBilingualPipeline.swift,
//   FoliateBilingualJS.swift, BilingualReadingViewModel.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-11)

import Testing
@testable import vreader

@Suite("Feature #56 WI-11 — FoliateBilingualPipeline")
struct FoliateBilingualPipelineTests {

    // MARK: - Message parsing

    @Test("parseEnumerateMessage decodes a {bid, text}[] payload")
    func parseValidPayload() {
        let body: Any = [
            ["bid": "b1", "text": "Hello world"],
            ["bid": "b2", "text": "Bonjour"]
        ]
        let blocks = FoliateBilingualPipeline.parseEnumerateMessage(body)
        #expect(blocks.count == 2)
        #expect(blocks[0].bid == "b1")
        #expect(blocks[0].text == "Hello world")
        #expect(blocks[1].bid == "b2")
        #expect(blocks[1].text == "Bonjour")
    }

    @Test("parseEnumerateMessage tolerates a non-array body")
    func parseNonArrayPayload() {
        let body: Any = "not an array"
        let blocks = FoliateBilingualPipeline.parseEnumerateMessage(body)
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
        let blocks = FoliateBilingualPipeline.parseEnumerateMessage(body)
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
        let blocks = FoliateBilingualPipeline.parseEnumerateMessage(body)
        #expect(blocks.count == 1)
        #expect(blocks[0].bid == "b3")
    }

    // MARK: - Per-section partitioning (Gate-4 audit H2)

    @Test("parseEnumerateMessage captures the per-block sectionIndex")
    func parseCapturesSectionIndex() {
        let body: Any = [
            ["bid": "b1", "text": "hello", "sectionIndex": 0],
            ["bid": "b2", "text": "world", "sectionIndex": 1]
        ]
        let blocks = FoliateBilingualPipeline.parseEnumerateMessage(body)
        #expect(blocks.count == 2)
        #expect(blocks[0].sectionIndex == 0)
        #expect(blocks[1].sectionIndex == 1)
    }

    @Test("parseEnumerateMessage tolerates blocks without a sectionIndex (older bundle)")
    func parseTolerantOfMissingSectionIndex() {
        let body: Any = [
            ["bid": "b1", "text": "hello"],
            ["bid": "b2", "text": "world"]
        ]
        let blocks = FoliateBilingualPipeline.parseEnumerateMessage(body)
        #expect(blocks.count == 2)
        #expect(blocks[0].sectionIndex == nil)
        #expect(blocks[1].sectionIndex == nil)
    }

    @Test("blocks(_:forSection:) returns only the section's blocks")
    func blocksForSectionFilters() {
        let mixed = [
            BilingualBlock(bid: "b1", text: "alpha", sectionIndex: 0),
            BilingualBlock(bid: "b2", text: "beta",  sectionIndex: 0),
            BilingualBlock(bid: "b3", text: "gamma", sectionIndex: 1),
            BilingualBlock(bid: "b4", text: "delta", sectionIndex: 1)
        ]
        let scoped = FoliateBilingualPipeline.blocks(mixed, forSection: 1)
        #expect(scoped.map(\.bid) == ["b3", "b4"])
    }

    @Test("blocks(_:forSection:) returns empty when section index has no matches")
    func blocksForSectionNoMatch() {
        let mixed = [
            BilingualBlock(bid: "b1", text: "alpha", sectionIndex: 0),
            BilingualBlock(bid: "b2", text: "beta",  sectionIndex: 1)
        ]
        let scoped = FoliateBilingualPipeline.blocks(mixed, forSection: 99)
        #expect(scoped.isEmpty)
    }

    @Test("blocks(_:forSection:) falls back to all blocks when none are tagged")
    func blocksForSectionFallbackUntagged() {
        // Older JS bundle: no sectionIndex on any block. The pipeline
        // should pass the unfiltered list through so the renderer
        // still works against legacy payloads.
        let untagged = [
            BilingualBlock(bid: "b1", text: "alpha"),
            BilingualBlock(bid: "b2", text: "beta")
        ]
        let scoped = FoliateBilingualPipeline.blocks(untagged, forSection: 7)
        #expect(scoped.count == 2)
        #expect(scoped.map(\.bid) == ["b1", "b2"])
    }

    // MARK: - Translation lookup

    @Test("translationsByBid emits an empty map when no translations are cached")
    func translationsByBidEmpty() {
        let blocks = [
            BilingualBlock(bid: "b1", text: "Hello"),
            BilingualBlock(bid: "b2", text: "World")
        ]
        let table = FoliateBilingualPipeline.translationsByBid(
            blocks: blocks, translatedSegments: nil)
        #expect(table.isEmpty)
    }

    @Test("translationsByBid maps each block to its translation by index")
    func translationsByBidMapsByIndex() {
        let blocks = [
            BilingualBlock(bid: "b1", text: "Hello"),
            BilingualBlock(bid: "b2", text: "World")
        ]
        let table = FoliateBilingualPipeline.translationsByBid(
            blocks: blocks, translatedSegments: ["Bonjour", "Monde"])
        #expect(table.count == 2)
        #expect(table["b1"] == "Bonjour")
        #expect(table["b2"] == "Monde")
    }

    @Test("translationsByBid truncates extra translation segments")
    func translationsByBidTruncatesExtras() {
        let blocks = [
            BilingualBlock(bid: "b1", text: "Hello"),
            BilingualBlock(bid: "b2", text: "World")
        ]
        let table = FoliateBilingualPipeline.translationsByBid(
            blocks: blocks,
            translatedSegments: ["Bonjour", "Monde", "Extra"]
        )
        #expect(table.count == 2)
        #expect(table["b1"] == "Bonjour")
        #expect(table["b2"] == "Monde")
        #expect(!table.keys.contains("b3"))
    }

    @Test("translationsByBid short translation arrays emit a partial map")
    func translationsByBidShortArrayPartialMap() {
        let blocks = [
            BilingualBlock(bid: "b1", text: "Hello"),
            BilingualBlock(bid: "b2", text: "World"),
            BilingualBlock(bid: "b3", text: "Goodbye")
        ]
        let table = FoliateBilingualPipeline.translationsByBid(
            blocks: blocks,
            translatedSegments: ["Bonjour", "Monde"]
        )
        #expect(table.count == 2)
        #expect(table["b1"] == "Bonjour")
        #expect(table["b2"] == "Monde")
        #expect(table["b3"] == nil)
    }

    // MARK: - parseEnumeratePayload — Round-3 audit fix

    @Test("parseEnumeratePayload decodes the wrapped shape")
    func parseEnumeratePayloadWrapped() {
        let body: Any = [
            "requestedSectionIndex": 3,
            "blocks": [
                ["bid": "b1", "text": "hello", "sectionIndex": 3]
            ]
        ]
        let payload = FoliateBilingualPipeline.parseEnumeratePayload(body)
        #expect(payload.requestedSectionIndex == 3)
        #expect(payload.blocks.count == 1)
        #expect(payload.blocks[0].sectionIndex == 3)
    }

    @Test("parseEnumeratePayload surfaces a scoped-empty enumerate")
    func parseEnumeratePayloadScopedEmpty() {
        // The host enumerated section 5 and found no translatable
        // blocks. The container must be able to distinguish this
        // from "no scope was requested" so it can clear stale
        // per-section caches.
        let body: Any = [
            "requestedSectionIndex": 5,
            "blocks": []
        ]
        let payload = FoliateBilingualPipeline.parseEnumeratePayload(body)
        #expect(payload.requestedSectionIndex == 5)
        #expect(payload.blocks.isEmpty)
    }

    @Test("parseEnumeratePayload accepts the legacy bare-array shape")
    func parseEnumeratePayloadLegacyArray() {
        // Older bundles deliver the bare-array form. The payload's
        // `requestedSectionIndex` must be nil so callers know the
        // empty-clear signal is not available.
        let body: Any = [
            ["bid": "b1", "text": "hello"]
        ]
        let payload = FoliateBilingualPipeline.parseEnumeratePayload(body)
        #expect(payload.requestedSectionIndex == nil)
        #expect(payload.blocks.count == 1)
    }

    @Test("parseEnumerateMessage still works against the wrapped shape")
    func parseEnumerateMessageWrappedShapeUnwraps() {
        // The non-payload API is used by tests + the existing
        // observer plumbing — ensure it still returns the blocks
        // when given the new wrapped shape.
        let body: Any = [
            "requestedSectionIndex": 1,
            "blocks": [
                ["bid": "b1", "text": "alpha", "sectionIndex": 1],
                ["bid": "b2", "text": "beta",  "sectionIndex": 1]
            ]
        ]
        let blocks = FoliateBilingualPipeline.parseEnumerateMessage(body)
        #expect(blocks.count == 2)
        #expect(blocks.map(\.bid) == ["b1", "b2"])
    }
}
