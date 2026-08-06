package com.vreader.app.reader.foliate

import com.vreader.app.reader.foliate.FoliateAssetServer.SHELL_ORIGIN
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Feature #126 WI-3 — the pure WebView security decisions. Feature #142 WI-1 adds the per-message-name
 *  raw ceiling ([FoliateBridgePolicy.rawCeilingFor]) and the composed admission gate. */
class FoliateBridgePolicyTest {

    // --- isTrustedMessage: only the main frame of the shell origin ---

    @Test fun trustedMessage_onlyMainFrameOfShellOrigin() {
        assertTrue(FoliateBridgePolicy.isTrustedMessage(SHELL_ORIGIN, true))
    }

    @Test fun trustedMessage_rejectsSubFrame() {
        assertFalse(FoliateBridgePolicy.isTrustedMessage(SHELL_ORIGIN, false))
    }

    @Test fun trustedMessage_rejectsForeignOrigin() {
        assertFalse(FoliateBridgePolicy.isTrustedMessage("https://evil.example", true))
        assertFalse(FoliateBridgePolicy.isTrustedMessage("https://appassets.androidplatform.net.evil.com", true))
        assertFalse(FoliateBridgePolicy.isTrustedMessage(null, true))
    }

    // --- isSameOrigin: exact origin or a path under it; sibling-host bypass blocked ---

    @Test fun sameOrigin_exactAndUnderPath() {
        assertTrue(FoliateBridgePolicy.isSameOrigin(SHELL_ORIGIN))
        assertTrue(FoliateBridgePolicy.isSameOrigin("$SHELL_ORIGIN/assets/foliate/reader.html"))
    }

    @Test fun sameOrigin_rejectsSiblingHostAndUserinfoBypass() {
        assertFalse(FoliateBridgePolicy.isSameOrigin("https://appassets.androidplatform.net.evil.com/x"))
        assertFalse(FoliateBridgePolicy.isSameOrigin("https://appassets.androidplatform.net@evil.com/x"))
        assertFalse(FoliateBridgePolicy.isSameOrigin("https://evil.example/x"))
        assertFalse(FoliateBridgePolicy.isSameOrigin(null))
    }

    // --- isAllowedNavigation: only within the shell origin ---

    @Test fun navigation_allowsShellOrigin() {
        assertTrue(FoliateBridgePolicy.isAllowedNavigation(SHELL_ORIGIN))
        assertTrue(FoliateBridgePolicy.isAllowedNavigation("$SHELL_ORIGIN/assets/foliate/reader.html"))
        assertTrue(FoliateBridgePolicy.isAllowedNavigation("$SHELL_ORIGIN/book/book"))
    }

    @Test fun navigation_blocksEverythingElse() {
        assertFalse(FoliateBridgePolicy.isAllowedNavigation("https://evil.example/x"))
        assertFalse(FoliateBridgePolicy.isAllowedNavigation("javascript:alert(1)"))
        assertFalse(FoliateBridgePolicy.isAllowedNavigation("data:text/html,<script>1</script>"))
        assertFalse(FoliateBridgePolicy.isAllowedNavigation("blob:$SHELL_ORIGIN/abc")) // top-level blob nav
        assertFalse(FoliateBridgePolicy.isAllowedNavigation("file:///etc/hosts"))
        assertFalse(FoliateBridgePolicy.isAllowedNavigation("https://appassets.androidplatform.net.evil.com/x"))
        assertFalse(FoliateBridgePolicy.isAllowedNavigation(null))
    }

    // --- shouldBlockRequest: block remote http(s); allow same-origin; pass blob/data through ---

    @Test fun request_allowsSameOriginAssetsAndBook() {
        assertFalse(FoliateBridgePolicy.shouldBlockRequest("$SHELL_ORIGIN/assets/foliate/foliate-bundle.js"))
        assertFalse(FoliateBridgePolicy.shouldBlockRequest("$SHELL_ORIGIN/book/book"))
    }

