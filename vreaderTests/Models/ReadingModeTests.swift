// Purpose: Tests for ReadingMode enum — Codable, Equatable, default value,
// persistence integration with ReaderSettingsStore, and PDF override behavior.

import Testing
import Foundation
@testable import vreader

@Suite("ReadingMode")
struct ReadingModeTests {

    // MARK: - Default Value

    @Test func readingMode_native_isDefault() {
        // .native is the conventional "zero" case; verify it exists
        let mode = ReadingMode.native
        #expect(mode == .native)
    }

    // MARK: - Codable Round-Trip

    @Test func readingMode_codable_roundTrip_native() throws {
        let original = ReadingMode.native
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReadingMode.self, from: data)
        #expect(decoded == original)
    }

    @Test func readingMode_codable_roundTrip_unified() throws {
        let original = ReadingMode.unified
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReadingMode.self, from: data)
        #expect(decoded == original)
    }

    @Test func readingMode_codable_encodesToExpectedJSON() throws {
        let data = try JSONEncoder().encode(ReadingMode.native)
        let json = String(data: data, encoding: .utf8)
        #expect(json == "\"native\"")

        let dataU = try JSONEncoder().encode(ReadingMode.unified)
        let jsonU = String(data: dataU, encoding: .utf8)
        #expect(jsonU == "\"unified\"")
    }

    @Test func readingMode_codable_invalidRawValue_throws() {
        let data = Data("\"futuristic\"".utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ReadingMode.self, from: data)
        }
    }

    // MARK: - Equatable

    @Test func readingMode_equatable_sameValues() {
        #expect(ReadingMode.native == ReadingMode.native)
        #expect(ReadingMode.unified == ReadingMode.unified)
    }

    @Test func readingMode_equatable_differentValues() {
        #expect(ReadingMode.native != ReadingMode.unified)
        #expect(ReadingMode.unified != ReadingMode.native)
    }

    // MARK: - Hashable

    @Test func readingMode_hashable_usableInSet() {
        var set = Set<ReadingMode>()
        set.insert(.native)
        set.insert(.unified)
        set.insert(.native) // duplicate
        #expect(set.count == 2)
    }

    // MARK: - CaseIterable

    @Test func readingMode_caseIterable_containsBothCases() {
        let allCases = ReadingMode.allCases
        #expect(allCases.count == 2)
        #expect(allCases.contains(.native))
        #expect(allCases.contains(.unified))
    }

    // MARK: - Sendable

    @Test func readingMode_sendable_compiles() {
        let mode: ReadingMode = .native
        let _: any Sendable = mode
        #expect(mode == .native)
    }

    // MARK: - Raw Value

    @Test func readingMode_rawValue_matches() {
        #expect(ReadingMode.native.rawValue == "native")
        #expect(ReadingMode.unified.rawValue == "unified")
    }

    @Test func readingMode_initFromRawValue() {
        #expect(ReadingMode(rawValue: "native") == .native)
        #expect(ReadingMode(rawValue: "unified") == .unified)
        #expect(ReadingMode(rawValue: "unknown") == nil)
        #expect(ReadingMode(rawValue: "") == nil)
    }
}

// MARK: - ReaderSettingsStore + ReadingMode

@Suite("ReaderSettingsStore+ReadingMode")
@MainActor
struct ReaderSettingsStoreReadingModeTests {

