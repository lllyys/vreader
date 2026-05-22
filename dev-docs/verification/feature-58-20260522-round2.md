---
kind: feature
id: 58
status_target: VERIFIED
commit_sha: 1973b0028ab75e4fcdc43a7c7410e37eae3bacdc
app_version: 3.39.8 (build 629)
date: 2026-05-22
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator (UDID 61149F0E-DC18-4BE2-BB37-52659F1F4F62)
os_version: iOS 26.4
build_configuration: Debug
backend: n/a for b/c/d (SwiftData local store via seed-sessions); rclone-class WebDAV round-trip exercised by BackupReadingHistoryTests for e/f
result: pass
---

# Feature #58 — Reading-time + activity dashboard — Gate-5b verification (round 2)

Round-2 Gate-5b against merged `main` `1973b002` (v3.39.8), unblocked by Bug
#263 / GH #1138 (the `vreader-debug://seed-sessions` command, shipped v3.39.8).
**Result: pass — all 6 acceptance criteria verified; row flips `DONE` →
`VERIFIED`.**

Round 1 (`feature-58-20260522.md`, `result: partial`) verified criterion (a)
reachability + criteria (e)/(f) backup round-trip, but (b)/(c)/(d) were
BLOCKED CU-free because no harness could seed `ReadingSession` records — the
dashboard rendered all-zero data. Bug #263 added the session-seeding command.
This round seeds deterministic sessions and exercises (b)/(c)/(d) against the
real `ReadingStatsAggregator` data path, on-device (live store inspection) plus
deterministic high-fidelity integration tests that drive the same aggregator
over the same seeded data.

## Verification posture — why b/c/d are confirmed at the data layer

The reading dashboard's **visual** surface is NOT reachable CU-free on the
current harness: there is no `vreader-debug://stats` command and no
`present?sheet=stats` (`DebugCommand`'s `present` handler only covers reader
sheets: `toc|highlights|ai|settings|bookmarks`). The dashboard is presented
only via Feature #67's Settings → profile-card → Stats pill
(`.openReadingStatsRequested` → `ReadingDashboardView`). With computer-use
DOWN this session and no present-dashboard DebugBridge hook, the rendered
SwiftUI cannot be screenshotted CU-free.

Per the verify-skill's authorized path (and the brief), b/c/d are therefore
confirmed at the **substance** layer: the dashboard's numbers ARE the
`ReadingStatsAggregator` output over `ReadingSession` rows. I (1) seeded real
`ReadingSession` rows on-device through the production persistence boundary and
inspected the live store, then (2) drove the SAME aggregator over the SAME
seeded data via the deterministic seam test, and (3) confirmed the table's
sort + the VM's persistence via their behavioral suites. Criterion (a)'s
visual mount is carried forward from round-1's committed artifact; the table
render is covered by `StatsPerBookTable` view-composition tests.

## Acceptance criteria

