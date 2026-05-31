// Purpose: Pure-logic helpers for CSS column-based EPUB pagination in WKWebView.
// Generates pagination CSS, JS for page navigation, and page count computation.
//
// Key decisions:
// - Uses CSS multi-column layout (column-width, column-gap, overflow: hidden).
// - Navigation is done by setting scrollLeft on the document body.
// - Total pages computed from scrollWidth / viewportWidth (rounded up).
// - All methods are static for testability (no side effects).
// - Pixel values are integers to avoid sub-pixel rendering issues.
// - Zero/negative viewport dimensions produce safe fallback values.
//
// @coordinates-with: EPUBWebViewBridge.swift, EPUBReaderContainerView.swift

import Foundation

/// Pure-logic helpers for CSS column-based EPUB pagination.
enum EPUBPaginationHelper {

    // MARK: - CSS Generation

    /// Generates CSS for column-based pagination that constrains content
    /// to viewport-sized pages arranged horizontally.
    ///
    /// - Parameters:
    ///   - viewportWidth: The WKWebView viewport width in points.
    ///   - viewportHeight: The WKWebView viewport height in points.
    /// - Returns: A CSS string with column layout rules.
    /// Column gap between pages (prevents text clipping at edges).
    static let columnGap: Int = 40

    static func paginationCSS(
        viewportWidth: CGFloat, viewportHeight: CGFloat, axis: PageAxis = .horizontalLTR
    ) -> String {
        // Bug #171 fix: clamp the computed column-width to a positive
        // value. The pre-fix expression `Int(viewportWidth) - columnGap`
        // emits negative px values for very small viewports (e.g.
        // viewportWidth < 40 during Stage Manager resize storms). The
        // round-1 audit flagged this as a pre-existing low-severity
        // gap; tightening it here while we're in the file.
        let colWidth = max(Int(viewportWidth) - columnGap, 1)
        let h = max(Int(viewportHeight), 0)
        // Feature #75 WI-2: inject the axis direction/writing-mode only when
        // non-LTR, so the LTR output is byte-identical to pre-#75.
        let directionDecl = EPUBPagedAxis.directionCSS(axis: axis)
        let directionLine = directionDecl.isEmpty ? "" : "\n            \(directionDecl)"
        // Bug #171: `column-width` alone is a HINT (minimum desired
        // width). The browser will fit as many columns as the available
        // body width permits — which produced a two-column "newspaper"
        // layout on EPUBs whose stylesheets pushed the body width
        // beyond the viewport. Pin `column-count: 1` to force the
        // browser to use exactly one column. With both declarations
        // present, `column-count` is the hard cap and `column-width`
        // is the minimum (always satisfied). Pagination math via
        // scrollWidth / viewportWidth is unchanged because the single
        // column still overflows horizontally into virtual columns.
        //
        // Round-2 audit finding [1]: the WHOLE pagination parameter
        // set is reader-owned while paged mode is active, not just
        // column-count. A book's `column-width: 600px !important` or
        // `height: 100vh !important` could leave one visible column but
        // misalign `scrollWidth / viewportWidth` so `totalPagesJS` and
        // `navigateToPageJS` miscount. Mark every pagination directive
        // `!important` (column-count, column-width, column-gap,
        // column-fill, height, overflow). margin and break-inside
        // remain at normal specificity — they're rendering hints, not
        // paging invariants.
        return """
        html {
            overflow: hidden !important;
        }
        body {
            column-count: 1 !important;
            column-width: \(colWidth)px !important;
            column-gap: \(columnGap)px !important;
            column-fill: auto !important;
            height: \(h)px !important;
            overflow: hidden !important;
            margin: 0;
            -webkit-column-break-inside: avoid;\(directionLine)
        }
        img, svg, video, figure {
            break-inside: avoid;
            page-break-inside: avoid;
        }
        """
    }

    /// Wraps pagination CSS in a `<style>` tag with a stable ID for injection/removal.
    static func paginationStyleTag(viewportWidth: CGFloat, viewportHeight: CGFloat) -> String {
        let css = paginationCSS(viewportWidth: viewportWidth, viewportHeight: viewportHeight)
        return "<style id=\"vreader-pagination\">\(css)</style>"
    }

    // MARK: - JS: Page Navigation

