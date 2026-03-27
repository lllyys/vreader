// Purpose: Tests for FoliateSearchAdapter — JS generation and search result parsing.
// Covers: JS string generation for search/clear/goTo, query escaping (quotes, backslashes,
//         newlines, Unicode/CJK), CFI escaping, result parsing for both direct hits and
//         grouped (book-wide) results with excerpt object {pre, match, post}.
//
// @coordinates-with: FoliateSearchAdapter.swift, FoliateTypes.swift

import Testing
import Foundation
@testable import vreader

// MARK: - searchJS

@Suite("FoliateSearchAdapter - searchJS")
struct SearchJSTests {

    @Test("contains readerAPI.search call")
    func containsSearchCall() {
        let js = FoliateSearchAdapter.searchJS(query: "hello")
        #expect(js.contains("readerAPI.search"))
    }

    @Test("includes the query text")
    func includesQuery() {
        let js = FoliateSearchAdapter.searchJS(query: "hello world")
        #expect(js.contains("hello world"))
    }

    @Test("double quotes in query are preserved (single-quoted JS string)")
    func doubleQuotesPreserved() {
        let js = FoliateSearchAdapter.searchJS(query: "say \"hello\"")
        // Double quotes inside a single-quoted JS string are safe
        #expect(js.contains("say \"hello\""))
    }

    @Test("escapes backslashes in query")
    func escapesBackslashes() {
        let js = FoliateSearchAdapter.searchJS(query: "path\\to\\file")
        #expect(js.contains("path\\\\to\\\\file"))
    }

    @Test("escapes newlines in query")
    func escapesNewlines() {
        let js = FoliateSearchAdapter.searchJS(query: "line1\nline2")
        // The JS output must not contain a raw newline from the query
        #expect(js.contains("\\n"))
    }

    @Test("escapes tabs in query")
    func escapesTabs() {
        let js = FoliateSearchAdapter.searchJS(query: "col1\tcol2")
        #expect(js.contains("\\t"))
    }

    @Test("escapes carriage returns in query")
    func escapesCarriageReturns() {
        let js = FoliateSearchAdapter.searchJS(query: "line1\rline2")
        #expect(js.contains("\\r"))
    }

    @Test("handles CJK characters in query")
    func cjkQuery() {
        let js = FoliateSearchAdapter.searchJS(query: "你好世界")
        #expect(js.contains("你好世界"))
        #expect(js.contains("readerAPI.search"))
    }

    @Test("handles empty query")
    func emptyQuery() {
        let js = FoliateSearchAdapter.searchJS(query: "")
        #expect(js.contains("readerAPI.search"))
    }

    @Test("single quotes in query are escaped")
    func singleQuotesEscaped() {
        let js = FoliateSearchAdapter.searchJS(query: "it's fine")
        // Single quotes must be escaped in single-quoted JS strings
        #expect(js.contains("it\\'s fine"))
        #expect(js.contains("readerAPI.search"))
    }

    @Test("passes query as the query property of the options object")
    func queryPropertyInOptions() {
        let js = FoliateSearchAdapter.searchJS(query: "test")
        // The JS should pass {query: "test"} to readerAPI.search
        #expect(js.contains("query"))
    }
}

// MARK: - clearSearchJS

@Suite("FoliateSearchAdapter - clearSearchJS")
struct ClearSearchJSTests {

    @Test("contains readerAPI.clearSearch call")
    func containsClearSearchCall() {
        let js = FoliateSearchAdapter.clearSearchJS()
        #expect(js.contains("readerAPI.clearSearch"))
    }

    @Test("is a function invocation")
    func isFunctionCall() {
        let js = FoliateSearchAdapter.clearSearchJS()
        #expect(js.contains("()"))
    }
}

// MARK: - goToResultJS

@Suite("FoliateSearchAdapter - goToResultJS")
struct GoToResultJSTests {

    @Test("contains readerAPI.goTo call")
    func containsGoToCall() {
        let js = FoliateSearchAdapter.goToResultJS(cfi: "epubcfi(/6/14!/4/2/1:0)")
        #expect(js.contains("readerAPI.goTo"))
    }

