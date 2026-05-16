// Purpose: Tests for FoliateMessageParser — parsing raw JS message bodies into typed Swift events.
// Covers: success cases, missing/invalid fields, optional fields, boundary values,
//         nested TOC structures, error parsing, and guard cases.
//
// @coordinates-with: FoliateMessageParser.swift, FoliateTypes.swift

import Testing
import Foundation
import CoreGraphics
@testable import vreader

// MARK: - parseRelocate

@Suite("FoliateMessageParser - parseRelocate")
struct ParseRelocateTests {

    @Test("valid dict returns correct FoliateRelocateEvent")
    func validDict() {
        let body: [String: Any] = [
            "cfi": "epubcfi(/6/14!/4/2/1:0)",
            "fraction": 0.23,
            "sectionIndex": 5,
            "sectionTotal": 65,
            "tocLabel": "Chapter 5",
            "tocHref": "chapter5.xhtml",
        ]
        let event = FoliateMessageParser.parseRelocate(body)
        #expect(event != nil)
        #expect(event?.cfi == "epubcfi(/6/14!/4/2/1:0)")
        #expect(event?.fraction == 0.23)
        #expect(event?.sectionIndex == 5)
        #expect(event?.sectionTotal == 65)
        #expect(event?.tocLabel == "Chapter 5")
        #expect(event?.tocHref == "chapter5.xhtml")
    }

    @Test("missing cfi returns nil")
    func missingCfi() {
        let body: [String: Any] = [
            "fraction": 0.5,
            "sectionIndex": 1,
            "sectionTotal": 10,
        ]
        let event = FoliateMessageParser.parseRelocate(body)
        #expect(event == nil)
    }

    @Test("missing fraction returns nil")
    func missingFraction() {
        let body: [String: Any] = [
            "cfi": "epubcfi(/6/2!/4/2)",
            "sectionIndex": 0,
            "sectionTotal": 10,
        ]
        let event = FoliateMessageParser.parseRelocate(body)
        #expect(event == nil)
    }

    @Test("missing sectionIndex returns nil")
    func missingSectionIndex() {
        let body: [String: Any] = [
            "cfi": "epubcfi(/6/2!/4/2)",
            "fraction": 0.0,
            "sectionTotal": 10,
        ]
        let event = FoliateMessageParser.parseRelocate(body)
        #expect(event == nil)
    }

    @Test("missing sectionTotal returns nil")
    func missingSectionTotal() {
        let body: [String: Any] = [
            "cfi": "epubcfi(/6/2!/4/2)",
            "fraction": 0.0,
            "sectionIndex": 0,
        ]
        let event = FoliateMessageParser.parseRelocate(body)
        #expect(event == nil)
    }

    @Test("missing optional tocLabel and tocHref returns event with nil optionals")
    func missingOptionalFields() {
        let body: [String: Any] = [
            "cfi": "epubcfi(/6/4!/4/2)",
            "fraction": 0.05,
            "sectionIndex": 1,
            "sectionTotal": 20,
        ]
        let event = FoliateMessageParser.parseRelocate(body)
        #expect(event != nil)
        #expect(event?.tocLabel == nil)
        #expect(event?.tocHref == nil)
    }

    @Test("fraction at boundary 0.0 parses correctly")
    func fractionZero() {
        let body: [String: Any] = [
            "cfi": "epubcfi(/6/2!/4/2)",
            "fraction": 0.0,
            "sectionIndex": 0,
            "sectionTotal": 1,
        ]
        let event = FoliateMessageParser.parseRelocate(body)
        #expect(event != nil)
        #expect(event?.fraction == 0.0)
    }

    @Test("fraction at boundary 1.0 parses correctly")
    func fractionOne() {
        let body: [String: Any] = [
            "cfi": "epubcfi(/6/130!/4/2)",
            "fraction": 1.0,
            "sectionIndex": 64,
            "sectionTotal": 65,
        ]
        let event = FoliateMessageParser.parseRelocate(body)
        #expect(event != nil)
        #expect(event?.fraction == 1.0)
    }

