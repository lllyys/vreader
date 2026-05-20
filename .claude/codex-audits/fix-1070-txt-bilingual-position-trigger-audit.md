---
branch: fix/1070-txt-bilingual-position-trigger
threadId: 019e45c0-9f68-78d1-a350-155f3be50e1a
rounds: 2
final_verdict: follow-up-recommended
date: 2026-05-20
---

# Codex Audit Log — Bug #245 (GH #1070)

Fix: TXT bilingual mode renders chrome pill but does NOT render inline translations
even after disk-cache hit. The TXT reader was missing the
`vm.handlePositionChange(locator)` trigger that EPUB / Foliate / PDF / MD all wire,
so the bilingual VM's in-memory `translationsByUnit` dict never populated from the
disk cache and the renderer fell through to source-only.

## Scope of audit

Codex audited a 6-file diff:
- `vreader/Views/Reader/TXTReaderContainerView+Bilingual.swift` — added
  `triggerBilingualPositionChange(viewModel:locator:)` static helper, added
  `onPositionChanged: () -> Void` field to `TXTBilingualSurfacesModifier`, wired
  chapter-idx `onChange` + `.readerPositionDidChange` observer in the modifier
  body, and added trigger calls from `ensureBilingualViewModel()` (re-open path),
  `confirmBilingualSetup()`, and `handleMoreBilingualToggle()` subsequent-enable
  branch.
- `vreaderTests/Views/Reader/Bilingual/TXTReaderContainerBilingualPositionTriggerTests.swift`
  — new Swift Testing suite, 5 cases (structural assertion that the modifier exposes
  `onPositionChanged`, behavioral assertion that the static helper populates
  `translationsByUnit` for the locator's chapter, plus three no-op guards).
- `docs/bugs.md` — row #245 flipped TODO → FIXED with fix summary.
- `archive/bugs-history.md` — new archive entry for #245 with repro, root cause,
  fix shipped, test, lessons, caught-by.
- `project.yml` + `vreader.xcodeproj/project.pbxproj` — version bump v3.38.16 → v3.38.17
  (build 591 → 592).

## Round 1 findings (2)

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| `vreader.xcodeproj/project.pbxproj:6237` | Medium | Required version bump did not propagate from `project.yml` into the checked-in `project.pbxproj` (still at `591` / `3.38.16`). Building from the committed pbxproj would still ship `v3.38.16`, violating the per-PR version-bump gate. | **Fixed.** Re-ran `xcodegen generate`. `project.pbxproj` now has `CURRENT_PROJECT_VERSION = 592` / `MARKETING_VERSION = 3.38.17` at both Debug (6237/6243) and Release (6387/6393) configs. |
| `vreader/Views/Reader/TXTReaderContainerView+Bilingual.swift:1` | Low | File is 430 lines, over the repo's `~300` soft budget. The new trigger wiring is correct; most of the file's size comes from the WI-12b offset-routing helpers that already shipped. | **Accepted in this PR (deferred follow-up).** Sibling `PDFReaderContainerView+Bilingual.swift` (341 lines) and `EPUBReaderContainerView+Bilingual.swift` (355 lines) are already over budget — a split is a separate refactor concern, not a bug-fix gating concern. |

## Round 2 findings (1)

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| `vreader/Views/Reader/TXTReaderContainerView+Bilingual.swift:1` | Low | File still 430 lines after Round-1 fix. | **Accepted as deferred follow-up per Round-1 rationale.** No open Critical/High/Medium findings remain. |

## Verdict

`follow-up-recommended` — no open Critical/High/Medium findings. One Low finding
(soft file-size budget) explicitly accepted in this PR with the rationale that
the sibling bilingual extensions are already over the same budget and a split is
a separate refactor concern.

## Tests

5/5 GREEN in `TXTReaderContainerBilingualPositionTriggerTests`. Full unit-test
suite (6951 tests across 691 suites) passes in 37.4s on iPhone 17 Pro Simulator
(UDID `61149F0E-DC18-4BE2-BB37-52659F1F4F62`).
