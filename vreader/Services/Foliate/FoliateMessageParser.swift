// Purpose: Static parser that converts raw JS message bodies (Any) into typed Swift events.
// Isolates parsing logic from WKWebView so it can be tested without WebKit dependencies.
//
// Key decisions:
// - Accepts `Any` to match WKScriptMessage.body's type.
// - Returns nil for invalid/unparseable payloads (caller decides error handling).
// - Pure functions, no side effects, no state.
//
// @coordinates-with: FoliateTypes.swift, FoliateViewCoordinator.swift

import Foundation
import CoreGraphics

enum FoliateMessageParser {

    /// Parse a `relocate` message body into a typed event.
    /// Expected keys: cfi, fraction, sectionIndex, sectionTotal, tocLabel?, tocHref?
    static func parseRelocate(_ body: Any) -> FoliateRelocateEvent? {
        guard let dict = body as? [String: Any] else { return nil }
        guard let cfi = dict["cfi"] as? String else { return nil }

        // fraction may arrive as Int (e.g. 0 instead of 0.0) from JS
        let fraction: Double
        if let d = dict["fraction"] as? Double {
            fraction = d
        } else if let i = dict["fraction"] as? Int {
            fraction = Double(i)
        } else {
            return nil
        }

        guard let sectionIndex = dict["sectionIndex"] as? Int else { return nil }
        guard let sectionTotal = dict["sectionTotal"] as? Int else { return nil }

        let tocLabel = dict["tocLabel"] as? String
        let tocHref = dict["tocHref"] as? String

        return FoliateRelocateEvent(
            cfi: cfi,
            fraction: fraction,
            sectionIndex: sectionIndex,
            sectionTotal: sectionTotal,
            tocLabel: tocLabel,
            tocHref: tocHref
        )
    }

    /// Parse a `selection` message body into a typed event.
    /// Expected keys: cfi, text, rect {x, y, width, height}, index
    /// Returns nil if collapsed=true (no text selected), if cfi is
    /// empty / whitespace-only (downstream paint + tap-resolver both
    /// reject empty CFIs — Bug #201 Codex round 1), or if cfi / text
    /// / index are missing.
    ///
    /// The `rect` is best-effort: if the dict is missing or malformed,
    /// the event is still returned with `rect = .zero`. The popover-
    /// anchoring path is not yet wired (rects come from foliate-host.js
    /// in a future iteration); the highlight-create path doesn't read
    /// rect at all. Per Codex round 1: rejecting the entire event on
    /// rect drift silently drops valid highlights when foliate-host.js
    /// changes its rect shape.
    static func parseSelection(_ body: Any) -> FoliateSelectionEvent? {
        guard let dict = body as? [String: Any] else { return nil }

        // Reject collapsed selections
        if let collapsed = dict["collapsed"] as? Bool, collapsed {
            return nil
        }

        guard let cfi = dict["cfi"] as? String else { return nil }
        // Bug #201 Codex round 1: reject empty/whitespace-only CFIs at
        // parse time. Downstream observers (`.foliateRequestAnnotationJSCreate`
        // requires `!cfi.isEmpty`; `FoliateHighlightTapResolver` matches
        // only on non-empty CFIs) would otherwise persist a highlight
        // that can neither paint nor round-trip on tap.
        guard !cfi.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        guard let text = dict["text"] as? String else { return nil }
        guard let index = dict["index"] as? Int else { return nil }

        // Bug #201 Codex round 1: rect is best-effort. Highlight-create
        // path doesn't use it; popover-anchoring (future) can re-query
        // when foliate-host.js ships rect-forwarding consistently.
        let rect = (dict["rect"] as? [String: Any])
            .flatMap { parseRect($0) }
            ?? .zero

        return FoliateSelectionEvent(
            cfi: cfi,
            text: text,
            rect: rect,
            sectionIndex: index
        )
    }

    /// Parse a `create-overlay` message body into a section index.
    /// Expected shape: `{index: Int}` per `foliate-host.js:48-52`.
    /// Returns `nil` when the body isn't a dict, the `index` key is
    /// missing, or `index` is not an `Int` (e.g., drifted to Double).
    /// `Int` 0 is a valid index (first section emits create-overlay
    /// on book open), so missing must be distinguished from zero
    /// — `as? Int` already does the right thing.
    ///
    /// Bug #207 / GH #765: lets `FoliateSpikeView.Coordinator.handleMessage`
    /// surface section-overlay-ready events without inline body
    /// introspection, mirroring the `parseSelection` /
    /// `parseRelocate` pattern.
    static func parseCreateOverlay(_ body: Any) -> Int? {
        guard let dict = body as? [String: Any] else { return nil }
        return dict["index"] as? Int
    }

    /// Parse a `book-ready` message body into book metadata.
    /// Expected keys: title, author, language, sections, layout, toc
    static func parseBookReady(_ body: Any) -> FoliateBookInfo? {
        guard let dict = body as? [String: Any] else { return nil }
        guard let title = dict["title"] as? String else { return nil }
        guard let sections = dict["sections"] as? Int else { return nil }
        guard let layout = dict["layout"] as? String else { return nil }

        // Author, language, and TOC are optional — real metadata is often sparse
        let author = dict["author"] as? String ?? ""
        let language = dict["language"] as? String ?? ""
        let tocArray = dict["toc"] as? [[String: Any]] ?? []
        let toc = parseTOC(tocArray)

        return FoliateBookInfo(
            title: title,
            author: author,
            language: language,
            sections: sections,
            layout: layout,
            toc: toc
        )
    }

    /// Parse an `error` message body into (message, type) tuple.
    /// Expected keys: message, type
    static func parseError(_ body: Any) -> (message: String, type: String)? {
        guard let dict = body as? [String: Any] else { return nil }
        guard let message = dict["message"] as? String else { return nil }
        guard let type = dict["type"] as? String else { return nil }
        return (message: message, type: type)
    }

    /// Parse a TOC array from Foliate-js into typed items.
    /// Each entry has: label, href, subitems (recursive).
    static func parseTOC(_ array: [[String: Any]]) -> [FoliateTOCItem] {
        array.compactMap { entry in
            guard let label = entry["label"] as? String else { return nil }
            guard let href = entry["href"] as? String else { return nil }

            let subitemsArray = entry["subitems"] as? [[String: Any]] ?? []
            let subitems = parseTOC(subitemsArray)

            return FoliateTOCItem(label: label, href: href, subitems: subitems)
        }
    }

    // MARK: - Private Helpers

    /// Parse a rect dictionary with x, y, width, height into CGRect.
    /// Returns nil if any of the four fields are missing.
    private static func parseRect(_ dict: [String: Any]) -> CGRect? {
        guard let x = asDouble(dict["x"]) else { return nil }
        guard let y = asDouble(dict["y"]) else { return nil }
        guard let width = asDouble(dict["width"]) else { return nil }
        guard let height = asDouble(dict["height"]) else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Coerce a value to Double, accepting both Double and Int.
    private static func asDouble(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        return nil
    }
}
