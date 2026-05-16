// Purpose: Feature #60 WI-9 — a single card in the "Continue reading"
// rail. Mirrors the design `ContinueCard` from
// `dev-docs/designs/vreader-fidelity-v1/project/vreader-library.jsx`:
// a 124×186 cover with an in-cover white progress strip, then a
// 2-line Source Serif 4 title and a `{percent}% · {lastRead}` meta
// line.
//
// Key decisions:
// - Reuses `BookCoverArtView` (the WI-8 shared cover) for the spine /
//   page-edge / shadow treatment, sized to the design's 124×186.
// - The in-cover progress strip is the design's white-on-image strip
//   (same token family as the WI-8 grid card's strip), shown for
//   every card — the rail only ever holds in-progress books, so the
//   strip always applies.
// - Percent + relative last-read text reuse `LibraryBookItem`'s
//   progress state and `ReadingTimeFormatter` so the rail agrees with
//   the list row's metadata.
//
// @coordinates-with: ContinueReadingRail.swift, BookCoverArtView.swift,
//   LibraryCardTokens.swift, LibraryBookItem.swift, CustomCoverStore.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-library.jsx`

import SwiftUI

/// A single "Continue reading" rail card — design `ContinueCard`.
struct LibraryContinueCard: View {
    let book: LibraryBookItem
    /// Bumped by the parent when a custom cover changes, to force reload.
    var coverVersion: Int = 0
    let onOpen: (LibraryBookItem) -> Void

    var body: some View {
        Button {
            onOpen(book)
        } label: {
            VStack(
                alignment: .leading,
                spacing: LibraryCardTokens.continueCardStackSpacing
            ) {
                cover
                titleAndMeta
            }
            .frame(width: LibraryCardTokens.continueCardCoverWidth)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to open")
        .accessibilityIdentifier("continueCard_\(book.fingerprintKey)")
    }

    // MARK: - Cover + progress strip

    private var cover: some View {
        BookCoverArtView(
            image: customCoverImage,
            coverColor: coverColor,
            formatIcon: book.formatIcon,
            formatBadge: book.formatBadge,
            cornerRadius: LibraryCardTokens.continueCardCoverCornerRadius
        )
        .frame(
            width: LibraryCardTokens.continueCardCoverWidth,
            height: LibraryCardTokens.continueCardCoverHeight
        )
        .overlay { progressStrip }
    }

    /// In-cover progress strip — the design's white-on-image bar inset
    /// from the cover's bottom edge. The fill spans `fraction` of the
    /// track. Measured inside a `GeometryReader` so the 6pt horizontal
    /// inset never depends on outer-padding proposal order.
    @ViewBuilder
    private var progressStrip: some View {
        if case .inProgress(let fraction) = book.readingProgressState {
            GeometryReader { geo in
                let inset = LibraryCardTokens.coverProgressStripInset
                let height = LibraryCardTokens.coverProgressStripHeight
                let radius = LibraryCardTokens.coverProgressStripCornerRadius
                let trackWidth = max(0, geo.size.width - inset * 2)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: radius)
                        .fill(LibraryCardTokens.coverProgressTrack)
                    RoundedRectangle(cornerRadius: radius)
                        .fill(LibraryCardTokens.coverProgressFill)
                        .frame(width: trackWidth * CGFloat(fraction))
                }
                .frame(width: trackWidth, height: height)
                .position(
                    x: geo.size.width / 2,
                    y: geo.size.height - height / 2
                        - LibraryCardTokens.continueCardStripBottomInset
                )
            }
        }
    }

    // MARK: - Title + meta

    private var titleAndMeta: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(book.title)
                .font(LibraryCardTokens.serifTitleFont(
                    size: LibraryCardTokens.continueCardTitleFontSize
                ))
                .fontWeight(.semibold)
                .lineLimit(2)
                .foregroundStyle(LibraryCardTokens.ink)

            HStack(spacing: 5) {
                Text(percentText)
                    .fontWeight(.medium)
                if let lastRead = lastReadText {
                    Text("·").foregroundStyle(
                        LibraryCardTokens.subText.opacity(0.4)
                    )
                    Text(lastRead).lineLimit(1)
                }
            }
            .font(.system(size: LibraryCardTokens.continueCardMetaFontSize))
            .foregroundStyle(LibraryCardTokens.subText)
        }
    }

    // MARK: - Testing surface

    /// Exposed so the WI-9 contract tests can pin the rail card's
    /// percent / last-read derivation without a SwiftUI render.
    var percentTextForTesting: String { percentText }
    var lastReadTextForTesting: String? { lastReadText }

    // MARK: - Private

    /// Reading-progress percentage label — e.g. "42%". Clamped to
    /// `[0, 100]`; a not-started / finished book (which the rail never
    /// shows) yields "0%" / "100%" rather than crashing.
    private var percentText: String {
        let fraction: Double
        switch book.readingProgressState {
        case .notStarted: fraction = 0
        case .finished:   fraction = 1
        case .inProgress(let value): fraction = value
        }
        let percent = Int((fraction * 100).rounded())
        return "\(min(max(percent, 0), 100))%"
    }

    /// Relative last-read text, or nil when the book has no recorded
    /// last-read timestamp.
    private var lastReadText: String? {
        guard let lastReadAt = book.lastReadAt else { return nil }
        return ReadingTimeFormatter.formatRelativeLastRead(from: lastReadAt)
    }

    /// Loads the custom cover for this book (if any). `coverVersion`
    /// dependency ensures SwiftUI re-evaluates when covers change.
    private var customCoverImage: UIImage? {
        _ = coverVersion
        return CustomCoverStore.loadCover(for: book.fingerprintKey)
    }

    private var coverColor: Color {
        switch book.format.lowercased() {
        case "epub": return .blue
        case "pdf":  return .red
        case "txt":  return .gray
        case "md":   return .purple
        default:     return .secondary
        }
    }

    private var accessibilityLabel: String {
        AccessibilityFormatters.accessibleBookDescription(
            title: book.title,
            author: book.author,
            format: book.format,
            readingTimeSeconds: book.totalReadingSeconds
        )
    }
}
