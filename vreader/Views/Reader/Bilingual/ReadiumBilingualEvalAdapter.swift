// Purpose: Feature #42 WI-11a (SPIKE) — JS-string builders for driving the
// bilingual interlinear enumerate→inject→clear loop on the Readium EPUB
// navigator via its public, one-way `evaluateJavaScript(_:) async ->
// Result<Any,Error>` eval channel.
//
// Why a separate adapter from EPUBBilingualJS:
// - The legacy `EPUBWebViewBridge` engine owns its WKWebView's content
//   controller, so its `EPUBBilingualJS.bilingualEnumerateJS()` POSTS the
//   `[{bid,text}]` payload via `webkit.messageHandlers.bilingualEnumerate`
//   (a `WKScriptMessageHandler`).
// - The Readium 3.9 `EPUBNavigatorViewController` owns its OWN (possibly
//   several) internal spine webviews and does NOT expose that handler to
//   app code. It instead exposes a clean public surface (confirmed in WI-4):
//
//       public func evaluateJavaScript(_ script: String) async -> Result<Any, Error>
//
//   which runs JS on the currently-visible spine HTML and RETURNS the
//   evaluation value. So the enumerate path here RETURNS the same
//   `[{bid,text}]` array as the IIFE's last expression — Readium yields it
//   as `.success(value)`, which the production WI-11b orchestrator will
//   decode with the existing `EPUBBilingualPipeline.parseEnumerateMessage`
//   (which already accepts the bare `[{bid,text}]` array shape).
//
// The inject + clear builders need NO change: the existing
// `EPUBBilingualJS.bilingualInjectJS` / `bilingualClearJS` bodies are
// self-contained IIFEs against `document` that never touch the message
// channel, so they run as-is through `evaluateJavaScript`. This adapter
// re-exports them so WI-11b feeds ONE coherent set of builders to the
// navigator and the call sites don't reach across engines.
//
// How WI-11b will call these (NOT built in this SPIKE):
//   - On the Readium navigator's `locationDidChange` delegate (the
//     relocate-equivalent that fires once a spine is rendered), the
//     orchestrator awaits `navigator.evaluateJavaScript(enumerateJS())`,
//     parses the returned array, fetches translations, then awaits
//     `navigator.evaluateJavaScript(injectJS(pairs:))`. A disable / language
//     change awaits `navigator.evaluateJavaScript(clearJS())`. That
//     per-section drive + the BilingualReadingViewModel / setup-sheet / toggle
//     wiring is WI-11b — this file is only the pure JS-string builders.
//
// Key decisions:
// - **Return-value enumerate, not postMessage.** Only the OUTPUT mechanism
//   differs from `EPUBBilingualJS.globalEnumerateJS()`: the DOM walk, the
//   leaf-block filter (Bug #266), the idempotent `data-vreader-bid` stamping,
//   and the decoration-sibling skip are byte-for-byte the same logic. The
//   trailing `webkit.messageHandlers.<...>.postMessage(out)` is dropped and
//   the IIFE simply `return out;`s the array.
// - **All translation text escaped via `FoliateJSEscaper`** — the inject
//   builder delegates to `EPUBBilingualJS.bilingualInjectJS`, which already
//   routes every value through `FoliateJSEscaper.escapeForJSString`, so a `'`
//   / newline / U+2028 in a cached translation cannot break the single-quoted
//   JS literal or open an injection vector.
// - **Decoration / bid / class literals come from `EPUBBilingualJS`** — the
//   same constants the legacy engine + the R-EPUB-CFI highlight decoration
//   skip rely on, so the Readium path shares one source of truth.
//
// @coordinates-with: EPUBBilingualJS.swift, EPUBBilingualPipeline.swift,
//   ReadiumReaderCoordinator.swift (the navigator + eval seam owner),
//   FoliateJSEscaper.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-11)

#if canImport(UIKit)
import Foundation

/// Pure JS-string builders for the Readium bilingual eval-channel loop.
/// Static-only, no instance state. The builders are pure (same input → same
/// output) and therefore unisolated — they can be called from any context,
/// including the `@MainActor` navigator-owning coordinator that WI-11b will
/// feed them to.
enum ReadiumBilingualEvalAdapter {

    // MARK: - enumerate (return-value channel)

