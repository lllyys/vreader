package com.vreader.app.reader.foliate

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Feature #126 WI-2 — the pure bridge-message parser. */
class FoliateMessageParserTest {

    @Test fun bridgeReady() {
        assertEquals(FoliateMessage.BridgeReady, FoliateMessageParser.parse("""{"name":"bridge-ready","detail":{}}"""))
    }

    @Test fun bridgeReady_withoutDetail() {
        assertEquals(FoliateMessage.BridgeReady, FoliateMessageParser.parse("""{"name":"bridge-ready"}"""))
    }

    @Test fun bookReady_sections() {
        val m = FoliateMessageParser.parse("""{"name":"book-ready","detail":{"title":"被偷走的勇气","sections":85}}""")
        assertEquals(FoliateMessage.BookReady("被偷走的勇气", 85), m)
    }

    @Test fun bookReady_acceptsSectionTotalAlias() {
        val m = FoliateMessageParser.parse("""{"name":"book-ready","detail":{"sectionTotal":12}}""")
        assertEquals(FoliateMessage.BookReady(null, 12), m)
    }

    @Test fun bookReady_missingSections_defaultsZero() {
        assertEquals(FoliateMessage.BookReady(null, 0), FoliateMessageParser.parse("""{"name":"book-ready","detail":{}}"""))
    }

    @Test fun relocate_full() {
        val m = FoliateMessageParser.parse(
            """{"name":"relocate","detail":{"cfi":"/6/4!/4/2","fraction":0.42,"sectionIndex":3,"sectionTotal":85}}""",
        )
        assertEquals(FoliateMessage.Relocate("/6/4!/4/2", 0.42, 3, 85), m)
    }

    @Test fun relocate_nullCfiAndFraction() {
        val m = FoliateMessageParser.parse("""{"name":"relocate","detail":{"cfi":null,"fraction":null}}""")
        assertEquals(FoliateMessage.Relocate(null, null, 0, 1), m)
    }

    @Test fun relocate_missingFraction_isNull() {
        val m = FoliateMessageParser.parse("""{"name":"relocate","detail":{"sectionIndex":2,"sectionTotal":9}}""") as FoliateMessage.Relocate
        assertNull(m.fraction)
        assertEquals(2, m.sectionIndex)
    }

    @Test fun relocate_fractionZero_isPreserved() {
        val m = FoliateMessageParser.parse("""{"name":"relocate","detail":{"fraction":0.0}}""") as FoliateMessage.Relocate
        assertEquals(0.0, m.fraction!!, 0.0)
    }

    @Test fun error_messageAndType() {
        assertEquals(
            FoliateMessage.Error("open failed: x", "open"),
            FoliateMessageParser.parse("""{"name":"error","detail":{"message":"open failed: x","type":"open"}}"""),
        )
    }

    @Test fun error_missingMessage_defaultsUnknown() {
        assertEquals(FoliateMessage.Error("unknown", null), FoliateMessageParser.parse("""{"name":"error","detail":{}}"""))
    }

    @Test fun unknownName_mapsToOther() {
        assertEquals(FoliateMessage.Other("selection"), FoliateMessageParser.parse("""{"name":"selection","detail":{"text":"hi"}}"""))
        assertEquals(FoliateMessage.Other("tts-ssml"), FoliateMessageParser.parse("""{"name":"tts-ssml"}"""))
    }

    @Test fun malformedJson_returnsNull() {
        assertNull(FoliateMessageParser.parse("not json"))
        assertNull(FoliateMessageParser.parse("""{"name":"relocate","detail":{"""))
        assertNull(FoliateMessageParser.parse(""))
    }

