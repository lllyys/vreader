// Purpose: DEBUG-only JS builder + result parser for the EPUB DebugBridge
// highlight-driver (Bug #220 / GH #845 — verification harness
// highlight-creator for EPUB). The companion to
// `EPUBReaderContainerView+DebugBridgeHighlight.swift`: this file holds the
// pure-value JS construction + result parsing so they can be unit-tested
// without a WKWebView.
//
// Flow:
//   1. URL → DebugCommand.parse → .highlight(startUTF16:endUTF16:color:)
//   2. RealDebugBridgeContext.highlight posts `.debugBridgeHighlightCommand`
//   3. EPUBReaderContainerView's DEBUG observer receives the notification,
//      builds the JS via `buildResolveRangeJS`, evaluates it in the active
//      EPUB WebView, parses the return value via `parseResult`, and then
//      persists via `HighlightCoordinator.create(...)`. The coordinator
//      itself calls `EPUBHighlightRenderer.apply(record:)` which paints
//      with the canonical persisted UUID via `__vreader_createHighlight`.
//
// Design — JS resolves DOM range only, does NOT paint:
//
// An earlier round of this fix had the JS paint the highlight with a
// transient UUID and then let the post-persist `restoreAll` re-paint with
// the canonical record ID. Codex Gate-4 Round-1 (High) flagged that the
// EPUB restore path is additive, not replace-all — the transient ID would
// stay painted and tap-targetable on the live page until a chapter reload.
// The cleaner design is to have the JS only resolve the DOM range, then
// let the Swift-side `HighlightCoordinator.create` → `renderer.apply`
// pipeline paint with the canonical persisted UUID (the same flow the
// gesture path uses). This file's JS therefore deliberately does NOT
// call `__vreader_createHighlight`.
//
// Why JS-driven for range resolution (not Swift-driven like TXT/MD):
// EPUB content is rendered inside a WKWebView as a DOM. A highlight needs
// an `EPUBSerializedRange` (start/end XPath + offset pairs) that only the
// DOM knows. Building the range from a JS-walk of visible text nodes
// preserves the gesture path's invariants — the resulting
// `EPUBSerializedRange` is byte-identical to what the selection-tracking
// JS would have produced for the same span.
//
// Entire file compiled out of Release builds via `#if DEBUG`.
//
// @coordinates-with EPUBReaderContainerView+DebugBridgeHighlight.swift,
//   EPUBHighlightBridge.swift, EPUBHighlightJS.swift,
//   EPUBHighlightRenderer.swift, EPUBHighlightActions.swift,
//   AnnotationAnchor.swift

#if DEBUG

import Foundation

/// Pure JS builder + result parser for the EPUB DebugBridge highlight
/// driver. All methods are static + pure — no WKWebView dependency.
enum EPUBDebugBridgeHighlightJS {

    // MARK: - Parsed result

    /// The parsed payload from the JS `evaluateJavaScript` return value.
    /// `selectedText` is the actual phrase captured (used as
    /// `selectedText:` for `HighlightCoordinator.create`); `range` is the
    /// canonical EPUB range (used to build the `AnnotationAnchor.epub`
    /// anchor that the production gesture path persists). The Swift
    /// caller pairs this with the active chapter's `href` (read from
    /// `viewModel.makeCurrentLocator()`) to construct the anchor.
    struct Result: Equatable {
        let range: EPUBSerializedRange
        let selectedText: String
    }

    // MARK: - JS construction

