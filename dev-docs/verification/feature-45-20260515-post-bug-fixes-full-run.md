---
kind: feature
id: 45
status_target: DONE
commit_sha: 897a459fcb62db3685a1e972a8e153ad0313f25a
app_version: 3.22.1 (build 353)
date: 2026-05-15
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.5
build_configuration: Debug
backend: n/a (XCUITest harness against in-simulator app + DebugBridge URL scheme)
result: partial
---

# Feature #45 — Verification plan re-run after WI-6 bug fixes

## Why this evidence file exists

After Feature #45 WI-6 shipped the named Verification test plan (PR #692 / v3.21.69), the first-real-run surfaced 2 product failures (`dev-docs/verification/feature-45-20260515-wi-6-full-run.md`): Feature28 (Bug #194) + Feature29 (Bug #195). Both were filed and then fixed in the same session (PR #699 / v3.21.74 and PR #701 / v3.22.1 respectively). This evidence file documents the re-run of `-testPlan Verification` against the current `main` to confirm the fixes landed correctly and to capture the post-fix per-class breakdown.

## Acceptance criteria

| # | Criterion (from Feature #45 plan + the prior round's deferred slices) | Observed | Pass/fail |
|---|---|---|---|
| 1 | Bug #194 fix (Feature #28 Chinese Text picker) lands on main and Feature28 verify suite passes | Feature28 ran 2 methods: 1 PASS (the surface test fixed by PR #699) + 1 SKIP (the conversion-applied-to-content test still XCTSkip-gated on missing CJK fixture). 0 failures. | **pass** |
| 2 | Bug #195 fix (Feature #29 WebDAV verify) lands on main and Feature29 verify suite passes | Feature29 ran 2 methods: 1 PASS (the surface test fixed by PR #701) + 1 SKIP (the live-backup test still XCTSkip-gated on CI env vars). 0 failures. | **pass** |
| 3 | Total Verification plan run dispatches exactly 25 methods, all class membership matches the documented roster | `Executed 25 tests` total. All 13 classes' suites started + completed. | **pass** |
| 4 | Carry-over of the 11 known classes from the prior run (Feature11/21/23/27/31/34/35/36/37/40/41) — no new failures introduced | **1 new failure**: Feature31AutoPageTurnVerificationTests.test_verify_feature_31_auto_page_turn_toggle_present at line 107. Filed as **Bug #196** (GH #702). | **partial — new bug surfaced** |
| 5 | All 5 previously-all-XCTSkip classes (Feature11, 21, 37, 40, 41) maintain the same skip count (capability gates stable, not regressed to product failures) | All 5 still all-skip with the same per-class counts. Capability gates stable. | **pass** |
| 6 | Wall-clock under the 8-minute Gate 5 budget | 421 seconds (~7 min 1 s). Within budget. | **pass** |

Overall: 5/6 pass + 1 partial. The partial is the new Feature31 regression, filed as Bug #196 for the bug-fix cron to handle. Feature #45 stays at `DONE` (per the prior evidence file; this run's regression doesn't change the WI-6 contract — the harness works, it just surfaced a previously-passing test).

## Per-class results

Total: **Executed 25 tests, with 13 tests skipped and 1 failure (0 unexpected) in 420.977 seconds**.

Compared to the previous WI-6 first-real-run on the same date:
- **Bug #194 (Feature28)**: was 1 FAIL + 1 SKIP → now 1 PASS + 1 SKIP ✓
- **Bug #195 (Feature29)**: was 1 FAIL + 1 SKIP → now 1 PASS + 1 SKIP ✓
- **NEW: Bug #196 (Feature31)**: was 2 PASS → now 1 PASS + 1 FAIL ✗

