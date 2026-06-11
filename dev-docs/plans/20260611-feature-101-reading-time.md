# Feature #101 — In-reader total reading time

- **Status**: Gate 1 v3 (2026-06-11) — Gate 2 PASSED (3 rounds; r3 clean, session `019eb565-f774-7112-93fc-0df8e89315f5`)
- **Revision history**:
  - v1: initial draft.
  - v3 (Gate-2 round 2, NEEDS-REVISION → 2 Medium): (1) the Book-details
    live "This session" row gains an explicit hoist seam — the session
    clock is host-private `@State`, so the lifecycle helper's tick now
    ALSO posts the repo-idiomatic bus notification
    `.readerSessionTimeDidChange` (`["fingerprintKey": String,
    "display": String]`, ~1 post/minute); `ReaderContainerView` mirrors
    it into `@State currentSessionDisplay` (keyed to its book) and
    passes it to the sheet — the same mirror pattern as
    `.readerBilingualDidChange` → chrome state. (2) the MD pages
    contract corrected to match today's split: MD paged =
    "Page N of M", MD scroll = percent.
  - v2 (Gate-2 round 1, NEEDS-REVISION → 1 High, 4 Medium):
    (H) `ReaderLifecycleHelper` is NOT `@Observable` — helper-only
    mutations are not a reliable SwiftUI invalidation seam; v2 makes the
    helper `@Observable` (the existing `sessionTimeDisplay` passthroughs
    keep working; `timeReadoutDisplay` rides the same invalidation).
    (M1) per-host PAGES-readout contracts enumerated (the native hosts'
    trailing slot is hardwired to session time today — there is no
    existing pages readout to "restore"): TXT scroll = percent, TXT
    chapter-paged = "Page N of M" (chapter-local), MD paged = "Page N of M" / MD scroll = percent, legacy
    EPUB = "Chapter N of M", PDF = "N pages left in book" (the design's
    canonical string), Readium = its existing percent fallback, Foliate =
    its existing section-position fallback (`FoliateBottomChromeLabels`).
    (M2) per-book persistence goes through ONE shared read-modify-write
    helper (`PerBookSettingsStore.update(bookKey:baseURL:_:)` mutating a
    loaded-or-empty settings value, then save) — no per-host merge logic;
    the metrics toggle uses it.
    (M3) WI-2 split: WI-2a = data sourcing/state (per-book stats +
    first-session-date fetches, a `BookReadingTimeModel` value derived in
    a testable builder) then WI-2b = the sheet rows rendering.
    (M4) a pure `ReaderMetricsReadout` seam (`resolve(persisted:)` +
    `toggled(hasTimeReadout:)`) pins the cycle rules; the SwiftUI layer
    stays wiring.
