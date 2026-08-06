// Purpose: feature #142 WI-3 — pins the EXACT JS the AZW3 (foliate-js) reader injects to paint, erase
// and dismiss a highlight, and proves its escaping. These three builders are the ONLY production seam
// FoliateBridge.addAnnotation / deleteAnnotation / deselect run through `evaluateJavascript`, so the
// string this test pins is byte-for-byte the string the WebView executes (the foliateSetStylesJs /
// FoliateJSEscaper pattern — no test-vs-production drift).
//
// Every interpolated value is attacker-influenceable in principle: a CFI is minted from book content,
// and a restored CFI came off a backup wire. So each is asserted as a FULL expected string — "the JS
// contains the cfi" would pass on an unescaped build — over an adversarial corpus (quote, double
// quote, backslash, newline, tab, NUL, `</script>`, astral emoji, CJK).
package com.vreader.app.reader.foliate

import com.vreader.app.annotations.AnnotationColor
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FoliateAnnotationJsTest {

    /** One literal backslash — as it appears in the EMITTED JS. Built by concatenation so this source
     *  file never contains a `\uXXXX` sequence (a tool-written escape can silently become a real
     *  control character in the file, which then breaks grep and reads as a binary file). */
    private val bs = "\\"

    /** A real NUL, built from its char code for the same reason. */
    private val nul = 0.toChar().toString()

    /** U+2028 / U+2029 — the two characters JSON leaves raw that JS treated as line terminators until
     *  ES2019. A raw one is a PARSE error, which no `try{…}catch{}` can rescue. */
    private val lineSeparator = 0x2028.toChar().toString()
    private val paragraphSeparator = 0x2029.toChar().toString()

    /** Unpaired surrogates — malformed UTF-16 that cannot be written as a source literal at all
     *  (UTF-8 cannot encode them), so they are built from code units. */
    private val loneHighSurrogate = 0xD83D.toChar().toString()
    private val loneLowSurrogate = 0xDE00.toChar().toString()

    private val cfi = "epubcfi(/6/4!/4/2,/1:0,/1:12)"
    private val yellow = AnnotationColor.yellow.dotHex // "#e6b800"

    private fun addJs(value: String, color: String) =
        """try{readerAPI.addAnnotation&&readerAPI.addAnnotation({value:"$value",color:"$color"})}catch(e){}"""

    private fun deleteJs(value: String) =
        """try{readerAPI.deleteAnnotation&&readerAPI.deleteAnnotation({value:"$value"})}catch(e){}"""

    // ---- the exact production strings -------------------------------------------------------

    @Test
    fun addAnnotationJs_isExactlyThisString() {
        assertEquals(addJs(cfi, yellow), foliateAddAnnotationJs(cfi, yellow))
    }

    @Test
    fun deleteAnnotationJs_isExactlyThisString() {
        assertEquals(deleteJs(cfi), foliateDeleteAnnotationJs(cfi))
    }

    @Test
    fun deselectJs_isExactlyThisString() {
        assertEquals("try{readerAPI.deselect&&readerAPI.deselect()}catch(e){}", foliateDeselectJs())
    }

    @Test
    fun everyPaletteColour_isEmittedAsItsDotHex() {
        // The colour the bundle hands to `Overlayer.highlight` is `annotation.color` verbatim
        // (foliate-bundle.js draw-annotation handler), so the palette hex must survive untouched.
        for (color in AnnotationColor.entries) {
            assertEquals(
                "colour ${color.key} must be emitted as its dotHex",
                addJs(cfi, color.dotHex),
                foliateAddAnnotationJs(cfi, color.dotHex),
            )
        }
    }

    // ---- adversarial CFIs: the value is a JSON string literal, escaped exactly ---------------

    /** input → the EXACT escaped body the builder must emit between the delimiting double quotes. */
    private fun adversarialCfis(): List<Pair<String, String>> = listOf(
        // A single quote is NOT special inside a double-quoted literal — and this is precisely why the
        // builder must use double quotes. A single-quoted literal (the iOS FoliateHighlightRenderer
        // shape) would break out here.
        "epubcfi(/6/4!/4/2)'+alert(1)+'" to "epubcfi(/6/4!/4/2)'+alert(1)+'",
        """a"b""" to """a$bs"b""",
        "a" + bs + "b" to "a" + bs + bs + "b",
        "a\nb" to "a" + bs + "n" + "b",
        "a\tb" to "a" + bs + "t" + "b",
        "a\rb" to "a" + bs + "r" + "b",
        // `/` is not escaped by JSON, and it does not need to be: the string is handed to
        // evaluateJavascript, never spliced into an HTML <script> element, so there is no parser
        // for `</script>` to terminate. Pinned so the claim is checked, not assumed.
        "</script>" to "</script>",
        "a" + nul + "b" to "a" + bs + "u0000" + "b",
        // JSON emits these two RAW; JS treated them as line terminators before ES2019, so a raw one is
        // a parse error the try/catch cannot rescue (the statement never compiles). Escaped on top of
        // JSON so the build does not depend on which System WebView the device ships.
        "a" + lineSeparator + "b" to "a" + bs + "u2028" + "b",
        "a" + paragraphSeparator + "b" to "a" + bs + "u2029" + "b",
        // Malformed UTF-16 passes through as-is: not an injection vector (neither half is a quote or a
        // backslash), and mangling it would silently corrupt a CFI. Pinned so the behaviour is a
        // decision rather than an accident.
        "a" + loneHighSurrogate + "b" to "a" + loneHighSurrogate + "b",
        "a" + loneLowSurrogate + "b" to "a" + loneLowSurrogate + "b",
        "第三章的高亮" to "第三章的高亮",
        "emoji 😀 tail" to "emoji 😀 tail",
        // The classic break-out attempt against a naive template.
        """"});readerAPI.destroy();({"value":"x""" to """$bs"});readerAPI.destroy();({$bs"value$bs":$bs"x""",
    )

    @Test
    fun addAnnotationJs_escapesEveryAdversarialCfi_exactly() {
        for ((input, escaped) in adversarialCfis()) {
            assertEquals(
                "cfi [$input] must escape to [$escaped]",
                addJs(escaped, yellow),
                foliateAddAnnotationJs(input, yellow),
            )
        }
    }

    @Test
    fun deleteAnnotationJs_escapesEveryAdversarialCfi_exactly() {
        for ((input, escaped) in adversarialCfis()) {
            assertEquals(
                "cfi [$input] must escape to [$escaped]",
                deleteJs(escaped),
                foliateDeleteAnnotationJs(input),
            )
        }
    }

    @Test
    fun addAnnotationJs_escapesTheColourToo() {
        // The colour comes from AnnotationColor today, but the parameter is a String: an unescaped
        // interpolation here is a break-out on any future caller that forwards a stored value.
        val hostile = """#fff"});readerAPI.destroy();({"value":"x","color":"#fff"""
        val escaped = """#fff$bs"});readerAPI.destroy();({$bs"value$bs":$bs"x$bs",$bs"color$bs":$bs"#fff"""
        assertEquals(addJs(cfi, escaped), foliateAddAnnotationJs(cfi, hostile))
    }

    // ---- structural invariants ---------------------------------------------------------------

    @Test
    fun escapedValues_roundTripThroughAJsonDecode() {
        // The emitted argument is a single, well-formed JS/JSON string literal whose decode is the
        // input — i.e. the value cannot have escaped its literal.
        for ((input, _) in adversarialCfis()) {
            val js = foliateAddAnnotationJs(input, yellow)
            val start = js.indexOf("{value:") + "{value:".length
            // lastIndexOf: a hostile CFI could itself contain the literal `,color:`.
            val end = js.lastIndexOf(",color:")
            assertTrue("could not locate the value literal in:\n$js", start in 1 until end)
            assertEquals(input, Json.decodeFromString(String.serializer(), js.substring(start, end)))
        }
    }

    @Test
    fun emittedJs_carriesNoRawJsLineTerminator() {
        // The one class of character JSON alone does NOT make safe for a JS string literal.
        for (raw in listOf(lineSeparator, paragraphSeparator)) {
            for (js in listOf(foliateAddAnnotationJs(raw, yellow), foliateDeleteAnnotationJs(raw))) {
                assertFalse("a raw JS line terminator survived into:\n$js", js.contains(raw))
            }
        }
        // The shared seam is what carries the guarantee — every builder in this package runs through it.
        assertFalse(foliateSetStylesJs("body{}" + lineSeparator).contains(lineSeparator))
    }

    @Test
    fun emittedJs_carriesNoRawControlCharacters() {
        // A raw newline or NUL reaching evaluateJavascript would terminate/corrupt the statement.
        for ((input, _) in adversarialCfis()) {
            for (js in listOf(foliateAddAnnotationJs(input, yellow), foliateDeleteAnnotationJs(input))) {
                val offender = js.firstOrNull { it.code < 0x20 }
                assertTrue("raw control char ${offender?.code} survived into:\n$js", offender == null)
            }
        }
    }

    @Test
    fun everyBuilder_isWrappedInATryCatch_soAMissingReaderApiCannotThrow() {
        // The bundle mounts asynchronously; a call landing before readerAPI exists must be inert.
        val all = listOf(
            foliateAddAnnotationJs(cfi, yellow),
            foliateDeleteAnnotationJs(cfi),
            foliateDeselectJs(),
        )
        for (js in all) {
            assertTrue("must be try-wrapped:\n$js", js.startsWith("try{"))
            assertTrue("must be catch-terminated:\n$js", js.endsWith("}catch(e){}"))
            assertTrue("must guard the readerAPI member:\n$js", js.contains("&&readerAPI."))
        }
    }

    @Test
    fun deleteAnnotationJs_carriesNoColour() {
        // `view.deleteAnnotation({value})` only needs the value; a colour key would be dead weight
        // that a future reader could mistake for a semantic.
        assertFalse(foliateDeleteAnnotationJs(cfi).contains("color"))
    }

    @Test
    fun blankAndEmptyCfi_stillProduceAWellFormedInertCall() {
        // The builders are mechanical: filtering blank CFIs is the mapper's job (WI-2). An empty value
        // reaches `view.addAnnotation`, fails to resolve, and is swallowed by the try/catch — never a
        // syntax error, which is what this pins.
        assertEquals(addJs("", yellow), foliateAddAnnotationJs("", yellow))
        assertEquals(addJs(" ", yellow), foliateAddAnnotationJs(" ", yellow))
        assertEquals(deleteJs(""), foliateDeleteAnnotationJs(""))
    }

    @Test
    fun aVeryLongCfi_isEscapedNotTruncated() {
        // A CFI is book-derived and unbounded; silently truncating one would paint the wrong range.
        val long = "epubcfi(/6/4!/4/" + "2/".repeat(5_000) + "1:0)"
        val js = foliateAddAnnotationJs(long, yellow)
        assertEquals(addJs(long, yellow), js)
        assertTrue(js.contains(long))
    }
}
