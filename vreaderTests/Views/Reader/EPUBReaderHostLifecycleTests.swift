// Purpose: Regression tests for bug #252 (GH #1089) — EPUB DebugBridge open
// path's `EPUBWebViewBridge.updateUIView` never invoked because a transient
// `EPUBReaderContainerView` re-mount during the open flow caused the
// disappearing instance's `.onDisappear` to call `viewModel.close()`, which
// closed the shared parser before the appearing instance could call
// `parser.resourceBaseURL()` — surfacing as "Failed to resolve book
// resources." on screen and zero EPUB log activity between
// `[DebugBridge] open` and a 30s settle timeout.
//
// The fix moves `viewModel.close()` from `EPUBReaderContainerView.onDisappear`
// to `EPUBReaderHost.onDisappear` so the close is tied to the resource
// owner (the host's `@State viewModel + parser`), not to transient
// container instances. These tests pin the invariants that fix relies on.
//
// @coordinates-with EPUBReaderContainerView.swift, ReaderFormatHosts.swift,
//   EPUBReaderViewModel.swift, EPUBParser.swift, MockEPUBParser.swift

import Testing
import Foundation
@testable import vreader

@Suite("EPUBReaderHost lifecycle (bug #252 / GH #1089)")
@MainActor
struct EPUBReaderHostLifecycleTests {

    // MARK: - Fixtures (shadow EPUBReaderViewModelTests so this suite is self-contained)

    private static let fingerprint = DocumentFingerprint(
        contentSHA256: "epub_host_lifecycle_test_sha256_000000000000000000000000000000",
        fileByteCount: 65_536,
        format: .epub
    )

    private static let spineItems = [
        EPUBSpineItem(id: "ch1", href: "chapter1.xhtml", title: "Chapter 1", index: 0),
        EPUBSpineItem(id: "ch2", href: "chapter2.xhtml", title: "Chapter 2", index: 1),
    ]

    private static let metadata = EPUBMetadata(
        title: "Bug #252 Regression Fixture",
        author: "Test",
        language: "en",
        readingDirection: .ltr,
        layout: .reflowable,
        spineItems: spineItems
    )

    private static let testURL = URL(fileURLWithPath: "/tmp/bug-252-fixture.epub")

    private func makeViewModel() async -> (EPUBReaderViewModel, MockEPUBParser) {
        let parser = MockEPUBParser()
        await parser.setMetadata(Self.metadata)

        let positionStore = MockPositionStore()
        let sessionStore = MockSessionStore()
        let clock = MockClock()
        let tracker = ReadingSessionTracker(
            clock: clock,
            store: sessionStore,
            deviceId: "test-device"
        )

        let vm = EPUBReaderViewModel(
            bookFingerprint: Self.fingerprint,
            parser: parser,
            positionStore: positionStore,
            sessionTracker: tracker,
            deviceId: "test-device"
        )
        return (vm, parser)
    }

    // MARK: - Case 1: parser resources reachable after a fresh open

    /// Sanity baseline — after `viewModel.open` succeeds, the parser
    /// reports itself open and `resourceBaseURL` / `extractedRootURL`
    /// don't throw. This is the happy path the bug breaks.
    @Test("after viewModel.open succeeds, parser exposes its directories")
    func case1_openSucceeds_parserExposesDirectories() async throws {
        let (vm, parser) = await makeViewModel()
        await vm.open(url: Self.testURL)
        #expect(vm.metadata != nil)
        #expect(await parser.isOpen)
        // These would throw .notOpen if the parser were closed under us.
        _ = try await parser.resourceBaseURL()
        _ = try await parser.extractedRootURL()
    }

    // MARK: - Case 2: viewModel.close closes the parser — root-cause pin