- **Design**: landed (PR #1652) — `vreader-reading-time.jsx`
  (`RTMetricsLine` / `RTBottomChrome` / `RTBookDetailsRows`) +
  `design-notes/bilingual-suite-issues.md` §#1641. Committed decision: the
  bottom-chrome metrics line's TRAILING label is a TAP TARGET cycling
  page ↔ time readouts; the time readout carries BOTH durations
  ("12m read · 6h 40m total", session first); first-ever session reads
  "4m read · first session"; totals above 10h drop minutes ("41h");
  the trailing label never wraps (leading truncates); the press state is
  a subtle rounded fill; the choice persists per book. Book details gains
  the always-on home: `Reading time — 6h 40m total` (sub "N sessions
  since <date>") · `This session — 12m` · `Average session — 17m`.
  NO new chrome.
- **Tracker row**: `docs/features.md` #101 (Low). Design request #1641
  closed (bundle landed); feature GH issue created at the PLANNED flip.

## Problem

The reader shows only the CURRENT session duration (the #345 trailing
label); the book's cumulative reading time is invisible without leaving
the book. User: "the reading interface requires a feature that displays
the total reading time and the duration of the current reading session."

## Surface area

| File | Change |
|---|---|
| `vreader/Services/Stats/ReadingTimeFormatter.swift` (or its home) | NEW pure builders: `totalDisplay(totalSeconds:)` (>10h drops minutes — "41h", else "6h 40m"), `combinedReadout(sessionSeconds:liveTotalSeconds:isFirstSession:)` → "12m read · 6h 40m total" / "4m read · first session". The TDD heart — parameterized tests incl. boundaries (599s, 1h, 9h59m, 10h, 10h01m), zero, first-session. |
| `vreader/ViewModels/ReaderLifecycleHelper.swift` | Becomes `@Observable` (Gate-2 H — the reliable invalidation seam; the existing passthroughs keep reading it). (a) `func attachBookTotals(totalSecondsAtOpen: Int, isFirstSession: Bool)` — the host queries stats ONCE at open (never per tick). (b) `timeReadoutDisplay: String?` = combined readout over `totalAtOpen + sessionSeconds`; nil until totals attach (chrome pins pages). Tick path untouched. |
| `vreader/Views/Reader/ReaderMetricsReadout.swift` (NEW, ~40 lines) | (Gate-2 M4) the pure cycle seam: `enum ReaderMetricsReadout: String { case pages, time }` + `static func resolve(persisted: String?) -> Self` + `func toggled(hasTimeReadout: Bool) -> Self` (no time readout → stays pages, no flash). All cycle rules pinned here. |
| `vreader/Services/PerBookSettings.swift` | (Gate-2 M2) new optional `metricsReadout: String?` + ONE shared `PerBookSettingsStore.update(bookKey:baseURL:_ mutate:)` read-modify-write helper — hosts never hand-merge the JSON. |
| `vreader/Views/Reader/ReaderBottomChrome.swift` | The trailing label becomes the designed tap target: new optional `timeTrailingLabel: String?` + `metricsReadout: Binding<ReaderMetricsReadout>` (enum `pages`/`time`). Tap cycles when BOTH readouts exist (a nil time label pins pages — pre-totals or no session). The pressed state = the design's rounded fill (`.background` on press via a ButtonStyle). `trailingLabel` (today's param) becomes the PAGES readout. `fixedSize`/layout-priority so the trailing never wraps and the leading truncates. |
| 7 host call sites | (Gate-2 M1) per-host PAGES readouts (the trailing slot is session-time-hardwired today — these are DEFINED, not restored): TXT scroll = percent; TXT chapter-paged = chapter-local "Page N of M"; MD paged = "Page N of M" / MD scroll = percent; legacy EPUB = "Chapter N of M"; PDF = "N pages left in book"; Readium = its percent fallback; Foliate = `FoliateBottomChromeLabels` section position. Each site passes pages + the lifecycle `timeReadoutDisplay` + the shared per-book readout binding. Session time moves INSIDE the `time` readout (the designed model). |
| Reader-open total query (each host's open path or `ReaderContainerView`) | One `PersistenceActor` stats fetch at open → `attachBookTotals`. A book with `sessionCount == 0` → `isFirstSession: true`. |
| `vreader/Views/Reader/BookDetails/BookDetailsSheet.swift` (+ subviews) | NEW Reading time group (3 designed rows): total (sub: "N sessions since <medium-format date>"), this session, average session (total/count, rounded minutes). Data: per-book `ReadingStatsRecord` + earliest session date. **Live-session seam (Gate-2 r2)**: `ReaderLifecycleHelper`'s tick posts `.readerSessionTimeDidChange` (`fingerprintKey` + `display`, ~1/min, `ReaderNotifications.swift` registered); `ReaderContainerView` mirrors into `@State currentSessionDisplay` (book-keyed) and passes it into the sheet; "—" when nil (sheet opened with no live reader). |
| `vreader/Services/PersistenceActor+Stats.swift` | Small additions: `fetchStats(forBookWithKey:)` + `firstSessionDate(forBookWithKey:)` (filtered fetches — the all-book scans exist; per-book variants avoid O(library) at sheet-open). |

**Files OUT of scope**: the stats dashboard (#58) + stats sheet (#67) —
read-only consumers of the same records; the scrubber; TTS time
accounting (whatever sessions record today is what totals show — the
row's open question resolves as "totals = recorded sessions", no new
accounting).

## Prior art / precedent / rejected alternatives

- #345 wired `sessionTimeDisplay` into the trailing slot on every host —
  this feature RESTRUCTURES that slot per the design (pages ↔ time
  cycle) rather than appending to it.
- `ReadingTimeFormatter.formatReadingTime` exists (session formatting) —
  the new builders compose with it.
- Per-book persistence: the `PerBookSettings` optional-field pattern
  (bilingual fields, #84).
- Rejected (design): a combined always-on label (contended slot), a
  long-press detail, a new chrome row ("No new chrome" is committed).

## Work items

- **WI-1 (behavioral, ~250 lines)** — formatters + lifecycle totals +
  chrome tap-cycle + per-book persistence + the 7 host call sites.
  RED: formatter parameterized tests (boundaries, first-session, >10h);
  lifecycle `timeReadoutDisplay` (nil before attach, live total grows
  with ticks); chrome readout-cycling state tests; per-book
  resolve/apply round-trip.
- **WI-2a (behavioral, ~120 lines)** — data sourcing/state (Gate-2 M3):
  `fetchStats(forBookWithKey:)` + `firstSessionDate(forBookWithKey:)` on
  the persistence actor; a testable `BookReadingTimeModel.build(record:
  firstSession:liveSessionDisplay:)` deriving total/since/average/this-
  session strings. RED: in-memory-container fetch tests; derivation
  tests (zero record, division guard, since-date formatting).
- **WI-2b (behavioral, ~120 lines)** — the Book details Reading time
  group rendering the model (3 designed rows; "—" session when no live
  reader). RED: row-content tests from a built model.

## Edge cases

- First-ever session: `total == session` → "Nm read · first session"
  (no duplicated number).
- Zero/absent stats record (never-read book): time readout nil → pages
  pinned; Book details shows "No reading time yet" state? — design shows
  rows with values only; absent record renders the group with "0m total /
  — / —" (simplest truthful rendering; the sub line omits "since").
- >10h totals drop minutes; exactly 10h ("10h"); 59s sessions ("<1m" per
  the existing session formatter).
- Restored books (WebDAV history): totals come from the same records —
  included by construction.
- Narrow widths / long chapter titles: trailing `layoutPriority(1)` +
  leading truncation.
- Tap with no time readout available: no cycle, no pressed flash.
- The per-book choice must survive reopen + engine swaps (it lives in
  PerBookSettings, host-agnostic).
- Average session rounds to minutes; guard division by zero.

## Test catalogue

- `vreaderTests/Services/Stats/ReadingTimeFormatterTests.swift` (extend):
  the two new builders, parameterized.
- `vreaderTests/ViewModels/ReaderLifecycleHelperTests.swift` (extend):
  attach + live-total growth + first-session flag + nil-before-attach.
- `vreaderTests/Views/Reader/ReaderBottomChromeTests.swift` (new or
  extend): cycle state machine, nil-time pinning, label selection.
- `vreaderTests/Services/PerBookSettingsTests.swift` (extend): the new
  field round-trip + resolve precedence.
- `vreaderTests/Services/PersistenceActorStatsTests.swift` (extend):
  per-book fetch + first-session date (in-memory container, seeded
  sessions).
- Book details: row-derivation tests (average, since-date formatting).

## Risks + mitigations

- **Per-tick queries**: forbidden by design — totals attach once at
  open; the live total is arithmetic.
- **7 call sites drift**: each host compiles against the new chrome
  signature — a missed site is a compile error, not a silent gap.
- **Stats staleness** (recompute timing): totals show the last
  recomputed record + the live session delta; a stale record self-heals
  at the next recompute (existing pipeline) — same staleness the
  dashboard already accepts.

## Backward compat

No schema changes (new optional PerBookSettings field; absent = pages
default). Older builds ignore the field. Stats records unchanged.
