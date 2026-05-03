# Feature Roadmap Plan

**Date**: 2026-03-11 (revised 2026-03-11 — Codex review findings applied)
**Scope**: 15 TODO features from `docs/features.md` (#5–#18, #20). Feature #1 already DONE.
**Mode**: Full plan (persistence changes, multi-phase rollout, API contracts)

---

## 1. Outcomes

Deliver the remaining 15 features in 4 phases, ordered by dependency chain and user impact:

1. **Phase A — Quick Wins** (no new infrastructure): #6, #20, #7, #5
2. **Phase B — Reader Enhancements** (new UI components): #8, #12, #9
3. **Phase C — EPUB/PDF Annotation** (platform integration): #11, #17 — preceded by annotation anchor schema design (WI-C00)
4. **Phase D — AI Features** (API + UI): preceded by AI foundation fixes (WI-D00), then #13, #14, #15, #18, #16, #10

### Constraints & Dependencies

| Constraint | Detail |
|------------|--------|
| Runtime | iOS 17+, Swift 6, SwiftUI + UIKit hybrid |
| Persistence | SwiftData via PersistenceActor (actor-isolated) |
| AI gate | `FeatureFlags.aiAssistant` (default OFF). Must be turned ON + user consent + API key. **Critical**: FeatureFlags is a value-type struct — AIService holds an immutable copy. WI-D00 fixes this. |
| EPUB rendering | WKWebView (no UITextView). JS injection required for selection/highlight |
| PDF rendering | PDFKit (read-only UIKit wrapper). PDFAnnotation API for highlights |
| Test framework | Swift Testing (`@Suite`, `@Test`, `#expect`) |
| Build | Xcode, `xcodebuild -sdk iphonesimulator` |

### Gaps Identified

| Gap | Resolution |
|-----|-----------|
| No `UserDefaults` usage anywhere for preferences | WI-001 introduces `PreferenceStore` wrapper around `UserDefaults` for library prefs |
| EPUBWebViewBridge has zero selection/highlight handling | WI-007 builds JS bridge from scratch |
| PDF has no selection or annotation support | WI-008 adds PDFAnnotation bridge |
| No annotation anchor schema for EPUB CFI/PDF page+rect/TXT offset cross-format persistence | WI-C00 defines unified anchor schema before any annotation UI |
| AI feature flag is OFF with no UI to toggle it | WI-009 adds Settings screen with AI toggle + API key entry |
| `FeatureFlags` is value-type struct — AIService holds immutable copy, never sees runtime overrides | WI-D00 converts to `@MainActor class` or `actor` so AIService shares the live instance |
| `AIRequest.cacheKey` ignores `userPrompt`, `targetLanguage`, `contextText` — different questions cache to same key | WI-D00 redesigns cache key to include all semantically distinct fields |
| `AIRequest.bookFingerprint` and `locator` are non-optional — general chat (#15) has no book context | WI-D00 makes these optional |
| `AIProvider` factory only takes `apiKey` — no model/temperature/endpoint configuration | WI-D00 introduces `AIConfiguration` model |
| No multi-turn conversation model or storage | WI-011 designs chat data model |
| Remote server (#16) has zero existing infrastructure | WI-014 scoped as design-only; implementation deferred |
| iCloud backup (#10) requires CloudKit or document-based sync | WI-015 scoped as design-only; implementation deferred |
| No AI data privacy requirements defined (what context gets sent, user opt-in scope) | WI-D00 documents privacy policy for AI data handling |

---

## 2. Current Behavior Inventory

### Bookmarks (#1)
- **BookmarkPersisting** protocol: `addBookmark`, `removeBookmark`, `fetchBookmarks`, `isBookmarked`, `updateBookmarkTitle`
- **BookmarkListViewModel**: load, add, remove, toggle, updateTitle — all CRUD exists
- **BookmarkListView**: list with swipe-to-delete, context menu (Rename, Delete), rename alert
- **Gap**: Feature #1 says "Full edit/delete UI not implemented" but code shows both rename and delete exist via context menu. **Feature #1 is already DONE** — mark as resolved.

### Library Preferences (#6, #20)
- **LibraryViewModel**: `viewMode: LibraryViewMode = .grid`, `sortOrder: LibrarySortOrder = .title`
- Both reset to defaults on every launch. No persistence.
- **LibraryViewMode** and **LibrarySortOrder** both have `String` raw values — compatible with `UserDefaults` (D1: `PreferenceStore` wrapper chosen over `@AppStorage`).

### Search Highlight (#5)
- Highlight auto-clear after 3s exists per feature #2 (DONE).
- Feature #5 wants clear-on-next-action (scroll, tap, new search) — not yet implemented.

### Bookmark Feedback (#7)
- Bookmark toggle calls `addBookmark`/`removeBookmark` — no visual/haptic feedback.

### TOC (#12)
- **TOCBuilder**: `forTXT()` and `forMD()` return `[]`. EPUB and PDF work.
- MD files have heading structure (`#`, `##`). TXT has no inherent structure.

### AI (#13, #14, #15, #18)
- **AIService**: actor with gate sequence (flag → consent → key → cache → provider).
- **AIProvider**: OpenAI-compatible. `sendRequest` + `streamRequest`.
- **AIActionType**: `.summarize`, `.explain`, `.translate`, `.vocabulary`, `.questionAnswer`.
- **AIAssistantViewModel**: single-request lifecycle (idle → loading → complete/error). No multi-turn.
- **AIAssistantView**: exists but not wired to any reader toolbar.
- **Feature flag**: `FeatureFlags.aiAssistant` default OFF in all environments.

### EPUB Annotation (#11)
- EPUBWebViewBridge has no text selection handling, no JS highlight injection.
- TXT/MD use UITextView with `editMenuInteraction` for highlight/note actions.

### PDF Annotation (#17)
- PDFViewBridge wraps PDFKit. Read-only. No selection API, no annotation creation.

---

## 3. Decision Log

| # | Decision | Options Considered | Rationale |
|---|----------|--------------------|-----------|
| D1 | Use `PreferenceStore` wrapping `UserDefaults.standard` for library prefs | `@AppStorage` (View-only), SwiftData settings table, bare UserDefaults | `@AppStorage` requires View context — LibraryViewModel is `@Observable` not a View. `PreferenceStore` is testable via protocol, reads in init, writes in didSet. |
| D2 | MD TOC via regex heading extraction, skip headings inside fenced code blocks | Full markdown parser AST, regex on raw text | Regex `^(#{1,6})\\s+(.+)$` per line, but skip lines between `` ``` `` fences to avoid false positives. Simpler than AST, handles 99% of real files. |
| D3 | TXT TOC: skip (return empty). Feature #12 redefined as MD-only | Heuristic chapter detection, regex for "Chapter N" | Too fragile and language-dependent. Users can use search instead. TXT portion of #12 deferred indefinitely. |
| D4 | EPUB highlights via JS injection | WKWebView.evaluateJavaScript, custom CSS | JS Selection API + Range.surroundContents for highlight spans |
| D5 | PDF highlights via PDFAnnotation | UIKit overlay view, custom drawing | PDFAnnotation(.highlight) is the standard PDFKit approach |
| D6 | AI chat: two modes — book-scoped (default in reader) and general (from library) | Single-book only, global only | WI-011 builds book-scoped chat. WI-013 extends with optional bookFingerprint=nil for general mode. No contradiction — #14 is book-chat, #15 is general-chat, both share AIChatViewModel with optional book context. |
| D7 | Remote server (#16): defer to V2 | Build now with WebSocket | Zero infrastructure exists. Need protocol design first |
| D8 | iCloud backup (#10): defer to V2 | Build now with CloudKit | Complex (schema versioning, conflict resolution). Low urgency |
| D9 | Progress bar: UISlider overlay | Custom SwiftUI Slider, page-turn gesture | UISlider gives fine-grained control + haptic snaps to chapters |
| D10 | Haptic feedback for bookmark: UIImpactFeedbackGenerator(.light) | No haptic (visual only), heavy haptic | Light impact is standard iOS convention for toggle actions |
| D11 | Convert FeatureFlags from struct to `@MainActor class` | Keep as struct (callers copy), actor wrapper | Value-type struct means AIService holds a frozen copy — never sees runtime overrides from Settings. `@MainActor class` enables shared reference + SwiftUI binding. |
| D12 | Redesign AIRequest.cacheKey to include all semantic fields | Keep minimal key (fingerprint+locator+action+version) | Current key ignores userPrompt, targetLanguage, contextText — a translate-to-Chinese and translate-to-Japanese for the same passage cache to the same key. New key: `"{fpKey}:{locHash}:{action}:{promptVer}:{promptHash}:{langHash}"` |
| D13 | AI Settings accessible via gear icon in library toolbar → dedicated SettingsView | Inline in reader toolbar, tab bar tab | Dedicated Settings screen follows iOS conventions. Gear icon in library is discoverable without adding a tab. |
| D14 | Features #14 and #15 remain separate features, share implementation | Merge into one feature | #14 (book chat) and #15 (general chat) have different contexts and entry points. AIChatViewModel supports both via optional bookFingerprint. Separate features, incremental delivery (WI-011 then WI-013). |

### Open Questions

| # | Question | Default if Undecided | Status |
|---|----------|---------------------|--------|
| Q1 | Should AI settings be in a dedicated Settings tab or inline in reader? | Dedicated Settings screen via gear icon in library toolbar (D13) | **Resolved** |
| Q2 | Should EPUB highlights persist across sessions? | Yes, stored via HighlightPersisting (same as TXT/MD) | Open |
| Q3 | Should PDF annotations be saved back to the PDF file? | No — store in SwiftData only (non-destructive) | Open |
| Q4 | What AI context data is sent to the provider? Privacy boundary? | Only current section text + user prompt. No PII, no reading history. User must opt-in per-session or persist consent. Documented in WI-D00. | Open |
| Q5 | Should features #14 and #15 merge into one feature? | No — keep separate. #14 is book-chat (WI-011), #15 is general-chat (WI-013). Shared ViewModel, different entry points (D14). | **Resolved** |

---

## 4. Work Items

### Phase A — Quick Wins

---

#### WI-001: Persist Library View Preferences (Feature #6, #20)

**Goal**: sortOrder and viewMode survive app restart. Add "Default" reset option.

**Priority**: High | **Estimate**: S

**Dependencies**: None.

**Tests (first)**:
- `vreaderTests/ViewModels/LibraryViewModelPersistenceTests.swift`
  - `sortOrderSurvivesRecreation`: set sortOrder, create new VM, verify restored
  - `viewModeSurvivesRecreation`: set viewMode, create new VM, verify restored
  - `defaultSortOrderIsTitle`: fresh install defaults to .title
  - `defaultViewModeIsGrid`: fresh install defaults to .grid

**Touched areas**:
- New: `vreader/Services/PreferenceStore.swift` — protocol + `UserDefaultsPreferenceStore` for testability
- `vreader/ViewModels/LibraryViewModel.swift` — inject `PreferenceStore`, read in init, write on set
- `vreader/Views/LibraryView.swift` — add "Default" option in sort picker menu
- `vreader/Models/LibrarySortOrder.swift` — no change (already has String rawValue)

**Edge cases**:
- First launch (no stored value) → defaults to .title/.grid
- Corrupted/unknown stored string → falls back to default
- Concurrent access from multiple views → single ViewModel instance, no contention

**Acceptance**:
- Sort order persists across app kill + relaunch (manual test)
- View mode persists across app kill + relaunch (manual test)
- "Default" sort option resets to .title (unit test)
- Unknown stored values fall back gracefully (unit test)
- Existing tests pass with no regression

**Risks**: None significant — `UserDefaults` is well-understood for 2 string values.

**Mitigation**: `PreferenceStore` protocol enables mock injection in tests.

**Rollback**: Remove `PreferenceStore` reads/writes. Properties revert to hardcoded defaults.

---

#### WI-002: Visual Feedback for Bookmark Toggle (Feature #7)

**Goal**: Light haptic (D10) + brief icon animation when bookmark is added/removed.

**Priority**: Low | **Estimate**: S

**Dependencies**: None.

**Tests (first)**:
- `vreaderTests/Views/Reader/BookmarkFeedbackTests.swift`
  - `feedbackGeneratorFiredOnAdd`: mock generator, verify `.impactOccurred()` called
  - `feedbackGeneratorFiredOnRemove`: same for remove
  - `noFeedbackOnError`: verify no haptic when add/remove fails

**Touched areas**:
- `vreader/Views/Reader/ReaderContainerView.swift` — add haptic after successful toggle
- New: `vreader/Services/HapticFeedback.swift` — thin wrapper around `UIImpactFeedbackGenerator` for testability

**Acceptance**:
- Light haptic fires on successful bookmark add (manual test on device)
- Light haptic fires on successful bookmark remove (manual test)
- No haptic on failure
- Unit test with mock generator passes

**Rollback**: Remove haptic calls. No persistence impact.

---

#### WI-003: Search Highlight Auto-Dismiss (Feature #5)

**Goal**: Active search highlight clears when user scrolls, taps, or starts a new search.

**Priority**: Low | **Estimate**: S

**Dependencies**: None.

**Tests (first)**:
- `vreaderTests/Views/Reader/SearchHighlightDismissTests.swift`
  - `highlightClearsOnScroll`: simulate scroll callback, verify highlight removed
  - `highlightClearsOnTap`: simulate tap, verify highlight removed
  - `highlightClearsOnNewSearch`: trigger new search, verify old highlight removed
  - `noHighlightNoCrash`: dismiss when no highlight active

**Touched areas**:
- `vreader/Views/Reader/TXTTextViewBridge.swift` — clear highlight on scrollViewDidScroll
- `vreader/Views/Reader/HighlightableTextView.swift` — add `clearSearchHighlight()` method
- `vreader/ViewModels/SearchViewModel.swift` — clear highlight when query changes
- `vreader/Views/Reader/EPUBWebViewBridge.swift` — clear via JS on scroll/navigation

**Acceptance**:
- Scrolling any amount after search-highlight clears the highlight (manual test)
- Tapping anywhere clears the highlight (manual test)
- Starting a new search clears previous highlight (manual test)
- Timer-based 3s clear still works as fallback

**Rollback**: Remove dismiss triggers. 3s timer remains as sole clear mechanism.

---

### Phase B — Reader Enhancements

---

#### WI-004: Reading Position Scrubber/Progress Bar (Feature #8)

**Goal**: Draggable progress bar (D9: UISlider overlay) at bottom of reader for seeking to arbitrary positions.

**Priority**: Medium | **Estimate**: M

**Dependencies**: None.

**Design**: Position reporting differs per format:
- TXT/MD: character offset / total characters (0.0–1.0 fraction)
- EPUB: spine index / total spine items
- PDF: page number / total pages

`ReadingProgressBar` takes a `progress: Double` (0–1) binding and an `onSeek: (Double) -> Void` callback. Each container view computes format-specific progress and translates seek values back to format-specific positions.

**Tests (first)**:
- `vreaderTests/Views/Reader/ProgressScrubberTests.swift`
  - `scrubberReflectsCurrentPosition`: set offset, verify slider value
  - `scrubberSeekUpdatesPosition`: drag slider, verify VM offset changes
  - `scrubberClampsToValidRange`: drag beyond bounds, verify clamped
  - `scrubberHiddenWhenNoContent`: empty/nil content hides scrubber

**Touched areas**:
- New: `vreader/Views/Reader/ReadingProgressBar.swift` — SwiftUI slider component
- `vreader/Views/Reader/TXTReaderContainerView.swift` — embed progress bar
- `vreader/Views/Reader/MDReaderContainerView.swift` — embed progress bar
- `vreader/Views/Reader/EPUBReaderContainerView.swift` — embed progress bar (spine-based)
- `vreader/Views/Reader/PDFReaderContainerView.swift` — embed progress bar (page-based)

**Acceptance**:
- Slider shows current position as 0–100% (manual test, all formats)
- Dragging slider scrolls to corresponding position
- Position persistence still works after scrubber seek
- Slider hidden when file not loaded
- Unit tests pass

**Rollback**: Remove progress bar overlay. Reader functions normally without it.

---

#### WI-005: Auto-Generate TOC for MD Files (Feature #12)

**Goal**: Extract headings from markdown text for TOC (D2). TXT stays empty (D3).

**Priority**: Medium | **Estimate**: S

**Dependencies**: None.

**Tests (first)**:
- `vreaderTests/Services/TOCBuilderMDTests.swift`
  - `extractsH1Headings`: `# Title` → level 0 entry
  - `extractsH2H3`: `## Sub` → level 1, `### Sub` → level 2
  - `ignoresHashesInFencedCodeBlocks`: `# inside ``` block` not treated as heading
  - `ignoresInlineHashes`: `some # text` mid-line not a heading
  - `emptyTextReturnsEmpty`: no headings → []
  - `preservesOrderAndLevel`: multiple headings in document order
  - `handlesATXOnly`: no setext heading support needed
  - `headingsWithSpecialChars`: `# 第一章 概述` (CJK), `# Über` (diacritics)
  - `nestedFencedBlocks`: triple-backtick inside quadruple-backtick

**Touched areas**:
- `vreader/Services/TOCBuilder.swift` — implement `forMD(text:fingerprint:)` with regex `^(#{1,6})\\s+(.+)$`, skip lines inside fenced code blocks (track `` ``` `` open/close state per D2)
- `vreader/ViewModels/MDReaderViewModel.swift` — call TOCBuilder.forMD after parse, expose to container
- `vreader/Services/Locator/LocatorFactory.swift` — reuse `LocatorFactory.mdPosition()` for heading navigation (no new factory needed)

**Acceptance**:
- Opening an MD file with headings shows populated TOC (manual test)
- TOC entries navigate to correct heading position
- MD files without headings show empty TOC
- Unit tests pass for all heading levels (1–6)

**Rollback**: Revert `forMD` to return `[]`. No persistence impact.

---

#### WI-006: Comprehensive Book Context Menu (Feature #9)

**Goal**: Context menu with Info, Share, and Delete (replacing Delete-only).

**Priority**: Medium | **Estimate**: S

**Dependencies**: None.

**Tests (first)**:
- `vreaderTests/Views/LibraryContextMenuTests.swift`
  - `contextMenuShowsAllActions`: verify Info, Share, Delete labels present
  - `deleteShowsConfirmation`: delete triggers confirmation alert
  - `infoShowsBookDetails`: info triggers detail sheet

**Touched areas**:
- `vreader/Views/LibraryView.swift` — expand contextMenu builder
- New: `vreader/Views/Library/BookInfoSheet.swift` — detail sheet (title, author, format, size, dates, reading stats)
- `vreader/Models/LibraryBookItem.swift` — may need `fileSize` if not present

**Acceptance**:
- Long-press (grid) or swipe (list) shows: "Info", "Share", "Delete" (manual test)
- "Info" opens sheet with book metadata
- "Share" invokes share sheet with file URL
- "Delete" still shows confirmation
- Unit tests pass

**Rollback**: Revert contextMenu to Delete-only.

---

### Phase C — EPUB/PDF Annotation

---

#### WI-C00: Annotation Anchor Schema Design (prerequisite for WI-007, WI-008)

**Goal**: Define a unified annotation anchor model that supports EPUB (CFI + href), PDF (page + rect), and TXT/MD (UTF-16 offset + sourceUnitId) in a single SwiftData schema.

**Priority**: High | **Estimate**: S

**Problem**: WI-007 (EPUB) and WI-008 (PDF) both need to persist highlights and notes, but EPUB uses CFI ranges, PDF uses page+bounding rect, and TXT/MD uses UTF-16 character offsets. Without a unified schema, each format would have its own table and the annotation list view would need format-specific code.

**Tests (first)**:
- `vreaderTests/Models/AnnotationAnchorTests.swift`
  - `epubAnchorRoundTrips`: create EPUB anchor (href + CFI), encode/decode, verify fields
  - `pdfAnchorRoundTrips`: create PDF anchor (page + rect), encode/decode, verify fields
  - `txtAnchorRoundTrips`: create TXT anchor (offset + unitId), encode/decode, verify fields
  - `anchorEquality`: same fields → equal, different → not equal

**Touched areas**:
- New: `vreader/Models/AnnotationAnchor.swift` — enum or protocol-based anchor with associated data per format
- `vreader/Models/` — update Highlight/Note models to reference `AnnotationAnchor` instead of format-specific fields
- New: `vreaderTests/Models/AnnotationAnchorTests.swift`

**Design**:
```swift
enum AnnotationAnchor: Codable, Sendable, Equatable {
    case epub(href: String, cfi: String)
    case pdf(page: Int, rect: CGRect)
    case text(sourceUnitId: String, startUTF16: Int, endUTF16: Int)
}
```

**Acceptance**:
- All three anchor types encode/decode correctly (unit test)
- Existing TXT/MD highlight persistence still works (regression test)
- Schema documented for WI-007 and WI-008 to implement against

**Dependencies**: None.

**Rollback**: Revert model changes. Existing highlights unaffected (this is additive).

---

#### WI-007: EPUB Text Selection + Highlighting (Feature #11)

**Goal**: Enable text selection in EPUB WKWebView with highlight and note actions.

**Priority**: High | **Estimate**: L

**Tests (first)**:
- `vreaderTests/Views/Reader/EPUBHighlightBridgeTests.swift`
  - `selectionMessageParsesCorrectly`: mock JS message → parsed range
  - `highlightInjectionProducesValidJS`: verify JS string for CSS class injection
  - `highlightPersistAndRestore`: save highlight, reload, verify restored
  - `removeHighlightClearsSpan`: remove highlight, verify span removed

**Touched areas**:
- New: `vreader/Views/Reader/EPUBHighlightBridge.swift` — JS ↔ Swift bridge for selection events
- New: `vreader/Resources/epub-highlight.js` — JS injected into WKWebView for selection handling
- `vreader/Views/Reader/EPUBWebViewBridge.swift` — add WKScriptMessageHandler for "selectionChanged"
- `vreader/Views/Reader/EPUBReaderContainerView.swift` — wire highlight/note actions
- `vreader/ViewModels/EPUBReaderViewModel.swift` — add highlight/note state management

**Design**:
1. Inject `epub-highlight.js` via `WKUserScript` at document end
2. JS listens for `selectionchange` event, posts message to Swift with selected text + CFI range
3. Swift shows action menu (Highlight, Note, Copy)
4. "Highlight" sends JS call to wrap selection in `<span class="vr-highlight">`
5. Persist via `HighlightPersisting` using `AnnotationAnchor.epub(href:cfi:)` from WI-C00
6. On page load, restore highlights by re-injecting `<span>` elements

**Acceptance**:
- Long-press selects text in EPUB (manual test)
- "Highlight" action wraps text in yellow span
- Highlights persist across close/reopen
- "Add Note" opens AddNoteSheet
- Existing TXT/MD highlighting unaffected

**Dependencies**: WI-C00 (annotation anchor schema must be defined first).

**Risks**: WKWebView content security policy may block inline script injection.
**Mitigation**: Use `WKUserScript` injection (runs in page context, bypasses CSP for user scripts).

**Rollback**: Remove JS injection + message handler. EPUB reverts to read-only.

---

#### WI-008: PDF Text Selection + Annotation (Feature #17)

**Goal**: Enable text selection and highlight annotation in PDFKit-based reader.

**Priority**: High | **Estimate**: L

**Tests (first)**:
- `vreaderTests/Views/Reader/PDFAnnotationBridgeTests.swift`
  - `highlightAnnotationCreated`: create highlight → PDFAnnotation exists on page
  - `highlightColorMatchesTheme`: verify annotation color
  - `removeAnnotationDeletesFromPage`: remove → annotation gone
  - `annotationPersistsAcrossReload`: close, reopen, annotations restored

**Touched areas**:
- New: `vreader/Views/Reader/PDFAnnotationBridge.swift` — manages PDFAnnotation creation/deletion
- `vreader/Views/Reader/PDFViewBridge.swift` — add selection detection + action menu
- `vreader/Views/Reader/PDFReaderContainerView.swift` — wire highlight/note actions
- `vreader/ViewModels/PDFReaderViewModel.swift` — add annotation state

**Design**:
1. Enable `PDFView.isInMarkupMode = false` but detect selection via `PDFViewDelegate.selectionDidChange`
2. On selection, show custom action menu (Highlight, Note, Copy)
3. "Highlight" creates `PDFAnnotation(bounds:forType:withProperties:)` with `.highlight` type
4. Store annotation metadata in SwiftData via `HighlightPersisting` using `AnnotationAnchor.pdf(page:rect:)` from WI-C00
5. On page load, recreate `PDFAnnotation` objects from stored data

**Acceptance**:
- Text selection works in PDF (manual test)
- Highlight creates yellow annotation overlay
- Annotations persist across close/reopen
- Annotations stored in SwiftData, not in PDF file (non-destructive)

**Dependencies**: WI-C00 (annotation anchor schema must be defined first).

**Risks**: PDFKit selection API may be limited on certain PDF types (scanned, image-only).
**Mitigation**: Detect selectable text; show "No selectable text" message for image-only PDFs.

**Rollback**: Remove annotation bridge. PDF reverts to read-only.

---

### Phase D — AI Features

---

#### WI-D00: AI Foundation Fixes (prerequisite for all AI features)

**Goal**: Fix structural issues in AI infrastructure that would block or break all AI features.

**Priority**: Critical | **Estimate**: M

**Dependencies**: None.

**Problem**: Four issues make the current AI infrastructure unusable:
1. **FeatureFlags is a value-type struct** — AIService holds an immutable copy captured at init. When Settings toggles AI ON, AIService's copy is still OFF. (D11)
2. **AIRequest.cacheKey ignores semantic fields** — `userPrompt`, `targetLanguage`, and `contextText` are excluded. A translate-to-Chinese and translate-to-Japanese request for the same passage produce the same cache key → wrong cached result returned. (D12)
3. **AIRequest.bookFingerprint and locator are non-optional** — general chat (#15) has no book context. Cannot construct a valid AIRequest without a book.
4. **AIProvider factory only takes apiKey** — no way to configure model, temperature, or endpoint.

**Tests (first)**:
- `vreaderTests/Services/FeatureFlagsTests.swift`
  - `sharedInstanceReflectsOverride`: set override on shared instance, read from another reference → sees change
  - `defaultValuesPreserved`: fresh instance has expected defaults
- `vreaderTests/Services/AI/AIRequestCacheKeyTests.swift`
  - `differentUserPromptsProduceDifferentKeys`: same context, different prompts → different keys
  - `differentTargetLanguagesProduceDifferentKeys`: same context, different languages → different keys
  - `sameInputsProduceSameKey`: deterministic
- `vreaderTests/Services/AI/AIRequestOptionalFieldsTests.swift`
  - `generalChatRequestHasNilFingerprint`: create without book → valid request
  - `bookChatRequestHasFingerprint`: create with book → fingerprint populated

**Touched areas**:
- `vreader/Services/FeatureFlags.swift` — convert from struct to `@MainActor class` (or `actor`). Add `shared` singleton. Persist `aiAssistant` override to UserDefaults so it survives restart.
- `vreader/Services/AI/AITypes.swift` — make `bookFingerprint` and `locator` optional on AIRequest. Redesign `cacheKey` to hash `userPrompt` + `targetLanguage` when present.
- `vreader/Services/AI/AIService.swift` — update gate sequence to read from shared FeatureFlags reference (not frozen copy)
- New: `vreader/Services/AI/AIConfiguration.swift` — model, temperature, endpoint, maxTokens configuration
- `vreader/Services/AI/AIProvider.swift` — accept `AIConfiguration` in factory
- `vreader/Services/AppConfiguration.swift` — update FeatureFlags construction to use shared instance
- New: `docs/ai-privacy-policy.md` — document what data is sent to AI providers (Q4: current section text + user prompt only, no PII, no reading history)

**Edge cases**:
- AIRequest with nil bookFingerprint and nil locator → cache key uses "general" prefix
- Empty userPrompt → hash of "" (distinct from nil/absent)
- FeatureFlags.shared accessed before AppConfiguration.configure() → fatal or default instance
- Concurrent flag reads during Settings toggle → `@MainActor` ensures serial access

**Acceptance**:
- FeatureFlags override set in Settings is visible to AIService immediately (unit test)
- AI feature flag persists across app restart (manual test)
- Different translation languages produce different cache keys (unit test)
- AIRequest can be constructed without book context (unit test)
- AIProvider accepts configuration model (unit test)
- AI privacy policy document exists with data handling rules
- All existing AI tests pass

**Risks**: Changing FeatureFlags from struct to class affects all call sites.
**Mitigation**: `Sendable` compliance via `@MainActor`. Grep all usages (currently only AppConfiguration + AIService).

**Rollback**: Revert to struct. AI features remain broken but app is stable.

---

#### WI-009: AI Settings Screen (prerequisite for all AI features)

**Goal**: Settings screen to toggle AI, enter API key, select provider/model. Accessible via gear icon in library toolbar (D13).

**Priority**: High | **Estimate**: M

**Dependencies**: WI-D00 (FeatureFlags must be shared reference, AIConfiguration must exist)

**Tests (first)**:
- `vreaderTests/Views/Settings/AISettingsTests.swift`
  - `toggleAIUpdatesFeatureFlag`: flip toggle, verify `FeatureFlags.shared.aiAssistant` changed
  - `apiKeySavedToKeychain`: enter key, verify `KeychainService` stores it
  - `emptyKeyShowsError`: submit empty key, verify error message
  - `consentToggleWorks`: grant/revoke consent, verify state
  - `modelPickerUpdatesConfiguration`: select model, verify `AIConfiguration` updated

**Touched areas**:
- New: `vreader/Views/Settings/SettingsView.swift` — presented from gear icon in library toolbar
- New: `vreader/Views/Settings/AISettingsSection.swift` — AI toggle, API key field, model picker, endpoint config
- `vreader/Views/LibraryView.swift` — add gear icon button in toolbar
- `vreader/App/VReaderApp.swift` — no tab bar change needed (sheet presentation)

**Edge cases**:
- API key with leading/trailing whitespace → trim before saving
- Switching provider resets model picker to provider defaults
- Keychain access denied (simulator vs device) → show clear error

**Acceptance**:
- Settings screen accessible from library toolbar gear icon (manual test)
- AI toggle enables/disables AI feature flag (reads/writes `FeatureFlags.shared`)
- API key entry saves to keychain securely
- Model selection persists via `AIConfiguration`
- Settings persist across app restart

**Rollback**: Remove Settings screen. AI stays gated behind feature flag (OFF).

---

#### WI-010: AI Summarization in Reader (Feature #13)

**Goal**: Wire AIAssistantViewModel to reader toolbar. "Summarize" button calls AI on current context.

**Priority**: High | **Estimate**: M

**Dependencies**: WI-D00 + WI-009 (AI foundation + settings must exist)

**Tests (first)**:
- `vreaderTests/ViewModels/AIReaderIntegrationTests.swift`
  - `summarizeButtonCallsAIService`: tap summarize, verify sendRequest called with .summarize
  - `responseDisplayedInPanel`: mock response, verify text shown
  - `errorShownOnFailure`: mock error, verify error state
  - `featureDisabledHidesButton`: flag OFF → button not visible
  - `longContentTruncatedToContextWindow`: verify context extraction respects max token limit

**Touched areas**:
- `vreader/Views/Reader/ReaderContainerView.swift` — add AI toolbar button (conditional on flag)
- New: `vreader/Views/Reader/AIReaderPanel.swift` — bottom sheet showing AI response
- `vreader/ViewModels/AIAssistantViewModel.swift` — no changes needed (already supports summarize)

**Acceptance**:
- AI button visible only when feature flag ON + API key set (manual test)
- Tapping "Summarize" sends current page/section context to AI
- Response displayed in bottom panel
- Loading state shown during request
- Error shown for network/auth failures

**Risks**: Context extraction may exceed provider token limits for large sections.
**Mitigation**: Truncate context to configurable max token count (default 4000 tokens). Show truncation indicator in UI.

**Rollback**: Remove toolbar button + panel. AI code remains but unwired.

---

#### WI-011: AI Chat — Multi-Turn Conversations (Feature #14)

**Goal**: Multi-turn chat UI for asking questions about the book.

**Priority**: High | **Estimate**: L

**Dependencies**: WI-D00 + WI-009, WI-010

**Tests (first)**:
- `vreaderTests/ViewModels/AIChatViewModelTests.swift`
  - `sendMessageAddsToHistory`: send message, verify history has user + assistant messages
  - `multiTurnPreservesContext`: send 2 messages, verify 2nd request includes prior context
  - `clearHistoryResetsConversation`: clear, verify empty
  - `streamingUpdatesLastMessage`: streaming chunks update the assistant message incrementally
  - `slidingWindowDropsOldMessages`: send N+1 messages, verify oldest dropped from context
  - `bookContextPrependedAsSystemMessage`: verify first message in API call is system + book context

**Touched areas**:
- New: `vreader/ViewModels/AIChatViewModel.swift` — manages conversation history + streaming. `bookFingerprint: DocumentFingerprint?` (nil = general mode, per D6/D14)
- New: `vreader/Views/AI/AIChatView.swift` — message list + input field
- New: `vreader/Models/ChatMessage.swift` — message model (role, content, timestamp)
- `vreader/Views/Reader/AIReaderPanel.swift` — add chat tab alongside summarize

**Design**:
- Conversation history stored in memory (session-scoped, not persisted in V1)
- Each request includes last N messages as context (sliding window, N=10 default)
- Book context (current section) prepended as system message when `bookFingerprint != nil`
- General mode (nil fingerprint) omits book context — used by WI-013
- Streaming via `streamRequest` for incremental display

**Acceptance**:
- Chat UI shows message list with user/assistant bubbles (manual test)
- Multiple questions maintain context
- Streaming shows text appearing incrementally
- "Clear" button resets conversation
- Unit tests pass for history management

**Risks**: Sliding window may drop important early conversation context; user may see inconsistent answers.
**Mitigation**: Show "context window" indicator. Allow user to pin important messages.

**Rollback**: Remove chat UI. Single-shot summarize/explain remain.

**Note**: WI-011 modifies `AIReaderPanel.swift` (created in WI-010, also modified by WI-012). If WI-011 and WI-012 are parallelized, coordinate merge on this file.

---

#### WI-012: AI Translation with Bilingual View (Feature #18)

**Goal**: Translate current section via AI, show original + translation side by side.

**Priority**: High | **Estimate**: M

**Dependencies**: WI-D00 + WI-009, WI-010

**Tests (first)**:
- `vreaderTests/ViewModels/AITranslationTests.swift`
  - `translateCallsAIWithTargetLanguage`: verify request has `.translate` + targetLanguage
  - `bilingualViewShowsBothTexts`: verify both original and translation displayed
  - `languagePickerSetsTarget`: select Chinese, verify targetLanguage == "Chinese"

**Touched areas**:
- New: `vreader/Views/Reader/BilingualView.swift` — side-by-side or interleaved display
- `vreader/Views/Reader/AIReaderPanel.swift` — add Translation tab
- `vreader/ViewModels/AIAssistantViewModel.swift` — `translate()` already exists

**Acceptance**:
- "Translate" shows language picker then translates (manual test)
- Bilingual view shows original on left/top, translation on right/bottom
- Supports at least Chinese, Japanese, Korean, Spanish, French
- Translation cached for repeated access to same section

**Risks**: Translation quality varies by provider/model; long sections may exceed token limits.
**Mitigation**: Chunk long sections; show per-chunk loading. Display provider/model info so user knows quality expectations.

**Rollback**: Remove bilingual view + translation tab. AI translate action remains but UI-less.

**Note**: WI-012 modifies `AIReaderPanel.swift` (created in WI-010, also modified by WI-011). If WI-011 and WI-012 are parallelized, coordinate merge on this file.

---

#### WI-013: General AI Chat Interface (Feature #15)

**Goal**: AI chat not tied to specific book context (general Q&A, overlaps with #14).

**Priority**: Medium | **Estimate**: S (incremental on WI-011)

**Dependencies**: WI-011

**Tests (first)**:
- `vreaderTests/ViewModels/AIChatViewModelTests.swift` (extend)
  - `generalChatHasNoBookContext`: create without book, verify no book context in system prompt
  - `switchBetweenBookAndGeneral`: toggle modes, verify context changes

**Touched areas**:
- `vreader/ViewModels/AIChatViewModel.swift` — optional bookFingerprint (nil = general mode)
- `vreader/Views/AI/AIChatView.swift` — accessible from library (not just reader)
- `vreader/Views/LibraryView.swift` — add AI chat button in toolbar (conditional on flag)

**Acceptance**:
- AI chat accessible from library toolbar (manual test)
- General chat has no book-specific context
- Book chat still includes current book context
- Unit tests pass

**Risks**: None significant — incremental on WI-011.

**Rollback**: Remove library toolbar button. Book-scoped chat remains.

---

#### WI-014: Remote Server Integration — Design Only (Feature #16)

**Goal**: Design document for remote server protocol. No implementation.

**Priority**: Medium | **Estimate**: S (design only)

**Dependencies**: None.

**Output**: `docs/codex-plans/remote-server-design.md` with:
- Protocol definition (WebSocket vs REST)
- Authentication flow
- Command taxonomy (directory listing, file operations, AI relay)
- Security considerations
- Data model for server connections

**Acceptance**: Design document reviewed and approved before implementation.

**No code changes. No tests.**

**Rollback**: N/A (design only).

---

#### WI-015: iCloud Backup & Restore — Design Only (Feature #10)

**Goal**: Design document for iCloud backup. No implementation.

**Priority**: Medium | **Estimate**: S (design only)

**Dependencies**: None.

**Output**: `docs/codex-plans/icloud-backup-design.md` with:
- Data scope (books, annotations, positions, settings)
- CloudKit vs document-based sync
- Conflict resolution strategy
- Migration/versioning plan
- Privacy implications

**Acceptance**: Design document reviewed and approved before implementation.

**No code changes. No tests.**

**Rollback**: N/A (design only).

---

## 5. Execution Order

```
Phase A (Quick Wins — all independent, can parallelize):
  WI-001 (library prefs)
  WI-002 (bookmark haptic)
  WI-003 (search highlight dismiss)

Phase B (Reader Enhancements — all independent, can parallelize):
  WI-004 (progress bar)
  WI-005 (MD TOC)
  WI-006 (context menu)

Phase C (Annotation):
  WI-C00 (anchor schema) → WI-007 (EPUB) }
                          → WI-008 (PDF)  } independent after WI-C00

Phase D (AI):
  WI-D00 (foundation) → WI-009 (Settings) → WI-010 (Summarize) → WI-011 (Chat) → WI-013 (General Chat)
                                                                 → WI-012 (Translation) [parallel with WI-011*]
  WI-014, WI-015 (Design docs — anytime, can start in Phase B)

  * WI-011 and WI-012 both modify AIReaderPanel.swift — if parallelized, coordinate merge.
```

**Critical path**: WI-D00 → WI-009 → WI-010 → WI-011 → WI-013 (longest AI chain).
**Second critical path**: WI-C00 → WI-007/WI-008 (annotation gated on anchor schema).
**Note**: WI-012 branches from WI-010, not WI-011 — it can start as soon as WI-010 is done.

---

## 6. Feature → WI Mapping

| Feature # | Summary | WI (full dependency chain) | Status |
|-----------|---------|----------------------------|--------|
| #1 | Edit and delete bookmarks | N/A | **ALREADY DONE** |
| #5 | Search highlight auto-dismiss | WI-003 | PLANNED |
| #6 | Persist library view preferences | WI-001 | PLANNED |
| #7 | Visual feedback for bookmark | WI-002 | PLANNED |
| #8 | Reading position scrubber | WI-004 | PLANNED |
| #9 | Comprehensive book context menu | WI-006 | PLANNED |
| #10 | iCloud backup and restore | WI-015 (design only) | PLANNED |
| #11 | EPUB text highlighting | WI-C00 → WI-007 | PLANNED |
| #12 | Auto-generate TOC for MD (TXT deferred per D3) | WI-005 | PLANNED |
| #13 | AI summarization | WI-D00 → WI-009 → WI-010 | PLANNED |
| #14 | AI chat — talk to the book | WI-D00 → WI-009 → WI-010 → WI-011 | PLANNED |
| #15 | AI chat interface (general) | WI-D00 → WI-009 → WI-010 → WI-011 → WI-013 | PLANNED |
| #16 | Remote server integration | WI-014 (design only) | PLANNED |
| #17 | PDF annotation | WI-C00 → WI-008 | PLANNED |
| #18 | AI translation + bilingual | WI-D00 → WI-009 → WI-010 → WI-012 | PLANNED |
| #20 | Sort order reset to default | WI-001 (bundled) | PLANNED |

**Total**: 15 features → 17 WIs (13 implementation + 2 prerequisite foundations + 2 design-only)

---

## 7. Testing Procedures

### Build Command
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project vreader.xcodeproj -scheme vreader \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

### Test Command (per suite)
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project vreader.xcodeproj -scheme vreader \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test -only-testing:vreaderTests/<SuiteName>
```

### When to Run
- After each WI implementation: build + targeted test suite
- After each phase: full test suite
- Before PR: full build + all tests

---

## 8. Manual Test Checklist

### Phase A
- [ ] Kill app, relaunch — sort order and view mode preserved
- [ ] Tap bookmark button — feel light haptic
- [ ] Search, navigate to result, scroll — highlight clears

### Phase B
- [ ] Open TXT/MD/EPUB/PDF — drag progress bar, reader scrolls to position
- [ ] Open MD file with headings — TOC shows heading list
- [ ] Long-press book in library — see Info, Share, Delete options

### Phase C
- [ ] AnnotationAnchor round-trip: EPUB, PDF, TXT anchor types all encode/decode correctly
- [ ] Open EPUB — long-press text — see Highlight/Note/Copy menu
- [ ] Open PDF — select text — see Highlight/Note/Copy menu
- [ ] Close and reopen — highlights restored (both EPUB and PDF)

### Phase D (foundation)
- [ ] Change FeatureFlags.shared.aiAssistant to ON — AIService immediately sees the change
- [ ] Kill/relaunch — AI toggle setting persisted
- [ ] Translate same passage to Chinese vs Japanese — get different cached responses

### Phase D (features)
- [ ] Settings → enable AI → enter API key → select model → back to reader
- [ ] Tap Summarize — see AI response in panel
- [ ] Open chat — ask question — get contextual answer with book context
- [ ] Open general chat from library — no book context in prompt
- [ ] Translate section — see bilingual view

---

## 9. Plan → Verify Handoff

| WI | Evidence to Collect |
|----|-------------------|
| WI-001 | Unit test pass + manual kill/relaunch screenshot |
| WI-002 | Unit test pass + device haptic video |
| WI-003 | Unit test pass + screen recording of scroll-dismiss |
| WI-004 | Unit test pass + screen recording of scrubber in all 4 formats |
| WI-005 | Unit test pass + TOC screenshot for MD file with headings |
| WI-006 | Unit test pass + context menu screenshot |
| WI-C00 | Unit test pass for all 3 anchor types (encode/decode round-trip) |
| WI-007 | Unit test pass + EPUB highlight screenshot + reopen verification |
| WI-008 | Unit test pass + PDF annotation screenshot + reopen verification |
| WI-D00 | Unit test pass for FeatureFlags shared ref, cache key uniqueness, optional fields |
| WI-009 | Unit test pass + settings screen screenshot |
| WI-010 | Unit test pass + AI response screenshot |
| WI-011 | Unit test pass + multi-turn chat screenshot |
| WI-012 | Unit test pass + bilingual view screenshot |
| WI-013 | Unit test pass + library chat screenshot |
| WI-014 | Design doc reviewed |
| WI-015 | Design doc reviewed |

**Fixtures needed**:
- MD file with `#`–`######` headings including headings inside fenced code blocks (for WI-005)
- EPUB with selectable text (for WI-007)
- PDF with selectable text + image-only PDF for edge case (for WI-008)
- Mock `PreferenceStore` conformance for unit tests (for WI-001)
- Mock `FeatureFlags` shared instance (for WI-D00, WI-009)
- Mock AI provider returning canned responses (for WI-010–013)
- Sample `AnnotationAnchor` values for all 3 formats (for WI-C00)
