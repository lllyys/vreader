# Full Project Refactor

---
title: "Full Project Refactor"
created_at: "2026-03-10 21:40 CST"
revised_at: "2026-03-11 02:15 CST"
mode: "full-plan"
revision: "v5 — incorporates second Codex gpt-5.4 review (thread 019cd854)"
---

## Outcomes

- **Desired behavior**: Phase 1 brings all major offenders under ~300 lines. Files with cohesive single-algorithm logic (MDAttributedStringRenderer, QuoteRecovery, ReadingSessionTracker) are documented exceptions. Duplicated logic between bridges and containers is extracted. ViewModels adopt shared services.
- **Constraints**: Zero behavior changes — all existing functionality must work identically after refactor. No new features.
- **Non-goals**: Changing persistence layer, adding features, rewriting the search pipeline, changing the UI, modifying the SwiftData schema.

## Constraints & Dependencies

- Runtime: iOS 17+, Swift 6, Xcode 26
- SwiftData schema: unchanged (SchemaV1)
- No external service changes
- Feature flags: none (pure refactor)
- Build gate: `xcodebuild build` must pass after every WI
- Test gate (`ut`): `xcodebuild test -project vreader.xcodeproj -scheme vreader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` — this IS the `ut` command for this project. Must pass after every WI.
- pbxproj: new files added to Xcode project in each WI's commit (not deferred)
- **All WIs are fully serialized** (v5): Every WI that adds files touches `project.pbxproj`. No parallel tracks — execute one WI at a time in the order defined in Execution Order. This eliminates merge conflicts and semantic drift.

## Current Behavior Inventory

### Files Over 300 Lines (Convention Violation)

| File | Lines | Concern |
|------|-------|---------|
| ReaderContainerView.swift | 739 | Format dispatcher + chrome + annotations panel + sheets |
| TXTChunkedReaderBridge.swift | 583 | Chunked UITableView rendering + highlights + edit menu + scroll |
| TXTTextViewBridge.swift | 532 | Single UITextView rendering + highlights + edit menu + scroll |
| TXTReaderViewModel.swift | 490 | File I/O + position save + session tracking + selection + word count |
| MDAttributedStringRenderer.swift | 451 | Full markdown→NSAttributedString pipeline |
| TXTReaderContainerView.swift | 429 | Layout + notification handlers + highlight loading + bottom overlay |
| SearchIndexStore.swift | 414 | FTS5 database: create, insert, query, maintenance |
| EPUBReaderViewModel.swift | 397 | EPUB state management |
| MDReaderViewModel.swift | 394 | MD state management |
| PDFReaderViewModel.swift | 374 | PDF state management |
| QuoteRecovery.swift | 329 | Reflow recovery algorithm |
| ReadingSessionTracker.swift | 323 | Time aggregation |
| EPUBParser.swift | 303 | ZIP + OPF parsing |
| BookImporter.swift | 303 | Import orchestration |

### Documented Exceptions (Cohesive Single-Purpose Files)

These files exceed 300 lines but contain a single cohesive algorithm or pipeline. Splitting them would reduce cohesion without meaningful benefit:

| File | Lines (post-refactor) | Rationale |
|------|----------------------|-----------|
| TXTChunkedReaderBridge.swift | ~530 | Chunked UITableView renderer — cell config, scroll tracking, highlight projection, and chunk-local range conversion are tightly coupled. Further split would scatter the chunk↔global offset contract across files (v3 — audit addition) |
| MDAttributedStringRenderer.swift | 451 | Single markdown→NSAttributedString rendering pipeline |
| ReaderContainerView.swift | ~450 | Format dispatcher + SwiftUI toolbar/sheet/dismiss APIs require parent-level ownership. Private @ViewBuilder methods improve readability without extraction (v3 — audit addition) |
| QuoteRecovery.swift | 329 | Single reflow recovery algorithm |
| ReadingSessionTracker.swift | 323 | Single time-aggregation state machine |
| EPUBParser.swift | 303 | ZIP extraction + OPF parsing — tightly coupled |
| BookImporter.swift | 303 | Import orchestration — at the boundary |

### Key Duplication Hotspots

1. **TXT bridges** (~80 lines truly duplicated): edit menu construction (`editMenuForTextIn`), selection notification posting (`postSelectionNotification`/`postChunkedSelectionNotification`), content tap handler (`handleContentTap`), `gestureRecognizer(shouldRecognizeSimultaneouslyWith)`. Highlight state management is **NOT** duplicated — single-TV uses coordinator ranges while chunked uses chunk-local projection.
2. **Container views** (~100 lines duplicated): `.onReceive` blocks for `readerBookmarkRequested`, `readerContentTapped`, `readerNavigateToLocator`, `readerHighlightRequested`, `readerAnnotationRequested` + the AddNoteSheet presentation — nearly identical in TXTReaderContainerView and MDReaderContainerView.
3. **Reader ViewModels** (~60 lines per VM): position save debouncing and session tracking lifecycle.

### Known Invariants

