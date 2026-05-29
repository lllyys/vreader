// Purpose: Feature #42 Phase 1 WI-9a — navigation wiring for the Readium EPUB
// host: page-turn (`.readerNextPage` / `.readerPreviousPage`) + jump
// (`.readerNavigateToLocator`) intents drive the live
// `EPUBNavigatorViewController`. Extracted from `ReadiumEPUBHost.swift` to keep
// that file under the ~300-line budget; this file owns the host→coordinator
// indirection (`ReadiumNavCommander`) + the coordinator's nav methods.
//
// Host → coordinator indirection (the mirror of WI-6/WI-8 wiring):
// - WI-6 threads callbacks coordinator → host (`onLocationChange`,
//   `onNavigatorInitFailure`); WI-8 has the host own the `highlightAdapter` via
//   `@State` and the representable bind it to the navigator. Nav needs the
//   REVERSE of the WI-6 direction — host → coordinator — and follows the WI-8
//   ownership shape exactly: the host owns a `ReadiumNavCommander` via `@State`
//   and passes it into the representable; the coordinator registers its
//   navigator-backed handlers into the commander on `attach` and clears them on
//   `detach`. The host's `.onReceive` nav handlers call the commander, which
//   forwards to whatever live navigator is currently bound (or no-ops before
//   `attach` / after `detach`). This keeps the coordinator off the View struct
//   (it survives body recomputation) without the host holding the navigator
//   directly — the same decoupling WI-6/WI-8 use.
//
// Nav dispatch is `async` (Readium's `go*` are `async @MainActor`); the
// commander wraps each call in a `Task` so the synchronous `.onReceive` handler
// stays non-blocking. The async navigator call itself is device-verified (the
// concrete `EPUBNavigatorViewController` has no protocol seam to fake); the
// commander's bind/clear lifecycle + the pure locator mapping are unit-tested.
//
// @coordinates-with ReadiumEPUBHost.swift,
//   ReadiumEPUBReaderViewModel+Navigation.swift, ReaderNotifications.swift

#if canImport(UIKit)
import Foundation
import ReadiumShared
import ReadiumNavigator

/// Host-owned sink for reader navigation intents. The host holds it via `@State`
/// and posts page-turn / jump intents into it; the coordinator binds its
/// navigator-backed handlers on `attach` and clears them on `detach`. No-ops
/// when nothing is bound (before the navigator mounts / after teardown), so a
/// late notification can never reach a torn-down navigator.
@MainActor
final class ReadiumNavCommander {
    /// Set by the coordinator on `attach`; each forwards to the live navigator.
    /// `@MainActor @Sendable` so they survive the navigator-delegate boundary
    /// under `SWIFT_STRICT_CONCURRENCY = complete`.
    private var onNextPage: (@MainActor @Sendable () -> Void)?
    private var onPreviousPage: (@MainActor @Sendable () -> Void)?
    private var onNavigate: (@MainActor @Sendable (ReadiumShared.Locator) -> Void)?

    init() {}

    /// Coordinator → commander binding. Called from `ReadiumReaderCoordinator.attach`.
    func bind(
        next: @escaping @MainActor @Sendable () -> Void,
        previous: @escaping @MainActor @Sendable () -> Void,
        navigate: @escaping @MainActor @Sendable (ReadiumShared.Locator) -> Void
    ) {
        onNextPage = next
        onPreviousPage = previous
        onNavigate = navigate
    }

    /// Drops all handlers so a late intent no-ops after teardown. Called from
    /// `ReadiumReaderCoordinator.detach`.
    func clear() {
        onNextPage = nil
        onPreviousPage = nil
        onNavigate = nil
    }

    func nextPage() { onNextPage?() }
    func previousPage() { onPreviousPage?() }
    func navigate(to locator: ReadiumShared.Locator) { onNavigate?(locator) }
}

// MARK: - Coordinator nav methods

extension ReadiumReaderCoordinator {

    /// Turns to the next page (paginated) or scrolls forward (scroll mode) via
    /// the navigator's `goForward`. No-op + log when no navigator is attached.
    ///
    /// Gate-4 Medium: `boundNavigator` is re-read INSIDE the `Task`, not captured
    /// before the async hop — so if `detach()` (from `dismantleUIViewController`)
    /// nils it between the intent firing and the task executing, the task
    /// no-ops instead of driving a torn-down navigator. `boundNavigator` is weak,
    /// so a deallocated navigator also reads nil.
    func goToNextPage() {
        Task { [weak self] in
            guard let navigator = self?.boundNavigator else { return }
            _ = await navigator.goForward(options: NavigatorGoOptions(animated: true))
        }
    }

    /// Turns to the previous page / scrolls backward via `goBackward`.
    func goToPreviousPage() {
        Task { [weak self] in
            guard let navigator = self?.boundNavigator else { return }
            _ = await navigator.goBackward(options: NavigatorGoOptions(animated: true))
        }
    }

    /// Jumps to a Readium locator (TOC / bookmark / search result) via `go(to:)`.
    func navigate(to readiumLocator: ReadiumShared.Locator) {
        Task { [weak self] in
            guard let navigator = self?.boundNavigator else { return }
            _ = await navigator.go(to: readiumLocator, options: NavigatorGoOptions(animated: true))
        }
    }
}
#endif
