// Purpose: Feature #42 — navigator-delegate + DebugBridge coordinator for the
// Readium EPUB host. Conforms to `EPUBNavigatorDelegate` (position + settle +
// highlight-decoration restore) and (DEBUG) `ReadiumNavigatorEvaluating` (the
// eval seam). Extracted from `ReadiumEPUBHost.swift` (Gate-4 WI-9a: file-size
// split) so the host View, the representable, and the coordinator each live in
// their own file as the Readium engine grows through WI-10+.
//
// @coordinates-with ReadiumEPUBHost.swift, ReadiumNavigatorRepresentable.swift,
//   ReadiumEPUBHost+Navigation.swift, ReadiumDebugProbe.swift (DEBUG)

#if canImport(UIKit)
import SwiftUI
import UIKit
import OSLog
import ReadiumShared
import ReadiumNavigator

@MainActor
final class ReadiumReaderCoordinator: NSObject {
    private let fingerprintKey: String
    private let readerToken: UUID
    // Not `private`/`fileprivate` so the WI-9a `+Navigation` extension's nav
    // methods can log a no-navigator dispatch.
    let log = Logger(subsystem: "com.vreader.app", category: "ReadiumEPUB")

    /// Weak — the navigator is owned by the SwiftUI representable's controller
    /// lifecycle; the coordinator must not keep it alive past the host. Exposed
    /// (not `private`) so the WI-9a `+Navigation` extension's nav methods can
    /// dispatch `goForward` / `goBackward` / `go(to:)` to the live navigator.
    weak var boundNavigator: EPUBNavigatorViewController?

    /// WI-9a: the current reading layout, set by the representable from
    /// `ReaderSettingsStore.epubLayout` (kept in sync on each preference update).
    /// `navigator(_:didTapAt:)` passes it to `ReaderTapZoneRouter` so a side-tap
    /// turns the page only in `.paged` layout (in `.scroll` every tap toggles
    /// chrome, matching the legacy reader's tap contract).
    var currentLayout: EPUBLayoutPreference = .paged

    /// WI-9a: the host-owned navigation sink. `attach` binds this coordinator's
    /// nav methods into it; `detach` clears it so a late page-turn / jump intent
    /// no-ops after teardown. Optional because a non-nav call site (DebugBridge
    /// eval seam construction) need not supply one.
    private let navCommander: ReadiumNavCommander?

    /// WI-11b: the host-owned bilingual eval-channel sink. `attach` binds this
    /// coordinator's production `evaluateForBilingual` method into it; `detach`
    /// clears it so a late enumerate/inject/clear no-ops after teardown. Optional
    /// — a non-bilingual call site need not supply one. Mirrors `navCommander`.
    private let bilingualCommander: ReadiumBilingualCommander?

    /// WI-6: forwards `locationDidChange` to the host VM's debounced save.
    /// Dropped in `detach()` so no stale callback fires after teardown.
    private var onLocationChange: (@MainActor @Sendable (ReadiumShared.Locator) -> Void)?

    /// WI-8: the highlight adapter bound to this navigator. Detached on teardown
    /// so no stale decoration apply fires after the host leaves the hierarchy.
    private let highlightAdapter: ReadiumDecorationHighlightAdapter

    #if DEBUG
    /// Test seam: when set, `evaluateJavaScriptValue` uses this instead of the
    /// real navigator's `evaluateJavaScript`, so the JSON-serialization contract
    /// is unit-testable without a rendered spine WebView. Returns the raw value
    /// Readium's `Result<Any, Error>.success` would carry (`nil` = JS undefined).
    var evaluatorForTests: ((String) async -> Any?)?
    #endif

    init(
        fingerprintKey: String,
        readerToken: UUID,
        onLocationChange: (@MainActor @Sendable (ReadiumShared.Locator) -> Void)? = nil,
        // Gate-4 round-1 Low: no default — the adapter MUST be the host-owned
        // instance the `HighlightCoordinator` drives, else `detach()` would clear
        // a different adapter than the one attached to the navigator. Explicit
        // param removes that footgun; every call site passes the host's adapter.
        highlightAdapter: ReadiumDecorationHighlightAdapter,
        // WI-9a: the host-owned nav sink the coordinator binds its nav methods
        // into on `attach`. nil for non-nav construction.
        navCommander: ReadiumNavCommander? = nil,
        // WI-11b: the host-owned bilingual eval sink the coordinator binds its
        // production eval method into on `attach`. nil for non-bilingual
        // construction.
        bilingualCommander: ReadiumBilingualCommander? = nil
    ) {
        self.fingerprintKey = fingerprintKey
        self.readerToken = readerToken
        self.onLocationChange = onLocationChange
        self.highlightAdapter = highlightAdapter
        self.navCommander = navCommander
        self.bilingualCommander = bilingualCommander
        super.init()
    }

    func attach(navigator: EPUBNavigatorViewController) {
        self.boundNavigator = navigator
        // WI-9a: bind the host's nav sink to this coordinator's nav methods so
        // the host's `.readerNextPage` / `.readerPreviousPage` /
        // `.readerNavigateToLocator` observers drive the live navigator.
        navCommander?.bind(
            next: { [weak self] in self?.goToNextPage() },
            previous: { [weak self] in self?.goToPreviousPage() },
            navigate: { [weak self] locator in self?.navigate(to: locator) }
        )
        // WI-11b: bind the bilingual eval sink to this coordinator's production
        // eval method so the host's bilingual extension can drive the
        // enumerate/inject/clear loop on the live navigator's visible spine.
        bilingualCommander?.setEvaluator { [weak self] script in
            await self?.evaluateForBilingual(script)
        }
    }

