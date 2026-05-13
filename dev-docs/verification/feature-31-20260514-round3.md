---
kind: feature
id: 31
status_target: VERIFIED
commit_sha: 75b6a27ace4d7b09da5074b86d4e6e9fcd44b54e
app_version: 3.21.21 (build 298)
date: 2026-05-14
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.5
build_configuration: Debug
backend: n/a
result: partial
---

# Feature #31 — Auto page turning — round-3 (live advancement BLOCKED on fixture)

Round-3 attempted the deferred "live multi-page advancement" slice from
rounds 1-2. Result: still blocked on fixture limits, NOT on code.
Status stays `DONE`. No new bug filed — the limit is a known
documented-in-row-Notes fixture issue, not a regression.

## Acceptance criteria

| # | Criterion | Observed | Pass/Fail |
|---|-----------|----------|-----------|
| 1 | `AutoPageTurner` state machine + timer reschedule + cancellation | 14 unit tests pass (rounds 1-2). Re-verified by `xcodebuild test -only-testing:vreaderTests` clean after bug #175 fix (this morning) — 801 tests in 84 suites pass. | **PASS** (test-covered) |
| 2 | Reader Settings UI: Paged toggle → Auto Page Turn toggle → Interval slider; settings persist | XCUITest verified end-to-end round-2 (`feature-31-20260508.md`). | **PASS** (round-2) |
| 3 | Capability gating: only MD shows Auto Page Turn toggle (bug #157 fix) | Round-2 confirmed visually for TXT. Code-confirmed for PDF/EPUB/AZW3 via `FormatCapabilities` enum. | **PASS** (code-confirmed) |
| 4 | Live multi-page advancement — open paged MD book, enable auto-page-turn, wait, observe page advance | **BLOCKED** — see "Round-3 attempt" below. | **DEFERRED (fixture)** |

## Round-3 attempt — what was tried

1. Build at v3.21.21 (commit `75b6a27`), install, terminate any running instance.
2. Pre-inject UserDefaults BEFORE launch (so the seed-flow doesn't wipe them):
   ```bash
   xcrun simctl spawn $SIMID defaults write com.vreader.app readerAutoPageTurn -bool true
   xcrun simctl spawn $SIMID defaults write com.vreader.app readerAutoPageTurnInterval -float 3.0
   ```
   Confirmed both persist (read-back: `1` and `3`).
3. Launch `--uitesting --seed-md-toc` (NO `--reset-preferences` — that wipes the defaults).
4. Open `mdTOC` fixture via `vreader-debug://open?bookId=md:00...c0c001:678`.
   - **Snapshot confirms reader open**: `currentBookId: "md:...c0c001:678"`, `format: "md"`, `lastError: null`.
5. Bump `fontSize` to 48 via `vreader-debug://theme?mode=light&fontSize=48`.
   - **Snapshot confirms `fontSize: 48`** persisted in UserDefaults.

## Observations (round-3 specific findings)

- **MD reader opens in scroll mode by default, not paged**. The `--reader-default-layout=paged` launch arg (feature #45 WI-4c-a) sets `readerEPUBLayout` — that's an EPUB-only key. MD reads `readerReadingMode` instead. No DebugBridge URL exists today to switch MD into paged mode programmatically; the slice would need to go through the Reader Settings panel via XCUITest, which is independent UI-driving work outside this verify-cron iteration.
- **Font-size override doesn't visually re-render in scroll mode in the captured screenshot window**. `fontSize: 48` is in UserDefaults + DebugSnapshot reflects it, but the on-screen MD render still shows ~18pt text. Either (a) MD bridge doesn't re-render on `themeChanged` notification at this granularity, (b) the screenshot timing missed the re-render, or (c) the MD reader has its own font-size scale not driven by `TypographySettings.fontSize`. Not investigated further this round — out of scope for #31.
- **The mdTOC fixture (678 bytes) fits in one page** at 18pt scroll-mode render. Same blocker as Position Test's "1 page at 18pt" noted in round-2 — different fixture, same outcome.
- **`vreader-debug://open` interaction with `--reset-preferences`**: re-running open after `xcrun simctl spawn defaults write` while `--reset-preferences` was used left the reader stuck on the Library view. Without `--reset-preferences`, the open URL works correctly. The mechanism is not investigated further (probably a race between `--reset-preferences`'s UserDefaults wipe and the simctl-spawn write).

## Commands run

```bash
SIMID=1FAB9493-B97E-48F0-96C7-44A8E5AAA21E
APP_PATH=/Users/ll/Library/Developer/Xcode/DerivedData/vreader-hdhlhcqmxppsadhececcxeadpkvz/Build/Products/Debug-iphonesimulator/vreader.app

xcrun simctl terminate $SIMID com.vreader.app
xcrun simctl install $SIMID "$APP_PATH"
xcrun simctl spawn $SIMID defaults write com.vreader.app readerAutoPageTurn -bool true
xcrun simctl spawn $SIMID defaults write com.vreader.app readerAutoPageTurnInterval -float 3.0
xcrun simctl launch $SIMID com.vreader.app --uitesting --seed-md-toc

MD_KEY="md:0000000000000000000000000000000000000000000000000000000000c0c001:678"
xcrun simctl openurl $SIMID "vreader-debug://open?bookId=$MD_KEY"
xcrun simctl openurl $SIMID "vreader-debug://snapshot?dest=f31-r3-prelaunch-defaults.json"
xcrun simctl io $SIMID screenshot feature-31-r3-04-prelaunch-defaults-20260514.png

xcrun simctl openurl $SIMID "vreader-debug://theme?mode=light&fontSize=48"
xcrun simctl openurl $SIMID "vreader-debug://snapshot?dest=f31-r3-font48.json"
xcrun simctl io $SIMID screenshot feature-31-r3-05-font48-20260514.png
```

## Why no bug is filed

- The fixture limit is a documented test-asset constraint, not a regression.
- The MD scroll-vs-paged mode switching gap and `fontSize` re-render path are tangents to feature #31's contract — out of scope per scope guardrail.
- The `open?bookId=...` interaction with `--reset-preferences` + `simctl spawn defaults write` race is a harness quirk, not a production bug — production users never write defaults this way.

## What would unblock the VERIFIED flip

One of:

- **(a) A larger MD test fixture** that paginates to 2+ pages at default 18pt in paged-mode rendering. Could be a new seed flag (`--seed-md-multi-page` → 50+ paragraphs / 5+ KB MD), added through the same `TestSeeder.seedMDWithTOC` pattern. Test-fixture work, not a verify-cron task.
- **(b) A new DebugBridge URL to set `readerReadingMode=paged` for MD** (mirrors `--reader-default-layout=paged` for EPUB). Today no such URL exists; the only path is via Settings UI. DebugBridge / feature #45 territory, not a verify-cron task.
- **(c) Capability-gating Auto Page Turn further** (bug #157 option b — hide toggle when content is single-page). Would resolve the slice by definition, but is a code change with its own scope.

Recommendation: prioritize (a) — it's the minimum-risk path and unblocks `#31 VERIFIED` + future MD pagination verifications.

## Artifacts

- `dev-docs/verification/artifacts/feature-31-r3-01-t0-initial-20260514.png` — Library view (reader didn't open under the pre-defaults-injection sequence; documented finding).
- `dev-docs/verification/artifacts/feature-31-r3-02-retry-after-open-20260514.png` — Library view after re-firing `open` URL.
- `dev-docs/verification/artifacts/feature-31-r3-03-baseline-no-defaults-20260514.png` — confirms open URL DOES work without the simctl spawn defaults dance interleaved with `--reset-preferences`.
- `dev-docs/verification/artifacts/feature-31-r3-04-prelaunch-defaults-20260514.png` — reader opens correctly when defaults are written BEFORE launch (the success state for opening; auto-page-turn still doesn't fire because MD is single-page).
- `dev-docs/verification/artifacts/feature-31-r3-05-font48-20260514.png` — fontSize=48 in UserDefaults + snapshot, but visual render unchanged at single-page size.

## Verdict

**PARTIAL** — same blocker as rounds 1-2 ("fixture limit"). Status stays `DONE`. Append the round-3 attempt to feature #31's Notes column documenting (a) the simctl-spawn-defaults-before-launch recipe that works for opening MD with custom UserDefaults, (b) the persistent fixture-size blocker, (c) the three paths that would unblock VERIFIED (none of which are verify-cron scope).
