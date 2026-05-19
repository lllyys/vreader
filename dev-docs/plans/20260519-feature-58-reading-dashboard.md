# Feature #58 — Reading-time + activity dashboard — Implementation Plan

- **Feature row**: `docs/features.md` #58 (`TODO`, Medium priority, Area `Library/*, Stats/*`).
- **GH issue**: #665.
- **Design bundle**: `dev-docs/designs/vreader-fidelity-v1/project/vreader-profile-stats.jsx` (issue-canvas handoff delivered 2026-05-18, resolves `needs-design` #862) + the pre-existing `vreader-stats.jsx`.
- **Plan author**: Claude Opus 4.7 (1M context). **Gate 2 auditor**: Codex MCP (independent process).
- **Workflow**: rule 47 six-gate. This document is **Gate 1**. Gate 2 audit log is in the revision history at the bottom.

---

## Revision history

| Version | Date | Change |
|---|---|---|
| v1 | 2026-05-19 | Initial plan drafted from the feature #58 row contract + codebase research. |
| v2 | 2026-05-19 | Gate-2 round-1 Codex audit fixes applied — F1–F8 (see "Audit fixes applied"). |
| v3 | 2026-05-19 | Gate-2 round-2 Codex re-audit: all 8 round-1 fixes confirmed RESOLVED; 2 new findings (1 High, 1 Medium) on `ReadingStats` exactness fixed — aggregator no longer reads `ReadingStats` (derives all numbers from sessions); restore writes `ReadingStats` verbatim, never calls `recomputeStats`. See round-2 log. |

---

## Problem

Per-session reading-time data is **already collected** — `ReadingSession` (SwiftData `@Model`: `sessionId`, `bookFingerprintKey`, `bookFingerprint`, `startedAt`, `endedAt`, `durationSeconds`, `pagesRead`, `wordsRead`, `startLocator`, `endLocator`, `deviceId`, `isRecovered`) is written by `ReadingSessionTracker` on every reader close. Per-book lifetime aggregates exist in `ReadingStats` (`@Model`: `bookFingerprintKey`, `bookFingerprint`, `totalReadingSeconds`, `sessionCount`, `lastReadAt`, `averagePagesPerHour`, `averageWordsPerMinute`, `totalPagesRead`, `totalWordsRead`, `longestSessionSeconds`), recomputed by `PersistenceActor.recomputeStats(...)`.

But **no surface exposes this to the user**. There is:
- no time-window aggregation (today / week / month / …);
- no per-book breakdown panel with notes + highlights counts;
- no sorting beyond `LibrarySortOrder.totalReadingTime` (which only sorts the Library list, not a stats view);
- no inclusion of `ReadingSession` / `ReadingStats` in the WebDAV backup payload — `BackupDataCollector` omits both, so a restore-to-fresh-device loses all reading history (CloudKit sync covers it only when iCloud sync is enabled, via `SyncReadingSessionRecord`).

This feature builds the read-only dashboard over the existing schemas plus one new backup payload section. **No new `@Model` types are required.**

---

## Surface area

### Files this plan will CREATE

| Path | What |
|---|---|
| `vreader/Services/Stats/ReadingStatsAggregator.swift` | New **actor** — time-window aggregation over `ReadingSession`. Public API below. |
| `vreader/Services/Stats/ReadingStatsModels.swift` | Value types: `ReadingStatsWindow` (enum), `WindowTotal`, `PerBookStatsRow`, `ReadingDashboardSnapshot`, `ReadingDashboardSortField`, `ReadingDashboardSort`. All `Sendable`/`Equatable`/`Codable` where needed. |
| `vreader/ViewModels/ReadingDashboardViewModel.swift` | `@MainActor @Observable` VM — owns the active window + sort, calls the aggregator, exposes the snapshot, persists sort via `PreferenceStoring`. |
| `vreader/Views/Stats/ReadingDashboardView.swift` | SwiftUI dashboard. `FullStatsDashboard` from the design — `ReaderSheetChrome` + `StatsTimeWindowBar` + hero total + per-book `SortablePerBookTable`. ≤300 lines; split helpers below. |
| `vreader/Views/Stats/StatsTimeWindowBar.swift` | The designed scrollable window-selector pill bar (`StatsTimeWindowBar` in `vreader-profile-stats.jsx`). |
| `vreader/Views/Stats/StatsPerBookTable.swift` | The designed sortable per-book table (`SortablePerBookTable` in `vreader-profile-stats.jsx`) — header with sort indicator + rows. |
| `vreader/Services/Backup/BackupReadingHistory.swift` | DTOs for the new `reading-history.json` backup section: `BackupReadingHistoryEnvelope`, `BackupReadingSession`, `BackupReadingStats`. (Kept in its own file rather than swelling `BackupSectionDTOs.swift` past the ~300-line guideline.) |
| `vreaderTests/Services/Stats/ReadingStatsAggregatorTests.swift` | Aggregator unit tests. |
| `vreaderTests/Services/Stats/ReadingStatsModelsTests.swift` | Window-boundary + sort-comparator unit tests. |
| `vreaderTests/ViewModels/ReadingDashboardViewModelTests.swift` | VM state + sort-persistence tests. |
| `vreaderTests/Services/Backup/BackupReadingHistoryTests.swift` | Collector/restorer round-trip + schema-compat tests. |

### Files this plan will MODIFY

| Path | Modification |
|---|---|
| `vreader/Services/Backup/BackupSectionDTOs.swift` | Bump `kBackupCurrentSchemaVersion` 1 → 2. Add a `// MARK: - Reading History` pointer comment referencing `BackupReadingHistory.swift`. **No other DTO moves.** |
| `vreader/Services/Backup/BackupDataRestorer.swift` | Decouple per-section schema acceptance from the global constant — see "Backward compat". Add `restoreReadingHistory(from:)`. |
| `vreader/Services/Backup/BackupDataCollector.swift` | Add `collectReadingHistory()`. |
| `vreader/Services/Backup/WebDAVProvider.swift` | Add `collectReadingHistory` to the `BackupDataCollecting` protocol **with a default-impl** in the `extension BackupDataCollecting` (returns an empty envelope — same pattern `collectLibraryManifest` uses, so existing mock collectors still compile). Add `restoreReadingHistory` to `BackupDataRestoring` **with a default no-op extension**. Add `("reading-history.json", rr-style)` to the collect tuple list and the `restoreFiles` loop. |
| `vreader/Services/PersistenceActor+Stats.swift` | Add `fetchAllReadingSessions() -> [ReadingSessionRecord]`, `fetchAllReadingStats() -> [ReadingStatsRecord]`, `restoreReadingHistory(_:)`. New value-type records (`ReadingSessionRecord`, `ReadingStatsRecord`) are declared in `ReadingStatsModels.swift` — never return `@Model` across the actor boundary. |
| `vreader/Views/Settings/SettingsView.swift` | Wire the **profile-card "Stats" button** to present `ReadingDashboardView` as a sheet. **See "Design-vs-row divergences" (D1) — this is the recommended resolution, NOT yet locked. The profile card itself is feature #67; this feature only adds the dashboard sheet + its presentation hook. If feature #67's profile card has not landed when WI-6 is reached, WI-6 is BLOCKED on #67 and the dashboard ships behind a temporary DEBUG-only `vreader-debug://` entry for verification only (Gate 5), with the user-facing entry deferred to the #67 merge.** |
| `docs/architecture.md` | Add `ReadingStatsAggregator` to the Services Layer table; add `reading-history.json` to the backup-section list; bump the stated backup schema version. (Doc-sync per rule 24 — separate commit in the WI that introduces each.) |
| `README.md` | Add "Reading stats dashboard" to the Features section (WI that ships the view). |

### Files explicitly OUT of scope

- **No new SwiftData `@Model`** — `ReadingSession` / `ReadingStats` are read-only here; `VReaderMigrationPlan.swift` / `SchemaV*.swift` are **untouched**. The backup-schema bump is the JSON-envelope `kBackupCurrentSchemaVersion`, a different versioning axis from the SwiftData schema.
- `ReadingSessionTracker.swift` — session capture is done; not modified.
- `vreader/Models/ReadingSession.swift`, `vreader/Models/ReadingStats.swift` — models unchanged.
- `LibrarySortOrder.swift` — the Library list sort is unrelated; the dashboard gets its own `ReadingDashboardSort`. Not modified.
- CloudKit sync types (`SyncReadingSessionRecord`, `VRReadingSession`) — the WebDAV backup section is independent of CloudKit; sync path untouched.
- `vreader/Views/Settings/` profile-header card — that surface is **feature #67** (GH #825), separately tracked. This feature consumes its `onOpenStats` hook only.
- The design's **streak / books-finished / pages-read tiles / hour-of-day chart / daily chart / recent-sessions list / "tracking since"** (present in `vreader-stats.jsx` and partially in `FullStatsDashboard`) — see "Design-vs-row divergences". These are **OUT of feature #58's row scope**; this plan ships only the row-scoped subset (window-pill bar + hero total + per-book table). The extra design widgets are noted as a follow-up feature.
- PDF/AZW3/MOBI-specific behavior — the dashboard is format-agnostic (it aggregates `ReadingSession`, which all formats write).

---

## Design-vs-row divergences — REQUIRE USER DECISION before Gate 3

The feature #58 **row** (the binding contract) and the **committed design** (`vreader-profile-stats.jsx`, the 2026-05-18 issue-#862 handoff) disagree on four points. **A plan cannot unilaterally rewrite the contract** — the row is the source of truth, and the design bundle is also binding (rule 51). Where they conflict, the conflict must be resolved by the user amending the tracker row, NOT by the plan silently picking a side. This section therefore **stages each divergence as an open decision** rather than asserting a resolution. The Gate-2 audit (round 1) explicitly flagged the plan's earlier "I'll just follow the design" framing as a contract change — corrected here.

These four divergences are the plan's known limitations. WI-1..WI-5 (the aggregator + backup half) are **unaffected** by all four — they can proceed. WI-6 (the dashboard UI) **cannot begin Gate 3 until the user picks** on divergences D1–D4, because each one changes what the View must render.

### D1 — Entry point (row says Library toolbar; design says Settings profile card)

- **Row**: "accessible from the Library toolbar (alongside Sort / Filter)".
- **Design**: routes from the **Settings sheet profile card's "Stats" button** (`ProfileCardLibrary.onOpenStats` → `FullStatsDashboard`).
- **Code fact**: `LibraryNavBar` has **no** Sort/Filter pill — Sort lives in `LibrarySectionHeader`'s chevron `Menu`; there is no Filter button at all. So the row's "alongside Sort/Filter" describes a toolbar arrangement that does not exist.
- **The conflict**: building a Library-toolbar Stats pill = self-designed UI (no design depicts it) → rule 51 violation. Building the Settings entry = following the design but contradicting the row's stated location AND depending on feature #67 (which owns that profile card and is itself `TODO`).
- **Decision needed**: (option A) amend the row to "reachable from the Settings profile card" and accept the #67 dependency; OR (option B) file a `needs-design` issue for a Library-toolbar Stats entry and block WI-6 until that design lands. **Plan recommendation: option A** — the committed design already answers "where does Stats live", and feature #67's row already names the Stats button as #58's entry point ("the Stats button's destination is feature #58's reading dashboard"). But this is the user's call, recorded as an open decision.

### D2 — Time windows (row's set ≠ design's set)

- **Row**: today / past-7d / past-30d / past-90d / **past-180d** / **past-365d** / all-time (7 rolling intervals).
- **Design** `TIME_WINDOWS`: Today / 7d / 30d / 90d / **Year** / All / **Custom** (7).
- **The conflict**: design has no 180d and no 365d-rolling; it has `Year` (calendar-YTD — ambiguous) and `Custom` (a custom-range picker — an undesigned sub-surface; building it = rule 51 violation).
- **Decision needed**: ship the **row's 7 windows** (`today, last7Days, last30Days, last90Days, last180Days, last365Days, allTime`) and relabel the designed 7-pill bar to `Today / 7d / 30d / 90d / 180d / 365d / All` — a label/data change to a designed component, no new surface. `Custom` is dropped (row never asks for it; its picker is undesigned). **Plan recommendation: accept** — the row's intervals are unambiguous and the pill bar's *shape* (7 scrollable pills) is unchanged; only the labels differ. Low-risk; recorded as a decision because it changes a designed component's text.

### D3 — Per-book table sort fields (row says 5; design's table has 4 columns)

- **Row Scope prose**: "sortable by: title, reading time, notes count, highlights count, last-read" (5 fields). **Row acceptance criterion (c)**: "sortable on all **4 columns**" (4).
- **Design** `SortablePerBookTable`: 4 columns — Book / Time / Hl / Notes — each a sortable header; default `mins desc`. No last-read column.
- **The conflict**: the row's own text is internally inconsistent (Scope says 5, criterion (c) says 4). The design has 4. Adding a 5th `last-read` header = an undesigned column = rule 51 violation.
- **Decision needed**: ship **4 sort fields** (title / readingTime / highlights / notes), matching the design's 4 columns AND the row's binding acceptance criterion (c). `last-read` sort is dropped. **Plan recommendation: accept 4** — criterion (c) ("all 4 columns") is the binding acceptance bar; the Scope prose's "5" predates the design and is superseded by it. Recorded as a decision because it drops a Scope-prose item.

### D4 — "Seven cards" vs the design's "one hero + 7-pill bar"

- **Row Scope**: "Top section shows the seven aggregate totals as **cards**".
- **Design** `FullStatsDashboard`: ONE large serif **hero total** for the *active* window + the 7-pill `StatsTimeWindowBar`; switching a pill re-renders the hero. There is no 7-simultaneous-card layout anywhere in the design.
- **The conflict**: 7 static cards is a layout the committed design does not contain — building it = rule 51 violation. The design's hero+bar shows one window at a time.
- **Decision needed**: ship the **design's hero + 7-pill bar** (one total visible, 7 windows selectable). **Plan recommendation: accept the design** — rule 51 forbids inventing the 7-card layout; the design's hero+bar surface delivers the same information (every window is one tap away). This is the **largest divergence** and the row's "as cards" phrasing is the casualty. Recorded as a decision because it overrides the row's explicit "seven … cards" wording.

> **Summary for the user**: the plan recommends accepting the committed design on all four points (A / accept / accept-4 / accept-hero) and amending the feature #58 row's Scope prose to match — because rule 51 makes the design binding and the row's UI prose predates the 2026-05-18 design handoff. **If the user instead wants the row's literal Library-toolbar + 7-card layout, that needs a fresh `needs-design` bundle and WI-6 blocks until it lands.** WI-1..WI-5 proceed either way. The plan's WI-6 section and the test catalogue are written assuming the recommended resolution; if the user picks differently, WI-6 + its tests are revised before Gate 3.

---

## Prior art / project precedent / rejected alternatives

### Precedent we build on

- **Actor-isolated aggregation over a `ModelContext` snapshot.** `PersistenceActor.recomputeStats` (in `PersistenceActor+Stats.swift`) already does exactly this shape: open `ModelContext(modelContainer)`, fetch `ReadingSession` via `#Predicate`, aggregate, done. `ReadingStats.recompute(from:)` is the in-memory aggregation precedent (clamps negatives, `Int64` accumulation to avoid overflow, idempotent). `ReadingStatsAggregator` reuses both patterns.
- **Value-type records across the actor boundary.** `BookRecord` / `HighlightRecord` / `BookmarkRecord` / `AnnotationRecord` are the established DTO pattern (rule 50 §2: "never return `@Model` from `PersistenceActor`"). New `ReadingSessionRecord` / `ReadingStatsRecord` follow it.
- **Versioned backup-section DTOs.** `BackupSectionDTOs.swift` + `BackupDataCollector` + `BackupDataRestorer` + the `BackupDataCollecting`/`BackupDataRestoring` protocols in `WebDAVProvider.swift` are the exact template. The new `reading-history.json` section is the 9th section, added the same way the `library-manifest.json` 8th section (feature #46) was — including a **protocol default-impl** so existing mock collectors compile unchanged.
- **Optional restore sections.** `WebDAVProvider`'s Phase-B restore loop already treats every section file as optional (`if let entryData = try? ZIPWriter.extractEntry(...)`) and never aborts on a per-section error. A v1 backup with no `reading-history.json` simply skips it — exactly edge case (f).
- **`@Observable @MainActor` VM + injected `PreferenceStoring`.** `LibraryViewModel` persists `sortOrder` via `preferenceStore?.set(_:forKey:)` under key `"library.sortOrder"`. `ReadingDashboardViewModel` mirrors this: key `"stats.dashboardSort"`.
- **`ReaderSheetChrome`.** `SettingsView` already wraps its content in `ReaderSheetChrome(theme:title:trailing:)` with a Done button — the design's `Sheet` component. `ReadingDashboardView` uses the same chrome (design `FullStatsDashboard` is a `Sheet`).
- **`ReadingTimeFormatter`.** Existing pure formatter. `formatReadingTime` appends `" read"` — the dashboard needs a bare-duration variant; add `formatDuration(totalSeconds:)` ("41h 23m" / "38m" / "0m") to the same enum rather than a new formatter.

### Rejected alternatives

- **A denormalized per-day-bucket cache `@Model`.** The row's Risk (a) raises it. Rejected for v1: it adds a SwiftData schema migration (heavy, error-prone) for a read-only view; a single `#Predicate`-filtered fetch over `startedAt` plus in-memory bucketing is `O(n)` over the session count, fast for the realistic ceiling (the row's edge case (e) says "1000+ sessions" — 1000 small structs aggregate in well under a frame). If profiling ever shows a problem, the cache becomes a follow-up feature. Documented in "Risks".
- **Putting aggregation in `PersistenceActor`.** Rejected: `PersistenceActor` is already large and split across 10 `+Feature` files; the row explicitly names a *new* `ReadingStatsAggregator` service. The aggregator does need a `ModelContext`, so it takes a `ModelContainer` (same as `PersistenceActor`) — but the *window-bucketing math* is pure and unit-tested independently of SwiftData.
- **A `@Query` in the View.** Rejected: `@Query` runs on `@MainActor` and couples the View to the SwiftData schema; the row says "actor-isolated" service; aggregation off the main actor keeps a 1000-session sweep from janking the UI.
- **Reusing `kBackupCurrentSchemaVersion` exact-match validation as-is.** Rejected — see "Backward compat"; bumping to 2 with the current exact-match restorer would reject **every existing v1 backup**. The restorer's per-section validation must be loosened first.
- **Hour-of-day / streak / books-finished widgets.** In the design but not the row. Rejected for this feature to keep scope honest; noted as a follow-up.

---

## Work-item sequencing

8 WIs. Each WI = one PR. "Foundational" = DTO/pure-logic/actor with no user-observable behavior (unit + integration tests suffice, no device verify). "Behavioral" = changes app behavior / persistence / backup / UI (Gate-5 slice verify required).

| WI | Title | Tier | PR size | Depends on |
|---|---|---|---|---|
| **WI-1** | `ReadingStatsModels` — window enum, `WindowTotal`, `PerBookStatsRow`, `ReadingDashboardSnapshot`, `ReadingDashboardSort`, `ReadingSessionRecord`, `ReadingStatsRecord`. Pure value types + window-boundary date math (`DateInterval` per window, local-timezone midnight) + sort comparator. | **Foundational** | ~200 LOC + tests | — |
| **WI-2** | `ReadingStatsAggregator` actor — `snapshot(window:sort:now:) async throws -> ReadingDashboardSnapshot`; per-window totals + per-book rows (reading-time / notes / highlights / `lastReadAt`) **derived entirely from `ReadingSession` + `Book` rows in one `ModelContext` pass — never reads `ReadingStats`** (round-2 consistency model). Plus `PersistenceActor+Stats` additions `fetchAllReadingSessions` / `fetchAllReadingStats` (for the WI-5 collector). | **Foundational** | ~240 LOC + tests | WI-1 |
| **WI-3** | `ReadingTimeFormatter.formatDuration(totalSeconds:)` bare-duration variant. Tiny, but TDD'd (boundary cases). | **Foundational** | ~40 LOC + tests | — (parallel-safe with WI-1/2) |
| **WI-4** | `ReadingDashboardViewModel` — `@MainActor @Observable`; active window + sort, calls aggregator, persists sort via `PreferenceStoring` (`"stats.dashboardSort"`). | **Foundational** | ~150 LOC + tests | WI-2, WI-3 |
| **WI-5** | `BackupReadingHistory.swift` DTOs + `kBackupCurrentSchemaVersion` 1→2 + restorer per-section-version decoupling (`kBackupAcceptedSchemaVersions`) + `collectReadingHistory` / **upsert** `restoreReadingHistory` on collector/restorer/`PersistenceActor` + protocol default-impls + `WebDAVProvider` wiring (collect tuple + restore loop). | **Behavioral** (backup format) | ~280 LOC + tests | WI-1 |
| **WI-6** | `ReadingDashboardView` + `StatsTimeWindowBar` + `StatsPerBookTable` SwiftUI surfaces, per the design. Sheet presentation hook in `SettingsView` (profile-card Stats button). **BLOCKED until the user resolves divergences D1–D4** (see "Design-vs-row divergences"); under the recommended resolution, **also depends on feature #67's profile card** for the entry point. | **Behavioral** (UI) | ~280 LOC + tests | WI-4; user D1–D4 decision; **feature #67** (under recommended resolution) |
| **WI-7** | `docs/architecture.md` + `README.md` doc-sync for the aggregator + backup section. (Folds into WI-2 and WI-5's PRs as separate commits per rule 24 — listed separately only for the test catalogue; **not its own PR**.) | n/a (doc) | — | — |
| **WI-8** | Final integration WI — full acceptance pass on the dashboard (all 6 acceptance criteria a–f), backup→wipe→restore round-trip against Docker WebDAV. Flips the row `DONE`→`VERIFIED`. | **Behavioral** (verification) | verification only | WI-1..WI-6 |

**Sequencing note for rule 48 (parallel execution)**: WI-1, WI-3 touch disjoint files and can run in parallel. WI-2 needs WI-1. WI-5 needs WI-1 (the records) but is otherwise disjoint from WI-2/3/4 (different files) — WI-5 can run parallel to WI-2/3/4. WI-6 needs WI-4 + feature #67. One writer per file: only WI-5 and WI-6 touch `WebDAVProvider.swift` / `SettingsView.swift` respectively, and they don't overlap. **WI-5 and WI-2 both touch `PersistenceActor+Stats.swift`** — serialize those two (WI-2 first, then WI-5 rebases) OR put WI-5's persistence additions in a new `PersistenceActor+Backup.swift`-adjacent file. **Resolution**: WI-5's `restoreReadingHistory` persistence method goes in the existing `PersistenceActor+Backup.swift` (it is a backup-restore method, semantically belongs there), and WI-2's read methods go in `PersistenceActor+Stats.swift` — disjoint files, no serialization needed.

---

## Public API sketches (for Gate-2 signature critique)

> Round-1 audit fixes folded in: the aggregator's `snapshot` now takes the active `window`; `BackupReadingSession` carries **every** persisted `ReadingSession` field; the duplicate fingerprint-key field is collapsed; the aggregator resolves the calendar per-call.

```swift
// ReadingStatsModels.swift
enum ReadingStatsWindow: String, CaseIterable, Identifiable, Sendable {
    case today, last7Days, last30Days, last90Days, last180Days, last365Days, allTime
    var id: String { rawValue }
    var label: String { /* "Today" / "7d" / "30d" / "90d" / "180d" / "365d" / "All" */ }
    /// The half-open [start, now) interval for this window, in the user's
    /// current calendar/timezone. `allTime` returns nil (no lower bound).
    /// `today` = local-midnight(now)..<now; the Nd windows = (now - Nd)..<now.
    func dateInterval(now: Date, calendar: Calendar) -> DateInterval?
}

struct WindowTotal: Sendable, Equatable {
    let window: ReadingStatsWindow
    let totalSeconds: Int
    let sessionCount: Int
}

struct PerBookStatsRow: Sendable, Equatable, Identifiable {
    let id: String                 // bookFingerprintKey
    let bookFingerprintKey: String
    let title: String              // book title; "(deleted)" when no Book row exists (D-edge b)
    let isDeleted: Bool            // true when sessions/stats exist but the Book row is gone
    let readingSecondsInWindow: Int
    let notesCount: Int            // 0 for a deleted book — its notes were cascade-deleted (see Edge cases)
    let highlightsCount: Int       // 0 for a deleted book — same reason
    let lastReadAt: Date?
}

enum ReadingDashboardSortField: String, CaseIterable, Sendable {
    case title, readingTime, highlights, notes   // 4 fields — see divergence D3
}
struct ReadingDashboardSort: Sendable, Equatable, Codable {
    var field: ReadingDashboardSortField
    var ascending: Bool
    static let `default` = ReadingDashboardSort(field: .readingTime, ascending: false)
    /// String round-trip for PreferenceStoring ("readingTime:desc").
    var storageString: String { ... }
    init?(storageString: String) { ... }
}

/// One immutable dashboard render. Carries totals for ALL 7 windows (cheap —
/// 7 small structs) so the window-pill tap need not re-hit the actor; the
/// per-book table is computed for the `activeWindow` only (the table is the
/// expensive part — see audit fix F1).
struct ReadingDashboardSnapshot: Sendable, Equatable {
    /// All 7 windows. An ARRAY in canonical `ReadingStatsWindow.allCases`
    /// order (audit fix F1b — a dictionary has nondeterministic iteration and
    /// makes `Equatable` order-insensitive in a way tests shouldn't rely on).
    let windowTotals: [WindowTotal]
    let activeWindow: ReadingStatsWindow
    let perBook: [PerBookStatsRow]            // for activeWindow, sorted per the requested sort
    let lifetimeTotalSeconds: Int
    let trackingSince: Date?
    /// Convenience lookup; total for a window not present → zeroed.
    func total(for window: ReadingStatsWindow) -> WindowTotal { ... }
}

// Returned across the actor boundary — value types, never @Model. Sendable
// because every stored property is a value type (audit fix F8).
struct ReadingSessionRecord: Sendable, Equatable, Codable {
    let sessionId: UUID
    let bookFingerprintKey: String            // == DocumentFingerprint.canonicalKey (single key — fix F2)
    let startedAt: Date
    let endedAt: Date?
    let durationSeconds: Int
    let pagesRead: Int?
    let wordsRead: Int?
    let startLocator: Locator?
    let endLocator: Locator?
    let deviceId: String
    let isRecovered: Bool
}
struct ReadingStatsRecord: Sendable, Equatable, Codable {
    let bookFingerprintKey: String
    let totalReadingSeconds: Int
    let sessionCount: Int
    let lastReadAt: Date?
    let averagePagesPerHour: Double?
    let averageWordsPerMinute: Double?
    let totalPagesRead: Int?
    let totalWordsRead: Int?
    let longestSessionSeconds: Int
}
```

```swift
// ReadingStatsAggregator.swift
actor ReadingStatsAggregator {
    /// `calendarProvider` is a closure, NOT a stored `Calendar` — so a
    /// long-lived aggregator picks up a timezone/DST change on the NEXT
    /// snapshot without being rebuilt (audit fix F5). Default = `{ .current }`.
    init(modelContainer: ModelContainer, calendarProvider: @Sendable @escaping () -> Calendar = { .current })

    /// Produces one consistent dashboard render. `window` selects which
    /// window the per-book table is computed for (audit fix F1). `now` is
    /// injectable for deterministic tests.
    ///
    /// **Consistency model (audit fixes F8 + round-2 Medium)**: the snapshot
    /// is derived ENTIRELY from `ReadingSession` rows + `Book` rows in ONE
    /// `ModelContext` pass. It does **NOT read `ReadingStats` at all** —
    /// every displayed number, including `lifetimeTotalSeconds`, the per-book
    /// `lastReadAt`, and `trackingSince`, is computed from the session rows
    /// in that same pass:
    ///   - per-window `totalSeconds` / per-book `readingSecondsInWindow` =
    ///     sum of `ReadingSession.durationSeconds` for sessions whose
    ///     `startedAt` falls in the window;
    ///   - `lastReadAt` (per book + the dashboard's notion) = `max` of the
    ///     session `endedAt` (falling back to `startedAt`);
    ///   - `lifetimeTotalSeconds` = sum over all sessions;
    ///   - `trackingSince` = `min` `startedAt` over all sessions.
    /// `ReadingStats` is a *derived cache* maintained by `recomputeStats` for
    /// the Library list's sort; the dashboard recomputes the same facts from
    /// the source rows, so it can never show a session total that disagrees
    /// with a stale `ReadingStats` row. This also closes the torn-read window
    /// the round-2 audit flagged: `ReadingSessionTracker` writes the session
    /// row first and `recomputeStats` runs later — but the aggregator never
    /// looks at `ReadingStats`, so a snapshot taken between those two commits
    /// sees a coherent session-only view (either the session is fully there
    /// or it is not; there is no second table to be out of step with).
    func snapshot(
        window: ReadingStatsWindow,
        sort: ReadingDashboardSort,
        now: Date
    ) async throws -> ReadingDashboardSnapshot
}
```

```swift
// PersistenceActor+Stats.swift (WI-2 — read side)
// Used by the WI-5 backup COLLECTOR. The aggregator does NOT consume these —
// it owns its own ModelContainer + ModelContext pass (consistency model
// above). These exist so `collectReadingHistory` has a value-typed read of
// the two tables without the collector touching `@Model` rows directly.
extension PersistenceActor {
    func fetchAllReadingSessions() async throws -> [ReadingSessionRecord]
    func fetchAllReadingStats()    async throws -> [ReadingStatsRecord]
}
// PersistenceActor+Backup.swift (WI-5 — restore side, lives with the other restore methods)
extension PersistenceActor {
    /// UPSERT restore (audit fix F6 + round-2 High).
    ///
    /// **Why NOT call `recomputeStats`** (round-2 High): the existing
    /// `recomputeStats` force-sets `lastReadAt = Date()` (its "Bug #45 v5"
    /// line — correct for the reader-close caller, wrong for restore). Calling
    /// it from restore would rewrite every restored `ReadingStats.lastReadAt`
    /// to restore-time, violating criterion (f) "preserves `ReadingStats`
    /// exactly". So restore does NOT recompute — it writes the backed-up
    /// `ReadingStats` fields verbatim.
    ///
    /// Algorithm:
    ///  1. **Sessions** — prefetch existing `ReadingSession` rows whose
    ///     `sessionId` is in the envelope; index by `sessionId`. For each
    ///     envelope session: if a row exists, update its mutable fields in
    ///     place (via the model's `update*` mutators — `didSet` is unreliable
    ///     on @Model); else insert a new `ReadingSession`. `sessionId` is
    ///     `@Attribute(.unique)` — prefetch-and-update is exactly how the
    ///     existing annotation restore avoids the unique-constraint violation.
    ///  2. **Stats** — same prefetch/upsert keyed by `bookFingerprintKey`
    ///     (also `@Attribute(.unique)`), writing the backed-up scalar fields
    ///     **verbatim** (`totalReadingSeconds`, `sessionCount`, `lastReadAt`,
    ///     averages, totals, `longestSessionSeconds`). No recompute.
    ///  3. **Conflict policy** — backup value WINS for both tables (a restore
    ///     is an explicit "make this device match the backup" act). Existing
    ///     local rows not mentioned in the backup are left untouched (additive
    ///     merge, like every other restore section).
    ///  4. One `context.save()` at the end.
    ///
    /// Consistency note: because the dashboard aggregator derives its totals
    /// from `ReadingSession` rows (NOT `ReadingStats`), the verbatim-restored
    /// `ReadingStats` only feeds the Library list's sort. If a backup's
    /// `ReadingStats` were ever internally inconsistent with its own sessions,
    /// the dashboard would still be correct (it recomputes from sessions); the
    /// Library sort would reflect the backed-up cache until the next natural
    /// `recomputeStats` on reader-close. This is acceptable — exact round-trip
    /// (criterion f) beats eager self-healing, and the next read corrects it.
    func restoreReadingHistory(_ envelope: BackupReadingHistoryEnvelope) async throws
}
```

```swift
// BackupReadingHistory.swift (WI-5)
// Audit fix F2: BackupReadingSession now mirrors EVERY persisted ReadingSession
// field, so criterion (f) "preserves ReadingSession exactly" holds. A single
// `bookFingerprintKey` (which IS the canonical key — ReadingSession derives
// `bookFingerprintKey` from `DocumentFingerprint.canonicalKey`); the
// DocumentFingerprint is reconstructed on restore via `init(canonicalKey:)`,
// exactly as BackupLibraryEntry does. No duplicate key field.
struct BackupReadingHistoryEnvelope: Codable, Sendable, Equatable, BackupVersionedEnvelope {
    let schemaVersion: Int
    let sessions: [BackupReadingSession]
    let stats: [BackupReadingStats]
}
struct BackupReadingSession: Codable, Sendable, Equatable {
    let sessionId: UUID
    let bookFingerprintKey: String   // == DocumentFingerprint.canonicalKey
    let startedAt: Date
    let endedAt: Date?
    let durationSeconds: Int
    let pagesRead: Int?
    let wordsRead: Int?
    let startLocatorJSON: String?    // Locator is Codable — round-trips as a JSON string,
    let endLocatorJSON: String?      //   matching how BackupHighlight stores `locatorJSON`
    let deviceId: String
    let isRecovered: Bool
}
struct BackupReadingStats: Codable, Sendable, Equatable {
    let bookFingerprintKey: String
    let totalReadingSeconds: Int
    let sessionCount: Int
    let lastReadAt: Date?
    let averagePagesPerHour: Double?
    let averageWordsPerMinute: Double?
    let totalPagesRead: Int?
    let totalWordsRead: Int?
    let longestSessionSeconds: Int
}
```

> **Locator-in-DTO note (F2 detail)**: `ReadingSession.startLocator/endLocator` are `Locator?`. The existing backup DTOs (`BackupHighlight`, `BackupPosition`) store a `Locator` as a JSON-string field (`locatorJSON`) rather than nesting the `Locator` struct, because `BackupDataCollector` already has a `locatorJSON(_:encoder:)` helper and the round-trip is proven. `BackupReadingSession` follows that precedent — `startLocatorJSON`/`endLocatorJSON`. A `nil` locator → `nil` string. On restore, a malformed locator string degrades to `nil` (the session still restores; only its locators are dropped) rather than failing the whole section.

---

## Test catalogue

| Test file | Covers |
|---|---|
| `ReadingStatsModelsTests.swift` | `dateInterval(now:calendar:)` for each window: today = local-midnight→now; 7/30/90/180/365d = `now - Nd`→now; `allTime` = nil. **Timezone**: same `now` in two `Calendar`s with different `timeZone` yields different `today` lower bounds (edge case g). **DST boundary**: a `today` interval spanning a spring-forward day is still anchored at local midnight. Sort comparator: each `ReadingDashboardSortField`, asc + desc, with ties broken by title; `(deleted)` rows sort stably. `ReadingDashboardSort` `storageString` round-trip, malformed string → nil. |
| `ReadingStatsAggregatorTests.swift` | In-memory `ModelContainer`. **Empty DB** → all-zero snapshot, empty `perBook`. **Single session in today** → counts in today/7d/30d/…/all. **Session at exact window boundary** — `startedAt` exactly at `now-7d`: counts toward 7d (half-open `[start, now)`). **Session crossing midnight** — `startedAt` 23:50 yesterday, `endedAt` 00:30 today: counts to *yesterday's* bucket → in 7d not today (edge case c). **Book deleted, sessions remain** (a `ReadingSession` whose `bookFingerprintKey` has no matching `Book` row — the post-restore scenario, see Edge cases) → `PerBookStatsRow` with `isDeleted=true`, title `(deleted)`, **`notesCount==0`, `highlightsCount==0`** (the book's highlights/notes were cascade-deleted with it — they cannot be recovered, audit fix F7). **Zero-session book that has a `ReadingStats` row** → row present with `0m` (edge case a). **Per-window table**: `snapshot(window: .today)` vs `snapshot(window: .last30Days)` over the same DB → different `perBook` reading-seconds per row (audit fix F1 — the `window:` param is exercised). **1000 sessions** → completes; assert correctness not just non-crash (edge case e). **Negative `durationSeconds`** (corrupt) → clamped to 0. **`endedAt` < `startedAt`** → still bucketed by `startedAt`. **notes/highlights counts for a LIVE book** match `fetchAnnotations`/`fetchHighlights` for that book. **Snapshot consistency** (audit fix F8): seed sessions, take a snapshot, assert the per-book reading-seconds + window totals are mutually consistent (the per-book sum for `allTime` equals the `allTime` `WindowTotal.totalSeconds`) — proves the single-`ModelContext`-pass invariant. |
| `ReadingDashboardViewModelTests.swift` | Initial load → snapshot populated. Window switch → VM re-queries, `activeWindow` updates. Sort change → `perBook` reorders + `PreferenceStoring` written with the right key/value. Construction with a pre-seeded `MockPreferenceStore` → sort restored (criterion d). Aggregator throws → VM exposes an error state, does not crash. |
| `ReadingTimeFormatterTests.swift` (extend existing) | `formatDuration`: 0→"0m", 59→"0m" (sub-minute floors), 60→"1m", 3599→"59m", 3600→"1h 0m", 5400→"1h 30m", 90000→"25h 0m" (>24h is fine, no day rollup). Negative → "0m". |
| `BackupReadingHistoryTests.swift` | **Collector**: seed N sessions + stats → `collectReadingHistory()` emits a `BackupReadingHistoryEnvelope` with `schemaVersion == 2`, all rows present, dates ISO-8601, every `ReadingSession` field (incl. locators + `deviceId` + `isRecovered`) round-trips (F2). **Restorer round-trip**: collect → wipe → `restoreReadingHistory` → `fetchAllReadingSessions` / `fetchAllReadingStats` byte-equal to the original (criterion f). **`ReadingStats` `lastReadAt` verbatim** (round-2 High): seed a `ReadingStats` with a fixed past `lastReadAt`, back up, wipe, restore → restored `lastReadAt` equals the seeded value (proves restore does NOT call `recomputeStats`, which would stamp `Date()`). **Idempotency**: restore the same envelope twice → no duplicate sessions/stats (`@Attribute(.unique)` — assert dedup not crash), and `lastReadAt` still byte-equal after the second restore. **Missing section**: a ZIP with no `reading-history.json` restores cleanly, leaves local sessions intact (edge case f). **Schema v1 archive**: an envelope with `schemaVersion: 1` for an *unrelated* section still restores after the bump — the `kBackupAcceptedSchemaVersions` decoupling test. **Synthetic v3**: a `schemaVersion: 3` section still throws `unsupportedSchemaVersion` (R7). **Corrupt JSON**: malformed `reading-history.json` → that section fails, other sections still restore (`WebDAVProvider` per-section isolation). **Partial restore**: a session whose `bookFingerprintKey` matches no local Book still restores (history is book-independent — assert it lands). |
| `WebDAVProviderTests.swift` (extend existing if present) | The collect tuple includes `reading-history.json`; the restore loop includes it; a collector that does NOT implement `collectReadingHistory` (uses the default-impl) still produces a valid empty section — protocol-default-impl compile + behavior test. |

Reader-bridge / pixel tests: not applicable (read-only dashboard, no WebView). `ReadingDashboardView` SwiftUI tests assert observable state + the rendered sort/window via accessibility identifiers, not pixels (rule 10 §"SwiftUI views" — test behavior).

---

## Edge cases (row a–g — resolved)

The feature #58 row enumerates edge cases a–g. The row leaves (b) explicitly undecided ("`(deleted)` placeholder title or omit — decide in plan"). All resolutions below; each has a test in the catalogue.

| Row | Case | Resolution |
|---|---|---|
| (a) | Zero sessions for a book that still has a `ReadingStats` row | Row is **shown** with `0m`. `ReadingStats` rows exist independently of sessions (a quick <5s open discards the session but `recomputeStats` still ran). |
| (b) | **Book deleted but historical sessions exist** — DECIDED | **Show the row** with title `(deleted)` and `isDeleted=true`. **`notesCount` and `highlightsCount` are 0** — `Highlight`/`AnnotationNote` have a SwiftData `book` relationship and are cascade-deleted with the `Book` (`fetchAnnotations`/`fetchHighlights` route through the `Book` row and return `[]` when it is gone — Codex F7). Reading-time and `lastReadAt` still display from the surviving `ReadingSession`/`ReadingStats` rows. **When does this even happen?** The normal `deleteBook` path *also* explicitly deletes sessions+stats, so a user-deleted book leaves nothing. The real trigger is a **restored backup** that brought `reading-history.json` sessions for a book whose blob was not materialized — sessions exist, the `Book` does not. Showing `(deleted)` is honest; omitting would silently drop restored history. |
| (c) | Session crosses midnight / week boundary | Counts toward the bucket containing `startedAt` (the row's stated rule). A 23:50→00:30 session belongs to the *starting* day. |
| (d) | Clock skew (device-time changes) | Accept whatever `startedAt` recorded — no correction. `ReadingSession` already clamps `endedAt < startedAt` at the model level. |
| (e) | Very long history (1000+ sessions) | One `#Predicate` fetch + `O(n)` in-memory bucketing. Tested at 1000 sessions for correctness + completion. |
| (f) | WebDAV restore from an older backup with **no** `reading-history.json` | The section is optional — `WebDAVProvider`'s `try? ZIPWriter.extractEntry` returns nil, the restore loop skips it, the aggregator falls back to whatever local `ReadingSession` rows exist. No error. |
| (g) | Timezone — bucket boundaries in the user's current timezone | `today` = local-midnight..<now, resolved per-`snapshot` via the calendar provider (audit fix F5). Travel/DST → next render rebuckets. |

---

## Risks + mitigations

| # | Risk | Mitigation |
|---|---|---|
| R1 | **Aggregator performance** over large session histories (row Risk a). | Single `#Predicate` fetch + in-memory `O(n)` bucketing; `ReadingStats.recompute` already proves this scales. Test with 1000 sessions. If real-world profiling later shows jank, a per-day-bucket cache `@Model` becomes a follow-up feature — explicitly NOT in v1 (avoids a schema migration). |
| R2 | **Backup payload bloat** — `ReadingSession` rows accumulate (row Risk b). | v1 backs up *all* sessions (correctness over size; the row's acceptance criterion f demands an exact round-trip). JSON is `.prettyPrinted` like the other sections; the ZIP compresses it. Window-based truncation / compression is a documented follow-up, not v1 — truncating would break criterion f. |
| R3 | **`kBackupCurrentSchemaVersion` bump breaks every v1 backup.** The restorer's `decodeAndValidate` requires `envelope.schemaVersion == kBackupCurrentSchemaVersion` exactly. Bumping to 2 makes all 7 pre-existing v1 sections in an old archive throw `unsupportedSchemaVersion`. | **See Backward compat — this is the central correctness risk.** WI-5 changes the restorer to validate per-section against a named accepted set `kBackupAcceptedSchemaVersions = {1, 2}`, not the single current constant. |
| R4 | **Timezone / clock skew** — buckets recomputed when the user travels (row Risk c). | Correct by design. **Audit fix F5**: the aggregator holds a `@Sendable () -> Calendar` *provider*, not a stored `Calendar`, and `dateInterval(now:calendar:)` resolves it per `snapshot` call — so a long-lived aggregator picks up a timezone/DST change on the next render. Sessions store `startedAt` as an absolute `Date`; only the *bucket boundaries* move. Tested with two providers yielding different time zones. The row says "document in UI" — the dashboard's window labels are relative ("7d") so no calendar-date claim is shown; no extra UI copy needed. |
| R5 | **`DocumentFingerprint` round-trip in the backup DTO.** `ReadingSession.bookFingerprint` is a `DocumentFingerprint` value; `ReadingStats` too. The backup DTO must serialize it. | `DocumentFingerprint` exposes `canonicalKey` (string) and an `init(canonicalKey:)` — the backup DTO stores the single canonical string (`bookFingerprintKey`) and reconstructs the `DocumentFingerprint` on restore, exactly as `BackupLibraryEntry.fingerprintKey` does. Verified in `ReadingSession.swift` (`updateBookFingerprint` derives `bookFingerprintKey` from `canonicalKey`). **Audit fix F2**: one key field only — no `bookFingerprintCanonicalKey` duplicate. |
| R6 | **Feature #67 dependency** for the entry point (under the recommended D1 resolution). If #67 slips, the dashboard has no user-facing entry. | WI-1..WI-5 are #67-independent and ship value (aggregator + backup) regardless. WI-6's *view* is buildable; only the *Settings hook* needs #67. Gate-5 verification of WI-6 uses a DEBUG `vreader-debug://` route so the dashboard is verifiable before #67 lands. The row's `DONE`→`VERIFIED` flip (WI-8) waits for the real entry. The user may also choose D1-option-B (file `needs-design` for a Library entry) — then this risk is moot but WI-6 blocks on the new design. |
| R7 | **Restorer schema-decoupling regression.** Loosening `decodeAndValidate` could let a genuinely-too-new (v3) archive through. | The accepted set is explicit (`{1, 2}`), not `<= current`. A v3 section still throws. Tested with a synthetic v3 envelope. |
| R8 | **`ReadingStats` duplicate rows.** `fetchAllLibraryBooks` already guards against duplicate `ReadingStats` ("data integrity issue, keep first"). The aggregator + the backup collector must do the same. | Aggregator + collector dedupe by `bookFingerprintKey`, first-wins, mirroring `PersistenceActor+Library.swift`. Tested. |
| R9 | **Idempotent restore — `@Attribute(.unique)` collision + `lastReadAt` rewrite** (audit fix F6 + round-2 High). `ReadingSession.sessionId` and `ReadingStats.bookFingerprintKey` are both `@Attribute(.unique)`; a naive `context.insert` of an already-present row throws. Separately, the existing `recomputeStats` force-sets `lastReadAt = Date()` — calling it from restore would rewrite restored `ReadingStats`, violating criterion (f). | `restoreReadingHistory` is an **upsert** (full algorithm in the API sketch): prefetch by the unique key, update existing rows in place via the model's `update*` mutators, insert only when absent — exactly how the existing annotation restore avoids the violation. `ReadingStats` is written **verbatim from the backup** — restore does **NOT** call `recomputeStats`, so backed-up `lastReadAt` survives intact. Tested: restore the same envelope twice → no duplicates, no throw, `lastReadAt` byte-equal to the backup. |
| R10 | **Torn read — aggregator vs concurrent `ReadingSessionTracker` write** (audit fix F8 + round-2 Medium). `ReadingSessionTracker` writes a `ReadingSession` row, and `recomputeStats` runs *later* as a separate async step — so for a window between those two commits, `ReadingSession` is fresh but `ReadingStats` is stale. | The aggregator **never reads `ReadingStats`**. Every displayed number — per-window totals, per-book reading-seconds, per-book `lastReadAt`, `lifetimeTotalSeconds`, `trackingSince` — is derived from `ReadingSession` rows (+ `Book` rows for titles) in **one `ModelContext` pass**. There is no second table to be out of step with: a snapshot taken between the session-write and the `recomputeStats` commit still sees a coherent session-only view (the session is either fully present or absent). `ReadingStats` remains a derived cache for the *Library list sort* only. Tested by the "snapshot consistency" case (per-book `allTime` sum == `allTime` `WindowTotal`). |

---

## Backward compat

**The single most important compatibility concern.** Two independent versioning axes:

1. **SwiftData schema** (`VReaderMigrationPlan` / `SchemaV*`) — **untouched**. No new `@Model`, no new field. An old app binary and a new one read the same `ReadingSession` / `ReadingStats` store. No migration.

2. **Backup JSON envelope schema** (`kBackupCurrentSchemaVersion`, currently `1`) — **bumped to `2`** so that new backups' `reading-history.json` (and the existing 7 sections re-emitted at v2) are tagged correctly.

**The trap (row Risk + R3).** `BackupDataRestorer.decodeAndValidate` currently does:
```swift
guard envelope.schemaVersion == kBackupCurrentSchemaVersion else { throw .unsupportedSchemaVersion(...) }
```
An exact-equality check. If we bump the constant to 2 and change nothing else, **every section of every pre-existing v1 backup is rejected on restore** — a catastrophic regression for users restoring an old archive.

**The fix (WI-5).** Decouple "what this client emits" from "what this client accepts":
- `kBackupCurrentSchemaVersion = 2` — what the collector emits.
- Add `kBackupAcceptedSchemaVersions: Set<Int> = [1, 2]` — what the restorer accepts.
- `decodeAndValidate` validates `kBackupAcceptedSchemaVersions.contains(envelope.schemaVersion)`. A genuinely-newer archive (v3) still throws `unsupportedSchemaVersion`.
- The v1→v2 envelope shapes for the **7 pre-existing sections are byte-identical** (only the `schemaVersion` integer differs) — there is no field migration; a v1 `BackupAnnotationsEnvelope` decodes correctly under the same `Codable` struct. So accepting v1 is sound: no per-section migration code is needed for the existing 7 sections, only the accepted-set widening.
- `reading-history.json` is **new in v2**. A v1 archive simply lacks the entry → `WebDAVProvider`'s Phase-B `try? ZIPWriter.extractEntry` returns nil → the section is skipped → the aggregator falls back to whatever local `ReadingSession` rows exist (edge case f). No error.

**`library-manifest.json` note.** That section already uses a *literal* `schemaVersion: 1` (not the constant) precisely so a constant bump doesn't disturb it. WI-5 leaves it at `1`; its restorer path (`BackupLibraryManifestEnvelope`) is decoded with a tolerant `try?` in `WebDAVProvider`, unaffected.

**Forward compat.** A v1 (old) app restoring a v2 backup: the old app's restorer has the old exact-match `== 1` check → it rejects every v2 section. This is **pre-existing behavior** for any schema bump and not made worse by this feature; it is the reason the bump is conservative (one bump, accepted-set widened on the *new* client). The old app simply cannot consume new backups — acceptable and unavoidable without retrofitting old binaries. Documented here so Gate 2 sees it was considered.

---

## Acceptance criteria mapping (row → verification)

| Row criterion | Verified by | WI |
|---|---|---|
| (a) dashboard surface reachable | Gate-5: under the recommended D1 resolution, Settings → profile card → Stats → dashboard sheet (or the DEBUG `vreader-debug://` route if #67 has not landed). **The row's literal "from Library" wording is divergence D1 — see "Design-vs-row divergences"; the user resolves where the entry lives before WI-6.** | WI-6 / WI-8 |
| (b) all 7 windows render correct totals on a seeded fixture | `ReadingStatsAggregatorTests` + Gate-5 DebugBridge seed | WI-2 / WI-8 |
| (c) per-book table shows time/notes/highlights, sortable on all 4 columns | `ReadingDashboardViewModelTests` + Gate-5 tap-through (4 columns / 4 sort fields — divergence D3) | WI-4 / WI-6 / WI-8 |
| (d) sort selection persists across launches | `ReadingDashboardViewModelTests` (pre-seeded `MockPreferenceStore`) + Gate-5 relaunch | WI-4 / WI-8 |
| (e) `BackupDataCollector` emits `reading-history.json`; restore reproduces totals | `BackupReadingHistoryTests` + Gate-5 Docker-WebDAV round-trip | WI-5 / WI-8 |
| (f) backup → wipe → restore preserves `ReadingSession` + `ReadingStats` exactly | `BackupReadingHistoryTests` round-trip (DTO carries every field — F2) + Gate-5 | WI-5 / WI-8 |

---

## Gate 2 — Independent Plan Audit

**Auditor**: Codex MCP (`mcp__plugin_codex-toolkit_codex__codex`), read-only sandbox, independent process — satisfies rule 47 / rule 48 author/auditor separation. Thread `019e4029-2bc3-7673-804c-3516c58ab595`.

### Round 1 — findings (3 High, 5 Medium, 0 Critical)

Model-assumption check: **clean** — every named SwiftData field, type, protocol, default-impl extension, file path, and the design components verified against disk. `ReadingTimeFormatter.formatReadingTime` confirmed to append `" read"`.

| # | Sev | Finding | Fix label |
|---|---|---|---|
| 1 | High | `snapshot(sort:now:)` had no active-`window` parameter — could not produce the per-book table for a specific window. | **F1** |
| 2 | High | `BackupReadingSession` omitted `startLocator`/`endLocator`/`deviceId`/`isRecovered` (criterion f "exactly" violated) and carried a duplicate `bookFingerprintKey`+`bookFingerprintCanonicalKey`. | **F2** |
| 3 | High | The plan rewrote the contract ("reachable from Library" → "from Settings") and called it a "reconciliation" — that is a contract change, not an interpretation. | **F3** |
| 4 | Medium | Two further scope cuts (5→4 sort fields, "7 cards" → 1 hero) presented as reconciliations rather than staged as decisions. | **F3** |
| 5 | Medium | The aggregator captured `Calendar` at `init` — a long-lived actor would not rebucket on a timezone/DST change. | **F5** |
| 6 | Medium | `restoreReadingHistory` upsert algorithm unspecified — `@Attribute(.unique)` collision risk on re-run. | **F6** |
| 7 | Medium | Deleted-book edge case underspecified — the plan said counts "match `fetchAnnotations`/`fetchHighlights`", but those return `[]` once the `Book` row is gone. | **F7** |
| 8 | Medium | Snapshot consistency not pinned — a multi-fetch aggregator could observe torn state vs a concurrent `ReadingSessionTracker` write. | **F8** |

### Audit fixes applied (plan v2)

- **F1** — `ReadingStatsAggregator.snapshot` now takes `window: ReadingStatsWindow`; `ReadingDashboardSnapshot` documents that `perBook` is for `activeWindow`. WI-2 row + a per-window aggregator test added.
- **F1b** — `windowTotals` changed from `[ReadingStatsWindow: WindowTotal]` dictionary to a deterministically-ordered `[WindowTotal]` array (a dictionary has nondeterministic iteration and an order-insensitive `Equatable`); a `total(for:)` convenience lookup added.
- **F2** — `BackupReadingSession` now mirrors **every** persisted `ReadingSession` field (locators as JSON strings per the `BackupHighlight.locatorJSON` precedent); the duplicate key field is removed (one `bookFingerprintKey`, which *is* the canonical key). `ReadingSessionRecord`/`ReadingStatsRecord` fully field-listed.
- **F3** — "Design-vs-row reconciliation" renamed to "**Design-vs-row divergences — REQUIRE USER DECISION before Gate 3**"; all four divergences (D1 entry point, D2 windows, D3 sort fields, D4 cards-vs-hero) restaged as open decisions with a plan *recommendation* each, explicitly noting the plan cannot rewrite the contract. WI-6 marked **BLOCKED until the user resolves D1–D4**. The acceptance-criteria mapping for (a) now points at D1.
- **F5** — aggregator holds a `@Sendable () -> Calendar` provider, not a stored `Calendar`; resolved per `snapshot` call. R4 updated; a two-timezone test added.
- **F6** — `restoreReadingHistory` API sketch now spells out the full upsert algorithm (prefetch by unique key, update-in-place via the model's `update*` mutators, insert-if-absent, `recomputeStats` per affected book, single `save()`). New risk R9 + an idempotent-restore test.
- **F7** — Edge case (b) **decided**: deleted-book rows show title `(deleted)` with `notesCount==0`/`highlightsCount==0` (highlights/notes cascade-delete with the `Book`); reading-time still shows from the surviving sessions. New dedicated "Edge cases (row a–g — resolved)" section maps all seven. The aggregator test for the deleted-book case updated to assert 0 counts.
- **F8** — `snapshot` documented to compute the entire render from **one `ModelContext` pass**; the per-window table sums `ReadingSession.durationSeconds` directly rather than trusting `ReadingStats` aggregates, so a stale stats row cannot desync the table. New risk R10 + a "snapshot consistency" test.

### Round 2 — re-audit (same thread)

Codex confirmed **all 8 round-1 fixes RESOLVED** (F1–F8 each cited against the v2 text). It then raised **2 new findings** created by the F6/F8 fixes:

| # | Sev | Finding | Fix label |
|---|---|---|---|
| 9 | High | F6's restore "calls `recomputeStats` per book" conflicts with criterion (f) "preserves `ReadingStats` exactly" — `recomputeStats` force-sets `lastReadAt = Date()` (its Bug-#45-v5 line), so restore would rewrite restored stats to restore-time. | **F9** |
| 10 | Medium | F8's "one `ModelContext` pass" still permits a stale-`ReadingStats` read: the session row is committed *before* `recomputeStats` runs, and the plan still said stats feed `lastReadAt`/lifetime — a snapshot between the two commits mixes fresh sessions with old stats metadata. | **F10** |

### Audit fixes applied (plan v3)

- **F9** — `restoreReadingHistory` now writes `ReadingStats` **verbatim from the backup** and explicitly does **NOT** call `recomputeStats`; the API sketch documents why (the `lastReadAt = Date()` override). Criterion (f) "exactly" now holds. R9 updated; a new `BackupReadingHistoryTests` case asserts restored `lastReadAt` equals the seeded backup value (and survives a double-restore).
- **F10** — root-caused the torn-read to "the aggregator reads two tables that update at different times". Fix: the aggregator **no longer reads `ReadingStats` at all** — every dashboard number (per-window totals, per-book reading-seconds, per-book `lastReadAt`, `lifetimeTotalSeconds`, `trackingSince`) is derived from `ReadingSession` + `Book` rows in one pass. `ReadingStats` is left as a derived cache for the *Library list sort only*. With one source table there is no second table to desync against — the torn-read window is structurally closed, not merely narrowed. The aggregator API doc + WI-2 row + R10 updated; the "snapshot consistency" test asserts the per-book `allTime` sum equals the `allTime` `WindowTotal`.

### Verdict

**Gate 2 PASSED at plan v3.** Two Codex rounds (rule-47 max is 3). Round 1: 0 Critical / 3 High / 5 Medium — all fixed in v2. Round 2: all 8 confirmed resolved; 2 new (1 High / 1 Medium) created by the fixes — both fixed in v3. **Zero open Critical / High / Medium.** No Low findings were left open (round 2's Low entries were the per-finding RESOLVED confirmations, not defects).

**Known limitations carried forward (accepted, not defects):**
- **Divergences D1–D4** (entry point / windows / 4-vs-5 sort fields / cards-vs-hero) are *open user decisions*, not audit findings. WI-1..WI-5 proceed regardless; **WI-6 is BLOCKED at Gate 3 until the user resolves D1–D4**. The plan records a recommendation for each (accept the committed design + amend the row's UI prose). This is a deliberate Gate-1 escalation per rule 47 ("if the row and design conflict, the user decides"), not an unresolved audit gap.
- A v1 (old) app cannot restore a v2 backup — pre-existing behavior of any schema bump, documented under "Backward compat / Forward compat".
- Per-day-bucket cache table deferred (R1) — a follow-up feature only if profiling shows the `O(n)` sweep janks.
