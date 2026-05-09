// Purpose: JavaScript source constants for EPUB highlight bridge.
// Contains the selection tracking and CSS Highlight API JS injected into WKWebView.
//
// Key decisions:
// - Selection tracking uses debounced selectionchange listener (300ms).
// - XPath serialization covers text nodes and element nodes.
// - CSS Highlight API is the primary path; TreeWalker <mark> fallback for iOS 17.0-17.1.
// - Named color map provides consistent highlight colors across themes.
//
// @coordinates-with: EPUBHighlightBridge.swift, EPUBWebViewBridge.swift

import Foundation

/// JavaScript source constants for the EPUB highlight bridge.
/// Separated from EPUBHighlightBridge to keep file sizes manageable.
extension EPUBHighlightBridge {

    /// JavaScript for tracking text selection changes in the EPUB WKWebView.
    /// Debounced to 300ms. Posts message to Swift with selection details.
    static let selectionTrackingJS = """
    (function() {
        var debounceTimer = null;

        function getXPath(node) {
            if (!node || node.nodeType === 9) return '';
            if (node.nodeType === 3) {
                var parent = node.parentNode;
                if (!parent) return '';
                var textIndex = 0;
                for (var i = 0; i < parent.childNodes.length; i++) {
                    if (parent.childNodes[i] === node) break;
                    if (parent.childNodes[i].nodeType === 3) textIndex++;
                }
                return getXPath(parent) + '/text()[' + (textIndex + 1) + ']';
            }
            if (node.nodeType === 1) {
                var parent = node.parentNode;
                if (!parent) return '/' + node.tagName.toLowerCase();
                var sameTagSiblings = [];
                for (var i = 0; i < parent.childNodes.length; i++) {
                    var sibling = parent.childNodes[i];
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

        document.addEventListener('selectionchange', function() {
            clearTimeout(debounceTimer);
            debounceTimer = setTimeout(function() {
                var sel = window.getSelection();
                if (!sel || sel.isCollapsed || !sel.rangeCount) return;
                var range = sel.getRangeAt(0);
                var text = sel.toString();
                if (!text || !text.trim()) return;

                var rect = range.getBoundingClientRect();
                var msg = {
                    selectedText: text,
                    startPath: getXPath(range.startContainer),
                    startOffset: range.startOffset,
                    endPath: getXPath(range.endContainer),
                    endOffset: range.endOffset,
                    rectX: rect.x,
                    rectY: rect.y,
                    rectWidth: rect.width,
                    rectHeight: rect.height
                };
                window.webkit.messageHandlers.selectionChanged.postMessage(msg);
            }, 300);
        });
    })();
    """

