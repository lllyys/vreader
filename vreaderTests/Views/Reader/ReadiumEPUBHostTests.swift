// Purpose: Feature #42 Phase 1 WI-5 — unit tests for the testable seams of the
// Readium EPUB host: (1) the pure dispatch routing decision (flag ON →
// `.epubReadium`, flag OFF → `.epubWKWebView`); (2) the `EPUBLayoutPreference`
// → Readium `EPUBPreferences(scroll:)` mapping; (3) the coordinator's
// `ReadiumNavigatorEvaluating` JSON serialization of a navigator eval result
// (fed through a stub navigator-evaluator closure so no real WebView renders).
//
// The render itself (UIViewControllerRepresentable hosting
// EPUBNavigatorViewController) is exercised by device verification, not here.
//
// @coordinates-with vreader/Views/Reader/ReadiumEPUBHost.swift,
//   vreader/ViewModels/ReadiumEPUBReaderViewModel.swift,
//   vreader/Models/ReaderEngine.swift

import Testing
import Foundation
import ReadiumNavigator
@testable import vreader

@Suite("ReadiumEPUBHost (WI-5)")
struct ReadiumEPUBHostTests {

    // MARK: - Dispatch routing (pure, flag-driven)

    @Test func routeEPUB_flagOff_isLegacyWKWebView() {
        #expect(ReaderEngine.routeEPUB(readiumFlagEnabled: false) == .epubWKWebView)
    }

    @Test func routeEPUB_flagOn_isReadium() {
        #expect(ReaderEngine.routeEPUB(readiumFlagEnabled: true) == .epubReadium)
    }

    /// `resolve(format:)` stays the pure format→default-engine map (the flag
    /// branch lives in the dispatcher, NOT here) — EPUB still resolves to the
    /// legacy engine so a flag-unaware caller gets today's behavior.
    @Test func resolve_epub_unchanged_isLegacy() {
        #expect(ReaderEngine.resolve(format: .epub) == .epubWKWebView)
    }

    @Test func epubReadium_isACase_andRoundTrips() {
        #expect(ReaderEngine.allCases.contains(.epubReadium))
        #expect(ReaderEngine(rawValue: "epubReadium") == .epubReadium)
        #expect(ReaderEngine.epubReadium.rawValue == "epubReadium")
    }

    // MARK: - EPUBLayoutPreference → EPUBPreferences(scroll:)

    @Test func preferences_scrollLayout_enablesScroll() {
        let prefs = ReadiumEPUBReaderViewModel.epubPreferences(for: .scroll)
        #expect(prefs.scroll == true)
    }

    @Test func preferences_pagedLayout_disablesScroll() {
        let prefs = ReadiumEPUBReaderViewModel.epubPreferences(for: .paged)
        #expect(prefs.scroll == false)
    }

    // MARK: - Coordinator eval serialization (ReadiumNavigatorEvaluating)

    /// Stub navigator-evaluator that returns a caller-supplied raw value (the
    /// shape Readium's `evaluateJavaScript(_:) -> Result<Any, Error>` yields on
    /// success), so the coordinator's JSON-serialization contract is testable
    /// without a real spine WebView.
    @MainActor
    private func coordinator(returning value: Any?) -> ReadiumReaderCoordinator {
        let coord = ReadiumReaderCoordinator(
            fingerprintKey: "epub:\(String(repeating: "a", count: 64)):10",
            readerToken: UUID(),
            highlightAdapter: ReadiumDecorationHighlightAdapter()
        )
        coord.evaluatorForTests = { _ in value }
        return coord
    }

