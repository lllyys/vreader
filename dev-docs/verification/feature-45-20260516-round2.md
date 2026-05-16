---
kind: feature
id: 45
status_target: VERIFIED
commit_sha: a6103e5094c28af95851699fb4bb826428608a66
app_version: 3.24.6 (build 401)
date: 2026-05-16
verifier: claude (verify-cron)
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.5
build_configuration: Debug
backend: n/a (XCUITest -testPlan Verification)
result: partial
---

# Feature #45 — Verification harness sweep (round-2 sampling, post-v3.22.20)

Re-ran `Verification.xctestplan` against merged `main` at v3.24.6 (commit
`a6103e5`) to check whether any of the 5 fully-gated classes (#11, #21,
#37, #40, #41) flipped clean across the 40+ commits since the prior
sampling at v3.22.20 (`feature-45-20260516-sampling.md`).

## Result summary

`Executed 25 tests, with 13 tests skipped and 0 failures (0 unexpected) in 410.086 seconds`

**12 PASSED**, **13 SKIPPED**, **0 FAILED**. Identical shape to the
v3.22.20 round. No regressions, no progressions.

## Per-class results

| Class | Methods | Pass | Skip | Skip reason |
|---|---|---|---|---|
| Feature11EPUBHighlightVerificationTests | 2 | 0 | 2 | "EPUB reader did not load" — XCUITest wait-for-ready condition times out at ~30s per method |
| Feature21PaginatedModeVerificationTests | 2 | 0 | 2 | "Reading Mode picker absent" / "readingProgressLabel not present" — mini-epub3 fixture paginates to 1 page; no multi-page EPUB fixture in DebugFixtureCatalog |
| Feature23TXTTocVerificationTests | 2 | **2** | 0 | — |
| Feature27ReplacementRulesVerificationTests | 1 | **1** | 0 | — |
| Feature28ChineseConversionVerificationTests | 2 | 1 | 1 | "CJK TXT fixture not present in DebugFixtureCatalog" — fixture gap |
| Feature29WebDAVVerificationTests | 2 | 1 | 1 | "CI_WEBDAV_URL / USERNAME / PASSWORD env vars not set" — env dependency |
| Feature31AutoPageTurnVerificationTests | 2 | **2** | 0 | — |
| Feature34CollectionsVerificationTests | 2 | **2** | 0 | — |
| Feature35AnnotationsExportVerificationTests | 2 | **2** | 0 | — |
| Feature36OPDSVerificationTests | 2 | 1 | 1 | "CI_OPDS_URL env var not set" — env dependency |
| Feature37PerBookSettingsVerificationTests | 2 | 0 | 2 | "Per-book toggle not found" — Bug #204 / GH #746 (harness gap) |
| Feature40TTSSentenceHighlightVerificationTests | 2 | 0 | 2 | "TTS control bar didn't appear within 15s even with --tts-test-mode" |
| Feature41TTSAutoScrollVerificationTests | 2 | 0 | 2 | "TTS control bar didn't appear within 15s even with --tts-test-mode" |

## Comparison to prior round (v3.22.20)

| Metric | v3.22.20 (round-1) | v3.24.6 (round-2) | Change |
|---|---|---|---|
| Passed | 12 | 12 | 0 |
| Skipped | 13 | 13 | 0 |
| Failed | 0 | 0 | 0 |
| Total duration | 413.025 s | 410.086 s | -2.9 s |

Every class produced the same pass/skip count and the same skip reasons.
The 5 fully-skipped classes (#11, #21, #37, #40, #41) and the 4
partial-skipped classes (#28, #29, #36) remain blocked by the same
fixture / env / harness gaps documented in round-1.

## What flipped from this run

Nothing. Same 12-clean / 13-skipped status.

## What's still gated for VERIFIED flip

**5 classes fully gated (no methods passing):**
1. **#11 EPUB highlight** — `Feature11EPUBHighlightVerificationTests`.
   XCUITest's wait for EPUB reader-ready state exceeds the timeout. Not
   filed as a bug — prior round flagged "Worth a future investigation,
   possibly bug-class. Filing skipped." This round: no new diagnostic
   evidence to escalate; still a harness-conditions issue.
2. **#21 Paginated mode** — `Feature21PaginatedModeVerificationTests`.
   No multi-page EPUB fixture. Same fixture-class gap blocking Feature
   #25 round-6 and Feature #31 round-3. Cross-row documented.
3. **#37 Per-book settings** — `Feature37PerBookSettingsVerificationTests`.
   Bug #204 / GH #746 already filed (harness gap). Pending harness fix.
4. **#40 TTS sentence highlight** — `Feature40TTSSentenceHighlightVerificationTests`.
   TTS control bar appearance timing. Could be product slowness or
   `--tts-test-mode` wiring. Not filed as a bug (same precedent as
   prior round).
5. **#41 TTS autoscroll** — `Feature41TTSAutoScrollVerificationTests`.
   Shares root cause with #40. Same skip reason.

**4 classes with partial gating (1-of-2 methods clean):**
- **#28 Chinese conversion** — 1 method passes; conversion-applies test
  needs a CJK TXT fixture (war-and-peace.txt is English only).
- **#29 WebDAV** — 1 method passes; backup-executes test needs
  `CI_WEBDAV_URL` env var set.
- **#36 OPDS** — 1 method passes; live-fixture test needs `CI_OPDS_URL`
  env var set.

## Commands run

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project vreader.xcodeproj -scheme vreader \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -testPlan Verification 2>&1 | tee /tmp/feature-45-verify-20260516-round2.log
```

Total runtime: 410 s (~7 minutes). Single iPhone 17 Pro Simulator booted instance.

## Observations

- The 40+ commits between v3.22.20 and v3.24.6 (including Feature #60
  WI-1 through WI-7c3, Bug #710 PDF dark-theme fix, Bug #202/#203/#207
  Foliate/highlight fixes) did not touch the 5 gated classes' code
  paths. Same gates apply.
- The verify-cron pattern (re-sample on each version bump to detect
  regressions) is producing diminishing returns for #45 specifically:
  the same skip-gates will keep firing until either the harness is
  fixed (Bug #204 for #37) or fixtures are added (multi-page EPUB for
  #21, CJK TXT for #28) or env vars are configured (#29 #36 not gating
  VERIFIED since they're 1-of-2).
- No new bugs filed this round. Filing thresholds: a class must show
  evidence beyond "XCTSkip with documented reason" to warrant a fresh
  bug row — i.e., a new failure mode, a regressed previously-passing
  method, or fresh root-cause analysis. None of those triggered here.

## Filing decisions

- **No new bug rows or GH issues filed** this round.
- **Feature #45 row Notes update**: add one-line round-2 entry noting
  same shape at v3.24.6.

## Artifacts

- `/tmp/feature-45-verify-20260516-round2.log` — full xcodebuild stdout
  (not committed; ephemeral diagnostic).
- Test run xcresult bundle: `~/Library/Developer/Xcode/DerivedData/vreader-hdhlhcqmxppsadhececcxeadpkvz/Logs/Test/Test-vreader-2026.05.16_11-43-45-+0800.xcresult`

## VERIFIED gate status

Still blocked. Path to flip remains:

1. Bug #204 fix (harness retry-budget for #37 per-book toggle) — already filed.
2. Multi-page EPUB fixture addition to DebugFixtureCatalog (blocks #21).
3. EPUB load-timing harness fix or product investigation (blocks #11).
4. TTS control-bar appearance timing investigation (blocks #40, #41).

Until those land, Feature #45 row stays at `DONE` with the round-1 +
round-2 sampling evidence files documenting the gate.
