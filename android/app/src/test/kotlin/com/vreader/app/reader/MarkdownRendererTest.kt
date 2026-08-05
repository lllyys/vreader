package com.vreader.app.reader

import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Feature #112 (Android Markdown reader) — the AUTHORITATIVE style proof. The
 * instrumented Compose test can only see rendered text, not span ranges; this JVM test
 * pins the exact `AnnotatedString` span offsets + `SpanStyle` attributes the renderer
 * produces for the v1 single-line CommonMark subset (line-chunk → AnnotatedString).
 */
class MarkdownRendererTest {
    private fun render(s: String) = MarkdownRenderer.render(s)

    // --- Headers: marker consumed, Bold + larger size over the heading text. ---

    @Test fun h1_dropsMarker_boldAndLarger() {
        val a = render("# Hello")
        assertEquals("Hello", a.text)
        val span = a.spanStyles.single()
        assertEquals(0, span.start); assertEquals(5, span.end)
        assertEquals(FontWeight.Bold, span.item.fontWeight)
        assertNotNull("heading sets a font size", span.item.fontSize)
    }

    @Test fun h2_isSmallerThanH1() {
        val h1 = render("# H").spanStyles.single().item.fontSize
        val h2 = render("## H").spanStyles.single().item.fontSize
        val h3 = render("### H").spanStyles.single().item.fontSize
        assertTrue("h1 > h2 > h3", h1.value > h2.value && h2.value > h3.value)
    }

    @Test fun hashWithoutSpace_isLiteral_notHeading() {
        // CommonMark: ATX heading needs a space after the run of '#'.
        val a = render("#NoSpace")
        assertEquals("#NoSpace", a.text)
        assertTrue(a.spanStyles.isEmpty())
    }

    @Test fun emptyHeading_noCrash_noStyle() {
        val a = render("## ")
        assertEquals("", a.text)
        assertTrue("empty heading content gets no span", a.spanStyles.isEmpty())
    }

    // --- Emphasis. ---

    @Test fun bold_dropsDelimiters() {
        val a = render("**bold**")
        assertEquals("bold", a.text)
        val span = a.spanStyles.single()
        assertEquals(0, span.start); assertEquals(4, span.end)
        assertEquals(FontWeight.Bold, span.item.fontWeight)
        assertNull(span.item.fontStyle)
    }

    @Test fun italicStar_dropsDelimiters() {
        val a = render("*italic*")
        assertEquals("italic", a.text)
        val span = a.spanStyles.single()
        assertEquals(FontStyle.Italic, span.item.fontStyle)
    }

    @Test fun italicUnderscore_dropsDelimiters() {
        val a = render("_italic_")
        assertEquals("italic", a.text)
        assertEquals(FontStyle.Italic, a.spanStyles.single().item.fontStyle)
    }

    @Test fun boldItalic_tripleStar_appliesBoth() {
        val a = render("***both***")
        assertEquals("both", a.text)
        assertTrue("a Bold span over 0..4", a.spanStyles.any {
            it.start == 0 && it.end == 4 && it.item.fontWeight == FontWeight.Bold
        })
        assertTrue("an Italic span over 0..4", a.spanStyles.any {
            it.start == 0 && it.end == 4 && it.item.fontStyle == FontStyle.Italic
        })
    }

    @Test fun nestedEmphasis_boldContainingItalic() {
        val a = render("**bold _and italic_**")
        assertEquals("bold and italic", a.text)
        assertTrue("Bold over the whole inner", a.spanStyles.any {
            it.start == 0 && it.end == 15 && it.item.fontWeight == FontWeight.Bold
        })
        assertTrue("Italic over 'and italic'", a.spanStyles.any {
            it.item.fontStyle == FontStyle.Italic &&
                a.text.substring(it.start, it.end) == "and italic"
        })
    }

    @Test fun escapedDelimiters_areLiteral() {
        val a = render("\\*literal\\*")
        assertEquals("*literal*", a.text)
        assertTrue(a.spanStyles.isEmpty())
    }

    @Test fun intrawordUnderscore_isLiteral() {
        // CommonMark: underscores inside a word do not open/close emphasis.
        val a = render("foo_bar_baz")
        assertEquals("foo_bar_baz", a.text)
        assertTrue(a.spanStyles.isEmpty())
    }