    /// JS that walks every translatable LEAF block, stamps an idempotent
    /// `data-vreader-bid` on it, and RETURNS the ordered `[{bid, text}]` array
    /// as the IIFE's value — so `navigator.evaluateJavaScript(...)` yields it
    /// as `.success([...])`. Mirrors `EPUBBilingualJS.globalEnumerateJS()`'s
    /// DOM walk + Bug #266 leaf filter + idempotent stamping + decoration-skip
    /// EXACTLY; only the output mechanism differs (return vs postMessage).
    static func enumerateJS() -> String {
        let bid = EPUBBilingualJS.blockIDAttribute
        let deco = EPUBBilingualJS.decorationAttribute
        return """
        (function() {
            // Tags we treat as translatable blocks. Inline content
            // (span, em, strong) is left to its parent block; lists
            // are walked one <li> at a time so each item carries its
            // own translation. Headings (h1..h6) are intentionally
            // EXCLUDED (same as the legacy EPUB enumerate) so chapter
            // titles are not interlinearly translated.
            var BLOCK_TAGS = {
                p: 1, li: 1, blockquote: 1, pre: 1, dd: 1, dt: 1
            };
            // Bug #266: the CSS selector for "any block tag", used to detect a
            // NON-leaf block (a block element that contains another block).
            var BLOCK_SELECTOR = Object.keys(BLOCK_TAGS).join(',');

            var seq = 0;
            function stamp(el) {
                var existing = el.getAttribute('\(bid)');
                if (existing) { return existing; }
                seq += 1;
                var b = 'b' + seq;
                el.setAttribute('\(bid)', b);
                return b;
            }

            var out = [];
            try {
                var all = document.body
                    ? document.body.getElementsByTagName('*')
                    : document.getElementsByTagName('*');
                for (var i = 0; i < all.length; i++) {
                    var el = all[i];
                    var tag = (el.localName || '').toLowerCase();
                    if (!BLOCK_TAGS[tag]) continue;
                    // Skip a decoration sibling we may already have
                    // injected — a re-enumerate after inject must
                    // never re-stamp translation nodes.
                    if (el.hasAttribute && el.hasAttribute('\(deco)')) {
                        continue;
                    }
                    // Bug #266: enumerate LEAF blocks only. A block element
                    // that contains another block element would otherwise
                    // enumerate BOTH the container and its child, drifting the
                    // translation pairing. Enumerate the inner leaf; skip the
                    // container.
                    if (el.querySelector && el.querySelector(BLOCK_SELECTOR)) {
                        continue;
                    }
                    var text = el.textContent || '';
                    text = text.replace(/\\s+/g, ' ').trim();
                    if (!text) continue;
                    var bidValue = stamp(el);
                    out.push({ bid: bidValue, text: text });
                }
            } catch (e) {}

            // Readium eval-channel: RETURN the array (one-way eval). Unlike the
            // legacy EPUB engine, there is no script-message-handler post — the
            // navigator's evaluateJavaScript yields this as .success(out).
            return out;
        })();
        """
    }

    // MARK: - inject (engine-agnostic body, re-exported)

    /// JS that injects a translation `<div>` after each block matching the
    /// supplied `data-vreader-bid` → translation map. Delegates to the
    /// engine-agnostic `EPUBBilingualJS.bilingualInjectJS` — that body is a
    /// self-contained IIFE against `document` (no message channel), so it runs
    /// as-is via `navigator.evaluateJavaScript`. Every value is escaped through
    /// `FoliateJSEscaper.escapeForJSString` by that builder.
    static func injectJS(pairs: [String: String]) -> String {
        EPUBBilingualJS.bilingualInjectJS(translationsByBid: pairs)
    }

    /// Bug #304: JS that ensures the interlinear `.vreader-bilingual` `<style>`
    /// is present on the Readium spine (the Readium engine doesn't thread
    /// `epubOverrideCSS`, so the injected blocks otherwise render as plain text).
    static func styleJS(css: String) -> String {
        EPUBBilingualJS.bilingualStyleJS(css: css)
    }

    // MARK: - clear (engine-agnostic body, re-exported)

    /// JS that removes every `vreader-bilingual` decoration node from the
    /// document. Delegates to `EPUBBilingualJS.bilingualClearJS` — a
    /// `document.querySelectorAll(...).forEach`-style removal that runs as-is
    /// through `navigator.evaluateJavaScript`.
    static func clearJS() -> String {
        EPUBBilingualJS.bilingualClearJS()
    }
}
#endif
