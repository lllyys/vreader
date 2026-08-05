package com.vreader.app.reader.foliate

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Feature #140 WI-1 — the bounded, throw-free `book-ready.toc` tree parser.
 *
 * SCOPE. Every assertion here is about a PAYLOAD, never about a book opening. foliate's own
 * recursive `assignIDs` / `flatten` / `serializeTOC` walks (foliate-bundle.js) run inside
 * `readerAPI.open()` BEFORE Kotlin sees anything, so a TOC pathological enough to break them posts
 * `error` instead of `book-ready` and no Kotlin-side bound can change that. That exposure is
 * pre-existing and unchanged by #140 (plan §5.4, risk R13 / follow-up F6).
 */
class FoliateTocParserTest {

    private fun el(json: String): JsonElement = Json.parseToJsonElement(json)

    // --- happy path -------------------------------------------------------------------------

    @Test fun flatToc_parsesLabelAndHrefInOrder() {
        val items = FoliateTocParser.parse(
            el(
                """[
                  {"label":"Cover","href":"cover.xhtml","subitems":[]},
                  {"label":"Chapter 1","href":"c1.xhtml","subitems":[]},
                  {"label":"Chapter 2","href":"c2.xhtml","subitems":[]}
                ]""",
            ),
        )
        assertEquals(3, items.size)
        assertEquals(listOf("Cover", "Chapter 1", "Chapter 2"), items.map { it.label })
        assertEquals(listOf("cover.xhtml", "c1.xhtml", "c2.xhtml"), items.map { it.href })
        assertTrue(items.all { it.subitems.isEmpty() })
    }

    @Test fun nestedToc_preservesSubitemTree() {
        val items = FoliateTocParser.parse(
            el(
                """[
                  {"label":"Part I","href":"p1.xhtml","subitems":[
                    {"label":"Ch 1","href":"c1.xhtml","subitems":[
                      {"label":"1.1","href":"c1.xhtml#a","subitems":[]}
                    ]},
                    {"label":"Ch 2","href":"c2.xhtml","subitems":[]}
                  ]},
                  {"label":"Part II","href":"p2.xhtml","subitems":[]}
                ]""",
            ),
        )
        assertEquals(2, items.size)
        val partOne = items[0]
        assertEquals("Part I", partOne.label)
        assertEquals(listOf("Ch 1", "Ch 2"), partOne.subitems.map { it.label })
        val chOne = partOne.subitems[0]
        assertEquals(listOf("1.1"), chOne.subitems.map { it.label })
        assertEquals("c1.xhtml#a", chOne.subitems[0].href)
        assertTrue(chOne.subitems[0].subitems.isEmpty())
        assertTrue(items[1].subitems.isEmpty())
    }

    // --- absent / malformed shapes degrade, never throw --------------------------------------

    @Test fun nullElement_yieldsEmptyList() {
        // The `toc` field is absent from the message — a LEGAL input, not an error.
        assertEquals(emptyList<FoliateTocItem>(), FoliateTocParser.parse(null))
    }

    @Test fun jsonNullElement_yieldsEmptyList() {
        assertEquals(emptyList<FoliateTocItem>(), FoliateTocParser.parse(JsonNull))
        assertEquals(emptyList<FoliateTocItem>(), FoliateTocParser.parse(el("null")))
    }

