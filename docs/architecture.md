# VReader Architecture

## Overview

VReader is an iOS e-book reader built with SwiftUI + SwiftData. It supports TXT, EPUB, AZW3/MOBI, PDF, and Markdown formats with dual rendering modes (native UIKit/WebView bridges + unified TextKit 2 reflow). AZW3/MOBI is rendered via Foliate-js inside a WKWebView; the unified path falls back to a placeholder for AZW3 today.

## System Diagram

```
┌──────────────────────────────────────────────────────┐
│                    VReaderApp                         │
│  SwiftData SchemaV5 · PersistenceActor · BookImporter│
└─────────────────────┬────────────────────────────────┘
                      │
          ┌───────────┴───────────┐
          │                       │
    ┌─────▼──────────┐    ┌──────▼──────────────────┐
    │  LibraryView    │    │  ReaderContainerView     │
    │  LibraryViewModel│   │  (format dispatcher)     │
    │  PreferenceStore │   │  ReaderChromeBar (overlay)│
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

- `VReaderApp.swift` — SwiftData `ModelContainer` init (SchemaV5), migration plan (V1→V2→V3→V4→V5), test seeding, error handling. Injects the live `PersistenceActor` into the SwiftUI environment via `\.persistenceActor` so settings sub-screens can construct backup providers without rewriting every parent's signature.

### 2. Library Layer (`vreader/Views/LibraryView.swift`, `vreader/ViewModels/LibraryViewModel.swift`)

- Grid/list view with sort (persisted via `PreferenceStore`)
- Context menu: Info, Share, Set Cover, Add to Collection, Delete
- Collections sidebar, OPDS catalog, AI chat entry points

### 3. Reader Layer (`vreader/Views/Reader/`)

#### Dispatcher

`ReaderContainerView.swift` routes to format-specific readers:

- If unified mode is on and `FormatCapabilities.unifiedReflow` is true → `unifiedReaderView` (TXT/MD/EPUB → `UnifiedTextRenderer`; AZW3 has no unified case yet and falls back to `UnifiedPlaceholderView`).
- Else → native format host. AZW3/MOBI specifically routes to `FoliateSpikeView` (`ReaderContainerView.swift:368`), not `FoliateReaderHost`. The host wrapper exists but isn't currently in the dispatch path.

#### Chrome

`ReaderChromeBar.swift` — custom overlay toolbar (not system nav bar). Floats on top of content, no safe area impact. Buttons: back, search, bookmark, annotations, AI, TTS, settings.

#### Format Hosts (`ReaderFormatHosts.swift`)

Each host owns its ViewModel lifecycle via `@State`:

- `TXTReaderHost` → `TXTReaderContainerView` → `TXTTextViewBridge` (small) or `TXTChunkedReaderBridge` (>500K UTF-16)
- `EPUBReaderHost` → `EPUBReaderContainerView` → `EPUBWebViewBridge` (WKWebView + JS injection)
- `PDFReaderHost` → `PDFReaderContainerView` → `PDFViewBridge` (PDFKit)
- `MDReaderHost` → `MDReaderContainerView` → reuses `TXTTextViewBridge` with NSAttributedString
- AZW3/MOBI is dispatched directly to `FoliateSpikeView` (the AZW3 spike landed before the host abstraction; convergence is deferred). `FoliateReaderHost` / `FoliateReaderContainerView` exist but are not currently wired into `ReaderContainerView`.

#### Foliate-js Bridge (`vreader/Views/Reader/`, `vreader/Services/Foliate/`)

`FoliateViewBridge` (UIViewRepresentable) hosts a WKWebView and uses `loadHTMLString` with the IIFE-bundled `foliate-bundle.js` inlined; books are handed to JS as base64 (no scheme handler in the live load path — `FoliateURLSchemeHandler` exists in the codebase but isn't wired into the active bridge today). `FoliateViewCoordinator` (WKScriptMessageHandler + WKNavigationDelegate) receives JS messages, parses via `FoliateMessageParser`, and routes to typed callbacks. `FoliateHighlightRenderer` generates JS strings for SVG overlay annotations — but it is **not** plugged in as a `HighlightRenderer` adapter today; AZW3 highlight create has a TODO for persistence/JS injection and overlay restore is a no-op placeholder (`FoliateReaderContainerView+Highlights.swift`). `FoliateJSEscaper` provides shared sanitization for all JS/CSS string interpolation across the bridge. `FoliateReaderViewModel` maps bridge events to `Locator` for position persistence.

#### Unified Engine

`ReaderUnifiedCoordinator` loads text + applies transforms (replacement rules, simp/trad). `UnifiedTextRenderer` displays with TextKit 2 pagination or scroll.

### 4. Coordinator Layer (`vreader/Views/Reader/`)

Cross-format coordinators that compose with multiple readers:

| Coordinator                | Responsibility                                                      | Setup Timing                                                          |
| -------------------------- | ------------------------------------------------------------------- | --------------------------------------------------------------------- |
| `ReaderAICoordinator`      | AI ViewModels, text loading, context extraction                     | On AI/TTS invoke                                                      |
| `ReaderSearchCoordinator`  | Search service, indexing, FTS5                                      | Service+VM via `ensureSearchReady()` when the search sheet opens      |
| `ReaderUnifiedCoordinator` | Unified renderer state, text transforms                             | On reader open (unified mode only)                                    |
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
| `WebDAVProviderFactory`              | `KeychainService`          | Assembles a `WebDAVProvider` from saved credentials + live persistence + live `BookImporter` (feature #46) |
| `BackupDataCollector`                | `PersistenceActor`         | Serializes 8 versioned JSON sections (annotations, positions, settings, library-manifest, …) |
| `BackupDataRestorer`                 | `PersistenceActor`         | Decodes + dedupes by UUID/profileKey; rejects future schema versions      |
| `BlobPath`                           | —                          | Pure utility: `(format, sha256, byteCount)` ↔ `VReader/books/<format>/<sha>_<bytes>.<ext>` (feature #46) |
| `BackupBlobStore` (protocol pair)    | —                          | Transport-neutral read (`BackupBlobReading`) + write (`BackupBlobWriting`) blob API |
| `WebDAVBlobStore`                    | `WebDAVTransport`          | Adapter that owns the temp+MOVE atomic-publication algorithm (feature #46) |
| `BookFileMaterializer`               | `BackupBlobReading` + `BookImporting` | Restore-side: download + size/SHA-256 verify + import via `BookImporter`. Preflight-rehashes existing local files to catch corrupt content (feature #46). |
| `FoliateURLSchemeHandler`            | WKURLSchemeHandler         | Scheme-handler implementation (not on the live load path; see Foliate-js Bridge note) |
| `FoliateMessageParser`               | Pure functions             | Parses raw JS message bodies into typed Swift events                      |
| `FoliateJSEscaper`                   | Pure functions             | Escapes/sanitizes strings for safe JS/CSS interpolation in Foliate bridge |
| `ReaderSettingsStore`                | UserDefaults               | Global reader UI prefs: theme, typography, reading mode, EPUB layout, auto-page-turn, page-turn animation, Chinese conversion, custom background |
| `PerBookSettingsStore`               | Per-book JSON files        | Per-book overrides on top of `ReaderSettingsStore` (font/theme/spacing) |
| `KeychainService`                    | Keychain                   | Secure credential storage (used by `WebDAVProviderFactory`)               |
| `BookSourcePipeline`                 | Actor + HTTP / rule engine | Search → BookInfo → TOC → Content scraping for Legado-style web novels    |
| `SyncService`                        | CloudKit (feature-flagged) | Coordinates sync with `SyncConflictResolver`, tombstones, change tokens   |
| `DebugBridge`                        | URL handler (DEBUG-only)   | `vreader-debug://` reset/seed/open/settle/snapshot/eval; feature #49 added position-aware open + DebugSnapshot schema v2 (TTS state, render phase, settings provenance); see `docs/subsystems/debug-bridge.md` |
| `DebugPositionResolver`              | —                          | Pure parser: `?position=<value>` string → typed `DebugPosition` per BookFormat (TXT/MD UTF-16 offset, EPUB CFI, AZW3 Foliate-CFI, PDF page). Native-mode-only; unified-renderer rejects via `openPositionUnsupportedInUnifiedMode`. Feature #49 WI-7a. |
| `DebugReaderRegistry.awaitReader`    | DebugReaderRegistry singleton | Token-based keyed waiter that resumes when a reader matching `fingerprintKey` registers. Concurrent waiters with different timeouts each get their own continuation (UUID-token ownership). Feature #49 WI-7a. |
| `ImportJobQueue`                     | Actor                      | Serializes book imports (avoids parallel `BookImporter` writes)           |
| `LibraryRefreshService`              | NotificationCenter         | Coalesces library refresh requests across views                           |
| `FeatureFlags`                       | Static                     | Compile/runtime flag resolution (`SyncService` and others gate on it)     |
| `DictionaryLookup`                   | UIKit                      | System dictionary + AI-translate hooks for selected text                  |

