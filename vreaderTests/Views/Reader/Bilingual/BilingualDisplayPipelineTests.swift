// Purpose: Feature #56 WI-12b — pin the TXT/MD bilingual display pipeline
// that bridges chapter source + view-model state into the
// `(NSAttributedString, BilingualDisplaySegmentMap)` pair the TXT/MD
// containers consume. Off-mode (`isEnabled == false`, or no VM, or no
// translation cached for the unit) returns the source string + identity
// map verbatim — the byte-identical pass-through that gates the R-TXT-
// offsets risk.
//
// @coordinates-with: BilingualDisplayPipeline.swift,
//   BilingualTextRenderer.swift, BilingualDisplaySegmentMap.swift,
//   BilingualReadingViewModel.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-12b)

import Testing
import Foundation
@testable import vreader

@Suite("Feature #56 WI-12b — BilingualDisplayPipeline")
struct BilingualDisplayPipelineTests {

    // MARK: - off-mode pass-through

    @Test("nil VM returns source identity")
    @MainActor func nilVM() {
        let source = "Hello world"
        let result = BilingualDisplayPipeline.makeDisplay(
            chapterSourceText: source,
            unit: nil,
            viewModel: nil
        )
        #expect(result.attributedString.string == source)
        #expect(result.segmentMap == BilingualDisplaySegmentMap.identity(sourceLength: source.utf16.count))
    }

    @Test("disabled VM returns source identity")
    @MainActor func disabledVM() {
        let source = "Hello world"
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: "test-key", perBookBaseURL: tempBaseURL())
        let unit = TranslationUnitID(kind: .txtChapterIndex, value: "0")
        // VM defaults to disabled.
        let result = BilingualDisplayPipeline.makeDisplay(
            chapterSourceText: source,
            unit: unit,
            viewModel: vm
        )
        #expect(result.attributedString.string == source)
        #expect(result.segmentMap == BilingualDisplaySegmentMap.identity(sourceLength: source.utf16.count))
    }

    @Test("enabled VM with no translation cached returns source identity")
    @MainActor func enabledButUncached() {
        let source = "First paragraph.\n\nSecond paragraph."
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: "test-key", perBookBaseURL: tempBaseURL())
        vm.setEnabled(true)
        vm.dismissSetupSheet()
        let unit = TranslationUnitID(kind: .txtChapterIndex, value: "0")
        let result = BilingualDisplayPipeline.makeDisplay(
            chapterSourceText: source,
            unit: unit,
            viewModel: vm
        )
        // Off-path: cached translation absent → identity map.
        #expect(result.attributedString.string == source)
        #expect(result.segmentMap == BilingualDisplaySegmentMap.identity(sourceLength: source.utf16.count))
    }

    @Test("nil unit returns identity even with enabled VM")
    @MainActor func enabledButNoUnit() {
        let source = "Hello world"
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: "test-key", perBookBaseURL: tempBaseURL())
        vm.setEnabled(true)
        vm.dismissSetupSheet()
        let result = BilingualDisplayPipeline.makeDisplay(
            chapterSourceText: source,
            unit: nil,
            viewModel: vm
        )
        #expect(result.attributedString.string == source)
        #expect(result.segmentMap == BilingualDisplaySegmentMap.identity(sourceLength: source.utf16.count))
    }

    // MARK: - on-mode interleave

    @Test("enabled VM with cached translation interleaves source + translation")
    @MainActor func enabledWithCachedTranslation() {
        let source = "First paragraph.\n\nSecond paragraph."
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: "test-key", perBookBaseURL: tempBaseURL())
        vm.setEnabled(true)
        vm.dismissSetupSheet()
        let unit = TranslationUnitID(kind: .txtChapterIndex, value: "0")
        vm.setTranslations(["Translation 1.", "Translation 2."], for: unit)

        let result = BilingualDisplayPipeline.makeDisplay(
            chapterSourceText: source,
            unit: unit,
            viewModel: vm
        )

        // Display contains both source paragraphs + both translations.
        #expect(result.attributedString.string.contains("First paragraph."))
        #expect(result.attributedString.string.contains("Second paragraph."))
        #expect(result.attributedString.string.contains("Translation 1."))
        #expect(result.attributedString.string.contains("Translation 2."))
        // Segment map is NOT identity — synthetic runs are present.
        #expect(result.segmentMap != BilingualDisplaySegmentMap.identity(sourceLength: source.utf16.count))
        // Source length matches the original.
        #expect(result.segmentMap.sourceLength == source.utf16.count)
    }

    @Test("empty source with enabled VM returns identity")
    @MainActor func emptySource() {
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: "test-key", perBookBaseURL: tempBaseURL())
        vm.setEnabled(true)
        vm.dismissSetupSheet()
        let unit = TranslationUnitID(kind: .txtChapterIndex, value: "0")
        vm.setTranslations(["should not show"], for: unit)

        let result = BilingualDisplayPipeline.makeDisplay(
            chapterSourceText: "",
            unit: unit,
            viewModel: vm
        )
        #expect(result.attributedString.string == "")
        #expect(result.segmentMap.displayLength == 0)
    }

    // MARK: - helpers

    private func tempBaseURL() -> URL {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("vreader-bilingual-pipeline-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        return temp
    }
}