    @Test fun tocIsNotAnArray_yieldsEmptyList() {
        assertEquals(emptyList<FoliateTocItem>(), FoliateTocParser.parse(el("""{"label":"x"}""")))
        assertEquals(emptyList<FoliateTocItem>(), FoliateTocParser.parse(el(""""c1.xhtml"""")))
        assertEquals(emptyList<FoliateTocItem>(), FoliateTocParser.parse(el("42")))
        assertEquals(emptyList<FoliateTocItem>(), FoliateTocParser.parse(el("true")))
    }

    @Test fun tocElementIsNotAnObject_isSkipped_siblingsSurvive() {
        val items = FoliateTocParser.parse(
            el(
                """[
                  {"label":"A","href":"a.xhtml","subitems":[]},
                  "not-an-object",
                  42,
                  null,
                  ["nested","array"],
                  {"label":"B","href":"b.xhtml","subitems":[]}
                ]""",
            ),
        )
        assertEquals(listOf("A", "B"), items.map { it.label })
    }

    @Test fun subitemsMissingOrNullOrNotAnArray_treatedAsNoChildren() {
        val items = FoliateTocParser.parse(
            el(
                """[
                  {"label":"missing","href":"m.xhtml"},
                  {"label":"null","href":"n.xhtml","subitems":null},
                  {"label":"object","href":"o.xhtml","subitems":{"label":"ghost","href":"g"}},
                  {"label":"string","href":"s.xhtml","subitems":"nope"},
                  {"label":"number","href":"i.xhtml","subitems":7}
                ]""",
            ),
        )
        assertEquals(5, items.size)
        assertTrue(items.all { it.subitems.isEmpty() })
        assertEquals(listOf("missing", "null", "object", "string", "number"), items.map { it.label })
    }

    @Test fun labelAndHrefOfWrongTypeOrAbsent_degradeToEmptyString() {
        val items = FoliateTocParser.parse(
            el(
                """[
                  {"subitems":[]},
                  {"label":42,"href":true,"subitems":[]},
                  {"label":null,"href":null,"subitems":[]},
                  {"label":{"a":1},"href":["x"],"subitems":[]}
                ]""",
            ),
        )
        assertEquals(4, items.size)
        assertTrue(items.all { it.label == "" && it.href == "" })
    }

    // --- verbatim preservation (the provider, not the parser, filters) -----------------------

    @Test fun blankLabelAndBlankHref_arePreservedVerbatim_filteringIsTheProvidersJob() {
        val items = FoliateTocParser.parse(
            el(
                """[
                  {"label":"","href":"","subitems":[{"label":"child","href":"c.xhtml","subitems":[]}]},
                  {"label":"   ","href":"  \t ","subitems":[]},
                  {"label":"  padded  ","href":"  p.xhtml  ","subitems":[]}
                ]""",
            ),
        )
        assertEquals(3, items.size)
        // Empty stays empty — and the blank-href node's children are NOT dropped here; the
        // skip-but-recurse policy is FoliateTocProvider's (WI-2), not the parser's.
        assertEquals("", items[0].label)
        assertEquals("", items[0].href)
        assertEquals(listOf("child"), items[0].subitems.map { it.label })
        // Whitespace-only and padded values survive byte-for-byte — no trimming in the parser.
        assertEquals("   ", items[1].label)
        assertEquals("  \t ", items[1].href)
        assertEquals("  padded  ", items[2].label)
        assertEquals("  p.xhtml  ", items[2].href)
    }

    @Test fun cjkAndRtlLabels_areByteForBytePreserved() {
        val items = FoliateTocParser.parse(
            el(
                """[
                  {"label":"第一章　序言","href":"c1.xhtml","subitems":[]},
                  {"label":"الفصل الأول","href":"c2.xhtml","subitems":[]},
                  {"label":"פרק ראשון","href":"c3.xhtml","subitems":[]},
                  {"label":"エミリー・ブロンテ 〜嵐が丘〜","href":"c4.xhtml","subitems":[]},
                  {"label":"Ⅶ. Résumé — “quoted”","href":"c5.xhtml","subitems":[]}
                ]""",
            ),
        )
        assertEquals("第一章　序言", items[0].label)
        assertEquals("الفصل الأول", items[1].label)
        assertEquals("פרק ראשון", items[2].label)
        assertEquals("エミリー・ブロンテ 〜嵐が丘〜", items[3].label)
        assertEquals("Ⅶ. Résumé — “quoted”", items[4].label)
    }

    @Test fun hrefWithFragmentQueryOrNonAscii_isPreservedByteForByte() {
        val items = FoliateTocParser.parse(
            el(
                """[
                  {"label":"frag","href":"text/part0007.html#filepos123","subitems":[]},
                  {"label":"query","href":"text/ch.xhtml?v=2&x=1","subitems":[]},
                  {"label":"both","href":"text/ch.xhtml?v=2#sec-3","subitems":[]},
                  {"label":"cjk","href":"文本/第一章.xhtml#序","subitems":[]},
                  {"label":"kf8","href":"kindle:pos:fid:0021:off:0000001234","subitems":[]},
                  {"label":"mobi6","href":"filepos:0000012345","subitems":[]},
                  {"label":"pct","href":"text/a%20b.xhtml","subitems":[]},
                  {"label":"space","href":"text/a b.xhtml","subitems":[]}
                ]""",
            ),
        )
        assertEquals("text/part0007.html#filepos123", items[0].href)
        assertEquals("text/ch.xhtml?v=2&x=1", items[1].href)
        assertEquals("text/ch.xhtml?v=2#sec-3", items[2].href)
        assertEquals("文本/第一章.xhtml#序", items[3].href)
        assertEquals("kindle:pos:fid:0021:off:0000001234", items[4].href)
        assertEquals("filepos:0000012345", items[5].href)
        assertEquals("text/a%20b.xhtml", items[6].href)
        assertEquals("text/a b.xhtml", items[7].href)
    }

    @Test fun labelWithEmbeddedNewline_isPreserved_sheetNormalizesAtRender() {
        val items = FoliateTocParser.parse(
            el("""[{"label":"Chapter 1\nThe Beginning\r\n","href":"c1.xhtml\t","subitems":[]}]"""),
        )
        assertEquals("Chapter 1\nThe Beginning\r\n", items[0].label)
        assertEquals("c1.xhtml\t", items[0].href)
    }

    // --- bounds ------------------------------------------------------------------------------

    @Test fun deeplyNestedToc_doesNotOverflow_andDropsBeyondMaxDepth() {
        // A 200-deep synthetic payload. The assertion is about the DROP-BEYOND-MAX-DEPTH
        // behaviour, not about "it didn't crash" — a green JVM run is weak evidence for ART,
        // whose stack budget differs; WI-7 re-runs the payload on-device.
        val items = FoliateTocParser.parse(el(deepTocJson(200)))

        val labels = mutableListOf<String>()
        var level = items
        while (level.isNotEmpty()) {
            labels += level[0].label
            level = level[0].subitems
        }
        assertEquals(FoliateTocParser.MAX_TOC_DEPTH, labels.size)
        assertEquals((0 until FoliateTocParser.MAX_TOC_DEPTH).map { "L$it" }, labels)
    }

    @Test fun exactlyMaxDepth_isFullyKept() {
        val items = FoliateTocParser.parse(el(deepTocJson(FoliateTocParser.MAX_TOC_DEPTH)))
        var level = items
        var depth = 0
        while (level.isNotEmpty()) {
            depth++
            level = level[0].subitems
        }
        assertEquals(FoliateTocParser.MAX_TOC_DEPTH, depth)
    }

    @Test fun overMaxEntries_rejectsWholeToc_neverTruncates() {
        val items = FoliateTocParser.parse(el(flatTocJson(FoliateTocParser.MAX_TOC_ENTRIES + 1)))
        // EMPTY, not merely bounded: reject-whole and silently-truncate both leave <= MAX rows,
        // so only an emptiness assertion can tell them apart.
        assertTrue("over-cap TOC must be rejected whole, got ${items.size} rows", items.isEmpty())
    }

    @Test fun exactlyMaxEntries_isKept() {
        val items = FoliateTocParser.parse(el(flatTocJson(FoliateTocParser.MAX_TOC_ENTRIES)))
        assertEquals(FoliateTocParser.MAX_TOC_ENTRIES, items.size)
        assertEquals("c0", items.first().label)
        assertEquals("c${FoliateTocParser.MAX_TOC_ENTRIES - 1}", items.last().label)
    }

    @Test fun entryCapCountsNestedRows_notJustTopLevelOnes() {
        val half = FoliateTocParser.MAX_TOC_ENTRIES / 2
        // half parents x (itself + 1 child) == MAX_TOC_ENTRIES exactly → kept.
        val atCap = FoliateTocParser.parse(el(parentWithOneChildJson(half)))
        assertEquals(half, atCap.size)
        assertTrue(atCap.all { it.subitems.size == 1 })
        // One more parent → MAX_TOC_ENTRIES + 2 rows → the WHOLE toc is rejected.
        val overCap = FoliateTocParser.parse(el(parentWithOneChildJson(half + 1)))
        assertTrue("nested rows must count toward the cap, got ${overCap.size} rows", overCap.isEmpty())
    }

    @Test fun skippedNonObjectSiblingsDoNotConsumeTheEntryBudget() {
        // MAX entries interleaved with junk siblings still parses fully.
        val n = FoliateTocParser.MAX_TOC_ENTRIES
        val json = (0 until n).joinToString(",", "[", "]") { """0,{"label":"c$it","href":"h$it","subitems":[]}""" }
        val items = FoliateTocParser.parse(el(json))
        assertEquals(n, items.size)
    }

    // --- fixtures ----------------------------------------------------------------------------

    /** `[{L0,[{L1,[ … ]}]}]` nested `depth` levels deep. */
    private fun deepTocJson(depth: Int): String {
        val sb = StringBuilder()
        repeat(depth) { i -> sb.append("""[{"label":"L$i","href":"h$i","subitems":""") }
        sb.append("[]")
        repeat(depth) { sb.append("}]") }
        return sb.toString()
    }

    private fun flatTocJson(n: Int): String =
        (0 until n).joinToString(",", "[", "]") { """{"label":"c$it","href":"h$it","subitems":[]}""" }

    private fun parentWithOneChildJson(parents: Int): String =
        (0 until parents).joinToString(",", "[", "]") {
            """{"label":"p$it","href":"p$it","subitems":[{"label":"k$it","href":"k$it","subitems":[]}]}"""
        }
}