    @Test("non-dict body returns nil")
    func nonDictBody() {
        let body = "not a dictionary"
        let event = FoliateMessageParser.parseRelocate(body)
        #expect(event == nil)
    }

    @Test("cfi as non-string type returns nil")
    func cfiWrongType() {
        let body: [String: Any] = [
            "cfi": 12345,
            "fraction": 0.5,
            "sectionIndex": 0,
            "sectionTotal": 10,
        ]
        let event = FoliateMessageParser.parseRelocate(body)
        #expect(event == nil)
    }

    @Test("fraction as string type returns nil")
    func fractionWrongType() {
        let body: [String: Any] = [
            "cfi": "epubcfi(/6/2!/4/2)",
            "fraction": "not a number",
            "sectionIndex": 0,
            "sectionTotal": 10,
        ]
        let event = FoliateMessageParser.parseRelocate(body)
        #expect(event == nil)
    }

    @Test("empty dict returns nil")
    func emptyDict() {
        let body: [String: Any] = [:]
        let event = FoliateMessageParser.parseRelocate(body)
        #expect(event == nil)
    }
}

// MARK: - parseSelection

@Suite("FoliateMessageParser - parseSelection")
struct ParseSelectionTests {

    @Test("valid dict with rect returns correct FoliateSelectionEvent")
    func validDict() {
        let body: [String: Any] = [
            "cfi": "epubcfi(/6/8!/4/2/3:5,/6/8!/4/2/3:42)",
            "text": "selected text passage",
            "rect": [
                "x": 100.0,
                "y": 200.0,
                "width": 250.0,
                "height": 18.0,
            ] as [String: Any],
            "index": 3,
        ]
        let event = FoliateMessageParser.parseSelection(body)
        #expect(event != nil)
        #expect(event?.cfi == "epubcfi(/6/8!/4/2/3:5,/6/8!/4/2/3:42)")
        #expect(event?.text == "selected text passage")
        #expect(event?.rect == CGRect(x: 100.0, y: 200.0, width: 250.0, height: 18.0))
        #expect(event?.sectionIndex == 3)
    }

    @Test("missing cfi returns nil")
    func missingCfi() {
        let body: [String: Any] = [
            "text": "some text",
            "rect": ["x": 0, "y": 0, "width": 100, "height": 20] as [String: Any],
            "index": 0,
        ]
        let event = FoliateMessageParser.parseSelection(body)
        #expect(event == nil)
    }

    @Test("missing text returns nil")
    func missingText() {
        let body: [String: Any] = [
            "cfi": "epubcfi(/6/4!/4/2/1:0,/6/4!/4/2/1:10)",
            "rect": ["x": 0, "y": 0, "width": 100, "height": 20] as [String: Any],
            "index": 0,
        ]
        let event = FoliateMessageParser.parseSelection(body)
        #expect(event == nil)
    }

    @Test("missing rect returns event with .zero rect (Bug #201 round 1)")
    func missingRectIsBestEffort() {
        // Bug #201 Codex round 1: rect was previously required, but the
        // highlight-create path doesn't use it. Drop only the rect when
        // missing — keep the rest of the event so highlight creation
        // survives foliate-host.js rect-shape drift.
        let body: [String: Any] = [
            "cfi": "epubcfi(/6/4!/4/2/1:0,/6/4!/4/2/1:10)",
            "text": "hello",
            "index": 0,
        ]
        let event = FoliateMessageParser.parseSelection(body)
        #expect(event != nil)
        #expect(event?.rect == .zero)
        #expect(event?.cfi == "epubcfi(/6/4!/4/2/1:0,/6/4!/4/2/1:10)")
        #expect(event?.text == "hello")
    }

    @Test("malformed rect returns event with .zero rect")
    func malformedRectIsBestEffort() {
        // Malformed rect (missing width) — same best-effort handling.
        let body: [String: Any] = [
            "cfi": "epubcfi(/6/4!/4/2/1:0,/6/4!/4/2/1:10)",
            "text": "hello",
            "index": 0,
            "rect": ["x": 0, "y": 0, "height": 20] as [String: Any],
        ]
        let event = FoliateMessageParser.parseSelection(body)
        #expect(event != nil)
        #expect(event?.rect == .zero)
    }

