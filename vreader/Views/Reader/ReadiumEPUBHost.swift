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
// the representable re-submits them to the navigator. WI-7 photo/custom-bg
// compositing layers `ThemeBackgroundView` behind the navigator (a transparent
// navigator over the decorative image) — wrapper + reload observers in
// `ReadiumEPUBHost+Background`. Highlight/search/TTS parity land in later WIs.
// Loading + error states reuse the existing reader's plain `ProgressView` + the
// dispatcher's `fingerprintErrorView`-style message (no new UI chrome — rule 51:
// this is an engine swap behind a dark flag for the designed EPUB surface).
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
    /// WI-8: renders stored highlights as Readium decorations. Owned by the host
    /// (via @State) so the same instance is both attached to the live navigator
    /// (in the representable's `makeUIViewController`) and driven by the host's
    /// `HighlightCoordinator` restore / `.readerHighlightRemoved` observer.
    @State private var highlightAdapter = ReadiumDecorationHighlightAdapter()
    /// WI-8: restore-on-open + create/remove plumbing through the shared
    /// highlight lifecycle (renderer = `highlightAdapter`). Built in `.task`
    /// once a `modelContainer` is available.
    @State private var highlightCoordinator: HighlightCoordinator?
    /// WI-9a: host-owned navigation sink. Passed into the representable, where
    /// the coordinator binds its nav methods on `attach`; the host's page-turn /
    /// jump `.onReceive` observers post into it. Owned here (like
    /// `highlightAdapter`) so the same instance survives body recomputation.
    @State private var navCommander = ReadiumNavCommander()

    // MARK: - WI-11b/WI-12 bilingual (per-spine interlinear via the eval channel)

    // All non-`private` so the `ReadiumEPUBHost+Bilingual` / `+BilingualDriver`
    // extensions (separate files) read/write them — `@State` cannot live in an
    // extension. Owned here (like `navCommander` / `highlightAdapter`) so the same
    // instances survive body recomputation. WI-12: works in both paged and scroll,
    // per-spine (no stitched cross-chapter bilingual — that stays legacy #71 only).

    /// Host-owned eval sink; the coordinator binds its production eval on `attach`
    /// and clears it on `detach`. Drives enumerate/inject/clear.
    @State var bilingualCommander = ReadiumBilingualCommander()
    /// Engine-agnostic block↔translation orchestrator (reused from #56); the PAGED
    /// global `-1` bucket via `updateBlocks(_:)`.
    @State var bilingualOrchestrator = EPUBBilingualOrchestrator()
    /// Per-book bilingual VM (toggle / language / granularity / translation cache /
    /// prefetch). Built once the EPUBParser spine is known.
    @State var bilingualViewModel: BilingualReadingViewModel?
    /// vreader's own EPUB parser, opened alongside the Readium open so the
    /// `EPUBChapterTextProvider` (keyed on OPF-relative spine hrefs) can extract
    /// per-spine source text — Readium does not expose raw spine HTML to app code.
    @State var bilingualParser: EPUBParser?
    /// The OPF-relative spine hrefs the provider keys on, captured at parser open
    /// so the extension can normalize a Readium container-relative href (seam #3).
    @State var bilingualSpineHrefs: [String] = []
    /// First-enable setup-sheet flag (reuses the designed `BilingualSetupSheet` —
    /// rule 51 satisfied).
    @State var showBilingualSetupSheet = false
    /// The setup-sheet's working language/granularity state.
    @State var bilingualSetupState = BilingualSetupSheetState(
        languageKey: BilingualReadingViewModel.defaultTargetLanguage,
        granularity: .paragraph
    )
    /// Chapter-change dedupe + pure decision logic. A reference type so the
    /// `onLocationChange` closure mutates the live instance, not a stale snapshot.
    @State var bilingualChapterTracker = ReadiumBilingualChapterTracker()
    /// Gate-4 HIGH-1: the most recent Readium locator (captured in
    /// `onLocationChange`). The toggle/confirm first-enable reads it so the
    /// enumerate resolves the VISIBLE chapter instead of nil; also the locator for
    /// a prefetch-landed inject that carries none of its own.
    @State var lastKnownReadiumLocator: ReadiumShared.Locator?

    /// WI-7 photo/custom-background compositing: tracks whether a decorative
    /// background image is stored for the current theme. Reloaded on appear and
    /// whenever the theme / custom-background toggle / revision changes (mirrors
    /// `ThemeBackgroundView`'s own reload triggers). Drives both the
    /// `ThemeBackgroundView` composition and the transparent-navigator decision.
    /// Non-`private` so the `+Background` extension's reload helper can write it.
    @State var hasBackgroundImage = false

    var body: some View {
        // WI-7: compose the decorative background BEHIND the navigator, mirroring
        // the legacy `ReaderContainerView` (`ZStack { if useCustomBackground {
        // ThemeBackgroundView }; reader }`). When transparency is active the
        // navigator renders clear-bodied over this layer. The compositing
        // wrapper + reload observers live in `ReadiumEPUBHost+Background` for the
        // 300-line budget; bilingual body modifiers live in `bilingualSurfaces`.
        backgroundComposited(bilingualSurfaces(coreBody))
    }

    @ViewBuilder
    private var coreBody: some View {
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
                        ),
                        // WI-7: clear the HTML body background so the composited
                        // ThemeBackgroundView shows through (photo/custom-bg path).
                        transparentBackground: shouldRenderTransparentBackground
                    ),
                    fingerprintKey: fingerprint.canonicalKey,
                    readerToken: readerToken,
                    initialLocation: restoredLocator,
                    // Med-2: a representable can only return a placeholder
                    // controller synchronously, so a navigator-init throw routes
                    // here to flip the host to `.failed`. `[weak viewModel]`
                    // avoids mutating @State during a render pass.
                    onNavigatorInitFailure: { [weak viewModel] message in
                        viewModel?.markNavigatorInitFailed(message)
                    },
                    // WI-6: forward `locationDidChange` into the VM's debounced
                    // save. `@MainActor @Sendable` so the coordinator stays
                    // decoupled from the VM type.
                    onLocationChange: { [weak viewModel] locator in
                        viewModel?.save(readiumLocator: locator)  // WI-6 save
                        // Gate-4 HIGH-1: remember the live locator so a first-enable
                        // toggle (no location change of its own) resolves the
                        // VISIBLE chapter. Compose — the WI-6 save above still runs.
                        lastKnownReadiumLocator = locator
                        // WI-11b: drive the chapter-change enumerate off the same
                        // callback (href change + enabled → enumerate; intra-chapter
                        // deduped). HIGH-2: a persisted-on book enumerates on its
                        // FIRST locator (lastEnumeratedHref nil → href differs).
                        handleBilingualLocationChange(locator)
                    },
                    // WI-8: the host-owned highlight adapter — bound to the live
                    // navigator in the representable, detached on teardown — so the
                    // adapter the host's coordinator drives is the one on-spine.
                    highlightAdapter: highlightAdapter,
                    navCommander: navCommander,
                    bilingualCommander: bilingualCommander,
                    // WI-7: make the navigator view + spine WebViews transparent
                    // so the ThemeBackgroundView composited behind shows through.
                    transparentBackground: shouldRenderTransparentBackground
                )
                .ignoresSafeArea()
                // WI-9a: the jump observer resolves a (legacy, OPF-relative)
                // vreader `Locator` href against the publication's reading-order.
                .onReceive(NotificationCenter.default.publisher(for: .readerNextPage)) { _ in
                    navCommander.nextPage()
                }
                .onReceive(NotificationCenter.default.publisher(for: .readerPreviousPage)) { _ in
                    navCommander.previousPage()
                }
                .onReceive(NotificationCenter.default.publisher(for: .readerNavigateToLocator)) { notification in
                    guard let vLocator = notification.object as? Locator,
                          let readiumLocator = ReadiumEPUBReaderViewModel.readiumLocator(
                            fromVReader: vLocator,
                            spineHrefs: publication.readingOrder.map(\.href)
                          ) else { return }
                    navCommander.navigate(to: readiumLocator)
                }
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
            // WI-8: build the highlight coordinator over the host-owned adapter
            // so restore-on-open + the `.readerHighlightRemoved` observer route
            // through the shared highlight lifecycle (mirrors the legacy EPUB
            // container). The adapter binds to the navigator separately (in the
            // representable) once `state == .ready`.
            highlightCoordinator = HighlightCoordinator(
                renderer: highlightAdapter,
                persistence: persistence,
                bookFingerprintKey: fingerprint.canonicalKey
            )
            // WI-6: load the saved position BEFORE the navigator mounts (the
            // representable is only built once `state == .ready`) so the
            // navigator opens directly at the restored locator instead of the
            // start. nil → open at the start (first-open / nothing saved).
            restoredLocator = await vm.restoredReadiumLocator()
            // WI-11b Gate-4 round-3 HIGH-1 (persisted-on open race): build the
            // bilingual parser + VM BEFORE `vm.open()` flips `state = .ready` and
            // mounts the navigator, so the navigator's initial `locationDidChange`
            // sees a non-nil VM and a persisted-on book's only initial enumerate
            // isn't dropped. Neither call depends on the Readium publication.
            await openBilingualParser()
            ensureBilingualViewModel()
            await vm.open()
            // WI-8: restore stored highlights once the publication is open. The
            // adapter tracks the set even before the navigator attaches, so the
            // decorations submit as soon as `attach(navigator:)` runs in the
            // representable's `makeUIViewController`. `forHref: nil` — Readium
            // decorations are book-wide; the navigator renders only those whose
            // locators fall on visible spine items.
            await highlightCoordinator?.restoreAll()
        }
        // WI-8: clear a removed highlight's decoration (the cross-format Bug #78
        // visual-clear pipeline `HighlightCoordinator.deleteHighlight` posts).
        // Mirrors the legacy EPUB container's observer.
        .onReceive(NotificationCenter.default.publisher(for: .readerHighlightRemoved)) { notification in
            guard let idString = notification.object as? String,
                  let id = UUID(uuidString: idString) else { return }
            highlightAdapter.remove(id: id)
        }
        // WI-8: re-restore after an annotation import refreshes the set.
        .onReceive(NotificationCenter.default.publisher(for: .readerHighlightsDidImport)) { _ in
            Task { await highlightCoordinator?.restoreAll() }
        }
        .onDisappear {
            // High (bug #252 lesson): host-level close lifecycle. The host owns the
            // VM (+ its `Publication`) via @State, so the close fires only on a
            // genuine nav pop — releasing file handles deterministically. Registry
            // + navigator teardown live in `dismantleUIViewController`.
            // WI-6: `closeAndFlush()` awaits the final position save in a
            // background task (like `EPUBReaderHost`) so it survives the dismiss.
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

#endif
