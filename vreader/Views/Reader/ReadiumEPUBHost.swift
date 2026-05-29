// Purpose: Feature #42 Phase 1 (WI-5) — SwiftUI host that renders an EPUB via
// the Readium Swift Toolkit `EPUBNavigatorViewController`, selected only when
// the `readiumEPUBEngine` flag is ON (the legacy `EPUBWebViewBridge`
// `EPUBReaderHost` stays the live default). Sibling of `EPUBReaderHost`: owns
// the `ReadiumEPUBReaderViewModel` + the navigator-hosting representable via
// `@State`, opens the publication off-main in `.task`, and tears the reading
// session down in `.onDisappear` (mirrors `EPUBReaderHost`'s bug-#252 lifecycle).
//
// Render scope (WI-5): open + render + scroll/paginate. WI-7: full live
// theme/font mapping — the body reads `ReaderSettingsStore.theme` +
// `.typography` + `.epubLayout`, recomputes `EPUBPreferences` on any change, and
// the representable re-submits them to the navigator. Highlight/search/TTS
// parity land in later WIs. Loading + error states reuse the existing reader's
// plain `ProgressView` + the dispatcher's `fingerprintErrorView`-style message
// (no new UI chrome — rule 51: this is an engine swap behind a dark flag for the
// already-designed EPUB reading surface).
//
// DebugBridge (WI-4 probe): the coordinator registers the active navigator on
// `navigator(_:locationDidChange:)` via `setActiveReadiumNavigator(_:for:token:)`
// and marks the reader settled, so `eval?bridge=epub` + settle probes reach the
// Readium spine WebView CU-free (the eval wiring is in ReaderContainerView's
// DEBUG `.onAppear`).
//
// @coordinates-with ReadiumEPUBReaderViewModel.swift, ReaderContainerView.swift,
//   ReadiumDebugProbe.swift (DEBUG)

#if canImport(UIKit)
import SwiftUI
import SwiftData
import UIKit
import OSLog
import ReadiumShared
import ReadiumNavigator

/// Owns `ReadiumEPUBReaderViewModel` lifecycle via @State and hosts the Readium
/// navigator. Selected by the dispatcher when `readiumEPUBEngine` is ON.
struct ReadiumEPUBHost: View {
    let fileURL: URL
    let fingerprint: DocumentFingerprint
    /// WI-6: threaded so the VM can build a `PersistenceActor` for reading
    /// position save/restore (mirrors `EPUBReaderHost`).
    let modelContainer: ModelContainer
    let settingsStore: ReaderSettingsStore
    /// Bug #142 / WI-4: per-reader instance token threaded into the coordinator's
    /// registry registration so a stale callback from an outgoing reader cannot
    /// clobber an incoming probe binding.
    var readerToken: UUID?

    @State private var viewModel: ReadiumEPUBReaderViewModel?
    /// WI-6: the restored Readium locator, loaded before the navigator mounts so
    /// it can be passed as `initialLocation`. nil = open at the start.
    @State private var restoredLocator: ReadiumShared.Locator?