| # | Criterion | Method | Observed | Verdict |
|---|---|---|---|---|
| a | Dashboard reachable from Settings → profile card → Stats (D1=A) | Round-1 artifact + `architecture.md` `.openReadingStatsRequested` route (Feature #67 WI-4 Stats pill → presents `ReadingDashboardView`) | Confirmed via the committed Feature #67 WI-4 artifact `dev-docs/verification/artifacts/feature-67-wi-4-04-stats-sheet-20260520.png` (dashboard mounts with 7-pill window bar + per-book table) | **PASS** (carried from round 1) |
| b | All 7 time windows render correct totals on a fixture with seeded sessions | `seed-sessions` on-device → live `ZREADINGSESSION` store inspection of per-window sums + the deterministic seam→aggregator integration test `PersistenceActor reading-history reads / seedSyntheticReadingSessions_producesNonZeroIncreasingWindowTotals` + the full `ReadingStatsAggregator` window-boundary suite | **Live store** (war-and-peace key, 6 sessions @ 600s, bands 0.26/3/15/60/120/300d ago): per-window totals **today=600, 7d=1200, 30d=1800, 90d=2400, 180d=3000, all=3600** — non-zero + strictly increasing. **Test**: the SAME aggregator over the SAME seeded container asserts exactly that ladder (`today=1×s … all=6×s`) + `today<7d<…<all` + `180d ≤ year ≤ all` | **PASS** |
| c | Per-book table shows time/notes/highlights counts, sortable on all columns | `ReadingStatsAggregator / sortIsAppliedToPerBookTable` (real row reorder) + `ReadingStatsAggregator` per-book notes/highlights projection (`seedAnnotations`) + `StatsPerBookTable composition` 5-column header-tap suite | Aggregator reorders `perBook` by readingTime-desc → `["Aardvark","Zeta"]` (500s before 100s) and by title-asc → alphabetical; per-book row carries `notesCount`/`highlightsCount`/`lastReadAt` from real annotation rows; table exposes the 5 sortable columns `[.title,.readingTime,.highlights,.notes,.lastRead]` with header-tap → activate-desc / toggle-direction semantics on every column | **PASS** |
| d | Sort selection persists across app launches | `ReadingDashboardViewModel` sort-persistence suite — UserDefaults round-trip across VM construction (= relaunch) | `changingSortPersistsToPreferenceStore` (writes `storageString`), `sortIsRestoredFromPreferenceStoreAtConstruction` (a saved `notes:asc` is restored on a fresh VM), `corruptStoredSortFallsBackToDefault` (garbage → `readingTime:desc`) all pass | **PASS** |
| e | `BackupDataCollector` emits `reading-history.json`; restore reproduces totals | High-fidelity integration suite `Backup reading-history section` (`BackupReadingHistoryTests`) — real collect → envelope → restore boundary | Suite green on `1973b002` (in the 333-test run) | **PASS** (re-confirmed) |
| f | Round-trip: backup → wipe → restore preserves `ReadingSession` + `ReadingStats` exactly | Same integration suite (the round-trip path) | Round-trip preservation asserted by the suite; green on `1973b002` | **PASS** (re-confirmed) |

## Commands run

```bash
SIM=61149F0E-DC18-4BE2-BB37-52659F1F4F62

# 1. Clean DEBUG build + targeted test gate into a fresh derivedDataPath
#    (Bug #259: incremental rebuilds drop the injected vreader-debug scheme).
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project vreader.xcodeproj -scheme vreader -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM" \
  -only-testing:vreaderTests/DebugCommandTests \
  -only-testing:vreaderTests/DebugBridgeTests \
  -only-testing:vreaderTests/RealDebugBridgeContextTests \
  -only-testing:vreaderTests/PersistenceActorStatsReadTests \
  -only-testing:vreaderTests/ReadingStatsAggregatorTests \
  -only-testing:vreaderTests/StatsPerBookTableTests \
  -only-testing:vreaderTests/ReadingDashboardViewModelTests \
  -only-testing:vreaderTests/ReadingDashboardSnapshotTests \
  -only-testing:vreaderTests/BackupReadingHistoryTests \
  -parallel-testing-enabled NO -derivedDataPath build/verify-58b
# → ** TEST SUCCEEDED **; xcresult: 333 tests, 333 passed, 0 failed.

# 2. Install the just-built app (resolved from MY derivedDataPath, not a
#    global newest-mtime find — avoids picking a sibling worktree's build).
APP="$(pwd)/build/verify-58b/Build/Products/Debug-iphonesimulator/vreader.app"
/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes" "$APP/Info.plist" | grep vreader-debug  # scheme present
xcrun simctl install "$SIM" "$APP"
xcrun simctl launch "$SIM" com.vreader.app

# 3. Reproduce the (now-fixed) gap, then seed sessions live.
xcrun simctl openurl "$SIM" "vreader-debug://reset"
xcrun simctl openurl "$SIM" "vreader-debug://seed?fixture=war-and-peace"
STORE="$(xcrun simctl get_app_container "$SIM" com.vreader.app data)/Library/Application Support/default.store"
sqlite3 "$STORE" "SELECT COUNT(*) FROM ZREADINGSESSION;"   # 0 (dashboard would render all-zero)

KEY="txt:bd8285a80f01df96dedd20a02178043afb85c0b499127e300baf57b7f1ed7508:1705"
ENCKEY="txt%3Abd8285a80f01df96dedd20a02178043afb85c0b499127e300baf57b7f1ed7508%3A1705"
xcrun simctl openurl "$SIM" "vreader-debug://seed-sessions?book=$ENCKEY"

# 4. Confirm 6 sessions across the bands + the per-window ladder + stats refresh.
sqlite3 "$STORE" "SELECT COUNT(*) FROM ZREADINGSESSION;"   # 6
sqlite3 "$STORE" "SELECT ZDURATIONSECONDS,
  ROUND((strftime('%s','now') - (ZSTARTEDAT + 978307200))/86400.0,2)
  FROM ZREADINGSESSION ORDER BY ZSTARTEDAT DESC;"          # 600 each @ 0.26/3/15/60/120/300 days
sqlite3 "$STORE" "SELECT ZTOTALREADINGSECONDS, ZSESSIONCOUNT FROM ZREADINGSTATS;"  # 3600, 6
# Per-window sums (rolling, by startedAt, half-open [start,now)):
#   today=600 7d=1200 30d=1800 90d=2400 180d=3000 all=3600  (strictly increasing)
```

## Observations

- The dashboard is reachable only through Feature #67's Settings Stats pill;
  there is no DebugBridge present-dashboard hook, so the *visual* render is not
  screenshot-able CU-free with computer-use down. b/c/d are therefore confirmed
  at the data/behavioral layer, which IS the substance of those criteria — the
  on-device live store gives the real inputs, and the deterministic seam test
  drives the real `ReadingStatsAggregator` over those exact inputs to produce
  the dashboard's numbers. The visual mount is covered by round-1's artifact +
  the `StatsPerBookTable` composition tests.
- The OSLog `[DebugBridge]` lines do not surface via `log show`/`log stream` on
  this iOS-26 sim (a known `.info` log-persistence quirk), so the live
  verification reads the SwiftData store directly — the strongest possible
  evidence here, since the data path is exactly what criteria b/c/d are about.
- The today band landed at 0.26 days (~6.2h) ago because the command ran
  mid-morning local; the midpoint-of-elapsed-day anchor (Bug #263 Codex
  round-1 fix) keeps it inside `[startOfDay, now)` regardless of time of day
  (confirmed: startedAt 06:18 local ∈ [00:00, 12:36)). Every `endedAt ≤ now`
  (Bug #263 Codex round-2 fix holds live — no future `lastReadAt`).
- My hand-written raw-SQLite `today` bucket initially returned blank due to
  imprecise `strftime` midnight/timezone juggling; a Python timezone-aware
  check confirmed the today session is inside the local calendar day, giving
  today=600 — matching `seedSyntheticReadingSessions_producesNonZeroIncreasingWindowTotals`
  exactly. The production `Calendar.startOfDay` path (what the aggregator uses)
  is the authoritative bucketer, not my ad-hoc SQL.

## Artifacts

- `dev-docs/verification/artifacts/feature-67-wi-4-04-stats-sheet-20260520.png` (dashboard reachability, criterion a — committed under Feature #67's WI-4 evidence).
- `dev-docs/verification/bug-263-20260522.md` (the `seed-sessions` command's own verification — the harness this round depends on).
- `.xcresult`: `build/verify-58b/Logs/Test/Test-vreader-2026.05.22_12-32-45-+0800.xcresult` (333 tests, 0 failures, 9 suites incl. `Backup reading-history section`).
- Live store query output captured inline in `## Commands run`.
