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

    static func paginationCSS(viewportWidth: CGFloat, viewportHeight: CGFloat) -> String {
        let colWidth = Int(viewportWidth) - columnGap
        let h = Int(viewportHeight)
        return """
        html {
            overflow: hidden;
        }
        body {
            column-width: \(colWidth)px;
            column-gap: \(columnGap)px;
            column-fill: auto;
            height: \(h)px;
            overflow: hidden;
            margin: 0;
            -webkit-column-break-inside: avoid;
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
    static func navigateToPageJS(page: Int, viewportWidth: CGFloat) -> String {
        let safePage = max(0, page)
        let offset = safePage * Int(viewportWidth)
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

    // MARK: - JS: CSS Injection/Removal

    /// Generates JavaScript to inject or replace the pagination CSS style element.
    static func injectPaginationCSSJS(viewportWidth: CGFloat, viewportHeight: CGFloat) -> String {
        let css = paginationCSS(viewportWidth: viewportWidth, viewportHeight: viewportHeight)
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