    var body: some View {
        Group {
            switch viewModel?.state {
            case .ready(let publication):
                // WI-7: read `theme` + `typography` + `epubLayout` directly here
                // so SwiftUI tracks all three as `@Observable` dependencies of
                // this body — a Display-settings change mutates one of them,
                // re-runs the body, and re-builds the representable with fresh
                // preferences, which `updateUIViewController` then re-submits.
                ReadiumNavigatorRepresentable(
                    publication: publication,
                    preferences: ReadiumEPUBReaderViewModel.epubPreferences(
                        theme: settingsStore.theme,
                        typography: settingsStore.typography,
                        layout: settingsStore.epubLayout,
                        // Gate-4 round-1: feed the per-format-calibrated `.epub`
                        // size (the same calibration band the legacy EPUB engine
                        // renders through) so perceived font size stays consistent
                        // across the legacy and Readium engines.
                        calibratedFontSizePt: settingsStore.calibrator.calibratedSize(
                            forUnified: settingsStore.typography.fontSize, target: .epub
                        )
                    ),
                    fingerprintKey: fingerprint.canonicalKey,
                    readerToken: readerToken,
                    initialLocation: restoredLocator,
                    // Med-2: when `EPUBNavigatorViewController` init throws the
                    // representable can only return a placeholder controller
                    // synchronously — it routes the failure here so the host
                    // flips to `.failed` and shows the error view instead of a
                    // blank page. `[weak viewModel]` avoids capturing the View
                    // struct + mutating @State during a render pass.
                    onNavigatorInitFailure: { [weak viewModel] message in
                        viewModel?.markNavigatorInitFailed(message)
                    },
                    // WI-6: forward the navigator's `locationDidChange` into the
                    // VM's debounced save. `@MainActor @Sendable` (same posture
                    // as `onNavigatorInitFailure`) so the coordinator stays
                    // decoupled from the VM type.
                    onLocationChange: { [weak viewModel] locator in
                        viewModel?.save(readiumLocator: locator)
                    }
                )
                .ignoresSafeArea()
            case .failed:
                // Reuse the existing reader's failure messaging (rule 51 — no
                // new chrome): the same copy the dispatcher shows when a book
                // cannot be opened.
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Unable to open this book.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("readiumOpenErrorView")
            case .loading, .none:
                ProgressView()
            }
        }
        .task {
            guard viewModel == nil else { return }
            let persistence = PersistenceActor(modelContainer: modelContainer)
            let vm = ReadiumEPUBReaderViewModel(
                fileURL: fileURL,
                fingerprint: fingerprint,
                persistence: persistence,
                deviceId: ReaderContainerView.deviceId
            )
            viewModel = vm
            // WI-6: load the saved position BEFORE the navigator mounts (the
            // representable is only built once `state == .ready`) so the
            // navigator opens directly at the restored locator instead of the
            // start. nil → open at the start (first-open / nothing saved).
            restoredLocator = await vm.restoredReadiumLocator()
            await vm.open()
        }
        .onDisappear {
            // High (bug #252 lesson): host-level close lifecycle. The host owns
            // the VM (and through `.ready` its `Publication`) via @State, so the
            // close fires only when the host genuinely leaves the hierarchy (nav
            // pop) — releasing the publication's file handles deterministically
            // instead of waiting on @State teardown timing. The registry slot +
            // navigator teardown is handled in the representable's
            // `dismantleUIViewController` (it knows the coordinator's token).
            //
            // WI-6: `closeAndFlush()` awaits the final position save so a pending
            // debounced write completes before iOS suspends. Wrapped in a
            // background task like `EPUBReaderHost` so the save survives the
            // dismiss transition.
            guard let viewModel else { return }
            let bgTaskID = UIApplication.shared.beginBackgroundTask(
                expirationHandler: nil
            )
            Task {
                await viewModel.closeAndFlush()
                if bgTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTaskID)
                }
            }
        }
    }
}

/// Bridges the Readium `EPUBNavigatorViewController` into SwiftUI. The
/// coordinator owns the navigator-delegate callbacks + the DebugBridge
/// registration. Constructed only once the publication is open (the host gates
/// on `.ready`).
private struct ReadiumNavigatorRepresentable: UIViewControllerRepresentable {
    let publication: Publication
    let preferences: EPUBPreferences
    let fingerprintKey: String
    let readerToken: UUID?
    /// WI-6: the restored reading position to open at, or nil to open at the
    /// start. Passed straight into `EPUBNavigatorViewController(initialLocation:)`.
    let initialLocation: ReadiumShared.Locator?
    /// Med-2: invoked (on the main actor, deferred past the current render
    /// pass) when `EPUBNavigatorViewController` init throws, so the host can
    /// flip to `.failed`. `@MainActor @Sendable` so capturing it into the
    /// deferral `Task` is clean under `SWIFT_STRICT_CONCURRENCY = complete`
    /// (Gate-4 round-2 Med).
    var onNavigatorInitFailure: (@MainActor @Sendable (String) -> Void)?
    /// WI-6: invoked with the navigator's reported locator on every
    /// `locationDidChange`, so the host's VM can debounce-save the position.
    /// `@MainActor @Sendable` so the coordinator can hold it across the
    /// navigator-delegate boundary under strict concurrency.
    var onLocationChange: (@MainActor @Sendable (ReadiumShared.Locator) -> Void)?

