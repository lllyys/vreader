// Purpose: Feature #96 WI-2 — pure-logic tests for the diagnostics viewer's
// level→tint mapping, the level-filter predicate, and the day grouper.

import Testing
import Foundation
@testable import vreader

private func entry(_ level: DiagnosticsLevel, _ category: String = "C", _ message: String = "m",
                   at date: Date) -> DiagnosticsLogEntry {
    DiagnosticsLogEntry(date: date, level: level, category: category, message: message)
}

@Suite("DiagnosticsLevelStyle")
struct DiagnosticsLevelStyleTests {

    @Test func viewerTintMapsErrorAndFaultToError() {
        #expect(DiagnosticsLevel.error.viewerTint == .error)
        #expect(DiagnosticsLevel.fault.viewerTint == .error)
    }

    @Test func viewerTintMapsInfoToInfo() {
        #expect(DiagnosticsLevel.info.viewerTint == .info)
    }

    @Test(arguments: [DiagnosticsLevel.debug, .notice, .undefined])
    func viewerTintMapsTheRestToNeutral(_ level: DiagnosticsLevel) {
        #expect(level.viewerTint == .neutral)
    }

    // MARK: - Level filter

    @Test func allFilterMatchesEverything() {
        for level in DiagnosticsLevel.allCases {
            #expect(DiagnosticsLevelFilter.all.matches(level))
        }
    }

    @Test func errorsFilterIncludesFault() {
        #expect(DiagnosticsLevelFilter.errors.matches(.error))
        #expect(DiagnosticsLevelFilter.errors.matches(.fault))
        #expect(!DiagnosticsLevelFilter.errors.matches(.info))
        #expect(!DiagnosticsLevelFilter.errors.matches(.debug))
    }

    @Test func debugAndInfoFiltersAreExact() {
        #expect(DiagnosticsLevelFilter.debug.matches(.debug))
        #expect(!DiagnosticsLevelFilter.debug.matches(.info))
        #expect(DiagnosticsLevelFilter.info.matches(.info))
        #expect(!DiagnosticsLevelFilter.info.matches(.debug))
    }

    @Test func filterLabelsMatchTheDesignChips() {
        #expect(DiagnosticsLevelFilter.allCases.map(\.label) == ["All", "Errors", "Debug", "Info"])
    }

    // MARK: - Day grouper

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }

    private func identified(_ entries: [DiagnosticsLogEntry]) -> [IdentifiedDiagnosticsEntry] {
        entries.enumerated().map { IdentifiedDiagnosticsEntry(id: $0.offset, entry: $0.element) }
    }

    @Test func groupsEntriesIntoTodayAndYesterdayNewestFirst() {
        let cal = utc
        // now = 2026-06-10 12:00 UTC
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 12))!
        let todayA = cal.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 9))!
        let todayB = cal.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 11))!
        let yesterday = cal.date(from: DateComponents(year: 2026, month: 6, day: 9, hour: 20))!

        let sections = DiagnosticsDayGrouper.sections(
            from: identified([entry(.info, at: todayA), entry(.error, at: yesterday), entry(.debug, at: todayB)]),
            now: now, calendar: cal)

        #expect(sections.count == 2)
        #expect(sections[0].relativeWord == "Today")
        #expect(sections[1].relativeWord == "Yesterday")
        // newest entry first within Today: 11:00 before 09:00
        #expect(sections[0].entries.map(\.entry.date) == [todayB, todayA])
        #expect(sections[0].header == "Today · 10 June")
        #expect(sections[1].header == "Yesterday · 9 June")
    }

    @Test func groupingPreservesAssignedIdentity() {
        // Two value-EQUAL entries must keep DISTINCT ids through grouping so the
        // viewer expands them independently.
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 12))!
        let t = cal.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 9))!
        let dup = DiagnosticsLogEntry(date: t, level: .error, category: "C", message: "same")
        let items = [IdentifiedDiagnosticsEntry(id: 0, entry: dup),
                     IdentifiedDiagnosticsEntry(id: 1, entry: dup)]
        let sections = DiagnosticsDayGrouper.sections(from: items, now: now, calendar: cal)
        #expect(sections.count == 1)
        #expect(Set(sections[0].entries.map(\.id)) == [0, 1])
    }

    @Test func olderDayHasNoRelativeWord() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 12))!
        let old = cal.date(from: DateComponents(year: 2026, month: 6, day: 3, hour: 8))!
        let sections = DiagnosticsDayGrouper.sections(from: identified([entry(.info, at: old)]), now: now, calendar: cal)
        #expect(sections.count == 1)
        #expect(sections[0].relativeWord == nil)
        #expect(sections[0].header == "3 June")
    }

    @Test func emptyInputYieldsNoSections() {
        #expect(DiagnosticsDayGrouper.sections(from: [], now: Date(), calendar: utc).isEmpty)
    }
}
