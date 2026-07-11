---
title: Architecture — reader dispatch and format hosts
updated: 2026-07-10
status: verified
---

# Architecture — reader dispatch and format hosts

## Purpose

Explains how an opened library book reaches the right rendering engine: `ReaderContainerView` is the single dispatcher that parses the book's fingerprint, selects an engine via `ReaderEngine`, mounts the matching format host, and layers the shared format-agnostic chrome (top bar, More popover, sheets, TTS bar, DebugBridge probe) on top.

## Key files and types

- `vreader/Views/Reader/ReaderContainerView.swift` (1366 lines) — `struct ReaderContainerView: View { let book: LibraryBookItem }`. Its `body` guards on `DocumentFingerprint(canonicalKey: book.fingerprintKey)`; an unparseable key renders `fingerprintErrorView` ("Unable to open this book.", accessibility id `fingerprintErrorView`). `unsupportedFormatView(format:)` is retained for future surfaces and pinned by `vreaderTests/Views/Reader/ReaderContainerViewEngineDispatchTests.swift`.
- `vreader/Models/ReaderEngine.swift` — `enum ReaderEngine: String, Sendable, Hashable, CaseIterable` with six cases: `textNative`, `markdownNative`, `epubWKWebView`, `epubReadium`, `foliateWeb`, `pdfKit`. `static func resolve(format: BookFormat) -> ReaderEngine` is pure and total: `.txt→.textNative, .md→.markdownNative, .epub→.epubWKWebView` (unconditional), `.azw3→.foliateWeb, .pdf→.pdfKit`. Feature #54 replaced the user-visible ReadingMode (Native/Unified) toggle; the engine is derived per open and never persisted.
- `static func routeEPUB(readiumFlagEnabled:layout:) -> ReaderEngine` — the flag-aware EPUB branch, kept pure (the dispatcher passes `FeatureFlags.shared.isEnabled(.readiumEPUBEngine)` + `settingsStore.epubLayout`). Flag OFF → `.epubWKWebView`; flag ON → scroll → `.epubWKWebView` (the legacy engine's feature-#71 continuous-scroll stitch — feature #85 approach C, because Readium's per-resource paginator has an inherent chapter-boundary seam in scroll), paged → `.epubReadium`. `readiumEPUBEngine` is a persisted flag (`vreader/Services/FeatureFlags.swift`), default ON since the feature #42 WI-14 G2 flip (2026-06-01).
- `vreader/Views/Reader/ReaderFormatHosts.swift` (264 lines) — `TXTReaderHost`, `PDFReaderHost`, `MDReaderHost`, `EPUBReaderHost`, `FoliateReaderHost`. Each owns its ViewModel via `@State`, builds `PersistenceActor(modelContainer:)` + `ReadingSessionTracker(clock: SystemClock(), store: SwiftDataSessionStore(...), deviceId: ReaderContainerView.deviceId)` in `.task`, and shows a `ProgressView` until ready. `FoliateReaderHost` is defined here but has NO call site — the dispatcher routes `.foliateWeb` to `FoliateBilingualContainerView` instead.
- `vreader/Services/ReaderSettingsStore.swift` — `@Observable @MainActor final class ReaderSettingsStore`; the shared display-settings store threaded into every host.

## The dispatch (bug #246 hardening)