    @MainActor
    private func decode(_ data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    @MainActor @Test func eval_serializesNumber() async throws {
        let data = try await coordinator(returning: 42).evaluateJavaScriptValue("1+41")
        #expect(try decode(data) as? Int == 42)
    }

    @MainActor @Test func eval_serializesString() async throws {
        let data = try await coordinator(returning: "hello").evaluateJavaScriptValue("'hello'")
        #expect(try decode(data) as? String == "hello")
    }

    @MainActor @Test func eval_serializesArray() async throws {
        let data = try await coordinator(returning: [1, 2, 3]).evaluateJavaScriptValue("[1,2,3]")
        let arr = try decode(data) as? [Int]
        #expect(arr == [1, 2, 3])
    }

    @MainActor @Test func eval_serializesObject() async throws {
        let data = try await coordinator(returning: ["k": "v"]).evaluateJavaScriptValue("({k:'v'})")
        let obj = try decode(data) as? [String: String]
        #expect(obj?["k"] == "v")
    }

    /// JS `undefined` / Swift `nil` → JSON `null` (mirrors the EPUB/Foliate
    /// jsEvaluator `raw ?? NSNull()` contract so the bridge can splat it).
    @MainActor @Test func eval_undefinedBecomesNull() async throws {
        let data = try await coordinator(returning: nil).evaluateJavaScriptValue("void 0")
        #expect(try decode(data) is NSNull)
    }

    /// CJK string round-trips through UTF-8 JSON without mojibake (edge case).
    @MainActor @Test func eval_serializesCJK() async throws {
        let data = try await coordinator(returning: "被讨厌的勇气").evaluateJavaScriptValue("title")
        #expect(try decode(data) as? String == "被讨厌的勇气")
    }

    // MARK: - VM teardown + init-failure state (Codex Gate-4 round 2)

    /// Med-2: a thrown navigator init is surfaced into the VM's render state so
    /// the host shows its error view instead of a blank placeholder controller.
    @MainActor @Test func markNavigatorInitFailed_setsFailedWithMessage() {
        let vm = ReadiumEPUBReaderViewModel(fileURL: URL(fileURLWithPath: "/dev/null"))
        vm.markNavigatorInitFailed("navigator init threw")
        guard case let .failed(message) = vm.state else {
            Issue.record("expected .failed state, got \(vm.state)")
            return
        }
        #expect(message == "navigator init threw")
    }

    /// High: `close()` drops whatever the VM was holding (releasing the
    /// publication's file handles in the `.ready` case) and returns to loading.
    /// Driven from `.failed` here because constructing a real `.ready`
    /// `Publication` needs a fixture open; the state reassignment is the same
    /// code path that drops a `.ready(Publication)`.
    @MainActor @Test func close_resetsToLoading() {
        let vm = ReadiumEPUBReaderViewModel(fileURL: URL(fileURLWithPath: "/dev/null"))
        vm.markNavigatorInitFailed("boom")
        vm.close()
        guard case .loading = vm.state else {
            Issue.record("close should reset to .loading, got \(vm.state)")
            return
        }
    }

    /// High (Gate-4 round 2): a dismiss-during-open must not install a result.
    /// `close()` (host `.onDisappear`) runs before a still-suspended `open()`
    /// resumes; the `isClosed` guard makes `open()` a no-op so no `.ready` /
    /// `.failed` is written into the closed VM.
    @MainActor @Test func open_afterClose_isNoOp() async {
        let vm = ReadiumEPUBReaderViewModel(
            fileURL: URL(fileURLWithPath: "/nonexistent/missing.epub")
        )
        vm.close()
        await vm.open()
        guard case .loading = vm.state else {
            Issue.record("open() after close() must not mutate state, got \(vm.state)")
            return
        }
    }

    #if DEBUG
    // MARK: - Registry deterministic teardown (Codex Gate-4 round 2 — High)

    /// `clearActiveReadiumNavigator` drops the slot when the key+token match,
    /// so a Readium host (which registers no `DebugReaderProbe`) can tear its
    /// registry binding down deterministically on dismantle.
    @MainActor @Test func clearActiveReadiumNavigator_clearsMatchingSlot() {
        let registry = DebugReaderRegistry.makeIsolatedForTests()
        let token = UUID()
        let key = "epub:\(String(repeating: "a", count: 64)):10"
        // Strong local ref — the registry holds the navigator weak.
        let coord = ReadiumReaderCoordinator(fingerprintKey: key, readerToken: token, highlightAdapter: ReadiumDecorationHighlightAdapter())
        registry.setActiveReadiumNavigator(coord, for: key, token: token)
        #expect(registry.readiumNavigator(for: key, token: token) != nil)

        registry.clearActiveReadiumNavigator(for: key, token: token)
        #expect(registry.readiumNavigator(for: key, token: token) == nil)
        #expect(registry.rawActiveReadiumNavigatorKeyForTests == nil)
        _ = coord // keep alive across the clear
    }

    /// A late detach from an outgoing reader (mismatched key) must not wipe the
    /// current reader's binding (bug #142 stale-write class).
    @MainActor @Test func clearActiveReadiumNavigator_ignoresNonMatchingKey() {
        let registry = DebugReaderRegistry.makeIsolatedForTests()
        let token = UUID()
        let key = "epub:\(String(repeating: "b", count: 64)):20"
        let coord = ReadiumReaderCoordinator(fingerprintKey: key, readerToken: token, highlightAdapter: ReadiumDecorationHighlightAdapter())
        registry.setActiveReadiumNavigator(coord, for: key, token: token)

        registry.clearActiveReadiumNavigator(for: "epub:other:1", token: token)
        #expect(registry.readiumNavigator(for: key, token: token) != nil)

        registry.clearActiveReadiumNavigator(for: key, token: UUID())
        #expect(registry.readiumNavigator(for: key, token: token) != nil)
        _ = coord
    }

    /// Med (Gate-4 round 2): in a same-book quick reopen, the outgoing reader A
    /// still owns the slot while `expectedReaderToken` belongs to incoming
    /// reader B. A's detach must clear its OWN settle state without clobbering
    /// B's (mirrors `unregister(_:)`'s `preservingToken` posture).
    @MainActor @Test func clearActiveReadiumNavigator_preservesIncomingTokenSettleState() {
        let registry = DebugReaderRegistry.makeIsolatedForTests()
        let key = "epub:\(String(repeating: "c", count: 64)):30"
        let tokenA = UUID()
        let tokenB = UUID()
        let coordA = ReadiumReaderCoordinator(fingerprintKey: key, readerToken: tokenA, highlightAdapter: ReadiumDecorationHighlightAdapter())
        // A registers first (no expected token yet), then B claims the slot
        // expectation + settles.
        registry.setActiveReadiumNavigator(coordA, for: key, token: tokenA)
        registry.setExpectedReaderToken(tokenB)
        registry.markReaderSettled(for: key, token: tokenB)
        #expect(registry.settledKeys.contains(.init(fingerprintKey: key, token: tokenB)))

        registry.clearActiveReadiumNavigator(for: key, token: tokenA)
        #expect(registry.settledKeys.contains(.init(fingerprintKey: key, token: tokenB)))
        _ = coordA
    }

    /// When the leaving reader IS the last reader for the key (no incoming
    /// `expectedReaderToken`), its detach clears ALL of the key's settle state.
    @MainActor @Test func clearActiveReadiumNavigator_clearsOwnSettleWhenLastReader() {
        let registry = DebugReaderRegistry.makeIsolatedForTests()
        let key = "epub:\(String(repeating: "d", count: 64)):40"
        let token = UUID()
        let coord = ReadiumReaderCoordinator(fingerprintKey: key, readerToken: token, highlightAdapter: ReadiumDecorationHighlightAdapter())
        registry.setActiveReadiumNavigator(coord, for: key, token: token)
        registry.markReaderSettled(for: key, token: token)
        #expect(registry.settledKeys.contains(.init(fingerprintKey: key, token: token)))

        registry.clearActiveReadiumNavigator(for: key, token: token)
        #expect(!registry.settledKeys.contains(.init(fingerprintKey: key, token: token)))
        _ = coord
    }
    #endif
}

/// Bug #313: the Readium host is the only format host that never posted
/// `.readerPositionDidChange`, so `ReaderContainerView.currentLocator` stayed
/// nil for Readium EPUBs → the TOC sheet couldn't highlight/scroll to the
/// current chapter (and the AI-panel locator was stale). `ReadiumPositionBroadcast`
/// is the testable seam the host's `onLocationChange` now delegates to — it
/// posts the spine-href-carrying vreader `Locator`, and is a no-op when the
/// relocate can't be resolved to a locator (so nothing clobbers a good
/// `currentLocator` with garbage).
@Suite("ReadiumPositionBroadcast (Bug #313)")
@MainActor
struct ReadiumPositionBroadcastTests {

