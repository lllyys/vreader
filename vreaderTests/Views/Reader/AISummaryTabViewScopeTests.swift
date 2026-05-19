// Purpose: Feature #69 WI-5 — tests for AISummaryTabView's scope chip
// strip + scoped runSummarize wiring.
//
// Covers: chip-strip selection mirrors viewModel.selectedScope; tapping
// a chip calls setScope (selection-only, no auto-fire); runSummarize
// passes selectedScope + fullTextContent + chapterBounds; the in-flight
// guard still holds with the scoped call.
//
// The actual chip-tap UI wiring is covered by the Gate-5 XCUITest /
// DebugBridge pass — these are the view-logic unit tests (the repo's
// unit-vs-UI split).
//
// @coordinates-with: AISummaryTabView.swift, AIAssistantViewModel.swift,
//   SummaryScope.swift, ChapterBounds.swift, WI11TestHelpers.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`

import Testing
import Foundation
@testable import vreader

@Suite("AISummaryTabView scope chip strip — feature #69 WI-5")
@MainActor
struct AISummaryTabViewScopeTests {

    // MARK: - Recording extractor (proves runSummarize forwards scope)

    /// Records what the view model forwards to the extractor when
    /// `runSummarize` runs.
    final class RecordingExtractor: AIContextExtracting, @unchecked Sendable {
        struct Call: Sendable {
            let fullText: String
            let scope: SummaryScope
            let chapterBounds: ChapterBounds?
        }
        private let lock = NSLock()
        private var _calls: [Call] = []
        var calls: [Call] {
            lock.lock(); defer { lock.unlock() }
            return _calls
        }
        var lastCall: Call? { calls.last }

        func extractContext(
            locator: Locator, fullText: String, format: BookFormat,
            scope: SummaryScope, chapterBounds: ChapterBounds?, maxUTF16: Int
        ) -> String {
            lock.lock()
            _calls.append(Call(
                fullText: fullText, scope: scope, chapterBounds: chapterBounds
            ))
            lock.unlock()
            return "EXTRACTED"
        }
    }

    // MARK: - Harness

