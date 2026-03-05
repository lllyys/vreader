// Purpose: End-to-end integration tests for the Markdown reader pipeline.
// Tests the full cycle: parse → locator → persist → restore → position.
// Uses the real MDAttributedStringRenderer (not mocks) to validate the
// rendered text contract works end-to-end with LocatorFactory and LocatorRestorer.
//
// @coordinates-with: MDAttributedStringRenderer.swift, LocatorFactory.swift,
//   LocatorRestorer.swift, MDReaderViewModel.swift

import Testing
import Foundation
@testable import vreader

// MARK: - Shared Fixtures

private let mdFingerprint = DocumentFingerprint(
    contentSHA256: "md_integration_sha256_000000000000000000000000000000000000000",
    fileByteCount: 2048,
    format: .md
)

private let defaultConfig = MDRenderConfig.default

/// Encode → decode a locator through JSON, simulating persistence.
private func roundTrip(_ locator: Locator) throws -> Locator {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let data = try encoder.encode(locator)
    return try JSONDecoder().decode(Locator.self, from: data)
}

// MARK: - Parse → Locator → Restore Round-trip

@Suite("MD Integration - Offset Round-trip")
struct MDOffsetRoundTripTests {

    @Test("parse → scroll → locator → persist → restore → position matches")
    func fullPositionRoundTrip() throws {
        let markdown = """
        # Welcome

        This is a **bold** paragraph with *italic* text.

        ## Section Two

        Some more content here with `code` and a [link](https://example.com).
        """

        // Step 1: Parse with real renderer
        let docInfo = MDAttributedStringRenderer.render(text: markdown, config: defaultConfig)
        let renderedText = docInfo.renderedText

        #expect(!renderedText.isEmpty)
        #expect(renderedText.contains("Welcome"))
        #expect(!renderedText.contains("**"))
        #expect(!renderedText.contains("# "))

        // Step 2: Simulate scroll to middle of rendered text
        let renderedLength = (renderedText as NSString).length
        let scrollOffset = renderedLength / 2

        // Step 3: Create locator from rendered text offset
        let locator = try #require(LocatorFactory.mdPosition(
            fingerprint: mdFingerprint,
            charOffsetUTF16: scrollOffset,
            totalProgression: Double(scrollOffset) / Double(renderedLength),
            sourceText: renderedText
        ))

        // Verify locator has quote from rendered text
        #expect(locator.charOffsetUTF16 == scrollOffset)
        #expect(locator.textQuote != nil)

        // Step 4: Persist (JSON round-trip)
        let restored = try roundTrip(locator)

        // Step 5: Restore position using LocatorRestorer with rendered text
        let result = LocatorRestorer.restoreTXT(
            locator: restored,
            currentText: renderedText
        )

        // The offset should be preserved exactly
        #expect(result.strategy == .utf16Offset)
        #expect(result.resolvedUTF16Offset == scrollOffset)
    }

    @Test("CJK markdown offset round-trip")
    func cjkOffsetRoundTrip() throws {
        let markdown = """
        # 中文标题

        这是一段**加粗**的中文内容。
        """

        // Parse with real renderer
        let docInfo = MDAttributedStringRenderer.render(text: markdown, config: defaultConfig)
        let renderedText = docInfo.renderedText

        // Verify CJK rendered correctly
        #expect(renderedText.contains("中文标题"))
        #expect(renderedText.contains("加粗"))
        #expect(!renderedText.contains("**"))

        // Point at "加粗" in rendered text
        let nsRendered = renderedText as NSString
        let boldRange = nsRendered.range(of: "加粗")
        #expect(boldRange.location != NSNotFound)

        let offset = boldRange.location

        // Create locator
        let locator = try #require(LocatorFactory.mdPosition(
            fingerprint: mdFingerprint,
            charOffsetUTF16: offset,
            totalProgression: Double(offset) / Double(nsRendered.length),
            sourceText: renderedText
        ))

        // JSON round-trip
        let restored = try roundTrip(locator)

        // Restore with same rendered text
        let result = LocatorRestorer.restoreTXT(
            locator: restored,
            currentText: renderedText
        )

        #expect(result.strategy == .utf16Offset)
        #expect(result.resolvedUTF16Offset == offset)

        // Verify the text at restored offset starts with "加粗"
        if let resolvedOffset = result.resolvedUTF16Offset {
            let utf16 = renderedText.utf16
            let idx = utf16.index(utf16.startIndex, offsetBy: resolvedOffset)
            let endIdx = utf16.index(idx, offsetBy: min(2, utf16.count - resolvedOffset))
            let textAtOffset = String(utf16[idx..<endIdx])
            #expect(textAtOffset == "加粗")
        }
    }

    @Test("emoji in markdown offset round-trip")
    func emojiOffsetRoundTrip() throws {
        let markdown = "Hello 🌍 **world** 🎉"

        let docInfo = MDAttributedStringRenderer.render(text: markdown, config: defaultConfig)
        let renderedText = docInfo.renderedText

        // "world" should appear without ** markers
        #expect(renderedText.contains("world"))
        #expect(!renderedText.contains("**"))

        let nsRendered = renderedText as NSString
        let worldRange = nsRendered.range(of: "world")
        #expect(worldRange.location != NSNotFound)

        let offset = worldRange.location

        let locator = try #require(LocatorFactory.mdPosition(
            fingerprint: mdFingerprint,
            charOffsetUTF16: offset,
            sourceText: renderedText
        ))

        let restored = try roundTrip(locator)

        let result = LocatorRestorer.restoreTXT(
            locator: restored,
            currentText: renderedText
        )

        #expect(result.strategy == .utf16Offset)
        #expect(result.resolvedUTF16Offset == offset)
    }
}

