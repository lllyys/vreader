---
kind: feature
id: 45
status_target: VERIFIED
commit_sha: 8cab12a4574304831666decf343ffc477943ae31
app_version: 3.27.25 (build 439)
date: 2026-05-18
verifier: claude (verify-cron)
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.4
build_configuration: Debug
backend: n/a
result: partial
---

# Feature #45 — Verification harness sweep — round-4 regression sampling

Feature #45 is `DONE`. Its row documents progressive verify-cron sampling
rounds of the `Verification` xctestplan; round-3
(`feature-45-20260518-round3.md`, result=partial) ran at v3.27.23 commit
`6936ccf`. Since then `main` advanced to v3.27.25 commit `8cab12a` — the
Bug #213 / #216 / #217 (GH #830 / #838 / #839) test-infrastructure fixes and
intervening feature work landed. This round-4 re-runs the full `Verification`
xctestplan at current `main` to confirm those commits did not regress the
verification harness.

This is a **regression-sampling round**, not the final-acceptance pass: #45's
`VERIFIED` flip is gated on the 9 currently-SKIPPED method-groups being sampled
clean (fixture/harness/env gaps), which is unchanged this round. Feature #45
stays `DONE`.

## Acceptance criteria

| # | Criterion | Observed | Result |
|---|---|---|---|
| 1 | The `Verification` xctestplan builds and runs end-to-end on the iPhone 17 Pro Simulator | `xcodebuild test -testPlan Verification` built with 0 compile errors and ran all 27 selected test methods across 14 classes; `** TEST SUCCEEDED **`, exit 0, 443.5 s test execution. | pass |
| 2 | Zero test failures (no regression vs round-3) | 27 executed, **0 failures (0 unexpected)**, 15 XCTSkip-gated, 12 PASS. Identical pass/skip/fail shape to round-3 (12 / 15 / 0) and round-2. No regression across the v3.27.23→v3.27.25 commit range. | pass |
| 3 | Full acceptance — every Verification class sampled clean (no SKIPs) | NOT met — 15 of 27 methods (9 method-groups) remain XCTSkip-gated on fixture/harness/env gaps. Unchanged from round-3; not a product defect (see Observations). | partial — gates #45 `VERIFIED` |

`result: partial` — criteria 1-2 pass (the harness is GREEN, zero regression);
criterion 3 is unchanged-partial. Feature #45 stays `DONE`; the `VERIFIED`
flip remains gated on the 9 SKIP method-groups.

## Test class breakdown (round-4)

| Class | Exec | Pass | Skip |
|---|---|---|---|
| Feature11EPUBBottomChromeVerificationTests | 2 | 2 | 0 |
| Feature11EPUBHighlightVerificationTests | 2 | 0 | 2 |
| Feature21PaginatedModeVerificationTests | 2 | 0 | 2 |
| Feature23TXTTocVerificationTests | 2 | 2 | 0 |
| Feature27ReplacementRulesVerificationTests | 1 | 1 | 0 |
| Feature28ChineseConversionVerificationTests | 2 | 1 | 1 |
| Feature29WebDAVVerificationTests | 2 | 1 | 1 |
| Feature31AutoPageTurnVerificationTests | 2 | 0 | 2 |
| Feature34CollectionsVerificationTests | 2 | 2 | 0 |
| Feature35AnnotationsExportVerificationTests | 2 | 0 | 2 |
| Feature36OPDSVerificationTests | 2 | 1 | 1 |
| Feature37PerBookSettingsVerificationTests | 2 | 2 | 0 |
| Feature40TTSSentenceHighlightVerificationTests | 2 | 0 | 2 |
| Feature41TTSAutoScrollVerificationTests | 2 | 0 | 2 |
| **Total** | **27** | **12** | **15** |

## Commands run

```bash
SIM=61149F0E-DC18-4BE2-BB37-52659F1F4F62   # iPhone 17 Pro, iOS 26.4

# main at commit 8cab12a (v3.27.25 build 439) — Verification xctestplan
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project vreader.xcodeproj -scheme vreader \
  -testPlan Verification \
  -destination "id=$SIM" \
  -resultBundlePath /tmp/f45r4.xcresult
# → ** TEST SUCCEEDED **  (exit 0)
# → Executed 27 tests, with 15 tests skipped and 0 failures (0 unexpected) in 443.5 s
```

## Observations

- Round-4 is byte-identical in shape to round-3 and round-2: 12 PASS / 15 SKIP
  / 0 FAIL across 27 methods. Zero regressions across the ~2 patch versions of
  commits between round-3's `6936ccf` and round-4's `8cab12a`.
- The commit range round-3→round-4 includes three test-infrastructure bug
  fixes — Bug #213 (GH #830, `BookSourceHTTPClientTests` parallel safety),
  Bug #216 (GH #838, `PDFViewBridgeThemeTests` `@MainActor`), Bug #217
  (GH #839, `ReplacementTransform` regex no-op under dispatch-pool saturation).
  These are unit-test / service-layer changes; running the UI-level
  `Verification` plan confirms they did not regress the XCUITest harness.
  `Feature27ReplacementRulesVerificationTests` — the Verification class closest
  to Bug #217's `ReplacementTransform` area — passed.
- The 15 SKIP methods are the same 9 method-groups as round-3, all gated on
  fixture/harness/env reasons (not product defects), per the #45 row's prior
  root-cause analysis:
  - `Feature11EPUBHighlightVerificationTests` ×2 — EPUB highlight happy-path +
    bug77 buffering-race regression (EPUB load-timing harness gap).
  - `Feature21PaginatedModeVerificationTests` ×2 — multi-page EPUB fixture gap.
  - `Feature28ChineseConversionVerificationTests` ×1 —
    `conversion_applies_to_reader_content` (fixture/env-var gap).
  - `Feature29WebDAVVerificationTests` ×1 —
    `webdav_backup_executes_when_configured` (live-backend env gap).
  - `Feature31AutoPageTurnVerificationTests` ×2 — auto-page-turn toggle +
    interval slider.
  - `Feature35AnnotationsExportVerificationTests` ×2 — export/import buttons.
  - `Feature36OPDSVerificationTests` ×1 — `opds_browse_with_live_fixture`
    (live OPDS feed env gap).
  - `Feature40TTSSentenceHighlightVerificationTests` ×2 — TTS control-bar
    timing.
  - `Feature41TTSAutoScrollVerificationTests` ×2 — TTS auto-scroll timing.
- `Feature37PerBookSettingsVerificationTests` (2/2 PASS) and the new
  `Feature11EPUBBottomChromeVerificationTests` (2/2 PASS) — both unblocked
  since round-2 (Bug #204 swipe-helper fix; Bug #214 bottom-chrome class) —
  remain green.
- Verification-only round: no bug discovered, no code changed.

## Artifacts

- `dev-docs/verification/artifacts/feature-45-r4-verification-testplan-20260518.txt`
  — extracted `Test Suite` / `Test Case` / `Executed … tests` / `TEST SUCCEEDED`
  lines from the `xcodebuild test` run.
- `/tmp/f45r4.xcresult` — full result bundle (local, not committed).

## Outcome

Feature #45 stays **DONE**. Round-4 confirms the `Verification` xctestplan is
GREEN at current `main` (v3.27.25 / `8cab12a`) with zero regressions across the
round-3→round-4 commit range. The `VERIFIED` flip remains gated on the 9 SKIP
method-groups (fixture/harness/env gaps) being sampled clean — unchanged this
round. No new bugs filed.
