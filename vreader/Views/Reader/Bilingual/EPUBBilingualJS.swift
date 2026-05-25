// Purpose: Feature #56 WI-10 — JavaScript constants for the EPUB
// bilingual interlinear renderer. Three JS payloads:
//
//   1. `bilingualEnumerateJS()` — walks each translatable block,
//      stamps a stable `data-vreader-bid` attribute on it, and
//      posts `[{bid, text}]` back to Swift via the
//      `bilingualEnumerate` message handler so the host can
//      translate.
//   2. `bilingualInjectJS(translationsByBid:)` — finds each block
//      by its `data-vreader-bid`, and appends a styled, non-
//      selectable, XPath-excluded `<div class="vreader-bilingual"
//      data-vreader-decoration>` after it carrying the translation.
//   3. `bilingualClearJS()` — removes every `vreader-bilingual`
//      node so a re-enable / language change starts clean.
//
// Key decisions:
// - **Decoration attribute is keystone.** `data-vreader-decoration`
//   is the literal both the inject path emits AND the
//   `EPUBHighlightJS.getXPath` decoration-skip filters against
//   (the R-EPUB-CFI fix). Renaming this attribute would silently
//   regress persisted-highlight anchoring under bilingual on —
//   so the constant lives here, in the producer, and is referenced
//   by the highlight regression test by string literal.
// - **All translation text is escaped via `FoliateJSEscaper`.**
//   A translation containing `'`, `\n`, or U+2028 would otherwise
//   break the single-quoted JS literal and silently fail to inject
//   (best case) or expose a JS injection vector (worst case).
// - **Idempotent.** Enumerate stamps once: re-enumerate is a no-op
//   if the block already has a `data-vreader-bid`. Inject checks
//   for an existing decoration sibling before appending. Clear is
//   a `querySelectorAll(...).forEach` — an empty NodeList is a
//   no-op.
// - **No interlinear style here.** Visual styling (font size,
//   color, accent left border) lives in CSS injected via the
//   existing theme-CSS pipeline. The bilingual JS only emits the
//   structural markup; the design `.vreader-bilingual { ... }`
//   rule paints it.
//
// @coordinates-with: EPUBHighlightJS.swift (R-EPUB-CFI decoration-
//   skip), EPUBWebViewBridge.swift (pendingJS seam),
//   EPUBReaderContainerView.swift (the host wiring),
//   FoliateJSEscaper.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-10)

#if canImport(UIKit)
import Foundation

/// JavaScript source builders for the EPUB bilingual interlinear
/// renderer. All three payloads are pure — same input → same
/// output — and tested via the JS-source-string pins in
/// `EPUBBilingualJSTests`.
enum EPUBBilingualJS {

    /// The attribute every injected translation block carries.
    /// Pinned by name in `EPUBHighlightJS.getXPath` /
    /// `selectionTrackingJS` so the highlight pipeline skips
    /// decoration siblings. Renaming this string requires updating
    /// every producer + consumer site simultaneously.
    static let decorationAttribute = "data-vreader-decoration"

    /// The attribute the enumerate path stamps on each translatable
    /// block, matched by the inject path. Renaming this string
    /// breaks the enumerate→inject contract.
    static let blockIDAttribute = "data-vreader-bid"

    /// The class name every injected translation block carries.
    /// Pinned by name in CSS + the clear path.
    static let blockClassName = "vreader-bilingual"

    /// The WKScriptMessageHandler name the enumerate payload posts
    /// to. Wired up in `EPUBWebViewBridge.makeUIView`.
    static let enumerateMessageHandlerName = "bilingualEnumerate"

    // MARK: - enumerate

