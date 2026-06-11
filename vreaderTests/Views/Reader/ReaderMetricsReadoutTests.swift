// Purpose: Tests for ReaderMetricsReadout — the feature #101 pure page↔time
// cycle seam (Gate-2 M4). Pins resolve precedence, the inert-tap rule when
// no time readout exists, and label selection.

import Testing
@testable import vreader

@Suite("ReaderMetricsReadout")
struct ReaderMetricsReadoutTests {

    // MARK: - resolve(persisted:)

    @Test(arguments: [
        (nil, ReaderMetricsReadout.pages),          // absent → default
        ("pages", ReaderMetricsReadout.pages),
        ("time", ReaderMetricsReadout.time),
        ("garbage", ReaderMetricsReadout.pages),    // unknown → default
        ("", ReaderMetricsReadout.pages),           // empty → default
        ("TIME", ReaderMetricsReadout.pages),       // case-sensitive rawValue
    ] as [(String?, ReaderMetricsReadout)])
    func resolvesPersistedChoice(_ persisted: String?, _ expected: ReaderMetricsReadout) {
        #expect(ReaderMetricsReadout.resolve(persisted: persisted) == expected)
    }

    // MARK: - toggled(hasTimeReadout:)

    @Test func tapCyclesPagesToTimeWhenAvailable() {
        #expect(ReaderMetricsReadout.pages.toggled(hasTimeReadout: true) == .time)
    }

    @Test func tapCyclesTimeBackToPages() {
        #expect(ReaderMetricsReadout.time.toggled(hasTimeReadout: true) == .pages)
    }

    @Test func tapIsInertWithoutTimeReadout() {
        // Pre-totals / zero-session: no cycle, no flash — pages pinned.
        #expect(ReaderMetricsReadout.pages.toggled(hasTimeReadout: false) == .pages)
    }

    @Test func timeFallsBackToPagesWhenTimeReadoutVanishes() {
        // A persisted .time choice on a book whose readout is (still) nil
        // must not strand the label on a stale state after a tap.
        #expect(ReaderMetricsReadout.time.toggled(hasTimeReadout: false) == .pages)
    }

    // MARK: - displayLabel(pages:time:)

    @Test func pagesReadoutShowsPagesLabel() {
        let label = ReaderMetricsReadout.pages.displayLabel(
            pages: "414 pages left in book", time: "12m read \u{B7} 6h 40m total")
        #expect(label == "414 pages left in book")
    }

    @Test func timeReadoutShowsTimeLabel() {
        let label = ReaderMetricsReadout.time.displayLabel(
            pages: "414 pages left in book", time: "12m read \u{B7} 6h 40m total")
        #expect(label == "12m read \u{B7} 6h 40m total")
    }

    @Test func timeReadoutPinsPagesWhileTimeIsNil() {
        // Persisted .time choice, totals not yet attached → pages, no flash
        // of an empty label.
        let label = ReaderMetricsReadout.time.displayLabel(
            pages: "Chapter 8 of 54", time: nil)
        #expect(label == "Chapter 8 of 54")
    }
}
