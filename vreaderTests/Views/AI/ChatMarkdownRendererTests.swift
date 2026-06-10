// Purpose: Bug #335 — the AI chat assistant row rendered `Text(message.content)`
// where `content` is a `String` variable, so SwiftUI's literal-only markdown
// parsing left `**bold**` / `[tags]` / `-` lists showing verbatim. These tests
// pin the pure renderer that turns the raw LLM string into a formatted
// `AttributedString`.

import Testing
import Foundation
@testable import vreader

@Suite("ChatMarkdownRenderer")
struct ChatMarkdownRendererTests {

    /// The rendered string's visible characters (markup stripped).
    private func plain(_ s: AttributedString) -> String {
        String(s.characters)
    }

    @Test func boldMarkupIsStrippedFromVisibleText() {
        let out = ChatMarkdownRenderer.attributedString(from: "This is **bold** text")
        // The literal asterisks must be gone — that was the bug.
        #expect(!plain(out).contains("**"))
        #expect(plain(out).contains("bold"))
    }

    @Test func italicAndCodeMarkupStripped() {
        let out = ChatMarkdownRenderer.attributedString(from: "an *em* and `code` span")
        let text = plain(out)
        #expect(!text.contains("*"))
        #expect(!text.contains("`"))
        #expect(text.contains("em"))
        #expect(text.contains("code"))
    }

    @Test func boldRunCarriesBoldIntent() {
        let out = ChatMarkdownRenderer.attributedString(from: "**笔记：** 内容")
        // At least one run must carry a bold inline-presentation intent.
        let hasBold = out.runs.contains { run in
            run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
        }
        #expect(hasBold)
        #expect(!plain(out).contains("**"))
    }

    @Test func plainTextRoundTripsUnchanged() {
        let out = ChatMarkdownRenderer.attributedString(from: "just plain text, no markup")
        #expect(plain(out) == "just plain text, no markup")
    }

    @Test func newlinesArePreservedAcrossParagraphsAndLists() {
        // The design clamps to N lines, so paragraph/line structure must survive
        // (inline-only-PRESERVING-whitespace, not the newline-collapsing default).
        let input = "Line one\n- item A\n- item B"
        let out = ChatMarkdownRenderer.attributedString(from: input)
        #expect(plain(out).contains("\n"))
        #expect(plain(out).contains("item A"))
        #expect(plain(out).contains("item B"))
    }

    @Test func malformedMarkupDegradesGracefullyNoCrash() {
        // A half-open `**` mid-stream (coalesced deltas) must not crash and must
        // still surface the text.
        for input in ["**half open", "unclosed `code", "[link](", "***", ""] {
            let out = ChatMarkdownRenderer.attributedString(from: input)
            #expect(plain(out).count >= 0)   // no crash; some string returned
        }
        #expect(plain(ChatMarkdownRenderer.attributedString(from: "**half open")).contains("half open"))
    }

    @Test func emptyStringYieldsEmpty() {
        #expect(plain(ChatMarkdownRenderer.attributedString(from: "")).isEmpty)
    }

    // MARK: - Gate-4 Medium: list markers → bullets

    @Test func unorderedListMarkersBecomeBullets() {
        let out = ChatMarkdownRenderer.attributedString(from: "- first\n- second\n* third\n+ fourth")
        let text = plain(out)
        #expect(text.contains("• first"))
        #expect(text.contains("• second"))
        #expect(text.contains("• third"))
        #expect(text.contains("• fourth"))
        // The literal leading hyphen/asterisk markers are gone.
        #expect(!text.contains("- first"))
        #expect(!text.contains("* third"))
    }

    @Test func indentedListMarkerKeepsIndentAndBullets() {
        let out = ChatMarkdownRenderer.attributedString(from: "  - nested")
        #expect(plain(out).contains("• nested"))
    }

    @Test func nonListHyphenIsNotTouched() {
        // A hyphen mid-line (not a list marker) stays literal.
        let out = ChatMarkdownRenderer.attributedString(from: "well-known result is 5 - 3")
        #expect(plain(out).contains("well-known"))
        #expect(plain(out).contains("5 - 3"))
    }

    // MARK: - Gate-4 Medium: unsafe-link sanitization

    @Test func unsafeSchemeLinkIsStrippedButTextKept() {
        // A custom/deep-link scheme from LLM output must not become a live link.
        let out = ChatMarkdownRenderer.attributedString(from: "tap [here](vreader-debug://reset) now")
        #expect(plain(out).contains("here"))
        let hasLink = out.runs.contains { $0.link != nil }
        #expect(!hasLink)
    }

    @Test func httpsLinkIsPreserved() {
        let out = ChatMarkdownRenderer.attributedString(from: "see [docs](https://example.com)")
        let preserved = out.runs.contains { $0.link?.scheme == "https" }
        #expect(preserved)
    }

    @Test func telAndJavascriptSchemesStripped() {
        for url in ["tel:+15551234", "javascript:alert(1)"] {
            let out = ChatMarkdownRenderer.attributedString(from: "x [y](\(url)) z")
            #expect(!out.runs.contains { $0.link != nil }, "stripped \(url)")
        }
    }
}
