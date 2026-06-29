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
}
