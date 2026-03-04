# iOS Reader App - Implementation Plan (Revised)

**Date:** 2026-03-04
**Status:** Revised Draft (Post-Architecture Review)
**Project:** vreader (iOS)

---

## 0. Revision Goals

This revision addresses all previously identified Critical/High issues by:

- Resolving sync scope contradictions with an explicit **file + metadata sync contract** (V2) and local-only baseline (V1).
- Splitting delivery into **MVP-v1** and **MVP-v2** with realistic timelines.
- Defining a canonical, cross-format **Locator** and **DocumentIdentity** model before reader feature work.
- Adding explicit **TDD RED/GREEN/REFACTOR** steps and `ut` gates per work item.
- Replacing `swift build/test` assumptions with **`xcodebuild`**** + ****`ut`**.
- Adding schema migration strategy, lifecycle matrix, configuration work item, key storage policy, and AI consent/privacy requirements.
- Clarifying previously ambiguous behavior (refresh semantics, duplicate identity, overlap handling, normalization, merge algorithm).
- Pulling a sync feasibility spike earlier and isolating AI behind a feature flag.

---

## 1. Technology and Architecture Decisions

### 1.1 Core Stack

| Choice        | D ecision                                                                    |
| ------------- | ---------------------------------------------------------------------------- |
| Language      | Swift 6                                                                      |
| UI            | SwiftUI-first with UIKit bridges                                             |
| Persistence   | SwiftData (local), CloudKit-backed SwiftData for sync-enabled entities in V2 |
| Reader Engine | Readium Swift Toolkit for EPUB; PDFKit for PDF                               |
| Testing       | Swift Testing + XCTest where required by UI/integration harness              |
| Min OS        | iOS 17                                                                       |

### 1.2 Wording Correction

Previous "SwiftUI only" wording is replaced with:

> **SwiftUI-first with UIKit bridges** (`UIViewControllerRepresentable` / `UIViewRepresentable`) for Readium and PDFKit surfaces.

### 1.3 AI Feature Flag

AI is gated by runtime + build-time flags:

- `FeatureFlags.aiAssistant` (default OFF in V1 release branch).
- Requires explicit user consent + valid provider config.
- App remains fully functional when AI is disabled/unconfigured.

---

## 2. Scope and Timeline

### 2.1 MVP-v1 (10 weeks)

**Goal:** Stable local reader with import, EPUB/PDF reading, settings, bookmarks, highlights, search index, and robust lifecycle/error handling.
**No cross-device sync. No AI in production.**

Included:

1. Local library + import (EPUB/PDF)
2. Reader core (EPUB + PDF)
3. Typography/theme settings
4. Canonical locator-based reading position persistence
5. Bookmarks + TOC
6. Highlights + annotations
7. In-book full-text search with background indexing
8. Accessibility/performance baseline
9. Configuration system + secure settings foundation

### 2.2 MVP-v2 (8 weeks)

**Goal:** Cross-device sync + AI assistant rollout after foundational stability.

Included:

1. Cloud sync spike hardening -> production sync
2. File + metadata sync model (on-demand file downloads)
3. Conflict resolution and observability
4. AI assistant (summary/Q\&A/translation/vocabulary) behind feature flag
5. AI privacy consent flow + cache + error policy
6. Export highlights, reading statistics (if capacity allows)

---

## 3. Canonical Data Contracts (Must Be Implemented Early)

### 3.1 DocumentIdentity (Duplicate + Cross-device Identity)

```swift
struct DocumentIdentity: Codable, Hashable {
    let contentSHA256: String          // Hash of normalized file bytes
    let fileByteCount: Int64
    let format: BookFormat             // epub, pdf, txt, md
    let importSource: ImportSource     // filesApp, shareSheet, icloudDrive, localCopy
}
```

Rules:

1. Primary identity key: `(contentSHA256, fileByteCount, format)`.
2. Filename and metadata are non-authoritative.
3. Duplicate import detection uses identity key.
4. If metadata changes but identity key matches, update metadata, do not create a new book.
5. For sync, this identity is the cross-device join key.

### 3.2 Locator (Cross-format Reading Position)

