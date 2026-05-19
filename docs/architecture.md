# VReader Architecture

## Overview

VReader is an iOS e-book reader built with SwiftUI + SwiftData. It supports TXT, EPUB, AZW3/MOBI, PDF, and Markdown formats, each rendered by a format-specific native host (UIKit/WebView bridges) selected internally by `ReaderEngine` (feature #54). AZW3/MOBI is rendered via Foliate-js inside a WKWebView. The `UnifiedTextRenderer` (TextKit 2 reflow) stack is retained in the codebase but no longer wired into the reader dispatch.

## System Diagram

```
┌──────────────────────────────────────────────────────┐
│                    VReaderApp                         │
│  SwiftData SchemaV6 · PersistenceActor · BookImporter│
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

- `VReaderApp.swift` — SwiftData `ModelContainer` init (SchemaV6), migration plan (V1→V2→V3→V4→V5→V6), test seeding, error handling. Injects the live `PersistenceActor` into the SwiftUI environment via `\.persistenceActor` so settings sub-screens can construct backup providers without rewriting every parent's signature. Adopts `@UIApplicationDelegateAdaptor(VReaderAppDelegate.self)` for background-URLSession completion-handler delivery (feature #47).
- `VReaderAppDelegate.swift` — `UIApplicationDelegate` adapter that captures `application(_:handleEventsForBackgroundURLSession:completionHandler:)` into a MainActor-isolated static dictionary keyed by URLSession identifier. The lazy-download coordinator retrieves and invokes the handler from `LazyDownloadDelegate.urlSessionDidFinishEvents` so iOS releases the app's background-launch grace period.

### 2. Library Layer (`vreader/Views/LibraryView.swift`, `vreader/ViewModels/LibraryViewModel.swift`)

- Grid/list view with sort (persisted via `PreferenceStore`)
- Context menu: Info, Share, Set Cover, Add to Collection, Delete
- Collections sidebar, OPDS catalog, AI chat entry points
- Cover art (`BookCoverArtView`) renders a custom image when one exists, otherwise a generative typographic cover (Feature #60 WI-10 — `GenerativeCoverView`). The cover's style family + colour palette are deterministically derived from the book's `fingerprintKey` (FNV-1a hash → one of 5 style families × 12 design palettes in `GenerativeCoverStyle.swift`), so a given book always shows the same generated cover.

### 3. Reader Layer (`vreader/Views/Reader/`)

#### Dispatcher

`ReaderContainerView.swift` routes to format-specific readers via
`engineReaderView(fingerprint:)`, which switches on `ReaderEngine.resolve(format:)`
— an internal per-format engine selector (feature #54). The dispatch no
longer consults a reading-mode preference, and the reader-settings Reading
Mode picker UI is gone. (The `readerReadingMode` UserDefaults key + the
`ReadingMode` enum are removed in a later feature-#54 work item.)

- `.textNative` → `TXTReaderHost`, `.markdownNative` → `MDReaderHost`,
  `.epubWKWebView` → `EPUBReaderHost`, `.pdfKit` → `PDFReaderHost`,
  `.foliateWeb` → `FoliateSpikeView` (AZW3/MOBI; routes directly to
  `FoliateSpikeView`, not `FoliateReaderHost` — the host wrapper exists but
  isn't currently in the dispatch path).
- `resolve(format:)` maps `.epub` to `.epubWKWebView` unconditionally;
  feature #42 will later route EPUB to `.foliateWeb` behind a flag.

#### Chrome

Reader chrome (Feature #60 WI-6b — visual-identity-v2) is two custom overlays, floating on top of content with no safe-area impact:

- `ReaderTopChrome.swift` — top bar: `← Library | Title | Search Bookmark More`. Composed once in `ReaderContainerView`, format-agnostic. The `⋯` More button toggles `ReaderMorePopover`.
- `ReaderBottomChrome.swift` — bottom bar: progress scrubber + position labels + a Contents/Notes/Display/AI toolbar. Composed per paginated format (TXT/MD/EPUB/PDF), each passing its own seek closure; the toolbar posts `.readerOpen*` notifications that `ReaderContainerView` observes. Foliate (AZW3/MOBI) keeps its own bottom overlay.
- `ReaderMorePopover.swift` — anchored More-menu popover (Feature #60 WI-6c), composed in `ReaderContainerView`'s chrome overlay. Five rows (Read aloud / Auto-turn | Book details / Share / Export); each posts a `.readerMore*` notification that `ReaderContainerView` observes. The design's sixth row (Bilingual) is deferred — GH #790.

Slot/button identity lives in `ReaderChromeButton.swift` (`ReaderTopChromeSlot` / `ReaderBottomChromeButton`); More-menu row identity lives in `ReaderMoreMenuRow.swift`.

#### Sheets (Feature #60 WI-10 — visual-identity-v2)

The app sheets share `ReaderSheetChrome.swift` — a reusable wrapper matching the design's `Sheet` component: a theme-tinted surface (`ReaderThemeV2.sheetSurfaceColor`), an optional centred Source Serif 4 title bar with 50pt leading/trailing slots (a default circular close button fills the trailing slot when an `onClose` is given and no custom trailing view is), and a scrollable body. The slide-up animation + drag grabber come from SwiftUI's own `.sheet` + `.presentationDragIndicator(.visible)`; `ReaderSheetChrome` supplies only the title bar + surface tint. It wraps the Display sheet (`ReaderSettingsPanel`), the Annotations sheet (`AnnotationsPanelView`), the reader Book Details sheet (`BookDetailsSheet`, feature #61 — opened from More → Book details, with a trailing Share button in place of the default close), and the AI sheet (`AIReaderPanel`, `title: nil` + a custom sparkle header). `SettingsView` (App Settings) keeps an inner `NavigationStack` for its `NavigationLink` push destinations, with `ReaderSheetChrome` above it. The per-sheet section contract is pinned in `SheetSectionContract.swift` (`ReaderSheetKind`). Reader sheets pass the book's `ReaderThemeV2`; the App Settings sheet uses `.paper` (the Library is not theme-switchable).

`AnnotationsPanelView` is a pre-#60 unified 4-tab sheet (Contents / Bookmarks / Highlights / Notes); the design bundle depicts the TOC and highlights surfaces as two separate sheets, so WI-10 re-skinned the unified sheet's chrome only — splitting it to match the design's information architecture is tracked in GH #793 (`needs-design`).

`ReaderContainerView` drives `preferredColorScheme(_:)` from `ReaderThemeV2.preferredColorScheme` (`ReaderThemeV2+ColorScheme.swift`) so the status bar tints to match the theme — `.dark` for the Dark / OLED / Photo families, `.light` for Paper / Sepia.

#### Format Hosts (`ReaderFormatHosts.swift`)

Each host owns its ViewModel lifecycle via `@State`:

- `TXTReaderHost` → `TXTReaderContainerView` → `TXTTextViewBridge` (small) or `TXTChunkedReaderBridge` (>500K UTF-16)
- `EPUBReaderHost` → `EPUBReaderContainerView` → `EPUBWebViewBridge` (WKWebView + JS injection)
- `PDFReaderHost` → `PDFReaderContainerView` → `PDFViewBridge` (PDFKit)
- `MDReaderHost` → `MDReaderContainerView` → reuses `TXTTextViewBridge` with NSAttributedString
- AZW3/MOBI is dispatched directly to `FoliateSpikeView` (the AZW3 spike landed before the host abstraction; convergence is deferred). `FoliateReaderHost` / `FoliateReaderContainerView` exist but are not currently wired into `ReaderContainerView`.

#### Foliate-js Bridge (`vreader/Views/Reader/`, `vreader/Services/Foliate/`)

`FoliateViewBridge` (UIViewRepresentable) hosts a WKWebView and uses `loadHTMLString` with the IIFE-bundled `foliate-bundle.js` inlined; books are handed to JS as base64 (no scheme handler in the live load path — `FoliateURLSchemeHandler` exists in the codebase but isn't wired into the active bridge today). `FoliateViewCoordinator` (WKScriptMessageHandler + WKNavigationDelegate) receives JS messages, parses via `FoliateMessageParser`, and routes to typed callbacks. `FoliateHighlightRenderer` generates JS strings for SVG overlay annotations — but it is **not** plugged in as a `HighlightRenderer` adapter today; AZW3 highlight create has a TODO for persistence/JS injection and overlay restore is a no-op placeholder (`FoliateReaderContainerView+Highlights.swift`). `FoliateJSEscaper` provides shared sanitization for all JS/CSS string interpolation across the bridge. `FoliateReaderViewModel` maps bridge events to `Locator` for position persistence.

#### Unified Engine (retained, not dispatched)

`ReaderUnifiedCoordinator` loads text + applies transforms (replacement rules, simp/trad); `UnifiedTextRenderer` displays with TextKit 2 pagination or scroll. Feature #54 removed the unified path from the reader dispatch and the reader-settings Reading Mode picker, so this stack is **no longer reachable from reader dispatch** — it is retained (a follow-up may consume it for bilingual reading, or delete it once provably orphaned).

### 4. Coordinator Layer (`vreader/Views/Reader/`)

Cross-format coordinators that compose with multiple readers:

| Coordinator                | Responsibility                                                      | Setup Timing                                                          |
| -------------------------- | ------------------------------------------------------------------- | --------------------------------------------------------------------- |
| `ReaderAICoordinator`      | AI ViewModels, text loading, context extraction                     | On AI/TTS invoke                                                      |
| `ReaderSearchCoordinator`  | Search service, indexing, FTS5                                      | Service+VM via `ensureSearchReady()` when the search sheet opens      |
| `ReaderUnifiedCoordinator` | Unified renderer state, text transforms — retained but no longer dispatched (feature #54) | n/a (no dispatch path)                                     |
| `HighlightCoordinator`     | Persists via `HighlightPersisting`, dispatches to `HighlightRenderer` adapters | On reader open per format (TXT/MD/PDF/EPUB)                          |

Bridge-internal coordinators (`EPUBWebViewBridgeCoordinator`, `FoliateViewCoordinator`, `TXTTextViewBridgeCoordinator`) handle delegate / WKScriptMessageHandler plumbing for one bridge each; they're not cross-cutting and aren't enumerated here.

### 5. Services Layer (`vreader/Services/`)

| Service                              | Backing                    | Purpose                                                                   |
| ------------------------------------ | -------------------------- | ------------------------------------------------------------------------- |
| `PersistenceActor`                   | SwiftData (actor-isolated) | All DB writes serialized                                                  |
| `SearchService` + `SearchIndexStore` | SQLite FTS5                | Full-text search with persistent index                                    |
| `AIService`                          | OpenAI-compatible REST API | Summarize, translate, chat                                                |
| `TTSService`                         | AVSpeechSynthesizer + HTTP | Read aloud with controls                                                  |
| `BookContentCache`                   | In-memory                  | Text cache for AI context loading (TXT/MD only)                           |
| `PreferenceStore`                    | UserDefaults               | Sort order, view mode persistence                                         |
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
| `ReaderSettingsStore`                | UserDefaults               | Global reader UI prefs: theme, typography, reading mode, EPUB layout, auto-page-turn, page-turn animation, Chinese conversion, custom background |
| `PerBookSettingsStore`               | Per-book JSON files        | Per-book overrides on top of `ReaderSettingsStore` (font/theme/spacing) |
| `KeychainService`                    | Keychain                   | Secure credential storage (used by `WebDAVProviderFactory`)               |
| `BookSourcePipeline`                 | Actor + HTTP / rule engine | Search → BookInfo → TOC → Content scraping for Legado-style web novels    |
| `SyncService`                        | CloudKit (feature-flagged) | Coordinates sync with `SyncConflictResolver`, tombstones, change tokens   |
| `DebugBridge`                        | URL handler (DEBUG-only)   | `vreader-debug://` reset/seed/open/settle/snapshot/eval/tts; feature #49 added position-aware open + DebugSnapshot schema v2 (TTS state, render phase, settings provenance); feature #45 WI-4c-b added `tts?action=start\|stop` to bypass XCUITest's audio-session block; see `docs/subsystems/debug-bridge.md` |
| `DebugPositionResolver`              | —                          | Pure parser: `?position=<value>` string → typed `DebugPosition` per BookFormat (TXT/MD UTF-16 offset, EPUB CFI, AZW3 Foliate-CFI, PDF page). Native-mode-only; unified-renderer rejects via `openPositionUnsupportedInUnifiedMode`. Feature #49 WI-7a. |
| `DebugReaderRegistry.awaitReader`    | DebugReaderRegistry singleton | Token-based keyed waiter that resumes when a reader matching `fingerprintKey` registers. Concurrent waiters with different timeouts each get their own continuation (UUID-token ownership). Feature #49 WI-7a. |
| `DebugReaderRegistry.awaitReaderSettled` | DebugReaderRegistry singleton (`+Settle` extension) | Bug #141: render-settled signal keyed by `(fingerprintKey, token)`. Hosts call `markReaderSettled` on real render-complete — EPUB from `webView(_:didFinish:)`, AZW3/MOBI from the Foliate `relocate` message. `ReaderContainerView` wires `probe.settleStrategy` so `vreader-debug://settle` blocks until that signal (or `settleTimeout`) instead of the 100ms placeholder. TXT/MD/PDF keep the placeholder. Same UUID-token waiter machinery + stale-write guard as `awaitReader`. |
| `ImportJobQueue`                     | Actor                      | Serializes book imports (avoids parallel `BookImporter` writes)           |
| `FileURLImportRouter`                | `BookImporting` (protocol) | `@MainActor` dispatcher for incoming `file://` URLs from iOS Share Sheet / "Open in vreader" (Feature #59 WI-2). Wired by `VReaderApp`'s production `.onOpenURL`. Returns `false` for non-file URLs (Debug-bridge handler intercepts those upstream). Unsupported extensions reported via injected closure (App layer wires the user-facing alert; current production wiring is a no-op). Supported extensions kick off `bookImporter.importFile(at:source:.shareSheet)` in a fire-and-forget Task. Security-scope handling owned by `BookImporter`, not the router. |
| `LibraryRefreshService`              | NotificationCenter         | Coalesces library refresh requests across views                           |
| `FeatureFlags`                       | Static                     | Compile/runtime flag resolution (`SyncService` and others gate on it)     |
| `DictionaryLookup`                   | UIKit                      | System dictionary + AI-translate hooks for selected text                  |

### 6. Data Layer (`vreader/Models/`)

SwiftData SchemaV6 entities:

- `Book` (fingerprintKey unique; gains `originalExtension: String?` in SchemaV5 for backup blob extension preservation; gains `fileState: String` and `blobPath: String?` in SchemaV6 for feature #47's lazy-load row state) → `ReadingPosition`, `Highlight`, `Bookmark`, `AnnotationNote`, `BookCollection`
- `ReadingSession`, `ReadingStats`
- `BookSource`, `ContentReplacementRule` (added in SchemaV4)

`PersistenceActor.fetchAllBooksForBackup() -> [BackupBookProjection]` (in `PersistenceActor+Backup.swift`) returns a Sendable value-type view of every book — used by feature #46's WebDAV backup to emit `library-manifest.json` without leaking `@Model` instances across the actor boundary. Legacy V4 rows (no `originalExtension`) coalesce to the canonical extension for their format.

**Feature #47 — Selective picker + lazy-load (data layer)**: backend complete (WI-3 + WI-4 + WI-5 partial); UI picker + WebDAVProvider integration in WI-6; final acceptance + Docker-test follow-ups in WI-7. `Book.fileState` enum mirrors `BookFileState`: `.local` (bytes present, default), `.remoteOnly` (row exists, blob on server, no local bytes), `.downloading` (lazy fetch in flight), `.failed` (lazy fetch errored — retryable), `.missingRemote` (server lost the blob — needs re-upload, not re-download). `LibraryBookItem` carries the projection so row UI branches on `isReadable` / `needsDownload` / `canShare`. `PersistenceActor+RemoteOnly.swift` adds the bulk insert + state mutation helpers the lazy-download coordinator + `SelectiveRestoreCoordinator` use. The lazy-download coordinator's `bookFileStateDidChange` notification refreshes library rows after reconcile flips an orphaned `.downloading` row to `.failed`.

**Feature #46 — WebDAV materializing restore (data layer)**: backup ZIPs now carry an additional `library-manifest.json` section (one `BackupLibraryEntry` per book, including content-addressed `blobPath`). On `backup`, `WebDAVProvider` uploads each missing book blob atomically — `WebDAVBlobStore` PUTs to `VReader/uploads/tmp/<uuid>.part`, PROPFIND-verifies the size, then `MOVE`s into the canonical `VReader/books/<format>/<sha256>_<byteCount>.<ext>` path. Repeat backups skip already-published blobs via PROPFIND-by-size dedupe. On `restore`, when the manifest is present and a `BookImporter` is wired in (production: via `\.bookImporter` SwiftUI Environment), `BookFileMaterializer` downloads + verifies + imports each missing blob before metadata sections apply. v1-format backups (no manifest) restore as before — books silently skipped if missing locally. The 412 response from `MOVE Overwrite: F` is treated as "blob already converged" (content-addressing). 501 from `MOVE` raises `BackupBlobStoreError.serverCapabilityMissing` — no silent atomicity loss.

Backup section JSONs (`vreader/Services/Backup/BackupSectionDTOs.swift`) are
versioned via the `BackupVersionedEnvelope` protocol. Restore validates exact
`schemaVersion == 1` and raises `BackupRestoreError.unsupportedSchemaVersion`
on mismatch, so a future v2 archive can't silently apply on a v1 client.

Key types:

- `DocumentFingerprint` — `{format}:{SHA256}:{byteCount}` deterministic identity
- `Locator` — universal position: href+progression+CFI (EPUB/AZW3), page (PDF), UTF-16 offset (TXT/MD)
- `AnnotationAnchor` — format-agnostic location encoding for highlights/bookmarks
- `FormatCapabilities` — per-`BookFormat` capability matrix (selection, highlights, search, TTS, native pagination, unified reflow, TOC, annotations) consulted by the dispatcher and feature gates

## Notification Bus (`vreader/Views/Reader/ReaderNotifications.swift`)

All cross-component communication uses NotificationCenter:

| Notification                   | Payload              | Direction                                               |
| ------------------------------ | -------------------- | ------------------------------------------------------- |
| `.readerContentTapped`         | nil                  | Bridge → Container (toggle chrome)                      |
| `.readerPositionDidChange`     | `Locator`            | Format container → ReaderContainerView → AI coordinator |
| `.readerNavigateToLocator`     | `Locator`            | Container → Format container                            |
| `.readerBookmarkRequested`     | nil                  | Chrome → Format container                               |
| `.readerTextSelected`          | `TextSelectionInfo`  | Bridge → Container (active selection state)            |
| `.readerHighlightRequested`    | `TextSelectionInfo`  | Bridge → Container                                      |
| `.readerSelectionPopoverRequested` | `TextSelectionInfo` (object) | Bridge → `SelectionPopoverPresenterModifier` (Feature #60 WI-7c1). Bridges that have swapped to the popover suppress their legacy `UIMenu` and post this instead; the presenter mounts `SelectionPopoverView` (WI-7a) as a sheet and routes taps through `SelectionPopoverActionRouter` (WI-7b). |
| `.readerHighlightRemoved`      | UUID string          | HighlightListVM → Container                             |
| `.readerHighlightsDidImport`   | fingerprintKey       | Importer → format containers (refresh persisted highlights) |
| `.readerDidClose`              | fingerprintKey       | ViewModel → LibraryView                                 |
| `.readerAnnotationRequested`   | `TextSelectionInfo`  | Bridge → Container                                      |
| `.readerDefineRequested`       | `TextSelectionInfo`  | Bridge → Container (dictionary)                         |
| `.readerTranslateRequested`    | `TextSelectionInfo`  | Bridge → Container (AI translate)                       |
| `.searchHighlightClear`        | nil                  | SearchViewModel → Bridges                               |
| `.readerPreviousPage`          | nil                  | TapZoneOverlay → Container                              |
| `.readerNextPage`              | nil                  | TapZoneOverlay → Container                              |
| `.readerOpenContents`          | nil                  | `ReaderBottomChrome` toolbar → ReaderContainerView (Feature #60 WI-6b — opens annotations panel on the Contents tab) |
| `.readerOpenNotes`             | nil                  | `ReaderBottomChrome` toolbar → ReaderContainerView (Feature #60 WI-6b — opens annotations panel on the Highlights tab) |
| `.readerOpenDisplay`           | nil                  | `ReaderBottomChrome` toolbar → ReaderContainerView (Feature #60 WI-6b — opens reader settings) |
| `.readerOpenAI`                | nil                  | `ReaderBottomChrome` toolbar → ReaderContainerView (Feature #60 WI-6b — opens the AI assistant when configured) |
| `.readerMoreReadAloud`         | nil                  | `ReaderMorePopover` → ReaderContainerView (Feature #60 WI-6c — starts read-aloud / TTS) |
| `.readerMoreToggleAutoTurn`    | nil                  | `ReaderMorePopover` → ReaderContainerView (Feature #60 WI-6c — flips `ReaderSettingsStore.autoPageTurn`) |
| `.readerMoreBookDetails`       | nil                  | `ReaderMorePopover` → ReaderContainerView (opens the `BookDetailsSheet`, feature #61) |
| `.readerMoreShareBook`         | nil                  | `ReaderMorePopover` → ReaderContainerView (Feature #60 WI-6c — presents the system share sheet for the book file) |
| `.readerMoreExportAnnotations` | nil                  | `ReaderMorePopover` → ReaderContainerView (Feature #60 WI-6c — opens the annotations panel on the Highlights tab, which carries export) |
| `.epubFootnoteDetected`        | footnote ref         | EPUB bridge → Container (footnote popup)                |
| `.bookFileStateDidChange`      | `["fingerprintKey","state"]` | LazyDownloadCoordinator (reconcile) → LibraryView (refresh row, feature #47) |
| `.libraryRowTappedWhileNotLocal` | `["fingerprintKey","fileState"]` | LibraryView → BookDownloadSheet (future, #47 WI-6) |
| `.bookDidImport`               | `["fingerprintKey"]`         | BookImporter (after persist, new + duplicate paths) → LibraryView (force-refresh; bug #197) |

## Shared Reader UI State (Phase R3)

`TextReaderUIState` (`@Observable`) holds UI state shared between TXT and MD containers:

- Highlight/annotation state: `scrollToOffset`, `highlightRange`, `highlightIsTemporary`, `persistedHighlightRanges`, `pendingAnnotationInfo`, `annotationNoteText`
- Pagination state: `pageNavigator`, `pagedCurrentPage`, `autoPageTurner`
- Reading progress: `readingProgress`
- Helper methods: `syncPagedState()`, `updatePagination()`, `updateAutoPageTurner()`, `refreshPersistedHighlights()`

Conforms to `ReaderNotificationHandlerStateProtocol` so `ReaderNotificationModifier` mutates it directly. Note: TXT extraction is partial — `TXTReaderContainerView` still holds some legacy `@State` alongside `uiState` and a follow-up pass would consolidate it.

Format-specific state remains in each container:

- TXT: chunking, chunk offsets, attributed string building, large-file detection
- MD: rendered attributed string (from `MDReaderViewModel`)

## Highlight System (Phase R4a/R4b)

`HighlightRenderer` protocol defines format-agnostic visual operations: `apply(record:)`, `remove(id:)`, `restore(records:)`.

| Adapter                 | Format    | Mechanism                                                                           |
| ----------------------- | --------- | ----------------------------------------------------------------------------------- |
| `TextHighlightRenderer` | TXT, MD   | Mutates `TextReaderUIState.persistedHighlightRanges`                                |
| `EPUBHighlightRenderer` | EPUB      | Generates CSS Highlight API JS via `onInjectJS` callback                            |
| `PDFHighlightRenderer`  | PDF       | Creates/removes `PDFAnnotation` objects; tracks `highlightId → [PDFAnnotation]` map |
| _(none yet)_            | AZW3/MOBI | Selection capture + CFI anchoring landed; `FoliateHighlightRenderer` exists for SVG-overlay JS but is not yet wired as a `HighlightRenderer` adapter. AZW3 highlight create/restore are TODO/no-op placeholders today. |

`HighlightCoordinator` orchestrates the highlight lifecycle:

- `create()` — persists via `HighlightPersisting`, then calls `renderer.apply()`
- `handleRemoval()` — calls `renderer.remove()`, re-fetches, calls `renderer.restore()`
- `restoreAll()` — fetches from persistence, calls `renderer.restore()`

Each container creates its format-specific renderer and coordinator:

- TXT/MD: via `ReaderNotificationModifier` (handles `readerHighlightRequested` / `readerHighlightRemoved`)
- EPUB: coordinator for persistence, renderer for JS injection
- PDF: coordinator + renderer with annotation map (fixes bug #87: highlight deletion)

## Key Design Patterns

1. **Bridge** — UIKit views (UITextView, WKWebView, PDFView) wrapped in `UIViewRepresentable` with Coordinator for delegate/gesture handling
2. **Coordinator** — Complex multi-subsystem flows managed by dedicated coordinator objects (AI, Search, Unified, Highlight)
3. **Protocol injection** — `LibraryPersisting`, `BookImporting`, `PreferenceStoring`, `TTSProviderProtocol`, `HighlightRenderer` enable testing
4. **Actor isolation** — `PersistenceActor` serializes all SwiftData writes; `TXTService` is actor-isolated
5. **Deferred setup** — AI is wired on first AI/TTS invoke; the search service+VM are prepared via `ensureSearchReady()` only when the search sheet opens. TXT TOC is the exception — it's built eagerly on reader open so the chapter progress bar has data in legacy mode.
6. **Observer** — NotificationCenter decouples format-specific readers from chrome and coordinators
7. **Shared state extraction** — `TextReaderUIState` eliminates duplicated `@State` between TXT/MD containers (Phase R3)
8. **Format adapters** — `HighlightRenderer` protocol with per-format adapters decouples highlight lifecycle from rendering mechanism (Phase R4a)
9. **Extension splitting** — Container views and bridges decomposed into `+Highlights`, `+Navigation`, `+Overlays`, `+Helpers` extensions. Core wiring stays in the main file; subviews and action methods live in extensions (Phase R5a/R5b)
10. **Lifecycle composition** — `ReaderLifecycleHelper` owns session tracking, periodic flush, time display, and close/background/foreground sequences. Each format VM composes one instance and delegates shared lifecycle calls (Phase R6)

## Performance Optimizations

| Optimization                      | Target                                      |
| --------------------------------- | ------------------------------------------- |
| Sample-based encoding (8KB)       | Fast TXT open for non-UTF-8 files           |
| Chunked reader (UITableView)      | Large TXT files (>500K UTF-16)              |
| Deferred coordinator setup        | AI wired on invoke; search prepared on sheet open. TXT TOC stays eager for the chapter progress bar |
| Persistent FTS5 index             | Skip re-indexing on subsequent opens        |
| Off-main-thread attributed string | Non-blocking TXT/MD rendering               |
| PaginationCache                   | Avoid redundant TextKit layout passes       |
| Non-contiguous layout             | TextKit 1 performance for large documents   |

## File Organization

```
vreader/
├── App/                    # VReaderApp, ContentView
├── Models/                 # SwiftData models, DocumentFingerprint, Locator
├── ViewModels/             # LibraryViewModel, format ViewModels
├── Views/
│   ├── LibraryView.swift   # Library grid/list
│   ├── Reader/             # Reader container, format containers, bridges
│   ├── Bookmarks/          # BookmarkListView, TOCListView
│   ├── Annotations/        # HighlightListView, AnnotationListView
│   └── Settings/           # SettingsView, ReaderSettingsPanel
├── Services/
│   ├── PersistenceActor.swift
│   ├── TXT/                # TXTService, TXTFileLoader
│   ├── EPUB/               # EPUBParser, EPUBTypes
│   ├── Search/             # SearchService, FTS5, extractors
│   ├── AI/                 # AIService, providers
│   ├── TTS/                # TTSService, providers
│   ├── Backup/             # WebDAV, BackupProvider
│   ├── Import/             # BookImporter
│   ├── Export/             # AnnotationExporter
│   ├── Locator/            # LocatorFactory, position resolution
│   ├── OPDS/               # OPDSClient, OPDSParser
│   ├── Sync/               # SyncService, SyncStatusMonitor
│   ├── AZW3/              # MOBICoverExtractor (native PDB/MOBI header parsing)
│   ├── Foliate/            # FoliateURLSchemeHandler, FoliateMessageParser, FoliateTypes, JS/
│   ├── Unified/            # PaginationCache, TextKit2 helpers
│   └── TextMapping/        # Transforms, offset mapping
└── (no Plugins/ directory — BookSource views are in Views/BookSource/)
```

## Verification Harness (`vreaderUITests/Verification/`)

DEBUG-only XCUITest harness that exercises 13 features' UI surfaces end-to-end
on iPhone 17 Pro Simulator for autonomous device verification. Shipped as
feature #45 in WI-1 (PR #581) → WI-2 (PR #584) → WI-3 (PR #587) → WI-4
(this WI).

```
vreaderUITests/Verification/
├── Helpers/
│   ├── VerificationDebugBridgeHelper.swift    # Wraps vreader-debug:// commands
│   └── VerificationSettingsHelper.swift       # Reader settings panel navigation
├── Feature11EPUBHighlightVerificationTests.swift
├── Feature21PaginatedModeVerificationTests.swift
├── Feature23TXTTocVerificationTests.swift
├── Feature27ReplacementRulesVerificationTests.swift
├── Feature28ChineseConversionVerificationTests.swift
├── Feature29WebDAVVerificationTests.swift
├── Feature31AutoPageTurnVerificationTests.swift
├── Feature34CollectionsVerificationTests.swift
├── Feature35AnnotationsExportVerificationTests.swift
├── Feature36OPDSVerificationTests.swift
├── Feature37PerBookSettingsVerificationTests.swift
├── Feature40TTSSentenceHighlightVerificationTests.swift
└── Feature41TTSAutoScrollVerificationTests.swift
```

### Conventions

- **`test_verify_` method prefix** — XCTest discovers methods starting
  with `test`; the `_verify_` infix preserves the descriptive feature
  slug for grep-friendly mapping (`test_verify_feature_<NN>_<scenario>`).
  The verification harness runs on its own cadence by `-only-testing:
  vreaderUITests/<Class>` invocations or by the named `Verification`
  test plan: `xcodebuild test -scheme vreader -testPlan Verification`
  (Feature #45 WI-6). The plan lives at `TestPlans/Verification.xctestplan`
  and selects exactly 25 `test_verify_*` per-method identifiers across
  the 13 classes listed below; the default plan
  `TestPlans/All.xctestplan` runs the full `vreaderTests` + `vreaderUITests`
  suites on no-flag `xcodebuild test` / `Cmd+U`. Bug #192 (GH #686, 2026-05-15) fixed an earlier
  shape where these methods used a plain `verify_` prefix — they were
  XCTest-invisible and the entire 13-class verification suite had
  been silently no-opping (`Executed 0 tests` + `TEST SUCCEEDED` =
  vacuous pass). The rename to `test_verify_*` made them discoverable.
- **`@MainActor final class XCTestCase`** — verification tests touch
  the SwiftUI element tree which is main-actor-isolated.
- **Seed via `launchApp(seed:)`** — `.warAndPeace` / `.mdTOC` for tests
  that need real content; `.books` for UI-surface-only tests.
- **`XCTSkip` for capability gates** — features gated by
  `FormatCapabilities` (e.g., autoPageTurn on TXT) skip gracefully
  rather than fail.
- **`XCTSkip` for env-var-gated live tests** — WebDAV/OPDS live-server
  tests skip unless `CI_WEBDAV_URL` / `CI_OPDS_URL` are set.
- **RED-proof catalog** at `dev-docs/verification-red-checks.md`
  records evidence that each `test_verify_` method correctly fails when
  its production seam is broken.

### Why no auto-discovery

vreader's default `xcodebuild test` gate runs `vreaderTests/` only
(skipping UITests via `-only-testing:vreaderTests`). The verification
harness is heavier (each test launches the app + drives gestures) and
runs on its own cadence via the verify cron. Auto-discovery from the
default scheme would slow every dev unit-test run by minutes for no
incremental signal.

