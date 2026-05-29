// Purpose: Feature #42 Phase 1 (WI-5) — SwiftUI host that renders an EPUB via
// the Readium Swift Toolkit `EPUBNavigatorViewController`, selected only when
// the `readiumEPUBEngine` flag is ON (the legacy `EPUBWebViewBridge`
// `EPUBReaderHost` stays the live default). Sibling of `EPUBReaderHost`: owns
// the `ReadiumEPUBReaderViewModel` + the navigator-hosting representable via
// `@State`, opens the publication off-main in `.task`, and tears the reading
// session down in `.onDisappear` (mirrors `EPUBReaderHost`'s bug-#252 lifecycle).
//
// Render scope (WI-5): open + render + scroll/paginate (`EPUBPreferences(scroll:)`
// from `ReaderSettingsStore.epubLayout`). Position/highlight/theme/search/TTS
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
import UIKit
import OSLog
import ReadiumShared
import ReadiumNavigator

/// Owns `ReadiumEPUBReaderViewModel` lifecycle via @State and hosts the Readium
/// navigator. Selected by the dispatcher when `readiumEPUBEngine` is ON.
struct ReadiumEPUBHost: View {
    let fileURL: URL
    let fingerprint: DocumentFingerprint
    let settingsStore: ReaderSettingsStore
    /// Bug #142 / WI-4: per-reader instance token threaded into the coordinator's
    /// registry registration so a stale callback from an outgoing reader cannot
    /// clobber an incoming probe binding.
    var readerToken: UUID?

    @State private var viewModel: ReadiumEPUBReaderViewModel?

    var body: some View {
        Group {
            switch viewModel?.state {
            case .ready(let publication):
                ReadiumNavigatorRepresentable(
                    publication: publication,
                    preferences: ReadiumEPUBReaderViewModel.epubPreferences(
                        for: settingsStore.epubLayout
                    ),
                    fingerprintKey: fingerprint.canonicalKey,
                    readerToken: readerToken
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
            let vm = ReadiumEPUBReaderViewModel(fileURL: fileURL)
            viewModel = vm
            await vm.open()
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

    func makeCoordinator() -> ReadiumReaderCoordinator {
        ReadiumReaderCoordinator(
            fingerprintKey: fingerprintKey,
            readerToken: readerToken ?? UUID()
        )
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let config = EPUBNavigatorViewController.Configuration(preferences: preferences)
        do {
            let navigator = try EPUBNavigatorViewController(
                publication: publication,
                initialLocation: nil,
                config: config
            )
            navigator.delegate = context.coordinator
            context.coordinator.attach(navigator: navigator)
            return navigator
        } catch {
            context.coordinator.log.error(
                "ReadiumEPUB navigator init failed: \(String(describing: error), privacy: .public)"
            )
            // Empty controller — the host's `.failed` branch normally pre-empts
            // this; a precondition failure here would crash the reader.
            return UIViewController()
        }
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        // WI-5 renders a fixed layout preference; live preference updates
        // (theme/font/scroll toggle) land in WI-7. Re-submit the current
        // preference so a re-render after a settings change reflects it.
        if let navigator = controller as? EPUBNavigatorViewController {
            navigator.submitPreferences(preferences)
        }
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

    #if DEBUG
    /// Test seam: when set, `evaluateJavaScriptValue` uses this instead of the
    /// real navigator's `evaluateJavaScript`, so the JSON-serialization contract
    /// is unit-testable without a rendered spine WebView. Returns the raw value
    /// Readium's `Result<Any, Error>.success` would carry (`nil` = JS undefined).
    var evaluatorForTests: ((String) async -> Any?)?
    #endif

    init(fingerprintKey: String, readerToken: UUID) {
        self.fingerprintKey = fingerprintKey
        self.readerToken = readerToken
        super.init()
    }

    func attach(navigator: EPUBNavigatorViewController) {
        self.navigator = navigator
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
