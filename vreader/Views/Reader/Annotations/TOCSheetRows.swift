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
    /// Feature #94 — the non-overlapping ranges of the active filter query
    /// inside `title` (empty when not filtering). Every matched run is
    /// tinted; the plain-`Text` fast path is taken when this is empty so
    /// the unfiltered list pays no `AttributedString` cost.
    let matchRanges: [Range<String.Index>]
    /// Page number — nil for formats without a page concept (TXT/MD/EPUB).
    let page: Int?
    /// True when this row is the reader's current chapter.
    let isCurrent: Bool
    let onTap: () -> Void

    init(
        theme: ReaderThemeV2,
        chapterOrdinal: Int,
        title: String,
        matchRanges: [Range<String.Index>] = [],
        page: Int?,
        isCurrent: Bool,
        onTap: @escaping () -> Void
    ) {
        self.theme = theme
        self.chapterOrdinal = chapterOrdinal
        self.title = title
        self.matchRanges = matchRanges
        self.page = page
        self.isCurrent = isCurrent
        self.onTap = onTap
    }

    /// The current-chapter visual treatment, derived once from `theme` +
    /// `isCurrent` so the highlight decision is a single named value the
    /// body reads and the tests pin (Bug #248: the user reported the
    /// current-chapter title "isn't highlighted"). Mirrors the design
    /// `vreader-panels.jsx` TOCSheet: the current row's title is the accent
    /// colour at weight 600 with an accent-tinted background; every other
    /// row is the ink colour at weight 400 with a clear background.
    struct Style: Equatable {
        /// Title foreground colour — `accentColor` when current, else `inkColor`.
        let titleColor: UIColor
        /// Title weight — `.semibold` (the design's 600) when current, else `.regular`.
        let titleWeight: Font.Weight
        /// Row background fill — an accent tint when current, else clear.
        let background: Color

        static func make(theme: ReaderThemeV2, isCurrent: Bool) -> Style {
            Style(
                titleColor: isCurrent ? theme.accentColor : theme.inkColor,
                titleWeight: isCurrent ? .semibold : .regular,
                background: isCurrent
                    ? Color(theme.accentColor).opacity(theme.isDark ? 0.12 : 0.06)
                    : Color.clear
            )
        }
    }

    var body: some View {
        let style = Style.make(theme: theme, isCurrent: isCurrent)
        Button(action: onTap) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("\(chapterOrdinal)")
                    .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 12)))
                    .fontWeight(.medium)
                    .foregroundStyle(Color(theme.subColor))
                    .frame(width: 24, alignment: .trailing)

                titleText(style: style)
                    .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 16)))
                    .fontWeight(style.titleWeight)
                    .foregroundStyle(Color(style.titleColor))
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
                RoundedRectangle(cornerRadius: 10).fill(style.background)
            )
        }
        .buttonStyle(.plain)
    }

    /// The chapter title. Plain `Text` when not filtering (no
    /// `AttributedString` overhead); a match-tinted `AttributedString`
    /// when the filter query matched runs in the title. The accent ink +
    /// bold of the current-chapter row come from the `.foregroundStyle` /
    /// `.fontWeight` modifiers on the returned `Text`, so the match tint
    /// (background + underline) composes UNDER them (Feature #94 design).
    @ViewBuilder
    private func titleText(style: Style) -> some View {
        if matchRanges.isEmpty {
            Text(title)
        } else {
            Text(Self.highlightedTitle(title, matchRanges: matchRanges, accent: theme.accentColor))
        }
    }

    /// Builds the match-tinted attributed title — every matched run gets a
    /// 15%-opacity accent background and a 40%-opacity accent underline
    /// (the in-text-highlight vocabulary, scaled to inline type). Marks
    /// ALL occurrences, not just the first.
    static func highlightedTitle(
        _ title: String,
        matchRanges: [Range<String.Index>],
        accent: UIColor
    ) -> AttributedString {
        var attributed = AttributedString(title)
        let tint = Color(accent).opacity(0.15)
        let underlineUIColor = accent.withAlphaComponent(0.40)
        for range in matchRanges {
            // Map the `String.Index` range onto the `AttributedString`.
            guard let lower = AttributedString.Index(range.lowerBound, within: attributed),
                  let upper = AttributedString.Index(range.upperBound, within: attributed)
            else { continue }
            // Background tint resolves through the SwiftUI attribute scope.
            attributed[lower..<upper].backgroundColor = tint
            // The colored underline lives in the UIKit attribute scope —
            // `Text(AttributedString)` honours it and it carries its own
            // colour independent of the run's foreground (the design's
            // 40%-accent underline composes under the current-row accent
            // ink + bold).
            attributed[lower..<upper].uiKit.underlineStyle = .single
            attributed[lower..<upper].uiKit.underlineColor = underlineUIColor
        }
        return attributed
    }
}

#if DEBUG
extension TOCContentsRow {
    /// Inspectable snapshot of the current-chapter row styling — pins the
    /// Bug #248 highlight decision (accent + bold + tint vs ink + regular +
    /// clear) without rendering a view.
    struct StyleProbe {
        let foregroundUIColor: UIColor
        let isBold: Bool
        let hasBackgroundTint: Bool
    }

    static func styleForTesting(theme: ReaderThemeV2, isCurrent: Bool) -> StyleProbe {
        let style = Style.make(theme: theme, isCurrent: isCurrent)
        return StyleProbe(
            foregroundUIColor: style.titleColor,
            isBold: style.titleWeight == .semibold,
            hasBackgroundTint: style.background != Color.clear
        )
    }
}
#endif

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

/// Feature #94 — the pinned "Reading" row shown above the filtered Contents
/// list when the active chapter has been filtered OUT, so the current location
/// stays reachable (the design's `PinnedCurrentRow`). Tapping navigates to it.
struct PinnedCurrentRow: View {
    let theme: ReaderThemeV2
    let title: String
    /// 1-based page, nil for formats without a page concept.
    let page: Int?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("READING")
                        .font(.system(size: 9.5, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(Color(theme.accentColor))
                    Text(title)
                        .font(.system(size: 14.5, weight: .semibold, design: .serif))
                        .foregroundStyle(Color(theme.accentColor))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let page {
                        Text("p.\(page)")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color(theme.accentColor).opacity(0.8))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(theme.accentColor).opacity(theme.isDark ? 0.12 : 0.06))
                )
                .padding(.horizontal, 8)
                .padding(.top, 8)
                Rectangle()
                    .fill(Color(theme.ruleColor))
                    .frame(height: 0.5)
                    .padding(.top, 8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tocPinnedCurrentRow")
        .accessibilityLabel("Reading: \(title)")
    }
}