    @Test fun doubleUnderscore_isLiteral_v1() {
        // v1 supports only ** for bold; __bold__ stays literal (documented OUT of scope).
        val a = render("__bold__")
        assertEquals("__bold__", a.text)
        assertTrue(a.spanStyles.isEmpty())
    }

    // --- Inline code. ---

    @Test fun inlineCode_monospace_dropsBackticks() {
        val a = render("`code`")
        assertEquals("code", a.text)
        val span = a.spanStyles.single()
        assertEquals(FontFamily.Monospace, span.item.fontFamily)
    }

    @Test fun inlineCode_suppressesEmphasis() {
        val a = render("`a*b*c`")
        assertEquals("a*b*c", a.text)
        assertEquals(FontFamily.Monospace, a.spanStyles.single().item.fontFamily)
        assertTrue("no italic inside code", a.spanStyles.none { it.item.fontStyle == FontStyle.Italic })
    }

    // --- Bullets. ---

    @Test fun dashBullet_glyphPrefix_markerConsumed() {
        val a = render("- item")
        assertEquals("• item", a.text)
    }

    @Test fun starBullet_glyphPrefix() {
        val a = render("* item")
        assertEquals("• item", a.text)
    }

    // --- Passthrough / robustness. ---

    @Test fun plainLine_verbatim_noSpans() {
        val a = render("just plain text")
        assertEquals("just plain text", a.text)
        assertTrue(a.spanStyles.isEmpty())
    }

    @Test fun unterminatedBold_rendersLiterally_noCrash() {
        val a = render("**unterminated")
        assertEquals("**unterminated", a.text)
        assertTrue(a.spanStyles.isEmpty())
    }

    @Test fun trailingMarker_rendersLiterally() {
        val a = render("trailing **")
        assertEquals("trailing **", a.text)
        assertTrue(a.spanStyles.isEmpty())
    }

    @Test fun emptyString_rendersEmpty() {
        val a = render("")
        assertEquals("", a.text)
        assertTrue(a.spanStyles.isEmpty())
    }

    // Gate-4 Medium: delimiter-only runs are NOT empty emphasis — kept literal.
    @Test fun sixStars_rendersLiterally_notEmpty() {
        val a = render("******")
        assertEquals("******", a.text)
        assertTrue(a.spanStyles.isEmpty())
    }

    @Test fun emptyEmphasisRunBetweenWords_preserved() {
        val a = render("before ****** after")
        assertEquals("before ****** after", a.text)
        assertTrue(a.spanStyles.isEmpty())
    }

    @Test fun fourStars_rendersLiterally() {
        val a = render("****")
        assertEquals("****", a.text)
        assertTrue(a.spanStyles.isEmpty())
    }

    // Gate-4 Low: an escaped delimiter must NOT close emphasis.
    @Test fun escapedClose_doesNotTerminateBold() {
        // The \* is escaped, so the real bold runs to the final **.
        val a = render("**a\\* b**")
        assertEquals("a* b", a.text)
        assertTrue("bold spans the whole inner", a.spanStyles.any {
            it.start == 0 && it.end == 4 && it.item.fontWeight == FontWeight.Bold
        })
    }

    @Test fun escapedClose_doesNotTerminateItalicUnderscore() {
        val a = render("_a\\_ b_")
        assertEquals("a_ b", a.text)
        assertTrue("italic spans the whole inner", a.spanStyles.any {
            it.item.fontStyle == FontStyle.Italic && a.text.substring(it.start, it.end) == "a_ b"
        })
    }

    // --- Unicode / CJK span arithmetic. ---

    @Test fun cjkBold_spanOffsetsCorrect() {
        val a = render("**中文**")
        assertEquals("中文", a.text)
        val span = a.spanStyles.single()
        assertEquals(0, span.start); assertEquals(2, span.end)
        assertEquals(FontWeight.Bold, span.item.fontWeight)
    }

    @Test fun cjkHeading_spanOffsetsCorrect() {
        val a = render("# 標題")
        assertEquals("標題", a.text)
        assertEquals(0, a.spanStyles.single().start)
        assertEquals(2, a.spanStyles.single().end)
    }

