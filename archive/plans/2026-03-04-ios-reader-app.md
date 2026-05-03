# iOS Reader App - Implementation Plan (Revised v4)

**Date:** 2026-03-04 (Updated 2026-03-05)
**Status:** Revised Draft (Post-Feasibility Review + Reading Time Integration + Architecture Corrections)
**Project:** vreader (iOS)

---

## 0. Revision Goals

This revision addresses all Critical/High feasibility issues by:

- Defining one source of truth for reading-speed metadata (indexing only).
- Defining one normative TXT `wordsRead` formula.
- Adding a SwiftData concurrency contract with actor isolation.
- Defining `deviceId` lifecycle and `readerProfileId`.
- Moving SwiftData+CloudKit schema feasibility validation into WI-1.
- Splitting V2 sync into explicit milestones with exit criteria.
- Defining canonical `sourceUnitId` format for all content types.
- Introducing shared `ReadingSessionTracker` work before reader-specific integration.
- Pulling a thin search-to-locator vertical slice before annotations.
- Adding a normative reading-session state machine with idempotent guards.
- Adding explicit FTS5 corpus sizing and benchmark targets.
- Removing trailing non-plan artifact content.

---

## 1. Technology and Architecture Decisions

### 1.1 Core Stack

| Choice        | Decision                                                                          |
| ------------- | --------------------------------------------------------------------------------- |
| Language      | Swift 6                                                                           |
| UI            | SwiftUI-first with UIKit bridges                                                  |
| Persistence   | SwiftData (local), CloudKit-backed SwiftData for sync metadata in V2              |
| Reader Engine | Readium Swift Toolkit (EPUB), PDFKit (PDF), TextKit via `UITextView` bridge (TXT) |
| Search Index  | SQLite FTS5 + token span mapping store                                            |
| Testing       | Swift Testing + XCTest where required by UI/integration harness                   |
| Min OS        | iOS 17                                                                            |

### 1.2 Wording Correction

`SwiftUI-first with UIKit bridges` remains the app architecture.
EPUB/PDF use UIKit bridges. TXT also uses a UIKit bridge (`UITextView`) for precise selection and offset mapping; SwiftUI remains the container/screen composition layer.

### 1.3 AI Feature Flag

AI is gated by runtime + build-time flags:

- `FeatureFlags.aiAssistant` (default OFF in V1 release branch).
- Requires explicit user consent + valid provider config.
- App remains fully functional when AI is disabled/unconfigured.

### 1.4 SwiftData Concurrency Contract

All persistence access follows strict actor isolation:

1. `PersistenceActor` is the only writer actor for SwiftData mutations.
2. Background jobs (import/index/sync) use dedicated background `ModelContext`s created inside `PersistenceActor`.
3. UI reads use main-actor snapshot/view models; UI never performs direct background writes.
4. Cross-actor transfer uses immutable DTOs only (no passing live model objects across actors).
5. Write operations are serialized by key (`bookFingerprint`) to avoid race conditions in import/index/session updates.
6. Every write path is idempotent and retry-safe.

---

## 2. Scope and Timeline

### 2.1 MVP-v1 (Weeks 1-10)

**Goal:** Stable local reader with import, EPUB/PDF/TXT reading, settings, bookmarks, highlights, search index, reading time tracking, and robust lifecycle/error handling.  
**No production cross-device sync. No AI in production.**

Included:

1. Local library + import (EPUB/PDF/TXT)
2. Reader core (EPUB + PDF + TXT)
3. Typography/theme settings
4. Canonical locator-based reading position persistence
5. Bookmarks + TOC (TOC gracefully absent for TXT)
6. Highlights + annotations
7. In-book full-text search with background indexing
8. Accessibility/performance baseline integrated per work item
9. Configuration system + secure settings foundation
10. Early sync feasibility spikes and schema validation (non-production)
11. Reading time tracking per book (session duration, accumulated totals, reading speed)

### 2.2 MVP-v2 (Weeks 11-18)

**Goal:** Production sync + AI rollout after foundational stability.

Included:

1. Production sync build and hardening
2. File + metadata sync model (on-demand file downloads)
3. Conflict resolution and observability
4. AI assistant (summary/Q\&A/translation/vocabulary) behind feature flag
5. AI privacy consent flow + cache + error policy
6. Export highlights, reading statistics dashboard (extends V1 reading time foundation with cross-device merge and historical charts)

---

## 3. Canonical Data Contracts (Must Be Implemented Early)

### 3.1 DocumentFingerprint and ImportProvenance

```swift
struct DocumentFingerprint: Codable, Hashable {
    let contentSHA256: String          // SHA-256 over exact imported bytes
    let fileByteCount: Int64
    let format: BookFormat             // epub, pdf, txt, md (md reserved; not importable in V1)
}

struct ImportProvenance: Codable, Hashable {
    let source: ImportSource           // filesApp, shareSheet, icloudDrive, localCopy
    let importedAt: Date
    let originalURLBookmarkData: Data? // optional security-scoped bookmark
}
```

Rules:

1. Primary identity key is `DocumentFingerprint`.
2. Filename and metadata are non-authoritative.
3. Duplicate import detection uses `DocumentFingerprint`.
4. If metadata changes but fingerprint matches, update metadata and provenance history; do not create a new book.
5. For sync, `DocumentFingerprint` is the cross-device join key.
6. `ImportProvenance` is never part of identity equality/hash.

### 3.2 Locator (Cross-format Reading Position)

```swift
struct Locator: Codable, Hashable {
    let bookFingerprint: DocumentFingerprint
    let href: String?                  // EPUB spine/document reference
    let progression: Double?           // 0...1 within resource/chapter
    let totalProgression: Double?      // 0...1 across whole publication
    let page: Int?                     // PDF page index or fixed-layout page
    let charOffsetUTF16: Int?          // TXT canonical offset
    let charRangeStartUTF16: Int?      // TXT highlight range start
    let charRangeEndUTF16: Int?        // TXT highlight range end (exclusive)
    let cfi: String?                   // EPUB CFI when available
    let textQuote: String?             // Stable quote anchor for reflow recovery
    let textContextBefore: String?
    let textContextAfter: String?
}
```

Rules:

1. All reading state (position, bookmark, highlight anchor, search target) stores `Locator`.
2. EPUB uses `href + progression` and `cfi` when available.
3. PDF uses `page` (+ optional quote/context fallback when extractable).
4. TXT canonical offsets are UTF-16 code unit offsets over decoded raw source text before display transforms.
5. TXT paragraph joining/wrapping is display-only and must never change stored offsets.
6. No feature-specific custom position schemas allowed.
7. `bookFingerprint.format` is the single source of format truth; locator does not duplicate format.

### 3.3 Locator Canonical Hash

`locatorCanonicalHash = SHA-256(canonical JSON of Locator v1)` with rules:

1. UTF-8 encoding.
2. Sorted keys lexicographically.
3. Omit `nil` fields.
4. Round floating values (`progression`, `totalProgression`) to 6 decimal places.
5. Normalize line endings in quote/context to `\n` before hashing.

### 3.4 ReadingSession and ReadingStats

```swift
@Model
final class ReadingSession {
    @Attribute(.unique) var sessionId: UUID
    var bookFingerprint: DocumentFingerprint
    var startedAt: Date
    var endedAt: Date?
    var durationSeconds: Int
    var pagesRead: Int?
    var wordsRead: Int?
    var startLocator: Locator?
    var endLocator: Locator?
    var deviceId: String
    var isRecovered: Bool
}

@Model
final class ReadingStats {
    @Attribute(.unique) var bookFingerprint: DocumentFingerprint
    var totalReadingSeconds: Int
    var sessionCount: Int
    var lastReadAt: Date?
    var averagePagesPerHour: Double?
    var averageWordsPerMinute: Double?
    var totalPagesRead: Int?
    var totalWordsRead: Int?
    var longestSessionSeconds: Int
}
```

Rules:

1. `ReadingSession` is the source of truth; `ReadingStats` is a materialized aggregate.
2. Duration is measured using `ProcessInfo.processInfo.systemUptime` (monotonic clock), not `Date` subtraction.
3. Wall-clock `startedAt`/`endedAt` are stored for display and sync ordering only.
4. Sessions shorter than 5 seconds are discarded.
5. Sessions longer than 24 hours are capped/split.
6. `ReadingStats` is recomputed from sessions on first access after app update or data repair.
7. Active sessions (`endedAt == nil`) are closed on next app launch with `isRecovered = true`.
8. `wordsRead` for EPUB/TXT is estimated using metadata produced only by the indexing pipeline (Section 8.2). Import does not compute reading-speed metadata.
9. `pagesRead` for PDF is counted by tracking distinct page indices visited during a session.
10. Reading speed averages use exponential moving average (alpha = 0.3).

### 3.5 Device Identity and Reader Profile

`deviceId` policy:

1. `deviceId` is a random UUID generated on first launch and stored in Keychain.
2. `deviceId` persists across app relaunch and reinstall when Keychain survives.
3. If Keychain is wiped, a new `deviceId` is generated.
4. `deviceId` is pseudonymous and never joined with PII.
5. Settings exposes `Reset Sync Identity` to rotate `deviceId`.

`readerProfileId` policy:

1. V1 supports one profile only: `readerProfileId = "default"`.
2. V2 may add multiple profiles.
3. Reading position key is `(bookFingerprint, readerProfileId)`.

---

## 4. Sync Contract

### 4.1 V1

- Local-only storage; production sync disabled.
- Data model can be sync-ready, but `FeatureFlags.sync == false` by default in V1.
- Lifecycle sync actions are guarded no-op when sync is disabled.

### 4.2 V2 (Production)

Sync scope includes:

1. Library metadata
2. Reading positions
3. Bookmarks
4. Highlights/notes
5. File manifest + optional file payload via iCloud container/on-demand download
6. Reading sessions (`ReadingStats` recomputed locally from sessions)

Behavior:

