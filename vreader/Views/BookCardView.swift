// Purpose: Grid card view for a book in the library.
// Shows cover placeholder, format badge, title, author, and reading time.
//
// Key decisions:
// - Uses system fonts for Dynamic Type support.
// - Accessibility label uses AccessibilityFormatters for VoiceOver-friendly expanded text.
// - Cover placeholder uses format-specific colors.
// - Reading time label omitted for zero reading time.
//
// @coordinates-with: AccessibilityFormatters.swift, LibraryBookItem.swift, CustomCoverStore.swift

import SwiftUI

/// Grid card view for a single book in the library.
struct BookCardView: View {
    let book: LibraryBookItem
    /// Bumped by parent when custom cover changes, to force reload.
    var coverVersion: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover: fixed 2:3 ratio container — uniform card height in grid
            CoverContainerView(
                image: customCoverImage,
                coverColor: coverColor,
                formatIcon: formatIcon,
                formatBadge: book.formatBadge
            )

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to open")
    }

    // MARK: - Private

    /// Loads the custom cover for this book (if any). `coverVersion` dependency
    /// ensures SwiftUI re-evaluates when covers change.
    private var customCoverImage: UIImage? {
        _ = coverVersion // force re-evaluation when version changes
        return CustomCoverStore.loadCover(for: book.fingerprintKey)
    }

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

/// Fixed 2:3 aspect ratio cover container.
/// `Color.clear` drives layout — guarantees identical height for every card
/// regardless of image dimensions. Image is in `.overlay` (not `.background`)
/// so it never participates in layout sizing. `.clipped()` trims any
/// scaledToFill overflow.
private struct CoverContainerView: View {
    let image: UIImage?
    let coverColor: Color
    let formatIcon: String
    let formatBadge: String

    var body: some View {
        Color(white: 0.92)
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    } else {
                        coverColor
                    }
                }
            }
            .overlay {
                if image == nil {
                    VStack(spacing: 4) {
                        Image(systemName: formatIcon)
                            .font(.system(size: 32))
                            .foregroundStyle(.white.opacity(0.8))
                        Text(formatBadge)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                // Bug #107: bump stroke opacity 0.2 → 0.35 so covers
                // with white/light edges visibly delineate against the
                // white library-grid background. The previous 0.2 was
                // effectively invisible on white, making AZW3 covers
                // like 被讨厌的勇气 look like they had top padding.
                // Stays subtle (still 0.5pt) so darker covers don't
                // get a heavy outline.
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.35), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
    }
}
