// Purpose: Tests for ChapterReTranslateViewModel — the @MainActor UI-facing
// state for the per-chapter re-translation flow (feature #56 WI-15).
//
// Covers acceptance criteria (e) "per-chapter re-translate clears old cache
// and fetches fresh" and (f) "provider override for re-translate does not
// change the global active provider".
//
// @coordinates-with: ChapterReTranslateViewModel.swift,
//   ChapterTranslationStore.swift, ChapterTranslationService.swift,
//   AIService.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-15)

import Testing
import Foundation
import SwiftData
@testable import vreader

@MainActor
@Suite("ChapterReTranslateViewModel")
struct ChapterReTranslateViewModelTests {

    private static let bookKey = "epub:fp-rt-tests"
    private static let promptVersion = "v1"
    private static let initialProfileID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    private static let overrideProfileID = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!

    private static func unit(_ value: String = "ch6") -> TranslationUnitID {
        TranslationUnitID(kind: .epubHref, value: value)
    }

    private static func makeStore() throws -> ChapterTranslationStore {
        let schema = Schema(SchemaV7.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ChapterTranslationStore(modelContainer: container)
    }

    private static func makeConfig(model: String = "gpt-test") -> ResolvedAIProviderConfig {
        ResolvedAIProviderConfig(
            kind: .openAICompatible,
            baseURL: URL(string: "https://api.test.example.com")!,
            apiKey: "sk-test", model: model, maxTokens: 4096)
    }

    private static func seedCache(
        _ store: ChapterTranslationStore,
        bookKey: String = bookKey,
        unit: TranslationUnitID,
        profileID: UUID,
        segments: [String]
    ) async throws {
        try await store.upsert(ChapterTranslationRecord(
            bookFingerprintKey: bookKey,
            unitStorageKey: unit.storageKey,
            targetLanguage: "Chinese",
            providerProfileID: profileID,
            promptVersion: promptVersion,
            translatedSegments: segments,
            sourceParagraphCount: segments.count))
    }

    /// Records the calls a VM makes through the AIService seam — captures the
    /// (profileID, modelOverride) the picker resolved, and returns a canned
    /// config so the VM never reaches the network.
    actor MockProviderResolver: RetranslateProviderResolving {
        private(set) var calls: [(profileID: UUID, modelOverride: String?)] = []
        private let result: Result<ResolvedAIProviderConfig, Error>

        init(result: Result<ResolvedAIProviderConfig, Error>) { self.result = result }

        func resolveProviderConfig(
            profileID: UUID, modelOverride: String?
        ) async throws -> ResolvedAIProviderConfig {
            calls.append((profileID, modelOverride))
            return try result.get()
        }
    }

    /// Records the calls the VM makes into the translation service — captures
    /// the style + config so a test can prove the picker's selection actually
    /// flows down to translation.
    actor MockTranslationRunner: ChapterReTranslating {
        private(set) var calls: [(unit: TranslationUnitID, style: TranslationStyle, providerProfileID: UUID, model: String)] = []
        private let result: Result<ChapterTranslationResult, Error>
        /// Bug #311: when > 0, fire `onChunkProgress(i, n)` for i in 1...n to
        /// simulate the real per-chunk ticks the service emits.
        private let simulateChunks: Int
        /// Bug #311: records whether the VM passed a non-nil progress callback.
        private(set) var receivedProgressCallback = false
        /// Bug #311 (Codex Gate-4 Low): when true, stash the callback instead of
        /// firing it, so a test can fire a STALE tick after cancel()/dismiss()/a
        /// second submit() and assert the run-generation guard ignores it.
        private let captureCallback: Bool
        private var capturedCallback: (@Sendable (Int, Int) -> Void)?

        init(
            result: Result<ChapterTranslationResult, Error>,
            simulateChunks: Int = 0,
            captureProgressCallback: Bool = false
        ) {
            self.result = result
            self.simulateChunks = simulateChunks
            self.captureCallback = captureProgressCallback
        }

        func translateForRetranslate(
            bookFingerprintKey: String,
            unit: TranslationUnitID,
            sourceText: String,
            targetLanguage: String,
            providerProfileID: UUID,
            config: ResolvedAIProviderConfig,
            style: TranslationStyle,
            granularity: TranslationGranularity,
            onChunkProgress: (@Sendable (Int, Int) -> Void)?
        ) async throws -> ChapterTranslationResult {
            calls.append((unit, style, providerProfileID, config.model))
            receivedProgressCallback = (onChunkProgress != nil)
            if captureCallback { capturedCallback = onChunkProgress }
            if simulateChunks > 0, let cb = onChunkProgress {
                for i in 1...simulateChunks { cb(i, simulateChunks) }
            }
            return try result.get()
        }

        /// Fires the callback captured during the most recent translate, as if a
        /// late chunk from that (now-finished/superseded) run just landed.
        func fireCapturedProgress(_ done: Int, _ total: Int) {
            capturedCallback?(done, total)
        }
    }

    private static func makeVM(
        bookKey: String = bookKey,
        store: ChapterTranslationStore,
        resolver: MockProviderResolver,
        runner: MockTranslationRunner,
        sourceText: String = "Source paragraph one.\n\nSource paragraph two."
    ) -> ChapterReTranslateViewModel {
        ChapterReTranslateViewModel(
            bookFingerprintKey: bookKey,
            promptVersion: promptVersion,
            initialProviderProfileID: initialProfileID,
            initialModel: "initial-model",
            resolver: resolver,
            runner: runner,
            store: store,
            sourceTextProvider: { _ in sourceText })  // implicit async throws, returns immediately
    }

    // MARK: - Initial state

    @Test func initialState_isDismissed_andHasInitialSelection() async throws {
        let store = try Self.makeStore()
        let resolver = MockProviderResolver(result: .success(Self.makeConfig()))
        let runner = MockTranslationRunner(result: .success(
            ChapterTranslationResult(segments: ["新译文"], fromCache: false)))
        let vm = Self.makeVM(store: store, resolver: resolver, runner: runner)
        #expect(vm.sheetState == .dismissed)
        #expect(vm.selection.providerProfileID == Self.initialProfileID)
        #expect(vm.selection.style == .natural)
    }

    // MARK: - Picker presentation

    @Test func presentPicker_movesToPickerState_andCarriesUnitContext() async throws {
        let store = try Self.makeStore()
        let resolver = MockProviderResolver(result: .success(Self.makeConfig()))
        let runner = MockTranslationRunner(result: .success(
            ChapterTranslationResult(segments: ["新译文"], fromCache: false)))
        let vm = Self.makeVM(store: store, resolver: resolver, runner: runner)

        vm.presentPicker(unit: Self.unit("ch6"), unitTitle: "Chapter 6", targetLanguage: "Chinese")

        #expect(vm.sheetState == .picker)
        #expect(vm.unit == Self.unit("ch6"))
        #expect(vm.unitTitle == "Chapter 6")
        #expect(vm.targetLanguage == "Chinese")
    }

    @Test func dismiss_clearsSheetState() async throws {
        let store = try Self.makeStore()
        let resolver = MockProviderResolver(result: .success(Self.makeConfig()))
        let runner = MockTranslationRunner(result: .success(
            ChapterTranslationResult(segments: ["新译文"], fromCache: false)))
        let vm = Self.makeVM(store: store, resolver: resolver, runner: runner)

        vm.presentPicker(unit: Self.unit(), unitTitle: "ch", targetLanguage: "Chinese")
        vm.dismiss()
        #expect(vm.sheetState == .dismissed)
    }

    // MARK: - Bug #311: real per-chunk progress (not pinned at 0.5)

    /// The translate-phase mapping starts at the 0.5 post-resolve baseline, is
    /// strictly monotonic in completed chunks, and stays below 1.0 even at full
    /// completion (the terminal 1.0 is reserved for the whole flow finishing) —
    /// so the bar advances honestly during a slow chapter instead of pinning.
    @Test func translateProgressMapping_isMonotonic_andBoundedBelowComplete() {
        let total = 4
        let p0 = ChapterReTranslateViewModel.translateProgress(chunksDone: 0, totalChunks: total)
        let p1 = ChapterReTranslateViewModel.translateProgress(chunksDone: 1, totalChunks: total)
        let p2 = ChapterReTranslateViewModel.translateProgress(chunksDone: 2, totalChunks: total)
        let p4 = ChapterReTranslateViewModel.translateProgress(chunksDone: 4, totalChunks: total)
        #expect(p0 == 0.5)                        // baseline == post-resolve
        #expect(p1 > p0 && p2 > p1 && p4 > p2)    // strictly monotonic
        #expect(p4 < 1.0 && p4 <= 0.95)           // full chunks < 100% (flow not done)
        // defensive: empty chunking returns the baseline, never NaN/∞
        #expect(ChapterReTranslateViewModel.translateProgress(chunksDone: 0, totalChunks: 0) == 0.5)
        // clamps an over-count rather than exceeding the band
        #expect(ChapterReTranslateViewModel.translateProgress(chunksDone: 9, totalChunks: total) <= 0.95)
    }

    /// Bug #311: the VM must pass a real per-chunk progress callback into the
    /// runner (pre-fix it passed none, so the bar pinned at 0.5 for the entire
    /// opaque translate and read as "stuck"). The mock fires 3 chunk ticks; we
    /// assert the runner RECEIVED a non-nil callback and the flow still
    /// completes at 1.0.
    @Test func submit_passesPerChunkProgressCallback_toRunner() async throws {
        let store = try Self.makeStore()
        let unit = Self.unit("ch6")
        let resolver = MockProviderResolver(result: .success(Self.makeConfig()))
        let runner = MockTranslationRunner(
            result: .success(ChapterTranslationResult(segments: ["新一", "新二"], fromCache: false)),
            simulateChunks: 3)
        let vm = Self.makeVM(store: store, resolver: resolver, runner: runner)
        vm.presentPicker(unit: unit, unitTitle: "ch6", targetLanguage: "Chinese")

        await vm.submit()

        #expect(await runner.receivedProgressCallback,
                "VM must pass a per-chunk progress callback so the bar isn't pinned at 0.5")
        #expect(vm.sheetState == .complete)
        #expect(vm.progress == 1.0)
    }

