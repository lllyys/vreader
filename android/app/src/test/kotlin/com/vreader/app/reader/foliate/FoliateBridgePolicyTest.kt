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

    @Test fun rawCeiling_requiresNameToBeTheFIRSTTopLevelKey_soNoDecoyCanReclassify() {
        // Anchoring to the first KEY (not merely the first `"name"` that appears) is what makes the
        // sniff decoy-proof. Scanning for any `"name"` would let a payload pick its own classification
        // in EITHER direction — including LOOSENING a `selection` to the uncapped `book-ready`, which
        // is precisely the hole the ceiling exists to close.

        // A nested decoy AFTER the real name cannot loosen it: our shim's actual ordering is immune.
        assertEquals(
            FoliateBridgePolicy.RAW_CEILING_SELECTION,
            FoliateBridgePolicy.rawCeilingFor("""{"name":"selection","detail":{"name":"book-ready"}}"""),
        )
        // A decoy BEFORE the real name yields null — uncapped, i.e. today's behaviour. Fail-open is
        // deliberate: the load-bearing defense is the bundle patch + the origin gate, and a
        // fail-closed sniff could strand the reader on a future shim's reordering.
        for (decoyed in listOf(
            """{"detail":{"name":"book-ready"},"name":"selection"}""",
            """{"detail":{"name":"create-overlay"},"name":"selection"}""",
            """{"ts":1,"name":"selection","detail":{}}""",
        )) {
            assertNull("decoy: $decoyed", FoliateBridgePolicy.rawCeilingFor(decoyed))
        }
    }

    @Test fun duplicateTopLevelNameKeys_areAnACCEPTEDResidual_boundedByTheFieldCaps() {
        // ACCEPTED RESIDUAL (Gate-4 round 2, Low), pinned rather than left unknown. With DUPLICATE
        // top-level `name` keys the classifier and the parser can disagree: the sniff is lexical and
        // reads the FIRST key, while kotlinx builds a map, so the parser sees the LAST. A payload can
        // therefore present an uncapped name to the gate and a capped one to the parser.
        //
        // Not fixed, deliberately. (a) Our shim cannot emit it — it serialises one `name` from a JS
        // object literal. (b) Forging it requires posting from the shell origin, which per the Gate-2
        // reasoning already means controlling the shell page and having evaluateJavascript-equivalent
        // power, at which point the ceiling is moot. (c) The damage is bounded anyway: the ceiling only
        // ever bounded PARSE-TIME amplification, and every value that survives is still subject to the
        // field caps — asserted below, which is the part that actually protects storage and backups.
        val huge = "x".repeat(FoliateMessageParser.MAX_SELECTION_CHARS + 1)
        val raw = """{"name":"book-ready","name":"selection","detail":{"collapsed":false,"text":"$huge","cfi":"/6/4"}}"""

        // The gate classifies from the FIRST key → uncapped → admitted.
        assertNull(FoliateBridgePolicy.rawCeilingFor(raw))
        assertTrue(FoliateBridgePolicy.admitsMessage(SHELL_ORIGIN, true, raw))
        // ...and the field cap still drops it, so nothing over-long is ever emitted downstream.
        assertNull(FoliateMessageParser.parse(raw))
    }

    @Test fun rawCeiling_isNullWhenTheNameLiteralRunsPastTheSniffWindow() {
        // The documented degradation (plan §4.3 limit 2): unsniffable ⇒ UNCAPPED ⇒ today's behaviour.
        val longName = "s".repeat(FoliateBridgePolicy.NAME_SNIFF_WINDOW)
        assertNull(FoliateBridgePolicy.rawCeilingFor("""{"name":"$longName","detail":{}}"""))
    }

    @Test fun rawCeiling_sniffWindowBoundary_isInclusiveOfTheClosingQuote() {
        // Pad with JSON whitespace after `{` so the name's CLOSING quote sits exactly at the last
        // readable index, then push it one char further and watch the ceiling disappear.
        val tail = """"name":"selection","detail":{}}"""
        val quoteAt = tail.indexOf("selection") + "selection".length // closing quote's offset in tail
        val pad = FoliateBridgePolicy.NAME_SNIFF_WINDOW - 2 - quoteAt

        val atEdge = "{" + " ".repeat(pad) + tail
        assertEquals(
            "fixture must place the closing quote on the window's last readable index",
            FoliateBridgePolicy.NAME_SNIFF_WINDOW - 1,
            1 + pad + quoteAt,
        )
        assertEquals(FoliateBridgePolicy.RAW_CEILING_SELECTION, FoliateBridgePolicy.rawCeilingFor(atEdge))

        val onePast = "{" + " ".repeat(pad + 1) + tail
        assertNull(FoliateBridgePolicy.rawCeilingFor(onePast))
    }

    @Test fun rawCeiling_acceptsOnlyJsonWhitespace_notEveryUnicodeSpace() {
        // JSON's whitespace set is space/tab/LF/CR (RFC 8259). Kotlin's Char.isWhitespace() also
        // accepts NBSP and friends; using it would classify payloads no JSON parser would accept.
        val jsonWs = listOf(0x20, 0x09, 0x0A, 0x0D)
        for (code in jsonWs) {
            val ws = code.toChar()
            assertEquals(
                "ws=$code",
                FoliateBridgePolicy.RAW_CEILING_SELECTION,
                FoliateBridgePolicy.rawCeilingFor("""{$ws"name"$ws:$ws"selection","detail":{}}"""),
            )
        }
        val nbsp = 0x00A0.toChar()
        assertNull(FoliateBridgePolicy.rawCeilingFor("""{$nbsp"name":"selection","detail":{}}"""))
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
            """"name":"selection"""",             // no enclosing object
            """[{"name":"selection"}]""",         // an array, not an object
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

    // --- the enforcement POINT: an inadmissible payload must never REACH the parser ---------------

    @Test fun inboundMessage_neverInvokesTheParserForAnInadmissiblePayload() {
        // The ordering claim, asserted as an OBSERVATION. `admitsMessage` returning false is not
        // enough on its own: the hole this WI closes is `parse` running FIRST and the size check
        // running on its output, which would leave every value-level assertion green while
        // parseToJsonElement had already built the tree. So the seam records whether the parser was
        // reached at all.
        val seen = mutableListOf<String>()
        val spy: (String) -> FoliateMessage? = { raw -> seen += raw; FoliateMessageParser.parse(raw) }
        val admissible = """{"name":"selection","detail":{"collapsed":true}}"""

        // Over its ceiling → dropped, and the parser is NEVER called.
        val oversized = rawOfLength("selection", FoliateBridgePolicy.RAW_CEILING_SELECTION + 1)
        assertNull(foliateInboundMessage(oversized, SHELL_ORIGIN, true, spy))
        assertTrue("an over-ceiling payload must not reach the parser, saw $seen", seen.isEmpty())

        // Untrusted origin / sub-frame → dropped, parser still never called.
        assertNull(foliateInboundMessage(admissible, "https://evil.example", true, spy))
        assertNull(foliateInboundMessage(admissible, SHELL_ORIGIN, false, spy))
        assertNull(foliateInboundMessage(admissible, null, true, spy))
        assertTrue("an untrusted payload must not reach the parser, saw $seen", seen.isEmpty())

        // Admitted → parsed exactly once, with the payload verbatim, and the parser's result returned.
        assertEquals(FoliateMessage.SelectionCleared, foliateInboundMessage(admissible, SHELL_ORIGIN, true, spy))
        assertEquals(listOf(admissible), seen)
    }

    @Test fun inboundMessage_admitsAnUncappedPayloadOfAnySize() {
        // The H1 pin at the enforcement point: a `book-ready` far past every capped ceiling reaches
        // the parser, because dropping it would strand the reader before Loaded.
        val seen = mutableListOf<String>()
        val spy: (String) -> FoliateMessage? = { raw -> seen += raw; FoliateMessage.Other("stub") }
        val huge = rawOfLength("book-ready", 5_000_000)

        assertEquals(FoliateMessage.Other("stub"), foliateInboundMessage(huge, SHELL_ORIGIN, true, spy))
        assertEquals(listOf(huge), seen)
    }

    @Test fun inboundMessage_defaultParserIsTheRealOne() {
        // The injectable parser exists only so the test above can OBSERVE the ordering; production
        // must run the real parser. Pinned so the default can never drift into a stub.
        assertEquals(
            FoliateMessage.BridgeReady,
            foliateInboundMessage("""{"name":"bridge-ready","detail":{}}""", SHELL_ORIGIN, true),
        )
        assertNull(foliateInboundMessage("not json", SHELL_ORIGIN, true))
    }

    @Test fun foliateBridge_routesEveryInboundMessageThroughTheSeam() {
        // Narrowly structural, and the claim is only what it can support: the WebView listener body is
        // not reachable from a JVM test, so this asserts that the bridge has NO direct parse call site
        // — every inbound message goes through `foliateInboundMessage`, which the tests above pin
        // behaviourally. Re-inlining `FoliateMessageParser.parse(...)` into the listener (the way the
        // gate was bypassed before this WI) fails here. Same technique as
        // FoliateBundleProvenanceTest reading the shipped bundle.
        val source = bridgeSource()
        assertTrue(
            "FoliateBridge's listener must delegate to foliateInboundMessage",
            source.contains("foliateInboundMessage("),
        )
        assertEquals(
            "FoliateBridge must have NO direct FoliateMessageParser.parse(...) call site — the seam owns parsing",
            0,
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
