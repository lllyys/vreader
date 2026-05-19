// Purpose: Regression-guard tests for the Chinese-conversion picker gate
// in ReaderSettingsPanel. After feature #54 retired the Native/Unified
// toggle, the gate is purely format-driven: TXT and MD support native
// conversion (feature #28 WI-A) so the picker is enabled; EPUB/AZW3 have
// no native conversion path yet (deferred to feature #54 Phase D) so the
// picker is disabled with `.nativeMode`; PDF has no text-transform path
// at all so it is disabled with `.formatUnsupported`.
//
// @coordinates-with: vreader/Views/Reader/ReaderSettingsPanel.swift

import Testing
import Foundation
@testable import vreader

@Suite("ReaderSettingsPanel Chinese conversion gate (feature #54 — format-driven)")
struct ReaderSettingsPanelChineseConversionGateTests {

    // MARK: - TXT / MD — native conversion path (feature #28 WI-A)

    @Test func txt_noDisableReason() {
        #expect(
            ReaderSettingsPanel.chineseConversionDisableReason(for: .txt) == nil,
            "TXT supports native Chinese conversion — picker enabled"
        )
    }

    @Test func md_noDisableReason() {
        #expect(
            ReaderSettingsPanel.chineseConversionDisableReason(for: .md) == nil,
            "MD supports native Chinese conversion — picker enabled"
        )
    }

    // MARK: - EPUB / AZW3 — no native conversion path yet (Phase D)

    @Test func epub_disabledWithNativeModeReason() {
        #expect(
            ReaderSettingsPanel.chineseConversionDisableReason(for: .epub) == .nativeMode,
            "EPUB has no native conversion path yet — disabled with .nativeMode"
        )
    }

    @Test func azw3_disabledWithNativeModeReason() {
        #expect(
            ReaderSettingsPanel.chineseConversionDisableReason(for: .azw3) == .nativeMode,
            "AZW3 has no native conversion path yet — disabled with .nativeMode"
        )
    }

    // MARK: - PDF — no text-transform path

    @Test func pdf_disabledFormatUnsupported() {
        #expect(
            ReaderSettingsPanel.chineseConversionDisableReason(for: .pdf) == .formatUnsupported,
            "PDF has no text-transform path — disabled with .formatUnsupported"
        )
    }

    // MARK: - Unknown / nil format (backward compat)

    @Test func nilFormat_disabledWithNativeModeReason() {
        // An unknown format has no proven native conversion path —
        // conservative default is disabled (.nativeMode), matching the
        // EPUB/AZW3 not-yet-supported case.
        #expect(
            ReaderSettingsPanel.chineseConversionDisableReason(for: nil) == .nativeMode,
            "nil/unknown format defaults to disabled (.nativeMode)"
        )
    }

    // MARK: - Every BookFormat is covered

    @Test func everyBookFormatHasADefinedGate() {
        // Exhaustiveness — the gate must return the expected value for
        // every format. `expected` maps each format to its reason (a
        // non-optional dict value; `nil` reasons are listed separately
        // to avoid the double-optional `.some(.none)` subscript pitfall).
        let enabledFormats: Set<BookFormat> = [.txt, .md]
        let disabledReasons: [BookFormat: ReaderSettingsPanel.ChineseConversionDisableReason] = [
            .epub: .nativeMode,
            .azw3: .nativeMode,
            .pdf:  .formatUnsupported
        ]
        for format in BookFormat.allCases {
            let actual = ReaderSettingsPanel.chineseConversionDisableReason(for: format)
            if enabledFormats.contains(format) {
                #expect(actual == nil, "gate for \(format.rawValue) should be nil (enabled)")
            } else {
                #expect(
                    actual == disabledReasons[format],
                    "gate for \(format.rawValue) should be \(String(describing: disabledReasons[format]))"
                )
            }
        }
        // Every format is classified in exactly one bucket.
        #expect(enabledFormats.count + disabledReasons.count == BookFormat.allCases.count)
    }
}
