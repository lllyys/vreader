// Purpose: Pure JS-string generators for the EPUB continuous-scroll
// multi-chapter WKWebView document (feature #71, WI-3). Each function returns
// a self-invoking JS snippet to run via `evaluateJavaScript`; none touch a
// WKWebView, so the generators are unit-tested for injection-safety + DOM
// correctness without WebKit (mirrors `EPUBWebViewBridgeJS` / `EPUBBilingualJS`).
//
// The continuous-scroll document is a single scrollable column
// (`#vreader-scroll-root`) into which the coordinator (WI-4) appends/prepends
// rewritten chapter bodies (WI-2 `EPUBChapterBody`) as
// `<section data-vreader-spine-index="N" data-vreader-href="…">` blocks
// separated by chapter dividers, and evicts far ones to bound memory.
//
// Key decisions:
// - **Single-quoted JS literals + `FoliateJSEscaper.escapeForJSString`** for
//   every interpolated value (chapter body, divider title, search quote). A
//   double quote sits inertly inside a `'…'` literal, so HTML attributes + CSS
//   selectors use double quotes and only `'`/`\`/newlines/U+2028/U+2029 need
//   escaping. The snippets run via `evaluateJavaScript`, NOT inside an HTML
//   `<script>`, so `</script>` / backtick / `${` are inert too.
// - **Divider title is HTML-escaped first** (it lands in element text), then
//   the whole section string is JS-escaped — defense in depth against a TOC
//   title containing markup.
// - **Section-scoped ops** (`removeChapterSectionJS`, `scrollToSpineFractionJS`,
//   `findInSectionJS`) target `[data-vreader-spine-index="N"]`, never the whole
//   document, so a quote/needle that also appears in another loaded chapter
//   can't cross-fire (plan round-1 [M1]).
// - `restoreHighlightsInSectionJS` is deferred to WI-6 (container integration),
//   where the per-section highlight-restore is wired + tested end-to-end; its
//   shape depends on that integration, so it is not shipped untested here.
//
// @coordinates-with: EPUBChapterBodyRewriter.swift (EPUBChapterBody),
//   EPUBContinuousScrollCoordinator.swift (WI-4 consumer), FoliateJSEscaper.swift,
//   dev-docs/plans/20260525-feature-71-epub-continuous-scroll.md (WI-3)

import Foundation

enum EPUBContinuousScrollJS {

    /// The id of the single scrollable column the chapters are stitched into.
    static let scrollRootID = "vreader-scroll-root"

    // MARK: - bootstrap

    /// The bootstrap HTML document loaded once into the WKWebView: an empty
    /// `#vreader-scroll-root` overflow column plus the chapter-divider styling
    /// (per design §2.3 `ChapterDivider`) and the caller-supplied theme CSS.
    static func bootstrapDocumentHTML(themeCSS: String) -> String {
        """
        <!DOCTYPE html>
        <html><head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>
        html, body { margin: 0; padding: 0; }
        #\(scrollRootID) { overflow-y: auto; -webkit-overflow-scrolling: touch; height: 100vh; }
        .vreader-chapter-divider { display: flex; align-items: center; gap: 14px; margin: 36px 0 28px; }
        .vreader-chapter-divider .vreader-divider-rule { flex: 1; height: 0.5px; background: currentColor; opacity: 0.3; }
        .vreader-chapter-divider .vreader-divider-label {
            font: 600 11px/1 "Source Serif 4", Georgia, serif;
            letter-spacing: 2.5px; text-transform: uppercase; white-space: nowrap; opacity: 0.6;
        }
        \(themeCSS)
        </style>
        </head>
        <body><div id="\(scrollRootID)"></div></body></html>
        """
    }

    // MARK: - append / prepend

    /// JS that appends `body`'s rewritten chapter section to the end of the
    /// scroll column (forward scroll into the next chapter).
    static func appendChapterSectionJS(_ body: EPUBChapterBody, dividerTitle: String?) -> String {
        let escaped = FoliateJSEscaper.escapeForJSString(sectionHTML(body, dividerTitle: dividerTitle))
        return """
        (function() {
            var root = document.getElementById('\(scrollRootID)');
            if (!root) { return; }
            root.insertAdjacentHTML('beforeend', '\(escaped)');
        })();
        """
    }

    /// JS that prepends `body`'s section to the START of the column (reverse
    /// scroll into the previous chapter), compensating the scroll offset in one
    /// transaction so the viewport does NOT jump: measure `scrollHeight` before
    /// the insert, then add the height delta back to `scrollTop` after.
    static func prependChapterSectionJS(_ body: EPUBChapterBody, dividerTitle: String?) -> String {
        let escaped = FoliateJSEscaper.escapeForJSString(sectionHTML(body, dividerTitle: dividerTitle))
        return """
        (function() {
            var root = document.getElementById('\(scrollRootID)');
            if (!root) { return; }
            var before = root.scrollHeight;
            root.insertAdjacentHTML('afterbegin', '\(escaped)');
            var after = root.scrollHeight;
            root.scrollTop += (after - before);
        })();
        """
    }

    // MARK: - evict