1. On new device, library entries appear with sync metadata.
2. Entries are readable only when file state is `available`.
3. If payload unavailable, entry remains visible with explicit state + retry actions.
4. No broken/implicit unreadable states.

### 4.3 File Availability State Machine

States:

1. `metadataOnly`
2. `queuedDownload`
3. `downloading`
4. `available`
5. `failed`
6. `stale`

Transitions:

1. `metadataOnly -> queuedDownload` on auto-download policy or user open.
2. `queuedDownload -> downloading` when scheduler starts transfer.
3. `downloading -> available` after checksum/fingerprint verification.
4. `downloading -> failed` on network/auth/quota errors.
5. `available -> stale` on local corruption or manifest mismatch.
6. `failed -> queuedDownload` on retry.

Guard:

- Reader open is allowed only in `available`.
- UI always surfaces current state and next action.

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
2. Local debug overrides
3. Runtime remote overrides (optional, V2+; signed payload + versioned TTL)

### 5.2 Storage Policy

- `@AppStorage` only for non-sensitive preferences.
- Keychain for secrets (AI keys/tokens and `deviceId`).
- Never store secrets in SwiftData/UserDefaults.
- Provide key reset/revocation path in Settings.

---

## 6. Schema Evolution and Migration Strategy

### 6.1 Versioning

- Define explicit schema versions (`SchemaV1`, `SchemaV2`, ...).
- Every schema change requires:

1. Migration plan document
2. Migration fixture from previous schema
3. Rollback/fallback behavior

### 6.2 Migration Policy

- Lightweight migration where possible.
- For breaking changes:

1. Add compatibility fields
2. Backfill on first launch post-upgrade
3. Keep old readers tolerant for one version window

- Sync-aware migrations require conflict tests.

---

## 7. Lifecycle Matrix

| App State Event            | Required Actions                                                                                                       | Timeout / Guard       |
| -------------------------- | ---------------------------------------------------------------------------------------------------------------------- | --------------------- |
| Cold Launch                | Load config -> open DB -> hydrate library snapshot -> recover active sessions -> defer indexing/sync until first frame | First frame < 1.5s    |
| Enter Foreground           | Resume import/index tasks; if reader open, invoke tracker resume/start; if sync enabled, refresh status                | No blocking UI        |
| Enter Background           | End or grace-pause session via tracker; flush reading position; checkpoint jobs                                        | Hard cap 3s           |
| Reader Open                | Call `startSessionIfNeeded` with monotonic baseline and start locator                                                  | Idempotent            |
| Reader Close               | Call `endSessionIfNeeded`; persist session + aggregate update                                                          | Atomic write          |
| Termination (normal)       | Best-effort background flush                                                                                           | Best effort           |
| Crash Recovery Next Launch | Close sessions with `endedAt == nil`, mark `isRecovered = true`, use last periodic flush                               | Queue ops deduped     |
| Memory Warning             | Release non-critical caches, pause non-critical indexing                                                               | Reader remains stable |

Reading session periodic flush:

- While active, flush `durationSeconds` every 60 seconds.
- Limits crash-loss window to <= 60 seconds.

### 7.1 Reading Session State Machine (Normative)

States:

1. `idle`
2. `active(sessionId)`
3. `pausedGrace(sessionId, pausedAt)`
4. `closed`

Transitions:

1. `idle -> active` on `startSessionIfNeeded`.
2. `active -> pausedGrace` on background when reader remains mounted.
3. `pausedGrace -> active` on foreground within 30s for same book.
4. `pausedGrace -> closed` when grace expires or different book opens.
5. `active -> closed` on reader close/termination flush.
6. Duplicate `startSessionIfNeeded` while active is a no-op.
7. Duplicate `endSessionIfNeeded` while idle/closed is a no-op.

---

## 8. Search Indexing Pipeline

Search does not scan full books at query time.

Pipeline:

1. On import/open, enqueue indexing job per book.
2. Extract text units by format.
3. Normalize text for search keys.
4. Store terms in SQLite FTS5 and token span map for navigation.
5. Query FTS5, rank snippets, resolve hits through span map to `Locator`.
6. Support cancellation/resume and incremental reindex on parser/version changes.

Format extraction:

- EPUB: text per spine item/chapter.
- PDF: text per page via PDFKit.
- TXT: decoded raw text; paragraph chunking for snippets only.

Performance constraints:

- Background-priority indexing.
- Paginated large result sets.

Normalization:

- Unicode NFKC
- Locale-aware case folding
- Diacritic folding
- Full-width/half-width folding
- Literal matching for special characters (no regex in MVP)

### 8.1 Token-to-Offset Mapping Contract

For every indexed token occurrence, store:

1. `bookFingerprint`
2. `normalizedToken`
3. `startOffsetUTF16` and `endOffsetUTF16`
4. `sourceUnitId` with canonical per-format encoding:
   - EPUB: `epub:<href>`
   - PDF: `pdf:page:<zero-based-page-index>`
   - TXT: `txt:segment:<zero-based-segment-index>`

Navigation rule:

