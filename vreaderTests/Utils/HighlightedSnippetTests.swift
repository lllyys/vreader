// Purpose: Tests for HighlightedSnippet — verifying query highlighting
// in search result snippets, including multi-word tokenized queries.
//
// @coordinates-with: HighlightedSnippet.swift

import Testing
import SwiftUI
@testable import vreader

@Suite("HighlightedSnippet")
struct HighlightedSnippetTests {

    // MARK: - Basic

    @Test func emptyQuery_returnsPlainText() {
        let result = HighlightedSnippet.highlight(snippet: "hello world", query: "")
        #expect(String(result.characters) == "hello world")
    }

    @Test func emptySnippet_returnsEmpty() {
        let result = HighlightedSnippet.highlight(snippet: "", query: "foo")
        #expect(String(result.characters) == "")
    }

    @Test func singleWordMatch_highlighted() {
        let result = HighlightedSnippet.highlight(snippet: "hello world", query: "hello")
        #expect(String(result.characters) == "hello world")
        // "hello" should be bolded — we verify by checking the range has bold font
        let helloRange = result.characters.startIndex..<result.characters.index(result.characters.startIndex, offsetBy: 5)
        let helloSlice = result[helloRange]
        #expect(helloSlice.font != nil) // bold applied
    }

    @Test func caseInsensitiveMatch() {
        let result = HighlightedSnippet.highlight(snippet: "Hello World", query: "hello")
        #expect(String(result.characters) == "Hello World")
    }

    @Test func fts5TagsStripped() {
        let result = HighlightedSnippet.highlight(snippet: "<b>hello</b> world", query: "hello")
        #expect(String(result.characters) == "hello world")
    }

    @Test func noMatch_returnsPlainText() {
        let result = HighlightedSnippet.highlight(snippet: "hello world", query: "xyz")
        #expect(String(result.characters) == "hello world")
    }

    // MARK: - Multi-word queries (Issue 4)

    @Test func multiWordQuery_highlightsBothWords() {
        // "foo bar" should highlight "foo" and "bar" independently
        let result = HighlightedSnippet.highlight(
            snippet: "foo is here and bar is there",
            query: "foo bar"
        )
        let text = String(result.characters)
        #expect(text == "foo is here and bar is there")
        // Both "foo" and "bar" should be found and bolded.
        // The result should contain at least 2 bold runs.
        var boldRunCount = 0
        for run in result.runs {
            if run.font != nil {
                boldRunCount += 1
            }
        }
        #expect(boldRunCount >= 2, "Expected at least 2 bold runs for 'foo' and 'bar'")
    }

    @Test func multiWordQuery_worksWhenExactPhraseNotPresent() {
        // The snippet contains "foo" and "bar" but NOT the exact phrase "foo bar"
        let result = HighlightedSnippet.highlight(
            snippet: "bar appears first, then foo appears",
            query: "foo bar"
        )
        let text = String(result.characters)
        #expect(text == "bar appears first, then foo appears")
        var boldRunCount = 0
        for run in result.runs {
            if run.font != nil {
                boldRunCount += 1
            }
        }
        #expect(boldRunCount >= 2, "Expected at least 2 bold runs")
    }

    @Test func multiWordQuery_duplicateWordHighlightsAllOccurrences() {
        let result = HighlightedSnippet.highlight(
            snippet: "foo foo foo bar",
            query: "foo bar"
        )
        var boldRunCount = 0
        for run in result.runs {
            if run.font != nil {
                boldRunCount += 1
            }
        }
        // 3 "foo" + 1 "bar" = 4 bold runs
        #expect(boldRunCount >= 4)
    }

    @Test func singleWordQuery_stillWorks() {
        // Ensure the multi-word change doesn't break single-word queries
        let result = HighlightedSnippet.highlight(
            snippet: "hello beautiful world",
            query: "beautiful"
        )
        var boldRunCount = 0
        for run in result.runs {
            if run.font != nil {
                boldRunCount += 1
            }
        }
        #expect(boldRunCount == 1)
    }

    @Test func whitespaceOnlyQuery_returnsPlainText() {
        let result = HighlightedSnippet.highlight(snippet: "hello world", query: "   ")
        #expect(String(result.characters) == "hello world")
    }

    @Test func multiWordQuery_withExtraSpaces_handledGracefully() {
        let result = HighlightedSnippet.highlight(
            snippet: "foo and bar here",
            query: "  foo   bar  "
        )
        var boldRunCount = 0
        for run in result.runs {
            if run.font != nil {
                boldRunCount += 1
            }
        }
        #expect(boldRunCount >= 2)
    }

    @Test func multipleNonAdjacentMatches_produceSeparateBoldRuns() {
        // Bug #105 (re-diagnosed): the original test asserted "abcabc" + "abc"
        // produces 2 bold runs. That's impossible — AttributedString
        // correctly coalesces back-to-back runs with identical
        // attributes into one run, and NSRegularExpression's default
        // matching is non-overlapping anyway. The visible rendering of
        // 2 adjacent bolds is identical to one bold spanning both
        // matches, so there's no UX bug to fix.
        //
        // This test now exercises the realistic case: matches separated
        // by plain text (the FTS5 snippet shape — words spaced apart)
        // genuinely produce 2 distinct bold runs because the plain
        // text between them breaks the coalescing.
        let result = HighlightedSnippet.highlight(
            snippet: "the cat sat on the mat",
            query: "cat mat"
        )
        var boldRunCount = 0
        for run in result.runs {
            if run.font != nil {
                boldRunCount += 1
            }
        }
        #expect(boldRunCount == 2,
                "Two non-adjacent word matches should produce two distinct bold runs (separated by the intervening plain-text 'sat on the ').")
    }

    @Test func consecutiveAdjacentMatches_coalesceIntoOneBoldRun() {
        // Bug #105 follow-up: pin the AttributedString coalescing
        // behavior so future readers don't waste time on the same
        // rabbit hole. When matches are adjacent (no plain text
        // between them), AttributedString merges the runs — visible
        // rendering is identical to one bold span. NSRegularExpression
        // returns 2 matches for "abcabc" + "abc" but `result.runs`
        // exposes a single bold run for the merged attributed
        // sub-string.
        let result = HighlightedSnippet.highlight(
            snippet: "abcabc",
            query: "abc"
        )
        var boldRunCount = 0
        for run in result.runs {
            if run.font != nil {
                boldRunCount += 1
            }
        }
        #expect(boldRunCount == 1,
                "Adjacent identical bold runs coalesce in AttributedString. The whole 'abcabc' becomes one bold run.")
        // The whole string ends up bold — visible rendering is correct.
        #expect(String(result.characters) == "abcabc")
    }

    @Test func regexSpecialCharsInQuery_escaped() {
        // Ensure regex special chars don't break anything
        let result = HighlightedSnippet.highlight(
            snippet: "price is $100 (total)",
            query: "$100 (total)"
        )
        let text = String(result.characters)
        #expect(text == "price is $100 (total)")
    }
}