    @Test("empty cfi returns nil (Bug #201 round 1)")
    func emptyCFIReturnsNil() {
        // Downstream observers reject empty CFIs, so reject at parse
        // time to avoid persisting a highlight that can't paint or
        // resolve on tap.
        let body: [String: Any] = [
            "cfi": "",
            "text": "hello",
            "index": 0,
            "rect": ["x": 0, "y": 0, "width": 100, "height": 20] as [String: Any],
        ]
        let event = FoliateMessageParser.parseSelection(body)
        #expect(event == nil)
    }

    @Test("whitespace-only cfi returns nil (Bug #201 round 1)")
    func whitespaceOnlyCFIReturnsNil() {
        let body: [String: Any] = [
            "cfi": "   \n\t  ",
            "text": "hello",
            "index": 0,
            "rect": ["x": 0, "y": 0, "width": 100, "height": 20] as [String: Any],
        ]
        let event = FoliateMessageParser.parseSelection(body)
        #expect(event == nil)
    }

    @Test("missing index returns nil")
    func missingIndex() {
        let body: [String: Any] = [
            "cfi": "epubcfi(/6/4!/4/2/1:0,/6/4!/4/2/1:10)",
            "text": "hello",
            "rect": ["x": 0, "y": 0, "width": 100, "height": 20] as [String: Any],
        ]
        let event = FoliateMessageParser.parseSelection(body)
        #expect(event == nil)
    }

    @Test("collapsed selection returns nil")
    func collapsedSelection() {
        let body: [String: Any] = [
            "cfi": "epubcfi(/6/4!/4/2/1:5)",
            "text": "",
            "rect": ["x": 50, "y": 100, "width": 0, "height": 0] as [String: Any],
            "index": 0,
            "collapsed": true,
        ]
        let event = FoliateMessageParser.parseSelection(body)
        #expect(event == nil)
    }

    @Test("non-dict body returns nil")
    func nonDictBody() {
        let event = FoliateMessageParser.parseSelection(42)
        #expect(event == nil)
    }

    @Test("rect with missing width returns event with .zero rect (Bug #201 round 1)")
    func rectMissingWidthIsBestEffort() {
        // Updated semantics per Bug #201 Codex round 1: malformed rect
        // is best-effort, not fatal. Same body as the new "malformed
        // rect" test (above) but kept under the older test-name to
        // preserve git-blame continuity.
        let body: [String: Any] = [
            "cfi": "epubcfi(/6/4!/4/2/1:0,/6/4!/4/2/1:10)",
            "text": "hello",
            "rect": ["x": 0, "y": 0, "height": 20] as [String: Any],
            "index": 0,
        ]
        let event = FoliateMessageParser.parseSelection(body)
        #expect(event != nil)
        #expect(event?.rect == .zero)
    }

    @Test("CJK text in selection parses correctly")
    func cjkText() {
        let body: [String: Any] = [
            "cfi": "epubcfi(/6/10!/4/2/1:0,/6/10!/4/2/1:6)",
            "text": "这是中文文本选择",
            "rect": ["x": 50.5, "y": 120.3, "width": 180.0, "height": 22.5] as [String: Any],
            "index": 4,
        ]
        let event = FoliateMessageParser.parseSelection(body)
        #expect(event != nil)
        #expect(event?.text == "这是中文文本选择")
    }
}

// MARK: - parseBookReady

@Suite("FoliateMessageParser - parseBookReady")
struct ParseBookReadyTests {

