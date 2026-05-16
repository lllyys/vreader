// Purpose: Feature #60 WI-9 — the "All books" section header with its
// sort-order dropdown. Mirrors the design `GridView`'s header block in
// `dev-docs/designs/vreader-fidelity-v1/project/vreader-library.jsx`:
// an 18pt Source Serif 4 "All books" title with a trailing
// label-plus-chevron sort affordance.
//
// Design-vs-reality note (rule 51): the design depicts this header
// inside `GridView` only, with a `Recent ⌄` dropdown label. The app's
// real sort model is `LibrarySortOrder` (Title / Date Added / Last
// Read / Reading Time) — the chevron opens a `Menu` over that real
// enum. The header is rendered above BOTH the grid and the list body
// (the pre-#60 toolbar sort control worked in both modes); reusing a
// DESIGNED component above the list is using designed UI, not
// inventing it. The dropdown label shows the active sort, not a fixed
// "Recent" string, so it reflects real state.
//
// @coordinates-with: LibraryView.swift, LibrarySortOrder.swift,
//   LibraryViewModel.swift, LibraryCardTokens.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-library.jsx`

import SwiftUI

/// The "All books" section header + sort-order dropdown — design
/// `GridView` header block.
struct LibrarySectionHeader: View {
    /// Two-way bound sort order — drives the dropdown label and the
    /// `LibraryViewModel`'s re-sort + persistence (bug #75).
    @Binding var sortOrder: LibrarySortOrder

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("All books")
                .font(LibraryCardTokens.serifTitleFont(
                    size: LibraryCardTokens.sectionHeaderFontSize
                ))
                .fontWeight(.semibold)
                .foregroundStyle(LibraryCardTokens.ink)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            sortMenu
        }
        .padding(.horizontal, LibraryCardTokens.shellContentPadding)
        .padding(.bottom, 14)
    }

    /// The sort dropdown — design `Recent ⌄` affordance, wired to the
    /// app's `LibrarySortOrder`.
    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: $sortOrder) {
                ForEach(LibrarySortOrder.allCases) { order in
                    Text(order.label).tag(order)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(sortOrder.label)
                    .font(.system(size: LibraryCardTokens.subtitleFontSize))
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(LibraryCardTokens.subText)
        }
        .accessibilityLabel("Sort books")
        .accessibilityIdentifier("sortPicker")
    }
}
