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
    /// Feature #56 WI-14 — optional translate-entire-book progress for
    /// this book. Drives `LibraryCardTranslateBadge` overlay (running
    /// chip / translated check). Default `.idle` hides the overlay
    /// entirely so cards stay visually identical for non-translated
    /// books. The translate action itself lives on the LibraryView's
    /// `bookContextMenu(for:)`, not inside the card — keeping the card
    /// view itself purely presentational.
    var translateProgress: BookTranslationProgress = .idle(total: 0)

    var body: some View {
        VStack(alignment: .leading, spacing: LibraryCardTokens.cardStackSpacing) {
            // Cover: fixed 2:3 ratio container — uniform card height in grid
            BookCoverArtView(
                image: customCoverImage,
                fingerprintKey: book.fingerprintKey,
                title: book.title,
                author: book.author,
                cornerRadius: LibraryCardTokens.cardCoverCornerRadius
            )
            // Per-book reading-progress accents (feature #60 WI-8) —
            // the in-cover strip while reading, the checkmark when done.
            .overlay { progressStrip }
            .overlay(alignment: .topTrailing) { finishedBadge }
            // Feature #56 WI-14 — translate-status badge. Two visual
            // states: bottom running chip, top-right translated check
            // (per the design). Hidden when phase is .idle.
            .overlay(alignment: .bottom) { translateRunningBadge }
            .overlay(alignment: .topTrailing) { translateDoneBadge }

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

    /// Exposed so the WI-8 contract tests can assert which progress
    /// state the card derives — the strip / checkmark are otherwise
    /// opaque SwiftUI overlays.
    var progressStateForTesting: LibraryBookItem.ReadingProgressState {
        book.readingProgressState
    }

    // MARK: - Private

    private let accessibilityHint = "Double tap to open"

    /// Loads the custom cover for this book (if any). `coverVersion`
    /// dependency ensures SwiftUI re-evaluates when covers change.
    private var customCoverImage: UIImage? {
        _ = coverVersion // force re-evaluation when version changes
        return CustomCoverStore.loadCover(for: book.fingerprintKey)
    }

    private var accessibilityLabel: String {
        AccessibilityFormatters.accessibleBookDescription(
            title: book.title,
            author: book.author,
            format: book.format,
            readingTimeSeconds: book.totalReadingSeconds
        )
    }

    // MARK: - Reading-progress accents (feature #60 WI-8)

    /// In-cover progress strip — design `GridView`: a thin bar inset
    /// from the cover's bottom edge, shown only while the book is
    /// partially read. The fill spans `fraction` of the track width.
    ///
    /// The `GeometryReader` spans the whole cover (it is the overlay
    /// content); the strip's width and position are computed inside
    /// the measured space, so the 6pt horizontal inset and 4pt bottom
    /// inset never depend on outer-`padding` proposal order.
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
                        - LibraryCardTokens.coverProgressStripBottomInset
                )
            }
        }
    }

    /// Feature #56 WI-14 — running translate-book chip pinned to the
    /// bottom of the cover. Only renders while a job is in flight.
    @ViewBuilder
    private var translateRunningBadge: some View {
        if translateProgress.phase == .running {
            LibraryCardTranslateBadge(progress: translateProgress)
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
        }
    }

    /// Feature #56 WI-14 — translated check pinned to the cover's
    /// top-right. Renders only when the book has a completed whole-
    /// book translation.
    @ViewBuilder
    private var translateDoneBadge: some View {
        if translateProgress.phase == .completed {
            LibraryCardTranslateBadge(progress: translateProgress)
                .padding(6)
        }
    }

    /// Finished checkmark — design `GridView`: a white disc with a
    /// green check inset from the cover's top-trailing corner, shown
    /// only when the book is fully read.
    @ViewBuilder
    private var finishedBadge: some View {
        if book.readingProgressState == .finished {
            Circle()
                .fill(LibraryCardTokens.coverFinishedBadgeFill)
                .frame(
                    width: LibraryCardTokens.finishedBadgeSize,
                    height: LibraryCardTokens.finishedBadgeSize
                )
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(LibraryCardTokens.finished)
                }
                .padding(LibraryCardTokens.finishedBadgeInset)
        }
    }
}