    /// Generates JavaScript that scrolls horizontally to a specific page.
    /// Page index is clamped to >= 0.
    ///
    /// - Parameters:
    ///   - page: Zero-based page index. Negative values are treated as 0.
    ///   - viewportWidth: The viewport width used to compute scroll offset.
    /// - Returns: A JavaScript string that sets the horizontal scroll position.
    static func navigateToPageJS(
        page: Int, viewportWidth: CGFloat, axis: PageAxis = .horizontalLTR
    ) -> String {
        // Feature #75 WI-2: axis-aware page→scrollLeft offset. LTR is unchanged
        // (positive); RTL / vertical-rl negate (WebKit negative-scrollLeft).
        let offset = EPUBPagedAxis.scrollOffset(
            page: page, viewportWidth: Int(viewportWidth), axis: axis
        )
        return """
        (function() {
            document.documentElement.scrollLeft = \(offset);
            document.body.scrollLeft = \(offset);
        })();
        """
    }

    // MARK: - JS: Total Pages Query

    /// Generates JavaScript that returns the total number of pages.
    /// Computed as ceil(scrollWidth / viewportWidth), minimum 1.
    ///
    /// - Parameter viewportWidth: The viewport width for page size.
    /// - Returns: A JavaScript expression string that evaluates to the page count.
    static func totalPagesJS(viewportWidth: CGFloat) -> String {
        let w = Int(viewportWidth)
        return """
        (function() {
            var sw = Math.max(document.documentElement.scrollWidth || 0, document.body.scrollWidth || 0);
            var vw = \(w);
            if (vw <= 0) return 1;
            return Math.max(Math.ceil(sw / vw), 1);
        })();
        """
    }

    // MARK: - JS: Current Page Query

    /// Generates JavaScript that returns the current page index (0-based).
    /// Computed as round(scrollLeft / viewportWidth).
    ///
    /// - Parameter viewportWidth: The viewport width for page size.
    /// - Returns: A JavaScript expression string that evaluates to the current page index.
    static func currentPageJS(viewportWidth: CGFloat) -> String {
        let w = Int(viewportWidth)
        return """
        (function() {
            var sl = document.documentElement.scrollLeft || document.body.scrollLeft || 0;
            var vw = \(w);
            if (vw <= 0) return 0;
            return Math.round(sl / vw);
        })();
        """
    }

    // MARK: - JS: Paged Swipe Tracking

    /// JavaScript that detects a horizontal swipe in paged mode and posts the
    /// total `{dx, dy}` of the gesture to the `pagedSwipeHandler` message
    /// channel. Bug #281 / GH #1258: the custom EPUB host only had a `click`
    /// (side-tap) listener, so paged mode had no swipe-to-turn — unlike the
    /// AZW3/Foliate paged reader. The Swift coordinator parses the payload and
    /// routes it through `EPUBSwipeGestureClassifier` →
    /// `.readerNextPage` / `.readerPreviousPage` (the SAME notifications
    /// side-tap produces), so this adds no new chrome, only an input affordance.
    ///
    /// `dx` follows the classifier's convention: `start.x - end.x` (positive =
    /// finger swept right→left = advance forward). The payload is the GESTURE
    /// total, not per-move — the classifier applies the dominance + threshold
    /// guards, so the JS posts unconditionally on `touchend` (cheap; the Swift
    /// side ignores sub-threshold / vertical gestures). When a real horizontal
    /// swipe is detected the JS marks the gesture so the synthetic `click` that
    /// WebKit fires after a touch sequence can be swallowed by the tap handler
    /// (`window.__vreaderSwipeConsumedTap`) — otherwise a swipe would also
    /// trigger a side-tap page-turn (double-advance).
    ///
    /// The swipe-consume threshold (`\(Int(EPUBSwipeGestureClassifier.defaultThreshold))`px)
    /// and the horizontal-dominance test MUST match `EPUBSwipeGestureClassifier`
    /// exactly — Codex Gate-4 round-1 [M1]: a looser JS threshold would swallow
    /// the click for an 11-49px jitter that Swift does NOT turn on, making a
    /// genuine side-tap / chrome-tap feel dropped. The flag is cleared on
    /// `touchcancel` and auto-expires after a short window (round-1 [Low]) so a
    /// consumed swipe that produces no synthetic click can't strand the flag and
    /// swallow the NEXT genuine tap. The content is a fixed app-authored literal
    /// with no interpolation — no injection surface.
    static let pagedSwipeTrackingJS = """
    (function() {
        var startX = null, startY = null;
        var SWIPE_PX = \(Int(EPUBSwipeGestureClassifier.defaultThreshold));
        function clearConsumed() {
            window.__vreaderSwipeConsumedTap = false;
            window.__vreaderSwipeExpireTimer = null;
        }
        document.addEventListener('touchstart', function(e) {
            if (!e.touches || e.touches.length !== 1) { startX = null; return; }
            var t = e.touches[0];
            startX = t.clientX; startY = t.clientY;
        }, { passive: true });
        document.addEventListener('touchcancel', function() {
            startX = null; startY = null;
        }, { passive: true });
        document.addEventListener('touchend', function(e) {
            if (startX === null) return;
            var t = (e.changedTouches && e.changedTouches[0]) || null;
            if (!t) { startX = null; return; }
            var dx = startX - t.clientX;
            var dy = startY - t.clientY;
            startX = null; startY = null;
            if (!isFinite(dx) || !isFinite(dy)) return;
            // Mark the gesture as a consumed swipe ONLY when it matches what the
            // Swift classifier will turn on (same threshold + dominance), so the
            // click handler swallows the synthetic click for a real page-turn —
            // never for a sub-threshold jitter that produces no turn.
            if (Math.abs(dx) > SWIPE_PX && Math.abs(dx) > Math.abs(dy)) {
                window.__vreaderSwipeConsumedTap = true;
                // Self-expire so a swipe with no following synthetic click can't
                // strand the flag and swallow the next genuine tap. Codex Gate-4
                // round-2 [Low]: own the timer per swipe — cancel any prior
                // pending expiry first so a stale timeout from an earlier swipe
                // can't clear THIS swipe's flag before its synthetic click lands
                // (rapid-swipe double-advance / link-activation reopener).
                if (window.__vreaderSwipeExpireTimer) {
                    clearTimeout(window.__vreaderSwipeExpireTimer);
                }
                window.__vreaderSwipeExpireTimer = setTimeout(clearConsumed, 700);
            }
            window.webkit.messageHandlers.pagedSwipeHandler.postMessage({ dx: dx, dy: dy });
        }, { passive: true });
    })();
    """

