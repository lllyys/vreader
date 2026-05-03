// Purpose: List row view for a book in the library.
// Shows format badge, title, author, reading time, and speed in a horizontal layout.
//
// Key decisions:
// - Horizontal layout with format icon, text stack, and trailing metadata.
// - Accessibility label uses AccessibilityFormatters for VoiceOver-friendly expanded text.
// - Dynamic Type supported via system fonts.
// - Reading time label omitted for zero reading time.
//
// @coordinates-with: AccessibilityFormatters.swift, LibraryBookItem.swift, CustomCoverStore.swift

import SwiftUI

/// List row view for a single book in the library.
struct BookRowView: View {
    let book: LibraryBookItem
    /// Bumped by parent when custom cover changes, to force reload.
    var coverVersion: Int = 0

    var body: some View {
        HStack(spacing: 12) {
            // Format icon or custom cover
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(formatColor)
                    .frame(width: 44, height: 44)

                if let customCover = customCoverImage {
                    Image(uiImage: customCover)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: formatIcon)
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                }
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
                // Format badge OR file-state indicator (feature #47).
                // Non-`.local` rows replace the format badge with a
                // status icon so the user immediately sees the row is
                // remote / downloading / failed.
                fileStateBadge
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
        switch book.fileState {
        case .local:
            Text(book.formatBadge)
                .font(.caption2)
                .fontWeight(.semibold)
        case .remoteOnly:
            Label("Remote", systemImage: "cloud")
                .font(.caption2)
                .fontWeight(.semibold)
                .labelStyle(.titleAndIcon)
        case .downloading:
            Label("Downloading", systemImage: "arrow.down.circle")
                .font(.caption2)
                .fontWeight(.semibold)
                .labelStyle(.titleAndIcon)
        case .failed:
            Label("Retry", systemImage: "exclamationmark.icloud")
                .font(.caption2)
                .fontWeight(.semibold)
                .labelStyle(.titleAndIcon)
        case .missingRemote:
            Label("Missing", systemImage: "xmark.icloud")
                .font(.caption2)
                .fontWeight(.semibold)
                .labelStyle(.titleAndIcon)
        }
    }

    // MARK: - Private

    /// Loads the custom cover for this book (if any). `coverVersion` dependency
    /// ensures SwiftUI re-evaluates when covers change.
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
