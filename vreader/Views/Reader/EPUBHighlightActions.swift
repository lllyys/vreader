// Purpose: Pure-logic handlers for EPUB highlight actions.
// Generates JS for visual injection and filters highlights by chapter
// for page-load restoration.
//
// Key decisions:
// - Pure logic — no WKWebView or SwiftUI dependency.
// - Delegates to EPUBHighlightBridge for JS generation.
// - Anchor filtering by href ensures only matching-chapter highlights are restored.
//
// @coordinates-with: EPUBHighlightBridge.swift, EPUBReaderContainerView.swift,
//   AnnotationAnchor.swift

import Foundation

/// Pure-logic handlers for EPUB highlight JS generation.
enum EPUBHighlightActions {

    // MARK: - Create Highlight JS

    /// Generates JavaScript to visually create a highlight from a record.
    /// Returns nil if the record has no EPUB anchor (e.g., PDF or nil anchor).
    static func createHighlightJS(for record: HighlightRecord) -> String? {
        guard let anchor = record.anchor,
              case .epub(_, _, let range) = anchor else {
            return nil
        }
        return EPUBHighlightBridge.createHighlightJS(
            id: record.highlightId.uuidString,
            range: range,
            color: record.color
        )
    }

    // MARK: - Restore Highlights JS

    /// Generates JavaScript to restore all highlights matching the given chapter href.
    /// Filters out highlights with non-EPUB or nil anchors, and those from other chapters.
    /// Returns an empty string if no highlights match.
    static func restoreHighlightsJS(
        highlights: [HighlightRecord],
        currentHref: String
    ) -> String {
        guard !currentHref.isEmpty else { return "" }

        let matching: [(id: String, range: EPUBSerializedRange, color: String)] = highlights
            .compactMap { record in
                guard let anchor = record.anchor,
                      case .epub(let href, _, let range) = anchor,
                      href == currentHref else {
                    return nil
                }
                return (id: record.highlightId.uuidString, range: range, color: record.color)
            }

        return EPUBHighlightBridge.restoreHighlightsJS(highlights: matching)
    }
}
