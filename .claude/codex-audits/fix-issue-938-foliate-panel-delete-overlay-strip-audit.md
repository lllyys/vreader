---
branch: fix/issue-938-foliate-panel-delete-overlay-strip
threadId: 019e43cf-48ab-7b13-b762-d1a90caa0050
rounds: 2
final_verdict: ship-as-is
date: 2026-05-20
---

# Codex Gate-4 audit — Bug #229 / GH #938

## Subject

Bug #229 / GH #938 (issue titled "Bug #228" on GitHub due to a 2026-05-19
concurrent-filer numbering collision; `docs/bugs.md` row 229 is the source of
truth). The Annotations-panel delete path on AZW3/MOBI books left the
Foliate-js SVG overlay painted until the next book reload, because
`HighlightListViewModel.removeHighlight` posted only `.readerHighlightRemoved`
(UUID-keyed) and the Foliate Coordinator's observer keys on
`.foliateRequestAnnotationJSDelete` (CFI-keyed).

The fix plumbs the deleted highlight's `.epub` anchor CFI through the dormant
`.foliateRequestAnnotationJSDelete` hook (kept intentionally post-feature-#55
WI-7 as exactly this reuse path), mirroring `FoliateHighlightJSBridge.delete`
— the in-reader popover's delete path — so panel + in-reader paths converge
on the same notification contract (names, userInfo shape, emission order).

## Files changed

- `vreader/ViewModels/HighlightListViewModel.swift` — `removeHighlight` now
  captures the pre-delete record from `self.highlights`, extracts the `.epub`
  anchor CFI via a new `private static epubAnchorCFI(of:)` helper, and posts
  `.foliateRequestAnnotationJSDelete` (CFI + `fingerprintKey`) alongside the
  existing `.readerHighlightRemoved`. The emission order matches
  `FoliateHighlightJSBridge.delete` (`.readerHighlightRemoved` first).
- `vreaderTests/ViewModels/HighlightListViewModelFoliateOverlayStripTests.swift`
  — new file with 6 tests: epub-anchored happy path (with strict ordering
  assertion), pre-delete capture proof, `.text`-anchor skip, nil-anchor skip,
  empty-CFI skip, persistence-failure atomicity.
- `vreaderTests/Services/Mocks/MockHighlightStore.swift` — added
  `setRemoveError(_:)` mirroring existing `setFetchError` / `setAddError`,
  reusing the existing `removeError` ivar.
- `docs/bugs.md` — row 229 status flipped OPEN → IN PROGRESS → FIXED on the
  fix branch.
- `vreader.xcodeproj/project.pbxproj` — xcodegen regen after adding the new
  test file (project.yml auto-globs `vreaderTests/`).

## Round 1 — 2 Low findings

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| `HighlightListViewModelTests.swift:220` (pre-split) | Low | The happy-path Foliate test proved both notifications fired with the right payload, but did not assert relative order. A future reorder in `removeHighlight` would still pass the suite while quietly breaking path parity with `FoliateHighlightJSBridge.delete`. | Fixed — added `#expect(spy.captured.map(\.name) == [.readerHighlightRemoved, .foliateRequestAnnotationJSDelete])` and refactored the payload assertions to read from the ordered captures (`spy.captured[0]` / `[1]`) rather than unordered `filter`. |
| `HighlightListViewModelTests.swift:1` (pre-split) | Low | The file was now 632 lines, well over the repo's ~300-line guideline (`.claude/rules/50-codebase-conventions.md` §9). | Fixed — extracted the entire Foliate overlay-strip suite to a new dedicated file `HighlightListViewModelFoliateOverlayStripTests.swift`. Original test file back to 292 lines. New file is 368 lines (a single coherent bug-focused suite + local fixture helpers; comparable to the existing `FoliateHighlightJSBridgeTests.swift` for the sibling in-reader path). |

## Round 2 — zero findings

> "No findings.
>
> The round-1 items are resolved correctly:
>
> - The ordering assertion … now pins the exact sequence `readerHighlightRemoved` then `foliateRequestAnnotationJSDelete`, and the payload assertions read from the ordered captures rather than unordered filters.
> - The extraction is wired correctly: the new test file is present in the project and sources build phase, and HighlightListViewModelTests.swift is back under the size guideline at 292 lines.
>
> Path parity also checks out: HighlightListViewModel.swift emits `.readerHighlightRemoved` first and `.foliateRequestAnnotationJSDelete` second, which matches FoliateHighlightJSBridge.swift. The observer contract remains aligned with `[\"cfi\": String, \"fingerprintKey\": String]`.
>
> On the residual 368-line test file: acceptable here. It is a single bug-focused suite with local fixture/setup code, not a grab-bag file, and splitting it further would likely reduce cohesion more than it helps.
>
> `final_verdict: ship-as-is`"

## Summary verdict

`ship-as-is`. Two rounds, two Low findings opened in round 1 and both
resolved before round 2; round 2 returned zero findings and explicitly named
the verdict.

The fix matches the bug row's fix-direction (a) precisely (reuse the dormant
Foliate Coordinator observer; capture the CFI before persistence delete;
filter by `fingerprintKey`), and the audit confirms path parity with
`FoliateHighlightJSBridge.delete`.
