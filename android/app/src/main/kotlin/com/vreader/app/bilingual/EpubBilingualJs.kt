// Purpose: feature #131 WI-7b — the EPUB bilingual render surface: a PURE Kotlin
// builder producing the JS strings the Readium navigator's `evaluateJavascript`
// runs to enumerate leaf blocks, inject interlinear translation nodes, clear them,
// and probe the current decoration count. No Compose, no navigator reference — so it
// is JVM-unit-testable in isolation. The runtime owner is EpubBilingualController.
//
// Mirrors the iOS EPUBBilingualJS pipeline (vreader/Views/Reader/Bilingual/EPUBBilingualJS.swift):
//   - enumerate LEAF blocks only (iOS Bug #266 — a <blockquote><p> counts the inner
//     <p> once; a block that CONTAINS another block is skipped, so the enumerate count
//     stays aligned with the direct-block segmentation),
//   - inject via createElement + createTextNode/textContent (NEVER innerHTML concat —
//     CSP-safe), idempotent (replace an existing decoration sibling in place),
//   - a single injected <style id="vreader-bilingual-style"> (iOS bilingualStyleJS)
//     + a per-target heading/cjk modifier class (iOS Feature #100 parity),
//   - clear removes every decoration node; a probe returns the current count.
//
// Android divergence from iOS (spike-confirmed): iOS POSTS the enumerate payload to a
// WKScriptMessageHandler; Android RETURNS the `[{id,text}]` array DIRECTLY from the
// evaluate call — `WebView.evaluateJavascript` already JSON-encodes the return value,
// so the enumerate/probe scripts `return` a JS value (an array / a number) and the
// Kotlin side parses the raw JSON with JSONTokener. NEVER JSON.stringify the return
// (that double-encodes). All interpolated Kotlin strings are JSON-encoded before they
// enter the JS literal (CSP-safe: a `"` / `</script>` / `'` in a translation cannot
// break out of the string or CSS literal).
//
// @coordinates-with: EpubBilingualController.kt, EpubChapterTextProvider.kt,
//   BilingualRenderState.kt,
//   iOS vreader/Views/Reader/Bilingual/EPUBBilingualJS.swift,
//   dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md (WI-7b)
package com.vreader.app.bilingual

import org.json.JSONObject

/**
 * A JS-string builder for the EPUB bilingual DOM pipeline (enumerate / inject / clear /
 * probe). Pure: every method returns a self-invoking JS string; no Android/Compose/IO.
 * The single runtime consumer is [EpubBilingualController].
 */
object EpubBilingualJs {

    /** The attribute the enumerate path stamps on each translatable leaf block; the
     *  inject path matches on it. Parity with iOS `blockIDAttribute`. */
    const val BLOCK_ID_ATTRIBUTE = "data-vreader-bid"

    /** The marker attribute on every injected translation node (never a source block). */
    const val DECORATION_ATTRIBUTE = "data-vreader-decoration"

    /** The class every injected translation node carries (matched by clear + the CSS). */
    const val BLOCK_CLASS = "vreader-bilingual"

    /** The id of the single injected `<style>` element (idempotent — updated in place). */
    const val STYLE_ELEMENT_ID = "vreader-bilingual-style"

    /** Modifier class on a decoration whose SOURCE block is a heading (h1–h6). */
    const val HEADING_CLASS = "vreader-bilingual--heading"

    /** Modifier class added alongside [HEADING_CLASS] when the target language is CJK. */
    const val CJK_CLASS = "vreader-bilingual--cjk"

    /** One enumerated leaf block: its stamped id and its normalized (collapsed) text. */
    data class Block(val id: String, val text: String)

