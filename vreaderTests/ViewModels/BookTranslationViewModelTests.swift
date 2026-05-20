// Purpose: Tests for BookTranslationViewModel — the @MainActor UI-facing
// state for the global "translate entire book" flow (feature #56 WI-14).
//
// @coordinates-with: BookTranslationViewModel.swift,
//   BookTranslationCoordinator.swift, BookTranslationProgress.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-14)

import Testing
import Foundation
import SwiftData
@testable import vreader

@MainActor
@Suite("BookTranslationViewModel")
struct BookTranslationViewModelTests {

    private static let bookKey = "epub:fp-vm-tests"
    private static let providerID = UUID(uuidString: "EEEEEEEE-0000-0000-0000-000000000001")!

    private static func makeConfig() -> ResolvedAIProviderConfig {
        ResolvedAIProviderConfig(
            kind: .openAICompatible,
            baseURL: URL(string: "https://api.test.example.com")!,
            apiKey: "sk-test", model: "test-model", maxTokens: 4096)
    }

    private static func makeStore() throws -> ChapterTranslationStore {
        let schema = Schema(SchemaV7.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ChapterTranslationStore(modelContainer: container)
    }

    private static func unit(_ value: String) -> TranslationUnitID {
        TranslationUnitID(kind: .epubHref, value: value)
    }

    private static func makeCoordinator(
        store: ChapterTranslationStore, sender: any TranslationRequestSending = MockTranslationSender(responses: [])
    ) -> BookTranslationCoordinator {
        let service = ChapterTranslationService(
            sender: sender, store: store, promptVersion: "v1")
        return BookTranslationCoordinator(
            service: service, store: store, promptVersion: "v1")
    }

    // MARK: - Initial state

    @Test func initialState_isIdle_andNoSheetShown() async throws {
        let store = try Self.makeStore()
        let coordinator = Self.makeCoordinator(store: store)
        let viewModel = BookTranslationViewModel(
            bookFingerprintKey: Self.bookKey, coordinator: coordinator)
        #expect(viewModel.progress.phase == .idle)
        #expect(viewModel.isShowingConfirmAlert == false)
        #expect(viewModel.isShowingStatusSheet == false)
        #expect(viewModel.isShowingCancelAlert == false)
    }

    // MARK: - Estimate + confirm

    @Test func presentConfirm_loadsEstimate_andShowsAlert() async throws {
        let units = [Self.unit("ch1"), Self.unit("ch2"), Self.unit("ch3")]
        let provider = MockChapterTextProvider(units: units, texts: [
            units[0]: "p", units[1]: "p", units[2]: "p"
        ])
        let store = try Self.makeStore()
        let coordinator = Self.makeCoordinator(store: store)
        let viewModel = BookTranslationViewModel(
            bookFingerprintKey: Self.bookKey, coordinator: coordinator)

        await viewModel.presentConfirm(
            textProvider: provider, targetLanguage: "Chinese")

        #expect(viewModel.isShowingConfirmAlert == true)
        #expect(viewModel.estimate?.unitCount == 3)
    }

    @Test func dismissConfirm_hidesAlert() async throws {
        let provider = MockChapterTextProvider(units: [Self.unit("ch1")], texts: [Self.unit("ch1"): "p"])
        let store = try Self.makeStore()
        let coordinator = Self.makeCoordinator(store: store)
        let viewModel = BookTranslationViewModel(
            bookFingerprintKey: Self.bookKey, coordinator: coordinator)
        await viewModel.presentConfirm(
            textProvider: provider, targetLanguage: "Chinese")
        viewModel.dismissConfirm()
        #expect(viewModel.isShowingConfirmAlert == false)
    }

    // MARK: - Confirm → start

    @Test func confirmTranslate_startsCoordinatorJob_andOpensStatusSheet() async throws {
        let units = [Self.unit("ch1")]
        let provider = MockChapterTextProvider(units: units, texts: [units[0]: "p"])
        let store = try Self.makeStore()
        let sender = MockTranslationSender(responses: ["[\"译\"]"])
        let coordinator = Self.makeCoordinator(store: store, sender: sender)
        let viewModel = BookTranslationViewModel(
            bookFingerprintKey: Self.bookKey, coordinator: coordinator)

        await viewModel.presentConfirm(
            textProvider: provider, targetLanguage: "Chinese")
        await viewModel.confirmTranslate(
            textProvider: provider, targetLanguage: "Chinese",
            providerProfileID: Self.providerID,
            config: Self.makeConfig(),
            style: .natural)

        #expect(viewModel.isShowingConfirmAlert == false)
        // The coordinator received the start request.
        try await coordinator.awaitJobForTesting(bookFingerprintKey: Self.bookKey)
        let progress = await coordinator.currentProgress(forBookWithKey: Self.bookKey)
        #expect(progress.phase == .completed)
    }

    // MARK: - Status sheet

    @Test func openStatusSheet_setsFlag_andCloseClearsIt() async throws {
        let store = try Self.makeStore()
        let coordinator = Self.makeCoordinator(store: store)
        let viewModel = BookTranslationViewModel(
            bookFingerprintKey: Self.bookKey, coordinator: coordinator)
        viewModel.openStatusSheet()
        #expect(viewModel.isShowingStatusSheet == true)
        viewModel.closeStatusSheet()
        #expect(viewModel.isShowingStatusSheet == false)
    }

    // MARK: - Cancel flow

    @Test func requestCancel_showsCancelAlert_butKeepsJobRunning() async throws {
        let store = try Self.makeStore()
        let coordinator = Self.makeCoordinator(store: store)
        let viewModel = BookTranslationViewModel(
            bookFingerprintKey: Self.bookKey, coordinator: coordinator)
        viewModel.requestCancel()
        #expect(viewModel.isShowingCancelAlert == true)
    }

    @Test func dismissCancel_keepsJobRunning() async throws {
        let store = try Self.makeStore()
        let coordinator = Self.makeCoordinator(store: store)
        let viewModel = BookTranslationViewModel(
            bookFingerprintKey: Self.bookKey, coordinator: coordinator)
        viewModel.requestCancel()
        viewModel.dismissCancelAlert()
        #expect(viewModel.isShowingCancelAlert == false)
    }

    @Test func confirmCancel_cancelsAtCoordinator_andHidesAlerts() async throws {
        let units = (1...4).map { Self.unit("ch\($0)") }
        var texts: [TranslationUnitID: String] = [:]
        for u in units { texts[u] = "p" }
        let provider = MockChapterTextProvider(units: units, texts: texts)
        let sender = SlowTranslationSender(
            responses: units.map { _ in "[\"x\"]" }, perRequestNanos: 150_000_000)
        let store = try Self.makeStore()
        let coordinator = Self.makeCoordinator(store: store, sender: sender)
        let viewModel = BookTranslationViewModel(
            bookFingerprintKey: Self.bookKey, coordinator: coordinator)

        await viewModel.presentConfirm(textProvider: provider, targetLanguage: "Chinese")
        await viewModel.confirmTranslate(
            textProvider: provider, targetLanguage: "Chinese",
            providerProfileID: Self.providerID,
            config: Self.makeConfig(),
            style: .natural)

        try await Task.sleep(nanoseconds: 200_000_000)
        viewModel.requestCancel()
        await viewModel.confirmCancel()
        try? await coordinator.awaitJobForTesting(bookFingerprintKey: Self.bookKey)

        #expect(viewModel.isShowingCancelAlert == false)
        let progress = await coordinator.currentProgress(forBookWithKey: Self.bookKey)
        #expect(progress.phase == .cancelled)
    }
}
