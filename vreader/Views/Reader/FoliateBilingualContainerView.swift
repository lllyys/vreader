// Purpose: Feature #56 WI-11 — host wrapper for the AZW3/MOBI
// bilingual interlinear renderer. Wraps `FoliateSpikeView` (the
// live AZW3/MOBI host) with the bilingual VM, orchestrator,
// first-enable setup sheet, and the notification observers that
// drive the enumerate / inject / clear pipeline.
//
// Sits in `ReaderContainerView`'s `.foliateWeb` dispatch branch so
// the spike itself stays unchanged for non-bilingual paths (no
// runtime overhead beyond an idle observer for AZW3/MOBI books
// the user never enables bilingual on).
//
// Pipeline (mirror of `EPUBReaderContainerView+Bilingual`):
//
//   1. `.readerMoreBilingual` → toggle the VM. First enable raises
//      `BilingualSetupSheet`; confirm posts an enumerate.
//      Subsequent flips skip the sheet.
//   2. `.readerRelocate` (or `section-load`) → if bilingual on
//      and not in the setup sheet, post the enumerate JS via
//      `.foliateRequestBilingualEvalJS`. The spike's coordinator
//      runs it; the resulting `bilingualEnumerate` message goes
//      back through `.foliateBilingualBlocksEnumerated`.
//   3. `.foliateBilingualBlocksEnumerated` → cache blocks on the
//      orchestrator, ask the VM to prefetch translations for the
//      current unit.
//   4. `.readerBilingualDidChange` → prefetch landed; build the
//      inject JS and post it.
//
// Key decisions:
// - **No new SwiftData / network deps in this file.** The wrapper
//   owns view-layer state; data flow goes through the existing
//   `BilingualReadingViewModel` + `ChapterTranslationPrefetcher`
//   the EPUB renderer already uses.
// - **`FoliateSectionExtracting` comes from the live Coordinator.**
//   Captured via the `FoliateCoordinatorBox` the spike fills in
//   from `makeCoordinator()`. The `FoliateChapterTextProvider`
//   actor is constructed once the coordinator is non-nil + the
//   book is ready.
// - **Setup sheet is the same `BilingualSetupSheet`.** UI parity
//   with the EPUB renderer — rule 51 is satisfied because the
//   sheet is already a designed surface (rendered by WI-9).
//
// @coordinates-with: FoliateSpikeView.swift,
//   FoliateBilingualOrchestrator.swift, FoliateBilingualJS.swift,
//   FoliateChapterTextProvider.swift, FoliateSectionExtracting.swift,
//   ChapterTranslationPrefetcher.swift, BilingualSetupSheet.swift,
//   ReaderNotifications.swift,
//   EPUBReaderContainerView+Bilingual.swift (sibling EPUB host),
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-11)

#if canImport(UIKit)
import SwiftUI
import SwiftData

/// AZW3/MOBI host wrapper that adds bilingual interlinear rendering
/// to `FoliateSpikeView`. Owns the VM + orchestrator + setup sheet
/// state.
struct FoliateBilingualContainerView: View {

    let bookURL: URL
    let fingerprintKey: String
    let readerToken: UUID?
    let settingsStore: ReaderSettingsStore?
    let coordinatorBox: FoliateCoordinatorBox?
    /// Bug #260: TTS state, threaded from `engineReaderView`. The
    /// bottom chrome hides while TTS is active so it does not stack
    /// over `ReaderContainerView`'s `TTSControlBar` (the same gate the
    /// EPUB / TXT / PDF / MD containers apply to their own bottom
    /// overlays). Optional → preview / test call sites stay
    /// source-compatible.
    var ttsService: TTSService?

    // Bug #265: `internal` (not `private`) so the `+Position` extension file
    // can build the PersistenceActor from the SwiftData container.
    @Environment(\.modelContext) var modelContext

    // MARK: - Bottom chrome state (Bug #260)

    /// Bug #260: mirrors the shared chrome-visibility toggle. The live
    /// AZW3/MOBI spike posts `.readerContentTapped` on a center tap;
    /// `ReaderContainerView` toggles the *top* chrome on it, and this
    /// container toggles the *bottom* chrome in lockstep — the same
    /// per-container pattern the four native containers use (each owns
    /// its own `isChromeVisible`). Defaults visible so the bar shows on
    /// first open, matching the native containers.
    @State private var isChromeVisible = true

