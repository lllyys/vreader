// Purpose: Feature #60 WI-9 — the "Continue reading" horizontal rail.
// Mirrors the design `LibraryScreen`'s continue-reading block from
// `dev-docs/designs/vreader-fidelity-v1/project/vreader-library.jsx`:
// an 18pt Source Serif 4 section header with a trailing "See all"
// label, then a horizontally-scrolling row of `LibraryContinueCard`s.
//
// Design-vs-reality note (rule 51): the design's "See all" is a
// non-interactive `<div>` (no `onClick`) — it depicts a label, not a
// wired affordance, and there is no designed "all in-progress books"
// destination screen. It is therefore rendered as the designed static
// text, NOT a button. Wiring it would require an undesigned
// destination; that is deliberately out of scope for WI-9.
//
// Key decisions:
// - The design caps the rail at the first 5 cards (`recent.slice(0,5)`);
//   this view applies the same cap.
// - The rail is mounted by the parent only when
//   `LibraryContainerModel.showsContinueReadingRail` is true and the
//   in-progress set is non-empty — so this view always renders ≥1 card.
//
// @coordinates-with: LibraryView.swift, LibraryContinueCard.swift,
//   LibraryContainerModel.swift, LibraryCardTokens.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-library.jsx`

import SwiftUI

/// The "Continue reading" horizontal rail — design `LibraryScreen`
/// continue-reading block.
struct ContinueReadingRail: View {
    /// In-progress books for the rail. The parent passes the already-
    /// filtered set; this view caps it at the design's first 5.
    let books: [LibraryBookItem]
    /// Bumped by the parent when a custom cover changes.
    var coverVersion: Int = 0
    let onOpen: (LibraryBookItem) -> Void

    /// Design caps the rail at the first 5 cards (`recent.slice(0, 5)`).
    private static let maxCards = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            railScroll
        }
        .padding(.bottom, 24)
        .accessibilityIdentifier("continueReadingRail")
    }

    // MARK: - Header

    /// `Continue reading` title + the design's static "See all" label.
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Continue reading")
                .font(LibraryCardTokens.serifTitleFont(
                    size: LibraryCardTokens.sectionHeaderFontSize
                ))
                .fontWeight(.semibold)
                .foregroundStyle(LibraryCardTokens.ink)

            Spacer(minLength: 0)

            // Design `See all` is a non-interactive label (no onClick).
            Text("See all")
                .font(.system(
                    size: LibraryCardTokens.subtitleFontSize,
                    weight: .medium
                ))
                .foregroundStyle(LibraryCardTokens.seeAllAccent)
        }
        .padding(.horizontal, LibraryCardTokens.shellContentPadding)
        .padding(.bottom, 10)
    }

    // MARK: - Rail

    private var railScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(
                alignment: .top,
                spacing: LibraryCardTokens.continueRailSpacing
            ) {
                ForEach(books.prefix(Self.maxCards)) { book in
                    LibraryContinueCard(
                        book: book,
                        coverVersion: coverVersion,
                        onOpen: onOpen
                    )
                }
            }
            .padding(.horizontal, LibraryCardTokens.shellContentPadding)
        }
    }
}
