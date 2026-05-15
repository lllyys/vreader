---
branch: fix/issue-689-opds-xcuitest-element-class-mismatch
threadId: 019e29d4-a05b-73e2-8d48-e0899bb94c0b
rounds: 2
final_verdict: ship-as-is
date: 2026-05-15
---

# Codex audit log — Bug #193 (GH #689) — Feature #36 OPDS XCUITest element-class mismatch

## Round 1 findings

| # | File | Severity | Finding | Resolution |
|---|---|---|---|---|
| 1 | `Feature36OPDSVerificationTests.swift:47` | Low | The third signal `app.buttons["opdsAddCatalogEmpty"]` was added as a "guaranteed-findable Button widget" fallback, but the repo's `OPDSCatalogListTests.swift:132` already documents that SwiftUI propagates `opdsEmptyState` onto its descendants and can shadow the inner button's own identifier. So that signal is not actually reliable. | Dropped the third signal entirely. The two descendant-query signals (`opdsCatalogList` + `opdsEmptyState` via `app.descendants(matching:.any).matching(identifier:).firstMatch`) cover both surface states without depending on the shadowable button identifier. |

## Round 2 verdict

Codex confirmed the Low is closed; the test now uses only the two app-wide descendant identifier queries and avoids the known identifier-propagation issue. Verdict: **ship-as-is**.

## Test gate

`xcodebuild test -only-testing:vreaderUITests/Feature36OPDSVerificationTests/test_verify_feature_36_opds_catalog_ui_surface` — passes in 16.7s post-revision (vs. 11.1s FAIL pre-fix, and Executed-0-tests vacuous pre-Bug-192).

## Pre/post RED proof

Pre-fix (post-Bug-192): test FAILED at line 46 because element-class lookups didn't match SwiftUI rendering. Failure excerpt from `/tmp/verify-post-bug192.log`:

```
t = 10.74s Checking existence of `"opdsEmptyState" Other`
t = 10.78s Checking existence of `"opdsCatalogList" ScrollView`
Feature36OPDSVerificationTests.swift:46: error: XCTAssertTrue failed
```

Post-fix: descendant-any-class queries find the elements regardless of underlying `XCUIElement.ElementType` classification. Test passes.

## Diff scope

Single-file change. The 4-line surface-existence block at `Feature36OPDSVerificationTests.swift:43-49` was rewritten to use broader queries; no other test logic, no production code, no doc-comment cross-references. Round-1 additionally trimmed an over-confident third signal.

## Codex's notes (round 1)

- `app.descendants(matching: .any).matching(identifier: ...).firstMatch` searches the full app accessibility tree, so it spans the sheet/navigation split introduced by `LibraryView`'s `.sheet { NavigationStack { OPDSCatalogListView() } }`. App-wide scope is appropriate here.
- `.firstMatch` is acceptable for existence-only assertions; if multiple descendants inherit the same identifier, any match proves the surface rendered.
- The second OPDS test (`test_verify_feature_36_opds_browse_with_live_fixture`) does NOT need the same change — it never performs the broken class-specific lookups; it waits for `opdsAddCatalog` (toolbar button, real widget) and asserts the saved catalog row by label.
- No existing helper like `app.firstMatching(identifier:)` in the repo; the verbose descendant query is consistent with current practice.
- Not fixing the other 9 unsampled Verification classes (#11, 21, 23, 28, 29, 31, 37, 40, 41) is correct per scope rules — those need separate bug filings / audits.

## Cross-refs

- Filed by verify-cron PR #690 (commit `5397618`) after Bug #192 fix (PR #688) made the test runnable for the first time.
- Original WI-3 (Feature #45) shipped this test in commit `cdb007b` with the (vacuous) Executed-0-tests result that obscured the element-class mismatch.
