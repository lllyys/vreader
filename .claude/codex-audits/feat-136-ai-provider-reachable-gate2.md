Reading additional input from stdin...
OpenAI Codex v0.144.1
--------
workdir: /Users/ll/workspace/vreader
model: gpt-5.6-sol
provider: openai
approval: never
sandbox: read-only
reasoning effort: high
reasoning summaries: none
session id: 019f5432-e326-7561-a958-07641fd41323
--------
user
Independent Gate-2 plan audit (round 1) for feature #136 (Android: make the already-built #118 AI provider config PRODUCTION-REACHABLE). Read the plan at dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md and verify it against the LIVE code in this repo.

Required checks:
1. MODEL/API ASSUMPTION VERIFICATION (the highest-value check — read the actual files): Do these named Kotlin symbols/files exist as the plan claims? android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt, AiProviderEditSheet.kt, AiSettingsViewModel.kt, and the AiProviderStore type. The AppContainer inside android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt (or wherever AppContainer lives). reader/chrome/ReaderChromeScaffold.kt — confirm readerMoreRows(...), MoreActionId.BILINGUAL, MoreRow.Disabled, and MorePopup.MoreRowItem exist and that MoreRow.Disabled currently renders with a NON-interactive onClick. CRITICALLY: confirm the plan's core premise — that AiProviderStore is NOT currently constructed in AppContainer, and AiProviderListScreen is reachable from NO production NavHost/route (only tests reference it). If that premise is wrong, this is a Critical finding.
2. DESIGN AUTHORITY (rule 51): confirm the design bundles the plan cites exist and depict the surfaces — dev-docs/designs/.../vreader-more.jsx (a configure-ai row), vreader-ai-android.jsx (AiProviderList), vreader-ai-provider-entry.jsx, and design-notes reader-ai-provider-entry.md / reader-ai-readiness.md. If the in-reader AI Providers sheet (Variant A) the plan reuses is NOT depicted, that is a rule-51 blocker.
3. WI COHESION: is the 3-WI split right? WI-1 = AppContainer aiProviderStore + aiSettingsViewModel() factory (claimed FOUNDATIONAL — verify it has no user-observable behavior). WI-2 = ReaderAiProvidersHost + ReaderSheet.AiProviders route + saver (behavioral). WI-3 = reader More-menu configure-ai entry across 5 hosts + readerMoreRows(aiUnconfigured,onConfigureAi) making MoreRow.Disabled tappable (behavioral final). Is any WI too big/small? Does WI-3's write-set (5 reader hosts) risk one-writer conflicts?
4. RISKS + MISSING EDGE CASES: DataStore under noBackupFilesDir + KeystoreSecretCipher; cipher/keystore failure paths; the aiUnavailable gate (active profile with non-empty key); config-change/process-death of the in-reader sheet; the 5-host entry duplication.
5. CONCURRENCY: DataStore reads, cipher decryption, StateFlow exposure.

Output findings grouped by severity (Critical / High / Medium / Low), each with file:line evidence, then a FINAL VERDICT line exactly one of: ship-as-is | follow-up-recommended | block-recommended. ship-as-is or follow-up-recommended clears Gate-2.
codex
I’ll perform this as a read-only, evidence-based audit: first the repository state and governing architecture/rules, then the plan, live Kotlin symbols/routes, and the cited design bundles.
exec
/bin/zsh -lc "git status -sb && sed -n '1,240p' docs/architecture.md && sed -n '1,280p' .claude/rules/47-feature-workflow.md && sed -n '1,260p' .claude/rules/51-no-self-designed-ui.md" in /Users/ll/workspace/vreader
 succeeded in 1203ms:
git: warning: confstr() failed with code 5: couldn't get path of DARWIN_USER_TEMP_DIR; using /tmp instead
git: error: couldn't create cache file '/tmp/xcrun_db-M8iOP9DG' (errno=Operation not permitted)
## main...origin/main
 M dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md
 M docs/features.md
?? .claude/codex-audits/feat-131-bilingual-gate2-round2.md
?? .claude/codex-audits/feat-136-ai-provider-reachable-gate2.md
?? android/2026-06-29-223908-this-session-is-being-continued-from-a-previous-c.txt
?? dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md
?? dev-docs/security/
# VReader Architecture

## Overview

VReader is an iOS e-book reader built with SwiftUI + SwiftData. It supports TXT, EPUB, AZW3/MOBI, PDF, and Markdown formats, each rendered by a format-specific native host (UIKit/WebView bridges) selected internally by `ReaderEngine` (feature #54). AZW3/MOBI is rendered via Foliate-js inside a WKWebView. **Feature #42 Phase 2 (`kindleConvertOnImport`, default ON since the G2 flip 2026-06-02):** NEW AZW3/MOBI/KF8/PRC imports are converted to a first-class EPUB at import time (via the vendored libmobi MOBI→EPUB converter) and render via the default Readium EPUB engine; already-imported native `.azw3` books are unchanged and keep rendering via Foliate, and a user can revert via the persisted `kindleConvertOnImport` override OFF. The `UnifiedTextRenderer` (TextKit 2 reflow) stack is retained in the codebase but no longer wired into the reader dispatch.

## System Diagram

```
┌──────────────────────────────────────────────────────┐
│                    VReaderApp                         │
│  SwiftData SchemaV10 · PersistenceActor · BookImporter│
└─────────────────────┬────────────────────────────────┘
                      │
          ┌───────────┴───────────┐
          │                       │
    ┌─────▼──────────┐    ┌──────▼──────────────────┐
    │  LibraryView    │    │  ReaderContainerView     │
    │  LibraryViewModel│   │  (format dispatcher)     │
    │  PreferenceStore │   │  ReaderTopChrome (overlay)│
    └─────────────────┘   └──────┬───────────────────┘
                                 │
        ┌────────┬───────────┬───┴────┬─────────┐
        │        │           │        │         │
    ┌───▼──┐ ┌──▼───┐  ┌───▼──┐ ┌──▼───┐ ┌────▼─────┐
    │ TXT  │ │ EPUB │  │ PDF  │ │  MD  │ │  AZW3 /  │
    │Bridge│ │Bridge│  │Bridge│ │Bridge│ │  MOBI    │
    └──────┘ └──────┘  └──────┘ └──────┘ └──────────┘
    UITextView WKWebView PDFKit  UITextView WKWebView
                                            (Foliate-js)
```

## Layers

### 1. App Layer (`vreader/App/`)

- `VReaderApp.swift` — SwiftData `ModelContainer` init (SchemaV10), migration plan (V1→…→V9→V10, all lightweight; V9→V10 adds the additive `Book.sourceCanonicalKey: String?` for feature #108's converted-Kindle cross-platform identity). Also runs the feature #109 one-shot `LocatorKeyBackfillMigration` synchronously at launch (flag-gated; recomputes derived locator keys under NFC canonicalization + repairs non-finite locators — a launch backfill, NOT a migration stage, since the transform changes no entity shape). Plus test seeding, error handling. Injects the live `PersistenceActor` into the SwiftUI environment via `\.persistenceActor` so settings sub-screens can construct backup providers without rewriting every parent's signature. Adopts `@UIApplicationDelegateAdaptor(VReaderAppDelegate.self)` for background-URLSession completion-handler delivery (feature #47).
- `VReaderAppDelegate.swift` — `UIApplicationDelegate` adapter that captures `application(_:handleEventsForBackgroundURLSession:completionHandler:)` into a MainActor-isolated static dictionary keyed by URLSession identifier. The lazy-download coordinator retrieves and invokes the handler from `LazyDownloadDelegate.urlSessionDidFinishEvents` so iOS releases the app's background-launch grace period.

### 2. Library Layer (`vreader/Views/LibraryView.swift`, `vreader/ViewModels/LibraryViewModel.swift`)

- Grid/list view with sort (persisted via `PreferenceStore`)
- Context menu: Info, Share, Set Cover, Add to Collection, Delete
- Collections sidebar, OPDS catalog, AI chat entry points
- Cover art (`BookCoverArtView`) renders a custom image when one exists, otherwise a generative typographic cover (Feature #60 WI-10 — `GenerativeCoverView`). The cover's style family + colour palette are deterministically derived from the book's `fingerprintKey` (FNV-1a hash → one of 5 style families × 12 design palettes in `GenerativeCoverStyle.swift`), so a given book always shows the same generated cover.

### 3. Reader Layer (`vreader/Views/Reader/`)

#### Dispatcher

`ReaderContainerView.swift` routes to format-specific readers via
`engineReaderView(fingerprint:)`, which switches on
`ReaderEngine.resolve(format: fingerprint.format)` — an internal per-format
engine selector (feature #54). Bug #246 / GH #1072 hardened the dispatch
to route off `fingerprint.format` (the typed `BookFormat` already parsed
from the canonical `book.fingerprintKey` by the body's
`DocumentFingerprint(canonicalKey:)` guard) instead of `book.format` (a
parallel String `@Model` column set once at `Book.init` and never re-synced).
Routing off the structural primary key makes the dispatch drift-proof against
any future writer that updates one without the other (SwiftData migration,
direct context write, restore-path edit, CloudKit sync). The dispatch no
longer consults a reading-mode preference, and the reader-settings Reading
Mode picker UI is gone. The `readerReadingMode` UserDefaults key and the
`ReadingMode` enum have been removed; `ReadingModeMigration` (run
synchronously at launch from `VReaderApp`) clears the retired key from
UserDefaults and strips the `readingMode` field from per-book override
JSON files.

- `.textNative` → `TXTReaderHost`, `.markdownNative` → `MDReaderHost`,
  `.epubWKWebView` → `EPUBReaderHost`, `.pdfKit` → `PDFReaderHost`,
  `.foliateWeb` → `FoliateBilingualContainerView` (AZW3/MOBI; the
  bilingual wrapper from feature #56 WI-11 sits between the dispatcher
  and `FoliateSpikeView`, adding the bilingual VM / orchestrator / setup-
  sheet wiring without modifying the spike itself).
- `resolve(format:)` maps `.epub` to `.epubWKWebView` unconditionally (it
  stays the pure format→default-engine map). Feature #42 routes EPUB to the
  Readium Swift Toolkit engine (`ReadiumEPUBHost`) via
  `FeatureFlags.readiumEPUBEngine`, which is **default ON since the WI-14
  human-gated G2 flip (2026-06-01)** — Readium is now the default reflowable EPUB
  engine; a persisted user/debug override OFF reverts to the legacy
  `EPUBReaderHost`. The flag read lives in the dispatcher
  (`ReaderContainerView.engineReaderView` → `ReaderEngine.routeEPUB`), not in
  `resolve`, so a flag-unaware caller still gets the legacy `EPUBReaderHost`. The
  `.epubReadium` engine case exists for switch totality; `resolve` never returns
  it. **Feature #85 (approach C) makes the routing layout-aware**:
  `routeEPUB(readiumFlagEnabled:layout:)` sends EPUB **scroll** mode to the
  legacy `EPUBReaderHost` (which activates the seamless feature-#71
  continuous-scroll stitch) even when the Readium flag is ON — Readium's
  per-resource paginator has an inherent chapter-boundary seam in scroll mode —
  while **paged** mode keeps Readium. Because the SAME book is then rendered by
  two engines depending on mode, a reading-mode toggle SWAPS hosts; an in-memory
  `ReaderPositionHandoff` (a `@MainActor` per-book cache both hosts write
  synchronously on every location change + read on open before persistence)
  carries the position across the swap without loss, and a Readium open with no
  `.readium` envelope (a scroll session cleared it) restores the legacy locator
  post-open via `publication.readingOrder` + a one-shot `navCommander.navigate`.
  `EPUBScrollAnchorResolver` tolerates the container- vs OPF-relative href forms
  the two engines persist.

#### Chrome

Reader chrome (Feature #60 WI-6b — visual-identity-v2) is two custom overlays, floating on top of content with no safe-area impact:

- `ReaderTopChrome.swift` — top bar: `← Library | Title | Search Bookmark More`. Composed once in `ReaderContainerView`, format-agnostic. The `⋯` More button toggles `ReaderMorePopover`.
- `ReaderBottomChrome.swift` — bottom bar: progress scrubber + position labels + a Contents/Notes/Display/AI toolbar. Composed per format inside each container, each passing its own seek closure; the toolbar posts `.readerOpen*` notifications that `ReaderContainerView` observes. The four native containers (TXT/MD/EPUB/PDF) mount it in their `bottomOverlay`; Bug #260 added the Foliate (AZW3/MOBI) mount via `FoliateBilingualContainerView+BottomChrome.swift` — scrubber fed by the relocate `fraction`, seek via `.foliateRequestSeekFraction` → `readerAPI.goToFraction`, position labels via pure `FoliateBottomChromeLabels`. (Each container owns its own `isChromeVisible`; chrome visibility is not yet hoisted to the shared level — see Bug #262 for the cross-format desync follow-up.)
- `ReaderMorePopover.swift` — anchored More-menu popover (Feature #60 WI-6c), composed in `ReaderContainerView`'s chrome overlay. Five rows (Read aloud / Auto-turn | Book details / Share / Export); each posts a `.readerMore*` notification that `ReaderContainerView` observes. The design's sixth row (Bilingual) is deferred — GH #790.

Slot/button identity lives in `ReaderChromeButton.swift` (`ReaderTopChromeSlot` / `ReaderBottomChromeButton`); More-menu row identity lives in `ReaderMoreMenuRow.swift`.

#### Sheets (Feature #60 WI-10 — visual-identity-v2)

The app sheets share `ReaderSheetChrome.swift` — a reusable wrapper matching the design's `Sheet` component: a theme-tinted surface (`ReaderThemeV2.sheetSurfaceColor`), an optional centred Source Serif 4 title bar with 50pt leading/trailing slots (a default circular close button fills the trailing slot when an `onClose` is given and no custom trailing view is), and a scrollable body. The slide-up animation + drag grabber come from SwiftUI's own `.sheet` + `.presentationDragIndicator(.visible)`; `ReaderSheetChrome` supplies only the title bar + surface tint. It wraps the Display sheet (`ReaderSettingsPanel`), the two annotations sheets (`TOCSheet` + `HighlightsSheet`, feature #62 — see below), the reader Book Details sheet (`BookDetailsSheet`, feature #61 — opened from More → Book details, with a trailing Share button in place of the default close), and the AI sheet (`AIReaderPanel`, `title: nil` + a custom sparkle header). `SettingsView` (App Settings) keeps an inner `NavigationStack` for its `NavigationLink` push destinations, with `ReaderSheetChrome` above it. The per-sheet section contract is pinned in `SheetSectionContract.swift` (`ReaderSheetKind`). Reader sheets pass the book's `ReaderThemeV2`; the App Settings sheet uses `.paper` (the Library is not theme-switchable).

**Annotations sheets (feature #62 — annotations-panel split).** The pre-#62 unified 4-tab `AnnotationsPanelView` (Contents / Bookmarks / Highlights / Notes) is split into two job-focused sheets, each with one honest title: `TOCSheet` (book-titled — Contents + Bookmarks navigation tabs) and `HighlightsSheet` (titled "Annotations" — All / Highlights / Notes / Bookmarks review filters + a Share/export button). `ReaderContainerView` presents them via a single `.sheet(item: $annotationsRoute)` over the `AnnotationsSheetRoute` enum (`.toc(initialTab:)` / `.highlights(initialFilter:)`) — the Contents bottom-chrome button and the Notes button each map to one route; the two sheets are mutually exclusive by that optional. `HighlightsSheet`'s unified card stream interleaves highlight + standalone-note cards via `AnnotationStreamBuilder`. Both sheets' designed empty states use the shared `AnnotationsEmptyStateView` (custom SVG art). The legacy `HighlightListView` / `AnnotationListView` / `TOCListView` / `BookmarkListView` list views were removed by feature #62. Each card carries a per-row **delete affordance** (Bug #249 — a trailing `⋯` `NotesActionMenu` of Edit · Copy · Delete + an inline `NotesDeleteConfirm` strip mirroring the in-reader `HighlightPopoverDeleteConfirm`, plus a left-swipe `NotesSwipeActions` drawer); the per-row interaction phase is held on the sheet by the SHEET-owned pure `NotesRowState` (at most one row non-default at a time), and Delete routes through `HighlightListViewModel.removeHighlight` / `AnnotationListViewModel.removeAnnotation`. The container stays `LazyVStack` (not a `List`), so the swipe is a custom `DragGesture` translate rather than `.swipeActions` (which requires a `List` host).

`ReaderContainerView` drives `preferredColorScheme(_:)` from `ReaderThemeV2.preferredColorScheme` (`ReaderThemeV2+ColorScheme.swift`) so the status bar tints to match the theme — `.dark` for the Dark / OLED / Photo families, `.light` for Paper / Sepia.

#### Format Hosts (`ReaderFormatHosts.swift`)

Each host owns its ViewModel lifecycle via `@State`:

- `TXTReaderHost` → `TXTReaderContainerView` → `TXTTextViewBridge` (small single-chapter / Paged) or `TXTChunkedReaderBridge` (>500K UTF-16, **and** chaptered TXT in Scroll layout — bug #180). Chaptered TXT in Scroll layout renders as one continuous `UITableView` surface fed the whole book: `TXTContinuousChunkBuilder` splits the decoded book into document-global-offset chunks, `TXTChapterOffsetIndex` layers chapter awareness so `currentChapterIdx` is *derived* from scroll offset (no per-chapter render unit, no chapter-swap).
- `EPUBReaderHost` → `EPUBReaderContainerView` → `EPUBWebViewBridge` (WKWebView + JS injection). **Paged** EPUB loads one spine item per `loadFileURL`. **Continuous scroll** (feature #71, the DEFAULT for EPUB scroll layout since the terminal-WI flag flip on 2026-05-28 — `FeatureFlags.epubContinuousScroll` defaults ON; a persisted user/debug override can still disable it) instead loads a single bootstrap document and stitches a lazy ±1-chapter window into it: `EPUBContinuousScrollCoordinator` owns an `EPUBSpineWindow` `[lo…hi]` anchored on the reading chapter and, on the section-aware scroll observer's boundary signals, materializes the adjacent chapter (`EPUBContinuousChapterProvider` → `EPUBChapterBodyRewriter` → `EPUBContinuousScrollJS.append/prependChapterSectionJS`) and evicts the far side (`maxSpan`) to bound memory. Per-section highlight restore hangs off a `sectionMaterialized` lifecycle message (appended sections never fire `didFinish`); saved-position restore + TOC/bookmark/search navigation drive the coordinator (`navigate(toSpineIndex:fraction:)` — scroll within the window, or rebuild around an out-of-window target). The evaluator reaches the live `WKWebView` through a late-binding `EPUBWebViewEvaluatorHandle` the bridge binds in `makeUIView`.
- `ReadiumEPUBHost` (feature #42 Phase 1, WI-5) → `ReadiumNavigatorRepresentable` → Readium Swift Toolkit `EPUBNavigatorViewController`. Selected by the dispatcher in place of `EPUBReaderHost` when `FeatureFlags.readiumEPUBEngine` is ON (**default ON since the WI-14 G2 flip 2026-06-01**; a persisted override OFF reverts to the legacy `EPUBReaderHost`). Opens the publication off-main via `ReadiumEPUBReaderViewModel` (`AssetRetriever` → `PublicationOpener`), then mounts the navigator; `EPUBPreferences(scroll:)` is mapped from `ReaderSettingsStore.epubLayout`. The `ReadiumReaderCoordinator` is the `EPUBNavigatorDelegate` + (DEBUG) `ReadiumNavigatorEvaluating` seam — it registers the active navigator with `DebugReaderRegistry.setActiveReadiumNavigator` and `markReaderSettled` on `locationDidChange`, and tears that registration down on `dismantleUIViewController` via `detach()` → `clearActiveReadiumNavigator` (the host registers no `DebugReaderProbe`, so it owns its own registry teardown). Reading-position save/restore landed in WI-6: the coordinator forwards `locationDidChange` to the VM's debounced save, which maps the Readium `Locator` → a `VReaderLocator` envelope (engine `.readium`, authoritative `readiumLocatorJSON` + a lossy legacy `Locator` leg) and dual-writes it through `PersistenceActor`'s `VReaderLocatorPersisting` conformance — `saveVReaderLocator` writes both the envelope blob into the SchemaV8 `ReadingPosition.vreaderLocatorData` column AND the legacy `locator`; legacy `savePosition` clears the envelope so a flag-OFF write can't be shadowed by a stale Readium position. On open, the host loads the saved envelope (`restoredReadiumLocator()`) before the navigator mounts and passes it as `initialLocation`. Theme/font landed in WI-7: the host body reads `ReaderSettingsStore.theme` + `.typography` + `.epubLayout` (tracked `@Observable` deps) and recomputes a full `EPUBPreferences` on any Display-settings change, which `updateUIViewController` re-submits live (`submitPreferences`). `ReadiumEPUBReaderViewModel+Mapping` translates the 5 `ReaderThemeV2` themes → Readium's 3 base `Theme`s + explicit `backgroundColor`/`textColor` (which win via `effectiveBackgroundColor`); font size from the per-format-calibrated `.epub` size (`FontSizeCalibrator`) → Readium's multiplier; `lineHeight` from `lineSpacing`; `fontFamily` (system→sansSerif, serif/sourceSerif4→serif, monospace→monospace, inter→sansSerif — custom-font registration deferred); `publisherStyles=false`. The WI-7 photo/custom-background refinement composites the decorative image behind the navigator: `ReadiumEPUBHost+Background.swift` layers the existing `ThemeBackgroundView` under the navigator in a `ZStack` (only when `useCustomBackground` + an image exists for the theme), and `ReadiumReaderCoordinator+Transparency` makes the navigator render through — `epubPreferences(..., transparentBackground:)` emits `backgroundColor: nil` (so ReadiumCSS injects no body bg rule), the representable forces `navigator.view`/spine `WKWebView`s `.clear`/`isOpaque=false`, and a read-only self-gating user script clears the opaque `html:root` ReadiumCSS paints (transparency state is authored into `localStorage` by Swift on each `locationDidChange`/toggle). Normal opaque themes are unchanged. Highlights landed in WI-8: `ReadiumDecorationHighlightAdapter` (a `HighlightRenderer`, the Readium counterpart of `EPUBHighlightRenderer`) renders stored highlights as Readium **Decorations** via `EPUBNavigatorViewController.apply(decorations:in:"highlights")` (declarative — the adapter holds the active set and re-submits the whole group on each apply/remove/restore). Re-anchoring is **text-quote** based (WI-8a migration spike): each `HighlightRecord` → `Decoration(locator: Locator(href:, text: .Text(highlight: selectedText, before/after: context)), style: .highlight(tint:))` — Readium re-finds the quote, so the legacy XPath `serializedRange` is never consulted or mutated (flag-OFF returns to legacy XPath rendering losslessly). The host owns the adapter + a `HighlightCoordinator(renderer: adapter)`, calls `restoreAll()` on open, and observes `.readerHighlightRemoved`/`.readerHighlightsDidImport`. The WI-8 new-highlight refinement adds CREATE from a live Readium selection: `ReadiumReaderCoordinator` conforms to `SelectableNavigatorDelegate` and `navigator(_:shouldShowMenuForSelection:)` forwards the finalized `Selection` to the host then returns `false` (suppressing Readium's native menu so the designed `SelectionPopoverView` is the sole selection surface — rule 51). `ReadiumEPUBHost+Highlights` stashes the `Selection` in a generic `ReadiumSelectionTokenCache<Selection>` under a token, presents the popover; on a color tap (`.readerHighlightRequested`) it resolves the token and `ReadiumSelectionHighlightBuilder` maps the `Selection`'s text-quote (highlight/before/after) + container-relative href → `HighlightRecord` inputs → `HighlightCoordinator.create` → the same `ReadiumDecorationHighlightAdapter` renders it immediately; `navCommander.clearSelection()` dismisses the selection. Navigation landed in WI-9a: the host observes the shared reader nav bus — `.readerNextPage`/`.readerPreviousPage` → the coordinator's `goForward`/`goBackward`, and `.readerNavigateToLocator` (TOC/bookmark/search-result tap, object = a vreader `Locator`) → `go(to:)` after mapping the vreader Locator → Readium Locator (`readiumLocator(fromVReader:spineHrefs:)`, reusing the WI-8 legacy→spine href resolution). Host→coordinator dispatch goes through a host-owned `ReadiumNavCommander` (`@State`, bound on `attach`/cleared on `detach`, mirrors the WI-8 adapter ownership). WI-9a also split the host into `ReadiumEPUBHost.swift` (View) + `ReadiumNavigatorRepresentable.swift` + `ReadiumReaderCoordinator.swift`. Footnotes (#138, WI-9b) remain. Search result-list extraction still uses the existing FTS/`SearchViewModel` stack — WI-9a maps only result *navigation*. **Bilingual landed in WI-11 (paged) and WI-12 (scroll parity): interlinear bilingual works under the flag by driving the enumerate→prefetch→inject loop through Readium's one-way `evaluateJavaScript(_:) async -> Result<Any,Error>` channel — NOT a script-message handler (the navigator owns its content controller, exposing no app-side message channel; this is why the WI-11a `ReadiumBilingualEvalAdapter` RETURNS the `[{bid,text}]` array rather than posting it). A host-owned `ReadiumBilingualCommander` (`@State`, the bilingual counterpart of `ReadiumNavCommander`) holds an evaluator closure the coordinator binds on `attach` (the production non-DEBUG `ReadiumReaderCoordinator.evaluateForBilingual`, returning Readium's raw `Result<Any,Error>?`) and clears on `detach`; `enumerate()` runs `ReadiumBilingualEvalAdapter.enumerateJS()` and parses the return value via `EPUBBilingualPipeline.parseEnumerateMessage`, `inject(_:)`/`clear()` run the engine-agnostic inject/clear builders. The host reuses the feature-#56 `EPUBBilingualOrchestrator` (paged `-1` bucket via `updateBlocks(_:)`) + `BilingualReadingViewModel` + the designed `BilingualSetupSheet` (rule 51 — no new UI). Source text comes from vreader's own `EPUBParser` (opened alongside the Readium open — Readium does not expose raw spine HTML), so the `EPUBChapterTextProvider` is keyed on OPF-relative spine hrefs; the Readium-produced vreader `Locator` carries Readium's CONTAINER-relative href, so `ReadiumBilingualCommander.normalizedLocator(_:toSpineHrefs:)` rewrites it onto the OPF spine via the shared `ReadiumDecorationHighlightAdapter.resolveHref` tolerance before `vm.handlePositionChange(...)` (the WI-8 href-consistency finding class — without it `unit(containing:)` returns nil and nothing translates). Chapter-change detection composes onto the existing `onLocationChange` (WI-6 position save still runs): a fresh enumerate runs only when the spine href changes, deduped intra-chapter by a reference-type `ReadiumBilingualChapterTracker`. WI-12 lifted the WI-11 paged-only gate (`isBilingualSupported` is true for both layouts) so bilingual works in scroll too — but PER-SPINE only: Readium scroll mode is per-resource (it emits `locationDidChange` at spine boundaries, driving the same per-spine enumerate the paged path uses), and Readium has no multi-spine-stitch API, so off-screen chapters enumerate when scrolled into view rather than eagerly. This is a documented behavior delta vs legacy #71 — the flag-OFF `EPUBWebViewBridge` engine keeps its full stitched cross-chapter continuous bilingual; the Readium engine does not reproduce it. A paged↔scroll layout change re-renders the spine (discarding the `data-vreader-bid` stamps + decorations), so the layout-change handler re-enumerates the current spine in both directions.** TTS (WI-10): read-aloud already works under the Readium engine with NO Readium-specific code — `ReaderContainerView.startTTS()` → `ReaderAICoordinator.loadBookTextContent(format: "epub")` extracts spine text from the **file** via `EPUBParser` (renderer-agnostic, independent of which engine renders), then feeds the shared `TTSService` pipeline. Device-verified under `readiumEPUBEngine` ON (speaking, `ttsOffsetUTF16` advancing 42→115, stop→idle). The speaking-position **follow** landed in WI-10b: as TTS speaks, the navigator auto-advances so the spoken text stays on screen. `ReadiumEPUBHost` observes the shared `TTSService.currentOffsetUTF16` (threaded in like `EPUBReaderHost`); a pure value-type `ReadiumTTSFollowMapper` maps the flat UTF-16 offset → (spine href, intra-spine fraction). CRITICAL alignment: the per-spine offset table is built from the SAME spine text the TTS engine reads — `EPUBTextExtractor.stripHTML` + trim, skip empties, join `"\n\n"` (the `ReaderAICoordinator.loadBookTextContent` recipe) — extracted off-main from the host's already-open `bilingualParser` (so the index matches the engine's offsets; the block-preserving bilingual stripper is deliberately NOT used here). `ReadiumEPUBHost+TTSFollow` throttles: it navigates on any spine-href change or an intra-spine fraction drift > 0.08 (so the navigator tracks ~chapter-eighth granularity, not every `willSpeakRange` word), maps the target → a vreader `Locator` → Readium `Locator` via the WI-9a `readiumLocator(fromVReader:spineHrefs:)` resolution, and drives the existing `navCommander.navigate(to:)` → `navigator.go(to:)`. Follow runs only while TTS state == `.speaking`; the cursor resets on each play start and on pause/stop. This unblocks the WI-14 default-ON flip.
- `PDFReaderHost` → `PDFReaderContainerView` → `PDFViewBridge` (PDFKit)
- `MDReaderHost` → `MDReaderContainerView` → reuses `TXTTextViewBridge` with NSAttributedString
- AZW3/MOBI is dispatched directly to `FoliateSpikeView` (the AZW3 spike landed before the host abstraction; convergence is deferred). `FoliateReaderHost` / `FoliateReaderContainerView` exist but are not currently wired into `ReaderContainerView`. **Feature #73 added a windowed multi-section continuous-scroll surface inside the vendored Foliate-js `paginator.js`** (default ON for horizontal-writing scroll mode, gated behind the renderer's `#windowedScroll`). Instead of the per-section view-swap — whose `scrollToAnchor(0)` offset reset + blank-flash on `#createView` destroy/async-load + post-swap reflow were the three stacked discontinuities of the Bug #283 chapter-boundary jump — a K=3 window of adjacent sections is mounted into the single scrolling `#container` and recycled on scroll: `#ensureWindow` mounts neighbours (firing the same `load`/`create-overlayer` lifecycle so each neighbour doc is wired for selection/overlays), `#evictOutsideWindow` unmounts + unloads the far side with `scrollTop` compensation, `#promoteCurrentView` tracks the current section by scroll position (a pointer swap, no DOM move), and `#windowedResolve` emits the intra-section relocate fraction (`progress.js`/`SectionProgress` still owns whole-book conversion, preserving Bug #265 position restore). A `#windowGeneration` token aborts stale async mounts across navigation. Vertical writing + paged mode keep the single-`#view` swap path. The pure windowing math (window clamp, offset↔section mapping, intra-section fraction, evict adjustment, anchor translation) is mirrored + unit-tested in `FoliateScrolledWindowMath.swift`; flag-on behavior was device-verified and the JS diff passed a 2-round independent Codex audit.

#### Foliate-js Bridge (`vreader/Views/Reader/`, `vreader/Services/Foliate/`)

`FoliateViewBridge` (UIViewRepresentable) hosts a WKWebView and uses `loadHTMLString` with the IIFE-bundled `foliate-bundle.js` inlined; books are handed to JS as base64 (no scheme handler in the live load path — `FoliateURLSchemeHandler` exists in the codebase but isn't wired into the active bridge today). `FoliateViewCoordinator` (WKScriptMessageHandler + WKNavigationDelegate) receives JS messages, parses via `FoliateMessageParser`, and routes to typed callbacks. `FoliateHighlightRenderer` generates JS strings for SVG overlay annotations — but it is **not** plugged in as a `HighlightRenderer` adapter today; AZW3 highlight create has a TODO for persistence/JS injection and overlay restore is a no-op placeholder (`FoliateReaderContainerView+Highlights.swift`). `FoliateJSEscaper` provides shared sanitization for all JS/CSS string interpolation across the bridge. `FoliateReaderViewModel` maps bridge events to `Locator` for position persistence.

The Foliate JS bundle is built from sources under `vreader/Services/Foliate/JS/` via `build-bundle.sh`, which calls a locally-pinned esbuild (`package.json` + `package-lock.json`, currently `esbuild@0.28.0`; bootstrapped via `npm ci` — node ≥18). `paginator.js` is the source of truth; `foliate-bundle.js` is checked in and must be rebuilt whenever the source changes (a parity check in `FoliatePaginatorScrollBoundaryTests` enforces this for the scroll-mode boundary-detect helper that resolved Bug #235).

#### Unified Engine (retained, not dispatched)

`ReaderUnifiedCoordinator` loads text + applies transforms (replacement rules, simp/trad); `UnifiedTextRenderer` displays with TextKit 2 pagination or scroll. Feature #54 removed the unified path from the reader dispatch and the reader-settings Reading Mode picker, so this stack is **no longer reachable from reader dispatch** — it is retained (a follow-up may consume it for bilingual reading, or delete it once provably orphaned). Content replacement rules and Chinese conversion that previously required Unified mode now run in the native readers directly: `MDFileLoader.load` composes `ReplacementTransform` + `SimpTradTransform` over the decoded source text before parsing (feature #54 WI-7); **native EPUB applies replacement rules via `EPUBReplacementJS` (feature #54 Phase D-1)** — a CFI-safe per-text-node JS injection that runs on both EPUB engines (Readium per-spine via `ReadiumReaderCoordinator+Replacement`; the legacy #71 WKWebView stitch on `didFinish` via `EPUBWebViewBridgeCoordinator`, plus a scroll-root `MutationObserver` for appended chapters), keyed by `MDReplacementRuleFetcher`; native TXT has Chinese conversion only — TXT replacement rules are deferred (they need a source↔display offset map). Replacement rules apply at chapter/document open; a mid-read rules edit takes effect on next open (v1 scope).

### 4. Coordinator Layer (`vreader/Views/Reader/`)

Cross-format coordinators that compose with multiple readers:

| Coordinator                | Responsibility                                                      | Setup Timing                                                          |
| -------------------------- | ------------------------------------------------------------------- | --------------------------------------------------------------------- |
| `ReaderAICoordinator`      | AI ViewModels, text loading, context extraction                     | On AI/TTS invoke                                                      |
| `ReaderSearchCoordinator`  | Search service, indexing, FTS5                                      | Service+VM eagerly via `prepareEagerly()` on reader open (bug #79; cold SQLite open is `nonisolated`, off-MainActor); indexing still deferred to `setup()` on first sheet open |
| `ReaderUnifiedCoordinator` | Unified renderer state, text transforms — retained but no longer dispatched (feature #54) | n/a (no dispatch path)                                     |
| `HighlightCoordinator`     | Persists via `HighlightPersisting`, dispatches to `HighlightRenderer` adapters | On reader open per format (TXT/MD/PDF/EPUB)                          |

Bridge-internal coordinators (`EPUBWebViewBridgeCoordinator`, `FoliateViewCoordinator`, `TXTTextViewBridgeCoordinator`) handle delegate / WKScriptMessageHandler plumbing for one bridge each; they're not cross-cutting and aren't enumerated here.

### 5. Services Layer (`vreader/Services/`)

| Service                              | Backing                    | Purpose                                                                   |
| ------------------------------------ | -------------------------- | ------------------------------------------------------------------------- |
| `PersistenceActor`                   | SwiftData (actor-isolated) | All DB writes serialized                                                  |
| `SearchService` + `SearchIndexStore` | SQLite FTS5                | Full-text search with persistent index                                    |
| `AIService`                          | OpenAI-compatible REST API | Summarize, translate, chat. Feature #56 added a resolved-provider seam — `ResolvedAIProviderConfig` (an immutable `{kind, baseURL, apiKey, model, maxTokens}` snapshot) plus `resolveActiveProviderConfig()` / `resolveProviderConfig(profileID:modelOverride:)` / `sendRequest(_:using:)`. A *multi-request* operation (chapter translation = one request per chunk) resolves the config ONCE and pins the credential + model for every chunk; `sendRequest(_:using:)` deliberately bypasses `AIResponseCache` (its key is not provider-aware). The original `resolveProvider()` / `sendRequest(_:)` / `streamRequest(_:)` are unchanged. **Feature #91 (agentic tool-calling)** added `supportsToolUse` + `sendToolRequest(_:)` on `AIProvider` (Anthropic `tool_use` / OpenAI `tool_calls`; default-off so non-tool providers compile unchanged), and on `AIService`: `resolveToolProvider()` (resolve the config ONCE + report tool-use capability), `sendToolTurn(_:using:)` + `streamRequest(_:using:)` (one turn/stream through the pinned config, RE-checking the live flag + consent each turn so a mid-loop revoke fails closed) |
| `AgenticChatDriver` + `AIToolRegistry` (`Services/AI/`) | `AIService` + the tool executors | **Feature #91 — agentic AI chat.** `AgenticChatDriver` is the bounded send→tool→result→re-send loop (one pre-resolved provider via `AIServiceToolUseAdapter`, `maxIterations` cap, returns `{finalText, usedTools}`); `AIToolRegistry` dispatches a model `ToolCall` to its `AITool` (unknown tool → `isError` result, never throws). Four read-only executors wrap existing capabilities: `search_current_book` (the open book's FTS), `search_other_books` (the whole library, gated by the pure `LibraryBookSearchGate` over the persistent index), `get_book_content` (a book's text by title, locality/format-gated), and `list_library` (feature #97 — enumerate the bookshelf: title/author/format, over the same `LibrarySearchBackend.libraryBooks()`; dedupe, open-book exclude, total deterministic sort, cap+announce, canonical-format display, restore-placeholder friendliness). `AgenticToolRegistryBuilder.buildLive` assembles them over the production `LibrarySearchBackendAdapter` + `BookContentProviderAdapter` (+ `ClosedBookTextExtractor`) and the shared `PersistentSearchIndex` store. `AIChatViewModel.sendMessage` routes through the driver when `agenticTools` is on + the resolved provider supports tool-use (silent loop, single final answer, citations suppressed on a tool reply); otherwise the existing streaming path. Default OFF |
| `PersistentSearchIndex` (`Services/Search/`) | `SearchIndexCore` + `SearchIndexStore` | The single Services-layer source of truth for the on-disk FTS index location (`Application Support/SearchIndex/search.sqlite3`) + persistent-store construction (`makeStore()`, in-memory fallback). `ReaderSearchCoordinator` delegates to it; Feature #91's agentic search tools open the SAME persisted index through it |
| `TTSService`                         | `SpeechSynthesizing` seam | `@MainActor @Observable` read-aloud state machine (idle/speaking/paused + UTF-16 progress offset). Speaks through an injected `SpeechSynthesizing` and wires its `AVSpeechSynthesizerDelegate` callbacks generically via the protocol's `delegateTarget` (feature #72 WI-0), so any backend — on-device, XCUITest mock, or the cloud adapter — drives progress without type-casing. `defaultSynthesizer(configStore:)` picks the backend: XCUITest mock (DEBUG override) > `HTTPSpeechSynthesizer` when a valid `HTTPTTSConfig` is persisted (feature #72 WI-3) > `SystemSpeechSynthesizer` (on-device) |
| `HTTPSpeechSynthesizer`              | `HTTPTTSProvider` + `HTTPTTSChunkPlayer` | Feature #72 WI-3 cloud-TTS adapter: the `SpeechSynthesizing` impl that finally wires the orphaned `HTTPTTSProvider` (bug #270) into live read-aloud. Per `speak`, chunks the utterance (`HTTPTTSProvider.chunkText`), synthesizes each chunk over HTTP, streams the audio blobs into `HTTPTTSChunkPlayer`, and emulates the `AVSpeechSynthesizerDelegate` callbacks `TTSService` consumes (chunk-range `willSpeakRange`, `didFinish`, `didCancel`). Conforms to the non-isolated protocol via `@unchecked Sendable` + `MainActor.assumeIsolated` wrappers over `@MainActor` impls; `TTSService` (its only caller) is `@MainActor`. Audio session stays owned by `TTSService` |
| `HTTPTTSChunkPlayer`                 | `AVAudioPlayer` (behind `SpeechAudioPlaying` seam) | Feature #72 WI-2 sequential audio-chunk playback queue for the cloud path. Plays streamed `Data` chunks back-to-back, fires `onChunkStarted(index)` as each begins and `onFinished` once the LAST chunk of a COMPLETE input drains (drain ≠ complete — `markInputComplete()` gates the finish). Generation token ignores late finishes from stopped/replaced players. Does NOT manage `AVAudioSession` |
| `HTTPTTSConfigStore`                 | `UserDefaults` + `KeychainService` | Feature #72 WI-1 loader: decodes the persisted `HTTPTTSConfig` from UserDefaults and splices the API key from Keychain; `loadValidConfig()` returns the config only when it passes `validate()`. Consumed by `TTSService.defaultSynthesizer` to decide whether the cloud path is active |
| `BookContentCache`                   | In-memory                  | Text cache for AI context loading (TXT/MD only)                           |
| `PreferenceStore`                    | UserDefaults               | Sort order, view mode persistence                                         |
| `ReadingStatsAggregator`             | SwiftData (actor-isolated) | Reading-stats dashboard aggregator (feature #58). Sweeps `ReadingSession` + `Book` rows in one `ModelContext` pass and returns a `ReadingDashboardSnapshot` — per-window totals (today / 7d / 30d / 90d / 180d / 365d / all) + per-book breakdown. Derives every number from session rows, never from `ReadingStats`, so a stale stats cache cannot desync the dashboard. Holds a `@Sendable () -> Calendar` provider so window boundaries follow timezone/DST changes. **WI-6b**: `snapshot(window:sort:now:customRange:)` accepts an optional user-picked `ReadingStatsCustomRange` (calendar-day-inclusive `[start, end]`); when non-nil, the snapshot's `perBook` + `customRangeBreakdown` reflect that range while the seven enum totals stay populated for the pill bar |
| `CustomCoverStore`                   | JPEG files                 | Custom book cover images                                                  |
| `WebDAVClient`                       | HTTP                       | Low-level WebDAV transport (PROPFIND/PUT/GET/DELETE/MKCOL/MOVE)           |
| `WebDAVProvider`                     | `WebDAVClient`             | `BackupProvider` impl — backup/restore/list/delete over a WebDAV server   |
| `WebDAVProviderFactory`              | `WebDAVServerProfileStore`  | Assembles a `WebDAVProvider` from the active WebDAV profile (feature #52 WI-3 + WI-5). `make(persistence:profileStore:)` is the sole production path — the pre-#52 `make(keychain:)` flat-keychain variants were removed in WI-5 |
| `WebDAVServerProfileStore`           | `UserDefaults` / `KeychainService` | Actor-isolated list of saved WebDAV server profiles with one active selection (feature #52 WI-1). Profiles + active-id persist as `UserDefaults` JSON; per-profile passwords persist in Keychain. Atomic `loadSnapshot`, `upsert` / `remove` / `setActiveProfileID`, single-hop `updateIfExists`. Mirrors `ProviderProfileStore` (feature #50) for the AI multi-profile precedent |
| `WebDAVProfileMigrator`              | `KeychainService` / `WebDAVServerProfileStore` | One-shot migrator that lifts pre-#52 flat-keychain credentials (`com.vreader.webdav.{serverURL,username,password}`) into a `"Default"` profile and sets it active. Idempotent on both axes (marker key + non-empty store). Feature #52 WI-2 |
| `ReadingModeMigration`               | `UserDefaults` / per-book JSON files | One-shot **synchronous** launch migration retiring the Native/Unified reading mode (feature #54). Removes the `readerReadingMode` UserDefaults key and strips the `readingMode` field from per-book override JSON files (edited as raw `JSONSerialization` objects so other keys are semantically preserved). Synchronous-before-setup — the per-book JSON store has no actor, so a detached migration could race a panel save/restore. Idempotent |
| `BackupDataCollector`                | `PersistenceActor`         | Serializes 8 versioned JSON sections (annotations, positions, settings, library-manifest, …) |
| `BackupDataRestorer`                 | `PersistenceActor`         | Decodes + dedupes by UUID/profileKey; rejects future schema versions      |
| `BlobPath`                           | —                          | Pure utility: `(format, sha256, byteCount)` ↔ `VReader/books/<format>/<sha>_<bytes>.<ext>` (feature #46) |
| `BackupBlobStore` (protocol pair)    | —                          | Transport-neutral read (`BackupBlobReading`) + write (`BackupBlobWriting`) blob API |
| `WebDAVBlobStore`                    | `WebDAVTransport`          | Adapter that owns the temp+MOVE atomic-publication algorithm (feature #46) |
| `BookFileMaterializer`               | `BackupBlobReading` + `BookImporting` | Restore-side: download + size/SHA-256 verify + import via `BookImporter`. Preflight-rehashes existing local files to catch corrupt content (feature #46). Refactored in feature #47 WI-4a to delegate verify + import + fingerprint match to `BookFileImportFinalizer`. |
| `BookFileImportFinalizer`            | `BookImporting`            | Shared verify + import + fingerprint pipeline used by both `BookFileMaterializer` (restore-all path) and the lazy-download coordinator (feature #47 WI-4b). Streaming SHA-256 so very-large blobs don't spike memory. Caller owns temp-file lifetime. |
| `RemoteBookCatalog`                  | —                          | Pure decoder: extracts `library-manifest.json` from a backup ZIP via `ZIPWriter.extractEntry(named:from:)` and returns `[BackupLibraryEntry]`. Surfaces `manifestMissing` (older backups) / `manifestUndecodable` / `manifestSchemaVersionTooNew` as typed errors. Feature #47 WI-4a. |
| `SelectiveRestoreCoordinator`        | `BookFileMaterializer` + `PersistenceActor` + `BackupDataRestoring` | 3-phase orchestrator for the picker-driven restore: (1) preplant unselected entries as `.remoteOnly` rows, (2) materialize selected entries via `BookFileMaterializer`, (3) apply metadata sections so positions/annotations reattach to BOTH `.local` and `.remoteOnly` rows by fingerprintKey. Phase-weighted progress 0.10/0.75/0.15. Feature #47 WI-4b. |
| `LazyDownloadCoordinator`            | `BackgroundDownloadSessioning` + `PersistenceActor` | `@MainActor @Observable`. Receives forwarded events from a non-isolated `LazyDownloadDelegate` and exposes per-fingerprintKey progress + outcome state to library rows. Reattaches in-flight tasks at init via `URLSession.getAllTasks(...)` and reconciles orphaned `.downloading` rows (no live task) to `.failed`. Race-safe sticky `terminalKeys` guard outlives `clearOutcome(for:)`. Feature #47 WI-3. |
| `LazyDownloadDelegate`               | URLSessionDownloadDelegate | Nonisolated delegate that hops to MainActor via `Task` to forward `didWriteData` / `didFinishDownloadingTo` / `didCompleteWithError` / `urlSessionDidFinishEvents` events to the coordinator. Cancels orphaned tasks (missing/invalid `taskDescription`) and validates SHA/extension shape before staging. Feature #47 WI-3. |
| `LazyDownloadTaskMeta`               | —                          | `Codable Sendable` payload encoded into `URLSessionDownloadTask.taskDescription` so identity (`fingerprintKey`, `blobPath`, `expectedSHA256`, `expectedByteCount`, `originalExtension`) survives crash + relaunch. `schemaVersion` gate (`1...currentSchemaVersion`) rejects future formats. Feature #47 WI-3. |
| `BackgroundDownloadSessioning`       | `URLSession.background(...)` (production) / mock (tests) | Test seam for the background URLSession's `getAllTasks` enumeration. Production wrapper (`URLSessionBackgroundSession`) holds the live session; tests synthesize `LazyDownloadTaskDescriptor` values. Feature #47 WI-3b. |
| `WebDAVNetworkPolicy`                | `NWPathMonitor`            | `@MainActor @Observable` Wi-Fi-only gate. UserDefault `com.vreader.webdav.wifiOnly` (default true) + `currentInterface: .unknown / .none / .cellular / .wifi`. `shouldStart() -> Bool` consulted by the lazy-download enqueue path (#47 WI-4 follow-up) and "Restore all" guards. URLSession's `allowsCellularAccess = false` cancels rather than pauses, so we keep cellular allowed and gate at enqueue. Feature #47 WI-3c. |
| `FoliateURLSchemeHandler`            | WKURLSchemeHandler         | Scheme-handler implementation (not on the live load path; see Foliate-js Bridge note) |
| `FoliateMessageParser`               | Pure functions             | Parses raw JS message bodies into typed Swift events                      |
| `FoliateJSEscaper`                   | Pure functions             | Escapes/sanitizes strings for safe JS/CSS interpolation in Foliate bridge |
| `ReaderSettingsStore`                | UserDefaults               | Global reader UI prefs: theme, typography, EPUB layout, auto-page-turn, page-turn animation, Chinese conversion, custom background |
| `PerBookSettingsStore`               | Per-book JSON files        | Per-book overrides on top of `ReaderSettingsStore` (font/theme/spacing) |
| `FontSizeCalibrator`                 | Pure value type            | Maps the stored unified font-size value to a per-renderer concrete value via `FontSizeCalibrationProfile` multipliers (`txt`/`md`/`epub`/`foliate`), so the same slider number renders at a consistent perceived size across reflow formats. TXT is the `1.0` anchor; result re-clamped to each renderer's legal band (`12...64` text, `8...72` Foliate). PDF is intentionally not a target. Feature #70 |
| `KeychainService`                    | Keychain                   | Secure credential storage (used by `WebDAVProviderFactory`)               |
| `BookSourcePipeline`                 | Actor + HTTP / rule engine | Search → BookInfo → TOC → Content scraping for Legado-style web novels    |
| `SyncService`                        | CloudKit (feature-flagged) | Coordinates sync with `SyncConflictResolver`, tombstones, change tokens   |
| `DebugBridge`                        | URL handler (DEBUG-only)   | `vreader-debug://` reset/seed/open/settle/snapshot/eval/tts/search/highlight/provider/present/ai/seed-sessions/seek/scroll-sheet/navigate/scroll-boundary/locate?highlight=N; feature #49 added position-aware open + DebugSnapshot schema v2 (TTS state, render phase, settings provenance); feature #74 added `locate?highlight=<N>` to drive `.readerNavigateToLocator` for the active TXT/MD reader CU-free so the locate "bloom" (highlight/note landing) fires on the real render path, plus DebugSnapshot schema v3 (`landingBloomCount` / `landingBloomPeakIntensity`) read back from `HighlightableTextView`'s persisted bloom counters — the ~1.5s sub-second bloom visual can't be screenshot/video-captured on the virtual display, so the snapshot proves it fired; feature #45 WI-4c-b added `tts?action=start\|stop` to bypass XCUITest's audio-session block; bug #238 added `search?query=...[&index=N]` to drive search-result-tap repros (Bug #182 / GH #621) CU-free; bug #237 added `highlight?start=...&end=...[&color=...]` for TXT/MD highlight creation CU-free; bug #243 added `provider?action=add\|remove\|clear` for AI provider configuration without driving Settings → AI through CU (unlocks Feature #56 b/d / Feature #65 / Feature #69 / Bug #93 autonomous AI verification); bug #253 added `present?sheet=...[&tab=...]` + bug #255 added `ai?action=summarize\|chat\|translate` for CU-free reader-sheet + AI-response-card verification; bug #263 added `seed-sessions?book=<key>[&seconds=<n>]` to seed a deterministic `ReadingSession` spread (one per dashboard window band) so the reading-stats dashboard (Feature #58) renders non-zero per-window totals CU-free; bug #267 added `seek?fraction=<0...1>` to drive the active Foliate (AZW3/MOBI) reader to a fractional position CU-free; bug #271 added `scroll-sheet?to=top\|bottom` to scroll the active presented sheet's content (today `TranslationResultCard`) so the accent translation card below the tall ORIGINAL card — beyond even the `detent=large` fold (Bug #256) — becomes screenshot-capturable, unblocking Feature #65 row 11; bug #273 added `navigate?spine=<N>[&fraction=<F>]` to drive `.readerNavigateToLocator` for the active EPUB reader CU-free (the `search` driver doesn't navigate in continuous mode), posting DEBUG-only `.debugBridgeNavigateCommand` → `EPUBReaderContainerView` resolves spine → href → `Locator` → re-posts `.readerNavigateToLocator` — unblocking feature #71 WI-8 continuous-mode navigation verification (paired with the `multi-chapter-epub` 4-tall-chapter fixture for the out-of-window rebuild branch); a follow-up added `scroll-boundary?spine=<N>&near=top\|bottom` to post a DEBUG-only `.debugBridgeScrollBoundaryCommand` → `EPUBReaderContainerView` builds an `EPUBScrollBoundarySignal` and calls `EPUBContinuousScrollCoordinator.handleBoundarySignal` directly — bypassing the rAF-throttled `continuousScrollObserverJS` (unverifiable CU-free on a virtual display) so feature #71's scroll-driven extend/evict RESPONSE can be device-verified. **Host-vs-runner driving constraint (bug #242 / GH #1054)**: bridge URLs MUST be invoked from the host (`xcrun simctl openurl` outside any iOS sandbox) — invoking them from inside an XCUITest binary fails with NSPOSIX 61 because the runner sandbox blocks the CoreSimulatorService XPC endpoint. In-runner verification flows use `XCTSkipUnless(bridgeReachable())` (PR #1053) when they cannot move the bridge-dependent assertion to a host-side driver. See `docs/subsystems/debug-bridge.md` § "Driving the bridge from a verification flow". |
| `DebugPositionResolver`              | —                          | Pure parser: `?position=<value>` string → typed `DebugPosition` per BookFormat (TXT/MD UTF-16 offset, EPUB CFI, AZW3 Foliate-CFI, PDF page). Every format takes its native seek path (feature #54 retired the Native/Unified mode + its position-unsupported guard). Feature #49 WI-7a. |
| `DebugReaderRegistry.awaitReader`    | DebugReaderRegistry singleton | Token-based keyed waiter that resumes when a reader matching `fingerprintKey` registers. Concurrent waiters with different timeouts each get their own continuation (UUID-token ownership). Feature #49 WI-7a. |
| `DebugReaderRegistry.awaitReaderSettled` | DebugReaderRegistry singleton (`+Settle` extension) | Bug #141: render-settled signal keyed by `(fingerprintKey, token)`. Hosts call `markReaderSettled` on real render-complete — EPUB from `webView(_:didFinish:)`, AZW3/MOBI from the Foliate `relocate` message. `ReaderContainerView` wires `probe.settleStrategy` so `vreader-debug://settle` blocks until that signal (or `settleTimeout`) instead of the 100ms placeholder. TXT/MD/PDF keep the placeholder. Same UUID-token waiter machinery + stale-write guard as `awaitReader`. |
| `ImportJobQueue`                     | Actor                      | Serializes book imports (avoids parallel `BookImporter` writes)           |
| `FileURLImportRouter`                | `BookImporting` (protocol) | `@MainActor` dispatcher for incoming `file://` URLs from iOS Share Sheet / "Open in vreader" (Feature #59 WI-2). Wired by `VReaderApp`'s production `.onOpenURL`. Returns `false` for non-file URLs (Debug-bridge handler intercepts those upstream). Unsupported extensions reported via injected closure (App layer wires the user-facing alert; current production wiring is a no-op). Supported extensions kick off `bookImporter.importFile(at:source:.shareSheet)` in a fire-and-forget Task. Security-scope handling owned by `BookImporter`, not the router. |
| `LibraryRefreshService`              | NotificationCenter         | Coalesces library refresh requests across views                           |
| `FeatureFlags`                       | Static                     | Compile/runtime flag resolution (`SyncService` and others gate on it). Feature #91 added `agenticTools` (default OFF, persisted) — gates the AI chat's agentic tool-calling loop |
| `DictionaryLookup`                   | UIKit                      | System dictionary + AI-translate hooks for selected text                  |
| `DiagnosticsLogStore` + `OSLogDiagnosticsSource` + `DiagnosticsRedactor` (`Services/Diagnostics/`) | `OSLogStore` (current-process) | **Feature #96 — in-app runtime diagnostics.** `DiagnosticsLogStore` (`@MainActor @Observable`) reads the current session's `com.vreader.app` `Logger` entries back via the `DiagnosticsLogSource` seam (`OSLogDiagnosticsSource` runs the blocking `OSLogStore` enumeration off-main), holds them bounded, filters by level/category, and produces a `DiagnosticsRedactor`-scrubbed export string. `DiagnosticsRedactor` is a pure, context-driven secret/path scrubber (Authorization, keyed secrets, `sk-`/JWT keys, URL creds, container paths) — the defense-in-depth second line over OSLog's `.private` barrier for anything leaving the app (export file + Copy-entry). WI-2 added the Settings → Support → Diagnostics viewer (`Views/Settings/Diagnostics/`) binding to the store |
| `ChapterTranslationStore`            | SwiftData (actor-isolated) | Persistent disk cache for feature #56 bilingual reading. Wraps its own `ModelContext` over the `ChapterTranslation` `@Model` (SchemaV7) — a separate actor from `PersistenceActor` so bulk translation writes during a global-translate run never block library reads. App-scoped `.shared` single instance (the `ProviderProfileStore.shared` precedent); idempotent `upsert` fetches by `lookupKey` and updates in place, never relying on the unique constraint to throw. Returns the value-type `ChapterTranslationRecord` DTO, never the `@Model`. Bug #342: lazily migrates pre-#342 5-field keys (profile UUID baked in) to the canonical 4-field key on first access, deduping to the newest row. The cache is derived, re-fetchable data — excluded from WebDAV backup |
| `ChapterTranslationService`          | `ChapterTranslationStore` + `AIService` | Translates one chapter unit for feature #56 bilingual reading. Pipeline: cache lookup → (on miss) `ChapterSegmenter` → `ChapterTranslationChunker` → one `AIService.sendRequest(_:using:)` per chunk → strict `TranslationChunkContract` JSON-array decode → per-segment fallback on any decode/count/element mismatch → recombine → cache-write. Reaches the AI side through the `TranslationRequestSending` boundary protocol (tests inject a mock). `Task.checkCancellation()` between chunks so a cancelled prefetch stops promptly |
| `ChapterTextProviding` (`Services/Reader/`) | per-format reader services | Feature #56 WI-2.5 boundary protocol — supplies a book's translation units (`translationUnits()`), per-unit plain source text (`sourceText(for:)`), and the `Locator → unit` resolution (`unit(containing:)` / `unit(after:)`) the bilingual prefetch trigger needs. The translation *unit* is the format's natural rendering segment, not the logical TOC chapter (plan Decision 2.7). Four concrete `Sendable` `struct` adapters: `EPUBChapterTextProvider` (spine documents, HTML-stripped via `EPUBTextExtractor`), `TXTChapterTextProvider` (`TXTChapterIndex` chapters, UTF-16 slicing), `MDChapterTextProvider` (`MDHeading`-bounded chapters), `PDFChapterTextProvider` (page ranges via PDFKit). The AZW3/MOBI `FoliateChapterTextProvider` (an `actor`, bridges the `@MainActor` Foliate coordinator via the `FoliateSectionExtracting` facade) lands in WI-11. `ChapterTranslationService` / `BookTranslationCoordinator` consume this boundary, never a format-specific extractor |
| `FoliateChapterTextProvider` (`Services/Reader/`) | `FoliateSectionExtracting` | Feature #56 WI-11 — AZW3/MOBI `ChapterTextProviding` adapter. The odd one out: an `actor` (not a `struct`) because the live Foliate seam (`FoliateSpikeView.Coordinator` + `WKWebView`) is `@MainActor`. Stores an `any FoliateSectionExtracting` and reaches it via `await`; an `actor` is `Sendable` by construction so it satisfies `ChapterTextProviding: Sendable` without `nonisolated(unsafe)`. Caches the ordered section-id list on the first `translationUnits()` call; a book reopen rebuilds the provider from scratch so the cache never goes stale within one open book |
| `FoliateSectionExtracting` (`Services/Reader/`) | `FoliateSpikeView.Coordinator` (extension) | Feature #56 WI-11 — `@MainActor protocol` bridging the live Foliate per-section text extraction seam (the `readerAPI.bilingualSectionIDs` / `readerAPI.bilingualSectionText` JS calls) into the `Sendable` `ChapterTextProviding` boundary. Class-bound + `Sendable` + `@MainActor` means a `@MainActor`-isolated `AnyObject` existential is safely `Sendable` (members are main-actor-isolated), so the `FoliateChapterTextProvider` actor can hold a single live reference without an unsafe escape hatch |
| `ChapterPrefetching` (`Services/AI/`) | `BilingualReadingViewModel` | Feature #56 WI-7b seam — `translatedSegments(for:targetLanguage:granularity:)`, the single-method translation-prefetch boundary `BilingualReadingViewModel`'s unit-aware prefetch trigger depends on. Decouples the view model from provider resolution / the disk cache / chunking; production wires a thin adapter over `ChapterTranslationService` + `AIService`, tests inject a deterministic mock |
| `ChapterTranslationPrefetcher` (`Services/AI/`) | `ChapterTranslationService` + `AIService` + `ChapterTextProviding` | Feature #56 WI-10 production `ChapterPrefetching` adapter. `Sendable` `struct` per open book. Each `translatedSegments(...)` call consults the disk cache FIRST (profile-free — Bugs #306/#342: a cached chapter renders with no/any provider), then resolves the active provider config once — a profile flip during a chapter prefetch does not split chunks across providers. Pulls per-unit source text from the injected `ChapterTextProviding` and routes the request through `ChapterTranslationService.translate(...)`. Default style is `.natural`; the re-translate picker (WI-15) is the only path that overrides it |
| `BackgroundExecutionToken` (`Services/`) | `UIApplication` (via `BackgroundTaskRequesting`) | Feature #98 grace-window handle over `beginBackgroundTask`/`endBackgroundTask` behind the `BackgroundTaskRequesting` protocol seam (production = `UIApplication`, tests = recorder). `@MainActor` class; explicit `end()` is the contract (idempotent; `deinit` only DEBUG-logs leaks); the expiration handler strongly captures a shared end-state so even a leaked token self-ends at expiry; `.invalid` (iOS denied time) degrades to a no-op. Ships with `BackgroundExpiryLatch` — a lock-backed one-way latch the `@MainActor` expiry handler sets synchronously and the whole-book job loop reads between units. Consumers: `ChapterReTranslateViewModel.submit()` (one token per re-translate) and `BookTranslationCoordinator` (token renewed per translated unit; expiry → clean between-units stop with the `.failed` phase, completed units cached as the resume checkpoint) |
| `BookTranslationCoordinator` (`Services/AI/`) | `ChapterTranslationService` + `ChapterTranslationStore` + `ChapterTextProviding` | Feature #56 WI-14 actor driving the "translate entire book" flow. App-scoped `.shared` instance (configured at `VReaderApp.init`). `start(...)` spawns a background task that iterates `ChapterTextProviding.translationUnits()`, skips units already covered in `ChapterTranslationStore.cachedUnits(...)`, hands each remaining unit to `ChapterTranslationService.translate(...)`, and emits monotonic `BookTranslationProgress` snapshots through an `AsyncStream` (`progressUpdates(forBookWithKey:)`). At most one running job per book — a second `start` for the same book is a silent no-op. `cancel(_:)` stops between units; `cancelAndPurge(_:)` additionally wipes the book's cache rows for the user-delete-book path (plan edge case (g)). Posts `.readerBookTranslationProgressDidChange` on every snapshot so a reader open on the book drives its `ReaderTranslateBanner`. Feature #98: renews a `BackgroundExecutionToken` per translated unit; on OS expiry stops cleanly BETWEEN units (`.failed` phase = the designed PAUSED rendering) and persists an `InterruptedTranslationJob` descriptor (`{v, bookKey, targetLanguage, style, providerProfileID}` in UserDefaults via `InterruptedTranslationJobStore`); `resumeInterruptedJob(bookFingerprintKey:textProvider:)` — triggered by the reader container's provider-arrival handler — re-resolves the PERSISTED profile through the `ProviderConfigResolving` seam (`AIService` conforms) and re-enters `start` (cached units skip = resume); descriptor cleared on completion / user cancel / book delete, retained on provider failure |
| `BookTranslationViewModel` (`ViewModels/`) | `BookTranslationCoordinator` | Feature #56 WI-14 `@MainActor @Observable` UI-facing state for the translate-entire-book flow. Drives the confirm alert (`presentConfirm` loads `estimate` + shows alert), the status sheet (`startObserving` subscribes to the coordinator's progress stream and mirrors snapshots into `progress`), and the cancel alert (`requestCancel` opens the confirmation, `confirmCancel` propagates to the coordinator). One per surface (Book Details, library card, reader chrome); multiple VMs for the same book observe the same coordinator job |
| `ChapterReTranslateViewModel` (`ViewModels/`) | `AIService` + `ChapterTranslationService` + `ChapterTranslationStore` | Feature #56 WI-15 `@MainActor @Observable` UI-facing state for the per-chapter re-translation flow. `presentPicker(...)` opens `ReTranslatePickerSheet` with the chosen unit + title + target language; `updateSelection(_:)` mutates the picker's `(providerProfileID, model, style, keepGlossary)` selection; `submit()` resolves the picker's `ResolvedAIProviderConfig` through the `RetranslateProviderResolving` boundary (`AIService` conforms), runs the translation through `ChapterReTranslating` (`ChapterTranslationService` conforms, with the cache READ bypassed so a fresh row can't no-op the re-translate — Bug #341 atomic swap + Bug #342 canonical key: the cache-write replaces the ONE `book|unit|lang|prompt` row in place, the original translation survives every failure/cancel path, and an override re-translation is readable by bilingual mode on reopen), and fires `onTranslationApplied` so the host posts `.readerBilingualReTranslateApplied`. Picker override never mutates `ProviderProfileStore` (acceptance criterion (f)) |
| `EPUBBilingualPipeline` (`Views/Reader/Bilingual/`) | `EPUBBilingualJS` + `EPUBBilingualOrchestrator` | Feature #56 WI-10 pure glue between the EPUB WKWebView's `bilingualEnumerate` message payload and the `BilingualReadingViewModel`'s `translationsByUnit` cache. `parseEnumeratePayload(_:)` decodes the raw `Any` body into an `EPUBBilingualEnumeratePayload` (`{requestedSectionIndex, blocks}`) — accepting BOTH the paged bare-array shape (`[{bid,text}]`, no section identity) and the continuous-scroll envelope (`{sectionIndex, blocks}`); the envelope preserves the section identity on an EMPTY result so the container clears ONLY that section's bucket instead of every bucket (Feature #71 WI-7 Gate-4 round-3 MEDIUM 1). `parseEnumerateMessage(_:)` is the flat-`[BilingualBlock]` convenience over it; `translationsByBid(blocks:translatedSegments:)` maps the VM's ordered segment array onto a `[bid: text]` lookup by position. No `@MainActor` — pure value transforms |
| `EPUBBilingualOrchestrator` (`Views/Reader/Bilingual/`) | `EPUBBilingualJS` + `EPUBBilingualPipeline` | Feature #56 WI-10 host-side `@MainActor @Observable` controller, one per open EPUB. Holds the current chapter's `[BilingualBlock]` list; emits enumerate / inject / clear JS for the bridge to evaluate. Stateless beyond the block list — the container drives transitions via `enumerateJS()` on `didFinish`, `updateBlocks(_:)` on the enumerate callback, `buildInjectJS(translatedSegments:)` when the VM's prefetch lands, and `clearJS()` on disable / chapter swap |
| `FoliateBilingualPipeline` (`Views/Reader/Bilingual/`) | `FoliateBilingualJS` + `FoliateBilingualOrchestrator` | Feature #56 WI-11 — AZW3/MOBI sibling of `EPUBBilingualPipeline`. Same two static functions (`parseEnumerateMessage(_:)`, `translationsByBid(blocks:translatedSegments:)`) with the same shapes; reuses the `BilingualBlock` value type so the enumerate → translate → inject contract is byte-identical across formats. Independent file so format-specific test invariants don't cross-contaminate |
| `FoliateBilingualOrchestrator` (`Views/Reader/Bilingual/`) | `FoliateBilingualJS` + `FoliateBilingualPipeline` | Feature #56 WI-11 — AZW3/MOBI sibling of `EPUBBilingualOrchestrator`. `@MainActor @Observable` controller, one per open AZW3/MOBI book. Owned by `FoliateBilingualContainerView`; emits enumerate / inject / clear JS that the container posts through `.foliateRequestBilingualEvalJS` for the live `FoliateSpikeView.Coordinator` to evaluate against its `WKWebView` |
| `FoliateBilingualContainerView` (`Views/Reader/`) | `FoliateSpikeView` + `FoliateBilingualOrchestrator` + `BilingualReadingViewModel` + `FoliateChapterTextProvider` | Feature #56 WI-11 — AZW3/MOBI host wrapper that adds the bilingual VM / orchestrator / setup-sheet wiring around the unchanged `FoliateSpikeView`. Owns the bilingual `@State`, the first-enable `BilingualSetupSheet`, and the notification plumbing (`.readerMoreBilingual` → toggle, `.foliateSectionLoaded` → enumerate, `.foliateBilingualBlocksEnumerated` → cache + prefetch, `.readerBilingualDidChange` → inject) that mirrors `EPUBReaderContainerView+Bilingual` for the live Foliate path |
| `BilingualDisplaySegmentMap` (`Services/Reader/`) | `BilingualTextRenderer`, `TXTReaderContainerView`, `MDReaderContainerView` | Feature #56 WI-12a pure `Sendable` value type — the TXT/MD source↔display UTF-16 offset map. Records ordered display segments tagged `.source(sourceRange:displayRange:)` or `.synthetic(displayRange:)`. `sourceOffset(forDisplayOffset:)` returns `nil` for synthetic ranges or out-of-bounds offsets; `displayOffset(forSourceOffset:)` clamps a past-end source position to display end. `identity(sourceLength:)` builds the 1:1 pass-through used when bilingual is off. WI-12b consumes the map in TXT/MD container offset-routing |
| `BilingualTextRenderer` (`Views/Reader/Bilingual/`) | `BilingualDisplaySegmentMap` | Feature #56 WI-12a pure interlinear builder for TXT/MD. `render(sourceText:sourceParagraphRanges:translatedSegments:)` returns the rendered `NSAttributedString` (source paragraphs interleaved with synthetic translation runs, each carrying the `decorationAttributeKey` attribute) plus the matching `BilingualDisplaySegmentMap`. Nil or empty translations fall back to source + identity map. Partial translations inject the prefix and leave the tail source-only (plan Decision 2's silent-source-fallback). WI-12b wires the renderer's output into the live TXT/MD UITextView |
| `BilingualParagraphRanges` (`Services/Reader/`) | `BilingualTextRenderer`, `BilingualDisplayPipeline` | Feature #56 WI-12b — pure paragraph-range scanner that splits a TXT/MD chapter's source text into UTF-16 paragraph ranges. Blank-line-separated content lines fuse into one paragraph (matches reflow conventions); blank lines + leading/trailing whitespace are excluded from ranges. Feeds the interlinear renderer's `sourceParagraphRanges` argument. Pure O(N) UTF-16 single-pass — covers CRLF / CJK / interspersed-blank-line edge cases |
| `BilingualAttributedStringComposer` (`Views/Reader/Bilingual/`) | `BilingualDisplaySegmentMap`, `BilingualTextRenderer` | Feature #56 WI-12b — typography-preserving interlinear composer. `compose(sourceAttributed:sourceParagraphRanges:translatedSegments:)` takes an already-typographed source `NSAttributedString` (font, line spacing, drop-cap, heading restyle) and interleaves synthetic translation runs at paragraph boundaries. Synthetic runs inherit the prior source paragraph's attrs + carry the `decorationAttributeKey`. Used by TXT's chapter-paged path so the chapter-start drop-cap + heading restyle survive the bilingual interleave |
| `BilingualDisplayPipeline` (`Views/Reader/Bilingual/`) | `BilingualTextRenderer`, `BilingualAttributedStringComposer`, `BilingualReadingViewModel` | Feature #56 WI-12b — `@MainActor` bridge between the bilingual VM state and the renderer/composer. `makeDisplay(...)` builds a fresh attrString from a plain `String` source; `compose(sourceAttributed:...)` preserves an upstream typographed attrString. Both off-path (no VM / disabled / no unit / no cached translation) returns the source + identity map — the byte-identical pass-through that gates the R-TXT-offsets risk |
| `BilingualOffsetRouter` (`Views/Reader/Bilingual/`) | `BilingualDisplaySegmentMap` | Feature #56 WI-12b — pure source↔display offset router for the TXT/MD container's bilingual surfaces. Helpers: `displayOffset(forSourceOffset:map:)`, `sourceOffset(forDisplayOffset:map:)`, `displayRange(forSourceRange:map:)` (segment-union projection — a source range that crosses an intervening synthetic block produces a spanning display range), `displayNSRange(forSourceNSRange:map:)`, `isSynthetic(displayOffset:map:)`. Identity-map mode is byte-identical to today's offset code |
| `BilingualTXTBridgeDelegateAdapter` (`Views/Reader/Bilingual/`) | `BilingualDisplaySegmentMap`, `TXTTextViewBridge` | Feature #56 WI-12b — `@MainActor` delegate wrapper that maps display-domain offsets the bridge reports (selection range, top-visible-char scroll offset) back to source-domain offsets via `BilingualOffsetRouter`, so the TXT VM keeps persisting positions in document source coordinates with bilingual on. A selection that starts inside a synthetic translation run is dropped; a scroll-into-synthetic projects to the end of the preceding source segment. Identity map (bilingual off) is a transparent pass-through |
| `TXTLoaderBackedChapterTextProvider` (`Services/Reader/`) | `ChapterTextProviding`, `TXTChapterContentLoader` | Feature #56 WI-12b — chapter-paged-mode `ChapterTextProviding` adapter that reads each chapter on demand via the live reader's `TXTChapterContentLoader` actor. Sibling to `TXTChapterTextProvider` (full-book-slicing). Re-enables bilingual mode for chapter-paged TXT, the mode WI-12a's `makeTextProvider` explicitly disabled because the VM's `textContent` is chapter-local in that mode |
| `PDFBilingualPanel` (`Views/Reader/Bilingual/`) | `PDFBilingualPanelState`, `BilingualLanguage`, `ReaderThemeV2` | Feature #56 WI-13 — PDF below-page bilingual translation panel. Stateless SwiftUI sub-view rendering the design's split-layout A1..A8: header (lang-glyph chip + page label + status suffix + chevron) + body switched on `PDFBilingualPanelState` (5 states: `.off` / `.loading` / `.translated([String])` / `.offline` / `.empty`). PDF is fixed-layout so the paragraph-interlinear renderer used by EPUB/Foliate/TXT/MD doesn't apply; the panel below the page is the entire user-visible bilingual surface for PDF. 260pt expanded / 38pt collapsed; attached to `PDFViewBridge` via SwiftUI's `.safeAreaInset(edge: .bottom)` so PDFKit's `autoScales` reflows the page rendering automatically |
| `PDFBilingualPanelState` (`Views/Reader/Bilingual/`) | `BilingualReadingViewModel`, `PDFChapterTextProvider` | Feature #56 WI-13 — pure synchronous derivation of the panel's 5-state matrix from the bilingual VM + the PDF's `(currentPage, pagesPerUnit, totalPages)` triple. Computes the current `TranslationUnitID` synchronously (mirrors `PDFChapterTextProvider.pageRanges` arithmetic) instead of reading the VM's async-updated `lastTriggerUnit`, so page-turn-in-flight doesn't flash stale translations (Gate-2 v5 round-1 H1). `.empty` keyed on "translated segments empty after fetch" OR "totalPages <= 0", NOT `unit == nil` (which would never fire for a real PDF — Gate-2 v5 round-1 M1) |
| `PDFReaderContainerView+Bilingual` (`Views/Reader/`) | `BilingualReadingViewModel`, `PDFChapterTextProvider`, `PDFBilingualPanel`, `PDFBilingualPanelState` | Feature #56 WI-13 — PDF host extension owning the bilingual VM lifecycle (lazy construction gated on `viewModel.isDocumentLoaded` + `totalPages > 0`), the `PDFChapterTextProvider` build, the prefetcher build (mirrors TXT/EPUB `makePrefetcher`), the first-enable setup sheet, the More-menu toggle observer, the retry observer (`.readerBilingualRetry`), and the `.safeAreaInset`-attached panel. On reopen of an already-enabled book, `ensureBilingualViewModel` kicks the initial `handlePositionChange` so the panel doesn't stick in `.loading` for the open page (Gate-4 round-1 H1). Mirrors `TXTReaderContainerView+Bilingual` / `MDReaderContainerView+Bilingual` / `EPUBReaderContainerView+Bilingual` structurally |

### 6. Data Layer (`vreader/Models/`)

SwiftData SchemaV10 entities (V9→V10 adds the additive optional `Book.sourceCanonicalKey: String?` — feature #108's converted-Kindle cross-platform identity, carried in the backup manifest; feature #109's NFC locator-key recompute runs as the launch-time `LocatorKeyBackfillMigration`, not a schema migration — see the App Layer note above):

- `Book` (fingerprintKey unique; gains `originalExtension: String?` in SchemaV5 for backup blob extension preservation; gains `fileState: String` and `blobPath: String?` in SchemaV6 for feature #47's lazy-load row state; gains `sourceCanonicalKey: String?` in SchemaV10 — feature #108's converted-Kindle source-bytes cross-platform identity, while the converted-EPUB `fingerprintKey` stays the local primary) → `ReadingPosition` (gains `vreaderLocatorData: Data?` in SchemaV8 — feature #42's engine-agnostic `VReaderLocator` envelope, stored as raw JSON `Data?` mirroring `Highlight.anchorData`; additive/optional → lightweight migration, no stage), `Highlight`, `Bookmark`, `AnnotationNote`, `BookCollection`, `ChatSession` (SchemaV9 cascade child)
# 47 — Feature Implementation Workflow

Binding sequence for every feature implementation. Six gates, never skip one.

> **Plan → Independent plan audit → TDD implementation → Implementation audit loop → Device/integration verification → Merge**

This is a **gate model**, not a chronological task list. Each gate has an explicit acceptance bar; you do not enter the next gate until the current gate's bar is met. Multiple iterations within a gate are normal.

## Gate 1 — Plan

Write `dev-docs/plans/YYYYMMDD-feature-N-<slug>.md` covering, at minimum:

- **Problem** — what user need this addresses (mirror or refine the row's `Problem` field).
- **Surface area** — file-by-file with concrete signatures (which protocols, types, methods get added or modified). Includes a "files OUT of scope" subsection.
- **Prior art / project precedent / rejected alternatives** — what existing patterns we're building on, what we considered and rejected, and why. **Research is part of the plan**, not a separate step.
- **Work-item sequencing** — small, testable units (typically 1-15 WIs). Each WI is one PR's worth of work. Estimated PR size per WI.
- **Test catalogue** — concrete test files, what each covers, including the audit-driven additions (corruption, partial failure, idempotency edge cases).
- **Risks + mitigations** — known unknowns and how we'll handle them.
- **Backward compat** — what happens to existing data / older clients / older backups when this ships.

The features.md "Plan Template" fields (Problem, Scope, Edge Cases, Test plan, Acceptance criteria) live in the row; the implementation-detail plan in `dev-docs/plans/` expands on them with file paths, signatures, and sequencing.

**Acceptance bar**: plan exists at the documented path; status moves to `PLANNED` only when this gate passes.

## Gate 2 — Independent Plan Audit

Send the plan to an independent AI auditor (not the same agent/model/context as the plan author). cc-suite (driving Codex via `codex exec`) is the current default; Gemini, OpenCode, or any equivalent satisfies the gate. The invariant is **independence**, not the brand.

Audit prompt must explicitly request:

- **Model assumption verification** — do the SwiftData fields, enum cases, function signatures, file paths I named actually exist? (This catches the largest class of pre-implementation bugs.)
- **Risks + missing edge cases** — what failure modes the plan misses.
- **Protocol signature critique** — are new interfaces well-shaped, or do they leak implementation concerns?
- **Concurrency hazards** — actor isolation, Sendable, race conditions in mutable state.
- **Cohesion check** — is the WI split right, or are some WIs too big or too small?

**Acceptance bar**:

- Zero open Critical/High/Medium findings.
- Low findings either fixed in the plan or explicitly accepted with rationale (in the plan's "Known limitations" or "Audit fixes applied" section).
- **Maximum 3 audit rounds**. If unresolved findings remain after round 3, stop and escalate to the user — accept, defer, or redesign.

Track audit rounds in the plan's revision history. The author rewrites the plan to address findings; the auditor re-reviews. Same loop until clean.

**Why this gate exists**: Codex audits routinely catch 5-10 real bugs per round on non-trivial plans (compile-breaking model assumptions, missing preconditions, protocol shape mistakes). Skipping the audit shifts that cost into wasted implementation work.

## Gate 3 — TDD Implementation

Per work item:

1. **RED** — write a failing test that captures the WI's behavior. See `.claude/rules/10-tdd.md` for pattern catalogue.
2. **GREEN** — write minimal implementation to make the test pass.
3. **REFACTOR** — clean up without changing behavior. Tests stay green.
4. **PR** — small, focused PR per WI. Apply per-PR rules: docs sync (`24-doc-sync.md`), version bump (`40-version-bump.md`).

Status: feature → `IN PROGRESS` when WI-1's PR opens.

**Acceptance bar per WI**: tests pass under `xcodebuild test -only-testing:vreaderTests`; new code follows codebase conventions (`.claude/rules/50-codebase-conventions.md`).

## Gate 4 — Implementation Audit Loop

After implementation but before merge: independent audit of the changed files (read-only sandbox). This is what `/fix-issue` already runs.

Audit prompt focuses on:

- Correctness against the plan
- Edge cases in the diff (boundary conditions, nil, Unicode/CJK, concurrent access)
- Security (JS injection in evaluateJavaScript, WKWebView bridge safety, etc.)
- Duplicate / dead code introduced
- VReader compliance (Swift 6 concurrency, @MainActor correctness, file size <300 lines)
- Bridge safety (FoliateJSEscaper for JS interpolation, message parser edge cases)

**Acceptance bar**:

- Zero open Critical/High/Medium findings.
- Low findings fixed or explicitly accepted with rationale in the PR body.
- **Maximum 3 audit-fix rounds**. After round 3, escalate.

Same author/auditor separation as Gate 2.

## Gate 5 — Device / Integration Verification

For each PR before it merges:

- **Foundational WIs** (DTOs, protocols, utilities, pure types — no user-observable behavior): unit + integration tests + audit are sufficient. No device verification required.
- **Behavioral WIs** (anything that changes app behavior, persistence, networking, backup format, reader rendering, or UI flow): **slice verification** — exercise the slice end-to-end against the real environment available at this point. Run on iPhone 17 Pro Simulator with `vreader-debug://` harness; for backup/network features, against a real WebDAV server (or local Docker WebDAV equivalent); for reader features, with a fixture book.
- **Final WI** (the one that completes the feature): full end-to-end acceptance pass — every acceptance criterion exercised. This is what flips the feature row from `DONE` to `VERIFIED`.

Record slice verification in the PR description (what was run, what was observed). Record final acceptance verification in a structured evidence file at `dev-docs/verification/feature-<id>-<YYYYMMDD>.md` per the schema in `dev-docs/verification/SCHEMA.md`. The PreToolUse hook `.claude/hooks/check_terminal_status_evidence.sh` blocks any tracker edit that flips a row to `VERIFIED` (features) or `FIXED` (bugs) without a matching evidence file.

**Android tier (feature #107)** — the platform-router (`code_paths_platform`) picks the lane:
- **iOS WIs**: iPhone 17 Pro Simulator + `vreader-debug://` harness, as above.
- **Android WIs** (`android-app` / `android-spike`): verify on a booted **Android emulator** (AVD, android-35+) via `scripts/run-android-verify.sh` (the emulator analog of driving the simulator — rule 49/52/53). The CU-free instrumentation lane is the Spike-B `am instrument` pattern (#104/#105 precedent); the evidence file's `device_or_simulator` records the AVD (e.g. "Pixel 7 API 35 emulator"). Until #106's app shell exists, the only Android target is the `spikes/` harness, so Android-app Gate-5 is itself blocked on #106; pre-#106 Android work is spike/tooling (no device-verify, like a foundational WI).
- **Shared WIs** route to the iOS lane (rule 40 — shared is iOS while Android is pre-foundation).

**Acceptance bar per PR**: every behavioral slice in the PR has been verified end-to-end at the level appropriate to its WI tier. Final WI requires full acceptance pass + evidence file.

**"Tooling unavailable" is NOT an acceptable deferral reason** unless a specific tool is named and confirmed missing (e.g., `xcrun simctl` returns "command not found", a real device is required and none is connected, the rclone WebDAV server is down). "I'll do it next session" is not a tool-unavailability claim — it's a discipline lapse. The Stop hook (`.claude/hooks/check_unfinished_verification.sh`) surfaces unverified `DONE` rows at session end so the gap doesn't quietly carry over.

## Gate 6 — Merge

PR may merge when ALL of the following hold:

- Tests pass (the merge gate from `AGENTS.md`).
- Implementation audit loop is clean (Gate 4).
- Device / integration verification is complete for the PR's tier (Gate 5).
- Docs sync completed if triggered (`.claude/rules/24-doc-sync.md`).
- Version bump committed as the last commit before opening the PR (`.claude/rules/40-version-bump.md`).
- For PRs that reference an open bug/feature: the referenced row has reached its terminal status (`FIXED` for bugs, `DONE` for features) — the existing fix-or-implement merge gate.

After merge:

- Feature status moves to `DONE` only after **all** WIs are merged AND every acceptance criterion is implemented.
- `VERIFIED` is a separate post-implementation status, set after Gate 5's final-WI acceptance pass lands and is recorded in the row. Requires a `dev-docs/verification/feature-<id>-<YYYYMMDD>.md` evidence file (PreToolUse hook enforces).
- GH issue closes per close-gate rule (closure comment cites the verification: commit SHA + what was tested + what was observed).

## Gate progress is recorded in the GH issue (binding)

The GH issue mirror is not just a creation-time pointer — it is the **running record** of the feature's path through the six gates. Once the issue exists (created at the Gate 2 → `PLANNED` flip), every gate transition posts a short, append-only comment so the issue reads as a verifiable timeline of the workflow. A reviewer who only sees GitHub can then audit gate compliance without cloning the repo.

Post one comment at each of these transitions:

| Transition | Comment records |
| --- | --- |
| Gate 2 passes (issue just created) | plan path + audit verdict (Codex threadId + rounds, or `manual-fallback`) + the WI list with foundational/behavioral tiers |
| Each WI's PR merges (Gate 6) | WI number + tier, PR number, version bumped to, merge-commit SHA, Gate 4 audit verdict, Gate 5a slice result |
| Final WI merges → row `DONE` | "shipped in vX.Y.Z (commit `<sha>`), awaiting verification" — this is the existing close-gate comment |
| Gate 5b acceptance pass → row `VERIFIED` | evidence-file path + `result:` + a one-line acceptance-criteria summary — this is the existing closure comment, posted just before `gh issue close` |

Rules for these comments:

- **Append-only, short, factual.** Paths, SHAs, verdicts, version numbers — not prose. One comment per transition; do not edit prior comments.
- **The markdown artifacts stay the source of truth.** The `dev-docs/plans/` plan, the `.claude/codex-audits/` logs, `docs/features.md`, and the `dev-docs/verification/` evidence file are authoritative. The issue comments are a timeline that *points at* them; never copy a plan's full contents into the issue.
- **A skipped comment is a gate-process lapse, not a hard-blocked one.** No hook enforces these (they are post-action `gh issue comment` calls), so the discipline is the gate. If a transition happened without its comment, back-fill it before the next transition.

The two bottom rows already exist in the close-gate / finalizer flow; this rule adds the Gate-2 and per-WI-merge rows so the *middle* of the workflow is visible on GitHub, not just its endpoints.

## Audit count by feature size

To keep the audit cost honest:

| Size   | WIs     | Plan audits             | PR audits                                                                               |
| ------ | ------- | ----------------------- | --------------------------------------------------------------------------------------- |
| Small  | 1 PR    | 1                       | 1                                                                                       |
| Medium | 2-4 WIs | 1                       | 1 per WI                                                                                |
| Large  | 5+ WIs  | 1+ rounds (until clean) | 1 per WI; mechanical low-risk WIs that share the same surface MAY batch under one audit |

If a feature is genuinely 10+ WIs, consider whether the plan should split into multiple features.

## Author / auditor separation (invariant)

The agent that writes the plan must NOT be the same agent that audits it. Today this happens by accident (cc-suite runs Codex as a separate `codex exec` process from the implementing Claude Code session). The rule preserves this invariant explicitly so a future single-agent setup doesn't degenerate into self-marking.

If a future setup runs everything through one agent, the audit step requires invoking a different model/context boundary explicitly (e.g., a fresh subagent with read-only sandbox + explicit "audit, don't implement" framing).

## Manual fallback when AI auditor unavailable

When Codex / Gemini / equivalent is unavailable (network, quota, outage), do the audit manually AND record evidence in the plan or PR. Required `Manual Audit Evidence` section:

- **Files read** (paths)
- **Symbols / signatures verified** (which fields/types/enums you confirmed exist)
- **Edge cases checked** (the list)
- **Risks accepted** (with rationale)
- **Tests added or intentionally deferred**

Manual fallback is allowed only when the independent audit tool is genuinely unavailable, not just inconvenient. The audit step is non-negotiable; manual fallback is an evidence-bearing alternative, not a way to skip.

## What this rule does NOT change

- TDD discipline (`10-tdd.md`) is unchanged.
- Per-PR Codex audit in `/fix-issue` skill is exactly Gate 4 — reference, don't duplicate.
- Merge gate (fix-or-implement) and close gate (verified, not just merged) are unchanged — this rule names where they fit in the workflow.
- Bug fix workflow (`docs/bugs.md` `## Rules`) is unchanged — bugs follow Understand → RED → GREEN → REFACTOR → Verify → Track. Bugs do NOT require a separate plan + plan audit (they're reactive); they do require the implementation audit loop and verification gates.

## Worked example

Feature #46 (WebDAV materializing restore, 11 WIs, High priority):

- **Gate 1 (Plan)**: `dev-docs/plans/20260503-feature-46-materializing-restore.md` — drafted v1.
- **Gate 2 (Plan audit)**: 2 Codex rounds. Round 1 found compile-breaking model assumptions (`Book.originalFilename` doesn't exist), missing `ImportSource.restore`, MOBI handling gap, idempotency hole in `BookImporter`, MOVE 501 silent fallback. Round 2 found `Book.fileExtension` also doesn't exist, weak `BackupBlobStore` signature, weak error shape. Plan v2 incorporates all findings.
- **Gate 3 (TDD impl)**: 11 WIs sequenced (WI-0a model migration, WI-0b enum case, WI-1 BlobPath, etc.). Each ships its own PR.
- **Gate 4 (Impl audit)**: per-PR via `/fix-issue` audit loop.
- **Gate 5 (Verification)**: WI-0a, WI-0b, WI-1, WI-2 = foundational, no device verify. WI-7 (provider integration) = slice verify against Docker WebDAV. WI-10 (UI) = device verify on simulator. Final WI = full acceptance pass (backup → wipe → restore with positions/annotations).
- **Gate 6 (Merge + close)**: each WI's PR merges through its own gate. Final WI moves feature row to `DONE`. After Gate 5 final acceptance pass: row → `VERIFIED`, GH #144 closes with citation.

# 51 — UI/UX from claude.ai/design only

Binding rule for every agent (Claude, Codex, others). Applies to every feature, bug fix, refactor, and verification slice that introduces a new visible UI element.

## Hard rule

**Do not invent UI/UX.** If a feature, bug fix, or slice needs a UI element on a surface that is NOT depicted in a committed design bundle under `dev-docs/designs/...`, stop that slice and file a `needs-design` GitHub issue. The user manually carries it through `claude.ai/design`, re-handoffs a fresh bundle, and only then does the slice resume.

This applies to:

- New SwiftUI / UIKit views, sheets, modals, popovers, alerts, toasts.
- New rows, sections, settings entries, buttons, indicators, or empty states within existing screens.
- New visual states (loading, error, empty, partial, in-progress) when not depicted in the design.
- "Placeholder" UI introduced with intent to re-skin later — same prohibition.
- UI affordances introduced by a bug fix (e.g., a new confirmation dialog, a new status chip) — same prohibition.
- AZW3/Foliate-js / EPUB CSS / WKWebView injection — same prohibition when it changes visible chrome.

## What "designed" means

A surface is **designed** when ALL of the following hold:

1. A committed design bundle exists at `dev-docs/designs/<bundle-name>/`.
2. The specific surface (screen, sheet, popover, interaction state) is depicted in that bundle's HTML/JSX/screenshots — by name and by visual content.
3. "Looks similar to existing X" does NOT count. "Inherits the same chrome" does NOT count. The actual surface must appear in the design.

If you cannot point at a file in `dev-docs/designs/` that shows the surface you are about to build, it is **not designed**.

## Workflow

When you reach a slice that would touch undesigned UI:

1. **Stop that slice.** Do not write the View. Do not write a placeholder. Do not improvise.
2. **File a GitHub issue**:
   - Title: `Design needed: <surface name> for feature #<N>` (or `for bug #<N>`)
   - Labels: `enhancement` + `needs-design`
   - Body must include:
     - The surface being requested (screen / sheet / state)
     - The parent feature or bug (`Refs #<N>`)
     - The user-facing behavior the UI must expose
     - Screenshots of the current chrome if any
     - List of states the design must cover (default, loading, error, empty, etc.)
3. **Pause that slice** in the tracker — add a `BLOCKED: needs-design (#<new-issue>)` note on the WI or bug row.
4. **Continue parallel slices** that DO have design — see `.claude/rules/48-parallel-execution.md` for safe parallel execution.
5. **User loop**: the user manually takes the `needs-design` issue through `claude.ai/design`, gets a handoff bundle, and commits it under `dev-docs/designs/...` in a separate PR. The slice can then resume.

## What is NOT covered by this rule

- **System chrome (status bar, home indicator, dynamic island)** — iOS / SwiftUI handles these by default; no design needed.
- **Pure code changes with no visible delta** — refactors, persistence-only fixes, performance fixes, test-only changes.
- **Existing-surface bug fixes that restore broken UI back to its designed state** — fixing a typo in a label, fixing a hidden button, etc.
- **Verification-only artifacts** — XCUITest helpers, DebugBridge surfaces (`vreader-debug://...`), `dev-docs/verification/*` markdown — these are dev-only, never user-visible in Release.
- **CLI / config / hook / script files** — never user-facing.

## Anti-patterns

| Anti-pattern | Why it fails | Right move |
|---|---|---|
| "I'll match the existing chrome for now" | That's self-designed UI. Existing chrome IS the thing being replaced (feature #60). | File `needs-design`. |
| "Just a placeholder until v2" | Placeholders are committed code that ships in releases. Fragmenting UI for 2-3 versions is worse than pausing. | File `needs-design`. |
| "It's a small dialog, an Apple HIG default works fine" | HIG defaults look fine in isolation but clash with the specified design system over time. | File `needs-design`. |
| Inventing UI for a bug-fix toast / status chip / error sheet | Bug fixes don't escape this rule — they can introduce UI debt the same way features do. | File `needs-design`. |
| Inventing UI in a feature-workflow Gate 3 implementation because the WI list said "small change" | Gate-3 must reference the designed surface; if no design exists for a WI's UI, that WI itself was misclassified in Gate 1 — escalate. | Stop the WI, file `needs-design`, fix the Gate-1 plan. |

## Origin

2026-05-15 user directive after filing feature #60 (visual identity v2 design bundle). The user wants a one-way design loop:

```
design tool → handoff bundle → commit → implement
```

and explicitly rejects the round-trip:

```
agent invents UI → ships → user notices → user redesigns → re-implement
```

The cost of pausing a slice to file `needs-design` is far below the cost of producing UI debt that has to be re-skinned later. This rule encodes that trade-off.

codex
The worktree is already dirty with unrelated/user-owned changes, including this untracked plan and an audit artifact; I’ll preserve everything and make no edits. The first command’s architecture output was truncated, so I’m narrowing the reads to the Android architecture section and exact plan/code paths.
exec
/bin/zsh -lc "sed -n '1,360p' dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md
rg -n \"Android|AiProvider|AppContainer|ReaderChromeScaffold|ReaderSheet\" docs/architecture.md
rg --files android/app/src/main/kotlin android/app/src/test android/app/src/androidTest dev-docs/designs | rg '(AiProvider|AiSettings|VReaderApp|ReaderChromeScaffold|vreader-more\\.jsx|vreader-ai-android\\.jsx|vreader-ai-provider-entry\\.jsx|reader-ai-provider-entry\\.md|reader-ai-readiness\\.md)"'$'"'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
# Gate-1 Plan — Feature #136: AI provider setup made production-reachable (Android)

> Status target: `TODO` → `PLANNED` (on Gate-2 pass)
> Platform lane: `android-app` (Gate-5 = Android emulator connected run, rule 47 Android tier)
> Design authority (rule 51, LANDED — no `needs-design`): `vreader-more.jsx` (the reader More-menu `configure-ai` disabled-Bilingual row), `vreader-ai-android.jsx` (`AiProviderList` surface A), `vreader-ai-provider-entry.jsx` + `design-notes/reader-ai-provider-entry.md` + `design-notes/reader-ai-readiness.md` (the in-reader scoped AI-Providers entry decision), `vreader-ai-provider-fields.jsx` (the reused editor).

## 1. Problem

Feature #118 shipped the entire Android AI provider stack — `AiProviderStore` (keystore-encrypted profile persistence, #116 `KeystoreSecretCipher` precedent), `AiSettingsViewModel` (list + editor + Test Connection), `AiProviderListScreen` (the designed "AI Providers" gate surface), and `AiProviderEditSheet` (the canonical add/edit form). It is fully unit- and connected-tested. **But none of it is wired into any production entry.** Grep confirms `AiProviderListScreen`, `AiSettingsViewModel`, and `AiProviderEditSheet` are referenced **only** by `androidTest`/`test` sources; `AiProviderStore` is **never constructed** in `AppContainer` (it appears only in comments as a naming precedent); and `MainActivity` is a single Library Activity that `startActivity`-launches reader hosts — there is **no `NavHost`, no Settings tree, and no More-menu AI row** that reaches the AI screens. `LibraryScreen.kt:95-96` explicitly records that the design's Library settings/More pill "is added when that feature lands (a separate WI) … still omitted."

Consequence: **a fresh install has zero production route to configure an AI provider.** With no provider, every downstream AI feature is dead — bilingual (#131), chat (`AiChatPanel`, also unwired), translate, summaries. This is exactly the Gate-2-round-2 audit High-3 recorded against #131: bilingual's fresh-user path and its Gate-5 acceptance route both dead-end because there is no reachable AI config to land on.

**#136 makes the already-designed, already-built AI provider config production-reachable and independently verifiable**, from a designed in-reader entry that does not depend on #131.

## 2. Surface area

### Designed entry point (the decision)

Two designed reader entries exist; #136 uses the one that is **independent of #131**:

- **`vreader-more.jsx:91-95`** depicts the reader More-menu row: when `s.aiUnavailable`, a **disabled "Bilingual mode" row** with `sub="Configure AI provider first"` whose tap fires `onAction('configure-ai')`. This is the canonical "AI unconfigured → route to config" affordance in the reader chrome, and the Kotlin scaffolding already exists for it: `MoreActionId.BILINGUAL`, `MoreRow.Disabled(id, label, icon, sub, onTap)`, and the `readerMoreRows(...)` assembler in `ReaderChromeScaffold.kt`. The `configure-ai` action → presents the **AI Providers sheet** (`AiProviderListScreen`), matching `reader-ai-provider-entry.md`'s "closes the Library→Settings→AI gap inside the reader" decision (Variant A: a scoped in-reader provider sheet reusing the canonical editor, NOT the full SettingsView).

This entry is reachable by a fresh user (open any book → More → "Configure AI provider first") with **no bilingual wiring present** — which is precisely what independent-verifiability requires. #131 will later ADD the *enabled* Bilingual toggle + its own bilingual-Set-up→here route; #136 owns only the `aiUnavailable`/`configure-ai` path.

### Files MODIFIED

| File | Change (concrete signature) |
|---|---|
| `android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt` (`AppContainer`) | Add process-singleton `val aiProviderStore: AiProviderStore by lazy { AiProviderStore(<DataStore under noBackupFilesDir "ai_providers.preferences_pb">, KeystoreSecretCipher(<alias>)) }` (the `readerSettingsStore`/`OpdsSourceStore` DataStore-under-`noBackupFilesDir` + `KeystoreSecretCipher` precedent — keys are per-device, NOT in the backup contract). Add `fun aiSettingsViewModel(): AiSettingsViewModel = AiSettingsViewModel(aiProviderStore)` factory. |
| `android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderChromeScaffold.kt` (`readerMoreRows`) | Extend the assembler to additively accept the AI-entry callback and emit the designed disabled Bilingual row when AI is unconfigured: `internal fun readerMoreRows(onDetails, onShare, aiUnconfigured: Boolean = false, onConfigureAi: (() -> Unit)? = null): List<MoreRow>` → prepends `MoreRow.Disabled(id = MoreActionId.BILINGUAL, label = "Bilingual mode", icon = Icons.…Translate-analog, sub = "Configure AI provider first", onTap = onConfigureAi ?: {})` **only when `aiUnconfigured && onConfigureAi != null`** (no dead control — #129 rule; absent otherwise). Nullable defaults keep #134/#131 callers valid. Note: `MoreRow.Disabled` is currently non-interactive in `MorePopup.MoreRowItem` (`onClick = {}`); making the `configure-ai` row tappable is a **row-treatment change** — see Risks §6 (the design shows `disabled` + an `on` handler, so the row is dimmed-but-tappable). |
| `android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderChromeState.kt` (+`…StateSaver`) | Add `ReaderSheet.AiProviders` to the sealed `ReaderSheet` set and to the string saver (round-trips like `Toc`/`Notes`/`Bookmarks`; unknown token → `None`, never throws — the existing saver contract). Survives rotation/process-death. |
| `android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderChromeScaffold.kt` (host sheet layer) + `android/app/src/main/kotlin/com/vreader/app/reader/EpubReaderChrome.kt` (`EpubReaderSheets`) | Render the `ReaderSheet.AiProviders` route: host the `AiProviderListScreen` + `AiProviderEditSheet` fed by an `AiSettingsViewModel` (obtained via the Activity's `ViewModelStore`, `viewModel(factory = …container.aiSettingsViewModel())` — the `SearchViewModel` precedent in `MainActivity`), wired to `AiSettingsViewModel.openAdd/openEdit/close/update/test/save/delete/setActive` and the `editState`/`listState` flows. Back / Done → `ReaderSheet.None`. |
| The five reader host Activities that assemble chrome — `ReaderActivity.kt` (EPUB, via `EpubTopBand`/`EpubReaderSheets`) + `TxtReaderActivity.kt`, `PdfReaderActivity.kt`, `Azw3ReaderActivity.kt` (scaffold hosts) | Pass `aiUnconfigured` (derived from `container.aiProviderStore.observe().map { it.profiles.isEmpty() }` collected as state) + `onConfigureAi = { chromeState = …copy(sheet = ReaderSheet.AiProviders) }` into `readerMoreRows(...)` / `EpubTopBand`. This is the one-writer-coordinate additive pattern #132/#134/#135 already use for the chrome files. |

### Files ADDED

| File | Purpose |
|---|---|
| `android/app/src/main/kotlin/com/vreader/app/reader/ai/ReaderAiProvidersHost.kt` (new, ~120 lines) | The reader-scoped presentation container: a `@Composable ReaderAiProvidersHost(vm: AiSettingsViewModel, onClose: () -> Unit)` that observes `vm.listState`/`vm.editState` and hosts `AiProviderListScreen` (list/empty) + the `AiProviderEditSheet` modal-on-top (the `reader-ai-provider-entry.md` "list is a push, editor is a modal on top" nav model). **Rule 51: renders ONLY the existing designed surfaces** (`AiProviderListScreen`, `AiProviderEditSheet`) — no new visual chrome. New Kotlin file → lane-dispatchable (Gradle source-set glob). |
| Tests — see §5. | JVM/Robolectric + connected. |

### Files OUT of scope

- **Provider CRUD internals** — `AiProviderStore.upsert/delete/setActive/apiKey`, `AiSettingsViewModel.test/save`, `AiProviderFactory`, the provider clients, `SseEventReader`, `AiProviderKind`. All shipped and tested by #118; #136 constructs and reaches them, never re-implements them.
- **The designed surfaces themselves** — `AiProviderListScreen.kt`, `AiProviderEditSheet.kt`, `AiSettingsUiState.kt`. Used verbatim.
- **The AI-readiness sheet (flag + consent gates)** — `reader-ai-readiness.md`'s `ReaderAIReadinessSheet` (master AI toggle + consent ledger) is **design-landed but implementation-deferred** ("do NOT build without go-ahead"). #136 delivers the provider-list reachability only; the flag/consent capstone is a separate feature.
- **AI chat panel wiring** — `AiChatPanel`/`AiChatViewModel` are ALSO unwired, but chat's reader entry is #131/a chat feature's surface, not #136.
- **Bilingual toggle + bilingual Set-up → AI route** — #131 owns the enabled Bilingual `MoreRow.Toggle` and its own route into this same sheet.
- **A Library-level Settings tree / More pill** (`LibraryScreen.kt:95`) — not built; #136 deliberately does NOT depend on it (see §3 rejected alt).
- **`contracts/`** — no cross-platform contract change (keys are device-local, excluded from backup).

## 3. Prior art / precedent / rejected alternatives

**Committed design (rule 51 satisfied):**
- `design-notes/reader-ai-provider-entry.md` — Variant **A** (CANONICAL): "a scoped, in-reader 'AI Providers' sheet … reusing the canonical `AIProviderEditSheet`", chosen over B (deep-link the whole SettingsView) and C (inline mini-form). Its stated win: "Keeps the reader context … the user never sees Cloud & Sync, OPDS, TTS." #136 implements A's Android analog.
- `design-notes/reader-ai-readiness.md` — the same "close the loop **inside the reader**" decision, naming this the surface "every 'AI unconfigured' silent-no-op should route to."
- `vreader-more.jsx:91-95` — the exact reader-chrome affordance: `aiUnavailable` → disabled Bilingual row `sub="Configure AI provider first"` → `onAction('configure-ai')`.
- `vreader-ai-android.jsx` `AiProviderList` (surface A, "the gate for everything") — already implemented verbatim as `AiProviderListScreen.kt` (its header comment cites this).

**Project precedent for the wiring shape:**
- **#118** built the whole stack; **#116** `KeystoreSecretCipher` + `WebDavServerStore`/`OpdsSourceStore` established the "DataStore-under-`noBackupFilesDir` + keystore cipher, constructed once in `AppContainer`" pattern this plan follows for `aiProviderStore`.
- **#129/#132/#134/#135** wired every reader-chrome entry through the exact seams #136 reuses: the `readerMoreRows` assembler, `ReaderChromeState`/`ReaderSheet` + its saver, the `EpubReaderSheets` open-only sheet layer, and the additive-nullable-param "one-writer-coordinate" convention. #134 added Details/Share rows; #136 adds the `configure-ai` row by the same contract.
- **`MainActivity` `SearchViewModel`** precedent — obtaining a container-built ViewModel via `viewModel(factory = viewModelFactory { initializer { container.searchViewModel() } })` so its `viewModelScope` is cleared on Activity destroy. `aiSettingsViewModel()` follows this exactly.

**Rejected alternatives:**
1. **Library Settings tree / More pill entry (`LibraryScreen.kt:95`).** Rejected: that Settings tree does not exist on Android, and `OpdsSourcesViewModel`/`OpdsSourceStore` are *also* still test-only — building the whole Library Settings host is a large, separate feature. The design's own decision (both notes) is the in-reader scoped entry.
2. **Route only from #131's bilingual Set-up.** Rejected by independent-verifiability: it would couple #136 to #131 (still `PLANNED`) and make AI config unreachable until bilingual ships. The `aiUnavailable`/`configure-ai` More-row is reachable with zero bilingual wiring.
3. **Deep-link the full SettingsView (Variant B) / inline mini-form (Variant C).** Rejected by the design notes themselves.
4. **Build the deferred AI-readiness sheet (flag+consent) now.** Rejected: `reader-ai-readiness.md` marks it "implementation deferred — do NOT build without go-ahead."

## 4. Work-item sequencing (small feature — 3 WIs)

**WI-1 — `AppContainer` AI store + VM factory (FOUNDATIONAL).**
Construct `aiProviderStore` (DataStore under `noBackupFilesDir` + `KeystoreSecretCipher`) and `aiSettingsViewModel()` in `AppContainer`. No user-observable behavior → unit tests + audit suffice (Gate-5 foundational tier, no device verify). *PR size: XS.* Lane-dispatchable (edits one existing file + new test).

**WI-2 — `ReaderAiProvidersHost` + `ReaderSheet.AiProviders` route (BEHAVIORAL).**
Add the new `ReaderAiProvidersHost.kt` (hosts `AiProviderListScreen` + `AiProviderEditSheet` over the VM), the `ReaderSheet.AiProviders` sealed case + saver round-trip, and render it in the scaffold sheet layer + `EpubReaderSheets`. *PR size: S.* Connected Compose slice: open route → empty state → Add → editor → Save → list shows provider → back.

**WI-3 — reader More-menu `configure-ai` entry across all five hosts (BEHAVIORAL, FINAL WI).**
Extend `readerMoreRows` with the `aiUnconfigured`/`onConfigureAi` params emitting the designed disabled-Bilingual row, and wire `aiUnconfigured` (from `aiProviderStore.observe()`) + `onConfigureAi` (opens `ReaderSheet.AiProviders`) in the four host Activities + `EpubTopBand`. *PR size: M.* Closes the feature → full Gate-5 acceptance (the reachable end-to-end flow on emulator).

> Sequencing: WI-1 is a pure foundation WI-2 depends on; WI-2 makes the destination renderable + independently testable *before* any entry exists; WI-3 lights the entry across hosts. Each is one PR.

## 5. Test catalogue

**JVM / Robolectric (`app/src/test`):**
- `AppContainerAiWiringTest.kt` (new) — `aiProviderStore` is a stable singleton; `aiSettingsViewModel()` returns a VM whose `listState` reflects the store (empty fresh, non-empty after `upsert`). Guards WI-1.
- Extend `ReaderChromeStateSaverTest.kt` — `ReaderSheet.AiProviders` round-trips; unknown/garbage token → `None` (never throws). Guards WI-2 process-death.
- `ReaderMoreRowsAiEntryTest.kt` (new, JVM/pure) — `readerMoreRows(aiUnconfigured = true, onConfigureAi = {…})` includes exactly one `MoreRow.Disabled`/`configure-ai` row with the designed label + sub; `aiUnconfigured = false` OR `onConfigureAi = null` omits it (no dead control). Guards WI-3.

**Connected Compose (`app/src/androidTest`) — the #132/#134/#135 pattern; the connected run IS the Gate-5 acceptance:**
- Reuse existing `AiProviderListScreenTest`/`AiProviderEditSheetTest`/`AiRoundTripConnectedTest` (unchanged — surfaces verbatim).
- `ReaderAiProvidersHostConnectedTest.kt` (new) — drives `ReaderAiProvidersHost` over a real `AiSettingsViewModel`+`AiProviderStore`: empty state (`ai-add-provider`) → Add → `AiProviderEditSheet` (`ai-save`) → save → list shows `provider-<id>` → back → `ReaderSheet.None`.
- `ReaderMoreAiEntryConnectedTest.kt` (new) — the **reachability acceptance**: launch a reader host on a fresh (no-provider) store → open More → "Configure AI provider first" row present + tappable → tap → `AiProviderListScreen` empty state → add a provider → return → re-open More → the `configure-ai` row is now **absent**. The "fresh user can reach AI config, add a provider, and return" acceptance, independent of #131.

**Audit-driven additions:** corrupt/partial DataStore token (saver → `None`); process-death mid-editor (route restores, editor state transient by design); a provider deleted while the sheet is open (list re-derives from the store Flow).

## 6. Risks + mitigations

- **Coupling with #131.** Mitigation: the entry is the `aiUnavailable`/`configure-ai` More-row, reachable with zero bilingual code; #131 separately adds the *enabled* Bilingual toggle + its Set-up→here route. `readerMoreRows` params additive-nullable so #131's later change is one-writer-coordinate.
- **`MoreRow.Disabled` is currently non-interactive.** `MorePopup.MoreRowItem` renders `Disabled` with `onClick = {}`. The design (`vreader-more.jsx:94-95`) shows the row `disabled` AND `on={() => onAction('configure-ai')}` — dimmed but tappable. Mitigation: WI-3 makes the `Disabled` row's `onTap` fire (a small `MorePopup` change), matching the design; covered by `ReaderMoreAiEntryConnectedTest`. Restore-to-designed-state, rule-51-clean.
- **AI-key security surface (#118).** Mitigation: #136 constructs `AiProviderStore` with `KeystoreSecretCipher` under `noBackupFilesDir` (the #116 contract) and touches NO CRUD/crypto path. Keys stay device-local; no `contracts/` change.
- **Config-change / process-death.** Mitigation: `ReaderSheet.AiProviders` is in the `rememberSaveable` saver (rotation/death safe); the editor's transient form re-opens empty by design; the VM is Activity-`ViewModelStore`-owned (`SearchViewModel` precedent), scope cleared on destroy.
- **Five-host fan-out.** Mitigation: EPUB routes through `EpubTopBand`/`EpubReaderSheets`; the other three through the shared `ReaderChromeScaffold` — the split #134 already validated. One connected test per family confirms parity.

## 7. Backward compatibility

- **Fresh install, no providers (the designed onboarding state).** `aiProviderStore.observe()` → `profiles.isEmpty()` → the More-menu "Configure AI provider first" row → tapping lands on `AiProviderListScreen`'s empty state. No crash, no dead control before a provider exists.
- **Existing DEBUG-configured provider.** `profiles.isNotEmpty()` → the `configure-ai` row is **absent** from More (AI available); the store schema unchanged (#118 JSON-in-DataStore); no migration.
- **Older reader-chrome state tokens.** Unknown-token → `None` means a persisted pre-#136 `ReaderChromeState` restores cleanly.
- **No `contracts/` / backup-format impact** — keys device-local, excluded from the backup contract.

## Dependency statement (binding)

**#136 is a HARD dependency of #131.** #131's fresh-user AI-config path + its Gate-5 acceptance route both require a reachable AI provider config to land on; that destination is delivered by #136. #131 must not re-implement or inline provider config — it consumes #136's `ReaderSheet.AiProviders` sheet. **#131's bilingual-Set-up → #136 route (the enabled Bilingual `MoreRow.Toggle` + its "Set up"→AI-Providers navigation) is #131's OWN WI, not #136's** — #136 delivers only the independent `aiUnavailable`/`configure-ai` More-menu entry, so AI config is reachable + verifiable before #131 exists.

## Revision history

- v1 (2026-07-12) — Gate-1 draft. Authored to resolve #131 Gate-2-round-2 High-3 (AI-config unreachable): the #118 AI provider stack is production-reachable via the designed reader More-menu `configure-ai` entry (Variant A in-reader AI-Providers sheet). 3 WIs. Spun out per the orchestrator/user decision (2026-07-12) that AI-settings navigation is its own tiny feature + a hard dependency of #131.
112:The app sheets share `ReaderSheetChrome.swift` — a reusable wrapper matching the design's `Sheet` component: a theme-tinted surface (`ReaderThemeV2.sheetSurfaceColor`), an optional centred Source Serif 4 title bar with 50pt leading/trailing slots (a default circular close button fills the trailing slot when an `onClose` is given and no custom trailing view is), and a scrollable body. The slide-up animation + drag grabber come from SwiftUI's own `.sheet` + `.presentationDragIndicator(.visible)`; `ReaderSheetChrome` supplies only the title bar + surface tint. It wraps the Display sheet (`ReaderSettingsPanel`), the two annotations sheets (`TOCSheet` + `HighlightsSheet`, feature #62 — see below), the reader Book Details sheet (`BookDetailsSheet`, feature #61 — opened from More → Book details, with a trailing Share button in place of the default close), and the AI sheet (`AIReaderPanel`, `title: nil` + a custom sparkle header). `SettingsView` (App Settings) keeps an inner `NavigationStack` for its `NavigationLink` push destinations, with `ReaderSheetChrome` above it. The per-sheet section contract is pinned in `SheetSectionContract.swift` (`ReaderSheetKind`). Reader sheets pass the book's `ReaderThemeV2`; the App Settings sheet uses `.paper` (the Library is not theme-switchable).
512:## Android App (`android/` — feature #106 foundation bar)
514:vreader's Android app is a **second, independently-shippable native app**
535:| `:app` | Android application | Compose UI shell + the Room data layer + reader plumbing. `com.vreader.app`. |
536:| `:identity` | pure Kotlin/JVM (no Android deps) | The shared canonical contracts — `Identity` (fingerprint canonical key), `CanonicalLocator` (engine-neutral canonical JSON), `DocumentFingerprint` (streaming SHA-256 + format detection), and the `Locator` / `VReaderLocator` / `ReaderLocatorEngine` value types. **Both `:app` AND the `contracts/conformance` lane depend on this one module**, so the golden-vector conformance test proves the SAME code the app runs. |
604:<sha>_<bytes>.<canonicalExt>` = content-addressed blob store), so an Android
612:| `net.SecretCipher` / `KeystoreSecretCipher` | AndroidKeyStore | AES-256-GCM (fresh IV, non-exportable key) for the password at rest — the EncryptedSharedPreferences replacement. |
647:| `AiProviderKind` | `openAiCompatible` / `anthropicNative` + default base URL/model + appended endpoint path (`@SerialName` = iOS raw values). |
648:| `AiProviderStore` | DataStore JSON list of provider profiles + an active-id; API key kept ONLY as a `KeystoreSecretCipher` token. Snapshot-consistent `apiKey(profile)`. |
652:| `AiSettingsViewModel` + `AiProviderListScreen`/`AiProviderEditSheet` | The provider gate + the `EditorSheet` (test-connection against the live form). |
667:| `AnnotationColor` | The 5 design colors (yellow/green/blue/pink/red — design parity; iOS has 4, `red` is Android-only). |
669:| `AnnotationsRepository` | DTO boundary over `AnnotationDao`: CRUD + Flow reads; `addHighlight` dedupes via the transactional upsert and returns the PERSISTED row; rejects a locator whose `fingerprintKey` ≠ the book. Process-singleton in `AppContainer`. |
dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx
dev-docs/designs/vreader-fidelity-v1/project/vreader-more.jsx
dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-android.jsx
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-readiness.md
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md

exec
/bin/zsh -lc "rg --files android/app/src/main/kotlin | rg 'AiProvider|AiSettings|VReaderApp|ReaderChrome|ReaderActivity|EpubReaderChrome|TxtReaderActivity|PdfReaderActivity|Azw3ReaderActivity|MainActivity|LibraryScreen|SecretCipher|SourceStore'
rg -n \"class AiProviderStore|interface AiProviderStore|typealias AiProviderStore|class AiSettingsViewModel|fun AiProviderListScreen|fun AiProviderEditSheet|class AppContainer|object AppContainer|data class AppContainer|AiProviderStore\\(|AiProviderListScreen\\(|AiSettingsViewModel\\(|AiProviderEditSheet\\(\" android/app/src/main android/app/src/test android/app/src/androidTest" in /Users/ll/workspace/vreader
 succeeded in 0ms:
android/app/src/main/kotlin/com/vreader/app/backup/net/SecretCipher.kt
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderFactory.kt
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt
android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsUiState.kt
android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsViewModel.kt
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderKind.kt
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderEditSheet.kt
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt
android/app/src/main/kotlin/com/vreader/app/MainActivity.kt
android/app/src/main/kotlin/com/vreader/app/opds/OpdsSourceStore.kt
android/app/src/main/kotlin/com/vreader/app/library/LibraryScreen.kt
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt
android/app/src/main/kotlin/com/vreader/app/reader/EpubReaderChrome.kt
android/app/src/main/kotlin/com/vreader/app/reader/ReaderChromeModel.kt
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt
android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderChromeState.kt
android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderChromeScaffold.kt
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt:46:fun AiProviderListScreen(
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:41:class AiProviderStore(
android/app/src/test/kotlin/com/vreader/app/ai/AiChatViewModelTest.kt:48:        store = AiProviderStore(PreferenceDataStoreFactory.create(scope = CoroutineScope(dispatcher)) { tmp.newFile("ai.preferences_pb") }, cipher)
android/app/src/test/kotlin/com/vreader/app/ai/AiProviderStoreTest.kt:26:class AiProviderStoreTest {
android/app/src/test/kotlin/com/vreader/app/ai/AiProviderStoreTest.kt:39:        store = AiProviderStore(dataStore, fakeCipher)
android/app/src/test/kotlin/com/vreader/app/ai/AiSettingsViewModelTest.kt:29:class AiSettingsViewModelTest {
android/app/src/test/kotlin/com/vreader/app/ai/AiSettingsViewModelTest.kt:48:        store = AiProviderStore(
android/app/src/test/kotlin/com/vreader/app/ai/AiSettingsViewModelTest.kt:57:        AiSettingsViewModel(store, dispatcher) { _, _ -> FakeClient(result) }
android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsViewModel.kt:20:class AiSettingsViewModel(
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderEditSheet.kt:55:fun AiProviderEditSheet(
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:31:class AppContainer(context: Context) {
android/app/src/androidTest/kotlin/com/vreader/app/ai/AiProviderEditSheetTest.kt:25:        compose.setContent { BackupSurface(darkOverride = false) { AiProviderEditSheet(AiEditState(editMode = false)) } }
android/app/src/androidTest/kotlin/com/vreader/app/ai/AiProviderEditSheetTest.kt:38:        compose.setContent { BackupSurface(darkOverride = false) { AiProviderEditSheet(AiEditState(), onKind = { picked = it }) } }
android/app/src/androidTest/kotlin/com/vreader/app/ai/AiProviderEditSheetTest.kt:44:        compose.setContent { BackupSurface(darkOverride = false) { AiProviderEditSheet(AiEditState(apiKey = "")) } }
android/app/src/androidTest/kotlin/com/vreader/app/ai/AiProviderEditSheetTest.kt:51:                AiProviderEditSheet(AiEditState(apiKey = "sk", test = AiConnTest.ok, testMessage = "Connected — the provider responded successfully."))
android/app/src/androidTest/kotlin/com/vreader/app/ai/AiProviderEditSheetTest.kt:60:                AiProviderEditSheet(AiEditState(editMode = true, id = "x", name = "DeepSeek", keyAlreadySaved = true))
android/app/src/androidTest/kotlin/com/vreader/app/ai/AiProviderListScreenTest.kt:23:            BackupSurface(darkOverride = false) { AiProviderListScreen(AiProviderListState(emptyList()), onAdd = { added = true }) }
android/app/src/androidTest/kotlin/com/vreader/app/ai/AiProviderListScreenTest.kt:38:        compose.setContent { BackupSurface(darkOverride = false) { AiProviderListScreen(state, onEdit = { edited = it }) } }

exec
/bin/zsh -lc "nl -ba android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt | sed -n '1,240p'
nl -ba android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt | sed -n '1,280p'
nl -ba android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsViewModel.kt | sed -n '1,300p'
nl -ba android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt | sed -n '1,240p'
nl -ba android/app/src/main/kotlin/com/vreader/app/ai/AiProviderEditSheet.kt | sed -n '1,280p'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
     1	// Purpose: Application + manual DI container — feature #106 WI-8. Holds the
     2	// process-singleton Room database, repository, and importer so the Library
     3	// ViewModel gets shared instances (a Hilt module is a Phase-3 follow-on; manual
     4	// wiring at the app edge keeps the foundation bar dependency-light — rule 50 §5).
     5	package com.vreader.app
     6	
     7	import android.app.Application
     8	import android.content.Context
     9	import com.vreader.app.data.BookImporter
    10	import com.vreader.app.data.LibraryRepository
    11	import com.vreader.app.data.VReaderDatabase
    12	import com.vreader.app.reader.BookOpener
    13	import com.vreader.app.search.BookTextExtractor
    14	import com.vreader.app.search.EpubTextExtractor
    15	import com.vreader.app.search.asSearcher
    16	import com.vreader.app.search.SearchIndexCoordinator
    17	import com.vreader.app.search.TxtMdTextExtractor
    18	import com.vreader.app.annotations.AnnotationsRepository
    19	import com.vreader.app.stats.ReadingStatsRepository
    20	import com.vreader.app.stats.ReadingTimeTracker
    21	import com.vreader.app.stats.clock.SystemDateClock
    22	import com.vreader.app.stats.clock.SystemElapsedClock
    23	import kotlinx.coroutines.CoroutineScope
    24	import kotlinx.coroutines.Dispatchers
    25	import kotlinx.coroutines.SupervisorJob
    26	import kotlinx.coroutines.flow.map
    27	import vreader.contracts.BookFormat
    28	import java.io.File
    29	
    30	/** Process-wide singletons, lazily built. */
    31	class AppContainer(context: Context) {
    32	    private val appContext = context.applicationContext
    33	
    34	    val database: VReaderDatabase by lazy { VReaderDatabase.build(appContext) }
    35	    val repository: LibraryRepository by lazy {
    36	        LibraryRepository(database.bookDao(), database.readingPositionDao())
    37	    }
    38	    val importer: BookImporter by lazy {
    39	        BookImporter(File(appContext.filesDir, "books"), repository)
    40	    }
    41	
    42	    // feature #122 — reading-stats. The repository + the time tracker are process-singletons so a
    43	    // reading session survives the (shorter-lived) reader ViewModel / rotation. ONE shared DateClock
    44	    // so the dashboard's "today" and the tracker's bucket dates can't drift apart.
    45	    private val dateClock: SystemDateClock by lazy { SystemDateClock() }
    46	    val statsRepository: ReadingStatsRepository by lazy {
    47	        ReadingStatsRepository(database.readingStatsDao(), repository, dateClock)
    48	    }
    49	    val readingTimeTracker: ReadingTimeTracker by lazy {
    50	        ReadingTimeTracker(statsRepository, SystemElapsedClock(), dateClock)
    51	    }
    52	
    53	    // feature #123 — annotations (EPUB highlights & notes). Process-singleton so the reader VM /
    54	    // rotation share one instance (the statsRepository precedent).
    55	    val annotationsRepository: AnnotationsRepository by lazy {
    56	        AnnotationsRepository(database.annotationDao())
    57	    }
    58	
    59	    // feature #127 — library collections. Process-singleton (the annotationsRepository precedent).
    60	    val collectionRepository: com.vreader.app.data.CollectionRepository by lazy {
    61	        com.vreader.app.data.CollectionRepository(database.collectionDao())
    62	    }
    63	
    64	    // feature #129 — reader display settings. A device-local DataStore (the OpdsSourceStore /
    65	    // AiProviderStore precedent), global (not per-book), process-singleton so a settings change
    66	    // propagates to whatever reader is open. Stored under noBackupFilesDir — display prefs are
    67	    // per-device (NOT in the backup contract), so they must be excluded from Android Auto Backup.
    68	    private val readerSettingsDataStore: androidx.datastore.core.DataStore<androidx.datastore.preferences.core.Preferences> by lazy {
    69	        androidx.datastore.preferences.core.PreferenceDataStoreFactory.create {
    70	            File(appContext.noBackupFilesDir, "reader_settings.preferences_pb")
    71	        }
    72	    }
    73	    val readerSettingsStore: com.vreader.app.reader.settings.ReaderSettingsStore by lazy {
    74	        com.vreader.app.reader.settings.ReaderSettingsStore(readerSettingsDataStore)
    75	    }
    76	
    77	    /** Process-lifetime scope for fire-and-forget writes that must outlive a screen
    78	     *  (e.g. the reader's onStop position flush — it must finish even as the activity
    79	     *  is being torn down). */
    80	    val appScope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    81	
    82	    // feature #128 WI-5 — cross-book search index. The coordinator observes the library and
    83	    // streams each indexable book (epub/txt/md) through the WI-3 extractors into WI-4's staging →
    84	    // atomic publish. Eagerly started once from onCreate; pdf/azw3 map to null (never indexable).
    85	    private val bookOpener: BookOpener by lazy { BookOpener(appContext) }
    86	    private val epubTextExtractor: EpubTextExtractor by lazy { EpubTextExtractor(bookOpener) }
    87	    private val txtMdTextExtractor: TxtMdTextExtractor by lazy { TxtMdTextExtractor() }
    88	    val searchIndexCoordinator: SearchIndexCoordinator by lazy {
    89	        SearchIndexCoordinator(
    90	            repository = repository,
    91	            searchDao = database.searchDao(),
    92	            extractorFor = { fmt: BookFormat ->
    93	                when (fmt) {
    94	                    BookFormat.epub -> epubTextExtractor
    95	                    BookFormat.txt, BookFormat.md -> txtMdTextExtractor
    96	                    BookFormat.pdf, BookFormat.azw3 -> null   // metadata-only — never indexed
    97	                }
    98	            },
    99	            scope = appScope,
   100	            ioDispatcher = Dispatchers.IO,
   101	        )
   102	    }
   103	
   104	    /** Idempotent — starts the single search-index collector (the coordinator's own AtomicBoolean
   105	     *  makes a repeat call a no-op). Called once from [VReaderApp.onCreate]. */
   106	    fun startSearchIndexing() = searchIndexCoordinator.startSearchIndexing()
   107	
   108	    // feature #128 WI-6 — the query pipeline. SearchRepository turns a raw query into an observable
   109	    // Flow of first-hit-per-book text hits (grows as indexing completes); RecentSearchesStore is a
   110	    // device-local DataStore under noBackupFilesDir (the readerSettingsStore precedent — recents are
   111	    // per-device, NOT in the backup contract). The SearchViewModel factory wires the metadata filter,
   112	    // the text-hit Flow, the completeness gate, and recent-recording for the WI-7 screen.
   113	    val searchRepository: com.vreader.app.search.SearchRepository by lazy {
   114	        com.vreader.app.search.SearchRepository(database.searchDao())
   115	    }
   116	    private val recentSearchesDataStore: androidx.datastore.core.DataStore<androidx.datastore.preferences.core.Preferences> by lazy {
   117	        androidx.datastore.preferences.core.PreferenceDataStoreFactory.create {
   118	            File(appContext.noBackupFilesDir, "recent_searches.preferences_pb")
   119	        }
   120	    }
   121	    val recentSearchesStore: com.vreader.app.search.RecentSearchesStore by lazy {
   122	        com.vreader.app.search.RecentSearchesStore(recentSearchesDataStore)
   123	    }
   124	
   125	    /**
   126	     * feature #133 WI-10 — the per-reader-session in-book-search ViewModel for a TXT/MD host. Wires the
   127	     * WI-6 [InBookSearchRepository] (FTS DAO page/count/resume + the WI-4 [TxtMdInBookHitResolver] over the
   128	     * already-decoded [decodedText]) behind the WI-8 [InBookSearchViewModel], gated by the WI-7
   129	     * [IndexStateGate] over the DAO's `observeIndexState` Flow and fed the GLOBAL recents store.
   130	     *
   131	     * The EPUB engine seam is NEVER invoked for a TXT/MD host (the repository dispatches only the TXT/MD
   132	     * branch for `txt`/`md`), so `epubEngineFor` is an error-throwing guard — a call would be a wiring bug.
   133	     * ONE [InBookSearchRepository] per session (the VM's `closeAllEpubCursors` lifecycle contract holds
   134	     * uniformly even though TXT has no cursors). [coroutineScope] is the VM's `viewModelScope` in production
   135	     * (the VM cancels its child collectors on `onCleared`).
   136	     */
   137	    fun inBookSearchViewModel(
   138	        bookKey: String,
   139	        format: BookFormat,
   140	        decodedText: String,
   141	        contentSHA256: String,
   142	        fileByteCount: Long,
   143	        coroutineScope: CoroutineScope,
   144	    ): com.vreader.app.search.InBookSearchViewModel {
   145	        val searchDao = database.searchDao()
   146	        val repository = com.vreader.app.search.InBookSearchRepository(
   147	            dispatcher = Dispatchers.Default,
   148	            fts = com.vreader.app.search.InBookFtsDeps(
   149	                matchingChunksPage = { ftsQuery, afterSectionIndex, afterChunkOrdinal, afterId, limit ->
   150	                    searchDao.matchingChunksPage(bookKey, ftsQuery, afterSectionIndex, afterChunkOrdinal, afterId, limit)
   151	                },
   152	                chunkAtOrAfter = { ftsQuery, atSectionIndex, atChunkOrdinal, atId ->
   153	                    searchDao.chunkAtOrAfter(bookKey, ftsQuery, atSectionIndex, atChunkOrdinal, atId)
   154	                },
   155	                // The resolver re-derives the chunk boundaries from the ALREADY-decoded reader text (no I/O);
   156	                // memoized per session inside the resolver (built once).
   157	                resolverFor = {
   158	                    com.vreader.app.search.TxtMdInBookHitResolver(
   159	                        contentSHA256 = contentSHA256,
   160	                        fileByteCount = fileByteCount,
   161	                        format = format.name,
   162	                        decodedText = decodedText,
   163	                    )
   164	                },
   165	            ),
   166	            // TXT/MD never reaches the EPUB branch — a call here is a dispatch bug, fail fast.
   167	            epubEngineFor = { error("EPUB in-book search engine requested on a TXT/MD host") },
   168	        )
   169	        return com.vreader.app.search.InBookSearchViewModel(
   170	            bookKey = bookKey,
   171	            format = format,
   172	            searcher = repository.asSearcher(),
   173	            indexStateGate = com.vreader.app.search.IndexStateGate(Dispatchers.Default),
   174	            indexStateFlow = searchDao.observeIndexState(bookKey),
   175	            // For a settled-`indexed` TXT/MD row the gate consults this to decide Ready vs definitive
   176	            // NoResults. `hasOccurrence` carries no query, so we report Ready (true) and let the actual
   177	            // `page(...)` be the source of truth: a settled book with zero matches runs one fast FTS query
   178	            // and the repository returns NoResults — the SAME UI outcome the gate's occurrence short-circuit
   179	            // would give, without threading the live query through a shared mutable seam (no race). The gate
   180	            // is only consulted on a settled-indexed row, so this never fires while Indexing/missing/failed.
   181	            hasOccurrence = { true },
   182	            recentsFlow = recentSearchesStore.recents(),
   183	            recordQuery = { q -> recentSearchesStore.record(q) },
   184	            dispatcher = Dispatchers.Default,
   185	            coroutineScope = coroutineScope,
   186	        )
   187	    }
   188	
   189	    /**
   190	     * feature #133 WI-11 — the per-reader-session in-book-search ViewModel for the EPUB host. EPUB search does
   191	     * NOT use the #128 FTS index at all (a chunk-level, location-less index cannot yield a jumpable position);
   192	     * instead the WI-6 [InBookSearchRepository]'s EPUB branch runs Readium's OWN `SearchService` over the LIVE
   193	     * [publication] via the WI-5 [EpubInBookSearchEngine] production constructor (which wraps the real
   194	     * publication behind the `PublicationSearchSource` seam), returning navigable Readium `Locator`s the host
   195	     * jumps to with `navigator.go`.
   196	     *
   197	     * EPUB bypasses the WI-7 index-state gate entirely: the [indexStateFlow] emits `null` (missing) and
   198	     * [hasOccurrence] reports Ready, so the gate resolves to Ready and the engine's own `isSearchable` probe
   199	     * is the real capability check (an un-searchable publication → the repository's [InBookSearchOutcome.Unsupported]
   200	     * → the WI-8 VM's `hidesSearchEntry`, so the host omits the Search icon). The TXT/MD FTS branch is NEVER
   201	     * invoked for an EPUB host, so its factories are error-throwing guards (a call would be a wiring bug).
   202	     *
   203	     * ONE [InBookSearchRepository] per session (so the live Readium `SearchIterator` behind
   204	     * `SearchCursor.Epub` is held once and disposed via `closeAllEpubCursors` on dismiss / `onCleared`).
   205	     * [coroutineScope] is the host's `lifecycleScope` in production (the VM cancels its child collectors on
   206	     * `onCleared`).
   207	     */
   208	    fun epubInBookSearchViewModel(
   209	        bookKey: String,
   210	        publication: org.readium.r2.shared.publication.Publication,
   211	        coroutineScope: CoroutineScope,
   212	    ): com.vreader.app.search.InBookSearchViewModel {
   213	        val repository = com.vreader.app.search.InBookSearchRepository(
   214	            dispatcher = Dispatchers.Default,
   215	            // The EPUB host never reaches the FTS branch (the repository dispatches only the EPUB branch for
   216	            // `epub`), so the TXT/MD deps are error-throwing guards — a call here is a wiring bug, fail fast.
   217	            fts = com.vreader.app.search.InBookFtsDeps(
   218	                matchingChunksPage = { _, _, _, _, _ -> error("FTS matchingChunksPage requested on an EPUB host") },
   219	                chunkAtOrAfter = { _, _, _, _ -> error("FTS chunkAtOrAfter requested on an EPUB host") },
   220	                resolverFor = { error("FTS resolver requested on an EPUB host") },
   221	            ),
   222	            // The LIVE wiring: build the WI-5 engine over the real Readium publication (its production
   223	            // constructor wraps the publication behind the `PublicationSearchSource` seam). One engine per
   224	            // repository/session; the repository memoizes it per bookKey.
   225	            epubEngineFor = { com.vreader.app.search.EpubInBookSearchEngine(publication) },
   226	        )
   227	        return com.vreader.app.search.InBookSearchViewModel(
   228	            bookKey = bookKey,
   229	            format = BookFormat.epub,
   230	            searcher = repository.asSearcher(),
   231	            indexStateGate = com.vreader.app.search.IndexStateGate(Dispatchers.Default),
   232	            // EPUB bypasses the FTS index-state gate: a `null` (missing) row + `hasOccurrence == true` resolve
   233	            // the gate to Ready, so the engine's own `isSearchable` probe is the capability check.
   234	            indexStateFlow = kotlinx.coroutines.flow.flowOf(null),
   235	            hasOccurrence = { true },
   236	            recentsFlow = recentSearchesStore.recents(),
   237	            recordQuery = { q -> recentSearchesStore.record(q) },
   238	            dispatcher = Dispatchers.Default,
   239	            coroutineScope = coroutineScope,
   240	        )
     1	// Purpose: feature #118 WI-1 (#110 Phase 3) — persists saved AI provider profiles + the active
     2	// selection. Profile metadata (name/kind/baseUrl/model/temperature/maxTokens) lives in DataStore
     3	// as a JSON list; the API key is kept ONLY as a SecretCipher token (the #116 KeystoreSecretCipher).
     4	// Reuses the #116 WebDavServerStore DataStore+SecretCipher credential pattern, adding an active-id
     5	// and a request-start `snapshot()` (a chat/test reads one consistent profile, not live mid-request
     6	// store reads). The key + auth headers are NEVER logged.
     7	package com.vreader.app.ai
     8	
     9	import androidx.datastore.core.DataStore
    10	import androidx.datastore.preferences.core.Preferences
    11	import androidx.datastore.preferences.core.edit
    12	import androidx.datastore.preferences.core.stringPreferencesKey
    13	import com.vreader.app.backup.net.SecretCipher
    14	import kotlinx.coroutines.flow.Flow
    15	import kotlinx.coroutines.flow.first
    16	import kotlinx.coroutines.flow.map
    17	import kotlinx.serialization.Serializable
    18	import kotlinx.serialization.json.Json
    19	
    20	/** A saved AI provider. `encryptedApiKey` is a [SecretCipher] token, never plaintext. */
    21	@Serializable
    22	data class AiProviderProfile(
    23	    val id: String,
    24	    val name: String,
    25	    val kind: AiProviderKind,
    26	    val baseUrl: String,
    27	    val model: String,
    28	    val temperature: Double = 0.7,
    29	    val maxTokens: Int = 2048,
    30	    val encryptedApiKey: String,
    31	)
    32	
    33	/** A consistent point-in-time view: the profiles + which is active. */
    34	data class AiProviderSnapshot(val profiles: List<AiProviderProfile>, val activeId: String?) {
    35	    val active: AiProviderProfile? get() = profiles.firstOrNull { it.id == activeId }
    36	}
    37	
    38	@Serializable
    39	private data class AiStoreState(val profiles: List<AiProviderProfile> = emptyList(), val activeId: String? = null)
    40	
    41	class AiProviderStore(
    42	    private val dataStore: DataStore<Preferences>,
    43	    private val cipher: SecretCipher,
    44	    private val json: Json = Json { ignoreUnknownKeys = true; encodeDefaults = true },
    45	) {
    46	    /** One consistent profiles + active-id view (read once at request start). */
    47	    suspend fun snapshot(): AiProviderSnapshot = read(dataStore.data.first()).toSnapshot()
    48	
    49	    fun observe(): Flow<AiProviderSnapshot> = dataStore.data.map { read(it).toSnapshot() }
    50	
    51	    suspend fun list(): List<AiProviderProfile> = snapshot().profiles
    52	
    53	    suspend fun activeProfile(): AiProviderProfile? = snapshot().active
    54	
    55	    /**
    56	     * Insert/update a profile by [id]. [apiKey] is the PLAINTEXT to encrypt; pass null on an edit
    57	     * that leaves the key unchanged (the existing ciphertext is kept). A brand-new id REQUIRES a
    58	     * key. The first profile added becomes active. Returns the saved profile (key encrypted).
    59	     */
    60	    suspend fun upsert(
    61	        id: String,
    62	        name: String,
    63	        kind: AiProviderKind,
    64	        baseUrl: String,
    65	        model: String,
    66	        temperature: Double,
    67	        maxTokens: Int,
    68	        apiKey: String?,
    69	    ): AiProviderProfile {
    70	        lateinit var saved: AiProviderProfile
    71	        dataStore.edit { prefs ->
    72	            val cur = read(prefs)
    73	            val existing = cur.profiles.firstOrNull { it.id == id }
    74	            val encrypted = when {
    75	                apiKey != null -> cipher.encrypt(apiKey)
    76	                existing != null -> existing.encryptedApiKey  // unchanged on edit
    77	                else -> throw IllegalArgumentException("a new provider ($id) requires an API key")
    78	            }
    79	            saved = AiProviderProfile(id, name, kind, baseUrl, model, temperature, maxTokens, encrypted)
    80	            val next = cur.profiles.filterNot { it.id == id } + saved
    81	            val activeId = cur.activeId ?: id  // first provider becomes active
    82	            prefs[KEY] = json.encodeToString(AiStoreState(next, activeId))
    83	        }
    84	        return saved
    85	    }
    86	
    87	    /** Remove a profile. If it was active, the active selection moves to the first remaining (or null). */
    88	    suspend fun delete(id: String) {
    89	        dataStore.edit { prefs ->
    90	            val cur = read(prefs)
    91	            val next = cur.profiles.filterNot { it.id == id }
    92	            val activeId = if (cur.activeId == id) next.firstOrNull()?.id else cur.activeId
    93	            prefs[KEY] = json.encodeToString(AiStoreState(next, activeId))
    94	        }
    95	    }
    96	
    97	    /** Select the active provider (no-op if the id isn't present). */
    98	    suspend fun setActive(id: String) {
    99	        dataStore.edit { prefs ->
   100	            val cur = read(prefs)
   101	            if (cur.profiles.any { it.id == id }) prefs[KEY] = json.encodeToString(cur.copy(activeId = id))
   102	        }
   103	    }
   104	
   105	    /** Decrypt the key from a CAPTURED [profile] — snapshot-consistent (no live store read). The
   106	     *  chat/test request path uses THIS with a profile from a single [snapshot], so it can't pair
   107	     *  snapshot metadata with a concurrently-edited/deleted key. */
   108	    fun apiKey(profile: AiProviderProfile): String = cipher.decrypt(profile.encryptedApiKey)
   109	
   110	    /** The decrypted API key for [id] via a live read, or null if absent. Convenience for UI flows
   111	     *  that aren't mid-request; the request path should prefer [apiKey] (profile). */
   112	    suspend fun apiKey(id: String): String? =
   113	        list().firstOrNull { it.id == id }?.let { cipher.decrypt(it.encryptedApiKey) }
   114	
   115	    private fun read(prefs: Preferences): AiStoreState {
   116	        val raw = prefs[KEY] ?: return AiStoreState()
   117	        return runCatching { json.decodeFromString<AiStoreState>(raw) }.getOrDefault(AiStoreState())
   118	    }
   119	
   120	    private fun AiStoreState.toSnapshot() = AiProviderSnapshot(profiles, activeId)
   121	
   122	    companion object {
   123	        private val KEY = stringPreferencesKey("ai_providers_json")
   124	    }
   125	}
     1	// Purpose: feature #118 WI-3 (#110 Phase 3) — drives the AI provider list + editor: observes the
     2	// AiProviderStore for the list, owns the editor form state, runs Test Connection against the LIVE
     3	// form (a transient AiClient built from the form + key, no save first), and saves/deletes. v1 list
     4	// status is ok+model (persisted per-provider test status is a follow-on). The key is never logged.
     5	package com.vreader.app.ai
     6	
     7	import androidx.lifecycle.ViewModel
     8	import androidx.lifecycle.viewModelScope
     9	import kotlinx.coroutines.CoroutineDispatcher
    10	import kotlinx.coroutines.Dispatchers
    11	import kotlinx.coroutines.flow.MutableStateFlow
    12	import kotlinx.coroutines.flow.SharingStarted
    13	import kotlinx.coroutines.flow.StateFlow
    14	import kotlinx.coroutines.flow.map
    15	import kotlinx.coroutines.flow.stateIn
    16	import kotlinx.coroutines.launch
    17	import kotlinx.coroutines.withContext
    18	import java.util.UUID
    19	
    20	class AiSettingsViewModel(
    21	    private val store: AiProviderStore,
    22	    private val clientDispatcher: CoroutineDispatcher = Dispatchers.IO,
    23	    private val factory: (AiProviderProfile, String) -> AiClient = { p, key -> AiProviderFactory.create(p, key) },
    24	) : ViewModel() {
    25	
    26	    val listState: StateFlow<AiProviderListState> = store.observe()
    27	        .map { snap ->
    28	            AiProviderListState(
    29	                snap.profiles.map { p ->
    30	                    AiProviderRow(p.id, p.name, active = p.id == snap.activeId, statusOk = true, detail = p.model.ifBlank { p.kind.defaultModel })
    31	                }
    32	            )
    33	        }
    34	        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), AiProviderListState())
    35	
    36	    private val _edit = MutableStateFlow<AiEditState?>(null)
    37	    val editState: StateFlow<AiEditState?> = _edit
    38	
    39	    // Bumped whenever the editor opens/closes or a new test starts — an in-flight test result is
    40	    // only applied if its generation still matches, so a stale Ok/Fail can't land on a different
    41	    // form (the user closed it, opened another provider, or re-tested).
    42	    private var testGen = 0
    43	
    44	    fun openAdd() { testGen++; _edit.value = AiEditState(editMode = false) }
    45	
    46	    fun openEdit(id: String) = viewModelScope.launch {
    47	        val p = store.list().firstOrNull { it.id == id } ?: return@launch
    48	        testGen++
    49	        _edit.value = AiEditState(
    50	            editMode = true, id = p.id, kind = p.kind, name = p.name, baseUrl = p.baseUrl, model = p.model,
    51	            temperature = p.temperature, maxTokens = p.maxTokens, keyAlreadySaved = true,
    52	        )
    53	    }
    54	
    55	    fun close() { testGen++; _edit.value = null }
    56	
    57	    fun update(transform: (AiEditState) -> AiEditState) { _edit.value = _edit.value?.let(transform) }
    58	
    59	    fun test() {
    60	        val s = _edit.value ?: return
    61	        if (!s.canTest) return
    62	        val gen = ++testGen
    63	        update { it.copy(test = AiConnTest.testing, testMessage = "") }
    64	        viewModelScope.launch {
    65	            // Key lookup + client creation + the network call all off the main thread.
    66	            val result = withContext(clientDispatcher) {
    67	                val key = if (s.apiKey.isNotBlank()) s.apiKey else s.id?.let { store.apiKey(it) } ?: ""
    68	                val profile = AiProviderProfile(
    69	                    id = s.id ?: "transient", name = s.name, kind = s.kind, baseUrl = s.effectiveBaseUrl,
    70	                    model = s.effectiveModel, temperature = s.temperature, maxTokens = s.maxTokens, encryptedApiKey = "",
    71	                )
    72	                runCatching { factory(profile, key).testConnection() }
    73	                    .getOrElse { AiTestResult.Fail(AiError.Offline, it.message ?: "failed") }
    74	            }
    75	            if (gen != testGen) return@launch  // superseded by a newer test / form open / close
    76	            update {
    77	                when (result) {
    78	                    is AiTestResult.Ok -> it.copy(test = AiConnTest.ok, testMessage = "Connected — the provider responded successfully.")
    79	                    is AiTestResult.Fail -> it.copy(test = AiConnTest.fail, testMessage = result.message)
    80	                }
    81	            }
    82	        }
    83	    }
    84	
    85	    fun save() {
    86	        val s = _edit.value ?: return
    87	        if (!s.canSave) return
    88	        viewModelScope.launch {
    89	            store.upsert(
    90	                id = s.id ?: UUID.randomUUID().toString(),
    91	                name = s.name, kind = s.kind, baseUrl = s.baseUrl, model = s.model,
    92	                temperature = s.temperature, maxTokens = s.maxTokens,
    93	                apiKey = s.apiKey.ifBlank { null },  // blank on edit = keep existing
    94	            )
    95	            _edit.value = null
    96	        }
    97	    }
    98	
    99	    fun delete() {
   100	        val id = _edit.value?.id ?: return
   101	        viewModelScope.launch { store.delete(id); _edit.value = null }
   102	    }
   103	
   104	    fun setActive(id: String) = viewModelScope.launch { store.setActive(id) }
   105	}
     1	// Purpose: feature #118 WI-3 (#110 Phase 3) — the AI provider list (the gate), design surface A
     2	// from vreader-ai-android.jsx `AiProviderList`: unconfigured onboards to a single Add action;
     3	// configured shows the active provider + per-provider status (model, or the rejection reason).
     4	// Reuses the shared form vocabulary (NavScreen / SettingsCard / GroupHeader / StatusDot / tokens —
     5	// mapped from this surface's own design file). Stateless: a pure function of the list + callbacks.
     6	package com.vreader.app.ai
     7	
     8	import androidx.compose.foundation.background
     9	import androidx.compose.foundation.clickable
    10	import androidx.compose.foundation.layout.Box
    11	import androidx.compose.foundation.layout.Column
    12	import androidx.compose.foundation.layout.Row
    13	import androidx.compose.foundation.layout.fillMaxWidth
    14	import androidx.compose.foundation.layout.height
    15	import androidx.compose.foundation.layout.heightIn
    16	import androidx.compose.foundation.layout.padding
    17	import androidx.compose.foundation.layout.size
    18	import androidx.compose.foundation.shape.CircleShape
    19	import androidx.compose.foundation.shape.RoundedCornerShape
    20	import androidx.compose.material.icons.Icons
    21	import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
    22	import androidx.compose.material.icons.filled.Add
    23	import androidx.compose.material.icons.filled.AutoAwesome
    24	import androidx.compose.material3.Icon
    25	import androidx.compose.material3.Text
    26	import androidx.compose.runtime.Composable
    27	import androidx.compose.ui.Alignment
    28	import androidx.compose.ui.Modifier
    29	import androidx.compose.ui.draw.clip
    30	import androidx.compose.ui.graphics.Color
    31	import androidx.compose.ui.platform.testTag
    32	import androidx.compose.ui.text.font.FontWeight
    33	import androidx.compose.ui.text.style.TextAlign
    34	import androidx.compose.ui.unit.dp
    35	import androidx.compose.ui.unit.sp
    36	import com.vreader.app.backup.BackupFonts
    37	import com.vreader.app.backup.GroupFooter
    38	import com.vreader.app.backup.GroupHeader
    39	import com.vreader.app.backup.LocalBackupTokens
    40	import com.vreader.app.backup.NavScreen
    41	import com.vreader.app.backup.SettingsCard
    42	import com.vreader.app.backup.StatusDot
    43	import com.vreader.app.backup.VSpace
    44	
    45	@Composable
    46	fun AiProviderListScreen(
    47	    state: AiProviderListState,
    48	    onBack: () -> Unit = {},
    49	    onAdd: () -> Unit = {},
    50	    onEdit: (String) -> Unit = {},
    51	) {
    52	    val t = LocalBackupTokens.current
    53	    val addButton: @Composable () -> Unit = {
    54	        Box(
    55	            Modifier.size(44.dp).clip(RoundedCornerShape(22.dp)).clickable(onClickLabel = "Add provider", onClick = onAdd),
    56	            contentAlignment = Alignment.Center,
    57	        ) { Icon(Icons.Filled.Add, contentDescription = "Add provider", tint = t.tint, modifier = Modifier.size(22.dp)) }
    58	    }
    59	    NavScreen(title = "AI Providers", large = true, onBack = onBack, trailing = addButton) {
    60	        Column(Modifier.padding(horizontal = 18.dp).padding(bottom = 32.dp)) {
    61	            if (state.unconfigured) {
    62	                AiEmptyState(onAdd)
    63	            } else {
    64	                GroupHeader("Providers")
    65	                SettingsCard {
    66	                    state.providers.forEachIndexed { i, p ->
    67	                        ProviderRow(p, last = i == state.providers.lastIndex, onEdit = onEdit)
    68	                    }
    69	                }
    70	                GroupFooter("The selected provider is used for translation, chat, and summaries. Tap one to edit or test it.")
    71	            }
    72	        }
    73	    }
    74	}
    75	
    76	@Composable
    77	private fun AiEmptyState(onAdd: () -> Unit) {
    78	    val t = LocalBackupTokens.current
    79	    Column(Modifier.fillMaxWidth().padding(top = 36.dp), horizontalAlignment = Alignment.CenterHorizontally) {
    80	        Box(Modifier.size(64.dp).clip(CircleShape).background(t.chipBg), contentAlignment = Alignment.Center) {
    81	            Icon(Icons.Filled.AutoAwesome, contentDescription = null, tint = t.tint, modifier = Modifier.size(30.dp))
    82	        }
    83	        VSpace(18)
    84	        Text("Connect an AI provider", color = t.ink, fontFamily = BackupFonts.Serif, fontSize = 21.sp, textAlign = TextAlign.Center)
    85	        VSpace(8)
    86	        Text(
    87	            "One key unlocks bilingual translation, chat about a book, and chapter summaries. Your key is stored on-device only.",
    88	            color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 14.sp, lineHeight = 22.sp, textAlign = TextAlign.Center,
    89	        )
    90	        VSpace(18)
    91	        Box(
    92	            Modifier.fillMaxWidth().clip(RoundedCornerShape(13.dp)).background(t.tint)
    93	                .clickable(onClickLabel = "Add a provider", onClick = onAdd).testTag("ai-add-provider").padding(vertical = 14.dp),
    94	            contentAlignment = Alignment.Center,
    95	        ) { Text("Add a provider", color = Color.White, fontFamily = BackupFonts.Sans, fontSize = 15.sp, fontWeight = FontWeight.SemiBold) }
    96	        GroupFooter("Works with Anthropic, OpenAI-compatible endpoints, and local models.")
    97	    }
    98	}
    99	
   100	@Composable
   101	private fun ProviderRow(p: AiProviderRow, last: Boolean, onEdit: (String) -> Unit) {
   102	    val t = LocalBackupTokens.current
   103	    Box {
   104	        Row(
   105	            Modifier.fillMaxWidth().heightIn(min = 60.dp).clickable(onClick = { onEdit(p.id) })
   106	                .testTag("provider-${p.id}").padding(horizontal = 14.dp),
   107	            verticalAlignment = Alignment.CenterVertically,
   108	        ) {
   109	            // active = filled accent circle; inactive = hollow ring (sep ring + card-coloured core)
   110	            Box(
   111	                Modifier.size(20.dp).clip(CircleShape).background(if (p.active) t.tint else t.sep),
   112	                contentAlignment = Alignment.Center,
   113	            ) {
   114	                if (!p.active) Box(Modifier.size(16.5.dp).clip(CircleShape).background(t.card))
   115	            }
   116	            Column(Modifier.weight(1f).padding(start = 12.dp)) {
   117	                Text(p.name, color = t.ink, fontFamily = BackupFonts.Sans, fontSize = 15.5.sp, fontWeight = FontWeight.Medium)
   118	                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 2.dp)) {
   119	                    StatusDot(if (p.statusOk) t.green else t.red)
   120	                    Text(
   121	                        p.detail, color = if (p.statusOk) t.sec else t.red,
   122	                        fontFamily = BackupFonts.Mono, fontSize = 11.5.sp, modifier = Modifier.padding(start = 6.dp),
   123	                    )
   124	                }
   125	            }
   126	            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = t.ter, modifier = Modifier.size(18.dp))
   127	        }
   128	        if (!last) Box(Modifier.fillMaxWidth().padding(start = 46.dp).height(0.5.dp).background(t.sep).align(Alignment.BottomStart))
   129	    }
   130	}
     1	// Purpose: feature #118 WI-3 (#110 Phase 3) — the add/edit AI provider form (the committed
     2	// EditorSheet contract from vreader-ai-provider-fields.jsx): Provider Type (segmented) · Name ·
     3	// Endpoint (Base URL + Model, blank → kind default, with the path-append hint) · Sampling
     4	// (Temperature slider + Max Tokens stepper) · API Key (secure; edit shows Delete Key) · Connection
     5	// (Test — enabled once a key is available, idle/testing/ok/fail). Reuses the shared form
     6	// vocabulary; stateless: a pure function of AiEditState + callbacks.
     7	package com.vreader.app.ai
     8	
     9	import androidx.compose.foundation.background
    10	import androidx.compose.foundation.clickable
    11	import androidx.compose.foundation.gestures.detectTapGestures
    12	import androidx.compose.foundation.layout.Box
    13	import androidx.compose.foundation.layout.Column
    14	import androidx.compose.foundation.layout.Row
    15	import androidx.compose.foundation.layout.fillMaxSize
    16	import androidx.compose.foundation.layout.fillMaxWidth
    17	import androidx.compose.foundation.layout.height
    18	import androidx.compose.foundation.layout.heightIn
    19	import androidx.compose.foundation.layout.padding
    20	import androidx.compose.foundation.layout.size
    21	import androidx.compose.foundation.layout.sizeIn
    22	import androidx.compose.foundation.shape.CircleShape
    23	import androidx.compose.foundation.shape.RoundedCornerShape
    24	import androidx.compose.foundation.text.BasicTextField
    25	import androidx.compose.material3.Text
    26	import androidx.compose.runtime.Composable
    27	import androidx.compose.runtime.getValue
    28	import androidx.compose.runtime.mutableIntStateOf
    29	import androidx.compose.runtime.remember
    30	import androidx.compose.runtime.setValue
    31	import androidx.compose.ui.Alignment
    32	import androidx.compose.ui.Modifier
    33	import androidx.compose.ui.draw.clip
    34	import androidx.compose.ui.graphics.Color
    35	import androidx.compose.ui.graphics.SolidColor
    36	import androidx.compose.ui.input.pointer.pointerInput
    37	import androidx.compose.ui.layout.onSizeChanged
    38	import androidx.compose.ui.platform.LocalDensity
    39	import androidx.compose.ui.platform.testTag
    40	import androidx.compose.ui.text.TextStyle
    41	import androidx.compose.ui.text.font.FontWeight
    42	import androidx.compose.ui.text.input.PasswordVisualTransformation
    43	import androidx.compose.ui.text.input.VisualTransformation
    44	import androidx.compose.ui.unit.dp
    45	import androidx.compose.ui.unit.sp
    46	import com.vreader.app.backup.AppSheet
    47	import com.vreader.app.backup.BackupFonts
    48	import com.vreader.app.backup.GroupFooter
    49	import com.vreader.app.backup.GroupHeader
    50	import com.vreader.app.backup.LocalBackupTokens
    51	import com.vreader.app.backup.SettingsCard
    52	import com.vreader.app.backup.VSpace
    53	
    54	@Composable
    55	fun AiProviderEditSheet(
    56	    state: AiEditState,
    57	    onKind: (AiProviderKind) -> Unit = {},
    58	    onName: (String) -> Unit = {},
    59	    onBaseUrl: (String) -> Unit = {},
    60	    onModel: (String) -> Unit = {},
    61	    onTemperature: (Double) -> Unit = {},
    62	    onMaxTokens: (Int) -> Unit = {},
    63	    onApiKey: (String) -> Unit = {},
    64	    onDeleteKey: () -> Unit = {},
    65	    onTest: () -> Unit = {},
    66	    onSave: () -> Unit = {},
    67	    onCancel: () -> Unit = {},
    68	) {
    69	    val t = LocalBackupTokens.current
    70	    Box(Modifier.fillMaxSize()) {
    71	        AppSheet(
    72	            title = if (state.editMode) "Edit Provider" else "Add Provider",
    73	            leading = {
    74	                Box(Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp).clickable(onClick = onCancel), contentAlignment = Alignment.CenterStart) {
    75	                    Text("Cancel", color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 15.sp)
    76	                }
    77	            },
    78	            trailing = {
    79	                Box(Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp).clickable(enabled = state.canSave, onClick = onSave).testTag("ai-save"), contentAlignment = Alignment.CenterEnd) {
    80	                    Text("Save", color = if (state.canSave) t.tint else t.ter, fontFamily = BackupFonts.Sans, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
    81	                }
    82	            },
    83	        ) {
    84	            Column(Modifier.padding(horizontal = 18.dp).padding(top = 16.dp, bottom = 32.dp)) {
    85	                GroupHeader("Provider Type")
    86	                Segmented(state.kind, onKind)
    87	
    88	                VSpace(20)
    89	                GroupHeader("Name")
    90	                SettingsCard { Field("", state.name, "e.g. OpenRouter", onName) }
    91	
    92	                VSpace(20)
    93	                GroupHeader("Endpoint")
    94	                SettingsCard {
    95	                    Field("Base URL", state.baseUrl, state.kind.defaultBaseUrl, onBaseUrl, mono = true)
    96	                    Divider()
    97	                    Field("Model", state.model, state.kind.defaultModel, onModel)
    98	                }
    99	                GroupFooter(state.kind.endpointPathHint + "  Leave blank to use the default.")
   100	
   101	                VSpace(20)
   102	                GroupHeader("Sampling")
   103	                SettingsCard {
   104	                    TemperatureRow(state.temperature, onTemperature)
   105	                    Divider()
   106	                    MaxTokensRow(state.maxTokens, onMaxTokens)
   107	                }
   108	
   109	                VSpace(20)
   110	                GroupHeader("API Key")
   111	                SettingsCard {
   112	                    if (state.editMode && state.keyAlreadySaved && state.apiKey.isBlank()) {
   113	                        Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 14.dp), verticalAlignment = Alignment.CenterVertically) {
   114	                            Text("••••••••••••••", color = t.ink, fontFamily = BackupFonts.Sans, fontSize = 16.sp, modifier = Modifier.weight(1f))
   115	                            Box(Modifier.size(19.dp).clip(CircleShape).background(t.green))
   116	                        }
   117	                        Divider()
   118	                        Box(Modifier.fillMaxWidth().heightIn(min = 44.dp).clickable(onClick = onDeleteKey).padding(horizontal = 14.dp), contentAlignment = Alignment.CenterStart) {
   119	                            Text("Delete Key", color = t.red, fontFamily = BackupFonts.Sans, fontSize = 15.sp)
   120	                        }
   121	                    } else {
   122	                        Field("", state.apiKey, "Enter API Key", onApiKey, secure = true)
   123	                    }
   124	                }
   125	                if (!state.editMode) GroupFooter("Stored in the Android Keystore when you tap Save — but you can test it below first.")
   126	
   127	                VSpace(20)
   128	                GroupHeader("Connection")
   129	                SettingsCard {
   130	                    Row(Modifier.fillMaxWidth().padding(14.dp)) { TestChip(state.test, state.canTest, onTest) }
   131	                    if (state.test == AiConnTest.ok || state.test == AiConnTest.fail) TestResult(state.test, state.testMessage)
   132	                }
   133	                if (!state.canTest) GroupFooter("Enter an API key above to test — no need to save first.")
   134	            }
   135	        }
   136	    }
   137	}
   138	
   139	@Composable
   140	private fun Segmented(value: AiProviderKind, onChange: (AiProviderKind) -> Unit) {
   141	    val t = LocalBackupTokens.current
   142	    Row(Modifier.fillMaxWidth().padding(top = 8.dp).clip(RoundedCornerShape(12.dp)).background(t.codeBg).padding(3.dp)) {
   143	        AiProviderKind.entries.forEach { k ->
   144	            val on = k == value
   145	            Box(
   146	                Modifier.weight(1f).clip(RoundedCornerShape(10.dp)).background(if (on) t.card else Color.Transparent)
   147	                    .clickable { onChange(k) }.testTag("kind-${k.name}").padding(vertical = 9.dp),
   148	                contentAlignment = Alignment.Center,
   149	            ) {
   150	                Text(k.displayName, color = t.ink, fontFamily = BackupFonts.Sans, fontSize = 13.5.sp, fontWeight = if (on) FontWeight.SemiBold else FontWeight.Medium)
   151	            }
   152	        }
   153	    }
   154	}
   155	
   156	@Composable
   157	private fun Field(label: String, value: String, placeholder: String, onChange: (String) -> Unit, mono: Boolean = false, secure: Boolean = false) {
   158	    val t = LocalBackupTokens.current
   159	    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 14.dp), verticalAlignment = Alignment.CenterVertically) {
   160	        if (label.isNotEmpty()) Text(label, color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 15.sp, modifier = Modifier.padding(end = 10.dp))
   161	        BasicTextField(
   162	            value = value, onValueChange = onChange, singleLine = true,
   163	            textStyle = TextStyle(color = t.ink, fontFamily = if (mono) BackupFonts.Mono else BackupFonts.Sans, fontSize = if (mono) 13.5.sp else 15.sp),
   164	            cursorBrush = SolidColor(t.tint),
   165	            visualTransformation = if (secure) PasswordVisualTransformation() else VisualTransformation.None,
   166	            modifier = Modifier.weight(1f).testTag("field-${label.ifBlank { placeholder }}"),
   167	            decorationBox = { inner ->
   168	                Box(Modifier.fillMaxWidth(), contentAlignment = if (label.isEmpty()) Alignment.CenterStart else Alignment.CenterEnd) {
   169	                    if (value.isEmpty()) Text(placeholder, color = t.placeholder, fontFamily = if (mono) BackupFonts.Mono else BackupFonts.Sans, fontSize = if (mono) 13.5.sp else 15.sp)
   170	                    inner()
   171	                }
   172	            },
   173	        )
   174	    }
   175	}
   176	
   177	@Composable
   178	private fun Divider() {
   179	    val t = LocalBackupTokens.current
   180	    Box(Modifier.fillMaxWidth().padding(start = 14.dp).height(0.5.dp).background(t.sep))
   181	}
   182	
   183	@Composable
   184	private fun TemperatureRow(value: Double, onChange: (Double) -> Unit) {
   185	    val t = LocalBackupTokens.current
   186	    val density = LocalDensity.current
   187	    var trackPx by remember { mutableIntStateOf(0) }  // measured track width, in px
   188	    Column(Modifier.fillMaxWidth().padding(14.dp)) {
   189	        Row(verticalAlignment = Alignment.CenterVertically) {
   190	            Text("Temperature", color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 15.sp, modifier = Modifier.weight(1f))
   191	            Text("%.1f".format(value), color = t.ink, fontFamily = BackupFonts.Sans, fontSize = 15.sp)
   192	        }
   193	        // Custom track + thumb (0.0–2.0); tap maps x → value using the MEASURED width.
   194	        val frac = (value / 2.0).toFloat().coerceIn(0f, 1f)
   195	        Box(
   196	            Modifier.fillMaxWidth().padding(top = 14.dp, bottom = 4.dp).height(22.dp).testTag("temperature-slider")
   197	                .onSizeChanged { trackPx = it.width }
   198	                .pointerInput(Unit) {
   199	                    detectTapGestures { offset -> if (trackPx > 0) onChange(((offset.x / trackPx) * 2.0).coerceIn(0.0, 2.0)) }
   200	                },
   201	            contentAlignment = Alignment.CenterStart,
   202	        ) {
   203	            Box(Modifier.fillMaxWidth().height(4.dp).clip(RoundedCornerShape(2.dp)).background(t.sep))
   204	            Box(Modifier.fillMaxWidth(frac).height(4.dp).clip(RoundedCornerShape(2.dp)).background(t.tint))
   205	            val trackDp = with(density) { trackPx.toDp() }
   206	            val startPad = (trackDp * frac - 11.dp).coerceIn(0.dp, (trackDp - 22.dp).coerceAtLeast(0.dp))
   207	            Box(Modifier.padding(start = startPad).size(22.dp).clip(CircleShape).background(Color.White))
   208	        }
   209	    }
   210	}
   211	
   212	@Composable
   213	private fun MaxTokensRow(value: Int, onChange: (Int) -> Unit) {
   214	    val t = LocalBackupTokens.current
   215	    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 14.dp), verticalAlignment = Alignment.CenterVertically) {
   216	        Text("Max Tokens: $value", color = t.ink, fontFamily = BackupFonts.Sans, fontSize = 15.sp, modifier = Modifier.weight(1f))
   217	        Row(Modifier.clip(RoundedCornerShape(8.dp)).background(t.codeBg)) {
   218	            Box(Modifier.size(width = 42.dp, height = 30.dp).clickable(onClickLabel = "decrease", onClick = { onChange((value - 256).coerceAtLeast(256)) }).testTag("tokens-dec"), contentAlignment = Alignment.Center) {
   219	                Text("−", color = t.ink, fontSize = 19.sp)
   220	            }
   221	            Box(Modifier.size(width = 0.5.dp, height = 30.dp).background(t.sep))
   222	            Box(Modifier.size(width = 42.dp, height = 30.dp).clickable(onClickLabel = "increase", onClick = { onChange((value + 256).coerceAtMost(8192)) }).testTag("tokens-inc"), contentAlignment = Alignment.Center) {
   223	                Text("+", color = t.ink, fontSize = 19.sp)
   224	            }
   225	        }
   226	    }
   227	}
   228	
   229	@Composable
   230	private fun TestChip(test: AiConnTest, enabled: Boolean, onTest: () -> Unit) {
   231	    val t = LocalBackupTokens.current
   232	    val label = if (test == AiConnTest.testing) "Testing…" else "Test Connection"
   233	    Box(
   234	        Modifier.clip(RoundedCornerShape(100.dp)).background(if (enabled) t.chipBg else Color.Transparent)
   235	            .clickable(enabled = enabled && test != AiConnTest.testing, onClick = onTest).testTag("ai-test")
   236	            .padding(horizontal = 15.dp, vertical = 8.dp),
   237	    ) {
   238	        Text(label, color = if (enabled) t.tint else t.ter, fontFamily = BackupFonts.Sans, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
   239	    }
   240	}
   241	
   242	@Composable
   243	private fun TestResult(test: AiConnTest, message: String) {
   244	    val t = LocalBackupTokens.current
   245	    val ok = test == AiConnTest.ok
   246	    val fallback = if (ok) "Connected — the provider responded successfully." else "Failed: 401 Unauthorized — check your API key."
   247	    Row(Modifier.fillMaxWidth().padding(start = 14.dp, end = 14.dp, bottom = 14.dp), verticalAlignment = Alignment.Top) {
   248	        Box(Modifier.size(16.dp).clip(CircleShape).background(if (ok) t.green else t.red))
   249	        Text(message.ifBlank { fallback }, color = if (ok) t.green else t.red, fontFamily = BackupFonts.Sans, fontSize = 13.sp, lineHeight = 19.sp, modifier = Modifier.padding(start = 7.dp).testTag("ai-test-result"))
   250	    }
   251	}

exec
/bin/zsh -lc "nl -ba android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt | sed -n '38,220p'
nl -ba android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsViewModel.kt | sed -n '1,260p'
nl -ba android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderChromeScaffold.kt | sed -n '1,340p'
nl -ba android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderChromeState.kt | sed -n '1,260p'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
    38	@Serializable
    39	private data class AiStoreState(val profiles: List<AiProviderProfile> = emptyList(), val activeId: String? = null)
    40	
    41	class AiProviderStore(
    42	    private val dataStore: DataStore<Preferences>,
    43	    private val cipher: SecretCipher,
    44	    private val json: Json = Json { ignoreUnknownKeys = true; encodeDefaults = true },
    45	) {
    46	    /** One consistent profiles + active-id view (read once at request start). */
    47	    suspend fun snapshot(): AiProviderSnapshot = read(dataStore.data.first()).toSnapshot()
    48	
    49	    fun observe(): Flow<AiProviderSnapshot> = dataStore.data.map { read(it).toSnapshot() }
    50	
    51	    suspend fun list(): List<AiProviderProfile> = snapshot().profiles
    52	
    53	    suspend fun activeProfile(): AiProviderProfile? = snapshot().active
    54	
    55	    /**
    56	     * Insert/update a profile by [id]. [apiKey] is the PLAINTEXT to encrypt; pass null on an edit
    57	     * that leaves the key unchanged (the existing ciphertext is kept). A brand-new id REQUIRES a
    58	     * key. The first profile added becomes active. Returns the saved profile (key encrypted).
    59	     */
    60	    suspend fun upsert(
    61	        id: String,
    62	        name: String,
    63	        kind: AiProviderKind,
    64	        baseUrl: String,
    65	        model: String,
    66	        temperature: Double,
    67	        maxTokens: Int,
    68	        apiKey: String?,
    69	    ): AiProviderProfile {
    70	        lateinit var saved: AiProviderProfile
    71	        dataStore.edit { prefs ->
    72	            val cur = read(prefs)
    73	            val existing = cur.profiles.firstOrNull { it.id == id }
    74	            val encrypted = when {
    75	                apiKey != null -> cipher.encrypt(apiKey)
    76	                existing != null -> existing.encryptedApiKey  // unchanged on edit
    77	                else -> throw IllegalArgumentException("a new provider ($id) requires an API key")
    78	            }
    79	            saved = AiProviderProfile(id, name, kind, baseUrl, model, temperature, maxTokens, encrypted)
    80	            val next = cur.profiles.filterNot { it.id == id } + saved
    81	            val activeId = cur.activeId ?: id  // first provider becomes active
    82	            prefs[KEY] = json.encodeToString(AiStoreState(next, activeId))
    83	        }
    84	        return saved
    85	    }
    86	
    87	    /** Remove a profile. If it was active, the active selection moves to the first remaining (or null). */
    88	    suspend fun delete(id: String) {
    89	        dataStore.edit { prefs ->
    90	            val cur = read(prefs)
    91	            val next = cur.profiles.filterNot { it.id == id }
    92	            val activeId = if (cur.activeId == id) next.firstOrNull()?.id else cur.activeId
    93	            prefs[KEY] = json.encodeToString(AiStoreState(next, activeId))
    94	        }
    95	    }
    96	
    97	    /** Select the active provider (no-op if the id isn't present). */
    98	    suspend fun setActive(id: String) {
    99	        dataStore.edit { prefs ->
   100	            val cur = read(prefs)
   101	            if (cur.profiles.any { it.id == id }) prefs[KEY] = json.encodeToString(cur.copy(activeId = id))
   102	        }
   103	    }
   104	
   105	    /** Decrypt the key from a CAPTURED [profile] — snapshot-consistent (no live store read). The
   106	     *  chat/test request path uses THIS with a profile from a single [snapshot], so it can't pair
   107	     *  snapshot metadata with a concurrently-edited/deleted key. */
   108	    fun apiKey(profile: AiProviderProfile): String = cipher.decrypt(profile.encryptedApiKey)
   109	
   110	    /** The decrypted API key for [id] via a live read, or null if absent. Convenience for UI flows
   111	     *  that aren't mid-request; the request path should prefer [apiKey] (profile). */
   112	    suspend fun apiKey(id: String): String? =
   113	        list().firstOrNull { it.id == id }?.let { cipher.decrypt(it.encryptedApiKey) }
   114	
   115	    private fun read(prefs: Preferences): AiStoreState {
   116	        val raw = prefs[KEY] ?: return AiStoreState()
   117	        return runCatching { json.decodeFromString<AiStoreState>(raw) }.getOrDefault(AiStoreState())
   118	    }
   119	
   120	    private fun AiStoreState.toSnapshot() = AiProviderSnapshot(profiles, activeId)
   121	
   122	    companion object {
   123	        private val KEY = stringPreferencesKey("ai_providers_json")
   124	    }
   125	}
     1	// Purpose: feature #118 WI-3 (#110 Phase 3) — drives the AI provider list + editor: observes the
     2	// AiProviderStore for the list, owns the editor form state, runs Test Connection against the LIVE
     3	// form (a transient AiClient built from the form + key, no save first), and saves/deletes. v1 list
     4	// status is ok+model (persisted per-provider test status is a follow-on). The key is never logged.
     5	package com.vreader.app.ai
     6	
     7	import androidx.lifecycle.ViewModel
     8	import androidx.lifecycle.viewModelScope
     9	import kotlinx.coroutines.CoroutineDispatcher
    10	import kotlinx.coroutines.Dispatchers
    11	import kotlinx.coroutines.flow.MutableStateFlow
    12	import kotlinx.coroutines.flow.SharingStarted
    13	import kotlinx.coroutines.flow.StateFlow
    14	import kotlinx.coroutines.flow.map
    15	import kotlinx.coroutines.flow.stateIn
    16	import kotlinx.coroutines.launch
    17	import kotlinx.coroutines.withContext
    18	import java.util.UUID
    19	
    20	class AiSettingsViewModel(
    21	    private val store: AiProviderStore,
    22	    private val clientDispatcher: CoroutineDispatcher = Dispatchers.IO,
    23	    private val factory: (AiProviderProfile, String) -> AiClient = { p, key -> AiProviderFactory.create(p, key) },
    24	) : ViewModel() {
    25	
    26	    val listState: StateFlow<AiProviderListState> = store.observe()
    27	        .map { snap ->
    28	            AiProviderListState(
    29	                snap.profiles.map { p ->
    30	                    AiProviderRow(p.id, p.name, active = p.id == snap.activeId, statusOk = true, detail = p.model.ifBlank { p.kind.defaultModel })
    31	                }
    32	            )
    33	        }
    34	        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), AiProviderListState())
    35	
    36	    private val _edit = MutableStateFlow<AiEditState?>(null)
    37	    val editState: StateFlow<AiEditState?> = _edit
    38	
    39	    // Bumped whenever the editor opens/closes or a new test starts — an in-flight test result is
    40	    // only applied if its generation still matches, so a stale Ok/Fail can't land on a different
    41	    // form (the user closed it, opened another provider, or re-tested).
    42	    private var testGen = 0
    43	
    44	    fun openAdd() { testGen++; _edit.value = AiEditState(editMode = false) }
    45	
    46	    fun openEdit(id: String) = viewModelScope.launch {
    47	        val p = store.list().firstOrNull { it.id == id } ?: return@launch
    48	        testGen++
    49	        _edit.value = AiEditState(
    50	            editMode = true, id = p.id, kind = p.kind, name = p.name, baseUrl = p.baseUrl, model = p.model,
    51	            temperature = p.temperature, maxTokens = p.maxTokens, keyAlreadySaved = true,
    52	        )
    53	    }
    54	
    55	    fun close() { testGen++; _edit.value = null }
    56	
    57	    fun update(transform: (AiEditState) -> AiEditState) { _edit.value = _edit.value?.let(transform) }
    58	
    59	    fun test() {
    60	        val s = _edit.value ?: return
    61	        if (!s.canTest) return
    62	        val gen = ++testGen
    63	        update { it.copy(test = AiConnTest.testing, testMessage = "") }
    64	        viewModelScope.launch {
    65	            // Key lookup + client creation + the network call all off the main thread.
    66	            val result = withContext(clientDispatcher) {
    67	                val key = if (s.apiKey.isNotBlank()) s.apiKey else s.id?.let { store.apiKey(it) } ?: ""
    68	                val profile = AiProviderProfile(
    69	                    id = s.id ?: "transient", name = s.name, kind = s.kind, baseUrl = s.effectiveBaseUrl,
    70	                    model = s.effectiveModel, temperature = s.temperature, maxTokens = s.maxTokens, encryptedApiKey = "",
    71	                )
    72	                runCatching { factory(profile, key).testConnection() }
    73	                    .getOrElse { AiTestResult.Fail(AiError.Offline, it.message ?: "failed") }
    74	            }
    75	            if (gen != testGen) return@launch  // superseded by a newer test / form open / close
    76	            update {
    77	                when (result) {
    78	                    is AiTestResult.Ok -> it.copy(test = AiConnTest.ok, testMessage = "Connected — the provider responded successfully.")
    79	                    is AiTestResult.Fail -> it.copy(test = AiConnTest.fail, testMessage = result.message)
    80	                }
    81	            }
    82	        }
    83	    }
    84	
    85	    fun save() {
    86	        val s = _edit.value ?: return
    87	        if (!s.canSave) return
    88	        viewModelScope.launch {
    89	            store.upsert(
    90	                id = s.id ?: UUID.randomUUID().toString(),
    91	                name = s.name, kind = s.kind, baseUrl = s.baseUrl, model = s.model,
    92	                temperature = s.temperature, maxTokens = s.maxTokens,
    93	                apiKey = s.apiKey.ifBlank { null },  // blank on edit = keep existing
    94	            )
    95	            _edit.value = null
    96	        }
    97	    }
    98	
    99	    fun delete() {
   100	        val id = _edit.value?.id ?: return
   101	        viewModelScope.launch { store.delete(id); _edit.value = null }
   102	    }
   103	
   104	    fun setActive(id: String) = viewModelScope.launch { store.setActive(id) }
   105	}
     1	// Purpose: feature #132 WI-5 (#110 Phase 3) — the host-agnostic reader chrome scaffold that stitches
     2	// the designed reader chrome + modal sheets over any reader body. It stacks [ReaderTopChrome] (WI-2) at
     3	// the top, the host's [body] filling the middle, and the host's [bottomChrome] at the bottom — passing
     4	// the Contents/Notes open callbacks INTO the bottom-chrome slot so the host wires them without reaching
     5	// into scaffold state. A center-tap on the body toggles chrome visibility (the top + bottom bars hide
     6	// together). It hosts the modal sheets driven by the hoisted [ReaderChromeState.sheet]:
     7	// [ReaderSheet.Toc] → the #135 WI-6 [TocBookmarksSheet] (the promoted two-tab Contents|Bookmarks sheet,
     8	// which REUSES #132's Contents body), [ReaderSheet.Notes] → the WI-4 [AnnotationsReviewSheet], and —
     9	// feature #134 WI-5 — [ReaderSheet.Details] → the WI-4 [BookDetailsSheet]. The top-bar More button
    10	// (rendered iff [bookDetails] is non-null) toggles the WI-3 [MorePopup] carrying ONLY the Details + Share
    11	// rows (the §more-row-ownership contract — TTS/Auto-turn/Bilingual/Export belong to other features):
    12	// Details opens the Details sheet, Share fires [onShareBook], and the Details sheet's copy-fingerprint
    13	// mini-action fires [onCopyFingerprint] (the host copies to the OS clipboard — no invented toast, rule 51).
    14	// The Contents control is HIDDEN when [tocEntries] is empty (the scaffold passes a null open callback,
    15	// so the bottom chrome omits it — the no-dead-controls rule). feature #135 WI-5 — the top-bar bookmark
    16	// toggle: when [onToggleBookmark] is non-null the scaffold fills [ReaderTopChrome]'s reserved bookmark
    17	// slot with the WI-5 [BookmarkToggleButton] (filled/outline by [isCurrentBookmarked]); a null callback
    18	// omits it (the #129 no-dead-control rule → #132 Contents/Notes-only callers stay back-compatible). feature
    19	// #135 WI-6 — the promoted two-tab TOC sheet: the [ReaderSheet.Toc] route now renders [TocBookmarksSheet]
    20	// (Contents|Bookmarks), and [bookmarks]/[onJumpBookmark] feed its Bookmarks tab (nullable/defaulted → #132
    21	// Contents/Notes-only callers stay valid); the [ReaderSheet.Bookmarks] route opens the SAME two-tab sheet
    22	// (host wiring feeds the data in WI-7). [currentLocator] is threaded for the host to derive presence but the
    23	// scaffold does not read it. Pure function of hoisted state + callbacks (rule 50 §4); same [ReaderTheme]
    24	// token map as the reader chrome.
    25	package com.vreader.app.reader.chrome
    26	
    27	import androidx.compose.foundation.background
    28	import androidx.compose.foundation.gestures.detectTapGestures
    29	import androidx.compose.foundation.layout.Box
    30	import androidx.compose.foundation.layout.Column
    31	import androidx.compose.foundation.layout.fillMaxSize
    32	import androidx.compose.foundation.layout.fillMaxWidth
    33	import androidx.compose.material.icons.Icons
    34	import androidx.compose.material.icons.filled.Info
    35	import androidx.compose.material.icons.filled.Share
    36	import androidx.compose.runtime.Composable
    37	import androidx.compose.runtime.MutableState
    38	import androidx.compose.runtime.getValue
    39	import androidx.compose.runtime.mutableStateOf
    40	import androidx.compose.runtime.remember
    41	import androidx.compose.runtime.setValue
    42	import androidx.compose.ui.Modifier
    43	import androidx.compose.ui.input.pointer.pointerInput
    44	import com.vreader.app.annotations.AnnotationItem
    45	import com.vreader.app.annotations.AnnotationsReviewSheet
    46	import com.vreader.app.annotations.AnnotationsSnapshot
    47	import com.vreader.app.reader.details.BookDetailsSheet
    48	import com.vreader.app.reader.details.BookDetailsUiModel
    49	import com.vreader.app.annotations.BookmarkRecord
    50	import com.vreader.app.reader.more.MoreActionId
    51	import com.vreader.app.reader.more.MorePopup
    52	import com.vreader.app.reader.more.MoreRow
    53	import com.vreader.app.reader.nav.BookmarkRowItem
    54	import com.vreader.app.reader.nav.JumpResult
    55	import com.vreader.app.reader.nav.TocBookmarksSheet
    56	import com.vreader.app.reader.nav.TocEntry
    57	import com.vreader.app.reader.nav.TocTab
    58	import com.vreader.app.reader.settings.ReaderTheme
    59	import vreader.contracts.Locator
    60	
    61	/**
    62	 * The host-agnostic reader chrome scaffold. [chromeState] is the hoisted [ReaderChromeState]
    63	 * (visibility + open sheet). [title] fills the top bar; [onBack] fires the "‹ Library" control;
    64	 * [onOpenSearch] populates the top-bar Search slot (null → omitted; #133); [topBookmarkSlot] fills the
    65	 * top-bar bookmark slot (null in #132; #135). [tocEntries]/[currentTocIndex] drive the Contents sheet
    66	 * (empty entries → the Contents control is hidden). [annotations] is the one-shot snapshot for the Notes
    67	 * sheet; [onJumpToc] performs a TOC jump (returns success for dismiss-on-success); [onJumpToAnnotation] is
    68	 * the capability-based nullable annotation jump; [onShareAnnotations] is the Notes sheet-level Share.
    69	 *
    70	 * feature #134 WI-5 — the top-bar More menu + Book Details: when [bookDetails] is non-null the top-bar
    71	 * More button appears and toggles the WI-3 [MorePopup] carrying ONLY the Details + Share rows; tapping
    72	 * Details opens the [ReaderSheet.Details] sheet (the WI-4 [BookDetailsSheet] over [bookDetails]), tapping
    73	 * Share fires [onShareBook], and the Details sheet's copy-fingerprint mini-action fires [onCopyFingerprint]
    74	 * (the host copies to the OS clipboard — no invented copy-confirmation UI, rule 51). When [bookDetails] is
    75	 * null the More button is omitted (no dead control) — a caller-supplied [onOpenMore] still populates the
    76	 * More slot for hosts that want a different More action.
    77	 *
    78	 * feature #135 WI-5 — the top-bar bookmark toggle: when [onToggleBookmark] is non-null the scaffold fills
    79	 * [ReaderTopChrome]'s reserved bookmark slot with the WI-5 [BookmarkToggleButton], rendered filled/outline
    80	 * by [isCurrentBookmarked]; a null callback omits the slot (the #129 no-dead-control rule → #132
    81	 * Contents/Notes-only callers stay valid). [currentLocator] is the current reading position the host uses
    82	 * to derive presence + create the bookmark (threaded through for WI-7's host wiring; the scaffold itself
    83	 * does not read it). A host that passes [topBookmarkSlot] directly overrides the built toggle (kept for
    84	 * symmetry with [onOpenMore]).
    85	 *
    86	 * feature #135 WI-6 — the promoted two-tab TOC sheet: [ReaderSheet.Toc] renders [TocBookmarksSheet]
    87	 * (Contents|Bookmarks, the Contents tab REUSING #132's body), and [ReaderSheet.Bookmarks] opens the same
    88	 * sheet with the Bookmarks tab pre-selected. [bookmarks] are the projected Bookmarks-tab rows (default
    89	 * empty); [onJumpBookmark] is the capability-based nullable bookmark jump (non-null → clickable rows +
    90	 * dismiss-on-Succeeded; null → review-only, non-clickable rows, NO dead no-op). Both are nullable/defaulted
    91	 * so #132 Contents/Notes-only callers stay valid (WI-7 feeds them per host).
    92	 *
    93	 * [bottomChrome] receives the Contents/Notes open callbacks (a null Contents callback when [tocEntries] is
    94	 * empty) and renders the reader's bottom chrome. [body] is the reader content; a center-tap on it toggles
    95	 * [ReaderChromeState.chromeVisible].
    96	 */
    97	@Composable
    98	fun ReaderChromeScaffold(
    99	    theme: ReaderTheme,
   100	    title: String,
   101	    chromeState: MutableState<ReaderChromeState>,
   102	    onBack: () -> Unit,
   103	    tocEntries: List<TocEntry>,
   104	    currentTocIndex: Int,
   105	    annotations: AnnotationsSnapshot,
   106	    onJumpToc: (Int) -> Boolean,
   107	    onJumpToAnnotation: ((AnnotationItem) -> Unit)?,
   108	    onShareAnnotations: () -> Unit,
   109	    bottomChrome: @Composable (onOpenContents: (() -> Unit)?, onOpenNotes: (() -> Unit)?) -> Unit,
   110	    body: @Composable () -> Unit,
   111	    modifier: Modifier = Modifier,
   112	    onOpenSearch: (() -> Unit)? = null,
   113	    onOpenMore: (() -> Unit)? = null,
   114	    isCurrentBookmarked: Boolean = false,
   115	    onToggleBookmark: (() -> Unit)? = null,
   116	    currentLocator: Locator? = null,
   117	    topBookmarkSlot: (@Composable () -> Unit)? = null,
   118	    bookmarks: List<BookmarkRowItem> = emptyList(),
   119	    onJumpBookmark: ((BookmarkRecord) -> JumpResult)? = null,
   120	    bookDetails: BookDetailsUiModel? = null,
   121	    onShareBook: () -> Unit = {},
   122	    onCopyFingerprint: (String) -> Unit = {},
   123	) {
   124	    val state = chromeState.value
   125	
   126	    // feature #135 WI-5 — build the top-bar bookmark slot from the WI-5 [BookmarkToggleButton] when the
   127	    // host opts in via [onToggleBookmark]. An explicit [topBookmarkSlot] (rare) wins; otherwise a non-null
   128	    // toggle synthesizes the button, and a null toggle leaves the slot empty (no dead control).
   129	    val bookmarkSlot: (@Composable () -> Unit)? = when {
   130	        topBookmarkSlot != null -> topBookmarkSlot
   131	        onToggleBookmark != null -> {
   132	            { BookmarkToggleButton(theme = theme, isBookmarked = isCurrentBookmarked, onToggle = onToggleBookmark) }
   133	        }
   134	        else -> null
   135	    }
   136	
   137	    // Sheet transitions read `chromeState.value` FRESH (never the composed-time [state] snapshot) so a
   138	    // rapid open/dismiss can't clobber a concurrent visibility toggle.
   139	    fun openSheet(sheet: ReaderSheet) { chromeState.value = chromeState.value.copy(sheet = sheet) }
   140	
   141	    // Contents is available only when there IS a table of contents; an empty TOC hides the control
   142	    // (the scaffold hands the bottom chrome a null open callback, so it omits it — no dead control).
   143	    val onOpenContents: (() -> Unit)? =
   144	        if (tocEntries.isEmpty()) null else { { openSheet(ReaderSheet.Toc) } }
   145	    val onOpenNotes: () -> Unit = { openSheet(ReaderSheet.Notes) }
   146	
   147	    // feature #134 WI-5 — the More menu is available only when this host has a Book-details data source.
   148	    // The scaffold owns the popup-open state so the More button toggles it; a null [bookDetails] omits the
   149	    // button (no dead control), falling back to any caller-supplied [onOpenMore].
   150	    var showMore by remember { mutableStateOf(false) }
   151	    val onMore: (() -> Unit)? = when {
   152	        bookDetails != null -> { { showMore = true } }
   153	        else -> onOpenMore
   154	    }
   155	
   156	    Column(modifier.fillMaxSize().background(theme.background)) {
   157	        if (state.chromeVisible) {
   158	            ReaderTopChrome(
   159	                theme = theme,
   160	                title = title,
   161	                onBack = onBack,
   162	                onSearch = onOpenSearch,
   163	                onMore = onMore,
   164	                bookmarkSlot = bookmarkSlot,
   165	            )
   166	        }
   167	
   168	        // Body — fills the space between the bars; a center-tap toggles the chrome visibility.
   169	        Box(
   170	            Modifier
   171	                .fillMaxWidth()
   172	                .weight(1f)
   173	                .pointerInput(Unit) {
   174	                    detectTapGestures { chromeState.value = chromeState.value.copy(chromeVisible = !chromeState.value.chromeVisible) }
   175	                },
   176	        ) {
   177	            body()
   178	        }
   179	
   180	        if (state.chromeVisible) {
   181	            bottomChrome(onOpenContents, onOpenNotes)
   182	        }
   183	    }
   184	
   185	    // feature #134 WI-5 — the More popover (Details + Share only). Details opens the Details sheet; Share
   186	    // fires the host's book-share flow. Dismisses on a backdrop tap or after either action.
   187	    if (showMore && bookDetails != null) {
   188	        MorePopup(
   189	            theme = theme,
   190	            rows = readerMoreRows(
   191	                onDetails = { showMore = false; openSheet(ReaderSheet.Details) },
   192	                onShare = { showMore = false; onShareBook() },
   193	            ),
   194	            onDismiss = { showMore = false },
   195	        )
   196	    }
   197	
   198	    // Modal sheets — driven by the hoisted open-sheet state. Dismiss returns to [ReaderSheet.None].
   199	    // feature #135 WI-6 — [onJumpBookmark] is passed through nullable (capability-gated); an unwired host
   200	    // (#132/#134/#135-WI-5 callers) passes null → the Bookmarks-tab rows are review-only, NOT clickable
   201	    // dead rows (WI-7 supplies the real per-host jump).
   202	    when (state.sheet) {
   203	        ReaderSheet.None -> Unit
   204	        // feature #135 WI-6 — the promoted two-tab TOC sheet (Contents|Bookmarks). The Contents tab REUSES
   205	        // #132's TocContentsSheet body unchanged; the Bookmarks tab renders [bookmarks].
   206	        ReaderSheet.Toc -> TocBookmarksSheet(
   207	            theme = theme,
   208	            bookTitle = title,
   209	            entries = tocEntries,
   210	            currentTocIndex = currentTocIndex,
   211	            bookmarks = bookmarks,
   212	            onJumpToc = onJumpToc,
   213	            onJumpBookmark = onJumpBookmark,
   214	            onDismiss = { openSheet(ReaderSheet.None) },
   215	        )
   216	        ReaderSheet.Notes -> AnnotationsReviewSheet(
   217	            theme = theme,
   218	            snapshot = annotations,
   219	            onShareAll = onShareAnnotations,
   220	            onJumpToAnnotation = onJumpToAnnotation,
   221	            onDismiss = { openSheet(ReaderSheet.None) },
   222	        )
   223	        // Render the Details sheet only when there IS a model; a Details route with no model (should not
   224	        // happen — the route is only reachable when [bookDetails] fed the More menu) is a safe no-op.
   225	        ReaderSheet.Details -> if (bookDetails != null) BookDetailsSheet(
   226	            theme = theme,
   227	            model = bookDetails,
   228	            onCopyFingerprint = onCopyFingerprint,
   229	            onShare = onShareBook,
   230	            onDismiss = { openSheet(ReaderSheet.None) },
   231	        )
   232	        // feature #135 WI-6 — the Bookmarks route opens the SAME two-tab sheet with the Bookmarks tab
   233	        // pre-selected (the designed [TocBookmarksSheet]; rule 51 — no invented list surface).
   234	        ReaderSheet.Bookmarks -> TocBookmarksSheet(
   235	            theme = theme,
   236	            bookTitle = title,
   237	            entries = tocEntries,
   238	            currentTocIndex = currentTocIndex,
   239	            bookmarks = bookmarks,
   240	            onJumpToc = onJumpToc,
   241	            onJumpBookmark = onJumpBookmark,
   242	            onDismiss = { openSheet(ReaderSheet.None) },
   243	            initialTab = TocTab.Bookmarks,
   244	        )
   245	    }
   246	}
   247	
   248	/**
   249	 * feature #134 WI-5 — the reader More-menu rows the scaffold + the EPUB chrome feed to the WI-3
   250	 * [MorePopup]. #134 owns ONLY the Details + Share rows (the design's `vreader-more.jsx` `Book details` /
   251	 * `Share book` actions); TTS / Auto-turn / Bilingual / Export are OTHER features' rows and are never
   252	 * invented here (the §more-row-ownership contract + the #129 no-dead-control rule — the popup renders only
   253	 * the rows it is given). Pure function of its two callbacks (no Compose runtime beyond the icon refs).
   254	 */
   255	internal fun readerMoreRows(onDetails: () -> Unit, onShare: () -> Unit): List<MoreRow> = listOf(
   256	    MoreRow.Action(id = MoreActionId.DETAILS, label = "Book details", icon = Icons.Filled.Info, onTap = onDetails),
   257	    MoreRow.Action(id = MoreActionId.SHARE, label = "Share book", icon = Icons.Filled.Share, onTap = onShare),
   258	)
     1	// Purpose: feature #132 WI-5 (#110 Phase 3) — the host-agnostic reader chrome state consumed by
     2	// [ReaderChromeScaffold]: whether the top/bottom chrome is visible, and which modal sheet (if any) is
     3	// open. #132 ships the Contents + Notes sheet routes; #134 WI-5 adds the [Details] (Book details) route
     4	// reached from the top-bar More menu; #135 WI-5 adds the [Bookmarks] route (the token/Saver land here so
     5	// the route survives process death; the designed Bookmarks LIST surface is WI-6's TocBookmarksSheet, so
     6	// WI-5's render of this route is a no-op — no dead route until it has a data source).
     7	// Persisted across rotation / process death via [ReaderChromeStateSaver] — a custom
     8	// `Saver<ReaderChromeState, String>` mirroring #127's `SheetRouteSaver` (library/CollectionSheets.kt),
     9	// because `rememberSaveable` cannot auto-persist an arbitrary class. Any unrecognized/malformed token
    10	// restores to the safe fallback (`chromeVisible=false`, `sheet=None`) and NEVER throws.
    11	package com.vreader.app.reader.chrome
    12	
    13	import androidx.compose.runtime.saveable.Saver
    14	
    15	/**
    16	 * Which modal sheet the reader chrome currently shows. #132 has Contents ([Toc]) and Notes; #134 WI-5
    17	 * adds [Details] (the Book details sheet, opened from the More menu); #135 WI-5 adds [Bookmarks] (the
    18	 * two-tab TOC sheet's Bookmarks surface — routed here so it persists across process death; WI-6 renders
    19	 * the designed surface, so WI-5 treats this route as a documented no-op).
    20	 */
    21	sealed interface ReaderSheet {
    22	    data object None : ReaderSheet
    23	    data object Toc : ReaderSheet
    24	    data object Notes : ReaderSheet
    25	    data object Details : ReaderSheet
    26	    data object Bookmarks : ReaderSheet
    27	}
    28	
    29	/**
    30	 * Hoisted reader-chrome UI state. [chromeVisible] toggles the top/bottom bars (a center-tap on the body
    31	 * flips it); [sheet] names the open modal sheet (default [ReaderSheet.None]). Defaults to chrome VISIBLE
    32	 * with no sheet — the reader opens with its chrome shown.
    33	 */
    34	data class ReaderChromeState(
    35	    val chromeVisible: Boolean = true,
    36	    val sheet: ReaderSheet = ReaderSheet.None,
    37	)
    38	
    39	/** The stable token for a [ReaderSheet] (used by [ReaderChromeStateSaver]; `None` never appears in a token). */
    40	private fun ReaderSheet.token(): String = when (this) {
    41	    ReaderSheet.None -> "none"
    42	    ReaderSheet.Toc -> "toc"
    43	    ReaderSheet.Notes -> "notes"
    44	    ReaderSheet.Details -> "details"
    45	    ReaderSheet.Bookmarks -> "bookmarks"
    46	}
    47	
    48	/** Parses a sheet token; any unknown value falls back to [ReaderSheet.None] (never throws). */
    49	private fun sheetFromToken(token: String): ReaderSheet = when (token) {
    50	    "toc" -> ReaderSheet.Toc
    51	    "notes" -> ReaderSheet.Notes
    52	    "details" -> ReaderSheet.Details
    53	    "bookmarks" -> ReaderSheet.Bookmarks
    54	    else -> ReaderSheet.None
    55	}
    56	
    57	/**
    58	 * Serializes [ReaderChromeState] to a `"<visible>|<sheet>"` String so `rememberSaveable` survives
    59	 * process death — the #127 `SheetRouteSaver` pattern. Restore is total: a malformed/empty/unknown token
    60	 * (wrong separator, non-boolean flag, unknown sheet name) restores to the safe fallback
    61	 * (`chromeVisible=false`, `sheet=None`) rather than throwing.
    62	 */
    63	val ReaderChromeStateSaver: Saver<ReaderChromeState, String> = Saver(
    64	    save = { "${it.chromeVisible}|${it.sheet.token()}" },
    65	    restore = { token ->
    66	        val parts = token.split("|")
    67	        if (parts.size != 2) {
    68	            ReaderChromeState(chromeVisible = false, sheet = ReaderSheet.None)
    69	        } else {
    70	            val visible = parts[0].toBooleanStrictOrNull() ?: false
    71	            ReaderChromeState(chromeVisible = visible, sheet = sheetFromToken(parts[1]))
    72	        }
    73	    },
    74	)

exec
/bin/zsh -lc "rg -n \"enum class MoreActionId|sealed interface MoreRow|sealed class MoreRow|data class Disabled|fun MoreRowItem|MoreRowItem|onClick\" android/app/src/main/kotlin/com/vreader/app/reader/more android/app/src/main/kotlin/com/vreader/app/reader
nl -ba android/app/src/main/kotlin/com/vreader/app/reader/more/MorePopup.kt | sed -n '1,300p'
nl -ba android/app/src/main/kotlin/com/vreader/app/reader/EpubReaderChrome.kt | sed -n '1,360p'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
android/app/src/main/kotlin/com/vreader/app/reader/more/MorePopup.kt:86:                    .clickable(onClick = onDismiss)
android/app/src/main/kotlin/com/vreader/app/reader/more/MorePopup.kt:110:                    rows.forEach { row -> MoreRowItem(theme, row) }
android/app/src/main/kotlin/com/vreader/app/reader/more/MorePopup.kt:128:private fun MoreRowItem(theme: ReaderTheme, row: MoreRow) {
android/app/src/main/kotlin/com/vreader/app/reader/more/MorePopup.kt:139:            enabled = true, onClick = row.onTap,
android/app/src/main/kotlin/com/vreader/app/reader/more/MorePopup.kt:146:            enabled = false, dim = true, subBold = true, onClick = {},
android/app/src/main/kotlin/com/vreader/app/reader/more/MorePopup.kt:153:            enabled = true, active = row.on, onClick = { row.onToggle(!row.on) },
android/app/src/main/kotlin/com/vreader/app/reader/more/MorePopup.kt:184:    onClick: () -> Unit,
android/app/src/main/kotlin/com/vreader/app/reader/more/MorePopup.kt:192:    val rowModifier = if (enabled) base.clickable(onClick = onClick) else base
android/app/src/main/kotlin/com/vreader/app/reader/more/MoreRow.kt:19:enum class MoreActionId {
android/app/src/main/kotlin/com/vreader/app/reader/more/MoreRow.kt:41:sealed interface MoreRow {
android/app/src/main/kotlin/com/vreader/app/reader/more/MoreRow.kt:66:    data class Disabled(
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderScreen.kt:88:                Modifier.heightIn(min = 48.dp).clip(RoundedCornerShape(8.dp)).clickable(onClickLabel = "Library", onClick = onBack).padding(horizontal = 6.dp),
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderScreen.kt:244:                    .clickable(onClick = onOpenNotes)
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocBookmarksSheet.kt:266:                onClick = onJumpBookmark?.let { jump ->
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocBookmarksSheet.kt:278: * clickable → [onClick] ONLY when [onClick] is non-null (the capability gate — a null callback leaves it
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocBookmarksSheet.kt:282:private fun BookmarkRow(theme: ReaderTheme, item: BookmarkRowItem, onClick: (() -> Unit)?) {
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocBookmarksSheet.kt:297:    val rowModifier = (if (onClick != null) base.clickable { onClick() } else base)
android/app/src/main/kotlin/com/vreader/app/reader/details/BookDetailsSheet.kt:149:                .clickable(onClick = onShare)
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocSheetRows.kt:42: * highlighted-chapter state). Tapping calls [onClick] with [index]. testTags: `toc-row-$index` (+
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocSheetRows.kt:51:    onClick: (Int) -> Unit,
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocSheetRows.kt:75:            .clickable { onClick(index) }
android/app/src/main/kotlin/com/vreader/app/reader/details/BookDetailsRows.kt:243:                    .clickable(onClick = onShare)
android/app/src/main/kotlin/com/vreader/app/reader/nav/TocContentsSheet.kt:142:                    onClick = { tapped -> if (onJump(tapped)) onDismiss() },
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:515:                    .clickable(onClick = onOpenNotes)
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:543:                Modifier.heightIn(min = 48.dp).clip(RoundedCornerShape(8.dp)).clickable(onClickLabel = "Library", onClick = onBack).padding(horizontal = 6.dp),
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsSheet.kt:87:                ThemeSwatch(swatch, selected = theme == swatch, ringColor = accent, labelColor = sub, onClick = { onTheme(swatch) }, modifier = Modifier.weight(1f))
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsSheet.kt:139:    onClick: () -> Unit,
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsSheet.kt:142:    Column(modifier.testTag("theme-${theme.name}").clickable { onClick() }, horizontalAlignment = Alignment.CenterHorizontally) {
android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderTopChrome.kt:106:                    .clickable(onClick = onBack)
android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderTopChrome.kt:141:                        onClick = onSearch,
android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderTopChrome.kt:158:                        onClick = onMore,
android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderTopChrome.kt:179:    onClick: () -> Unit,
android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderTopChrome.kt:185:            .clickable(onClick = onClick)
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:971:            .clickable(enabled = enabled, onClick = onReadAloud)
android/app/src/main/kotlin/com/vreader/app/reader/chrome/BookmarkToggleButton.kt:51:            .clickable(onClick = onToggle)
android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderBottomChrome.kt:133:                        ink = ink, sub = sub, onClick = onOpenContents,
android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderBottomChrome.kt:139:                        ink = ink, sub = sub, onClick = onOpenNotes,
android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderBottomChrome.kt:168:    onClick: () -> Unit,
android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderBottomChrome.kt:172:            .clickable(onClick = onClick)
android/app/src/main/kotlin/com/vreader/app/reader/more/MoreRow.kt:19:enum class MoreActionId {
android/app/src/main/kotlin/com/vreader/app/reader/more/MoreRow.kt:41:sealed interface MoreRow {
android/app/src/main/kotlin/com/vreader/app/reader/more/MoreRow.kt:66:    data class Disabled(
android/app/src/main/kotlin/com/vreader/app/reader/more/MorePopup.kt:86:                    .clickable(onClick = onDismiss)
android/app/src/main/kotlin/com/vreader/app/reader/more/MorePopup.kt:110:                    rows.forEach { row -> MoreRowItem(theme, row) }
android/app/src/main/kotlin/com/vreader/app/reader/more/MorePopup.kt:128:private fun MoreRowItem(theme: ReaderTheme, row: MoreRow) {
android/app/src/main/kotlin/com/vreader/app/reader/more/MorePopup.kt:139:            enabled = true, onClick = row.onTap,
android/app/src/main/kotlin/com/vreader/app/reader/more/MorePopup.kt:146:            enabled = false, dim = true, subBold = true, onClick = {},
android/app/src/main/kotlin/com/vreader/app/reader/more/MorePopup.kt:153:            enabled = true, active = row.on, onClick = { row.onToggle(!row.on) },
android/app/src/main/kotlin/com/vreader/app/reader/more/MorePopup.kt:184:    onClick: () -> Unit,
android/app/src/main/kotlin/com/vreader/app/reader/more/MorePopup.kt:192:    val rowModifier = if (enabled) base.clickable(onClick = onClick) else base
     1	// Purpose: feature #134 WI-3 — the reader More popover (`vreader-more.jsx` `MorePopover`): an anchored
     2	// top-right popover (width 268, radius 16, a notch pointing at the "..." button) over a list of [MoreRow]
     3	// rows the caller supplies. Renders ONLY the supplied rows — an id with no row is absent (no dead TTS/
     4	// Auto-turn/Bilingual/Export rows; the plan's §more-row-ownership + #129 no-dead-control rule). Action
     5	// rows fire onTap (chevron accessory), Toggle rows reflect `on` + call onToggle (switch accessory),
     6	// Disabled rows are non-interactive with a sub-text. A transparent full-bleed backdrop dismisses on tap.
     7	// Reuses the active [ReaderTheme]'s token map (ink/accent/isDark → the design's ink/sub/rule/surface
     8	// tokens) so it matches the reader chrome. The host renders this inside the More-button anchor slot so
     9	// the popup positions off the button's own layout coordinates (WI-5 wiring). Pure function of state.
    10	package com.vreader.app.reader.more
    11	
    12	import androidx.compose.foundation.background
    13	import androidx.compose.foundation.clickable
    14	import androidx.compose.foundation.layout.Arrangement
    15	import androidx.compose.foundation.layout.Box
    16	import androidx.compose.foundation.layout.Column
    17	import androidx.compose.foundation.layout.Row
    18	import androidx.compose.foundation.layout.Spacer
    19	import androidx.compose.foundation.layout.fillMaxSize
    20	import androidx.compose.foundation.layout.fillMaxWidth
    21	import androidx.compose.foundation.layout.height
    22	import androidx.compose.foundation.layout.padding
    23	import androidx.compose.foundation.layout.size
    24	import androidx.compose.foundation.layout.width
    25	import androidx.compose.foundation.layout.widthIn
    26	import androidx.compose.foundation.shape.RoundedCornerShape
    27	import androidx.compose.material.icons.Icons
    28	import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
    29	import androidx.compose.material3.Icon
    30	import androidx.compose.material3.Surface
    31	import androidx.compose.material3.Switch
    32	import androidx.compose.material3.SwitchDefaults
    33	import androidx.compose.material3.Text
    34	import androidx.compose.runtime.Composable
    35	import androidx.compose.ui.Alignment
    36	import androidx.compose.ui.Modifier
    37	import androidx.compose.ui.draw.clip
    38	import androidx.compose.ui.graphics.Color
    39	import androidx.compose.ui.graphics.vector.ImageVector
    40	import androidx.compose.ui.platform.testTag
    41	import androidx.compose.ui.semantics.contentDescription
    42	import androidx.compose.ui.semantics.semantics
    43	import androidx.compose.ui.text.font.FontWeight
    44	import androidx.compose.ui.text.style.TextOverflow
    45	import androidx.compose.ui.unit.dp
    46	import androidx.compose.ui.unit.sp
    47	import androidx.compose.ui.window.Popup
    48	import androidx.compose.ui.window.PopupProperties
    49	import com.vreader.app.reader.settings.ReaderTheme
    50	
    51	private val POPUP_WIDTH = 268.dp
    52	private val POPUP_RADIUS = 16.dp
    53	private val SWITCH_ON_TRACK = Color(0xFF3A6A5A) // vreader-more.jsx ToggleSwitch on-track.
    54	
    55	/**
    56	 * The reader More popover. [rows] are the caller-supplied rows in design order — the popup renders ONLY
    57	 * these (no invented/dead rows). [onDismiss] fires on a backdrop tap. Anchored to the top-trailing edge
    58	 * (under the "..." button in the top chrome) via a [Popup] with [Alignment.TopEnd]. Renders in [theme]'s
    59	 * colors.
    60	 */
    61	@Composable
    62	fun MorePopup(
    63	    theme: ReaderTheme,
    64	    rows: List<MoreRow>,
    65	    onDismiss: () -> Unit,
    66	    modifier: Modifier = Modifier,
    67	) {
    68	    // A single Popup that fills the window so the transparent backdrop can catch outside taps, and the
    69	    // popover card is aligned to the top-trailing corner (the design's `top:92 right:14`). Compose flips
    70	    // TopEnd to the leading edge automatically under RTL. `focusable` so the back button dismisses.
    71	    Popup(
    72	        alignment = Alignment.TopEnd,
    73	        onDismissRequest = onDismiss,
    74	        properties = PopupProperties(focusable = true),
    75	    ) {
    76	        Box(
    77	            modifier
    78	                .fillMaxSize()
    79	                .testTag("more-popup"),
    80	        ) {
    81	            // Transparent full-bleed backdrop — a tap outside the card dismisses (the design's dim layer).
    82	            Box(
    83	                Modifier
    84	                    .fillMaxSize()
    85	                    .testTag("more-backdrop")
    86	                    .clickable(onClick = onDismiss)
    87	                    .semantics { contentDescription = "Dismiss menu" },
    88	            )
    89	
    90	            // The popover card, offset from the top-trailing corner to sit under the "..." button. The
    91	            // width is the design's 268dp but clamped ≤ available width (`widthIn(max)` + `fillMaxWidth`
    92	            // capped by the parent 14dp end padding) so it never clips on a narrow screen.
    93	            Surface(
    94	                shape = RoundedCornerShape(POPUP_RADIUS),
    95	                color = surfaceColor(theme),
    96	                shadowElevation = 12.dp,
    97	                tonalElevation = 0.dp,
    98	                modifier = Modifier
    99	                    .align(Alignment.TopEnd)
   100	                    .padding(top = 8.dp, end = 14.dp)
   101	                    .widthIn(max = POPUP_WIDTH)
   102	                    .testTag("more-popup-card"),
   103	            ) {
   104	                // The design's fixed 268dp column; the Surface's widthIn(max) clamps it on a narrow window.
   105	                Column(
   106	                    Modifier
   107	                        .width(POPUP_WIDTH)
   108	                        .padding(vertical = 6.dp),
   109	                ) {
   110	                    rows.forEach { row -> MoreRowItem(theme, row) }
   111	                }
   112	            }
   113	        }
   114	    }
   115	}
   116	
   117	/** The popover's fill color — the design's `#2a2724` (dark) / `#fcf8f0` (light). */
   118	private fun surfaceColor(theme: ReaderTheme): Color =
   119	    if (theme.isDark) Color(0xFF2A2724) else Color(0xFFFCF8F0)
   120	
   121	/**
   122	 * One More-menu row, dispatched on the [MoreRow] shape. Layout mirrors `vreader-more.jsx` `Row`: a 28dp
   123	 * rounded icon tile + a label (+ optional sub-text) + a trailing accessory (a switch for [MoreRow.Toggle],
   124	 * a chevron for [MoreRow.Action]/[MoreRow.Disabled]). Renders in [theme]'s tokens. Disabled rows are
   125	 * dimmed + non-interactive.
   126	 */
   127	@Composable
   128	private fun MoreRowItem(theme: ReaderTheme, row: MoreRow) {
   129	    val ink = theme.ink
   130	    val sub = theme.ink.copy(alpha = 0.6f)
   131	    val accent = theme.accent
   132	    val slug = row.id.slug
   133	
   134	    when (row) {
   135	        is MoreRow.Action -> RowScaffold(
   136	            testTag = "more-row-$slug",
   137	            icon = row.icon, label = row.label, sub = row.sub,
   138	            ink = ink, sub_ = sub, accent = accent, isDark = theme.isDark,
   139	            enabled = true, onClick = row.onTap,
   140	        ) { ChevronAccessory(sub) }
   141	
   142	        is MoreRow.Disabled -> RowScaffold(
   143	            testTag = "more-row-$slug",
   144	            icon = row.icon, label = row.label, sub = row.sub,
   145	            ink = ink, sub_ = accent, accent = accent, isDark = theme.isDark,
   146	            enabled = false, dim = true, subBold = true, onClick = {},
   147	        ) { ChevronAccessory(sub) }
   148	
   149	        is MoreRow.Toggle -> RowScaffold(
   150	            testTag = "more-row-$slug",
   151	            icon = row.icon, label = row.label, sub = row.sub,
   152	            ink = ink, sub_ = sub, accent = accent, isDark = theme.isDark,
   153	            enabled = true, active = row.on, onClick = { row.onToggle(!row.on) },
   154	        ) {
   155	            Switch(
   156	                checked = row.on,
   157	                onCheckedChange = { row.onToggle(it) },
   158	                modifier = Modifier.testTag("more-row-toggle-$slug"),
   159	                colors = SwitchDefaults.colors(checkedTrackColor = SWITCH_ON_TRACK),
   160	            )
   161	        }
   162	    }
   163	}
   164	
   165	/**
   166	 * The shared row shell: an optional-click wrapper around the icon tile + text block + trailing
   167	 * [accessory]. [enabled]=false makes the row non-interactive (no click action). [dim] applies the
   168	 * design's disabled opacity; [active] tints the icon tile with the accent.
   169	 */
   170	@Composable
   171	private fun RowScaffold(
   172	    testTag: String,
   173	    icon: ImageVector,
   174	    label: String,
   175	    sub: String?,
   176	    ink: Color,
   177	    sub_: Color,
   178	    accent: Color,
   179	    isDark: Boolean,
   180	    enabled: Boolean,
   181	    active: Boolean = false,
   182	    dim: Boolean = false,
   183	    subBold: Boolean = false,
   184	    onClick: () -> Unit,
   185	    accessory: @Composable () -> Unit,
   186	) {
   187	    val base = Modifier
   188	        .fillMaxWidth()
   189	        .testTag(testTag)
   190	        .semantics { contentDescription = label }
   191	    // A disabled row carries no click action (non-interactive, per the design + the test).
   192	    val rowModifier = if (enabled) base.clickable(onClick = onClick) else base
   193	    val contentAlpha = if (dim) 0.55f else 1f
   194	
   195	    Row(
   196	        rowModifier.padding(horizontal = 14.dp, vertical = 11.dp),
   197	        verticalAlignment = Alignment.CenterVertically,
   198	        horizontalArrangement = Arrangement.spacedBy(12.dp),
   199	    ) {
   200	        // Icon tile — 28dp rounded (radius 8); accent-tinted background when active.
   201	        Box(
   202	            Modifier
   203	                .size(28.dp)
   204	                .clip(RoundedCornerShape(8.dp))
   205	                .background(
   206	                    if (active) accent.copy(alpha = if (isDark) 0.20f else 0.10f)
   207	                    else ink.copy(alpha = if (isDark) 0.05f else 0.04f),
   208	                ),
   209	            contentAlignment = Alignment.Center,
   210	        ) {
   211	            Icon(
   212	                icon, contentDescription = null,
   213	                tint = (if (active) accent else ink).copy(alpha = contentAlpha),
   214	                modifier = Modifier.size(15.dp),
   215	            )
   216	        }
   217	
   218	        // Text block — label (+ optional sub-text). Takes the remaining width; the accessory follows.
   219	        Column(Modifier.weight(1f)) {
   220	            Text(
   221	                label,
   222	                color = ink.copy(alpha = contentAlpha),
   223	                fontSize = 14.5.sp,
   224	                fontWeight = FontWeight.Medium,
   225	                maxLines = 1,
   226	                overflow = TextOverflow.Ellipsis,
   227	            )
   228	            if (sub != null) {
   229	                Text(
   230	                    sub,
   231	                    color = sub_,
   232	                    fontSize = 11.sp,
   233	                    fontWeight = if (subBold) FontWeight.SemiBold else FontWeight.Normal,
   234	                    maxLines = 1,
   235	                    overflow = TextOverflow.Ellipsis,
   236	                )
   237	            }
   238	        }
   239	
   240	        accessory()
   241	    }
   242	}
   243	
   244	@Composable
   245	private fun ChevronAccessory(tint: Color) {
   246	    Icon(
   247	        Icons.AutoMirrored.Filled.KeyboardArrowRight,
   248	        contentDescription = null,
   249	        tint = tint,
   250	        modifier = Modifier.size(16.dp),
   251	    )
   252	}
   253	
   254	/** A design divider between row groups (0.5dp, the theme rule token, inset 14dp). Kept for host use. */
   255	@Composable
   256	fun MoreMenuDivider(theme: ReaderTheme) {
   257	    Box(
   258	        Modifier
   259	            .fillMaxWidth()
   260	            .padding(horizontal = 14.dp, vertical = 4.dp),
   261	    ) {
   262	        Spacer(
   263	            Modifier
   264	                .fillMaxWidth()
   265	                .height(0.5.dp)
   266	                .background(theme.ink.copy(alpha = 0.10f)),
   267	        )
   268	    }
   269	}
     1	// Purpose: feature #132 WI-7-EPUB (#110 Phase 3) — the Compose chrome CONTENT for the EPUB reader host
     2	// (ReaderActivity). The EPUB host is the outlier: a Readium EpubNavigatorFragment (a View) renders the
     3	// page under the chrome, so — unlike the Compose-native TXT/PDF/AZW3 hosts — it CANNOT wrap the
     4	// full-screen ReaderChromeScaffold (which owns a `weight(1f)` composable body). Instead the host stacks
     5	// THREE separately-sized ComposeViews over the fragment's FrameLayout, each rendered by one composable
     6	// here and each fed the persistent MutableStateFlow<ReaderChromeModel> + a hoisted ReaderChromeState:
     7	//   • [EpubTopBand]    — the top ComposeView (title + "‹ Library" + — feature #134 WI-5 — the More button
     8	//                         that toggles the WI-3 MorePopup); sized to the top chrome only.
     9	//   • [EpubBottomBand] — the bottom ComposeView (progress + Contents/Notes/Display toolbar); sized to the
    10	//                         bottom chrome only. Contents shown only when the model's TOC is non-empty.
    11	//   • [EpubReaderSheets] — a full-screen ComposeView that is EMPTY (renders nothing, so it does not cover
    12	//                         the fragment) until a sheet is open, at which point it lays a full-screen dismiss
    13	//                         overlay + the Contents/Notes/Details ModalBottomSheet. This "open-only"
    14	//                         full-screen posture is what keeps the Readium fragment's scroll/selection/link
    15	//                         input working while no sheet is up — the top/bottom bands only cover the chrome
    16	//                         regions.
    17	// Contents onJump → the host's `navigator.go(entry.epubReadiumLocator)` (Boolean): dismiss on success,
    18	// stay-open on false, NO invented error surface (rule 51 §nav-error-presentation). Notes → the WI-4 review
    19	// sheet with onJumpToAnnotation NULL (EPUB review-only, cards non-clickable, until #135 supplies the nav
    20	// seam). feature #134 WI-5 — Details → the WI-4 BookDetailsSheet over the host-supplied [bookDetails];
    21	// the More menu carries ONLY Details + Share (Share → the host's book-share flow; copy-fingerprint → the
    22	// host's OS clipboard copy, no invented toast — rule 51). Pure functions of state + callbacks (rule 50 §4);
    23	// same ReaderTheme token map as the other hosts.
    24	// @coordinates-with: ReaderActivity.kt (owns the StateFlow + the ComposeViews + the navigator jump + the
    25	//   Book-details model/share/copy wiring), ReaderChromeModel.kt (the collected model), chrome/ReaderTopChrome
    26	//   + chrome/ReaderBottomChrome (the reused designed bands), chrome/BookmarkToggleButton (the #135 top-bar
    27	//   bookmark toggle filling the top band's bookmark slot), chrome/ReaderChromeState (the hoisted
    28	//   sheet/visibility state incl. the #135 Bookmarks route), chrome/ReaderChromeScaffold (the shared
    29	//   readerMoreRows assembler), more/MorePopup + details/BookDetailsSheet + nav/TocBookmarksSheet (the #135
    30	//   WI-6 promoted two-tab Contents|Bookmarks sheet, which reuses nav/TocContentsSheet's Contents body) +
    31	//   annotations/AnnotationsReviewSheet (the popup + modal sheets).
    32	package com.vreader.app.reader
    33	
    34	import androidx.compose.foundation.clickable
    35	import androidx.compose.foundation.interaction.MutableInteractionSource
    36	import androidx.compose.foundation.layout.Box
    37	import androidx.compose.foundation.layout.fillMaxSize
    38	import androidx.compose.runtime.Composable
    39	import androidx.compose.runtime.MutableState
    40	import androidx.compose.runtime.getValue
    41	import androidx.compose.runtime.mutableStateOf
    42	import androidx.compose.runtime.remember
    43	import androidx.compose.runtime.setValue
    44	import androidx.compose.ui.Modifier
    45	import androidx.compose.ui.platform.testTag
    46	import androidx.lifecycle.compose.collectAsStateWithLifecycle
    47	import com.vreader.app.annotations.AnnotationsReviewSheet
    48	import com.vreader.app.reader.chrome.BookmarkToggleButton
    49	import com.vreader.app.reader.chrome.ReaderBottomChrome
    50	import com.vreader.app.reader.chrome.ReaderChromeState
    51	import com.vreader.app.reader.chrome.ReaderSheet
    52	import com.vreader.app.reader.chrome.ReaderTopChrome
    53	import com.vreader.app.reader.chrome.readerMoreRows
    54	import com.vreader.app.annotations.BookmarkRecord
    55	import com.vreader.app.reader.details.BookDetailsSheet
    56	import com.vreader.app.reader.details.BookDetailsUiModel
    57	import com.vreader.app.reader.more.MorePopup
    58	import com.vreader.app.reader.nav.BookmarkRowItem
    59	import com.vreader.app.reader.nav.JumpResult
    60	import com.vreader.app.reader.nav.TocBookmarksSheet
    61	import com.vreader.app.reader.nav.TocTab
    62	import com.vreader.app.reader.settings.ReaderTheme
    63	import kotlinx.coroutines.flow.StateFlow
    64	
    65	/**
    66	 * The EPUB top chrome band — the title + "‹ Library" back control (the WI-2 [ReaderTopChrome]) + —
    67	 * feature #134 WI-5 — the More button. Rendered in its OWN top ComposeView sized to WRAP_CONTENT so it
    68	 * covers only the top strip; the Readium fragment fills the rest. [model] supplies the live title;
    69	 * [onBack] fires the back control. The More button appears ONLY when [bookDetails] is non-null (no dead
    70	 * control) and toggles the WI-3 [MorePopup] carrying ONLY the Details + Share rows: Details writes
    71	 * [ReaderSheet.Details] onto [chromeState] (so [EpubReaderSheets] shows the Book Details sheet), Share
    72	 * fires [onShareBook]. The popup renders in its own window (a full-screen backdrop) so the WRAP_CONTENT
    73	 * band height doesn't clip it. feature #133 WI-11 — the top-bar Search slot is now WIRED: [onSearch] fills
    74	 * [ReaderTopChrome]'s Search slot (null → the icon is omitted — the #129 no-dead-control rule; a host whose
    75	 * publication is not searchable / whose index-state gate reports Unsupported passes null so the icon
    76	 * disappears). feature #135 WI-5 — the top-bar bookmark toggle: when [onToggleBookmark] is non-null the
    77	 * band fills [ReaderTopChrome]'s bookmark slot with the WI-5 [BookmarkToggleButton] (filled/outline by
    78	 * [isCurrentBookmarked]); a null callback leaves the slot empty (no dead control).
    79	 */
    80	@Composable
    81	fun EpubTopBand(
    82	    model: StateFlow<ReaderChromeModel>,
    83	    theme: ReaderTheme,
    84	    onBack: () -> Unit,
    85	    chromeState: MutableState<ReaderChromeState>,
    86	    bookDetails: BookDetailsUiModel?,
    87	    onShareBook: () -> Unit,
    88	    // feature #133 WI-11 — the in-book Search entry. A null [onSearch] omits the top-bar Search icon
    89	    // (a non-searchable publication / Unsupported gate — no dead control). Nullable/default so #132/#134/#135
    90	    // callers stay valid.
    91	    onSearch: (() -> Unit)? = null,
    92	    isCurrentBookmarked: Boolean = false,
    93	    onToggleBookmark: (() -> Unit)? = null,
    94	) {
    95	    val chrome by model.collectAsStateWithLifecycle()
    96	    var showMore by remember { mutableStateOf(false) }
    97	    // More is available only when this book has a Book-details data source (no dead control).
    98	    val onMore: (() -> Unit)? = if (bookDetails != null) ({ showMore = true }) else null
    99	    // feature #135 WI-5 — the bookmark slot is built only when the host opts in via [onToggleBookmark].
   100	    val bookmarkSlot: (@Composable () -> Unit)? =
   101	        if (onToggleBookmark != null) {
   102	            { BookmarkToggleButton(theme = theme, isBookmarked = isCurrentBookmarked, onToggle = onToggleBookmark) }
   103	        } else {
   104	            null
   105	        }
   106	    ReaderTopChrome(theme = theme, title = chrome.title, onBack = onBack, onSearch = onSearch, onMore = onMore, bookmarkSlot = bookmarkSlot)
   107	    if (showMore && bookDetails != null) {
   108	        MorePopup(
   109	            theme = theme,
   110	            rows = readerMoreRows(
   111	                onDetails = { showMore = false; chromeState.value = chromeState.value.copy(sheet = ReaderSheet.Details) },
   112	                onShare = { showMore = false; onShareBook() },
   113	            ),
   114	            onDismiss = { showMore = false },
   115	        )
   116	    }
   117	}
   118	
   119	/**
   120	 * The EPUB bottom chrome band — the progress scrubber + the Contents/Notes/Display toolbar (the extended
   121	 * WI-5 [ReaderBottomChrome]). Rendered in its OWN bottom ComposeView sized to WRAP_CONTENT so it covers
   122	 * only the bottom strip. Contents opens the TOC sheet ONLY when the model has a non-empty TOC (else the
   123	 * control is omitted — no dead control); Notes opens the review sheet; Display opens the #129 settings
   124	 * sheet ([onOpenDisplay], preserved). [progress] is 0..1 (the host's live reading fraction); [onScrub]
   125	 * seeks. Opening a sheet writes [chromeState] so [EpubReaderSheets] shows it.
   126	 */
   127	@Composable
   128	fun EpubBottomBand(
   129	    model: StateFlow<ReaderChromeModel>,
   130	    theme: ReaderTheme,
   131	    chromeState: MutableState<ReaderChromeState>,
   132	    progress: Float,
   133	    onScrub: (Float) -> Unit,
   134	    onOpenDisplay: () -> Unit,
   135	) {
   136	    val chrome by model.collectAsStateWithLifecycle()
   137	    // Contents available only when there IS a TOC — an empty TOC hides the control (no dead control).
   138	    val onOpenContents: (() -> Unit)? =
   139	        if (chrome.tocEntries.isEmpty()) null
   140	        else { { chromeState.value = chromeState.value.copy(sheet = ReaderSheet.Toc) } }
   141	    ReaderBottomChrome(
   142	        theme = theme,
   143	        progress = progress,
   144	        displayPage = 0,
   145	        totalPages = 0, // EPUB scroll layout — no page labels (Spike-B scroll mode)
   146	        onScrub = onScrub,
   147	        onOpenDisplay = onOpenDisplay,
   148	        onOpenContents = onOpenContents,
   149	        onOpenNotes = { chromeState.value = chromeState.value.copy(sheet = ReaderSheet.Notes) },
   150	    )
   151	}
   152	
   153	/**
   154	 * The EPUB modal-sheet layer — the open-only full-screen dismiss overlay + the Contents / Notes / Details
   155	 * sheets. Rendered in a FULL-SCREEN ComposeView that renders NOTHING while [ReaderChromeState.sheet] is
   156	 * [ReaderSheet.None] (so it does not cover the fragment); the instant a sheet opens it lays a full-screen
   157	 * dismiss overlay (a transparent scrim that dismisses the sheet on an outside tap) beneath the
   158	 * ModalBottomSheet. This keeps the Readium fragment's scroll/selection/link input alive whenever no sheet
   159	 * is up.
   160	 *
   161	 * [onJumpToc] performs the native-locator TOC jump (returns success → the Contents tab dismisses on
   162	 * success, stays open on false — no invented error surface). [onShareAnnotations] is the Notes sheet-level
   163	 * Share. EPUB Notes cards are review-only (onJumpToAnnotation NULL) until #135's nav seam lands. feature
   164	 * #135 WI-6 — the Toc route renders the promoted two-tab [TocBookmarksSheet]; [bookmarks] feed its
   165	 * Bookmarks tab and [onJumpBookmark] is the capability-based nullable bookmark jump (non-null → clickable
   166	 * rows + dismiss-on-Succeeded; null → review-only, non-clickable rows before WI-7 lights up the EPUB jump);
   167	 * the Bookmarks route opens the same sheet on its Bookmarks tab. feature #134 WI-5 — [bookDetails] drives the Details sheet
   168	 * (the WI-4 [BookDetailsSheet]); [onShareBook] is its Share flow and [onCopyFingerprint] its copy-fingerprint
   169	 * mini-action (the host copies to the OS clipboard — no invented toast, rule 51). A Details route with no
   170	 * [bookDetails] (should not happen — the route is only reachable when the More menu was fed a model) treats
   171	 * the scrim as present but shows no sheet (a safe no-op).
   172	 */
   173	@Composable
   174	fun EpubReaderSheets(
   175	    model: StateFlow<ReaderChromeModel>,
   176	    theme: ReaderTheme,
   177	    chromeState: MutableState<ReaderChromeState>,
   178	    onJumpToc: (Int) -> Boolean,
   179	    onShareAnnotations: () -> Unit,
   180	    bookDetails: BookDetailsUiModel? = null,
   181	    onShareBook: () -> Unit = {},
   182	    onCopyFingerprint: (String) -> Unit = {},
   183	    bookmarks: List<BookmarkRowItem> = emptyList(),
   184	    onJumpBookmark: ((BookmarkRecord) -> JumpResult)? = null,
   185	) {
   186	    val chrome by model.collectAsStateWithLifecycle()
   187	    val sheet = chromeState.value.sheet
   188	    if (sheet is ReaderSheet.None) return // render nothing → the fragment keeps all input
   189	
   190	    fun closeSheet() { chromeState.value = chromeState.value.copy(sheet = ReaderSheet.None) }
   191	
   192	    // feature #134 WI-5 — a Details route with NO model would render no sheet yet still lay the
   193	    // full-screen dismiss overlay below, silently intercepting Readium scroll/selection/link input (a
   194	    // dead route). Normalize it back to None so touch-through is preserved (Gate-4 P1). In practice this
   195	    // route is only reached once [bookDetails] fed the More menu, so this is a defensive guard.
   196	    if (sheet is ReaderSheet.Details && bookDetails == null) {
   197	        closeSheet()
   198	        return
   199	    }
   200	
   201	    // feature #135 WI-6 — the Bookmarks route now DOES render (the two-tab TocBookmarksSheet with the
   202	    // Bookmarks tab pre-selected), so it is NOT normalized away — it lays the scrim + the sheet like Toc.
   203	
   204	    // The open-only full-screen dismiss overlay — a transparent scrim under the sheet. An outside tap
   205	    // (a tap that reaches the scrim, not the sheet) closes the sheet. Present ONLY while a sheet is open.
   206	    Box(
   207	        Modifier
   208	            .fillMaxSize()
   209	            .testTag("epub-sheet-dismiss-overlay")
   210	            .clickable(
   211	                interactionSource = remember { MutableInteractionSource() },
   212	                indication = null,
   213	            ) { closeSheet() },
   214	    )
   215	
   216	    when (sheet) {
   217	        ReaderSheet.None -> Unit
   218	        // feature #135 WI-6 — the promoted two-tab TOC sheet (Contents|Bookmarks). The Contents tab REUSES
   219	        // #132's TocContentsSheet body unchanged; dismiss-on-success (Contents) / dismiss-on-Succeeded
   220	        // (Bookmarks) — a false/Failed jump keeps the sheet open, NO invented error surface (rule 51).
   221	        ReaderSheet.Toc -> TocBookmarksSheet(
   222	            theme = theme,
   223	            bookTitle = chrome.title,
   224	            entries = chrome.tocEntries,
   225	            currentTocIndex = chrome.currentTocIndex,
   226	            bookmarks = bookmarks,
   227	            onJumpToc = onJumpToc,
   228	            onJumpBookmark = onJumpBookmark,
   229	            onDismiss = { closeSheet() },
   230	        )
   231	        ReaderSheet.Notes -> AnnotationsReviewSheet(
   232	            theme = theme,
   233	            snapshot = chrome.annotations,
   234	            onShareAll = onShareAnnotations,
   235	            // EPUB is review-only until #135 supplies the jump-to-annotation nav seam → cards non-clickable.
   236	            onJumpToAnnotation = null,
   237	            onDismiss = { closeSheet() },
   238	        )
   239	        // feature #134 WI-5 — the Book Details sheet. Rendered only when there IS a model (the Details
   240	        // route is only reachable when [bookDetails] fed the More menu); a null model is a safe no-op.
   241	        ReaderSheet.Details -> if (bookDetails != null) BookDetailsSheet(
   242	            theme = theme,
   243	            model = bookDetails,
   244	            onCopyFingerprint = onCopyFingerprint,
   245	            onShare = onShareBook,
   246	            onDismiss = { closeSheet() },
   247	        )
   248	        // feature #135 WI-6 — the Bookmarks route opens the SAME two-tab sheet with the Bookmarks tab
   249	        // pre-selected (the designed [TocBookmarksSheet]; rule 51 — no invented list surface).
   250	        ReaderSheet.Bookmarks -> TocBookmarksSheet(
   251	            theme = theme,
   252	            bookTitle = chrome.title,
   253	            entries = chrome.tocEntries,
   254	            currentTocIndex = chrome.currentTocIndex,
   255	            bookmarks = bookmarks,
   256	            onJumpToc = onJumpToc,
   257	            onJumpBookmark = onJumpBookmark,
   258	            onDismiss = { closeSheet() },
   259	            initialTab = TocTab.Bookmarks,
   260	        )
   261	    }
   262	}

exec
/bin/zsh -lc "nl -ba android/app/src/main/kotlin/com/vreader/app/reader/more/MoreRow.kt | sed -n '1,130p'
rg -n \"NavHost|composable\\(|navigation\\(|AiProviderListScreen|AiProviderEditSheet|AiSettingsViewModel|AiProviderStore\" android/app/src/main/kotlin android/app/src/test/kotlin android/app/src/androidTest/kotlin
rg -n \"setContent|LibraryScreen|startActivity|ReaderActivity|TxtReaderActivity|PdfReaderActivity|Azw3ReaderActivity\" android/app/src/main/kotlin/com/vreader/app/MainActivity.kt android/app/src/main/kotlin/com/vreader/app/library/LibraryScreen.kt" in /Users/ll/workspace/vreader
 succeeded in 0ms:
     1	// Purpose: feature #134 WI-3 — the reader More-menu ROW model (`vreader-more.jsx` `MorePopover` rows),
     2	// rendered by [MorePopup]. A `sealed interface` so each row carries a stable [MoreActionId] + its own
     3	// callback + (for toggles) its own on/onToggle state. The row's OWNER supplies it: #134 owns only
     4	// DETAILS + SHARE (Action rows); TTS/AUTO_TURN/BILINGUAL ids exist so their owning features (#121/#131/
     5	// a future Auto-turn feature) can supply rows, but a row is NEVER invented here — an id with no supplied
     6	// row is simply absent from the popup (the plan's §more-row-ownership contract; the #129 no-dead-control
     7	// rule). Pure model: an ImageVector icon ref + strings + lambdas, no Compose UI in the type itself.
     8	package com.vreader.app.reader.more
     9	
    10	import androidx.compose.ui.graphics.vector.ImageVector
    11	
    12	/**
    13	 * A stable identifier for a More-menu row. Used for the row's testTag (`more-row-$id`) and to key row
    14	 * ownership. #134 owns [DETAILS] + [SHARE]; the others exist so their owning features can supply rows —
    15	 * #134 supplies none of them and omits any id it is not given a row for. There is deliberately NO
    16	 * `EXPORT` id: Android has no annotation-export subsystem, so the Export row is never rendered (the
    17	 * plan's scoped-out invariant), and absence-by-omission is enforced by there being no id to supply.
    18	 */
    19	enum class MoreActionId {
    20	    DETAILS,
    21	    SHARE,
    22	    TTS,
    23	    AUTO_TURN,
    24	    BILINGUAL,
    25	}
    26	
    27	/** The lowercase stable slug for this id — the testTag / route suffix (e.g. `AUTO_TURN` → `auto_turn`). */
    28	val MoreActionId.slug: String
    29	    get() = name.lowercase()
    30	
    31	/**
    32	 * A single More-menu row. Exactly one of three shapes, mirroring the design's three row treatments:
    33	 *  - [Action]   — a tap row with a trailing chevron (`vreader-more.jsx` `onAction`).
    34	 *  - [Toggle]   — a stateful row with a trailing switch reflecting [Toggle.on] (`onToggle`).
    35	 *  - [Disabled] — the design's disabled state (e.g. Bilingual "Configure AI provider first"):
    36	 *                 non-interactive, dimmed, shows its [Disabled.sub].
    37	 *
    38	 * Every row carries a stable [id] (its testTag key) and its own callback. The OWNER of a row's behavior
    39	 * is the feature that supplies it — never [MorePopup] itself.
    40	 */
    41	sealed interface MoreRow {
    42	    val id: MoreActionId
    43	    val label: String
    44	    val icon: ImageVector
    45	
    46	    /** A tap row: fires [onTap]; renders a trailing chevron accessory. */
    47	    data class Action(
    48	        override val id: MoreActionId,
    49	        override val label: String,
    50	        override val icon: ImageVector,
    51	        val sub: String? = null,
    52	        val onTap: () -> Unit,
    53	    ) : MoreRow
    54	
    55	    /** A toggle row: the trailing switch reflects [on]; tapping the row calls [onToggle] with `!on`. */
    56	    data class Toggle(
    57	        override val id: MoreActionId,
    58	        override val label: String,
    59	        override val icon: ImageVector,
    60	        val sub: String? = null,
    61	        val on: Boolean,
    62	        val onToggle: (Boolean) -> Unit,
    63	    ) : MoreRow
    64	
    65	    /** A disabled row: non-interactive, dimmed, shows [sub] (the design's "Configure AI provider first"). */
    66	    data class Disabled(
    67	        override val id: MoreActionId,
    68	        override val label: String,
    69	        override val icon: ImageVector,
    70	        val sub: String,
    71	        val onTap: () -> Unit,
    72	    ) : MoreRow
    73	}
android/app/src/androidTest/kotlin/com/vreader/app/ai/AiProviderEditSheetTest.kt:21:class AiProviderEditSheetTest {
android/app/src/androidTest/kotlin/com/vreader/app/ai/AiProviderEditSheetTest.kt:25:        compose.setContent { BackupSurface(darkOverride = false) { AiProviderEditSheet(AiEditState(editMode = false)) } }
android/app/src/androidTest/kotlin/com/vreader/app/ai/AiProviderEditSheetTest.kt:38:        compose.setContent { BackupSurface(darkOverride = false) { AiProviderEditSheet(AiEditState(), onKind = { picked = it }) } }
android/app/src/androidTest/kotlin/com/vreader/app/ai/AiProviderEditSheetTest.kt:44:        compose.setContent { BackupSurface(darkOverride = false) { AiProviderEditSheet(AiEditState(apiKey = "")) } }
android/app/src/androidTest/kotlin/com/vreader/app/ai/AiProviderEditSheetTest.kt:51:                AiProviderEditSheet(AiEditState(apiKey = "sk", test = AiConnTest.ok, testMessage = "Connected — the provider responded successfully."))
android/app/src/androidTest/kotlin/com/vreader/app/ai/AiProviderEditSheetTest.kt:60:                AiProviderEditSheet(AiEditState(editMode = true, id = "x", name = "DeepSeek", keyAlreadySaved = true))
android/app/src/androidTest/kotlin/com/vreader/app/ai/AiProviderListScreenTest.kt:17:class AiProviderListScreenTest {
android/app/src/androidTest/kotlin/com/vreader/app/ai/AiProviderListScreenTest.kt:23:            BackupSurface(darkOverride = false) { AiProviderListScreen(AiProviderListState(emptyList()), onAdd = { added = true }) }
android/app/src/androidTest/kotlin/com/vreader/app/ai/AiProviderListScreenTest.kt:38:        compose.setContent { BackupSurface(darkOverride = false) { AiProviderListScreen(state, onEdit = { edited = it }) } }
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderFactory.kt:3:// AiProviderStore.snapshot(), decrypts via apiKey(profile), and calls this — so the client is built
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt:46:fun AiProviderListScreen(
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:41:class AiProviderStore(
android/app/src/test/kotlin/com/vreader/app/ai/AiChatViewModelTest.kt:36:    private lateinit var store: AiProviderStore
android/app/src/test/kotlin/com/vreader/app/ai/AiChatViewModelTest.kt:48:        store = AiProviderStore(PreferenceDataStoreFactory.create(scope = CoroutineScope(dispatcher)) { tmp.newFile("ai.preferences_pb") }, cipher)
android/app/src/test/kotlin/com/vreader/app/ai/AiSettingsViewModelTest.kt:29:class AiSettingsViewModelTest {
android/app/src/test/kotlin/com/vreader/app/ai/AiSettingsViewModelTest.kt:37:    private lateinit var store: AiProviderStore
android/app/src/test/kotlin/com/vreader/app/ai/AiSettingsViewModelTest.kt:48:        store = AiProviderStore(
android/app/src/test/kotlin/com/vreader/app/ai/AiSettingsViewModelTest.kt:57:        AiSettingsViewModel(store, dispatcher) { _, _ -> FakeClient(result) }
android/app/src/main/kotlin/com/vreader/app/ai/AiChatViewModel.kt:2:// ACTIVE provider from one AiProviderStore snapshot, streams a chat answer (accumulating deltas),
android/app/src/main/kotlin/com/vreader/app/ai/AiChatViewModel.kt:24:    private val store: AiProviderStore,
android/app/src/test/kotlin/com/vreader/app/ai/AiProviderStoreTest.kt:21: * Feature #118 WI-1 — AiProviderStore CRUD + active-id + key-as-cipher-token, with a temp DataStore
android/app/src/test/kotlin/com/vreader/app/ai/AiProviderStoreTest.kt:26:class AiProviderStoreTest {
android/app/src/test/kotlin/com/vreader/app/ai/AiProviderStoreTest.kt:35:    private lateinit var store: AiProviderStore
android/app/src/test/kotlin/com/vreader/app/ai/AiProviderStoreTest.kt:39:        store = AiProviderStore(dataStore, fakeCipher)
android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsViewModel.kt:2:// AiProviderStore for the list, owns the editor form state, runs Test Connection against the LIVE
android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsViewModel.kt:20:class AiSettingsViewModel(
android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsViewModel.kt:21:    private val store: AiProviderStore,
android/app/src/main/kotlin/com/vreader/app/ai/AiProviderEditSheet.kt:55:fun AiProviderEditSheet(
android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:65:    // AiProviderStore precedent), global (not per-book), process-singleton so a settings change
android/app/src/main/kotlin/com/vreader/app/opds/ui/OpdsSourcesViewModel.kt:4:// #118 AiSettingsViewModel test path), and saves/deletes. The password is never logged.
android/app/src/main/kotlin/com/vreader/app/opds/ui/OpdsSourcesViewModel.kt:50:    // closed form). Mirrors AiSettingsViewModel.testGen.
android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsStore.kt:2:// DataStore (the OpdsSourceStore / AiProviderStore JSON-in-Preferences precedent). Global, device-
android/app/src/main/kotlin/com/vreader/app/library/LibraryScreen.kt:56:fun LibraryScreen(
android/app/src/main/kotlin/com/vreader/app/MainActivity.kt:8://   (the DI container), library/LibraryViewModel.kt, library/LibraryScreen.kt
android/app/src/main/kotlin/com/vreader/app/MainActivity.kt:15:import androidx.activity.compose.setContent
android/app/src/main/kotlin/com/vreader/app/MainActivity.kt:29:import com.vreader.app.library.LibraryScreen
android/app/src/main/kotlin/com/vreader/app/MainActivity.kt:33:import com.vreader.app.reader.Azw3ReaderActivity
android/app/src/main/kotlin/com/vreader/app/MainActivity.kt:34:import com.vreader.app.reader.ReaderActivity
android/app/src/main/kotlin/com/vreader/app/MainActivity.kt:35:import com.vreader.app.reader.PdfReaderActivity
android/app/src/main/kotlin/com/vreader/app/MainActivity.kt:36:import com.vreader.app.reader.TxtReaderActivity
android/app/src/main/kotlin/com/vreader/app/MainActivity.kt:50:        setContent {
android/app/src/main/kotlin/com/vreader/app/MainActivity.kt:82:                            startActivity(ReaderActivity.intent(this@MainActivity, key))
android/app/src/main/kotlin/com/vreader/app/MainActivity.kt:86:                            startActivity(TxtReaderActivity.intent(this@MainActivity, key))
android/app/src/main/kotlin/com/vreader/app/MainActivity.kt:89:                            startActivity(PdfReaderActivity.intent(this@MainActivity, key))
android/app/src/main/kotlin/com/vreader/app/MainActivity.kt:92:                            startActivity(Azw3ReaderActivity.intent(this@MainActivity, key))
android/app/src/main/kotlin/com/vreader/app/MainActivity.kt:96:                LibraryScreen(

codex
The core reachability premise is confirmed so far: the production tree contains the types, but the only direct screen invocations are connected tests, and `AppContainer` mentions `AiProviderStore` only in a comment. I’m now checking the higher-risk mismatch: the plan equates “any profile exists” with “AI is configured,” while the requested readiness contract is an active profile with a usable, non-empty key.
exec
/bin/zsh -lc "nl -ba android/app/src/main/kotlin/com/vreader/app/backup/net/SecretCipher.kt | sed -n '1,260p'
nl -ba android/app/src/main/kotlin/com/vreader/app/backup/net/WebDavServerStore.kt | sed -n '1,260p'
nl -ba android/app/src/main/kotlin/com/vreader/app/opds/OpdsSourceStore.kt | sed -n '1,180p'
nl -ba android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsUiState.kt | sed -n '1,250p'
nl -ba android/app/src/main/kotlin/com/vreader/app/MainActivity.kt | sed -n '35,120p'
nl -ba android/app/src/main/kotlin/com/vreader/app/library/LibraryScreen.kt | sed -n '45,115p'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
     1	// Purpose: feature #116 WI-5 (#110 Phase 3) — symmetric encryption for WebDAV passwords at rest.
     2	// The store keeps a password only as a SecretCipher token (never plaintext); the production
     3	// impl wraps an AndroidKeyStore AES-GCM key (hardware-backed where available, non-exportable),
     4	// chosen over EncryptedSharedPreferences (deprecated AndroidX Security-Crypto — Gate-2 Low-2).
     5	// The interface lets WebDavServerStore be unit-tested with a fake (AndroidKeyStore isn't
     6	// available under Robolectric/JVM).
     7	package com.vreader.app.backup.net
     8	
     9	import android.security.keystore.KeyGenParameterSpec
    10	import android.security.keystore.KeyProperties
    11	import java.security.KeyStore
    12	import java.util.Base64
    13	import javax.crypto.Cipher
    14	import javax.crypto.KeyGenerator
    15	import javax.crypto.SecretKey
    16	import javax.crypto.spec.GCMParameterSpec
    17	
    18	/** Reversibly protects a secret string. [encrypt]/[decrypt] round-trip; the token is opaque. */
    19	interface SecretCipher {
    20	    fun encrypt(plaintext: String): String
    21	    fun decrypt(token: String): String
    22	}
    23	
    24	/**
    25	 * AES-256-GCM via a non-exportable AndroidKeyStore key. The token is base64( iv ‖ ciphertext ),
    26	 * a fresh random IV per encryption (GCM requirement). Not unit-testable under Robolectric (no
    27	 * AndroidKeyStore); exercised on-device in WI-6.
    28	 */
    29	class KeystoreSecretCipher(private val alias: String = DEFAULT_ALIAS) : SecretCipher {
    30	    override fun encrypt(plaintext: String): String {
    31	        val cipher = Cipher.getInstance(TRANSFORMATION)
    32	        cipher.init(Cipher.ENCRYPT_MODE, key())
    33	        val iv = cipher.iv
    34	        val ct = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))
    35	        return Base64.getEncoder().encodeToString(iv + ct)
    36	    }
    37	
    38	    override fun decrypt(token: String): String {
    39	        val blob = Base64.getDecoder().decode(token)
    40	        val iv = blob.copyOfRange(0, IV_BYTES)
    41	        val ct = blob.copyOfRange(IV_BYTES, blob.size)
    42	        val cipher = Cipher.getInstance(TRANSFORMATION)
    43	        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(TAG_BITS, iv))
    44	        return String(cipher.doFinal(ct), Charsets.UTF_8)
    45	    }
    46	
    47	    private fun key(): SecretKey {
    48	        val ks = KeyStore.getInstance(KEYSTORE).apply { load(null) }
    49	        (ks.getEntry(alias, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
    50	        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
    51	        gen.init(
    52	            KeyGenParameterSpec.Builder(
    53	                alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
    54	            )
    55	                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
    56	                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
    57	                .setKeySize(256)
    58	                .build()
    59	        )
    60	        return gen.generateKey()
    61	    }
    62	
    63	    companion object {
    64	        const val DEFAULT_ALIAS = "vreader.webdav.password"
    65	        private const val KEYSTORE = "AndroidKeyStore"
    66	        private const val TRANSFORMATION = "AES/GCM/NoPadding"
    67	        private const val IV_BYTES = 12
    68	        private const val TAG_BITS = 128
    69	    }
    70	}
     1	// Purpose: feature #116 WI-5 (#110 Phase 3) — persists saved WebDAV server profiles. URL / user /
     2	// name / wifiOnly live in DataStore as a JSON list; the password is kept only as a SecretCipher
     3	// token (AndroidKeyStore AES-GCM in production). The WebDavBackupService (WI-5b) reads a profile +
     4	// decrypts its password to build a WebDavClient. Chosen over EncryptedSharedPreferences (Gate-2
     5	// Low-2). All ops suspend; `observe()` is reactive for the #114 server-list UI.
     6	package com.vreader.app.backup.net
     7	
     8	import androidx.datastore.core.DataStore
     9	import androidx.datastore.preferences.core.Preferences
    10	import androidx.datastore.preferences.core.edit
    11	import androidx.datastore.preferences.core.stringPreferencesKey
    12	import kotlinx.coroutines.flow.Flow
    13	import kotlinx.coroutines.flow.first
    14	import kotlinx.coroutines.flow.map
    15	import kotlinx.serialization.Serializable
    16	import kotlinx.serialization.json.Json
    17	
    18	/** A saved server. `encryptedPassword` is a [SecretCipher] token, never plaintext. */
    19	@Serializable
    20	data class WebDavServerProfile(
    21	    val id: String,
    22	    val name: String,
    23	    val baseUrl: String,
    24	    val username: String,
    25	    val encryptedPassword: String,
    26	    val wifiOnly: Boolean,
    27	)
    28	
    29	class WebDavServerStore(
    30	    private val dataStore: DataStore<Preferences>,
    31	    private val cipher: SecretCipher,
    32	    private val json: Json = Json { ignoreUnknownKeys = true; encodeDefaults = true },
    33	) {
    34	    /** All saved profiles (password still encrypted). */
    35	    suspend fun list(): List<WebDavServerProfile> = read(dataStore.data.first())
    36	
    37	    /** Reactive list for the server-list UI. */
    38	    fun observe(): Flow<List<WebDavServerProfile>> = dataStore.data.map(::read)
    39	
    40	    /**
    41	     * Inserts or updates a profile by [id]. [password] is the PLAINTEXT to encrypt; pass null on an
    42	     * edit that leaves the password unchanged (the existing ciphertext is kept). Returns the saved
    43	     * profile (password encrypted). Throws if [password] is null for a brand-new id.
    44	     */
    45	    suspend fun upsert(
    46	        id: String,
    47	        name: String,
    48	        baseUrl: String,
    49	        username: String,
    50	        password: String?,
    51	        wifiOnly: Boolean,
    52	    ): WebDavServerProfile {
    53	        lateinit var saved: WebDavServerProfile
    54	        dataStore.edit { prefs ->
    55	            val current = read(prefs)
    56	            val existing = current.firstOrNull { it.id == id }
    57	            val encrypted = when {
    58	                password != null -> cipher.encrypt(password)
    59	                existing != null -> existing.encryptedPassword  // unchanged on edit
    60	                else -> throw IllegalArgumentException("a new server ($id) requires a password")
    61	            }
    62	            saved = WebDavServerProfile(id, name, baseUrl, username, encrypted, wifiOnly)
    63	            val next = current.filterNot { it.id == id } + saved
    64	            prefs[KEY] = json.encodeToString(next)
    65	        }
    66	        return saved
    67	    }
    68	
    69	    /** Removes a profile (no-op if absent). */
    70	    suspend fun delete(id: String) {
    71	        dataStore.edit { prefs ->
    72	            val next = read(prefs).filterNot { it.id == id }
    73	            prefs[KEY] = json.encodeToString(next)
    74	        }
    75	    }
    76	
    77	    /** The decrypted password for [id], or null if the profile doesn't exist. */
    78	    suspend fun password(id: String): String? =
    79	        list().firstOrNull { it.id == id }?.let { cipher.decrypt(it.encryptedPassword) }
    80	
    81	    private fun read(prefs: Preferences): List<WebDavServerProfile> {
    82	        val raw = prefs[KEY] ?: return emptyList()
    83	        return runCatching { json.decodeFromString<List<WebDavServerProfile>>(raw) }.getOrDefault(emptyList())
    84	    }
    85	
    86	    companion object {
    87	        private val KEY = stringPreferencesKey("webdav_servers_json")
    88	    }
    89	}
     1	// Purpose: feature #120 WI-1 (#110 Phase 3) — persists saved OPDS catalogs. Name/URL/requiresAuth/
     2	// username live in DataStore as a JSON list; the optional password is kept ONLY as a SecretCipher
     3	// token (a DISTINCT AndroidKeyStore alias from WebDAV/AI — `vreader.opds.password`). Reuses the #116
     4	// WebDavServerStore DataStore+cipher pattern. `clientFor(source)` builds an origin-scoped #117
     5	// OpdsClient. The password is never logged.
     6	package com.vreader.app.opds
     7	
     8	import androidx.datastore.core.DataStore
     9	import androidx.datastore.preferences.core.Preferences
    10	import androidx.datastore.preferences.core.edit
    11	import androidx.datastore.preferences.core.stringPreferencesKey
    12	import com.vreader.app.backup.net.KeystoreSecretCipher
    13	import com.vreader.app.backup.net.SecretCipher
    14	import kotlinx.coroutines.flow.Flow
    15	import kotlinx.coroutines.flow.first
    16	import kotlinx.coroutines.flow.map
    17	import kotlinx.serialization.Serializable
    18	import kotlinx.serialization.json.Json
    19	import java.net.URL
    20	
    21	/** A saved OPDS catalog. `encryptedPassword` is a [SecretCipher] token (blank when no auth). */
    22	@Serializable
    23	data class OpdsSource(
    24	    val id: String,
    25	    val name: String,
    26	    val url: String,
    27	    val requiresAuth: Boolean = false,
    28	    val username: String = "",
    29	    val encryptedPassword: String = "",
    30	)
    31	
    32	class OpdsSourceStore(
    33	    private val dataStore: DataStore<Preferences>,
    34	    private val cipher: SecretCipher = KeystoreSecretCipher(ALIAS),
    35	    private val json: Json = Json { ignoreUnknownKeys = true; encodeDefaults = true },
    36	) {
    37	    suspend fun list(): List<OpdsSource> = read(dataStore.data.first())
    38	    fun observe(): Flow<List<OpdsSource>> = dataStore.data.map(::read)
    39	
    40	    /**
    41	     * Insert/update by [id]. [password] is the PLAINTEXT to encrypt; pass null to keep the existing
    42	     * (edit without changing it). When [requiresAuth] is false the username/password are CLEARED.
    43	     */
    44	    suspend fun upsert(
    45	        id: String,
    46	        name: String,
    47	        url: String,
    48	        requiresAuth: Boolean,
    49	        username: String,
    50	        password: String?,
    51	    ): OpdsSource {
    52	        lateinit var saved: OpdsSource
    53	        dataStore.edit { prefs ->
    54	            val cur = read(prefs)
    55	            val existing = cur.firstOrNull { it.id == id }
    56	            saved = if (!requiresAuth) {
    57	                OpdsSource(id, name, url, requiresAuth = false)  // auth off → no creds stored
    58	            } else {
    59	                val enc = when {
    60	                    password != null -> cipher.encrypt(password)
    61	                    existing != null && existing.requiresAuth -> existing.encryptedPassword
    62	                    else -> ""  // auth on but no password yet (the user can still browse public sections)
    63	                }
    64	                OpdsSource(id, name, url, requiresAuth = true, username = username, encryptedPassword = enc)
    65	            }
    66	            prefs[KEY] = json.encodeToString(cur.filterNot { it.id == id } + saved)
    67	        }
    68	        return saved
    69	    }
    70	
    71	    suspend fun delete(id: String) {
    72	        dataStore.edit { prefs -> prefs[KEY] = json.encodeToString(read(prefs).filterNot { it.id == id }) }
    73	    }
    74	
    75	    /** The decrypted password for [source], or null if it has no auth / no password. */
    76	    fun password(source: OpdsSource): String? =
    77	        if (source.requiresAuth && source.encryptedPassword.isNotBlank()) cipher.decrypt(source.encryptedPassword) else null
    78	
    79	    /** Build a #117 OpdsClient scoped to this catalog's origin (so auth never leaks cross-origin). */
    80	    fun clientFor(source: OpdsSource): OpdsClient {
    81	        val user = if (source.requiresAuth && source.username.isNotBlank()) source.username else null
    82	        // Decrypt ONLY when a usable auth client will actually be built — a corrupt/stale token on a
    83	        // source with no username would otherwise throw even though no auth header would be sent.
    84	        val pass = if (user != null) password(source) else null
    85	        return OpdsClient(username = user, password = pass, authOrigin = if (user != null) originOf(source.url) else null)
    86	    }
    87	
    88	    private fun originOf(url: String): String? = runCatching {
    89	        val u = URL(url); val port = if (u.port == -1) u.defaultPort else u.port
    90	        "${u.protocol.lowercase()}://${u.host.lowercase()}:$port"
    91	    }.getOrNull()
    92	
    93	    private fun read(prefs: Preferences): List<OpdsSource> {
    94	        val raw = prefs[KEY] ?: return emptyList()
    95	        return runCatching { json.decodeFromString<List<OpdsSource>>(raw) }.getOrDefault(emptyList())
    96	    }
    97	
    98	    companion object {
    99	        const val ALIAS = "vreader.opds.password"
   100	        private val KEY = stringPreferencesKey("opds_sources_json")
   101	    }
   102	}
     1	// Purpose: feature #118 WI-3 (#110 Phase 3) — UI state for the AI provider list + editor surfaces
     2	// (the committed `AiProviderList` + the `EditorSheet` contract from vreader-ai-android.jsx /
     3	// vreader-ai-provider-fields.jsx). Stateless composables render a pure function of these.
     4	package com.vreader.app.ai
     5	
     6	/** Test-connection state for the editor's Connection section (mirrors the design's test states). */
     7	enum class AiConnTest { idle, testing, ok, fail }
     8	
     9	/** One row in the provider list: active radio + name + model (ok) or the rejection reason (fail). */
    10	data class AiProviderRow(
    11	    val id: String,
    12	    val name: String,
    13	    val active: Boolean,
    14	    val statusOk: Boolean,
    15	    val detail: String,  // model when ok, e.g. "401 — key rejected" when fail
    16	)
    17	
    18	/** The provider-list screen state. */
    19	data class AiProviderListState(
    20	    val providers: List<AiProviderRow> = emptyList(),
    21	) {
    22	    val unconfigured: Boolean get() = providers.isEmpty()
    23	}
    24	
    25	/** The add/edit provider form state (the EditorSheet contract). */
    26	data class AiEditState(
    27	    val editMode: Boolean = false,
    28	    val id: String? = null,
    29	    val kind: AiProviderKind = AiProviderKind.openAiCompatible,
    30	    val name: String = "",
    31	    val baseUrl: String = "",      // blank → kind default
    32	    val model: String = "",        // blank → kind default
    33	    val temperature: Double = 0.7,
    34	    val maxTokens: Int = 2048,
    35	    val apiKey: String = "",       // entered key (blank in edit = keep existing)
    36	    val keyAlreadySaved: Boolean = false,  // edit mode with a stored key
    37	    val test: AiConnTest = AiConnTest.idle,
    38	    val testMessage: String = "",
    39	) {
    40	    /** canSave = name non-empty AND a key is available — entered now, or already saved on edit (a
    41	     *  blank base/model fall back to the kind default = valid; a NEW provider must have a key, since
    42	     *  the store rejects a keyless new profile). */
    43	    val canSave: Boolean get() = name.isNotBlank() && (apiKey.isNotBlank() || (editMode && keyAlreadySaved))
    44	    /** Test is enabled once a key is available (entered now, or already saved in edit mode). */
    45	    val canTest: Boolean get() = apiKey.isNotBlank() || keyAlreadySaved
    46	    val effectiveBaseUrl: String get() = baseUrl.ifBlank { kind.defaultBaseUrl }
    47	    val effectiveModel: String get() = model.ifBlank { kind.defaultModel }
    48	}
    35	import com.vreader.app.reader.PdfReaderActivity
    36	import com.vreader.app.reader.TxtReaderActivity
    37	import com.vreader.app.search.SearchScreen
    38	import com.vreader.app.ui.theme.VReaderTheme
    39	import vreader.contracts.BookFormat
    40	import androidx.compose.runtime.LaunchedEffect
    41	
    42	class MainActivity : ComponentActivity() {
    43	    override fun onCreate(savedInstanceState: Bundle?) {
    44	        super.onCreate(savedInstanceState)
    45	        val container = (application as VReaderApp).container
    46	        val factory = viewModelFactory {
    47	            initializer { LibraryViewModel(container.repository, container.importer, container.collectionRepository, contentResolver) }
    48	        }
    49	
    50	        setContent {
    51	            VReaderTheme {
    52	                val viewModel: LibraryViewModel = viewModel(factory = factory)
    53	                val state by viewModel.uiState.collectAsStateWithLifecycle()
    54	                val collections by viewModel.collections.collectAsStateWithLifecycle()
    55	                val selectedCollectionId by viewModel.selectedCollectionId.collectAsStateWithLifecycle()
    56	                // feature #127 WI-4 — which collections sheet is open (survives rotation/process death).
    57	                var sheetRoute by rememberSaveable(stateSaver = SheetRouteSaver) { mutableStateOf<SheetRoute>(SheetRoute.None) }
    58	                // feature #128 WI-7 — the search takeover open/closed flag (the SheetRoute saveable
    59	                // precedent; a Boolean needs no custom Saver, so rememberSaveable survives rotation/death).
    60	                var searchOpen by rememberSaveable { mutableStateOf(false) }
    61	
    62	                val picker = rememberLauncherForActivityResult(
    63	                    ActivityResultContracts.OpenDocument(),
    64	                ) { uri -> uri?.let(viewModel::import) }
    65	
    66	                LaunchedEffect(Unit) {
    67	                    viewModel.events.collect { event ->
    68	                        val message = when (event) {
    69	                            is LibraryEvent.ImportFailed -> event.message
    70	                            is LibraryEvent.CollectionOpFailed -> event.message
    71	                        }
    72	                        Toast.makeText(this@MainActivity, message, Toast.LENGTH_SHORT).show()
    73	                    }
    74	                }
    75	
    76	                // Route by the typed format (exhaustive — never open a format into the wrong host).
    77	                // Shared by the library grid tap and the search result tap (both carry a typed format +
    78	                // fingerprintKey).
    79	                fun openBook(format: BookFormat, key: String) {
    80	                    when (format) {
    81	                        BookFormat.epub ->
    82	                            startActivity(ReaderActivity.intent(this@MainActivity, key))
    83	                        BookFormat.txt, BookFormat.md ->
    84	                            // .md reuses the text reader host (#112): same decode/
    85	                            // document/resume/chrome, MarkdownRenderer per chunk.
    86	                            startActivity(TxtReaderActivity.intent(this@MainActivity, key))
    87	                        BookFormat.pdf ->
    88	                            // #115 — continuous-scroll PdfRenderer reader.
    89	                            startActivity(PdfReaderActivity.intent(this@MainActivity, key))
    90	                        BookFormat.azw3 ->
    91	                            // #126 — foliate-js WebView reader (AZW3/MOBI/KF8).
    92	                            startActivity(Azw3ReaderActivity.intent(this@MainActivity, key))
    93	                    }
    94	                }
    95	
    96	                LibraryScreen(
    97	                    state = state,
    98	                    collections = collections,
    99	                    selectedCollectionId = selectedCollectionId,
   100	                    onSelectCollection = viewModel::selectCollection,
   101	                    onAssignBook = { book -> sheetRoute = SheetRoute.Assign(book.id) },
   102	                    onManageCollections = { sheetRoute = SheetRoute.Manage },
   103	                    onOpenSearch = { searchOpen = true },
   104	                    onOpenBook = { book -> openBook(book.originalFormat, book.id) },
   105	                    // EPUBs are exposed by SAF providers under varied MIME types
   106	                    // (epub+zip, octet-stream, generic); accept broadly and let
   107	                    // BookImporter reject non-EPUBs by extension with a clear toast.
   108	                    onImport = {
   109	                        picker.launch(
   110	                            arrayOf("application/epub+zip", "application/octet-stream", "*/*"),
   111	                        )
   112	                    },
   113	                )
   114	
   115	                // feature #128 WI-7 — the search takeover. Rendered OVER the library when open; fed by
   116	                // the AppContainer's SearchViewModel (WI-6). Obtained through `viewModel(factory=…)` so it's
   117	                // owned by the Activity's ViewModelStore — its viewModelScope is properly cleared on the
   118	                // Activity's destroy (a raw `remember { … }` would leak the coroutine collector forever).
   119	                if (searchOpen) {
   120	                    val searchViewModel: com.vreader.app.search.SearchViewModel = viewModel(
    45	import androidx.compose.ui.graphics.Color
    46	import androidx.compose.ui.text.font.FontWeight
    47	import androidx.compose.ui.text.style.TextOverflow
    48	import androidx.compose.ui.unit.dp
    49	import androidx.compose.ui.unit.sp
    50	import com.vreader.app.ui.theme.VReaderColors
    51	import com.vreader.app.ui.theme.VReaderFonts
    52	
    53	private enum class LibraryView { Grid, List }
    54	
    55	@Composable
    56	fun LibraryScreen(
    57	    state: LibraryUiState,
    58	    onOpenBook: (LibraryBook) -> Unit,
    59	    onImport: () -> Unit,
    60	    // feature #128 WI-7 — the functional Search pill in the nav row opens the search takeover.
    61	    onOpenSearch: () -> Unit = {},
    62	    // feature #127 — collections shelf-bar (empty list = no bar; "All" = null selection).
    63	    collections: List<com.vreader.app.data.Collection> = emptyList(),
    64	    selectedCollectionId: String? = null,
    65	    onSelectCollection: (String?) -> Unit = {},
    66	    // feature #127 WI-4 — long-press a book to assign it to collections.
    67	    onAssignBook: (LibraryBook) -> Unit = {},
    68	    // feature #127 WI-5 — open the manage-collections sheet (shown once a collection exists).
    69	    onManageCollections: () -> Unit = {},
    70	) {
    71	    // Boolean (not the enum) so rememberSaveable persists the mode across rotation /
    72	    // process recreation without a custom Saver.
    73	    var isGrid by rememberSaveable { mutableStateOf(true) }
    74	    val view = if (isGrid) LibraryView.Grid else LibraryView.List
    75	
    76	    Column(
    77	        Modifier.fillMaxSize().background(VReaderColors.Background).systemBarsPadding(),
    78	    ) {
    79	        // feature #127 — header. When a collection is selected the design's `scope === 'collection'`
    80	        // surface replaces the WHOLE all-library header (nav pills + "Library" title + shelf-bar) with
    81	        // just the scoped-collection header: a back breadcrumb to "All", the collection name (serif), and
    82	        // a "N books · edit collection" subtitle (the DESIGNED manage-sheet entry). The scoped view has NO
    83	        // action pills (Gate-4 WI-5 round-2 Medium, rule 51) — the nav pills live only in the All branch.
    84	        val selectedCollection = collections.firstOrNull { it.id == selectedCollectionId }
    85	        if (selectedCollection != null) {
    86	            ScopedCollectionHeader(
    87	                collectionName = selectedCollection.name,
    88	                bookCount = state.books.size,
    89	                onBack = { onSelectCollection(null) },
    90	                onEditCollection = onManageCollections,
    91	            )
    92	        } else {
    93	            // Nav bar — the functional controls (search / view-toggle / import). The Search pill
    94	            // is wired as of feature #128 WI-7 (opens the search takeover). The design's
    95	            // settings/More pill is added when that feature lands (a separate WI); shipping a
    96	            // non-functional control is a fidelity defect, so it's still omitted.
    97	            Row(
    98	                Modifier.fillMaxWidth().padding(start = 18.dp, end = 18.dp, top = 6.dp),
    99	                horizontalArrangement = Arrangement.End,
   100	                verticalAlignment = Alignment.CenterVertically,
   101	            ) {
   102	                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
   103	                    PillIcon(Icons.Filled.Search, "Search", onOpenSearch)
   104	                    PillIcon(
   105	                        if (view == LibraryView.Grid) Icons.AutoMirrored.Filled.ViewList else Icons.Filled.GridView,
   106	                        "Toggle view",
   107	                    ) { isGrid = !isGrid }
   108	                    PillIcon(Icons.Filled.Add, "Import book", onImport)
   109	                }
   110	            }
   111	
   112	            // Title + count.
   113	            Text(
   114	                "Library",
   115	                Modifier.padding(start = 22.dp, end = 22.dp, top = 12.dp, bottom = 4.dp),

exec
/bin/zsh -lc "nl -ba dev-docs/designs/vreader-fidelity-v1/project/vreader-more.jsx | sed -n '1,180p'
rg -n \"AiProviderList|AI Providers|Provider|Variant A|scoped|in-reader|sheet|configure-ai|deferred|do NOT build|Do not build\" dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-android.jsx dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-readiness.md
nl -ba dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md | sed -n '1,280p'
nl -ba dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-readiness.md | sed -n '1,280p'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
     1	// More-menu popover — anchored to the "..." button in reader top chrome.
     2	// Issue #760: design the contents of the More menu.
     3	
     4	function MorePopover({ theme, state, onToggle, onAction, onClose }) {
     5	  const t = theme;
     6	  const s = state || {};
     7	
     8	  const Row = ({ icon, label, sub, value, toggle, active, danger, divider, on, disabled }) => {
     9	    if (divider) {
    10	      return <div style={{
    11	        height: 0.5, background: t.rule, margin: '4px 14px',
    12	      }}/>;
    13	    }
    14	    const Ico = icon;
    15	    return (
    16	      <button onClick={disabled ? undefined : on} style={{
    17	        display: 'flex', alignItems: 'center', gap: 12,
    18	        padding: '11px 14px', width: '100%', border: 'none',
    19	        background: 'transparent', cursor: disabled ? 'default' : 'pointer', textAlign: 'left',
    20	        opacity: disabled ? 0.55 : 1,
    21	      }}>
    22	        <div style={{
    23	          width: 28, height: 28, borderRadius: 8,
    24	          background: active
    25	            ? (t.isDark ? `${t.accent}33` : `${t.accent}1a`)
    26	            : (t.isDark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.04)'),
    27	          display: 'flex', alignItems: 'center', justifyContent: 'center',
    28	          flexShrink: 0,
    29	        }}>
    30	          <Ico size={15} color={active ? t.accent : t.ink} stroke={1.7}/>
    31	        </div>
    32	        <div style={{ flex: 1, minWidth: 0 }}>
    33	          <div style={{
    34	            fontSize: 14.5, color: danger ? '#c44' : t.ink,
    35	            fontWeight: 500, lineHeight: 1.2,
    36	          }}>{label}</div>
    37	          {sub && (
    38	            <div style={{
    39	              fontSize: 11, color: disabled ? t.accent : t.sub, marginTop: 2, lineHeight: 1.2,
    40	              fontWeight: disabled ? 600 : 400,
    41	            }}>{sub}</div>
    42	          )}
    43	        </div>
    44	        {toggle !== undefined && !disabled && (
    45	          <ToggleSwitch on={!!toggle} theme={t}/>
    46	        )}
    47	        {value && (
    48	          <span style={{ fontSize: 12, color: t.sub, marginRight: 2 }}>{value}</span>
    49	        )}
    50	        {(disabled || (toggle === undefined && value === undefined)) && (
    51	          <Icons.Chevron size={13} color={t.sub} stroke={2}/>
    52	        )}
    53	      </button>
    54	    );
    55	  };
    56	
    57	  return (
    58	    <>
    59	      {/* dim backdrop */}
    60	      <div onClick={onClose} style={{
    61	        position: 'absolute', inset: 0, zIndex: 70,
    62	        background: 'transparent',
    63	      }}/>
    64	      {/* popover */}
    65	      <div style={{
    66	        position: 'absolute', top: 92, right: 14, zIndex: 75,
    67	        width: 268, borderRadius: 16,
    68	        background: t.isDark ? '#2a2724' : '#fcf8f0',
    69	        boxShadow: '0 12px 36px rgba(0,0,0,0.28), 0 0 0 0.5px ' + (t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'),
    70	        padding: '6px 0', overflow: 'hidden',
    71	      }}>
    72	        {/* notch pointing to ... button */}
    73	        <div style={{
    74	          position: 'absolute', top: -6, right: 24,
    75	          width: 12, height: 12, transform: 'rotate(45deg)',
    76	          background: t.isDark ? '#2a2724' : '#fcf8f0',
    77	          boxShadow: '-1px -1px 0 0 ' + (t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'),
    78	        }}/>
    79	
    80	        <Row icon={Icons.Volume} label="Read aloud"
    81	             sub={s.ttsPlaying ? 'Playing · System voice' : 'Start text-to-speech'}
    82	             active={s.ttsPlaying}
    83	             on={() => onAction('tts')}/>
    84	
    85	        <Row icon={Icons.Timer} label="Auto-turn pages"
    86	             sub={s.autoTurn ? `Every ${s.autoTurnInterval || 30}s` : 'Off'}
    87	             toggle={s.autoTurn}
    88	             active={s.autoTurn}
    89	             on={() => onToggle('autoTurn')}/>
    90	
    91	        {s.aiUnavailable ? (
    92	          <Row icon={Icons.Translate} label="Bilingual mode"
    93	               sub="Configure AI provider first"
    94	               disabled
    95	               on={() => onAction('configure-ai')}/>
    96	        ) : (
    97	          <Row icon={Icons.Translate} label="Bilingual mode"
    98	               sub={s.bilingual ? `English ↔ ${s.bilingualLang || 'Chinese'}` : 'Translate inline'}
    99	               toggle={s.bilingual}
   100	               active={s.bilingual}
   101	               on={() => onToggle('bilingual')}/>
   102	        )}
   103	
   104	        <Row divider/>
   105	
   106	        <Row icon={Icons.Info} label="Book details"
   107	             on={() => onAction('details')}/>
   108	
   109	        <Row icon={Icons.Share} label="Share book"
   110	             on={() => onAction('share')}/>
   111	
   112	        <Row icon={Icons.Download} label="Export annotations"
   113	             sub="Markdown · JSON · VReader JSON"
   114	             on={() => onAction('export')}/>
   115	      </div>
   116	    </>
   117	  );
   118	}
   119	
   120	// Tiny iOS-style toggle
   121	function ToggleSwitch({ on, theme }) {
   122	  const t = theme;
   123	  return (
   124	    <div style={{
   125	      width: 34, height: 20, borderRadius: 10, position: 'relative',
   126	      background: on ? '#3a6a5a' : (t.isDark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.12)'),
   127	      transition: 'background 0.15s',
   128	      flexShrink: 0,
   129	    }}>
   130	      <div style={{
   131	        position: 'absolute', top: 2, left: on ? 16 : 2,
   132	        width: 16, height: 16, borderRadius: 8, background: '#fff',
   133	        transition: 'left 0.15s',
   134	        boxShadow: '0 1px 2px rgba(0,0,0,0.2), 0 0.5px 0 rgba(0,0,0,0.06)',
   135	      }}/>
   136	    </div>
   137	  );
   138	}
   139	
   140	Object.assign(window, { MorePopover });
dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-android.jsx:17:function AiProviderList({ ui, state = 'configured', height = 880 }) {
dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-android.jsx:30:          <div style={{ flex: 1, fontFamily: AI_SERIF, fontSize: 18, fontWeight: 600, color: ui.ink }}>AI Providers</div>
dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-android.jsx:50:              <GroupHeader ui={ui}>Providers</GroupHeader>
dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-android.jsx:164:          <GroupHeader ui={ui}>Provider</GroupHeader>
dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-android.jsx:166:            <Row ui={ui} label="Provider"><ValueText ui={ui} text="Claude (Anthropic)" /></Row>
dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-android.jsx:210:        {/* chat sheet */}
dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-android.jsx:306:Object.assign(window, { AiProviderList, BilingualReader, BilingualSetupSheet, AiChatPanel });
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-readiness.md:5:> Resolves needs-design [#1394](https://github.com/lllyys/vreader/issues/1394) (Feature **#82**). Follow-up to Feature #81 (#1380, in-reader provider entry) and Bug #301 (truthful engine strip).
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-readiness.md:6:> Status: **design landed — implementation deferred** (recorded, not built; Swift held for a separate go-ahead per the handoff convention).
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-readiness.md:12:Feature #81 lets a user **add a provider** in-reader — but on a fresh device the **flag and
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-readiness.md:21:## Decision (binding) — Variant A: "Set up translation" readiness sheet
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-readiness.md:23:Reached from the bilingual engine strip's **"Set up"**. One scoped sheet makes the whole
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-readiness.md:34:4. **Provider step** — reuses the canonical `AIProviderEditSheet` (#81/#1363) **unchanged**
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-readiness.md:50:## Production wiring (deferred — do NOT build without go-ahead)
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-readiness.md:52:- New `ReaderAIReadinessSheet` (or extend the #81 `ReaderAIProvidersView` into a readiness
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-readiness.md:53:  container) presented from `BilingualSetupSheet.onOpenSettings` (currently the deferred slice
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-readiness.md:56:  the #81 provider list (`AIProviderEditSheet` reused).
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-readiness.md:59:- The same readiness sheet is the route target for **Bug #308** (bottom-bar AI button) and the
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:1:# In-reader AI Providers entry — from the bilingual "Set up" button
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:5:> Source of truth: `VReader AI Provider Entry Canvas.html` (every state across themes).
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:8:**Decision: a scoped, in-reader "AI Providers" sheet pushed inside the bilingual
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:9:flow, reusing the canonical `AIProviderEditSheet` for the actual add/edit, and
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:10:returning to the bilingual sheet with the new provider already selected as the
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:11:engine.** Components: `AIProvidersSheet` (list, empty + populated), `BilingualEngineStrip`
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:18:Bug #301 made the bilingual setup sheet *truthful*: when no AI provider is
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:21:sheet** — it routes nowhere.
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:23:Wiring it is not a one-liner, because the in-reader → AI Providers path does not
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:26:- The reader's `showSettings` sheet presents **only** `ReaderSettingsPanel`
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:31:So "Set up" has nothing to call. This is a new in-reader navigation surface →
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:39:### A — Scoped AI Providers sheet, pushed in the bilingual flow  ·  CANONICAL
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:41:"Set up" pushes a **navigation level inside the same bottom sheet** — same frame,
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:42:same height, slide-left push. Nav bar: `‹ Bilingual` leading, **AI Providers**
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:49:- **Add provider** presents the canonical `AIProviderEditSheet`
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:50:  (`vreader-ai-provider-fields.jsx`) as its own modal sheet — full height,
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:65:  already shipped in `AIProviderEditSheet` comes for free.
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:66:- **Keeps the reader context.** A scoped sheet, not the whole app-settings tree.
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:91:  back to the reader with the bilingual sheet already gone, so the "I was turning
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:94:### C — Inline expansion inside the bilingual sheet
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:99:- **Pro:** the tightest possible loop — the user never leaves the bilingual sheet.
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:102:  key, and a live connection test. A bilingual half-sheet can't host that without
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:104:  `AIProviderEditSheet`** — at which point a key saved here wouldn't be testable,
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:114:        └─ BilingualSetupSheet        [bottom sheet · height 620]
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:117:                                   ▼   (push, slide-left, same sheet frame)
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:118:           AIProvidersSheet           [nav bar: ‹ Bilingual · "AI Providers"]
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:122:                          AIProviderEditSheet   [vreader-ai-provider-fields.jsx]
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:129:- The AI Providers view is a **push within the bilingual sheet**, NOT a modal over
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:132:- "Change…" on an already-configured strip opens the **same** `AIProvidersSheet`,
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:140:- The bilingual sheet, engine unconfigured, "Set up" highlighted (start point) —
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:144:- AI Providers — empty (no providers) + bilingual-context note + Add CTA.
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:145:- Add Provider — the canonical `AIProviderEditSheet`, pushed.
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:146:- AI Providers — populated, new provider "In use" checked, Done.
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:162:- New reader-scoped presentation: a lightweight nav container hosting **only**
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:163:  `AISettingsSection`'s provider list — call it `ReaderAIProvidersView`. It is NOT
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:164:  `SettingsView`; it reuses the same `AIProviderListView` + `AIProviderEditSheet`
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:166:- `BilingualSetupSheet.onOpenSettings` → presents `ReaderAIProvidersView` as a
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:167:  push inside the bilingual sheet's own `NavigationStack` (so `‹ Bilingual` is a
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:169:- On `AIProviderEditSheet` Save when launched from this flow: set the saved
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:170:  provider as the bilingual mode engine (`BilingualConfig.engineProviderID`) and
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:171:  dismiss back to the bilingual sheet (pop to root).
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:176:  full list. This adds a *second*, scoped entry — it does not move the first.
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:182:| `VReader AI Provider Entry Canvas.html` | Canvas of every state across themes. Source of truth. |
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:183:| `vreader-ai-provider-entry.jsx` | `AIProvidersSheet`, `BilingualEngineStrip`, `EngineStripInline`, `NavFlowDiagram` — #1380 |
dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:184:| `vreader-ai-provider-fields.jsx` | `EditorSheet` (`AIProviderEditSheet`) — reused unchanged for the add/edit step (#1363) |
dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx:1:// In-reader AI Providers entry — issue #1380.
dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx:3:// Wires the bilingual setup sheet's "Set up" button (shown when no AI provider
dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx:4:// is configured, per Bug #301) to an actual AI Providers surface — which does
dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx:5:// not exist in-reader today (the reader's showSettings sheet is display/fonts
dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx:8:// CANONICAL (A): a scoped "AI Providers" sheet PUSHED inside the bilingual
dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx:9://   flow (nav bar: ‹ Bilingual · "AI Providers"), hosting only the provider
dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx:10://   list. Empty → "Add provider" → the canonical AIProviderEditSheet
dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx:17://   C — inline expansion of the engine strip inside the bilingual sheet.
dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx:20:// tile keeps the fixed #8c2f2f brand color used by the shipped AI Provider row.
dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx:27:// NavSheet — bottom sheet with an iOS-style navigation bar (back + centered
dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx:28:// title + trailing). This is the "push within the sheet" presentation: same
dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx:128:// Provider list row — matches the shipped SettingsRow vocabulary.
dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx:130:function ProviderRow({ theme, name, model, selected, onClick, last }) {
dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx:160:// AI Providers sheet body — empty + populated.
dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx:162:function AIProvidersSheetBody({ theme, providers, selectedId, onAdd, onSelect }) {
dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx:213:          <SectionLabel theme={t}>Providers</SectionLabel>
dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx:220:              <ProviderRow key={p.id} theme={t} name={p.name} model={p.model}
dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx:245:function AIProvidersSheet({ theme, providers = [], selectedId, onBack, onAdd, onSelect, trailing, height = 620 }) {
dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx:247:    <NavSheet theme={theme} height={height} title="AI Providers" backLabel="Bilingual" onBack={onBack} trailing={trailing}>
dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx:248:      <AIProvidersSheetBody theme={theme} providers={providers} selectedId={selectedId} onAdd={onAdd} onSelect={onSelect}/>
dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx:398:  NavSheet, BilingualEngineStrip, ProviderRow,
dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx:399:  AIProvidersSheetBody, AIProvidersSheet,
     1	# In-reader AI Providers entry — from the bilingual "Set up" button
     2	
     3	> Resolves [#1380](https://github.com/lllyys/vreader/issues/1380). Splits off the
     4	> routing slice of Bug [#301](https://github.com/lllyys/vreader/pull/301) (GH [#1356](https://github.com/lllyys/vreader/issues/1356)).
     5	> Source of truth: `VReader AI Provider Entry Canvas.html` (every state across themes).
     6	> Component file: `vreader-ai-provider-entry.jsx`. Editor reused from `vreader-ai-provider-fields.jsx`.
     7	
     8	**Decision: a scoped, in-reader "AI Providers" sheet pushed inside the bilingual
     9	flow, reusing the canonical `AIProviderEditSheet` for the actual add/edit, and
    10	returning to the bilingual sheet with the new provider already selected as the
    11	engine.** Components: `AIProvidersSheet` (list, empty + populated), `BilingualEngineStrip`
    12	(before/after), plus the inline-expansion alternative `EngineStripInline`.
    13	
    14	---
    15	
    16	## The gap this fills
    17	
    18	Bug #301 made the bilingual setup sheet *truthful*: when no AI provider is
    19	configured, the engine strip stops claiming "configured" and shows a **"Set up"**
    20	button. But `BilingualSetupSheet.onOpenSettings` currently just **dismisses the
    21	sheet** — it routes nowhere.
    22	
    23	Wiring it is not a one-liner, because the in-reader → AI Providers path does not
    24	exist:
    25	
    26	- The reader's `showSettings` sheet presents **only** `ReaderSettingsPanel`
    27	  (display / fonts / theme).
    28	- The full `SettingsView` — the one that contains `AISettingsSection` — is
    29	  presented **only from the Library**.
    30	
    31	So "Set up" has nothing to call. This is a new in-reader navigation surface →
    32	`needs-design` per rule 51. The question the issue poses: **where does "Set up"
    33	land, and how is it presented?**
    34	
    35	---
    36	
    37	## Three approaches
    38	
    39	### A — Scoped AI Providers sheet, pushed in the bilingual flow  ·  CANONICAL
    40	
    41	"Set up" pushes a **navigation level inside the same bottom sheet** — same frame,
    42	same height, slide-left push. Nav bar: `‹ Bilingual` leading, **AI Providers**
    43	title. The body is *only* the `AISettingsSection` provider list — nothing else
    44	from `SettingsView`.
    45	
    46	- **Zero providers** → the list shows an empty state (sparkle tile, one line of
    47	  copy naming *why* the user is here — "Bilingual mode needs a provider to
    48	  translate") and a single **Add provider** CTA.
    49	- **Add provider** presents the canonical `AIProviderEditSheet`
    50	  (`vreader-ai-provider-fields.jsx`) as its own modal sheet — full height,
    51	  unchanged from the Library path. Kind / Name / Endpoint / Sampling / API Key /
    52	  Test Connection all intact.
    53	- **On the first Save**, the new provider becomes the bilingual engine default
    54	  and the stack **pops all the way back to Bilingual**. The engine strip now reads
    55	  *"Claude · configured" / "Change…"*, ready for **Turn on bilingual mode**. That
    56	  return is the payoff — the user lands exactly where they started, with the one
    57	  thing they were missing now filled in.
    58	- Tapping `‹ Bilingual` *without* adding returns to Bilingual still unconfigured —
    59	  no state mutated, no penalty for backing out.
    60	
    61	**Why A wins**
    62	
    63	- **Reuses the canonical editor.** No second, diverging "add a provider" form to
    64	  maintain. Test Connection, keychain storage, endpoint hints — all the work
    65	  already shipped in `AIProviderEditSheet` comes for free.
    66	- **Keeps the reader context.** A scoped sheet, not the whole app-settings tree.
    67	  The user never sees Cloud & Sync, OPDS catalogs, Book sources, TTS, replacement
    68	  rules — none of which they came for.
    69	- **Closes the loop.** The user's actual goal is "turn on bilingual"; A returns
    70	  them to that goal with the blocker removed. B and C both leak that thread.
    71	- **One surface for both entry points.** "Change…" (when already configured) lands
    72	  on the *same* list, current provider checked — so add-first and change-later
    73	  share a destination.
    74	
    75	The extra navigation level (list → editor) looks like a cost when there are zero
    76	providers, but it isn't: the empty state is a one-tap shortcut into the editor.
    77	When the user *does* already have providers (added from Library, or for the AI
    78	chat assistant), the list is the correct landing — "Set up" should let them pick,
    79	not silently create a duplicate.
    80	
    81	### B — Deep-link into the full `SettingsView`, scrolled to the AI section
    82	
    83	Present the entire app `SettingsView` modally over the reader, auto-scrolled and
    84	briefly highlighting the AI section.
    85	
    86	- **Pro:** one surface, verbatim reuse of the Library path, no new navigation
    87	  container.
    88	- **Why not canonical:** it dumps a reader-context user into the *whole* app
    89	  configuration — Cloud, OPDS, sources, TTS, Chinese conversion, About — to do one
    90	  narrow thing. And the return is ambiguous: closing `SettingsView` drops the user
    91	  back to the reader with the bilingual sheet already gone, so the "I was turning
    92	  on bilingual" thread is lost. They have to re-open More → toggle bilingual again.
    93	
    94	### C — Inline expansion inside the bilingual sheet
    95	
    96	"Set up" expands the engine strip *in place* into a minimal provider-+-key form;
    97	no navigation at all.
    98	
    99	- **Pro:** the tightest possible loop — the user never leaves the bilingual sheet.
   100	- **Why not canonical:** the real provider model is not "provider + key". It's
   101	  kind, name, base URL (with append-path hints), model, sampling, keychain-stored
   102	  key, and a live connection test. A bilingual half-sheet can't host that without
   103	  either cramping it or shipping a stripped-down form that **diverges from
   104	  `AIProviderEditSheet`** — at which point a key saved here wouldn't be testable,
   105	  and two "add provider" surfaces would drift. Held in reserve for a future
   106	  "express setup" only if we ever ship a genuinely one-field provider kind.
   107	
   108	---
   109	
   110	## Navigation model (precise)
   111	
   112	```
   113	   More ▸ Bilingual mode (first toggle on)
   114	        └─ BilingualSetupSheet        [bottom sheet · height 620]
   115	             engine strip: "No AI provider configured"  [ Set up ]
   116	                                   │  onOpenSettings
   117	                                   ▼   (push, slide-left, same sheet frame)
   118	           AIProvidersSheet           [nav bar: ‹ Bilingual · "AI Providers"]
   119	             ├─ empty  → [ Add provider ] ─┐
   120	             └─ list   → tap a row sets it │  (present modal, full height)
   121	                                   ▼        ▼
   122	                          AIProviderEditSheet   [vreader-ai-provider-fields.jsx]
   123	                                   │  Save
   124	                                   ▼   (provider becomes bilingual engine,
   125	                                        pop the whole stack)
   126	           BilingualSetupSheet  ← engine strip now "Claude · configured" / Change…
   127	```
   128	
   129	- The AI Providers view is a **push within the bilingual sheet**, NOT a modal over
   130	  the reader and NOT the full `SettingsView`.
   131	- The editor is a **modal on top** (tall form deserves full height).
   132	- "Change…" on an already-configured strip opens the **same** `AIProvidersSheet`,
   133	  populated, current provider checked.
   134	
   135	---
   136	
   137	## States — covered exhaustively in the canvas
   138	
   139	**Trigger**
   140	- The bilingual sheet, engine unconfigured, "Set up" highlighted (start point) —
   141	  paper + dark.
   142	
   143	**A · canonical**
   144	- AI Providers — empty (no providers) + bilingual-context note + Add CTA.
   145	- Add Provider — the canonical `AIProviderEditSheet`, pushed.
   146	- AI Providers — populated, new provider "In use" checked, Done.
   147	- Return to Bilingual — engine configured, "Change…", ready to turn on (payoff).
   148	- Empty + populated in dark.
   149	- Reached via "Change…" — multiple providers, switching the selected one.
   150	
   151	**B · alternative** — full `SettingsView` deep-link, AI section highlighted —
   152	paper + dark.
   153	
   154	**C · alternative** — inline expansion in the bilingual strip — paper + dark.
   155	
   156	**D · anatomy** — the nav-stack diagram + engine-strip before/after, true size.
   157	
   158	---
   159	
   160	## Production wiring
   161	
   162	- New reader-scoped presentation: a lightweight nav container hosting **only**
   163	  `AISettingsSection`'s provider list — call it `ReaderAIProvidersView`. It is NOT
   164	  `SettingsView`; it reuses the same `AIProviderListView` + `AIProviderEditSheet`
   165	  cells.
   166	- `BilingualSetupSheet.onOpenSettings` → presents `ReaderAIProvidersView` as a
   167	  push inside the bilingual sheet's own `NavigationStack` (so `‹ Bilingual` is a
   168	  real back, not a dismiss).
   169	- On `AIProviderEditSheet` Save when launched from this flow: set the saved
   170	  provider as the bilingual mode engine (`BilingualConfig.engineProviderID`) and
   171	  dismiss back to the bilingual sheet (pop to root).
   172	- `aiConfigured` on the engine strip is derived from
   173	  `AISettingsViewModel.providers.isEmpty == false`; the strip's CTA label is
   174	  `Set up` when empty, `Change…` otherwise (already shipped by #301).
   175	- The Library `SettingsView → AI provider` row is unchanged; it still opens the
   176	  full list. This adds a *second*, scoped entry — it does not move the first.
   177	
   178	## Cross-references
   179	
   180	| File | Role |
   181	|---|---|
   182	| `VReader AI Provider Entry Canvas.html` | Canvas of every state across themes. Source of truth. |
   183	| `vreader-ai-provider-entry.jsx` | `AIProvidersSheet`, `BilingualEngineStrip`, `EngineStripInline`, `NavFlowDiagram` — #1380 |
   184	| `vreader-ai-provider-fields.jsx` | `EditorSheet` (`AIProviderEditSheet`) — reused unchanged for the add/edit step (#1363) |
   185	| `vreader-bilingual.jsx` | `BilingualSetupSheet` — the surface whose "Set up" button this wires (#790) |
   186	| `design-notes/feature-60-followups.md` | Parent bilingual feature notes (#60 / #56) |
     1	# In-reader AI-enable + consent readiness affordance (#1394 · Feature #82)
     2	
     3	> Source of truth (design): `VReader AI Readiness Canvas.html` → `ai-readiness-artboards.jsx` + `vreader-ai-readiness.jsx` (+ a clickable happy-path `VReader AI Readiness Prototype.html`).
     4	> Chat transcript: `chats/chat17-ai-readiness-1394.md`.
     5	> Resolves needs-design [#1394](https://github.com/lllyys/vreader/issues/1394) (Feature **#82**). Follow-up to Feature #81 (#1380, in-reader provider entry) and Bug #301 (truthful engine strip).
     6	> Status: **design landed — implementation deferred** (recorded, not built; Swift held for a separate go-ahead per the handoff convention).
     7	
     8	## The gap
     9	
    10	`BilingualAIReadiness` requires **all four gates**: `FeatureFlags.aiAssistant` ON · explicit
    11	consent (`AIConsentManager.hasConsent`) · a provider profile · that profile's API key.
    12	Feature #81 lets a user **add a provider** in-reader — but on a fresh device the **flag and
    13	consent default OFF**, so adding a provider *alone* leaves readiness false and the bilingual
    14	engine strip correctly still shows **"Set up."** Today the only way to flip the flag + grant
    15	consent is a trip to Library → Settings → AI. This closes that loop **inside the reader**.
    16	
    17	This is the **capstone of the AI-gating cluster** — the surface every "AI unconfigured"
    18	silent-no-op should route to: Bug #301 (bilingual "Set up" routing), Bug #308 (bottom-bar AI
    19	button no-op), and the gate behind Bug #306 (cache) all resolve to *this* readiness flow.
    20	
    21	## Decision (binding) — Variant A: "Set up translation" readiness sheet
    22	
    23	Reached from the bilingual engine strip's **"Set up"**. One scoped sheet makes the whole
    24	`BilingualAIReadiness` legible and satisfiable top-to-bottom:
    25	
    26	1. **3-step tracker** — *Turn on AI · Allow data · Add provider* — doubles as the explainer
    27	   ("why am I still seeing Set up?") by showing exactly which gates remain. Each clears with a
    28	   check as it's satisfied.
    29	2. **Master AI toggle** (`aiAssistant` flag) — the first gate, satisfied in place.
    30	3. **Explicit full-disclosure consent card** — the two-column **"sent to provider / stays on
    31	   device"** ledger from #1068 (Variant C), tuned to translation. **Consent is NEVER
    32	   auto-granted** — it has its own toggle, and the card only **appears once AI is on** (matches
    33	   the #1068 gating logic).
    34	4. **Provider step** — reuses the canonical `AIProviderEditSheet` (#81/#1363) **unchanged**
    35	   (provider + key); on save it becomes the bilingual engine.
    36	5. **"Ready" payoff** — all four gates cleared → the engine strip flips to **"Claude ·
    37	   configured / Change…"**, ready to turn on bilingual. The user lands back where they started
    38	   with the blocker removed.
    39	
    40	Covered across **paper / sepia / dark / oled**, all four gate states, plus the reused editor.
    41	
    42	### Rejected alternatives (explored in the canvas)
    43	- **B · guided 1·2·3 stepper** — clear for a first-timer, but **order-forces every visit**: a
    44	  returning user who only lacks consent still walks the whole rail, and step 3 re-presents the
    45	  #81 editor mid-flow.
    46	- **C · pre-flight enable+consent gate** — demands both switches before the provider list is
    47	  reachable. One tidy consent moment, but it **front-loads privacy before the user has
    48	  committed** to anything, and re-gates returning users who already granted it.
    49	
    50	## Production wiring (deferred — do NOT build without go-ahead)
    51	
    52	- New `ReaderAIReadinessSheet` (or extend the #81 `ReaderAIProvidersView` into a readiness
    53	  container) presented from `BilingualSetupSheet.onOpenSettings` (currently the deferred slice
    54	  of Bug #301). It hosts: the tracker, the `aiAssistant` master toggle (`FeatureFlags`), the
    55	  consent card (`AIConsentManager.grantConsent` on its own toggle, shown only when AI on), and
    56	  the #81 provider list (`AIProviderEditSheet` reused).
    57	- On all-four-cleared: set the saved provider as the bilingual engine and pop back to Bilingual
    58	  with the strip reading "configured / Change…".
    59	- The same readiness sheet is the route target for **Bug #308** (bottom-bar AI button) and the
    60	  bilingual "Set up"/"Change…" (Feature #81). One surface, multiple entry points.
    61	- `aiConfigured`/readiness derives from `BilingualAIReadiness.resolve` (already mirrors the live
    62	  `AIService` gate per the #301 fix). Rule 51 satisfied (this note + canvas are the committed
    63	  design).

exec
/bin/zsh -lc "rg -n \"ReaderChromeScaffold\\(|EpubTopBand\\(|EpubReaderSheets\\(|rememberSaveable.*ReaderChromeStateSaver|ReaderChromeStateSaver\" android/app/src/main/kotlin/com/vreader/app/reader/{ReaderActivity.kt,TxtReaderActivity.kt,PdfReaderActivity.kt,Azw3ReaderActivity.kt,EpubReaderChrome.kt}
rg -n \"application as VReaderApp|container|readerSettingsStore|collectAsStateWithLifecycle|observe\\(\\)\" android/app/src/main/kotlin/com/vreader/app/reader/{ReaderActivity.kt,TxtReaderActivity.kt,PdfReaderActivity.kt,Azw3ReaderActivity.kt} | head -n 240
nl -ba android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt | sed -n '235,370p'
nl -ba android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt | sed -n '230,360p'
nl -ba android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt | sed -n '100,240p'
nl -ba android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt | sed -n '110,260p'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
android/app/src/main/kotlin/com/vreader/app/reader/EpubReaderChrome.kt:81:fun EpubTopBand(
android/app/src/main/kotlin/com/vreader/app/reader/EpubReaderChrome.kt:174:fun EpubReaderSheets(
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:76:import com.vreader.app.reader.chrome.ReaderChromeStateSaver
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:122:                    // process death via ReaderChromeStateSaver (keyed on the book).
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:124:                    val chromeState = rememberSaveable(bookKey, stateSaver = ReaderChromeStateSaver) {
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:459:        ReaderChromeScaffold(
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:19:// state is persisted across rotation via ReaderChromeStateSaver; the Notes snapshot is a one-shot read
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:49:import com.vreader.app.reader.chrome.ReaderChromeStateSaver
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:148:                        // rotation / process death via ReaderChromeStateSaver (keyed on the book).
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:150:                        val chromeState = rememberSaveable(bookKey, stateSaver = ReaderChromeStateSaver) {
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:640:                EpubReaderSheets(
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:670:                EpubTopBand(
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:126:import com.vreader.app.reader.chrome.ReaderChromeStateSaver
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:318:                        // sheet), persisted across rotation / process death via ReaderChromeStateSaver.
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:319:                        val chromeState = rememberSaveable(bookKey, stateSaver = ReaderChromeStateSaver) {
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:858:        ReaderChromeScaffold(
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:69:import androidx.lifecycle.compose.collectAsStateWithLifecycle
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:96:    private val container get() = (application as VReaderApp).container
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:110:        container.appScope.launch {
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:111:            for (locator in saveRequests) container.repository.savePosition(locator, System.currentTimeMillis())
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:127:                    val displayTheme by container.readerSettingsStore.settings
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:128:                        .collectAsStateWithLifecycle(initialValue = com.vreader.app.reader.settings.ReaderSettings())
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:133:                        value = runCatching { container.annotationsRepository.annotationsForBook(bookKey) }
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:138:                    val collectionNames by container.collectionRepository
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:140:                        .collectAsStateWithLifecycle(initialValue = emptyList())
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:149:                    val bookmarkRecords by container.annotationsRepository.bookmarks(bookKey)
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:150:                        .collectAsStateWithLifecycle(initialValue = emptyList())
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:162:                        value = c != null && runCatching { container.annotationsRepository.isBookmarked(bookKey, c) }.getOrDefault(false)
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:181:                                if (c != null) container.appScope.launch {
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:182:                                    runCatching { container.annotationsRepository.toggleBookmark(bookKey, title = null, locator = c) }
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:216:                                settings = container.readerSettingsStore.settings,
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:233:        val book = container.repository.findBook(key) ?: return OuterState.NoBook
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:236:        container.repository.markOpened(key, System.currentTimeMillis())
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:237:        return OuterState.Ready(book, path, container.repository.loadPosition(key))
android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:350:    val displaySettings by settings.collectAsStateWithLifecycle(initialValue = com.vreader.app.reader.settings.ReaderSettings())
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:44:import androidx.lifecycle.compose.collectAsStateWithLifecycle
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:70:    private val container get() = (application as VReaderApp).container
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:93:        container.appScope.launch {
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:101:                container.repository.savePosition(
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:115:            val settingsOrNull by container.readerSettingsStore.settings.collectAsStateWithLifecycle(initialValue = null)
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:140:                            onDispose { container.appScope.launch { s.document.close() } }
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:157:                            value = runCatching { container.annotationsRepository.annotationsForBook(bookKey) }
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:163:                        val collectionNames by container.collectionRepository
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:165:                            .collectAsStateWithLifecycle(initialValue = emptyList())
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:175:                            container.annotationsRepository.bookmarks(bookKey)
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:176:                        }.collectAsStateWithLifecycle(emptyList())
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:183:                            value = runCatching { container.annotationsRepository.isBookmarked(bookKey, liveCanonical) }.getOrDefault(false)
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:205:                                container.appScope.launch {
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:206:                                    runCatching { container.annotationsRepository.toggleBookmark(bookKey, title = null, locator = liveCanonical) }
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:257:        val book = container.repository.findBook(key) ?: return PdfUiState.Corrupt
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:261:                container.repository.markOpened(key, System.currentTimeMillis())
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:273:        val cached = container.cachedPage(key)
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:275:            val saved = container.repository.loadPosition(key) ?: return 0
android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt:283:        container.cachePage(book.fingerprintKey, page)
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:113:import androidx.lifecycle.compose.collectAsStateWithLifecycle
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:160:    private val container get() = (application as VReaderApp).container
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:185:        container.appScope.launch {
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:193:                container.repository.savePosition(
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:211:                val settingsOrNull by container.readerSettingsStore.settings
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:212:                    .collectAsStateWithLifecycle(initialValue = null)
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:238:                        val tts by ttsVm.state.collectAsStateWithLifecycle()
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:268:                        val tracker = container.readingTimeTracker
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:270:                        val sessionSeconds by tracker.sessionSeconds.collectAsStateWithLifecycle()
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:282:                            if (annotatable) container.annotationsRepository.highlights(bookKey) else flowOf(emptyList())
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:283:                        }.collectAsStateWithLifecycle(emptyList())
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:289:                        val popoverState by popoverVm.state.collectAsStateWithLifecycle()
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:295:                                    Lifecycle.Event.ON_RESUME -> container.appScope.launch { tracker.start(bookKey) }
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:298:                                    Lifecycle.Event.ON_STOP -> if (!isChangingConfigurations) container.appScope.launch { tracker.stop(bookKey) }
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:329:                            else runCatching { container.annotationsRepository.annotationsForBook(bookKey) }
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:336:                        val collectionNames by container.collectionRepository
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:338:                            .collectAsStateWithLifecycle(initialValue = emptyList())
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:352:                        val bookmarkRecords by remember(bookKey) { container.annotationsRepository.bookmarks(bookKey) }
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:353:                            .collectAsStateWithLifecycle(emptyList())
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:361:                            value = runCatching { container.annotationsRepository.isBookmarked(bookKey, liveCanonical) }.getOrDefault(false)
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:373:                            container.inBookSearchViewModel(
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:383:                        val inBookSearchState by inBookSearchVm.state.collectAsStateWithLifecycle()
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:398:                                container.appScope.launch {
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:399:                                    runCatching { container.annotationsRepository.toggleBookmark(bookKey, title = null, locator = liveCanonical) }
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:570:                            val store = container.readerSettingsStore
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:573:                                onTheme = { v -> val o = store.nextSeq(); container.appScope.launch { store.setTheme(v, o) } },
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:574:                                onFontFamily = { v -> val o = store.nextSeq(); container.appScope.launch { store.setFontFamily(v, o) } },
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:575:                                onFontSize = { v -> val o = store.nextSeq(); container.appScope.launch { store.setFontSize(v, o) } },
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:576:                                onLineSpacing = { v -> val o = store.nextSeq(); container.appScope.launch { store.setLineSpacing(v, o) } },
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:577:                                onMargin = { v -> val o = store.nextSeq(); container.appScope.launch { store.setMargin(v, o) } },
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:599:        val book = container.repository.findBook(key)
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:604:        container.repository.markOpened(key, System.currentTimeMillis())
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:613:        container.cachedOffset(key)?.let { return document.chunkForOffset(it) }
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:614:        val saved = container.repository.loadPosition(key) ?: return 0
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:627:        container.cacheOffset(book.fingerprintKey, offset)
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:710:            container.appScope.launch { container.annotationsRepository.updateHighlight(id, vm.state.value.activeColor, note) }
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:724:        container.appScope.launch { container.annotationsRepository.updateHighlight(id, color, note) }
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:730:        container.appScope.launch { container.annotationsRepository.removeHighlight(id) }
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:751:        container.appScope.launch {
android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt:752:            container.annotationsRepository.addHighlight(book.fingerprintKey, color, visible, locator, anchor, note)
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:53:import androidx.lifecycle.compose.collectAsStateWithLifecycle
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:103:    private val container get() = (application as VReaderApp).container
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:104:    private val repository: LibraryRepository get() = container.repository
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:107:    private val annotations: AnnotationsRepository get() = container.annotationsRepository
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:109:    private var containerId: Int = 0
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:180:            container.readerSettingsStore.settings.collect { chromeTheme.value = it.theme }
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:200:            val initialPrefs = EpubPreferences(scroll = true) + container.readerSettingsStore.current().toEpubPreferences()
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:220:                    add(containerId, EpubNavigatorFragment::class.java, Bundle(), READER_TAG)
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:255:        val vm = container.epubInBookSearchViewModel(
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:301:            container.collectionRepository.observeCollectionNamesForBook(current.fingerprintKey).collect { names ->
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:388:        container.appScope.launch {
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:398:        container.appScope.launch { annotations.updateHighlight(id, color, note) }
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:406:            container.appScope.launch { annotations.updateHighlight(id, popoverVm.state.value.activeColor, note) }
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:415:        container.appScope.launch { annotations.removeHighlight(id) }
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:452:        container.appScope.launch { persist(locator, current) }
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:484:            container.readerSettingsStore.settings.collect { settings ->
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:622:     *    1. the fragment container — MATCH_PARENT (the reading area fills the WHOLE screen, under the bands);
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:635:        containerId = frame.id
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:755:            val settings = container.readerSettingsStore.settings.collectAsStateWithLifecycle(initialValue = null).value
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:757:                val store = container.readerSettingsStore
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:760:                    onTheme = { v -> val o = store.nextSeq(); container.appScope.launch { store.setTheme(v, o) } },
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:761:                    onFontFamily = { v -> val o = store.nextSeq(); container.appScope.launch { store.setFontFamily(v, o) } },
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:762:                    onFontSize = { v -> val o = store.nextSeq(); container.appScope.launch { store.setFontSize(v, o) } },
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:763:                    onLineSpacing = { v -> val o = store.nextSeq(); container.appScope.launch { store.setLineSpacing(v, o) } },
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:764:                    onMargin = { v -> val o = store.nextSeq(); container.appScope.launch { store.setMargin(v, o) } },
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:781:        val screen by vm.state.collectAsStateWithLifecycle()
android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt:802:        val state by popoverVm.state.collectAsStateWithLifecycle()
   235	            bookmarkTocIndex = BookmarkTocIndex.build(chromeModel.value.tocEntries)
   236	            observeBookmarks(loaded)
   237	            observePosition(nav, loaded)
   238	            observeDisplaySettings(nav)
   239	            observeHighlights(loaded, controller)
   240	            observeAnnotationsSnapshot(loaded)
   241	            observeBookDetails(loaded)
   242	            controller.observeActivations { id, rect -> onHighlightTapped(id, rect) }
   243	            // feature #133 WI-11 — build the per-session in-book search VM over the LIVE publication (Readium
   244	            // SearchService) + observe its state for the top-bar Search-icon presence + the sheet.
   245	            buildInBookSearch(key, pub)
   246	        }
   247	    }
   248	
   249	    /** feature #133 WI-11 — construct the ONE per-session in-book search VM (over the live Readium
   250	     *  [publication], Readium's own SearchService — NOT the FTS index) and collect its state into
   251	     *  [inBookSearchState] so the top band knows whether to show the Search icon and the sheet layer can
   252	     *  render the sheet. The VM's collectors run on [lifecycleScope]; it is disposed in [onDestroy]
   253	     *  (`onCleared` → closeAllEpubCursors → no leaked Readium SearchIterator). */
   254	    private fun buildInBookSearch(bookKey: String, publication: Publication) {
   255	        val vm = container.epubInBookSearchViewModel(
   256	            bookKey = bookKey,
   257	            publication = publication,
   258	            coroutineScope = lifecycleScope,
   259	        )
   260	        inBookSearchVm = vm
   261	        inBookSearchVmBuildCount += 1
   262	        lifecycleScope.launch { vm.state.collect { inBookSearchState.value = it } }
   263	    }
   264	
   265	    /** feature #132 WI-7-EPUB — populate the persistent chrome model after open: title + flattened TOC
   266	     *  (ReadiumTocProvider) + the Notes snapshot + the initial currentTocIndex. Failures are tolerated (a
   267	     *  book with no/broken TOC still renders the chrome with an empty Contents control). */
   268	    private suspend fun populateChromeModel(pub: Publication, current: Book, nav: EpubNavigatorFragment) {
   269	        val entries = runCatching { ReadiumTocProvider(pub, current).toc() }.getOrDefault(emptyList())
   270	        val snapshot = runCatching { annotations.annotationsForBook(current.fingerprintKey) }
   271	            .getOrDefault(AnnotationsSnapshot(emptyList(), emptyList()))
   272	        val locator = nav.currentLocator.value
   273	        val index = tocIndexFor(locator.href.toString(), locator.locations.progression, tocPositions(entries))
   274	        chromeModel.value = chromeModel.value.copy(
   275	            title = current.title,
   276	            tocEntries = entries,
   277	            annotations = snapshot,
   278	            currentTocIndex = index,
   279	        )
   280	    }
   281	
   282	    /** feature #132 WI-7-EPUB — reload the Notes snapshot whenever this book's stored highlights change (a
   283	     *  fresh highlight/edit/remove), so a newly added annotation appears in the review sheet without a
   284	     *  reopen. Notes are review-only for EPUB (no jump-to-annotation) until #135. */
   285	    private fun observeAnnotationsSnapshot(current: Book) {
   286	        lifecycleScope.launch {
   287	            annotations.highlights(current.fingerprintKey).collect {
   288	                val snapshot = runCatching { annotations.annotationsForBook(current.fingerprintKey) }
   289	                    .getOrDefault(AnnotationsSnapshot(emptyList(), emptyList()))
   290	                chromeModel.value = chromeModel.value.copy(annotations = snapshot)
   291	            }
   292	        }
   293	    }
   294	
   295	    /** feature #134 WI-5 — build + keep the More menu's Book-details model in sync with this book's live
   296	     *  collection names (EPUB supplies no page count → the Pages row is omitted). The mapped model appears
   297	     *  on the [chromeBookDetails] state the top band/sheet layer read, so the More button appears once the
   298	     *  book + its collections are known (null until then — no dead control). */
   299	    private fun observeBookDetails(current: Book) {
   300	        lifecycleScope.launch {
   301	            container.collectionRepository.observeCollectionNamesForBook(current.fingerprintKey).collect { names ->
   302	                chromeBookDetails.value =
   303	                    com.vreader.app.reader.details.BookDetailsMapper.map(current, names, pageCount = null)
   304	            }
   305	        }
   306	    }
   307	
   308	    /** feature #134 WI-5 — copy the FULL canonical fingerprint to the OS clipboard (the Book Details
   309	     *  copy-fingerprint mini-action). Rely on the OS copy confirmation — no invented toast (rule 51). */
   310	    private fun copyFingerprint(fingerprintFull: String) {
   311	        val clip = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
   312	        clip.setPrimaryClip(ClipData.newPlainText("fingerprint", fingerprintFull))
   313	    }
   314	
   315	    /** feature #134 WI-5 — the More menu's Share book action: launch the WI-2 book-file share chooser for
   316	     *  the current book (a missing/out-of-scope file or no receiver is a silent no-op — WI-2 handles it). */
   317	    private fun shareBookFile() {
   318	        val current = book ?: return
   319	        com.vreader.app.reader.share.shareBook(this, current)
   320	    }
   321	
   322	    /** A tap on an existing highlight decoration → open the popover in EDIT mode (Note/Copy/Share/Remove). */
   323	    private fun onHighlightTapped(id: String, rect: android.graphics.RectF?) {
   324	        lifecycleScope.launch {
   325	            val h = annotations.findHighlight(id) ?: return@launch
   326	            pendingHighlightId = id
   327	            pendingSelectedText = h.selectedText
   328	            pendingSelection = null
   329	            val d = resources.displayMetrics.density
   330	            popoverVm.showForExisting(h.color, h.note, (rect?.centerX() ?: 0f) / d, (rect?.bottom ?: 0f) / d)
   331	        }
   332	    }
   333	
   334	    /** Re-apply the book's stored highlights as Readium decorations whenever the set changes. */
   335	    private fun observeHighlights(current: Book, controller: ReaderHighlightController) {
   336	        lifecycleScope.launch {
   337	            annotations.highlights(current.fingerprintKey).collect { highlights ->
   338	                runCatching { controller.applyHighlights(highlights) }
   339	                    .onSuccess { built -> appliedHighlightCount = built }   // decorations actually built/applied
   340	            }
   341	        }
   342	    }
   343	
   344	    @Volatile private var appliedHighlightCount: Int = -1
   345	
   346	    /** Test hook: the count of highlights applied as decorations on the live navigator (-1 until the
   347	     *  first apply). Proves the reopen-render path ran against the real EpubNavigatorFragment. */
   348	    @androidx.annotation.VisibleForTesting
   349	    fun appliedHighlightCount(): Int = appliedHighlightCount
   350	
   351	    /** The selection action-mode callback. We KEEP the action mode alive (return true) with an emptied
   352	     *  menu so the WebView selection survives the suspend `currentSelection()` read, capture the
   353	     *  selection (text + rect) → show the floating popover, then `finish()` to drop the (empty) system
   354	     *  bar. Reading the selection while the mode is still alive avoids the "cancellation clears the
   355	     *  selection" race of a bare `return false`. The empty bar is transient (gone the same tick the
   356	     *  suspend read resolves), not persistent undesigned chrome. */
   357	    private fun selectionCallback(): ActionMode.Callback = object : ActionMode.Callback {
   358	        override fun onCreateActionMode(mode: ActionMode?, menu: Menu?): Boolean {
   359	            menu?.clear()
   360	            lifecycleScope.launch {
   361	                val nav = navigator ?: run { mode?.finish(); return@launch }
   362	                val selection = nav.currentSelection()
   363	                if (selection == null || selection.locator.text.highlight.isNullOrBlank()) {
   364	                    mode?.finish(); return@launch
   365	                }
   366	                pendingSelection = selection.locator
   367	                pendingHighlightId = null       // entering CREATE context — drop any stale EDIT context
   368	                pendingSelectedText = null
   369	                val rect = selection.rect
   370	                val density = resources.displayMetrics.density
   230	                                .collect { savePosition(s.book, s.document, it) }
   231	                        }
   232	                        // feature #121 — read-aloud. The VM drives the designed control bar; the spoken
   233	                        // sentence is washed + auto-scrolled (TXT). Chunking is LAZY + off-main (only
   234	                        // on Read aloud) so a large book never scans the whole text on composition.
   235	                        val ttsVm: TtsViewModel = viewModel(factory = viewModelFactory {
   236	                            initializer { TtsViewModel(AndroidTtsEngine(applicationContext)) }
   237	                        })
   238	                        val tts by ttsVm.state.collectAsStateWithLifecycle()
   239	                        val ttsScope = rememberCoroutineScope()
   240	                        LaunchedEffect(ttsVm) { ttsVm.intents.collect { launchTtsIntent(it) } }
   241	                        // pause read-aloud when the reader is backgrounded (no MediaSession by design —
   242	                        // plan §OOS); the engine is shut down on Activity finish via the VM's onCleared.
   243	                        val lifecycleOwner = LocalLifecycleOwner.current
   244	                        DisposableEffect(lifecycleOwner) {
   245	                            // guard against ON_STOP firing on a rotation (config change) — the VM is
   246	                            // retained across rotation, so don't pause when we're just reconfiguring.
   247	                            val obs = LifecycleEventObserver { _, e -> if (e == Lifecycle.Event.ON_STOP && !isChangingConfigurations) ttsVm.pause() }
   248	                            lifecycleOwner.lifecycle.addObserver(obs)
   249	                            onDispose { lifecycleOwner.lifecycle.removeObserver(obs) }
   250	                        }
   251	                        val active = tts.phase != TtsPhase.idle
   252	                        val spokenChunk = if (tts.phase == TtsPhase.speaking) s.document.chunkForOffset(tts.charStart) else -1
   253	                        // auto-scroll ONLY when the spoken chunk is off-screen — so a small manual scroll
   254	                        // while listening isn't fought on every sentence.
   255	                        LaunchedEffect(spokenChunk) {
   256	                            if (spokenChunk >= 0 && listState.layoutInfo.visibleItemsInfo.none { it.index == spokenChunk }) {
   257	                                runCatching { listState.animateScrollToItem(spokenChunk) }
   258	                            }
   259	                        }
   260	                        var showSpeed by remember { mutableStateOf(false) }
   261	                        var showVoice by remember { mutableStateOf(false) }
   262	                        var starting by remember { mutableStateOf(false) }   // guards double-tap → double-chunk
   263	                        // snapshot the voice options once when the sheet opens (not every recomposition).
   264	                        val voiceList = remember(showVoice) { if (showVoice) ttsVm.voiceListState() else com.vreader.app.tts.TtsVoiceListState() }
   265	
   266	                        // feature #122 — reading-stats: track this session (the process-singleton tracker
   267	                        // survives rotation) + show the auto-fading session pill.
   268	                        val tracker = container.readingTimeTracker
   269	                        val bookKey = s.book.fingerprintKey
   270	                        val sessionSeconds by tracker.sessionSeconds.collectAsStateWithLifecycle()
   271	
   272	                        // feature #124/#125 — stored highlights → per-chunk washes. Enabled for TXT AND MD
   273	                        // (#125 added the MarkdownChunkTextMapper source-offset map, so MD is no longer
   274	                        // render-only). The mapper is the single rendered↔source bridge + render owner,
   275	                        // shared by the wash, the selection controller, and the body.
   276	                        val annotatable = s.book.originalFormat == BookFormat.txt || s.book.originalFormat == BookFormat.md
   277	                        val chunkMapper = remember(s.document, s.book.originalFormat) {
   278	                            if (s.book.originalFormat == BookFormat.md) MarkdownChunkTextMapper(s.document)
   279	                            else IdentityChunkTextMapper(s.document)
   280	                        }
   281	                        val highlightsList by remember(bookKey, annotatable) {
   282	                            if (annotatable) container.annotationsRepository.highlights(bookKey) else flowOf(emptyList())
   283	                        }.collectAsStateWithLifecycle(emptyList())
   284	                        val washMap = remember(highlightsList, s.document, chunkMapper) { TxtWashMapper.washesByChunk(s.document, highlightsList, chunkMapper) }
   285	
   286	                        // feature #124/#125 — custom selection + popover (TXT + MD).
   287	                        val selectionController = remember(s.document, chunkMapper) { if (annotatable) TxtSelectionController(s.document, chunkMapper) else null }
   288	                        val popoverVm = remember(bookKey) { com.vreader.app.annotations.SelectionPopoverViewModel() }
   289	                        val popoverState by popoverVm.state.collectAsStateWithLifecycle()
   290	                        DisposableEffect(lifecycleOwner, bookKey) {
   291	                            val obs = LifecycleEventObserver { _, e ->
   292	                                when (e) {
   293	                                    // start/stop on the PROCESS scope (not the composition-scoped ttsScope) so the
   294	                                    // durable bank in stop()/flush() can't be cancelled by the reader's teardown.
   295	                                    Lifecycle.Event.ON_RESUME -> container.appScope.launch { tracker.start(bookKey) }
   296	                                    // don't end the session on a rotation (config change) — only a real background.
   297	                                    // keyed stop: a no-op unless THIS book is the active session (stale-Activity safe).
   298	                                    Lifecycle.Event.ON_STOP -> if (!isChangingConfigurations) container.appScope.launch { tracker.stop(bookKey) }
   299	                                    else -> Unit
   300	                                }
   301	                            }
   302	                            // addObserver replays lifecycle events up to the current state — so a Loaded
   303	                            // composition that arrives AFTER ON_RESUME still receives ON_RESUME here and the
   304	                            // initial open is tracked (no missed first session).
   305	                            lifecycleOwner.lifecycle.addObserver(obs)
   306	                            onDispose { lifecycleOwner.lifecycle.removeObserver(obs) }
   307	                        }
   308	                        // live pill + periodic bank — gated to RESUMED so neither loop wakes while backgrounded.
   309	                        LaunchedEffect(Unit) { lifecycleOwner.repeatOnLifecycle(Lifecycle.State.RESUMED) { while (true) { delay(1_000); tracker.tickSessionSeconds() } } }
   310	                        LaunchedEffect(Unit) { lifecycleOwner.repeatOnLifecycle(Lifecycle.State.RESUMED) { while (true) { delay(60_000); tracker.flush() } } }
   311	                        var pillVisible by remember { mutableStateOf(true) }
   312	                        LaunchedEffect(Unit) { delay(5_000); pillVisible = false }                             // auto-fade
   313	
   314	                        // feature #129 WI-4 — the Display sheet, opened from the chrome's Aa slot.
   315	                        var showDisplaySheet by remember { mutableStateOf(false) }
   316	
   317	                        // feature #132 WI-6 — the shared reader-chrome state (top/bottom visibility + open
   318	                        // sheet), persisted across rotation / process death via ReaderChromeStateSaver.
   319	                        val chromeState = rememberSaveable(bookKey, stateSaver = ReaderChromeStateSaver) {
   320	                            mutableStateOf(ReaderChromeState())
   321	                        }
   322	                        // The Notes review sheet's one-shot snapshot. Reloads whenever this book's stored
   323	                        // highlights change (a fresh highlight/edit/remove OR a #124/#125 wash) so a newly
   324	                        // added annotation appears in the sheet without reopening the reader.
   325	                        val annotationsSnapshot by produceState(
   326	                            AnnotationsSnapshot(emptyList(), emptyList()), bookKey, annotatable, highlightsList,
   327	                        ) {
   328	                            value = if (!annotatable) AnnotationsSnapshot(emptyList(), emptyList())
   329	                            else runCatching { container.annotationsRepository.annotationsForBook(bookKey) }
   330	                                .getOrDefault(AnnotationsSnapshot(emptyList(), emptyList()))
   331	                        }
   332	
   333	                        // feature #134 WI-5 — the More menu's Book-details model (mapped from the loaded
   334	                        // book + its live collection names via BookDetailsMapper). TXT/MD supplies no page
   335	                        // count (pageCount=null). Rebuilds when the book's collection membership changes.
   336	                        val collectionNames by container.collectionRepository
   337	                            .observeCollectionNamesForBook(bookKey)
   338	                            .collectAsStateWithLifecycle(initialValue = emptyList())
   339	                        val bookDetails = remember(s.book, collectionNames) {
   340	                            com.vreader.app.reader.details.BookDetailsMapper.map(s.book, collectionNames, pageCount = null)
   341	                        }
   342	
   343	                        // feature #135 WI-7 — the bookmark wiring. TXT/MD has no TOC (null tocIndex → the WI-4
   344	                        // projection degrades chapter/page to null) but DOES supply a preview provider (a bounded
   345	                        // snippet around the stored char offset — the host owns the decoded text). The current
   346	                        // position is the top-visible chunk's char offset → a plain canonical Locator.
   347	                        val previewProvider = remember(s.document) { txtBookmarkPreviewProvider(s.document) }
   348	                        val dateRenderer = remember { bookmarkDateRenderer() }
   349	                        val currentCanonical = remember(s.book) {
   350	                            { off: Int -> txtBookmarkLocator(s.book, off) }
   351	                        }
   352	                        val bookmarkRecords by remember(bookKey) { container.annotationsRepository.bookmarks(bookKey) }
   353	                            .collectAsStateWithLifecycle(emptyList())
   354	                        val bookmarkRows = remember(bookmarkRecords, s.book) {
   355	                            bookmarkRowItems(bookmarkRecords, s.book.originalFormat, tocIndex = null, previewProvider = previewProvider, dateRenderer = dateRenderer)
   356	                        }
   357	                        // The live top-visible offset → canonical (recomputed on scroll; the toggle/presence read it).
   358	                        val liveOffset = s.document.offsetForChunk(listState.firstVisibleItemIndex)
   359	                        val liveCanonical = remember(s.book, liveOffset) { txtBookmarkLocator(s.book, liveOffset) }
   360	                        val isBookmarked by produceState(false, liveCanonical, bookmarkRecords) {
   100	                )
   101	                container.repository.savePosition(
   102	                    vreader.contracts.VReaderLocator.wrapLegacy(locator),
   103	                    System.currentTimeMillis(),
   104	                )
   105	            }
   106	        }
   107	
   108	        setContent {
   109	            val state by produceState<PdfUiState>(PdfUiState.Loading, key) {
   110	                value = withContext(Dispatchers.IO) { load(key) }
   111	            }
   112	            // feature #129 WI-7 — the live Display settings; PDF reads ONLY the theme background. NULL
   113	            // until the DataStore's first emission — the composition is GATED on it (like the reflowable
   114	            // readers) so a user with a stored dark theme never sees a wrong bright frame on open/rotation.
   115	            val settingsOrNull by container.readerSettingsStore.settings.collectAsStateWithLifecycle(initialValue = null)
   116	            val settings = settingsOrNull
   117	            if (settings == null) {
   118	                // Pre-emission: nothing painted (an empty full-screen surface), the test hook stays null.
   119	                Box(Modifier.fillMaxSize())
   120	            } else {
   121	                val backdrop = settings.pdfBackdrop()
   122	                SideEffect { appliedBackdropArgb = backdrop.toArgb() }
   123	                when (val s = state) {
   124	                    is PdfUiState.Loading -> PdfScaffold("", ::finish, backdrop) { CenterMessage("Opening…") }
   125	                    is PdfUiState.Protected -> PdfScaffold("", ::finish, backdrop) {
   126	                        CenterMessage("This PDF is protected", "It's password-protected or uses a security scheme this reader can't open.")
   127	                    }
   128	                    is PdfUiState.Corrupt -> PdfScaffold("", ::finish, backdrop) {
   129	                        CenterMessage("Couldn’t open this PDF", "The file appears to be damaged or uses a format the reader can’t decode.")
   130	                    }
   131	                    is PdfUiState.Empty -> PdfScaffold("", ::finish, backdrop) {
   132	                        CenterMessage("This PDF has no pages", null)
   133	                    }
   134	                    is PdfUiState.Loaded -> {
   135	                        val listState = rememberLazyListState(initialFirstVisibleItemIndex = s.initialPage)
   136	                        // Close the renderer when the reader leaves composition — launched on the
   137	                        // process scope (NOT runBlocking on main: close() awaits the doc mutex behind
   138	                        // any in-flight render, which could ANR the teardown/rotation frame).
   139	                        DisposableEffect(s.document) {
   140	                            onDispose { container.appScope.launch { s.document.close() } }
   141	                        }
   142	                        SideEffect { flushPosition = { savePage(s.book, listState.firstVisibleItemIndex) } }
   143	                        LaunchedEffect(listState) {
   144	                            snapshotFlow { listState.firstVisibleItemIndex }
   145	                                .drop(1).debounce(800).collect { savePage(s.book, it) }
   146	                        }
   147	                        // feature #132 WI-7-hosts — the shared reader chrome. State persists across
   148	                        // rotation / process death via ReaderChromeStateSaver (keyed on the book).
   149	                        val bookKey = s.book.fingerprintKey
   150	                        val chromeState = rememberSaveable(bookKey, stateSaver = ReaderChromeStateSaver) {
   151	                            mutableStateOf(ReaderChromeState())
   152	                        }
   153	                        // The Notes review sheet's one-shot snapshot of this book's highlights + notes.
   154	                        val annotationsSnapshot by produceState(
   155	                            AnnotationsSnapshot(emptyList(), emptyList()), bookKey,
   156	                        ) {
   157	                            value = runCatching { container.annotationsRepository.annotationsForBook(bookKey) }
   158	                                .getOrDefault(AnnotationsSnapshot(emptyList(), emptyList()))
   159	                        }
   160	                        val jumpScope = rememberCoroutineScope()
   161	                        // feature #134 WI-5 — the More menu's Book-details model (mapped from the book + its
   162	                        // live collection names + the real PDF page count → the Pages row).
   163	                        val collectionNames by container.collectionRepository
   164	                            .observeCollectionNamesForBook(bookKey)
   165	                            .collectAsStateWithLifecycle(initialValue = emptyList())
   166	                        val bookDetails = androidx.compose.runtime.remember(s.book, collectionNames, s.document.pageCount) {
   167	                            com.vreader.app.reader.details.BookDetailsMapper.map(s.book, collectionNames, pageCount = s.document.pageCount)
   168	                        }
   169	
   170	                        // feature #135 WI-7 — the bookmark wiring. PDF has no TOC or preview (null tocIndex +
   171	                        // null provider → the WI-4 projection shows just "p. N"). The current position is the
   172	                        // top-visible page → a plain canonical Locator; the jump scrolls to the page.
   173	                        val dateRenderer = androidx.compose.runtime.remember { bookmarkDateRenderer() }
   174	                        val bookmarkRecords by androidx.compose.runtime.remember(bookKey) {
   175	                            container.annotationsRepository.bookmarks(bookKey)
   176	                        }.collectAsStateWithLifecycle(emptyList())
   177	                        val bookmarkRows = androidx.compose.runtime.remember(bookmarkRecords, s.book) {
   178	                            bookmarkRowItems(bookmarkRecords, s.book.originalFormat, tocIndex = null, previewProvider = null, dateRenderer = dateRenderer)
   179	                        }
   180	                        val livePage = listState.firstVisibleItemIndex
   181	                        val liveCanonical = androidx.compose.runtime.remember(s.book, livePage) { pdfBookmarkLocator(s.book, livePage) }
   182	                        val isBookmarked by produceState(false, liveCanonical, bookmarkRecords) {
   183	                            value = runCatching { container.annotationsRepository.isBookmarked(bookKey, liveCanonical) }.getOrDefault(false)
   184	                        }
   185	
   186	                        PdfReaderChrome(
   187	                            theme = settings.theme,
   188	                            title = s.title,
   189	                            chromeState = chromeState,
   190	                            annotations = annotationsSnapshot,
   191	                            onBack = ::finish,
   192	                            // PDF tap-to-jump: scroll the page list to the annotation's clamped page —
   193	                            // the existing resume/save page-scroll seam (listState.firstVisibleItemIndex).
   194	                            onJumpToAnnotation = { item ->
   195	                                jumpScope.launch { listState.scrollToItem(pdfAnnotationPage(item, s.document.pageCount)) }
   196	                            },
   197	                            onShareAnnotations = { shareAnnotations(annotationsSnapshot) },
   198	                            body = { PdfReaderBody(s.document, listState, backdrop) },
   199	                            bookDetails = bookDetails,
   200	                            onShareBook = { com.vreader.app.reader.share.shareBook(this@PdfReaderActivity, s.book) },
   201	                            onCopyFingerprint = { copyFingerprint(it) },
   202	                            // feature #135 WI-7 — the top-bar bookmark toggle + Bookmarks-tab rows + PDF jump.
   203	                            isCurrentBookmarked = isBookmarked,
   204	                            onToggleBookmark = {
   205	                                container.appScope.launch {
   206	                                    runCatching { container.annotationsRepository.toggleBookmark(bookKey, title = null, locator = liveCanonical) }
   207	                                }
   208	                            },
   209	                            currentLocator = liveCanonical,
   210	                            bookmarks = bookmarkRows,
   211	                            // PDF jump: scroll to the bookmark's page; out-of-range → Failed (sheet stays open).
   212	                            onJumpBookmark = { record ->
   213	                                val target = pdfBookmarkPageTarget(record.locator.page, s.document.pageCount)
   214	                                if (target == null) {
   215	                                    JumpResult.Failed
   216	                                } else {
   217	                                    jumpScope.launch { listState.scrollToItem(target) }
   218	                                    JumpResult.Succeeded
   219	                                }
   220	                            },
   221	                        )
   222	                    }
   223	                }
   224	            }
   225	        }
   226	    }
   227	
   228	    override fun onStop() {
   229	        super.onStop()
   230	        flushPosition?.invoke()
   231	    }
   232	
   233	    override fun onDestroy() {
   234	        super.onDestroy()
   235	        saveRequests.close()
   236	    }
   237	
   238	    /** feature #134 WI-5 — copy the FULL canonical fingerprint to the OS clipboard (the Book Details
   239	     *  copy-fingerprint mini-action). Rely on the OS copy confirmation — no invented toast (rule 51). */
   240	    private fun copyFingerprint(fingerprintFull: String) {
   110	        container.appScope.launch {
   111	            for (locator in saveRequests) container.repository.savePosition(locator, System.currentTimeMillis())
   112	        }
   113	
   114	        setContent {
   115	            val outer by produceState<OuterState>(OuterState.Loading, key) { value = loadOuter(key) }
   116	            when (val o = outer) {
   117	                OuterState.Loading -> ReaderScaffold("", ::finish) { Centered { CircularProgressIndicator() } }
   118	                OuterState.NoBook -> ReaderScaffold("", ::finish) { Centered { Text("This book can’t be opened.", color = Ink) } }
   119	                is OuterState.Ready -> {
   120	                    currentBook = o.book
   121	                    // feature #132 WI-7-hosts — the shared reader chrome. State persists across rotation /
   122	                    // process death via ReaderChromeStateSaver (keyed on the book).
   123	                    val bookKey = o.book.fingerprintKey
   124	                    val chromeState = rememberSaveable(bookKey, stateSaver = ReaderChromeStateSaver) {
   125	                        mutableStateOf(ReaderChromeState())
   126	                    }
   127	                    val displayTheme by container.readerSettingsStore.settings
   128	                        .collectAsStateWithLifecycle(initialValue = com.vreader.app.reader.settings.ReaderSettings())
   129	                    // The Notes review sheet's one-shot snapshot of this book's highlights + notes.
   130	                    val annotationsSnapshot by produceState(
   131	                        AnnotationsSnapshot(emptyList(), emptyList()), bookKey,
   132	                    ) {
   133	                        value = runCatching { container.annotationsRepository.annotationsForBook(bookKey) }
   134	                            .getOrDefault(AnnotationsSnapshot(emptyList(), emptyList()))
   135	                    }
   136	                    // feature #134 WI-5 — the More menu's Book-details model (mapped from the book + its
   137	                    // live collection names). AZW3 supplies no page count (pageCount=null).
   138	                    val collectionNames by container.collectionRepository
   139	                        .observeCollectionNamesForBook(bookKey)
   140	                        .collectAsStateWithLifecycle(initialValue = emptyList())
   141	                    val bookDetails = remember(o.book, collectionNames) {
   142	                        com.vreader.app.reader.details.BookDetailsMapper.map(o.book, collectionNames, pageCount = null)
   143	                    }
   144	
   145	                    // feature #135 WI-7 — the bookmark wiring. AZW3 has no reader TOC, so the row projection
   146	                    // has no chapter/page (the WI-4 EPUB/AZW3 branch degrades to null fields — no crash) — a
   147	                    // null tocIndex. The current position comes from the relocate-derived canonical Locator;
   148	                    // the jump uses Azw3Document.goTo (CFI-first→fraction, render-death carry-across).
   149	                    val bookmarkRecords by container.annotationsRepository.bookmarks(bookKey)
   150	                        .collectAsStateWithLifecycle(initialValue = emptyList())
   151	                    val dateRenderer = remember { bookmarkDateRenderer() }
   152	                    val bookmarkRows = remember(bookmarkRecords) {
   153	                        bookmarkRowItems(bookmarkRecords, BookFormat.azw3, tocIndex = null, previewProvider = null, dateRenderer = dateRenderer)
   154	                    }
   155	                    // The live position + the document to jump into, hoisted from the body so the chrome-level
   156	                    // toggle/jump can reach them. currentCanonical is null until foliate's first relocate.
   157	                    var currentCanonical by remember { mutableStateOf<Locator?>(null) }
   158	                    var liveDocument by remember { mutableStateOf<Azw3Document?>(null) }
   159	                    // Presence — refreshed on every relocate AND right after a toggle.
   160	                    val isBookmarked by produceState(false, currentCanonical, bookmarkRecords) {
   161	                        val c = currentCanonical
   162	                        value = c != null && runCatching { container.annotationsRepository.isBookmarked(bookKey, c) }.getOrDefault(false)
   163	                    }
   164	                    val jumpScope = rememberCoroutineScope()
   165	
   166	                    Azw3ReaderChrome(
   167	                        theme = displayTheme.theme,
   168	                        title = o.book.title,
   169	                        chromeState = chromeState,
   170	                        annotations = annotationsSnapshot,
   171	                        onBack = ::finish,
   172	                        onShareAnnotations = { shareAnnotations(annotationsSnapshot) },
   173	                        bookDetails = bookDetails,
   174	                        onShareBook = { com.vreader.app.reader.share.shareBook(this@Azw3ReaderActivity, o.book) },
   175	                        onCopyFingerprint = { copyFingerprint(it) },
   176	                        // feature #135 WI-7 — the top-bar bookmark toggle + Bookmarks-tab rows + AZW3 jump.
   177	                        isCurrentBookmarked = isBookmarked,
   178	                        onToggleBookmark = if (currentCanonical != null) {
   179	                            {
   180	                                val c = currentCanonical
   181	                                if (c != null) container.appScope.launch {
   182	                                    runCatching { container.annotationsRepository.toggleBookmark(bookKey, title = null, locator = c) }
   183	                                }
   184	                            }
   185	                        } else null,
   186	                        currentLocator = currentCanonical,
   187	                        bookmarks = bookmarkRows,
   188	                        onJumpBookmark = { record ->
   189	                            val doc = liveDocument
   190	                            // Decide the sheet's dismiss SYNCHRONOUSLY from target validity: an unjumpable
   191	                            // bookmark (no cfi + no finite progression) → Failed (sheet stays open, no
   192	                            // invented error surface — rule 51); a jumpable one → Succeeded (dismiss). The
   193	                            // ACTUAL landing is the awaited Azw3Document.goTo (CFI-first→fraction) launched
   194	                            // off the jump scope — it blocks ~3s on the bundle relocate ack, so it CANNOT run
   195	                            // on the tap thread (that would ANR). render-death mid-jump is carried across by
   196	                            // the host's recreate path (takePendingGoTo → run(pendingGoTo=)); goTo re-lands once.
   197	                            val decision = azw3JumpDecision(doc, record.locator)
   198	                            if (decision == JumpResult.Succeeded && doc != null) {
   199	                                jumpScope.launch {
   200	                                    // The awaited landing (mapped for symmetry with the plan's Succeeded/
   201	                                    // Timeout/Failed contract); a landed jump relocates → presence refreshes.
   202	                                    val landed = runCatching { doc.goTo(record.locator) }
   203	                                        .getOrDefault(Azw3GoToResult.Failed)
   204	                                    if (azw3JumpResult(landed) == JumpResult.Succeeded && currentCanonical != null) {
   205	                                        currentCanonical = record.locator // reflect the reached position promptly
   206	                                    }
   207	                                }
   208	                            }
   209	                            decision
   210	                        },
   211	                        body = {
   212	                            Azw3ReaderHost(
   213	                                book = o.book,
   214	                                bookFile = File(o.path),
   215	                                restore = o.restore,
   216	                                settings = container.readerSettingsStore.settings,
   217	                                onRelocate = { rel ->
   218	                                    enqueueSave(o.book, rel)
   219	                                    currentCanonical = Azw3LocatorBridge
   220	                                        .toEnvelope(rel, o.book.contentSHA256, o.book.fileByteCount)
   221	                                        .legacyLocator?.copy(format = BookFormat.azw3.name)?.validatedOrNull()
   222	                                },
   223	                                onDocument = { doc -> liveDocument = doc },
   224	                            )
   225	                        },
   226	                    )
   227	                }
   228	            }
   229	        }
   230	    }
   231	
   232	    private suspend fun loadOuter(key: String): OuterState {
   233	        val book = container.repository.findBook(key) ?: return OuterState.NoBook
   234	        val path = book.localFilePath ?: return OuterState.NoBook
   235	        if (!File(path).isFile) return OuterState.NoBook
   236	        container.repository.markOpened(key, System.currentTimeMillis())
   237	        return OuterState.Ready(book, path, container.repository.loadPosition(key))
   238	    }
   239	
   240	    private fun enqueueSave(book: Book, relocate: FoliateMessage.Relocate) {
   241	        currentBook = book
   242	        latestRelocate = relocate
   243	        saveRequests.trySend(Azw3LocatorBridge.toEnvelope(relocate, book.contentSHA256, book.fileByteCount))
   244	    }
   245	
   246	    override fun onStop() {
   247	        super.onStop()
   248	        val book = currentBook
   249	        val relocate = latestRelocate
   250	        if (book != null && relocate != null) {
   251	            saveRequests.trySend(Azw3LocatorBridge.toEnvelope(relocate, book.contentSHA256, book.fileByteCount))
   252	        }
   253	    }
   254	
   255	    override fun onDestroy() {
   256	        super.onDestroy()
   257	        saveRequests.close()
   258	    }
   259	
   260	    /** feature #134 WI-5 — copy the FULL canonical fingerprint to the OS clipboard (the Book Details

exec
/bin/zsh -lc "rg --files android/app/src/androidTest android/app/src/test | rg 'Ai|ReaderChromeStateSaver|ReaderMoreRows|MorePopup'
rg -n \"class AiRoundTripConnectedTest|AiRoundTrip\" android/app/src
nl -ba dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx | sed -n '1,280p'
nl -ba dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-android.jsx | sed -n '1,115p'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
android/app/src/test/kotlin/com/vreader/app/ai/AiChatViewModelTest.kt
android/app/src/test/kotlin/com/vreader/app/ai/AiFakeServer.kt
android/app/src/test/kotlin/com/vreader/app/ai/AiSettingsViewModelTest.kt
android/app/src/test/kotlin/com/vreader/app/ai/OpenAiCompatibleProviderTest.kt
android/app/src/test/kotlin/com/vreader/app/ai/AiProviderStoreTest.kt
android/app/src/test/kotlin/com/vreader/app/ai/AiMarkdownRendererTest.kt
android/app/src/test/kotlin/com/vreader/app/ai/AiProviderKindTest.kt
android/app/src/androidTest/kotlin/com/vreader/app/ai/AiRoundTripConnectedTest.kt
android/app/src/androidTest/kotlin/com/vreader/app/ai/AiProviderEditSheetTest.kt
android/app/src/androidTest/kotlin/com/vreader/app/ai/AiProviderListScreenTest.kt
android/app/src/androidTest/kotlin/com/vreader/app/ai/AiChatPanelTest.kt
android/app/src/test/kotlin/com/vreader/app/reader/chrome/ReaderMoreRowsTest.kt
android/app/src/test/kotlin/com/vreader/app/reader/chrome/ReaderChromeStateSaverTest.kt
android/app/src/androidTest/kotlin/com/vreader/app/reader/more/MorePopupTest.kt
android/app/src/androidTest/kotlin/com/vreader/app/ai/AiRoundTripConnectedTest.kt:22:class AiRoundTripConnectedTest {
     1	// In-reader AI Providers entry — issue #1380.
     2	//
     3	// Wires the bilingual setup sheet's "Set up" button (shown when no AI provider
     4	// is configured, per Bug #301) to an actual AI Providers surface — which does
     5	// not exist in-reader today (the reader's showSettings sheet is display/fonts
     6	// only; the full SettingsView with AISettingsSection is Library-only).
     7	//
     8	// CANONICAL (A): a scoped "AI Providers" sheet PUSHED inside the bilingual
     9	//   flow (nav bar: ‹ Bilingual · "AI Providers"), hosting only the provider
    10	//   list. Empty → "Add provider" → the canonical AIProviderEditSheet
    11	//   (vreader-ai-provider-fields.jsx, reused unchanged). On first Save the
    12	//   provider becomes the bilingual engine and the stack pops back to Bilingual,
    13	//   whose engine strip now reads "configured / Change…".
    14	//
    15	// ALTERNATIVES shown for comparison:
    16	//   B — deep-link into the full SettingsView, scrolled to the AI section.
    17	//   C — inline expansion of the engine strip inside the bilingual sheet.
    18	//
    19	// Reuses: Sheet vocabulary, SectionLabel, Icons, THEMES tokens. The provider
    20	// tile keeps the fixed #8c2f2f brand color used by the shipped AI Provider row.
    21	
    22	const AIPE_BRAND = '#8c2f2f';           // AI provider tile (theme-independent)
    23	const AIPE_MONO  = 'ui-monospace, "SF Mono", "Menlo", monospace';
    24	const AIPE_SERIF = '"Source Serif 4", Georgia, serif';
    25	
    26	// ────────────────────────────────────────────────────
    27	// NavSheet — bottom sheet with an iOS-style navigation bar (back + centered
    28	// title + trailing). This is the "push within the sheet" presentation: same
    29	// grabber + frame as Sheet, but a real back affordance instead of a grabber-
    30	// only modal. Title is absolutely centered so a wide back label can't shove it.
    31	// ────────────────────────────────────────────────────
    32	function NavSheet({ theme, height = 620, title, backLabel = 'Bilingual', onBack, trailing, children }) {
    33	  const t = theme || THEMES.paper;
    34	  return (
    35	    <div style={{
    36	      position: 'absolute', inset: 0, zIndex: 200,
    37	      display: 'flex', flexDirection: 'column', justifyContent: 'flex-end',
    38	      background: 'rgba(0,0,0,0.35)',
    39	    }}>
    40	      <div style={{
    41	        background: t.isDark ? '#222020' : '#fcf8f0',
    42	        height, borderTopLeftRadius: 22, borderTopRightRadius: 22,
    43	        boxShadow: '0 -8px 28px rgba(0,0,0,0.25)',
    44	        display: 'flex', flexDirection: 'column', overflow: 'hidden',
    45	      }}>
    46	        <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 8 }}>
    47	          <div style={{
    48	            width: 36, height: 5, borderRadius: 3,
    49	            background: t.isDark ? 'rgba(255,255,255,0.18)' : 'rgba(0,0,0,0.12)',
    50	          }}/>
    51	        </div>
    52	        <div style={{
    53	          position: 'relative', display: 'flex', alignItems: 'center',
    54	          padding: '13px 16px 12px',
    55	          borderBottom: `0.5px solid ${t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'}`,
    56	        }}>
    57	          <button onClick={onBack} style={{
    58	            display: 'flex', alignItems: 'center', gap: 1, zIndex: 1,
    59	            background: 'none', border: 'none', padding: 0, cursor: 'pointer',
    60	            color: t.accent, fontFamily: 'inherit', fontSize: 15, fontWeight: 500,
    61	            whiteSpace: 'nowrap',
    62	          }}>
    63	            <Icons.ChevronL size={19} color={t.accent} stroke={2.2}/>
    64	            <span>{backLabel}</span>
    65	          </button>
    66	          <div style={{
    67	            position: 'absolute', left: 0, right: 0, textAlign: 'center',
    68	            fontFamily: AIPE_SERIF, fontSize: 17, fontWeight: 600, color: t.ink,
    69	            pointerEvents: 'none',
    70	          }}>{title}</div>
    71	          <div style={{ marginLeft: 'auto', zIndex: 1 }}>{trailing}</div>
    72	        </div>
    73	        <div style={{ flex: 1, overflow: 'auto' }} className="hide-scroll">{children}</div>
    74	      </div>
    75	    </div>
    76	  );
    77	}
    78	
    79	// ────────────────────────────────────────────────────
    80	// Bilingual engine strip — standalone replica of the strip inside
    81	// BilingualSetupSheet, so the canvas can show the before ("Set up") and after
    82	// ("Change…") states and the flow's payoff. justChanged adds a brief accent
    83	// ring on the freshly-configured return.
    84	// ────────────────────────────────────────────────────
    85	function BilingualEngineStrip({ theme, configured, providerName = 'Claude', onSetup, justChanged = false }) {
    86	  const t = theme;
    87	  return (
    88	    <div>
    89	      <SectionLabel theme={t}>Translation engine</SectionLabel>
    90	      <div style={{
    91	        marginTop: 8, padding: '12px 14px', borderRadius: 12,
    92	        background: configured ? (t.isDark ? 'rgba(255,255,255,0.04)' : '#fff') : `${t.accent}10`,
    93	        border: configured ? `0.5px solid ${t.rule}` : `0.5px solid ${t.accent}55`,
    94	        boxShadow: justChanged ? `0 0 0 2px ${t.accent}66` : 'none',
    95	        display: 'flex', alignItems: 'center', gap: 12,
    96	        transition: 'box-shadow 0.3s',
    97	      }}>
    98	        <div style={{
    99	          width: 28, height: 28, borderRadius: 14, flexShrink: 0,
   100	          background: configured ? `linear-gradient(135deg, ${t.accent}, ${t.accent}aa)` : 'rgba(0,0,0,0.08)',
   101	          display: 'flex', alignItems: 'center', justifyContent: 'center',
   102	        }}>
   103	          <Icons.Sparkle size={14} color={configured ? '#fff' : t.sub} stroke={2}/>
   104	        </div>
   105	        <div style={{ flex: 1, minWidth: 0 }}>
   106	          <div style={{ fontSize: 13.5, color: t.ink, fontWeight: 600 }}>
   107	            {configured ? `${providerName} · with this book’s context` : 'No AI provider configured'}
   108	          </div>
   109	          <div style={{ fontSize: 11.5, color: t.sub, marginTop: 1 }}>
   110	            {configured
   111	              ? 'Translations cached per paragraph, one page ahead.'
   112	              : 'Bilingual mode needs an AI provider to translate.'}
   113	          </div>
   114	        </div>
   115	        <button onClick={onSetup} style={{
   116	          padding: '5px 11px', borderRadius: 100, border: 'none',
   117	          background: configured ? (t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)') : t.accent,
   118	          color: configured ? t.ink : '#fff',
   119	          fontFamily: 'inherit', fontSize: 11.5, fontWeight: 600, cursor: 'pointer',
   120	          flexShrink: 0,
   121	        }}>{configured ? 'Change…' : 'Set up'}</button>
   122	      </div>
   123	    </div>
   124	  );
   125	}
   126	
   127	// ────────────────────────────────────────────────────
   128	// Provider list row — matches the shipped SettingsRow vocabulary.
   129	// ────────────────────────────────────────────────────
   130	function ProviderRow({ theme, name, model, selected, onClick, last }) {
   131	  const t = theme;
   132	  return (
   133	    <div onClick={onClick} style={{
   134	      display: 'flex', alignItems: 'center', gap: 12, padding: '12px 14px',
   135	      borderBottom: last ? 'none' : `0.5px solid ${t.rule}`, cursor: 'pointer',
   136	    }}>
   137	      <div style={{
   138	        width: 30, height: 30, borderRadius: 8, flexShrink: 0, background: AIPE_BRAND,
   139	        display: 'flex', alignItems: 'center', justifyContent: 'center',
   140	      }}>
   141	        <Icons.Sparkle size={17} color="#fff" stroke={1.8}/>
   142	      </div>
   143	      <div style={{ flex: 1, minWidth: 0 }}>
   144	        <div style={{ fontSize: 15, color: t.ink }}>{name}</div>
   145	        <div style={{ fontSize: 11, color: t.sub, marginTop: 1, fontFamily: AIPE_MONO }}>{model}</div>
   146	      </div>
   147	      {selected ? (
   148	        <div style={{ display: 'flex', alignItems: 'center', gap: 6, flexShrink: 0 }}>
   149	          <span style={{ fontSize: 10.5, fontWeight: 600, color: t.accent, letterSpacing: 0.4, textTransform: 'uppercase', whiteSpace: 'nowrap' }}>In use</span>
   150	          <Icons.Check size={16} color={t.accent} stroke={2.6}/>
   151	        </div>
   152	      ) : (
   153	        <Icons.Chevron size={13} color={t.sub} stroke={2}/>
   154	      )}
   155	    </div>
   156	  );
   157	}
   158	
   159	// ────────────────────────────────────────────────────
   160	// AI Providers sheet body — empty + populated.
   161	// ────────────────────────────────────────────────────
   162	function AIProvidersSheetBody({ theme, providers, selectedId, onAdd, onSelect }) {
   163	  const t = theme;
   164	  const empty = !providers || providers.length === 0;
   165	  return (
   166	    <div style={{ padding: '14px 18px 28px' }}>
   167	      {/* why-you're-here context — the bilingual thread, kept visible */}
   168	      <div style={{
   169	        display: 'flex', alignItems: 'center', gap: 10,
   170	        padding: '10px 12px', borderRadius: 10,
   171	        background: `${t.accent}10`, border: `0.5px solid ${t.accent}33`,
   172	        marginBottom: 18,
   173	      }}>
   174	        <div style={{
   175	          width: 22, height: 22, borderRadius: 11, flexShrink: 0,
   176	          background: `${t.accent}1f`, display: 'flex', alignItems: 'center', justifyContent: 'center',
   177	        }}>
   178	          <Icons.Translate size={13} color={t.accent} stroke={1.9}/>
   179	        </div>
   180	        <div style={{ fontSize: 11.5, color: t.ink, lineHeight: 1.35 }}>
   181	          Choose the provider <b style={{ fontWeight: 600 }}>bilingual mode</b> will use to translate this book.
   182	        </div>
   183	      </div>
   184	
   185	      {empty ? (
   186	        <div style={{ textAlign: 'center', padding: '24px 12px 8px' }}>
   187	          <div style={{
   188	            width: 54, height: 54, borderRadius: 27, margin: '0 auto 14px',
   189	            background: `linear-gradient(135deg, ${t.accent}, ${t.accent}aa)`,
   190	            display: 'flex', alignItems: 'center', justifyContent: 'center',
   191	            boxShadow: `0 6px 18px ${t.accent}44`,
   192	          }}>
   193	            <Icons.Sparkle size={26} color="#fff" stroke={1.7}/>
   194	          </div>
   195	          <div style={{ fontFamily: AIPE_SERIF, fontSize: 18, fontWeight: 600, color: t.ink }}>
   196	            No providers yet
   197	          </div>
   198	          <div style={{ fontSize: 12.5, color: t.sub, lineHeight: 1.5, maxWidth: 268, margin: '6px auto 20px' }}>
   199	            Add Claude, OpenAI, or any OpenAI-compatible endpoint. Your API key is stored in the device keychain — never synced.
   200	          </div>
   201	          <button onClick={onAdd} style={{
   202	            display: 'inline-flex', alignItems: 'center', gap: 7,
   203	            padding: '11px 20px', borderRadius: 100, border: 'none',
   204	            background: t.accent, color: '#fff',
   205	            fontFamily: 'inherit', fontSize: 14, fontWeight: 600, cursor: 'pointer',
   206	            boxShadow: `0 4px 14px ${t.accent}55`,
   207	          }}>
   208	            <Icons.Plus size={17} color="#fff" stroke={2.2}/>Add provider
   209	          </button>
   210	        </div>
   211	      ) : (
   212	        <div>
   213	          <SectionLabel theme={t}>Providers</SectionLabel>
   214	          <div style={{
   215	            marginTop: 8, borderRadius: 14, overflow: 'hidden',
   216	            background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
   217	            boxShadow: t.isDark ? 'none' : '0 1px 0 rgba(0,0,0,0.04)',
   218	          }}>
   219	            {providers.map((p) => (
   220	              <ProviderRow key={p.id} theme={t} name={p.name} model={p.model}
   221	                selected={p.id === selectedId} onClick={() => onSelect && onSelect(p.id)}/>
   222	            ))}
   223	            <div onClick={onAdd} style={{
   224	              display: 'flex', alignItems: 'center', gap: 12, padding: '12px 14px', cursor: 'pointer',
   225	            }}>
   226	              <div style={{
   227	                width: 30, height: 30, borderRadius: 8, flexShrink: 0,
   228	                background: t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)',
   229	                display: 'flex', alignItems: 'center', justifyContent: 'center',
   230	              }}>
   231	                <Icons.Plus size={18} color={t.accent} stroke={2.2}/>
   232	              </div>
   233	              <div style={{ flex: 1, fontSize: 15, color: t.accent, fontWeight: 500 }}>Add provider</div>
   234	            </div>
   235	          </div>
   236	          <div style={{ fontSize: 11.5, color: t.sub, lineHeight: 1.45, padding: '10px 4px 0' }}>
   237	            Tap a provider to use it for translating this book.
   238	          </div>
   239	        </div>
   240	      )}
   241	    </div>
   242	  );
   243	}
   244	
   245	function AIProvidersSheet({ theme, providers = [], selectedId, onBack, onAdd, onSelect, trailing, height = 620 }) {
   246	  return (
   247	    <NavSheet theme={theme} height={height} title="AI Providers" backLabel="Bilingual" onBack={onBack} trailing={trailing}>
   248	      <AIProvidersSheetBody theme={theme} providers={providers} selectedId={selectedId} onAdd={onAdd} onSelect={onSelect}/>
   249	    </NavSheet>
   250	  );
   251	}
   252	
   253	// ────────────────────────────────────────────────────
   254	// ALTERNATIVE C — inline expansion of the engine strip.
   255	// Collapsed = the unconfigured strip; expanded = a minimal provider+key form
   256	// in place. Shows why it can't host the real editor without diverging.
   257	// ────────────────────────────────────────────────────
   258	function EngineStripInline({ theme, expanded }) {
   259	  const t = theme;
   260	  const seg = ['Claude', 'OpenAI', 'Custom'];
   261	  return (
   262	    <div>
   263	      <SectionLabel theme={t}>Translation engine</SectionLabel>
   264	      <div style={{
   265	        marginTop: 8, borderRadius: 12, overflow: 'hidden',
   266	        background: `${t.accent}10`, border: `0.5px solid ${t.accent}55`,
   267	      }}>
   268	        <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 14px' }}>
   269	          <div style={{
   270	            width: 28, height: 28, borderRadius: 14, flexShrink: 0, background: 'rgba(0,0,0,0.08)',
   271	            display: 'flex', alignItems: 'center', justifyContent: 'center',
   272	          }}>
   273	            <Icons.Sparkle size={14} color={t.sub} stroke={2}/>
   274	          </div>
   275	          <div style={{ flex: 1, minWidth: 0 }}>
   276	            <div style={{ fontSize: 13.5, color: t.ink, fontWeight: 600 }}>No AI provider configured</div>
   277	            <div style={{ fontSize: 11.5, color: t.sub, marginTop: 1 }}>
   278	              {expanded ? 'Add one below to translate.' : 'Bilingual mode needs an AI provider to translate.'}
   279	            </div>
   280	          </div>
     1	// Issue #1798 / Feature #110 (Android Phase-3) — AI provider + bilingual + chat.
     2	//
     3	// iOS has bilingual interlinear translation (#56) + AI chat (#89); Android
     4	// needs both UIs AND a user-configured provider credential. None of these were
     5	// in a committed bundle (rule 51). Built in VReader's vocabulary; the provider
     6	// editor itself is the already-designed EditorSheet (vreader-ai-provider-
     7	// fields.jsx) — this file adds the provider LIST, the bilingual interlinear
     8	// reader + setup, and the reader AI-chat / summary panel.
     9	//
    10	// One credential powers all three features, so the through-line is the four
    11	// states the issue calls out: unconfigured → configured → in-flight → error.
    12	
    13	const AI_SERIF = '"Source Serif 4", Georgia, serif';
    14	const AI_SANS = "'Inter', -apple-system, system-ui, sans-serif";
    15	
    16	// ── A · provider list (the gate for everything) ──────────────
    17	function AiProviderList({ ui, state = 'configured', height = 880 }) {
    18	  const unconf = state === 'unconfigured';
    19	  const providers = [
    20	    { name: 'Claude (Anthropic)', model: 'claude-sonnet-4-6', active: true, status: 'ok' },
    21	    { name: 'OpenAI', model: 'gpt-4o-mini', active: false, status: 'ok' },
    22	    { name: 'DeepSeek', model: 'deepseek-chat', active: false, status: 'fail' },
    23	  ];
    24	  return (
    25	    <PhoneFrame ui={ui} height={height}>
    26	      <div style={{ position: 'absolute', inset: 0, background: ui.bg, display: 'flex', flexDirection: 'column' }}>
    27	        <div style={{ height: 30 }} />
    28	        <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '6px 14px 12px', borderBottom: `0.5px solid ${ui.sep}` }}>
    29	          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke={ui.tint} strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><path d="M15 6l-6 6 6 6"/></svg>
    30	          <div style={{ flex: 1, fontFamily: AI_SERIF, fontSize: 18, fontWeight: 600, color: ui.ink }}>AI Providers</div>
    31	          <window.Icons.Plus size={24} color={ui.tint} />
    32	        </div>
    33	        <div className="hide-scroll" style={{ flex: 1, overflow: 'auto', padding: '14px 16px 32px' }}>
    34	          {unconf ? (
    35	            <>
    36	              <div style={{ textAlign: 'center', padding: '36px 24px 10px' }}>
    37	                <div style={{ width: 64, height: 64, borderRadius: 32, background: ui.isDark ? 'rgba(214,136,90,0.14)' : 'rgba(140,47,47,0.09)', display: 'flex', alignItems: 'center', justifyContent: 'center', margin: '0 auto 18px' }}>
    38	                  <window.Icons.Sparkle size={30} color={ui.tint} />
    39	                </div>
    40	                <div style={{ fontFamily: AI_SERIF, fontSize: 21, color: ui.ink, marginBottom: 8 }}>Connect an AI provider</div>
    41	                <div style={{ fontFamily: AI_SANS, fontSize: 14, color: ui.sec, lineHeight: 1.55 }}>
    42	                  One key unlocks bilingual translation, chat about a book, and chapter summaries. Your key is stored on-device only.
    43	                </div>
    44	              </div>
    45	              <button style={{ width: '100%', border: 'none', cursor: 'pointer', background: ui.tint, color: '#fff', borderRadius: 13, padding: '14px 0', fontFamily: AI_SANS, fontSize: 15, fontWeight: 600, marginTop: 18 }}>Add a provider</button>
    46	              <GroupFooter ui={ui}>Works with Anthropic, OpenAI-compatible endpoints, and local models.</GroupFooter>
    47	            </>
    48	          ) : (
    49	            <>
    50	              <GroupHeader ui={ui}>Providers</GroupHeader>
    51	              <Card ui={ui}>
    52	                {providers.map((p, i) => (
    53	                  <div key={p.name} style={{ display: 'flex', alignItems: 'center', minHeight: 60, padding: '0 14px', position: 'relative' }}>
    54	                    {p.active
    55	                      ? <svg width="20" height="20" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="9" fill={ui.tint}/><path d="M8 12.3l3 3 5.5-6" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" fill="none"/></svg>
    56	                      : <div style={{ width: 20, height: 20, borderRadius: 10, boxShadow: `inset 0 0 0 1.7px ${ui.sep}` }} />}
    57	                    <div style={{ flex: 1, minWidth: 0, marginLeft: 12 }}>
    58	                      <div style={{ fontFamily: AI_SANS, fontSize: 15.5, fontWeight: 500, color: ui.ink }}>{p.name}</div>
    59	                      <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 2 }}>
    60	                        <span style={{ width: 7, height: 7, borderRadius: 4, background: p.status === 'ok' ? ui.green : ui.red }} />
    61	                        <span style={{ fontFamily: window.MONO, fontSize: 11.5, color: p.status === 'ok' ? ui.sec : ui.red }}>{p.status === 'ok' ? p.model : '401 — key rejected'}</span>
    62	                      </div>
    63	                    </div>
    64	                    <window.Icons.ChevronD size={18} color={ui.ter} style={{ transform: 'rotate(-90deg)' }} />
    65	                    {i < providers.length - 1 && <div style={{ position: 'absolute', left: 46, right: 0, bottom: 0, height: 0.5, background: ui.sep }} />}
    66	                  </div>
    67	                ))}
    68	              </Card>
    69	              <GroupFooter ui={ui}>The selected provider is used for translation, chat, and summaries. Tap one to edit or test it.</GroupFooter>
    70	            </>
    71	          )}
    72	        </div>
    73	      </div>
    74	    </PhoneFrame>
    75	  );
    76	}
    77	
    78	// ── B · bilingual interlinear reader ─────────────────────────
    79	const BL_PAIRS = [
    80	  ['It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.', '凡是有钱的单身汉，总想娶位太太，这已成了一条举世公认的真理。'],
    81	  ['However little known the feelings of such a man may be, this truth is so well fixed in the minds of the surrounding families…', '这样的单身汉，每逢新搬到一个地方，四邻八舍虽然完全不了解他的性情……'],
    82	  ['…that he is considered as the rightful property of some one or other of their daughters.', '……却把他视作自己某一个女儿理所应得的一笔财产。'],
    83	];
    84	
    85	function BilingualReader({ themeKey = 'paper', state = 'on', height = 880 }) {
    86	  const t = window.THEMES[themeKey];
    87	  const trans = t.isDark ? '#d6885a' : '#8c2f2f';
    88	  return (
    89	    <window.TtsFrame t={t} height={height}>
    90	      <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column' }}>
    91	        <window.StatusStrip t={t} />
    92	        <window.ReaderChrome t={t} />
    93	        {state === 'inflight' && (
    94	          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 9, padding: '6px 0 10px' }}>
    95	            <svg className="apf-spin" width="15" height="15" viewBox="0 0 24 24" fill="none" stroke={trans} strokeWidth="2.6" strokeLinecap="round"><path d="M12 3a9 9 0 1 0 9 9"/></svg>
    96	            <span style={{ fontFamily: AI_SANS, fontSize: 12.5, fontWeight: 600, color: trans }}>Translating chapter… 38%</span>
    97	          </div>
    98	        )}
    99	        <div style={{ flex: 1, overflow: 'hidden', padding: '6px 26px 0' }}>
   100	          {state === 'error' ? (
   101	            <div style={{ textAlign: 'center', padding: '90px 20px' }}>
   102	              <div style={{ width: 58, height: 58, borderRadius: 29, background: t.isDark ? 'rgba(224,119,90,0.14)' : 'rgba(168,64,47,0.1)', display: 'flex', alignItems: 'center', justifyContent: 'center', margin: '0 auto 16px' }}>
   103	                <window.Icons.Translate size={28} color={trans} />
   104	              </div>
   105	              <div style={{ fontFamily: AI_SERIF, fontSize: 18, color: t.ink, marginBottom: 8 }}>Couldn't translate</div>
   106	              <div style={{ fontFamily: AI_SANS, fontSize: 13.5, color: t.sub, lineHeight: 1.5, marginBottom: 18 }}>Claude returned a 429 (rate limit). The original text is unchanged — try again or switch provider.</div>
   107	              <button style={{ border: 'none', cursor: 'pointer', background: t.accent, color: '#fff', borderRadius: 11, padding: '10px 20px', fontFamily: AI_SANS, fontSize: 14, fontWeight: 600 }}>Retry</button>
   108	            </div>
   109	          ) : (
   110	            <div style={{ fontFamily: AI_SERIF, fontSize: 18, lineHeight: 1.5, color: t.ink, textWrap: 'pretty' }}>
   111	              {BL_PAIRS.map(([en, zh], i) => (
   112	                <div key={i} style={{ marginBottom: 19 }}>
   113	                  <div style={{ color: state === 'inflight' && i > 0 ? t.sub : t.ink, opacity: state === 'inflight' && i > 0 ? 0.5 : 1 }}>{en}</div>
   114	                  {(state === 'on' || (state === 'inflight' && i === 0)) && (
   115	                    <div style={{ color: trans, fontSize: 16, marginTop: 5, lineHeight: 1.5, paddingLeft: 11, borderLeft: `2px solid ${trans}`, opacity: 0.92 }}>{zh}</div>

exec
/bin/zsh -lc "nl -ba dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md | sed -n '1,260p'
nl -ba android/app/src/androidTest/kotlin/com/vreader/app/ai/AiRoundTripConnectedTest.kt | sed -n '1,200p'
nl -ba android/app/src/test/kotlin/com/vreader/app/reader/chrome/ReaderMoreRowsTest.kt | sed -n '1,180p'
nl -ba android/app/src/androidTest/kotlin/com/vreader/app/reader/more/MorePopupTest.kt | sed -n '1,240p'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
     1	# Gate-1 Plan — Feature #136: AI provider setup made production-reachable (Android)
     2	
     3	> Status target: `TODO` → `PLANNED` (on Gate-2 pass)
     4	> Platform lane: `android-app` (Gate-5 = Android emulator connected run, rule 47 Android tier)
     5	> Design authority (rule 51, LANDED — no `needs-design`): `vreader-more.jsx` (the reader More-menu `configure-ai` disabled-Bilingual row), `vreader-ai-android.jsx` (`AiProviderList` surface A), `vreader-ai-provider-entry.jsx` + `design-notes/reader-ai-provider-entry.md` + `design-notes/reader-ai-readiness.md` (the in-reader scoped AI-Providers entry decision), `vreader-ai-provider-fields.jsx` (the reused editor).
     6	
     7	## 1. Problem
     8	
     9	Feature #118 shipped the entire Android AI provider stack — `AiProviderStore` (keystore-encrypted profile persistence, #116 `KeystoreSecretCipher` precedent), `AiSettingsViewModel` (list + editor + Test Connection), `AiProviderListScreen` (the designed "AI Providers" gate surface), and `AiProviderEditSheet` (the canonical add/edit form). It is fully unit- and connected-tested. **But none of it is wired into any production entry.** Grep confirms `AiProviderListScreen`, `AiSettingsViewModel`, and `AiProviderEditSheet` are referenced **only** by `androidTest`/`test` sources; `AiProviderStore` is **never constructed** in `AppContainer` (it appears only in comments as a naming precedent); and `MainActivity` is a single Library Activity that `startActivity`-launches reader hosts — there is **no `NavHost`, no Settings tree, and no More-menu AI row** that reaches the AI screens. `LibraryScreen.kt:95-96` explicitly records that the design's Library settings/More pill "is added when that feature lands (a separate WI) … still omitted."
    10	
    11	Consequence: **a fresh install has zero production route to configure an AI provider.** With no provider, every downstream AI feature is dead — bilingual (#131), chat (`AiChatPanel`, also unwired), translate, summaries. This is exactly the Gate-2-round-2 audit High-3 recorded against #131: bilingual's fresh-user path and its Gate-5 acceptance route both dead-end because there is no reachable AI config to land on.
    12	
    13	**#136 makes the already-designed, already-built AI provider config production-reachable and independently verifiable**, from a designed in-reader entry that does not depend on #131.
    14	
    15	## 2. Surface area
    16	
    17	### Designed entry point (the decision)
    18	
    19	Two designed reader entries exist; #136 uses the one that is **independent of #131**:
    20	
    21	- **`vreader-more.jsx:91-95`** depicts the reader More-menu row: when `s.aiUnavailable`, a **disabled "Bilingual mode" row** with `sub="Configure AI provider first"` whose tap fires `onAction('configure-ai')`. This is the canonical "AI unconfigured → route to config" affordance in the reader chrome, and the Kotlin scaffolding already exists for it: `MoreActionId.BILINGUAL`, `MoreRow.Disabled(id, label, icon, sub, onTap)`, and the `readerMoreRows(...)` assembler in `ReaderChromeScaffold.kt`. The `configure-ai` action → presents the **AI Providers sheet** (`AiProviderListScreen`), matching `reader-ai-provider-entry.md`'s "closes the Library→Settings→AI gap inside the reader" decision (Variant A: a scoped in-reader provider sheet reusing the canonical editor, NOT the full SettingsView).
    22	
    23	This entry is reachable by a fresh user (open any book → More → "Configure AI provider first") with **no bilingual wiring present** — which is precisely what independent-verifiability requires. #131 will later ADD the *enabled* Bilingual toggle + its own bilingual-Set-up→here route; #136 owns only the `aiUnavailable`/`configure-ai` path.
    24	
    25	### Files MODIFIED
    26	
    27	| File | Change (concrete signature) |
    28	|---|---|
    29	| `android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt` (`AppContainer`) | Add process-singleton `val aiProviderStore: AiProviderStore by lazy { AiProviderStore(<DataStore under noBackupFilesDir "ai_providers.preferences_pb">, KeystoreSecretCipher(<alias>)) }` (the `readerSettingsStore`/`OpdsSourceStore` DataStore-under-`noBackupFilesDir` + `KeystoreSecretCipher` precedent — keys are per-device, NOT in the backup contract). Add `fun aiSettingsViewModel(): AiSettingsViewModel = AiSettingsViewModel(aiProviderStore)` factory. |
    30	| `android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderChromeScaffold.kt` (`readerMoreRows`) | Extend the assembler to additively accept the AI-entry callback and emit the designed disabled Bilingual row when AI is unconfigured: `internal fun readerMoreRows(onDetails, onShare, aiUnconfigured: Boolean = false, onConfigureAi: (() -> Unit)? = null): List<MoreRow>` → prepends `MoreRow.Disabled(id = MoreActionId.BILINGUAL, label = "Bilingual mode", icon = Icons.…Translate-analog, sub = "Configure AI provider first", onTap = onConfigureAi ?: {})` **only when `aiUnconfigured && onConfigureAi != null`** (no dead control — #129 rule; absent otherwise). Nullable defaults keep #134/#131 callers valid. Note: `MoreRow.Disabled` is currently non-interactive in `MorePopup.MoreRowItem` (`onClick = {}`); making the `configure-ai` row tappable is a **row-treatment change** — see Risks §6 (the design shows `disabled` + an `on` handler, so the row is dimmed-but-tappable). |
    31	| `android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderChromeState.kt` (+`…StateSaver`) | Add `ReaderSheet.AiProviders` to the sealed `ReaderSheet` set and to the string saver (round-trips like `Toc`/`Notes`/`Bookmarks`; unknown token → `None`, never throws — the existing saver contract). Survives rotation/process-death. |
    32	| `android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderChromeScaffold.kt` (host sheet layer) + `android/app/src/main/kotlin/com/vreader/app/reader/EpubReaderChrome.kt` (`EpubReaderSheets`) | Render the `ReaderSheet.AiProviders` route: host the `AiProviderListScreen` + `AiProviderEditSheet` fed by an `AiSettingsViewModel` (obtained via the Activity's `ViewModelStore`, `viewModel(factory = …container.aiSettingsViewModel())` — the `SearchViewModel` precedent in `MainActivity`), wired to `AiSettingsViewModel.openAdd/openEdit/close/update/test/save/delete/setActive` and the `editState`/`listState` flows. Back / Done → `ReaderSheet.None`. |
    33	| The five reader host Activities that assemble chrome — `ReaderActivity.kt` (EPUB, via `EpubTopBand`/`EpubReaderSheets`) + `TxtReaderActivity.kt`, `PdfReaderActivity.kt`, `Azw3ReaderActivity.kt` (scaffold hosts) | Pass `aiUnconfigured` (derived from `container.aiProviderStore.observe().map { it.profiles.isEmpty() }` collected as state) + `onConfigureAi = { chromeState = …copy(sheet = ReaderSheet.AiProviders) }` into `readerMoreRows(...)` / `EpubTopBand`. This is the one-writer-coordinate additive pattern #132/#134/#135 already use for the chrome files. |
    34	
    35	### Files ADDED
    36	
    37	| File | Purpose |
    38	|---|---|
    39	| `android/app/src/main/kotlin/com/vreader/app/reader/ai/ReaderAiProvidersHost.kt` (new, ~120 lines) | The reader-scoped presentation container: a `@Composable ReaderAiProvidersHost(vm: AiSettingsViewModel, onClose: () -> Unit)` that observes `vm.listState`/`vm.editState` and hosts `AiProviderListScreen` (list/empty) + the `AiProviderEditSheet` modal-on-top (the `reader-ai-provider-entry.md` "list is a push, editor is a modal on top" nav model). **Rule 51: renders ONLY the existing designed surfaces** (`AiProviderListScreen`, `AiProviderEditSheet`) — no new visual chrome. New Kotlin file → lane-dispatchable (Gradle source-set glob). |
    40	| Tests — see §5. | JVM/Robolectric + connected. |
    41	
    42	### Files OUT of scope
    43	
    44	- **Provider CRUD internals** — `AiProviderStore.upsert/delete/setActive/apiKey`, `AiSettingsViewModel.test/save`, `AiProviderFactory`, the provider clients, `SseEventReader`, `AiProviderKind`. All shipped and tested by #118; #136 constructs and reaches them, never re-implements them.
    45	- **The designed surfaces themselves** — `AiProviderListScreen.kt`, `AiProviderEditSheet.kt`, `AiSettingsUiState.kt`. Used verbatim.
    46	- **The AI-readiness sheet (flag + consent gates)** — `reader-ai-readiness.md`'s `ReaderAIReadinessSheet` (master AI toggle + consent ledger) is **design-landed but implementation-deferred** ("do NOT build without go-ahead"). #136 delivers the provider-list reachability only; the flag/consent capstone is a separate feature.
    47	- **AI chat panel wiring** — `AiChatPanel`/`AiChatViewModel` are ALSO unwired, but chat's reader entry is #131/a chat feature's surface, not #136.
    48	- **Bilingual toggle + bilingual Set-up → AI route** — #131 owns the enabled Bilingual `MoreRow.Toggle` and its own route into this same sheet.
    49	- **A Library-level Settings tree / More pill** (`LibraryScreen.kt:95`) — not built; #136 deliberately does NOT depend on it (see §3 rejected alt).
    50	- **`contracts/`** — no cross-platform contract change (keys are device-local, excluded from backup).
    51	
    52	## 3. Prior art / precedent / rejected alternatives
    53	
    54	**Committed design (rule 51 satisfied):**
    55	- `design-notes/reader-ai-provider-entry.md` — Variant **A** (CANONICAL): "a scoped, in-reader 'AI Providers' sheet … reusing the canonical `AIProviderEditSheet`", chosen over B (deep-link the whole SettingsView) and C (inline mini-form). Its stated win: "Keeps the reader context … the user never sees Cloud & Sync, OPDS, TTS." #136 implements A's Android analog.
    56	- `design-notes/reader-ai-readiness.md` — the same "close the loop **inside the reader**" decision, naming this the surface "every 'AI unconfigured' silent-no-op should route to."
    57	- `vreader-more.jsx:91-95` — the exact reader-chrome affordance: `aiUnavailable` → disabled Bilingual row `sub="Configure AI provider first"` → `onAction('configure-ai')`.
    58	- `vreader-ai-android.jsx` `AiProviderList` (surface A, "the gate for everything") — already implemented verbatim as `AiProviderListScreen.kt` (its header comment cites this).
    59	
    60	**Project precedent for the wiring shape:**
    61	- **#118** built the whole stack; **#116** `KeystoreSecretCipher` + `WebDavServerStore`/`OpdsSourceStore` established the "DataStore-under-`noBackupFilesDir` + keystore cipher, constructed once in `AppContainer`" pattern this plan follows for `aiProviderStore`.
    62	- **#129/#132/#134/#135** wired every reader-chrome entry through the exact seams #136 reuses: the `readerMoreRows` assembler, `ReaderChromeState`/`ReaderSheet` + its saver, the `EpubReaderSheets` open-only sheet layer, and the additive-nullable-param "one-writer-coordinate" convention. #134 added Details/Share rows; #136 adds the `configure-ai` row by the same contract.
    63	- **`MainActivity` `SearchViewModel`** precedent — obtaining a container-built ViewModel via `viewModel(factory = viewModelFactory { initializer { container.searchViewModel() } })` so its `viewModelScope` is cleared on Activity destroy. `aiSettingsViewModel()` follows this exactly.
    64	
    65	**Rejected alternatives:**
    66	1. **Library Settings tree / More pill entry (`LibraryScreen.kt:95`).** Rejected: that Settings tree does not exist on Android, and `OpdsSourcesViewModel`/`OpdsSourceStore` are *also* still test-only — building the whole Library Settings host is a large, separate feature. The design's own decision (both notes) is the in-reader scoped entry.
    67	2. **Route only from #131's bilingual Set-up.** Rejected by independent-verifiability: it would couple #136 to #131 (still `PLANNED`) and make AI config unreachable until bilingual ships. The `aiUnavailable`/`configure-ai` More-row is reachable with zero bilingual wiring.
    68	3. **Deep-link the full SettingsView (Variant B) / inline mini-form (Variant C).** Rejected by the design notes themselves.
    69	4. **Build the deferred AI-readiness sheet (flag+consent) now.** Rejected: `reader-ai-readiness.md` marks it "implementation deferred — do NOT build without go-ahead."
    70	
    71	## 4. Work-item sequencing (small feature — 3 WIs)
    72	
    73	**WI-1 — `AppContainer` AI store + VM factory (FOUNDATIONAL).**
    74	Construct `aiProviderStore` (DataStore under `noBackupFilesDir` + `KeystoreSecretCipher`) and `aiSettingsViewModel()` in `AppContainer`. No user-observable behavior → unit tests + audit suffice (Gate-5 foundational tier, no device verify). *PR size: XS.* Lane-dispatchable (edits one existing file + new test).
    75	
    76	**WI-2 — `ReaderAiProvidersHost` + `ReaderSheet.AiProviders` route (BEHAVIORAL).**
    77	Add the new `ReaderAiProvidersHost.kt` (hosts `AiProviderListScreen` + `AiProviderEditSheet` over the VM), the `ReaderSheet.AiProviders` sealed case + saver round-trip, and render it in the scaffold sheet layer + `EpubReaderSheets`. *PR size: S.* Connected Compose slice: open route → empty state → Add → editor → Save → list shows provider → back.
    78	
    79	**WI-3 — reader More-menu `configure-ai` entry across all five hosts (BEHAVIORAL, FINAL WI).**
    80	Extend `readerMoreRows` with the `aiUnconfigured`/`onConfigureAi` params emitting the designed disabled-Bilingual row, and wire `aiUnconfigured` (from `aiProviderStore.observe()`) + `onConfigureAi` (opens `ReaderSheet.AiProviders`) in the four host Activities + `EpubTopBand`. *PR size: M.* Closes the feature → full Gate-5 acceptance (the reachable end-to-end flow on emulator).
    81	
    82	> Sequencing: WI-1 is a pure foundation WI-2 depends on; WI-2 makes the destination renderable + independently testable *before* any entry exists; WI-3 lights the entry across hosts. Each is one PR.
    83	
    84	## 5. Test catalogue
    85	
    86	**JVM / Robolectric (`app/src/test`):**
    87	- `AppContainerAiWiringTest.kt` (new) — `aiProviderStore` is a stable singleton; `aiSettingsViewModel()` returns a VM whose `listState` reflects the store (empty fresh, non-empty after `upsert`). Guards WI-1.
    88	- Extend `ReaderChromeStateSaverTest.kt` — `ReaderSheet.AiProviders` round-trips; unknown/garbage token → `None` (never throws). Guards WI-2 process-death.
    89	- `ReaderMoreRowsAiEntryTest.kt` (new, JVM/pure) — `readerMoreRows(aiUnconfigured = true, onConfigureAi = {…})` includes exactly one `MoreRow.Disabled`/`configure-ai` row with the designed label + sub; `aiUnconfigured = false` OR `onConfigureAi = null` omits it (no dead control). Guards WI-3.
    90	
    91	**Connected Compose (`app/src/androidTest`) — the #132/#134/#135 pattern; the connected run IS the Gate-5 acceptance:**
    92	- Reuse existing `AiProviderListScreenTest`/`AiProviderEditSheetTest`/`AiRoundTripConnectedTest` (unchanged — surfaces verbatim).
    93	- `ReaderAiProvidersHostConnectedTest.kt` (new) — drives `ReaderAiProvidersHost` over a real `AiSettingsViewModel`+`AiProviderStore`: empty state (`ai-add-provider`) → Add → `AiProviderEditSheet` (`ai-save`) → save → list shows `provider-<id>` → back → `ReaderSheet.None`.
    94	- `ReaderMoreAiEntryConnectedTest.kt` (new) — the **reachability acceptance**: launch a reader host on a fresh (no-provider) store → open More → "Configure AI provider first" row present + tappable → tap → `AiProviderListScreen` empty state → add a provider → return → re-open More → the `configure-ai` row is now **absent**. The "fresh user can reach AI config, add a provider, and return" acceptance, independent of #131.
    95	
    96	**Audit-driven additions:** corrupt/partial DataStore token (saver → `None`); process-death mid-editor (route restores, editor state transient by design); a provider deleted while the sheet is open (list re-derives from the store Flow).
    97	
    98	## 6. Risks + mitigations
    99	
   100	- **Coupling with #131.** Mitigation: the entry is the `aiUnavailable`/`configure-ai` More-row, reachable with zero bilingual code; #131 separately adds the *enabled* Bilingual toggle + its Set-up→here route. `readerMoreRows` params additive-nullable so #131's later change is one-writer-coordinate.
   101	- **`MoreRow.Disabled` is currently non-interactive.** `MorePopup.MoreRowItem` renders `Disabled` with `onClick = {}`. The design (`vreader-more.jsx:94-95`) shows the row `disabled` AND `on={() => onAction('configure-ai')}` — dimmed but tappable. Mitigation: WI-3 makes the `Disabled` row's `onTap` fire (a small `MorePopup` change), matching the design; covered by `ReaderMoreAiEntryConnectedTest`. Restore-to-designed-state, rule-51-clean.
   102	- **AI-key security surface (#118).** Mitigation: #136 constructs `AiProviderStore` with `KeystoreSecretCipher` under `noBackupFilesDir` (the #116 contract) and touches NO CRUD/crypto path. Keys stay device-local; no `contracts/` change.
   103	- **Config-change / process-death.** Mitigation: `ReaderSheet.AiProviders` is in the `rememberSaveable` saver (rotation/death safe); the editor's transient form re-opens empty by design; the VM is Activity-`ViewModelStore`-owned (`SearchViewModel` precedent), scope cleared on destroy.
   104	- **Five-host fan-out.** Mitigation: EPUB routes through `EpubTopBand`/`EpubReaderSheets`; the other three through the shared `ReaderChromeScaffold` — the split #134 already validated. One connected test per family confirms parity.
   105	
   106	## 7. Backward compatibility
   107	
   108	- **Fresh install, no providers (the designed onboarding state).** `aiProviderStore.observe()` → `profiles.isEmpty()` → the More-menu "Configure AI provider first" row → tapping lands on `AiProviderListScreen`'s empty state. No crash, no dead control before a provider exists.
   109	- **Existing DEBUG-configured provider.** `profiles.isNotEmpty()` → the `configure-ai` row is **absent** from More (AI available); the store schema unchanged (#118 JSON-in-DataStore); no migration.
   110	- **Older reader-chrome state tokens.** Unknown-token → `None` means a persisted pre-#136 `ReaderChromeState` restores cleanly.
   111	- **No `contracts/` / backup-format impact** — keys device-local, excluded from the backup contract.
   112	
   113	## Dependency statement (binding)
   114	
   115	**#136 is a HARD dependency of #131.** #131's fresh-user AI-config path + its Gate-5 acceptance route both require a reachable AI provider config to land on; that destination is delivered by #136. #131 must not re-implement or inline provider config — it consumes #136's `ReaderSheet.AiProviders` sheet. **#131's bilingual-Set-up → #136 route (the enabled Bilingual `MoreRow.Toggle` + its "Set up"→AI-Providers navigation) is #131's OWN WI, not #136's** — #136 delivers only the independent `aiUnavailable`/`configure-ai` More-menu entry, so AI config is reachable + verifiable before #131 exists.
   116	
   117	## Revision history
   118	
   119	- v1 (2026-07-12) — Gate-1 draft. Authored to resolve #131 Gate-2-round-2 High-3 (AI-config unreachable): the #118 AI provider stack is production-reachable via the designed reader More-menu `configure-ai` entry (Variant A in-reader AI-Providers sheet). 3 WIs. Spun out per the orchestrator/user decision (2026-07-12) that AI-settings navigation is its own tiny feature + a hard dependency of #131.
     1	package com.vreader.app.ai
     2	
     3	import androidx.test.ext.junit.runners.AndroidJUnit4
     4	import androidx.test.platform.app.InstrumentationRegistry
     5	import kotlinx.coroutines.Dispatchers
     6	import kotlinx.coroutines.flow.toList
     7	import kotlinx.coroutines.runBlocking
     8	import org.junit.Assert.assertEquals
     9	import org.junit.Assert.assertTrue
    10	import org.junit.Assume.assumeNotNull
    11	import org.junit.Test
    12	import org.junit.runner.RunWith
    13	
    14	/**
    15	 * Feature #118 WI-5 — the LIVE AI acceptance (Gate-5). Drives the REAL OpenAiCompatibleProvider
    16	 * (HttpURLConnection + the bounded SSE framer) against a local OpenAI-compatible SSE stub on the Mac
    17	 * host (reachable from the emulator at 10.0.2.2): test-connection (one-shot) succeeds, and a sent
    18	 * prompt streams an assembled answer over a real socket SSE stream. Skips unless
    19	 * scripts/run-ai-roundtrip.sh passes the `aiBaseUrl` instrumentation arg.
    20	 */
    21	@RunWith(AndroidJUnit4::class)
    22	class AiRoundTripConnectedTest {
    23	
    24	    @Test
    25	    fun testConnection_and_streamChat_overLiveSse() = runBlocking {
    26	        val base = InstrumentationRegistry.getArguments().getString("aiBaseUrl")
    27	        assumeNotNull("set -e aiBaseUrl to run (via scripts/run-ai-roundtrip.sh)", base)
    28	
    29	        val client = OpenAiCompatibleProvider(base!!, "sk-test", "gpt-4o-mini", 0.7, 64, Dispatchers.IO)
    30	
    31	        // Test connection = a one-shot ping; the stub returns choices[0].message.content.
    32	        assertTrue("testConnection ok", client.testConnection() is AiTestResult.Ok)
    33	
    34	        // Stream a chat completion; the stub streams 4 deltas then [DONE].
    35	        val answer = client.streamChat(
    36	            AiRequest("gpt-4o-mini", listOf(AiMessage(AiRole.user, "hello")), 0.7, 64)
    37	        ).toList().joinToString("") { it.deltaText }
    38	        assertEquals("Hello from the vreader stub.", answer)
    39	    }
    40	}
     1	package com.vreader.app.reader.chrome
     2	
     3	import com.vreader.app.reader.more.MoreActionId
     4	import com.vreader.app.reader.more.MoreRow
     5	import org.junit.Assert.assertEquals
     6	import org.junit.Assert.assertFalse
     7	import org.junit.Assert.assertTrue
     8	import org.junit.Test
     9	import org.junit.runner.RunWith
    10	import org.robolectric.RobolectricTestRunner
    11	
    12	/**
    13	 * Feature #134 WI-5 — the pure [readerMoreRows] assembler that the reader chrome feeds to the WI-3
    14	 * [com.vreader.app.reader.more.MorePopup]. #134 owns ONLY the Details + Share rows: no TTS / Auto-turn /
    15	 * Bilingual / Export (those belong to other features and are supplied by them, never invented here — the
    16	 * §more-row-ownership contract + the #129 no-dead-control rule). Both are [MoreRow.Action]s wiring their
    17	 * respective callbacks. Robolectric only because constructing the material `ImageVector` icon refs touches
    18	 * Compose's graphics vector; the function itself has no Android/Compose-runtime dependency.
    19	 */
    20	@RunWith(RobolectricTestRunner::class)
    21	class ReaderMoreRowsTest {
    22	
    23	    @Test fun assemblesOnlyDetailsAndShare() {
    24	        val rows = readerMoreRows(onDetails = {}, onShare = {})
    25	        assertEquals(listOf(MoreActionId.DETAILS, MoreActionId.SHARE), rows.map { it.id })
    26	    }
    27	
    28	    @Test fun bothAreActionRows_withDesignedLabels() {
    29	        val rows = readerMoreRows(onDetails = {}, onShare = {})
    30	        val details = rows.single { it.id == MoreActionId.DETAILS }
    31	        val share = rows.single { it.id == MoreActionId.SHARE }
    32	        assertTrue(details is MoreRow.Action)
    33	        assertTrue(share is MoreRow.Action)
    34	        assertEquals("Book details", details.label)
    35	        assertEquals("Share book", share.label)
    36	    }
    37	
    38	    @Test fun detailsActionFiresOnlyOnDetailsTap() {
    39	        var detailed = false
    40	        var shared = false
    41	        val rows = readerMoreRows(onDetails = { detailed = true }, onShare = { shared = true })
    42	        (rows.single { it.id == MoreActionId.DETAILS } as MoreRow.Action).onTap()
    43	        assertTrue(detailed)
    44	        assertFalse(shared)
    45	    }
    46	
    47	    @Test fun shareActionFiresOnlyOnShareTap() {
    48	        var detailed = false
    49	        var shared = false
    50	        val rows = readerMoreRows(onDetails = { detailed = true }, onShare = { shared = true })
    51	        (rows.single { it.id == MoreActionId.SHARE } as MoreRow.Action).onTap()
    52	        assertTrue(shared)
    53	        assertFalse(detailed)
    54	    }
    55	
    56	    @Test fun noTtsAutoTurnBilingualOrExportRows() {
    57	        val rows = readerMoreRows(onDetails = {}, onShare = {})
    58	        val ids = rows.map { it.id }.toSet()
    59	        assertFalse(ids.contains(MoreActionId.TTS))
    60	        assertFalse(ids.contains(MoreActionId.AUTO_TURN))
    61	        assertFalse(ids.contains(MoreActionId.BILINGUAL))
    62	        // There is deliberately no EXPORT id in MoreActionId — absence is structural.
    63	    }
    64	}
     1	package com.vreader.app.reader.more
     2	
     3	import androidx.compose.material.icons.Icons
     4	import androidx.compose.material.icons.filled.Info
     5	import androidx.compose.material.icons.filled.Share
     6	import androidx.compose.material.icons.outlined.Timer
     7	import androidx.compose.material.icons.outlined.Translate
     8	import androidx.compose.runtime.CompositionLocalProvider
     9	import androidx.compose.ui.platform.LocalLayoutDirection
    10	import androidx.compose.ui.test.assertCountEquals
    11	import androidx.compose.ui.test.assertHasClickAction
    12	import androidx.compose.ui.test.assertIsOff
    13	import androidx.compose.ui.test.assertIsOn
    14	import androidx.compose.ui.test.junit4.createComposeRule
    15	import androidx.compose.ui.test.onAllNodesWithTag
    16	import androidx.compose.ui.test.onNodeWithTag
    17	import androidx.compose.ui.test.onNodeWithText
    18	import androidx.compose.ui.test.performClick
    19	import androidx.compose.ui.unit.LayoutDirection
    20	import androidx.test.ext.junit.runners.AndroidJUnit4
    21	import com.vreader.app.reader.settings.ReaderTheme
    22	import org.junit.Assert.assertFalse
    23	import org.junit.Assert.assertTrue
    24	import org.junit.Rule
    25	import org.junit.Test
    26	import org.junit.runner.RunWith
    27	
    28	/**
    29	 * Feature #134 WI-3 — the reader More popover (`vreader-more.jsx` `MorePopover`) over the `MoreRow`
    30	 * model. The popup renders ONLY the rows the caller supplies (the §more-row-ownership contract): an
    31	 * action id with NO supplied row is ABSENT — no dead TTS/Auto-turn/Bilingual/Export rows. #134 owns
    32	 * only DETAILS + SHARE. Action rows fire onTap, Toggle rows reflect `on` + call onToggle, Disabled rows
    33	 * are non-interactive with a sub-text. Backdrop tap dismisses. Reuses the [ReaderTheme] token map.
    34	 */
    35	@RunWith(AndroidJUnit4::class)
    36	class MorePopupTest {
    37	    @get:Rule val compose = createComposeRule()
    38	
    39	    private fun detailsRow(onTap: () -> Unit = {}) =
    40	        MoreRow.Action(id = MoreActionId.DETAILS, label = "Book details", icon = Icons.Filled.Info, onTap = onTap)
    41	
    42	    private fun shareRow(onTap: () -> Unit = {}) =
    43	        MoreRow.Action(id = MoreActionId.SHARE, label = "Share book", icon = Icons.Filled.Share, onTap = onTap)
    44	
    45	    @Test fun popupRendersWithTestTag() {
    46	        compose.setContent {
    47	            MorePopup(theme = ReaderTheme.Paper, rows = listOf(detailsRow(), shareRow()), onDismiss = {})
    48	        }
    49	        compose.onNodeWithTag("more-popup", useUnmergedTree = true).assertExists()
    50	    }
    51	
    52	    @Test fun detailsAndShareRowsRenderAndFireCallbacks() {
    53	        var detailed = false
    54	        var shared = false
    55	        compose.setContent {
    56	            MorePopup(
    57	                theme = ReaderTheme.Paper,
    58	                rows = listOf(detailsRow { detailed = true }, shareRow { shared = true }),
    59	                onDismiss = {},
    60	            )
    61	        }
    62	        compose.onNodeWithText("Book details", useUnmergedTree = true).assertExists()
    63	        compose.onNodeWithText("Share book", useUnmergedTree = true).assertExists()
    64	
    65	        compose.onNodeWithTag("more-row-details", useUnmergedTree = true).performClick()
    66	        assertTrue(detailed)
    67	        assertFalse(shared)
    68	
    69	        compose.onNodeWithTag("more-row-share", useUnmergedTree = true).performClick()
    70	        assertTrue(shared)
    71	    }
    72	
    73	    @Test fun suppliedToggleRowReflectsOnAndFiresOnToggle() {
    74	        var toggledTo: Boolean? = null
    75	        compose.setContent {
    76	            MorePopup(
    77	                theme = ReaderTheme.Dark,
    78	                rows = listOf(
    79	                    MoreRow.Toggle(
    80	                        id = MoreActionId.AUTO_TURN, label = "Auto-turn pages", icon = Icons.Outlined.Timer,
    81	                        sub = "Every 30s", on = true, onToggle = { toggledTo = it },
    82	                    ),
    83	                ),
    84	                onDismiss = {},
    85	            )
    86	        }
    87	        compose.onNodeWithText("Auto-turn pages", useUnmergedTree = true).assertExists()
    88	        // The switch reflects on=true.
    89	        compose.onNodeWithTag("more-row-toggle-auto_turn", useUnmergedTree = true).assertIsOn()
    90	        // Tapping the row toggles it.
    91	        compose.onNodeWithTag("more-row-auto_turn", useUnmergedTree = true).performClick()
    92	        assertTrue(toggledTo == false)
    93	    }
    94	
    95	    @Test fun suppliedToggleRowReflectsOffState() {
    96	        compose.setContent {
    97	            MorePopup(
    98	                theme = ReaderTheme.Paper,
    99	                rows = listOf(
   100	                    MoreRow.Toggle(
   101	                        id = MoreActionId.AUTO_TURN, label = "Auto-turn pages", icon = Icons.Outlined.Timer,
   102	                        sub = "Off", on = false, onToggle = {},
   103	                    ),
   104	                ),
   105	                onDismiss = {},
   106	            )
   107	        }
   108	        compose.onNodeWithTag("more-row-toggle-auto_turn", useUnmergedTree = true).assertIsOff()
   109	    }
   110	
   111	    @Test fun disabledRowRendersNonInteractiveWithSubText() {
   112	        var tapped = false
   113	        compose.setContent {
   114	            MorePopup(
   115	                theme = ReaderTheme.Paper,
   116	                rows = listOf(
   117	                    MoreRow.Disabled(
   118	                        id = MoreActionId.BILINGUAL, label = "Bilingual mode", icon = Icons.Outlined.Translate,
   119	                        sub = "Configure AI provider first", onTap = { tapped = true },
   120	                    ),
   121	                ),
   122	                onDismiss = {},
   123	            )
   124	        }
   125	        compose.onNodeWithText("Bilingual mode", useUnmergedTree = true).assertExists()
   126	        compose.onNodeWithText("Configure AI provider first", useUnmergedTree = true).assertExists()
   127	        // A disabled row is non-interactive: clicking it does nothing (no crash, callback not fired).
   128	        compose.onNodeWithTag("more-row-bilingual", useUnmergedTree = true).performClick()
   129	        assertFalse(tapped)
   130	    }
   131	
   132	    @Test fun unsuppliedIdsAreAbsent_noDeadTtsAutoTurnBilingual() {
   133	        // Only DETAILS + SHARE supplied → TTS / Auto-turn / Bilingual rows are ABSENT (§more-row-ownership).
   134	        compose.setContent {
   135	            MorePopup(theme = ReaderTheme.Paper, rows = listOf(detailsRow(), shareRow()), onDismiss = {})
   136	        }
   137	        compose.onAllNodesWithTag("more-row-tts", useUnmergedTree = true).assertCountEquals(0)
   138	        compose.onAllNodesWithTag("more-row-auto_turn", useUnmergedTree = true).assertCountEquals(0)
   139	        compose.onAllNodesWithTag("more-row-bilingual", useUnmergedTree = true).assertCountEquals(0)
   140	        compose.onNodeWithText("Read aloud", useUnmergedTree = true).assertDoesNotExist()
   141	        compose.onNodeWithText("Auto-turn pages", useUnmergedTree = true).assertDoesNotExist()
   142	        compose.onNodeWithText("Bilingual mode", useUnmergedTree = true).assertDoesNotExist()
   143	    }
   144	
   145	    @Test fun exportRowNeverPresent() {
   146	        // #134 has no export subsystem — the Export row is never rendered, even by absence there is no
   147	        // MoreActionId for it. Assert by label + that no export row is present.
   148	        compose.setContent {
   149	            MorePopup(theme = ReaderTheme.Paper, rows = listOf(detailsRow(), shareRow()), onDismiss = {})
   150	        }
   151	        compose.onNodeWithText("Export annotations", useUnmergedTree = true).assertDoesNotExist()
   152	        compose.onAllNodesWithTag("more-row-export", useUnmergedTree = true).assertCountEquals(0)
   153	    }
   154	
   155	    @Test fun backdropTapDismisses() {
   156	        var dismissed = false
   157	        compose.setContent {
   158	            MorePopup(theme = ReaderTheme.Paper, rows = listOf(detailsRow()), onDismiss = { dismissed = true })
   159	        }
   160	        compose.onNodeWithTag("more-backdrop", useUnmergedTree = true).assertHasClickAction().performClick()
   161	        assertTrue(dismissed)
   162	    }
   163	
   164	    @Test fun rendersUnderRtlLayout() {
   165	        // The popup anchors to the trailing edge; under RTL it still renders (Compose flips automatically).
   166	        compose.setContent {
   167	            CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
   168	                MorePopup(theme = ReaderTheme.Paper, rows = listOf(detailsRow(), shareRow()), onDismiss = {})
   169	            }
   170	        }
   171	        compose.onNodeWithTag("more-popup", useUnmergedTree = true).assertExists()
   172	        compose.onNodeWithText("Book details", useUnmergedTree = true).assertExists()
   173	    }
   174	
   175	    @Test fun rendersAcrossThemes() {
   176	        // The popup is a pure function of the theme tokens — it renders in every theme (light + dark).
   177	        // AndroidComposeTestRule.setContent may be called only ONCE per test; drive the theme via
   178	        // state across a single content tree instead of looping setContent (which throws
   179	        // "has already set content").
   180	        val theme = androidx.compose.runtime.mutableStateOf(ReaderTheme.values().first())
   181	        compose.setContent {
   182	            MorePopup(theme = theme.value, rows = listOf(detailsRow(), shareRow()), onDismiss = {})
   183	        }
   184	        for (t in ReaderTheme.values()) {
   185	            theme.value = t
   186	            compose.onNodeWithTag("more-popup", useUnmergedTree = true).assertExists()
   187	        }
   188	    }
   189	
   190	    @Test fun emptyRowsRendersEmptyPopupWithoutCrash() {
   191	        // Degenerate case: no supplied rows → the popup surface exists but has no rows (no crash).
   192	        compose.setContent {
   193	            MorePopup(theme = ReaderTheme.Paper, rows = emptyList(), onDismiss = {})
   194	        }
   195	        compose.onNodeWithTag("more-popup", useUnmergedTree = true).assertExists()
   196	    }
   197	}

exec
/bin/zsh -lc "nl -ba android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt | sed -n '38,78p'
nl -ba android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt | tail -n 100
nl -ba android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt | sed -n '600,700p'
nl -ba android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt | sed -n '835,900p'
nl -ba android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt | sed -n '390,450p'
nl -ba android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt | sed -n '440,490p'" in /Users/ll/workspace/vreader
 succeeded in 0ms:
    38	import com.vreader.app.backup.GroupHeader
    39	import com.vreader.app.backup.LocalBackupTokens
    40	import com.vreader.app.backup.NavScreen
    41	import com.vreader.app.backup.SettingsCard
    42	import com.vreader.app.backup.StatusDot
    43	import com.vreader.app.backup.VSpace
    44	
    45	@Composable
    46	fun AiProviderListScreen(
    47	    state: AiProviderListState,
    48	    onBack: () -> Unit = {},
    49	    onAdd: () -> Unit = {},
    50	    onEdit: (String) -> Unit = {},
    51	) {
    52	    val t = LocalBackupTokens.current
    53	    val addButton: @Composable () -> Unit = {
    54	        Box(
    55	            Modifier.size(44.dp).clip(RoundedCornerShape(22.dp)).clickable(onClickLabel = "Add provider", onClick = onAdd),
    56	            contentAlignment = Alignment.Center,
    57	        ) { Icon(Icons.Filled.Add, contentDescription = "Add provider", tint = t.tint, modifier = Modifier.size(22.dp)) }
    58	    }
    59	    NavScreen(title = "AI Providers", large = true, onBack = onBack, trailing = addButton) {
    60	        Column(Modifier.padding(horizontal = 18.dp).padding(bottom = 32.dp)) {
    61	            if (state.unconfigured) {
    62	                AiEmptyState(onAdd)
    63	            } else {
    64	                GroupHeader("Providers")
    65	                SettingsCard {
    66	                    state.providers.forEachIndexed { i, p ->
    67	                        ProviderRow(p, last = i == state.providers.lastIndex, onEdit = onEdit)
    68	                    }
    69	                }
    70	                GroupFooter("The selected provider is used for translation, chat, and summaries. Tap one to edit or test it.")
    71	            }
    72	        }
    73	    }
    74	}
    75	
    76	@Composable
    77	private fun AiEmptyState(onAdd: () -> Unit) {
    78	    val t = LocalBackupTokens.current
   181	            hasOccurrence = { true },
   182	            recentsFlow = recentSearchesStore.recents(),
   183	            recordQuery = { q -> recentSearchesStore.record(q) },
   184	            dispatcher = Dispatchers.Default,
   185	            coroutineScope = coroutineScope,
   186	        )
   187	    }
   188	
   189	    /**
   190	     * feature #133 WI-11 — the per-reader-session in-book-search ViewModel for the EPUB host. EPUB search does
   191	     * NOT use the #128 FTS index at all (a chunk-level, location-less index cannot yield a jumpable position);
   192	     * instead the WI-6 [InBookSearchRepository]'s EPUB branch runs Readium's OWN `SearchService` over the LIVE
   193	     * [publication] via the WI-5 [EpubInBookSearchEngine] production constructor (which wraps the real
   194	     * publication behind the `PublicationSearchSource` seam), returning navigable Readium `Locator`s the host
   195	     * jumps to with `navigator.go`.
   196	     *
   197	     * EPUB bypasses the WI-7 index-state gate entirely: the [indexStateFlow] emits `null` (missing) and
   198	     * [hasOccurrence] reports Ready, so the gate resolves to Ready and the engine's own `isSearchable` probe
   199	     * is the real capability check (an un-searchable publication → the repository's [InBookSearchOutcome.Unsupported]
   200	     * → the WI-8 VM's `hidesSearchEntry`, so the host omits the Search icon). The TXT/MD FTS branch is NEVER
   201	     * invoked for an EPUB host, so its factories are error-throwing guards (a call would be a wiring bug).
   202	     *
   203	     * ONE [InBookSearchRepository] per session (so the live Readium `SearchIterator` behind
   204	     * `SearchCursor.Epub` is held once and disposed via `closeAllEpubCursors` on dismiss / `onCleared`).
   205	     * [coroutineScope] is the host's `lifecycleScope` in production (the VM cancels its child collectors on
   206	     * `onCleared`).
   207	     */
   208	    fun epubInBookSearchViewModel(
   209	        bookKey: String,
   210	        publication: org.readium.r2.shared.publication.Publication,
   211	        coroutineScope: CoroutineScope,
   212	    ): com.vreader.app.search.InBookSearchViewModel {
   213	        val repository = com.vreader.app.search.InBookSearchRepository(
   214	            dispatcher = Dispatchers.Default,
   215	            // The EPUB host never reaches the FTS branch (the repository dispatches only the EPUB branch for
   216	            // `epub`), so the TXT/MD deps are error-throwing guards — a call here is a wiring bug, fail fast.
   217	            fts = com.vreader.app.search.InBookFtsDeps(
   218	                matchingChunksPage = { _, _, _, _, _ -> error("FTS matchingChunksPage requested on an EPUB host") },
   219	                chunkAtOrAfter = { _, _, _, _ -> error("FTS chunkAtOrAfter requested on an EPUB host") },
   220	                resolverFor = { error("FTS resolver requested on an EPUB host") },
   221	            ),
   222	            // The LIVE wiring: build the WI-5 engine over the real Readium publication (its production
   223	            // constructor wraps the publication behind the `PublicationSearchSource` seam). One engine per
   224	            // repository/session; the repository memoizes it per bookKey.
   225	            epubEngineFor = { com.vreader.app.search.EpubInBookSearchEngine(publication) },
   226	        )
   227	        return com.vreader.app.search.InBookSearchViewModel(
   228	            bookKey = bookKey,
   229	            format = BookFormat.epub,
   230	            searcher = repository.asSearcher(),
   231	            indexStateGate = com.vreader.app.search.IndexStateGate(Dispatchers.Default),
   232	            // EPUB bypasses the FTS index-state gate: a `null` (missing) row + `hasOccurrence == true` resolve
   233	            // the gate to Ready, so the engine's own `isSearchable` probe is the capability check.
   234	            indexStateFlow = kotlinx.coroutines.flow.flowOf(null),
   235	            hasOccurrence = { true },
   236	            recentsFlow = recentSearchesStore.recents(),
   237	            recordQuery = { q -> recentSearchesStore.record(q) },
   238	            dispatcher = Dispatchers.Default,
   239	            coroutineScope = coroutineScope,
   240	        )
   241	    }
   242	
   243	    /** Builds a [com.vreader.app.search.SearchViewModel] wired to the live library, in-text repository,
   244	     *  recents, collections, and the settled-completeness gate. */
   245	    fun searchViewModel(): com.vreader.app.search.SearchViewModel =
   246	        com.vreader.app.search.SearchViewModel(
   247	            libraryFlow = repository.observeLibrary(),
   248	            textHitsFor = { q -> searchRepository.textHits(q) },
   249	            recentsFlow = recentSearchesStore.recents(),
   250	            collectionsFlow = collectionRepository.observeCollections(),
   251	            indexCompleteFlow = database.searchDao().observeUnsettledIndexableCount()
   252	                .map { it == 0 },
   253	            recordQuery = { q -> recentSearchesStore.record(q) },
   254	        )
   255	
   256	    /** In-memory last reading char-offset per fingerprintKey. Written synchronously on
   257	     *  save so a fast rotation / reopen restores the LATEST position without waiting for
   258	     *  the async Room write to commit; Room remains the durable store across process death. */
   259	    private val lastOffsets = java.util.concurrent.ConcurrentHashMap<String, Int>()
   260	    fun cacheOffset(fingerprintKey: String, charOffsetUtf16: Int) { lastOffsets[fingerprintKey] = charOffsetUtf16 }
   261	    fun cachedOffset(fingerprintKey: String): Int? = lastOffsets[fingerprintKey]
   262	
   263	    /** In-memory last PDF page index per fingerprintKey — a TYPED cache distinct from the
   264	     *  char-offset one (feature #115; a PDF position is a page, not a UTF-16 offset). */
   265	    private val lastPages = java.util.concurrent.ConcurrentHashMap<String, Int>()
   266	    fun cachePage(fingerprintKey: String, page: Int) { lastPages[fingerprintKey] = page }
   267	    fun cachedPage(fingerprintKey: String): Int? = lastPages[fingerprintKey]
   268	}
   269	
   270	class VReaderApp : Application() {
   271	    lateinit var container: AppContainer
   272	        private set
   273	
   274	    override fun onCreate() {
   275	        super.onCreate()
   276	        container = AppContainer(this)
   277	        // feature #128 WI-5 — eagerly start the cross-book search-index collector (idempotent).
   278	        container.startSearchIndexing()
   279	    }
   280	}
   600	    /** feature #133 WI-11 — dismiss the in-book search sheet: run the VM's dismiss (invalidates the active
   601	     *  session + disposes the live Readium SearchIterator via closeAllEpubCursors — no leak) then hide it. */
   602	    private fun dismissInBookSearch() {
   603	        inBookSearchVm?.onDismiss()
   604	        showSearchSheet.value = false
   605	    }
   606	
   607	    private suspend fun persist(locator: Locator, current: Book) {
   608	        val envelope = runCatching {
   609	            bridge.toEnvelope(
   610	                readiumLocatorJSON = locator.toJSON().toString(),
   611	                bookContentSHA256 = current.contentSHA256,
   612	                bookFileByteCount = current.fileByteCount,
   613	                bookFormat = current.originalFormat,
   614	            )
   615	        }.getOrNull() ?: return
   616	        repository.savePosition(envelope, System.currentTimeMillis())
   617	    }
   618	
   619	    /** feature #132 WI-7-EPUB — the full reader nav chrome over the Readium fragment. Because the reader
   620	     *  body is a View (EpubNavigatorFragment), NOT a composable, the chrome cannot use the Compose-native
   621	     *  ReaderChromeScaffold. Instead a single root FrameLayout stacks, bottom-to-top:
   622	     *    1. the fragment container — MATCH_PARENT (the reading area fills the WHOLE screen, under the bands);
   623	     *    2. the selection-popover overlay — MATCH_PARENT (unchanged; renders nothing unless a selection);
   624	     *    3. the sheet layer — MATCH_PARENT but EMPTY until a sheet opens (so it's touch-through: the
   625	     *       fragment keeps scroll/selection/link input whenever no sheet is up), then a full-screen dismiss
   626	     *       overlay + the Contents/Notes ModalBottomSheet;
   627	     *    4. the top band — WRAP_CONTENT, gravity TOP (covers only the top chrome strip);
   628	     *    5. the bottom band — WRAP_CONTENT, gravity BOTTOM (covers only the bottom chrome strip).
   629	     *  The two bands sit ON TOP of the fragment but occupy only their own height, so the reading area
   630	     *  between them stays the fragment's — touch-through by construction. */
   631	    private fun buildChrome(): View {
   632	        val root = FrameLayout(this).apply { setBackgroundColor(chromeTheme.value.background.toArgb()) }
   633	
   634	        val frame = FrameLayout(this).apply { id = View.generateViewId() }
   635	        containerId = frame.id
   636	
   637	        val popoverOverlay = ComposeView(this).apply { setContent { PopoverOverlay() } }
   638	        val sheetLayer = ComposeView(this).apply {
   639	            setContent {
   640	                EpubReaderSheets(
   641	                    model = chromeModel,
   642	                    theme = chromeTheme.value,
   643	                    chromeState = chromeState,
   644	                    onJumpToc = ::jumpToTocEntry,
   645	                    onShareAnnotations = { shareAnnotations(chromeModel.value.annotations) },
   646	                    // feature #134 WI-5 — the Book Details route + its Share / copy-fingerprint actions.
   647	                    bookDetails = chromeBookDetails.value,
   648	                    onShareBook = ::shareBookFile,
   649	                    onCopyFingerprint = ::copyFingerprint,
   650	                    // feature #135 WI-7 — the Bookmarks-tab rows + the per-bookmark jump (canonical → Readium).
   651	                    bookmarks = bookmarkRows.value,
   652	                    onJumpBookmark = ::jumpToBookmark,
   653	                )
   654	                // feature #133 WI-11 — the in-book search sheet renders in the SAME sheet-layer ComposeView
   655	                // (open-only, so it does not cover the fragment while closed → touch-through preserved). It is
   656	                // a ModalBottomSheet (its own window), driven by the per-session VM's live Readium search;
   657	                // tapping a hit → jumpToSearchHit (Locator.fromJSON → nav.go), dismiss disposes the iterator.
   658	                InBookSearchLayer()
   659	            }
   660	        }
   661	        val topBand = ComposeView(this).apply {
   662	            setContent {
   663	                // feature #133 WI-11 — the Search icon is shown UNLESS the VM reports the entry is hidden (a
   664	                // non-searchable publication → Unsupported → hidesSearchEntry). A null onSearch omits the icon
   665	                // (no dead control). feature #134 WI-5 — the top-bar More button (shown once chromeBookDetails
   666	                // is populated) toggles the More popup; Details writes ReaderSheet.Details, Share launches share.
   667	                val searchState = inBookSearchState.value
   668	                val onSearch: (() -> Unit)? =
   669	                    if (searchState != null && !searchState.hidesSearchEntry) ({ showSearchSheet.value = true }) else null
   670	                EpubTopBand(
   671	                    model = chromeModel,
   672	                    theme = chromeTheme.value,
   673	                    onBack = { finish() },
   674	                    chromeState = chromeState,
   675	                    bookDetails = chromeBookDetails.value,
   676	                    onShareBook = ::shareBookFile,
   677	                    onSearch = onSearch,
   678	                    // feature #135 WI-7 — the top-bar bookmark toggle (filled/outline by presence).
   679	                    isCurrentBookmarked = isCurrentBookmarked.value,
   680	                    onToggleBookmark = ::toggleCurrentBookmark,
   681	                )
   682	            }
   683	        }
   684	        val bottomBand = ComposeView(this).apply {
   685	            setContent {
   686	                DisplaySettingsHost {
   687	                    EpubBottomBand(
   688	                        model = chromeModel,
   689	                        theme = chromeTheme.value,
   690	                        chromeState = chromeState,
   691	                        progress = chromeProgress.value,
   692	                        onScrub = ::scrubTo,
   693	                        onOpenDisplay = { showDisplaySheet.value = true },
   694	                    )
   695	                }
   696	            }
   697	        }
   698	
   699	        val match = FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)
   700	        root.addView(frame, FrameLayout.LayoutParams(match))
   835	    annotations: AnnotationsSnapshot,
   836	    onBack: () -> Unit,
   837	    onJumpToAnnotation: (AnnotationItem) -> Unit,
   838	    onShareAnnotations: () -> Unit,
   839	    bottomBar: @Composable (Pair<(() -> Unit)?, (() -> Unit)?>) -> Unit,
   840	    body: @Composable () -> Unit,
   841	    // feature #133 WI-10 — the in-book Search entry + sheet overlay (nullable/default so #132/#134/#135
   842	    // callers stay valid). A null [onOpenSearch] omits the top-bar Search icon (Unsupported / no-dead-control).
   843	    onOpenSearch: (() -> Unit)? = null,
   844	    searchSheet: (@Composable () -> Unit)? = null,
   845	    // feature #134 WI-5 — the More menu's Book-details model + Share/copy actions (null model → no More).
   846	    bookDetails: com.vreader.app.reader.details.BookDetailsUiModel? = null,
   847	    onShareBook: () -> Unit = {},
   848	    onCopyFingerprint: (String) -> Unit = {},
   849	    // feature #135 WI-7 — the top-bar bookmark toggle + Bookmarks-tab rows + TXT/MD jump (all nullable/default
   850	    // so #132/#134 callers stay valid). TXT supplies a preview provider (the Bookmarks-tab snippet).
   851	    isCurrentBookmarked: Boolean = false,
   852	    onToggleBookmark: (() -> Unit)? = null,
   853	    currentLocator: vreader.contracts.Locator? = null,
   854	    bookmarks: List<BookmarkRowItem> = emptyList(),
   855	    onJumpBookmark: ((BookmarkRecord) -> JumpResult)? = null,
   856	) {
   857	    Column(Modifier.fillMaxSize().background(theme.background).systemBarsPadding()) {
   858	        ReaderChromeScaffold(
   859	            theme = theme,
   860	            title = title,
   861	            chromeState = chromeState,
   862	            onBack = onBack,
   863	            tocEntries = emptyList(),           // no TOC → the scaffold hides the Contents control
   864	            currentTocIndex = 0,
   865	            annotations = annotations,
   866	            onJumpToc = { false },              // unreachable: Contents is hidden with an empty TOC
   867	            onJumpToAnnotation = onJumpToAnnotation,
   868	            onShareAnnotations = onShareAnnotations,
   869	            // feature #133 WI-10 — the top-bar Search slot is now WIRED (the scaffold forwards it to
   870	            // ReaderTopChrome(onSearch=…)). A null [onOpenSearch] omits the icon (Unsupported / no-dead-
   871	            // control). feature #134 WI-5: the More button + Book Details / Share ride the scaffold's More menu.
   872	            onOpenSearch = onOpenSearch,
   873	            bottomChrome = { onOpenContents, onOpenNotes -> bottomBar(onOpenContents to onOpenNotes) },
   874	            body = body,
   875	            bookDetails = bookDetails,
   876	            onShareBook = onShareBook,
   877	            onCopyFingerprint = onCopyFingerprint,
   878	            // feature #135 WI-7 — the bookmark toggle + Bookmarks tab, now lit up for TXT/MD.
   879	            isCurrentBookmarked = isCurrentBookmarked,
   880	            onToggleBookmark = onToggleBookmark,
   881	            currentLocator = currentLocator,
   882	            bookmarks = bookmarks,
   883	            onJumpBookmark = onJumpBookmark,
   884	        )
   885	    }
   886	    // feature #133 WI-10 — the in-book search sheet overlay (a ModalBottomSheet; the host renders it when
   887	    // its search-open state is set). Layered outside the chrome Column so it covers the full reader.
   888	    searchSheet?.invoke()
   889	}
   890	
   891	// ---- feature #135 WI-7 — TXT/MD pure host wiring helpers ----
   892	
   893	/**
   894	 * feature #135 WI-7 — the current TXT/MD reading position (a top-visible char offset) as a plain canonical
   895	 * [vreader.contracts.Locator] (the bookmark equality basis + create/jump anchor). Mirrors the host's
   896	 * save-position construction (identity triple + `charOffsetUTF16`), so a bookmark's position lines up with
   897	 * the resume seam. Pure/JVM-testable.
   898	 */
   899	fun txtBookmarkLocator(book: com.vreader.app.data.Book, charOffsetUTF16: Int): vreader.contracts.Locator =
   900	    vreader.contracts.Locator(
   440	    chromeState: MutableState<ReaderChromeState>,
   441	    annotations: AnnotationsSnapshot,
   442	    onBack: () -> Unit,
   443	    onShareAnnotations: () -> Unit,
   444	    body: @Composable () -> Unit,
   445	    // feature #134 WI-5 — the More menu's Book-details model + Share/copy actions (null model → no More).
   446	    bookDetails: com.vreader.app.reader.details.BookDetailsUiModel? = null,
   447	    onShareBook: () -> Unit = {},
   448	    onCopyFingerprint: (String) -> Unit = {},
   449	    // feature #135 WI-7 — the top-bar bookmark toggle + Bookmarks-tab rows + AZW3 jump (all nullable/default
   450	    // so #132/#134 callers stay valid). A non-null onToggleBookmark fills the toggle; onJumpBookmark makes
   451	    // the Bookmarks-tab rows clickable + dismiss-on-Succeeded (null → review-only rows).
   452	    isCurrentBookmarked: Boolean = false,
   453	    onToggleBookmark: (() -> Unit)? = null,
   454	    currentLocator: Locator? = null,
   455	    bookmarks: List<BookmarkRowItem> = emptyList(),
   456	    onJumpBookmark: ((BookmarkRecord) -> JumpResult)? = null,
   457	) {
   458	    Column(Modifier.fillMaxSize().background(theme.background).systemBarsPadding()) {
   459	        ReaderChromeScaffold(
   460	            theme = theme,
   461	            title = title,
   462	            chromeState = chromeState,
   463	            onBack = onBack,
   464	            tocEntries = emptyList(),           // no TOC → the scaffold hides the Contents control
   465	            currentTocIndex = 0,
   466	            annotations = annotations,
   467	            onJumpToc = { false },              // unreachable: Contents is hidden with an empty TOC
   468	            // AZW3 tap-to-jump is NULL — review-only capability gate (no goTo until #135); cards non-clickable.
   469	            onJumpToAnnotation = null,
   470	            onShareAnnotations = onShareAnnotations,
   471	            // Search top-bar slot stays null (#133 — no dead control). feature #134 WI-5:
   472	            // the More button + Book Details / Share are wired through the scaffold's More menu below.
   473	            bottomChrome = { _, onOpenNotes ->
   474	                // AZW3 has no Contents (empty TOC) + no Display control → Notes only.
   475	                Azw3NotesBottomChrome(theme = theme, onOpenNotes = onOpenNotes)
   476	            },
   477	            body = body,
   478	            bookDetails = bookDetails,
   479	            onShareBook = onShareBook,
   480	            onCopyFingerprint = onCopyFingerprint,
   481	            // feature #135 WI-7 — the bookmark toggle + Bookmarks tab, now lit up for AZW3.
   482	            isCurrentBookmarked = isCurrentBookmarked,
   483	            onToggleBookmark = onToggleBookmark,
   484	            currentLocator = currentLocator,
   485	            bookmarks = bookmarks,
   486	            onJumpBookmark = onJumpBookmark,
   487	        )
   488	    }
   489	}
   490	

codex
## Critical

None. The plan’s core premise is correct:

- All named AI types exist: [AiProviderStore.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:41), [AiSettingsViewModel.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsViewModel.kt:20), [AiProviderListScreen.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt:46), and [AiProviderEditSheet.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderEditSheet.kt:55).
- `AppContainer` exists, but constructs no `AiProviderStore`; its only current mention is a precedent comment at [VReaderApp.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:64).
- Production navigation is Activity-based, with books launched using `startActivity`; there is no `NavHost` route to the provider UI at [MainActivity.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/MainActivity.kt:76).
- Direct calls to `AiProviderListScreen` and `AiProviderEditSheet` occur only in `androidTest`. `AiSettingsViewModel` and `AiProviderStore` are likewise not constructed by production wiring.
- `readerMoreRows`, `MoreActionId.BILINGUAL`, and `MoreRow.Disabled` exist at [ReaderChromeScaffold.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderChromeScaffold.kt:255) and [MoreRow.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/more/MoreRow.kt:19).

## High

1. Rule 51 blocker: the proposed tappable “disabled” More row contradicts the cited design.

   The plan claims `disabled` plus an `on` callback depicts a dimmed-but-tappable row at [plan](/Users/ll/workspace/vreader/dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md:101). In the actual JSX, however, `disabled` explicitly suppresses the callback via `onClick={disabled ? undefined : on}` at [vreader-more.jsx](/Users/ll/workspace/vreader/dev-docs/designs/vreader-fidelity-v1/project/vreader-more.jsx:16). Current Kotlin faithfully implements that behavior at [MorePopup.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/more/MorePopup.kt:142), and the connected test expressly requires no callback at [MorePopupTest.kt](/Users/ll/workspace/vreader/android/app/src/androidTest/kotlin/com/vreader/app/reader/more/MorePopupTest.kt:111).

   Making `MoreRow.Disabled` interactive is therefore a new, undesigned interaction state, not a restoration to design.

2. Rule 51 blocker: the direct More → generic provider screen is not Variant A as depicted.

   Variant A is specifically a push inside the bilingual sheet, with a `‹ Bilingual` back control, bilingual-context content, selection semantics, and return to Bilingual after save: [reader-ai-provider-entry.md](/Users/ll/workspace/vreader/dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:39), [vreader-ai-provider-entry.jsx](/Users/ll/workspace/vreader/dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx:27), and [vreader-ai-provider-entry.jsx](/Users/ll/workspace/vreader/dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx:245).

   The plan instead opens `ReaderSheet.AiProviders` directly from More, renders the generic full-screen Android `AiProviderListScreen`, and closes back to the reader at [plan](/Users/ll/workspace/vreader/dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md:21) and [plan](/Users/ll/workspace/vreader/dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md:32). The reused screen has generic copy and only `onBack/onAdd/onEdit`, not Variant A’s bilingual-context selection contract, at [AiProviderListScreen.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt:46).

   Thus the proposed standalone in-reader sheet is not actually depicted by the cited Variant A bundle.

3. The `aiUnavailable` predicate is materially wrong.

   WI-3 derives availability solely from `profiles.isEmpty()` at [plan](/Users/ll/workspace/vreader/dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md:33). The live model separately stores `activeId`, and `active` can be null even with profiles present at [AiProviderStore.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:33). API-key usability additionally depends on successfully decrypting the active profile’s token at [AiProviderStore.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:105).

   Consequently, an orphaned/unknown `activeId`, blank token, corrupt token, or invalidated keystore key would hide the configuration entry while AI remains unusable. The plan needs a single readiness definition covering an active profile plus a non-empty, decryptable key, with explicit failure behavior.

4. Keystore and DataStore failures are not handled despite becoming production-reachable.

   `KeystoreSecretCipher` can throw during keystore loading, key generation, Base64 decoding, GCM initialization, or authentication at [SecretCipher.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/backup/net/SecretCipher.kt:29). `AiSettingsViewModel.save()` performs `store.upsert` without catching failures at [AiSettingsViewModel.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsViewModel.kt:85), while `observe()` has no DataStore I/O recovery at [AiProviderStore.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:49).

   The plan explicitly declares crypto/CRUD untouched and supplies no failure-state contract or tests at [plan](/Users/ll/workspace/vreader/dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md:44). Production wiring can therefore surface uncaught save failures or permanently cancel UI collection. Error presentation may itself require design authority.

## Medium

1. The planned JVM `AppContainerAiWiringTest` cannot exercise the stated real upsert path as written.

   The test proposes constructing the production container and performing `upsert` at [plan](/Users/ll/workspace/vreader/dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md:87). The production cipher explicitly cannot be unit-tested under Robolectric because AndroidKeyStore is unavailable at [SecretCipher.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/backup/net/SecretCipher.kt:24). The plan needs an injected cipher/DataStore seam or must move the real-container encryption assertion to instrumentation.

2. Process-death behavior is inaccurately specified.

   Only `ReaderSheet` is persisted by the saver at [ReaderChromeState.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderChromeState.kt:63). Editor state is a plain `MutableStateFlow`, not `SavedStateHandle` state, at [AiSettingsViewModel.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsViewModel.kt:36). After process death during editing, `ReaderSheet.AiProviders` can restore, but the editor will be closed and the list displayed; it will not “re-open empty” as claimed at [plan](/Users/ll/workspace/vreader/dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md:103). The plan should state and test the exact intended fallback.

3. The keystore alias is underspecified.

   WI-1 uses `KeystoreSecretCipher(<alias>)` without naming a stable, AI-specific alias at [plan](/Users/ll/workspace/vreader/dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md:29). Omitting it would silently use the WebDAV default alias, `vreader.webdav.password`, at [SecretCipher.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/backup/net/SecretCipher.kt:63). The plan should pin a distinct constant such as `vreader.ai.api-key` and test it on-device.

4. WI-3 needs explicit serialization against #131.

   WI-3 modifies the shared More assembler, popup treatment, EPUB chrome, scaffold, and every Activity family at [plan](/Users/ll/workspace/vreader/dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md:79). Those are also the exact integration seams #131 will modify. The dependency statement correctly blocks #131 conceptually, but the write-isolation plan should explicitly forbid concurrent implementation of #131’s chrome WI until #136 WI-3 merges.

## Low

1. The host count is imprecise.

   The plan repeatedly says “five host Activities” but names four Activity classes at [plan](/Users/ll/workspace/vreader/dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md:33). There are five formats because TXT and Markdown share `TxtReaderActivity`, as shown at [MainActivity.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/MainActivity.kt:83). The write set is four Activities plus the shared EPUB/scaffold chrome files.

2. The three-WI split is otherwise cohesive.

   WI-1 is genuinely foundational: lazy construction alone has no visible behavior. WI-2 and WI-3 are appropriately behavioral. DataStore’s atomic edits and snapshot-based request API are sound concurrency foundations at [AiProviderStore.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:46) and [AiProviderStore.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:70). The split should remain three WIs after resolving design, readiness, and failure handling.

FINAL VERDICT: block-recommended
tokens used
120,709
## Critical

None. The plan’s core premise is correct:

- All named AI types exist: [AiProviderStore.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:41), [AiSettingsViewModel.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsViewModel.kt:20), [AiProviderListScreen.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt:46), and [AiProviderEditSheet.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderEditSheet.kt:55).
- `AppContainer` exists, but constructs no `AiProviderStore`; its only current mention is a precedent comment at [VReaderApp.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt:64).
- Production navigation is Activity-based, with books launched using `startActivity`; there is no `NavHost` route to the provider UI at [MainActivity.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/MainActivity.kt:76).
- Direct calls to `AiProviderListScreen` and `AiProviderEditSheet` occur only in `androidTest`. `AiSettingsViewModel` and `AiProviderStore` are likewise not constructed by production wiring.
- `readerMoreRows`, `MoreActionId.BILINGUAL`, and `MoreRow.Disabled` exist at [ReaderChromeScaffold.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderChromeScaffold.kt:255) and [MoreRow.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/more/MoreRow.kt:19).

## High

1. Rule 51 blocker: the proposed tappable “disabled” More row contradicts the cited design.

   The plan claims `disabled` plus an `on` callback depicts a dimmed-but-tappable row at [plan](/Users/ll/workspace/vreader/dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md:101). In the actual JSX, however, `disabled` explicitly suppresses the callback via `onClick={disabled ? undefined : on}` at [vreader-more.jsx](/Users/ll/workspace/vreader/dev-docs/designs/vreader-fidelity-v1/project/vreader-more.jsx:16). Current Kotlin faithfully implements that behavior at [MorePopup.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/more/MorePopup.kt:142), and the connected test expressly requires no callback at [MorePopupTest.kt](/Users/ll/workspace/vreader/android/app/src/androidTest/kotlin/com/vreader/app/reader/more/MorePopupTest.kt:111).

   Making `MoreRow.Disabled` interactive is therefore a new, undesigned interaction state, not a restoration to design.

2. Rule 51 blocker: the direct More → generic provider screen is not Variant A as depicted.

   Variant A is specifically a push inside the bilingual sheet, with a `‹ Bilingual` back control, bilingual-context content, selection semantics, and return to Bilingual after save: [reader-ai-provider-entry.md](/Users/ll/workspace/vreader/dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md:39), [vreader-ai-provider-entry.jsx](/Users/ll/workspace/vreader/dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx:27), and [vreader-ai-provider-entry.jsx](/Users/ll/workspace/vreader/dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx:245).

   The plan instead opens `ReaderSheet.AiProviders` directly from More, renders the generic full-screen Android `AiProviderListScreen`, and closes back to the reader at [plan](/Users/ll/workspace/vreader/dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md:21) and [plan](/Users/ll/workspace/vreader/dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md:32). The reused screen has generic copy and only `onBack/onAdd/onEdit`, not Variant A’s bilingual-context selection contract, at [AiProviderListScreen.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt:46).

   Thus the proposed standalone in-reader sheet is not actually depicted by the cited Variant A bundle.

3. The `aiUnavailable` predicate is materially wrong.

   WI-3 derives availability solely from `profiles.isEmpty()` at [plan](/Users/ll/workspace/vreader/dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md:33). The live model separately stores `activeId`, and `active` can be null even with profiles present at [AiProviderStore.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:33). API-key usability additionally depends on successfully decrypting the active profile’s token at [AiProviderStore.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:105).

   Consequently, an orphaned/unknown `activeId`, blank token, corrupt token, or invalidated keystore key would hide the configuration entry while AI remains unusable. The plan needs a single readiness definition covering an active profile plus a non-empty, decryptable key, with explicit failure behavior.

4. Keystore and DataStore failures are not handled despite becoming production-reachable.

   `KeystoreSecretCipher` can throw during keystore loading, key generation, Base64 decoding, GCM initialization, or authentication at [SecretCipher.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/backup/net/SecretCipher.kt:29). `AiSettingsViewModel.save()` performs `store.upsert` without catching failures at [AiSettingsViewModel.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsViewModel.kt:85), while `observe()` has no DataStore I/O recovery at [AiProviderStore.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:49).

   The plan explicitly declares crypto/CRUD untouched and supplies no failure-state contract or tests at [plan](/Users/ll/workspace/vreader/dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md:44). Production wiring can therefore surface uncaught save failures or permanently cancel UI collection. Error presentation may itself require design authority.

## Medium

1. The planned JVM `AppContainerAiWiringTest` cannot exercise the stated real upsert path as written.

   The test proposes constructing the production container and performing `upsert` at [plan](/Users/ll/workspace/vreader/dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md:87). The production cipher explicitly cannot be unit-tested under Robolectric because AndroidKeyStore is unavailable at [SecretCipher.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/backup/net/SecretCipher.kt:24). The plan needs an injected cipher/DataStore seam or must move the real-container encryption assertion to instrumentation.

2. Process-death behavior is inaccurately specified.

   Only `ReaderSheet` is persisted by the saver at [ReaderChromeState.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderChromeState.kt:63). Editor state is a plain `MutableStateFlow`, not `SavedStateHandle` state, at [AiSettingsViewModel.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsViewModel.kt:36). After process death during editing, `ReaderSheet.AiProviders` can restore, but the editor will be closed and the list displayed; it will not “re-open empty” as claimed at [plan](/Users/ll/workspace/vreader/dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md:103). The plan should state and test the exact intended fallback.

3. The keystore alias is underspecified.

   WI-1 uses `KeystoreSecretCipher(<alias>)` without naming a stable, AI-specific alias at [plan](/Users/ll/workspace/vreader/dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md:29). Omitting it would silently use the WebDAV default alias, `vreader.webdav.password`, at [SecretCipher.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/backup/net/SecretCipher.kt:63). The plan should pin a distinct constant such as `vreader.ai.api-key` and test it on-device.

4. WI-3 needs explicit serialization against #131.

   WI-3 modifies the shared More assembler, popup treatment, EPUB chrome, scaffold, and every Activity family at [plan](/Users/ll/workspace/vreader/dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md:79). Those are also the exact integration seams #131 will modify. The dependency statement correctly blocks #131 conceptually, but the write-isolation plan should explicitly forbid concurrent implementation of #131’s chrome WI until #136 WI-3 merges.

## Low

1. The host count is imprecise.

   The plan repeatedly says “five host Activities” but names four Activity classes at [plan](/Users/ll/workspace/vreader/dev-docs/plans/20260712-feature-136-android-ai-provider-reachable.md:33). There are five formats because TXT and Markdown share `TxtReaderActivity`, as shown at [MainActivity.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/MainActivity.kt:83). The write set is four Activities plus the shared EPUB/scaffold chrome files.

2. The three-WI split is otherwise cohesive.

   WI-1 is genuinely foundational: lazy construction alone has no visible behavior. WI-2 and WI-3 are appropriately behavioral. DataStore’s atomic edits and snapshot-based request API are sound concurrency foundations at [AiProviderStore.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:46) and [AiProviderStore.kt](/Users/ll/workspace/vreader/android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt:70). The split should remain three WIs after resolving design, readiness, and failure handling.

FINAL VERDICT: block-recommended