    /// Creates a fresh store backed by an ephemeral UserDefaults suite.
    private func makeStore(suiteSuffix: String = UUID().uuidString) -> (ReaderSettingsStore, UserDefaults, String) {
        let suiteName = "ReadingModeTests-\(suiteSuffix)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("UserDefaults(suiteName:) should not fail")
        }
        let store = ReaderSettingsStore(defaults: defaults)
        return (store, defaults, suiteName)
    }

    @Test func settingsStore_defaultsToNative_whenNoSavedValue() {
        let (store, defaults, suiteName) = makeStore()
        #expect(store.readingMode == .native)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func settingsStore_persistsReadingMode() {
        let suiteName = "ReadingModeTests-persist-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("UserDefaults(suiteName:) should not fail")
        }

        // Write
        var store1 = ReaderSettingsStore(defaults: defaults)
        store1.readingMode = .unified
        #expect(store1.readingMode == .unified)

        // Read from fresh store
        let store2 = ReaderSettingsStore(defaults: defaults)
        #expect(store2.readingMode == .unified)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func settingsStore_persistsReadingMode_backToNative() {
        let suiteName = "ReadingModeTests-native-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("UserDefaults(suiteName:) should not fail")
        }

        var store = ReaderSettingsStore(defaults: defaults)
        store.readingMode = .unified
        store.readingMode = .native

        let restored = ReaderSettingsStore(defaults: defaults)
        #expect(restored.readingMode == .native)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func settingsStore_corruptReadingMode_fallsBackToNative() {
        let suiteName = "ReadingModeTests-corrupt-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("UserDefaults(suiteName:) should not fail")
        }

        // Write garbage
        defaults.set("holographic", forKey: ReaderSettingsStore.readingModeKey)
        let store = ReaderSettingsStore(defaults: defaults)
        #expect(store.readingMode == .native)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func settingsStore_emptyString_fallsBackToNative() {
        let suiteName = "ReadingModeTests-empty-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("UserDefaults(suiteName:) should not fail")
        }

        defaults.set("", forKey: ReaderSettingsStore.readingModeKey)
        let store = ReaderSettingsStore(defaults: defaults)
        #expect(store.readingMode == .native)

        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - PDF Always Native

    @Test func pdfFormat_alwaysUsesNative_ignoresUnifiedSetting() {
        // PDF capabilities never include .unifiedReflow
        let pdfCaps = FormatCapabilities.capabilities(for: .pdf)
        #expect(!pdfCaps.contains(.unifiedReflow))

        // Even when readingMode is .unified, PDF should not be eligible for unified
        let (store, defaults, suiteName) = makeStore()
        var mutableStore = store
        mutableStore.readingMode = .unified

        // Simulate the dispatch logic: unified only applies when format supports it
        let shouldUseUnified = mutableStore.readingMode == .unified
            && pdfCaps.contains(.unifiedReflow)
        #expect(!shouldUseUnified, "PDF must always use native, even when setting is .unified")

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func txtFormat_cannotUseUnified_evenWhenSettingIsUnified() {
        // Bug #158 / GH #468: TXT lost `.unifiedReflow` because the unified
        // TXT renderer truncated content + dropped chrome + blanked on
        // toggle. The capability removal hides the broken path; the
        // dispatcher's own `&& contains(.unifiedReflow)` guard prevents
        // dispatch even if a stale persisted preference says `.unified`.
        // This test pins that contract: TXT is always native-routed.
        let txtCaps = FormatCapabilities.capabilities(for: .txt)
        #expect(!txtCaps.contains(.unifiedReflow))

        let (store, defaults, suiteName) = makeStore()
        var mutableStore = store
        mutableStore.readingMode = .unified

        let shouldUseUnified = mutableStore.readingMode == .unified
            && txtCaps.contains(.unifiedReflow)
        #expect(!shouldUseUnified, "TXT must always use native, even when setting is .unified (bug #158)")

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func epubFormat_canUseUnified_whenSettingIsUnified() {
        let epubCaps = FormatCapabilities.capabilities(for: .epub)
        #expect(epubCaps.contains(.unifiedReflow))

        let (store, defaults, suiteName) = makeStore()
        var mutableStore = store
        mutableStore.readingMode = .unified

        let shouldUseUnified = mutableStore.readingMode == .unified
            && epubCaps.contains(.unifiedReflow)
        #expect(shouldUseUnified, "EPUB should be eligible for unified when setting is .unified")

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func complexEPUB_cannotUseUnified() {
        let complexCaps = FormatCapabilities.capabilities(for: .epub, isComplexEPUB: true)
        #expect(!complexCaps.contains(.unifiedReflow))

        let shouldUseUnified = true // readingMode == .unified
            && complexCaps.contains(.unifiedReflow)
        #expect(!shouldUseUnified, "Complex EPUB should not be eligible for unified")
    }
}
