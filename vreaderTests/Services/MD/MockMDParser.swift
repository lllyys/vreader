// Purpose: Mock Markdown parser for unit testing MDReaderViewModel.
//
// @coordinates-with: MDParserProtocol.swift, MDReaderViewModelTests.swift

import Foundation
@testable import vreader

/// In-memory mock of MDParserProtocol for unit tests.
final class MockMDParser: MDParserProtocol, @unchecked Sendable {
    /// The document info to return on parse.
    var documentInfoToReturn: MDDocumentInfo?

    /// Count of parse calls.
    private(set) var parseCallCount = 0

    /// Last text passed to parse.
    private(set) var lastParsedText: String?

    func parse(text: String, config: MDRenderConfig) async -> MDDocumentInfo {
        parseCallCount += 1
        lastParsedText = text

        if let info = documentInfoToReturn {
            return info
        }

        // Default: render text as-is (no Markdown processing)
        let attrStr = NSAttributedString(string: text)
        return MDDocumentInfo(
            renderedText: text,
            renderedAttributedString: attrStr,
            headings: [],
            title: nil
        )
    }

    // MARK: - Test Helpers

    func setDocumentInfo(_ info: MDDocumentInfo?) {
        documentInfoToReturn = info
    }

    /// Creates a simple MDDocumentInfo from rendered text.
    static func makeDocumentInfo(
        renderedText: String,
        title: String? = nil,
        headings: [MDHeading] = []
    ) -> MDDocumentInfo {
        MDDocumentInfo(
            renderedText: renderedText,
            renderedAttributedString: NSAttributedString(string: renderedText),
            headings: headings,
            title: title
        )
    }
}
