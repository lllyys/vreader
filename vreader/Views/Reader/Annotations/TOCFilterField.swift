// Purpose: Feature #94 WI-1 — the pinned filter field at the top of the
// Contents tab, plus its live result-count line.
//
// Transcribed from the committed design
// (`dev-docs/designs/vreader-fidelity-v1/project/toc-filter-artboards.jsx`
// → `TOCFilterField`): an inline filled pill (38pt tall, 11pt radius) with
// a leading magnifier glyph, a "Filter chapters" placeholder, a `TextField`
// bound to the query, and a trailing clear (✕) button shown only when
// non-empty. Below it, while filtering, the live count line — wording from
// `TOCFilterCountLabel` ("N of M chapters" / "No chapters match"); hidden
// when the query is empty.
//
// The field is PINNED — `TOCSheet` places it OUTSIDE the contents
// `ScrollView` so it stays put while the chapter list scrolls (Gate-2 H2).
// Accessibility ids: `tocFilterField` (the text field) / `tocFilterCount`
// (the count line) per the design's accessibility spec.
//
// @coordinates-with: TOCSheet.swift, TOCSheet+Filter.swift,
//   TOCTitleFilter.swift (TOCFilterCountLabel), ReaderThemeV2.swift

import SwiftUI

/// The Contents-tab filter field + live count line. Themed via
/// `ReaderThemeV2`; the query binds back to `TOCSheet`'s `filterQuery`.
struct TOCFilterField: View {
    let theme: ReaderThemeV2
    @Binding var query: String
    /// Survivor count for the current query (drives the count line).
    let visibleCount: Int
    /// Total TOC entry count (the "of M" denominator).
    let totalCount: Int

    @FocusState private var isFocused: Bool

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasQuery: Bool { !query.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                pill
                // Design's focused-state "Cancel" — clears the query + resigns focus.
                if isFocused {
                    Button("Cancel") {
                        query = ""
                        isFocused = false
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(theme.accentColor))
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tocFilterCancel")
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: isFocused)
            if let countText = TOCFilterCountLabel.text(
                visibleCount: visibleCount,
                totalCount: totalCount,
                trimmedQuery: trimmedQuery
            ) {
                Text(countText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color(theme.subColor))
                    .padding(.top, 7)
                    .padding(.horizontal, 4)
                    .accessibilityIdentifier("tocFilterCount")
                    .accessibilityValue(countText)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var pill: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color(isFocused ? theme.accentColor : theme.subColor))

            TextField("", text: $query, prompt: placeholder)
                .font(.system(size: 15))
                .foregroundStyle(Color(theme.inkColor))
                .tint(Color(theme.accentColor))
                .focused($isFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("tocFilterField")
                .accessibilityLabel("Filter chapters")

            if hasQuery {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(theme.subColor))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tocFilterClear")
                .accessibilityLabel("Clear filter")
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 11)
                .fill(Color.primary.opacity(theme.isDark ? 0.07 : 0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(Color(theme.accentColor), lineWidth: isFocused ? 2 : 0)
        )
    }

    private var placeholder: Text {
        Text("Filter chapters").foregroundColor(Color(theme.subColor))
    }
}
