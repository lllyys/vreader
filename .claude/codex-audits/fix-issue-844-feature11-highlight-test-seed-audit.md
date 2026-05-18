---
branch: fix/issue-844-feature11-highlight-test-seed
threadId: 019e392a-4e8e-79a1-ad68-76192a9f114a
rounds: 2
final_verdict: ship-as-is
date: 2026-05-18
---

# Codex audit — Bug #219 / GH #844: Feature11EPUBHighlightVerificationTests seed + readiness fix

## Scope

One-file change: `vreaderUITests/Verification/Feature11EPUBHighlightVerificationTests.swift`.
Bug #219 — the harness silently skipped (vacuous `** TEST SUCCEEDED **`,
2 tests skipped) because `setUpWithError` seeded `.books` (metadata-only,
non-openable EPUB records). The fix: `.books` → `.epubFixture` seed;
`openEPUBBook()` rewritten to a retry-tap `-> Bool` helper mirroring
`Feature11EPUBBottomChromeVerificationTests.openEPUB()`; the reader-load
`XCTSkip`s converted to hard `XCTAssertTrue`; `waitForEPUBReaderReady()`
stale identifier probe replaced with `app.webViews.firstMatch`.

## Round 1 — findings

| # | location | severity | issue | resolution |
|---|---|---|---|---|
| 1 | happy-path reopen half | High | The happy-path reopen still had `guard card.waitForExistence … else { return }` + `guard waitForEPUBReaderReady() else { return }` — silent-success exits that preserved Bug #219's false-green class on the persistence half of the scenario. | FIXED — both `return` guards replaced with `XCTAssertTrue(openEPUBBook(), …)` + `XCTAssertTrue(waitForEPUBReaderReady(), …)`, reusing `openEPUBBook()` for the reopen. |

Round 1 also confirmed: the core fix is correct; `.epubFixture` is a real
`TestSeedState` case (`--seed-epub-fixture`, `TestSeeder.seedMiniEPUB`
writes the bundled `mini-epub3.epub`); no remaining `try openEPUBBook()`
callers after the signature change (compile-safe); no dead code (the old
`epubPredicate` local is gone); the remaining long-press `XCTSkip`s are a
defensible Bug-#219 scope boundary — they fire post-open as explicit
skipped tests, not silent `** TEST SUCCEEDED **` vacuity.

## Author change after round 1 (not an audit finding)

A test re-run proved `waitForEPUBReaderReady()`'s `epubReaderContent` /
`epubReaderContainer` identifier queries never resolved — the test failed
at that probe even after the seed fix. The XCUITest log showed
`epubReaderContainer` is the a11y identifier on the WebView itself
(`Find the "epubReaderContainer" WebView`), not an `otherElements`
element (Bug #214 scoped it onto an inner content `Group`). The probe was
replaced with `app.webViews.firstMatch.waitForExistence(timeout:)` —
identifier-independent — still gated by `readerBackButton`.

## Round 2 — verification

Zero remaining Critical/High/Medium findings. The round-1 High is fully
resolved (the reopen half now hard-fails). The `waitForEPUBReaderReady()`
change is correct and free of new compile/logic issues. The remaining
`XCTSkip`s are the explicit post-open WebView long-press limitation —
filed separately as Bug #220 / GH #845 — and do not reintroduce
Bug #219's silent-pass mechanism.

**Final verdict: ship-as-is.**