    /**
     * JS that enumerates the CURRENT resource's LEAF blocks (iOS Bug #266), stamps a
     * stable `data-vreader-bid` on each, and RETURNS the `[{id,text}]` array DIRECTLY.
     * A block that already contains another block element (a non-leaf, e.g.
     * `<blockquote><p>…`) is skipped so the count stays aligned with the direct-block
     * segmentation. An already-injected decoration node is never re-stamped. Whitespace
     * is collapsed + trimmed; empty blocks are dropped. Re-runnable: a pre-existing bid
     * is reused (never re-stamped), so re-enumerate is stable.
     */
    val enumScript: String = """
        (function() {
            var BLOCK_TAGS = {
                p: 1, li: 1, blockquote: 1, pre: 1, dd: 1, dt: 1,
                h1: 1, h2: 1, h3: 1, h4: 1, h5: 1, h6: 1
            };
            var BLOCK_SELECTOR = Object.keys(BLOCK_TAGS).join(',');
            var seq = 0;
            var seen = {};   // guards against a book-supplied duplicate/reserved bid (Gate-4 Low)
            function stamp(el) {
                var existing = el.getAttribute('$BLOCK_ID_ATTRIBUTE');
                // Reuse a stable existing bid ONLY when it is unique this enumeration — a
                // book-supplied duplicate would otherwise collapse the translation map.
                if (existing && !Object.prototype.hasOwnProperty.call(seen, existing)) {
                    seen[existing] = 1;
                    return existing;
                }
                do { seq += 1; var bid = 'b' + seq; } while (Object.prototype.hasOwnProperty.call(seen, bid));
                seen[bid] = 1;
                el.setAttribute('$BLOCK_ID_ATTRIBUTE', bid);
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
                    if (el.hasAttribute && el.hasAttribute('$DECORATION_ATTRIBUTE')) continue;
                    // Bug #266: LEAF blocks only — skip a block that contains another block.
                    if (el.querySelector && el.querySelector(BLOCK_SELECTOR)) continue;
                    var text = el.textContent || '';
                    text = text.replace(/\s+/g, ' ').trim();
                    if (!text) continue;
                    var bid = stamp(el);
                    out.push({ id: bid, text: text });
                }
            } catch (e) {}
            return out;
        })();
    """.trimIndent()

    /**
     * JS that ensures the single `<style id="vreader-bilingual-style">` carrying the
     * interlinear CSS is present in `<head>` (idempotent — updates the existing node's
     * text on a theme/language change). NEVER innerHTML: the CSS is JSON-encoded and
     * assigned via `textContent`. Mirrors iOS `bilingualStyleJS`.
     */
    fun styleScript(css: String): String {
        val cssLiteral = jsString(css)
        return """
            (function() {
                try {
                    var id = '$STYLE_ELEMENT_ID';
                    var css = $cssLiteral;
                    var el = document.getElementById(id);
                    if (!el) {
                        el = document.createElement('style');
                        el.id = id;
                        (document.head || document.documentElement).appendChild(el);
                    }
                    if (el.textContent !== css) { el.textContent = css; }
                } catch (e) {}
            })();
        """.trimIndent()
    }

    /**
     * JS that injects one translation decoration node after each source block named in
     * [translationsById] (bid → translation). CSP-safe: the map is JSON-encoded via
     * `JSONObject(map).toString()` (a `"` / `'` / `</script>` inside a translation cannot
     * break out of the JS literal) and each node is built with `createElement` +
     * `textContent` — NEVER innerHTML string-concat. Idempotent: a source block whose
     * next sibling is already our decoration is UPDATED in place (no duplicate), and the
     * heading/cjk modifier classes are NORMALIZED on the in-place update (a language
     * switch reuses the node, so stale modifiers drop). The bid selector is escaped via
     * `CSS.escape` with the iOS `[^a-zA-Z0-9_-]` fallback. Injected nodes are
     * non-selectable (`user-select: none`, iOS parity — a long-press on the translation
     * does not perturb the source selection offsets). RETURNS the decoration count.
     * [targetIsCjk] toggles the CJK heading tracking modifier.
     */
    fun injectScript(translationsById: Map<String, String>, targetIsCjk: Boolean = false): String {
        // JSON-encode the whole map in ONE call — CSP-safe, cannot break the JS literal.
        val translationsLiteral = JSONObject(translationsById.toMap()).toString()
        return """
            (function() {
                var translations = $translationsLiteral;
                $BID_SELECTOR_ESCAPE_JS
                function findBlock(bid) {
                    try {
                        return document.querySelector(
                            '[$BLOCK_ID_ATTRIBUTE="' + __vreaderBidEsc(bid) + '"]'
                        );
                    } catch (e) { return null; }
                }
                var TARGET_CJK = ${if (targetIsCjk) "true" else "false"};
                function isHeading(el) {
                    return !!(el && /^H[1-6]${'$'}/i.test(el.tagName || ''));
                }
                function headingClasses(el) {
                    if (!isHeading(el)) { return ''; }
                    return ' $HEADING_CLASS' + (TARGET_CJK ? ' $CJK_CLASS' : '');
                }
                function makeBlock(text, sourceBlock) {
                    var div = document.createElement('div');
                    div.className = '$BLOCK_CLASS' + headingClasses(sourceBlock);
                    div.setAttribute('$DECORATION_ATTRIBUTE', '');
                    div.style.cssText = 'user-select: none; -webkit-user-select: none;';
                    div.textContent = text;
                    return div;
                }
                var count = 0;
                var keys = Object.keys(translations);
                for (var k = 0; k < keys.length; k++) {
                    var bid = keys[k];
                    // Use the prototype's hasOwnProperty so a book-supplied bid that shadows a
                    // built-in name (e.g. 'hasOwnProperty') cannot break the guard (Gate-4 Low).
                    if (!Object.prototype.hasOwnProperty.call(translations, bid)) continue;
                    var block = findBlock(bid);
                    if (!block) continue;
                    var existing = block.nextElementSibling;
                    if (existing
                        && existing.hasAttribute
                        && existing.hasAttribute('$DECORATION_ATTRIBUTE')
                        && existing.classList
                        && existing.classList.contains('$BLOCK_CLASS')) {
                        if (isHeading(block)) {
                            existing.classList.add('$HEADING_CLASS');
                            existing.classList.toggle('$CJK_CLASS', TARGET_CJK);
                        } else {
                            existing.classList.remove('$HEADING_CLASS');
                            existing.classList.remove('$CJK_CLASS');
                        }
                        existing.textContent = translations[bid];
                        count += 1;
                        continue;
                    }
                    var node = makeBlock(translations[bid], block);
                    if (block.parentNode) {
                        block.parentNode.insertBefore(node, block.nextSibling);
                        count += 1;
                    }
                }
                return count;
            })();
        """.trimIndent()
    }