    func makeCoordinator() -> ReadiumReaderCoordinator {
        ReadiumReaderCoordinator(
            fingerprintKey: fingerprintKey,
            readerToken: readerToken ?? UUID(),
            onLocationChange: onLocationChange
        )
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let config = EPUBNavigatorViewController.Configuration(preferences: preferences)
        do {
            let navigator = try EPUBNavigatorViewController(
                publication: publication,
                initialLocation: initialLocation,
                config: config
            )
            navigator.delegate = context.coordinator
            context.coordinator.attach(navigator: navigator)
            return navigator
        } catch {
            context.coordinator.log.error(
                "ReadiumEPUB navigator init failed: \(String(describing: error), privacy: .public)"
            )
            // Med-2: a representable must return a controller synchronously, so
            // hand back an empty placeholder and route the failure into host
            // state on the next main-actor turn (mutating @State synchronously
            // here would be a "modifying state during view update" violation).
            // The host then swaps this placeholder for its `.failed` error view.
            let handler = onNavigatorInitFailure
            let message = String(describing: error)
            Task { @MainActor in handler?(message) }
            return UIViewController()
        }
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        // WI-7: the host body reads `settingsStore.theme` + `.typography` +
        // `.epubLayout` and recomputes `preferences` on every Display-settings
        // change, so this re-submit applies the new theme/font/line-height/scroll
        // to the live navigator without a reopen.
        if let navigator = controller as? EPUBNavigatorViewController {
            navigator.submitPreferences(preferences)
        }
    }

    /// High (bug #252 lesson): deterministic navigator + registry teardown when
    /// the representable leaves the hierarchy. The coordinator knows its own
    /// `(fingerprintKey, token)` — which the host cannot when `readerToken` was
    /// nil and the coordinator generated its own — so it owns the clear.
    static func dismantleUIViewController(
        _ controller: UIViewController,
        coordinator: ReadiumReaderCoordinator
    ) {
        coordinator.detach()
    }
}

/// Navigator-delegate + DebugBridge coordinator for the Readium EPUB host.
/// `final class` (not the SwiftUI view) so it survives view-body recomputation
/// and can hold the navigator + per-reader token. `@MainActor` because the
/// navigator and its WebViews are main-actor-isolated (feature #42 Med-4).
@MainActor
final class ReadiumReaderCoordinator: NSObject {
    private let fingerprintKey: String
    private let readerToken: UUID
    fileprivate let log = Logger(subsystem: "com.vreader.app", category: "ReadiumEPUB")

    /// Weak — the navigator is owned by the SwiftUI representable's controller
    /// lifecycle; the coordinator must not keep it alive past the host.
    private weak var navigator: EPUBNavigatorViewController?

    /// WI-6: forwards `locationDidChange` to the host VM's debounced save.
    /// Dropped in `detach()` so no stale callback fires after teardown.
    private var onLocationChange: (@MainActor @Sendable (ReadiumShared.Locator) -> Void)?

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
        onLocationChange: (@MainActor @Sendable (ReadiumShared.Locator) -> Void)? = nil
    ) {
        self.fingerprintKey = fingerprintKey
        self.readerToken = readerToken
        self.onLocationChange = onLocationChange
        super.init()
    }

    func attach(navigator: EPUBNavigatorViewController) {
        self.navigator = navigator
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
        navigator?.delegate = nil
        navigator = nil
        onLocationChange = nil
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
            guard let navigator else {
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
