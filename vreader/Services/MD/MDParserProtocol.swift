// Purpose: Protocol for Markdown parsing. Decouples the reader ViewModel
// from the concrete swift-markdown implementation for testability.
//
// Key decisions:
// - Async for background parsing (large files).
// - Returns MDDocumentInfo with both rendered text and attributed string.
// - Config parameter allows customizing appearance.
//
// @coordinates-with: MDTypes.swift, MDReaderViewModel.swift

import Foundation

/// Errors that can occur during Markdown parsing.
enum MDParserError: Error, Sendable, Equatable {
    case emptyInput
    case parsingFailed(String)
}

/// Protocol for Markdown file parsing operations.
protocol MDParserProtocol: Sendable {
    /// Parses Markdown text and renders to attributed string.
    ///
    /// - Parameters:
    ///   - text: Raw Markdown source text.
    ///   - config: Rendering configuration.
    /// - Returns: Parsed document info with rendered content.
    func parse(text: String, config: MDRenderConfig) async -> MDDocumentInfo
}