    /**
     * JS that removes every injected decoration node from the whole document. Idempotent
     * — an empty `querySelectorAll` is a no-op. RETURNS the remaining decoration count
     * (0 after a successful clear). Mirrors iOS `globalClearJS`.
     */
    val clearScript: String = """
        (function() {
            try {
                var nodes = document.querySelectorAll(
                    '.$BLOCK_CLASS[$DECORATION_ATTRIBUTE]'
                );
                for (var i = 0; i < nodes.length; i++) {
                    var n = nodes[i];
                    if (n.parentNode) { n.parentNode.removeChild(n); }
                }
                return document.querySelectorAll('.$BLOCK_CLASS[$DECORATION_ATTRIBUTE]').length;
            } catch (e) { return -1; }
        })();
    """.trimIndent()

    /**
     * A cheap probe returning the CURRENT decoration count in the resource DOM. Used by
     * the controller's probe-gated re-apply: a scroll round-trip / a `submitPreferences`
     * reflow can leave the decorations in place, so the controller re-injects ONLY when
     * this probe reports the expected decorations are missing.
     */
    val decorationCountScript: String = """
        (function() {
            try {
                return document.querySelectorAll('.$BLOCK_CLASS[$DECORATION_ATTRIBUTE]').length;
            } catch (e) { return -1; }
        })();
    """.trimIndent()

    /**
     * Parse the raw JSON string a `evaluateJavascript(enumScript)` call returns (the
     * WebView already JSON-encoded the returned array) into an ordered [Block] list.
     * A null/blank/`"null"` return, a non-array, or a malformed entry yields an empty
     * list (never a crash). An entry missing `id` or `text`, or with a blank id, is
     * skipped. This is the ONLY place the enumerate wire form is decoded.
     */
    fun parseEnumResult(raw: String?): List<Block> {
        val trimmed = raw?.trim().orEmpty()
        if (trimmed.isEmpty() || trimmed == "null") return emptyList()
        val value = runCatching { org.json.JSONTokener(trimmed).nextValue() }.getOrNull()
        val array = value as? org.json.JSONArray ?: return emptyList()
        val out = ArrayList<Block>(array.length())
        for (i in 0 until array.length()) {
            val obj = array.optJSONObject(i) ?: continue
            val id = obj.optString("id").takeIf { it.isNotEmpty() } ?: continue
            if (!obj.has("text")) continue
            out.add(Block(id = id, text = obj.optString("text")))
        }
        return out
    }

    /**
     * Parse the numeric return of a `evaluateJavascript(injectScript/clearScript/
     * decorationCountScript)` call into an Int. A null/blank/non-numeric return yields
     * [default] (never a crash) — the caller treats an unparseable probe as "unknown"
     * and re-injects defensively.
     */
    fun parseCountResult(raw: String?, default: Int = -1): Int =
        raw?.trim()?.toIntOrNull() ?: default

    /** JSON-encode [value] into a JS string literal (quotes included). CSP-safe: the
     *  content cannot break out of the enclosing string. Uses the JSON string form
     *  (`JSONObject.quote`), which escapes `"`, `\`, control chars, and `</` sequences. */
    private fun jsString(value: String): String = JSONObject.quote(value)

    /** iOS `__vreaderBidEsc` parity: `CSS.escape` with the `[^a-zA-Z0-9_-] → \\$&`
     *  fallback so a stamped bid interpolated into a `[data-vreader-bid="…"]` selector
     *  can never break the selector context. */
    private const val BID_SELECTOR_ESCAPE_JS =
        "function __vreaderBidEsc(s) { return (typeof CSS !== 'undefined' && CSS.escape) ? " +
            "CSS.escape(s) : String(s).replace(/[^a-zA-Z0-9_-]/g, '\\\\\$&'); }"
}