- Search result tap resolves canonical offsets first, then constructs `Locator`.
- Display snippets can be transformed, but offset anchors remain source-canonical.

### 8.2 Reading-Speed Metadata Extraction (Single Source of Truth)

Reading-speed metadata is computed only during indexing (not during import) and persisted on `Book`:

- `totalWordCount: Int?`
- `totalPageCount: Int?` (PDF only)
- `totalTextLengthUTF16: Int?` (TXT only)

Computation:

- EPUB: sum words across spine items using Unicode word boundaries.
- TXT: compute both `totalWordCount` and `totalTextLengthUTF16` over decoded source text.
- PDF: compute `totalPageCount`; word count optional and may be nil for non-text PDFs.

If metadata is missing, reading speed is omitted until indexing completes; reading duration tracking always continues.

### 8.3 Corpus Sizing and Benchmarks (Required)

Benchmark corpus tiers:

1. Small: 50 books, total raw text <= 250 MB.
2. Medium: 500 books, total raw text <= 2 GB.
3. Large: 1000 books, total raw text <= 4 GB.

Performance targets (iPhone 14 baseline, release build):

1. Query p50 <= 80 ms, p95 <= 150 ms on Small/Medium.
2. Query p95 <= 220 ms on Large.
3. Initial indexing throughput >= 1.5 MB/s average.
4. Search index overhead <= 35% of normalized text size.
5. Peak RSS during indexing one 50 MB TXT <= 450 MB.

Fixtures:

- Tiered fixture manifest and repeatable benchmark harness.
- CI: Small on every PR; Medium/Large nightly.

---

## 9. Normative Behavior

### 9.1 Pull-to-refresh (Library)

1. Refresh does not rescan full file bytes by default.
2. Refresh reloads SwiftData snapshot + verifies file existence + updates lightweight timestamps.
3. Full metadata re-parse is manual (`Rebuild Metadata`).
4. Refresh is throttled (min 5s interval) and cancelable.

### 9.2 Duplicate Model

- Duplicate if `DocumentFingerprint` matches.
- Same filename with different fingerprint => new book.
- Same fingerprint from different source => same logical book; append provenance history.
- Concurrent import race resolved by DB unique constraint + retry fetch.

### 9.3 Highlight Overlap Rule

- Layered highlights (no auto-merge).
- Overlaps allowed.
- Render order newest first.
- Edit/delete targets selected highlight only.
- Export preserves distinct highlights.

### 9.4 Sync Merge Algorithms (All Entities)

#### ReadingPosition

- Key: `(bookFingerprint, readerProfileId)`
- Rule: last-write-wins by `updatedAt`; tie-breaker lexicographic `deviceId`.
- Staleness guard: if payload is `stale`/missing, keep metadata but block open until file available.

#### Bookmark

- Key: `(bookFingerprint, locatorCanonicalHash)`
- Fields: `bookmarkId`, `updatedAt`, `isDeleted`
- Rule: newest `updatedAt` wins active vs tombstone; keep earliest `createdAt`.

#### Highlight

- Key: `highlightId` + `bookFingerprint`
- Rule: operation-based merge with tombstones; newest `updatedAt` per field set wins.

#### AnnotationNote

- Key: `noteId`
- Rule: last-write-wins by `updatedAt`, with tombstone precedence when newer.

#### LibraryMetadata

- Key: `bookFingerprint`
- Rule:

1. User-edited title/author wins over extracted metadata.
2. Newest user edit wins.
3. Extracted metadata fills only empty user fields.

#### FileManifest

- Key: `bookFingerprint`
- Rule: manifest version monotonic; higher version wins, checksum mismatch forces `stale`.

#### ReadingSession

- Key: `sessionId`
- Rule: append-only, immutable after end, idempotent insert on duplicates.

#### ReadingStats

- Not synced directly. Recomputed locally from synced `ReadingSession` union per book.

Tombstone retention window:

- Minimum 30 days before purge.

### 9.5 TXT Format Handling

Encoding detection pipeline:

1. BOM sniff (UTF-8/UTF-16 LE/BE/UTF-32 LE/BE).
2. Strict UTF-8 decode attempt.
3. `NSString.stringEncoding(for:encodingOptions:convertedString:usedLossyConversion:)` with suggested encodings:
   - windowsCP1252
   - isoLatin1
   - shiftJIS
   - GB\_18030\_2000
   - EUC\_KR
   - big5
4. Fallback `.windowsCP1252`.
5. Final fallback UTF-8 lossy replacement (`U+FFFD`).

Store detected encoding in `Book` metadata for reopen consistency.

Paragraph splitting (display-only):

- Paragraph boundary: one or more blank lines.
- Single newlines inside a paragraph may be visually joined with spaces.
- Trim leading/trailing paragraph whitespace.
- Empty files produce zero paragraphs.
- Files with no blank lines are one paragraph.

Metadata for TXT:

- Title from filename (trimmed, max 255 chars).
- Author unknown.
- No cover image; use format placeholder.

### 9.6 Reading Time Tracking