    @Test("includes the CFI string")
    func includesCFI() {
        let cfi = "epubcfi(/6/14!/4/2/1:0)"
        let js = FoliateSearchAdapter.goToResultJS(cfi: cfi)
        #expect(js.contains(cfi))
    }

    @Test("preserves double quotes in CFI (single-quoted JS string)")
    func preservesCFIWithQuotes() {
        let cfi = "epubcfi(/6/14!/4/2/1:0\")"
        let js = FoliateSearchAdapter.goToResultJS(cfi: cfi)
        // Double quotes are safe inside single-quoted JS strings
        #expect(js.contains("epubcfi(/6/14!/4/2/1:0\")"))
    }

    @Test("escapes CFI with backslashes")
    func escapesCFIWithBackslashes() {
        let cfi = "epubcfi(/6/14\\!/4/2/1:0)"
        let js = FoliateSearchAdapter.goToResultJS(cfi: cfi)
        #expect(js.contains("\\\\"))
    }

    @Test("handles standard CFI format")
    func standardCFI() {
        let cfi = "epubcfi(/6/8!/4/2/3:5,/6/8!/4/2/3:42)"
        let js = FoliateSearchAdapter.goToResultJS(cfi: cfi)
        #expect(js.contains("readerAPI.goTo"))
        #expect(js.contains(cfi))
    }
}

// MARK: - parseSearchResult (direct hit: {cfi, excerpt: {pre, match, post}})

@Suite("FoliateSearchAdapter - parseSearchResult")
struct ParseSearchResultTests {

    @Test("valid dict with excerpt object returns correct FoliateSearchResult")
    func validDictWithExcerptObject() {
        let body: [String: Any] = [
            "cfi": "epubcfi(/6/14!/4/2/1:0)",
            "excerpt": [
                "pre": "the quick brown ",
                "match": "fox",
                "post": " jumped over",
            ] as [String: Any],
        ]
        let result = FoliateSearchAdapter.parseSearchResult(body)
        #expect(result != nil)
        #expect(result?.cfi == "epubcfi(/6/14!/4/2/1:0)")
        #expect(result?.excerpt == "the quick brown fox jumped over")
        #expect(result?.sectionLabel == nil)
    }

    @Test("missing cfi returns nil")
    func missingCfi() {
        let body: [String: Any] = [
            "excerpt": [
                "pre": "before",
                "match": "word",
                "post": "after",
            ] as [String: Any],
        ]
        let result = FoliateSearchAdapter.parseSearchResult(body)
        #expect(result == nil)
    }

    @Test("missing excerpt returns nil")
    func missingExcerpt() {
        let body: [String: Any] = [
            "cfi": "epubcfi(/6/14!/4/2/1:0)",
        ]
        let result = FoliateSearchAdapter.parseSearchResult(body)
        #expect(result == nil)
    }

    @Test("excerpt as plain string returns result")
    func excerptAsString() {
        // Defensive: handle plain string excerpt if JS ever changes
        let body: [String: Any] = [
            "cfi": "epubcfi(/6/14!/4/2/1:0)",
            "excerpt": "plain text excerpt",
        ]
        let result = FoliateSearchAdapter.parseSearchResult(body)
        #expect(result != nil)
        #expect(result?.excerpt == "plain text excerpt")
    }

    @Test("excerpt object missing match returns nil")
    func excerptMissingMatch() {
        let body: [String: Any] = [
            "cfi": "epubcfi(/6/14!/4/2/1:0)",
            "excerpt": [
                "pre": "before",
                "post": "after",
            ] as [String: Any],
        ]
        let result = FoliateSearchAdapter.parseSearchResult(body)
        #expect(result == nil)
    }

    @Test("excerpt object with missing pre/post uses empty strings")
    func excerptMissingPrePost() {
        let body: [String: Any] = [
            "cfi": "epubcfi(/6/14!/4/2/1:0)",
            "excerpt": [
                "match": "found",
            ] as [String: Any],
        ]
        let result = FoliateSearchAdapter.parseSearchResult(body)
        #expect(result != nil)
        #expect(result?.excerpt == "found")
    }

