// Purpose: Feature #60 WI-9 — the horizontal Library filter-chip row.
// Mirrors the design `LibraryScreen`'s filter-chip block from
// `dev-docs/designs/vreader-fidelity-v1/project/vreader-library.jsx`:
// a horizontally-scrolling row of full-pill chips, the selected one
// filled near-black, the rest in the warm wash.
//
// Design-vs-reality note (rule 51): the design mock's chip LABELS are
// content categories (`All / Fiction / Non-fiction / Technical /
// Classics / CJK`) — a fixed taxonomy the app does not model. The
// app's real library filter is `LibraryFilter` over user-created
// collections (`CollectionSidebar`). This view therefore renders the
// DESIGNED visual treatment (full-pill chips, near-black selected
// fill, warm-wash rest, horizontal scroll, 13pt label) populated with
// the app's REAL data model — an "All Books" chip plus one chip per
// collection. No chrome is invented; only the data source differs
// from the static mock, which the WI-9 brief explicitly authorizes.
//
// @coordinates-with: LibraryView.swift, LibraryFilter (CollectionSidebar.swift),
//   LibraryCardTokens.swift, CollectionRecord,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-library.jsx`

import SwiftUI

/// Horizontally-scrolling filter-chip row — design `LibraryScreen`
/// filter-chip block, populated from the app's collections.
struct LibraryFilterChips: View {
    /// Two-way bound active filter — shared with `CollectionSidebar`
    /// so the chip row and the sidebar stay in sync.
    @Binding var activeFilter: LibraryFilter
    /// User-created collections; each becomes a chip after "All Books".
    let collections: [CollectionRecord]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LibraryCardTokens.filterChipSpacing) {
                chip(for: .allBooks, label: "All Books")
                ForEach(collections, id: \.name) { collection in
                    chip(
                        for: .collection(collection.name),
                        label: collection.name
                    )
                }
            }
            .padding(.horizontal, LibraryCardTokens.shellEdgePadding)
        }
    }

    // MARK: - Chip

    /// A single filter chip. Selected when `filter` equals the active
    /// filter — selected draws the near-black fill / shell-colour text,
    /// unselected the warm wash / dark-brown text (design parity).
    private func chip(for filter: LibraryFilter, label: String) -> some View {
        let isSelected = activeFilter == filter
        return Button {
            activeFilter = filter
        } label: {
            Text(label)
                .font(.system(
                    size: LibraryCardTokens.filterChipFontSize,
                    weight: .medium
                ))
                .lineLimit(1)
                .foregroundStyle(
                    isSelected
                        ? LibraryCardTokens.filterChipSelectedText
                        : LibraryCardTokens.filterChipText
                )
                .padding(.horizontal, LibraryCardTokens.filterChipHorizontalPadding)
                .padding(.vertical, LibraryCardTokens.filterChipVerticalPadding)
                .background(
                    Capsule().fill(
                        isSelected
                            ? LibraryCardTokens.filterChipSelectedBackground
                            : LibraryCardTokens.filterChipBackground
                    )
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("libraryFilterChip_\(label)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