```swift
struct Locator: Codable, Hashable {
    let bookIdentity: DocumentIdentity
    let format: BookFormat
    let href: String?                  // EPUB spine/document reference
    let progression: Double?           // 0...1 within resource/chapter
    let totalProgression: Double?      // 0...1 across whole publication
    let page: Int?                     // PDF page index or fixed-layout page
    let cfi: String?                   // EPUB CFI when available
    let textQuote: String?             // Stable quote anchor for reflow recovery
    let textContextBefore: String?
    let textContextAfter: String?
}
```

Rules:

1. All reading state (position, bookmark, highlight anchor, search result target) stores Locator.
2. EPUB uses `href + progression` and `cfi` when available.
3. PDF uses `page` (+ optional textQuote anchors for robust restore).
4. Reflow invalidation recovery uses `textQuote + context` fallback.
5. No feature-specific custom position schemas allowed.

---

## 4. Sync Contract (Contradiction Resolved)

### 4.1 V1

- Local-only storage; no CloudKit production sync.
- Data model includes sync-ready fields but sync is disabled.

### 4.2 V2 (Production)

- Sync scope includes:

1. Library metadata
2. Reading positions
3. Bookmarks
4. Highlights/notes
5. **File manifest + optional file payload sync** via iCloud container/on-demand download

Behavior:

1. On new device, library entries appear with sync metadata.
2. If payload present in iCloud, book auto-downloads or downloads on open.
3. If payload missing/unavailable, entry is shown as "Not Downloaded" with retry.
4. No "broken" readable states without clear UI state.

---

## 5. Configuration and Secrets

### 5.1 Configuration Work Item Required

Create `AppConfiguration` with:

- `Environment` (dev/staging/prod)
- API base URLs
- Retry/timeouts
- Feature flags (`aiAssistant`, `sync`, `searchIndexingVerboseLogs`)
- Logging/telemetry toggles

Sources:

1. Build settings (`xcconfig`)
2. Local overrides for debug only
3. Runtime remote overrides (optional, V2+)

### 5.2 Storage Policy

- `@AppStorage` only for non-sensitive preferences (theme, font size, layout mode).
- Keychain for secrets (AI API keys, provider tokens).
- Never store secrets in SwiftData or UserDefaults.
- Provide key reset/revocation path in Settings.

---

## 6. Schema Evolution and Migration Strategy

### 6.1 Versioning

- Define model versions `SchemaV1`, `SchemaV2`, ... explicitly.
- Every schema change requires:

1. Migration plan document
2. Migration test fixture from previous schema
3. Rollback/fallback behavior documented

### 6.2 Migration Policy

- Lightweight migration first where possible.
- For breaking changes:

1. Add compatibility fields
2. Backfill on first launch post-upgrade
3. Keep old readers tolerant for one version window

- Sync-aware migrations must include conflict tests.

---

## 7. Lifecycle Matrix

| App State Event            | Required Actions                                                                                  | Timeout / Guard                  |
| -------------------------- | ------------------------------------------------------------------------------------------------- | -------------------------------- |
| Cold Launch                | Load config -> open DB -> hydrate library snapshot -> defer indexing/sync until first frame       | First frame < 1.5s target        |
| Enter Foreground           | Refresh stale sync status, resume pending imports/index tasks                                     | No blocking UI                   |
| Enter Background           | Flush reading position, persist pending bookmark/highlight ops, checkpoint import/index job state | Hard cap 3s background task      |
| Termination (normal)       | Same as background flush                                                                          | Best effort                      |
| Crash Recovery Next Launch | Replay idempotent pending operations from durable queue                                           | Queue operations must be deduped |
| Memory Warning             | Release thumbnails/caches, pause non-critical indexing                                            | Keep active reader stable        |

---

## 8. Search Indexing Pipeline

Search is not direct full-book scanning on each query.

Pipeline:

1. On import/open, enqueue indexing job per book.
2. Extract normalized text chunks by chapter/page.
3. Store tokenized index in local persistent store.
4. Query uses indexed lookup + ranked snippets.
5. Update index incrementally when parser/version changes.
6. Support cancellation and resume.

Performance constraints:

- Indexing runs background-priority.
- UI queries must remain responsive (<150ms for typical books).
- Large result sets paginated.