Session lifecycle:

1. Session starts when reader view appears or app foregrounds with active reader.
2. Session ends on reader disappear, background timeout, or termination flush.
3. Foreground within 30s resumes same session for same book.
4. Duration uses monotonic uptime clock.

Guards:

- Sessions under 5s discarded.
- Sessions over 24h are split.
- Sessions crossing midnight are not split.
- Crash recovery closes sessions with `isRecovered = true` using last flush.

Reading speed calculation:

| Format | Metric           | Calculation                                                                                                                            |
| ------ | ---------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| PDF    | Pages per hour   | `pagesRead / (durationSeconds / 3600)`                                                                                                 |
| EPUB   | Words per minute | `round((abs(endTotalProgression - startTotalProgression)) * totalWordCount)` then divide by minutes                                    |
| TXT    | Words per minute | `wordsRead = round((abs(endOffsetUTF16 - startOffsetUTF16) / totalTextLengthUTF16) * totalWordCount)` clamped to `[0, totalWordCount]` |

Rules:

- No speed for sessions under 60s.
- No speed if required metadata is unavailable.
- Outliers (>3x or <0.1x running average) excluded from average, still stored.
- Display rounding: pages/hr nearest int, wpm nearest 10.

Display:

- Library: `Xh Ym read` from `ReadingStats.totalReadingSeconds`.
- Reader overlay: `Session: Xm`, `Total: Xh Ym`.
- Reader info panel: `~Y pages/hr` or `~Z wpm`.
- `<1m`, `Xm`, `Xh Ym` formatting rules apply.

---

## 10. Work Breakdown Structure

### WI-0: Project Scaffold, CI, and Test Gates (Week 1)

Goal: Establish build/test baseline aligned with AGENTS constraints.

Tasks:

1. Verify Xcode project targets iOS 17.
2. Add dependencies (Readium modules, SQLite FTS5 integration).
3. Configure `xcodebuild` schemes/test plans.
4. Wire `ut` in CI and local docs.

Acceptance:

- `xcodebuild ... build` passes.
- `xcodebuild ... test` passes.
- `ut` passes and is required gate.

---

### WI-1: Data Models, Fingerprint, Locator, Migration Baseline + Schema Feasibility (Weeks 1-2)

Tasks:

1. Add models: `Book`, `ReadingPosition`, `Bookmark`, `Highlight`, `AnnotationNote`, `ImportProvenance`.
2. Add `DocumentFingerprint` and revised `Locator`.
3. Define `BookFormat`: `.epub`, `.pdf`, `.txt`, `.md` (`.md` reserved/not importable in V1).
4. Add unique constraints/indexes.
5. Add schema version scaffold (`SchemaV1`).
6. Add migration fixture layout.
7. Add canonical TXT UTF-16 offset fields.
8. Add `ReadingSession`.
9. Add `ReadingStats`.
10. Add `Book.totalWordCount`, `Book.totalPageCount`, `Book.totalTextLengthUTF16` (indexing-produced metadata).
11. Add unique constraints on `ReadingSession.sessionId` and `ReadingStats.bookFingerprint`.
12. Run early SwiftData+CloudKit feasibility spike for sync keys/constraints.
13. If unsupported, introduce primitive key columns (`fingerprintKey`, `locatorHash`, `profileKey`) as canonical sync keys.

Acceptance:

- Round-trip model tests pass.
- Duplicate uniqueness enforced by `DocumentFingerprint` (or canonical primitive key fallback).
- Locator serialization stable for EPUB/PDF/TXT.
- TXT UTF-16 offsets round-trip at boundaries.
- Baseline migration test passes.
- Reading session/stats persistence and recomputation tests pass.
- Feasibility report produced and approved before V2 sync build.

---

### WI-2: Import Service + Identity + Durable Job Queue (Weeks 2-3)

Tasks:

1. Implement `BookImporter`.
2. Handle security-scoped URLs with guaranteed cleanup.
3. Compute content hash by streaming exact bytes.
4. Copy to sandbox atomically (temp + rename).
5. Extract metadata: Readium/PDFKit/filename.
6. Add durable import queue with retry/cancel/resume.
7. Return structured domain errors.
8. TXT encoding pipeline from Section 9.5.
9. TXT binary masquerade heuristic (>10% control bytes in first 8KB excluding `\t\n\r`).
10. Persist provenance entry for each import source.
11. Emit indexing trigger only; do not compute reading-speed metadata in import.

Acceptance:

- Duplicate imports return existing book.
- Cancel cleans temp artifacts and releases scoped resources.
- Structured errors map to UI messages.
- Race-safe idempotent behavior.
- TXT encoding fixtures pass.
- Binary masquerade rejected with clear error.
- Empty TXT import succeeds.

---

### WI-3: Configuration and Secrets (Week 3)

Tasks:

1. Implement `AppConfiguration`.
2. Define feature flags (`aiAssistant`, `sync`).
3. Build Keychain credential store + `deviceId` storage/rotation.
4. Restrict `@AppStorage` to non-secrets.
5. Add env resolution and keychain CRUD tests.

