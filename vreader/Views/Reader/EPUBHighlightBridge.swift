// Purpose: Bridge between WKWebView JavaScript and Swift for EPUB text highlighting.
// Parses JS selection messages into ReaderSelectionEvent, generates JS for
// creating/removing/restoring CSS Highlight API highlights.
//
// Key decisions:
// - Pure logic — no WKWebView dependency, fully unit-testable.
// - JS generation uses string interpolation with escaping for safety.
// - Selection parsing validates all required fields and ignores empty/whitespace text.
// - JS source constants live in EPUBHighlightJS.swift (extension) to keep file size down.
//
// @coordinates-with: EPUBHighlightJS.swift, EPUBWebViewBridge.swift,
//   ReaderNotifications.swift, AnnotationAnchor.swift, EPUBReaderContainerView.swift

import Foundation
import CoreGraphics

/// Parsed result from a JS selection message.
struct EPUBSelectionMessage: Sendable {
    let selectedText: String
    let range: EPUBSerializedRange
    let sourceRect: CGRect
}

/// Bridge for EPUB text selection and highlight JS interop.
/// All methods are static and pure — no WKWebView dependency.
enum EPUBHighlightBridge {

    // MARK: - Selection Message Parsing

    /// Parses a WKScriptMessage body (dictionary) into an EPUBSelectionMessage.
    /// Returns nil if required fields are missing or the selected text is empty/whitespace.
    static func parseSelectionMessage(_ body: Any) -> EPUBSelectionMessage? {
        guard let dict = body as? [String: Any] else { return nil }

        guard let selectedText = dict["selectedText"] as? String,
              !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        guard let startPath = dict["startPath"] as? String,
              let endPath = dict["endPath"] as? String else {
            return nil
        }

        guard let startOffset = intValue(dict["startOffset"]),
              let endOffset = intValue(dict["endOffset"]) else {
            return nil
        }

        let rectX = doubleValue(dict["rectX"]) ?? 0
        let rectY = doubleValue(dict["rectY"]) ?? 0
        let rectWidth = doubleValue(dict["rectWidth"]) ?? 0
        let rectHeight = doubleValue(dict["rectHeight"]) ?? 0

        let range = EPUBSerializedRange(
            startContainerPath: startPath,
            startOffset: startOffset,
            endContainerPath: endPath,
            endOffset: endOffset
        )

        return EPUBSelectionMessage(
            selectedText: selectedText,
            range: range,
            sourceRect: CGRect(x: rectX, y: rectY, width: rectWidth, height: rectHeight)
        )
    }

    // MARK: - Anchor Construction

    /// Creates an EPUB AnnotationAnchor from href, CFI, and serialized range.
    static func makeAnchor(
        href: String,
        cfi: String,
        range: EPUBSerializedRange
    ) -> AnnotationAnchor {
        .epub(href: href, cfi: cfi, serializedRange: range)
    }

    // MARK: - Selection Event Construction

    /// Creates a ReaderSelectionEvent from parsed selection data.
    static func makeSelectionEvent(
        selectedText: String,
        href: String,
        cfi: String,
        range: EPUBSerializedRange,
        sourceRect: CGRect
    ) -> ReaderSelectionEvent {
        let anchor = makeAnchor(href: href, cfi: cfi, range: range)
        return ReaderSelectionEvent(
            selectedText: selectedText,
            anchor: anchor,
            sourceRect: sourceRect
        )
    }

    // MARK: - Highlight JS Generation

    /// Generates JavaScript to create a CSS Highlight API highlight.
    static func createHighlightJS(
        id: String,
        range: EPUBSerializedRange,
        color: String
    ) -> String {
        let escapedId = jsEscape(id)
        let escapedStartPath = jsEscape(range.startContainerPath)
        let escapedEndPath = jsEscape(range.endContainerPath)
        let escapedColor = jsEscape(color)

        return """
        (function() {
            if (typeof window.__vreader_createHighlight === 'function') {
                window.__vreader_createHighlight(
                    '\(escapedId)',
                    '\(escapedStartPath)',
                    \(range.startOffset),
                    '\(escapedEndPath)',
                    \(range.endOffset),
                    '\(escapedColor)'
                );
            }
        })();
        """
    }

    /// Generates JavaScript to remove a highlight by ID.
    static func removeHighlightJS(id: String) -> String {
        let escapedId = jsEscape(id)
        return """
        (function() {
            if (typeof window.__vreader_removeHighlight === 'function') {
                window.__vreader_removeHighlight('\(escapedId)');
            }
        })();
        """
    }