    @Test("non-dict body returns nil")
    func nonDictBody() {
        let result = FoliateSearchAdapter.parseSearchResult("not a dict")
        #expect(result == nil)
    }

    @Test("empty dict returns nil")
    func emptyDict() {
        let body: [String: Any] = [:]
        let result = FoliateSearchAdapter.parseSearchResult(body)
        #expect(result == nil)
    }

    @Test("cfi as non-string returns nil")
    func cfiWrongType() {
        let body: [String: Any] = [
            "cfi": 12345,
            "excerpt": ["pre": "", "match": "x", "post": ""] as [String: Any],
        ]
        let result = FoliateSearchAdapter.parseSearchResult(body)
        #expect(result == nil)
    }

    @Test("excerpt as integer returns nil")
    func excerptWrongType() {
        let body: [String: Any] = [
            "cfi": "epubcfi(/6/2!/4/2)",
            "excerpt": 42,
        ]
        let result = FoliateSearchAdapter.parseSearchResult(body)
        #expect(result == nil)
    }

    @Test("CJK text in excerpt parses correctly")
    func cjkExcerpt() {
        let body: [String: Any] = [
            "cfi": "epubcfi(/6/10!/4/2/1:0)",
            "excerpt": [
                "pre": "这是",
                "match": "中文搜索",
                "post": "结果",
            ] as [String: Any],
        ]
        let result = FoliateSearchAdapter.parseSearchResult(body)
        #expect(result != nil)
        #expect(result?.excerpt == "这是中文搜索结果")
    }

    @Test("NSNull cfi is treated as missing")
    func nsNullCfi() {
        let body: [String: Any] = [
            "cfi": NSNull(),
            "excerpt": ["pre": "", "match": "x", "post": ""] as [String: Any],
        ]
        let result = FoliateSearchAdapter.parseSearchResult(body)
        #expect(result == nil)
    }

    @Test("extra unexpected keys do not cause failure")
    func extraKeys() {
        let body: [String: Any] = [
            "cfi": "epubcfi(/6/2!/4/2)",
            "excerpt": ["pre": "", "match": "text", "post": ""] as [String: Any],
            "unknownKey": "ignored",
            "range": ["startIndex": 0, "endIndex": 5],
        ]
        let result = FoliateSearchAdapter.parseSearchResult(body)
        #expect(result != nil)
    }
}

// MARK: - parseGroupedSearchResults (book-wide: {label, subitems: [{cfi, excerpt}]})

@Suite("FoliateSearchAdapter - parseGroupedSearchResults")
struct ParseGroupedSearchResultsTests {

    @Test("valid grouped result returns array of FoliateSearchResult with sectionLabel")
    func validGroupedResult() {
        let body: [String: Any] = [
            "label": "Chapter 5",
            "subitems": [
                [
                    "cfi": "epubcfi(/6/14!/4/2/1:0)",
                    "excerpt": ["pre": "the ", "match": "fox", "post": " jumped"] as [String: Any],
                ] as [String: Any],
                [
                    "cfi": "epubcfi(/6/14!/4/2/3:10)",
                    "excerpt": ["pre": "a ", "match": "fox", "post": " ran"] as [String: Any],
                ] as [String: Any],
            ] as [[String: Any]],
        ]
        let results = FoliateSearchAdapter.parseGroupedSearchResults(body)
        #expect(results.count == 2)
        #expect(results[0].cfi == "epubcfi(/6/14!/4/2/1:0)")
        #expect(results[0].excerpt == "the fox jumped")
        #expect(results[0].sectionLabel == "Chapter 5")
        #expect(results[1].cfi == "epubcfi(/6/14!/4/2/3:10)")
        #expect(results[1].excerpt == "a fox ran")
        #expect(results[1].sectionLabel == "Chapter 5")
    }