Normalization:

- Unicode NFKC normalization.
- Case folding locale-aware.
- Diacritic-insensitive matching using folded forms.
- CJK full-width/half-width normalization.
- Literal matching for special characters (no regex semantics in MVP).

---

## 9. Ambiguity Resolutions (Normative)

### 9.1 Pull-to-refresh (Library)

Semantics:

1. Refresh does **not** rescan full file bytes by default.
2. It reloads SwiftData snapshot + checks filesystem existence + refreshes lightweight metadata timestamps.
3. Full metadata re-parse is manual via per-book "Rebuild Metadata".
4. Refresh is throttled (min 5s interval) and cancelable.

### 9.2 Duplicate Model

- Duplicate if identity key matches `(contentSHA256, fileByteCount, format)`.
- Same filename with different hash => new book.
- Same hash from different source => same logical book; update source list history.
- Concurrent import race resolved by DB unique constraint + retry fetch.

### 9.3 Highlight Overlap Rule

Chosen behavior: **Layered highlights (no auto-merge).**

- Overlaps allowed.
- Render order: newest on top.
- Editing/deleting acts on selected highlight ID only.
- Export preserves individual highlights.

### 9.4 Bookmark Merge Algorithm (Sync)

Data model fields:

- `bookmarkId` (UUID)
- `bookIdentity`
- `locatorCanonicalHash`
- `updatedAt`
- `isDeleted` (tombstone)

Merge:

1. Group by `(bookIdentity, locatorCanonicalHash)`.
2. If one active + one tombstone -> winner by newest `updatedAt`.
3. If multiple active duplicates -> keep newest label, preserve earliest createdAt.
4. Tombstones retained for retention window to prevent resurrection.

---

## 10. Work Breakdown Structure

### WI-0: Project Scaffold, CI, and Test Gates (Week 1)

**Goal:** Establish build/test baseline aligned with AGENTS constraints.

Tasks:

1. Create/verify Xcode project targeting iOS 17.
2. Add dependencies (Readium modules, test utilities).
3. Configure `xcodebuild` schemes and test plans.
4. Wire `ut` gate command in CI and local docs.
5. Add lint/format hooks if present in repo standards.

Acceptance:

- `xcodebuild -scheme vreader -destination 'platform=iOS Simulator,name=iPhone 15' build` passes.
- `xcodebuild ... test` passes.
- `ut` passes and is documented as required gate.

TDD:

1. RED: Add failing CI smoke test expecting missing scheme/test plan.
2. GREEN: Configure scheme/test plan.
3. REFACTOR: Simplify CI scripts and docs.

---

### WI-1: Data Models, DocumentIdentity, Locator, Migration Baseline (Week 1-2)

**Goal:** Define canonical data contracts and persistence schema foundation.

Tasks:

1. Add models: `Book`, `ReadingPosition`, `Bookmark`, `Highlight`, `AnnotationNote`.
2. Add `DocumentIdentity` and `Locator` structs.
3. Add unique constraints and indexes for duplicate prevention.
4. Add schema versioning scaffold (`SchemaV1`).
5. Add migration test harness fixture layout.

Edge cases:

- Missing metadata title/author.
- CJK/RTL strings.
- Long titles.
- Deleted book cascade behavior.
- Locator fallback when CFI missing.

Acceptance:

- Model round-trip tests pass.
- Duplicate key uniqueness enforced.
- Locator serialization/deserialization stable.
- Baseline migration test from empty DB passes.

TDD:

1. RED: Failing tests for duplicate detection, locator persistence, cascade delete.
2. GREEN: Implement minimal models and constraints.
3. REFACTOR: Extract shared locator helpers.

---

### WI-2: Import Service + Identity + Durable Job Queue (Week 2-3)

**Goal:** Robust EPUB/PDF import with deterministic identity and safe failure behavior.

Tasks:

1. Implement `BookImporter` with protocol abstraction.
2. Compute content hash with streaming read (memory-safe).
3. Copy into sandbox atomically (temp + rename).
4. Extract metadata via Readium/PDFKit.
5. Add import job queue with resume/retry/cancel.
6. Return structured domain errors.

Edge cases:

- Corrupt files, permission denied, low disk, canceled import, external source removed mid-copy, extension mismatch, DRM EPUB.
- Concurrent same-file imports.

Acceptance:

- Duplicate imports return existing book.
- Cancel cleans temp artifacts.
- Structured errors mapped to user-facing messages.
- Race-safe idempotent import behavior.

TDD:

1. RED: Failing tests for corruption, cancellation cleanup, race duplicate.
2. GREEN: Minimal importer + queue.
3. REFACTOR: Split hashing/copy/metadata adapters.

---

### WI-3: Configuration and Secrets (Week 3)

**Goal:** Centralized configuration and secure secret storage.

Tasks:

1. Implement `AppConfiguration`.
2. Define feature flags (`aiAssistant`, `sync`).
3. Build Keychain-backed credential store.
4. Keep preference storage in `@AppStorage` only for non-secrets.
5. Add tests for environment resolution and keychain read/write/delete.

Acceptance:

- Config values resolved by environment.
- Keychain operations tested.
- No API key reads/writes via UserDefaults/SwiftData.

TDD:

1. RED: Failing tests for missing env fallback and keychain persistence.
2. GREEN: Implement minimal config/keychain services.
3. REFACTOR: Remove duplicated config access paths.

---

### WI-4: Library View + Pull-to-refresh Semantics (Week 3-4)

**Goal:** Performant local library UX with deterministic refresh behavior.

Tasks:

1. Grid/list toggle, sort modes, delete.
2. Empty state and onboarding CTA.
3. Pull-to-refresh using defined lightweight semantics.
4. Accessibility labels and Dynamic Type support.

Acceptance:

- 1000-book library remains responsive.
- Refresh follows throttled local semantics.
- Delete removes local file + metadata.
- Accessibility checks pass baseline.

TDD:

1. RED: Failing tests for sort/delete/empty/refresh-throttle.
2. GREEN: Implement ViewModel and view bindings.
3. REFACTOR: Isolate formatting/accessibility helpers.

---

### WI-5: Locator & Document Identity Integration Spike (Week 4)

**Goal:** De-risk downstream features before full reader implementation.

Tasks:

1. Verify Locator generation from Readium and PDFKit samples.
2. Verify re-open restore for EPUB reflow and PDF page model.
3. Validate textQuote fallback recovery.
4. Produce design note with proven mapping and limitations.

Acceptance:

- Integration tests pass for at least 3 EPUB fixtures + 2 PDF fixtures.
- Known limitations documented with mitigations.

TDD:

1. RED: Failing restore tests with reflow/font changes.
2. GREEN: Implement mapping and fallback.
3. REFACTOR: Consolidate locator adapters.

---

### WI-6: EPUB Reader Core (Week 4-6)

**Goal:** Stable paginated EPUB reading via Readium.

Tasks:

1. `ReadiumService` wrapper.
2. `EPUBReaderView` with UIKit bridge.
3. Page navigation (swipe/tap).
4. Persist position using Locator with debounce.
5. Handle fixed-layout and RTL.

Acceptance:

- Open/read EPUB reliably.
- Position restore robust after app restart.
- Debounced save works.
- RTL/fixed layout validated on fixtures.

TDD:

1. RED: Failing tests for page turn persistence and restore.
2. GREEN: Implement reader shell and position save.
3. REFACTOR: Extract navigator event adapter.

---

### WI-7: PDF Reader Core (Week 6-7)

**Goal:** PDF reading with position persistence and large-file handling.

Tasks:

1. `PDFReaderView` wrapper around `PDFView`.
2. Page navigation, page indicator, zoom.
3. Password prompt flow.
4. Position persistence using Locator page + optional quote anchor.

Acceptance:

- Password-protected docs supported.
- Large PDF navigation remains stable.
- Position restore works after restart.

TDD:

1. RED: Failing tests for password branch and page persistence.
2. GREEN: Implement minimal PDF reader behavior.
3. REFACTOR: Isolate PDF document adapter.

---

### WI-8: Typography and Themes (Week 7)

**Goal:** Global reading preferences and immediate application.

Tasks:

1. Theme/typography controls.
2. Persist via `@AppStorage`.
3. Apply to Readium via style injection.
4. WCAG contrast validation tests.
5. CJK default spacing profile.