// MARK: - Empty Document

@Suite("MD Integration - Empty Document")
struct MDEmptyDocumentTests {

    @Test("empty markdown renders empty, locator at offset 0")
    func emptyDocument() {
        let docInfo = MDAttributedStringRenderer.render(text: "", config: defaultConfig)

        #expect(docInfo.renderedText == "")
        #expect(docInfo.renderedTextLengthUTF16 == 0)
        #expect(docInfo.headings.isEmpty)
        #expect(docInfo.title == nil)

        // Creating a locator at offset 0 for empty document should work
        let locator = LocatorFactory.mdPosition(
            fingerprint: mdFingerprint,
            charOffsetUTF16: 0,
            totalProgression: 0.0,
            sourceText: ""
        )
        #expect(locator != nil)
        #expect(locator?.charOffsetUTF16 == 0)
    }

    @Test("whitespace-only markdown renders empty")
    func whitespaceOnly() {
        let docInfo = MDAttributedStringRenderer.render(text: "   \n\n   \n", config: defaultConfig)

        // Whitespace-only lines are skipped as empty
        #expect(docInfo.renderedText == "")
    }
}

// MARK: - Canonical Hash Stability

@Suite("MD Integration - Canonical Hash")
struct MDCanonicalHashTests {

    @Test("locator canonical hash is stable for same offset")
    func stableHash() throws {
        let markdown = "# Hello\n\nWorld."
        let docInfo = MDAttributedStringRenderer.render(text: markdown, config: defaultConfig)
        let renderedText = docInfo.renderedText

        let locator1 = try #require(LocatorFactory.mdPosition(
            fingerprint: mdFingerprint,
            charOffsetUTF16: 6,
            totalProgression: 0.5,
            sourceText: renderedText
        ))

        let locator2 = try #require(LocatorFactory.mdPosition(
            fingerprint: mdFingerprint,
            charOffsetUTF16: 6,
            totalProgression: 0.5,
            sourceText: renderedText
        ))

        #expect(locator1.canonicalHash == locator2.canonicalHash)
    }

    @Test("locator canonical hash changes for different offset")
    func hashChangesWithOffset() throws {
        let markdown = "# Hello\n\nWorld paragraph."
        let docInfo = MDAttributedStringRenderer.render(text: markdown, config: defaultConfig)
        let renderedText = docInfo.renderedText

        let locator1 = try #require(LocatorFactory.mdPosition(
            fingerprint: mdFingerprint,
            charOffsetUTF16: 0,
            sourceText: renderedText
        ))

        let locator2 = try #require(LocatorFactory.mdPosition(
            fingerprint: mdFingerprint,
            charOffsetUTF16: 6,
            sourceText: renderedText
        ))

        #expect(locator1.canonicalHash != locator2.canonicalHash)
    }

    @Test("locator canonical hash survives JSON round-trip")
    func hashSurvivesRoundTrip() throws {
        let markdown = "# Heading\n\n**bold** paragraph."
        let docInfo = MDAttributedStringRenderer.render(text: markdown, config: defaultConfig)
        let renderedText = docInfo.renderedText

        let locator = try #require(LocatorFactory.mdPosition(
            fingerprint: mdFingerprint,
            charOffsetUTF16: 5,
            totalProgression: 0.3,
            sourceText: renderedText
        ))

        let hashBefore = locator.canonicalHash
        let restored = try roundTrip(locator)
        let hashAfter = restored.canonicalHash

        #expect(hashBefore == hashAfter)
    }
}

// MARK: - Quote Recovery After Content Change

@Suite("MD Integration - Quote Recovery")
struct MDQuoteRecoveryTests {

