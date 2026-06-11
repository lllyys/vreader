// Purpose: Feature #101 WI-2b — the Reading time data wiring for
// `ReaderContainerView`, bundled into one modifier (the container body
// is near the type-checker's expression-complexity ceiling):
//  (a) mirrors `.readerSessionTimeDidChange` (posted ~1/min by
//      `ReaderLifecycleHelper.updateTimeDisplays`) into the host's
//      `currentSessionDisplay` when the payload is keyed to THIS book —
//      the same mirror pattern as `.readerBilingualDidChange` → chrome;
//  (b) fetches the per-book stats record + earliest session date when
//      the Book details sheet presents (never per tick).
//
// @coordinates-with: ReaderContainerView.swift,
//   ReaderContainerView+Sheets.swift, ReaderLifecycleHelper.swift,
//   BookReadingTimeModel.swift, PersistenceActor+Stats.swift

#if canImport(UIKit)
import SwiftUI

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
                guard isShowing, let persistence else { return }
                let key = bookFingerprintKey
                Task {
                    let record = try? await persistence.readingStats(forBookWithKey: key)
                    let first = try? await persistence.firstSessionDate(forBookWithKey: key)
                    readingStats = BookReadingTimeStats(
                        record: record, firstSessionDate: first)
                }
            }
    }
}
#endif
