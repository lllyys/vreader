// Purpose: Static JavaScript generators for EPUBWebViewBridge — scroll-to-fraction,
// theme CSS injection/removal, view teardown, and event tracking scripts.
//
// @coordinates-with EPUBWebViewBridge.swift, EPUBWebViewBridgeCoordinator.swift

#if canImport(UIKit)
import UIKit
import WebKit

extension EPUBWebViewBridge {

    // MARK: - Scroll View Background

    /// Bug #167: Resolves the WKWebView scroll-view background color so the
    /// rubber-band overscroll area matches the current reader theme instead
    /// of falling through to the host UIView (white by default).
    /// Returns the input color if non-nil, otherwise `.clear` to preserve
    /// the prior behaviour for any caller that hasn't yet been threaded
    /// through with a themed color.
    static func scrollViewBackgroundColor(for color: UIColor?) -> UIColor {
        color ?? .clear
    }

    /// Bug #167: Single seam through which the bridge writes the scroll
    /// view's `backgroundColor`. Exists so tests can exercise the actual
    /// `UIScrollView.backgroundColor` assignment — not just the resolver
    /// — and catch a wiring regression if anyone deletes the call site.
    static func applyScrollViewBackground(to scrollView: UIScrollView, color: UIColor?) {
        scrollView.backgroundColor = scrollViewBackgroundColor(for: color)
    }

    // MARK: - Safe Area Top Inset (bug #163)

    /// Bug #163: WKWebView's scroll view has `contentInsetAdjustmentBehavior =
    /// .never` (set in `makeUIView` so paginated layout's `scrollLeft` math
    /// works correctly without the OS pre-shifting `contentOffset`). The
    /// side-effect was that EPUB content started at y=0, clipped behind the
    /// Dynamic Island on chapter start. This seam writes the safe-area top
    /// inset directly so the content begins at the right place. Negative
    /// inputs clamp to 0 — UIScrollView would happily accept a negative top
    /// inset (pushing content UP) but that's exactly the regression we're
    /// fixing, so guard against it here.
    static func applySafeAreaTopInset(to scrollView: UIScrollView, top: CGFloat) {
        let clamped = max(top, 0)
        scrollView.contentInset.top = clamped
        // The scroll indicator also needs to start below the safe area;
        // otherwise the scrollbar is clipped behind the Dynamic Island
        // identical to how the content was. `verticalScrollIndicatorInsets`
        // is the modern API; on iOS 13+ writes here also reflect into
        // legacy `scrollIndicatorInsets`.
        scrollView.verticalScrollIndicatorInsets.top = clamped
    }

    // MARK: - Initial Content Offset (bug #163 reopen)

    /// Bug #163 (reopen): `applySafeAreaTopInset` sets `contentInset.top` once,
    /// but WKWebView resets `contentOffset` to `.zero` after every `loadFileURL`.
    /// With contentInset.top = safeAreaTopInset and contentOffset.y = 0, content
    /// y=0 is positioned at screen y=0 — behind the Dynamic Island.
    /// Calling this seam after page load resets contentOffset.y to -topInset so
    /// document y=0 appears at screen y=topInset, just below the DI.
    /// Negative topInset clamps to 0 (no overshoot on zero-inset devices).
    static func applyInitialContentOffset(to scrollView: UIScrollView, topInset: CGFloat) {
        let clamped = max(topInset, 0)
        scrollView.contentOffset = CGPoint(x: 0, y: -clamped)
    }

    // MARK: - Scroll to Fraction

    /// Generates JavaScript that scrolls the page to a vertical fraction (0.0-1.0).
    /// Clamping is applied: negative and NaN values map to 0.0, values > 1.0 map to 1.0.
    static func scrollToFractionJS(_ fraction: Double) -> String {
        let clamped: Double
        if fraction.isNaN || fraction < 0 {
            clamped = 0.0
        } else if fraction > 1.0 {
            clamped = 1.0
        } else {
            clamped = fraction
        }
        return """
        (function() {
            var scrollHeight = Math.max(
                document.documentElement.scrollHeight || 0,
                document.body.scrollHeight || 0
            );
            var clientHeight = document.documentElement.clientHeight || window.innerHeight || 0;
            var maxScroll = scrollHeight - clientHeight;
            if (maxScroll > 0) {
                window.scrollTo(0, maxScroll * \(clamped));
            }
        })();
        """
    }

