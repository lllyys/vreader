// Purpose: List row view for a book in the library.
// Shows format badge, title, author, reading time, and speed in a horizontal layout.
//
// Key decisions:
// - Horizontal layout with format icon, text stack, and trailing metadata.
// - Accessibility label uses AccessibilityFormatters for VoiceOver-friendly expanded text.
// - Dynamic Type supported via system fonts.
// - Reading time label omitted for zero reading time.
//
// @coordinates-with: AccessibilityFormatters.swift, LibraryBookItem.swift

import SwiftUI

/// List row view for a single book in the library.
struct BookRowView: View {
    let book: LibraryBookItem

    var body: some View {
        HStack(spacing: 12) {
            // Format icon
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(formatColor)
                    .frame(width: 44, height: 44)

                Image(systemName: formatIcon)
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
            }

            // Title and author
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                if let author = book.author {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Reading metadata
            VStack(alignment: .trailing, spacing: 2) {
                // Format badge
                Text(book.formatBadge)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(formatColor.opacity(0.15))
                    .foregroundStyle(formatColor)
                    .clipShape(Capsule())

                // Reading time (omitted for zero)
                if let readingTime = book.formattedReadingTime {
                    Text(readingTime)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Speed
                if let speed = book.formattedSpeed {
                    Text(speed)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to open")
    }

    // MARK: - Private

    private var formatColor: Color {
        switch book.format.lowercased() {
        case "epub": return .blue
        case "pdf": return .red
        case "txt": return .gray
        case "md": return .purple
        default: return .secondary
        }
    }

    private var formatIcon: String { book.formatIcon }

    private var accessibilityLabel: String {
        AccessibilityFormatters.accessibleBookDescription(
            title: book.title,
            author: book.author,
            format: book.format,
            readingTimeSeconds: book.totalReadingSeconds
        )
    }
}