    @Test fun request_blocksRemoteHttpResources() {
        // passive exfil: remote img / css url() / font / media a hostile book could trigger w/o script
        assertTrue(FoliateBridgePolicy.shouldBlockRequest("https://tracker.example/pixel.gif"))
        assertTrue(FoliateBridgePolicy.shouldBlockRequest("http://insecure.example/a.css"))
        assertTrue(FoliateBridgePolicy.shouldBlockRequest("https://appassets.androidplatform.net.evil.com/x.png"))
        assertTrue(FoliateBridgePolicy.shouldBlockRequest("HTTPS://Tracker.Example/p")) // case-insensitive
    }

    @Test fun request_passesNonHttpThrough() {
        // blob:/data: section docs are handled internally by the WebView; the loader/WebView own these.
        assertFalse(FoliateBridgePolicy.shouldBlockRequest("blob:$SHELL_ORIGIN/uuid"))
        assertFalse(FoliateBridgePolicy.shouldBlockRequest("data:image/png;base64,AAAA"))
        assertFalse(FoliateBridgePolicy.shouldBlockRequest(null))
    }

    // --- feature #142 WI-1: the PER-MESSAGE-NAME raw ceiling ------------------------------------
    //
    // Read §4.3 of the plan before changing a number here. A GLOBAL ceiling was designed, audited and
    // WITHDRAWN: TOC labels/hrefs are unbounded by design (FoliateTocParser preserves them
    // byte-for-byte because `relocate.tocHref` matching is byte-exact), so no finite global number can
    // both admit a legitimate `book-ready` and bound a `selection`. Only names whose every
    // variable-length field THIS feature already caps may be capped here.

    @Test fun rawCeiling_capsExactlyTheThreeNamesThisFeatureIntroduces() {
        assertEquals(
            FoliateBridgePolicy.RAW_CEILING_SELECTION,
            FoliateBridgePolicy.rawCeilingFor("""{"name":"selection","detail":{"collapsed":true}}"""),
        )
        assertEquals(
            FoliateBridgePolicy.RAW_CEILING_ANNOTATION_SHOW,
            FoliateBridgePolicy.rawCeilingFor("""{"name":"annotation-show","detail":{"value":"/6/4"}}"""),
        )
        assertEquals(
            FoliateBridgePolicy.RAW_CEILING_CREATE_OVERLAY,
            FoliateBridgePolicy.rawCeilingFor("""{"name":"create-overlay","detail":{"index":2}}"""),
        )
        // The derived values themselves are pinned — a silent re-tune must show up as a test change.
        assertEquals(131_072, FoliateBridgePolicy.RAW_CEILING_SELECTION)
        assertEquals(65_536, FoliateBridgePolicy.RAW_CEILING_ANNOTATION_SHOW)
        assertEquals(1_024, FoliateBridgePolicy.RAW_CEILING_CREATE_OVERLAY)
    }

    @Test fun rawCeiling_isNullForEveryOtherName() {
        // `book-ready` and `relocate` carry byte-exact, unbounded, book-derived identifiers #140
        // depends on; the rest are pre-existing names #142 does not touch. All keep today's behaviour.
        val uncapped = listOf(
            """{"name":"book-ready","detail":{"title":"T","sections":85}}""",
            """{"name":"relocate","detail":{"tocHref":"c1.xhtml#s2"}}""",
            """{"name":"goto-ack","detail":{"id":"g1","ok":true}}""",
            """{"name":"bridge-ready","detail":{}}""",
            """{"name":"error","detail":{"message":"x"}}""",
            """{"name":"tap","detail":{"x":10}}""",
            """{"name":"section-load","detail":{"index":3}}""",
            """{"name":"external-link","detail":{"href":"https://x"}}""",
            """{"name":"tts-ssml","detail":{}}""",
            """{"name":"a-name-that-does-not-exist-yet","detail":{}}""", // a future/unknown name
        )
        for (raw in uncapped) assertNull("ceiling for $raw", FoliateBridgePolicy.rawCeilingFor(raw))
    }