    /// Bug #311 (Codex Gate-4 Medium): a per-chunk tick that is delivered (via
    /// the actor→main hop) AFTER the run finished and the sheet was dismissed
    /// must NOT push the now-idle bar back into the 0.5–0.95 translate band. The
    /// run-generation + `.running` guard drops it. (The `max()` guard alone
    /// would not — it only protects the terminal 1.0, not the reset-to-0.0.)
    @Test func staleChunkTick_afterDismiss_doesNotMoveIdleBar() async throws {
        let store = try Self.makeStore()
        let resolver = MockProviderResolver(result: .success(Self.makeConfig()))
        let runner = MockTranslationRunner(
            result: .success(ChapterTranslationResult(segments: ["新一"], fromCache: false)),
            captureProgressCallback: true)
        let vm = Self.makeVM(store: store, resolver: resolver, runner: runner)
        vm.presentPicker(unit: Self.unit("ch6"), unitTitle: "ch6", targetLanguage: "Chinese")
        await vm.submit()                 // run completes; runner captured the callback
        vm.dismiss()                      // idle: progress 0.0, generation invalidated
        #expect(vm.progress == 0.0)

        // A late chunk tick from the finished + dismissed run arrives:
        await runner.fireCapturedProgress(2, 4)
        // Drain the @MainActor hop the VM's callback enqueues.
        await Task.yield(); await Task.yield(); await Task.yield()

        #expect(vm.progress == 0.0,
                "a stale per-chunk tick after dismiss must not push the idle bar into the translate band")
        #expect(vm.sheetState == .dismissed)
    }

    // MARK: - Submit — happy path

    @Test func submit_clearsCacheForThatUnit_andCallsTranslate() async throws {
        let store = try Self.makeStore()
        let unit = Self.unit("ch6")
        // Seed the cache for this exact (book, unit, target, profile,
        // promptVersion). The VM must DELETE this row before triggering the
        // re-translate.
        try await Self.seedCache(
            store, unit: unit, profileID: Self.initialProfileID,
            segments: ["旧译文"])

        let resolver = MockProviderResolver(result: .success(Self.makeConfig(model: "override-model")))
        let runner = MockTranslationRunner(result: .success(
            ChapterTranslationResult(segments: ["新译文一", "新译文二"], fromCache: false)))

        var translationsApplied: [TranslationUnitID: [String]] = [:]
        let vm = Self.makeVM(store: store, resolver: resolver, runner: runner)
        vm.onTranslationApplied = { unit, segments in
            translationsApplied[unit] = segments
        }

        vm.presentPicker(unit: unit, unitTitle: "Chapter 6", targetLanguage: "Chinese")
        vm.updateSelection { selection in
            selection.providerProfileID = Self.overrideProfileID
            selection.model = "override-model"
            selection.style = .literary
        }
        await vm.submit()

        // Cache row deleted for the ORIGINAL profile/key (initialProfileID).
        let cachedKey = ChapterTranslationRecord.lookupKey(
            bookFingerprintKey: Self.bookKey,
            unitStorageKey: unit.storageKey,
            targetLanguage: "Chinese",
            providerProfileID: Self.initialProfileID,
            promptVersion: Self.promptVersion)
        let cached = await store.translation(forKey: cachedKey)
        #expect(cached == nil)

        // Resolver was called with the OVERRIDE profile + model — picker
        // selection actually flows through.
        let resolverCalls = await resolver.calls
        #expect(resolverCalls.count == 1)
        #expect(resolverCalls.first?.profileID == Self.overrideProfileID)
        #expect(resolverCalls.first?.modelOverride == "override-model")

        // Runner was called with the picker's style.
        let runnerCalls = await runner.calls
        #expect(runnerCalls.count == 1)
        #expect(runnerCalls.first?.style == .literary)
        #expect(runnerCalls.first?.providerProfileID == Self.overrideProfileID)
        #expect(runnerCalls.first?.model == "override-model")

        // Result flowed back through the host callback.
        #expect(translationsApplied[unit] == ["新译文一", "新译文二"])
        // Sheet ended at .complete after success.
        #expect(vm.sheetState == .complete)
        #expect(vm.lastError == nil)
    }

    // MARK: - Default selection — no override

    @Test func submit_withInitialSelection_usesInitialProfileAndModel() async throws {
        let store = try Self.makeStore()
        let resolver = MockProviderResolver(result: .success(Self.makeConfig(model: "initial-model")))
        let runner = MockTranslationRunner(result: .success(
            ChapterTranslationResult(segments: ["新译文"], fromCache: false)))
        let vm = Self.makeVM(store: store, resolver: resolver, runner: runner)

        vm.presentPicker(unit: Self.unit(), unitTitle: "ch", targetLanguage: "Chinese")
        await vm.submit()

        let resolverCalls = await resolver.calls
        #expect(resolverCalls.first?.profileID == Self.initialProfileID)
        // initialModel was set; modelOverride was sent through.
        #expect(resolverCalls.first?.modelOverride == "initial-model")
    }

    // MARK: - Error path

    @Test func submit_runnerFails_setsErrorState() async throws {
        let store = try Self.makeStore()
        let resolver = MockProviderResolver(result: .success(Self.makeConfig()))
        let runner = MockTranslationRunner(result: .failure(
            ChapterTranslationError.providerFailed("upstream offline")))
        let vm = Self.makeVM(store: store, resolver: resolver, runner: runner)

        vm.presentPicker(unit: Self.unit(), unitTitle: "ch", targetLanguage: "Chinese")
        await vm.submit()

        #expect(vm.sheetState == .picker)
        #expect(vm.lastError?.contains("upstream offline") == true)
    }

    // Bug #333: a timeout renders a distinct "timed out" message, NOT the
    // misleading "You appear to be offline" copy.
    @Test func submit_timeout_showsTimedOutNotOffline() async throws {
        let store = try Self.makeStore()
        let resolver = MockProviderResolver(result: .success(Self.makeConfig()))
        let runner = MockTranslationRunner(result: .failure(ChapterTranslationError.timedOut))
        let vm = Self.makeVM(store: store, resolver: resolver, runner: runner)

        vm.presentPicker(unit: Self.unit(), unitTitle: "ch", targetLanguage: "Chinese")
        await vm.submit()

        #expect(vm.lastError?.lowercased().contains("timed out") == true)
        #expect(vm.lastError?.lowercased().contains("offline") == false)
    }

    @Test func submit_resolverFails_setsErrorState() async throws {
        struct StubError: Error { let message: String }
        let store = try Self.makeStore()
        let resolver = MockProviderResolver(result: .failure(StubError(message: "no-keychain")))
        let runner = MockTranslationRunner(result: .success(
            ChapterTranslationResult(segments: [], fromCache: false)))
        let vm = Self.makeVM(store: store, resolver: resolver, runner: runner)

        vm.presentPicker(unit: Self.unit(), unitTitle: "ch", targetLanguage: "Chinese")
        await vm.submit()

        #expect(vm.sheetState == .picker)
        // Runner was NOT called when resolver failed.
        let runnerCalls = await runner.calls
        #expect(runnerCalls.isEmpty)
        #expect(vm.lastError != nil)
    }

    // MARK: - Empty source text

    @Test func submit_emptySource_doesNotCallTranslate_andDismisses() async throws {
        let store = try Self.makeStore()
        let resolver = MockProviderResolver(result: .success(Self.makeConfig()))
        let runner = MockTranslationRunner(result: .success(
            ChapterTranslationResult(segments: [], fromCache: false)))
        let vm = Self.makeVM(
            store: store, resolver: resolver, runner: runner, sourceText: "")

        vm.presentPicker(unit: Self.unit(), unitTitle: "ch", targetLanguage: "Chinese")
        await vm.submit()

        // No translation work for an empty unit — sheet completes without
        // sending a request.
        let runnerCalls = await runner.calls
        #expect(runnerCalls.isEmpty)
        // The host gets a no-op callback (no translations to apply).
        #expect(vm.sheetState == .complete)
    }

    // MARK: - Source-text extraction failure

    @Test func submit_sourceTextProviderThrows_surfacesErrorAndDoesNotApply() async throws {
        // Codex Gate-4 round-1 Critical (thread `019e4399-b8cd`): a thrown
        // sourceText error must roll back to .picker with an error message
        // — it must NOT post the empty-source success state, which would
        // leave the original cache row deleted and the user believing the
        // re-translate succeeded.
        struct ExtractionFailed: Error {}
        let store = try Self.makeStore()
        let resolver = MockProviderResolver(result: .success(Self.makeConfig()))
        let runner = MockTranslationRunner(result: .success(
            ChapterTranslationResult(segments: [], fromCache: false)))
        let vm = ChapterReTranslateViewModel(
            bookFingerprintKey: Self.bookKey,
            promptVersion: Self.promptVersion,
            initialProviderProfileID: Self.initialProfileID,
            initialModel: "initial-model",
            resolver: resolver,
            runner: runner,
            store: store,
            sourceTextProvider: { _ in throw ExtractionFailed() })

        var translationsApplied: [TranslationUnitID: [String]] = [:]
        vm.onTranslationApplied = { unit, segments in
            translationsApplied[unit] = segments
        }

        vm.presentPicker(unit: Self.unit(), unitTitle: "ch", targetLanguage: "Chinese")
        await vm.submit()

        // No translation applied (no spurious empty [] flowed back).
        #expect(translationsApplied.isEmpty)
        // Runner was not called.
        let runnerCalls = await runner.calls
        #expect(runnerCalls.isEmpty)
        // Sheet rolled back to picker with an error visible.
        #expect(vm.sheetState == .picker)
        #expect(vm.lastError != nil)
    }

    @Test func submit_sourceTextProviderCancels_returnsWithoutApplyOrError() async throws {
        // CancellationError thrown by the source-text provider should
        // restore state via the cancel() path — no error banner, no apply.
        let store = try Self.makeStore()
        let resolver = MockProviderResolver(result: .success(Self.makeConfig()))
        let runner = MockTranslationRunner(result: .success(
            ChapterTranslationResult(segments: [], fromCache: false)))
        let vm = ChapterReTranslateViewModel(
            bookFingerprintKey: Self.bookKey,
            promptVersion: Self.promptVersion,
            initialProviderProfileID: Self.initialProfileID,
            initialModel: "initial-model",
            resolver: resolver,
            runner: runner,
            store: store,
            sourceTextProvider: { _ in throw CancellationError() })

        vm.presentPicker(unit: Self.unit(), unitTitle: "ch", targetLanguage: "Chinese")
        await vm.submit()

        // No translation applied, no error surfaced — clean cancellation.
        let runnerCalls = await runner.calls
        #expect(runnerCalls.isEmpty)
        #expect(vm.lastError == nil)
    }

    // MARK: - Provider override does not mutate ProviderProfileStore

    @Test func submit_overrideProvider_doesNotMutateProfileStoreActiveID() async throws {
        // The picker selection is local to the VM — the resolver call carries
        // the chosen profile, but the VM never touches `ProviderProfileStore`'s
        // active id setter. Test by spying on the resolver's call shape (only
        // the override-resolver path is exercised — `setActiveProfileID` is
        // never invoked since we don't even hand the store in).
        let store = try Self.makeStore()
        let resolver = MockProviderResolver(result: .success(Self.makeConfig()))
        let runner = MockTranslationRunner(result: .success(
            ChapterTranslationResult(segments: ["新"], fromCache: false)))
        let vm = Self.makeVM(store: store, resolver: resolver, runner: runner)

        vm.presentPicker(unit: Self.unit(), unitTitle: "ch", targetLanguage: "Chinese")
        vm.updateSelection { $0.providerProfileID = Self.overrideProfileID }
        await vm.submit()

        // The VM has no hook into ProviderProfileStore — confirm only by
        // asserting the override flowed through the resolver shape (the only
        // seam touching profiles), which the prior test already covered.
        let calls = await resolver.calls
        #expect(calls.first?.profileID == Self.overrideProfileID)
    }
}