    /// Bug #260: reading progress (0...1) for the bottom-chrome
    /// scrubber, fed from the Foliate relocate `fraction`. Two-way so
    /// the thumb tracks page turns as well as drags.
    // Bug #260: `internal` (not `private`) so the `+BottomChrome`
    // extension file can read/write — the container body is already
    // past the ~300-line guideline, so the bottom-chrome view + update
    // logic live in that extension file.
    @State var readingProgress: Double = 0

    /// Bug #260: the bottom-chrome leading label — the current chapter
    /// title (relocate `tocLabel`) when present, else a percentage.
    @State var chromeLeadingLabel: String = ""

    /// Bug #260: the bottom-chrome trailing label — the section
    /// position ("Chapter X of Y") derived from relocate
    /// `sectionIndex` / `sectionTotal`.
    @State var chromeTrailingLabel: String = ""

    // MARK: - Bilingual state

    @State private var bilingualViewModel: BilingualReadingViewModel?
    @State private var bilingualOrchestrator = FoliateBilingualOrchestrator()
    @State private var showBilingualSetupSheet: Bool = false
    @State private var bilingualSetupState: BilingualSetupSheetState = .defaultValue

    /// The active locator's section href — captured from the Foliate
    /// relocate notification. Used to resolve the current unit for
    /// prefetch + inject. We track the section index (stringified)
    /// since `TranslationUnitID.Kind.foliateHref` carries the
    /// integer-string id the JS host exposes.
    @State private var currentSectionHref: String?

    /// The Foliate section index of the current page. Updated on
    /// every relocate (Gate-4 audit H1) so a page turn
    /// within an already-loaded section keeps the current unit in
    /// sync. Drives the `targetSectionIndex` argument on the
    /// orchestrator's enumerate / inject / clear JS so a unit's
    /// translations never bleed into adjacent loaded sections.
    @State private var currentSectionIndex: Int?

    // MARK: - Reading-position persistence (Bug #265)

    /// Bug #265: owns cross-session position save/restore for the live
    /// AZW3/MOBI path (the wiring previously lived only in dead
    /// `FoliateReaderHost`). Built lazily from the SwiftData container on
    /// first need. Handler logic lives in
    /// `FoliateBilingualContainerView+Position.swift`.
    @State var positionController: FoliatePositionRestoreController?

    /// Bug #265: ensures restore (load saved position → seek) runs once per
    /// open, on the first `.foliateRelocated`.
    @State var didStartPositionRestore = false

    /// Bug #265: the in-flight restore task, cancelled on teardown so a
    /// fast dismiss→reopen of the same book can't have a stale task post a
    /// seek into the new reader instance (Codex Gate-4).
    @State var positionRestoreTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            spikeWithBilingualWiring

