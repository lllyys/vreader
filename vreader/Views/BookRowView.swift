// Purpose: List row view for a book in the library — re-skinned for
// feature #60 visual identity v2.
//
// Key decisions:
// - Horizontal layout: cover thumbnail (44×62), then a left-aligned
//   text stack — Source Serif 4 title, warm-taupe author, and a
//   metadata line carrying the format chip (or feature-#47 file-state
//   badge).
// - Visual tokens come from `LibraryCardTokens` (one home for the
//   design spec). Reading-time / speed metadata rows are omitted in
//   the v2 design — the row is cover + title + author + chip.
// - The feature-#47 file-state badge is preserved verbatim per state
//   (remote / downloading / failed / missing); only the chip container
//   is re-skinned to the design's warm-wash capsule.
// - Accessibility label uses AccessibilityFormatters for VoiceOver-
//   friendly expanded text; exposed as a testing surface so the WI-8
//   contract tests can pin it without inspecting SwiftUI internals.
//
// @coordinates-with: AccessibilityFormatters.swift, LibraryBookItem.swift,
//   CustomCoverStore.swift, LibraryCardTokens.swift, BookFileState.swift

import SwiftUI

/// List row view for a single book in the library.
struct BookRowView: View {
    let book: LibraryBookItem
    /// Bumped by parent when custom cover changes, to force reload.
    var coverVersion: Int = 0

    var body: some View {
        HStack(spacing: LibraryCardTokens.rowContentSpacing) {
            // Cover thumbnail — shared spine/page-edge treatment.
            BookCoverArtView(
                image: customCoverImage,
                coverColor: formatColor,
                formatIcon: formatIcon,
                formatBadge: book.formatBadge,
                cornerRadius: LibraryCardTokens.rowCoverCornerRadius
            )
            .frame(
                width: LibraryCardTokens.rowCoverWidth,
                height: LibraryCardTokens.rowCoverHeight
            )

            // Title, author, metadata chip — left-aligned.
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(LibraryCardTokens.serifTitleFont(
                        size: LibraryCardTokens.rowTitleFontSize
                    ))
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .foregroundStyle(LibraryCardTokens.ink)

                if let author = book.author {
                    Text(author)
                        .font(.system(size: LibraryCardTokens.rowAuthorFontSize))
                        .foregroundStyle(LibraryCardTokens.subText)
                        .lineLimit(1)
                }

                // Format badge OR file-state indicator (feature #47).
                fileStateBadge
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(badgeBackground)
                    .foregroundStyle(badgeForeground)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(.top, 3)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }

    // MARK: - File-state badge (feature #47 WI-5)

    /// Replaces the format badge for non-`.local` rows so the user
    /// sees the row's transfer state at a glance. Display logic:
    ///   - `.local` → format badge ("EPUB", "PDF", …)
    ///   - `.remoteOnly` → cloud + "Remote"
    ///   - `.downloading` → arrow.down.circle + "Downloading"
    ///   - `.failed` → exclamationmark.icloud + "Retry"
    ///   - `.missingRemote` → xmark.icloud + "Missing"
    @ViewBuilder
    private var fileStateBadge: some View {
        let text = fileStateBadgeText
        if let symbol = fileStateBadgeSymbol {
            Label(text, systemImage: symbol)
                .font(.system(size: LibraryCardTokens.rowChipFontSize))
                .fontWeight(.semibold)
                .labelStyle(.titleAndIcon)
        } else {
            Text(text)
                .font(.system(size: LibraryCardTokens.rowChipFontSize))
                .fontWeight(.semibold)
                .tracking(0.5)
        }
    }

    /// Badge text per file state — the format badge for `.local`,
    /// otherwise the transfer-state word (feature #47 contract).
    private var fileStateBadgeText: String {
        switch book.fileState {
        case .local:         return book.formatBadge
        case .remoteOnly:    return "Remote"
        case .downloading:   return "Downloading"
        case .failed:        return "Retry"
        case .missingRemote: return "Missing"
        }
    }

    /// SF Symbol for non-local file states; nil for `.local` (format
    /// badge is text-only).
    private var fileStateBadgeSymbol: String? {
        switch book.fileState {
        case .local:         return nil
        case .remoteOnly:    return "cloud"
        case .downloading:   return "arrow.down.circle"
        case .failed:        return "exclamationmark.icloud"
        case .missingRemote: return "xmark.icloud"
        }
    }

    /// Chip fill — the design's warm wash for the format badge, the
    /// format color tint for active transfer states (keeps the
    /// feature-#47 status colour-coding).
    private var badgeBackground: Color {
        switch book.fileState {
        case .local: return LibraryCardTokens.chipBackground
        default:     return formatColor.opacity(0.15)
        }
    }

    /// Chip text/icon colour — warm sub-text for the format badge,
    /// format colour for transfer states.
    private var badgeForeground: Color {
        switch book.fileState {
        case .local: return LibraryCardTokens.subText
        default:     return formatColor
        }
    }

    // MARK: - Testing surface

    /// Exposed so the WI-8 contract tests can assert the accessibility
    /// contract + feature-#47 badge logic without inspecting opaque
    /// SwiftUI modifier state.
    var accessibilityLabelForTesting: String { accessibilityLabel }
    var accessibilityHintForTesting: String { accessibilityHint }
    var fileStateBadgeTextForTesting: String { fileStateBadgeText }
    var fileStateBadgeSymbolForTesting: String? { fileStateBadgeSymbol }

    // MARK: - Private

    private let accessibilityHint = "Double tap to open"

    /// Loads the custom cover for this book (if any). `coverVersion`
    /// dependency ensures SwiftUI re-evaluates when covers change.
    private var customCoverImage: UIImage? {
        _ = coverVersion // force re-evaluation when version changes
        return CustomCoverStore.loadCover(for: book.fingerprintKey)
    }

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