    /// JavaScript to inject or replace the vreader-theme style element.
    /// `styleTag` is a full `<style id="vreader-theme">…</style>` tag.
    /// We extract the inner CSS and inject via createElement + textContent
    /// to avoid innerHTML-based DOM injection.
    static func injectThemeCSSJS(_ styleTag: String) -> String {
        // Extract CSS content from between <style ...> and </style> tags
        var cssContent = styleTag
        if let startRange = cssContent.range(of: ">", options: .literal),
           let endRange = cssContent.range(of: "</style>", options: .backwards) {
            cssContent = String(cssContent[startRange.upperBound..<endRange.lowerBound])
        }
        // Bug #136: delegate to the shared escape helper. Adds coverage
        // for `\r`, `\t`, U+2028, U+2029 — strict superset of the prior
        // inline escape. CSS inputs here are app-generated today; this
        // is the consolidation half of the bug #135 / #136 cluster.
        let escaped = FoliateJSEscaper.escapeForJSString(cssContent)
        return """
        (function() {
            var existing = document.getElementById('vreader-theme');
            if (existing) existing.remove();
            var style = document.createElement('style');
            style.id = 'vreader-theme';
            style.textContent = '\(escaped)';
            document.head.appendChild(style);
        })();
        """
    }

    /// JavaScript to remove the vreader-theme style element (when theme is cleared).
    static let removeThemeCSSJS = """
    (function() {
        var existing = document.getElementById('vreader-theme');
        if (existing) existing.remove();
    })();
    """

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: "progressHandler"
        )
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: "contentTapHandler"
        )
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: "selectionChanged"
        )
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: "footnoteHandler"
        )
        // Feature #53 WI-4: matching teardown for the highlight-tap handler
        // added at makeUIView. Skipping this leaks the WKScriptMessageHandler
        // proxy retainment per Bug #109's investigation.
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: "highlightTapHandler"
        )
    }

    // MARK: - JavaScript

    /// Content tap tracking — sends message on non-link clicks for toolbar toggle.
    static let contentTapTrackingJS = """
    (function() {
        document.addEventListener('click', function(e) {
            if (e.target.closest('a')) return;
            window.webkit.messageHandlers.contentTapHandler.postMessage('tap');
        }, false);
    })();
    """

    /// CSS preprocessing — fixes common EPUB rendering issues (inspired by foliate-js).
    /// Runs at document end to rewrite problematic CSS rules:
    /// 1. Replaces -epub-* prefixed properties with standard equivalents
    /// 2. Converts vw/vh units to pixel values (break in CSS columns)
    /// 3. Replaces page-break-* with break-* (CSS3 fragmentation)
    /// 4. Constrains image sizes to prevent overflow
    static let cssPreprocessJS = """
    (function() {
        var sheets = document.styleSheets;
        for (var i = 0; i < sheets.length; i++) {
            try {
                var rules = sheets[i].cssRules;
                if (!rules) continue;
                for (var j = 0; j < rules.length; j++) {
                    var rule = rules[j];
                    if (!rule.style) continue;
                    var style = rule.style;
                    // Replace -epub-* properties
                    for (var k = style.length - 1; k >= 0; k--) {
                        var prop = style[k];
                        if (prop.startsWith('-epub-')) {
                            var val = style.getPropertyValue(prop);
                            var prio = style.getPropertyPriority(prop);
                            style.removeProperty(prop);
                            style.setProperty(prop.replace('-epub-', ''), val, prio);
                        }
                    }
                    // Replace page-break-* with break-*
                    var pageBreakProps = ['page-break-before', 'page-break-after', 'page-break-inside'];
                    var breakProps = ['break-before', 'break-after', 'break-inside'];
                    for (var k = 0; k < pageBreakProps.length; k++) {
                        var val = style.getPropertyValue(pageBreakProps[k]);
                        if (val) {
                            style.setProperty(breakProps[k], val === 'always' ? 'page' : val);
                        }
                    }
                }
            } catch(e) { /* cross-origin stylesheet, skip */ }
        }
    })();
    """

    /// Scroll progress tracking with 100ms throttle to reduce callback churn.
    static let progressTrackingJS = """
    (function() {
        var lastReport = 0;
        function reportProgress() {
            var now = Date.now();
            if (now - lastReport < 100) return;
            lastReport = now;
            var scrollTop = document.documentElement.scrollTop || document.body.scrollTop || 0;
            var scrollHeight = Math.max(
                document.documentElement.scrollHeight || 0,
                document.body.scrollHeight || 0
            );
            var clientHeight = document.documentElement.clientHeight || window.innerHeight || 0;
            var maxScroll = scrollHeight - clientHeight;
            var progress = maxScroll > 0 ? Math.min(Math.max(scrollTop / maxScroll, 0), 1) : 0;
            window.webkit.messageHandlers.progressHandler.postMessage(progress);
        }
        window.addEventListener('scroll', reportProgress, { passive: true });
        // Report initial progress after layout
        setTimeout(reportProgress, 100);
    })();
    """
}
#endif
