// Purpose: Feature #62 WI-3 — the design-faithful Contents + Bookmark
// row views for `TOCSheet`'s filled states.
//
// The legacy `TOCListView` / `BookmarkListView` row renderers do NOT
// match the committed `TOCSheetV2` design (Gate-2 round-2 finding 1):
// `TOCListView` renders only indented titles — no chapter ordinal, no
// page number; `BookmarkListView` renders a plain title/date `List`
// row — no italic preview, no chapter, no chevron. So `TOCSheet` ships
// its own rows, transcribed from `vreader-annotations.jsx`'s
// `TOCSheetV2`.
//
// Both are pure `View`s taking a `ReaderThemeV2`; tapping calls the
// supplied jump closure. Each keeps a stable `accessibilityIdentifier`.
//
// @coordinates-with: TOCSheet.swift, ReaderThemeV2.swift, TOCEntry.swift,
//   BookmarkRecord.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-annotations.jsx`

import SwiftUI

// MARK: - TOCContentsRow

/// One Contents row — a right-aligned serif chapter ordinal, the serif
/// chapter title (accent + bold when current), and a trailing `p. N`.
/// The current-chapter row gets an `accent`-tinted background. JSX
/// `TOCSheetV2` contents button.
struct TOCContentsRow: View {
    let theme: ReaderThemeV2
    /// 1-based chapter ordinal shown right-aligned.
    let chapterOrdinal: Int
    let title: String
    /// Page number — nil for formats without a page concept (TXT/MD/EPUB).
    let page: Int?
    /// True when this row is the reader's current chapter.
    let isCurrent: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("\(chapterOrdinal)")
                    .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 12)))
                    .fontWeight(.medium)
                    .foregroundStyle(Color(theme.subColor))
                    .frame(width: 24, alignment: .trailing)

                Text(title)
                    .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 16)))
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .foregroundStyle(Color(isCurrent ? theme.accentColor : theme.inkColor))
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let page {
                    Text("p. \(page)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(theme.subColor))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isCurrent
                          ? Color(theme.accentColor).opacity(theme.isDark ? 0.12 : 0.06)
                          : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - TOCBookmarkRow

/// One Bookmark row — an accent bookmark glyph, a serif-italic 1-line
/// preview, a `chapter · p. N · date` sub-line, and a trailing chevron.
/// A 0.5pt hairline separates rows. JSX `TOCSheetV2` bookmark card.
struct TOCBookmarkRow: View {
    let theme: ReaderThemeV2
    /// 1-line italic preview — the bookmark title, or a fallback.
    let preview: String
    /// `chapter · p. N · date` sub-line, pre-composed by `TOCSheet`.
    let subtitle: String
    /// Whether to draw the 0.5pt bottom hairline (omitted on the last row).
    let showsSeparator: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(theme.accentColor))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(preview)
                            .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 14)))
                            .italic()
                            .foregroundStyle(Color(theme.inkColor))
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(Color(theme.subColor))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(theme.subColor))
                }
                .padding(.vertical, 14)

                if showsSeparator {
                    Rectangle()
                        .fill(Color(theme.ruleColor))
                        .frame(height: 0.5)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