    @Test("missing subitems returns empty array")
    func missingSubitems() {
        let body: [String: Any] = [
            "label": "Chapter 1",
        ]
        let results = FoliateSearchAdapter.parseGroupedSearchResults(body)
        #expect(results.isEmpty)
    }

    @Test("empty subitems returns empty array")
    func emptySubitems() {
        let body: [String: Any] = [
            "label": "Chapter 1",
            "subitems": [] as [[String: Any]],
        ]
        let results = FoliateSearchAdapter.parseGroupedSearchResults(body)
        #expect(results.isEmpty)
    }

    @Test("malformed subitem is skipped")
    func malformedSubitemSkipped() {
        let body: [String: Any] = [
            "label": "Chapter 1",
            "subitems": [
                ["excerpt": ["pre": "", "match": "x", "post": ""]] as [String: Any],  // missing cfi
                [
                    "cfi": "epubcfi(/6/4!/4/2)",
                    "excerpt": ["pre": "", "match": "good", "post": ""] as [String: Any],
                ] as [String: Any],
            ] as [[String: Any]],
        ]
        let results = FoliateSearchAdapter.parseGroupedSearchResults(body)
        #expect(results.count == 1)
        #expect(results[0].cfi == "epubcfi(/6/4!/4/2)")
    }

    @Test("missing label uses nil sectionLabel")
    func missingLabel() {
        let body: [String: Any] = [
            "subitems": [
                [
                    "cfi": "epubcfi(/6/2!/4/2)",
                    "excerpt": ["pre": "", "match": "hit", "post": ""] as [String: Any],
                ] as [String: Any],
            ] as [[String: Any]],
        ]
        let results = FoliateSearchAdapter.parseGroupedSearchResults(body)
        #expect(results.count == 1)
        #expect(results[0].sectionLabel == nil)
    }

    @Test("non-dict body returns empty array")
    func nonDictBody() {
        let results = FoliateSearchAdapter.parseGroupedSearchResults("not a dict")
        #expect(results.isEmpty)
    }

    @Test("CJK label propagates to all results")
    func cjkLabel() {
        let body: [String: Any] = [
            "label": "第五章 黎明",
            "subitems": [
                [
                    "cfi": "epubcfi(/6/14!/4/2/1:0)",
                    "excerpt": ["pre": "", "match": "黎明", "post": ""] as [String: Any],
                ] as [String: Any],
            ] as [[String: Any]],
        ]
        let results = FoliateSearchAdapter.parseGroupedSearchResults(body)
        #expect(results.count == 1)
        #expect(results[0].sectionLabel == "第五章 黎明")
    }
}

// MARK: - FoliateSearchResult Equatable

@Suite("FoliateSearchResult - Equatable")
struct SearchResultEquatableTests {

    @Test("equal results compare as equal")
    func equalResults() {
        let a = FoliateSearchResult(cfi: "cfi1", excerpt: "text", sectionLabel: "Ch1")
        let b = FoliateSearchResult(cfi: "cfi1", excerpt: "text", sectionLabel: "Ch1")
        #expect(a == b)
    }

    @Test("different cfi compares as not equal")
    func differentCfi() {
        let a = FoliateSearchResult(cfi: "cfi1", excerpt: "text", sectionLabel: nil)
        let b = FoliateSearchResult(cfi: "cfi2", excerpt: "text", sectionLabel: nil)
        #expect(a != b)
    }

    @Test("different sectionLabel compares as not equal")
    func differentSectionLabel() {
        let a = FoliateSearchResult(cfi: "cfi1", excerpt: "text", sectionLabel: "Ch1")
        let b = FoliateSearchResult(cfi: "cfi1", excerpt: "text", sectionLabel: nil)
        #expect(a != b)
    }

    @Test("different excerpt compares as not equal")
    func differentExcerpt() {
        let a = FoliateSearchResult(cfi: "cfi1", excerpt: "hello", sectionLabel: nil)
        let b = FoliateSearchResult(cfi: "cfi1", excerpt: "world", sectionLabel: nil)
        #expect(a != b)
    }
}
