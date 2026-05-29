// Purpose: Feature #42 WI-10b — unit tests for `ReadiumTTSFollowMapper`, the
// pure flat-UTF16-offset → (spine href, intra-spine fraction) mapper + the
// follow-throttle decision that drives the Readium navigator to track the
// spoken position. The mapping is the crux + most bug-prone part (off-by-one at
// spine boundaries, the extraction-alignment contract), so this is the
// highest-value test in the WI.
//
// The per-spine offset table MUST mirror `ReaderAICoordinator.loadBookTextContent`'s
// EPUB concatenation EXACTLY: per-spine `stripHTML` + trim, SKIP empties, join
// with "\n\n" (2 UTF-16 units between adjacent non-empty entries). These tests
// pin both the table builder (skip-empty + separator accounting) and the
// offset→fraction math.
//
// @coordinates-with vreader/Views/Reader/ReadiumTTSFollowMapper.swift

#if canImport(UIKit)
import Testing
import Foundation
@testable import vreader

@Suite("ReadiumTTSFollowMapper (WI-10b)")
struct ReadiumTTSFollowMapperTests {

    // MARK: - Table builder (extraction-alignment contract)

    @Test func build_skipsEmptySpines_andAccountsForSeparator() {
        // Three spine docs; the middle one strips to empty (only whitespace).
        let entries = ReadiumTTSFollowMapper.buildEntries(spineTexts: [
            (href: "a.xhtml", text: "Hello"),   // 5 UTF-16
            (href: "b.xhtml", text: "   "),      // trims to empty → skipped
            (href: "c.xhtml", text: "World!"),   // 6 UTF-16
        ])
        // Two non-empty entries; "Hello" + "\n\n" + "World!"
        #expect(entries.count == 2)
        #expect(entries[0].href == "a.xhtml")
        #expect(entries[0].start == 0)
        #expect(entries[0].length == 5)
        // separator is 2 UTF-16 units: "World!" starts at 5 + 2 = 7
        #expect(entries[1].href == "c.xhtml")
        #expect(entries[1].start == 7)
        #expect(entries[1].length == 6)
    }