### 6. Data Layer (`vreader/Models/`)

SwiftData SchemaV5 entities:

- `Book` (fingerprintKey unique; gains `originalExtension: String?` in SchemaV5 for backup blob extension preservation) → `ReadingPosition`, `Highlight`, `Bookmark`, `AnnotationNote`, `BookCollection`
- `ReadingSession`, `ReadingStats`
- `BookSource`, `ContentReplacementRule` (added in SchemaV4)

`PersistenceActor.fetchAllBooksForBackup() -> [BackupBookProjection]` (in `PersistenceActor+Backup.swift`) returns a Sendable value-type view of every book — used by feature #46's WebDAV backup to emit `library-manifest.json` without leaking `@Model` instances across the actor boundary. Legacy V4 rows (no `originalExtension`) coalesce to the canonical extension for their format.

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
| `.readerHighlightRemoved`      | UUID string          | HighlightListVM → Container                             |
| `.readerHighlightsDidImport`   | fingerprintKey       | Importer → format containers (refresh persisted highlights) |
| `.readerDidClose`              | fingerprintKey       | ViewModel → LibraryView                                 |
| `.readerAnnotationRequested`   | `TextSelectionInfo`  | Bridge → Container                                      |
| `.readerDefineRequested`       | `TextSelectionInfo`  | Bridge → Container (dictionary)                         |
| `.readerTranslateRequested`    | `TextSelectionInfo`  | Bridge → Container (AI translate)                       |
| `.searchHighlightClear`        | nil                  | SearchViewModel → Bridges                               |
| `.readerPreviousPage`          | nil                  | TapZoneOverlay → Container                              |
| `.readerNextPage`              | nil                  | TapZoneOverlay → Container                              |
| `.epubFootnoteDetected`        | footnote ref         | EPUB bridge → Container (footnote popup)                |

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

