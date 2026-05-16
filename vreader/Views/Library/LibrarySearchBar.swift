// Purpose: Feature #60 WI-9 — the toggleable Library search bar.
// Mirrors the design `LibraryScreen`'s search block from
// `dev-docs/designs/vreader-fidelity-v1/project/vreader-library.jsx`:
// a rounded warm-wash field with a leading magnifier, a borderless
// text field, and a trailing clear button that appears once text is
// entered.
//
// The field filters the library by title / author substring (the
// derivation lives in `LibraryContainerModel`). The design's
// placeholder mentions "content"; the JSX filter is title/author
// only, so the placeholder text is kept faithful to the design while
// the behavior matches the actual designed filter.
//
// Key decisions:
// - Geometry + palette from `LibraryCardTokens`.
// - The field is shown / hidden by the parent (`LibraryView` owns the
//   `showSearch` `@State`); this view only renders when mounted.
// - Clear button is shown only when the bound text is non-empty —
//   design parity (`{query && (...)}`).
//
// @coordinates-with: LibraryView.swift, LibraryContainerModel.swift,
//   LibraryCardTokens.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-library.jsx`

import SwiftUI

/// The toggleable Library search field — design `LibraryScreen` search block.
struct LibrarySearchBar: View {
    /// Two-way bound search text. Trimmed by `LibraryContainerModel`
    /// before it filters.
    @Binding var query: String

    var body: some View {
        HStack(spacing: LibraryCardTokens.searchFieldIconSpacing) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(LibraryCardTokens.subText)

            TextField("Search title, author, content…", text: $query)
                .font(.system(size: LibraryCardTokens.searchFieldFontSize))
                .foregroundStyle(LibraryCardTokens.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("librarySearchField")

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(LibraryCardTokens.subText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .accessibilityIdentifier("librarySearchClearButton")
            }
        }
        .padding(.horizontal, LibraryCardTokens.searchFieldHorizontalPadding)
        .padding(.vertical, LibraryCardTokens.searchFieldVerticalPadding)
        .background(
            RoundedRectangle(
                cornerRadius: LibraryCardTokens.searchFieldCornerRadius
            )
            .fill(LibraryCardTokens.searchFieldBackground)
        )
        .padding(.horizontal, LibraryCardTokens.shellEdgePadding)
    }
}