Acceptance:

- Config resolves by environment.
- Keychain operations tested.
- No secret reads/writes via UserDefaults/SwiftData.

---

### WI-4: Library View + Pull-to-refresh (Weeks 3-4)

Tasks:

1. Grid/list toggle, sort, delete.
2. Empty state and onboarding CTA.
3. Pull-to-refresh semantics from Section 9.1.
4. Accessibility labels + Dynamic Type baseline.
5. Format badges/placeholders.
6. Display accumulated reading time from `ReadingStats.totalReadingSeconds`.
7. Display speed if available.
8. Sorting by `lastReadAt` and `totalReadingSeconds`.
9. Omit reading time label for zero time.

Acceptance:

- 1000-book library responsive.
- Refresh throttling works.
- Delete removes local file + metadata + associated sessions/stats.
- Accessibility baseline checks pass.
- Reading labels/sorts/speed behavior correct.

---

### WI-5: Locator & Fingerprint Integration Spike (Week 4)

Tasks:

1. Validate locator generation for Readium/PDFKit/TXT.
2. Validate reopen restore + fallback.
3. Validate textQuote/context recovery.
4. Validate TXT UTF-16 offset restore.
5. Produce design note and limitations.

Acceptance:

- Integration tests: 3 EPUB + 2 PDF + 2 TXT fixtures.
- TXT restore survives restart.

---

### WI-5A: TXT Anchor & Rendering Feasibility Spike (Weeks 4-5)

Tasks:

1. Prototype `UITextView` bridge with SwiftUI container.
2. Verify selection range extraction to canonical UTF-16 offsets.
3. Verify scroll position -> offset mapping from TextKit layout APIs.
4. Validate 5MB/50MB large-file behavior with chunked/lazy strategy.
5. Validate no-freeze behavior on very long lines.

Go/No-go:

- Exact offset round-trip (+/-0 UTF-16).
- No UI freeze in fixtures.
- Peak RSS within benchmark budget from Section 8.3.

---

### WI-5B: Shared ReadingSessionTracker Contract (Week 5)

Tasks:

1. Implement `ReadingSessionTracker` with idempotent APIs:
   - `startSessionIfNeeded(...)`
   - `recordProgress(...)`
   - `endSessionIfNeeded(...)`
2. Centralize 30s grace-resume behavior.
3. Centralize <5s discard and 24h split logic.
4. Add tests for duplicate lifecycle events, crash recovery, and flapping transitions.

Acceptance:

- One canonical session behavior for EPUB/TXT/PDF.
- Double-start/double-end events are no-op.
- Shared tracker tests pass before reader-specific work.

---

### WI-6: EPUB Reader Core (Weeks 5-6)

Tasks:

1. `ReadiumService` wrapper.
2. `EPUBReaderView` bridge.
3. Page navigation.
4. Debounced locator persistence.
5. Fixed-layout + RTL handling.
6. Integrate shared `ReadingSessionTracker`.
7. Capture session start/end locators.
8. Estimate EPUB `wordsRead` from progression delta \* `totalWordCount`.
9. Display current/total reading time.
10. Display wpm when metadata is available.

Acceptance:

- Open/read EPUB reliably.
- Position restore robust.
- Accessibility/perf baselines pass.
- Session lifecycle correctness and guard behavior pass.

---

### WI-6A: TXT Reader Core (Weeks 6-7)

Tasks:

1. Implement `TXTService`.
2. Implement SwiftUI container + TextKit bridge.
3. Offset mapping/restore via TextKit APIs.
4. Debounced position save.
5. Selection -> highlight/bookmark char ranges.
6. Chunked/lazy loading for large files.
7. Theme/typography without anchor drift.
8. Integrate shared `ReadingSessionTracker`.
9. Capture canonical UTF-16 start/end locators.
10. Estimate TXT `wordsRead` with Section 9.6 normative formula.
11. Display current/total reading time.
12. Display wpm when metadata is available.

Acceptance:

- UTF-8/ASCII/legacy render correctly.
- Position persists/restores via canonical offsets.
- Large fixtures stable.
- Session/speed behavior matches contract.

---

### WI-7: PDF Reader Core (Weeks 7-8)

Tasks:

1. `PDFReaderView` wrapper.
2. Navigation, indicator, zoom.
3. Password prompt flow.
4. Locator persistence with page + fallback anchor.
5. Integrate shared `ReadingSessionTracker`.
6. Track distinct page indices for `pagesRead`.
7. Capture start/end locators.
8. Display current/total reading time.
9. Display pages/hr.

Acceptance:

- Password-protected docs supported.
- Large PDFs stable.
- Accessibility/perf baselines pass.
- Session/page metrics correct.

---

### WI-8: Typography and Themes (Week 8)

Tasks:

1. Theme/typography controls.
2. Persist via `@AppStorage`.
3. Apply EPUB styles via Readium injection.
4. Apply TXT styles via bridge.
5. WCAG contrast tests.
6. CJK spacing profile.

Acceptance:

- Immediate updates without losing position.
- Contrast tests pass.
- Preferences survive relaunch.

---

### WI-8A: Search-to-Locator Vertical Slice (Week 8)

Tasks:

1. Index one EPUB, one PDF, one TXT fixture into FTS5 + span map.
2. Implement query -> result tap -> locator restore end-to-end.
3. Verify canonical offset and sourceUnitId mapping by format.

Acceptance:

- End-to-end search navigation works on all 3 formats.
- Contract gaps resolved before WI-9.

---

### WI-9: Bookmarks, TOC, Highlights, Annotations (Weeks 8-9)

Tasks:

1. Bookmark toggle/list/navigation.
2. TOC display/navigation; TXT TOC absent state.
3. Highlight + note flow.
4. Layered overlap behavior.
5. Annotation list/edit/delete.
6. TXT highlights use UTF-16 range locator fields.

Acceptance:

- Accurate navigation for EPUB/PDF/TXT.
- Deterministic overlap behavior.
- Persistence across sessions.
- Out-of-bounds ranges clamp + content-changed indicator.

---

### WI-10: Full-text Search with Indexing (Weeks 9-10)

Tasks:

1. Build production FTS5 indexing + span map service.
2. Debounced query UI + pagination.
3. Navigate via locator from span map.
4. Apply normalization rules.
5. Handle no-text PDFs.
6. TXT indexing from decoded source text and canonical offsets.
7. Add benchmark harness and enforce Section 8.3 thresholds.

Acceptance:

- Responsive search on large fixtures.
- CJK/diacritic tests pass.
- Non-blocking pagination.
- Correct search-to-locator navigation.
- Query latency and memory thresholds from Section 8.3 pass.

---

### WI-11: AI Assistant (Feature-flagged) + Privacy/Consent (V2 Weeks 11-13)

Tasks:

1. Provider abstraction + streaming responses.
2. Context extraction around current locator.
3. Cache by `(bookFingerprint, locatorHash, actionType, promptVersion)`.
4. Mandatory consent before outbound call.
5. Keychain-based key management.
6. Error taxonomy and mapping.
7. Feature-flag rollout controls.

Acceptance:

- Disabled path fully functional.
- No outbound calls before consent/key.
- Clear error behavior.
- Cache behavior validated.

---

### WI-12: Sync Build (V2 Weeks 13-16)

Part A (already completed in V1):

- Schema feasibility and early sync spike outputs from WI-1 + earlier spikes are required inputs.

Part B: Production Sync Milestones

Milestone 1 (Metadata Sync Core):

1. Implement metadata sync for library/positions/bookmarks/highlights/notes/sessions.
2. Implement conflict resolver and tombstones.
   Exit criteria:

- Deterministic conflict tests pass.
- Offline edit/reconnect convergence verified.

Milestone 2 (File Manifest + Downloader):

1. Implement file manifest sync + download scheduler.
2. Implement file availability state machine from Section 4.3.
   Exit criteria:

- Reader open blocked outside `available`.
- Retry/recovery validated for network/auth/quota failures.

Milestone 3 (Observability + Hardening):

1. Sync status UI, retries, diagnostics.
2. iCloud disabled/sign-out/account-switch handling.
   Exit criteria:

- Eventual consistency verified in soak tests.
- Failure states visible and actionable.

---

### WI-13: Accessibility, Performance, Release Hardening (V2 Weeks 16-18)

Tasks:

1. Cross-feature VoiceOver audit.
2. Dynamic Type and Reduce Motion compliance.
3. Launch-time profiling and deferred init checks.
4. Memory and soak tests.
5. Final error-message audit.
6. Verify reading time labels are spoken accessibly (expanded text).

Acceptance:

- Checklist complete.
- Startup first frame <1.5s on iPhone 14 baseline.
- No P0 crashers in soak/regression.

---

## 11. Testing and Gates (Global)

Required per WI:

1. RED: failing tests first.
2. GREEN: minimum implementation.
3. REFACTOR: cleanup.
4. Run `ut` before marking complete.

CI baseline:

```bash
xcodebuild -scheme vreader -destination 'platform=iOS Simulator,name=iPhone 15' build
xcodebuild -scheme vreader -destination 'platform=iOS Simulator,name=iPhone 15' test
ut
```

No WI is done without:

- Acceptance criteria met
- Edge-case tests for listed cases
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
│   │   ├── BookFormat.swift
│   │   ├── DocumentFingerprint.swift
│   │   ├── ImportProvenance.swift
│   │   ├── Locator.swift
│   │   ├── ReadingPosition.swift
│   │   ├── Bookmark.swift
│   │   ├── Highlight.swift
│   │   ├── ReadingSession.swift
│   │   ├── ReadingStats.swift
│   │   └── Migration/
│   │       ├── SchemaV1.swift
│   │       └── MigrationPlan.swift
│   ├── Services/
│   │   ├── PersistenceActor.swift
│   │   ├── BookImporter.swift
│   │   ├── ImportJobQueue.swift
│   │   ├── ReadiumService.swift
│   │   ├── PDFService.swift
│   │   ├── TXTService.swift
│   │   ├── ThemeService.swift
│   │   ├── SearchIndexService.swift
│   │   ├── ReadingSessionTracker.swift
│   │   ├── ReadingStatsAggregator.swift
│   │   ├── SyncService.swift
│   │   ├── AIService.swift
│   │   ├── ConsentService.swift
│   │   ├── KeychainService.swift
│   │   └── FeatureFlags.swift
│   ├── ViewModels/
│   │   └── ReadingTimeFormatter.swift
│   ├── Views/
│   │   ├── Library/
│   │   │   └── ReadingTimeBadge.swift
│   │   ├── Reader/
│   │   │   ├── EPUBReaderView.swift
│   │   │   ├── PDFReaderView.swift
│   │   │   ├── TXTReaderContainerView.swift
│   │   │   ├── TXTTextViewBridge.swift
│   │   │   ├── ReaderContainerView.swift
│   │   │   └── ReadingSessionOverlay.swift
│   │   ├── Bookmarks/
│   │   ├── Annotations/
│   │   ├── Search/
│   │   ├── Sync/
│   │   ├── AI/
│   │   └── Settings/
│   └── Utils/
│       ├── EncodingDetector.swift
│       ├── LocatorCanonicalizer.swift
│       └── MonotonicClock.swift
├── vreaderTests/
│   ├── Models/
│   │   ├── LocatorTests.swift
│   │   ├── ReadingSessionTests.swift
│   │   └── ReadingStatsTests.swift
│   ├── Services/
│   │   ├── Mocks/
│   │   │   └── MockMonotonicClock.swift
│   │   ├── TXTServiceTests.swift
│   │   ├── EncodingDetectorTests.swift
│   │   ├── SearchSpanMapTests.swift
│   │   ├── SearchBenchmarkTests.swift
│   │   ├── ReadingSessionTrackerTests.swift
│   │   └── ReadingStatsAggregatorTests.swift
│   ├── Integration/
│   │   ├── LocatorIntegrationTests.swift
│   │   ├── SearchLocatorSliceTests.swift
│   │   ├── ImportRaceTests.swift
│   │   ├── TXTBridgeOffsetTests.swift
│   │   ├── SyncConflictTests.swift
│   │   └── ReadingSessionLifecycleTests.swift
│   └── Fixtures/
│       ├── corpus-small-manifest.json
│       ├── corpus-medium-manifest.json
│       ├── corpus-large-manifest.json
│       ├── sample.epub
│       ├── sample.pdf
│       ├── sample-utf8.txt
│       ├── sample-latin1.txt
│       ├── sample-shift-jis.txt
│       ├── sample-empty.txt
│       ├── sample-large.txt
│       └── sample-binary-masquerade.txt
└── vreaderUITests/
```

Constraint:

- Keep Swift files under \~300 LOC by splitting adapters/helpers.

---

## 13. Risks and Mitigations

1. Locator robustness across reflow/content changes  
   Mitigation: WI-5 spike, canonical hash, quote/context fallback, fixture-heavy tests.
2. TXT anchor correctness + rendering scale  
   Mitigation: WI-5A feasibility spike, TextKit bridge, large fixtures, benchmark gates in Section 8.3.
3. Sync complexity (metadata + files)  
   Mitigation: WI-1 schema feasibility + phased WI-12 milestones with exit criteria.
4. Encoding detection across legacy charsets  
   Mitigation: deterministic API pipeline + persisted encoding + lossy fallback.
5. Reading time accuracy under edge conditions  
   Mitigation: monotonic clock, minimum duration filter, 24h split, periodic flush, crash recovery, EMA smoothing.

---

## 14. Release Criteria

### MVP-v1

- Local workflows stable and tested (EPUB/PDF/TXT).
- AI disabled in production.
- Production sync disabled.
- `ut` green and critical UI flows pass.
- TXT open/render/position/bookmark/search pass canonical offset tests.
- Reading time tracks correctly across open/close, background/foreground, and crash recovery.
- Reading speed calculates correctly where metadata is available.
- Library view displays accumulated reading time per book.
- Search benchmark targets for Small tier pass in CI.

### MVP-v2

- Sync + AI flags enabled only after QA sign-off.
- Conflict/offline/file-state scenarios validated.
- Privacy consent/settings approved.
- Telemetry shows stable crash/perf profile.
- Reading sessions sync across devices; aggregated stats recompute correctly.
- Medium/Large search benchmark tiers pass scheduled gates.

---

## 15. Non-goals (Current Plan Window)

- Kindle/AZW proprietary formats.
- Collaborative/shared annotations.
- Regex search across full library.
- Server-side account system beyond iCloud identity.
- Cross-platform clients (macOS/web) in this phase.
- TXT encoding override UI (future iteration).
- Rich text rendering for TXT (no Markdown interpretation in TXT mode).
- Reading time goal-setting or daily reading challenges (future iteration).
- Historical reading charts or calendar heatmaps (V2 stretch goal, not V1).