            // Bug #260: the shared bottom chrome (scrubber + labels +
            // Contents / Notes / Display / AI toolbar) — previously
            // never mounted for AZW3/MOBI. Gated on chrome visibility
            // and TTS-idle so it hides on a chrome-toggle tap and never
            // stacks over the TTS control bar (parity with the four
            // native containers' bottom-overlay gate). The toolbar
            // buttons post `.readerOpen*` notifications that
            // `ReaderContainerView` already observes — no closure
            // plumbing is needed here.
            if isChromeVisible, (ttsService?.state ?? .idle) == .idle {
                VStack(spacing: 0) {
                    Spacer()
                    bottomChromeOverlay
                }
            }
        }
        // Bug #260: mirror the chrome toggle. The spike posts
        // `.readerContentTapped` on a center tap; toggling here keeps
        // the bottom bar in lockstep with the top chrome.
        .onReceive(
            NotificationCenter.default.publisher(for: .readerContentTapped)
        ) { _ in isChromeVisible.toggle() }
        // Feature #77 — DebugBridge bilingual-driver observer (enable/disable/
        // status CU-free for the Foliate AZW3/MOBI loading-shimmer verification).
        // Attached at the short `body` level (not the near-budget spike chain).
        #if DEBUG
        .modifier(debugBilingualObserver)
        #endif
    }

    /// The live AZW3/MOBI spike plus the bilingual enumerate / inject /
    /// clear wiring. Extracted from `body` so the Bug #260 bottom-chrome
    /// overlay can compose over it in a `ZStack` without ballooning the
    /// `body` expression past the Swift type-checker's complexity ceiling.
    private var spikeWithBilingualWiring: some View {
        FoliateSpikeView(
            bookURL: bookURL,
            fingerprintKey: fingerprintKey,
            readerToken: readerToken,
            settingsStore: settingsStore,
            coordinatorBox: coordinatorBox
        )
        .onReceive(
            NotificationCenter.default.publisher(for: .readerMoreBilingual)
        ) { _ in handleMoreBilingualToggle() }
        .onReceive(
            NotificationCenter.default.publisher(for: .readerBilingualDidChange)
        ) { notification in
            let key = notification.userInfo?["fingerprintKey"] as? String
            guard key == fingerprintKey else { return }
            handleBilingualDidChange()
        }
        // Feature #77 WI-3: the prefetch-state bus drives the inline loading
        // shimmer for AZW3/MOBI — show it while the current section's unit is
        // fetching, remove it on a failed/cancelled prefetch (a landed one is
        // replaced in place by the inject above).
        .onReceive(
            NotificationCenter.default.publisher(for: .readerBilingualPrefetchDidChange)
        ) { notification in
            let key = notification.userInfo?["fingerprintKey"] as? String
            guard key == fingerprintKey else { return }
            let inFlight = notification.userInfo?["inFlightUnits"]
                as? Set<TranslationUnitID> ?? []
            handleBilingualPrefetchChange(inFlightUnits: inFlight)
        }
        // Feature #56 WI-15: a re-translate result for this book —
        // refresh the VM's in-memory cache so the open chapter re-renders.
        .onReceive(
            NotificationCenter.default.publisher(for: .readerBilingualReTranslateApplied)
        ) { notification in
            guard let info = notification.userInfo,
                  info["fingerprintKey"] as? String == fingerprintKey,
                  let unit = info["unit"] as? TranslationUnitID,
                  let segments = info["segments"] as? [String]
            else { return }
            bilingualViewModel?.applyReTranslateResult(segments, for: unit)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .foliateBilingualBlocksEnumerated)
        ) { notification in
            let key = notification.userInfo?["fingerprintKey"] as? String
            guard key == fingerprintKey else { return }
            let blocks = (notification.userInfo?["blocks"] as? [BilingualBlock]) ?? []
            // Gate-4 round-3 audit fix:
            // `requestedSectionIndex` is present when the enumerate
            // was scoped to one section. An empty blocks list for a
            // scoped request signals "previously-populated section
            // re-enumerated empty" — the container must clear that
            // section's cache.
            let requestedSection = notification.userInfo?["requestedSectionIndex"] as? Int
            handleEnumeratedBlocks(blocks, requestedSection: requestedSection)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .foliateSectionLoaded)
        ) { notification in
            guard let key = notification.userInfo?["fingerprintKey"] as? String,
                  key == fingerprintKey else { return }
            // Feature #56 WI-14: publish the Foliate text provider on
            // section-load so the Book Details "Translate entire book…"
            // entry point becomes reachable on normal book open (not
            // only after the user toggles bilingual mode). Codex Gate-4
            // round-2 H2 fix. Idempotent — host caches by fingerprintKey.
            publishTranslateBookTextProviderIfReady()
            // Bug #305 / GH #1360: build the bilingual VM on OPEN (not only
            // on the first toggle) so a book whose persisted state is
            // `isEnabled == true` posts `.readerBilingualDidChange` to the
            // parent — otherwise the More menu shows Bilingual OFF + hides
            // "Re-translate chapter" on reopen. Safe on open: a persistence-
            // loaded VM has `needsSetupSheet == false`, so no setup sheet is
            // raised. Foliate analogue of the TXT-only Bug #245 fix.
            ensureBilingualViewModel()
            handleSectionLoaded(notification.userInfo)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .foliateRelocated)
        ) { notification in
            guard let key = notification.userInfo?["fingerprintKey"] as? String,
                  key == fingerprintKey else { return }
            handleRelocated(notification.userInfo)
        }
        // Bug #262 / GH #1136: the live AZW3/MOBI Contents source. The spike
        // forwards the parsed `book-ready` TOC here; we convert the tree to
        // flat `[TOCEntry]` and relay it up to `ReaderContainerView` so the
        // bottom-chrome Contents button (Bug #260) lists chapters. The
        // file-based `ReaderTOCFactory.buildTOC` has no Foliate parser, so
        // this live event is the only AZW3/MOBI TOC source.
        .onReceive(
            NotificationCenter.default.publisher(for: .foliateBookReadyTOC)
        ) { notification in
            guard let key = notification.userInfo?["fingerprintKey"] as? String,
                  key == fingerprintKey,
                  let items = notification.userInfo?["toc"] as? [FoliateTOCItem],
                  !items.isEmpty,
                  let fingerprint = DocumentFingerprint(canonicalKey: fingerprintKey)
            else { return }
            let entries = FoliateTOCConverter.convert(items, fingerprint: fingerprint)
            guard !entries.isEmpty else { return }
            NotificationCenter.default.post(
                name: .foliateTOCAvailable,
                object: nil,
                userInfo: [
                    "entries": entries,
                    "fingerprintKey": fingerprintKey,
                ]
            )
        }
        // Bug #262 / GH #1136: relay a shared TOC / Notes / Highlight row tap
        // into AZW3/MOBI content navigation. The shared sheets post
        // `.readerNavigateToLocator` (object: Locator); we resolve the
        // Foliate-js navigation target (CFI preferred, else the EPUB-style
        // href TOC entries carry) and forward it on the dedicated
        // `.foliateRequestSeekTarget` channel the spike coordinator observes.
        .onReceive(
            NotificationCenter.default.publisher(for: .readerNavigateToLocator)
        ) { notification in
            guard let locator = notification.object as? Locator,
                  let target = FoliateNavSeek.navigationTarget(for: locator)
            else { return }
            NotificationCenter.default.post(
                name: .foliateRequestSeekTarget,
                object: nil,
                userInfo: [
                    "target": target,
                    "fingerprintKey": fingerprintKey,
                ]
            )
        }
        // Bug #239 — paged-mode side-tap → page-turn for AZW3/MOBI.
        // `ReaderTapZoneRouter` (fed by the foliate-host.js content-tap
        // handler in `FoliateSpikeView`) posts `.readerNextPage` /
        // `.readerPreviousPage`. The spike's coordinator observes those
        // notifications directly and evaluates `readerAPI.next()` /
        // `readerAPI.prev()` against the live `WKWebView` (scoped by
        // `fingerprintKey` so a second open reader can't steal the call).
        // Observers live on the coordinator — no extra wiring is needed
        // here in the container.
        .sheet(isPresented: $showBilingualSetupSheet) {
            BilingualSetupSheetContainer(
                theme: settingsStore?.theme ?? .paper,
                state: $bilingualSetupState,
                engineDescriptor: BilingualEngineDescriptor(
                    configured: bilingualViewModel?.aiConfigured ?? false,
                    providerName: nil,
                    subtitle: nil
                ),
                onConfirm: { confirmBilingualSetup() },
                onCancel: { cancelBilingualSetup() },
                // Feature #81: "Set up" / "Change…" pushes the scoped AI
                // Providers list (handled inside the container); on configure
                // it refreshes this strip + pops back.
                onConfigured: { await bilingualViewModel?.refreshAIConfigured() }
            )
            // Bug #301: re-resolve live AI readiness each time the sheet
            // appears, so the engine strip is truthful even if AI settings
            // changed after the reader VM was first built (audit-Medium).
            .task { await bilingualViewModel?.refreshAIConfigured() }
        }
        // Bug #265: persist the live reading position. The spike posts
        // `.readerPositionDidChange` (object: Locator) on every relocate; the
        // controller gates out the pre-restore open→start relocate and saves
        // the rest (filtered to this book). Handler in `+Position.swift`.
        .onReceive(
            NotificationCenter.default.publisher(for: .readerPositionDidChange)
        ) { notification in
            handlePositionDidChange(notification)
        }
        // Bug #267: DEBUG-only — forward a harness seek-fraction command to the
        // spike's key-filtered `.foliateRequestSeekFraction` observer. Both the
        // call site and the modifier are `#if DEBUG`-gated so no symbol leaks
        // into Release (rule 50 §11; Bug #254 lesson).
        #if DEBUG
        .modifier(FoliateDebugSeekFractionObserver(fingerprintKey: fingerprintKey))
        #endif
        // Bug #265: build the persistence controller eagerly so a fast
        // close-before-relocate can still flush, and so restore is ready.
        .task { ensurePositionController() }
        // Bug #265: flush the last position on teardown (close to library /
        // relaunch) in case the debounce window hasn't elapsed, and cancel any
        // in-flight restore task so it can't seek a re-opened reader instance.
        .onDisappear {
            positionRestoreTask?.cancel()
            let controller = positionController
            Task { await controller?.flush() }
        }
    }

    // MARK: - VM lifecycle

    /// Lazily constructs the bilingual VM + prefetcher once the
    /// Foliate coordinator is available. Idempotent — already-built
    /// VM is preserved on subsequent calls.
    private func ensureBilingualViewModel() {
        guard bilingualViewModel == nil else { return }
        guard let extractor = coordinatorBox?.coordinator else { return }
        let textProvider = FoliateChapterTextProvider(extractor: extractor)
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: fingerprintKey,
            perBookBaseURL: ReaderContainerView.perBookSettingsBaseURL
        )
        vm.attachProvider(textProvider)
        vm.attachPrefetcher(
            EPUBReaderContainerView.makePrefetcher(
                bookFingerprintKey: fingerprintKey,
                textProvider: textProvider
            )
        )
        bilingualViewModel = vm
        // Bug #301: resolve the LIVE AI-readiness so the setup-sheet
        // engineDescriptor (`configured`) is truthful, not hardcoded.
        Task { await vm.refreshAIConfigured() }
        if vm.needsSetupSheet {
            showBilingualSetupSheet = true
            bilingualSetupState = BilingualSetupSheetState(
                languageKey: vm.targetLanguage,
                granularity: vm.granularity
            )
        }
        // Bug #305 / GH #1360: mirror the loaded-from-persistence bilingual
        // state to the parent `ReaderContainerView` — `.readerBilingualDidChange`
        // is what the parent observes to repaint the chrome pill + the More-menu
        // "Bilingual" / "Re-translate chapter" rows. Without this the parent
        // stays at the default `bilingualActive = false` on reopen even when the
        // book was previously bilingual. Mirrors the TXT #245 fix.
        vm.postDidChange()
    }

    /// Feature #56 WI-14: publishes the Foliate chapter-text provider
    /// to the parent `ReaderContainerView` so the Book Details
    /// translate-entire-book entry point can consume it. The Foliate
    /// publish path needs to fire on normal book open (not only when
    /// the user toggles bilingual mode), so this is invoked from the
    /// `.foliateSectionLoaded` observer above. Idempotent — the host
    /// caches by `fingerprintKey`, so repeating the post on every
    /// section-load is cheap (Codex Gate-4 round-2 H2).
    private func publishTranslateBookTextProviderIfReady() {
        guard let extractor = coordinatorBox?.coordinator else { return }
        let textProvider = FoliateChapterTextProvider(extractor: extractor)
        NotificationCenter.default.post(
            name: .readerBookTranslationTextProviderAvailable,
            object: textProvider,
            userInfo: ["fingerprintKey": fingerprintKey])
    }

    // MARK: - Event handlers

    /// Toggle bilingual mode. First enable raises the setup sheet
    /// (sheet's confirm runs an enumerate against the freshest
    /// language). Subsequent enables push enumerate immediately.
    private func handleMoreBilingualToggle() {
        ensureBilingualViewModel()
        guard let vm = bilingualViewModel else { return }
        let nextEnabled = !vm.isEnabled
        vm.setEnabled(nextEnabled)
        if !nextEnabled {
            evalBilingualJS(bilingualOrchestrator.clearJS())
            return
        }
        if vm.needsSetupSheet {
            bilingualSetupState = BilingualSetupSheetState(
                languageKey: vm.targetLanguage,
                granularity: vm.granularity
            )
            showBilingualSetupSheet = true
        } else {
            evalBilingualJS(
                bilingualOrchestrator.enumerateJS(
                    sectionIndex: currentSectionIndex)
            )
        }
    }

    /// VM prefetch landed — build inject JS and push it through
    /// the eval observer.
    private func handleBilingualDidChange() {
        guard let vm = bilingualViewModel else { return }
        if !vm.isEnabled {
            evalBilingualJS(bilingualOrchestrator.clearJS())
            return
        }
        injectIfCached()
    }

    /// Parsed `[BilingualBlock]` from the JS enumerate channel —
    /// partition by section index and store each section's blocks
    /// in the orchestrator's per-section cache. Gate-4 round-2
    /// audit fix: per-section storage means an adjacent preloaded
    /// section (paginated mode) cannot clobber the active section's
    /// block list. Only the active section drives the prefetch
    /// trigger.
    ///
    /// Gate-4 round-3 audit fix:
    /// `requestedSection` is non-nil when the JS enumerate was
    /// scoped. An empty `blocks` for a scoped request means the
    /// section re-enumerated empty (re-render, transient failure);
    /// the matching per-section cache is cleared to avoid stale
    /// bid leaks. An empty payload from an unscoped request (no
    /// `requestedSection`) drops silently — we don't know which
    /// section to clear.
    private func handleEnumeratedBlocks(
        _ blocks: [BilingualBlock],
        requestedSection: Int? = nil
    ) {
        if blocks.isEmpty {
            if let section = requestedSection {
                // Round-3 fix: the JS enumerated this specific
                // section and found no blocks. Clear any stale
                // cache so a later inject for that section cannot
                // resolve old bids.
                bilingualOrchestrator.clearBlocks(forSection: section)
            }
            return
        }
        // Partition the parsed payload by section. Untagged blocks
        // (older bundle / EPUB-style payload) bucket under `-1`.
        let byIndex = Dictionary(grouping: blocks, by: { $0.sectionIndex ?? -1 })
        for (sectionIndex, sectionBlocks) in byIndex {
            bilingualOrchestrator.updateBlocks(
                sectionBlocks, forSection: sectionIndex)
        }
        // Round-3 fix: a scoped enumerate may also need to drop
        // an OLD section's cache. If the JS host walked one section
        // and returned blocks tagged with a different index, the
        // requested section was empty even though the response
        // wasn't empty overall. This case is unusual but defensive.
        if let section = requestedSection,
           byIndex[section] == nil {
            bilingualOrchestrator.clearBlocks(forSection: section)
        }
        guard let vm = bilingualViewModel, vm.isEnabled else { return }
        guard let locator = makeCurrentLocator() else { return }
        Task { await vm.handlePositionChange(locator) }
        // If translations are already cached for the resolved unit,
        // inject immediately; otherwise the prefetch landing will
        // fire `.readerBilingualDidChange` and we inject then.
        injectIfCached()
    }

    /// Foliate section-load — a (possibly off-screen, preloaded)
    /// section's DOM has just been rendered. Gate-4 round-2 audit
    /// fix: this handler must NOT mutate the
    /// canonical current-section state. In paginated mode, foliate-js
    /// can fire section-load for an adjacent preloaded section
    /// *before* the user relocates there; only `.foliateRelocated`
    /// owns the "I'm on section N now" transition.
    ///
    /// What this handler does do is push an enumerate scoped to the
    /// loaded section so the orchestrator's per-section block cache
    /// gets populated for that section. When the user eventually
    /// relocates to it, the inject path has the blocks ready.
    private func handleSectionLoaded(_ userInfo: [AnyHashable: Any]?) {
        guard let loadedIndex = userInfo?["sectionIndex"] as? Int else {
            return
        }
        guard let vm = bilingualViewModel, vm.isEnabled,
              !showBilingualSetupSheet else { return }
        evalBilingualJS(
            bilingualOrchestrator.enumerateJS(
                sectionIndex: loadedIndex)
        )
    }

    /// Foliate relocate — fires for every position change including
    /// page turns that stay within an already-loaded section. Gate-4
    /// audit H1: update the current-section tracking here so a page
    /// turn into an already-loaded next section refreshes the
    /// prefetch / inject target. When the index actually changes,
    /// also push a scoped enumerate of the now-current section so
    /// the orchestrator's block cache reflects the live DOM.
    ///
    /// Gate-4 round-2 audit fix: this is the
    /// SOLE owner of the canonical current-section state. The
    /// `section-load` handler does NOT mutate it, because foliate-js
    /// can fire `section-load` for an adjacent preloaded section
    /// before the user relocates there.
    ///
    /// Note: we do NOT clear the just-left section's block cache.
    /// In paginated mode the user often returns to recently-visited
    /// sections (back-paging), and keeping the cache avoids a
    /// re-enumerate round-trip. The orchestrator's per-section
    /// cache only grows by section-load count, which is bounded by
    /// the book length, so this is not a leak hazard.
    private func handleRelocated(_ userInfo: [AnyHashable: Any]?) {
        // Bug #265: the FIRST relocate is the right restore trigger — it fires
        // for EVERY book (TOC or not) and only AFTER `readerAPI.init({})` has
        // rendered + navigated, so a restore `goTo` actually takes (book-ready
        // fires before init, and `.foliateBookReadyTOC` is suppressed for
        // TOC-less books — neither is a safe seek signal). Guarded once.
        triggerPositionRestoreIfNeeded()

        // Bug #260: update the bottom-chrome scrubber + labels from the
        // relocate payload. Runs regardless of bilingual state (the
        // bottom bar shows for every AZW3/MOBI book), so it precedes the
        // bilingual-only guard below.
        updateBottomChrome(from: userInfo)

        guard let nextIndex = userInfo?["sectionIndex"] as? Int else {
            return
        }
        let previousIndex = currentSectionIndex
        currentSectionHref = String(nextIndex)
        currentSectionIndex = nextIndex

        guard let vm = bilingualViewModel, vm.isEnabled,
              !showBilingualSetupSheet else { return }

        // The current rendered section's block list lives on the
        // orchestrator already (a section-load fires before its
        // relocate). What we need on a within-loaded-section page
        // turn is to (a) ask the VM to prefetch the (possibly new)
        // current unit + its next, and (b) push an inject scoped to
        // the new section if translations are cached.
        if previousIndex != nextIndex {
            // Feature #77: clear any stale LOADING shimmer on the section we just
            // LEFT — a prefetch that was in flight there may land or fail
            // off-current, and the prefetch-change handler below only targets the
            // NEW current section. Unlike Readium's single-spine eval channel,
            // Foliate can target the left section directly, so the stale shimmer
            // never lingers. (A landed translation is unaffected — clearLoading is
            // loading-only.) On return, `injectIfCached` re-injects a cached
            // translation or the prefetch re-triggers a fresh shimmer.
            if let prev = previousIndex {
                evalBilingualJS(bilingualOrchestrator.clearLoadingJS(sectionIndex: prev))
            }
            // The user moved into a new (already-loaded) section.
            // Refresh enumerate so the block list reflects the new
            // section's DOM — section-load may not fire when
            // foliate-js had the section preloaded in paginated
            // mode.
            evalBilingualJS(
                bilingualOrchestrator.enumerateJS(
                    sectionIndex: nextIndex)
            )
        }
        injectIfCached()
    }

    /// Build inject JS for the current unit's translations (if any
    /// are cached) and push it through the eval observer. No-op when
    /// the orchestrator has no blocks or the VM has no translations
    /// for the current unit. Gate-4 audit H2: scopes
    /// to the current section index so an adjacent loaded section
    /// (paginated mode) does not get this unit's translations.
    private func injectIfCached() {
        guard let vm = bilingualViewModel, vm.isEnabled else { return }
        guard let locator = makeCurrentLocator() else { return }
        let scopedIndex = currentSectionIndex
        Task { @MainActor in
            guard let provider = vm.textProvider,
                  let unit = await provider.unit(containing: locator),
                  let segments = vm.translations(for: unit) else { return }
            if let js = bilingualOrchestrator.buildInjectJS(
                translatedSegments: segments,
                sectionIndex: scopedIndex
            ) {
                evalBilingualJS(js)
            } else {
                // Bug #334 (Codex audit): translations exist for this unit but the
                // pairing produced no inject map — i.e. a residual block/segment
                // count mismatch from any future cause. Fail safe to source-only by
                // clearing this section's loading shimmer so it can NEVER get stuck
                // (the original #334 symptom). The shared leaf-block selector makes
                // the mismatch unreachable today; this is the belt-and-suspenders.
                evalBilingualJS(
                    bilingualOrchestrator.clearLoadingJS(sectionIndex: scopedIndex))
            }
        }
    }

    /// Feature #77 WI-3: `.readerBilingualPrefetchDidChange` handler — show or
    /// remove the inline LOADING shimmer for the current section as the in-flight
    /// unit set changes (the FULL set is carried in the notification). When the
    /// current section's unit is fetching, inject a shimmer after each
    /// still-untranslated block of that section (`bilingualInjectLoading` skips
    /// already-decorated blocks, so it never downgrades a landed row). When the
    /// unit leaves the set, the translation arrives via `.readerBilingualDidChange`
    /// and the inject replaces the shimmer IN PLACE — so a landed unit must NOT be
    /// cleared here; only a failed / cancelled prefetch (no cached translation)
    /// has its leftover shimmer removed. A shimmer on a section the user has since
    /// left is cleared by `handleRelocated`.
    private func handleBilingualPrefetchChange(inFlightUnits: Set<TranslationUnitID>) {
        guard let vm = bilingualViewModel, vm.isEnabled else { return }
        Task { @MainActor in
            // Resolve against LIVE state (not state captured before the task), and
            // re-check the section after the unit-resolve await — a relocate during
            // the await would otherwise let this task inject a shimmer back into a
            // just-left section that `handleRelocated` already cleared (Gate-4
            // Medium). The section-stability guard makes the work owner-scoped.
            let scopedIndex = currentSectionIndex
            guard let locator = makeCurrentLocator(),
                  let provider = vm.textProvider,
                  let unit = await provider.unit(containing: locator) else { return }
            guard currentSectionIndex == scopedIndex else { return }
            if inFlightUnits.contains(unit) {
                if let js = bilingualOrchestrator.buildLoadingJS(sectionIndex: scopedIndex) {
                    evalBilingualJS(js)
                }
            } else if vm.translations(for: unit) == nil {
                evalBilingualJS(
                    bilingualOrchestrator.clearLoadingJS(sectionIndex: scopedIndex))
            }
        }
    }

    /// Confirm path for the first-enable setup sheet. Commits the
    /// chosen language + granularity to the VM and runs the first
    /// enumerate against the user's choice.
    private func confirmBilingualSetup() {
        guard let vm = bilingualViewModel else { return }
        vm.setTargetLanguage(bilingualSetupState.languageKey)
        vm.setGranularity(bilingualSetupState.granularity)
        vm.dismissSetupSheet()
        showBilingualSetupSheet = false
        evalBilingualJS(
            bilingualOrchestrator.enumerateJS(
                sectionIndex: currentSectionIndex)
        )
    }

    /// Cancel path — dismiss the sheet and turn bilingual back off
    /// without persisting changes.
    private func cancelBilingualSetup() {
        guard let vm = bilingualViewModel else { return }
        vm.dismissSetupSheet()
        vm.setEnabled(false)
        showBilingualSetupSheet = false
    }

    #if DEBUG
    // MARK: - Feature #77 DebugBridge harness (bilingual?action=…)

    /// Enable bilingual CU-free on the Foliate (AZW3/MOBI) engine, BYPASSING the
    /// setup sheet, then enumerate the current section (the prefetch that drives
    /// the loading shimmer in `foliate-host.js`).
    func handleDebugBilingualEnable(lang: String?, granularity: String?) {
        ensureBilingualViewModel()
        guard let vm = bilingualViewModel else { return }
        if let lang { vm.setTargetLanguage(lang) }
        if let granularity, let g = TranslationGranularity(rawValue: granularity) {
            vm.setGranularity(g)
        }
        vm.dismissSetupSheet()
        showBilingualSetupSheet = false
        vm.setEnabled(true)
        evalBilingualJS(
            bilingualOrchestrator.enumerateJS(sectionIndex: currentSectionIndex)
        )
    }

    func handleDebugBilingualDisable() {
        guard let vm = bilingualViewModel else { return }
        vm.setEnabled(false)
        evalBilingualJS(bilingualOrchestrator.clearJS())
    }

    func handleDebugBilingualStatus(dest: String) {
        DebugBridgeBilingualStatus.write(dest: dest, engine: "foliate", vm: bilingualViewModel)
    }

    /// The DebugBridge bilingual-driver observer, factored out of the body chain
    /// to keep SwiftUI's per-node type-inference within budget.
    var debugBilingualObserver: ReaderDebugBridgeBilingualObserver {
        ReaderDebugBridgeBilingualObserver(
            onEnable: { lang, gran in handleDebugBilingualEnable(lang: lang, granularity: gran) },
            onDisable: { handleDebugBilingualDisable() },
            onStatus: { dest in handleDebugBilingualStatus(dest: dest) }
        )
    }
    #endif

    // MARK: - Helpers

    /// Build a `Locator` for the current Foliate render position.
    /// Foliate provides the section's href via the relocate event;
    /// we shoulder no canonical-fingerprint validation here — the
    /// bilingual VM only reads `.href` for unit resolution.
    private func makeCurrentLocator() -> Locator? {
        guard let fp = DocumentFingerprint(canonicalKey: fingerprintKey) else {
            return nil
        }
        return Locator(
            bookFingerprint: fp,
            href: currentSectionHref,
            progression: nil,
            totalProgression: nil,
            cfi: nil,
            page: nil,
            charOffsetUTF16: nil,
            charRangeStartUTF16: nil,
            charRangeEndUTF16: nil,
            textQuote: nil,
            textContextBefore: nil,
            textContextAfter: nil
        )
    }

    /// Post a `.foliateRequestBilingualEvalJS` notification with the
    /// given JS payload. The spike's Coordinator observer picks it
    /// up and evaluates against the live `WKWebView`.
    private func evalBilingualJS(_ js: String) {
        NotificationCenter.default.post(
            name: .foliateRequestBilingualEvalJS,
            object: nil,
            userInfo: [
                "js": js,
                "fingerprintKey": fingerprintKey,
            ]
        )
    }
}

#endif