    // MARK: - JS: CSS Injection/Removal

    /// Generates JavaScript to inject or replace the pagination CSS style element.
    static func injectPaginationCSSJS(
        viewportWidth: CGFloat, viewportHeight: CGFloat, axis: PageAxis = .horizontalLTR
    ) -> String {
        let css = paginationCSS(
            viewportWidth: viewportWidth, viewportHeight: viewportHeight, axis: axis
        )
        // Bug #136: delegate to the shared escape helper for parity with
        // FoliateJSEscaper-routed sites and the bug #135 fix.
        let escaped = FoliateJSEscaper.escapeForJSString(css)
        return """
        (function() {
            var existing = document.getElementById('vreader-pagination');
            if (existing) existing.remove();
            var style = document.createElement('style');
            style.id = 'vreader-pagination';
            style.textContent = '\(escaped)';
            document.head.appendChild(style);
        })();
        """
    }

    /// JavaScript to remove the pagination style element (when switching to scroll layout).
    static let removePaginationCSSJS = """
    (function() {
        var existing = document.getElementById('vreader-pagination');
        if (existing) existing.remove();
    })();
    """

    // MARK: - Pure Calculations

    /// Computes the total number of pages from document scroll width and viewport width.
    /// Returns at least 1 page. Returns 1 for zero or negative viewport width.
    ///
    /// - Parameters:
    ///   - scrollWidth: The total horizontal scroll width of the document.
    ///   - viewportWidth: The viewport width (one page width).
    /// - Returns: The total page count (>= 1).
    static func totalPages(scrollWidth: CGFloat, viewportWidth: CGFloat) -> Int {
        guard viewportWidth > 0 else { return 1 }
        guard scrollWidth > 0 else { return 1 }
        let pages = Int(ceil(scrollWidth / viewportWidth))
        return max(pages, 1)
    }

    /// Computes the current page index from the horizontal scroll offset.
    /// Returns 0 for zero or negative viewport width.
    ///
    /// - Parameters:
    ///   - scrollLeft: The current horizontal scroll offset.
    ///   - viewportWidth: The viewport width (one page width).
    /// - Returns: The zero-based page index.
    static func pageFromScrollOffset(scrollLeft: CGFloat, viewportWidth: CGFloat) -> Int {
        guard viewportWidth > 0 else { return 0 }
        return Int(round(scrollLeft / viewportWidth))
    }
}
