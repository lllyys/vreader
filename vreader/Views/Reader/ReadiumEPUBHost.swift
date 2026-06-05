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
// compositing layers `ThemeBackgroundView` behind the navigator — wrapper +
// reload observers in `ReadiumEPUBHost+Background`. WI-8 highlight restore +
// create (selection → designed color popover → decoration) lives in
// `ReadiumEPUBHost+Highlights`. Loading + error states reuse the existing
// reader's `ProgressView` + failure message (no new UI chrome — rule 51).
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
    /// WI-10b: shared TTS service (from `ReaderContainerView`), observed by
    /// `+TTSFollow` to auto-advance the navigator. Optional → existing call sites compat.
    var ttsService: TTSService?
    /// Bug #299: the dispatcher's shared chrome-visibility (same source of truth
    /// as the top chrome) — gates the bottom chrome (scrubber + toolbar) this
    /// host mounts in its own `bottomOverlay`. Default `true` keeps existing test
    /// call sites compiling; the live dispatcher always passes its `isChromeVisible`.
    var isChromeVisible: Bool = true

    /// Not `private` — the `+Body` extension's `coreBody`/`openHostTask` read &
    /// write it (a `private` @State is file-scoped, invisible to an extension in
    /// another file).
    @State var viewModel: ReadiumEPUBReaderViewModel?
    /// WI-6: the restored Readium locator, loaded before the navigator mounts so
    /// it can be passed as `initialLocation`. nil = open at the start. Not
    /// `private` for the same `+Body`-extension-access reason as `viewModel`.
    @State var restoredLocator: ReadiumShared.Locator?
    /// WI-8: renders stored highlights as Readium decorations. Owned by the host
    /// (via @State) so the same instance is both attached to the live navigator
    /// (in the representable's `makeUIViewController`) and driven by the host's
    /// `HighlightCoordinator` restore / `.readerHighlightRemoved` observer.
    /// Non-`private` so the `+Highlights` extension reads it (WI-8 new-highlight).
    @State var highlightAdapter = ReadiumDecorationHighlightAdapter()
    /// WI-8: restore-on-open + create/remove plumbing through the shared
    /// highlight lifecycle (renderer = `highlightAdapter`). Built in `.task`
    /// once a `modelContainer` is available. Non-`private` for the `+Highlights`
    /// extension.
    @State var highlightCoordinator: HighlightCoordinator?
    /// WI-9a: host-owned navigation sink. The coordinator binds its nav methods
    /// on `attach`; the host's page-turn / jump observers post into it. Owned here
    /// so the instance survives body recomputation. Non-`private` so the
    /// `+Highlights` create handler can `clearSelection()` (WI-8 new-highlight).
    @State var navCommander = ReadiumNavCommander()
    /// WI-8 (new-highlight): single-entry token→Readium-`Selection` cache that
    /// round-trips a live selection through the designed `SelectionPopoverView`
    /// (the text-quote anchor can't ride a bare `TextSelectionInfo`). Mirrors the
    /// legacy `EPUBSelectionTokenCache`; wiring in `ReadiumEPUBHost+Highlights`.
    @State var readiumSelectionTokenCache = ReadiumSelectionTokenCache<Selection>()

    // MARK: - Bug #303: select → Note (annotation) parity

    // The Readium host had no `.readerAnnotationRequested` observer + no note
    // sheet, so a selection's "Note" action was a no-op (legacy EPUB + TXT/MD
    // mount it; Readium omitted it). Mirrors the legacy `pendingSelectionEvent`
    // round-trip; wiring lives in `ReadiumEPUBHost+Annotations`. Not `private`
    // so that extension can read/write them (`@State` can't live in an extension).

    /// Whether the first-class `AddNoteSheet` (designed surface — rule 51 reuse)
    /// is presented for an in-flight selection→Note request.
    @State var showReadiumNoteSheet = false
    /// The note text bound into `AddNoteSheet`; reset on each present.
    @State var readiumNoteText = ""
    /// The Readium `Selection` resolved from the annotation request token, held
    /// across the sheet's lifetime (the token is consumed on resolve, so the
    /// selection is stashed here — the same shape as legacy `pendingSelectionEvent`).
    @State var pendingReadiumNoteSelection: Selection?

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

    /// Feature #85 WI-1: a CROSS-ENGINE restore position (an engine-neutral
    /// `Locator` from a just-departed legacy scroll host's handoff, or the disk
    /// legacy locator after a scroll session cleared the Readium envelope). It
    /// can't be a pre-mount `initialLocation` because converting its href needs
    /// the publication's reading order, available only post-open — so it is
    /// applied ONCE in the navigator's first `onLocationChange` (the navigator
    /// is attached there, so `navCommander.navigate` is valid). Nil for the
    /// normal same-engine envelope restore.
    @State var pendingCrossEngineRestore: Locator?

    /// WI-7 photo/custom-background compositing: tracks whether a decorative
    /// background image is stored for the current theme. Reloaded on appear and
    /// whenever the theme / custom-background toggle / revision changes (mirrors
    /// `ThemeBackgroundView`'s own reload triggers). Drives both the
    /// `ThemeBackgroundView` composition and the transparent-navigator decision.
    /// Non-`private` so the `+Background` extension's reload helper can write it.
    @State var hasBackgroundImage = false

    // MARK: - WI-10b TTS speaking-position follow (wiring in `+TTSFollow`)

    /// Per-spine offset table (offset→href+fraction); throttle cursor. See `+TTSFollow`.
    @State var ttsFollowMapper: ReadiumTTSFollowMapper?
    @State var lastFollowedTTSTarget: ReadiumTTSFollowMapper.Target?

    // MARK: - Bug #299: bottom-chrome state

    /// Whole-book reading progress (0…1) for the scrubber thumb, updated from
    /// each Readium `locationDidChange` (`+BottomChrome`).
    @State var readingProgress: Double = 0
    /// Bottom-chrome leading label — chapter title / percentage.
    @State var chromeLeadingLabel: String = ""
    /// Bottom-chrome trailing label — section position.
    @State var chromeTrailingLabel: String = ""

    var body: some View {
        // WI-7: compose the decorative background BEHIND the navigator, mirroring
        // the legacy `ReaderContainerView` (`ZStack { if useCustomBackground {
        // ThemeBackgroundView }; reader }`). When transparency is active the
        // navigator renders clear-bodied over this layer. The compositing
        // wrapper + reload observers live in `ReadiumEPUBHost+Background` for the
        // 300-line budget; bilingual body modifiers live in `bilingualSurfaces`.
        //
        // Bug #299: overlay the shared bottom chrome (scrubber + Contents / Notes
        // / Display / AI toolbar) on top, gated on the dispatcher's chrome
        // visibility — restoring parity with every other reader host.
        ZStack {
            backgroundComposited(bilingualSurfaces(coreBody))
            // Gated on ready + chrome-visible + TTS-idle (parity with the other
            // hosts' bottomOverlay — Codex Gate-4 M2).
            if isBottomChromeVisible {
                VStack(spacing: 0) {
                    Spacer()
                    bottomChromeOverlay
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

#endif