    @Test("valid dict with TOC returns correct FoliateBookInfo")
    func validDictWithTOC() {
        let body: [String: Any] = [
            "title": "How to Make Anyone Fall in Love with You",
            "author": "Leil Lowndes",
            "language": "en",
            "sections": 65,
            "layout": "reflowable",
            "toc": [
                ["label": "Cover", "href": "cover.xhtml", "subitems": []] as [String: Any],
                ["label": "Chapter 1", "href": "ch1.xhtml", "subitems": []] as [String: Any],
            ] as [[String: Any]],
        ]
        let info = FoliateMessageParser.parseBookReady(body)
        #expect(info != nil)
        #expect(info?.title == "How to Make Anyone Fall in Love with You")
        #expect(info?.author == "Leil Lowndes")
        #expect(info?.language == "en")
        #expect(info?.sections == 65)
        #expect(info?.layout == "reflowable")
        #expect(info?.toc.count == 2)
        #expect(info?.toc[0].label == "Cover")
        #expect(info?.toc[1].label == "Chapter 1")
    }

    @Test("empty TOC array returns info with empty toc")
    func emptyTOC() {
        let body: [String: Any] = [
            "title": "Minimal Book",
            "author": "Author",
            "language": "en",
            "sections": 1,
            "layout": "reflowable",
            "toc": [] as [[String: Any]],
        ]
        let info = FoliateMessageParser.parseBookReady(body)
        #expect(info != nil)
        #expect(info?.toc.isEmpty == true)
    }

    @Test("missing title returns nil")
    func missingTitle() {
        let body: [String: Any] = [
            "author": "Author",
            "language": "en",
            "sections": 10,
            "layout": "reflowable",
            "toc": [] as [[String: Any]],
        ]
        let info = FoliateMessageParser.parseBookReady(body)
        #expect(info == nil)
    }

    @Test("missing author defaults to empty string")
    func missingAuthor() {
        let body: [String: Any] = [
            "title": "Title",
            "language": "en",
            "sections": 10,
            "layout": "reflowable",
            "toc": [] as [[String: Any]],
        ]
        let info = FoliateMessageParser.parseBookReady(body)
        #expect(info != nil)
        #expect(info?.author == "")
    }

    @Test("missing sections returns nil")
    func missingSections() {
        let body: [String: Any] = [
            "title": "Title",
            "author": "Author",
            "language": "en",
            "layout": "reflowable",
            "toc": [] as [[String: Any]],
        ]
        let info = FoliateMessageParser.parseBookReady(body)
        #expect(info == nil)
    }

    @Test("missing toc key defaults to empty array")
    func missingTOCKey() {
        let body: [String: Any] = [
            "title": "Title",
            "author": "Author",
            "language": "en",
            "sections": 10,
            "layout": "reflowable",
        ]
        let info = FoliateMessageParser.parseBookReady(body)
        #expect(info != nil)
        #expect(info?.toc.isEmpty == true)
    }

    @Test("non-dict body returns nil")
    func nonDictBody() {
        let info = FoliateMessageParser.parseBookReady([1, 2, 3])
        #expect(info == nil)
    }

    @Test("fixed layout book parses correctly")
    func fixedLayout() {
        let body: [String: Any] = [
            "title": "Comic Book",
            "author": "Artist",
            "language": "ja",
            "sections": 120,
            "layout": "pre-paginated",
            "toc": [] as [[String: Any]],
        ]
        let info = FoliateMessageParser.parseBookReady(body)
        #expect(info != nil)
        #expect(info?.layout == "pre-paginated")
        #expect(info?.language == "ja")
    }

    @Test("sections as zero parses correctly")
    func zeroSections() {
        let body: [String: Any] = [
            "title": "Empty",
            "author": "Nobody",
            "language": "en",
            "sections": 0,
            "layout": "reflowable",
            "toc": [] as [[String: Any]],
        ]
        let info = FoliateMessageParser.parseBookReady(body)
        #expect(info != nil)
        #expect(info?.sections == 0)
    }
}

// MARK: - parseTOC

@Suite("FoliateMessageParser - parseTOC")
struct ParseTOCTests {

    @Test("empty array returns empty result")
    func emptyArray() {
        let result = FoliateMessageParser.parseTOC([])
        #expect(result.isEmpty)
    }

