// Purpose: Feature #101 WI-2b — one row of the Book details "Reading
// time" card. Pinned to the design `RTBookDetailsRows` Row: a 13.5pt
// ink label with an optional 11pt sub line stacked left, and a 13pt
// sub-color tabular-nums value right. Dividers are drawn by the card.
//
// @coordinates-with: BookDetailsSheet.swift, BookReadingTimeModel.swift,
//   ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-reading-time.jsx`

#if canImport(UIKit)
import SwiftUI

/// One Reading time row in the reader Book Details sheet.
struct BookReadingTimeRow: View {

    /// A row's data — value type so `BookDetailsSheet.readingTimeRows`
    /// (which composes them) is unit-testable.
    struct Model: Equatable, Identifiable {
        /// Stable identity — row labels are unique within the card.
        var id: String { label }
        /// "Reading time" / "This session" / "Average session".
        let label: String
        /// Optional sub line ("23 sessions since Mar 2").
        let sub: String?
        /// The trailing value ("6h 40m total", "12m", "—").
        let value: String
    }

    let model: Model
    let theme: ReaderThemeV2

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.label)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Color(theme.inkColor))
                if let sub = model.sub {
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(theme.subColor))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(model.value)
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(Color(theme.subColor))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("bookDetailsReadingTimeRow_\(model.label)")
    }
}
#endif