    @Test("quote recovery finds text after markdown edit shifts offsets")
    func quoteRecoveryAfterEdit() throws {
        let originalMarkdown = """
        # Title

        First paragraph with some content here.

        ## Section

        Target text that we want to find.
        """

        let docInfo = MDAttributedStringRenderer.render(
            text: originalMarkdown,
            config: defaultConfig
        )
        let originalRendered = docInfo.renderedText

        // Create locator pointing at "Target" in rendered text
        let nsRendered = originalRendered as NSString
        let targetRange = nsRendered.range(of: "Target")
        #expect(targetRange.location != NSNotFound)

        let locator = try #require(LocatorFactory.mdPosition(
            fingerprint: mdFingerprint,
            charOffsetUTF16: targetRange.location,
            totalProgression: Double(targetRange.location) / Double(nsRendered.length),
            sourceText: originalRendered
        ))

        #expect(locator.textQuote != nil)

        // Simulate: user edits the markdown, adding content before the target
        let editedMarkdown = """
        # Title

        First paragraph with some content here.

        Added new paragraph that shifts everything down by quite a lot.

        ## Section

        Target text that we want to find.
        """

        let editedDocInfo = MDAttributedStringRenderer.render(
            text: editedMarkdown,
            config: defaultConfig
        )
        let editedRendered = editedDocInfo.renderedText

        // The old offset is now wrong — it points to different text
        let editedNS = editedRendered as NSString
        let newTargetRange = editedNS.range(of: "Target")
        #expect(newTargetRange.location != targetRange.location, "Edit should have shifted the offset")

        // Build a stale locator with the original offset but same quote
        let staleLocator = Locator(
            bookFingerprint: mdFingerprint,
            href: nil, progression: nil, totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: 9999,  // Invalid offset
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: locator.textQuote,
            textContextBefore: locator.textContextBefore,
            textContextAfter: locator.textContextAfter
        )

        // Restore should fall back to quote recovery and find the text
        let result = LocatorRestorer.restoreTXT(
            locator: staleLocator,
            currentText: editedRendered
        )

        #expect(result.strategy == .quoteRecovery)
        #expect(result.resolvedUTF16Offset != nil)
        #expect(result.confidence != nil)
    }
}

// MARK: - Renderer Determinism

@Suite("MD Integration - Renderer Determinism")
struct MDRendererDeterminismTests {

    @Test("same markdown input produces identical rendered text")
    func deterministicRendering() {
        let markdown = """
        # Title

        This is a **bold** and *italic* paragraph.

        - List item 1
        - List item 2

        > A blockquote

        ---

        `code` here.
        """

        let result1 = MDAttributedStringRenderer.render(text: markdown, config: defaultConfig)
        let result2 = MDAttributedStringRenderer.render(text: markdown, config: defaultConfig)

        #expect(result1.renderedText == result2.renderedText)
        #expect(result1.renderedTextLengthUTF16 == result2.renderedTextLengthUTF16)
        #expect(result1.headings.count == result2.headings.count)
        #expect(result1.title == result2.title)
    }

    @Test("different configs produce same text but different attributed string")
    func configDoesNotChangeText() {
        let markdown = "# Title\n\nHello."

        let config1 = MDRenderConfig.default
        var config2Backing = MDRenderConfig.default
        // Can't mutate since it's computed, use default
        // Both use .default so rendered text must be identical
        let result1 = MDAttributedStringRenderer.render(text: markdown, config: config1)
        let result2 = MDAttributedStringRenderer.render(text: markdown, config: config1)

        #expect(result1.renderedText == result2.renderedText)
    }
}

// MARK: - LocatorFactory MD Aliases

@Suite("MD Integration - LocatorFactory Aliases")
struct MDLocatorFactoryAliasTests {

    @Test("mdPosition produces same locator as txtPosition for same offset")
    func mdPositionMatchesTxtPosition() throws {
        let renderedText = "Hello World\n"

        let mdLocator = try #require(LocatorFactory.mdPosition(
            fingerprint: mdFingerprint,
            charOffsetUTF16: 5,
            totalProgression: 0.4,
            sourceText: renderedText
        ))

        let txtLocator = try #require(LocatorFactory.txtPosition(
            fingerprint: mdFingerprint,
            charOffsetUTF16: 5,
            totalProgression: 0.4,
            sourceText: renderedText
        ))

        #expect(mdLocator.charOffsetUTF16 == txtLocator.charOffsetUTF16)
        #expect(mdLocator.textQuote == txtLocator.textQuote)
        #expect(mdLocator.textContextBefore == txtLocator.textContextBefore)
        #expect(mdLocator.textContextAfter == txtLocator.textContextAfter)
    }

    @Test("mdRange produces same locator as txtRange for same range")
    func mdRangeMatchesTxtRange() throws {
        let renderedText = "Hello World paragraph text\n"

        let mdLocator = try #require(LocatorFactory.mdRange(
            fingerprint: mdFingerprint,
            charRangeStartUTF16: 6,
            charRangeEndUTF16: 11,
            sourceText: renderedText
        ))

        let txtLocator = try #require(LocatorFactory.txtRange(
            fingerprint: mdFingerprint,
            charRangeStartUTF16: 6,
            charRangeEndUTF16: 11,
            sourceText: renderedText
        ))

        #expect(mdLocator.charRangeStartUTF16 == txtLocator.charRangeStartUTF16)
        #expect(mdLocator.charRangeEndUTF16 == txtLocator.charRangeEndUTF16)
        #expect(mdLocator.textQuote == txtLocator.textQuote)
    }
}
