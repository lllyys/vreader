// Purpose: Tests for MDTypes — MDDocumentInfo, MDRenderConfig, MDHeading.
//
// @coordinates-with: MDTypes.swift

import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#endif
@testable import vreader

@Suite("MDTypes")
struct MDTypesTests {

    // MARK: - MDDocumentInfo

    @Test("MDDocumentInfo stores rendered text and attributed string")
    func documentInfoStoresContent() {
        let text = "Hello world"
        let attrStr = NSAttributedString(string: text)
        let info = MDDocumentInfo(
            renderedText: text,
            renderedAttributedString: attrStr,
            headings: [],
            title: "Test"
        )
        #expect(info.renderedText == "Hello world")
        #expect(info.renderedAttributedString.string == "Hello world")
        #expect(info.title == "Test")
        #expect(info.headings.isEmpty)
    }

    @Test("MDDocumentInfo computes UTF-16 length correctly")
    func documentInfoUTF16Length() {
        let text = "Hello 🌍"
        let attrStr = NSAttributedString(string: text)
        let info = MDDocumentInfo(
            renderedText: text,
            renderedAttributedString: attrStr,
            headings: [],
            title: nil
        )
        #expect(info.renderedTextLengthUTF16 == (text as NSString).length)
        // "Hello " = 6, 🌍 = 2 UTF-16 code units
        #expect(info.renderedTextLengthUTF16 == 8)
    }

    @Test("MDDocumentInfo with empty text")
    func emptyDocumentInfo() {
        let info = MDDocumentInfo(
            renderedText: "",
            renderedAttributedString: NSAttributedString(string: ""),
            headings: [],
            title: nil
        )
        #expect(info.renderedText.isEmpty)
        #expect(info.renderedTextLengthUTF16 == 0)
        #expect(info.title == nil)
    }

    @Test("MDDocumentInfo with headings")
    func documentInfoWithHeadings() {
        let headings = [
            MDHeading(level: 1, text: "Title", charOffsetUTF16: 0),
            MDHeading(level: 2, text: "Section", charOffsetUTF16: 6),
        ]
        let info = MDDocumentInfo(
            renderedText: "Title\nSection\n",
            renderedAttributedString: NSAttributedString(string: "Title\nSection\n"),
            headings: headings,
            title: "Title"
        )
        #expect(info.headings.count == 2)
        #expect(info.headings[0].level == 1)
        #expect(info.headings[0].text == "Title")
        #expect(info.headings[1].level == 2)
    }

    // MARK: - MDHeading

    @Test("MDHeading is Equatable")
    func headingEquatable() {
        let h1 = MDHeading(level: 1, text: "A", charOffsetUTF16: 0)
        let h2 = MDHeading(level: 1, text: "A", charOffsetUTF16: 0)
        let h3 = MDHeading(level: 2, text: "A", charOffsetUTF16: 0)
        #expect(h1 == h2)
        #expect(h1 != h3)
    }

    // MARK: - MDRenderConfig

    @Test("MDRenderConfig has sensible defaults")
    func renderConfigDefaults() {
        let config = MDRenderConfig.default
        #expect(config.fontSize == 18)
        #expect(config.lineSpacing == 6)
    }

    @Test("MDRenderConfig is Equatable")
    func renderConfigEquatable() {
        let a = MDRenderConfig(fontSize: 18, lineSpacing: 6)
        let b = MDRenderConfig(fontSize: 18, lineSpacing: 6)
        let c = MDRenderConfig(fontSize: 20, lineSpacing: 6)
        #expect(a == b)
        #expect(a != c)
    }

    #if canImport(UIKit)
    @Test("MDRenderConfig equality includes textColor")
    func renderConfigTextColorEquality() {
        var a = MDRenderConfig(fontSize: 18, lineSpacing: 6)
        a.textColor = .red
        var b = MDRenderConfig(fontSize: 18, lineSpacing: 6)
        b.textColor = .blue
        #expect(a != b)

        var c = MDRenderConfig(fontSize: 18, lineSpacing: 6)
        c.textColor = .red
        #expect(a == c)
    }
    #endif

    // MARK: - MDParserError

    @Test("MDParserError is Equatable")
    func parserErrorEquatable() {
        #expect(MDParserError.emptyInput == MDParserError.emptyInput)
        #expect(MDParserError.parsingFailed("a") == MDParserError.parsingFailed("a"))
        #expect(MDParserError.parsingFailed("a") != MDParserError.parsingFailed("b"))
        #expect(MDParserError.emptyInput != MDParserError.parsingFailed("x"))
    }
}