    /// JS that walks every translatable LEAF block (`p` / `li` /
    /// `blockquote` / `pre` / `dd` / `dt` that does NOT contain another
    /// block element), stamps a stable `data-vreader-bid` on it, and posts
    /// an ordered `[{bid, text}]` array back to Swift.
    ///
    /// Bug #266: only leaf blocks are enumerated — a `<blockquote><p>…` or
    /// `<li><p>…` would otherwise enumerate both container and child,
    /// double-counting against the plain-text paragraph segmentation and
    /// drifting the translation pairing.
    ///
    /// Stamping is idempotent — a block that already carries
    /// `data-vreader-bid` keeps the existing id (so re-enumerating
    /// after a translation cache hit reuses the same bid as the
    /// originally-stored translation).
    static func bilingualEnumerateJS() -> String {
        """
        (function() {
            // Tags we treat as translatable blocks. Inline content
            // (span, em, strong) is left to its parent block; lists
            // are walked one <li> at a time so each item carries its
            // own translation.
            //
            // Codex Gate-4 audit finding [5]: headings (h1..h6) are
            // intentionally EXCLUDED so chapter / section titles are
            // not interlinearly translated. Chapter titles are short,
            // often stylized (drop-cap follows them via feature #68),
            // and translating them mid-render produces a jarring
            // double-title effect; the design bundle's interlinear
            // mock shows source paragraphs only. Excluding them also
            // keeps the enumerate/segment counts aligned (headings
            // would inflate enumerate but not be matched by paragraph
            // segmentation downstream).
            var BLOCK_TAGS = {
                p: 1, li: 1, blockquote: 1, pre: 1, dd: 1, dt: 1
            };
            // Bug #266: the CSS selector for "any block tag", used to detect a
            // NON-leaf block (a block element that contains another block).
            var BLOCK_SELECTOR = Object.keys(BLOCK_TAGS).join(',');

            var seq = 0;
            function stamp(el) {
                var existing = el.getAttribute('\(blockIDAttribute)');
                if (existing) { return existing; }
                seq += 1;
                var bid = 'b' + seq;
                el.setAttribute('\(blockIDAttribute)', bid);
                return bid;
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
                    if (el.hasAttribute && el.hasAttribute('\(decorationAttribute)')) {
                        continue;
                    }
                    // Bug #266: enumerate LEAF blocks only. A block element
                    // that contains another block element (e.g.
                    // <blockquote><p>…</p></blockquote>, <li><p>…</p></li>)
                    // would otherwise enumerate BOTH the container and its
                    // child, double-counting against the plain-text paragraph
                    // segmentation and drifting every later translation pairing.
                    // Enumerate the inner leaf; skip the container (its text is
                    // covered by its block descendants).
                    if (el.querySelector && el.querySelector(BLOCK_SELECTOR)) {
                        continue;
                    }
                    var text = el.textContent || '';
                    text = text.replace(/\\s+/g, ' ').trim();
                    if (!text) continue;
                    var bid = stamp(el);
                    out.push({ bid: bid, text: text });
                }
            } catch (e) {}

            try {
                window.webkit.messageHandlers
                    .\(enumerateMessageHandlerName).postMessage(out);
            } catch (e) {}
            return out.length;
        })();
        """
    }

    // MARK: - inject

    /// JS that injects a translation `<div>` after each block
    /// matching the supplied `data-vreader-bid` → translation map.
    ///
    /// Idempotent — an existing decoration sibling is replaced in
    /// place rather than re-appended, so a re-injection (chapter
    /// re-render, language change refetch) does NOT stack
    /// duplicates.
    ///
    /// All translation text routes through
    /// `FoliateJSEscaper.escapeForJSString` so a `'` or newline in a
    /// cached AI response cannot break out of the JS literal or
    /// inject markup.
    static func bilingualInjectJS(translationsByBid: [String: String]) -> String {
        var entries: [String] = []
        // Stable order: sort keys so the emitted JS is deterministic
        // and tests can compare full strings without flakes from
        // dictionary iteration order. The runtime walk is
        // attribute-keyed so order does not affect correctness.
        for bid in translationsByBid.keys.sorted() {
            guard let translation = translationsByBid[bid] else { continue }
            let safeBid = FoliateJSEscaper.escapeForJSString(bid)
            let safeText = FoliateJSEscaper.escapeForJSString(translation)
            entries.append("    '\(safeBid)': '\(safeText)'")
        }
        let table = entries.isEmpty ? "" : entries.joined(separator: ",\n") + "\n"

        return """
        (function() {
            var translations = {
        \(table)};

            function findBlock(bid) {
                try {
                    return document.querySelector(
                        '[\(blockIDAttribute)="' + bid + '"]'
                    );
                } catch (e) { return null; }
            }

            function makeBlock(text) {
                var div = document.createElement('div');
                div.className = '\(blockClassName)';
                div.setAttribute('\(decorationAttribute)', '');
                // Apply via cssText so the literal CSS property name
                // (`user-select`) is emitted into the document, not
                // just its JS camelCase mirror. Belt-and-braces:
                // older WebKit honours `-webkit-user-select`, modern
                // WebKit honours `user-select`. The test pins both
                // forms exist in the JS source so a future regression
                // to a single form is caught here, not by missing
                // selection guards in production.
                div.style.cssText = 'user-select: none; -webkit-user-select: none;';
                div.textContent = text;
                return div;
            }

            for (var bid in translations) {
                if (!translations.hasOwnProperty(bid)) continue;
                var block = findBlock(bid);
                if (!block) continue;
                // Idempotency: if the next sibling is already our
                // decoration block, replace its text in place rather
                // than appending a second one.
                var existing = block.nextElementSibling;
                if (existing
                    && existing.hasAttribute
                    && existing.hasAttribute('\(decorationAttribute)')
                    && existing.classList
                    && existing.classList.contains('\(blockClassName)')) {
                    existing.textContent = translations[bid];
                    continue;
                }
                var node = makeBlock(translations[bid]);
                if (block.parentNode) {
                    block.parentNode.insertBefore(node, block.nextSibling);
                }
            }
        })();
        """
    }

    // MARK: - clear

    /// JS that removes every `vreader-bilingual` node from the
    /// document. Safe to run multiple times in a row — an empty
    /// `querySelectorAll` is a no-op.
    static func bilingualClearJS() -> String {
        """
        (function() {
            try {
                var nodes = document.querySelectorAll(
                    '.\(blockClassName)[\(decorationAttribute)]'
                );
                for (var i = 0; i < nodes.length; i++) {
                    var n = nodes[i];
                    if (n.parentNode) {
                        n.parentNode.removeChild(n);
                    }
                }
            } catch (e) {}
        })();
        """
    }
}
#endif
