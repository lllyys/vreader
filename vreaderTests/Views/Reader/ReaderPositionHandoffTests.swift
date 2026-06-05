// Purpose: Feature #85 WI-1 — pin the in-memory cross-engine position handoff
// that prevents position LOSS when a reading-mode toggle swaps EPUB hosts
// (Readium paged ↔ legacy #71 scroll, approach C). The cache must return the
// freshest recorded position per book, independent of persistence timing.
//
// @coordinates-with: ReaderPositionHandoff.swift

import Testing
@testable import vreader

@Suite("Feature #85 WI-1 — ReaderPositionHandoff")
@MainActor
struct ReaderPositionHandoffTests {

    private func makeLocator(href: String, progression: Double) -> Locator {
        let fp = DocumentFingerprint(
            contentSHA256: String(repeating: "a", count: 64),
            fileByteCount: 1, format: .epub)
        return Locator.validated(bookFingerprint: fp, href: href, progression: progression)!
    }

    @Test func recordThenReadReturnsLatest() {
        let h = ReaderPositionHandoff()
        h.record(makeLocator(href: "ch2.html", progression: 0.5), forKey: "b1")
        #expect(h.latestLocator(forKey: "b1")?.href == "ch2.html")
        #expect(h.latestLocator(forKey: "b1")?.progression == 0.5)
    }

    /// The handoff always holds the FRESHEST position — the load-bearing
    /// property (a stale read here would be the Gate-4 position-loss bug).
    @Test func recordOverwritesWithFreshest() {
        let h = ReaderPositionHandoff()
        h.record(makeLocator(href: "ch1.html", progression: 0.1), forKey: "b")
        h.record(makeLocator(href: "ch3.html", progression: 0.9), forKey: "b")
        #expect(h.latestLocator(forKey: "b")?.href == "ch3.html")
        #expect(h.latestLocator(forKey: "b")?.progression == 0.9)
    }

    @Test func unknownKeyReturnsNil() {
        #expect(ReaderPositionHandoff().latestLocator(forKey: "nope") == nil)
    }

    @Test func emptyKeyIsIgnored() {
        let h = ReaderPositionHandoff()
        h.record(makeLocator(href: "x.html", progression: 0.1), forKey: "")
        #expect(h.latestLocator(forKey: "") == nil)
    }

    @Test func keysAreIndependent() {
        let h = ReaderPositionHandoff()
        h.record(makeLocator(href: "a.html", progression: 0.2), forKey: "k1")
        h.record(makeLocator(href: "b.html", progression: 0.3), forKey: "k2")
        #expect(h.latestLocator(forKey: "k1")?.href == "a.html")
        #expect(h.latestLocator(forKey: "k2")?.href == "b.html")
    }
}