    /// Root-cause pin: `viewModel.close()` closes the shared parser. The
    /// fix doesn't change THIS behavior at the viewmodel level — the
    /// close MUST close the parser when the resource owner (the host) is
    /// going away. The fix is at the VIEW level: the inner
    /// `EPUBReaderContainerView` no longer triggers this close path on
    /// transient re-mounts. This test pins the precondition that makes
    /// the view-level fix necessary in the first place.
    @Test("viewModel.close closes the parser — explains why an inappropriate close kills resourceBaseURL")
    func case2_closeClosesParser_explainsWhyInnerOnDisappearMustNotCallIt() async throws {
        let (vm, parser) = await makeViewModel()
        await vm.open(url: Self.testURL)
        #expect(await parser.isOpen)
        await vm.close()
        #expect(await parser.isOpen == false)
        // Subsequent resource probes throw .notOpen — exactly the failure
        // the host-driven DebugBridge open hit at line 192-194 of
        // EPUBReaderContainerView when the inner onDisappear closed the
        // parser before the new container's task could resolve its base
        // directories.
        await #expect(throws: EPUBParserError.self) {
            _ = try await parser.resourceBaseURL()
        }
        await #expect(throws: EPUBParserError.self) {
            _ = try await parser.extractedRootURL()
        }
    }

    // MARK: - Case 3: viewModel survives a real host-disappear close cycle

    /// When the host genuinely disappears (e.g. navigation pop), the
    /// host's `.onDisappear` calls `viewModel.close()`. A SUBSEQUENT
    /// open on a FRESH host+viewModel pair (the user navigates back
    /// into the book) must succeed cleanly — open is not stuck in
    /// an inconsistent state after a clean close. This codifies that
    /// the architectural fix does not break the normal close-then-reopen
    /// pattern: the close-on-host-disappear semantics remain intact.
    @Test("a fresh viewModel can open after a previous one closed")
    func case3_freshViewModelOpens_afterPreviousClosed() async throws {
        // Round 1: open then close on viewModel A.
        let (vmA, parserA) = await makeViewModel()
        await vmA.open(url: Self.testURL)
        #expect(vmA.metadata != nil)
        await vmA.close()
        #expect(await parserA.isOpen == false)

        // Round 2: a brand-new host instantiates its OWN viewModel +
        // parser (the host's `@State` is destroyed on nav-pop and
        // recreated on push). The new pair must open without observing
        // any residual state from round 1.
        let (vmB, parserB) = await makeViewModel()
        await vmB.open(url: Self.testURL)
        #expect(vmB.metadata != nil)
        #expect(await parserB.isOpen)
        _ = try await parserB.resourceBaseURL()
    }

    // MARK: - Case 4: open on same viewModel after close — explicit recovery

    /// Defense-in-depth: if for any reason `viewModel.close()` runs
    /// while the SAME viewModel is still in use (e.g. an unforeseen
    /// SwiftUI lifecycle quirk we haven't predicted), a SUBSEQUENT
    /// `viewModel.open()` must re-open the parser cleanly. The
    /// `_isLoading` guard inside `viewModel.open` doesn't trip because
    /// `close()` already returned and `isLoading` is false. This pins
    /// the resilience the viewmodel offers if the architectural fix
    /// ever lets a close+open cycle land on the same instance.
    @Test("viewModel.open succeeds again after viewModel.close on the same instance")
    func case4_sameViewModelReOpens_afterClose() async throws {
        let (vm, parser) = await makeViewModel()
        await vm.open(url: Self.testURL)
        #expect(vm.metadata != nil)
        #expect(await parser.isOpen)

        await vm.close()
        #expect(vm.metadata == nil)
        #expect(await parser.isOpen == false)

        // Re-open succeeds — the parser's `.alreadyOpen` guard isn't
        // tripped because close() reset `_isOpen` to false. The mock's
        // openCallCount records both invocations so a regression that
        // silently no-ops the second open is detected.
        await vm.open(url: Self.testURL)
        #expect(vm.metadata != nil)
        #expect(await parser.isOpen)
        let count = await parser.openCallCount
        #expect(count == 2)
        // Resource probes work again on the re-opened parser.
        _ = try await parser.resourceBaseURL()
    }
}
