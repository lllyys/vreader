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

        // Feature #56 WI-10 (R-EPUB-CFI): bilingual mode injects
        // `<div data-vreader-decoration>` siblings after each
        // translatable block. The XPath serializer counts
        // `parent.childNodes` siblings; without skipping decoration
        // nodes the index of every following sibling would shift by
        // N once bilingual is on, and existing persisted highlights
        // (feature #11) would mis-anchor on the next chapter load.
        // The producer (selection-tracking, here) and the resolver
        // (highlightAPIJS, below) BOTH apply this filter so the path
        // serialized at selection time matches the path the
        // resolver walks at restore time.
        function isDecoration(node) {
            return node && node.nodeType === 1
                && node.hasAttribute
                && node.hasAttribute('data-vreader-decoration');
        }

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

        document.addEventListener('selectionchange', function() {
            clearTimeout(debounceTimer);
            debounceTimer = setTimeout(function() {
                var sel = window.getSelection();
                if (!sel || sel.isCollapsed || !sel.rangeCount) return;
                var range = sel.getRangeAt(0);
                var text = sel.toString();
                if (!text || !text.trim()) return;

                var rect = range.getBoundingClientRect();
                // Feature #71 WI-5: attribute the selection to its section's href
                // in continuous-scroll mode (the stitched DOM holds many chapters).
                // closest('[data-vreader-href]') of the START / END containers'
                // elements; both null in legacy single-chapter mode (no such
                // ancestor) → Swift reads nil and falls back to the global
                // currentHref, leaving the one-chapter path unchanged.
                var startEl = range.startContainer.nodeType === 1
                    ? range.startContainer
                    : range.startContainer.parentElement;
                var endEl = range.endContainer.nodeType === 1
                    ? range.endContainer
                    : range.endContainer.parentElement;
                var startSection = startEl ? startEl.closest('[data-vreader-href]') : null;
                var endSection = endEl ? endEl.closest('[data-vreader-href]') : null;
                // Gate-2 [C1]: a drag can cross a chapter boundary in the stitched
                // DOM. A mixed-section range (start in section A, end in B) can't be
                // restored/painted per-section, so CLAMP the range to the END of the
                // START section — the popover then operates on that single section's
                // text. If the clamp empties the selection (degenerate), REJECT it
                // (no popover). In legacy mode startSection/endSection are null so
                // this never runs.
                if (startSection && endSection && startSection !== endSection) {
                    range.setEnd(startSection, startSection.childNodes.length);
                    text = range.toString();
                    if (!text || !text.trim()) return;
                    rect = range.getBoundingClientRect();
                }
                var msg = {
                    selectedText: text,
                    startPath: getXPath(range.startContainer),
                    startOffset: range.startOffset,
                    endPath: getXPath(range.endContainer),
                    endOffset: range.endOffset,
                    rectX: rect.x,
                    rectY: rect.y,
                    rectWidth: rect.width,
                    rectHeight: rect.height,
                    sectionHref: startSection ? startSection.getAttribute('data-vreader-href') : null
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

        // Bug #159 / GH #472: EPUB chapters load as `application/xhtml+xml`, so
        // `documentElement.namespaceURI` is the XHTML namespace. XPath 1.0
        // element names without a prefix do NOT match default-namespaced
        // elements, so unqualified `getXPath` paths (e.g. `/html/body/p[3]`)
        // returned null and highlights silently failed to paint. Rewrite each
        // element-name segment to `*[local-name()="name"]` so the path resolves
        // regardless of namespace; preserve the axis tokens text()/comment()/node().
        // Also tolerates prefix-qualified names (`svg:svg`) by emitting the local
        // part. Extracted (WI-6b-ii) so the document-rooted resolver AND the
        // section-scoped resolver share one rewrite.
        function rewriteXPathNS(xpath) {
            var docNS = document.documentElement && document.documentElement.namespaceURI;
            if (!docNS) return xpath;
            return xpath.replace(/\\/([A-Za-z_][A-Za-z0-9_-]*(?::[A-Za-z_][A-Za-z0-9_-]*)?)/g, function(_, name) {
                if (name === 'text' || name === 'comment' || name === 'node') {
                    return '/' + name;
                }
                var colon = name.indexOf(':');
                var local = colon >= 0 ? name.substring(colon + 1) : name;
                return '/*[local-name()="' + local + '"]';
            });
        }

        function resolveNodeFromXPath(xpath) {
            try {
                var result = document.evaluate(
                    rewriteXPathNS(xpath), document, null,
                    XPathResult.FIRST_ORDERED_NODE_TYPE, null
                );
                return result.singleNodeValue;
            } catch (e) { return null; }
        }

        // WI-6b-ii: resolve a chapter-document XPath (e.g. `/html/body/p[3]/text()[1]`)
        // RELATIVE to a continuous-scroll chapter-content root. In scroll mode the
        // rewriter places the chapter body's children inside
        // `<section data-vreader-spine-index="N"> … <div class="vreader-chapter-content">`,
        // so strip the `/html/body` document prefix and evaluate the remainder
        // against `contentRoot` (whose child-index space matches the original
        // `<body>`). Returns null when the path is not document-rooted (the
        // section-scoped resolve only handles chapter-document paths).
        function resolveNodeFromXPathInSection(xpath, contentRoot) {
            try {
                // Require the literal `/html/body` document prefix (optional [1]
                // positional predicates) — reject anything else so a malformed or
                // corrupted persisted path can't silently re-root to the wrong
                // node (Codex Gate-4 Low). Reduce it to a section-relative `.` base.
                var rel = xpath.replace(/^\\/html(?:\\[1\\])?\\/body(?:\\[1\\])?(?=\\/|$)/, '.');
                if (rel === xpath || rel.charAt(0) !== '.') return null;
                var result = document.evaluate(
                    rewriteXPathNS(rel), contentRoot, null,
                    XPathResult.FIRST_ORDERED_NODE_TYPE, null
                );
                return result.singleNodeValue;
            } catch (e) { return null; }
        }

        function makeRange(startNode, startOffset, endNode, endOffset) {
            if (!startNode || !endNode) return null;
            try {
                var range = document.createRange();
                range.setStart(startNode, Math.min(startOffset, startNode.length || 0));
                range.setEnd(endNode, Math.min(endOffset, endNode.length || 0));
                return range;
            } catch (e) { return null; }
        }

        function buildRange(startPath, startOffset, endPath, endOffset) {
            return makeRange(
                resolveNodeFromXPath(startPath), startOffset,
                resolveNodeFromXPath(endPath), endOffset
            );
        }

        // WI-6b-ii: build a range from chapter-document paths re-rooted into a
        // continuous-scroll chapter-content element.
        function buildRangeInSection(startPath, startOffset, endPath, endOffset, contentRoot) {
            return makeRange(
                resolveNodeFromXPathInSection(startPath, contentRoot), startOffset,
                resolveNodeFromXPathInSection(endPath, contentRoot), endOffset
            );
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

        // Feature #53 WI-4: registry of {id → Range} for tap-on-highlight
        // hit-testing. Populated by `__vreader_createHighlight`, cleared by
        // `__vreader_removeHighlight` / `__vreader_clearAllHighlights`.
        // The click listener below uses it to map a tap point to a
        // highlight UUID without going through CSS.highlights (which
        // doesn't expose Range membership in a tap-time-cheap way).
        window.__vreader_highlightRanges = window.__vreader_highlightRanges || {};

        // WI-6b-ii: apply a resolved Range as a highlight — CSS Highlight API
        // primary (layout-aware; survives column transforms), foliate SVG
        // Overlayer fallback (older WebKit without the CSS Highlight API).
        // Extracted from `__vreader_createHighlight` so the document-rooted and
        // section-rooted (continuous-scroll) paths share one implementation.
        function applyHighlightRange(id, range, color) {
            var cssColor = colorMap[color] || color;
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
                    // WI-4: remember the live Range so the click handler can hit-test.
                    window.__vreader_highlightRanges[id] = range;
                    return;
                } catch (e) { /* fall through to SVG Overlayer */ }
            }
            if (window.__foliate && window.__foliate.overlayer) {
                try {
                    window.__foliate.overlayer.add(
                        'hl-' + id, range,
                        window.__foliate.Overlayer.highlight,
                        { color: cssColor }
                    );
                    window.__vreader_highlightRanges[id] = range;
                } catch (e) {}
            }
        }

        window.__vreader_createHighlight = function(id, startPath, startOffset, endPath, endOffset, color) {
            var range = buildRange(startPath, startOffset, endPath, endOffset);
            if (!range) return;
            applyHighlightRange(id, range, color);
        };

        // WI-6b-ii: section-scoped highlight restore for continuous scroll mode.
        // Resolves the stored chapter-document XPaths relative to the matching
        // section's `.vreader-chapter-content` wrapper, so a range captured in the
        // single-chapter document re-roots into the correct stitched section.
        // No-op when the section (or its content wrapper) is not currently
        // materialized in the window.
        window.__vreader_createHighlightInSection = function(spineIndex, id, startPath, startOffset, endPath, endOffset, color) {
            var section = document.querySelector('[data-vreader-spine-index="' + spineIndex + '"]');
            if (!section) return;
            var contentRoot = section.querySelector('.vreader-chapter-content') || section;
            var range = buildRangeInSection(startPath, startOffset, endPath, endOffset, contentRoot);
            if (!range) return;
            applyHighlightRange(id, range, color);
        };

        // Feature #85 WI-2: build a Range from a text QUOTE within a content
        // root — the re-anchor for empty-`serializedRange` highlight records
        // (Readium-created highlights persist a quote + context but no DOM
        // range, so the path-based restore above can't paint them; with
        // approach C they surface when scroll mode renders this legacy stitch).
        // Walks text nodes (SKIPPING injected bilingual `data-vreader-decoration`
        // subtrees), flattens to a string with an offset→node map, finds the
        // quote (preferring the occurrence whose preceding text matches the
        // stored context, so a repeated phrase disambiguates), and creates a
        // Range. Returns null when the quote isn't found.
        function findQuoteRangeInRoot(root, quote, contextBefore, contextAfter) {
            if (!root || !quote) return null;
            var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
                acceptNode: function(n) {
                    var p = n.parentNode;
                    while (p && p !== root) {
                        if (p.nodeType === 1 && p.hasAttribute &&
                            p.hasAttribute('data-vreader-decoration')) {
                            return NodeFilter.FILTER_REJECT;
                        }
                        p = p.parentNode;
                    }
                    return NodeFilter.FILTER_ACCEPT;
                }
            });
            var nodes = [], starts = [], flat = '', node;
            while ((node = walker.nextNode())) {
                starts.push(flat.length);
                nodes.push(node);
                flat += node.nodeValue;
            }
            if (!nodes.length) return null;
            // Mirror Swift `QuoteRecovery`: enumerate ALL occurrences and
            // disambiguate by scoring BOTH the preceding (contextBefore) and
            // following (contextAfter) context, so a repeated quote anchors to
            // the right occurrence (Gate-4 Medium — contextBefore-only could
            // silently mis-anchor). Case-insensitive fallback for cross-engine
            // normalization drift (Gate-4 Low); whitespace-normalized matching
            // is intentionally NOT ported (the offset re-mapping is complex in
            // JS) — a quote that matches neither exactly nor case-insensitively
            // degrades to a no-op (no paint), never a WRONG anchor.
            function allIndexes(hay, needle) {
                var out = [], i = hay.indexOf(needle);
                while (i >= 0) { out.push(i); i = hay.indexOf(needle, i + 1); }
                return out;
            }
            function choose(hits, hay, needleLen, cb, ca) {
                if (hits.length === 1) return hits[0];
                var best = hits[0], bestScore = -1;
                for (var k = 0; k < hits.length; k++) {
                    var pos = hits[k], score = 0;
                    if (cb) {
                        var pre = hay.slice(Math.max(0, pos - cb.length), pos);
                        if (pre === cb) score += 2;
                        else if (pre && cb.slice(-pre.length) === pre) score += 1;
                    }
                    if (ca) {
                        var post = hay.slice(pos + needleLen, pos + needleLen + ca.length);
                        if (post === ca) score += 2;
                        else if (post && ca.slice(0, post.length) === post) score += 1;
                    }
                    if (score > bestScore) { bestScore = score; best = pos; }
                }
                return best;
            }
            var idx = -1;
            var exact = allIndexes(flat, quote);
            if (exact.length) {
                idx = choose(exact, flat, quote.length, contextBefore, contextAfter);
            } else {
                var lf = flat.toLowerCase();
                var ci = allIndexes(lf, quote.toLowerCase());
                if (ci.length) {
                    idx = choose(ci, lf, quote.length,
                        contextBefore ? contextBefore.toLowerCase() : contextBefore,
                        contextAfter ? contextAfter.toLowerCase() : contextAfter);
                }
            }
            if (idx < 0) return null;
            var endIdx = idx + quote.length;
            function locate(off) {
                for (var i = nodes.length - 1; i >= 0; i--) {
                    if (starts[i] <= off) return { node: nodes[i], offset: off - starts[i] };
                }
                return { node: nodes[0], offset: 0 };
            }
            var s = locate(idx), e = locate(endIdx);
            try {
                var r = document.createRange();
                r.setStart(s.node, Math.min(s.offset, s.node.length || 0));
                r.setEnd(e.node, Math.min(e.offset, e.node.length || 0));
                return r.collapsed ? null : r;
            } catch (err) { return null; }
        }

        // Feature #85 WI-2: paint a quote-anchored highlight in a stitched
        // section — routes through the SAME `applyHighlightRange` pipeline as
        // the path-based restore, so tap-to-edit + delete keep working.
        window.__vreader_createHighlightInSectionByQuote = function(spineIndex, id, quote, color, contextBefore, contextAfter) {
            var section = document.querySelector('[data-vreader-spine-index="' + spineIndex + '"]');
            if (!section) return;
            var contentRoot = section.querySelector('.vreader-chapter-content') || section;
            var range = findQuoteRangeInRoot(contentRoot, quote, contextBefore, contextAfter);
            if (!range) return;
            applyHighlightRange(id, range, color);
        };

        // Bug #212 / GH #828: deleting a CSS Highlight API entry does
        // not reliably invalidate an already-composited paged/columned
        // EPUB column, so a removed highlight's yellow paint lingered
        // on screen until the chapter reloaded. Force the text blocks
        // the highlight covered to re-rasterize by recreating their
        // render objects: `display:none` destroys the RenderObject,
        // the forced synchronous reflow commits that teardown, and
        // restoring `display` rebuilds it — a freshly-built
        // RenderObject always paints fresh, with no highlight
        // registered. The browser does not paint between the two
        // style writes within one JS turn, so the element never
        // visibly disappears; the user sees only highlight ->
        // no-highlight. A paint-only invalidation (opacity /
        // visibility toggle) is the class of invalidation WebKit
        // drops here, so the render-object rebuild is the reliable
        // nudge.

        // Inline-level tags a highlight boundary can land inside.
        // Climbing past them yields the containing text block, so a
        // multi-paragraph highlight's start/end blocks compare as
        // siblings. Keyed by lowercase `localName` — EPUB chapters
        // are application/xhtml+xml, where tag names are
        // case-sensitive and authored lowercase.
        var REPAINT_INLINE_TAGS = {
            span: 1, a: 1, em: 1, strong: 1, i: 1, b: 1, u: 1, s: 1,
            sup: 1, sub: 1, small: 1, mark: 1, code: 1, abbr: 1,
            cite: 1, q: 1, bdi: 1, bdo: 1, ruby: 1, font: 1, tt: 1,
            "var": 1, kbd: 1, samp: 1, dfn: 1
        };

        // Resolve a range boundary to a bounded repaint target — the
        // text block containing the boundary node, climbing past any
        // inline wrappers. Never <body> / <html> / the document root:
        // rebuilding those repaginates the whole chapter and resets
        // the paged-column scroll position (Codex audit, Bug #212).
        function repaintBlockFor(node) {
            var el = (node && node.nodeType === 1)
                ? node
                : (node && node.parentElement);
            while (el && el.parentElement
                   && el !== document.body
                   && el !== document.documentElement
                   && REPAINT_INLINE_TAGS[el.localName]) {
                el = el.parentElement;
            }
            if (!el || el === document.body
                || el === document.documentElement) {
                return null;
            }
            return el;
        }

        function repaintElement(el) {
            var prevDisplay = el.style.display;
            el.style.display = 'none';
            // Forced synchronous reflow: commits the display:none
            // teardown so the restore below is seen as a real change
            // rather than coalesced away to a no-op.
            void el.offsetHeight;
            el.style.display = prevDisplay;
        }

        function forceRangeRepaint(range) {
            if (!range) return;
            try {
                var startEl = repaintBlockFor(range.startContainer);
                var endEl = repaintBlockFor(range.endContainer);
                var targets = [];
                if (startEl) targets.push(startEl);
                if (endEl && endEl !== startEl) targets.push(endEl);
                // Multi-block highlight whose start and end blocks are
                // siblings: also repaint the blocks between them so no
                // middle paragraph keeps stale paint. Bounded so a
                // malformed range cannot walk the whole chapter.
                if (startEl && endEl && startEl !== endEl
                    && startEl.parentElement === endEl.parentElement) {
                    var guard = 0;
                    for (var n = startEl.nextElementSibling;
                         n && n !== endEl && guard < 64;
                         n = n.nextElementSibling, guard++) {
                        targets.push(n);
                    }
                }
                for (var i = 0; i < targets.length; i++) {
                    repaintElement(targets[i]);
                }
            } catch (e) {}
        }

        window.__vreader_removeHighlight = function(id) {
            // Bug #212 / GH #828: capture the range before the registry
            // entry is dropped — forceRangeRepaint needs it to find the
            // container element to re-rasterize.
            var range = window.__vreader_highlightRanges[id];
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
            // WI-4: drop the registry entry so a deleted highlight stops
            // being tap-targetable.
            delete window.__vreader_highlightRanges[id];
            // Bug #212 / GH #828: nudge WebKit to drop the now-stale
            // highlight paint from the composited column.
            forceRangeRepaint(range);
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
            // WI-4: drop ALL registry entries on chapter swap / book swap.
            window.__vreader_highlightRanges = {};
        };

        // Feature #53 WI-4: tap-on-highlight click listener.
        // Uses capture-phase + caretPositionFromPoint to identify the
        // tapped position, then walks the registry in reverse insert
        // order (most-recent paint wins on overlap). On hit, posts a
        // {id, rect} payload to Swift and stops propagation so the
        // outer chrome-toggle listener does NOT also fire. Footnote
        // links are checked first via `e.target.closest('a[href]')` —
        // tapping a highlighted link still navigates the anchor.
        document.addEventListener('click', function(e) {
            // Don't intercept link clicks — those go to the existing
            // footnote handler / default-anchor navigation.
            if (e.target.closest('a[href]')) return;
            var ids = Object.keys(window.__vreader_highlightRanges);
            if (ids.length === 0) return;
            // Locate caret at tap point. Use caretPositionFromPoint
            // (standard) with caretRangeFromPoint (WebKit legacy) as a
            // fallback.
            var hitNode = null;
            var hitOffset = 0;
            try {
                if (document.caretPositionFromPoint) {
                    var cp = document.caretPositionFromPoint(e.clientX, e.clientY);
                    if (cp) { hitNode = cp.offsetNode; hitOffset = cp.offset; }
                } else if (document.caretRangeFromPoint) {
                    var cr = document.caretRangeFromPoint(e.clientX, e.clientY);
                    if (cr) { hitNode = cr.startContainer; hitOffset = cr.startOffset; }
                }
            } catch (err) { hitNode = null; }
            // Build a degenerate range at the tap point so we can use
            // Range.compareBoundaryPoints for membership testing. Bug #287:
            // if the caret APIs fail or return no node — common in line gaps
            // and adjacent whitespace, exactly where a near-miss tap lands —
            // do NOT return; skip the exact loop and fall through to the
            // tolerance band below.
            var probe = null;
            if (hitNode) {
                try {
                    probe = document.createRange();
                    probe.setStart(hitNode, hitOffset);
                    probe.setEnd(hitNode, hitOffset);
                } catch (err) { probe = null; }
            }
            for (var i = ids.length - 1; probe && i >= 0; i--) {
                var id = ids[i];
                var range = window.__vreader_highlightRanges[id];
                if (!range) continue;
                try {
                    // probe ∈ [range.start, range.end] iff:
                    //   range.start <= probe.start  AND  range.end >= probe.start
                    // Bug #211: `compareBoundaryPoints` constant names read
                    // counter-intuitively. `START_TO_START` compares
                    // range.start vs probe.start; `START_TO_END` compares
                    // range.END vs probe.start — the comparison the end
                    // check needs. The pre-fix code used `END_TO_START`,
                    // which compares range.start vs probe.END, so
                    // `endVsProbe` was never >= 0 for an in-range tap and
                    // every tap-on-highlight missed.
                    var startVsProbe = range.compareBoundaryPoints(Range.START_TO_START, probe);
                    var endVsProbe = range.compareBoundaryPoints(Range.START_TO_END, probe);
                    if (startVsProbe <= 0 && endVsProbe >= 0) {
                        var rect;
                        try { rect = range.getBoundingClientRect(); } catch (err2) {}
                        var payload = { id: id };
                        if (rect) {
                            payload.rectX = rect.x;
                            payload.rectY = rect.y;
                            payload.rectWidth = rect.width;
                            payload.rectHeight = rect.height;
                        }
                        try {
                            window.webkit.messageHandlers.highlightTapHandler
                                .postMessage(payload);
                        } catch (err2) {}
                        // Stop the chrome-toggle handler from also firing.
                        e.stopImmediatePropagation();
                        e.preventDefault();
                        return;
                    }
                } catch (err) { /* skip stale Range entries */ }
            }
            // Bug #287 / GH #1268: exact caret membership above hits only the
            // ~17-22px glyph extent, below the 44px minimum touch target — a
            // near-miss tap turns the page instead of opening the highlight
            // popover. Fall back to a tolerance band: inflate each registered
            // range's bounding rect toward 44px (zero inflation for a range
            // already that large, so legit page-turn taps next to a tall
            // highlight are NOT captured) and test the raw click point against
            // the inflated rect, choosing the nearest center on overlap.
            var VREADER_HL_TAP_SLOP_PX = 44;
            function __vreader_slop(dim) {
                var deficit = VREADER_HL_TAP_SLOP_PX - dim;
                return deficit > 0 ? deficit / 2 : 0;
            }
            function __vreader_tapSlopHit(px, py) {
                var bestId = null;
                var bestDist = Infinity;
                for (var j = ids.length - 1; j >= 0; j--) {
                    var rid = ids[j];
                    var rrange = window.__vreader_highlightRanges[rid];
                    if (!rrange) continue;
                    // Per-fragment client rects (not the union bounding box):
                    // a multi-line highlight's ragged-edge whitespace gaps are
                    // NOT tappable — only the painted line fragments get a
                    // slop band. (Bug #287 M2.)
                    var rects;
                    try { rects = rrange.getClientRects(); } catch (e2) { continue; }
                    if (!rects) continue;
                    for (var k = 0; k < rects.length; k++) {
                        var rr = rects[k];
                        if (!rr || (rr.width <= 0 && rr.height <= 0)) continue;
                        var sx = __vreader_slop(rr.width);
                        var sy = __vreader_slop(rr.height);
                        if (px < rr.left - sx || px > rr.right + sx ||
                            py < rr.top - sy || py > rr.bottom + sy) continue;
                        var cx = (rr.left + rr.right) / 2;
                        var cy = (rr.top + rr.bottom) / 2;
                        var d = (px - cx) * (px - cx) + (py - cy) * (py - cy);
                        if (d < bestDist) { bestDist = d; bestId = rid; }
                    }
                }
                return bestId;
            }
            var slopId = __vreader_tapSlopHit(e.clientX, e.clientY);
            if (slopId) {
                var srange = window.__vreader_highlightRanges[slopId];
                var spayload = { id: slopId };
                try {
                    var srect = srange.getBoundingClientRect();
                    if (srect) {
                        spayload.rectX = srect.x;
                        spayload.rectY = srect.y;
                        spayload.rectWidth = srect.width;
                        spayload.rectHeight = srect.height;
                    }
                } catch (e3) {}
                try {
                    window.webkit.messageHandlers.highlightTapHandler
                        .postMessage(spayload);
                } catch (e3) {}
                // Absorb the tap so the chrome-toggle / page-turn listener
                // does not also fire on this near-miss.
                e.stopImmediatePropagation();
                e.preventDefault();
                return;
            }
        }, true);

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