    @Test fun rawCeiling_isLexical_soAnUnparseablePayloadIsStillCapped() {
        // THE load-bearing property: rawCeilingFor must NOT parse. A cap that required the parse it
        // exists to bound would be circular — the audit checked this explicitly. A truncated payload
        // (parseToJsonElement would fail) still resolves its name and therefore its ceiling.
        assertEquals(
            FoliateBridgePolicy.RAW_CEILING_SELECTION,
            FoliateBridgePolicy.rawCeilingFor("""{"name":"selection","detail":{"text":"unterminated"""),
        )
        assertEquals(
            FoliateBridgePolicy.RAW_CEILING_CREATE_OVERLAY,
            FoliateBridgePolicy.rawCeilingFor("""{"name":"create-overlay","detail":{"index":"""),
        )
        // ...and duplicate keys / trailing junk, which a strict parser may also reject.
        assertEquals(
            FoliateBridgePolicy.RAW_CEILING_ANNOTATION_SHOW,
            FoliateBridgePolicy.rawCeilingFor("""{"name":"annotation-show","name":"book-ready"} trailing"""),
        )
    }

    @Test fun rawCeiling_toleratesWhitespaceAroundTheNameSeparator() {
        assertEquals(
            FoliateBridgePolicy.RAW_CEILING_SELECTION,
            FoliateBridgePolicy.rawCeilingFor("""{ "name" : "selection" , "detail":{} }"""),
        )
    }

    @Test fun rawCeiling_takesTheFirstNameKey_soANestedDecoyOnlyEverTIGHTENS() {
        // Our shim serialises `{name, detail}` with `name` FIRST (reader.html), so the first `"name"`
        // in the window IS the envelope name. A payload that buries the envelope name behind a nested
        // one resolves to the NESTED name's ceiling — i.e. it can only make the gate STRICTER (a drop),
        // never looser. Documented rather than defended: this is not an adversarial parser.
        val decoyed = """{"detail":{"name":"create-overlay"},"name":"selection"}"""
        assertEquals(FoliateBridgePolicy.RAW_CEILING_CREATE_OVERLAY, FoliateBridgePolicy.rawCeilingFor(decoyed))
    }

    @Test fun rawCeiling_isNullWhenTheNameIsBeyondTheSniffWindow() {
        // The documented degradation (plan §4.3 limit 2): unsniffable ⇒ UNCAPPED ⇒ today's behaviour.
        // Fail-open is deliberate — the load-bearing defense is the bundle patch + the origin gate,
        // and a fail-closed sniff could drop a legitimate message from a future shim.
        val pad = "p".repeat(FoliateBridgePolicy.NAME_SNIFF_WINDOW)
        assertNull(FoliateBridgePolicy.rawCeilingFor("""{"pad":"$pad","name":"selection","detail":{}}"""))
    }

    @Test fun rawCeiling_sniffWindowBoundary_isInclusiveOfTheClosingQuote() {
        // Build `{"pad":"<n>","name":"selection"...` so the name's CLOSING quote sits exactly at the
        // last readable index, then push it one char further and watch the ceiling disappear.
        val prefix = """{"pad":""""
        val middle = """","name":"selection""""
        val padLen = FoliateBridgePolicy.NAME_SNIFF_WINDOW - prefix.length - middle.length
        val atEdge = prefix + "p".repeat(padLen) + middle + ""","detail":{}}"""
        assertEquals(FoliateBridgePolicy.RAW_CEILING_SELECTION, FoliateBridgePolicy.rawCeilingFor(atEdge))
        val onePast = prefix + "p".repeat(padLen + 1) + middle + ""","detail":{}}"""
        assertNull(FoliateBridgePolicy.rawCeilingFor(onePast))
    }

    @Test fun rawCeiling_isNullForNamelessOrNonJsonInput() {
        for (raw in listOf(
            "",
            "not json at all",
            """["selection"]""",
            "{}",
            """{"detail":{"text":"hi"}}""",       // no name key
            """{"name":42}""",                    // non-string name
            """{"name":}""",                      // no value
            """{"name""",                         // truncated before the separator
            """{"name":"selection""",             // unterminated name literal
            """{"nametag":"selection"}""",        // a DIFFERENT key that merely starts with `name`
        )) {
            assertNull("ceiling for [$raw]", FoliateBridgePolicy.rawCeilingFor(raw))
        }
    }

