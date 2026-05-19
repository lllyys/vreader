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
//   ReadingPositionPersisting.swift, EncodingDetector.swift,
//   ReplacementTransform.swift, SimpTradTransform.swift, TextMapper.swift

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
    /// Feature #68: `renderConfig` (default `.default`) is forwarded to
    /// `parser.parse` so the rendered attributed string picks up the
    /// theme-aware colors. Replaces the previously-hardcoded
    /// `MDRenderConfig.default`. Every existing call site that omits the
    /// argument compiles and behaves exactly as before.
    ///
    /// Feature #54 WI-7: `replacementRules` (default `[]`) wires content
    /// replacement rules into the native MD reader. The transform chain is
    /// applied to the decoded source text BEFORE `parser.parse`, in this
    /// order: `ReplacementTransform` first, then `SimpTradTransform`. (A
    /// replacement rule that targets simplified-Chinese text must run
    /// before the conversion; this order matches the pre-#54 Unified-mode
    /// pipeline.) An empty `replacementRules` is a no-op identity
    /// passthrough — every existing call site is unaffected.
    ///
    /// Offset safety: the chain runs on the *source text before parse*, and
    /// `restoreOffset` clamps the saved offset to
    /// `docInfo.renderedTextLengthUTF16` — the rendered length the
    /// post-transform parse produced. Unlike the native TXT stack, MD does
    /// not persist global *source-coordinate* offsets/boundaries, so a
    /// transform-before-parse pipeline yields self-consistent rendered
    /// coordinates. A mid-book rule edit triggers a full reload (the
    /// open-time pattern); positions are re-derived against the new
    /// rendered text — a re-derivation on reload, not a silent
    /// misplacement. This matches the existing `chineseConversion`
    /// "live re-apply requires reopen" behavior.
    static func load(
        url: URL,
        parser: any MDParserProtocol,
        positionStore: any ReadingPositionPersisting,
        bookFingerprintKey: String,
        renderConfig: MDRenderConfig = .default,
        chineseConversion: ChineseConversionDirection = .none,
        replacementRules: [ReplacementRuleDescriptor] = []
    ) async throws -> MDLoadResult {
        // Stage 1: Read file, detect encoding, apply the transform chain
        // (replacement rules → Chinese conversion), and parse on a
        // background thread.
        let config = renderConfig
        let docInfo: MDDocumentInfo = try await Task.detached {
            let data = try Data(contentsOf: url)
            let result = try EncodingDetector.detect(data: data)
            // Build the transform chain in fixed order: replacement rules
            // first, then Chinese conversion. Each element is omitted when
            // it would be a no-op so an all-empty chain skips `TextMapper`
            // entirely (identity passthrough).
            var transforms: [any TextTransform] = []
            let enabledRules = replacementRules.filter(\.enabled)
            if !enabledRules.isEmpty {
                transforms.append(ReplacementTransform(rules: enabledRules))
            }
            if chineseConversion != .none {
                transforms.append(SimpTradTransform(direction: chineseConversion))
            }
            let sourceText: String
            if transforms.isEmpty {
                sourceText = result.text
            } else {
                sourceText = TextMapper.apply(
                    transforms: transforms,
                    to: result.text
                ).text
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
