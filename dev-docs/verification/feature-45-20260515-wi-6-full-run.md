---
kind: feature
id: 45
status_target: DONE
commit_sha: 3753d2a3e21114717b9dbde11d405442658e03be
app_version: 3.21.69 (build 346)
date: 2026-05-15
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.5
build_configuration: Debug
backend: n/a (XCUITest harness against in-simulator app + DebugBridge URL scheme)
result: partial
---

# Feature #45 — WI-6 first-real-run of the named Verification test plan

## Why this evidence file exists

WI-6 (PR #692, commit `3753d2a`) shipped `TestPlans/Verification.xctestplan` and `TestPlans/All.xctestplan`. The Verification plan selects 25 `test_verify_*` per-method identifiers across the 13 Verification XCTestCase classes. Pre-Bug-#192 the entire 13-class suite returned `Executed 0 tests` + `TEST SUCCEEDED` (vacuous pass) because the methods used a plain `verify_*` prefix that XCTest skips. This is the **first end-to-end run** of all 13 classes via the named flag.

The run is intentionally documented here rather than under `status_target: VERIFIED`, because Feature #45's row note says: "VERIFIED status depends on Gate 5 final acceptance evidence file once those unsampled classes are sampled clean." Two product failures (#28, #29) and five XCTSkip-gated classes (#11, #21, #37, #40, #41) prevent a clean `VERIFIED` flip this iteration. Row stays at `DONE`.

## Acceptance criteria

| # | Criterion (from Feature #45 row + WI-6 plan v3 §Gate 5) | Observed | Pass/fail |
|---|---|---|---|
| 1 | `xcodebuild test -scheme vreader -testPlan Verification -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` is recognized by the toolchain (no "test plan not found" error) and dispatches a non-zero test count. | Plan recognized; `Executed 25 tests` logged. | **pass** |
| 2 | Membership exact: `selectedTests` JSON parses to exactly 25 identifiers, and `xcodebuild test` actually runs exactly 25 invocations. | `python3 -c "import json; print(len(json.load(open('TestPlans/Verification.xctestplan'))['testTargets'][0]['selectedTests']))"` → `25`. Runner reported `Executed 25 tests`. | **pass** |
| 3 | No-flag default invocation (`xcodebuild test -scheme vreader -only-testing:vreaderTests/DebugFixtureCatalogTests`) still uses the All plan. | DebugFixtureCatalogTests: 9 tests passed via no-flag invocation. | **pass** |
| 4 | `xcodebuild -showTestPlans -scheme vreader` lists both `All` and `Verification`. | Both listed. | **pass** |
| 5 | All 13 Verification classes either PASS, XCTSkip on documented capability/fixture/env-var guard, or FAIL with a filed-bug citation. | 6 classes PASS (10 methods), 5 classes all-XCTSkip (10 methods), 2 classes FAIL (Feature28 + Feature29, filed as Bug #194 + #195). | **partial** |
| 6 | Wall-clock under the 8-minute budget. | 408 s ≈ 6 min 48 s. | **pass** |

Overall: 5/6 criteria pass. Criterion 5 is partial: the 2 product failures are real bugs filed for the bug-fix cron, and the 5 all-skip classes need their per-test fixture/env-var guards lifted before they can produce real PASS signals.

## Per-class results

Total: **Executed 25 tests, with 13 tests skipped and 2 failures (0 unexpected) in 407.956 seconds**.

| Class (file) | Methods | Pass | XCTSkip | Fail | Notes |
|---|---|---|---|---|---|
| Feature11EPUBHighlightVerificationTests | 2 | ? | ? | 0 | Per-class breakdown not captured in the head/tail of the run log; safe inference from totals: contributes to the all-skip pool. Re-verify by isolating `-only-testing:vreaderUITests/Feature11EPUBHighlightVerificationTests`. |
| Feature21PaginatedModeVerificationTests | 2 | ? | ? | 0 | As above — likely all-skip. Re-verify isolated. |
| Feature23TXTTocVerificationTests | 2 | 2 | 0 | 0 | Confirmed pass: `Executed 2 tests, with 0 failures` at 26.4 s. |
| Feature27ReplacementRulesVerificationTests | 1 | 1 | 0 | 0 | Confirmed pass: `Executed 1 test, with 0 failures` at 10.5 s. |
| Feature28ChineseConversionVerificationTests | 2 | 0 | 1 | 1 | **FAIL** at line 56 — "Could not find section header 'Chinese Text' in settings panel after 6 swipes". Filed as **Bug #194** (GH #694). |
| Feature29WebDAVVerificationTests | 2 | 0 | 1 | 1 | **FAIL** at line 67 — "WebDAV Server URL field should be visible in WebDAV settings". Filed as **Bug #195** (GH #695). |
| Feature31AutoPageTurnVerificationTests | 2 | 2 | 0 | 0 | Confirmed pass: `Executed 2 tests, with 0 failures` at 32.4 s. |
| Feature34CollectionsVerificationTests | 2 | 2 | 0 | 0 | Confirmed pass: `Executed 2 tests, with 0 failures` at 49.5 s. |
| Feature35AnnotationsExportVerificationTests | 2 | 2 | 0 | 0 | Confirmed pass: `Executed 2 tests, with 0 failures` at 21.0 s. |
| Feature36OPDSVerificationTests | 2 | 1 | 1 | 0 | Confirmed: `Executed 2 tests, with 1 test skipped and 0 failures` at 18.4 s. The skip is `test_verify_feature_36_opds_browse_with_live_fixture` (no `CI_OPDS_URL` env var). Surface-check test passes. |
| Feature37PerBookSettingsVerificationTests | 2 | 0 | 2 | 0 | `Executed 2 tests, with 2 tests skipped` at 29.4 s — both methods XCTSkipped on prerequisite/capability gates. Re-verify needed to confirm whether skips are genuine or harness bugs. |
| Feature40TTSSentenceHighlightVerificationTests | 2 | 0 | 2 | 0 | `Executed 2 tests, with 2 tests skipped` at 46.0 s — TTS fixture / capability gate. |
| Feature41TTSAutoScrollVerificationTests | 2 | 0 | 2 | 0 | `Executed 2 tests, with 2 tests skipped` at 46.2 s — TTS fixture / capability gate. |
| **Total** | **25** | **10** | **13** | **2** | |

The 6 confirmed-pass classes (Feature23/27/31/34/35/36) account for 10 PASSed methods. The 5 all-skip classes (Feature11/21/37/40/41) plus Feature28/29 (1 skip each) plus Feature36 (1 skip) account for the 13 skips. Feature28/29 contribute the 2 failures.

## Commands run

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
    -project vreader.xcodeproj -scheme vreader \
    -testPlan Verification \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    2>&1 | tee /tmp/feature-45-wi-6-first-run.log
```

Membership verification:

```bash
python3 -c "import json; print(len(json.load(open('TestPlans/Verification.xctestplan'))['testTargets'][0]['selectedTests']))"
# → 25

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project vreader.xcodeproj -scheme vreader -showTestPlans
# → All
# → Verification
```

No-flag default verification:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
    -project vreader.xcodeproj -scheme vreader \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -only-testing:vreaderTests/DebugFixtureCatalogTests
# → Executed 9 tests, with 0 failures
```

## Observations

- **The named test plan works end-to-end for the first time.** Pre-Bug-#192, the entire 13-class suite was vacuous (Executed 0 tests, TEST SUCCEEDED). Bug #192's rename + WI-6's plan together close the gap: the harness now runs and reports real PASS/SKIP/FAIL signals. Feature #45's foundational contract is fulfilled.
- **Two real product failures surfaced** (Feature28, Feature29) and were filed as Bug #194 + #195. Both are filed at severity:medium because they're XCUITest-layer-only — the underlying production features are presumed functional (Feature28 Chinese conversion + Feature29 WebDAV backup are both `VERIFIED` via prior manual rounds); the failures are about the test's element queries diverging from current UI structure. Confirmation of "production is fine, test is stale" requires manual / CU verification of the actual UI surfaces.
- **Five classes are entirely XCTSkip-gated** (Feature11, 21, 37, 40, 41). The 8 skipped methods plus Feature28/29/36's individual skips total 13. Without per-class isolation runs, the all-skip classes' skips look indistinguishable from "tests passed" in the aggregate — this is exactly the kind of vacuous signal Bug #192 was about, except now scoped to per-class XCTSkip guards instead of class-wide method discovery. Each all-skip class needs an isolated run to determine whether the skip is a legitimate capability/fixture gate (e.g., AZW3 TTS requires a fixture that doesn't ship in Debug) or a stale guard.
- **Wall-clock 408 s** for the 25-method plan is within the 8-minute Gate 5 budget but the bulk is XCTSkip overhead (each XCTSkip still goes through full app launch + setUp + tearDown). If/when the all-skip classes start producing real signals, expect total wall-clock to grow.
- **Membership-drift safety**: the JSON-parse check `python3 -c "..." == 25` is the regression guardrail. If a new `test_verify_*` method is added to one of the 13 classes without updating `TestPlans/Verification.xctestplan`, the next verification run's actual count will diverge from 25 and Gate 5 §2 will catch it.

## Artifacts

- Full `xcodebuild test -testPlan Verification` log: transient at `/tmp/feature-45-wi-6-first-run.log`; not committed (large).
- GH #694 — Bug #194 filing (Feature #28 verify failure).
- GH #695 — Bug #195 filing (Feature #29 verify failure).
- WI-6 audit log: `.claude/codex-audits/feat-feature-45-wi-6-named-test-plan-selector-audit.md`.
- Plan: `dev-docs/plans/20260513-feature-45-verification-harness-sweep.md` (WI-6 section v3).
- Prior partial sample (4 classes): `dev-docs/verification/feature-45-20260515-post-bug192-batch.md`.

## Status

Feature #45 stays at `DONE` — not yet `VERIFIED`. Outstanding work to reach `VERIFIED`:

1. Isolate-run Feature11 + Feature21 to capture their pass/skip/fail breakdown (currently inferred only from totals).
2. Investigate the 5 all-skip classes (Feature11, 21, 37, 40, 41) — for each, determine whether each method's XCTSkip is a legitimate capability/fixture gate or a stale guard. File per-class follow-ups as bugs where the skip is stale.
3. Wait for Bug #194 + #195 fixes (bug-fix cron picks them up). Once those land, re-run `-testPlan Verification` and re-verify Feature28 + Feature29 pass.
4. Decide a clean cutoff for `VERIFIED`: the contract says "13 of 15 simulator-automatable backlog items have XCUITest + DebugBridge recipes" — that contract is already met (13 classes exist + the named plan dispatches them). What's not met is "every class produces real PASS or documented-skip evidence." A future iteration should write a smaller per-class evidence file documenting each all-skip class's skip rationale, then flip `DONE` → `VERIFIED`.
