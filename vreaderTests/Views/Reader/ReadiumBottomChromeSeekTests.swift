// Bug #299: the Readium bottom-chrome scrubber's seek math — maps a whole-book
// fraction onto an equal-weight spine index + intra-chapter progression. Pure +
// CI-safe (no navigator). Regression coverage for the scrubber seek that the
// restored bottom chrome drives.

import Testing
@testable import vreader

@Suite("Readium bottom-chrome seek mapping (Bug #299)")
struct ReadiumBottomChromeSeekTests {

    @Test("fraction 0 → first chapter, start")
    func startOfBook() {
        let t = ReadiumBottomChromeSeek.target(fraction: 0, spineCount: 5)
        #expect(t.index == 0)
        #expect(t.intra == 0)
    }

    @Test("fraction 1 → last chapter")
    func endOfBook() {
        let t = ReadiumBottomChromeSeek.target(fraction: 1, spineCount: 5)
        #expect(t.index == 4)  // clamped to last spine index
        #expect(t.intra == 1)
    }

    @Test("fraction 0.5 of a 2-chapter book → start of chapter 2")
    func midpointTwoChapters() {
        let t = ReadiumBottomChromeSeek.target(fraction: 0.5, spineCount: 2)
        #expect(t.index == 1)
        #expect(t.intra == 0)
    }

    @Test("intra-chapter progression is the within-chapter remainder")
    func intraProgression() {
        // 0.3 of a 2-chapter book → 0.6 of the book → chapter 0 (0…0.5 maps idx 0),
        // intra = 0.6 within chapter 0.
        let t = ReadiumBottomChromeSeek.target(fraction: 0.3, spineCount: 2)
        #expect(t.index == 0)
        #expect(abs(t.intra - 0.6) < 1e-9)
    }

    @Test("out-of-range fractions clamp")
    func clamps() {
        #expect(ReadiumBottomChromeSeek.target(fraction: -1, spineCount: 3).index == 0)
        let hi = ReadiumBottomChromeSeek.target(fraction: 2, spineCount: 3)
        #expect(hi.index == 2)
    }

    @Test("empty spine → safe default")
    func emptySpine() {
        let t = ReadiumBottomChromeSeek.target(fraction: 0.5, spineCount: 0)
        #expect(t.index == 0)
        #expect(t.intra == 0)
    }

    // M1: display `progress` is the inverse of seek `target` — they agree, so a
    // dragged fraction and the relocate that follows don't snap.
    @Test("display progress is the inverse of seek target (no snap)")
    func displaySeekRoundTrip() {
        for spineCount in [1, 2, 5, 13] {
            for f in stride(from: 0.0, through: 1.0, by: 0.1) {
                let t = ReadiumBottomChromeSeek.target(fraction: f, spineCount: spineCount)
                let back = ReadiumBottomChromeSeek.progress(
                    index: t.index, intra: t.intra, spineCount: spineCount)
                #expect(abs(back - max(0, min(1, f))) < 1e-9)
            }
        }
    }

    // M2: the visibility gate matches the other hosts (ready + visible + TTS idle).
    @Test("visibility gate requires ready + chrome-visible + TTS idle")
    func visibilityGate() {
        #expect(ReadiumBottomChromeSeek.shouldShow(isChromeVisible: true, isReady: true, ttsIsIdle: true))
        #expect(!ReadiumBottomChromeSeek.shouldShow(isChromeVisible: false, isReady: true, ttsIsIdle: true))
        #expect(!ReadiumBottomChromeSeek.shouldShow(isChromeVisible: true, isReady: false, ttsIsIdle: true))
        #expect(!ReadiumBottomChromeSeek.shouldShow(isChromeVisible: true, isReady: true, ttsIsIdle: false))
    }
}