    /// JS that removes the materialized section for `spineIndex` (far-end
    /// eviction to bound memory). No-op if the section isn't present.
    ///
    /// Scroll compensation (Codex Gate-4): `evictFarFromAnchor` can trim the
    /// TOP end (the `lo` side, when the reader has scrolled down). Removing a
    /// section ABOVE the viewport collapses content upward, so — mirroring the
    /// prepend anchor — when the removed section sits above `scrollTop` we
    /// subtract its height delta from `scrollTop` so the viewport stays put.
    /// Below-viewport removals need no adjustment.
    static func removeChapterSectionJS(spineIndex: Int) -> String {
        """
        (function() {
            var root = document.getElementById('\(scrollRootID)');
            var el = document.querySelector('[data-vreader-spine-index="\(spineIndex)"]');
            if (!root || !el) { return; }
            var wasAbove = el.offsetTop < root.scrollTop;
            var before = root.scrollHeight;
            el.remove();
            if (wasAbove) {
                root.scrollTop -= (before - root.scrollHeight);
            }
        })();
        """
    }

    // MARK: - scroll observer

    /// The section-aware scroll observer user script. Replaces the single-`Double`
    /// `progressTrackingJS` in continuous mode: on a throttled scroll it reports
    /// `{ visibleSpineIndex, intraFraction, nearTopBoundary, nearBottomBoundary }`
    /// — the topmost section in the viewport, how far through it the viewport is,
    /// and whether the user is within the prefetch threshold of either end.
    static let continuousScrollObserverJS = """
    (function() {
        var root = document.getElementById('\(scrollRootID)');
        if (!root || root.__vreaderScrollObserver) { return; }
        root.__vreaderScrollObserver = true;
        var PREFETCH_PX = 800;
        var ticking = false;
        function report() {
            ticking = false;
            var sections = root.querySelectorAll('[data-vreader-spine-index]');
            if (!sections.length) { return; }
            var top = root.scrollTop;
            var visibleSpineIndex = parseInt(sections[0].getAttribute('data-vreader-spine-index'), 10);
            var intraFraction = 0;
            for (var i = 0; i < sections.length; i++) {
                var s = sections[i];
                if (s.offsetTop <= top) {
                    visibleSpineIndex = parseInt(s.getAttribute('data-vreader-spine-index'), 10);
                    var h = s.offsetHeight || 1;
                    intraFraction = Math.max(0, Math.min(1, (top - s.offsetTop) / h));
                }
            }
            var nearTopBoundary = top <= PREFETCH_PX;
            var nearBottomBoundary = (root.scrollHeight - (top + root.clientHeight)) <= PREFETCH_PX;
            try {
                window.webkit.messageHandlers.continuousScrollHandler.postMessage({
                    visibleSpineIndex: visibleSpineIndex,
                    intraFraction: intraFraction,
                    nearTopBoundary: nearTopBoundary,
                    nearBottomBoundary: nearBottomBoundary
                });
            } catch (e) {}
        }
        root.addEventListener('scroll', function() {
            if (!ticking) { ticking = true; requestAnimationFrame(report); }
        }, { passive: true });
        report();
    })();
    """

    // MARK: - scroll-to-section

    /// JS that scrolls the column to `fraction` (clamped to 0...1; non-finite →
    /// 0) through the section for `spineIndex` — used to restore a saved
    /// position or land a TOC/search navigation inside the stitched document.
    static func scrollToSpineFractionJS(spineIndex: Int, fraction: Double) -> String {
        let clamped = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        return """
        (function() {
            var root = document.getElementById('\(scrollRootID)');
            var el = document.querySelector('[data-vreader-spine-index="\(spineIndex)"]');
            if (!root || !el) { return; }
            root.scrollTop = el.offsetTop + (el.offsetHeight * \(clamped));
        })();
        """
    }

    // MARK: - find-in-section

    /// JS that searches for `quote` ONLY within the section subtree for
    /// `spineIndex` (not the whole document), so the same quote in another
    /// loaded chapter can't be matched first (plan round-1 [M1]). Reports
    /// whether the section was found + the match offset to the search handler.
    static func findInSectionJS(spineIndex: Int, quote: String) -> String {
        let needle = FoliateJSEscaper.escapeForJSString(quote)
        return """
        (function() {
            var section = document.querySelector('[data-vreader-spine-index="\(spineIndex)"]');
            if (!section) {
                try { window.webkit.messageHandlers.findInSectionHandler.postMessage({ found: false }); } catch (e) {}
                return;
            }
            var needle = '\(needle)';
            var idx = (section.textContent || '').indexOf(needle);
            try {
                window.webkit.messageHandlers.findInSectionHandler.postMessage({
                    found: idx >= 0, spineIndex: \(spineIndex), offset: idx
                });
            } catch (e) {}
        })();
        """
    }

    // MARK: - section markup

    /// Builds one chapter `<section>` (divider + scoped style + rewritten body).
    /// Attributes use double quotes (inert in the single-quoted JS literal the
    /// caller wraps this in); the divider title + href are HTML-escaped.
    private static func sectionHTML(_ body: EPUBChapterBody, dividerTitle: String?) -> String {
        var divider = ""
        if let title = dividerTitle {
            divider = """
            <div class="vreader-chapter-divider"><div class="vreader-divider-rule"></div>\
            <div class="vreader-divider-label">\(htmlEscape(title))</div>\
            <div class="vreader-divider-rule"></div></div>
            """
        }
        return """
        <section data-vreader-spine-index="\(body.spineIndex)" data-vreader-href="\(htmlEscape(body.href))">\
        \(divider)\(body.scopedStyleHTML)\(body.bodyHTML)</section>
        """
    }

    /// Minimal HTML text/attribute escape (`&`, `<`, `>`, `"`) so a chapter
    /// title or href can't inject markup into the section before it is itself
    /// JS-escaped. `&` first to avoid double-escaping.
    private static func htmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
