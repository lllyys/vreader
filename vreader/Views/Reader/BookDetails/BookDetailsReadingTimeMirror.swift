// Purpose: Feature #101 WI-2b — the Reading time data wiring for
// `ReaderContainerView`, bundled into one modifier (the container body
// is near the type-checker's expression-complexity ceiling):
//  (a) mirrors `.readerSessionTimeDidChange` (posted ~1/min by
//      `ReaderLifecycleHelper.updateTimeDisplays`) into the host's
//      `currentSessionDisplay` when the payload is keyed to THIS book —
//      the same mirror pattern as `.readerBilingualDidChange` → chrome;
//  (b) fetches the per-book stats record + earliest session date when
//      the Book details sheet presents (never per tick), clearing the
//      previous fetch's rows first and dropping out-of-order results
//      via the generation-stamped `BookDetailsReadingTimeFetcher`
//      (Gate-4 r1 Mediums — the same stale-async family as WI-1's
//      lifecycle-helper High).
//
// @coordinates-with: ReaderContainerView.swift,
//   ReaderContainerView+Sheets.swift, ReaderLifecycleHelper.swift,
//   BookReadingTimeModel.swift, PersistenceActor+Stats.swift

#if canImport(UIKit)
import SwiftUI

/// Feature #101 WI-2b: the present-time stats fetch seam — what the
/// fetcher needs from the store (production: `PersistenceActor`; tests
/// inject stubs with controlled latency).
protocol BookReadingTimeStatsFetching: Sendable {
    func readingStats(forBookWithKey key: String) async throws -> ReadingStatsRecord?
    func firstSessionDate(forBookWithKey key: String) async throws -> Date?
}

extension PersistenceActor: BookReadingTimeStatsFetching {}

/// Generation-stamped present-time fetch: each `fetch` supersedes any
/// in-flight one (its completion is dropped), and `invalidate()` drops
/// every in-flight completion (book change / dismissal). `@MainActor`
/// so the generation compare-and-apply is race-free.
@MainActor
final class BookDetailsReadingTimeFetcher {
    private var generation = 0

    /// Drops any in-flight fetch's completion without starting a new one.
    func invalidate() { generation += 1 }

    /// Starts a fetch; `apply` runs only if no newer fetch/invalidate
    /// superseded this one by the time both reads complete.
    func fetch(
        from store: any BookReadingTimeStatsFetching,
        bookKey: String,
        into apply: @escaping @MainActor (BookReadingTimeStats) -> Void
    ) {
        generation += 1
        let stamped = generation
        Task { [weak self] in
            let record = try? await store.readingStats(forBookWithKey: bookKey)
            let first = try? await store.firstSessionDate(forBookWithKey: bookKey)
            guard let self, stamped == self.generation else { return }
            apply(BookReadingTimeStats(record: record, firstSessionDate: first))
        }
    }
}

/// The feature #101 WI-2b Reading time wiring. See file header.
struct BookDetailsReadingTimeMirror: ViewModifier {

    /// The outcome of filtering one `.readerSessionTimeDidChange`
    /// payload — pure so the keying rules are unit-testable.
    enum SessionDisplayUpdate: Equatable {
        /// Payload is for a different book (or malformed) — keep state.
        case ignore
        /// Payload is for this book — set the display (nil for empty).
        case set(String?)
    }

    let bookFingerprintKey: String
    let persistence: PersistenceActor?
    let showBookDetails: Bool
    @Binding var currentSessionDisplay: String?
    @Binding var readingStats: BookReadingTimeStats?

    @State private var fetcher = BookDetailsReadingTimeFetcher()

    /// Filters one notification payload against this book's key.
    /// An empty display (the helper posts "" when the session formatter
    /// returns nil) maps to `.set(nil)` so the row falls back to "—".
    static func sessionDisplayUpdate(
        from userInfo: [AnyHashable: Any]?, bookFingerprintKey: String
    ) -> SessionDisplayUpdate {
        guard let key = userInfo?["fingerprintKey"] as? String,
              key == bookFingerprintKey else { return .ignore }
        let display = userInfo?["display"] as? String
        return .set((display?.isEmpty == false) ? display : nil)
    }

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(
                for: .readerSessionTimeDidChange)
            ) { notification in
                if case .set(let display) = Self.sessionDisplayUpdate(
                    from: notification.userInfo,
                    bookFingerprintKey: bookFingerprintKey
                ) {
                    currentSessionDisplay = display
                }
            }
            .onChange(of: showBookDetails) { _, isShowing in
                guard isShowing else { return }
                // Clear the previous present's rows FIRST so a reopen
                // omits the section while the fresh fetch is in flight
                // rather than flashing stale totals (Gate-4 r1 Medium).
                readingStats = nil
                guard let persistence else { return }
                fetcher.fetch(from: persistence, bookKey: bookFingerprintKey) {
                    readingStats = $0
                }
            }
            .onChange(of: bookFingerprintKey) {
                // Host reuse for a different book: drop any in-flight
                // fetch's completion and reset the book-keyed state.
                fetcher.invalidate()
                readingStats = nil
                currentSessionDisplay = nil
            }
    }
}
#endif