    /// High (bug #252 lesson): host-teardown hook called from the
    /// representable's `dismantleUIViewController`. Clears this reader's
    /// DebugBridge registry slot (the slot holds the navigator `weak`, but the
    /// key/token + settle state otherwise linger until the weak ref nils — a
    /// reader-switch race in the verify harness; the legacy EPUB/Foliate slots
    /// get this from `unregister(_:)`, which the Readium host never triggers)
    /// and drops the navigator delegate + ref so no stale delegate callback
    /// fires after the host leaves the hierarchy.
    func detach() {
        #if DEBUG
        DebugReaderRegistry.shared.clearActiveReadiumNavigator(
            for: fingerprintKey, token: readerToken
        )
        #endif
        boundNavigator?.delegate = nil
        boundNavigator = nil
        onLocationChange = nil
        // WI-9a: clear the nav sink so a late page-turn / jump intent no-ops
        // after teardown (mirrors the navigator-weak discipline above).
        navCommander?.clear()
        // WI-11b: clear the bilingual eval sink so a late enumerate/inject/clear
        // no-ops after teardown (same navigator-weak discipline).
        bilingualCommander?.clearEvaluator()
        // WI-8: drop the adapter's navigator ref so no stale decoration apply
        // fires after teardown (mirrors the navigator-weak discipline above).
        highlightAdapter.detach()
    }
}

// MARK: - Bilingual eval seam (WI-11b, production)

extension ReadiumReaderCoordinator {
    /// WI-11b: PRODUCTION (non-DEBUG) eval that the `ReadiumBilingualCommander`
    /// binds on `attach`. Runs `script` on the live navigator's currently-visible
    /// spine HTML and returns Readium's raw `Result<Any, Error>`. Returns `nil`
    /// when no navigator is bound (before mount / after `detach`) so a late
    /// bilingual enumerate/inject/clear no-ops — the navigator is `weak`, so a
    /// deallocated navigator also reads nil. Unlike the DEBUG
    /// `evaluateJavaScriptValue` (which JSON-serializes into `Data` for the probe
    /// contract), this hands the raw value back so the commander can parse the
    /// `[{bid,text}]` array directly via `EPUBBilingualPipeline`.
    func evaluateForBilingual(_ script: String) async -> Result<Any, Error>? {
        guard let navigator = boundNavigator else { return nil }
        return await navigator.evaluateJavaScript(script)
    }
}

// MARK: - Navigator delegate

extension ReadiumReaderCoordinator: EPUBNavigatorDelegate {
    nonisolated func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
        // Surfaced by Readium for resource-load errors; logged, not fatal.
        Task { @MainActor in
            self.log.error("ReadiumEPUB navigator error: \(String(describing: error), privacy: .public)")
        }
    }

    /// WI-9a: Readium reports taps via the `VisualNavigatorDelegate` but does
    /// NOT auto-navigate on tap (the host decides) — which is why a bare reader
    /// tap did nothing before this. Route the tap through the shared
    /// `ReaderTapZoneRouter` (the same dispatcher the legacy bridges use): in
    /// `.paged` layout a left/right-zone tap posts `.readerNextPage` /
    /// `.readerPreviousPage` (→ the host's WI-9a observers → `goForward` /
    /// `goBackward`), a center tap posts `.readerContentTapped` (chrome toggle);
    /// in `.scroll` layout every tap toggles chrome. `point` is in the
    /// navigator view's coordinate space, so its `.x` against the view width is
    /// the correct zone fraction.
    func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) {
        let width = boundNavigator?.view.bounds.width ?? 0
        guard width > 0 else { return }
        ReaderTapZoneRouter.dispatch(
            x: point.x, totalWidth: width, layout: currentLayout
        )
    }

    func navigator(_ navigator: Navigator, locationDidChange locator: ReadiumShared.Locator) {
        // WI-6: forward the reported locator to the host VM's debounced save so
        // the reading position persists as the user navigates/scrolls.
        onLocationChange?(locator)
        // WI-4 probe wiring: register the active navigator + signal settle the
        // first time a spine is rendered and a location is reported, so the
        // DebugBridge eval/settle probes (eval?bridge=epub) reach this host.
        #if DEBUG
        // Register the coordinator (not the navigator) — the coordinator is the
        // `ReadiumNavigatorEvaluating` conformer that holds the navigator + the
        // JSON-serializing eval seam.
        DebugReaderRegistry.shared.setActiveReadiumNavigator(
            self, for: fingerprintKey, token: readerToken
        )
        DebugReaderRegistry.shared.markReaderSettled(
            for: fingerprintKey, token: readerToken
        )
        #endif
    }
}

#if DEBUG
// MARK: - DebugBridge eval seam (WI-4)

extension ReadiumReaderCoordinator: ReadiumNavigatorEvaluating {
    /// Evaluate `script` on the navigator's currently-visible spine HTML and
    /// JSON-serialize the success value into raw bytes (mirrors the EPUB/Foliate
    /// `jsEvaluator` contract: `nil`/undefined → `null`, then `JSONSerialization`
    /// with `.fragmentsAllowed` so scalars/arrays/objects all splat cleanly).
    func evaluateJavaScriptValue(_ script: String) async throws -> Data {
        let raw: Any?
        if let stub = evaluatorForTests {
            raw = await stub(script)
        } else {
            guard let navigator = boundNavigator else {
                throw DebugReaderProbeError.evalUnsupported(format: "epub")
            }
            switch await navigator.evaluateJavaScript(script) {
            case let .success(value):
                raw = value
            case let .failure(error):
                throw error
            }
        }
        let normalized: Any = raw ?? NSNull()
        return try JSONSerialization.data(
            withJSONObject: normalized,
            options: [.fragmentsAllowed]
        )
    }
}
#endif

#endif