| Class | Methods | Pass | XCTSkip | Fail | Wall-clock | Δ from prior run |
|---|---|---|---|---|---|---|
| Feature11EPUBHighlight | 2 | 0 | 2 | 0 | 55.3 s | — (still all-skip) |
| Feature21PaginatedMode | 2 | 0 | 2 | 0 | 29.4 s | — (still all-skip) |
| Feature23TXTToc | 2 | 2 | 0 | 0 | 26.8 s | — (still 2 PASS) |
| Feature27ReplacementRules | 1 | 1 | 0 | 0 | (not parsed) | — (still 1 PASS) |
| Feature28ChineseConversion | 2 | 1 | 1 | 0 | 23.2 s | **Bug #194 fixed** (was 1 FAIL → now 1 PASS) |
| Feature29WebDAV | 2 | 1 | 1 | 0 | 20.0 s | **Bug #195 fixed** (was 1 FAIL → now 1 PASS) |
| Feature31AutoPageTurn | 2 | 1 | 0 | 1 | 43.3 s | **REGRESSED — Bug #196** (was 2 PASS → now 1 PASS + 1 FAIL) |
| Feature34Collections | 2 | 2 | 0 | 0 | 50.4 s | — (still 2 PASS) |
| Feature35AnnotationsExport | 2 | 2 | 0 | 0 | 21.3 s | — (still 2 PASS) |
| Feature36OPDS | 2 | 1 | 1 | 0 | 18.6 s | — (still 1 PASS + 1 SKIP for live env) |
| Feature37PerBookSettings | 2 | 0 | 2 | 0 | 29.5 s | — (still all-skip) |
| Feature40TTSSentenceHighlight | 2 | 0 | 2 | 0 | 46.1 s | — (still all-skip) |
| Feature41TTSAutoScroll | 2 | 0 | 2 | 0 | 46.2 s | — (still all-skip) |
| **Total** | **25** | **11** | **13** | **1** | **421.0 s** | **+1 PASS, +0 SKIP, -1 FAIL (net)** |

The "+1 PASS, -1 FAIL" reflects the swap-pair: Bug #194 + #195 went green (2 PASSes recovered), Bug #196 went red (1 PASS regressed). Net: 11 PASS (vs. prior 10), 1 FAIL (vs. prior 2).

## Commands run

```bash
git checkout main && git pull
git log --oneline -3
# 897a459 fix(#695): Feature #29 WebDAV verify test — traverse multi-profile path (#701)
# c9fddcd feat(#667 WI-2): FileURLImportRouter + production .onOpenURL handler (final WI of Feature #59) (#700)
# 285fb06 fix(#694): Feature #28 Chinese Text picker — accessibility-id query (#699)

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
    -project vreader.xcodeproj -scheme vreader \
    -testPlan Verification \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    2>&1 | tee /tmp/verify-cron-full-run-v3221.log
```

## Observations

- **Bug #194 + #195 fixes confirmed on main**: both Feature28 and Feature29 surface tests now PASS. The descendant-by-identifier pattern (Bug #193 template) holds well as a reliable strategy for SwiftUI accessibility queries that need to be tolerant of element-class drift.
- **5 all-skip classes are stable**: Feature11/21/37/40/41 all returned the same skip count (2 each) as the prior run. The XCTSkip rationale is probably legitimate capability/fixture/env-var gates rather than stale guards. A future iteration should investigate each class's setUp code to document the skip reasons (separate verify-cron scope).
- **Feature31 regression is a NEW signal**: Feature31 PASSED in the prior run earlier today. The fact that it FAILED now while no Feature31-touching code changed between runs makes this either (a) a timing flake or (b) downstream of Bug #194's accessibility-tree change in `ReaderSettingsPanel.swift`. Documented in Bug #196's body. Filed for bug-fix cron.
- **Wall-clock 421s** (vs. prior run's 408s) — within the 8-minute budget, ~13s longer mostly from Feature31's retry loop adding ~10s.
- **Net trajectory**: the WI-6 harness's recovery arc is complete for 3/4 originally surfaced bugs (#192/#193/#194/#195). The first-real-run revealed 2 product failures; both are now fixed. WI-6's job is to make the subset runnable; the bugs are bugs, not WI-6 contract failures.

## Artifacts

- Full `xcodebuild test -testPlan Verification` log: transient at `/tmp/verify-cron-full-run-v3221.log` (~131KB; not committed).
- GH #702 — Bug #196 filing (Feature #31 toggle hittability regression).
- Prior runs (chronologically):
  - `dev-docs/verification/feature-45-20260515-post-bug192-batch.md` — 4-class sample
  - `dev-docs/verification/feature-45-20260515-wi-6-full-run.md` — first end-to-end (10 PASS, 13 SKIP, 2 FAIL = Bug #194 + #195)
  - This file — post-fix re-run (11 PASS, 13 SKIP, 1 FAIL = Bug #196 new regression)

## Status

Feature #45 stays at `DONE` (the harness functions correctly; surfaced failures are product/test bugs, not WI-6 contract failures). Outstanding work to reach `VERIFIED`:

1. **Bug #196 fix** — for the bug-fix cron.
2. **5 all-skip classes investigation** (Feature11/21/37/40/41) — separate verify-cron iterations to document each method's XCTSkip rationale + decide whether each skip is a legitimate capability gate or a stale guard that should be lifted.
3. **Once Bug #196 + all-skip classes resolved**: a clean run with 25 PASS (or 25 PASS + documented-skip evidence) becomes the basis for flipping Feature #45 from `DONE` to `VERIFIED`.
