---
title: Module — library
updated: 2026-07-11
status: verified
---

# Module — library

## Purpose

The library is vreader's home screen: it lists imported books as a 3-column grid or an inset-grouped list, supports search (title/author substring), collection filtering (tag/series filtering are defined in `LibraryFilter` but not functional — see Key files), four sort orders, a "Continue reading" rail, custom cover replacement, book info/share/delete, file import, and entry into the reader. It was fully re-skinned by feature #60 "visual identity v2" (WI-8/WI-9/WI-10) to a warm-paper design pinned to `dev-docs/designs/vreader-fidelity-v1/project/vreader-library.jsx`.

## Key files and types

- `vreader/ViewModels/LibraryViewModel.swift` — `@Observable @MainActor final class LibraryViewModel`. Owns `books: [LibraryBookItem]`, `viewMode: LibraryViewMode` (grid/list), `sortOrder: LibrarySortOrder`, `isInitialLoad`, `isRefreshing`, `errorMessage`. Actions: `loadBooks()`, `refresh(force:)`, `deleteBook(fingerprintKey:)`, `importFiles(_ urls: [URL])`, `toggleViewMode()`, `markBookAsJustRead(fingerprintKey:)`.
- `vreader/Views/LibraryView.swift` — `struct LibraryView: View`, the container shell: `NavigationStack` (bar hidden), `LibraryNavBar` pill row, 36pt Source Serif 4 title with a `{N} books · {M} reading` subtitle, toggleable `LibrarySearchBar`, `LibraryFilterChips`, then the scrollable grid/list body. `openBook(_:)` gates on `book.isReadable` and posts `.libraryRowTappedWhileNotLocal` for non-local rows (feature #47 WI-5). `static let importableTypes: [UTType]` accepts epub/pdf/plainText/markdown/mobi plus generic `.data` so `.azw3/.mobi/.azw` aren't filtered.
- `vreader/Views/Library/LibraryView+Body.swift` — extension holding `gridBody` (LazyVGrid, 3 flexible columns, 14pt/22pt gaps), `listBody` (native `List` insetGrouped so `.swipeActions` delete survives the re-skin), `emptyState`, and `bookContextMenu(for:)` (Info / Share / Set Cover / Remove Cover / Add to Collection / Delete).
- `vreader/Views/Library/LibraryViewObservers.swift` — `struct LibraryViewObservers: ViewModifier`: the notification-observer chain (see Data flow). Contains `#if DEBUG`-gated `LibraryDebugBridgeObservers` (bug #254: the whole struct, not just `body()`, is DEBUG-gated).
- `vreader/Views/Library/LibraryViewSheets.swift` — `struct LibraryViewSheets: ViewModifier`: delete/error alerts (`LibraryAlerts`), Info/Share/Download/Settings/AI-chat/OPDS/Collections sheets, `.fileImporter`, `.coverPicker(_:)`. `static var generalChatTheme: ReaderThemeV2 { .paper }` pins the general AI chat surface (bug #310).
- `vreader/Views/Library/LibraryContainerModel.swift` — `struct LibraryContainerModel: Equatable, Sendable`, the pure (no-SwiftUI) derivation layer: `normalizedQuery`, `showsContinueReadingRail` (true only for `.allBooks` + no query), `matchingBooks(in:)` (filter AND query), `continueReadingBooks(in:)`, `subtitleCounts(for:)` (counts the whole library, not the filtered subset).
- `vreader/Views/Library/CollectionSidebar.swift` — `enum LibraryFilter` (`.allBooks / .collection(String) / .tag(String) / .series(String)`) with `matches(_ book:)` (bug #155: `.collection` is exact-string membership against `book.collectionNames`; `.tag` and `.series` are a functional no-op — `matches(_:)` returns `true` unconditionally for both cases because `LibraryBookItem` has no tag/series fields to check against, so selecting a tag or series filter silently shows the whole library) + `struct CollectionSidebar` (create/delete collections, filter selection; bug #129 surfaces delete failures via an alert instead of `try?`).
- `vreader/Views/Library/` components: `LibraryNavBar` (pill row: Settings leading; Search/Grid-List/Collections/OPDS/AI/Import trailing), `LibraryPillButton` (36pt circle), `LibrarySearchBar` (toggleable title/author search field: magnifier icon, borderless `TextField`, clear button shown only when non-empty; mounted/unmounted by `LibraryView`'s `isSearchVisible` state), `LibraryFilterChips` (designed chip treatment over real collections, not the mock's fixed taxonomy), `LibrarySectionHeader` ("All books" + sort `Menu`), `ContinueReadingRail` (caps at 5 cards), `LibraryContinueCard` (124×186 cover + percent/last-read meta), `BookInfoSheet` (with unit-testable `BookInfoViewModel` struct), `ShareSheet` (shares `book.resolvedFileURL` via `ShareActivityView`), `LibraryCardTranslateBadge` (feature #56 WI-14 translate-book overlay).
- `vreader/Views/BookCardView.swift` — grid card: cover + 2-line serif title + author; overlays: in-cover progress strip (`inProgress` fraction), finished checkmark badge, translate running/done badges. Bug #177: trailing `Spacer(minLength: 0)` top-aligns short cards in a grid row.
- `vreader/Views/BookRowView.swift` — list row: 44×62 thumbnail, title/author, format chip or feature-#47 file-state badge, trailing `LibraryProgressRing`.
- `vreader/Views/BookCoverArtView.swift` — shared cover: fixed 2:3 `aspectRatio`, custom image via `.overlay` (never `.background`), spine-shadow + page-edge gradients, hairline border (bug #107). Fallback when `image == nil` is the generative cover.
- `vreader/Views/GenerativeCoverView.swift` + `vreader/Views/GenerativeCoverMetrics.swift` + `vreader/Models/GenerativeCoverStyle.swift` — feature #60 WI-10 generative typographic covers: `GenerativeCoverStyle.style(forFingerprintKey:)` / `GenerativeCoverPalette.palette(forFingerprintKey:)` deterministically derive style + palette from `fingerprintKey`; metrics scale with cover width (`w * 0.13` title etc.).
- `vreader/Views/LibraryCardTokens.swift` — the design-token home (Library shell `#f7f4ee` differs from reader `.paper` `#f4eee0`, so the Library keeps its own tokens).
- `vreader/Views/Shared/CoverPickCoordinator.swift` — `@Observable @MainActor final class CoverPickCoordinator` (feature #61 WI-2): PhotosPicker flow + a `coverVersion: Int` counter observed by card/row/rail so covers reload after change. `CoverPickerModifier` presents the picker via `onChange(of: bookForCover)` (bug #80: waits for the context menu to dismiss).
- `vreader/Models/LibraryBookItem.swift` — `struct LibraryBookItem: Sendable, Identifiable, Equatable, Hashable`; `id` is `fingerprintKey`. Carries `fileState: BookFileState`, `blobPath`, `collectionNames`, `progressFraction`, `totalPageCount`. `readingProgressState` classifies into `.notStarted / .inProgress(Double) / .finished` (nil/NaN/∞/≤0 → notStarted; ≥1.0 → finished). Helpers: `isReadable` (== `.local`), `needsDownload`, `canShare`.
- `vreader/Models/LibrarySortOrder.swift` — `title / addedAt / lastReadAt / totalReadingTime` ("Title" / "Date Added" / "Last Read" / "Reading Time").
- `vreader/Services/CustomCoverStore.swift` — `enum CustomCoverStore`: JPEG (quality 0.8, max 512×512) at `<baseDirectory>/CustomCovers/<sanitizedKey>.jpg`; keys sanitized for filesystem safety.
- `vreader/Services/LibraryRefreshService.swift` — `final class LibraryRefreshService: @unchecked Sendable`: file-existence verification (`verifyFileExistence(books:)`, splits existing/missing without rescanning file bytes) and an atomic refresh-throttle permit (`tryAcquireRefreshPermit()`, 5s default, `FileExistenceChecking` protocol for mock injection). Not currently wired into `LibraryViewModel`, which implements its own inline throttle (see Concurrency).

## Views

Library-owned view components per the coverage ledger: `BookCardView`, `BookCoverArtView`, `BookRowView`, `GenerativeCoverView`, `GenerativeCoverMetrics`, `LibraryCardTokens`, `LibraryProgressRing`, `LibraryView` (each detailed above under "Key files and types"), plus `ScreenSpaceDemo` (a dev-only safe-area/layout-inspection overlay, swapped manually into `ContentView.body` for debugging; no library-specific behavior beyond this listing). `vreader/Views/ContentView.swift` itself is APP-owned, not library — it's the thin app-shell wrapper that embeds `LibraryView` (see [[Architecture — app layer and concurrency model]]).

## Dependencies

- `vreader/Services/LibraryPersisting.swift` — `protocol LibraryPersisting: Sendable { fetchAllLibraryBooks() / deleteBook(fingerprintKey:) }`; production conformer is `PersistenceActor` ([[Module — persistence and data model]]). Views also construct `PersistenceActor(modelContainer:)` directly for collections (`fetchAllCollections`, `fetchAllTags`, `fetchAllSeriesNames`, `createCollection`, `deleteCollection`, `addBookToCollection` in `PersistenceActor+Collections.swift`).
- `BookImporting` (importer, [[Module — import pipeline]]), `PreferenceStoring` (persists `library.sortOrder` / `library.viewMode` — bug #75).
- Feature #47 lazy download: `@Environment(\.lazyDownloadCoordinator)` + `@Environment(\.webDAVNetworkPolicy)`, `WebDAVProviderFactory.makeRequestBuilder(profileStore: WebDAVServerProfileStore.shared)` ([[Module — backup and WebDAV]]).
- AI chat gating via `AIReaderAvailability.isAvailable(...)`; general chat VM built with `AIService` + optional agentic registry ([[Module — AI providers and tools]]).
- DEBUG observers for `.debugBridgeOpenBook` / `.debugBridgeLibraryChanged` ([[Module — debug bridge]]).
- `vreader/Services/DictionaryLookup.swift` lives under `vreader/Services/` but is reader Define/Translate-on-Select scope, not library — see [[Architecture — reader dispatch and format hosts]].

## Data flow

Load: `LibraryView.task` → `viewModel.loadBooks()` → `persistence.fetchAllLibraryBooks()` → sorted locally. The notification bus keeps it fresh ([[Architecture — notification bus]]):

- `.readerDidClose` (object = fingerprintKey String) → `markBookAsJustRead` — in-memory `lastReadAt` update + re-sort, deliberately NOT `loadBooks()` (bug #45 v4: a DB re-fetch races `recomputeStats()`).
- `.bookFileStateDidChange` (defined in `vreader/Services/Backup/LazyDownloadCoordinator.swift`) → `refresh(force: true)` (bug #115 / #47 WI-4b).
- `.bookDidImport` (defined in `vreader/Services/BookImporter.swift`) → `refresh(force: true)` (bug #197 — covers Share-Sheet/Open-in imports).
- `.libraryRowTappedWhileNotLocal` → `LibraryViewObservers.handleRowTapWhileNotLocal`: parses `fingerprintKey` as `<format>:<sha256>:<byteCount>`, then `LazyDownloadCoordinator.enqueue(...)`; enqueue results `.deferredWiFi / .notReady / .taskDescriptionEncodeFailed / .started` map to error strings or the `BookDownloadSheet`.
- `.opdsBookDownloaded` (defined in `vreader/Views/OPDS/OPDSEntryView.swift`) → `importFiles([url])` ([[Module — OPDS]]).
- `.readerBookTranslationProgressDidChange` → `translationProgressByBook[key]` drives per-card translate badges (feature #56 WI-14, [[Module — bilingual translation]]).

Navigation: `openBook` sets `isPushingReader = true` (hides custom chrome before the push animation — bug #72) then `navigationPath.append(book)`; `navigationDestination(for: LibraryBookItem.self)` builds `ReaderContainerView(book:)` ([[Architecture — reader dispatch and format hosts]]).

## Concurrency

Everything UI-facing is `@Observable @MainActor`; persistence is reached with `await` on `PersistenceActor`. `refresh(force:)` is re-entrancy-coalescing (bug #197): a call arriving mid-refresh sets `hasPendingRefresh`; the in-flight call drains with a `repeat { hasPendingRefresh = false; await loadBooks() } while hasPendingRefresh && iterations < 8` loop, and if the 8-iteration safety bound trips with work still pending it dispatches one follow-up `Task { await self?.refresh(force: true) }` — the invariant is "every observed pending refresh runs at least one fetch after it was observed". Pull-to-refresh is throttled to 5s (`throttleInterval`, injectable); `lastRefreshTime` updates only on success so failures don't block retry.

## Edge cases and invariants

- Sorting: `lastReadAt` sort puts non-nil before nil; nil-nil keeps order. Title sort uses `localizedCaseInsensitiveCompare`.
- Search: whitespace-only query is a no-op (`normalizedQuery` nil); matching is `localizedCaseInsensitiveContains` on title or author (nil author never matches). Emptying the library collapses and clears the search bar (`onChange(of: viewModel.isEmpty)`).
- Subtitle pluralizes ("1 book", "2 books"); counts the whole library regardless of filter.
- The Continue-reading rail shows only under `.allBooks` with no query AND ≥1 `.inProgress` book; rail order is most-recently-read first.
- `importFiles` processes all URLs sequentially, collects only the first error, skips `CancellationError`, and reloads books after all imports.
- Delete is confirm-alerted; `deleteBook` removes from both `unsortedBooks` and `books` in memory after the persistence delete.
- Cover picking snapshots the target book before the async image load so a mid-flight retarget can't redirect the save; a failed cover save is logged and the version bump still refreshes views.
- Progress strip fill is `trackWidth * fraction`; `LibraryProgressRing` clamps progress to `[0, 1]`.

## History

Bug #45 v4 (stale lastReadAt), #72 (chrome flicker on push), #75 (persist sort/view mode), #80 (picker vs context-menu race), #85 (Add-to-Collection submenu), #93 (cache general-chat VM across sheet cycles), #107 (cover hairline border), #115 (file-state refresh), #129 (collection-delete error surfacing), #155 (collectionNames membership filter), #177 (grid top-alignment), #197 (refresh coalescing), #210 / GH #809 (stable accessibility identifiers `addToCollectionMenu`, `collectionFilterRow_<name>`), #254 (DEBUG symbol gating), #310 (general-chat theme). Features: #34 (collections), #44 (DebugBridge), #47 (lazy download / file states), #56 WI-14 (translate badges), #60 WI-8/9/10 (re-skin + generative covers), #61 WI-2 (CoverPickCoordinator), #91 (agentic registry for library chat).

**Sources.** [[session 014jggU2u3f3t6YRoPLS457u · 2026-07-10]] · [[session 014jggU2u3f3t6YRoPLS457u-audit · 2026-07-11]]

**Verified.** 2026-07-11 — checked against: vreader/ViewModels/LibraryViewModel.swift, vreader/Views/LibraryView.swift, vreader/Views/LibraryCardTokens.swift, vreader/Views/Library/LibraryView+Body.swift, vreader/Views/Library/LibraryViewObservers.swift, vreader/Views/Library/LibraryViewSheets.swift, vreader/Views/Library/LibraryContainerModel.swift, vreader/Views/Library/CollectionSidebar.swift, vreader/Views/Library/LibraryNavBar.swift, vreader/Views/Library/LibraryPillButton.swift, vreader/Views/Library/LibraryFilterChips.swift, vreader/Views/Library/LibrarySectionHeader.swift, vreader/Views/Library/ContinueReadingRail.swift, vreader/Views/Library/LibraryContinueCard.swift, vreader/Views/Library/BookInfoSheet.swift, vreader/Views/Library/ShareSheet.swift, vreader/Views/Library/LibraryCardTranslateBadge.swift, vreader/Views/BookCardView.swift, vreader/Views/BookRowView.swift, vreader/Views/BookCoverArtView.swift, vreader/Views/GenerativeCoverView.swift, vreader/Views/GenerativeCoverMetrics.swift, vreader/Views/LibraryProgressRing.swift, vreader/Views/Shared/CoverPickCoordinator.swift, vreader/Models/LibraryBookItem.swift, vreader/Models/LibrarySortOrder.swift, vreader/Models/GenerativeCoverStyle.swift, vreader/Models/ReaderThemeV2.swift, vreader/Services/CustomCoverStore.swift, vreader/Services/LibraryRefreshService.swift, vreader/Views/Library/LibrarySearchBar.swift, vreader/Views/ScreenSpaceDemo.swift, vreader/Views/ContentView.swift, vreader/Services/DictionaryLookup.swift, vreader/Services/LibraryPersisting.swift, vreader/Services/Backup/LazyDownloadCoordinator.swift, vreader/Services/Backup/WebDAVProviderFactory.swift, vreader/Services/BookImporter.swift, vreader/Services/AI/AIReaderAvailability.swift, vreader/Services/PersistenceActor+Collections.swift, vreader/Services/Sync/NSUKVSBridge.swift, vreader/Views/OPDS/OPDSEntryView.swift, vreader/Views/Reader/ReaderNotifications.swift, vreader/Services/DebugBridge/DebugBridgeNotifications.swift, vreader/ViewModels/ReaderLifecycleHelper.swift, vreader/App/VReaderApp.swift, vreader/App/TestSeeder.swift, dev-docs/designs/vreader-fidelity-v1/project/vreader-library.jsx, docs/bugs.md, archive/bugs-history.md, docs/features.md
