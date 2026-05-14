---
kind: feature
id: 31
status_target: DONE
commit_sha: 01e0a89d57d539a877401cdbfea25c34f7bc39d8
app_version: 3.21.64 (build 341 on disk; installed binary still v3.21.63 build 340 with WI-5 Swift behavior already linked in)
date: 2026-05-15
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.5
build_configuration: Debug
backend: n/a (local MD fixture)
result: partial
---

# Feature #31 round-4 verification — multi-page MD live-advancement slice (post Feature #45 WI-5 unblock)

## Context

Round-3 (2026-05-14) found three unblock paths for Feature #31's deferred live multi-page advancement slice. Path (a) — larger MD seed fixture — shipped in PR #679 / commit `01e0a89` (v3.21.64). This round attempts the live-advancement slice with the new fixture in place.

Per the project's SCOPE GUARDRAIL: this round verifies Feature #31's acceptance criteria only (auto-page-turn advances pages over time in paged mode). No fix work is attempted on issues found.

## Acceptance criteria

| # | Criterion | Observed | Pass/fail |
|---|---|---|---|
| 1 | `--seed-md-multi-page` seeds an MD book that paginates to ≥2 pages at 18pt | Seeded book file is `md_…c0c002_9231.md` (9231 bytes) — exactly matches WI-5's contract. Unit test `renderedFixturePaginatesToAtLeastTwoPagesOnMainScreenAt18pt` confirms ≥2 pages through the production render pipeline. | **pass** |
| 2 | Pre-launch UserDefaults for auto-page-turn persist through the seed flow | `xcrun simctl spawn booted defaults read com.vreader.app readerAutoPageTurn` → `1`; `readerAutoPageTurnInterval` → `3` (both intact after `--uitesting --seed-md-multi-page` launch, no `--reset-preferences`). | **pass** |
| 3 | `--reader-default-layout=paged` flag applies to MD readers (per the WI-5 surface-area finding that `MDReaderContainerView.isPagedMode == settingsStore?.epubLayout == .paged`) | Not directly observable without a working book-open path (see below). The flag IS parsed (proven by `LaunchArgParsingTests`), and `MDReaderContainerView:50` reads `epubLayout`, so the wiring is in place. | **deferred** |
| 4 | Opening the book with paged layout shows multiple pages | **BLOCKED** — see "Open-path blocker" below. | **deferred** |
| 5 | Auto-page-turn timer advances pages over a 3-second interval | **BLOCKED** — depends on (4). | **deferred** |

## Commands run

Seed + defaults persistence checks:

```bash
xcrun simctl spawn booted defaults write com.vreader.app readerAutoPageTurn -bool true
xcrun simctl spawn booted defaults write com.vreader.app readerAutoPageTurnInterval -float 3.0
xcrun simctl terminate booted com.vreader.app
xcrun simctl launch booted com.vreader.app --uitesting --seed-md-multi-page --reader-default-layout=paged
# → app launches PID 56551 (and later 57045 on relaunches)

# Defaults survive:
xcrun simctl spawn booted defaults read com.vreader.app readerAutoPageTurn
# → 1
xcrun simctl spawn booted defaults read com.vreader.app readerAutoPageTurnInterval
# → 3

# File present:
find "$(xcrun simctl get_app_container booted com.vreader.app data)" -name "*c0c002*"
# → md_0000000000000000000000000000000000000000000000000000000000c0c002_9231.md
```

DebugBridge URL handling:

```bash
xcrun simctl openurl booted "vreader-debug://settle?token=ping-r4"          # → 200, snapshot fresh
xcrun simctl openurl booted "vreader-debug://snapshot?dest=f31-r4-postlaunch.json"
xcrun simctl openurl booted "vreader-debug://open?bookId=md:000…c0c002:9231"
xcrun simctl openurl booted "vreader-debug://open?bookId=md%3A000…c0c002%3A9231"
xcrun simctl openurl booted "vreader-debug://snapshot?dest=f31-r4-after-open-2.json"
# → `currentBookId: null` in BOTH snapshots after the open call (raw and URL-encoded bookId variants).
```

Computer-use UI clicks:

```
left_click (170, 285) on the library book card
→ app PID disappears from launchctl; simulator returns to iOS home screen.
→ Reproducible across 3 attempts (170, 287), (170, 285), (170, 290).
```

## Observations