    private func sampleLocator(href: String = "OEBPS/ch3.xhtml") -> Locator {
        Locator.validated(
            bookFingerprint: DocumentFingerprint(
                contentSHA256: String(repeating: "a", count: 64),
                fileByteCount: 10,
                format: .epub
            ),
            href: href,
            progression: 0.25
        )!
    }

    @Test func post_withLocator_postsReaderPositionDidChange() {
        let center = NotificationCenter()
        let locator = sampleLocator()
        nonisolated(unsafe) var received: Locator?
        let token = center.addObserver(
            forName: .readerPositionDidChange, object: nil, queue: nil
        ) { note in received = note.object as? Locator }
        defer { center.removeObserver(token) }

        ReadiumPositionBroadcast.post(locator, on: center)

        #expect(received == locator)
    }

    @Test func post_withNil_doesNotPost() {
        let center = NotificationCenter()
        nonisolated(unsafe) var fired = false
        let token = center.addObserver(
            forName: .readerPositionDidChange, object: nil, queue: nil
        ) { _ in fired = true }
        defer { center.removeObserver(token) }

        ReadiumPositionBroadcast.post(nil, on: center)

        #expect(fired == false)
    }

    // MARK: - spineResolved gate (Codex Gate-4 MED)

    @Test func spineResolved_hrefInSpine_returnsLocator() {
        let locator = sampleLocator(href: "OEBPS/ch3.xhtml")
        let resolved = ReadiumPositionBroadcast.spineResolved(
            locator, spineHrefs: ["OEBPS/ch1.xhtml", "OEBPS/ch3.xhtml"]
        )
        #expect(resolved == locator)
    }

