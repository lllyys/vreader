// Purpose: Row view for displaying a single search result with highlighted snippet.
//
// Key decisions:
// - Strips FTS5 <b>...</b> markers and applies bold styling via AttributedString.
// - Shows source context (chapter, page, section) as secondary text.
// - Accessibility labels for VoiceOver.
//
// @coordinates-with SearchView.swift, SearchResult (SearchService.swift)

import SwiftUI

/// Row view for a single search result.
struct SearchResultRow: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(highlightedSnippet)
                .font(.body)
                .lineLimit(3)

            if !result.sourceContext.isEmpty {
                Text(result.sourceContext)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("searchResultRow")
    }

    // MARK: - Private

    /// Converts FTS5 snippet with <b>...</b> markers to an AttributedString with bold.
    private var highlightedSnippet: AttributedString {
        let raw = result.snippet
        var attributed = AttributedString()

        // Parse <b>...</b> tags for bold highlighting
        var remaining = raw[raw.startIndex...]
        while let boldStart = remaining.range(of: "<b>") {
            // Add text before <b>
            let before = remaining[remaining.startIndex..<boldStart.lowerBound]
            if !before.isEmpty {
                attributed.append(AttributedString(String(before)))
            }

            remaining = remaining[boldStart.upperBound...]

            // Find closing </b>
            if let boldEnd = remaining.range(of: "</b>") {
                let boldText = String(remaining[remaining.startIndex..<boldEnd.lowerBound])
                var boldAttr = AttributedString(boldText)
                boldAttr.font = .body.bold()
                boldAttr.foregroundColor = .primary
                attributed.append(boldAttr)
                remaining = remaining[boldEnd.upperBound...]
            } else {
                // No closing tag — add rest as-is
                attributed.append(AttributedString(String(remaining)))
                remaining = remaining[remaining.endIndex...]
            }
        }

        // Add any remaining text
        if !remaining.isEmpty {
            attributed.append(AttributedString(String(remaining)))
        }

        // Fallback if no tags found
        if attributed.characters.isEmpty && !raw.isEmpty {
            attributed = AttributedString(raw)
        }

        return attributed
    }

    private var accessibilityText: String {
        let clean = result.snippet
            .replacingOccurrences(of: "<b>", with: "")
            .replacingOccurrences(of: "</b>", with: "")
        if result.sourceContext.isEmpty {
            return clean
        }
        return "\(clean), \(result.sourceContext)"
    }
}