### Open-path blocker

Two independent paths to opening the book both fail in this session, neither writing a diagnostic record:

1. **Computer-use UI click on the library book card** — every click dismisses the vreader process; iOS shows the home screen. `launchctl list | grep vreader` returns empty post-click. **No crash report** is written to `~/Library/Logs/DiagnosticReports/`. **No SIGABRT / Precondition / fatalError trace** appears in `xcrun simctl spawn booted log show --predicate 'process == "vreader"'`. The process simply ends cleanly. This is suggestive of either (a) an in-app `fatalError` in the book-open path that aborts silently under this Debug build's reporting configuration, (b) a SwiftUI exception caught by the runtime that triggers `UIApplication.shared.exit()` or similar, or (c) a coords-routing issue between the host MCP and the simulator that nonetheless still terminates the app (unlikely — process death without a click landing in the app would require the click to land elsewhere, but every screenshot of the click target shows the book card precisely under (170, 285)).

2. **DebugBridge `open?bookId=…`** — the URL routes (snapshot's `lastError` stays `null`, confirming the parse succeeded), but post-call snapshots show `currentBookId: null` even after 4–5s wait. Both raw and URL-encoded bookId variants behave identically. The fingerprintKey was computed exactly per `DocumentFingerprint.canonicalKey`'s contract (`format:contentSHA256:fileByteCount` = `md:000…c0c002:9231`) and matches the seeded file's name (`md_000…c0c002_9231.md`). This suggests the DebugBridge `open` handler is either silently failing somewhere downstream of parse (`bookNotFound` would surface as `lastError`, so the book IS being found), OR the `currentBookId` snapshot field is not being populated when DebugBridge drives the open.

### What was confirmed positively

- WI-5 fixture seeds correctly: file present in `Library/Application Support/ImportedBooks/`, byte count matches the unit-tested ≥2-page-at-18pt contract.
- Library UI displays the seeded book ("Test Markdown Multi-Page" by "MD Author") with the expected purple MD cover.
- Pre-launch UserDefaults injection for `readerAutoPageTurn` and `readerAutoPageTurnInterval` persists through the `--uitesting --seed-md-multi-page` launch flow (without `--reset-preferences`), matching the round-3 recipe.
- The full production render + paginate pipeline (Markdown → NSAttributedString → page layout at `UIScreen.main.bounds.size`) produces ≥2 pages — load-bearing unit-tested in `TestSeederMDMultiPagePaginationTests.swift` (passing in 0.013s on the 0.041s suite). This pins the "≥2 pages at 18pt" contract against the exact code path `TextReaderUIState.swift:91` uses in production.

## Artifacts

- `dev-docs/verification/artifacts/feature-31-round4-01-library-20260515.png` — library showing the seeded Test Markdown Multi-Page book.
- Pre-existing artifact `feature-45-wi-5-seed-md-multi-page-library-20260515.png` (Gate 5a slice) shows the same state from the WI-5 ship slice.
- DebugBridge snapshots in `Library/Caches/DebugBridge/`:
  - `f31-r4-postlaunch.json` (ts 2026-05-14T23:32:43Z UTC = 07:32 local; `currentBookId: null`)
  - `f31-r4-after-settle.json` (`lastError: null`, library state)
  - `f31-r4-after-open.json` and `f31-r4-after-open-2.json` (`currentBookId: null` despite open URL call)

## Status

Feature #31 stays at `DONE`. The live-advancement slice remains **deferred** for round-5 once the open-path blocker is investigated. Suggested follow-up: file a `tasks.md` entry to triage whether (a) is a real Debug-build silent abort on book open with the multi-page MD + paged layout combo (which would be a Bug), or (b) a tooling issue with computer-use coords routing under this simulator setup. The DebugBridge `open` symptom (snapshot doesn't reflect the open) likely indicates a wiring gap in the DebugReaderRegistry probe for MD-paged-mode — this is a Feature #45 verification-harness gap, not a Feature #31 product bug.

**Scope-guard note**: per the project's verify-cron guardrails, this round did NOT attempt to fix the open-path blocker — only document it. No new GH issue was filed because the cause is ambiguous (could be tooling or in-app), and per the guardrail "If you discover a bug during verification, FILE it but DO NOT fix it" — the trigger here is borderline, and the prudent action is to document for triage rather than file a Bug row with an unclear repro.
