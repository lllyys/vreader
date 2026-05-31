// Purpose: Feature #75 WI-3 — the pre-pagination page-axis probe. Evaluates the
// loaded EPUB spine document's COMPUTED writing-mode / direction (+ the document
// `dir` / `lang`) and resolves it through `PageAxisResolver`. Must run BEFORE the
// app injects its pagination CSS, so it reads the BOOK's writing direction rather
// than the app-authored column CSS (Gate-2 High). The JS + JSON parsing are split
// out as a pure seam so the resolution is unit-testable without a WKWebView.
//
// @coordinates-with: PageAxisResolver.swift, EPUBWebViewBridgeCoordinator.swift
//   (setupPagination evaluates `computedStyleJS`, then calls `resolve`).

import Foundation

enum EPUBPageAxisProbe {
    /// JS that returns a JSON string of the body's computed writing direction.
    /// Run this on the loaded document BEFORE pagination CSS injection.
    static let computedStyleJS = """
    (function() {
        var s = getComputedStyle(document.body);
        var de = document.documentElement;
        return JSON.stringify({
            wm: s.writingMode || '',
            dir: s.direction || '',
            docDir: (de.getAttribute('dir') || document.body.getAttribute('dir') || ''),
            lang: (de.getAttribute('lang') || document.body.getAttribute('lang') || de.lang || '')
        });
    })();
    """

    /// Resolve the `PageAxis` from the probe's `evaluateJavaScript` result.
    /// A nil / malformed result falls back to resolving with empty computed
    /// values (so the hint / default decides) — never crashes.
    static func resolve(from evalResult: Any?, hint: ReadingDirection) -> PageAxis {
        let dict = parse(evalResult)
        return PageAxisResolver.resolve(
            writingMode: dict["wm"] ?? "",
            direction: dict["dir"] ?? "",
            dir: dict["docDir"],
            lang: dict["lang"],
            readingDirectionHint: hint
        )
    }

    /// Parse the probe JSON into a `[String: String]`; `[:]` on any failure.
    static func parse(_ evalResult: Any?) -> [String: String] {
        guard let json = evalResult as? String,
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: String] else {
            return [:]
        }
        return dict
    }
}
