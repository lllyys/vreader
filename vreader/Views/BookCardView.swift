// Purpose: Grid card view for a book in the library.
// Shows the generative cover (spine + page-edge accents), Source Serif 4
// title, and author — re-skinned for feature #60 visual identity v2.
//
// Key decisions:
// - Visual tokens (palette, layout constants, serif title face) come
//   from `LibraryCardTokens` — the design spec has one home.
// - Title uses Source Serif 4 via `ReaderTypography`; author uses the
//   warm-taupe sub-text token. Reading-time / speed metadata rows are
//   omitted in the v2 design — the card is cover + title + author only.
// - Cover carries the design's spine shadow + page-edge highlight so
//   plain format-color placeholders read as physical book objects.
// - Accessibility label uses AccessibilityFormatters for VoiceOver-
//   friendly expanded text; exposed as a testing surface so the WI-8
//   contract tests can pin it without inspecting SwiftUI internals.
//
// @coordinates-with: AccessibilityFormatters.swift, LibraryBookItem.swift,
//   CustomCoverStore.swift, LibraryCardTokens.swift

import SwiftUI

/// Grid card view for a single book in the library.
struct BookCardView: View {
    let book: LibraryBookItem
    /// Bumped by parent when custom cover changes, to force reload.
    var coverVersion: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: LibraryCardTokens.cardStackSpacing) {
            // Cover: fixed 2:3 ratio container — uniform card height in grid
            BookCoverArtView(
                image: customCoverImage,
                coverColor: coverColor,
                formatIcon: formatIcon,
                formatBadge: book.formatBadge,
                cornerRadius: LibraryCardTokens.cardCoverCornerRadius
            )

            // Title — Source Serif 4, 2-line clamp
            Text(book.title)
                .font(LibraryCardTokens.serifTitleFont(
                    size: LibraryCardTokens.cardTitleFontSize
                ))
                .fontWeight(.semibold)
                .lineLimit(2)
                .foregroundStyle(LibraryCardTokens.ink)

            // Author
            if let author = book.author {
                Text(author)
                    .font(.system(size: LibraryCardTokens.cardAuthorFontSize))
                    .foregroundStyle(LibraryCardTokens.subText)
                    .lineLimit(1)
            }

            // Bug #177: pushes content to the top so shorter cards align
            // top-edges with taller cards in the same LazyVGrid row —
            // SwiftUI's default is vertical centering.
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }

    // MARK: - Testing surface

    /// Exposed so the WI-8 contract tests can assert the accessibility
    /// contract without inspecting opaque SwiftUI modifier state.
    var accessibilityLabelForTesting: String { accessibilityLabel }
    var accessibilityHintForTesting: String { accessibilityHint }

    // MARK: - Private

    private let accessibilityHint = "Double tap to open"

    /// Loads the custom cover for this book (if any). `coverVersion`
    /// dependency ensures SwiftUI re-evaluates when covers change.
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
