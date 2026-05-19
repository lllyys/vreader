// Purpose: Tests for BilingualReadingViewModel's WI-7a persistence/state core
// for feature #56 bilingual reading — toggle persists to PerBookSettings,
// holds translationsByUnit, exposes isEnabled / targetLanguage / granularity,
// raises needsSetupSheet on the first enable only.
//
// @coordinates-with: BilingualReadingViewModel.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-7a)

import Testing
import Foundation
@testable import vreader

@MainActor
@Suite("BilingualReadingViewModel — persistence/state core (WI-7a)")
struct BilingualReadingViewModelCoreTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BilingualVMCore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static let bookKey = "epub:aa00112233445566778899aabbccddeeff00112233445566778899aabbccdd:1024"

    // MARK: - Initial state

    @Test func freshBook_startsDisabledWithDefaults() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)
        #expect(vm.isEnabled == false)
        #expect(vm.targetLanguage == "Chinese")     // design default
        #expect(vm.granularity == .paragraph)        // design default
        #expect(vm.translationsByUnit.isEmpty)
        #expect(vm.needsSetupSheet == false)
    }

    @Test func loadsPersistedEnabledStateOnInit() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Pre-write a per-book override with bilingual on.
        try PerBookSettingsStore.save(
            PerBookSettingsOverride(
                bilingualEnabled: true,
                bilingualTargetLanguage: "Japanese",
                bilingualGranularity: "sentence"),
            for: Self.bookKey, baseURL: dir)

        let vm = BilingualReadingViewModel(
            bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)
        #expect(vm.isEnabled == true)
        #expect(vm.targetLanguage == "Japanese")
        #expect(vm.granularity == .sentence)
    }

    @Test func olderPerBookFileWithoutBilingualKeys_startsDisabled() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // A pre-#56 file (typography only, no bilingual keys).
        try PerBookSettingsStore.save(
            PerBookSettingsOverride(fontSize: 20, themeName: "dark"),
            for: Self.bookKey, baseURL: dir)
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)
        #expect(vm.isEnabled == false)
    }

    // MARK: - Toggle persistence

    @Test func enabling_persistsToPerBookSettings() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)
        vm.setEnabled(true)

        // A fresh VM reads the persisted state back.
        let reloaded = BilingualReadingViewModel(
            bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)
        #expect(reloaded.isEnabled == true)
    }

    @Test func disabling_persistsToPerBookSettings() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try PerBookSettingsStore.save(
            PerBookSettingsOverride(bilingualEnabled: true),
            for: Self.bookKey, baseURL: dir)
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)
        vm.setEnabled(false)

        let reloaded = BilingualReadingViewModel(
            bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)
        #expect(reloaded.isEnabled == false)
    }

    @Test func toggleDoesNotClobberTypographyOverrides() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Existing typography override.
        try PerBookSettingsStore.save(
            PerBookSettingsOverride(fontSize: 23, themeName: "sepia"),
            for: Self.bookKey, baseURL: dir)
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)
        vm.setEnabled(true)

        // The typography fields survive the bilingual toggle write.
        let persisted = PerBookSettingsStore.settings(for: Self.bookKey, baseURL: dir)
        #expect(persisted?.fontSize == 23)
        #expect(persisted?.themeName == "sepia")
        #expect(persisted?.bilingualEnabled == true)
    }

    @Test func settingTargetLanguage_persists() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)
        vm.setTargetLanguage("Korean")
        let reloaded = BilingualReadingViewModel(
            bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)
        #expect(reloaded.targetLanguage == "Korean")
    }

    @Test func settingGranularity_persists() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)
        vm.setGranularity(.sentence)
        let reloaded = BilingualReadingViewModel(
            bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)
        #expect(reloaded.granularity == .sentence)
    }

    // MARK: - Setup sheet

    @Test func firstEnable_raisesNeedsSetupSheet() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)
        #expect(vm.needsSetupSheet == false)
        vm.setEnabled(true)
        #expect(vm.needsSetupSheet == true)
    }

    @Test func secondEnable_doesNotRaiseSetupSheetAgain() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)
        vm.setEnabled(true)        // first enable
        vm.dismissSetupSheet()      // user completes setup
        vm.setEnabled(false)
        vm.setEnabled(true)        // re-enable
        #expect(vm.needsSetupSheet == false)
    }

    @Test func aBookAlreadyConfigured_doesNotRaiseSetupSheetOnInit() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // The book was configured in a prior session — bilingual already on.
        try PerBookSettingsStore.save(
            PerBookSettingsOverride(bilingualEnabled: true, bilingualTargetLanguage: "Chinese"),
            for: Self.bookKey, baseURL: dir)
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)
        // Already on from persistence — no setup sheet on launch.
        #expect(vm.needsSetupSheet == false)
    }

    @Test func dismissSetupSheet_clearsTheFlag() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)
        vm.setEnabled(true)
        #expect(vm.needsSetupSheet == true)
        vm.dismissSetupSheet()
        #expect(vm.needsSetupSheet == false)
    }

    @Test func configuredThenDisabledBook_doesNotReRaiseSetupSheetOnReEnable() throws {
        // Reload-from-disk variant: a book configured in a prior session but
        // persisted as DISABLED must not re-raise the setup sheet when the
        // user toggles it back on — `hasBeenConfigured` keys on the presence
        // of any bilingual key, not on `bilingualEnabled == true`.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try PerBookSettingsStore.save(
            PerBookSettingsOverride(
                bilingualEnabled: false, bilingualTargetLanguage: "Chinese"),
            for: Self.bookKey, baseURL: dir)
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)
        vm.setEnabled(true)
        #expect(vm.needsSetupSheet == false)
    }

    // MARK: - Granularity back-compat

    @Test func garbageStoredGranularity_fallsBackToParagraph() throws {
        // A per-book file carrying an unknown/future granularity string must
        // decode to the safe .paragraph default, not crash or stay nil.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try PerBookSettingsStore.save(
            PerBookSettingsOverride(
                bilingualEnabled: true, bilingualGranularity: "future-value"),
            for: Self.bookKey, baseURL: dir)
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)
        #expect(vm.granularity == .paragraph)
    }

    // MARK: - translationsByUnit

    @Test func translationsByUnit_canBeStoredAndReadByUnit() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)
        let unit = TranslationUnitID(kind: .epubHref, value: "ch1.xhtml")
        vm.setTranslations(["你好", "世界"], for: unit)
        #expect(vm.translationsByUnit[unit] == ["你好", "世界"])
        #expect(vm.translations(for: unit) == ["你好", "世界"])
    }

    @Test func translations_forUncachedUnit_isNil() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)
        let unit = TranslationUnitID(kind: .epubHref, value: "missing.xhtml")
        #expect(vm.translations(for: unit) == nil)
    }

    @Test func disabling_clearsTranslationsByUnit() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)
        vm.setEnabled(true)
        vm.setTranslations(["译"], for: TranslationUnitID(kind: .epubHref, value: "a"))
        #expect(vm.translationsByUnit.isEmpty == false)
        vm.setEnabled(false)
        #expect(vm.translationsByUnit.isEmpty)
    }
}
