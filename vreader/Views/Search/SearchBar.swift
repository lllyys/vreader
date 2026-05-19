// Purpose: Feature #63 WI-1 — the custom in-sheet search bar for the
// re-skinned search panel. Replaces the system `.searchable` bar.
// Mirrors the design bundle's search-bar block from
// `dev-docs/designs/vreader-fidelity-v1/project/vreader-search.jsx`:
// a rounded warm-wash field with a leading search glyph, a borderless
// text field, a trailing clear button (shown only when text is
// present), and an accent-colored "Cancel" button.
//
// Scope reconciliation (plan §2.1): the design's "This book / All
// books" scope toggle is OUT of scope for feature #63 — `SearchView`
// searches a single book. This is a single-scope, in-book bar; the
// toggle is omitted rather than shown disabled.
//
// Key decisions:
// - `@FocusState` replicates the system bar's auto-focus (plan risk §2)
//   so the field is ready for input as soon as the sheet opens.
// - The clear button mutates `viewModel.query`; the static `clear(_:)`
//   helper makes that mutation testable without rendering.
// - Geometry / palette from `ReaderThemeV2` tokens — design parity with
//   the rest of the feature #60 v2 chrome.
// - The text field and "Cancel" button each carry a >=44 pt `minHeight`
//   tappable frame + rectangular content shape (Bug #224): SwiftUI sizes
//   neither element to the HIG 44 pt touch-target minimum on its own.
//
// @coordinates-with: SearchView.swift, SearchViewModel.swift,
//   ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-search.jsx`

import SwiftUI

/// The re-skinned search sheet's custom search bar.
struct SearchBar: View {
    /// The search view-model whose `query` the field is bound to.
    @Bindable var viewModel: SearchViewModel
    /// Visual-identity-v2 theme tokens for the bar surface + ink.
    let theme: ReaderThemeV2
    /// Placeholder copy — the design's `Search {book title}`.
    let placeholder: String
    /// Runs when the "Cancel" button is tapped (dismisses the sheet).
    let onCancel: () -> Void

    /// Drives auto-focus on appear — replicates the system search bar.
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            field
            cancelButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Field

    /// The rounded warm-wash field: glyph + text field + clear button.
    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color(theme.subColor))

            TextField(placeholder, text: $viewModel.query)
                .font(.system(size: 15))
                .foregroundStyle(Color(theme.inkColor))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($fieldFocused)
                // Bug #224: SwiftUI sizes a `TextField`'s accessibility
                // element to its ~19 pt text line — below the 44 pt HIG
                // touch-target minimum. A >=44 pt tappable frame plus a
                // rectangular content shape gives motor-impaired /
                // Switch Control users a HIG-compliant target.
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityIdentifier("searchTextField")

            if !viewModel.query.isEmpty {
                Button {
                    Self.clear(viewModel)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(theme.subColor))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .accessibilityIdentifier("searchClearButton")
            }
        }
        // Bug #224: the field's height is governed by the `TextField`'s
        // 44 pt `minHeight` tappable frame (HIG touch-target minimum).
        // Vertical padding is therefore omitted — adding it would stack
        // on top of the 44 pt and oversize the drawn field surface.
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(fieldFillColor))
        )
        .onAppear { fieldFocused = true }
    }

    /// The accent-colored "Cancel" button — dismisses the sheet.
    private var cancelButton: some View {
        Button("Cancel", action: onCancel)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color(theme.accentColor))
            // Bug #224: a bare text-label `Button` is not auto-expanded
            // to 44 pt — its hit region collapses to the ~17 pt glyph
            // box. A >=44 pt tappable frame plus a rectangular content
            // shape meets the HIG touch-target minimum.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityIdentifier("searchCancelButton")
    }

    // MARK: - Tokens

    /// Field fill — the design's `t.isDark ? 'rgba(255,255,255,0.06)'
    /// : 'rgba(0,0,0,0.05)'` warm wash.
    private var fieldFillColor: UIColor {
        theme.isDark
            ? UIColor.white.withAlphaComponent(0.06)
            : UIColor.black.withAlphaComponent(0.05)
    }

    // MARK: - Testable behavior

    /// Clears the search query. Wired to the field's clear button; a
    /// static helper so the mutation is unit-testable without rendering.
    static func clear(_ viewModel: SearchViewModel) {
        viewModel.query = ""
    }
}
