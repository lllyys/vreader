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

    // MARK: - Tap-on-Highlight Message Parsing (Feature #53 WI-4)

    /// Parses a WKScriptMessage body from the `highlightTapHandler` channel
    /// into a `ReaderHighlightTapEvent`. Returns nil when the payload is
    /// not a dictionary or the `id` field isn't a valid UUID string.
    /// Missing rect fields default to a `.zero` source rect — the caller
    /// then falls back to tap-location anchoring for the presenter.
    static func parseHighlightTapMessage(_ body: Any) -> ReaderHighlightTapEvent? {
        guard let dict = body as? [String: Any] else { return nil }
        guard let idString = dict["id"] as? String,
              let id = UUID(uuidString: idString) else { return nil }
        let rectX = doubleValue(dict["rectX"]) ?? 0
        let rectY = doubleValue(dict["rectY"]) ?? 0
        let rectWidth = doubleValue(dict["rectWidth"]) ?? 0
        let rectHeight = doubleValue(dict["rectHeight"]) ?? 0
        let rect = CGRect(x: rectX, y: rectY, width: rectWidth, height: rectHeight)
        return ReaderHighlightTapEvent(highlightID: id, sourceRect: rect)
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
    /// Bug #182 round-3: a cross-chapter search-result tap defers this JS to
    /// `webView(_:didFinish:)`, but at that instant the freshly-loaded chapter
    /// has not finished its post-load relayout — foliate-js `cssPreprocessJS`
    /// rewrites every `-epub-*` / `page-break-*` rule `atDocumentEnd`. A single
    /// `window.find()` there returns `false`, so the highlight span is never
    /// created. The JS now polls `window.find()` on a 50ms cadence (bounded at
    /// 40 attempts ≈ 2s) until the rendered text tree is searchable, then stops.
    ///
    /// - Parameters:
    ///   - textQuote: The text to search for and highlight.
    ///   - progression: Optional scroll fraction (0.0-1.0). When provided and > 0,
    ///     the JS scrolls to that position once before searching so the viewport
    ///     starts near the target location (Issue 4).
    static func searchHighlightJS(textQuote: String, progression: Double? = nil) -> String {
        let trimmed = textQuote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let escaped = jsEscape(trimmed)

        // Build optional scroll-before-find block. Runs once, before the
        // retry loop — re-scrolling on every poll would fight scrollIntoView.
        let scrollBlock: String
        if let progression, progression > 0 {
            scrollBlock = """
                // Issue 4: Scroll to approximate position so the viewport starts near target
                var docHeight = document.documentElement.scrollHeight || document.body.scrollHeight;
                window.scrollTo(0, \(progression) * docHeight);
            """
        } else {
            scrollBlock = ""
        }

        return """
        (function() {
            // Bug #182 round-3 (audit): bump a generation token so two
            // rapid search taps can't leave two retry loops racing — an
            // older loop bails as soon as a newer tap supersedes it.
            var myGen = (window.__vreaderSearchHighlightGen || 0) + 1;
            window.__vreaderSearchHighlightGen = myGen;

            // Unwrap every previous search highlight (querySelectorAll, so
            // a stale span from a superseded loop can never leak).
            function clearAll() {
                var spans = document.querySelectorAll('.vreader_search_highlight');
                spans.forEach(function(el) {
                    var parent = el.parentNode;
                    while (el.firstChild) parent.insertBefore(el.firstChild, el);
                    parent.removeChild(el);
                });
            }
            clearAll();

            \(scrollBlock)
            var selection = window.getSelection();
            if (selection) { selection.removeAllRanges(); }

            // Bug #182 round-3: poll window.find() until the freshly-loaded
            // chapter DOM has settled enough to be searchable. Bounded so a
            // genuinely-absent quote self-terminates instead of looping.
            var attemptsLeft = 40;
            function attempt() {
                // A newer search tap superseded this loop — stop.
                if (window.__vreaderSearchHighlightGen !== myGen) { return; }
                var found = window.find('\(escaped)', false, false, true);
                if (found) {
                    var sel = window.getSelection();
                    if (sel && sel.rangeCount > 0) {
                        try {
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
                            // Auto-clear after 3s (skip if a newer tap took over)
                            setTimeout(function() {
                                if (window.__vreaderSearchHighlightGen === myGen) { clearAll(); }
                            }, 3000);
                            return;
                        } catch (e) {
                            // Range invalidated mid-relayout — clear and let
                            // the bounded retry loop try again once settled.
                            sel.removeAllRanges();
                        }
                    } else if (sel) {
                        // window.find() matched but produced no usable range —
                        // reset the selection so the next poll restarts clean.
                        sel.removeAllRanges();
                    }
                }
                attemptsLeft--;
                if (attemptsLeft > 0) {
                    setTimeout(attempt, 50);
                }
            }
            attempt();
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
