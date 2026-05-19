---
branch: fix/issue-902-searchbar-touch-targets
threadId: 019e3e77-213e-79f2-91fa-33b7786c25e7
rounds: 3
final_verdict: ship-as-is
date: 2026-05-19
---

# Codex Audit — GH #902 / Bug #224

SearchBar v2 re-skin: `searchTextField` / `searchCancelButton` touch targets
below the 44 pt HIG minimum.

## Scope audited

Diff vs `origin/main` (4 files):

- `vreader/Views/Search/SearchBar.swift` — `.frame(minHeight: 44)` +
  `.contentShape(Rectangle())` on the `TextField` and the Cancel `Button`;
  redundant `.padding(.vertical, 10)` removed from the field `HStack`.
- `vreaderUITests/Search/SearchSheetPlaceholderTests.swift` — drop
  `.hitRegion` exclusion from `testSearchSheetAccessibilityAudit`.
- `vreaderUITests/Accessibility/GlobalAccessibilityAuditTests.swift` — drop
  `.hitRegion` exclusion from `testSearchSheetAudit`.
- `docs/bugs.md` — Bug #224 row `TODO` → `IN PROGRESS` (tracker only).

## Round 1 — findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| SearchBar.swift:80 | Medium | `searchClearButton` (image-only `Button`, ~15 pt glyph, shown only in the non-empty-query state) is also a sub-44 pt hit region. | **Deferred — out of #902 scope.** See "Scope decision" below. Logged as a separate bug. |
| SearchSheetPlaceholderTests.swift:79 | Medium | Restored audit exercises only the empty-query state — does not cover the conditional clear-button state. | **Deferred — out of #902 scope.** Adding non-empty-state coverage would fail RED on `searchClearButton`, conflating two defects in one PR. |
| GlobalAccessibilityAuditTests.swift:121 | Low | Global sweep mirrors the same empty-state-only blind spot. | **Deferred — out of #902 scope.** Same rationale. |

Round 1 also confirmed the in-scope code is correct: modifier order
(`.frame` → `.contentShape` → `.accessibilityIdentifier`) attaches the
identifier to the 44 pt-tall framed control, so `performAccessibilityAudit`
evaluates the framed element, not the inner glyph/text line. Removing the
field's vertical padding is safe — the `TextField`'s 44 pt `minHeight` now
governs the field height (~44 pt, HIG-standard) rather than inflating it.
Design-parity verdict: **exempt** (rule 51) — an accessibility-compliance
repair with no meaningful visible divergence.

## Scope decision — `searchClearButton` deferred

All three round-1 findings concern `searchClearButton`. Issue #902 / Bug #224's
named scope is strictly `searchTextField` + `searchCancelButton` — the two
elements its `performAccessibilityAudit` issue-dump identified. The clear
button is a distinct sibling defect:

1. **Scope discipline** — #902 names exactly two elements; the clear button
   is a separate touch-target defect that warrants its own tracker row.
2. **Rule 51** — a 44×44 hit frame on the ~15 pt clear glyph shifts the
   glyph's visible position within the field (it sits at the design's tight
   `padding: 2` inset; centering it in a 44 pt box moves it ~28 pt from the
   field edge). That is a visible layout delta on a control the issue did
   not name — it belongs in its own scoped change.
3. **Acceptance criterion #2** — the issue's GREEN bar is
   "`testSearchSheetAccessibilityAudit` passes with the `.hitRegion`
   exclusion removed." Both search-sheet audit tests exercise the
   empty-query state (no text entered), so they never reach the clear
   button — they pass GREEN with the in-scope fix. Non-empty-state audit
   coverage is deliberately NOT added, to avoid conflating two defects.

`searchClearButton` is logged as a separate discovered bug (see PR body /
final report) so it gets its own tracker row + GH issue.

## Round 2 — verification

With `searchClearButton` explicitly deferred, Codex re-reviewed the in-scope
diff (`searchTextField` + `searchCancelButton` 44 pt frames, the
`.padding(.vertical, 10)` removal, both audit tests dropping `.hitRegion`):

> No remaining Critical/High/Medium findings in the in-scope diff.

Confirmed:
- Both elements own a ≥44 pt framed accessibility element (correct modifier
  order — `.accessibilityIdentifier` applied after `.frame`/`.contentShape`).
- Removing `.padding(.vertical, 10)` is correct — field height governed by
  the `TextField`'s 44 pt minimum, no height inflation.
- Re-enabling `.hitRegion` in both search-sheet audits is the right GREEN
  evidence for the stated acceptance bar.
- Design-parity verdict: **exempt** — accessibility-compliance repair, no
  fresh design bundle required.
- VReader compliance: no concurrency / `@MainActor` regressions, file sizes
  small, follows local conventions.

## Round 3 — keyboard-chrome test infrastructure (commit `dfc3f6e`)

After round 2's sign-off, the test gate revealed both search-sheet
accessibility UITests were **flaky** once `.hitRegion` was re-enabled.
Root cause (captured via instrumented `performAccessibilityAudit`): the
`SearchBar` auto-focuses its field → the software keyboard rises → the
whole-app audit catches the keyboard's QuickType / predictive-text bar
(`TUIPredictionViewCell`, "missing useful accessibility information") —
an Apple keyboard-internal gap. Ground truth: offending element frame
`(0, 539, 134, 44)`, keyboard frame `(0, 583, 402, 233)` — the QuickType
strip sits flush *above* `app.keyboards`' own frame.

Commit `dfc3f6e` adds an additive `ignoringKeyboardElements: Bool = false`
parameter to `auditCurrentScreen` plus an `isSystemKeyboardChrome` helper
(vertical-band test — strict containment misses the QuickType strip). The
two search-sheet tests opt in; the other 20+ call sites are unaffected.

Codex round-3 verdict on `dfc3f6e`:

> No findings in `dfc3f6e`.

Confirmed:
- Additive parameter is non-breaking — existing call sites keep prior
  behavior.
- The classifier correctly tags the captured QuickType cell as keyboard
  chrome.
- It does **not** mask the #902 regression — the filter only ignores the
  keyboard's bottom band; real sub-44 pt `searchTextField` /
  `searchCancelButton` (which sit well above the keyboard) would still be
  audited and fail `.hitRegion`.
- The `60` pt QuickType-strip cap is a defensible upper bound; nil-keyboard
  and empty-frame guards are correct.
- VReader compliance fine — helper placement, docs, Swift, test scoping.

Both search-sheet audit tests now pass deterministically (3/3 runs each,
iPhone 17 Pro Simulator, iOS 26.5).

## Final verdict

**ship-as-is.** #902's three commits (`9c561d7` SearchBar 44 pt fix,
`766cd79` audit log, `dfc3f6e` keyboard-chrome test infra) are clean. The
sibling `searchClearButton` sub-44 pt touch target is logged separately as
its own bug / GH issue (out of #902's named scope), per the round-1/2 scope
decision above.
