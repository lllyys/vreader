---
kind: feature
id: 11
status_target: VERIFIED
commit_sha: 8cab12a4574304831666decf343ffc477943ae31
app_version: 3.27.25 (build 439)
date: 2026-05-18
verifier: claude (verify-cron)
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.4
build_configuration: Debug
backend: n/a (XCUITest Verification harness)
result: partial
---

# Feature #11 round-5 — regression-verify; discovered Bug #219 (harness vacuous-skip)

## Context

Feature #11 (EPUB text highlighting and note-taking) reached `VERIFIED`
at round-4 (2026-05-09, `feature-11-20260509-round4.md`) via a
computer-use-driven end-to-end pass covering all five acceptance
criteria.

This round is a **regression sample** at the current `main`
(`8cab12a`, v3.27.25) — motivated by three EPUB-highlight-area bug
fixes that landed after round-4: #211 (EPUB tap-on-highlight inline
Delete menu), #212 (force EPUB highlight repaint on delete), #214
(scope EPUB reader-container a11y identifiers off the bottom chrome).
The sample was driven CU-free via the
`Feature11EPUBHighlightVerificationTests` XCUITest class (CU MCP
unavailable this iteration — Screen-Sharing virtual-display issue).

## Scope

Regression verification of feature #11's EPUB highlight acceptance
criteria at `8cab12a`. Verification only; no code changed.

## Result

`result: partial` — **no product regression found, but the intended
regression sample could not execute**: `Feature11EPUBHighlightVerificationTests`
is vacuously skipping. Filed as **Bug #219 / GH #844**. EPUB-reader
product health was confirmed independently via an alternate test
(criterion 2).

## Acceptance criteria

| # | Criterion | Result | Observed |
|---|-----------|--------|----------|
| 1 | `Feature11EPUBHighlightVerificationTests` exercises the EPUB highlight pipeline | **FAIL (harness)** | `xcodebuild test -only-testing:vreaderUITests/Feature11EPUBHighlightVerificationTests` → `Executed 2 tests, with 2 tests skipped and 0 failures` / `** TEST SUCCEEDED **`. Both `test_verify_feature_11_epub_highlight_*` methods `XCTSkip("EPUB reader did not load")` at `Feature11EPUBHighlightVerificationTests.swift:172`. The harness seeds `.books` (metadata-only `BookRecord`s, no backing file — Bug #209 Cause A), so the tapped `bookCard_` never opens a reader. Vacuous pass → filed **Bug #219 / GH #844**. |
| 2 | EPUB reader product health (no regression from #211/#212/#214) | **PASS** | Same commit `8cab12a`: `Feature11EPUBBottomChromeVerificationTests` (seeds `.epubFixture` — the openable `--seed-epub-fixture` / `TestSeeder.seedMiniEPUB`) opened a real EPUB (`bookCard_epub:00000000…e9b00001:2198`); `readerBackButton` + `readerDisplayButton` resolved; `readerSettingsPanel` opened on tap. `Executed 2 tests, with 0 failures` / `** TEST SUCCEEDED **`. The EPUB reader loads and its chrome works at `8cab12a` — #211/#212/#214 did not regress EPUB reader load/chrome. |
| 3 | Feature #11 acceptance criteria (highlight create / yellow paint / persist / restore) | **not re-verified this round** | Blocked by criterion 1's harness defect. Round-4's CU-driven pass remains the standing end-to-end evidence; feature #11 stays `VERIFIED`. A CU-available or harness-fixed (Bug #219) round can re-run the full pipeline. |

## What this round establishes

- Feature #11 stays `VERIFIED` — round-4's end-to-end pass stands; no
  regression was found, and the EPUB reader is confirmed healthy at
  `8cab12a` (criterion 2).
- The dedicated feature-#11 XCUITest harness
  (`Feature11EPUBHighlightVerificationTests`) has been silently
  no-opping — a false-confidence verification gap. Filed as **Bug
  #219**. This is the Bug #192 *symptom* (vacuous `** TEST SUCCEEDED **`)
  with a different cause: #192 was method non-discovery (fixed by the
  `test_verify_*` rename); #219 is a bad seed (`.books` → non-openable
  EPUB records).
- The Bug #214 work created the *sibling*
  `Feature11EPUBBottomChromeVerificationTests` with the correct
  `.epubFixture` seed but left the pre-existing highlight test on
  `.books`. Bug #209 re-pointed Feature21/28/37 off `.books`, not
  Feature11.

## Commands run

```bash
DEST='platform=iOS Simulator,name=iPhone 17 Pro'   # iPhone 17 Pro, iOS 26.4
# clean main 8cab12a (v3.27.25 build 439)

xcodebuild test -project vreader.xcodeproj -scheme vreader \
  -destination "$DEST" \
  -only-testing:vreaderUITests/Feature11EPUBHighlightVerificationTests
#   → Executed 2 tests, with 2 tests skipped and 0 failures — ** TEST SUCCEEDED **
#   → skip: "EPUB reader did not load" (Feature11EPUBHighlightVerificationTests.swift:172)

xcodebuild test -project vreader.xcodeproj -scheme vreader \
  -destination "$DEST" \
  -only-testing:vreaderUITests/Feature11EPUBBottomChromeVerificationTests
#   → Executed 2 tests, with 0 failures — ** TEST SUCCEEDED **
#   → opened bookCard_epub:00000000…e9b00001:2198; reader chrome resolved
```

## Observations

- `seed: .books` is used by 6 Verification classes (Feature11Highlight,
  Feature27, Feature29, Feature34, Feature35, Feature36). Only classes
  that must *open a reader* are broken by the non-openable-record
  defect; Feature29/34/35/36 plausibly only need library rows to exist.
  `Feature27ReplacementRulesVerificationTests` also seeds `.books` and
  applies rules in the reader — a possible sibling of Bug #219; a
  harness-wide audit is noted in #219 but not performed this round
  (out of verification scope).
- Verification-only round: no code changed. One bug filed (#219 / GH
  #844).

## Artifacts

None (XCUITest run). `.xcresult` bundles in DerivedData:
`Test-vreader-2026.05.18_11-16-50` (highlight test, skipped) and
`Test-vreader-2026.05.18_11-21-15` (bottom-chrome test, 2/2 pass).

## Outcome

Feature #11 stays **VERIFIED** — round-4's end-to-end pass stands; no
regression. The verify-cron's intended regression sample could not
execute because `Feature11EPUBHighlightVerificationTests` vacuously
skips — filed **Bug #219 / GH #844** (harness seeds `.books`,
non-openable). EPUB-reader product health independently confirmed via
`Feature11EPUBBottomChromeVerificationTests` (2/2 PASS at `8cab12a`).
