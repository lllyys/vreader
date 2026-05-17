---
branch: fix/issue-834-epub-pdf-container-clobber
threadId: 019e3643-d264-73e2-860a-9990a2b48b44
rounds: 2
final_verdict: ship-as-is
date: 2026-05-17
---

# Codex Audit — Issue #834 (Bug #214)

EPUB/PDF reader-container `.accessibilityIdentifier` propagates onto the
bottom chrome — latent Cause-B clobber, same root cause as Bug #209,
not fixed for EPUB/PDF.

## Round 1 — findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| `PDFReaderContainerView.swift:85` | Medium | The PDF `Group` scoped `pdfReaderContainer` around `passwordOverlay` / `loadingOverlay` / `errorOverlay`, not just the content bridge — so the container identifier could still clobber the password prompt's own identifiers (`pdfPasswordField`, `pdfPasswordCancel`, `pdfPasswordSubmit`) and the loading/error identifiers when those overlays show. | **Fixed.** The PDF body `Group` now wraps ONLY `PDFViewBridge`. `passwordOverlay`, `loadingOverlay`, and `errorOverlay` were moved out of the `Group` to be separate `ZStack` siblings (alongside the bottom chrome), so `pdfReaderContainer` no longer reaches them. Now matches the EPUB approach and the #209 TXT/MD precedent. |
| `Feature11EPUBBottomChromeVerificationTests.swift:97` | Medium | The new XCUITest `XCTSkip`-ped if the seeded EPUB failed to open. With a dedicated `.epubFixture` (guaranteed-openable EPUB), "reader did not load" is a real regression in seed/launch-arg/navigation, not an environmental skip — the skip would hide it. | **Fixed.** Both tests now `XCTAssertTrue(openEPUB(), ...)` — a reader-load failure is a hard test failure, not a skip. The 3-retry loop inside `openEPUB()` is kept (it handles the legitimate LazyVGrid first-tap timing race); the per-attempt back-button timeout was bumped 15s→20s for cold-simulator headroom. `continueAfterFailure = false` makes a failed `openEPUB()` assertion stop the test cleanly. |
| `PDFReaderContainerView.swift:77` | Low | Production fix covers EPUB + PDF, but the new regression coverage is EPUB-only — no test opens a real PDF and proves `readerDisplayButton`/`readerNotesButton` survive the `pdfReaderContainer` + removed-`pdfBottomOverlay` paths. | **Accepted (not fixed).** The repo has no openable PDF fixture — `vreader/Resources/DebugFixtures/` ships no `.pdf` file and `DebugFixtureCatalog` has no PDF entry. A PDF bottom-chrome test would require new fixture infrastructure (bundle a PDF + catalog entry + a `seedMiniPDF`). The issue's acceptance criterion is "a Verification test exercises the EPUB **and/or** PDF bottom-chrome path" — the EPUB test satisfies it. The PDF production fix is the byte-identical pattern to the EPUB fix and to the proven #209 TXT/MD fix, and is covered by this audit. Documented in the `docs/bugs.md` row #214 and the PR body. |

## Round 2 — verification

Codex re-reviewed the round-1 fixes (re-scoped PDF `Group`, hard-fail
test posture). Verdict: **"No findings."**

- The PDF `pdfReaderContainer` is now scoped only to the `PDFViewBridge`
  subtree; password/loading/error/bottom overlays are separate `ZStack`
  siblings. No stacking or alignment regression — in a SwiftUI `ZStack`
  later siblings render above earlier ones, so the bridge stays at the
  back, the state overlays sit on top of it, and the bottom chrome
  renders above both, exactly as before. The overlays were already
  self-contained centered/full-screen views, so alignment is unchanged.
- The XCUITest now treats EPUB-open failure as a hard regression — the
  right posture for a dedicated seeded fixture. The 3-attempt tap loop
  and the 20s cold-sim per-attempt wait are reasonable.
- Residual accepted gap (no real-PDF verification test) is unchanged
  and is not a new issue.

## Summary verdict

**ship-as-is.** Two audit rounds. Zero open Critical/High/Medium
findings. One Low finding (no real-PDF verification test) accepted with
rationale — blocked on absent PDF fixture infrastructure, out of scope
for this bug fix, and the EPUB test already satisfies the issue's
"EPUB and/or PDF" acceptance criterion.

## Scope notes

- The fix addresses TWO distinct identifier-propagation clobbers for
  EPUB/PDF (the original Bug #214 issue text named only the first):
  1. The body-level container identifier (`epubReaderContainer` /
     `pdfReaderContainer`) — fixed by `Group`-scoping, mirroring #209.
  2. The `epubBottomOverlay` / `pdfBottomOverlay` identifier applied
     directly on the `ReaderBottomChrome` instance — which also
     propagated onto the toolbar buttons. Removed so EPUB/PDF match
     TXT/MD (TXT/MD never applied a wrapping identifier on their
     `ReaderBottomChrome`). These identifiers had zero test consumers.
- RED→GREEN was verified end-to-end on iPhone 17 Pro Simulator: the
  pre-fix code fails both EPUB XCUITests at the `readerDisplayButton`
  clobber assertion; the fixed code passes both (2 passed, 0 failed,
  0 skipped).
