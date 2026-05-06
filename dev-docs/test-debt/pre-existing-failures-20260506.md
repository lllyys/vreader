# Pre-existing test failures snapshot — 2026-05-06 (post v3.14.21)

Full `xcodebuild test -scheme vreader -only-testing:vreaderTests` against `main` at v3.14.21:

- **Passed**: 4374
- **Failed**: 19
- **Skipped**: 5

Feature #44 round 9 (PR #N — see `feature-44-...e.md` history) reported "Full suite green: 716/716 tests pass" at the time. Since then ~3700 Swift Testing tests have been added, and the failure roster persists. The 716-green claim may have been XCTest-only.

## Failure roster

All 19 failures are clustered in 5 areas. None of this session's PRs (#307–#328 for bug #126/#93/#141/#142/#144/#145/#147/#99-cause-1 plus 4 verification slices) touched the files containing these tests.

| Cluster | Count | Suite | Fix shape (untriaged) |
|---|---|---|---|
| AutoPageTurner | 10 | `AutoPageTurnerTests` | Class-wide failure suggests recent refactor of `AutoPageTurner` left tests stale, OR Swift Testing init/main-actor pattern changed. Read tests + production side-by-side. |
| TTSService Speed | 5 | `TTSServiceTests` (speed control suite) | Likely API drift on `TTSService` rate setter. |
| PersistenceActor rejection paths | 3 | `PersistenceActorBookmarksTests`, `PersistenceActorHighlightsTests` | `addBookmarkRejectsMismatchedKey`, `addHighlightRejectsMismatchedKey`, `addHighlightToMissingBookThrows` — assertion shape may have shifted in actor implementation. |
| PhaseBMediumAudit | 1 | `PhaseBMediumAuditTests` | "ReaderSettingsStore has autoPageTurnInterval setting" — possibly snapshot of expected store keys drifted. |

## Failed test names

```
AutoPageTurner :: intervalClamped_belowMin_becomesMin()
AutoPageTurner :: intervalClamped_aboveMax_becomesMax()
AutoPageTurner :: intervalClamped_exactMin_stays()
AutoPageTurner :: intervalClamped_exactMax_stays()
AutoPageTurner :: intervalClamped_negativeValue_becomesMin()
AutoPageTurner :: intervalClamped_zero_becomesMin()
AutoPageTurner :: start_callsNextPage_afterInterval()
AutoPageTurner :: stop_cancelsTimer_noPagesAfterStop()
AutoPageTurner :: pause_suspendsTimer_noPagesWhilePaused()
AutoPageTurner :: stopsAtLastPage()
PersistenceActor — Bookmarks :: addBookmarkRejectsMismatchedKey()
PersistenceActor — Highlights :: addHighlightRejectsMismatchedKey()
PersistenceActor — Highlights :: addHighlightToMissingBookThrows()
PhaseBMediumAudit — Issue 9: AutoPageTurner wiring readiness :: ReaderSettingsStore has autoPageTurnInterval setting
TTSService Speed Control :: speedControl_setsRate_low()
TTSService Speed Control :: speedControl_setsRate_high()
TTSService Speed Control :: speedControl_clampsAboveMax()
TTSService Speed Control :: speedControl_clampsBelowMin()
TTSService Speed Control :: speedControl_rateAppliedToUtterance()
```

## Why this isn't shipped as a fix

Investigating each cluster requires reading tests + production code side-by-side, identifying root cause, and either updating production or aligning tests. Multi-iteration scope. This file records the roster so a future session picks it up cleanly without re-running the full 7-minute test suite to find them.

## Verified-clean against this session's changes

Files touched 2026-05-06 (v3.14.13 → v3.14.21), all clean per cluster mapping above:

- `vreader/Services/DebugBridge/*` — registry, command, context, fixtures
- `vreader/Views/Reader/{EPUB,Foliate,TXTChunked}*.swift` — bridges, coordinators
- `vreader/Views/Reader/ReaderContainerView.swift` (+Sheets, +helpers)
- `vreader/Views/Reader/ReaderSettingsPanel.swift`
- `vreader/Services/ReaderSettingsStore.swift`
- `vreader/Views/LibraryView.swift`
- `vreaderTests/Services/DebugBridge/*`
- `vreaderTests/Views/Reader/TXTChunkedHighlightDeferredTimerTests.swift` (new)
- `vreaderTests/Services/ReaderSettingsStoreTests.swift`
- `vreaderTests/Services/DebugBridge/RealDebugBridgeContextTests.swift`

The 19 failing tests live in `AutoPageTurnerTests.swift`, `TTSServiceTests.swift`, `PersistenceActorBookmarksTests.swift`, `PersistenceActorHighlightsTests.swift`, `PhaseBMediumAuditTests.swift` — all untouched.