    @Test fun nonObjectJson_returnsNull() {
        assertNull(FoliateMessageParser.parse("""["relocate"]"""))
        assertNull(FoliateMessageParser.parse("""42"""))
        assertNull(FoliateMessageParser.parse(""""relocate""""))
    }

    @Test fun missingOrEmptyName_returnsNull() {
        assertNull(FoliateMessageParser.parse("""{"detail":{"x":1}}"""))
        assertNull(FoliateMessageParser.parse("""{"name":"","detail":{}}"""))
    }

    // --- hostile / wrong-type scalar payloads must degrade safely (Gate-4) ---

    @Test fun nonStringName_returnsNull() {
        assertNull(FoliateMessageParser.parse("""{"name":42,"detail":{}}"""))
        assertNull(FoliateMessageParser.parse("""{"name":true,"detail":{}}"""))
        assertNull(FoliateMessageParser.parse("""{"name":null,"detail":{}}"""))
    }

    @Test fun blankName_returnsNull() {
        assertNull(FoliateMessageParser.parse("""{"name":"   ","detail":{}}"""))
    }

    @Test fun numericOrNullTitle_isAbsent() {
        assertEquals(FoliateMessage.BookReady(null, 5), FoliateMessageParser.parse("""{"name":"book-ready","detail":{"title":42,"sections":5}}"""))
        assertEquals(FoliateMessage.BookReady(null, 5), FoliateMessageParser.parse("""{"name":"book-ready","detail":{"title":null,"sections":5}}"""))
    }

    @Test fun nonFiniteOrStringFraction_isRejected() {
        // "NaN"/"Infinity" as JSON strings, and a quoted number, must not become a fraction.
        assertNull((FoliateMessageParser.parse("""{"name":"relocate","detail":{"fraction":"NaN"}}""") as FoliateMessage.Relocate).fraction)
        assertNull((FoliateMessageParser.parse("""{"name":"relocate","detail":{"fraction":"Infinity"}}""") as FoliateMessage.Relocate).fraction)
        assertNull((FoliateMessageParser.parse("""{"name":"relocate","detail":{"fraction":"0.5"}}""") as FoliateMessage.Relocate).fraction)
    }

    @Test fun quotedNumericSectionIndex_isRejected_defaults() {
        val m = FoliateMessageParser.parse("""{"name":"relocate","detail":{"sectionIndex":"7"}}""") as FoliateMessage.Relocate
        assertEquals(0, m.sectionIndex) // quoted string not accepted → default
    }

    @Test fun nonObjectDetail_degradesToEmpty() {
        assertEquals(FoliateMessage.BookReady(null, 0), FoliateMessageParser.parse("""{"name":"book-ready","detail":null}"""))
        assertEquals(FoliateMessage.BookReady(null, 0), FoliateMessageParser.parse("""{"name":"book-ready","detail":[1,2]}"""))
        assertEquals(FoliateMessage.BookReady(null, 0), FoliateMessageParser.parse("""{"name":"book-ready","detail":7}"""))
    }

    @Test fun extraUnknownKeys_areIgnored() {
        val m = FoliateMessageParser.parse(
            """{"name":"relocate","detail":{"cfi":"/2","fraction":0.1,"tocLabel":"Ch 1","locationCurrent":7},"ts":123}""",
        )
        assertTrue(m is FoliateMessage.Relocate)
        assertEquals("/2", (m as FoliateMessage.Relocate).cfi)
    }

    // --- feature #135 WI-2: the awaited-goTo ack channel (goto-ack) ---

    @Test fun gotoAck_ok_full() {
        val m = FoliateMessageParser.parse(
            """{"name":"goto-ack","detail":{"id":"g7","ok":true,"cfi":"/6/4!/4/2","fraction":0.42}}""",
        )
        assertEquals(FoliateMessage.GoToAck("g7", true, "/6/4!/4/2", 0.42), m)
    }

    @Test fun gotoAck_failure_noPosition() {
        val m = FoliateMessageParser.parse("""{"name":"goto-ack","detail":{"id":"g7","ok":false}}""")
        assertEquals(FoliateMessage.GoToAck("g7", false, null, null), m)
    }

    @Test fun gotoAck_okDefaultsFalse_whenAbsent() {
        val m = FoliateMessageParser.parse("""{"name":"goto-ack","detail":{"id":"g7"}}""") as FoliateMessage.GoToAck
        assertEquals(false, m.ok)
        assertEquals("g7", m.id)
    }

    @Test fun gotoAck_missingOrBlankId_returnsNull() {
        // Without a request id the host cannot resolve the matching deferred — the whole message is useless.
        assertNull(FoliateMessageParser.parse("""{"name":"goto-ack","detail":{"ok":true}}"""))
        assertNull(FoliateMessageParser.parse("""{"name":"goto-ack","detail":{"id":"","ok":true}}"""))
        assertNull(FoliateMessageParser.parse("""{"name":"goto-ack","detail":{"id":42,"ok":true}}"""))
    }

    @Test fun gotoAck_nonBooleanOk_isFalse() {
        // A quoted "true" / numeric 1 must not read as a truthy ok — a hostile ack can't force a false success.
        assertEquals(false, (FoliateMessageParser.parse("""{"name":"goto-ack","detail":{"id":"g","ok":"true"}}""") as FoliateMessage.GoToAck).ok)
        assertEquals(false, (FoliateMessageParser.parse("""{"name":"goto-ack","detail":{"id":"g","ok":1}}""") as FoliateMessage.GoToAck).ok)
    }

    @Test fun gotoAck_nonFiniteOrStringFraction_isNull() {
        assertNull((FoliateMessageParser.parse("""{"name":"goto-ack","detail":{"id":"g","ok":true,"fraction":"0.5"}}""") as FoliateMessage.GoToAck).fraction)
        assertNull((FoliateMessageParser.parse("""{"name":"goto-ack","detail":{"id":"g","ok":true,"fraction":"NaN"}}""") as FoliateMessage.GoToAck).fraction)
    }

    // --- feature #140 WI-1: `book-ready` stops discarding the `toc` tree ---

    @Test fun bookReady_populatesTocTree() {
        val m = FoliateMessageParser.parse(
            """{"name":"book-ready","detail":{"title":"被偷走的勇气","sections":85,"toc":[
                 {"label":"Part I","href":"p1.xhtml","subitems":[
                   {"label":"第一章","href":"c1.xhtml#a","subitems":[]}
                 ]},
                 {"label":"Part II","href":"p2.xhtml","subitems":[]}
               ]}}""",
        ) as FoliateMessage.BookReady

        assertEquals("被偷走的勇气", m.title)
        assertEquals(85, m.sectionTotal)
        assertEquals(listOf("Part I", "Part II"), m.toc.map { it.label })
        assertEquals(listOf("第一章"), m.toc[0].subitems.map { it.label })
        assertEquals("c1.xhtml#a", m.toc[0].subitems[0].href)
    }

    @Test fun bookReady_withoutToc_stillParsesTitleAndSections() {
        // Back-compat: every message that carries no `toc` behaves exactly as before #140.
        assertEquals(
            FoliateMessage.BookReady("Moby-Dick", 42),
            FoliateMessageParser.parse("""{"name":"book-ready","detail":{"title":"Moby-Dick","sections":42}}"""),
        )
        val nulled = FoliateMessageParser.parse(
            """{"name":"book-ready","detail":{"title":"Moby-Dick","sections":42,"toc":null}}""",
        ) as FoliateMessage.BookReady
        assertTrue(nulled.toc.isEmpty())
        val notAnArray = FoliateMessageParser.parse(
            """{"name":"book-ready","detail":{"title":"Moby-Dick","sections":42,"toc":{"label":"x"}}}""",
        ) as FoliateMessage.BookReady
        assertTrue(notAnArray.toc.isEmpty())
    }

    @Test fun hostileTocPayload_isParsedWithoutThrowing() {
        // SCOPE: this asserts the PAYLOAD degrades safely — NOT that a pathological book opens.
        // foliate's own recursive assignIDs/flatten/serializeTOC run inside the SHA-pinned bundle
        // before `book-ready` is ever posted; a failure there posts `error` instead, and no
        // Kotlin-side bound can change that (plan §5.4, follow-up F6).
        val deep = StringBuilder()
        repeat(200) { deep.append("""[{"label":"L$it","href":"h$it","subitems":""") }
        deep.append("[]")
        repeat(200) { deep.append("}]") }

        val m = FoliateMessageParser.parse(
            """{"name":"book-ready","detail":{"title":"hostile","sections":3,"toc":$deep}}""",
        ) as FoliateMessage.BookReady
        assertEquals("hostile", m.title)
        assertEquals(3, m.sectionTotal)
        assertEquals(FoliateTocParser.MAX_TOC_DEPTH, tocDepthOf(m.toc))

        // Junk element types inside the array, and a non-array toc, degrade too.
        val junk = FoliateMessageParser.parse(
            """{"name":"book-ready","detail":{"sections":1,"toc":[1,"x",null,[],{"label":"ok","href":"o"}]}}""",
        ) as FoliateMessage.BookReady
        assertEquals(listOf("ok"), junk.toc.map { it.label })
    }

    // --- feature #140 WI-4: `relocate` stops discarding `tocHref` ---

    @Test fun relocate_populatesTocHref() {
        val m = FoliateMessageParser.parse(
            """{"name":"relocate","detail":{"cfi":"/6/4!/4/2","fraction":0.42,"sectionIndex":3,
                 "sectionTotal":85,"tocLabel":"第一章","tocHref":"kindle:pos:fid:0001:off:0000000123"}}""",
        ) as FoliateMessage.Relocate
        assertEquals("kindle:pos:fid:0001:off:0000000123", m.tocHref)
        // The siblings are untouched by the new field.
        assertEquals(FoliateMessage.Relocate("/6/4!/4/2", 0.42, 3, 85, "kindle:pos:fid:0001:off:0000000123"), m)
    }

    @Test fun relocate_tocHrefPreservesDecodedStringExactly() {
        // The href is matched downstream (foliateTocIndexFor) by exact Kotlin String equality after
        // JSON decoding, so the parser must apply no further transformation — no trimming, case
        // folding, re-encoding, fragment/query stripping or Unicode normalization. Each shape is
        // asserted verbatim.
        val shapes = listOf(
            "c1.xhtml#s2",                        // fragment
            "c1.xhtml?v=2#s2",                    // query + fragment
            "  c1.xhtml  ",                       // surrounding whitespace is CONTENT, not noise
            "第二章.xhtml#节2",                     // decodeURI'd non-ASCII (foliate-bundle.js:1753)
            "c1%20a.xhtml",                       // still-encoded form stays encoded
            "filepos:0000001234",                 // MOBI6
            "café.xhtml",                    // NFC — precomposed U+00E9
            "café.xhtml",                   // NFD — e + U+0301, canonically equivalent to the
                                                  //   line above but a DIFFERENT href: the parser
                                                  //   must not Unicode-normalize either into the other
            "📕.xhtml",                            // surrogate pair
            """a"b\c.xhtml""",                    // JSON-escaped characters round-trip
        )
        // Every shape must be a DISTINCT string — otherwise the NFC/NFD pair (canonically equivalent,
        // rendered identically) could be silently normalized by an editor and the pair would degrade
        // into one shape asserted twice. This fails loudly instead.
        assertEquals(shapes.size, shapes.distinct().size)

        for (href in shapes) {
            val encoded = href.replace("\\", "\\\\").replace("\"", "\\\"")
            val m = FoliateMessageParser.parse(
                """{"name":"relocate","detail":{"fraction":0.5,"tocHref":"$encoded"}}""",
            ) as FoliateMessage.Relocate
            assertEquals(href, m.tocHref)
        }
    }

    @Test fun relocate_withoutTocHref_isNull_otherFieldsUnchanged() {
        // Back-compat: a pre-#140-shaped relocate parses EXACTLY as before, field for field. Asserted
        // both per-field and by whole-value equality, so a change that dropped or reordered a sibling
        // while adding tocHref cannot pass.
        val m = FoliateMessageParser.parse(
            """{"name":"relocate","detail":{"cfi":"/6/4!/4/2","fraction":0.42,"sectionIndex":3,"sectionTotal":85}}""",
        ) as FoliateMessage.Relocate
        assertNull(m.tocHref)
        assertEquals("/6/4!/4/2", m.cfi)
        assertEquals(0.42, m.fraction!!, 0.0)
        assertEquals(3, m.sectionIndex)
        assertEquals(85, m.sectionTotal)
        assertEquals(FoliateMessage.Relocate("/6/4!/4/2", 0.42, 3, 85, null), m)

        // The documented defaults for an empty detail are unchanged too (sectionIndex 0, total 1).
        assertEquals(
            FoliateMessage.Relocate(null, null, 0, 1, null),
            FoliateMessageParser.parse("""{"name":"relocate","detail":{}}"""),
        )
        // ...and a message carrying every OTHER field but no tocHref keeps them all.
        val siblings = FoliateMessageParser.parse(
            """{"name":"relocate","detail":{"cfi":null,"fraction":0.0,"sectionIndex":7,"sectionTotal":9,
                 "tocLabel":"Ch 7","locationCurrent":3,"locationTotal":11}}""",
        ) as FoliateMessage.Relocate
        assertNull(siblings.tocHref)
        assertNull(siblings.cfi)
        assertEquals(0.0, siblings.fraction!!, 0.0)
        assertEquals(7, siblings.sectionIndex)
        assertEquals(9, siblings.sectionTotal)
    }

    @Test fun relocate_blankTocHref_isNull() {
        // foliate posts `tocItem?.href ?? null`; a blank / absent / wrong-typed href means "unknown
        // chapter", which the index helper answers with row 0 — never a match on a blank TOC row.
        // Every case also re-asserts a sibling, so a degenerate href can't take the rest down with it.
        val blanks = listOf(
            "\"tocHref\":\"\"",                    // empty string
            "\"tocHref\":\"   \"",                 // whitespace only
            "\"tocHref\":\"\\n\\t\"",              // whitespace-only escapes
            "\"tocHref\":null",                    // JSON null (what foliate posts with no tocItem)
            "\"tocHref\":42",                      // wrong scalar type
            "\"tocHref\":true",
            "\"tocHref\":[\"a\"]",                 // wrong container type
            "\"tocHref\":{\"href\":\"c1.xhtml\"}",
        )
        for (field in blanks) {
            val m = FoliateMessageParser.parse(
                """{"name":"relocate","detail":{"cfi":"/2","fraction":0.25,"sectionIndex":4,"sectionTotal":6,$field}}""",
            ) as FoliateMessage.Relocate
            assertNull("tocHref for $field", m.tocHref)
            assertEquals("cfi for $field", "/2", m.cfi)
            assertEquals("fraction for $field", 0.25, m.fraction!!, 0.0)
            assertEquals("sectionIndex for $field", 4, m.sectionIndex)
            assertEquals("sectionTotal for $field", 6, m.sectionTotal)
        }
    }

    @Test fun tocHrefOnOtherMessages_isNotConsumed() {
        // `tocHref` belongs to `relocate` only — a book-ready / goto-ack carrying one is unaffected.
        val book = FoliateMessageParser.parse(
            """{"name":"book-ready","detail":{"title":"T","sections":4,"tocHref":"c1.xhtml"}}""",
        )
        assertEquals(FoliateMessage.BookReady("T", 4), book)
        val ack = FoliateMessageParser.parse(
            """{"name":"goto-ack","detail":{"id":"g1","ok":true,"tocHref":"c1.xhtml"}}""",
        )
        assertEquals(FoliateMessage.GoToAck("g1", true, null, null), ack)
    }

    private fun tocDepthOf(root: List<FoliateTocItem>): Int {
        var level = root
        var depth = 0
        while (level.isNotEmpty()) {
            depth++
            level = level[0].subitems
        }
        return depth
    }
}