    @Test fun rawCeiling_isNullWhenTheNameLiteralContainsAnEscape() {
        // `"selection"` decodes to "selection", but the sniff reads the literal, not the decoded
        // value. It bails on the escape → uncapped → today's behaviour (fail-open, as documented).
        val backslash = 92.toChar()
        assertNull(FoliateBridgePolicy.rawCeilingFor("""{"name":"selecti${backslash}u006fn","detail":{}}"""))
    }

    @Test fun rawCeiling_readsBoundedInputWithoutThrowing() {
        // A multi-megabyte payload must be classified from its head, never scanned end-to-end.
        val huge = """{"name":"selection","detail":{"text":"""" + "x".repeat(5_000_000) + """"}}"""
        assertEquals(FoliateBridgePolicy.RAW_CEILING_SELECTION, FoliateBridgePolicy.rawCeilingFor(huge))
        assertFalse(FoliateBridgePolicy.withinRawCeiling(huge))
    }

    // --- withinRawCeiling: the length decision -------------------------------------------------

    @Test fun withinRawCeiling_boundariesForEachCappedName() {
        val cases = listOf(
            "selection" to FoliateBridgePolicy.RAW_CEILING_SELECTION,
            "annotation-show" to FoliateBridgePolicy.RAW_CEILING_ANNOTATION_SHOW,
            "create-overlay" to FoliateBridgePolicy.RAW_CEILING_CREATE_OVERLAY,
        )
        for ((name, ceiling) in cases) {
            assertTrue("$name one under", FoliateBridgePolicy.withinRawCeiling(rawOfLength(name, ceiling - 1)))
            assertTrue("$name at ceiling", FoliateBridgePolicy.withinRawCeiling(rawOfLength(name, ceiling)))
            assertFalse("$name one over", FoliateBridgePolicy.withinRawCeiling(rawOfLength(name, ceiling + 1)))
        }
    }

    @Test fun withinRawCeiling_admitsAnUncappedNameOfAnySize() {
        // The H1 regression pin at the policy level: a `book-ready` far larger than any capped name's
        // ceiling — and larger than the withdrawn 4 MiB global cap — is ADMITTED. A 10 000-row TOC with
        // 200-char labels and hrefs is ~4.37M chars, and label length is unbounded by contract.
        for (name in listOf("book-ready", "relocate", "goto-ack", "brand-new-name")) {
            assertTrue(name, FoliateBridgePolicy.withinRawCeiling(rawOfLength(name, 5_000_000)))
        }
    }

    @Test fun rawCeiling_neverSilentlyShrinksTheFieldCaps() {
        // The derivation's whole point: a selection sitting at BOTH field caps with worst-case
        // `\uXXXX` escaping (6 raw chars per character) must fit UNDER its raw ceiling — otherwise the
        // raw gate would quietly enforce a smaller text/cfi limit than FoliateMessageParser advertises.
        val escapedChar = "${92.toChar()}u4e2d" // 6 raw chars, decodes to one CJK character
        val text = escapedChar.repeat(FoliateMessageParser.MAX_SELECTION_CHARS)
        val cfi = escapedChar.repeat(FoliateMessageParser.MAX_CFI_CHARS)
        val raw = """{"name":"selection","detail":{"collapsed":false,"text":"$text","cfi":"$cfi",""" +
            """"index":3,"rect":{"x":1.0,"y":2.0,"width":3.0,"height":4.0}}}"""

        assertTrue(
            "worst-case raw length ${raw.length} exceeds the selection ceiling",
            raw.length <= FoliateBridgePolicy.RAW_CEILING_SELECTION,
        )
        assertTrue(FoliateBridgePolicy.withinRawCeiling(raw))
        // ...and the parser genuinely accepts it at both caps, so the two limits agree end to end.
        val parsed = FoliateMessageParser.parse(raw) as FoliateMessage.Selection
        assertEquals(FoliateMessageParser.MAX_SELECTION_CHARS, parsed.text.length)
        assertEquals(FoliateMessageParser.MAX_CFI_CHARS, parsed.cfi.length)
    }

    // --- admitsMessage: the single predicate the bridge listener runs ---------------------------

