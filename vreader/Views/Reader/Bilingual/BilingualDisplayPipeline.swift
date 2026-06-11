// Purpose: Feature #56 WI-12b — the TXT/MD bilingual display pipeline.
// Given a chapter's source text + the current `TranslationUnitID` + the
// `BilingualReadingViewModel`'s cached translation, returns the
// (display `NSAttributedString`, `BilingualDisplaySegmentMap`) pair
// that the TXT/MD container hands to the rendering bridge.
//
// Off-path (VM is nil / `isEnabled == false` / no unit / no translation
// cached for this unit) returns the source text + identity map. Off-path
// is byte-identical to the pre-bilingual code, which gates the
// R-TXT-offsets risk in the plan.
//
// Key decisions:
// - **Pure function, `@MainActor` only because it reads VM state.** No
//   I/O, no async, no network. Synchronous return.
// - **Identity-map shortcut** — when off, the pipeline returns the
//   plain source `NSAttributedString` (no attributes) and an identity
//   `BilingualDisplaySegmentMap`. This is the off-mode pass-through
//   `BilingualTextRenderer.render` already provides; the pipeline just
//   wraps the VM state check.
// - **Paragraph ranges scanned per call** — paragraph segmentation is
//   O(N) and we only call this on chapter rebuild (driven by the
//   container's `task(id: attrStringKey)`), so caching paragraph ranges
//   across calls would be premature optimisation. The off-path skips
//   the scan entirely (empty `sourceParagraphRanges` is fine for the
//   identity short-circuit).
//
// @coordinates-with: BilingualTextRenderer.swift,
//   BilingualParagraphRanges.swift, BilingualDisplaySegmentMap.swift,
//   BilingualReadingViewModel.swift, TXTReaderContainerView.swift,
//   MDReaderContainerView.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-12b)

#if canImport(UIKit)
import Foundation
import UIKit

/// Bridges chapter source + VM cache → renderer output for TXT/MD.
@MainActor
enum BilingualDisplayPipeline {

    /// Build the (display attrString, segment map) pair from a plain
    /// source string. Used when the container has not yet applied
    /// chapter typography (e.g. MD scroll mode, where the VM holds the
    /// already-typographed attrString and the pipeline produces a fresh
    /// one). For paths that have a typographed attrString already (the
    /// TXT chapter-paged path), use `compose(sourceAttributed:...)` to
    /// preserve drop-cap / heading restyle attributes.
    ///
    /// - Parameters:
    ///   - chapterSourceText: the source text of the current chapter /
    ///     unit (as the TXT/MD reader holds it pre-display).
    ///   - unit: the unit identity for this chapter; `nil` if no unit
    ///     resolves (e.g. before the chapter index is ready). A nil
    ///     unit forces the identity pass-through.
    ///   - viewModel: the bilingual VM. `nil` until the container has
    ///     constructed one; a nil VM forces the identity pass-through.
    static func makeDisplay(
        chapterSourceText: String,
        unit: TranslationUnitID?,
        viewModel: BilingualReadingViewModel?
    ) -> BilingualTextRenderer.Result {
        // Off-path: identity. Any of (no VM, VM disabled, no unit,
        // no cached translation for the unit) falls back to source +
        // identity map. The renderer's off-mode shortcut produces
        // exactly that when `translatedSegments` is nil/empty.
        guard let viewModel,
              viewModel.isEnabled,
              let unit,
              let translations = viewModel.translations(for: unit),
              !translations.isEmpty else {
            return BilingualTextRenderer.render(
                sourceText: chapterSourceText,
                sourceParagraphRanges: [],
                translatedSegments: nil
            )
        }

        // On-path: scan ranges per the book's granularity + interleave.
        // Bug #344: sentence mode scans sentence ranges through the SAME
        // segmenter the translation side uses, so counts pair 1:1 by
        // construction; the renderer's 1:1-or-nothing guard stays the
        // fail-safe for residual divergence.
        let ranges = scanRanges(
            sourceText: chapterSourceText, granularity: viewModel.granularity)
        // Bug #344 + the #266 invariant at this layer: the renderer pairs by
        // index, so a count divergence (e.g. paragraph-shaped translations
        // surviving a granularity switch) must paint source-only here —
        // never a wrong pairing.
        guard ranges.count == translations.count else {
            return BilingualTextRenderer.render(
                sourceText: chapterSourceText,
                sourceParagraphRanges: [],
                translatedSegments: nil
            )
        }
        return BilingualTextRenderer.render(
            sourceText: chapterSourceText,
            sourceParagraphRanges: ranges,
            translatedSegments: translations
        )
    }

    /// Build the (display attrString, segment map) pair from a
    /// **typographed** source `NSAttributedString`. Preserves the
    /// source's chapter-start typography (drop-cap, heading restyle,
    /// font, line spacing). Off-mode returns the source verbatim +
    /// identity map.
    ///
    /// Used by the TXT chapter-paged path, which applies its own
    /// typography via `TXTAttributedStringBuilder.buildChapterStart`.
    static func compose(
        sourceAttributed: NSAttributedString,
        unit: TranslationUnitID?,
        viewModel: BilingualReadingViewModel?
    ) -> BilingualAttributedStringComposer.Result {
        let sourceLen = sourceAttributed.length
        guard let viewModel,
              viewModel.isEnabled,
              let unit,
              let translations = viewModel.translations(for: unit),
              !translations.isEmpty else {
            return BilingualAttributedStringComposer.Result(
                attributedString: sourceAttributed,
                segmentMap: BilingualDisplaySegmentMap.identity(sourceLength: sourceLen)
            )
        }
        let ranges = scanRanges(
            sourceText: sourceAttributed.string, granularity: viewModel.granularity)
        // Same 1:1-or-nothing guard as makeDisplay (Bug #344 / #266).
        guard ranges.count == translations.count else {
            return BilingualAttributedStringComposer.Result(
                attributedString: sourceAttributed,
                segmentMap: BilingualDisplaySegmentMap.identity(sourceLength: sourceLen)
            )
        }
        return BilingualAttributedStringComposer.compose(
            sourceAttributed: sourceAttributed,
            sourceParagraphRanges: ranges,
            translatedSegments: translations
        )
    }

    /// Bug #344: the granularity-aware range scanner — paragraph ranges via
    /// `BilingualParagraphRanges`, sentence ranges via
    /// `ChapterSegmenter.sentenceRanges` (the count-parity twin of the
    /// translation side's `sentences(in:)`).
    static func scanRanges(
        sourceText: String, granularity: TranslationGranularity
    ) -> [Range<Int>] {
        switch granularity {
        case .paragraph:
            return BilingualParagraphRanges.scan(sourceText: sourceText)
        case .sentence:
            return ChapterSegmenter.sentenceRanges(in: sourceText)
        }
    }
}
#endif
