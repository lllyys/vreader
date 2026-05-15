---
kind: feature
id: 45
status_target: IN PROGRESS
commit_sha: 9d63d8336cd1a3df04fd2d9116cd28e3eb02feaa
app_version: 3.21.67 (build 344)
date: 2026-05-15
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.5
build_configuration: Debug
backend: n/a (local + no live OPDS server for the SKIP case)
result: partial
---

# Feature #45 — post-Bug-192-fix Verification suite sampling

## Why this evidence file exists

Bug #192 (GH #686) was fixed in PR #688 (v3.21.67, commit 9d63d83) just before this verify-cron iteration. Pre-fix, the entire Verification suite returned `Executed 0 tests + TEST SUCCEEDED` (vacuous pass) because XCTest's default discovery requires `test_*` prefix and the 25 methods used plain `verify_*`. Post-fix, the methods are discoverable and produce real pass/skip/fail signals for the first time.

This evidence file captures a 4-class sampling run to characterize the post-fix state of the Verification suite and surface any newly-visible failures.

## Sample

Batch invocation:

```bash
xcodebuild test -project vreader.xcodeproj -scheme vreader \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:vreaderUITests/Feature27ReplacementRulesVerificationTests \
  -only-testing:vreaderUITests/Feature34CollectionsVerificationTests \
  -only-testing:vreaderUITests/Feature35AnnotationsExportVerificationTests \
  -only-testing:vreaderUITests/Feature36OPDSVerificationTests
```

Total wall-clock: 99.4s. Total tests: 7. Pass: 5. Skip: 1. Fail: 1.

## Per-class results

### Feature #27 (Replacement Rules) — PASS

| Test | Result | Time |
|---|---|---|
| `test_verify_feature_27_replacement_rule_ui_surface` | **PASS** | 12.4s |

First real XCUITest evidence for Feature #27. Replacement Rules UI surface is reachable and functional in headless sim.

### Feature #34 (Collections) — PASS

| Test | Result | Time |
|---|---|---|
| `test_verify_feature_34_create_collection_appears_in_sidebar` | **PASS** | 21.1s |
| `test_verify_feature_34_add_book_to_collection_filters_library` | **PASS** | 29.8s |

First real XCUITest evidence for Feature #34. Both critical UI flows verified.

### Feature #35 (Annotations Export) — PASS

| Test | Result | Time |
|---|---|---|
| `test_verify_feature_35_export_button_is_visible` | **PASS** | 10.7s |
| `test_verify_feature_35_import_button_is_visible` | **PASS** | 10.6s |

First real XCUITest evidence for Feature #35's UI surface. Both Export and Import buttons reachable.

### Feature #36 (OPDS) — 1 SKIP + 1 FAIL

| Test | Result | Time |
|---|---|---|
| `test_verify_feature_36_opds_browse_with_live_fixture` | SKIP | 3.6s (no live OPDS server in env) |
| `test_verify_feature_36_opds_catalog_ui_surface` | **FAIL** | 11.1s |

The fail is `XCTAssertTrue failed - OPDS catalogs view should show either the catalog list or the empty state` at `Feature36OPDSVerificationTests.swift:46`. Element-class lookups (`collectionViews`, `scrollViews`, `otherElements`) don't match SwiftUI's actual rendering (`List` → table, `VStack` → transparent in accessibility tree).

**Filed as Bug #193 (GH #689)**. NOT fixed this iteration per verify-cron scope guard.

## What this round verifies / what it changes

- Three features (#27, #34, #35) move from "vacuously-VERIFIED" (the pre-Bug-192 silent no-op) to "VERIFIED with real XCUITest evidence" for the first time. Their row notes' XCUITest claims are now genuinely backed.
- Feature #36 reverses: previously cited as "VERIFIED via WI-3 XCUITest" but the XCUITest claim was vacuous. The test now reveals an element-class mismatch (Bug #193). The feature row's VERIFIED status should be reassessed — manual / CU evidence may still hold, but the XCUITest gate is now contradicted.
- 9 of the 13 Verification classes are still unsampled in this iteration: #11, #21, #23, #28, #29, #31, #37, #40, #41. Future verify-cron iterations should run those individually and document results.

## Acceptance criteria

| # | Criterion | Observed | Pass/fail |
|---|---|---|---|
| 1 | Feature #45 WI-6 acceptance ("xcodebuild test -only-testing:vreaderUITests/Verification exits 0 in under 8 minutes") — now meaningful post-Bug-192-fix | 4-class sample: 99s total, 1 real failure surfaced (Feature36). The 8-minute budget is provisional; full 13-class run will take longer. | **partial** — meaningful for the first time; full-suite measurement deferred |
| 2 | At least one Verification class produces real pass evidence (proving the harness functions end-to-end) | Three classes (#27, #34, #35) produced real PASS evidence for 5 methods total. | **pass** |
| 3 | Any newly-visible failures filed as separate bugs (NOT fixed in verify-cron) | Bug #193 (GH #689) filed for Feature #36 element-class mismatch. | **pass** |

## Commands run

(See "Sample" section above for the batch invocation.)

For the specific Feature36 failure inspection:

```bash
grep -B2 -A8 "test_verify_feature_36_opds_catalog_ui_surface.*failed" /tmp/verify-post-bug192.log
```

Failure log excerpt:

```
t = 10.74s Checking existence of `"opdsEmptyState" Other`
t = 10.78s Checking existence of `"opdsCatalogList" ScrollView`
Feature36OPDSVerificationTests.swift:46: error: XCTAssertTrue failed - OPDS catalogs view should show either the catalog list or the empty state
t = 10.85s Tear Down
Test Case '...test_verify_feature_36_opds_catalog_ui_surface' failed (11.079 seconds).
```

## Observations

- The verify-cron loop closed within one session: Feature #45 WI-6 Gate-2 audit → discovered Bug #192 → fixed Bug #192 → re-ran harness → first real failure (Bug #193) found and filed. That diagnostic chain (Gate 2 → harness fix → harness reveals product bug) is the value the binding 6-gate workflow is supposed to deliver.
- The 5 PASSing tests are notable not because they suddenly started passing (they were always going to pass once discoverable), but because they validate that production code IS correct for those flows — the previous "vacuous VERIFIED" claims were directionally right, just vacuously supported.
- The 1 FAILing test (Feature #36) is a harness-vs-production mismatch. The accessibility IDs ARE wired in production; the test's element-class lookups just don't match SwiftUI's rendering. This is solvable by either fixing the test (broader query) or fixing the production view (`.accessibilityElement(children:.contain)`).

## Artifacts

- `/tmp/verify-post-bug192.log` — full xcodebuild output (transient; not committed).
- GH #689 — Bug #193 filing with full triage + fix direction.
- This evidence file at `dev-docs/verification/feature-45-20260515-post-bug192-batch.md`.

## Status

Feature #45 stays at `IN PROGRESS`. WI-6 (named test-plan selector) was BLOCKED on Bug #192; now that Bug #192 is fixed, WI-6 can resume — but its Gate 2 plan still needs one more revision round to derive the 13-class membership list from filesystem (the prior attempt had hallucinated class names). The 9 unsampled Verification classes are open scope for future verify-cron iterations.