    /// Generates JavaScript to restore multiple highlights at once.
    static func restoreHighlightsJS(
        highlights: [(id: String, range: EPUBSerializedRange, color: String)]
    ) -> String {
        guard !highlights.isEmpty else { return "" }

        var calls: [String] = []
        for hl in highlights {
            let escapedId = jsEscape(hl.id)
            let escapedStartPath = jsEscape(hl.range.startContainerPath)
            let escapedEndPath = jsEscape(hl.range.endContainerPath)
            let escapedColor = jsEscape(hl.color)
            calls.append("""
                window.__vreader_createHighlight(
                    '\(escapedId)',
                    '\(escapedStartPath)',
                    \(hl.range.startOffset),
                    '\(escapedEndPath)',
                    \(hl.range.endOffset),
                    '\(escapedColor)'
                );
            """)
        }

        return """
        (function() {
            if (typeof window.__vreader_createHighlight === 'function') {
                \(calls.joined(separator: "\n            "))
            }
        })();
        """
    }

    /// JavaScript to clear all highlights from the page.
    static let clearAllHighlightsJS = """
    (function() {
        if (typeof window.__vreader_clearAllHighlights === 'function') {
            window.__vreader_clearAllHighlights();
        }
    })();
    """

    // MARK: - Search Highlight (Bug #43)

    /// Generates JavaScript to find and temporarily highlight a search match in the EPUB page.
    /// Uses window.find() to locate the text, then wraps the selection in a styled span.
    /// The highlight auto-clears after 3 seconds.
    /// Returns an empty string if textQuote is empty or whitespace-only.
    ///
    /// - Parameters:
    ///   - textQuote: The text to search for and highlight.
    ///   - progression: Optional scroll fraction (0.0-1.0). When provided and > 0,
    ///     the JS scrolls to that position and clears any selection first, so
    ///     `window.find()` starts searching from near the target location instead
    ///     of always finding the first occurrence (Issue 4).
    static func searchHighlightJS(textQuote: String, progression: Double? = nil) -> String {
        let trimmed = textQuote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let escaped = jsEscape(trimmed)

        // Build optional scroll-before-find block
        let scrollBlock: String
        if let progression, progression > 0 {
            scrollBlock = """
                // Issue 4: Scroll to approximate position so window.find starts near target
                window.getSelection().removeAllRanges();
                var docHeight = document.documentElement.scrollHeight || document.body.scrollHeight;
                window.scrollTo(0, \(progression) * docHeight);
            """
        } else {
            scrollBlock = ""
        }

        return """
        (function() {
            // Remove any previous search highlight
            var existing = document.querySelectorAll('.vreader_search_highlight');
            existing.forEach(function(el) {
                var parent = el.parentNode;
                while (el.firstChild) parent.insertBefore(el.firstChild, el);
                parent.removeChild(el);
            });

            \(scrollBlock)
            // Use window.find to locate text, then wrap selection
            var found = window.find('\(escaped)', false, false, true);
            if (found) {
                var sel = window.getSelection();
                if (sel && sel.rangeCount > 0) {
                    var range = sel.getRangeAt(0);
                    var span = document.createElement('span');
                    span.className = 'vreader_search_highlight';
                    span.style.backgroundColor = 'rgba(255, 230, 0, 0.45)';
                    span.style.borderRadius = '2px';
                    var contents = range.extractContents();
                    span.appendChild(contents);
                    range.insertNode(span);
                    sel.removeAllRanges();
                    span.scrollIntoView({ behavior: 'smooth', block: 'center' });
                    // Auto-clear after 3s
                    setTimeout(function() {
                        var hl = document.querySelector('.vreader_search_highlight');
                        if (hl) {
                            var p = hl.parentNode;
                            while (hl.firstChild) p.insertBefore(hl.firstChild, hl);
                            p.removeChild(hl);
                        }
                    }, 3000);
                }
            }
        })();
        """
    }

    /// JavaScript to clear any temporary search highlight from the EPUB page.
    static let clearSearchHighlightJS = """
    (function() {
        var highlights = document.querySelectorAll('.vreader_search_highlight');
        highlights.forEach(function(el) {
            var parent = el.parentNode;
            while (el.firstChild) parent.insertBefore(el.firstChild, el);
            parent.removeChild(el);
        });
    })();
    """

    // MARK: - Private Helpers

    /// Escapes a string for safe inclusion in single-quoted JS string literals.
    /// Bug #135: delegates to the shared `FoliateJSEscaper` so EPUB and Foliate
    /// readers share a single vetted escape implementation. Adds coverage for
    /// `\t`, U+2028, and U+2029 — the latter two are ECMAScript line
    /// terminators that broke search-highlight JS for queries containing
    /// legit Unicode separators (e.g., some CJK ebooks).
    private static func jsEscape(_ string: String) -> String {
        FoliateJSEscaper.escapeForJSString(string)
    }

    /// Extracts an Int from a JS message value (handles Int, Double, NSNumber).
    private static func intValue(_ value: Any?) -> Int? {
        if let intVal = value as? Int { return intVal }
        if let doubleVal = value as? Double { return Int(doubleVal) }
        return nil
    }

    /// Extracts a Double from a JS message value.
    private static func doubleValue(_ value: Any?) -> Double? {
        if let doubleVal = value as? Double { return doubleVal }
        if let intVal = value as? Int { return Double(intVal) }
        return nil
    }
}