    @Test func build_emptyInput_yieldsNoEntries() {
        #expect(ReadiumTTSFollowMapper.buildEntries(spineTexts: []).isEmpty)
        #expect(ReadiumTTSFollowMapper.buildEntries(spineTexts: [
            (href: "a.xhtml", text: ""),
            (href: "b.xhtml", text: "   \n  "),
        ]).isEmpty)
    }

    @Test func build_concatMatchesJoinedText() {
        // The cumulative offsets must reproduce the same string the TTS engine
        // is reading (joined with "\n\n", skipping empties).
        let spineTexts = [
            (href: "a.xhtml", text: "One"),
            (href: "b.xhtml", text: ""),       // skipped
            (href: "c.xhtml", text: "Two"),
            (href: "d.xhtml", text: "Three"),
        ]
        let entries = ReadiumTTSFollowMapper.buildEntries(spineTexts: spineTexts)
        let joined = ["One", "Two", "Three"].joined(separator: "\n\n")
        // Each entry's [start, start+length) slices back to its own text.
        let utf16 = Array(joined.utf16)
        for (entry, expected) in zip(entries, ["One", "Two", "Three"]) {
            let slice = Array(utf16[entry.start..<(entry.start + entry.length)])
            #expect(String(utf16CodeUnits: slice, count: slice.count) == expected)
        }
    }

    // MARK: - locate(offset:) — the mapping crux

    private func threeSpineMapper() -> ReadiumTTSFollowMapper {
        // "AAAA" + "\n\n" + "BBBBBBBB" + "\n\n" + "CC"
        // a: [0,4)  b: [6,14)  c: [16,18)
        ReadiumTTSFollowMapper(entries: ReadiumTTSFollowMapper.buildEntries(spineTexts: [
            (href: "a.xhtml", text: "AAAA"),
            (href: "b.xhtml", text: "BBBBBBBB"),
            (href: "c.xhtml", text: "CC"),
        ]))
    }

    @Test func locate_offsetInFirstSpine() {
        let m = threeSpineMapper()
        let r = m.locate(offset: 0)
        #expect(r?.href == "a.xhtml")
        #expect(r?.fraction == 0.0)
        let mid = m.locate(offset: 2)
        #expect(mid?.href == "a.xhtml")
        #expect(mid?.fraction == 0.5) // 2/4
    }

    @Test func locate_offsetInSecondSpine() {
        let m = threeSpineMapper()
        // offset 10 is in b [6,14): (10-6)/8 = 0.5
        let r = m.locate(offset: 10)
        #expect(r?.href == "b.xhtml")
        #expect(r?.fraction == 0.5)
    }

    @Test func locate_offsetInThirdSpine() {
        let m = threeSpineMapper()
        // offset 17 is in c [16,18): (17-16)/2 = 0.5
        let r = m.locate(offset: 17)
        #expect(r?.href == "c.xhtml")
        #expect(r?.fraction == 0.5)
    }

    @Test func locate_offsetExactlyAtSpineStartBoundary() {
        let m = threeSpineMapper()
        // offset 6 is the FIRST char of b → fraction 0.0 in b (not end of a)
        let r = m.locate(offset: 6)
        #expect(r?.href == "b.xhtml")
        #expect(r?.fraction == 0.0)
        // offset 16 is the FIRST char of c
        let c = m.locate(offset: 16)
        #expect(c?.href == "c.xhtml")
        #expect(c?.fraction == 0.0)
    }

    @Test func locate_offsetInSeparatorGap_belongsToPrecedingSpine() {
        let m = threeSpineMapper()
        // offsets 4,5 are the "\n\n" between a and b — clamp to END of a
        // (fraction 1.0) rather than dropping, so the follow doesn't stall.
        let r = m.locate(offset: 4)
        #expect(r?.href == "a.xhtml")
        #expect(r?.fraction == 1.0)
        let r5 = m.locate(offset: 5)
        #expect(r5?.href == "a.xhtml")
        #expect(r5?.fraction == 1.0)
    }

    @Test func locate_offsetPastEnd_clampsToLastSpineFraction1() {
        let m = threeSpineMapper()
        // last content char is at 17; total joined length is 18.
        let atEnd = m.locate(offset: 18)
        #expect(atEnd?.href == "c.xhtml")
        #expect(atEnd?.fraction == 1.0)
        let way = m.locate(offset: 9999)
        #expect(way?.href == "c.xhtml")
        #expect(way?.fraction == 1.0)
    }

    @Test func locate_negativeOffset_clampsToFirstSpineFraction0() {
        let m = threeSpineMapper()
        let r = m.locate(offset: -5)
        #expect(r?.href == "a.xhtml")
        #expect(r?.fraction == 0.0)
    }

    @Test func locate_emptyMapper_returnsNil() {
        let m = ReadiumTTSFollowMapper(entries: [])
        #expect(m.locate(offset: 0) == nil)
        #expect(m.locate(offset: 100) == nil)
    }

    @Test func locate_singleSpine() {
        let m = ReadiumTTSFollowMapper(entries: ReadiumTTSFollowMapper.buildEntries(
            spineTexts: [(href: "only.xhtml", text: "0123456789")]))
        #expect(m.locate(offset: 0)?.href == "only.xhtml")
        #expect(m.locate(offset: 0)?.fraction == 0.0)
        #expect(m.locate(offset: 5)?.fraction == 0.5)
        #expect(m.locate(offset: 10)?.fraction == 1.0) // past end clamps
    }

    // MARK: - Throttle decision

    @Test func shouldFollow_firstEverPosition_isTrue() {
        // No previous followed position → always follow.
        #expect(ReadiumTTSFollowMapper.shouldFollow(
            previous: nil,
            current: (href: "a.xhtml", fraction: 0.0),
            fractionThreshold: 0.08))
    }

    @Test func shouldFollow_sameSpine_smallDrift_isFalse() {
        #expect(!ReadiumTTSFollowMapper.shouldFollow(
            previous: (href: "a.xhtml", fraction: 0.50),
            current: (href: "a.xhtml", fraction: 0.55),
            fractionThreshold: 0.08))
    }

    @Test func shouldFollow_sameSpine_largeDrift_isTrue() {
        #expect(ReadiumTTSFollowMapper.shouldFollow(
            previous: (href: "a.xhtml", fraction: 0.50),
            current: (href: "a.xhtml", fraction: 0.62),
            fractionThreshold: 0.08))
    }

    @Test func shouldFollow_spineChange_alwaysTrue_evenSmallFraction() {
        // Crossing a spine boundary always follows, regardless of fraction delta.
        #expect(ReadiumTTSFollowMapper.shouldFollow(
            previous: (href: "a.xhtml", fraction: 0.99),
            current: (href: "b.xhtml", fraction: 0.0),
            fractionThreshold: 0.08))
    }

    @Test func shouldFollow_backwardDrift_isTrueWhenLarge() {
        // A backward jump (e.g. user seeked TTS back) past the threshold follows.
        #expect(ReadiumTTSFollowMapper.shouldFollow(
            previous: (href: "a.xhtml", fraction: 0.60),
            current: (href: "a.xhtml", fraction: 0.40),
            fractionThreshold: 0.08))
    }

    // MARK: - Extraction-alignment contract (the crux risk)

    /// The mapper table MUST be built from the SAME stripper + concatenation the
    /// TTS engine reads (`ReaderAICoordinator.loadBookTextContent`:
    /// `EPUBTextExtractor.stripHTML` → trim → skip empties → join "\n\n"). This
    /// test drives the REAL `stripHTML` so a future change to either side that
    /// breaks alignment is caught here — an offset into the joined feed must map
    /// to the spine whose text actually contains it.
    @Test func alignment_realStripHTML_offsetMapsToCorrectSpine() {
        let xhtmls = [
            ("ch1.xhtml", "<html><body><p>Alpha bravo charlie.</p></body></html>"),
            ("ch2.xhtml", "<html><body><img src=\"x.png\"/></body></html>"), // strips empty
            ("ch3.xhtml", "<html><body><p>Delta echo foxtrot golf.</p></body></html>"),
        ]
        // Reproduce the TTS feed exactly.
        var parts: [String] = []
        var spineTexts: [(href: String, text: String)] = []
        for (href, html) in xhtmls {
            let plain = EPUBTextExtractor.stripHTML(html)
            spineTexts.append((href: href, text: plain))
            let trimmed = plain.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { parts.append(trimmed) }
        }
        let feed = parts.joined(separator: "\n\n")
        let mapper = ReadiumTTSFollowMapper(
            entries: ReadiumTTSFollowMapper.buildEntries(spineTexts: spineTexts))

        // ch2 stripped empty → only ch1 + ch3 in the feed.
        #expect(mapper.locate(offset: 0)?.href == "ch1.xhtml")
        // An offset inside the "Delta echo..." region must map to ch3, not ch1/ch2.
        let deltaStart = (feed as NSString).range(of: "Delta").location
        #expect(deltaStart != NSNotFound)
        #expect(mapper.locate(offset: deltaStart)?.href == "ch3.xhtml")
        // The last char of the feed maps to ch3 at fraction near 1.0.
        let endTarget = mapper.locate(offset: feed.utf16.count - 1)
        #expect(endTarget?.href == "ch3.xhtml")
    }

    // MARK: - Off-main builder (Gate-4 round-1 Medium: parser walk off @MainActor)

    /// The `nonisolated` parser-walk builder must produce the SAME entry table as
    /// the direct `buildEntries(spineTexts:)` over the stripped + skip-empty feed,
    /// and a spine the parser can't read must contribute empty text (skipped),
    /// matching the TTS feed's `try?` skip in `loadBookTextContent`.
    @Test func buildEntries_offMainParserWalk_matchesDirectFeed() async throws {
        let parser = MockEPUBParser()
        await parser.setSpineContent([
            "ch1.xhtml": "<html><body><p>Alpha bravo.</p></body></html>",
            "ch2.xhtml": "<html><body><img src=\"x.png\"/></body></html>", // strips empty
            // ch3 intentionally absent → parser throws resourceNotFound → empty
        ])
        await parser.forceOpen()
        let entries = await ReadiumTTSFollowMapper.buildEntries(
            spineHrefs: ["ch1.xhtml", "ch2.xhtml", "ch3.xhtml"], parser: parser)
        // Only ch1 produced non-empty text.
        #expect(entries.count == 1)
        #expect(entries[0].href == "ch1.xhtml")
        #expect(entries[0].start == 0)
        #expect(entries[0].length == EPUBTextExtractor.stripHTML(
            "<html><body><p>Alpha bravo.</p></body></html>"
        ).trimmingCharacters(in: .whitespacesAndNewlines).utf16.count)
    }
}
#endif
