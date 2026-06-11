// Purpose: Feature #99 WI-3 — pins the More-menu "Translation settings"
// row contract (bilingual-gated visibility, declared order, chevron,
// notification + effect mapping, the context-driven sub-line), the
// divider-anchor chain, the `.readerBilingualDidChange` granularity
// payload, and the keyed `.readerMoreTranslationSettings` contract.

import Foundation
import Testing
@testable import vreader

@Suite("Feature #99 WI-3 — Translation settings row + mirrors")
struct ReaderMoreMenuTranslationSettingsTests {

    // MARK: - Visibility + order

    @Test func rowHiddenWhenBilingualOff() {
        let rows = ReaderMoreMenuRow.visibleRows(for: nil, bilingualOn: false)
        #expect(!rows.contains(.translationSettings))
    }

    @Test func rowVisibleAndOrderedInsideTheClusterWhenOn() {
        let rows = ReaderMoreMenuRow.visibleRows(for: nil, bilingualOn: true)
        let bilingualIdx = try! #require(rows.firstIndex(of: .bilingual))
        let settingsIdx = try! #require(rows.firstIndex(of: .translationSettings))
        let reTransIdx = try! #require(rows.firstIndex(of: .reTranslateChapter))
        // Declared order: toggle row → settings row → re-translate row.
        #expect(settingsIdx == bilingualIdx + 1)
        #expect(reTransIdx == settingsIdx + 1)
    }

    @Test func dividerAnchorPrefersTheLastClusterRow() {
        // All three present → re-translate stays the anchor.
        #expect(ReaderMoreMenuRow.dividerAnchor(
            in: [.bilingual, .translationSettings, .reTranslateChapter, .bookDetails])
            == .reTranslateChapter)
        // Hypothetical settings-without-re-translate → settings anchors.
        #expect(ReaderMoreMenuRow.dividerAnchor(
            in: [.bilingual, .translationSettings, .bookDetails])
            == .translationSettings)
    }

    // MARK: - Row contract

    @Test func rowContract() {
        let row = ReaderMoreMenuRow.translationSettings
        #expect(row.label == "Translation settings")
        #expect(row.notification == .readerMoreTranslationSettings)
        #expect(ReaderMoreMenuRow(notification: .readerMoreTranslationSettings)
            == .translationSettings)
        #expect(row.trailingControl(bilingualState: .on(targetLanguage: "Chinese"),
                                    autoTurnOn: false) == .chevron)
        #expect(ReaderMoreMenuEffect(row: row) == .presentTranslationSettings)
        #expect(row.accessibilityIdentifier == "readerMoreTranslationSettings")
    }

    // MARK: - Sub-line context

    @Test func subtitleWithProvider() {
        let context = ReaderMoreMenuBilingualContext(
            languageDisplay: "Chinese", granularityDisplay: "Paragraph",
            providerDisplay: "Claude")
        #expect(context.settingsSubtitle == "Chinese \u{B7} Paragraph \u{B7} Claude")
    }

    @Test func subtitleDropsUnresolvedProvider() {
        let nilProvider = ReaderMoreMenuBilingualContext(
            languageDisplay: "Chinese", granularityDisplay: "Sentence",
            providerDisplay: nil)
        #expect(nilProvider.settingsSubtitle == "Chinese \u{B7} Sentence")
        let emptyProvider = ReaderMoreMenuBilingualContext(
            languageDisplay: "French", granularityDisplay: "Paragraph",
            providerDisplay: "")
        #expect(emptyProvider.settingsSubtitle == "French \u{B7} Paragraph")
    }

    @Test func rowSubDetailReadsTheContext() {
        let context = ReaderMoreMenuBilingualContext(
            languageDisplay: "Chinese", granularityDisplay: "Paragraph",
            providerDisplay: "Claude")
        let sub = ReaderMoreMenuRow.translationSettings.subDetail(
            ttsPlaying: false, autoTurnOn: false, autoTurnInterval: 10,
            bilingualState: .on(targetLanguage: "Chinese"),
            bilingualContext: context)
        #expect(sub == "Chinese \u{B7} Paragraph \u{B7} Claude")
        // No context → no sub-line (presentation degrades gracefully).
        #expect(ReaderMoreMenuRow.translationSettings.subDetail(
            ttsPlaying: false, autoTurnOn: false, autoTurnInterval: 10) == nil)
    }

    // MARK: - Granularity payload (Gate-2 H1)

    @Test @MainActor func postDidChangeCarriesGranularity() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("f99-wi3-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: "epub:f99:1", perBookBaseURL: tmp)

        nonisolated(unsafe) var payload: [AnyHashable: Any]?
        let token = NotificationCenter.default.addObserver(
            forName: .readerBilingualDidChange, object: nil, queue: nil
        ) { note in payload = note.userInfo }
        defer { NotificationCenter.default.removeObserver(token) }

        vm.setGranularity(.sentence)
        let info = try #require(payload)
        #expect(info["granularity"] as? String == TranslationGranularity.sentence.rawValue)
        #expect(info["targetLanguage"] as? String == vm.targetLanguage)
        #expect(info["fingerprintKey"] as? String == "epub:f99:1")
    }
}