    @Test func spineResolved_hrefNotInSpine_returnsNil() {
        // An unresolved Readium container-relative href that matches no spine
        // entry must NOT be posted (else it clobbers a good currentLocator).
        let locator = sampleLocator(href: "container/raw-unresolved.xhtml")
        let resolved = ReadiumPositionBroadcast.spineResolved(
            locator, spineHrefs: ["OEBPS/ch1.xhtml", "OEBPS/ch3.xhtml"]
        )
        #expect(resolved == nil)
    }

    @Test func spineResolved_nilLocator_returnsNil() {
        #expect(ReadiumPositionBroadcast.spineResolved(nil, spineHrefs: ["OEBPS/ch1.xhtml"]) == nil)
    }

    @Test func spineResolved_emptySpine_returnsNil() {
        let locator = sampleLocator()
        #expect(ReadiumPositionBroadcast.spineResolved(locator, spineHrefs: []) == nil)
    }

    /// End-to-end through the gate: a resolved relocate reaches the bus; an
    /// unresolved one does not (so `currentLocator` is preserved).
    @Test func post_spineResolved_onlyPostsResolvableHref() {
        let center = NotificationCenter()
        let spine = ["OEBPS/ch3.xhtml"]
        nonisolated(unsafe) var postCount = 0
        let token = center.addObserver(
            forName: .readerPositionDidChange, object: nil, queue: nil
        ) { _ in postCount += 1 }
        defer { center.removeObserver(token) }

        ReadiumPositionBroadcast.post(
            ReadiumPositionBroadcast.spineResolved(sampleLocator(href: "OEBPS/ch3.xhtml"), spineHrefs: spine),
            on: center
        )
        ReadiumPositionBroadcast.post(
            ReadiumPositionBroadcast.spineResolved(sampleLocator(href: "raw/unresolved.xhtml"), spineHrefs: spine),
            on: center
        )

        #expect(postCount == 1)
    }
}
