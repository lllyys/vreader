// Purpose: feature #131 WI-7b — the EPUB bilingual INJECT JS builder, extracted from
// EpubBilingualJs.kt to keep that file under the ~300-line bar (rule 50 §9). This is the
// largest single script (inject + reconcile) and is the only piece with real branching, so
// it lives here as an internal member extension on EpubBilingualJs.
//
// The inject is CSP-safe (ids/texts passed as two index-paired JSON ARRAYS — a `__proto__`
// bid is an ordinary element, never a prototype-polluting object key), never uses innerHTML
// (createElement + textContent), is idempotent (replaces an owned decoration sibling in place),
// RECONCILES (removes the owned decoration of any enumerated block NOT translated this pass — a
// now-blank/absent block or a shorter language set), sets `dir=rtl/auto` for RTL targets, and
// returns the injected count.
//
// @coordinates-with: EpubBilingualJs.kt, EpubBilingualController.kt,
//   iOS vreader/Views/Reader/Bilingual/EPUBBilingualJS.swift (makeInjectJS),
//   dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md (WI-7b)
package com.vreader.app.bilingual

import org.json.JSONArray
import org.json.JSONObject

/**
 * Build the inject JS for [translationsById] (bid → translation), reconciled against the full
 * [allBlockIds] enumeration. See [EpubBilingualJs.injectScript]'s KDoc for the CSP / idempotency /
 * reconcile contract. [targetIsCjk] toggles the CJK heading modifier; [rtl] sets `dir=rtl`.
 */
internal fun EpubBilingualJs.buildInjectScript(
    translationsById: Map<String, String>,
    allBlockIds: List<String>,
    targetIsCjk: Boolean,
    rtl: Boolean,
): String {
    // Two ARRAYS (not a JS object) so a book-supplied `__proto__` bid is an ordinary array
    // element — it can neither collapse the map (a `{__proto__:…}` literal has no own key) nor
    // pollute Object.prototype. Both are JSON-encoded (CSP-safe). The two are index-paired
    // (ids[i] → texts[i]); the reconcile set is the FULL enumerated id list so a block whose
    // translation is now blank/absent has its owned decoration removed (Gate-4 High).
    val ids = translationsById.keys.toList()
    val texts = ids.map { translationsById.getValue(it) }
    val idsLiteral = JSONObject().put("v", JSONArray(ids)).getJSONArray("v").toString()
    val textsLiteral = JSONObject().put("v", JSONArray(texts)).getJSONArray("v").toString()
    val allLiteral = JSONObject().put("v", JSONArray(allBlockIds)).getJSONArray("v").toString()
    val cjk = if (targetIsCjk) "true" else "false"
    val dir = if (rtl) "'rtl'" else "'auto'"
    return """
        (function() {
            var ids = $idsLiteral;
            var texts = $textsLiteral;
            var allIds = $allLiteral;
            ${EpubBilingualJs.BID_SELECTOR_ESCAPE_JS}
            function findBlock(bid) {
                try {
                    return document.querySelector(
                        '[${EpubBilingualJs.BLOCK_ID_ATTRIBUTE}="' + __vreaderBidEsc(bid) + '"]'
                    );
                } catch (e) { return null; }
            }
            function ownedDecoration(block) {
                var e = block ? block.nextElementSibling : null;
                return (e && e.hasAttribute && e.hasAttribute('${EpubBilingualJs.DECORATION_ATTRIBUTE}')
                    && e.classList && e.classList.contains('${EpubBilingualJs.BLOCK_CLASS}')) ? e : null;
            }
            var TARGET_CJK = $cjk;
            var DIR = $dir;
            function isHeading(el) {
                return !!(el && /^H[1-6]${'$'}/i.test(el.tagName || ''));
            }
            function headingClasses(el) {
                if (!isHeading(el)) { return ''; }
                return ' ${EpubBilingualJs.HEADING_CLASS}' + (TARGET_CJK ? ' ${EpubBilingualJs.CJK_CLASS}' : '');
            }
            function makeBlock(text, sourceBlock) {
                var div = document.createElement('div');
                div.className = '${EpubBilingualJs.BLOCK_CLASS}' + headingClasses(sourceBlock);
                div.setAttribute('${EpubBilingualJs.DECORATION_ATTRIBUTE}', '');
                div.setAttribute('dir', DIR);
                div.style.cssText = 'user-select: none; -webkit-user-select: none;';
                div.textContent = text;
                return div;
            }
            // Build a set of ids that will carry a translation this pass (for reconciliation).
            var keep = {};
            for (var a = 0; a < ids.length; a++) { keep[ids[a]] = 1; }
            // 1) Reconcile: remove the owned decoration for any enumerated block that is NOT
            //    getting a translation this pass (a now-blank/absent block — Gate-4 High), so a
            //    language switch to a shorter/blank set never leaves stale nodes behind.
            for (var r = 0; r < allIds.length; r++) {
                var rid = allIds[r];
                if (Object.prototype.hasOwnProperty.call(keep, rid)) continue;
                var rblock = findBlock(rid);
                var rdec = ownedDecoration(rblock);
                if (rdec && rdec.parentNode) { rdec.parentNode.removeChild(rdec); }
            }
            // 2) Inject / update in place for each translated id.
            var count = 0;
            for (var i = 0; i < ids.length; i++) {
                var bid = ids[i];
                var block = findBlock(bid);
                if (!block) continue;
                var existing = ownedDecoration(block);
                if (existing) {
                    if (isHeading(block)) {
                        existing.classList.add('${EpubBilingualJs.HEADING_CLASS}');
                        existing.classList.toggle('${EpubBilingualJs.CJK_CLASS}', TARGET_CJK);
                    } else {
                        existing.classList.remove('${EpubBilingualJs.HEADING_CLASS}');
                        existing.classList.remove('${EpubBilingualJs.CJK_CLASS}');
                    }
                    existing.setAttribute('dir', DIR);
                    existing.textContent = texts[i];
                    count += 1;
                    continue;
                }
                var node = makeBlock(texts[i], block);
                if (block.parentNode) {
                    block.parentNode.insertBefore(node, block.nextSibling);
                    count += 1;
                }
            }
            return count;
        })();
    """.trimIndent()
}
