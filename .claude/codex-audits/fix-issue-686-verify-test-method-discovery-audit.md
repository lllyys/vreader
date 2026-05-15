---
branch: fix/issue-686-verify-test-method-discovery
threadId: 019e29a0-956e-7d32-9742-b4ad914e7dde
rounds: 2
final_verdict: ship-as-is
date: 2026-05-15
---

# Codex audit log — Bug #192 (GH #686) — `verify_*` test method discovery

## Round 1 findings

| # | File | Severity | Finding | Resolution |
|---|---|---|---|---|
| 1 | `docs/architecture.md:313` | Medium | Convention text claimed verification suite uses `verify_` prefix "intentionally NOT auto-discovered" — false statement, would mislead future work. | Rewrote convention text to describe `test_verify_*` prefix + record Bug #192 historical context. Also updated RED-proof catalog sentence at architecture.md:328. |
| 2 | `docs/features.md:184, :194` | Low | Feature #45 plan template documented naming rule + examples with old `verify_feature_<NN>_<slug>` prefix. | Updated both lines to `test_verify_feature_<NN>_<slug>` with explicit Bug #192 cross-ref. |
| 3 | `dev-docs/verification/feature-{23,31,35}-20260513.md` | Low | Historical evidence files contained `-only-testing:.../verify_feature_*` selectors that are stale post-rename. | Annotated each file with a Bug #192 caveat block right after frontmatter — preserves the original recorded commands (frozen-in-time evidence) but warns the reader that the `xcodebuild test` exit-0 signals captured were vacuous (`Executed 0 tests`) and the `verify_feature_*` selectors quoted have been renamed. |

## Round 2 verdict

Codex confirmed all 3 findings closed correctly. Zero new findings. Verdict: **ship-as-is**.

## Code correctness (Round 1)

Codex confirmed:
- Repo-wide scan: no remaining `func verify_*` declarations under `vreaderUITests`, including `Helpers/`.
- The 4 non-method edits were limited to doc comments and one `XCTSkip` message — no runtime strings, prints, or accessibility IDs touched.
- `test_verify_*` naming is an acceptable trade-off: satisfies XCTest discovery while preserving the grep-friendly `verify_feature_*` slug.
- Scope discipline correct: this bug fix stops at discovery; newly visible `XCTSkip`s, passes, or real failures are separate follow-up bugs, not part of Bug #192.

## Proof of discovery (pre/post)

Pre-fix:
```
$ xcodebuild test ... -only-testing:vreaderUITests/Feature11EPUBHighlightVerificationTests
Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
** TEST SUCCEEDED **       (vacuous — 0 tests discovered)
```

Post-fix:
```
$ xcodebuild test ... -only-testing:vreaderUITests/Feature11EPUBHighlightVerificationTests
Test Case '...test_verify_feature_11_epub_highlight_happy_path' started.
Test Case '...test_verify_feature_11_epub_highlight_happy_path' skipped (28.5s).
Test Case '...test_verify_feature_11_epub_highlight_regression_bug77_buffering_race' started.
Test Case '...test_verify_feature_11_epub_highlight_regression_bug77_buffering_race' skipped (26.8s).
Executed 2 tests, with 2 tests skipped and 0 failures
** TEST SUCCEEDED **       (real — 2 tests discovered, both XCTSkip on prereqs)
```

`Feature27ReplacementRulesVerificationTests.test_verify_feature_27_replacement_rule_ui_surface` confirmed running end-to-end + passing (10.7s) — the first method to clear an `XCTSkip` prereq.

## Newly-visible test state (out of scope per bug-fix cron scope guard)

After the rename, individual tests may:
- XCTSkip their bodies (existing behavior — many tests have prereq guards that return XCTSkip when the env doesn't satisfy the setup, e.g. "EPUB reader did not load" in headless sim).
- Pass cleanly (proven for Feature27).
- Fail for the first time (would be previously-masked regressions).

Per the bug row's "Fix direction": "Some may surface real test failures that have been masked by the silent no-op" — those need triage as separate bug filings in subsequent verify-cron iterations. This PR ships ONLY the rename, not full Verification-suite passage.

## Unblocks

Feature #45 WI-6 was BLOCKED on this bug. Once this PR merges, WI-6's plan needs one more revision round (correct 13-class filesystem-derived membership list, since the previous attempt had hallucinated class names) and a Gate 2 round-3 audit before Gate 3 can start.
