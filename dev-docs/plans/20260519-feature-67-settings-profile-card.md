# Feature #67 — Settings profile-header card + grouped-row restyle

- **Tracker row**: `docs/features.md` #67 — "Settings profile-header card + Stats entry point" (status `TODO`, GH #825).
- **Design source**: `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx` (`SettingsSheet` / `Row`); identity-model resolution in `dev-docs/designs/vreader-fidelity-v1/project/vreader-profile-stats.jsx` + `dev-docs/designs/vreader-fidelity-v1/project/design-notes/needs-design-issues.md` §#862.
- **Lineage**: v2 follow-on of feature #60 (visual-identity v2, VERIFIED). `SettingsView.swift` was re-skinned in feature #60 WI-10; this feature completes the design's `SettingsSheet` by adding the two pieces WI-10 deliberately deferred (profile-header card, 30pt colored-icon rows).
- **Workflow**: rule 47, six gates. This document is Gate 1.

---

## Revision history

| Rev | Date | Change |
|---|---|---|
| v1 | 2026-05-19 | Initial plan drafted (Gate 1). |
| v2 | 2026-05-19 | Gate-2 round 1 — Codex audit: 1 High + 6 Medium + 4 Low. All fixed (see "Audit fixes applied" §). |
| v3 | 2026-05-19 | Gate-2 round 2 — Codex re-audit: round-1 fixes all verified real; 5 Medium + 2 Low (all from a transient WI-numbering inconsistency). All fixed — consolidated to a final **5-WI** sequence, normalized every cross-section WI reference, removed the WI-5 scope fork. |

---

## Problem

`SettingsView.swift` was re-skinned to feature-#60 v2 chrome (`ReaderSheetChrome` + `.paper` theme + the four design section groups), but the re-skin stopped short of the design's `SettingsSheet` in two visible ways:

1. **No profile-header card.** The design opens the Settings sheet with a 14pt-radius card: a 48pt avatar disc, an identity line, and a "N books · Nh read this month" subline, with a pill-shaped **Stats** button on the trailing edge. The shipped sheet jumps straight into the section groups.
2. **Native rows, not the design's colored-icon rows.** The shipped sheet uses SwiftUI `Form` `NavigationLink`s with default `Label` + `systemImage` chrome. The design specifies a custom `Row`: a 30pt rounded-square icon tile filled with a per-row brand color, a 15pt title, an optional 11pt detail subline, an optional trailing value string, and a chevron.

The user need: the Settings sheet should add the design's profile-header card and the colored-icon row treatment to **every** group, and give the user a one-tap path into their reading statistics. **Scope note (Gate-2 fix, round 1 Medium #3)**: the design's "AI" group is owned by the feature-#50 `AISettingsSection` composite; this feature restyles the three groups `SettingsView` declares directly (Cloud & Sync / Reading / About) in WI-4 and the AI group in WI-5 — so the whole `SettingsSheet` matches the design when the feature completes. The AI group is a distinct WI only because it touches a different file (`AISettingsSection.swift`); it is not out of scope.

**Identity-model constraint (resolved).** The committed design (`vreader-panels.jsx`) shows a user *name* ("lllyys") and a single-initial gradient avatar. The production app has **no user account and no user-name source** — only OPDS / WebDAV credentials, which are not an identity. `needs-design` #862 was filed to resolve this. The #862 issue-canvas handoff (2026-05-18) **resolved it**: the canonical model is **"Library-as-identity" (Option A)** — the card represents the LIBRARY, not a person. The header reads **"Your library"** in serif italic; the avatar slot becomes a **three-book-spine glyph** (`ProfileCardLibrary` in `vreader-profile-stats.jsx`). No name, no account, no synthetic handle. Options B (user-set display name) and C (stats-as-hero) were explicitly rejected for v1; B is "defer to a feature ask". **This plan implements Option A only.**

**Stats destination (cross-feature).** The design's **Stats** button opens the reading-stats dashboard. That dashboard is **feature #58** ("Reading-time + activity dashboard", GH #665, status `TODO`), being planned in parallel. This plan scopes **only the entry-point Stats button in `SettingsView`** plus a clean hand-off mechanism; the dashboard surface itself is feature #58's deliverable and is explicitly OUT of scope here (see "Files OUT of scope" and "Cross-feature dependency").

---

## Surface area

### Files this feature CREATES

