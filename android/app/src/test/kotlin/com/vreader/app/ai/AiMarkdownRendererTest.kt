package com.vreader.app.ai

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** Feature #118 WI-4 — multi-line AI-answer markdown rendering (wraps the #112 single-line renderer). */
@RunWith(RobolectricTestRunner::class)
class AiMarkdownRendererTest {
    @Test fun multiLine_headingsBulletsParagraphs_preserved() {
        val md = "# Mr. Bingley\n\nHe leases Netherfield.\n- wealthy\n- good-natured"
        val text = AiMarkdownRenderer.render(md).text
        assertTrue(text.contains("Mr. Bingley"))
        assertTrue(text.contains("He leases Netherfield."))
        assertTrue(text.contains("wealthy"))
        assertTrue(text.contains("good-natured"))
        assertTrue("newlines preserved across lines", text.contains("\n"))
    }

    @Test fun fencedCodeBlock_rendersContent_dropsFenceMarkers() {
        val md = "Run:\n```\nval x = 1\nval y = 2\n```\nDone."
        val text = AiMarkdownRenderer.render(md).text
        assertTrue(text.contains("val x = 1"))
        assertTrue(text.contains("val y = 2"))
        assertTrue("fence markers not drawn", !text.contains("```"))
        assertTrue(text.contains("Done."))
    }

    @Test fun partialStreamingMarkdown_doesNotCrash() {
        // An unclosed bold + an unclosed fence (mid-stream) must render, not throw.
        AiMarkdownRenderer.render("This is **bol")
        AiMarkdownRenderer.render("intro\n```\nopen fence still streaming")
        // no exception = pass
    }

    @Test fun cjk_preserved() {
        assertTrue(AiMarkdownRenderer.render("# 第一章\n\n这是摘要。").text.contains("这是摘要。"))
    }

    @Test fun empty_isEmpty() {
        assertEquals("", AiMarkdownRenderer.render("").text)
    }
}
