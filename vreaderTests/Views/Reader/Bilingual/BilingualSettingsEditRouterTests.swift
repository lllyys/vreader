// Purpose: Feature #99 WI-4 — pins the shared edit-confirm routing
// (dirty computed BEFORE the setters mutate the baseline; the banner
// notification only for a genuinely new language; `needsSetupSheet`
// untouched), the generation-stamped cached-languages fetcher races,
// and the banner copy.

import Foundation
import SwiftData
import Testing
@testable import vreader

@Suite("BilingualSettingsEditRouter (feature #99 WI-4)")
@MainActor
struct BilingualSettingsEditRouterTests {

    private func makeVM(
        language: String = "Chinese", granularity: TranslationGranularity = .paragraph
    ) throws -> (BilingualReadingViewModel, URL) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("f99-wi4-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: "epub:f99wi4:1", perBookBaseURL: tmp)
        vm.setEnabled(true)
        vm.dismissSetupSheet()
        vm.setTargetLanguage(language)
        vm.setGranularity(granularity)
        return (vm, tmp)
    }

    @Test func confirmAppliesDraftThroughTheSetters() throws {
        let (vm, tmp) = try makeVM()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let draft = BilingualSetupSheetState(languageKey: "Japanese", granularity: .sentence)

        let dirty = BilingualSettingsEditRouter.confirmEdit(
            vm: vm, draft: draft, cachedLanguages: [])

        #expect(dirty == .newLanguage)
        #expect(vm.targetLanguage == "Japanese")
        #expect(vm.granularity == .sentence)
        #expect(!vm.needsSetupSheet)   // edit confirm never raises first-enable
        #expect(vm.isEnabled)          // and never touches the toggle
    }

    @Test func dirtyIsComputedBeforeTheSettersMutateTheBaseline() throws {
        // If the router applied first, current == draft and dirty would
        // collapse to .none — the cached switch would lose its banner-free
        // instant semantics AND "Done" framing distinctions downstream.
        let (vm, tmp) = try makeVM()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let draft = BilingualSetupSheetState(languageKey: "French", granularity: .paragraph)

        let dirty = BilingualSettingsEditRouter.confirmEdit(
            vm: vm, draft: draft, cachedLanguages: ["French"])

        #expect(dirty == .cachedLanguage)
        #expect(vm.targetLanguage == "French")
    }

    @Test func cleanConfirmIsANoOp() throws {
        let (vm, tmp) = try makeVM()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let dirty = BilingualSettingsEditRouter.confirmEdit(
            vm: vm,
            draft: BilingualSetupSheetState(languageKey: "Chinese", granularity: .paragraph),
            cachedLanguages: ["Chinese"])
        #expect(dirty == .none)
        #expect(vm.targetLanguage == "Chinese")
    }

    @Test func bannerPostsOnlyForANewLanguageWithBothLanguages() throws {
        let (vm, tmp) = try makeVM()
        defer { try? FileManager.default.removeItem(at: tmp) }

        nonisolated(unsafe) var payloads: [[AnyHashable: Any]] = []
        let token = NotificationCenter.default.addObserver(
            forName: .readerBilingualRetranslateStarted, object: nil, queue: nil
        ) { note in payloads.append(note.userInfo ?? [:]) }
        defer { NotificationCenter.default.removeObserver(token) }

        // Cached switch → no banner.
        BilingualSettingsEditRouter.confirmEdit(
            vm: vm,
            draft: BilingualSetupSheetState(languageKey: "French", granularity: .paragraph),
            cachedLanguages: ["French"])
        #expect(payloads.isEmpty)

        // New language → banner with new + previous languages.
        BilingualSettingsEditRouter.confirmEdit(
            vm: vm,
            draft: BilingualSetupSheetState(languageKey: "Japanese", granularity: .paragraph),
            cachedLanguages: ["Chinese", "French"])
        #expect(payloads.count == 1)
        #expect(payloads[0]["fingerprintKey"] as? String == "epub:f99wi4:1")
        #expect(payloads[0]["language"] as? String == "Japanese")
        #expect(payloads[0]["previousLanguage"] as? String == "French")
    }

    @Test func bannerDetailCopy() {
        #expect(BilingualRetranslateBanner.detail(previousLanguage: "Chinese")
            == "Cached Chinese stays \u{2014} switch back anytime")
    }
}

// MARK: - Cached-languages fetcher races

@Suite("BilingualCachedLanguagesFetcher (feature #99 WI-4)")
@MainActor
struct BilingualCachedLanguagesFetcherTests {

    private static let profile = UUID(uuidString: "AAAAAAAA-0000-0000-0000-00000000000A")!

    private func makeStore(languages: [String], book: String) throws -> ChapterTranslationStore {
        let schema = Schema(SchemaV7.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let store = ChapterTranslationStore(modelContainer: container)
        Task {
            for (i, lang) in languages.enumerated() {
                try? await store.upsert(ChapterTranslationRecord(
                    bookFingerprintKey: book, unitStorageKey: "u\(i)",
                    targetLanguage: lang, providerProfileID: Self.profile,
                    promptVersion: "v1", translatedSegments: ["x"],
                    sourceParagraphCount: 1))
            }
        }
        return store
    }

    @Test func fetchAppliesTheResult() async throws {
        let store = try makeStore(languages: ["Chinese", "French"], book: "fp1")
        try await Task.sleep(for: .milliseconds(150))  // let the seed land
        let fetcher = BilingualCachedLanguagesFetcher()
        var applied: Set<String>?
        fetcher.fetch(bookFingerprintKey: "fp1", store: store) { applied = $0 }
        try await Task.sleep(for: .milliseconds(300))
        #expect(applied == ["Chinese", "French"])
    }

    @Test func invalidateDropsTheInFlightCompletion() async throws {
        let store = try makeStore(languages: ["Chinese"], book: "fp1")
        let fetcher = BilingualCachedLanguagesFetcher()
        var applied = 0
        fetcher.fetch(bookFingerprintKey: "fp1", store: store) { _ in applied += 1 }
        fetcher.invalidate()   // sheet dismissed before the fetch landed
        try await Task.sleep(for: .milliseconds(300))
        #expect(applied == 0)
    }

    @Test func aNewerFetchSupersedesTheOlderOne() async throws {
        let store = try makeStore(languages: ["Chinese"], book: "fp1")
        try await Task.sleep(for: .milliseconds(150))
        let fetcher = BilingualCachedLanguagesFetcher()
        var applied: [String] = []
        fetcher.fetch(bookFingerprintKey: "fp1", store: store) { _ in applied.append("first") }
        fetcher.fetch(bookFingerprintKey: "fp1", store: store) { _ in applied.append("second") }
        try await Task.sleep(for: .milliseconds(400))
        #expect(applied == ["second"])
    }
}
