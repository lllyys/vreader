// Purpose: Unit tests for ReadingDashboardSnapshot's normalizing initializer
// and ReadingDashboardSort's storage-string round-trip. Feature #58 WI-1.
// (Split from ReadingStatsModelsTests.swift to stay under the ~300-line guide.)

import Foundation
import Testing
@testable import vreader

@Suite("ReadingDashboardSort string round-trip")
struct ReadingDashboardSortStorageTests {

    @Test func defaultIsReadingTimeDescending() {
        #expect(ReadingDashboardSort.default.field == .readingTime)
        #expect(ReadingDashboardSort.default.ascending == false)
    }

    /// All 8 field/direction combinations round-trip through `storageString`.
    @Test(arguments: ReadingDashboardSortField.allCases, [true, false])
    func roundTripsThroughStorageString(_ field: ReadingDashboardSortField, _ ascending: Bool) {
        let sort = ReadingDashboardSort(field: field, ascending: ascending)
        let restored = ReadingDashboardSort(storageString: sort.storageString)
        #expect(restored == sort)
    }

    @Test func storageStringFormat() {
        #expect(ReadingDashboardSort(field: .readingTime, ascending: false).storageString == "readingTime:desc")
        #expect(ReadingDashboardSort(field: .title, ascending: true).storageString == "title:asc")
        #expect(ReadingDashboardSort(field: .highlights, ascending: false).storageString == "highlights:desc")
        #expect(ReadingDashboardSort(field: .notes, ascending: true).storageString == "notes:asc")
    }

    @Test(arguments: ["", "garbage", "readingTime", "readingTime:sideways", "bogusField:asc", ":asc", "readingTime:"])
    func malformedStringYieldsNil(_ raw: String) {
        #expect(ReadingDashboardSort(storageString: raw) == nil)
    }

    @Test func codableRoundTrip() throws {
        let sort = ReadingDashboardSort(field: .highlights, ascending: true)
        let data = try JSONEncoder().encode(sort)
        let decoded = try JSONDecoder().decode(ReadingDashboardSort.self, from: data)
        #expect(decoded == sort)
    }
}

@Suite("ReadingDashboardSnapshot normalizing init")
struct ReadingDashboardSnapshotTests {

    @Test func totalForPresentWindowReturnsStoredValue() {
        let totals = ReadingStatsWindow.allCases.map {
            WindowTotal(window: $0, totalSeconds: $0 == .today ? 600 : 0, sessionCount: $0 == .today ? 2 : 0)
        }
        let snapshot = ReadingDashboardSnapshot(
            windowTotals: totals, activeWindow: .today, perBook: [],
            lifetimeTotalSeconds: 600, trackingSince: nil
        )
        #expect(snapshot.total(for: .today).totalSeconds == 600)
        #expect(snapshot.total(for: .today).sessionCount == 2)
    }

    @Test func initNormalizesToSevenWindowsInCanonicalOrder() {
        // Input has only 2 windows, out of canonical order → the init yields
        // exactly 7, canonically ordered, with the rest zero-filled.
        let snapshot = ReadingDashboardSnapshot(
            windowTotals: [
                WindowTotal(window: .last30Days, totalSeconds: 300, sessionCount: 3),
                WindowTotal(window: .today, totalSeconds: 100, sessionCount: 1),
            ],
            activeWindow: .today, perBook: [], lifetimeTotalSeconds: 300, trackingSince: nil
        )
        #expect(snapshot.windowTotals.count == 7)
        #expect(snapshot.windowTotals.map(\.window) == ReadingStatsWindow.allCases)
        #expect(snapshot.total(for: .today).totalSeconds == 100)
        #expect(snapshot.total(for: .last30Days).totalSeconds == 300)
        #expect(snapshot.total(for: .last7Days).totalSeconds == 0)
        #expect(snapshot.total(for: .allTime).sessionCount == 0)
    }

    @Test func initWithEmptyInputZeroFillsAllSevenWindows() {
        let snapshot = ReadingDashboardSnapshot(
            windowTotals: [], activeWindow: .allTime, perBook: [],
            lifetimeTotalSeconds: 0, trackingSince: nil
        )
        #expect(snapshot.windowTotals.count == 7)
        #expect(snapshot.windowTotals.map(\.window) == ReadingStatsWindow.allCases)
        #expect(snapshot.windowTotals.allSatisfy { $0.totalSeconds == 0 && $0.sessionCount == 0 })
    }

    @Test func initDeduplicatesFirstOccurrenceWins() {
        let snapshot = ReadingDashboardSnapshot(
            windowTotals: [
                WindowTotal(window: .today, totalSeconds: 111, sessionCount: 1),
                WindowTotal(window: .today, totalSeconds: 999, sessionCount: 9),
            ],
            activeWindow: .today, perBook: [], lifetimeTotalSeconds: 111, trackingSince: nil
        )
        #expect(snapshot.windowTotals.count == 7)
        #expect(snapshot.total(for: .today).totalSeconds == 111)
    }

    @Test func initWithAllSevenInOrderIsIdentity() {
        let totals = ReadingStatsWindow.allCases.enumerated().map { index, window in
            WindowTotal(window: window, totalSeconds: index * 10, sessionCount: index)
        }
        let snapshot = ReadingDashboardSnapshot(
            windowTotals: totals, activeWindow: .last7Days, perBook: [],
            lifetimeTotalSeconds: 210, trackingSince: nil
        )
        #expect(snapshot.windowTotals == totals)
    }

    /// Two snapshots built from differently-ordered (but equivalent) inputs
    /// are Equatable-equal — the init normalizes both to canonical order.
    @Test func equatableIgnoresInputOrdering() {
        let a = ReadingDashboardSnapshot(
            windowTotals: [
                WindowTotal(window: .today, totalSeconds: 5, sessionCount: 1),
                WindowTotal(window: .last7Days, totalSeconds: 9, sessionCount: 2),
            ],
            activeWindow: .today, perBook: [], lifetimeTotalSeconds: 9, trackingSince: nil
        )
        let b = ReadingDashboardSnapshot(
            windowTotals: [
                WindowTotal(window: .last7Days, totalSeconds: 9, sessionCount: 2),
                WindowTotal(window: .today, totalSeconds: 5, sessionCount: 1),
            ],
            activeWindow: .today, perBook: [], lifetimeTotalSeconds: 9, trackingSince: nil
        )
        #expect(a == b)
    }
}
