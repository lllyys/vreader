// Purpose: Grid card view for a book in the library.
// Shows cover placeholder, format badge, title, author, and reading time.
//
// Key decisions:
// - Uses system fonts for Dynamic Type support.
// - Accessibility label uses AccessibilityFormatters for VoiceOver-friendly expanded text.
// - Cover placeholder uses format-specific colors.
// - Reading time label omitted for zero reading time.
//
// @coordinates-with: AccessibilityFormatters.swift, LibraryBookItem.swift

import SwiftUI

/// Grid card view for a single book in the library.
struct BookCardView: View {
    let book: LibraryBookItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(coverColor)
                    .aspectRatio(0.65, contentMode: .fit)

                VStack(spacing: 4) {
                    Image(systemName: formatIcon)
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.8))

                    Text(book.formatBadge)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }

            // Title
            Text(book.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
                .foregroundStyle(.primary)

            // Author
            if let author = book.author {
                Text(author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to open")
    }

    // MARK: - Private

    private var coverColor: Color {
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
