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

    /// Feature #71 WI-6b-ii: section-scoped restore for continuous scroll mode.
    /// Filters to highlights anchored at `href`, then emits
    /// `__vreader_createHighlightInSection` calls targeting `spineIndex` so each
    /// stored range re-roots into the matching stitched section's content
    /// wrapper. Returns "" for an empty href or no matches.
    static func restoreHighlightsInSectionJS(
        highlights: [HighlightRecord],
        href: String,
        spineIndex: Int
    ) -> String {
        guard !href.isEmpty else { return "" }

        // Feature #85 WI-2: carry the quote + context so an empty-serializedRange
        // (Readium-created) record re-anchors by quote in the legacy section
        // renderer.
        let matching: [(id: String, range: EPUBSerializedRange, color: String,
                        quote: String, contextBefore: String?, contextAfter: String?)] = highlights
            .compactMap { record in
                guard let anchor = record.anchor,
                      case .epub(let anchorHref, _, let range) = anchor,
                      anchorHref == href else {
                    return nil
                }
                return (id: record.highlightId.uuidString, range: range, color: record.color,
                        quote: record.selectedText,
                        contextBefore: record.locator.textContextBefore,
                        contextAfter: record.locator.textContextAfter)
            }

        return EPUBHighlightBridge.restoreHighlightsInSectionJS(
            spineIndex: spineIndex, highlights: matching
        )
    }
}