    // --- EOL preserved (chunks keep their line terminator). ---

    @Test fun trailingNewline_preserved_headingStyledBeforeIt() {
        val a = render("# Heading\n")
        assertEquals("Heading\n", a.text)
        val span = a.spanStyles.single()
        assertEquals(0, span.start); assertEquals(7, span.end)
    }

    @Test fun crlf_preserved() {
        val a = render("plain\r\n")
        assertEquals("plain\r\n", a.text)
    }

    // --- feature #156 WI-1: the SCROLL-mode heading predicate the body's alignment branch reads. ---

    @Test fun isHeadingChunk_recognisesEveryAtxLevel() {
        for (level in 1..6) {
            val chunk = "#".repeat(level) + " Heading text"
            assertTrue("h$level must be a heading chunk", MarkdownRenderer.isHeadingChunk(chunk))
        }
    }

    @Test fun isHeadingChunk_rejectsNonHeadings() {
        // Every one of these renders as prose/bullet, so the body must justify it.
        val notHeadings = listOf(
            "",                       // empty chunk
            "\n", "\r\n",             // EOL-only
            "   ", "\t",              // whitespace only
            "#NoSpace",               // CommonMark needs whitespace after the hash run
            "####### seven hashes",   // >6 hashes is not ATX
            " # leading space",       // ATX is anchored at the chunk start
            "- bullet item", "* bullet item",
            "plain prose that happens to mention # in the middle",
            "**bold prose**",
            "`# code span`",
        )
        for (chunk in notHeadings) {
            assertFalse("must NOT be a heading chunk: ${'"'}$chunk${'"'}", MarkdownRenderer.isHeadingChunk(chunk))
        }
    }

    @Test fun isHeadingChunk_toleratesEolAndCjkAndTabSeparator() {
        assertTrue(MarkdownRenderer.isHeadingChunk("# Heading\n"))
        assertTrue(MarkdownRenderer.isHeadingChunk("## Heading\r\n"))
        assertTrue(MarkdownRenderer.isHeadingChunk("#\tTab separated"))
        assertTrue(MarkdownRenderer.isHeadingChunk("# 第一章 黑暗血时代"))     // CJK heading
        assertTrue(MarkdownRenderer.isHeadingChunk("# **bold** heading"))    // inline markup inside
    }

    /**
     * The predicate and the RENDERER must not drift: for every chunk the predicate calls a heading, the
     * renderer must emit the bold em-relative heading span — and for every chunk it calls prose, it must
     * not. A predicate that disagreed with the render would align a chunk as a heading while it draws as
     * prose (or the reverse), which no alignment assertion on either side alone would catch.
     */
    @Test fun isHeadingChunk_agreesWithWhatTheRendererActuallyStyles() {
        val chunks = listOf(
            "# Heading", "###### Small heading", "## Heading\n", "# 標題",
            "#NoSpace", "####### seven", " # leading space", "- bullet", "* bullet",
            "prose line", "**bold**", "", "\n", "   ",
        )
        for (chunk in chunks) {
            val styledAsHeading = render(chunk).spanStyles.any {
                it.item.fontWeight == FontWeight.Bold && it.item.fontSize.isEm
            }
            assertEquals(
                "predicate vs render disagree for ${'"'}$chunk${'"'}",
                styledAsHeading, MarkdownRenderer.isHeadingChunk(chunk),
            )
        }
    }

    /**
     * The one ATX-shaped chunk the predicate and the renderer legitimately differ on: `"# "` has no
     * heading TEXT, so the renderer emits no span (and no glyphs). It is pinned rather than papered
     * over — with an empty render there is nothing to justify either way, so the alignment branch is
     * moot and `true` is the honest answer for "this chunk is an ATX heading".
     */
    @Test fun isHeadingChunk_emptyHeadingText_isAtxShapedButRendersNothing() {
        assertTrue(MarkdownRenderer.isHeadingChunk("# "))
        assertEquals("", render("# ").text)
        assertTrue("no heading span when there is no heading text", render("# ").spanStyles.isEmpty())
    }
}
