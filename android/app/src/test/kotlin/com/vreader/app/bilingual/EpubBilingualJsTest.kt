// Purpose: feature #131 WI-7b — RED-first JVM tests for EpubBilingualJs (the pure JS-string
// builder for the EPUB bilingual DOM pipeline). Covers: the enumerate script emits a leaf-only
// walk (Bug #266) and RETURNS the array (no JSON.stringify); parseEnumResult decodes the raw
// `[{id,text}]` return via JSONTokener (and tolerates null/non-array/malformed); the inject
// script is CSP-safe (a `"` / `'` / `</script>` in a translation is JSON-encoded and cannot
// break the JS literal), never uses innerHTML, is idempotent (replaces in place), and carries
// the non-selectable + heading/cjk modifier parity; the clear/probe scripts + parseCountResult;
// the RTL/CJK style injection is single + textContent-only; the CSS.escape fallback is present.
// Robolectric-run so parseEnumResult uses the real android.org.json (JSONTokener/JSONObject).
package com.vreader.app.bilingual

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class EpubBilingualJsTest {

    // ── enumerate script shape ────────────────────────────────

    @Test fun enumScript_walksLeafBlocksOnly_andReturnsArrayNoStringify() {
        val js = EpubBilingualJs.enumScript
        // Bug #266: a block that CONTAINS another block is skipped (leaf-only).
        assertTrue("leaf-only guard via querySelector(BLOCK_SELECTOR)", js.contains("el.querySelector(BLOCK_SELECTOR)"))
        assertTrue("block tag table present", js.contains("blockquote: 1"))
        // Returns the array directly — NEVER JSON.stringify (the WebView encodes the return).
        assertTrue("returns an out array", js.contains("return out;"))
        assertFalse("must NOT JSON.stringify the return", js.contains("JSON.stringify"))
        // Skips an already-injected decoration node on re-enumerate.
        assertTrue("skips decoration siblings", js.contains(EpubBilingualJs.DECORATION_ATTRIBUTE))
        // Emits {id,text} (Android key names), not the iOS {bid,text}.
        assertTrue("pushes {id,text}", js.contains("out.push({ id: bid, text: text });"))
    }

    // ── parseEnumResult ───────────────────────────────────────

    @Test fun parseEnumResult_decodesArrayViaJsonTokener() {
        val blocks = EpubBilingualJs.parseEnumResult("""[{"id":"b1","text":"Hello"},{"id":"b2","text":"World"}]""")
        assertEquals(listOf(EpubBilingualJs.Block("b1", "Hello"), EpubBilingualJs.Block("b2", "World")), blocks)
    }

    @Test fun parseEnumResult_toleratesNullBlankNonArrayAndMalformed() {
        assertTrue(EpubBilingualJs.parseEnumResult(null).isEmpty())
        assertTrue(EpubBilingualJs.parseEnumResult("").isEmpty())
        assertTrue(EpubBilingualJs.parseEnumResult("null").isEmpty())
        assertTrue(EpubBilingualJs.parseEnumResult("42").isEmpty())        // not an array
        assertTrue(EpubBilingualJs.parseEnumResult("{not json").isEmpty()) // malformed
        // an entry missing id/text or with a blank id is skipped, the rest survive
        val blocks = EpubBilingualJs.parseEnumResult("""[{"id":"","text":"x"},{"id":"b2"},{"id":"b3","text":"ok"}]""")
        assertEquals(listOf(EpubBilingualJs.Block("b3", "ok")), blocks)
    }

    @Test fun parseEnumResult_preservesCjkAndEmptyText() {
        val blocks = EpubBilingualJs.parseEnumResult("""[{"id":"b1","text":"你好，世界"},{"id":"b2","text":""}]""")
        assertEquals(listOf(EpubBilingualJs.Block("b1", "你好，世界"), EpubBilingualJs.Block("b2", "")), blocks)
    }

    // ── inject script — CSP safety + idempotency + parity ─────

    @Test fun injectScript_isCspSafe_forHostileTranslation() {
        val hostile = "'; alert(1); //</script><img src=x onerror=alert(2)>\" \\ end"
        val js = EpubBilingualJs.injectScript(mapOf("b1" to hostile), allBlockIds = listOf("b1"))
        // The map is JSON-encoded into arrays, so the raw hostile text NEVER appears verbatim in
        // the JS — its quotes/backslashes/`</` are escaped. A break-out needs a bare `';` sequence.
        assertFalse("hostile text must not appear verbatim", js.contains("'; alert(1); //"))
        assertTrue("uses createTextNode/textContent, never innerHTML", !js.contains("innerHTML"))
        assertTrue("builds nodes via createElement", js.contains("createElement('div')"))
        // The escaped `</` sequence must be broken so the JS block can't be closed early.
        assertFalse("raw </script must not appear", js.contains("</script>"))
    }

    @Test fun injectScript_isCjkAndQuoteSafe() {
        val js = EpubBilingualJs.injectScript(mapOf("b1" to "你好\"世界'—<b>x</b>"), allBlockIds = listOf("b1"), targetIsCjk = true)
        assertTrue("CJK payload survives JSON-encoded", js.contains("\\u") || js.contains("你好") )
        assertTrue("no innerHTML", !js.contains("innerHTML"))
        assertTrue("CJK modifier toggled on", js.contains("var TARGET_CJK = true;"))
    }

    @Test fun injectScript_isIdempotent_replacesDecorationSiblingInPlace() {
        val js = EpubBilingualJs.injectScript(mapOf("b1" to "T"), allBlockIds = listOf("b1"))
        assertTrue("replaces existing decoration text in place", js.contains("existing.textContent = texts[i];"))
        assertTrue("checks the decoration attribute before replacing",
            js.contains("e.hasAttribute('${EpubBilingualJs.DECORATION_ATTRIBUTE}')"))
        assertTrue("returns the decoration count", js.contains("return count;"))
    }

    @Test fun injectScript_reconcilesBlankBlocks_byRemovingOwnedDecoration() {
        // b2 is enumerated but NOT translated → its owned decoration must be removed (Gate-4 High).
        val js = EpubBilingualJs.injectScript(mapOf("b1" to "T"), allBlockIds = listOf("b1", "b2"))
        assertTrue("removes owned decoration for a non-translated enumerated block",
            js.contains("rdec.parentNode.removeChild(rdec)"))
        assertTrue("reconcile walks all enumerated ids", js.contains("var allIds ="))
    }

    @Test fun injectScript_setsDirRtl_forRtlTarget() {
        val ltr = EpubBilingualJs.injectScript(mapOf("b1" to "T"), allBlockIds = listOf("b1"), rtl = false)
        val rtl = EpubBilingualJs.injectScript(mapOf("b1" to "T"), allBlockIds = listOf("b1"), rtl = true)
        assertTrue("LTR target → dir auto", ltr.contains("var DIR = 'auto';"))
        assertTrue("RTL target → dir rtl", rtl.contains("var DIR = 'rtl';"))
        assertTrue("dir set on the node", rtl.contains("div.setAttribute('dir', DIR)"))
    }

    @Test fun injectScript_reservedProtoBid_doesNotCollapseTheMap() {
        // A book-supplied '__proto__' bid must be an ordinary array element (arrays, not an object
        // literal) — Object.keys of a `{__proto__:…}` literal would silently drop it (Gate-4 Medium).
        val js = EpubBilingualJs.injectScript(mapOf("__proto__" to "T", "b1" to "U"), allBlockIds = listOf("__proto__", "b1"))
        assertTrue("__proto__ is carried as a data element", js.contains("__proto__"))
        assertTrue("iterates the ids array by index", js.contains("for (var i = 0; i < ids.length; i++)"))
    }

    @Test fun injectScript_nodesAreNonSelectable_forSourceOffsetSafety() {
        val js = EpubBilingualJs.injectScript(mapOf("b1" to "T"), allBlockIds = listOf("b1"))
        assertTrue("user-select none", js.contains("user-select: none"))
        assertTrue("webkit-user-select none", js.contains("-webkit-user-select: none"))
    }

    @Test fun injectScript_headingModifierAndCssEscapeFallback() {
        val js = EpubBilingualJs.injectScript(mapOf("b1" to "T"), allBlockIds = listOf("b1"))
        assertTrue("heading class parity", js.contains(EpubBilingualJs.HEADING_CLASS))
        assertTrue("CSS.escape with the [^a-zA-Z0-9_-] fallback",
            js.contains("CSS.escape") && js.contains("[^a-zA-Z0-9_-]"))
        assertTrue("selector matches on the block id attribute",
            js.contains("[${EpubBilingualJs.BLOCK_ID_ATTRIBUTE}="))
    }

    @Test fun injectScript_emptyMap_isSourceOnlyNoCrash() {
        val js = EpubBilingualJs.injectScript(emptyMap(), allBlockIds = emptyList())
        assertTrue("empty ids array", js.contains("var ids = []"))
        assertTrue("no innerHTML", !js.contains("innerHTML"))
    }

    // ── clear + probe ─────────────────────────────────────────

    @Test fun clearScript_removesDecorations_isIdempotent_returnsRemaining() {
        val js = EpubBilingualJs.clearScript
        assertTrue("querySelectorAll on decoration nodes",
            js.contains("'.${EpubBilingualJs.BLOCK_CLASS}[${EpubBilingualJs.DECORATION_ATTRIBUTE}]'"))
        assertTrue("removes each node", js.contains("removeChild"))
        assertTrue("returns the remaining count", js.contains("return document.querySelectorAll"))
    }

    @Test fun decorationCountScript_returnsCount() {
        assertTrue(EpubBilingualJs.decorationCountScript.contains("return document.querySelectorAll"))
    }

    @Test fun parseCountResult_parsesOrDefaults() {
        assertEquals(3, EpubBilingualJs.parseCountResult("3"))
        assertEquals(0, EpubBilingualJs.parseCountResult("0"))
        assertEquals(-1, EpubBilingualJs.parseCountResult(null))
        assertEquals(-1, EpubBilingualJs.parseCountResult("not a number"))
        assertEquals(7, EpubBilingualJs.parseCountResult(null, default = 7))
    }

    // ── style injection ───────────────────────────────────────

    @Test fun styleScript_injectsSingleStyle_viaTextContent_cspSafe() {
        val css = ".x{content:'</style><script>alert(1)</script>'}"
        val js = EpubBilingualJs.styleScript(css)
        assertTrue("single style element by id", js.contains("var id = '${EpubBilingualJs.STYLE_ELEMENT_ID}';"))
        assertTrue("assigns via textContent, never innerHTML", js.contains("el.textContent = css;"))
        assertFalse("no innerHTML", js.contains("innerHTML"))
        assertFalse("hostile </style> not verbatim", js.contains("</style><script>"))
    }
}