    @Test fun admitsMessage_requiresTrustAndTheCeilingTogether() {
        val small = """{"name":"selection","detail":{"collapsed":true}}"""
        val oversized = rawOfLength("selection", FoliateBridgePolicy.RAW_CEILING_SELECTION + 1)

        assertTrue(FoliateBridgePolicy.admitsMessage(SHELL_ORIGIN, true, small))
        // Trusted but over its ceiling → dropped before parse.
        assertFalse(FoliateBridgePolicy.admitsMessage(SHELL_ORIGIN, true, oversized))
        // Untrusted stays untrusted regardless of size.
        assertFalse(FoliateBridgePolicy.admitsMessage("https://evil.example", true, small))
        assertFalse(FoliateBridgePolicy.admitsMessage(SHELL_ORIGIN, false, small))
        assertFalse(FoliateBridgePolicy.admitsMessage(null, true, small))
        // An uncapped name of any size from the trusted origin is still admitted.
        assertTrue(FoliateBridgePolicy.admitsMessage(SHELL_ORIGIN, true, rawOfLength("book-ready", 5_000_000)))
    }

    @Test fun admitsMessage_admitsAnEmptyPayload() {
        // `message.data` may be null → the bridge passes "". It has no name, so it is uncapped and
        // admitted here; the PARSER is what drops it. Splitting those two rejections keeps the gate's
        // job (bounding parse-time amplification) separate from the parser's (validity).
        assertTrue(FoliateBridgePolicy.admitsMessage(SHELL_ORIGIN, true, ""))
        assertNull(FoliateMessageParser.parse(""))
    }

    // --- the enforcement POINT: the gate must run before the parse -----------------------------

    @Test fun foliateBridge_appliesTheAdmissionGateBeforeParsing() {
        // STRUCTURAL, and deliberately so. `admitsMessage` is behaviourally pinned above, but the one
        // thing a JVM test cannot observe is WHERE the bridge calls it — the listener body needs a real
        // WebView. Moving the gate after `parse` (or dropping it) would leave every behavioural test
        // green while re-opening exactly the hole this WI closes, so the wiring is pinned by reading
        // the source, the same way FoliateBundleProvenanceTest pins the shipped bundle's bytes.
        val source = bridgeSource()
        val gate = source.indexOf("FoliateBridgePolicy.admitsMessage(")
        val parse = source.indexOf("FoliateMessageParser.parse(")

        assertTrue("FoliateBridge must gate inbound messages with FoliateBridgePolicy.admitsMessage", gate >= 0)
        assertTrue("FoliateBridge must still parse admitted messages", parse >= 0)
        assertTrue("the admission gate must run BEFORE parse (gate@$gate, parse@$parse)", gate < parse)
        assertEquals(
            "FoliateBridge must have exactly ONE parse call site, all of it behind the gate",
            1,
            Regex(Regex.escape("FoliateMessageParser.parse(")).findAll(source).count(),
        )
    }

    // --- fixtures ------------------------------------------------------------------------------

    /**
     * A syntactically-plausible message for [name], padded to EXACTLY [length] characters. The pad is
     * a JSON number so the fixture needs no quote gymnastics; nothing here parses it.
     */
    private fun rawOfLength(name: String, length: Int): String {
        val prefix = """{"name":"$name","pad":"""
        val suffix = "}"
        val padding = length - prefix.length - suffix.length
        require(padding >= 1) { "length $length is too short for a $name fixture" }
        return prefix + "1".repeat(padding) + suffix
    }

    /** FoliateBridge.kt's source text. Gradle runs JVM tests with `android/app` as CWD (the
     *  FoliateBundleProvenanceTest convention); the extra candidates cover other runners. */
    private fun bridgeSource(): String {
        val relative = "src/main/kotlin/com/vreader/app/reader/foliate/FoliateBridge.kt"
        val candidates = listOf(relative, "app/$relative", "android/app/$relative")
        val file = candidates.map { File(it) }.firstOrNull { it.exists() }
            ?: error("FoliateBridge.kt not found from CWD=${File(".").absolutePath} (tried $candidates)")
        return file.readText()
    }
}
