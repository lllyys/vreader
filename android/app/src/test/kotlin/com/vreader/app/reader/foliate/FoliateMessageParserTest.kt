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
        // NOTE: `selection` used to be asserted here (feature #126). Feature #142 WI-1 TYPES it — see
        // the selection / annotation-show / create-overlay section below. Names this reader still
        // ignores (tts-*, search-*, tap, section-load, external-link, …) keep mapping to Other.
        assertEquals(FoliateMessage.Other("tts-ssml"), FoliateMessageParser.parse("""{"name":"tts-ssml"}"""))
        assertEquals(FoliateMessage.Other("tap"), FoliateMessageParser.parse("""{"name":"tap","detail":{"x":10}}"""))
        assertEquals(
            FoliateMessage.Other("section-load"),
            FoliateMessageParser.parse("""{"name":"section-load","detail":{"index":3}}"""),
        )
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

    // --- feature #142 WI-1: selection / annotation-show / create-overlay become TYPED -----------
    //
    // The PER-MESSAGE-NAME raw ceiling that runs BEFORE this parser lives in FoliateBridgePolicy and
    // is pinned by FoliateBridgePolicyTest — including the invariant that the raw ceiling never
    // silently shrinks the field caps asserted here.
    //
    // Control characters in fixtures are built from CHAR CODES rather than written as source escapes:
    // a literal NUL in a .kt file makes it a binary blob to every text tool in the repo.

    @Test fun selection_full_parsesTextCfiIndexAndRect() {
        val m = FoliateMessageParser.parse(
            """{"name":"selection","detail":{"collapsed":false,"text":"被偷走的勇气","cfi":"epubcfi(/6/14!/4/2,/1:0,/1:6)",
                 "index":6,"rect":{"x":12.5,"y":40.25,"width":180.5,"height":22.0}}}""",
        )
        assertEquals(
            FoliateMessage.Selection(
                text = "被偷走的勇气",
                cfi = "epubcfi(/6/14!/4/2,/1:0,/1:6)",
                sectionIndex = 6,
                rect = SelectionRect(12.5, 40.25, 180.5, 22.0),
            ),
            m,
        )
    }

    @Test fun selection_collapsed_isSelectionCleared() {
        assertEquals(
            FoliateMessage.SelectionCleared,
            FoliateMessageParser.parse("""{"name":"selection","detail":{"collapsed":true}}"""),
        )
        // The bundle posts ONLY `{collapsed:true}`, but a payload that also carries stale fields is
        // still a clear — collapsed wins, and no Selection is manufactured from the leftovers.
        assertEquals(
            FoliateMessage.SelectionCleared,
            FoliateMessageParser.parse("""{"name":"selection","detail":{"collapsed":true,"text":"x","cfi":"/6/4"}}"""),
        )
    }

    @Test fun selection_nonBooleanCollapsed_isNotAClear() {
        // Strict `bool`: a quoted "true" / numeric 1 must NOT read as collapsed — otherwise a hostile
        // payload could suppress a real selection. Such a payload falls through to the Selection
        // branch, which then needs a usable text + cfi.
        for (collapsed in listOf(""""true"""", "1", """"1"""", "null", """["true"]""")) {
            assertEquals(
                "collapsed=$collapsed",
                FoliateMessage.Selection("hi", "/6/4!/2", 0, null),
                FoliateMessageParser.parse(
                    """{"name":"selection","detail":{"collapsed":$collapsed,"text":"hi","cfi":"/6/4!/2"}}""",
                ),
            )
        }
    }

    @Test fun selection_collapsedFalseWithoutUsableText_returnsNull() {
        // A selection with no text is unusable — drop the whole message rather than emit a blank one.
        for (text in listOf("""""""", """"   """", "null", "42", "true", """["a"]""", """{"t":"a"}""")) {
            assertNull(
                "text=$text",
                FoliateMessageParser.parse("""{"name":"selection","detail":{"collapsed":false,"text":$text,"cfi":"/6/4"}}"""),
            )
        }
        // ...including a text that is only escaped whitespace (tab / LF / CR).
        val onlyWhitespace = "" + 9.toChar() + 10.toChar() + 13.toChar()
        assertNull(
            FoliateMessageParser.parse(
                """{"name":"selection","detail":{"collapsed":false,"text":"${jsonEscape(onlyWhitespace)}","cfi":"/6/4"}}""",
            ),
        )
        assertNull(FoliateMessageParser.parse("""{"name":"selection","detail":{"collapsed":false,"cfi":"/6/4"}}"""))
        assertNull(FoliateMessageParser.parse("""{"name":"selection","detail":{}}"""))
        assertNull(FoliateMessageParser.parse("""{"name":"selection"}"""))
    }

    @Test fun selection_collapsedFalseWithoutUsableCfi_returnsNull() {
        // Without a CFI the selection can never become an anchor or a decoration — drop it.
        for (cfi in listOf("""""""", """"   """", "null", "42", "true", """["a"]""", """{"c":"a"}""")) {
            assertNull(
                "cfi=$cfi",
                FoliateMessageParser.parse("""{"name":"selection","detail":{"collapsed":false,"text":"hi","cfi":$cfi}}"""),
            )
        }
        assertNull(FoliateMessageParser.parse("""{"name":"selection","detail":{"collapsed":false,"text":"hi"}}"""))
    }

    @Test fun selection_index_defaultsZero_andRejectsQuotedNumerics() {
        assertEquals(0, sel("""{"collapsed":false,"text":"a","cfi":"/6/4"}""").sectionIndex)
        assertEquals(0, sel("""{"collapsed":false,"text":"a","cfi":"/6/4","index":0}""").sectionIndex)
        assertEquals(84, sel("""{"collapsed":false,"text":"a","cfi":"/6/4","index":84}""").sectionIndex)
        // A quoted numeric is not a number (the `relocate.sectionIndex` convention) → default.
        assertEquals(0, sel("""{"collapsed":false,"text":"a","cfi":"/6/4","index":"7"}""").sectionIndex)
        assertEquals(0, sel("""{"collapsed":false,"text":"a","cfi":"/6/4","index":null}""").sectionIndex)
    }

    @Test fun selection_outOfRangeIndex_isCarriedVerbatim() {
        // The parser does NOT invent a spine bound it cannot know — this message carries no section
        // total, and `relocate` applies no such bound either. Consumers key decorations BY index and
        // treat an index no section ever mounts as a no-op, so a nonsense index is inert, not unsafe.
        assertEquals(-1, sel("""{"collapsed":false,"text":"a","cfi":"/6/4","index":-1}""").sectionIndex)
        assertEquals(Int.MAX_VALUE, sel("""{"collapsed":false,"text":"a","cfi":"/6/4","index":2147483647}""").sectionIndex)
    }

    @Test fun selection_rect_isNullWhenAbsentPartialOrNonFinite() {
        // The rect is ADVISORY (the host computes the popover anchor from the live layout instead), so
        // every degenerate shape degrades to `rect == null` — never a throw, never a partial rect.
        val bad = listOf(
            "",                                                        // absent
            ""","rect":null""",
            ""","rect":{"x":1.0,"y":2.0,"width":3.0}""",                // missing height
            ""","rect":{"y":2.0,"width":3.0,"height":4.0}""",           // missing x
            ""","rect":{"x":"1.0","y":2.0,"width":3.0,"height":4.0}""", // quoted numeric
            ""","rect":{"x":"NaN","y":2.0,"width":3.0,"height":4.0}""",
            ""","rect":{"x":1.0,"y":2.0,"width":3.0,"height":"Infinity"}""",
            ""","rect":[1,2,3,4]""",                                    // wrong container
            ""","rect":7""",
            ""","rect":"1,2,3,4"""",
            ""","rect":{}""",
        )
        for (fragment in bad) {
            val m = sel("""{"collapsed":false,"text":"hi","cfi":"/6/4","index":3$fragment}""")
            assertNull("rect for [$fragment]", m.rect)
            // ...and a degenerate rect never takes its siblings down with it.
            assertEquals("hi", m.text)
            assertEquals("/6/4", m.cfi)
            assertEquals(3, m.sectionIndex)
        }
    }

    @Test fun selection_rect_zeroAndNegativeValuesArePreserved() {
        // A zero-area rect is a REAL layout outcome (a range ending at a line break) and negative
        // coordinates are real too (a selection above the section viewport). Both are data, not
        // corruption — the parser rejects only non-finite / wrong-typed members.
        assertEquals(
            SelectionRect(0.0, 0.0, 0.0, 0.0),
            sel("""{"collapsed":false,"text":"a","cfi":"/6/4","rect":{"x":0,"y":0,"width":0,"height":0}}""").rect,
        )
        assertEquals(
            SelectionRect(-12.0, -3.5, 100.0, 18.0),
            sel("""{"collapsed":false,"text":"a","cfi":"/6/4","rect":{"x":-12,"y":-3.5,"width":100,"height":18}}""").rect,
        )
    }

    @Test fun selection_textAtFieldCap_isAccepted_oneOverIsDropped() {
        val atCap = "x".repeat(FoliateMessageParser.MAX_SELECTION_CHARS)
        assertEquals(atCap, sel("""{"collapsed":false,"text":"$atCap","cfi":"/6/4"}""").text)
        val overCap = "x".repeat(FoliateMessageParser.MAX_SELECTION_CHARS + 1)
        // Dropped WHOLESALE, never truncated: a truncated quote corrupts profileKey + the backup row.
        assertNull(
            FoliateMessageParser.parse("""{"name":"selection","detail":{"collapsed":false,"text":"$overCap","cfi":"/6/4"}}"""),
        )
    }

    @Test fun selection_cfiAtFieldCap_isAccepted_oneOverIsDropped() {
        val atCap = "c".repeat(FoliateMessageParser.MAX_CFI_CHARS)
        assertEquals(atCap, sel("""{"collapsed":false,"text":"hi","cfi":"$atCap"}""").cfi)
        val overCap = "c".repeat(FoliateMessageParser.MAX_CFI_CHARS + 1)
        // A truncated CFI would resolve to the WRONG range — drop the message instead.
        assertNull(
            FoliateMessageParser.parse("""{"name":"selection","detail":{"collapsed":false,"text":"hi","cfi":"$overCap"}}"""),
        )
    }

    @Test fun selection_capsCountUtf16Units_soAstralTextIsBounded() {
        // "📕" is ONE grapheme but TWO UTF-16 units, and the cap is on String.length. Half a cap's
        // worth of surrogate pairs sits exactly AT the cap; one more pair is over it.
        val atCap = "📕".repeat(FoliateMessageParser.MAX_SELECTION_CHARS / 2)
        assertEquals(FoliateMessageParser.MAX_SELECTION_CHARS, atCap.length)
        assertEquals(atCap, sel("""{"collapsed":false,"text":"$atCap","cfi":"/6/4"}""").text)
        val overCap = atCap + "📕"
        assertNull(
            FoliateMessageParser.parse("""{"name":"selection","detail":{"collapsed":false,"text":"$overCap","cfi":"/6/4"}}"""),
        )
    }

    @Test fun selection_textAndCfiAreCarriedVerbatim() {
        // The quote is persisted, hashed into profileKey via canonicalJson() and written to
        // annotations.json; the CFI is handed straight back to readerAPI.addAnnotation. Neither may be
        // trimmed, normalized, re-encoded or otherwise touched. Each shape is asserted verbatim.
        val texts = listOf(
            "被偷走的勇气", // CJK
            "café", // NFC — precomposed U+00E9
            "cafe" + 0x0301.toChar(), // NFD — e + combining acute: canonically equivalent, DIFFERENT string
            "📕 emoji", // surrogate pair
            "  leading and trailing  ", // surrounding whitespace is CONTENT, not noise
            "line1" + 10.toChar() + "line2" + 9.toChar() + "end", // LF + TAB
            "" + 0.toChar() + "nul" + 1.toChar() + "soh" + 31.toChar(), // C0 controls are not "blank"
            "zero" + 0x200B.toChar() + "width", // zero-width space
            """quote " backslash \ script </script>""",
            "a".repeat(4_000), // long but under the cap
        )
        assertEquals("fixture shapes must be distinct", texts.size, texts.distinct().size)
        for (text in texts) {
            val m = sel("""{"collapsed":false,"text":"${jsonEscape(text)}","cfi":"epubcfi(/6/4!/2,/1:0,/1:3)"}""")
            assertEquals(text, m.text)
        }
        for (cfi in listOf("epubcfi(/6/14!/4/2,/1:0,/1:6)", """a"b\c""", "第一章", "📕")) {
            assertEquals(cfi, sel("""{"collapsed":false,"text":"hi","cfi":"${jsonEscape(cfi)}"}""").cfi)
        }
    }

    @Test fun annotationShow_full_parsesValueAndIndex() {
        assertEquals(
            FoliateMessage.AnnotationShow("epubcfi(/6/14!/4/2,/1:0,/1:6)", 6),
            FoliateMessageParser.parse(
                """{"name":"annotation-show","detail":{"value":"epubcfi(/6/14!/4/2,/1:0,/1:6)","index":6}}""",
            ),
        )
    }

    @Test fun annotationShow_index_defaultsZero() {
        assertEquals(
            FoliateMessage.AnnotationShow("/6/4", 0),
            FoliateMessageParser.parse("""{"name":"annotation-show","detail":{"value":"/6/4"}}"""),
        )
        assertEquals(
            FoliateMessage.AnnotationShow("/6/4", 0),
            FoliateMessageParser.parse("""{"name":"annotation-show","detail":{"value":"/6/4","index":"3"}}"""),
        )
    }

    @Test fun annotationShow_withoutUsableValue_returnsNull() {
        // No CFI → nothing to resolve to a highlight id → the message is useless (the goto-ack rule).
        for (value in listOf("""""""", """"   """", "null", "42", "true", """["a"]""")) {
            assertNull(
                "value=$value",
                FoliateMessageParser.parse("""{"name":"annotation-show","detail":{"value":$value}}"""),
            )
        }
        assertNull(FoliateMessageParser.parse("""{"name":"annotation-show","detail":{"index":2}}"""))
        assertNull(FoliateMessageParser.parse("""{"name":"annotation-show"}"""))
    }

    @Test fun annotationShow_valueAtCfiCap_isAccepted_oneOverIsDropped() {
        val atCap = "c".repeat(FoliateMessageParser.MAX_CFI_CHARS)
        val parsed = FoliateMessageParser.parse("""{"name":"annotation-show","detail":{"value":"$atCap"}}""")
        assertEquals(atCap, (parsed as FoliateMessage.AnnotationShow).value)
        val overCap = "c".repeat(FoliateMessageParser.MAX_CFI_CHARS + 1)
        assertNull(FoliateMessageParser.parse("""{"name":"annotation-show","detail":{"value":"$overCap"}}"""))
    }

    @Test fun createOverlay_carriesIndex_includingZero() {
        assertEquals(FoliateMessage.OverlayCreated(0), FoliateMessageParser.parse("""{"name":"create-overlay","detail":{"index":0}}"""))
        assertEquals(FoliateMessage.OverlayCreated(41), FoliateMessageParser.parse("""{"name":"create-overlay","detail":{"index":41}}"""))
        // No usable index → 0. `create-overlay` carries no other field, so it is never DROPPED: the
        // host re-applies its whole recorded decoration set on it, which is index-independent.
        assertEquals(FoliateMessage.OverlayCreated(0), FoliateMessageParser.parse("""{"name":"create-overlay","detail":{}}"""))
        assertEquals(FoliateMessage.OverlayCreated(0), FoliateMessageParser.parse("""{"name":"create-overlay"}"""))
        assertEquals(FoliateMessage.OverlayCreated(0), FoliateMessageParser.parse("""{"name":"create-overlay","detail":{"index":"4"}}"""))
    }

    @Test fun newMessages_extraUnknownKeysAreIgnored() {
        assertEquals("hi", sel("""{"collapsed":false,"text":"hi","cfi":"/6/4","index":1,"lang":"zh","dir":"ltr"}""").text)
        assertEquals(
            FoliateMessage.OverlayCreated(2),
            FoliateMessageParser.parse("""{"name":"create-overlay","detail":{"index":2,"doc":{"a":1}},"ts":99}"""),
        )
    }

    @Test fun newMessages_nonObjectDetail_degradesToEmpty() {
        // An empty detail leaves selection / annotation-show with no usable field → dropped;
        // create-overlay has no required field → index 0.
        for (detail in listOf("null", "7", """[1,2]""", """"x"""")) {
            assertNull("selection detail=$detail", FoliateMessageParser.parse("""{"name":"selection","detail":$detail}"""))
            assertNull("annotation-show detail=$detail", FoliateMessageParser.parse("""{"name":"annotation-show","detail":$detail}"""))
            assertEquals(
                "create-overlay detail=$detail",
                FoliateMessage.OverlayCreated(0),
                FoliateMessageParser.parse("""{"name":"create-overlay","detail":$detail}"""),
            )
        }
    }

    @Test fun oversizedSelectionPayload_isIgnoredWithoutThrowing() {
        // Defense in depth: even with the raw ceiling bypassed, parse degrades to "ignored" rather
        // than throwing into the WebView callback thread. ~1 MB of text, far past the field cap.
        val huge = "x".repeat(1_000_000)
        assertNull(
            FoliateMessageParser.parse("""{"name":"selection","detail":{"collapsed":false,"text":"$huge","cfi":"/6/4"}}"""),
        )
    }

    @Test fun deeplyNestedSelectionPayload_isIgnoredWithoutThrowing() {
        // Pins the OBSERVED degradation of a within-ceiling but pathologically nested payload: this
        // asserts "nothing throws on the callback thread", NOT a documented kotlinx.serialization
        // depth guard (which is not part of its contract).
        val depth = 2_000
        val nested = "[".repeat(depth) + "]".repeat(depth)
        val raw = """{"name":"selection","detail":{"collapsed":false,"text":"hi","cfi":"/6/4","rect":$nested}}"""
        val outcome = runCatching { FoliateMessageParser.parse(raw) }
        assertTrue("parse must not throw on deep nesting: ${outcome.exceptionOrNull()}", outcome.isSuccess)
        val message = outcome.getOrNull()
        assertTrue(
            "a deeply nested payload must yield a rect-less Selection or nothing, got $message",
            message == null || (message is FoliateMessage.Selection && message.rect == null),
        )
    }

    // --- helpers ------------------------------------------------------------------------------

    /** Parse a `selection` message from its DETAIL object literal, asserting the typed shape. */
    private fun sel(detailJson: String): FoliateMessage.Selection =
        FoliateMessageParser.parse("""{"name":"selection","detail":$detailJson}""") as FoliateMessage.Selection

    /**
     * Minimal JSON string-body escaping for fixture text. Written with char CODES (92 = backslash,
     * 34 = quote) so this source file never itself contains a raw control byte.
     */
    private fun jsonEscape(s: String): String {
        val backslash = 92.toChar()
        return buildString {
            for (c in s) when {
                c == backslash -> { append(backslash); append(backslash) }
                c.code == 34 -> { append(backslash); append(34.toChar()) }
                c.code < 0x20 -> { append(backslash); append('u'); append("%04x".format(c.code)) }
                else -> append(c)
            }
        }
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