`engineReaderView(fingerprint:)` switches on `ReaderEngine.resolve(format: fingerprint.format)` — the canonical `BookFormat` parsed from `book.fingerprintKey`, NOT the parallel `book.format` String `@Model` column. `book.format` is set once at `Book.init` from `fingerprint.format.rawValue` and never re-synced, so a migration/restore edit could leave it stale; routing off the structural primary key makes dispatch drift-proof (bug #246 / GH #1072). The DEBUG eval-gate uses the matching `resolvedFingerprintFormat` helper so the probe wires the same engine the dispatcher renders (feature #42 WI-5 Codex Med-3).

## Format-host table (as dispatched in `engineReaderView`)

| Engine | Mounted view | Downstream |
| --- | --- | --- |
| `.textNative` | `TXTReaderHost` | `TXTReaderContainerView` (UITextView / chunked UITableView) — see [[Module — TXT reader]] |
| `.markdownNative` | `MDReaderHost` | `MDReaderContainerView` — see [[Module — MD reader]] |
| `.epubWKWebView` | `EPUBReaderHost` (when `routeEPUB` ≠ `.epubReadium`) | `EPUBReaderContainerView` → `EPUBWebViewBridge` — see [[Module — EPUB reader]] |
| `.epubReadium` | `ReadiumEPUBHost` (flag ON + paged; also a totality case in the switch) | Readium `EPUBNavigatorViewController` |
| `.foliateWeb` | `FoliateBilingualContainerView` (feature #56 WI-11 wrapper; bug #260 threads `ttsService`) | wraps `FoliateSpikeView` — see [[Module — Foliate AZW3 reader]] |
| `.pdfKit` | `PDFReaderHost` | `PDFReaderContainerView` → `PDFViewBridge` — see [[Module — PDF reader]] |

`BookFormat.azw3` subsumes `azw3/azw/mobi/prc` (`fileExtensions` in `vreader/Models/BookFormat.swift`). Separately, feature #42 Phase 2 (`kindleConvertOnImport`, a persisted flag in `FeatureFlags.swift`) converts NEW Kindle imports to EPUB at import time, so those books dispatch through the EPUB lane; already-imported native `.azw3` rows keep `.foliateWeb`.

## File URL resolution

`resolvedFileURL` reconstructs the sandbox path by convention (shared with `BookImporter`): Application Support `/ImportedBooks/<fingerprintKey with ":" → "_">.<BookFormat.fileExtensions.first>`.

## Adjacent reader subsystems (named, not detailed here)

This dossier is the shared-dispatch hub; it does not own the behavior of every file under `vreader/Views/Reader/` and its sibling `ViewModels/`/`Services/` directories. The groups below are named for coverage — detailed behavior lives in the owning module dossiers where those exist.

- **Reader AI panel and summary UI** (`Views/Reader/AISummary*.swift`, `ReaderAICoordinator.swift`, `Views/Reader/Bilingual/ReaderAIReadiness*`/`ReaderAIProvidersFlow.swift`, `Services/AI/SummaryScope*.swift`) — the AI-button sheet (chapter/book summary, bilingual scope picker) plus provider-readiness gating (bug #308).
- **BookDetails subsystem** (`Views/Reader/BookDetails/`: `BookDetailsSheet` + `+Cards`/`+Actions`/`+Translate`, `BookDetailsViewModel`, `BookDetailsMetadataRow`, `BookDetailsTagFlow`, `BookDetailsActionRow`, `BookDetailsReadingTimeMirror`) — feature #61's book-info sheet, a sibling of the annotation sheets in `readerChromeOverlay`.
- **Native pagination / unified-renderer stack** (`Services/Unified/PaginationCache.swift`, `Services/TextKit2Spike/TextKit2Paginator.swift`, `Services/ReflowableTextSource.swift` + format adapters `Services/TXT/TXTReflowableTextSource.swift`/`Services/MD/MDReflowableTextSource.swift`, `ViewModels/UnifiedTextRendererViewModel.swift`, `Views/Reader/UnifiedTextRenderer.swift`, `Views/Reader/EPUBPaginationHelper.swift`) — the shared TextKit2-based pagination engine underlying TXT/MD (and partially EPUB) rendering.
- **Highlight hit/render helpers** (`Views/Reader/TextHighlightRenderer.swift`/`TextHighlightHitResolver.swift`/`TextHighlightHitTester.swift`/`HighlightHitTolerance.swift`, `EPUBHighlightRenderer.swift`/`EPUBHighlightBridge.swift`, `FoliateHighlightJSBridge.swift`/`FoliateHighlightMutator.swift`, and the shared `HighlightCoordinator`/`HighlightPopoverPresenter`/`HighlightPopoverModifier` stack) — per-format render/hit-test pairs plus the format-agnostic popover, backed by `PersistenceActor+Highlights`/`HighlightPersisting`.
- **Dictionary and translation panels** (`DictionarySheet.swift`/`DictionaryLookup.swift`; `TranslationPanel.swift`/`TranslationResultCard.swift`/`TranslateLanguageRail.swift`; `Views/Reader/TranslateBook/` and `Views/Reader/ReTranslate/`; `BookTranslationViewModel`/`ChapterReTranslateViewModel`/`AITranslationViewModel`; `Services/AI/ChapterTranslationService.swift`/`BookTranslationCoordinator.swift`/`ChapterTranslationChunker.swift`) — word-lookup, selection-translate, and whole-book/chapter re-translate flows.
- **DebugBridge reader effects** — `Services/DebugBridge/DebugReaderRegistry.swift` (+`+WebViewWait`/`+Settle`) and `DebugReaderProbeAdapter.swift` are the harness this dossier's "Notification mirrors and DEBUG probe" section already covers at the dispatch level; per-format observer files (e.g. `DebugBridgeHighlightObserver`, `ReaderDebugBridgeSearchObserver`) live beside each format's container and belong to [[Module — debug bridge]].
- **Per-format ViewModels** (`ViewModels/TXTReaderViewModel.swift`, `MDReaderViewModel.swift`, `EPUBReaderViewModel.swift`, `ReadiumEPUBReaderViewModel.swift` + `+Mapping`/`+Navigation`, `FoliateReaderViewModel.swift`, `PDFReaderViewModel.swift`) — each owns its format's parsing/locator/session state, constructed by its host in `.task`; detailed behavior belongs to the owning format's module dossier.

## Shared chrome and reader-level state

- Custom overlay chrome replaces the system nav bar for pixel-stable content (bug #62 v3): `isChromeVisible` toggles on `.readerContentTapped`; `.toolbar(.hidden, for: .navigationBar)`, `statusBarHidden(!isChromeVisible)`, `preferredColorScheme` from `ReaderThemeV2.preferredColorScheme` (feature #60 WI-10/WI-11).
- `ReaderTopChrome` (feature #60 WI-6b): `← Library | Title [bilingual pill] | Search Bookmark ⋯`, composed once, format-agnostic, in `readerChromeOverlay` (`ReaderContainerView+Sheets.swift`). The `⋯` toggles `ReaderMorePopover` (WI-6c), whose rows post `.readerMore*` notifications.
- `ReaderBottomChrome` is composed PER FORMAT inside each container (each supplies its own progress binding + seek closure); its Contents/Notes/Display/AI buttons post `.readerOpenContents` / `.readerOpenNotes` / `.readerOpenDisplay` / `.readerOpenAI`, observed at the dispatcher via `.readerToolbarActionObservers`.
- Sheets: feature #62 split annotations into `TOCSheet` + `HighlightsSheet` behind one `.sheet(item: $annotationsRoute)` over `AnnotationsSheetRoute`; Book Details (feature #61, detents `.height(660)` + `.large`), Search, Share, AI panel, and AI readiness (bug #308) are sibling sheets using the `.sheet(onDismiss:)` handoff pattern (presenting two in one update drops the second).
- Bug #70 invariant: tap handling lives in each UIKit bridge (`UITapGestureRecognizer` with `shouldRecognizeSimultaneously`) — a SwiftUI tap overlay is forbidden because it blocks scroll gestures. `ReaderTapZoneRouter` (bug #239) is the pure side-tap → `.readerNextPage`/`.readerPreviousPage`/`.readerContentTapped` producer the bridges call, gated to `.paged` layout.

## ReaderSettingsStore wiring

Created as `@State var settingsStore = ReaderSettingsStore()` on the dispatcher and threaded into every host. Persists 9 UserDefaults keys enumerated in `allPersistedDefaultsKeys` (theme, typography, useCustomBackground, backgroundOpacity, epubLayout, autoPageTurn, autoPageTurnInterval, pageTurnAnimation, chineseConversion; drift-tested in `vreaderTests/Services/ReaderSettingsStoreTests.swift`). Per-book overrides load in the dispatcher's `.task` via `PerBookSettingsStore` and apply with `applyResolvedSettings` under `suppressPersistence` so they never leak into global defaults (bug #84); `reconcileFromDefaults()` re-reads globals after an override is disabled (bug #147). `epubLayout` is doubly load-bearing: it feeds `routeEPUB` AND the paged tap-zone routing in TXT/MD/EPUB/PDF bridges. Typography maps to per-renderer configs (`txtViewConfig`, `mdRenderConfig`) through `FontSizeCalibrator` (feature #70; TXT is the 1.0 anchor, PDF is not a target). Bug #222: clamped properties (`autoPageTurnInterval`, `backgroundOpacity`) use computed get/set over a backing store because an `@Observable` `didSet` that self-assigns recurses unboundedly. `ReaderSettingsPanel` (presented from the Display button, `.medium` detent) binds the store and gates controls on `FormatCapabilities` + `BookFormat`; feature #66 re-skinned its sliders (`Views/Reader/Settings/SettingsSliderRow.swift`) and font picker (`Views/Reader/Settings/TypefacePillToggle.swift`).

## Notification mirrors and DEBUG probe

The dispatcher mirrors per-format host state across the host boundary via the notification bus (see [[Architecture — notification bus]]): `.readerPositionDidChange` → `currentLocator` + `ReaderAICoordinator`; `.readerBilingualDidChange` (fingerprint-gated) → the chrome's bilingual pill state; `.readerBookTranslationTextProviderAvailable` → caches the host's `ChapterTextProviding` adapter and lazily builds `BookTranslationViewModel` (feature #56 WI-14). DEBUG-only (`#if DEBUG`): a `DebugReaderProbeAdapter` registers with `DebugReaderRegistry` on appear, keyed by a per-mount `readerToken: UUID` (bug #142 — a late `didFinish` from an outgoing webview cannot clobber a reopened reader). `probe.jsEvaluator` wires EPUB eval by the SAME flag+layout decision as the dispatcher (`epubEvalUsesReadiumEngine(store:)`, feature #85 WI-1) and AZW3 via the keyed Foliate webview; `settleStrategy` waits on real render-complete for EPUB/AZW3 (bug #141) while TXT/MD/PDF keep the 100 ms fallback. See [[Module — debug bridge]].

## Edge cases and invariants

- One host lifecycle quirk is host-owned on purpose: `EPUBReaderHost.onDisappear` (not the inner container) closes the viewModel/parser inside `beginBackgroundTask`, because closing on the inner view's disappear races transient re-mounts (`.notOpen` failures — bug #252 / GH #1089).
- `FoliateReaderHost` preloads the saved CFI (`persistence.loadPosition`) before constructing its VM.
- `ReaderContainerView.body` sits at SwiftUI's type-inference ceiling; new observers MUST be dedicated `ViewModifier`s (e.g. `FoliateTOCAvailableObserver`, `ReaderDebugBridgeSearchObserver`) or the build trips "unable to type-check in reasonable time".
- TOC builds eagerly in the dispatcher's `.task` (`ensureTOCReady()`, idempotent) through `ReaderTOCFactory.buildTOCDetailed` (EPUB spine, PDF outline, TXT Legado-rule chapters); `tocDidLoad` distinguishes "still loading" from "book ships no TOC".
- `deviceId` is `UIDevice.current.identifierForVendor?.uuidString` with a UUID fallback, shared by all hosts for position/session attribution.

## History

Feature #54 (engine selector replaces ReadingMode), #42 (Readium engine + flag), #85 (scroll → legacy routing), #56 WI-10/11/14 (bilingual chrome mirror, Foliate wrapper, translate-book), #60 WI-6b/6c/10/11 (chrome v2, themes), #61/#62 (Book Details, annotations split), #101 (reading-time readouts); bugs #62 v3 (overlay chrome), #70 (no SwiftUI tap overlay), #84/#147 (per-book settings), #142 (reader token), #239 (tap-zone producer), #246 / GH #1072 (fingerprint-format dispatch), #252 / GH #1089 (EPUB close lifecycle), #260 (Foliate TTS threading), #262 / GH #1136 (live Foliate TOC source).

**Sources.** [[session 014jggU2u3f3t6YRoPLS457u · 2026-07-10]] · [[session 014jggU2u3f3t6YRoPLS457u-audit · 2026-07-11]]. Artifacts consulted: vreader/Views/Reader/ReaderContainerView.swift, vreader/Models/ReaderEngine.swift, vreader/Views/Reader/ReaderFormatHosts.swift, vreader/Views/Reader/ReaderContainerView+Sheets.swift, vreader/Services/ReaderSettingsStore.swift, vreader/Views/Reader/ReaderTapZoneRouter.swift, vreader/Views/Reader/ReaderTOCBuilder.swift, vreader/Views/Reader/ReaderTopChrome.swift, vreader/Views/Reader/ReaderBottomChrome.swift, vreader/Models/BookFormat.swift, vreader/Services/FeatureFlags.swift, docs/architecture.md

**Verified.** 2026-07-11 — checked against: vreader/Views/Reader/ReaderContainerView.swift, vreader/Views/Reader/ReaderContainerView+Sheets.swift, vreader/Views/Reader/ReaderFormatHosts.swift, vreader/Models/ReaderEngine.swift, vreader/Models/BookFormat.swift, vreader/Models/ReaderThemeV2.swift, vreader/Models/ReaderThemeV2+ColorScheme.swift, vreader/Models/FontSizeCalibration.swift, vreader/Services/ReaderSettingsStore.swift, vreader/Services/FeatureFlags.swift, vreader/Services/FontSizeCalibrator.swift, vreader/Services/DebugBridge/DebugReaderProbeAdapter.swift, vreader/Views/Reader/ReaderNotifications.swift, vreader/Views/Reader/ReaderTapZoneRouter.swift, vreader/Views/Reader/ReaderTOCBuilder.swift, vreader/Views/Reader/ReaderTopChrome.swift, vreader/Views/Reader/ReaderBottomChrome.swift, vreader/Views/Reader/ReaderMorePopover.swift, vreader/Views/Reader/ReaderToolbarActionObservers.swift, vreader/Views/Reader/ReadiumEPUBHost.swift, vreader/Views/Reader/FoliateBilingualContainerView.swift, vreader/Views/Reader/Settings/SettingsSliderRow.swift, vreader/Views/Reader/Settings/TypefacePillToggle.swift, vreader/Views/Reader/ReaderSettingsPanel.swift, vreaderTests/Views/Reader/ReaderContainerViewEngineDispatchTests.swift, vreaderTests/Services/ReaderSettingsStoreTests.swift, docs/bugs.md, docs/features.md, archive/bugs-history.md, .claude/codex-audits/feat-feature-42-wi5-readium-host-audit.md
