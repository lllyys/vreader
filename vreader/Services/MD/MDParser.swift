// Purpose: Production Markdown parser. Reads raw Markdown text, converts to
// NSAttributedString via MDAttributedStringRenderer, and extracts metadata.
//
// Key decisions:
// - Async parsing runs on a detached task to avoid main-thread stalls.
// - Uses MDAttributedStringRenderer for rendering (simple regex-based until
//   swift-markdown SPM dependency is added, then will use MarkupWalker).
// - Encoding detection handled by caller (MDReaderViewModel).
//
// @coordinates-with: MDParserProtocol.swift, MDAttributedStringRenderer.swift,
//   MDMetadataExtractor.swift

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Production implementation of MDParserProtocol.
/// Parses Markdown and renders NSAttributedString off the main actor.
final class MDParser: MDParserProtocol, Sendable {

    func parse(text: String, config: MDRenderConfig) async -> MDDocumentInfo {
        // Rendering is pure computation — safe to run on any executor.
        // Using nonisolated(unsafe) is unnecessary since MDAttributedStringRenderer is a static enum.
        MDAttributedStringRenderer.render(text: text, config: config)
    }
}