    @Test("flat TOC items parse correctly")
    func flatItems() {
        let array: [[String: Any]] = [
            ["label": "Cover", "href": "cover.xhtml", "subitems": []] as [String: Any],
            ["label": "Preface", "href": "preface.xhtml", "subitems": []] as [String: Any],
            ["label": "Chapter 1", "href": "ch1.xhtml", "subitems": []] as [String: Any],
        ]
        let result = FoliateMessageParser.parseTOC(array)
        #expect(result.count == 3)
        #expect(result[0].label == "Cover")
        #expect(result[0].href == "cover.xhtml")
        #expect(result[0].subitems.isEmpty)
        #expect(result[1].label == "Preface")
        #expect(result[2].label == "Chapter 1")
    }

    @Test("nested subitems parse into tree structure")
    func nestedSubitems() {
        let array: [[String: Any]] = [
            [
                "label": "Part 1",
                "href": "part1.xhtml",
                "subitems": [
                    ["label": "Chapter 1", "href": "ch1.xhtml", "subitems": []] as [String: Any],
                    ["label": "Chapter 2", "href": "ch2.xhtml", "subitems": []] as [String: Any],
                ] as [[String: Any]],
            ] as [String: Any],
            [
                "label": "Part 2",
                "href": "part2.xhtml",
                "subitems": [
                    [
                        "label": "Chapter 3",
                        "href": "ch3.xhtml",
                        "subitems": [
                            ["label": "Section 3.1", "href": "s3-1.xhtml", "subitems": []] as [String: Any],
                        ] as [[String: Any]],
                    ] as [String: Any],
                ] as [[String: Any]],
            ] as [String: Any],
        ]
        let result = FoliateMessageParser.parseTOC(array)
        #expect(result.count == 2)
        #expect(result[0].label == "Part 1")
        #expect(result[0].subitems.count == 2)
        #expect(result[0].subitems[0].label == "Chapter 1")
        #expect(result[0].subitems[1].label == "Chapter 2")
        #expect(result[1].label == "Part 2")
        #expect(result[1].subitems.count == 1)
        #expect(result[1].subitems[0].label == "Chapter 3")
        #expect(result[1].subitems[0].subitems.count == 1)
        #expect(result[1].subitems[0].subitems[0].label == "Section 3.1")
    }

    @Test("item missing label is skipped")
    func missingLabel() {
        let array: [[String: Any]] = [
            ["href": "cover.xhtml", "subitems": []] as [String: Any],
            ["label": "Chapter 1", "href": "ch1.xhtml", "subitems": []] as [String: Any],
        ]
        let result = FoliateMessageParser.parseTOC(array)
        // Malformed item should be skipped, leaving only Chapter 1
        #expect(result.count == 1)
        #expect(result[0].label == "Chapter 1")
    }

    @Test("item missing href is skipped")
    func missingHref() {
        let array: [[String: Any]] = [
            ["label": "No Link", "subitems": []] as [String: Any],
            ["label": "Chapter 1", "href": "ch1.xhtml", "subitems": []] as [String: Any],
        ]
        let result = FoliateMessageParser.parseTOC(array)
        #expect(result.count == 1)
        #expect(result[0].label == "Chapter 1")
    }

    @Test("item with missing subitems key gets empty subitems")
    func missingSubitemsKey() {
        let array: [[String: Any]] = [
            ["label": "Chapter 1", "href": "ch1.xhtml"] as [String: Any],
        ]
        let result = FoliateMessageParser.parseTOC(array)
        // Should still parse with empty subitems (subitems defaults to [])
        #expect(result.count == 1)
        #expect(result[0].subitems.isEmpty)
    }

    @Test("CJK labels parse correctly")
    func cjkLabels() {
        let array: [[String: Any]] = [
            ["label": "目录", "href": "toc.xhtml", "subitems": []] as [String: Any],
            ["label": "第一章 黎明", "href": "ch1.xhtml", "subitems": []] as [String: Any],
            ["label": "第二章 黄昏", "href": "ch2.xhtml", "subitems": []] as [String: Any],
        ]
        let result = FoliateMessageParser.parseTOC(array)
        #expect(result.count == 3)
        #expect(result[0].label == "目录")
        #expect(result[1].label == "第一章 黎明")
        #expect(result[2].label == "第二章 黄昏")
    }
}

// MARK: - parseError