| File | Purpose | Key types / signatures |
|---|---|---|
| `vreader/Views/Settings/SettingsProfileCard.swift` | The design's profile-header card — `ProfileCardLibrary`. A self-contained SwiftUI `View`. | `struct SettingsProfileCard: View` — init `(theme: ReaderThemeV2, bookCount: Int, monthReadingSeconds: Int, onOpenStats: () -> Void)`. Renders the 48pt three-book-spine glyph tile, the "Your library" serif-italic header, the "N books · Nh read this month" subline, and the trailing pill **Stats** `Button`. Pure presentation — no data fetch inside. |
| `vreader/Views/Settings/SettingsRowStyle.swift` | The design's `Row` — a 30pt colored-icon settings row, factored as a reusable `View` so each `SettingsView` row uses one shape. | `struct SettingsIconRow<Trailing: View>: View` — init `(theme:icon:iconBackground:title:detail:trailingValue:showsChevron:isDestructive:trailing:)`. `icon` is an `Image`; `iconBackground` is a `Color`. Renders the 30pt rounded tile + 15pt title + optional 11pt `detail` + optional `trailingValue` text + optional chevron. A non-generic `extension where Trailing == EmptyView` convenience init covers the common "value string only" case. |
| `vreader/Models/SettingsRowPalette.swift` | Foundation-only enum/struct pinning each design row's brand color + SF Symbol, so the colors live in one home (mirrors `SheetSectionContract` / `LibraryCardTokens` precedent). | `enum SettingsRowPalette` with one `static let` of type `SettingsRowSpec` **per row this feature actually renders**. WI-2 creates it with the six core-group rows (`webDAVBackup`, `bookSources`, `replacementRules`, `httpTTS`, `helpFeedback`, `version`); WI-5 adds the AI-group rows (`aiAssistant`, `aiProvider`, `aiDataPrivacy`). `SettingsRowSpec` = `struct { let symbolName: String; let background: RGBComponents }` where `RGBComponents` is a Foundation-only `(r,g,b)` triple. Compiles in the test target without SwiftUI. **Gate-2 fix (round 1 Low #11)**: the design's OPDS-catalogs / translation-languages / Chinese-conversion rows are NOT in this enum — OPDS routes through the Library nav (not this sheet, per `SettingsView`'s existing comment), and the translation/Chinese-conversion rows are not present on this app's `SettingsView` at all (the design shows aspirational rows the shipped sheet does not have). The enum is scoped to exactly the rows this sheet renders across all four groups. |
| `vreader/Services/SettingsNotifications.swift` | **Gate-2 fix (Low #8)**: new app-level notification-names file — `ReaderNotifications.swift` is documented as reader-bridge/container coordination only, so a Settings-sheet notification does not belong there. Holds the Stats hand-off name. Follows the `vreader.<scope>.<event>` convention and the `ReaderNotifications.swift` file shape. | `extension Notification.Name { static let openReadingStatsRequested = Notification.Name("vreader.settings.openReadingStatsRequested") }`. |
| `vreader/ViewModels/SettingsHeaderViewModel.swift` | `@MainActor @Observable` view model that fetches the profile card's two numbers (book count, this-month reading seconds) off the `PersistenceActor`. Keeps `SettingsView` itself a thin composition. | `@MainActor @Observable final class SettingsHeaderViewModel` — `private(set) var bookCount: Int = 0`, `private(set) var monthReadingSeconds: Int = 0`, `func load(persistence: (any LibraryStatsReading)?) async`. **Gate-2 fix (Medium #2)**: `load` takes an **optional** boundary — `\.persistenceActor` is itself an optional Environment key, so `SettingsView` passes whatever the Environment holds and `load` `guard let`s it (a `nil` boundary is the "no data" path → zeros, the same as an empty library). Construction takes no args; `load` is called from `SettingsView`'s `.task`, and is idempotent (last-write-wins) so a `.task` re-run is safe. |
| `vreader/Services/LibraryStatsReading.swift` | **Gate-2 fix (Medium #2)**: the new read-only persistence boundary protocol `SettingsHeaderViewModel` depends on — defined precisely here rather than left implicit. Narrow by design: only the two reads the profile card needs. | `protocol LibraryStatsReading: Sendable { func countLibraryBooks() async throws -> Int; func sumReadingSeconds(in interval: DateInterval) async throws -> Int }`. `PersistenceActor` conforms (it is already an `actor`, so `Sendable`). `countLibraryBooks()` is a NEW count-only `PersistenceActor` method (a `FetchDescriptor<Book>` with `fetchCount` — NOT `fetchAllLibraryBooks()`, which materializes every `LibraryBookItem` just to count them — see Surface "MODIFIES" + rejected alternatives). `sumReadingSeconds(in:)` is WI-1's method. The protocol leaks nothing — both members are domain reads, no `ModelContext`, no SwiftData type in the signature. |
| `vreader/Services/PersistenceActor+ReadingWindow.swift` | New `PersistenceActor` extension: the two reads behind `LibraryStatsReading`. Reused by feature #58 later, but introduced here minimally for the card. | `func sumReadingSeconds(in interval: DateInterval) async throws -> Int` — fetches `ReadingSession` rows whose `startedAt` falls in `interval` via a `#Predicate` on the stored `startedAt` `Date` (store-side filter, not in-memory), sums `durationSeconds` (clamped ≥0, `Int64` accumulation to avoid overflow, matching `ReadingStats.recompute`). And `func countLibraryBooks() async throws -> Int` — a `FetchDescriptor<Book>` resolved via `context.fetchCount(_:)` so it returns the count without materializing `Book` rows. Both make `PersistenceActor` conform to `LibraryStatsReading`. Methods run on the `PersistenceActor` actor (each opens its own `ModelContext(modelContainer)`, the established `PersistenceActor+Stats` pattern). |
| `vreader/Utils/MonthBoundary.swift` | Pure helper computing the current calendar month's `DateInterval` in the user's current time zone. Deterministic + unit-testable with an injected `now` + `Calendar`. | `enum MonthBoundary { static func currentMonth(containing date: Date, calendar: Calendar = .current) -> DateInterval }`. |
| `vreaderTests/Views/Settings/SettingsProfileCardTests.swift` | Composition tests for `SettingsProfileCard`. | builds for every theme; `onOpenStats` callback fires; subline text for 0 books / 0h, singular "1 book", and populated. |
| `vreaderTests/Views/Settings/SettingsIconRowTests.swift` | Composition tests for `SettingsIconRow`. | builds with/without detail, with/without trailing value, destructive variant; builds for every theme. |
| `vreaderTests/Models/SettingsRowPaletteTests.swift` | Pins every design row's color + symbol against the design bundle. | each `SettingsRowSpec`'s `symbolName` is a non-empty valid SF Symbol token; `background` RGB matches the design hex; all specs distinct. |
| `vreaderTests/ViewModels/SettingsHeaderViewModelTests.swift` | View-model state tests with an in-memory `PersistenceActor`. | `load` populates `bookCount` from seeded books; `monthReadingSeconds` sums only this-month sessions; empty library → 0/0; error path leaves zeros (no crash). |
| `vreaderTests/Services/PersistenceActorReadingWindowTests.swift` | Actor tests for `sumReadingSeconds(in:)` + `countLibraryBooks()`. | sums sessions inside the interval; excludes sessions outside it; boundary sessions counted by `startedAt`; empty store → 0; large-history sum does not overflow; `countLibraryBooks` returns 0 for empty / N for N seeded. (No negative-`durationSeconds` case — `ReadingSession` clamps in `init`/`updateDuration`, so it is not constructible through the public model boundary; see the Test-catalogue WI-1 §, Gate-2 fix Medium #7. The `Int64`-accumulation defensiveness in `sumReadingSeconds` is still implemented but is not exercised via an unreachable corruption path.) |
| `vreaderTests/Utils/MonthBoundaryTests.swift` | Pure-function tests for `MonthBoundary`. | a mid-month date → that month's [start,end); first-instant-of-month; last-instant-of-month; DST-transition month; leap-February; year-boundary (Dec→Jan). |

### Files this feature MODIFIES

| File | Change |
|---|---|
| `vreader/Views/Settings/SettingsView.swift` | **Gate-2 fix (Medium #6) — exact composition.** The current structure is `ReaderSheetChrome { NavigationStack { Form { …4 sections… } } }`; `ReaderSheetChrome` does NOT scroll its body, and `Form` is the scroll container. The profile card must scroll WITH the list (a fixed header above a scrolling `Form` would clip on small devices / large Dynamic Type). Therefore the card becomes **the first row of the `Form`**, inside its own `Section` with no header, with `.listRowBackground(Color.clear)`, `.listRowInsets(EdgeInsets(top:16,leading:18,bottom:18,trailing:18))`, and `.listRowSeparator(.hidden)` — so it renders as the design's free-standing 14pt-radius card above the grouped sections while staying in the single `Form` scroll region. No `ScrollView` rewrite (see rejected alternatives). Concretely: (a) add a `profileSection` `@ViewBuilder` as the first child of `Form`, holding `SettingsProfileCard`; (b) `@State private var headerViewModel = SettingsHeaderViewModel()`, loaded in a `.task`; (c) the card's `onOpenStats` posts `Notification.Name.openReadingStatsRequested`; (d) `@Environment(\.persistenceActor) private var persistenceActor` (the optional-env pattern `WebDAVSettingsView` uses) feeds `headerViewModel.load(persistence:)` from `.task`; (e) keep `sectionsForTesting` unchanged; (f) the WI-4 row restyle replaces the `Label`-in-`NavigationLink` rows of the Cloud & Sync / Reading / About groups with `SettingsIconRow`, every `NavigationLink` destination + `accessibilityIdentifier` preserved verbatim; (g) add the `rowPaletteKeysForTesting` seam (see Test catalogue); (h) update the file header comment block (rule 22). The AI group's rows are restyled in WI-5, which touches `AISettingsSection.swift` (a different file) — `SettingsView.swift` itself is written by WI-4 only. |
| `vreader/Views/Settings/AISettingsSection.swift` | **WI-5** — restyle the feature-#50 AI group's rows (AI Assistant toggle / AI Providers `NavigationLink` / Data & Privacy toggle) to the design's `SettingsIconRow` colored-icon treatment, using the AI-row `SettingsRowPalette` entries WI-5 adds. The section's behavior (the `isAIEnabled` gate, the bound `Toggle`s, the `NavigationLink` to `AIProviderListView`, the `activeProfileSummary` trailing text, every `accessibilityIdentifier`) is preserved verbatim — only the row chrome changes. `AISettingsSection.swift` is written by WI-5 only. |
| `docs/architecture.md` | Notification Bus table gains the `openReadingStatsRequested` row (name `vreader.settings.openReadingStatsRequested`, payload `nil`, direction `SettingsView → ReadingDashboard presenter (feature #58)`). Per `.claude/rules/24-doc-sync.md`, a new cross-component notification name triggers a doc update. Done in WI-4. The notification name itself lives in the NEW `vreader/Services/SettingsNotifications.swift` (round 1 Low #8 fix), not in `ReaderNotifications.swift`. |
| `docs/features.md` | Status `TODO` → `PLANNED` (Gate 1 acceptance) — applied centrally, NOT by this worktree per the task brief. Listed here for completeness only. |

### Files OUT of scope

- **The reading-stats dashboard itself** (`ReadingDashboardView` / `FullStatsDashboard` / `StatsTimeWindowBar` / `SortablePerBookTable` and any `ReadingStatsAggregator` service) — that is **feature #58** (GH #665). This feature plans only the **entry-point Stats button** in `SettingsView` and the `openReadingStatsRequested` notification it posts. Feature #58 owns the observer + the dashboard view. **Gate-2 fix (High #1) — hard cross-feature dependency, no dead button ships.** The earlier draft accepted shipping a tappable Stats button with no consumer; the auditor correctly flagged that as a user-visible broken control. Resolution: **WI-4 (which adds the visible Stats button) is hard-blocked on feature #58 having merged its dashboard-presenter** — the WI that registers the `openReadingStatsRequested` observer and presents `ReadingDashboardView`. See "Cross-feature dependency" and "Work-item sequencing" for the gate. The button does not become visible to a user until its destination exists. WI-1/WI-2/WI-3 (foundational + the standalone card component) have NO dependency on #58 and proceed independently.
- `vreader/Views/Reader/ReaderSheetChrome.swift` — reused as-is; the sheet chrome was finalized in feature #60 WI-10. No change.
- `vreader/Models/ReaderThemeV2.swift` — reused as-is. The Settings sheet stays `.paper`-themed (the Library is not theme-switchable). No new theme tokens; the card's surface uses the existing `paperColor` / `sheetSurfaceColor` / `inkColor` / `subColor` / `ruleColor` / `accentColor` tokens.
- `vreader/Models/SheetSectionContract.swift` — the `ReaderSheetKind.appSettings` section contract is unchanged; the four design groups are unchanged. Only the *row rendering* inside the groups changes.
- The feature-#50 AI sub-screens (`AIProviderListView`, `AIProviderEditSheet`, `AISettingsViewModel`) — WI-5 restyles only `AISettingsSection`'s own rows; the pushed AI detail screens are untouched.
- `vreader/Views/Settings/AISettingsSection.swift` is **NOT out of scope** — it is modified by WI-5 (see the MODIFIES table). Listed here only to dispel the v1 draft's wrong "deferred" framing.
- `vreader/Services/ReadingSessionTracker.swift`, `vreader/Models/ReadingSession.swift`, `vreader/Models/ReadingStats.swift` — read-only consumers; no schema or model change. No SwiftData migration.
- WebDAV backup payload — feature #58 owns extending the backup with reading history. This feature does not touch backup.
- All reader-engine, importer, and persistence-write paths — untouched.

---

## Cross-feature dependency — feature #58 (reading-stats dashboard)

_(Gate-2 fix, High #1 — the Stats button must not ship as a dead control.)_

The design's **Stats** button opens the reading-stats dashboard. That dashboard is **feature #58** ("Reading-time + activity dashboard", GH #665, status `TODO` — being planned in parallel). This feature and #58 share the `vreader-profile-stats.jsx` design family and the #862 design handoff.

**The contract between the two features:**

- **#67 (this feature) owns**: the `SettingsProfileCard` with its Stats `Button`; the `Notification.Name.openReadingStatsRequested` (defined in the new `vreader/Services/SettingsNotifications.swift`, `vreader.settings.openReadingStatsRequested`, **no `userInfo` payload**); the `docs/architecture.md` Notification Bus row. The button's action posts that notification — nothing more.
- **#58 owns**: the `ReadingDashboardView` (and `ReadingStatsAggregator`); a "dashboard presenter" WI that **registers an observer for `openReadingStatsRequested`** and presents `ReadingDashboardView` (as a sheet from the Library, the natural host). #58's plan must consume the name this plan defines — the architecture-doc Notification Bus row is the single source of truth; #58 observes it, does not redefine it. **Risk R2** tracks the name-mismatch hazard.

**The hard dependency (resolves High #1).** The earlier draft accepted shipping the Stats button before #58's observer existed — a tappable button that does nothing. That is rejected. Instead:

- **WI-1, WI-2, WI-3** (the foundational helpers + the standalone `SettingsProfileCard` component) have **no dependency on #58** — they build and ship independently. `SettingsProfileCard` is a component that compiles and is composition-tested standalone; it is not user-visible until WI-4 mounts it.
- **WI-4** (mounts the card into `SettingsView` — the WI that makes the Stats button **user-visible**) is **hard-blocked on feature #58 having merged the WI that registers the `openReadingStatsRequested` observer + presents the dashboard.** Per `.claude/rules/48-parallel-execution.md` hard rule 2 ("hard dependency blocks downstream Gate 3"), WI-4's Gate-3 implementation does not start until #58's presenter WI is `DONE` on `main`. The tracker dependency is explicit: feature #67's row should carry a `Depends: #58 (dashboard presenter)` note, and #58's row already cross-references #67 ("entry point to feature #58").
- **WI-5** (the AI-group restyle) touches `AISettingsSection.swift`, a different file from WI-4's `SettingsView.swift` — but it is sequenced after WI-4 so the two visible-restyle slices land in order, and it therefore inherits the #58 gate transitively (it cannot start before WI-4, which cannot start before #58's presenter).

**Net effect**: a user never sees a Stats button without a working destination. If #58 slips, WI-1/2/3 still deliver value (the foundational reading-window query, the row style, the card component); only the visible mount waits. This keeps the two features decoupled at the code level (no shared type, only a notification name in the architecture doc) while removing the dead-control hazard.

---

## Prior art / project precedent / rejected alternatives

### Project precedent we build on

- **Feature #60 (visual-identity v2, VERIFIED)** is the direct lineage. WI-10 re-skinned the 5 app sheets with `ReaderSheetChrome` and pinned each sheet's section set in `SheetSectionContract.swift`. This feature finishes the `SettingsSheet` re-skin WI-10 left partial. We reuse `ReaderSheetChrome`, `ReaderThemeV2`, and the `.paper`-theme decision verbatim.
- **`SheetSectionContract` / `LibraryCardTokens` pattern** — feature #60 pins design-spec constants (section labels, card metrics) in a Foundation-only type that the test target asserts against without a render path. `SettingsRowPalette` follows this exactly: the per-row colors + symbols are design data with one home, and `SettingsRowPaletteTests` pins them.
- **`\.persistenceActor` Environment key** (`vreader/Utils/PersistenceActorEnvironment.swift`) — already exists "so settings sub-screens reach the persistence layer without threading the reference through every parent view"; it is an **optional** key (`PersistenceActor?`, `nil` in previews/tests). `WebDAVSettingsView` is the precedent: it declares `@Environment(\.persistenceActor)` and, in its `.task`, runs an async refresh (`refreshBackupVMIfNeeded()`) that reads the optional actor. `SettingsView` adopts the same shape — **optional Environment injection + an async load kicked off from `.task`** — to feed `SettingsHeaderViewModel`. (Gate-2 fix Low #9: the earlier draft said `.task { loadProfiles }`; the actual `WebDAVSettingsView.task` body is `refreshBackupVMIfNeeded()`. The precedent is the *pattern* — optional env + `.task`-driven async refresh — not a specific method name.)
- **`@MainActor @Observable` view models with protocol-boundary injection** (rule 50 §1, §10) — `LibraryViewModel`, `AISettingsViewModel`, `WebDAVProfileListViewModel` are all `@MainActor @Observable` and take their persistence boundary as a protocol so tests mock it. `SettingsHeaderViewModel` follows suit; its `load(persistence:)` takes a narrow read-only protocol (`LibraryStatsReading`) rather than the concrete `PersistenceActor`.
- **`ReadingTimeFormatter`** (`vreader/Utils/ReadingTimeFormatter.swift`) — pure, deterministic, locale-independent reading-time formatting, already unit-tested. The card subline reuses its hour/minute bucketing logic. Note: the existing `formatReadingTime` appends the literal " read" suffix, which the design subline does NOT want (design reads "41h read this month", suffix is "this month"). Decision: add a sibling pure function `ReadingTimeFormatter.formatCompactHours(totalSeconds:) -> String` (e.g. "41h", "<1h", "0h") rather than string-trimming the existing output. Tested in an extension of the existing formatter test suite.
- **`ReadingSession` / `ReadingStats`** SwiftData models already collect per-session reading time with a `startedAt` anchor — exactly the data the "Nh read this month" subline needs. No new model.
- **`ReaderTypography.body(for:size:)`** returns the Source Serif 4 font (Georgia + serif fallback). The card's "Your library" serif-italic header uses `ReaderTypography.body(for: .sourceSerif4, size: 16)` then applies italic, mirroring how `ReaderSheetChrome` renders its title.

### Industry convention

- iOS Settings-style "profile header card" is a well-established pattern (the system Settings app's Apple-ID header, Things 3, Bear, Reeder). The design's card follows the convention: a rounded card distinct from the grouped rows below, an avatar/identity slot, and a secondary metadata line. Library-as-identity (Option A from #862) is the honest variant when the app has no account — Apple's own Books app surfaces "reading goals" without a user identity. No external library needed; this is pure SwiftUI.
- The 30pt rounded colored-icon row is the standard iOS settings row (the system Settings app, 1Password, Fantastical). Matching it is convention, not invention. The design's `Row` is precisely this.

### Rejected alternatives

| Rejected | Why |
|---|---|
| **Implement the design's literal "lllyys" + initial-avatar card.** | The app has no user-name source. #862 explicitly resolved this to Option A (library-as-identity). Implementing the literal design would require inventing identity — prohibited by `.claude/rules/51-no-self-designed-ui.md` and contradicted by the #862 handoff. |
| **Option B (user-set display name field in Settings → About).** | #862 marked B "defer to a feature ask" — it adds a whole settings flow + a migration for users with nothing set, for purely cosmetic value. Not in this feature's scope; if the user wants it, it is a separate feature row. |
| **Option C (stats-as-hero card).** | #862 rejected C for v1 — it pushes the settings list down and a fresh install has a sad "0h" hero. |
| **Render the whole settings list with a hand-rolled `ScrollView` + `VStack` of `SettingsIconRow`s, dropping `Form`.** | Bigger blast radius — `Form` gives the grouped-section insets, the keyboard-avoidance, and the `NavigationLink` push behavior the existing sheet relies on. The design's grouped cards are achievable with `Form` + `.listRowBackground` + `.listRowInsets` while keeping every `NavigationLink` destination. Smaller, safer diff. Keep `Form`. |
| **Put the book-count / month-reading-seconds fetch directly in `SettingsView` `.task`.** | Violates rule 50 §2 (no view-level persistence orchestration) and is untestable without a render path. A thin `SettingsHeaderViewModel` is the project pattern (`WebDAVProfileListViewModel`, `AISettingsViewModel`). |
| **Have the Stats button directly present feature #58's `ReadingDashboardView`.** | `ReadingDashboardView` does not exist yet (feature #58 is `TODO`). A hard type reference would not compile and would couple #67 to #58's build order. A `NotificationCenter` hand-off decouples them — #67 ships a posting site, #58 ships the observer. This is the project's established cross-component decoupling mechanism (rule 50 §4). |
| **Add a brand-new `\.readingStatsPresenter` Environment closure for the Stats hand-off.** | Heavier than needed for a single fire-and-forget signal, and the notification bus is the documented vreader pattern for exactly this. A notification keeps #67 and #58 in separate compilation units with zero shared type. |
| **Compute "this month" with a naive `Date().addingTimeInterval(-30*86400)` rolling 30-day window.** | The design says "this month" — a *calendar* month, not a rolling 30 days. A rolling window drifts and is not what the user reads. `MonthBoundary` computes the real calendar-month interval in the user's time zone. (Feature #58's aggregator separately offers a `30d` window; that is a different, deliberate thing.) |

---

## Work-item sequencing

**Five WIs.** Each is one PR. Tiers per rule 47 Gate 5: **foundational** = pure types / DTOs / protocols / services with no user-observable behavior (unit + audit suffice, no device verify); **behavioral** = changes app behavior or visible UI (slice verification required).

This WI table is **authoritative** — the Test catalogue, Risks, and Surface-area sections all reference these five WI numbers. (Gate-2 round 2: the count + every cross-section WI reference was normalized to this table; the v1 5-WI numbering and the v2 transient 6-WI numbering are both superseded — this is the final cut.)

| WI | Title | Tier | Depends on | Scope | Est. PR size |
|---|---|---|---|---|---|
| **WI-1** | Reading-window persistence reads + month boundary + formatter | **foundational** | — | `MonthBoundary.swift` (pure) + `LibraryStatsReading.swift` (the protocol) + `PersistenceActor+ReadingWindow.swift` (`sumReadingSeconds(in:)` + `countLibraryBooks()`, making `PersistenceActor` conform to `LibraryStatsReading`) + `ReadingTimeFormatter.formatCompactHours`. Tests: `MonthBoundaryTests`, `PersistenceActorReadingWindowTests`, extend `ReadingTimeFormatterTests`. No UI, no user-observable behavior — pure types + actor reads. | Small (~4 source + 3 test files, ~260 LOC) |
| **WI-2** | `SettingsRowPalette` design data + `SettingsIconRow` row-style component | **behavioral** | — | `SettingsRowPalette.swift` (Foundation-only — the per-row symbol + RGB design data, scoped to the six rows on the three core groups) + `SettingsRowStyle.swift` (the `SettingsIconRow` SwiftUI view — pure presentation, no data fetch). Tests: `SettingsRowPaletteTests`, `SettingsIconRowTests` (composition, every theme). **Gate-2 fix (round 1 Medium #4 + round 2 Low #6)**: the palette is pure design data, but `SettingsIconRow` is a SwiftUI view for a visible app surface — **behavioral** under rule 47. The palette is too small (~90 LOC) to justify a standalone PR and only exists to feed the row, so the two ship in one PR; the PR's tier is **behavioral** (the higher of the two — it contains a visible-surface component). The row's "slice verification" is its composition test suite + build-for-every-theme assertion (the `ReaderSheetChrome` precedent, feature #60 WI-10) — there is no standalone user flow until WI-4 mounts it; recorded in the PR as such. | Small (~2 source + 2 test files, ~210 LOC) |
| **WI-3** | `SettingsHeaderViewModel` + `SettingsProfileCard` component | **foundational** | WI-1 | `SettingsHeaderViewModel.swift` (`@MainActor @Observable`, fetches via the `LibraryStatsReading` protocol) + `SettingsProfileCard.swift` (the design's library-identity card, consuming WI-1's helpers for the subline; takes an `onOpenStats` closure but does NOT post anything itself). Tests: `SettingsHeaderViewModelTests`, `SettingsProfileCardTests`. **Gate-2 fix (round 1 Medium #5)**: this WI ships the view model + the card **component**, NOT a user-visible surface — the card is not yet in `SettingsView`. An unmounted component cannot be "slice-verified" as shipped behavior, so this WI is **foundational** (verified by view-model state tests + card composition tests). The visible mount is WI-4. | Small-Medium (~2 source + 2 test files, ~240 LOC) |
| **WI-4** | Mount the card + restyle the three core groups + Stats hand-off — in `SettingsView` | **behavioral** | WI-2, WI-3, **feature #58 dashboard-presenter WI (`DONE` on `main`)** | Modify `SettingsView.swift`: (a) mount `SettingsProfileCard` as the first `Form` row (clear row background + insets + hidden separator — see Surface §); (b) add `@Environment(\.persistenceActor)` + `.task` load of `SettingsHeaderViewModel`; (c) the card's `onOpenStats` posts `Notification.Name.openReadingStatsRequested` (from the new `SettingsNotifications.swift`); (d) restyle the Cloud & Sync / Reading / About rows to `SettingsIconRow` with `SettingsRowPalette` colors, every `NavigationLink` destination + `accessibilityIdentifier` preserved verbatim. Also: create `SettingsNotifications.swift`; update `docs/architecture.md` Notification Bus table. Tests: extend `SheetReSkinSnapshotTests` (settings sheet still builds with the card + restyled rows) + `SettingsViewStatsHandoffTests` (the `onOpenStats` → notification post). **Gate-2 fix (High #1)**: this is the WI that makes the Stats button **user-visible**, so it is hard-blocked on feature #58's dashboard-presenter WI being merged — no dead button ships. Behavioral — slice-verified end-to-end on the simulator (open Settings → card renders with live counts → tap Stats → #58's dashboard presents). | Medium (~2 source + 2 test files + 1 doc, ~200 LOC) |
| **WI-5** | Restyle the AI group's rows to `SettingsIconRow` | **behavioral** | WI-2, WI-4 | **Gate-2 fix (round 1 Medium #3 + round 2 Medium #4)**: restyle the feature-#50 `AISettingsSection`'s rows (AI Assistant toggle / AI Providers nav / Data & Privacy) to the design's colored-icon `SettingsIconRow` treatment, so the whole `SettingsSheet` matches the design — closing the inconsistency the v1 draft left as a "known limitation". **Decision made now (no Gate-3 branch)**: WI-5 **definitively restyles** `AISettingsSection` in place — `AISettingsSection` is a thin (~70-line) `Section`-wrapper composite whose rows are plain `Toggle` / `NavigationLink`s, so swapping them to `SettingsIconRow` is a direct, bounded change of the same shape as WI-4's core-group restyle. The v2 "restyle OR narrow scope" fork is removed. Touches `AISettingsSection.swift` + adds the AI rows (`aiProvider` etc.) to `SettingsRowPalette`. Tests: extend `SheetReSkinSnapshotTests` + `SettingsRowPaletteTests` (the AI-row palette entries). This is the **final WI** — completing it implements every acceptance criterion → feature row to `DONE`, then Gate-5 final acceptance pass → `VERIFIED`. | Small (~2 source + 1 test file, ~110 LOC) |

**Sequencing rationale.** WI-1 and WI-2 are independent pieces on disjoint files — parallel-eligible, but small enough that serial is cheap (rule 48: "context switch is cheap"); recommend serial. WI-3 depends on WI-1 (subline math + the `LibraryStatsReading` protocol). WI-4 depends on WI-2 (`SettingsRowPalette` + `SettingsIconRow`) and WI-3 (the card component) **and** the feature-#58 dashboard-presenter WI being `DONE` on `main` (the High-#1 hard dependency — rule 48 hard rule 2). WI-5 depends on WI-2 (the row component) and WI-4 (which writes `SettingsView.swift`; WI-5 touches `AISettingsSection.swift`, a different file, but follows WI-4 to keep the two visible-restyle slices ordered). **WI-4 and WI-5 are the two visible-restyle WIs that touch the Settings surface; they are serialized — one writer at a time, rule 48 hard rule 3.** Recommended order: WI-1 → WI-2 → WI-3 → (wait for #58 presenter) → WI-4 → WI-5.

Feature size = 5 WIs = **Large** per rule 47's audit table (5+ WIs). The WIs are individually small (Small–Medium). Plan audits: 1+ rounds until clean (this document — 2 rounds run, see revision history). PR audits: 1 per WI; WI-1 (foundational) and WI-2 (behavioral) are on disjoint files and MAY batch under one audit if convenient — separate is fine. WI-4 and WI-5, both touching the Settings surface, get individual audits.

---

## Test catalogue

All new tests use Swift Testing (`import Testing`, `@Test`, `#expect`) per rule 10, except where `XCTestExpectation` is needed. File placement mirrors the source tree (rule 50 §8).

### WI-1

- **`vreaderTests/Utils/MonthBoundaryTests.swift`** — `MonthBoundary.currentMonth`:
  - mid-month date (e.g. 2026-05-19) → interval `[2026-05-01 00:00, 2026-06-01 00:00)` in a fixed calendar.
  - first instant of the month → start == that instant.
  - last instant of the month (2026-05-31 23:59:59) → still in the May interval, `end` is exclusive June-1.
  - February in a leap year (2024-02) → 29-day span; non-leap (2026-02) → 28-day span.
  - December → interval crosses the year boundary into Jan-1 next year.
  - a DST-transition month with an injected `Calendar` pinned to a DST-observing time zone → interval still spans the full calendar month (no off-by-one-hour).
- **`vreaderTests/Services/PersistenceActorReadingWindowTests.swift`** — `sumReadingSeconds(in:)` + `countLibraryBooks()` (in-memory `ModelContainer`, `SchemaV6`):
  - `sumReadingSeconds`: three sessions inside the interval → sum of their `durationSeconds`.
  - sessions before / after the interval → excluded.
  - a session whose `startedAt` is exactly the interval start → included; exactly the (exclusive) end → excluded.
  - empty store → 0.
  - 1,000+ seeded sessions → correct sum, no overflow (`Int64` accumulation), completes promptly.
  - `countLibraryBooks`: empty store → 0; N seeded `Book` rows → N.
  - **Gate-2 fix (Medium #7)**: the v1 plan's "negative `durationSeconds` stored value → clamped" case is **dropped** — `ReadingSession`'s `init` and `updateDuration(_:)` both clamp `durationSeconds` to `max(0, …)`, so a negative value is **not constructible** through `ReadingSession`'s public API. The `Int64`-accumulation defensiveness in `sumReadingSeconds` is still implemented (cheap, matches `ReadingStats.recompute`), but it is not unit-tested via an unreachable corruption path. If a corruption-path fixture is ever wanted, it needs a dedicated SwiftData store-rewrite harness — out of scope here.
- **extend `vreaderTests/Utils/ReadingTimeFormatterTests.swift`** — `formatCompactHours`:
  - 0 → "0h"; 30s → "<1h"; 3599s → "<1h"; 3600s → "1h"; 5400s → "1h"; 149400s (41h30m) → "41h" (design value).

### WI-2 (`SettingsRowPalette` + `SettingsIconRow`)

- **`vreaderTests/Models/SettingsRowPaletteTests.swift`** — `SettingsRowPalette`:
  - every `SettingsRowSpec`'s `symbolName` is non-empty.
  - every `symbolName` resolves to a real SF Symbol (`UIImage(systemName:) != nil`).
  - the `background` RGB of each spec matches the design hex in `vreader-panels.jsx` for the rows this feature renders (WebDAV `#3a8ac8`, Book sources `#3a6a5a`, Replacement rules `#a8804a`, HTTP TTS `#3a3a8c`, Help `#5a5a5a`, Version `#999`).
  - all specs are pairwise distinct (no accidental copy-paste duplicate).
- **`vreaderTests/Views/Settings/SettingsIconRowTests.swift`** — `SettingsIconRow` (`@MainActor`):
  - builds with title only; with title + detail; with title + trailing value; with all three.
  - **Gate-2 fix (round 1 Medium #7)**: the destructive variant — rather than the v1 plan's vague "`*ForTesting` accessor if needed", `SettingsIconRow` exposes a concrete, named `var resolvedTitleColorForTesting: Color` (mirroring `ReaderSettingsPanel.sheetChromeTitleForTesting` precedent) so the test asserts the destructive flag drives the title color. The plan commits to this seam now; it is not invented at implementation time.
  - `showsChevron: false` builds.
  - builds for every `ReaderThemeV2` theme (the row is theme-input even though Settings only uses `.paper` — future-proof, mirrors `ReaderSheetChrome`'s every-theme test).

### WI-3 (view model + card component)

- **`vreaderTests/ViewModels/SettingsHeaderViewModelTests.swift`** — `SettingsHeaderViewModel` (`@MainActor`, against a `LibraryStatsReading` mock — the protocol exists precisely for this — and also against a real in-memory `PersistenceActor`):
  - fresh VM → `bookCount == 0`, `monthReadingSeconds == 0` before `load`.
  - `load` with a mock returning `countLibraryBooks() == 5` → `bookCount == 5`.
  - `load` with sessions partly this month, partly last month → `monthReadingSeconds` counts only this-month sessions (uses `MonthBoundary` + `sumReadingSeconds`).
  - `load(persistence: nil)` → both stay 0 (the optional-boundary path — Medium #2 fix).
  - the `LibraryStatsReading` boundary `throw`ing → VM leaves zeros, does not crash, logs (assert no exception escapes).
  - `load` called twice → stable state (idempotent, last-write-wins — the `.task`-re-run guard).
- **`vreaderTests/Views/Settings/SettingsProfileCardTests.swift`** — `SettingsProfileCard` (`@MainActor`):
  - builds for every `ReaderThemeV2` theme.
  - **Gate-2 fix (round 1 Medium #7 + round 2 Low #7)**: the `onOpenStats` test — `SettingsProfileCard` is a value type whose Stats `Button` action is its `onOpenStats` closure. The test constructs the card with a closure that flips a captured flag, then invokes the card's exposed `var statsActionForTesting: () -> Void` (a named seam the plan commits to — the closure the button is wired to), and asserts the flag flipped. **`statsActionForTesting` is a closure-only seam**: it confirms the card invokes its `onOpenStats` closure, nothing more. The card does NOT post any notification — posting `openReadingStatsRequested` is `SettingsView`'s WI-4 wiring, and the notification-post assertion lives exclusively in WI-4's `SettingsViewStatsHandoffTests`, not here.
  - subline text: `bookCount: 0, monthReadingSeconds: 0` → "0 books · 0h read this month"; `bookCount: 1` → "1 book · 0h read this month" (singular); `bookCount: 152, monthReadingSeconds: 149400` → "152 books · 41h read this month" (design value). Asserted via an exposed `var sublineTextForTesting: String`.
  - header text is always "Your library" (library-identity model, never a name) — via `var headerTextForTesting: String`.

### WI-4 (mount + restyle + hand-off)

- **extend `vreaderTests/Views/SheetReSkinSnapshotTests.swift`** — `appSettingsViewStillBuilds` still passes; add: `SettingsView().body` builds with the profile card mounted and the restyled rows; `sectionsForTesting` unchanged (`["Cloud & Sync", "Reading", "About"]`). **Gate-2 fix (round 1 Medium #7)**: the v1 plan referenced a `rowSpecsForTesting` accessor "mirroring `sectionsForTesting`" — that accessor does not exist. The plan now **commits to adding it**: `SettingsView` gains `var rowPaletteKeysForTesting: [String]` returning, in render order, the `SettingsRowPalette` spec names of the rows it renders (exactly as `sectionsForTesting` already returns the section names). After WI-4 (core groups only) the test asserts this equals `["webDAVBackup", "bookSources", "replacementRules", "httpTTS", "helpFeedback", "version"]`. This is a new, named, planned seam — not an assumed-existing one.
- **`vreaderTests/Views/Settings/SettingsViewStatsHandoffTests.swift`** — the Stats hand-off (XCTest, needs `XCTestExpectation` per rule 10 §5):
  - posting through the card's `statsActionForTesting` closure (as wired by `SettingsView`) posts `Notification.Name.openReadingStatsRequested` exactly once.
  - the posted notification has no `userInfo` payload (the hand-off carries no data — feature #58's observer just presents its dashboard).
  - observer is removed in `defer`.

### WI-5 (AI-group restyle)

- **extend `vreaderTests/Views/SheetReSkinSnapshotTests.swift`** — `AISettingsSection` builds after the restyle; the AI group's rows carry their `SettingsRowPalette` colors. **Gate-2 fix (round 2 Medium #4)**: WI-5 definitively restyles `AISettingsSection` (the v2 "narrow scope instead" branch is removed). The assertion: an `AISettingsSection`-local `var rowPaletteKeysForTesting: [String]` (the same seam pattern as `SettingsView`'s) returns the AI rows' palette spec names — e.g. `["aiAssistant", "aiProvider", "aiDataPrivacy"]` for the rows the section renders (the exact set depends on the `isAIEnabled` toggle state, so the test exercises both states).
- **extend `vreaderTests/Models/SettingsRowPaletteTests.swift`** — the AI-row palette entries added in WI-5 (`aiProvider` `#8c2f2f`, plus the AI Assistant + Data & Privacy rows) satisfy the same invariants as the WI-2 entries: non-empty valid SF Symbol, design-hex RGB, pairwise distinct.

### Audit-driven additions (pre-emptive — likely Gate-2 asks)

- **Unicode / pluralization**: the subline pluralizes "book/books". Test the singular boundary (`1 book`) and zero (`0 books`). The string is English-only (the app is English per AGENTS.md) — no localized-plural infrastructure needed, but the test pins the exact copy.
- **Clock skew**: `MonthBoundary` is fed `Date()`. A test injects a future and a past `now` to confirm the interval is always the calendar month *containing* `now`, never negative-width.
- **Empty / fresh install**: `SettingsHeaderViewModel` with an empty store → "0 books · 0h" (covered above) — the design's card must not look broken on first launch.
- **Large history**: `sumReadingSeconds` over 1,000+ sessions (covered above) — no N+1, no overflow.
- **Concurrent load**: `SettingsView`'s `.task` could be re-triggered if the sheet re-appears. `SettingsHeaderViewModel.load` must be idempotent (re-runnable, last-write-wins) — add a test that calls `load` twice and asserts stable state.

---

## Risks + mitigations

| ID | Risk | Mitigation |
|---|---|---|
| **R1** | **Stats button could ship as a dead control** if its visible mount lands before feature #58's dashboard-presenter. A user taps "Stats" and nothing happens. | **RESOLVED — Gate-2 round 1, High #1.** The auditor correctly rejected the v1 plan's "accept a temporary no-op" stance. Resolution: **WI-4 (the WI that mounts the card and makes the Stats button user-visible) is hard-blocked on feature #58's dashboard-presenter WI being `DONE` on `main`** — see "Cross-feature dependency" and the WI table's `Depends on` column. WI-1/WI-2/WI-3 (foundational helpers + the standalone card component) proceed independently with no #58 dependency; the card component existing in the codebase is not user-visible until WI-4 mounts it. The design's Stats button is therefore never shown to a user without a working destination — the rule-51 design-fidelity requirement and the no-dead-control requirement are both satisfied by *sequencing*, not by gating the button's visibility (which would self-design a "button absent" state). |
| **R2** | The `openReadingStatsRequested` notification name must match what feature #58's observer expects. If #58's plan picks a different name, the hand-off silently breaks. | The name + payload shape is defined in **this** plan (`vreader.settings.openReadingStatsRequested`, no `userInfo`) and added to `docs/architecture.md`'s Notification Bus table in WI-4. Feature #58's plan must read this row and observe the same name. Cross-reference: this is called out in feature #58's tracker row already ("entry point to feature #58"). The architecture-doc table is the single source of truth for the name — #58 consumes it, does not redefine it. |
| **R3** | Re-skinning `Form` rows to `SettingsIconRow` could drop a `NavigationLink` destination or an accessibility identifier (the feature #60 WI-9 lesson — a re-skin must not drop wiring). | `SheetReSkinSnapshotTests` already asserts the settings view builds; WI-4 (core groups) and WI-5 (AI group) each extend it. For the core groups (WI-4), every `NavigationLink` destination (`WebDAVSettingsView`, `BookSourceListView`, `ReplacementRulesView`, `HTTPTTSSettingsView`) and every `accessibilityIdentifier` (`settingsWebDAV`, `settingsBookSources`, `settingsReplacementRules`, `settingsHTTPTTS`) is preserved verbatim — listed explicitly in WI-4's scope. For the AI group (WI-5), the `aiToggle` / `aiProvidersNavLink` / `consentToggle` identifiers + the `AIProviderListView` destination are likewise preserved. Gate-5 slice verification exercises each push on-simulator. |
| **R4** | `Form` + custom `.listRowBackground` / `.listRowInsets` can fight the design's 14pt-radius grouped-card look; the design's rows live inside a rounded card, `Form`'s `.insetGrouped` style has its own corner radius. | The design's grouped section *is* an inset-grouped card — `Form`'s native `.insetGrouped` already gives a rounded grouped container. The restyle changes the row *contents* (icon tile + title + value), not the section container. If the native container radius differs from the design's 14pt, that is a cosmetic delta noted for verification, not a blocker; `ReaderSheetChrome` already establishes the sheet surface. Decision made at WI-4 implementation with a fallback: if `Form`'s container cannot match, WI-4 keeps `Form` and accepts the native container radius (documented in L1), since the *row* is the design-critical element. No `ScrollView` rewrite (rejected above). |
| **R5** | `SettingsView` currently has **no** `\.persistenceActor` injected in some presentation contexts (it is `nil` in previews/tests). The header card would then show 0/0. | `SettingsHeaderViewModel.load` treats a `nil` / unavailable persistence boundary as "no data" → card shows "0 books · 0h" gracefully (same as a genuinely empty library). The live app *does* inject `\.persistenceActor` at `VReaderApp` root (confirmed: `PersistenceActorEnvironment` exists for exactly this, `WebDAVSettingsView` relies on it). Tests inject an in-memory actor. No crash path. |
| **R6** | `ReadingSession` rows accumulate; `sumReadingSeconds` over a long history could be slow if it fetches all rows then filters in memory. | `sumReadingSeconds(in:)` uses a `#Predicate<ReadingSession>` on `startedAt` (a stored `Date`) so SwiftData filters at the store, not in memory — `FetchDescriptor` + `#Predicate` is the established `PersistenceActor` query mechanism. **Gate-2 fix (Low #10)**: the v1 plan claimed `PersistenceActor+Stats` already filters by `startedAt` as precedent — it does not; `PersistenceActor+Stats` filters `ReadingSession` by `bookFingerprintKey`. The justification for the new windowed query stands on its own: predicate-on-`startedAt` keeps the filter store-side, and the 1,000-session test guards the performance characteristic. A denormalized per-day cache is explicitly **not** built here (feature #58 may, if its larger aggregator needs it). |
| **R7** | The card's serif-italic "Your library" header needs the Source Serif 4 font; if `ReaderTypography` cannot supply it, the header falls back inconsistently. | `ReaderTypography.body(for: .sourceSerif4, size:)` already exists and returns Georgia + a serif system fallback by design (its own header comment says so) — the same path `ReaderSheetChrome`'s title uses. The header reuses it; italic is applied on top. No new font asset, no `Info.plist` change. |

---

## Backward compatibility

- **No SwiftData schema change.** This feature reads `ReadingSession` / `ReadingStats` (existing models) and `Book` counts (existing). It adds no `@Model`, no migration, no schema-version bump. Existing data, existing backups, and older app versions are unaffected.
- **No persisted-preference change.** The profile card derives its two numbers live on each Settings-sheet open; nothing is persisted. There is no new `UserDefaults` key, no new CloudKit record, no backup-payload change. (Feature #58 separately handles persisting/backing-up reading history — not this feature.)
- **The new `openReadingStatsRequested` notification** is additive. Older code that does not observe it is unaffected (a posted notification with no observer is a no-op). The notification name is stable from WI-4 onward (its file `SettingsNotifications.swift` is created in WI-4); feature #58's observer consumes it. Per the High-#1 resolution, WI-4 does not merge until #58's observer exists, so the name has a consumer from the moment the posting site ships.
- **`SettingsView` API surface.** `SettingsView()` keeps its no-argument initializer (it reads `\.persistenceActor` from the Environment, not via init), so `LibraryViewSheets.swift`'s `.sheet { SettingsView() }` call site is unchanged. `sectionsForTesting` is unchanged. No caller is affected.
- **Older devices / iOS versions.** Pure SwiftUI + UIKit `UIFont` / `UIColor`; no new API beyond what feature #60 already requires. No deployment-target change.
- **Forward path.** If a future feature adds user accounts (the #862 Option B path), the library-identity card upgrades losslessly: per #862, the avatar slot becomes the user-photo slot and "Your library" becomes the display name — the card's layout and `SettingsProfileCard`'s shape do not change, only its inputs. The `SettingsProfileCard` init taking explicit values (not a hard-coded "Your library") keeps that door open.

---

## Known limitations (accepted)

- **L1 — `Form`-container corner radius vs the design's 14pt.** The design's grouped sections are 14pt-radius cards; SwiftUI `Form`'s native `.insetGrouped` container has its own system corner radius. The restyle changes the row *contents* (icon tile + title + value), which is the design-critical element; if the native container radius differs by a point or two from the design's 14pt, that is an accepted cosmetic delta (R4), not a blocker — a `ScrollView` rewrite to chase an exact radius is rejected (see rejected alternatives) as disproportionate. Recorded for verification, decided at WI-4 implementation.
- **L2 — singular/plural copy is English-only.** The card subline pluralizes "book/books" with a simple English rule; the app is English-only per AGENTS.md, so no localized-plural (`stringsdict`) infrastructure is added. If the app is ever localized, the subline copy joins that effort.

> The v1 plan's L1 ("the AI group keeps native rows, deferred") is **removed** — Gate-2 round 1 Medium #3 correctly judged that deferral let #67 falsely claim full design fidelity. The AI-group restyle is now **WI-5**, an explicit work item in the sequence above, not an accepted limitation.

---

## Audit fixes applied (Gate 2)

### Round 1 — Codex auditor (thread `019e4029`), 2026-05-19

Audit returned 1 High + 6 Medium + 4 Low. All resolved in plan v2:

| # | Sev | Finding | Resolution |
|---|---|---|---|
| 1 | High | Dead `Stats` button planned as shippable behavior. | New "Cross-feature dependency" §; WI-5 (the visible mount) hard-blocked on feature #58's dashboard-presenter WI. WI-1–WI-4 proceed independently. R1 marked RESOLVED. |
| 2 | Medium | `LibraryStatsReading` underspecified; `load(persistence:)` non-optional vs the optional env key. | New `LibraryStatsReading.swift` file with the exact protocol (`Sendable`, `countLibraryBooks()` + `sumReadingSeconds(in:)`); `load(persistence: (any LibraryStatsReading)?)` made optional; new `countLibraryBooks()` `PersistenceActor` method (not `fetchAllLibraryBooks()`). |
| 3 | Medium | Plan claimed full `SettingsSheet` fidelity but deferred the AI-group restyle. | AI-group restyle promoted to explicit **WI-6**; "end-to-end" claim removed from Problem; v1 limitation L1 deleted. |
| 4 | Medium | WI-2 (`SettingsIconRow` SwiftUI view) misclassified as foundational. | WI split: WI-2 = `SettingsRowPalette` (foundational, pure data); WI-3 = `SettingsIconRow` (behavioral — SwiftUI view for a visible surface). |
| 5 | Medium | WI-3 called "behavioral, slice-verified" but the card was "not wired". | The view-model + card-**component** WI (now WI-4) reclassified **foundational** (verified by VM-state + composition tests); the visible mount is the separate behavioral WI-5. |
| 6 | Medium | `Form`/header composition too vague. | Surface §`SettingsView.swift` row now specifies the exact composition: the card is the first `Form` row, `.listRowBackground(.clear)` + explicit insets + hidden separator, inside the single `Form` scroll region. No fixed header. |
| 7 | Medium | Tests rely on non-existent seams; the negative-`durationSeconds` case is not constructible. | The negative-duration test dropped (`ReadingSession` clamps in `init`/`updateDuration`). `rowSpecsForTesting` replaced by an explicitly-planned new seam `rowPaletteKeysForTesting`. The `onOpenStats` / destructive-variant / subline tests now name concrete planned seams (`statsActionForTesting`, `resolvedTitleColorForTesting`, `sublineTextForTesting`, `headerTextForTesting`). |
| 8 | Low | `ReaderNotifications.swift` is the wrong home for a settings notification. | New `vreader/Services/SettingsNotifications.swift` holds the name. |
| 9 | Low | `WebDAVSettingsView` precedent cited inaccurately (`.task` runs `refreshBackupVMIfNeeded()`, not `loadProfiles`). | Prior-art bullet corrected — the precedent is the *pattern* (optional env + `.task`-driven async refresh), method name fixed. |
| 10 | Low | R6 cited a nonexistent `startedAt`-predicate precedent. | R6 corrected — `PersistenceActor+Stats` filters by `bookFingerprintKey`; the windowed query is justified on its own merits. |
| 11 | Low | Palette inventory only partially aligned with the design row set. | `SettingsRowPalette` explicitly scoped to the six rows this feature renders; OPDS / translation / Chinese-conversion / AI rows explicitly excluded with rationale. |

All 11 findings closed in v2. No findings accepted-as-Low-without-fix. **Note**: the round-1 resolutions above used a transient 6-WI numbering (the round-1 fix for Medium #4 split WI-2 into a palette WI + a row WI). Round 2 found that numbering left the doc internally inconsistent and consolidated to the final **5-WI** sequence (WI-2 = palette + row in one PR). Where a round-1 row above says "WI-5"/"WI-6", read it against the round-2 final table: the visible-mount WI is **WI-4**, the AI-group restyle is **WI-5**. The WI table in "Work-item sequencing" is authoritative.

### Round 2 — Codex auditor (same thread `019e4029`), 2026-05-19

Re-audit of plan v2 verified all 11 round-1 fixes as real (`Book`, `ModelContext.fetchCount(_:)`, the `LibraryStatsReading` protocol shape, the `Form` composition, the dropped negative-duration case, and the actor/`@MainActor` concurrency model all confirmed sound). It returned **5 Medium + 2 Low** — all from the transient 6-WI numbering left inconsistent. Resolved in plan v3:

| # | Sev | Finding | Resolution |
|---|---|---|---|
| 1 | Medium | Plan said "Seven WIs" but defined only 6 — count not self-consistent. | Consolidated to **5 WIs** (round-2 Low #6 merge); every "7 WIs"/"Seven WIs"/"all 7" reference corrected. |
| 2 | Medium | High-#1 partially fixed — out-of-scope § said `WI-4` is the #58-blocked WI, the WI table said `WI-5`. | All references normalized: the visible-mount WI is **WI-4**, hard-blocked on #58; stated identically in the WI table, "Cross-feature dependency" §, OUT-of-scope §, and R1. |
| 3 | Medium | Other cross-section WI mismatches (architecture-doc line, R2) + a stale renumbering note while the Test-catalogue headings were already renumbered. | Full WI-reference normalization pass across Surface area / Test catalogue / Risks / Backward compat / Known limitations; the stale renumbering blockquote removed. |
| 4 | Medium | WI-6 (AI restyle) still had an unresolved "restyle OR narrow scope" branch — a scope decision left to Gate 3. | Decision **made now**: WI-5 (was WI-6) **definitively restyles** `AISettingsSection` in place — it is a ~70-line `Section`-wrapper, the restyle is bounded. The fork is removed. |
| 5 | Medium | Tiering claim ("all 7 WIs correctly tiered") was formally inconsistent because there were only 6 WIs. | Same as #1 — count fixed; the 5-WI table's tiers (WI-1 foundational, WI-2 behavioral, WI-3 foundational, WI-4 behavioral, WI-5 behavioral) are internally consistent. |
| 6 | Low | WI-2 (palette only, ~90 LOC) too small to be its own PR. | Palette merged with `SettingsIconRow` into a single WI-2 (the 6→5 consolidation). |
| 7 | Low | `statsActionForTesting` seam ownership not crisp — could read as the card posting the notification. | WI-3 card-test bullet now states explicitly: `statsActionForTesting` is a closure-only seam; the notification-post assertion belongs solely to WI-4's `SettingsViewStatsHandoffTests`. |

All 7 round-2 findings closed in v3. Round-2 verified-fixes (model assumptions, concurrency) carried forward unchanged.

### Round 3 — Codex auditor (same thread `019e4029`), 2026-05-19 — CLEAN

Re-audit of plan v3. The auditor verified every round-2 fix as real and correct:
- WI count self-consistent everywhere (WI table, "Five WIs" header, tiering recap, sequencing rationale, audit-fix-table mapping note).
- The #58 hard dependency stated identically as **WI-4** in all four required places (WI table `Depends on`, "Cross-feature dependency" §, "Files OUT of scope" bullet, R1).
- WI-5 a single definite action — no Gate-3 scope branch.
- Tiering correct for all 5 WIs.
- `AISettingsSection.swift` correctly in the MODIFIES table, no OUT-of-scope contradiction.
- Test-catalogue WI headings (WI-1..WI-5) aligned with the WI table.
- `statsActionForTesting` ownership crisp.

**Verdict: no open Critical / High / Medium findings.**

### Gate 2 outcome

3 audit rounds run (rule-47 maximum is 3). Round 1: 1 High + 6 Medium + 4 Low — all fixed. Round 2: 5 Medium + 2 Low — all fixed. Round 3: **clean**. Zero open Critical/High/Medium. No Low findings accepted-without-fix. **Gate 2 passes.** Author/auditor separation held throughout — the plan was authored by the Claude Code feature-workflow agent; the audit ran in a separate Codex MCP process (read-only sandbox).

---

## Manual Audit Evidence

_Not applicable — the Codex auditor was available and ran 3 rounds (see "Audit fixes applied (Gate 2)"). This section is the rule-47 manual-fallback, used only when the independent AI auditor is genuinely unavailable._

---

## WI-6 addendum (2026-05-21) — AI Assistant + Data & Privacy toggle rows (design #1068 unblocked)

**Why a new WI.** The original 5-WI plan's WI-5 said "definitively restyles `AISettingsSection`" assuming all three AI rows would take the existing `SettingsIconRow` colored-tile chrome. During WI-5's Gate-3 implementation (2026-05-20), an audit of the then-committed design (`vreader-panels.jsx:868-870`) found it depicted **only** the AI Provider row as a colored-icon row — it had no treatment for the two **toggle** rows (AI Assistant master gate, Allow AI data sharing consent). Per rule 51 (no self-designed UI), WI-5's PR narrowed scope to restyle the Provider row only (shipped as `SettingsRowPalette.aiProvider` + `AISettingsProviderRow`), and the two toggle rows were paused under `BLOCKED: needs-design (#1068)` on plain-`Toggle` chrome.

**The block is now resolved.** A dedicated design landed (commit `3735529a`, "resolves #1068"): `dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-toggles.jsx` + `ai-toggles-artboards.jsx`. The design introduces a **new component** (`SettingsToggleRow`) that the original plan did not anticipate, so the unblocked slice is its own WI (WI-6) rather than a continuation of WI-5.

**Design content (binding — implement exactly to it).** Three variants A/B/C are presented; the artboards file's recommendation post-it (`ai-toggles-artboards.jsx:222`) is explicit: **"ship A — peer-parity with the row WI-5 shipped, lowest implementation cost."** The brief independently names `AISectionVariantA`. **WI-6 implements Variant A only.**

Variant A (`vreader-ai-toggles.jsx:85-120`):
- A single AI group card with a `SectionLabel`/title.
- **AI Assistant** — `SettingsToggleRow`, icon `Icons.Sparkle` on `#8c2f2f`, title "Enable AI Assistant", detail "Translation, summarize, ask about the text", trailing `PillSwitch`. **Always visible** (master gate).
- When AI on: the existing AI **Provider** `SettingsRow` (already shipped, unchanged) + **Allow AI data sharing** — `SettingsToggleRow`, icon `ShieldIcon` on `#4a6a8a`, title "Allow AI data sharing", detail "Send passages and chat history for better answers", trailing `PillSwitch`. **Consent + Provider both hidden when AI off** — matches the current `if viewModel.isAIEnabled` gate exactly; no new visibility logic.

`SettingsToggleRow` (`vreader-ai-toggles.jsx:53-78`): the colored-tile peer of `SettingsRow`/`SettingsIconRow`, with a trailing `PillSwitch` instead of value+chevron, and an 11px detail subline (`marginTop: 2`, `lineHeight: 1.35`).

`PillSwitch` (`vreader-retranslate.jsx:362-377`): `34×20` track, `borderRadius: 10`; on-color `#3a6a5a`, off-color `rgba(255,255,255,0.12)` (dark) / `rgba(0,0,0,0.12)` (light); `16×16` white knob, `top: 2`, `left: on ? 16 : 2`, shadow `0 1px 2px rgba(0,0,0,0.2)`.

### Surface area (WI-6)

| File | Change |
|---|---|
| `vreader/Views/Settings/PillSwitch.swift` (CREATE) | The design's `PillSwitch` as a SwiftUI view — a 34×20 capsule track + 16pt knob, on/off bound to a `Binding<Bool>`, theme-aware off-color. Pure presentation. Used as the trailing slot of `SettingsToggleRow`. Foundation/SwiftUI; ~70 LOC. Exposes `resolvedTrackColorForTesting` so the composition test pins the on/off track color without a render path. |
| `vreader/Views/Settings/SettingsRowStyle.swift` (MODIFY) | Add `SettingsToggleRow` — a colored-tile row with a 30pt icon tile + 15pt title + optional 11pt detail + trailing `PillSwitch`. Reuses `SettingsRowMetrics`/`SettingsRowColors`. Distinct from `SettingsIconRow` (which has value+chevron); `SettingsToggleRow`'s trailing is always a `PillSwitch`, so it is a small dedicated struct, not a generic-`Trailing` reuse. Keeps the file <300 lines (currently 211; addition ~70 lines → ~280, within budget — if it exceeds, split `SettingsToggleRow` to its own file). |
| `vreader/Models/SettingsRowPalette.swift` (MODIFY) | Add `aiAssistant` (`sparkles` / `#8c2f2f` — same chroma as `aiProvider`, distinct `paletteKey`) and `aiDataSharing` (a shield SF Symbol / `#4a6a8a`). Same `SettingsRowSpec` shape + invariants as the existing entries. |
| `vreader/Views/Settings/AISettingsSection.swift` (MODIFY) | Restyle the AI Assistant + consent `Toggle`s to `SettingsToggleRow` bound to `$viewModel.isAIEnabled` / `$viewModel.hasConsent`. Merge the three separate `Section`s into the design's single AI group so it reads as one card (Variant A). Preserve `aiToggle` / `consentToggle` / `aiProvidersNavLink` accessibility identifiers + the `AIProviderListView` destination verbatim (R3 — re-skin must not drop wiring). Extend `rowPaletteKeysForTesting` to include `aiAssistant` (always) and `aiDataSharing` + `aiProvider` (when AI on). Update the file header comment (rule 22). |
| `docs/architecture.md` (MODIFY) | If `SettingsToggleRow` / `PillSwitch` count as new shared UI components, note them where `SettingsIconRow` is referenced. (Doc-sync check at PR time — likely a 1-line addition to whatever pattern table lists the WI-2 row components, or n/a if those weren't separately tabled.) |

**Files OUT of scope (WI-6):** Variants B and C (rejected by the design's own recommendation); the `AISettingsViewModel` consent/feature-flag logic (unchanged — only the row chrome changes); `AIProviderListView` / the pushed AI detail screens (unchanged); `SettingsView.swift` (the AI group is delegated to `AISettingsSection`, which WI-6 owns — `SettingsView` is not touched).

### Test catalogue (WI-6)

- **`vreaderTests/Views/Settings/PillSwitchTests.swift`** (CREATE) — builds on/off for every `ReaderThemeV2`; `resolvedTrackColorForTesting` is the design `#3a6a5a` when on; the design off-color (light vs dark) when off; the binding toggles (tapping flips the bound value).
- **`vreaderTests/Views/Settings/SettingsIconRowTests.swift`** (EXTEND) — `SettingsToggleRow` builds with detail + `PillSwitch`; builds for every theme; the icon-tile + title + detail render (composition).
- **`vreaderTests/Models/SettingsRowPaletteTests.swift`** (EXTEND) — `aiAssistant` + `aiDataSharing` satisfy the same invariants (non-empty valid SF Symbol via `UIImage(systemName:)`, design-hex RGB, pairwise-distinct from all existing specs).
- **`vreaderTests/Views/Settings/AISettingsSectionRestyleTests.swift`** (EXTEND) — `rowPaletteKeysForTesting` now returns `["aiAssistant"]` when AI disabled (the master toggle is a colored row now) and `["aiAssistant", "aiProvider", "aiDataSharing"]` when AI enabled (render order: master → provider → consent, per Variant A). Section still builds in both states. The existing `providerRow_composition_uses_paletteSpec` assertion is preserved.

### Tier + verification

**Behavioral** (visible UI). This WI **completes Feature #67** — it is the last remaining scope (WI-1/2/3/4 done; WI-5's Provider row shipped; these two toggle rows were the only deferred piece). On merge → feature row `IN PROGRESS` → `DONE`. Gate-5a slice-verify CU-free via DebugBridge present-sheet (`vreader-debug://present?sheet=settings`) + `simctl io screenshot`, or via the unit suite if the visual can't be captured (CU is virtual-display-only this session).

### Gate-2 status for WI-6

The design content is fixed (committed bundle, the design *is* the spec). This addendum records the now-unblocked scope; it does not redesign anything. The WI-6 implementation is audited at Gate 4 (per-WI Codex audit) like every WI. No new Gate-2 plan-audit round is required for a slice whose design is externally fixed and whose surface is a bounded restyle of an already-audited plan's AI-group WI — the original Gate-2 (3 rounds, clean) covered the AI-group restyle intent; #1068 only supplied the missing component vocabulary.

### WI-6 implementation outcome (2026-05-21)

**Gate 3 (TDD)**: RED tests for `PillSwitch` (design colors/metrics/binding), `SettingsToggleRow` (composition + design metrics + binding), `SettingsRowPalette` (`aiAssistant`/`aiDataSharing` design pins), and `AISettingsSection` (Variant A render order + visibility gate). GREEN: `PillSwitch.swift`, `SettingsToggleRow.swift` (extracted to its own file so `SettingsRowStyle.swift` stays under the 300-line guideline), palette specs, AISettingsSection Variant-A rewrite. Full suite green (7042 tests).

**Implementation decisions** (beyond the Surface-area sketch above):
- `PillSwitch` is implemented as `PillSwitchStyle: ToggleStyle` applied to a real label-less `Toggle` (the `PillSwitch` view wraps it). This gives native switch accessibility (VoiceOver announces a switch with an on/off value, not a "selected button") — a Gate-4 fix.
- The `aiToggle` / `consentToggle` identifiers are threaded through `SettingsToggleRow(toggleAccessibilityIdentifier:)` onto the `PillSwitch`'s underlying `Toggle` (the actionable control), not the row container — a Gate-4 wiring-preservation fix (feature #60 WI-9 lesson).
- The shield SF Symbol is `checkmark.shield` (matches the design `ShieldIcon`'s shield-with-inner-check).
- `SettingsToggleRowMetrics` carries the toggle-row's own detail spacing (`marginTop: 2` + `lineHeight: 1.35`), distinct from `SettingsIconRow`'s `marginTop: 1` (the toggle row's design source is `vreader-ai-toggles.jsx`, the icon row's is `vreader-panels.jsx`) — a Gate-4 fidelity fix.

**Gate 4 (impl audit)**: Codex thread `019e4a37`, 2 rounds, final verdict **ship-as-is**. Round 1: 1 High (a11y identifier on row container not the control), 1 Medium (button/selected vs toggle semantics), 1 Low (detail spacing not exact Variant A) — all fixed. Round 2: clean. Audit log: `.claude/codex-audits/feat-feature-67-wi-ai-toggle-rows-audit.md`.

**Gate 5a (slice verification)**: CU-free on iPhone 17 Pro Simulator (iOS 26.4) at v3.39.0, via the sim-drive-fallback tap-injection path (computer-use is virtual-display-only on this host; the app Settings sheet has no DebugBridge present hook, so DebugBridge alone can't reach it). Two-state proof chain: AI-ON shows all three colored rows (master `SettingsToggleRow` with green `PillSwitch`, AI Providers nav, consent `SettingsToggleRow` with shield tile + off `PillSwitch`); toggling AI OFF collapses the AI card to the single master row (provider + consent hidden). Artifacts: `dev-docs/verification/artifacts/feature-67-wi6-{02-ai-on-allrows,03-ai-off-collapsed}-20260521.png`.

**Feature completion**: WI-6 was the last remaining scope (WI-1/2/3/4 done; WI-5's Provider row shipped). Feature row → `DONE`. Gate-5b end-to-end acceptance pass + `dev-docs/verification/feature-67-<date>.md` evidence (`result: pass`) pending before `VERIFIED`.
