// Purpose: Loads and prepares a Markdown file for reading — file read, encoding
// detection, parse, and position restore. Extracted from MDReaderViewModel.open()
// in WI-008c to reduce VM size.
//
// Key decisions:
// - Pure function (enum namespace) — no state, no MainActor.
// - File I/O and parse run on Task.detached to avoid blocking the main actor.
// - Position restore is non-fatal (falls back to offset 0).
// - Offset is clamped to rendered text length to prevent out-of-bounds.
// - Checks Task.isCancelled between parse and position restore.
//
// @coordinates-with: MDReaderViewModel.swift, MDParserProtocol.swift,
//   ReadingPositionPersisting.swift, EncodingDetector.swift

import Foundation

/// Result of loading a Markdown file.
struct MDLoadResult: Sendable {
    let documentInfo: MDDocumentInfo
    let restoredOffsetUTF16: Int
}

/// Loads a Markdown file: reads data, detects encoding, parses, and restores position.
enum MDFileLoader {

    /// Reads the file, detects encoding, parses via the given parser, and restores
    /// the saved reading position. Throws on file read or encoding errors.
    ///
    /// Bug #178 / GH #606: `chineseConversion` (default `.none`) applies
    /// `SimpTradTransform` to the decoded source text BEFORE Markdown
    /// parsing. Mirrors `TXTReaderContainerView`'s pattern at the source-
    /// text seam (which is the only point the transform is meaningful for
    /// MD — applying after parse would break the offset alignment between
    /// `renderedText` and `renderedAttributedString`). The transform is
    /// 1:1 UTF-16 for BMP CJK characters, so reading positions and
    /// highlights in source-text coordinates remain valid across a
    /// conversion change.
    static func load(
        url: URL,
        parser: any MDParserProtocol,
        positionStore: any ReadingPositionPersisting,
        bookFingerprintKey: String,
        chineseConversion: ChineseConversionDirection = .none
    ) async throws -> MDLoadResult {
        // Stage 1: Read file, detect encoding, optionally apply Chinese
        // conversion, and parse on background thread.
        let config = MDRenderConfig.default
        let docInfo: MDDocumentInfo = try await Task.detached {
            let data = try Data(contentsOf: url)
            let result = try EncodingDetector.detect(data: data)
            let sourceText: String
            if chineseConversion != .none {
                sourceText = TextMapper.apply(
                    transforms: [SimpTradTransform(direction: chineseConversion)],
                    to: result.text
                ).text
            } else {
                sourceText = result.text
            }
            return await parser.parse(text: sourceText, config: config)
        }.value

        // Early exit if cancelled between parse and position restore
        if Task.isCancelled {
            throw CancellationError()
        }

        // Stage 2: Restore saved position (non-fatal)
        let offset = await restoreOffset(
            textLengthUTF16: docInfo.renderedTextLengthUTF16,
            positionStore: positionStore,
            bookFingerprintKey: bookFingerprintKey
        )

        return MDLoadResult(documentInfo: docInfo, restoredOffsetUTF16: offset)
    }

    // MARK: - Private

    private static func restoreOffset(
        textLengthUTF16: Int,
        positionStore: any ReadingPositionPersisting,
        bookFingerprintKey: String
    ) async -> Int {
        do {
            let savedLocator = try await positionStore.loadPosition(
                bookFingerprintKey: bookFingerprintKey
            )
            if let savedLocator, let savedOffset = savedLocator.charOffsetUTF16 {
                return clamp(savedOffset, max: textLengthUTF16)
            }
        } catch {
            // Position restore failure is non-fatal — fall back to 0
        }
        return 0
    }

    private static func clamp(_ offset: Int, max: Int) -> Int {
        min(Swift.max(offset, 0), max)
    }
}