- HighlightableTextView + HighlightingLayoutManager must stay together (bug #47 v12 crash fix)
- TXTViewConfig is shared between both bridges — must stay single definition
- TXTTextViewBridgeDelegate protocol is the callback interface for both bridges
- Notification names + TextSelectionInfo live in ReaderContainerView.swift — shared by bridges and containers
- PersistenceActor extensions are split by domain (Library, Bookmarks, Highlights, etc.) — keep this pattern

## Target Rules

1. **Phase 1 target: all actively-refactored files under 300 lines**. Documented exceptions list above is the only carve-out.
2. **No duplicate logic across bridges** — scope: menu construction, notification posting, content-tap handler, `gestureRecognizer(shouldRecognizeSimultaneouslyWith)`. All 4 patterns are 100% identical between bridges. Highlight state management stays format-specific.
3. **Single responsibility per ViewModel** — extract reusable position-save debouncing into a shared service.
4. **Container notification setup is DRY (TXT/MD only)** — identical `.onReceive` blocks for 4 notifications + AddNoteSheet extracted to a shared ViewModifier. EPUB/PDF only have 3 base notifications (bookmark, contentTapped, navigate) and lack highlight/annotation — they stay as-is (too little duplication to justify modifier overhead).
5. **Extract, don't rewrite** — move code into new files, update imports. No logic changes.
6. **Shared types get their own file** — `Notification.Name` extensions and `TextSelectionInfo` move to a dedicated coordination-types file.

## Decision Log

- **D1: Shared bridge logic extraction approach**
  - Options: (A) Protocol extension on Coordinator, (B) Free functions in a shared file, (C) Base class for Coordinator
  - Decision: (B) Free functions + shared types in `TXTBridgeShared.swift`
  - Rationale: Coordinators inherit from NSObject with different UIKit delegate conformances. Free functions are simplest and testable.
  - Rejected: (A) protocol extensions on NSObject subclasses are awkward; (C) multiple inheritance not supported.
  - **Scope (v4)**: Extract all 4 identical patterns: `buildReaderEditMenu()`, `postSelectionNotification()`, `handleContentTap()` (3-line notification post), `gestureRecognizer(shouldRecognizeSimultaneouslyWith)` (returns `true`). Total ~10 additional lines beyond v2 scope. Do NOT extract highlight state — it's structurally different between single-TV (coordinator ranges) and chunked (chunk-local projection with binary search).

- **D2: Container notification extraction approach**
  - Options: (A) SwiftUI ViewModifier, (B) Shared helper function returning [AnyCancellable], (C) Base protocol with default implementation
  - Decision: (A) SwiftUI ViewModifier — `ReaderNotificationModifier`
  - Rationale: `.modifier()` composes cleanly. Closures for format-specific behavior (locator factory method, text source).
  - **Contract (v4 — Codex review fix)**: Modifier handles these **4** notifications: `readerBookmarkRequested`, `readerNavigateToLocator`, `readerHighlightRequested`, `readerAnnotationRequested`. Plus the `AddNoteSheet` presentation (`.sheet` owned by the modifier, attached to the modified view). **`readerContentTapped` stays local** in each container — it toggles `isChromeVisible` which is `@State` on the container.
  - **Full dependency contract (v4 — Codex review fix)**: The modifier requires these parameters:
    - `modelContainer: ModelContainer` — for PersistenceActor creation (bookmark/highlight/annotation writes)
    - `bookFingerprintKey: String` — book identity for persistence
    - `bookFingerprint: DocumentFingerprint` — for locator construction
    - `locatorFactory: (DocumentFingerprint, _ charRangeStartUTF16: Int, _ charRangeEndUTF16: Int, _ selectedText: String?) -> Locator?` — format-specific (`.txtRange` vs `.mdRange`). The two `Int` params are UTF-16 start and end offsets of the selected text range (v5 — label fix).
    - `sourceText: () -> String?` — closure returning VM's text content (TXT: `textContent`, MD: `renderedText`)
    - `makeCurrentLocator: () -> Locator?` — for bookmark creation at current position
    - `onNavigate: (_ charOffsetUTF16: Int) -> Void` — callback to update VM scroll position
  - **Identity-stable closures (v5)**: All closures passed to the modifier MUST be instance methods or stored properties on the container, NOT inline closures in `body`. Pattern: define `private func handleNavigate(_ offset: Int)` on the container and pass `self.handleNavigate` to the modifier. This prevents SwiftUI identity churn from re-creating the modifier on every render.
    - Bindings: `scrollToOffset: Binding<Int?>`, `highlightRange: Binding<NSRange?>`, `highlightIsTemporary: Binding<Bool>`, `persistedHighlightRanges: Binding<[NSRange]>`, `pendingAnnotationInfo: Binding<TextSelectionInfo?>`, `annotationNoteText: Binding<String>`
  - **Sheet placement (v4)**: The modifier owns a single `.sheet(isPresented:)` for `AddNoteSheet`, computed from `pendingAnnotationInfo != nil`. This sheet is applied inside the modifier body via `content.sheet(...)`. Containers must NOT also attach an AddNoteSheet — the modifier is the single owner.
  - **@State ownership (v3 — audit fix)**: Modifier uses `@Binding` parameters owned by the container view, NOT its own `@State`. This avoids identity-dependent state reset if SwiftUI recreates the modifier.
  - **Handler ordering (v3 — audit fix)**: `.onReceive` must be applied as: bookmark → navigate → highlight → annotation (same order as current inline code).
  - Chrome toggle (`readerContentTapped`) and scene-phase handling stay local (they depend on `@State`/`@Environment` that can't cross modifier boundary cleanly).
  - **Scope: TXT and MD only (v4)**: EPUB/PDF only have 3 base notifications and lack highlight/annotation support. Applying the modifier there would add unused handlers. EPUB/PDF containers keep their inline `.onReceive` blocks.

- **D3: ViewModel decomposition approach**
  - Options: (A) Abstract base class, (B) Extract services that VMs call, (C) Protocol with default implementations
  - Decision: (B) Extract `ReaderPositionService`
  - **Scope revision (v3 — audit fix)**: Service handles: debounce timer, immediate save on close/background, persistence call. Service does NOT handle: locator construction (format-specific), restore-suppression timing (**ViewModel-specific**, not bridge-specific — `restoreSuppressUntil` and `isOpenComplete` guards live in each VM's `updateScrollPosition`), session tracking (already in ReadingSessionTracker).
  - **Service lifecycle (v5 — Codex review fix)**:
    - **Actor isolation**: `@MainActor` — all ViewModel callers are `@MainActor`, debounce `Task` must be on MainActor to safely cancel.
    - **Creation**: Each ViewModel creates its own `ReaderPositionService` in `init()`, passing `bookFingerprintKey` and `persistence`. One service instance per book open.
    - **Teardown**: VM's `close()` calls `cancel()` then `await saveNow(locator:)`. On VM `deinit`, `cancel()` is called defensively (idempotent). If book open fails (error in `openBook()`), service is never used — `cancel()` in `deinit` is safe no-op.
    - **Cancellation semantics**: `cancel()` cancels the pending debounce `Task` but does NOT prevent a subsequent `saveNow()` call. `saveNow()` always executes regardless of cancel state. This prevents the cancel→saveNow ordering bug.
    - **Clock injection (v5)**: Init takes optional `debounceNanoseconds: UInt64 = 2_000_000_000`. Tests pass `0` or a small value for deterministic testing. No abstract clock protocol needed — the debounce uses `Task.sleep(nanoseconds:)` which is cancellable.
  - **`saveNow` contract (v3 — audit fix)**: `saveNow(locator:)` is `async` and callers MUST `await` it. It is NOT fire-and-forget (bug #24's root cause was fire-and-forget position save racing with process suspension). `close()` sequence in VMs: cancel debounce → `await saveNow` → recordProgress → endSession → recomputeStats → postNotification. This order is load-bearing (bugs #34, #45).
  - **`beginBackgroundTask` stays in container views (v3 — audit fix)**: The background task assertion pattern (`UIApplication.shared.beginBackgroundTask`) stays in container views where `scenePhase` is observed. The service's `saveNow` is a plain `async` function the container awaits inside the background task.
  - Estimated ~130 lines (v5 — +10 for lifecycle guards). Mandatory adoption in all 4 VMs in WI-008.

- **D4: ReaderContainerView split strategy**
  - Decision: Split by concern — extract `AnnotationsPanelView` (owns VM creation + navigation posting), extract shared types file. Chrome (toolbar, `.toolbar` modifiers, sheet presentations) stays in ReaderContainerView as view-builder methods since SwiftUI toolbar/sheet APIs require parent-level ownership.
  - **Revision (v2)**: Drop `ReaderChromeView` extraction — SwiftUI `toolbar`, `sheet`, `dismiss`, and navigation-bar visibility must be controlled at the parent level. Instead, refactor inline code to private view-builder methods (`@ViewBuilder private var toolbarContent`, etc.) to improve readability without extracting to a separate file.

- **D5: SearchIndexStore split approach (new in v2, API frozen v4)**
  - Decision: Introduce `SearchIndexCore` (owns `db` + `lock`) as the shared foundation. `SearchIndexStore` retains schema + insert + maintenance. `SearchQueryExecutor` gets query + result mapping + snippet extraction. Both reference `SearchIndexCore`, not raw `OpaquePointer`.
  - **Frozen API (v5 — typed binder fix)**: `SearchIndexCore` exposes ONLY whole-statement execution methods — prepared statements must NOT escape the lock scope:
    - `withLock<T>(_ body: (OpaquePointer) throws -> T) rethrows -> T` — raw DB access within lock (escape hatch)
    - `exec(_ sql: String) throws` — fire-and-forget SQL
    - `query<T>(_ sql: String, bind: [SQLiteValue], map: (OpaquePointer) -> T) throws -> [T]` — prepare+bind+step+finalize within a single call, returns mapped results
    - `enum SQLiteValue { case text(String), integer(Int64), real(Double), blob(Data), null }` — typed binding values, no `[Any]` (v5 — Codex review fix). The `bind` implementation switches on enum cases to call `sqlite3_bind_text/int64/double/blob/null` — safe, exhaustive, no runtime type guessing.
    - Init opens `:memory:` DB. Deinit closes.
    - No `prepare()` that returns `OpaquePointer` — prevents statement lifetime bugs.
  - **Pagination ownership (v5)**: Pagination (limit/offset) lives in `SearchQueryExecutor.search(query:bookFingerprintKey:limit:offset:)`. The executor adds `LIMIT ? OFFSET ?` to the FTS5 query. `SearchIndexStore.search()` delegates to executor and passes through limit/offset. `SearchService` and `SearchViewModel` pagination logic (page size 20, loadMore) is unchanged.
  - **Public API preservation (v4)**: `SearchIndexStore`'s external API (`init`, `indexBook`, `removeBook`, `search`, `tokenSpans`, `isBookIndexed`) is unchanged. `SearchService` is the actual public contract consumed by `SearchViewModel`/`ReaderContainerView`. The split is internal to the search module.

- **D6: Shared coordination types (new in v2)**
  - Decision: Move `Notification.Name` extensions and `TextSelectionInfo` from ReaderContainerView.swift to new `ReaderNotifications.swift`. Both bridges and all containers import it.

## Open Questions

- **Q1: Should MDAttributedStringRenderer (451 lines) be split?**
  - Default: No — documented exception. Single cohesive pipeline.

- **Q2: Should QuoteRecovery (329 lines) be split?**
  - Default: No — documented exception. Single algorithm.

## Work Items

### WI-001: Extract HighlightableTextView + HighlightingLayoutManager

- **Goal**: Move `HighlightingLayoutManager` and `HighlightableTextView` (bug #47 v12) to their own file. Pure extraction, zero logic change.
- **Acceptance**:
  - New file `vreader/Views/Reader/HighlightableTextView.swift` ≤ 115 lines.
  - TXTTextViewBridge.swift drops to ~417 lines.
  - Build passes. Highlight rendering unchanged.
- **Tests (first)**:
  - File: `vreaderTests/Views/Reader/HighlightableTextViewTests.swift`
  - Intent: Test `setHighlightRanges()` updates layout manager ranges. Test `setSourceText()` sets text storage content. Test `isReplacingText` guard flag.
- **Touched areas**:
  - New: `vreader/Views/Reader/HighlightableTextView.swift`
  - Modified: `vreader/Views/Reader/TXTTextViewBridge.swift` — remove classes
  - Modified: `vreader.xcodeproj/project.pbxproj` — add new file
- **Dependencies**: None (first WI, smallest risk)
- **Risks**: Low — pure extraction.
- **Rollback**: Revert single commit.
- **Estimate**: S

### WI-002: Extract shared TXT bridge logic + ReaderNotifications

- **Goal**: Extract truly-duplicated bridge code and shared notification types.
- **Extraction map** (precise):
  - **Move to `ReaderNotifications.swift`**: `Notification.Name` extensions (lines 33-53 of ReaderContainerView.swift), `TextSelectionInfo` struct (lines 55-59).
  - **Move to `TXTBridgeShared.swift`** (v4 — expanded per Codex review):
    - `buildReaderEditMenu(range:chunkOffset:textView:)` — unified edit menu factory (~20 lines)
    - `postSelectionNotification(_:from:range:chunkOffset:)` — unified notification posting (~15 lines; accepts optional `chunkOffset` defaulting to 0)
    - `handleContentTap(_:)` — identical 3-line notification post. Extracted as free function `postContentTappedNotification()` that coordinators call from their `@objc handleContentTap` method (the `@objc` method stays on each coordinator since it's a gesture recognizer target, but the body becomes a one-liner calling the shared function).
    - `gestureRecognizerShouldRecognizeSimultaneously() -> Bool` — returns `true`. Both coordinators' `UIGestureRecognizerDelegate` conformance calls this shared function.
  - **Do NOT move**: Highlight state management, `rebuildHighlights`, `chunkLocalHighlightRanges`, scroll handling, selection-change-to-delegate callbacks — these are structurally different.
- **Acceptance**:
  - `ReaderNotifications.swift` ≤ 35 lines.
  - `TXTBridgeShared.swift` ≤ 90 lines (was 80 in v3; +10 for tap handler + gesture recognizer).
  - TXTTextViewBridge.swift ≤ 380 lines.
  - TXTChunkedReaderBridge.swift ≤ 530 lines.
  - ReaderContainerView.swift drops ~30 lines.
  - Build passes. Edit menu and selection behavior unchanged.
- **Tests (first)**:
  - File: `vreaderTests/Views/Reader/TXTBridgeSharedTests.swift`
  - Intent: Test `postSelectionNotification()` with valid/empty/out-of-bounds ranges and with/without chunkOffset. Test `buildReaderEditMenu()` returns 2 UIActions with correct titles.
- **Touched areas**:
  - New: `vreader/Views/Reader/ReaderNotifications.swift`
  - New: `vreader/Views/Reader/TXTBridgeShared.swift`
  - Modified: `vreader/Views/Reader/TXTTextViewBridge.swift` — coordinator calls shared functions
  - Modified: `vreader/Views/Reader/TXTChunkedReaderBridge.swift` — coordinator calls shared functions
  - Modified: `vreader/Views/Reader/ReaderContainerView.swift` — remove moved types
  - Modified: `vreader.xcodeproj/project.pbxproj`
- **Dependencies**: WI-001 (both modify TXTTextViewBridge.swift — must be sequential)
- **Risks**: Edit menu behavior could change if function signatures don't match → test both bridge types manually.
- **Rollback**: Revert single commit.
- **Estimate**: M

### WI-003: Extract ReaderNotificationModifier

- **Goal**: Eliminate ~80 lines of duplicate `.onReceive` notification handlers in TXT and MD container views (only — EPUB/PDF stay as-is per Rule 4).
- **Modifier contract (v4 — full dependency specification)**:
  - **Notifications owned (4)**: `readerBookmarkRequested`, `readerNavigateToLocator`, `readerHighlightRequested`, `readerAnnotationRequested`. **`readerContentTapped` stays local**.
  - **Init parameters**:
    - `modelContainer: ModelContainer` — for PersistenceActor creation
    - `bookFingerprintKey: String` — book identity
    - `bookFingerprint: DocumentFingerprint` — for locator construction
    - `locatorFactory: @escaping (DocumentFingerprint, Int, Int, String?) -> Locator?` — format-specific
    - `sourceText: @escaping () -> String?` — returns VM's text content
    - `makeCurrentLocator: @escaping () -> Locator?` — for bookmark at current position
    - `onNavigate: @escaping (Int) -> Void` — updates VM scroll position
  - **Bindings (owned by container, received as Binding)**: `scrollToOffset`, `highlightRange`, `highlightIsTemporary`, `persistedHighlightRanges`, `pendingAnnotationInfo`, `annotationNoteText`
  - **Sheet ownership (v4)**: Modifier owns the `AddNoteSheet` `.sheet(isPresented:)` via computed binding on `pendingAnnotationInfo != nil`. Containers must NOT attach their own AddNoteSheet — modifier is single owner.
  - **Stays local in container**: `isChromeVisible` toggle, `scenePhase` handling, body layout, loading/error views
  - **Handler ordering**: bookmark → navigate → highlight → annotation
- **Acceptance**:
  - New `ReaderNotificationModifier.swift` ≤ 140 lines (including AddNoteSheet presentation).
  - TXTReaderContainerView.swift ≤ 330 lines.
  - MDReaderContainerView.swift ≤ 200 lines.
  - Build passes. Notification handling unchanged.
- **Handler state carrier (v5 — Codex review fix)**: Extract a `ReaderNotificationHandlerState` class/struct that holds all mutable bindings as writable properties. The plain handler functions receive this state object + dependencies (persistence, locatorFactory, etc.) as parameters. This makes the functions pure-ish: input → state mutation + async persistence call. The modifier constructs this state carrier from its bindings on each `.onReceive`.
- **Tests (first) (v5 — revised)**:
  - File: `vreaderTests/Views/Reader/ReaderNotificationHandlerTests.swift`
  - Strategy: Test the plain handler functions against a mock `ReaderNotificationHandlerState` and mock `ReadingPositionPersisting`/`BookmarkPersisting`/`HighlightPersisting`/`AnnotationPersisting`. No SwiftUI view-inspection needed.
  - Intent: Test `handleBookmarkRequest()` calls `makeCurrentLocator` and persistence. Test `handleNavigateToLocator()` sets scrollToOffset and highlightRange from locator fields. Test `handleHighlightRequest()` calls locatorFactory and persistence, appends to persistedHighlightRanges. Test `handleAnnotationRequest()` sets pendingAnnotationInfo.
  - **AddNoteSheet flow (v5)**: Test `handleAnnotationSave()` trims whitespace, validates non-empty, calls persistence, clears `pendingAnnotationInfo` and `annotationNoteText`. Test `handleAnnotationCancel()` clears state without persistence call. Test empty note text → no persistence call.
  - **Regression tests (v4)**: Test highlight creation with empty selection (no-op). Test navigation with nil charOffsetUTF16 (fallback to charRangeStartUTF16).
- **Touched areas**:
  - New: `vreader/Views/Reader/ReaderNotificationModifier.swift`
  - Modified: `vreader/Views/Reader/TXTReaderContainerView.swift` — replace .onReceive blocks
  - Modified: `vreader/Views/Reader/MDReaderContainerView.swift` — replace .onReceive blocks
  - Modified: `vreader.xcodeproj/project.pbxproj`
- **Dependencies**: WI-002 (ReaderNotifications.swift must exist)
- **Risks**: SwiftUI modifier lifecycle may differ from inline `.onReceive` → test highlight creation + annotation flow manually. Closure params to modifier must be identity-stable (not inline closures that change every render).
- **Rollback**: Revert single commit.
- **Estimate**: M
- **Checkpoint (v5)**: After WI-003 merges, run full manual annotation regression before proceeding to WI-004: create bookmark, highlight text, add note, navigate from panel, dismiss sheet, verify all persist. This is the most stateful SwiftUI refactor in the plan.

### WI-004: Split ReaderContainerView

- **Goal**: Extract AnnotationsPanelView. Refactor chrome to private view-builder methods.
- **Split plan**:
  - **Extract**: `AnnotationsPanelView` with explicit interface (v4 — Codex review fix):
    - Init: `book: Book`, `modelContainer: ModelContainer`, `tocEntries: [TOCEntry]`, `onNavigate: (Locator) -> Void`, `onDismiss: () -> Void`
    - Owns: 4-tab `Picker` (Bookmarks, TOC, Highlights, Annotations), `@State selectedTab: AnnotationTab`
    - Creates VMs: `HighlightListViewModel`, `AnnotationListViewModel`, `BookmarkListViewModel` — each initialized with `modelContainer` and `book.fingerprintKey`
    - Calls `onNavigate(locator)` when user taps any item; calls `onDismiss()` when sheet is dismissed
    - Does NOT own: sheet presentation/dismiss (`.sheet` stays on parent per SwiftUI rules), toolbar state, search state
  - **Keep in ReaderContainerView**: format dispatch, toolbar, sheet presentations (`.sheet` must be parent-level), `isChromeVisible` state, search wiring, indexing orchestration, `@State isAnnotationsPanelPresented` controlling the panel sheet.
  - **Refactor inline**: Extract `@ViewBuilder private var toolbarContent: some ToolbarContent`, `@ViewBuilder private func formatContent(...)`, etc. for readability.
  - **Already moved in WI-002**: `Notification.Name` extensions + `TextSelectionInfo`.
- **Acceptance**:
  - ReaderContainerView.swift ≤ 450 lines (down from 739; ~250 lines moved to panel + ~30 to notifications).
  - New `AnnotationsPanelView.swift` ≤ 250 lines.
  - Build passes. Reader UI unchanged.
- **Tests (first)**:
  - File: `vreaderTests/Views/Reader/AnnotationsPanelViewTests.swift`
  - Intent: Test `onNavigate` closure fires when VM's navigation callback executes (test observable output, not internal VM type — v5 fix). Test `onDismiss` fires on sheet dismiss. Test empty data renders without crash. Test that passing `tocEntries` populates TOC tab.
- **Touched areas**:
  - Modified: `vreader/Views/Reader/ReaderContainerView.swift` — extract panel, add view-builders
  - New: `vreader/Views/Reader/AnnotationsPanelView.swift`
  - Modified: `vreader.xcodeproj/project.pbxproj`
- **Dependencies**: WI-002 (shared types file)
- **Risks**: SwiftUI `@State`/`@Binding` wiring across extracted panel → verify sheet presentation/dismiss and navigation callbacks manually.
- **Rollback**: Revert single commit.
- **Estimate**: L

### WI-005: Extract ReaderBottomOverlay

- **Goal**: Extract bottom overlay (progress bar, session timer) from TXTReaderContainerView.
- **Acceptance**:
  - New `ReaderBottomOverlay.swift` ≤ 80 lines.
  - TXTReaderContainerView.swift ≤ 300 lines.
  - Build passes. Bottom overlay UI unchanged.
- **Tests (first)**:
  - File: `vreaderTests/Views/Reader/ReaderBottomOverlayTests.swift`
  - Intent: Test progress percentage formatting, time display.
- **Touched areas**:
  - New: `vreader/Views/Reader/ReaderBottomOverlay.swift`
  - Modified: `vreader/Views/Reader/TXTReaderContainerView.swift`
  - Modified: `vreader.xcodeproj/project.pbxproj`
- **Dependencies**: WI-003 (notification modifier reduces file first)
- **Risks**: Low — pure UI extraction.
- **Rollback**: Revert single commit.
- **Estimate**: S

### WI-006: Extract ReaderPositionService

- **Goal**: Create `ReaderPositionService` as a standalone file with full test coverage. **Service-only — no adopters in this WI** (v5 — Codex review fix). Adoption happens in WI-008a–d.
- **Service scope**:
  - `scheduleSave(locator:)` — debounced save via `PersistenceActor`
  - `saveNow(locator:)` — immediate save for close/background
  - `cancel()` — cancel pending debounce on dealloc
  - Init: `bookFingerprintKey: String`, `persistence: ReadingPositionPersisting`, `debounceNanoseconds: UInt64 = 2_000_000_000`
  - `@MainActor` isolation. One instance per book open. See D3 lifecycle spec.
  - Does NOT handle: locator construction (format-specific, stays in VM), restore-suppression (VM-specific), session tracking (already ReadingSessionTracker)
- **Acceptance**:
  - New `ReaderPositionService.swift` ≤ 130 lines.
  - No other files modified (service-only WI — v5).
  - All service tests pass in isolation.
  - Build passes.
- **Tests (first)**:
  - File: `vreaderTests/Services/ReaderPositionServiceTests.swift`
  - Intent: Test debounce with `debounceNanoseconds: 0` for deterministic results (v5 — clock fix). Test `saveNow` calls persistence immediately. Test `cancel` prevents pending save. Mock `ReadingPositionPersisting` for isolation.
  - **Regression tests (v4 — bugs #24, #25, #34, #45)**: Test `saveNow` is truly `async` and awaitable (not fire-and-forget). Test rapid scheduleSave+saveNow interleaving (saveNow must always complete). Test cancel→saveNow ordering (cancel must not suppress the final save). Test deinit calls cancel (no leaked tasks).
- **Touched areas**:
  - New: `vreader/Services/ReaderPositionService.swift`
  - New: `vreaderTests/Services/ReaderPositionServiceTests.swift`
  - Modified: `vreader.xcodeproj/project.pbxproj`
- **Dependencies**: None (independent)
- **Risks**: Low — no adoption, no behavior change. Service is tested in isolation before any VM touches it.
- **Rollback**: Revert single commit.
- **Estimate**: M

### WI-007: Split SearchIndexStore

- **Goal**: Split SearchIndexStore into 3 focused files: core DB, index management, query execution.
- **Split plan (v4 — frozen API per D5)**:
  - **`SearchIndexCore.swift`** (~70 lines): Owns `db: OpaquePointer?` + `lock: OSAllocatedUnfairLock`. API per D5 frozen contract: `withLock`, `exec`, `query` (prepare+bind+step+finalize in one call). NO `prepare()` returning raw pointer.
  - **`SearchIndexStore.swift`** (~180 lines): Owns `SearchIndexCore`. Schema creation, `indexBook()`, `removeBook()`, `isBookIndexed()`. All `source_texts` and `token_spans` insert logic.
  - **`SearchQueryExecutor.swift`** (~180 lines): Takes `SearchIndexCore` reference. `search(query:bookFingerprintKey:limit:offset:)` — FTS5 query building, result mapping, snippet extraction, span-map lookups. Pagination via `LIMIT ? OFFSET ?` appended to FTS5 query (v5 — pagination ownership). `tokenSpans(fingerprintKey:sourceUnitId:normalizedToken:)` — span lookup. All queries use `core.query()` — no raw pointer access.
- **Public API preservation (v4)**: `SearchIndexStore`'s external methods (`init`, `indexBook`, `removeBook`, `search`, `tokenSpans`, `isBookIndexed`) remain unchanged. `SearchService` is the actual public contract — `SearchViewModel` and `ReaderContainerView` only call `SearchService` methods. The split is internal.
- **Acceptance**:
  - `SearchIndexCore.swift` ≤ 80 lines.
  - `SearchIndexStore.swift` ≤ 200 lines.
  - `SearchQueryExecutor.swift` ≤ 200 lines.
  - Build passes. Search behavior unchanged.
  - **Invariant (v4)**: `SearchService.swift` has zero diff (no API change).
- **Tests (first)**:
  - File: `vreaderTests/Services/Search/SearchQueryExecutorTests.swift`
  - Intent: Test FTS5 query building with CJK. Test snippet extraction returns correct offsets. Test empty query returns empty results.
  - **Regression tests (v4)**: Test concurrent `search()` calls don't deadlock or corrupt. Test CJK tokenization + span map lookup matches pre-split behavior (bug #1, #28).
- **Touched areas**:
  - New: `vreader/Services/Search/SearchIndexCore.swift`
  - New: `vreader/Services/Search/SearchQueryExecutor.swift`
  - Modified: `vreader/Services/Search/SearchIndexStore.swift` — extract core + query
  - Modified: `vreader.xcodeproj/project.pbxproj`
- **Dependencies**: None (independent). SearchService.swift is NOT modified.
- **Risks**: Lock/lifetime must be correct in SearchIndexCore → `query()` method owns full statement lifecycle. No prepared statements escape lock scope.
- **Rollback**: Revert single commit.
- **Estimate**: M

### WI-008a: Adopt ReaderPositionService in PDFReaderViewModel (v5 — first adopter, service proven in WI-006)

- **Goal**: First real adopter of `ReaderPositionService` (created in WI-006, tested in isolation). PDF has simplest position logic (page index) and lowest regression risk. Proves integration before applying to complex formats.
- **Decomposition**: Adopt ReaderPositionService (removes ~60 lines debounce/save). PDF VM does NOT need a FileLoader extraction — document loading lives in `PDFViewBridge.loadDocument()`, not the VM. The VM only owns page tracking, session tracking, and position persistence. Adopting the service alone brings it under 300 lines.
- **close() order (mandatory contract)**: cancel debounce → `await positionService.saveNow(locator)` → `sessionTracker.recordProgress(locator:)` → `sessionTracker.endSessionIfNeeded()` → `persistence.recomputeStats()` → post `.readerDidClose`. This order is load-bearing (bugs #34, #45).
- **Existing methods mapped**: `scheduleSave()` → `positionService.scheduleSave(locator:)`. `savePosition()` → `positionService.saveNow(locator:)`. `cancelDebounce()` → `positionService.cancel()`. `makeCurrentLocator()` stays local (page-index based).
- **Acceptance**:
  - PDFReaderViewModel.swift ≤ 300 lines.
  - No new file needed (no FileLoader for PDF).
  - Build passes. Position save/restore unchanged.
- **Tests (first)**:
  - File: `vreaderTests/ViewModels/PDFReaderViewModelTests.swift`
  - Intent: Test close() calls positionService.saveNow. Test page change triggers scheduleSave. Test background/foreground lifecycle.
- **Touched areas**:
  - Modified: `vreader/ViewModels/PDFReaderViewModel.swift`
  - Modified: `vreader.xcodeproj/project.pbxproj`
- **Dependencies**: WI-006 (ReaderPositionService must exist)
- **Risks**: Low — PDF position is page-index-based, no UTF-16 offsets, no suppress-window. Safest proving ground.
- **Rollback**: Revert single commit.
- **Estimate**: S

### WI-008b: Adopt ReaderPositionService in EPUBReaderViewModel (v4 — resequenced)

- **Goal**: Second adopter — EPUB uses href+progression positioning, moderately complex.
- **Decomposition**: Adopt ReaderPositionService. Extract `EPUBFileLoader` helper (~70 lines: `openBook()` containing parse call, spine setup, resource URL extraction — currently methods `loadBook()` and `setupSpine()` in the VM).
- **FileLoader error contract (v5)**: Returns `Result<EPUBLoadResult, Error>`. Errors propagate the original `EPUBParser` error types (missing OPF, invalid spine, etc.) — no wrapping or swallowing. Loading runs on a background actor; result is delivered to `@MainActor` VM via `await`. Cancellation: loader checks `Task.isCancelled` between parse and spine setup.
- **close() order**: Same mandatory contract as WI-008a.
- **Acceptance**:
  - EPUBReaderViewModel.swift ≤ 300 lines.
  - New `EPUBFileLoader.swift` ≤ 90 lines.
  - Build passes. Behavior unchanged.
- **Tests (first)**:
  - File: `vreaderTests/Services/EPUB/EPUBFileLoaderTests.swift`
  - Intent: Test EPUB loading returns metadata + spine items. Test error handling on invalid EPUB preserves original error message. Test cancellation mid-load.
- **Touched areas**:
  - Modified: `vreader/ViewModels/EPUBReaderViewModel.swift`
  - New: `vreader/Services/EPUB/EPUBFileLoader.swift`
  - Modified: `vreader.xcodeproj/project.pbxproj`
- **Dependencies**: WI-008a (proves service contract)
- **Rollback**: Revert single commit.
- **Estimate**: S

### WI-008c: Adopt ReaderPositionService in MDReaderViewModel (v4 — resequenced)

- **Goal**: Third adopter — MD shares TXT bridge and has similar position logic.
- **Decomposition**: Adopt ReaderPositionService. Extract `MDFileLoader` helper (~60 lines: `loadFile()` containing file read, markdown render call, metadata extraction — currently `openBook()` in the VM).
- **FileLoader error contract (v5)**: Returns `Result<MDLoadResult, Error>`. Errors propagate the original file-read and `MDAttributedStringRenderer` errors — no wrapping or swallowing. Loading runs on a background actor; result is delivered to `@MainActor` VM via `await`. Cancellation: loader checks `Task.isCancelled` between file read and render.
- **close() order**: Same mandatory contract as WI-008a.
- **Acceptance**:
  - MDReaderViewModel.swift ≤ 300 lines.
  - New `MDFileLoader.swift` ≤ 80 lines.
  - Build passes. Behavior unchanged.
- **Tests (first)**:
  - File: `vreaderTests/Services/MD/MDFileLoaderTests.swift`
  - Intent: Test markdown file loading returns attributed string. Test error handling preserves original error message. Test cancellation mid-load.
- **Touched areas**:
  - Modified: `vreader/ViewModels/MDReaderViewModel.swift`
  - New: `vreader/Services/MD/MDFileLoader.swift`
  - Modified: `vreader.xcodeproj/project.pbxproj`
- **Dependencies**: WI-008b (sequential to avoid pbxproj conflicts)
- **Rollback**: Revert single commit.
- **Estimate**: S

### WI-008d: Adopt ReaderPositionService in TXTReaderViewModel (v4 — resequenced, last)

- **Goal**: Final adopter — TXT has the most complex position logic (UTF-16 offsets, suppress-window, `isOpenComplete` guard). Applied last after service is proven on 3 simpler formats.
- **Decomposition**: Adopt ReaderPositionService (removes ~60 lines debounce/save). Extract `TXTFileLoader` helper (~80 lines: `loadFile()` containing file decode via `TXTService`, metadata extraction, word count, text chunking threshold decision — currently `openBook()` in the VM).
- **FileLoader error contract (v5)**: Returns `Result<TXTLoadResult, Error>`. Errors propagate the original `TXTService.decodeText` errors (encoding failures, file-not-found) — no wrapping or swallowing. Loading runs on a background actor; result is delivered to `@MainActor` VM via `await`. Cancellation: loader checks `Task.isCancelled` between decode and metadata extraction.
- **What stays in VM**: Published state, selection handling, `makeLocator()`, `estimatedWordsRead`, error display, session tracker lifecycle, `restoreSuppressUntil` / `isOpenComplete` guards (these are VM-specific, not service concerns).
- **close() order**: Same mandatory contract as WI-008a.
- **Acceptance**:
  - TXTReaderViewModel.swift ≤ 300 lines.
  - New `TXTFileLoader.swift` ≤ 100 lines.
  - Build passes. Position save/restore and session tracking unchanged.
- **Tests (first)**:
  - File: `vreaderTests/Services/TXT/TXTFileLoaderTests.swift`
  - Intent: Test file loading returns expected text/metadata. Test error handling preserves error messages. Test chunking threshold decision (>500K UTF-16 → chunked).
  - **Regression tests (v4)**: Test suppress-window still works after service adoption (restore doesn't overwrite immediate saves). Test rapid open/close doesn't lose position.
- **Touched areas**:
  - Modified: `vreader/ViewModels/TXTReaderViewModel.swift`
  - New: `vreader/Services/TXT/TXTFileLoader.swift`
  - Modified: `vreader.xcodeproj/project.pbxproj`
- **Dependencies**: WI-006
- **Rollback**: Revert single commit.
- **Estimate**: S

**Gate after WI-008d**: Grep for old debounce/save patterns across all 4 VMs. Zero matches confirms mandatory adoption complete.

## Execution Order (v5 — fully serialized, no interleaving)

```
WI-001 (HighlightableTV extraction)
  │
  ▼
WI-002 (bridge shared + ReaderNotifications)
  │
  ▼
WI-003 (notification modifier)
  │
  ▼
WI-004 (ReaderContainerView split)
  │
  ▼
WI-005 (bottom overlay)

WI-006 (position service) ─── can start after WI-001 (independent files)
  │
  ▼
WI-008a (PDF VM — simplest, proves service)
  │
  ▼
WI-008b (EPUB VM)
  │
  ▼
WI-008c (MD VM)
  │
  ▼
WI-008d (TXT VM — most complex, last)

WI-007 (SearchIndexStore split) ─── can start after WI-002 (independent files)
```

**All WIs are fully serialized** (v5 — Codex review fix). Reason: `project.pbxproj` is modified in nearly every WI. Parallel or interleaved WIs cause merge conflicts in this file. Execute one WI at a time, commit, then start the next.

**Three logical tracks** (all serialized — no interleaving):
- **Container track**: WI-001 → WI-002 → WI-003 → WI-004 → WI-005
- **ViewModel track**: WI-006 → WI-008a (PDF) → WI-008b (EPUB) → WI-008c (MD) → WI-008d (TXT)
- **Search track**: WI-007

**Sequencing rationale (v4)**: Position service adoption starts with PDF (simplest: page-index position, no suppress-window) and ends with TXT (most complex: UTF-16 offsets, `restoreSuppressUntil`, `isOpenComplete` guard, chunked/single-TV split). This proves the service contract on simple formats before risking the regression-heavy TXT path.

## Testing Procedures

- **Build gate**: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project vreader.xcodeproj -scheme vreader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
- **Test gate (v4)**: `xcodebuild test -project vreader.xcodeproj -scheme vreader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` — unit tests must pass after every WI.
- **When to run**: Both build gate and test gate after every WI commit, before moving to next WI.
- **Line count audit**: `find vreader/ -name "*.swift" -not -path "*/Tests/*" | xargs wc -l | sort -rn | head -20`
- **Codex audit gate (v5)**: After each WI is complete (build + test green), run a Codex `gpt-5.4` or `gpt-5.3-codex` mini audit on the changed files. Fix any findings before moving to the next WI.
- **Full gate**: Build + test + run on device, test highlight/search/bookmark/annotation flows manually.

## Manual Test Checklist

After all WIs complete:

- [ ] Open a small TXT file → highlight text → no crash, yellow highlight visible
- [ ] Open a large CJK TXT file (>500K) → highlight text → no crash, highlight visible per-chunk
- [ ] Search for text → tap result → scrolls to match with yellow highlight → auto-clears 3s
- [ ] Create bookmark → tap in annotations panel → navigates correctly
- [ ] Add note via edit menu → note appears in annotations panel with quoted text
- [ ] Close book → reopen → position restored, highlights visible
- [ ] Change theme → highlights re-render correctly
- [ ] Open EPUB, PDF, MD files → all reader features work (chrome toggle, settings, search)
- [ ] Verify: no production Swift file over 300 lines except documented exceptions

## Plan → Verify Handoff

**Evidence per WI:**
- Line count of all modified/new files
- `xcodebuild build` exit code 0
- `xcodebuild test` exit code 0 (v4)
- `git diff --stat` showing expected file changes

**Per-WI observable invariants (v4 — Codex review fix):**

| WI | Invariant to verify |
|----|---------------------|
| WI-001 | Highlight rendering in small TXT: select text → yellow highlight appears, persists across theme change |
| WI-002 | Edit menu in both TXT sizes: small file + large CJK file → "Highlight" and "Add Note" appear |
| WI-003 | Bookmark/highlight/annotation creation in TXT + MD: tap toolbar bookmark, select text → highlight, add note → all persist in annotations panel |
| WI-004 | Annotations panel: all 4 tabs render, tap items → navigate to position |
| WI-005 | Bottom overlay: progress % and session time display correctly |
| WI-006 | Position save: debounce fires after 2s idle. `saveNow` completes before process suspension. Rapid open/close doesn't lose position. |
| WI-007 | Search: CJK query returns results with correct snippets and offsets. Pagination works (20 per page). |
| WI-008a | PDF: position restored on reopen. Session time tracked. Background save works. |
| WI-008b | EPUB: position restored on reopen. Chapter navigation works. |
| WI-008c | MD: position restored on reopen. Highlights visible on reopen. |
| WI-008d | TXT: position restored on reopen. Suppress-window prevents ghost saves. Large file chunked rendering works. |

**Final verification:**
- All production Swift files under 300 lines (except documented exceptions: TXTChunkedReaderBridge, MDAttributedStringRenderer, ReaderContainerView, QuoteRecovery, ReadingSessionTracker, EPUBParser, BookImporter)
- No remaining references to extracted code in original locations
- Grep for duplicate notification handling patterns returns zero matches across TXT/MD containers
- Grep for duplicate edit menu construction returns zero matches across bridges
- Grep for old debounce/save patterns across all 4 VMs returns zero matches

---

## Appendix A: Complete App Inventory

_Generated 2026-03-10 from full codebase exploration. 136 production Swift files, 19,396 total lines._

### A.1 File Size Census (All Production Swift Files)

**Files over 300 lines (refactor targets):**

| # | File | Lines | Area | Refactor WI |
|---|------|-------|------|-------------|
| 1 | ReaderContainerView.swift | 739 | Views/Reader | WI-002, WI-004 |
| 2 | TXTChunkedReaderBridge.swift | 583 | Views/Reader | WI-001, WI-002 |
| 3 | TXTTextViewBridge.swift | 532 | Views/Reader | WI-001, WI-002 |
| 4 | TXTReaderViewModel.swift | 490 | ViewModels | WI-006, WI-008 |
| 5 | MDAttributedStringRenderer.swift | 451 | Services/MD | Exception |
| 6 | TXTReaderContainerView.swift | 429 | Views/Reader | WI-003, WI-005 |
| 7 | SearchIndexStore.swift | 414 | Services/Search | WI-007 |
| 8 | EPUBReaderViewModel.swift | 397 | ViewModels | WI-006, WI-008 |
| 9 | MDReaderViewModel.swift | 394 | ViewModels | WI-006, WI-008 |
| 10 | PDFReaderViewModel.swift | 374 | ViewModels | WI-006, WI-008 |
| 11 | QuoteRecovery.swift | 329 | Utils | Exception |
| 12 | ReadingSessionTracker.swift | 323 | Services | Exception |
| 13 | EPUBParser.swift | 303 | Services/EPUB | Exception |
| 14 | BookImporter.swift | 303 | Services | Exception |

**Files 200–300 lines (within convention, no action):**

| File | Lines | Area |
|------|-------|------|
| MDReaderContainerView.swift | 297 | Views/Reader |
| EPUBReaderContainerView.swift | 292 | Views/Reader |
| EPUBWebViewBridge.swift | 285 | Views/Reader |
| LocatorFactory.swift | 280 | Services/Locator |
| LibraryView.swift | 274 | Views |
| VReaderApp.swift | 268 | App |
| ZIPReader.swift | 260 | Services/EPUB |
| TestSeeder.swift | 245 | App (DEBUG) |
| KeychainService.swift | 236 | Services |
| LibraryViewModel.swift | 226 | ViewModels |
| ImportJobQueue.swift | 226 | Services |
| MDTextExtractor.swift | 217 | Services/Search |
| LocatorRestorer.swift | 216 | Services/Locator |
| SearchService.swift | 213 | Services/Search |
| EncodingDetector.swift | 211 | Utils |
| PDFReaderContainerView.swift | 209 | Views/Reader |
| AIAssistantViewModel.swift | 209 | ViewModels |
| SyncConflictResolver.swift | 208 | Services/Sync |
| TXTChunkedLoader.swift | 204 | Services/TXT |
| TXTService.swift | 200 | Services/TXT |

**Files under 200 lines (96 files, healthy):** ReaderSettingsPanel (195), AIProvider (189), PDFViewBridge (175), Locator (174), SearchViewModel (172), HighlightListViewModel (170), EPUBTextExtractor (169), ScreenSpaceDemo (167), BackgroundIndexingCoordinator (153), AccessibilityFormatters (152), ReaderSettingsStore (151), PersistenceActor (148), HighlightListView (146), SearchHitToLocatorResolver (144), BookmarkListView (143), SearchView (142), AnnotationListView (138), AIService (136), BookmarkListViewModel (135), TXTOffsetMapper (133), and 76 more files under 130 lines.

### A.2 Feature & Behavior Matrix

#### Library

| Feature | Status | Key Files | Notes |
|---------|--------|-----------|-------|
| Grid/List display toggle | Working | LibraryView, LibraryViewModel | Feature #6/#19: mode not persisted |
| Sort by title/addedAt/lastRead/readingTime | Working | LibraryViewModel.sorted() | Feature #6: sort not persisted |
| Pull-to-refresh (throttled 5s) | Working | LibraryViewModel.refresh() | |
| Book import (EPUB/PDF/TXT/MD) | Working | BookImporter (303 lines) | 12-step pipeline, atomic sandbox copy |
| Swipe/context-menu delete | Working | LibraryView | Cascade deletes all related data |
| Reading time display | Working | BookCardView, BookRowView | Omitted if zero |
| Reading speed display | Working | BookCardView, BookRowView | pages/hr or wpm |
| Format badges | Working | BookCardView, BookRowView | Color-coded + icon |
| Empty state + import CTA | Working | LibraryView.emptyState | |
| Accessibility labels | Working | AccessibilityFormatters | Dynamic Type supported |
| Sync status badge | Working (gated) | SyncStatusView | Hidden when sync disabled |

#### TXT Reader

| Feature | Status | Key Files | Notes |
|---------|--------|-----------|-------|
| Small file rendering (UITextView) | Working | TXTTextViewBridge (532) | Single UITextView |
| Large file chunked rendering (UITableView) | Working | TXTChunkedReaderBridge (583) | >500k UTF-16 threshold |
| Theme/font/line-spacing application | Working | ReaderSettingsStore → TXTViewConfig | Live update triggers rebuild |
| CJK spacing | Working | TXTViewConfig.letterSpacing | 0.05em equivalent |
| Position save (debounced 2s) | Working | TXTReaderViewModel | Full Locator with quote/context |
| Position restore on reopen | Working | TXTReaderContainerView | Phase 2 restore at t+0.05s, fade-in |
| Highlight via edit menu | Working | Coordinator.editMenuForTextIn | Bug #44 FIXED |
| Add Note via edit menu | Working | Coordinator.editMenuForTextIn | Bug #44 FIXED |
| Persisted highlight rendering | Working | HighlightingLayoutManager.drawBackground() | Bug #47 v12 — zero text storage mutation |
| Search highlight (temporary, 3s auto-clear) | Working | TXTTextViewBridge.highlightRange | Bug #43 FIXED |
| Bookmark creation (toolbar button) | Working | NotificationCenter → container | Bug #31 FIXED |
| Toolbar show/hide on tap | Working | UITapGestureRecognizer + notification | Bug #21 FIXED |
| Session time tracking | Working | ReadingSessionTracker | 60s periodic flush |
| Bottom overlay (progress + session time) | Working | TXTReaderContainerView.mdBottomOverlay | |
| Background/foreground handling | Working | scenePhase + viewModel.onBackground/Foreground | Bug #24 FIXED |
| Search navigation (scroll to match) | Working | scrollToOffset → bridge | Bug #40 FIXED |
| Annotation navigation | Working | scrollToOffset → bridge | Bug #50 FIXED |
| Words read estimation | Working | TXTReaderViewModel.estimatedWordsRead | Section 9.6 formula |
| Encoding detection | Working | TXTService.decodeText | UTF-8 → NSString heuristic → CJK fallbacks |

#### MD Reader

| Feature | Status | Key Files | Notes |
|---------|--------|-----------|-------|
| Markdown → NSAttributedString | Working | MDAttributedStringRenderer (451) | Regex-based rendering |
| Theme/font application | Working | Via TXTTextViewBridge (shared bridge) | |
| All TXT reader features | Working | Shares TXTTextViewBridge | Highlights, notes, search, bookmarks |
| Position save/restore | Working | MDReaderViewModel | Same debounce/locator pattern |

#### EPUB Reader

| Feature | Status | Key Files | Notes |
|---------|--------|-----------|-------|
| WKWebView rendering (XHTML) | Working | EPUBWebViewBridge (285) | loadFileURL + allowingReadAccessTo |
| Theme CSS injection (live) | Working | EPUBWebViewBridge.injectThemeCSSJS | Bug #9 FIXED |
| Spine navigation (next/prev) | Working | EPUBReaderViewModel | estimateTotalProgression |
| Scroll progress tracking | Working | JS script → WKScriptMessage | Throttled 100ms |
| Position save/restore | Working | EPUBReaderViewModel | href + progression |
| TOC from spine items | Working | TOCBuilder.fromSpineItems | |
| Toolbar show/hide on tap | Working | JS click handler → notification | Bug #20 FIXED |
| EPUB parsing (ZIP + OPF) | Working | EPUBParser (303) | Path traversal validation |
| Text highlighting/notes | **NOT IMPLEMENTED** | — | Feature #11 (WKWebView needs JS selection) |
| Bookmark creation | Working | Toolbar button → container | |

#### PDF Reader

| Feature | Status | Key Files | Notes |
|---------|--------|-----------|-------|
| PDFKit rendering | Working | PDFViewBridge (175) | autoScales, continuous |
| Password prompt flow | Working | PDFPasswordPromptView (66) | State-driven retry via attemptId |
| Page change tracking | Working | PDFViewPageChanged notification | |
| Position save/restore | Working | PDFReaderViewModel | Page index based |
| TOC from PDF outline | Working | TOCBuilder.fromPDFOutline | |
| Toolbar show/hide on tap | Working | UITapGestureRecognizer + notification | Bug #32 FIXED |
| Pages per hour metric | Working | PDFReaderViewModel.pagesPerHour | Requires ≥60s, ≥1 page |
| Distinct pages visited | Working | Set<Int> tracking | |
| Text highlighting/notes | **NOT IMPLEMENTED** | — | Feature #17 (PDFKit is read-only) |
| Theme/font application | **NOT POSSIBLE** | — | PDFKit is read-only renderer |

#### Search

| Feature | Status | Key Files | Notes |
|---------|--------|-----------|-------|
| FTS5 full-text indexing | Working | SearchIndexStore (414) | In-memory SQLite |
| Background indexing | Working | BackgroundIndexingCoordinator (153) | Serial actor queue |
| Debounced search (300ms) | Working | SearchViewModel | Cancel-on-new-query |
| Paginated results | Working | SearchViewModel.loadMore() | 20 per page |
| FTS5 snippet highlighting | Working | SearchResultRow | `<b>` tag parsing to bold |
| CJK search support | Working | SearchTextNormalizer | Bug #1 FIXED |
| Per-occurrence snippets | Working | SearchIndexStore.search() | Bug #28 FIXED — source_texts table |
| Navigate to result | Working | onNavigate → .readerNavigateToLocator | Bug #36 FIXED |
| Result highlight at destination | Working | highlightRange → bridge | Bug #43 FIXED |
| Multi-format (EPUB/PDF/TXT/MD) | Working | SearchService.formatSourceContext | |

#### Annotations Panel (4 tabs)

| Feature | Status | Key Files | Notes |
|---------|--------|-----------|-------|
| Bookmark list + navigate | Working | BookmarkListView, BookmarkListViewModel | |
| Bookmark rename | Working | Context menu → alert | Bug #42 FIXED |
| Bookmark delete (swipe) | Working | BookmarkListView | |
| TOC list + navigate | Working | TOCListView | Hierarchical indentation |
| Highlight list + navigate | Working | HighlightListView, HighlightListViewModel | |
| Highlight color indicator | Working | HighlightRowView | 6 colors |
| Highlight out-of-bounds warning | Working | HighlightListViewModel.detectOutOfBounds | |
| Annotation list + navigate | Working | AnnotationListView, AnnotationListViewModel | |
| Annotation edit/delete | Working | Context menu + AnnotationEditSheet | |
| Selected text quote in annotations | Working | AnnotationRowView | Bug #51 FIXED |

#### AI (Feature-flagged OFF)

| Feature | Status | Key Files | Notes |
|---------|--------|-----------|-------|
| AIService pipeline | Functional | AIService (136), AIProvider (189) | Gate: flag → consent → key → cache → provider |
| Summarize/explain/translate/vocabulary/Q&A | Functional | AIAssistantViewModel (209) | State machine with streaming |
| Consent flow | Functional | AIConsentView, AIConsentManager | |
| Context extraction | Functional | AIContextExtractor (115) | Around current locator |
| Response caching | Functional | AIResponseCache (68) | By (fingerprint, locatorHash, action, promptVersion) |
| **Reader UI wiring** | **NOT IMPLEMENTED** | — | Feature #13/#14: no toolbar button, no chat UI |

#### Sync (Feature-flagged OFF)

| Feature | Status | Key Files | Notes |
|---------|--------|-----------|-------|
| SyncService | Stub | SyncService (106) | All ops no-op when flag OFF |
| Conflict resolver | Implemented | SyncConflictResolver (208) | Last-write-wins + tombstones |
| File availability state machine | Implemented | FileAvailabilityStateMachine (68) | 6-state model |
| Status monitor | Implemented | SyncStatusMonitor (50) | idle/syncing/error/offline |
| Tombstone store | Implemented | TombstoneStore (84) | 30-day retention |
| **CloudKit integration** | **NOT IMPLEMENTED** | — | V2 scope |

#### Reader Chrome (shared across formats)

| Feature | Status | Key Files | Notes |
|---------|--------|-----------|-------|
| Navigation bar (back/search/settings/annotations) | Working | ReaderContainerView (739) | |
| Chrome show/hide toggle | Working | isChromeVisible state | Bug #12 FIXED |
| Safe area handling | Working | .ignoresSafeArea(.top) when hidden | Bug #22 FIXED |
| Settings panel (half-sheet) | Working | ReaderSettingsPanel (195) | |
| Search panel | Working | SearchView (142) | |
| Annotations panel (4-tab sheet) | Working | ReaderContainerView → panel | |
| Theme-matched chrome colors | Working | .toolbarColorScheme | Bug #35 FIXED |

### A.3 Notification-Based Coordination Map

| Notification | Posted By | Handled By | Purpose |
|-------------|-----------|------------|---------|
| `.readerContentTapped` | Bridge coordinator (UITapGesture) | Container views | Toggle chrome visibility |
| `.readerBookmarkRequested` | ReaderContainerView toolbar button | TXT/MD container views | Save bookmark at current position |
| `.readerNavigateToLocator` | SearchView, AnnotationListView, BookmarkListView, HighlightListView, TOCListView | TXT/MD container views | Scroll to locator position |
| `.readerHighlightRequested` | Bridge coordinator (edit menu) | TXT/MD container views | Create highlight from selection |
| `.readerAnnotationRequested` | Bridge coordinator (edit menu) | TXT/MD container views | Create annotation from selection |
| `.readerDidClose` | All 4 reader VMs (close()) | LibraryView | Refresh library after reading |
| `.indexingRequested` | BookImporter | BackgroundIndexingCoordinator | Trigger FTS5 indexing |

### A.4 Persistence Protocol Map

| Protocol | Conformance | Methods |
|----------|-------------|---------|
| `BookPersisting` | PersistenceActor | findBook, insertBook, replaceProvenance |
| `LibraryPersisting` | PersistenceActor+Library | fetchAllLibraryBooks, deleteBook |
| `BookmarkPersisting` | PersistenceActor+Bookmarks | add, remove, fetch, isBookmarked, updateTitle |
| `HighlightPersisting` | PersistenceActor+Highlights | add, remove, updateNote, updateColor, fetch |
| `AnnotationPersisting` | PersistenceActor+Annotations | add, remove, update, fetch |
| `ReadingPositionPersisting` | PersistenceActor+ReadingPosition | loadPosition, savePosition, updateLastOpened |
| `SessionPersisting` | SwiftDataSessionStore | saveSession, discardSession, flushDuration, fetchUnclosed |
| `SearchProviding` | SearchService | indexBook, search, removeIndex, isIndexed |
| `IndexingCoordinating` | BackgroundIndexingCoordinator | enqueueIndexing, cancelIndexing, indexingStatus |
| `BookImporting` | BookImporter | importFile |
| `TXTServiceProtocol` | TXTService | open, close |
| `EPUBParserProtocol` | EPUBParser | open, close, contentForSpineItem, resourceBaseURL, extractedRootURL |
| `MDParserProtocol` | MDParser | parse |

### A.5 SwiftData Schema (SchemaV1)

| @Model | Identity Key | Relationships | Key Fields |
|--------|-------------|---------------|------------|
| Book | fingerprintKey (unique) | → ReadingPosition?, [Bookmark], [Highlight], [AnnotationNote] (cascade) | title, author, format, provenance, addedAt, lastOpenedAt, totalWordCount, totalPageCount, totalTextLengthUTF16 |
| ReadingPosition | locatorHash | ← Book | locator, updatedAt, deviceId |
| Bookmark | bookmarkId (UUID, unique) | ← Book | profileKey, locator, title?, createdAt, updatedAt |
| Highlight | highlightId (UUID, unique) | ← Book | profileKey, locator, selectedText, color, note?, createdAt, updatedAt |
| AnnotationNote | annotationId (UUID, unique) | ← Book | profileKey, locator, content, createdAt, updatedAt |
| ReadingSession | sessionId (UUID, unique) | — | bookFingerprintKey, bookFingerprint, startedAt, endedAt?, durationSeconds, pagesRead?, wordsRead?, startLocator?, endLocator?, deviceId, isRecovered |
| ReadingStats | bookFingerprintKey (unique) | — | bookFingerprint, totalReadingSeconds, sessionCount, lastReadAt?, averagePagesPerHour?, averageWordsPerMinute?, totalPagesRead?, totalWordsRead?, longestSessionSeconds |

### A.6 ViewModel Duplication Analysis (Guides WI-006/WI-008)

**Duplicated across all 4 reader VMs (TXT, MD, EPUB, PDF):**

| Pattern | ~Lines Each | Extraction Target |
|---------|-------------|-------------------|
| Debounced position save (2s Task.sleep) | 15–20 | ReaderPositionService |
| `close()`: save → endSession → recomputeStats → postNotification | 15–20 | ReaderPositionService.saveNow + shared close sequence |
| `onBackground()`: save → pause → accumulate → cancelFlush | 8–12 | ReaderPositionService.onBackground |
| `onForeground()`: resume → restartFlush | 5–8 | ReaderPositionService.onForeground |
| `startPeriodicFlush()`: 60s loop | 10–12 | ReaderPositionService |
| `updateTimeDisplays()`: accumulated + current segment | 8–10 | ReaderPositionService or ReadingTimeFormatter |
| `resetState()` | 5–8 | Stays local (format-specific) |
| `makeLocator()` / `makeLightLocator()` | 10–15 | Stays local (format-specific: LocatorFactory.txtRange vs .epub vs .pdf) |

**Total extractable per VM: ~60–90 lines → ReaderPositionService ~120 lines**

### A.7 Bridge Duplication Analysis (Guides WI-001/WI-002)

**Duplicated between TXTTextViewBridge and TXTChunkedReaderBridge coordinators:**

| Pattern | Where (Single TV) | Where (Chunked) | Lines |
|---------|--------------------|------------------|-------|
| `editMenuForTextIn` (build 2 UIActions: Highlight + Add Note) | Coordinator | Coordinator | ~20 each |
| `postSelectionNotification` / `postChunkedSelectionNotification` | Coordinator | Coordinator (adds chunkOffset) | ~15 each |
| `handleContentTap` (UITapGesture → .readerContentTapped) | Coordinator | Coordinator | ~10 each |
| `gestureRecognizer(shouldRecognizeSimultaneouslyWith)` | Coordinator | Coordinator | ~3 each |

**NOT duplicated (structurally different):**
- Highlight state: single-TV uses coordinator ranges; chunked uses chunk-local projection + binary search
- Scroll tracking: single-TV uses contentOffset; chunked uses visible cell → chunk index → global offset
- Content rebuild: single-TV rebuilds full attributedString; chunked invalidates cell cache

### A.8 TODOs Found in Codebase

| File | TODO | Category |
|------|------|----------|
| MetadataExtractor.swift:58 | `TODO(WI-6): Replace with Readium-based extractor` | Deferred to future WI |
| MetadataExtractor.swift:67 | `TODO(WI-7): Replace with PDFKit-based extractor` | Deferred to future WI |

**All other TODOs have been resolved** (bugs #1–#55 all FIXED).

### A.9 Feature Tracker Cross-Reference

| Feature # | Summary | Status | Refactor Impact |
|-----------|---------|--------|-----------------|
| 1 | Edit/delete bookmarks | TODO | None (UI feature) |
| 2 | Search highlight at destination | DONE | None |
| 3 | Manual text highlighting | DONE | None |
| 4 | Add notes/annotations | DONE | None |
| 5 | Search highlight auto-dismiss | TODO | None (behavior feature) |
| 6 | Persist library view preferences (sort + display mode) | TODO | None (new feature) |
| 7 | Visual feedback on bookmark add | TODO | None (UI feature) |
| 8 | Reading position scrubber/progress bar | TODO | None (UI feature) |
| 9 | Comprehensive book context menu | TODO | None (UI feature) |
| 10 | iCloud backup and restore | TODO | None (sync feature) |
| 11 | EPUB text highlighting/notes | TODO | None (EPUB feature) |
| 12 | Auto-generate TOC for TXT/MD | TODO | None |
| 13 | AI book/chapter summarization | TODO | None (AI feature) |
| 14 | AI chat — talk to the book | TODO | None (AI feature) |
| 15 | AI chat interface (general) | TODO | None (AI feature) |
| 16 | Remote server integration | TODO | None (server feature) |
| 17 | PDF text highlighting/annotation/theming | TODO | None (PDF feature) |
| 18 | AI-powered translation with bilingual view | TODO | None (AI feature) |
| 19 | (Merged into #6) | DUPLICATE | — |
| 20 | Sort order reset/revert | TODO | None (UI feature) |

**Key insight**: No open features conflict with or are affected by the refactoring plan. The refactor is purely structural — extracting and deduplicating existing code without behavior changes.