Acceptance:

- Immediate updates without losing position.
- Theme contrast passes tests.
- Preferences survive relaunch.

TDD:

1. RED: Failing tests for bounds/clamping/contrast/persistence.
2. GREEN: Implement ThemeService and controls.
3. REFACTOR: Extract theme token definitions.

---

### WI-9: Bookmarks, TOC, Highlights, Annotations (Week 7-8)

**Goal:** Annotation workflows built on canonical Locator.

Tasks:

1. Bookmark toggle/list/navigation.
2. TOC display/navigation.
3. Text highlight + note flow.
4. Overlap behavior = layered (newest on top).
5. Annotation list and edit/delete.

Acceptance:

- Bookmark/annotation navigation accurate.
- Overlap behavior deterministic.
- Data persists and restores across sessions.

TDD:

1. RED: Failing tests for toggle/sort/dedupe/overlap behavior.
2. GREEN: Implement minimal logic and views.
3. REFACTOR: Share locator navigation utility.

---

### WI-10: Full-text Search with Indexing (Week 8-9)

**Goal:** Fast in-book search using background index pipeline.

Tasks:

1. Build indexing service and storage.
2. Add debounced query UI and paginated results.
3. Navigate to matched locations via Locator.
4. Implement normalization: NFKC + case fold + diacritic fold + full/half-width handling.
5. Handle no-text PDFs gracefully.

Acceptance:

- Search responsive on large books.
- CJK and diacritics behavior passes fixture tests.
- Results paginate and do not block UI.

TDD:

1. RED: Failing tests for normalization, empty query, no-text layer, pagination.
2. GREEN: Implement index + query pipeline.
3. REFACTOR: Split tokenizer/normalizer/query planner.

---

### WI-11: AI Assistant (Feature-flagged) + Privacy/Consent (V2 Week 11-13)

**Goal:** Optional AI actions with explicit consent and safe defaults.

Tasks:

1. AI provider abstraction + streaming response support.
2. Context window extraction around current locator.
3. Response cache by `(bookIdentity, locatorHash, actionType, promptVersion)`.
4. **Consent flow before first use**:
   - Explain what text leaves device.
   - Explain provider processing and retention caveats.
   - Require explicit opt-in.
5. Provider/API key management via Keychain.
6. Error taxonomy: network, timeout, rate limit, policy refusal, invalid key.
7. Feature flag rollout controls.

Acceptance:

- AI disabled path fully functional.
- No outbound AI call before consent + configured key.
- Clear user-facing errors for all failure classes.
- Cache hit behavior validated.

TDD:

1. RED: Failing tests for consent gating and no-key behavior.
2. GREEN: Implement minimal provider + consent gate.
3. REFACTOR: Extract provider adapters and error mapper.

---

### WI-12: Sync Spike (Early) and Production Sync (V2 Week 9-10 Spike, Week 13-16 Build)

**Goal:** De-risk and then implement Cloud sync with file availability guarantees.

#### Part A: Early Spike (moved earlier than final phase)

Tasks:

1. Validate CloudKit-backed SwiftData viability for core entities.
2. Validate conflict scenarios and tombstones.
3. Validate file manifest + on-demand payload model.
4. Produce go/no-go report before full sync implementation.

#### Part B: Production Sync

Tasks:

1. Implement sync state machine and status UI.
2. Implement file manifest sync + download manager.
3. Implement merge algorithm (bookmarks/highlights/positions).
4. Handle iCloud-disabled, sign-out, quota exceeded, interrupted network.

Acceptance:

- Sync correctness tests pass for conflict vectors.
- Eventual consistency achieved; UI exposes sync status and retry.
- No hard "30s" guarantee; documented SLA is eventual with observable status.

TDD:

1. RED: Failing conflict tests and offline/retry cases.
2. GREEN: Minimal sync + merge + file availability flow.
3. REFACTOR: Separate sync transport, merge engine, and UI state.

---

### WI-13: Accessibility, Performance, and Release Hardening (Week 16-18)

**Goal:** Production readiness for V1/V2 branches.

Tasks:

1. VoiceOver traversal audit.
2. Dynamic Type and Reduce Motion compliance.
3. Launch-time profiling and deferred initialization checks.
4. Memory pressure and long-session soak tests.
5. Final error-message audit.

Acceptance:

- Accessibility checklist complete.
- Startup target first frame <1.5s on iPhone 14 baseline.
- No P0 crashers in soak/regression suite.

TDD:

1. RED: Add failing regression/perf threshold tests where automatable.
2. GREEN: Fix bottlenecks and missing accessibility states.
3. REFACTOR: Remove temporary instrumentation and dead paths.

---

## 11. Testing and Gates (Global)

Required per WI:

1. RED: Add failing tests first.
2. GREEN: Implement minimum passing behavior.
3. REFACTOR: Cleanup while preserving green tests.
4. Run `ut` before marking WI complete.

CI command baseline (example):

```bash
xcodebuild -scheme vreader -destination 'platform=iOS Simulator,name=iPhone 15' build
xcodebuild -scheme vreader -destination 'platform=iOS Simulator,name=iPhone 15' test
ut
```

No WI is "done" without:

- Acceptance criteria met
- Tests added for listed edge cases
- `ut` passing

---

## 12. Project Structure (Updated)

```text
vreader/
├── docs/
│   └── codex-plans/
│       └── 2026-03-04-ios-reader-app.md
├── vreader/
│   ├── App/
│   │   ├── VReaderApp.swift
│   │   ├── AppState.swift
│   │   ├── LifecycleCoordinator.swift
│   │   └── AppConfiguration.swift
│   ├── Models/
│   │   ├── Book.swift
│   │   ├── DocumentIdentity.swift
│   │   ├── Locator.swift
│   │   ├── ReadingPosition.swift
│   │   ├── Bookmark.swift
│   │   ├── Highlight.swift
│   │   └── Migration/
│   │       ├── SchemaV1.swift
│   │       └── MigrationPlan.swift
│   ├── Services/
│   │   ├── BookImporter.swift
│   │   ├── ImportJobQueue.swift
│   │   ├── ReadiumService.swift
│   │   ├── PDFService.swift
│   │   ├── ThemeService.swift
│   │   ├── SearchIndexService.swift
│   │   ├── SyncService.swift
│   │   ├── AIService.swift
│   │   ├── ConsentService.swift
│   │   ├── KeychainService.swift
│   │   └── FeatureFlags.swift
│   ├── Views/
│   │   ├── Library/
│   │   ├── Reader/
│   │   ├── Bookmarks/
│   │   ├── Annotations/
│   │   ├── Search/
│   │   ├── Sync/
│   │   ├── AI/
│   │   └── Settings/
│   └── Utils/
├── vreaderTests/
│   ├── Models/
│   ├── Services/
│   ├── ViewModels/
│   ├── Integration/
│   │   ├── LocatorIntegrationTests.swift
│   │   ├── ImportRaceTests.swift
│   │   └── SyncConflictTests.swift
│   └── Fixtures/
└── vreaderUITests/
```

Constraint:

- Keep Swift files under \~300 LOC by splitting adapters/helpers.

---

## 13. Risks and Mitigations

1. **Locator robustness across reflow/content changes**
   Mitigation: WI-5 spike + quote/context fallback + fixture-heavy tests before feature expansion.
2. **Sync complexity (data + files)**
   Mitigation: early sync spike, explicit state machine, eventual consistency with status UI.
3. **AI legal/privacy/operational risk**
   Mitigation: feature flag, explicit consent gate, keychain storage, strict error taxonomy.

---

## 14. Release Criteria

### MVP-v1 Release Criteria

- Local reader workflows stable and tested.
- No AI in production path.
- No production sync requirement.
- `ut` green and critical UI flows pass.

### MVP-v2 Release Criteria

- Sync and AI feature flags enabled only after QA sign-off.
- Conflict and offline scenarios validated.
- Privacy consent and settings UX approved.
- Telemetry indicates stable crash/perf profile.

---

## 15. Non-goals (Current Plan Window)

- Kindle/AZW proprietary formats.
- Collaborative/shared annotations.
- Regex search across full library.
- Server-side account system beyond iCloud identity.
- Cross-platform clients (macOS/web) in this phase.

