// Purpose: Regression-guard tests for the Chinese-conversion picker gate
// in ReaderSettingsPanel. Verifies that TXT and MD in Native reading mode
// correctly show the picker as enabled (feature #28 WI-A), while EPUB
// native mode and PDF remain disabled.
//
// @coordinates-with: vreader/Views/Reader/ReaderSettingsPanel.swift,
// vreader/Models/FormatCapabilities.swift, vreader/Models/ReadingMode.swift

import Testing
import Foundation
@testable import vreader

@Suite("ReaderSettingsPanel Chinese conversion gate (feature #28 WI-A)")
struct ReaderSettingsPanelChineseConversionGateTests {

    // MARK: - TXT

    @Test func txt_nativeMode_noDisableReason() {
        let reason = ReaderSettingsPanel.chineseConversionDisableReason(
            for: .txt,
            readingMode: .native,
            capabilities: FormatCapabilities.capabilities(for: .txt)
        )
        #expect(reason == nil, "TXT in Native mode should show picker enabled")
    }

    @Test func txt_unifiedMode_noDisableReason() {
        // TXT has no .unifiedReflow (bug #158), but if readingMode is
        // somehow set to .unified, native-path detection still fires.
        // Picker is enabled because TXT supports native transforms.
        let reason = ReaderSettingsPanel.chineseConversionDisableReason(
            for: .txt,
            readingMode: .unified,
            capabilities: FormatCapabilities.capabilities(for: .txt)
        )
        #expect(reason == nil, "TXT (no unifiedReflow) should still enable picker via native path")
    }

    // MARK: - MD

    @Test func md_nativeMode_noDisableReason() {
        let reason = ReaderSettingsPanel.chineseConversionDisableReason(
            for: .md,
            readingMode: .native,
            capabilities: FormatCapabilities.capabilities(for: .md)
        )
        #expect(reason == nil, "MD in Native mode should show picker enabled")
    }

    @Test func md_unifiedMode_noDisableReason() {
        let reason = ReaderSettingsPanel.chineseConversionDisableReason(
            for: .md,
            readingMode: .unified,
            capabilities: FormatCapabilities.capabilities(for: .md)
        )
        #expect(reason == nil, "MD in Unified mode should remain enabled")
    }

    // MARK: - EPUB

    @Test func epub_nativeMode_disabledWithNativeModeReason() {
        let reason = ReaderSettingsPanel.chineseConversionDisableReason(
            for: .epub,
            readingMode: .native,
            capabilities: FormatCapabilities.capabilities(for: .epub)
        )
        #expect(reason == .nativeMode, "EPUB in Native mode should show nativeMode disable reason")
    }

    @Test func epub_unifiedMode_noDisableReason() {
        let reason = ReaderSettingsPanel.chineseConversionDisableReason(
            for: .epub,
            readingMode: .unified,
            capabilities: FormatCapabilities.capabilities(for: .epub)
        )
        #expect(reason == nil, "EPUB in Unified mode with unifiedReflow should be enabled")
    }

    @Test func epub_complexEpub_nativeMode_disabledNativeMode() {
        let caps = FormatCapabilities.capabilities(for: .epub, isComplexEPUB: true)
        let reason = ReaderSettingsPanel.chineseConversionDisableReason(
            for: .epub,
            readingMode: .native,
            capabilities: caps
        )
        #expect(reason == .nativeMode, "Complex EPUB in Native mode should show nativeMode reason")
    }

    @Test func epub_complexEpub_unifiedMode_disabledNativeMode() {
        // Complex EPUB loses .unifiedReflow; even in unified mode, picker should be disabled.
        let caps = FormatCapabilities.capabilities(for: .epub, isComplexEPUB: true)
        let reason = ReaderSettingsPanel.chineseConversionDisableReason(
            for: .epub,
            readingMode: .unified,
            capabilities: caps
        )
        #expect(reason == .nativeMode, "Complex EPUB in Unified (but no unifiedReflow) shows nativeMode")
    }

    // MARK: - PDF

    @Test func pdf_nativeMode_disabledFormatUnsupported() {
        let reason = ReaderSettingsPanel.chineseConversionDisableReason(
            for: .pdf,
            readingMode: .native,
            capabilities: FormatCapabilities.capabilities(for: .pdf)
        )
        #expect(reason == .formatUnsupported, "PDF should always show formatUnsupported")
    }

    @Test func pdf_unifiedMode_disabledFormatUnsupported() {
        let reason = ReaderSettingsPanel.chineseConversionDisableReason(
            for: .pdf,
            readingMode: .unified,
            capabilities: FormatCapabilities.capabilities(for: .pdf)
        )
        #expect(reason == .formatUnsupported, "PDF in any mode should show formatUnsupported")
    }

    // MARK: - AZW3

    @Test func azw3_unifiedMode_noDisableReason() {
        let reason = ReaderSettingsPanel.chineseConversionDisableReason(
            for: .azw3,
            readingMode: .unified,
            capabilities: FormatCapabilities.capabilities(for: .azw3)
        )
        #expect(reason == nil, "AZW3 in Unified mode (has unifiedReflow) should be enabled")
    }

    @Test func azw3_nativeMode_disabledNativeMode() {
        let reason = ReaderSettingsPanel.chineseConversionDisableReason(
            for: .azw3,
            readingMode: .native,
            capabilities: FormatCapabilities.capabilities(for: .azw3)
        )
        #expect(reason == .nativeMode, "AZW3 in Native mode should show nativeMode reason")
    }

    // MARK: - Nil capabilities (backward compat)

    @Test func nilCaps_txt_nativeMode_noDisableReason() {
        // When capabilities aren't supplied (previews, tests), TXT native mode
        // should still enable the picker — format check wins.
        let reason = ReaderSettingsPanel.chineseConversionDisableReason(
            for: .txt,
            readingMode: .native,
            capabilities: nil
        )
        #expect(reason == nil, "TXT native mode with nil caps should be enabled")
    }

    @Test func nilCaps_epub_unifiedMode_noDisableReason() {
        // Legacy: nil caps + unified mode → fallback allows picker (matches old behavior).
        let reason = ReaderSettingsPanel.chineseConversionDisableReason(
            for: .epub,
            readingMode: .unified,
            capabilities: nil
        )
        #expect(reason == nil, "nil caps + Unified mode should fall back to enabled")
    }

    @Test func nilFormat_unifiedMode_noDisableReason() {
        // Unknown format (nil): fall through to caps-based gate.
        let reason = ReaderSettingsPanel.chineseConversionDisableReason(
            for: nil,
            readingMode: .unified,
            capabilities: [.unifiedReflow]
        )
        #expect(reason == nil, "nil format + unified + unifiedReflow caps → enabled")
    }
}
