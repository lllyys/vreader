// Purpose: Feature #56 WI-10 — pin the block-boundary-preserving
// HTML stripper (`stripHTMLPreservingBlocks`) the bilingual EPUB
// path uses. Codex Gate-4 audit finding [1] flagged that the
// existing `stripHTML` collapses every block boundary into a single
// space, so `ChapterSegmenter.paragraphs` (which splits on
// `\n\n+`) produced one segment regardless of how many `<p>` /
// `<li>` blocks the chapter contains — the enumerate JS would
// stamp N blocks and translate would return 1 segment, breaking
// the inject path's 1:1 mapping.
//
// The fix: a second stripper that emits `\n\n` after every
// block-level closing tag. This file pins the boundary contract:
// `N <p>` blocks → exactly `N` paragraphs after segmentation.
//
// @coordinates-with: EPUBTextExtractor.swift,
//   ChapterSegmenter.swift, EPUBChapterTextProvider.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-10)

import Testing
@testable import vreader

@Suite("Feature #56 WI-10 — stripHTMLPreservingBlocks")
struct EPUBTextExtractorBilingualTests {

    @Test("preserves block boundaries between paragraphs")
    func preservesParagraphBoundaries() {
        let xhtml = """
        <html><body>\
        <p>First paragraph.</p>\
        <p>Second paragraph.</p>\
        <p>Third paragraph.</p>\
        </body></html>
        """
        let text = EPUBTextExtractor.stripHTMLPreservingBlocks(xhtml)
        let segments = ChapterSegmenter.paragraphs(in: text)
        #expect(
            segments.count == 3,
            "Three <p> blocks should yield three paragraph segments — the producer (enumerate) walks 3 blocks; the consumer (segmenter) must agree on the count."
        )
        #expect(segments[0] == "First paragraph.")
        #expect(segments[1] == "Second paragraph.")
        #expect(segments[2] == "Third paragraph.")
    }

    @Test("inline tags do not break block segmentation")
    func inlineTagsKeepBoundaries() {
        let xhtml = """
        <html><body>\
        <p>Hello <em>world</em> with <strong>bold</strong>.</p>\
        <p>Second paragraph.</p>\
        </body></html>
        """
        let text = EPUBTextExtractor.stripHTMLPreservingBlocks(xhtml)
        let segments = ChapterSegmenter.paragraphs(in: text)
        #expect(segments.count == 2)
        #expect(segments[0] == "Hello world with bold.")
        #expect(segments[1] == "Second paragraph.")
    }

    @Test("list items each become their own segment")
    func listItemsBecomeSegments() {
        let xhtml = """
        <html><body>\
        <ul>\
        <li>First item.</li>\
        <li>Second item.</li>\
        <li>Third item.</li>\
        </ul>\
        </body></html>
        """
        let text = EPUBTextExtractor.stripHTMLPreservingBlocks(xhtml)
        let segments = ChapterSegmenter.paragraphs(in: text)
        #expect(
            segments.count == 3,
            "Each <li> block should yield its own segment — the EPUBBilingualJS enumerate path walks <li>s one at a time."
        )
    }

    @Test("br tag is a soft wrap, not a block boundary")
    func brIsSoftWrap() {
        let xhtml = """
        <html><body>\
        <p>Line one<br/>Line two</p>\
        <p>Second paragraph.</p>\
        </body></html>
        """
        let text = EPUBTextExtractor.stripHTMLPreservingBlocks(xhtml)
        let segments = ChapterSegmenter.paragraphs(in: text)
        #expect(
            segments.count == 2,
            "A <br/> inside a <p> is a soft wrap inside one paragraph — must NOT split into a separate segment."
        )
    }

    @Test("script and style blocks are removed cleanly")
    func scriptStyleRemoved() {
        let xhtml = """
        <html><head>\
        <style>body { font-size: 16px; }</style>\
        </head><body>\
        <p>Real content.</p>\
        <script>var x = 1;</script>\
        </body></html>
        """
        let text = EPUBTextExtractor.stripHTMLPreservingBlocks(xhtml)
        let segments = ChapterSegmenter.paragraphs(in: text)
        #expect(segments.count == 1)
        #expect(segments[0] == "Real content.")
        #expect(!text.contains("font-size"))
        #expect(!text.contains("var x"))
    }

    @Test("empty body yields zero segments")
    func emptyBody() {
        let xhtml = "<html><body></body></html>"
        let text = EPUBTextExtractor.stripHTMLPreservingBlocks(xhtml)
        let segments = ChapterSegmenter.paragraphs(in: text)
        #expect(segments.isEmpty)
    }

    @Test("top-level headings glue to the next paragraph segment (count stays correct)")
    func headingsGlueToNextParagraph() {
        // Codex Gate-4 round-2 finding [R2-1] / round-3 finding [R3-2]:
        // heading content is intentionally kept in the source text.
        // Dropping it globally would lose content nested inside an
        // enumerated block (e.g. `<blockquote><h2>Title</h2><p>Body</p></blockquote>`
        // — the enumerator's `textContent` would include `Title` but
        // the translation would not). Keeping headings means a
        // top-level `<h1>Title</h1><p>Body</p>` glues onto the next
        // paragraph segment ("Title Body" as one segment matching
        // the one enumerated `<p>` block). The translated segment
        // can be longer than what the renderer paints under, but
        // there is no content loss — a known minor misalignment
        // documented for a follow-up to address via enumerator-driven
        // translation input.
        let xhtml = """
        <html><body>\
        <h1>Chapter Title</h1>\
        <p>First paragraph of the body.</p>\
        <h2>Section Subtitle</h2>\
        <p>Second paragraph after the section heading.</p>\
        </body></html>
        """
        let text = EPUBTextExtractor.stripHTMLPreservingBlocks(xhtml)
        let segments = ChapterSegmenter.paragraphs(in: text)
        #expect(
            segments.count == 2,
            "Two <p> blocks should yield exactly two segments — headings glue onto the next paragraph and do NOT contribute their own segment."
        )
        // Each segment contains heading + body for that section.
        #expect(segments[0].contains("Chapter Title"))
        #expect(segments[0].contains("First paragraph"))
        #expect(segments[1].contains("Section Subtitle"))
        #expect(segments[1].contains("Second paragraph"))
    }

    @Test("nested headings inside an enumerated block stay in the segment")
    func nestedHeadingsKept() {
        // Codex Gate-4 round-3 finding [R3-2]: a `<blockquote>` with a
        // nested `<h2>` must keep the heading text in the translation
        // source so the segment matches the enumerator's
        // `textContent`. Without this, the translation would be
        // shorter than the source block's visible content (silent
        // text loss).
        let xhtml = """
        <html><body>\
        <blockquote><h2>Quoted Heading</h2><p>Body of the quote.</p></blockquote>\
        <p>After the quote.</p>\
        </body></html>
        """
        let text = EPUBTextExtractor.stripHTMLPreservingBlocks(xhtml)
        // Note: the segmenter splits on the inner `</p>` too, so this
        // produces more segments than the enumerator's one
        // `<blockquote>` block. That mismatch is the trade-off
        // documented in `headingsGlueToNextParagraph` and is acceptable
        // for the slice (no content loss; renderer falls back to
        // source-only for the unmatched extras). The MUST-NOT is
        // content LOSS — the heading text must appear somewhere.
        #expect(
            text.contains("Quoted Heading"),
            "Heading nested inside a `<blockquote>` must NOT be stripped — its text is part of the enumerator's block content and must be in the translation source too."
        )
        #expect(text.contains("Body of the quote."))
        #expect(text.contains("After the quote."))
    }

    @Test("structural wrappers around block elements do not alter the segment count")
    func structuralWrappersTransparent() {
        // <section>, <article>, <div> are not in BLOCK_TAGS but they
        // contain `<p>` blocks. The stripper used to emit `\n\n` for
        // these wrappers, which over-counted boundaries. Now it
        // does not, so the contained `</p>` is the only boundary —
        // exactly what the enumerator sees.
        let xhtml = """
        <html><body>\
        <section><p>One.</p></section>\
        <article><div><p>Two.</p></div></article>\
        <p>Three.</p>\
        </body></html>
        """
        let text = EPUBTextExtractor.stripHTMLPreservingBlocks(xhtml)
        let segments = ChapterSegmenter.paragraphs(in: text)
        #expect(segments.count == 3)
        #expect(segments[0] == "One.")
        #expect(segments[1] == "Two.")
        #expect(segments[2] == "Three.")
    }

    @Test("EPUB chapter with mixed block types preserves order and count")
    func mixedBlockTypes() {
        // Realistic EPUB shape: blockquote, paragraph, blockquote — the
        // EPUBBilingualJS enumerate path stamps all three blocks, so
        // segmentation must yield three segments in order.
        let xhtml = """
        <html><body>\
        <blockquote>A quoted line.</blockquote>\
        <p>Author commentary.</p>\
        <blockquote>Another quote.</blockquote>\
        </body></html>
        """
        let text = EPUBTextExtractor.stripHTMLPreservingBlocks(xhtml)
        let segments = ChapterSegmenter.paragraphs(in: text)
        #expect(segments.count == 3)
        #expect(segments[0] == "A quoted line.")
        #expect(segments[1] == "Author commentary.")
        #expect(segments[2] == "Another quote.")
    }
}