    /// Builds the JS expression evaluated in the active EPUB WebView.
    ///
    /// The JS:
    ///   1. Walks visible text nodes (skipping `data-vreader-decoration`
    ///      so bilingual mode doesn't shift the offset, matching the
    ///      production XPath serializer in `EPUBHighlightJS.swift`).
    ///   2. Snaps `TARGET_START` / `TARGET_END` to scalar boundaries —
    ///      Codex Gate-4 Round-1 Medium fix: a UTF-16 offset that lands
    ///      between the high+low surrogates of a non-BMP scalar (emoji,
    ///      ancient scripts, etc.) would otherwise produce a half-scalar
    ///      DOM range. Snaps `start` backward and `end` forward to
    ///      surround the full scalar.
    ///   3. Finds the text-node + intra-node offset corresponding to
    ///      the snapped offsets in the concatenated chapter text.
    ///   4. Builds the same XPath shape (`/html/body/.../text()[N]`) the
    ///      production selection-tracking JS produces, so a bridge-driven
    ///      highlight is dedupe-compatible with a gesture-driven one at
    ///      the same range.
    ///   5. Returns `{ startPath, startOffset, endPath, endOffset,
    ///      selectedText }` as the IIFE's value. Swift reads it from
    ///      `evaluateJavaScript`'s result callback, parses it via
    ///      `parseResult`, and persists. The paint happens via
    ///      `coordinator.create` → `renderer.apply` with the canonical
    ///      persisted record UUID.
    ///
    /// Returns `null` from the JS (Swift sees `nil` / `NSNull`) on:
    ///   - empty visible text in the chapter
    ///   - `TARGET_START` / `TARGET_END` out of range
    ///   - selected text trims to empty (whitespace-only span — Codex
    ///     Gate-4 Round-1 Medium fix: match the gesture path's
    ///     `!selectedText.trim()` rejection in `selectionTrackingJS`)
    ///
    /// `startUTF16` / `endUTF16` are inlined as integer literals (already
    /// validated by `DebugCommand.parse` as `>= 0` and `start < end`).
    /// No untrusted string interpolation — the JS body is a constant
    /// modulo the two integer literals, so JS-injection surface is nil.
    static func buildResolveRangeJS(
        startUTF16: Int,
        endUTF16: Int
    ) -> String {
        return """
        (function() {
            var TARGET_START = \(startUTF16);
            var TARGET_END = \(endUTF16);

            // Feature #56 WI-10 (R-EPUB-CFI): bilingual mode injects
            // `<div data-vreader-decoration>` siblings. Skip them so
            // the index of every following text node matches what the
            // production XPath serializer (EPUBHighlightJS.selectionTrackingJS)
            // produces.
            function isDecoration(node) {
                return node && node.nodeType === 1
                    && node.hasAttribute
                    && node.hasAttribute('data-vreader-decoration');
            }

            // Mirror of getXPath in EPUBHighlightJS.selectionTrackingJS so
            // the path serialized here is byte-identical to a gesture-
            // produced path at the same selection.
            function getXPath(node) {
                if (!node || node.nodeType === 9) return '';
                if (node.nodeType === 3) {
                    var parent = node.parentNode;
                    if (!parent) return '';
                    var textIndex = 0;
                    for (var i = 0; i < parent.childNodes.length; i++) {
                        var n = parent.childNodes[i];
                        if (isDecoration(n)) continue;
                        if (n === node) break;
                        if (n.nodeType === 3) textIndex++;
                    }
                    return getXPath(parent) + '/text()[' + (textIndex + 1) + ']';
                }
                if (node.nodeType === 1) {
                    var parent = node.parentNode;
                    if (!parent) return '/' + node.tagName.toLowerCase();
                    var sameTagSiblings = [];
                    for (var i = 0; i < parent.childNodes.length; i++) {
                        var sibling = parent.childNodes[i];
                        if (isDecoration(sibling)) continue;
                        if (sibling.nodeType === 1 && sibling.tagName === node.tagName) {
                            sameTagSiblings.push(sibling);
                        }
                    }
                    var index = sameTagSiblings.indexOf(node) + 1;
                    var tagName = node.tagName.toLowerCase();
                    if (sameTagSiblings.length > 1) {
                        return getXPath(parent) + '/' + tagName + '[' + index + ']';
                    }
                    return getXPath(parent) + '/' + tagName;
                }
                return '';
            }

            // Walk the document body collecting non-empty text nodes
            // (skipping decoration siblings + their subtrees). Build a
            // running prefix sum of UTF-16 lengths so we can map a global
            // chapter offset to the text node containing it.
            if (!document.body) return null;
            var textNodes = [];
            var prefixLen = [];
            var runningLen = 0;
            var walker = document.createTreeWalker(
                document.body,
                NodeFilter.SHOW_TEXT,
                {
                    acceptNode: function(node) {
                        // Reject text whose ancestor is a decoration node.
                        var p = node.parentNode;
                        while (p) {
                            if (isDecoration(p)) return NodeFilter.FILTER_REJECT;
                            p = p.parentNode;
                            if (p === document.body) break;
                        }
                        if (!node.data || node.data.length === 0) {
                            return NodeFilter.FILTER_REJECT;
                        }
                        return NodeFilter.FILTER_ACCEPT;
                    }
                },
                false
            );
            var n;
            while ((n = walker.nextNode())) {
                textNodes.push(n);
                prefixLen.push(runningLen);
                runningLen += n.data.length;
            }
            if (textNodes.length === 0) return null;

            // Reject ranges that fall outside the document's UTF-16 stream.
            if (TARGET_START < 0 || TARGET_END > runningLen
                || TARGET_END <= TARGET_START) {
                return null;
            }

            // Locate the text node + intra-node offset for a global
            // chapter offset. Linear scan is fine — EPUB chapters
            // typically have <1000 text nodes; a binary search would
            // optimize the wrong axis.
            function locate(offset) {
                for (var i = 0; i < textNodes.length; i++) {
                    var nodeLen = textNodes[i].data.length;
                    if (offset < prefixLen[i] + nodeLen) {
                        return { node: textNodes[i], localOffset: offset - prefixLen[i] };
                    }
                }
                // End boundary lands exactly at runningLen → last node end.
                var lastIdx = textNodes.length - 1;
                return {
                    node: textNodes[lastIdx],
                    localOffset: textNodes[lastIdx].data.length
                };
            }

            // Codex Gate-4 Round-1 Medium fix: a UTF-16 offset that
            // lands between the high+low surrogate code units of a
            // non-BMP scalar (emoji, ancient scripts, etc.) would build
            // a half-scalar DOM range. JS code unit at index `i` is the
            // low surrogate of a pair iff `charCodeAt(i) >= 0xDC00 &&
            // charCodeAt(i) <= 0xDFFF` AND `charCodeAt(i-1) >= 0xD800 &&
            // charCodeAt(i-1) <= 0xDBFF`. Snap `start` backward and
            // `end` forward to surround the full scalar.
            function snapToScalarBoundary(loc, direction) {
                if (!loc) return loc;
                var node = loc.node;
                var off = loc.localOffset;
                var data = node.data;
                if (off <= 0 || off >= data.length) return loc;
                var prev = data.charCodeAt(off - 1);
                var curr = data.charCodeAt(off);
                var splitsSurrogate = prev >= 0xD800 && prev <= 0xDBFF
                    && curr >= 0xDC00 && curr <= 0xDFFF;
                if (!splitsSurrogate) return loc;
                if (direction === 'backward') {
                    return { node: node, localOffset: off - 1 };
                } else {
                    return { node: node, localOffset: off + 1 };
                }
            }

            var startLoc = snapToScalarBoundary(locate(TARGET_START), 'backward');
            var endLoc = snapToScalarBoundary(locate(TARGET_END), 'forward');
            if (!startLoc || !endLoc) return null;

            // Capture the selected text by composing the substring across
            // the spanned nodes.
            var selectedText = '';
            if (startLoc.node === endLoc.node) {
                selectedText = startLoc.node.data.substring(
                    startLoc.localOffset, endLoc.localOffset
                );
            } else {
                var startIdx = textNodes.indexOf(startLoc.node);
                var endIdx = textNodes.indexOf(endLoc.node);
                selectedText += startLoc.node.data.substring(startLoc.localOffset);
                for (var j = startIdx + 1; j < endIdx; j++) {
                    selectedText += textNodes[j].data;
                }
                selectedText += endLoc.node.data.substring(0, endLoc.localOffset);
            }

            // Codex Gate-4 Round-1 Medium fix: match the gesture path
            // (`selectionTrackingJS` rejects `!text.trim()`). Whitespace-
            // only selections are not meaningful highlights and would
            // create an invisible / undeletable ghost entry. Use a
            // regex test because String.prototype.trim is universally
            // supported here (WKWebView ships ES2015+) — equivalent to
            // !selectedText.trim().
            if (!selectedText || !/\\S/.test(selectedText)) return null;

            var startPath = getXPath(startLoc.node);
            var endPath = getXPath(endLoc.node);
            if (!startPath || !endPath) return null;

            return {
                startPath: startPath,
                startOffset: startLoc.localOffset,
                endPath: endPath,
                endOffset: endLoc.localOffset,
                selectedText: selectedText
            };
        })();
        """
    }

    // MARK: - Result parsing

    /// Parses the dictionary returned by `evaluateJavaScript` into a
    /// `Result`. Returns `nil` when the JS returned `null` / `NSNull`,
    /// when the payload isn't a dictionary, when required keys are
    /// missing, or when `selectedText` is empty.
    ///
    /// Accepts integer fields as `Int` or `Double` because WKWebView's
    /// `evaluateJavaScript` returns JS numbers as `NSNumber`, which
    /// Swift can deserialize as either depending on the value.
    static func parseResult(_ raw: Any?) -> Result? {
        guard let dict = raw as? [String: Any] else { return nil }
        guard let startPath = dict["startPath"] as? String,
              !startPath.isEmpty,
              let endPath = dict["endPath"] as? String,
              !endPath.isEmpty,
              let startOffset = intValue(dict["startOffset"]),
              let endOffset = intValue(dict["endOffset"]),
              let selectedText = dict["selectedText"] as? String,
              !selectedText.isEmpty else {
            return nil
        }
        let range = EPUBSerializedRange(
            startContainerPath: startPath,
            startOffset: startOffset,
            endContainerPath: endPath,
            endOffset: endOffset
        )
        return Result(range: range, selectedText: selectedText)
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        return nil
    }
}

#endif