    /// JavaScript implementing the CSS Highlight API bridge functions.
    /// Provides createHighlight, removeHighlight, clearAllHighlights.
    /// Uses CSS Highlight API where available, <mark> fallback otherwise.
    /// Highlight API JS — uses foliate-js SVG Overlayer (primary) with CSS Highlight API fallback.
    /// Also wires footnote detection on link clicks and TTS SSML message handler.
    static let highlightAPIJS = """
    (function() {
        var colorMap = {
            'yellow': 'rgba(255, 235, 59, 0.5)',
            'blue': 'rgba(66, 133, 244, 0.4)',
            'green': 'rgba(52, 168, 83, 0.4)',
            'pink': 'rgba(233, 30, 99, 0.35)',
            'orange': 'rgba(255, 152, 0, 0.4)',
            'purple': 'rgba(156, 39, 176, 0.35)'
        };

        function resolveNodeFromXPath(xpath) {
            try {
                // Bug #159 / GH #472: EPUB chapters load as
                // `application/xhtml+xml`, so `documentElement.namespaceURI`
                // is `http://www.w3.org/1999/xhtml`. XPath 1.0 element
                // names without a prefix do NOT match elements that have
                // a default namespace, so the unqualified paths produced
                // by `getXPath` (e.g. `/html/body/p[3]/text()[1]`)
                // returned null on EPUB pages and the highlight render
                // pipeline silently failed (data persisted, but visual
                // paint never happened). Rewrite element-name segments to
                // `*[local-name()="name"]` so the same path resolves
                // regardless of the element's namespace; preserve the
                // axis tokens `text()`, `comment()`, `node()` so the
                // selection-path shape continues to work.
                var query = xpath;
                var docNS = document.documentElement && document.documentElement.namespaceURI;
                if (docNS) {
                    // Codex audit fix: also tolerate prefix-qualified element
                    // names like `svg:svg` or `math:mfrac` that can appear in
                    // mixed-namespace XHTML (e.g. an EPUB with inline SVG
                    // declared via `xmlns:svg=...`). The regex now accepts
                    // a single optional colon inside the captured name; the
                    // replacement strips the prefix and emits the local part.
                    query = query.replace(/\\/([A-Za-z_][A-Za-z0-9_-]*(?::[A-Za-z_][A-Za-z0-9_-]*)?)/g, function(_, name) {
                        if (name === 'text' || name === 'comment' || name === 'node') {
                            return '/' + name;
                        }
                        var colon = name.indexOf(':');
                        var local = colon >= 0 ? name.substring(colon + 1) : name;
                        return '/*[local-name()="' + local + '"]';
                    });
                }
                var result = document.evaluate(
                    query, document, null,
                    XPathResult.FIRST_ORDERED_NODE_TYPE, null
                );
                return result.singleNodeValue;
            } catch (e) { return null; }
        }

        function buildRange(startPath, startOffset, endPath, endOffset) {
            var startNode = resolveNodeFromXPath(startPath);
            var endNode = resolveNodeFromXPath(endPath);
            if (!startNode || !endNode) return null;
            try {
                var range = document.createRange();
                range.setStart(startNode, Math.min(startOffset, startNode.length || 0));
                range.setEnd(endNode, Math.min(endOffset, endNode.length || 0));
                return range;
            } catch (e) { return null; }
        }

        // === Highlight: CSS Highlight API primary, foliate SVG Overlayer fallback ===
        // Bug #159 / GH #472: the SVG Overlayer paints rectangles into a single
        // SVG element absolutely-positioned over <html>. In paged EPUB mode (CSS
        // multi-column layout), the SVG's bounding rect tracks the visible
        // viewport but rect coordinates come from `range.getClientRects()` in
        // document coords — content shifted into the next column visually
        // appears at viewport y < column-height while its document y is >
        // column-height, so the rect is clipped out of the SVG viewport. CSS
        // Highlight API renders at text-paint time and follows column transforms
        // automatically. Prefer it for user-driven highlights; keep the
        // overlayer as a fallback for older WebKit (pre-iOS 17.2) where the
        // CSS Highlight API isn't available.

        window.__vreader_createHighlight = function(id, startPath, startOffset, endPath, endOffset, color) {
            var range = buildRange(startPath, startOffset, endPath, endOffset);
            if (!range) return;
            var cssColor = colorMap[color] || color;

            // Primary: CSS Highlight API (layout-aware; survives column transforms)
            if (typeof CSS !== 'undefined' && CSS.highlights) {
                try {
                    var highlight = new Highlight(range);
                    CSS.highlights.set('vreader-' + id, highlight);
                    var styleId = 'vreader-hl-style-' + id;
                    if (!document.getElementById(styleId)) {
                        var style = document.createElement('style');
                        style.id = styleId;
                        style.textContent = '::highlight(vreader-' + id + ') { background-color: ' + cssColor + '; }';
                        document.head.appendChild(style);
                    }
                    return;
                } catch (e) { /* fall through to SVG Overlayer */ }
            }

            // Fallback: foliate SVG Overlayer (older WebKit without CSS Highlight API)
            if (window.__foliate && window.__foliate.overlayer) {
                try {
                    window.__foliate.overlayer.add(
                        'hl-' + id, range,
                        window.__foliate.Overlayer.highlight,
                        { color: cssColor }
                    );
                } catch (e) {}
            }
        };

        window.__vreader_removeHighlight = function(id) {
            // Remove from Overlayer
            if (window.__foliate && window.__foliate.overlayer) {
                window.__foliate.overlayer.remove('hl-' + id);
            }
            // Also remove from CSS Highlight API (in case fallback was used)
            if (typeof CSS !== 'undefined' && CSS.highlights) {
                CSS.highlights.delete('vreader-' + id);
                var styleEl = document.getElementById('vreader-hl-style-' + id);
                if (styleEl) styleEl.remove();
            }
        };

        window.__vreader_clearAllHighlights = function() {
            // Clear Overlayer — recreate SVG element (audit fix: stale artifacts)
            if (window.__foliate && window.__foliate.overlayer) {
                var svg = window.__foliate.overlayer.element;
                while (svg.firstChild) svg.removeChild(svg.firstChild);
                window.__foliate.overlayer = new window.__foliate.Overlayer();
                svg.parentNode.replaceChild(window.__foliate.overlayer.element, svg);
            }
            // Clear CSS Highlight API
            if (typeof CSS !== 'undefined' && CSS.highlights) {
                CSS.highlights.clear();
                document.querySelectorAll('style[id^="vreader-hl-style-"]')
                    .forEach(function(s) { s.remove(); });
            }
        };

        // === Footnote Detection: intercept link clicks ===

        document.addEventListener('click', function(e) {
            var a = e.target.closest('a[href]');
            if (!a) return;
            if (window.__foliate && window.__foliate.FootnoteDetector) {
                try {
                    if (window.__foliate.FootnoteDetector.isFootnoteReference(a)) {
                        // Bug #138: post a message for analytics / future
                        // inline-popover hookup. DO NOT preventDefault — the
                        // popover observer was never wired in Swift, and
                        // blocking the default scroll-to-anchor would leave
                        // tapping a footnote feeling broken (nothing happens).
                        // Letting the default behavior run gives the user
                        // standard "scroll to footnote anchor" navigation.
                        var href = a.getAttribute('href');
                        window.webkit.messageHandlers.footnoteHandler.postMessage({
                            href: href,
                            text: a.textContent,
                            type: 'footnote'
                        });
                        // Do NOT return / preventDefault: fall through so the
                        // browser performs default in-page anchor navigation.
                    }
                } catch (err) { /* detection failed, let link navigate normally */ }
            }
        }, true);

        // === TTS SSML: generate word-marked SSML for current visible content ===

        window.__vreader_generateTTSSSML = function() {
            if (!window.__foliate || !window.__foliate.tts) return null;
            var tts = window.__foliate.tts;
            var blocks = tts.getBlocks(document);
            if (!blocks.length) return null;
            // Generate SSML for first block (caller advances via __vreader_nextTTSBlock)
            window.__vreader_ttsBlocks = blocks;
            window.__vreader_ttsBlockIndex = 0;
            var result = tts.generateSSML(blocks[0]);
            return JSON.stringify(result);
        };

        window.__vreader_nextTTSBlock = function() {
            if (!window.__foliate || !window.__foliate.tts) return null;
            if (!window.__vreader_ttsBlocks) return null;
            window.__vreader_ttsBlockIndex++;
            if (window.__vreader_ttsBlockIndex >= window.__vreader_ttsBlocks.length) return null;
            var block = window.__vreader_ttsBlocks[window.__vreader_ttsBlockIndex];
            var result = window.__foliate.tts.generateSSML(block);
            return JSON.stringify(result);
        };

        window.__vreader_setTTSMark = function(markName) {
            if (!window.__foliate || !window.__foliate.tts) return null;
            var info = window.__foliate.tts.setMark(markName);
            if (!info) return null;
            // Highlight the word in the overlayer
            var blocks = window.__vreader_ttsBlocks;
            var idx = window.__vreader_ttsBlockIndex;
            if (blocks && blocks[idx]) {
                var block = blocks[idx];
                try {
                    var range = document.createRange();
                    // Find text node at offset
                    var walker = document.createTreeWalker(block.element, NodeFilter.SHOW_TEXT);
                    var charCount = 0;
                    var node;
                    while ((node = walker.nextNode())) {
                        if (charCount + node.length > info.offset) {
                            var localOffset = info.offset - charCount;
                            range.setStart(node, localOffset);
                            range.setEnd(node, Math.min(localOffset + info.length, node.length));
                            break;
                        }
                        charCount += node.length;
                    }
                    // Highlight via overlayer
                    if (window.__foliate.overlayer) {
                        window.__foliate.overlayer.remove('tts-word');
                        window.__foliate.overlayer.add('tts-word', range,
                            window.__foliate.Overlayer.highlight,
                            { color: 'rgba(66, 133, 244, 0.4)' });
                    }
                } catch (e) {}
            }
            return JSON.stringify(info);
        };

        window.__vreader_clearTTSHighlight = function() {
            if (window.__foliate && window.__foliate.overlayer) {
                window.__foliate.overlayer.remove('tts-word');
            }
        };
    })();
    """
}