    private static func makeViewModel(
        extractor: any AIContextExtracting,
        provider: any AIProvider
    ) -> AIAssistantViewModel {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)
        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            keychainService: WI11TestHelpers.makeKeychainService(),
            provider: provider
        )
        return AIAssistantViewModel(aiService: service, contextExtractor: extractor)
    }

    private static func okStub() -> StubAIProvider {
        let s = StubAIProvider()
        s.stubbedResponse = WI11TestHelpers.makeResponse(content: "summary")
        return s
    }

    private static func makeTabView(
        viewModel: AIAssistantViewModel,
        fullTextContent: String = "the full flattened book text",
        chapterBounds: ChapterBounds? = nil
    ) -> AISummaryTabView {
        AISummaryTabView(
            viewModel: viewModel,
            locator: WI11TestHelpers.makeLocator(),
            fullTextContent: fullTextContent,
            chapterBounds: chapterBounds,
            format: .txt,
            theme: .paper,
            onShare: { _ in }
        )
    }

    // MARK: - Chip-strip selection mirrors selectedScope

    @Test("The chip strip's selected chip mirrors viewModel.selectedScope")
    func chipStripMirrorsSelectedScope() {
        let vm = Self.makeViewModel(extractor: RecordingExtractor(), provider: Self.okStub())
        let view = Self.makeTabView(viewModel: vm)

        // The view exposes the active scope it would render selected.
        #expect(view.activeScope == .section)   // default

        vm.setScope(.chapter)
        #expect(view.activeScope == .chapter)

        vm.setScope(.bookSoFar)
        #expect(view.activeScope == .bookSoFar)
    }

    @Test("`isScopeActive` is true only for the selected scope")
    func isScopeActiveTracksSelection() {
        let vm = Self.makeViewModel(extractor: RecordingExtractor(), provider: Self.okStub())
        let view = Self.makeTabView(viewModel: vm)

        vm.setScope(.chapter)
        #expect(view.isScopeActive(.chapter))
        #expect(!view.isScopeActive(.section))
        #expect(!view.isScopeActive(.bookSoFar))
    }

    // MARK: - selectScope updates the view model (selection-only)

    @Test("`selectScope` forwards to viewModel.setScope without running a request")
    func selectScopeUpdatesViewModelOnly() async {
        let stub = Self.okStub()
        let vm = Self.makeViewModel(extractor: RecordingExtractor(), provider: stub)
        let view = Self.makeTabView(viewModel: vm)

        view.selectScope(.bookSoFar)
        #expect(vm.selectedScope == .bookSoFar)
        // Selection-only — no summarize fired.
        #expect(vm.state == .idle)
        #expect(stub.sendRequestCallCount == 0)
    }

    @Test("Selecting a chip does NOT transition to .loading (no auto-fire)")
    func selectScopeDoesNotAutoFire() async {
        let stub = Self.okStub()
        let vm = Self.makeViewModel(extractor: RecordingExtractor(), provider: stub)
        let view = Self.makeTabView(viewModel: vm)

        view.selectScope(.chapter)
        // Give any erroneously-spawned Task scheduler turns to run.
        for _ in 0..<10 { await Task.yield() }
        #expect(vm.state == .idle)
        #expect(stub.sendRequestCallCount == 0)
    }

    // MARK: - runSummarize forwards selectedScope + fullTextContent + bounds

    @Test("`runSummarize` passes the section scope + full text by default")
    func runSummarizePassesSectionByDefault() async {
        let extractor = RecordingExtractor()
        let vm = Self.makeViewModel(extractor: extractor, provider: Self.okStub())
        let view = Self.makeTabView(
            viewModel: vm, fullTextContent: "FULL-BOOK-TEXT"
        )

        view.runSummarize()
        for _ in 0..<20 { await Task.yield() }

        #expect(extractor.lastCall?.scope == .section)
        #expect(extractor.lastCall?.fullText == "FULL-BOOK-TEXT")
    }

    @Test("`runSummarize` forwards the selected Chapter scope + chapterBounds")
    func runSummarizeForwardsChapterScopeAndBounds() async {
        let extractor = RecordingExtractor()
        let bounds = ChapterBounds(startUTF16: 100, endUTF16: 3000)
        let vm = Self.makeViewModel(extractor: extractor, provider: Self.okStub())
        let view = Self.makeTabView(
            viewModel: vm, fullTextContent: "FULL-BOOK-TEXT", chapterBounds: bounds
        )

        vm.setScope(.chapter)
        view.runSummarize()
        for _ in 0..<20 { await Task.yield() }

        #expect(extractor.lastCall?.scope == .chapter)
        #expect(extractor.lastCall?.chapterBounds == bounds)
        #expect(extractor.lastCall?.fullText == "FULL-BOOK-TEXT")
    }

    @Test("`runSummarize` forwards the Book-so-far scope")
    func runSummarizeForwardsBookSoFarScope() async {
        let extractor = RecordingExtractor()
        let vm = Self.makeViewModel(extractor: extractor, provider: Self.okStub())
        let view = Self.makeTabView(viewModel: vm)

        vm.setScope(.bookSoFar)
        view.runSummarize()
        for _ in 0..<20 { await Task.yield() }

        #expect(extractor.lastCall?.scope == .bookSoFar)
    }

    // MARK: - In-flight guard still holds with the scoped call

    @Test("`runSummarize` is a no-op while a scoped request is in flight")
    func runSummarizeInFlightGuardHoldsForScopedCall() async {
        let extractor = RecordingExtractor()
        let gate = GatedAIProvider()
        gate.stubbedResponse = WI11TestHelpers.makeResponse(content: "summary")
        let vm = Self.makeViewModel(extractor: extractor, provider: gate)
        let view = Self.makeTabView(viewModel: vm)

        vm.setScope(.chapter)
        view.runSummarize()
        await gate.awaitEntered()
        #expect(vm.state == .loading)
        let countAfterFirst = await gate.sendRequestCallCount
        #expect(countAfterFirst == 1)

        // A second tap (e.g. Regenerate) while loading — must early-return.
        view.runSummarize()
        for _ in 0..<10 { await Task.yield() }
        let countAfterSecond = await gate.sendRequestCallCount
        #expect(countAfterSecond == 1)
        #expect(vm.state == .loading)

        await gate.release()
    }

    @Test("Changing scope mid-flight + re-tapping Regenerate is still a no-op")
    func scopeChangeDuringLoadingThenRegenerateIsNoOp() async {
        let extractor = RecordingExtractor()
        let gate = GatedAIProvider()
        gate.stubbedResponse = WI11TestHelpers.makeResponse(content: "summary")
        let vm = Self.makeViewModel(extractor: extractor, provider: gate)
        let view = Self.makeTabView(viewModel: vm)

        view.runSummarize()                // .section, in flight
        await gate.awaitEntered()
        #expect(vm.state == .loading)

        // Flip the scope chip mid-flight, then tap Regenerate.
        view.selectScope(.bookSoFar)
        view.runSummarize()
        for _ in 0..<10 { await Task.yield() }

        // The in-flight guard blocked the second request; the original
        // .section request is still the only one.
        let count = await gate.sendRequestCallCount
        #expect(count == 1)
        #expect(extractor.calls.count == 1)
        #expect(extractor.lastCall?.scope == .section)
        #expect(vm.selectedScope == .bookSoFar)

        await gate.release()
    }

    // MARK: - scopeChips contract

    @Test("All three SummaryScope chips are rendered in design order")
    func scopeChipsCoverAllCasesInOrder() {
        let vm = Self.makeViewModel(extractor: RecordingExtractor(), provider: Self.okStub())
        let view = Self.makeTabView(viewModel: vm)
        #expect(view.scopeChips == [.section, .chapter, .bookSoFar])
    }

    // MARK: - Accessibility identifier contract (XCUITest depends on these)

    @Test("Each scope chip exposes a stable, distinct accessibility identifier")
    func scopeChipIdentifiersAreStableAndDistinct() {
        // The Gate-5 XCUITest acceptance pass taps chips by these IDs —
        // a rename here would silently break the acceptance harness.
        #expect(AISummaryTabView.scopeChipIdentifier(.section) == "aiSummaryScopeChip.section")
        #expect(AISummaryTabView.scopeChipIdentifier(.chapter) == "aiSummaryScopeChip.chapter")
        #expect(AISummaryTabView.scopeChipIdentifier(.bookSoFar) == "aiSummaryScopeChip.bookSoFar")

        // All three identifiers are distinct.
        let ids = SummaryScope.allCases.map { AISummaryTabView.scopeChipIdentifier($0) }
        #expect(Set(ids).count == SummaryScope.allCases.count)
    }

    @Test("The chip-strip view re-exports the same identifier as the tab view")
    func chipStripIdentifierMatchesTabViewReExport() {
        // AISummaryTabView.scopeChipIdentifier re-exports
        // AISummaryScopeChipStrip.chipIdentifier — pin they agree so the
        // file split does not let the two drift apart.
        for scope in SummaryScope.allCases {
            #expect(
                AISummaryTabView.scopeChipIdentifier(scope)
                    == AISummaryScopeChipStrip.chipIdentifier(scope)
            )
        }
    }
}