@Suite("FoliateMessageParser - parseError")
struct ParseErrorTests {

    @Test("valid dict returns message and type")
    func validDict() {
        let body: [String: Any] = [
            "message": "Failed to parse book: DRM protected",
            "type": "parse",
        ]
        let result = FoliateMessageParser.parseError(body)
        #expect(result != nil)
        #expect(result?.message == "Failed to parse book: DRM protected")
        #expect(result?.type == "parse")
    }

    @Test("missing message returns nil")
    func missingMessage() {
        let body: [String: Any] = [
            "type": "render",
        ]
        let result = FoliateMessageParser.parseError(body)
        #expect(result == nil)
    }

    @Test("missing type returns nil")
    func missingType() {
        let body: [String: Any] = [
            "message": "Something went wrong",
        ]
        let result = FoliateMessageParser.parseError(body)
        #expect(result == nil)
    }

    @Test("non-dict body returns nil")
    func nonDictBody() {
        let result = FoliateMessageParser.parseError("just a string")
        #expect(result == nil)
    }

    @Test("empty dict returns nil")
    func emptyDict() {
        let body: [String: Any] = [:]
        let result = FoliateMessageParser.parseError(body)
        #expect(result == nil)
    }

    @Test("message and type as non-string returns nil")
    func wrongTypes() {
        let body: [String: Any] = [
            "message": 404,
            "type": true,
        ]
        let result = FoliateMessageParser.parseError(body)
        #expect(result == nil)
    }

    @Test("render error type parses correctly")
    func renderError() {
        let body: [String: Any] = [
            "message": "CSS rendering failed for section 3",
            "type": "render",
        ]
        let result = FoliateMessageParser.parseError(body)
        #expect(result != nil)
        #expect(result?.type == "render")
    }
}

// MARK: - Cross-cutting: idempotency and type safety

@Suite("FoliateMessageParser - cross-cutting")
struct CrossCuttingTests {

    @Test("parseRelocate is idempotent — same input gives same output")
    func relocateIdempotent() {
        let body: [String: Any] = [
            "cfi": "epubcfi(/6/14!/4/2/1:0)",
            "fraction": 0.23,
            "sectionIndex": 5,
            "sectionTotal": 65,
        ]
        let first = FoliateMessageParser.parseRelocate(body)
        let second = FoliateMessageParser.parseRelocate(body)
        #expect(first == second)
    }

    @Test("parseBookReady is idempotent — same input gives same output")
    func bookReadyIdempotent() {
        let body: [String: Any] = [
            "title": "Test Book",
            "author": "Author",
            "language": "en",
            "sections": 10,
            "layout": "reflowable",
            "toc": [] as [[String: Any]],
        ]
        let first = FoliateMessageParser.parseBookReady(body)
        let second = FoliateMessageParser.parseBookReady(body)
        #expect(first == second)
    }

    @Test("NSNull values in dict are treated as missing")
    func nsNullValues() {
        let body: [String: Any] = [
            "cfi": NSNull(),
            "fraction": 0.5,
            "sectionIndex": 0,
            "sectionTotal": 10,
        ]
        let event = FoliateMessageParser.parseRelocate(body)
        #expect(event == nil)
    }

    @Test("integer fraction coerces from Int to Double")
    func integerFraction() {
        // JS may send 0 instead of 0.0
        let body: [String: Any] = [
            "cfi": "epubcfi(/6/2!/4/2)",
            "fraction": 0 as Int,
            "sectionIndex": 0,
            "sectionTotal": 1,
        ]
        let event = FoliateMessageParser.parseRelocate(body)
        #expect(event != nil)
        #expect(event?.fraction == 0.0)
    }

    @Test("extra unexpected keys do not cause failure")
    func extraKeys() {
        let body: [String: Any] = [
            "cfi": "epubcfi(/6/2!/4/2)",
            "fraction": 0.1,
            "sectionIndex": 0,
            "sectionTotal": 10,
            "unknownKey": "should be ignored",
            "anotherExtra": 42,
        ]
        let event = FoliateMessageParser.parseRelocate(body)
        #expect(event != nil)
    }
}
