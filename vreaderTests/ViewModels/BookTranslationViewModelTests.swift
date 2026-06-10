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

    // MARK: - Row-tap routing (Bug #328)

    /// Bug #328: tapping "Translate entire book…" while a job is ALREADY
    /// running must open the in-progress status sheet (progress + cancel),
    /// NOT re-open the estimate→confirm alert (which can't reach progress and
    /// risks a duplicate start). The user has dismissed the status sheet but
    /// the job keeps running — the row tap must bring it back.
    @Test func handleTranslateRowTap_whileRunning_opensStatusSheet_notConfirm() async throws {
        let units = (1...4).map { Self.unit("ch\($0)") }
        var texts: [TranslationUnitID: String] = [:]
        for u in units { texts[u] = "p" }
        let provider = MockChapterTextProvider(units: units, texts: texts)
        let sender = SlowTranslationSender(
            responses: units.map { _ in "[\"x\"]" }, perRequestNanos: 200_000_000)
        let store = try Self.makeStore()
        let coordinator = Self.makeCoordinator(store: store, sender: sender)
        let viewModel = BookTranslationViewModel(
            bookFingerprintKey: Self.bookKey, coordinator: coordinator)

        // Start a job, then simulate the user dismissing the status sheet
        // while the job keeps running.
        await viewModel.presentConfirm(textProvider: provider, targetLanguage: "Chinese")
        await viewModel.confirmTranslate(
            textProvider: provider, targetLanguage: "Chinese",
            providerProfileID: Self.providerID, config: Self.makeConfig(), style: .natural)
        try await Task.sleep(nanoseconds: 120_000_000) // let the job claim a unit → .running
        viewModel.closeStatusSheet()
        #expect(await coordinator.currentProgress(forBookWithKey: Self.bookKey).phase == .running,
                "precondition: the job is running")

        // Tap the row again.
        await viewModel.handleTranslateRowTap(textProvider: provider, targetLanguage: "Chinese")

        #expect(viewModel.isShowingStatusSheet == true,
                "Bug #328: a running job's row tap must re-open the status sheet")
        #expect(viewModel.isShowingConfirmAlert == false,
                "Bug #328: it must NOT re-open the setup/confirm alert while running")

        // Clean up the slow job.
        viewModel.requestCancel()
        await viewModel.confirmCancel()
        try? await coordinator.awaitJobForTesting(bookFingerprintKey: Self.bookKey)
    }

    /// Bug #328 (Codex race-hardening): `presentConfirm` itself re-checks the
    /// live job state after resolving the estimate. If a job is running (e.g.
    /// started on another surface during the estimate await), it routes to the
    /// status sheet instead of the confirm alert — so the race can't surface a
    /// confirm alert for a now-running job. Covers all `presentConfirm` callers,
    /// not just the Book Details row tap.
    @Test func presentConfirm_whileRunning_routesToStatusSheet_notConfirm() async throws {
        let units = (1...4).map { Self.unit("ch\($0)") }
        var texts: [TranslationUnitID: String] = [:]
        for u in units { texts[u] = "p" }
        let provider = MockChapterTextProvider(units: units, texts: texts)
        let sender = SlowTranslationSender(
            responses: units.map { _ in "[\"x\"]" }, perRequestNanos: 200_000_000)
        let store = try Self.makeStore()
        let coordinator = Self.makeCoordinator(store: store, sender: sender)
        let viewModel = BookTranslationViewModel(
            bookFingerprintKey: Self.bookKey, coordinator: coordinator)

        await viewModel.presentConfirm(textProvider: provider, targetLanguage: "Chinese")
        await viewModel.confirmTranslate(
            textProvider: provider, targetLanguage: "Chinese",
            providerProfileID: Self.providerID, config: Self.makeConfig(), style: .natural)
        try await Task.sleep(nanoseconds: 120_000_000) // job is now running
        viewModel.closeStatusSheet()
        viewModel.dismissConfirm()

        // A second surface reaches presentConfirm while the job runs.
        await viewModel.presentConfirm(textProvider: provider, targetLanguage: "Chinese")
        #expect(viewModel.isShowingStatusSheet == true,
                "Bug #328: presentConfirm must route a running job to the status sheet")
        #expect(viewModel.isShowingConfirmAlert == false,
                "Bug #328: no confirm alert may surface for a running job")

        viewModel.requestCancel()
        await viewModel.confirmCancel()
        try? await coordinator.awaitJobForTesting(bookFingerprintKey: Self.bookKey)
    }

    /// The other branch: when no job is running (idle), the row tap runs the
    /// normal estimate→confirm flow.
    @Test func handleTranslateRowTap_whenIdle_runsConfirmFlow() async throws {
        let units = [Self.unit("ch1"), Self.unit("ch2")]
        let provider = MockChapterTextProvider(units: units, texts: [units[0]: "p", units[1]: "p"])
        let store = try Self.makeStore()
        let coordinator = Self.makeCoordinator(store: store)
        let viewModel = BookTranslationViewModel(
            bookFingerprintKey: Self.bookKey, coordinator: coordinator)

        await viewModel.handleTranslateRowTap(textProvider: provider, targetLanguage: "Chinese")

        #expect(viewModel.isShowingConfirmAlert == true,
                "idle book: row tap runs the estimate→confirm flow")
        #expect(viewModel.isShowingStatusSheet == false)
        #expect(viewModel.estimate?.unitCount == 2)
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

    // MARK: - Feature #98 WI-2: restartObserving

    /// The coordinator's progress stream is ONE-SHOT — it finishes on any
    /// terminal phase. `restartObserving()` is the explicit re-subscribe so
    /// an auto-RESUMED job's snapshots reach a VM whose previous stream
    /// already finished (Gate-2 round-1 High 1).
    @Test func restartObserving_deliversAResumedJobsSnapshots_afterTerminalStream() async throws {
        let units = [Self.unit("ch1"), Self.unit("ch2")]
        let store = try Self.makeStore()
        let sender = MockTranslationSender(responses: ["[\"a\"]", "[\"b\"]"])
        let coordinator = Self.makeCoordinator(store: store, sender: sender)
        let viewModel = BookTranslationViewModel(
            bookFingerprintKey: Self.bookKey, coordinator: coordinator)
        await viewModel.startObserving()

        // Job 1 (one unit) runs to .completed — the observed stream FINISHES.
        let provider1 = MockChapterTextProvider(units: [units[0]], texts: [units[0]: "p1."])
        await coordinator.start(
            bookFingerprintKey: Self.bookKey, textProvider: provider1,
            targetLanguage: "Chinese", providerProfileID: Self.providerID,
            config: Self.makeConfig(), style: .natural)
        try await coordinator.awaitJobForTesting(bookFingerprintKey: Self.bookKey)
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(viewModel.progress.phase == .completed)
        #expect(viewModel.progress.total == 1)

        // Re-subscribe, then job 2 (two units — ch1 cached, ch2 fresh).
        await viewModel.restartObserving()
        let provider2 = MockChapterTextProvider(units: units, texts: [
            units[0]: "p1.", units[1]: "p2."
        ])
        await coordinator.start(
            bookFingerprintKey: Self.bookKey, textProvider: provider2,
            targetLanguage: "Chinese", providerProfileID: Self.providerID,
            config: Self.makeConfig(), style: .natural)
        try await coordinator.awaitJobForTesting(bookFingerprintKey: Self.bookKey)
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(viewModel.progress.total == 2,
                "the fresh stream must deliver the resumed job's snapshots — the finished one never would")
        #expect(viewModel.progress.phase == .completed)
    }
}
