---
branch: fix/issue-537-epub-paged-two-column
threadId: 019e1827-04bd-7593-96a1-59f78fea2030
rounds: 2
final_verdict: ship-as-is
date: 2026-05-12
---

# Codex Audit — Bug #171 (GH #537): EPUB paged mode shows two-column layout

Branch: `fix/issue-537-epub-paged-two-column`
Thread: `019e1827-04bd-7593-96a1-59f78fea2030`
Rounds: 2 (max 3 per rule 47)
Final verdict: **ship-as-is**

## Scope

Bug #171 — `EPUBPaginationHelper.paginationCSS(viewportWidth:viewportHeight:)`
set `column-width: (viewportWidth - 40)px` without enforcing
`column-count`. CSS `column-width` is a hint (minimum desired width); the
browser packs as many columns as fit. Some EPUBs' own stylesheets push
the body width beyond the viewport, producing a two-column "newspaper"
layout instead of the expected Kindle-style single-page flip.

Files changed:
- `vreader/Views/Reader/EPUBPaginationHelper.swift` — added `column-count: 1 !important` + clamped column-width to >= 1px + extended `!important` to all pagination params (round-2 fix).
- `vreaderTests/Views/Reader/EPUBPaginationTests.swift` — 3 new regression-guard tests + updated existing string-level assertions to pin `!important`.
- `docs/bugs.md` — added row 171 with GH: #537 link.

## Round 1 — follow-up-recommended

3 findings (2 Medium, 1 Low):

| # | Severity | Finding | Fix |
|---|---|---|---|
| 1 | Medium | `column-count: 1` at normal specificity could be beaten by book CSS via `!important` or higher selector specificity. Doesn't fully close the "book stylesheet interaction" class described in the bug. | Pin `column-count: 1 !important`. Other pagination params left at normal specificity in round 1 — addressed further in round 2. |
| 2 | Medium | String-contains tests don't verify actual WKWebView layout. Refactor could keep string while breaking injection timing/cascade. | **Accepted as out of scope** — vreaderTests has no precedent for WKWebView runtime-rendering integration tests; the project pattern is pure-logic + JS string-contains unit tests for the helper layer, and post-merge device verification for the rendered behaviour. Adding a WKWebView harness for a one-line CSS fix is over-engineering. Structural tests now pin the EXACT contract so a refactor cannot silently drop the directive. Post-merge close-gate device verification on iPhone 17 Pro Simulator will exercise the rendered behaviour. |
| 3 | Low | Pre-existing: helper emits negative `column-width` for sub-40pt viewports (transient state during Stage Manager / split-screen resize). | Clamped `max(Int(viewportWidth) - columnGap, 1)` and `max(Int(viewportHeight), 0)`. New regression-guard test `paginationCSS_clampsColumnWidthAtTinyViewport` covers the edge case. |

## Round 2 — ship-as-is

1 finding (1 Medium):

| # | Severity | Finding | Fix |
|---|---|---|---|
| 1 | Medium | `!important` on only `column-count` is enough to stop the visible two-column symptom, but not enough to keep paging math authoritative. Book CSS with `column-width: 600px !important` or `height: 100vh !important` could still leave one visible column while desynchronizing `scrollWidth / viewportWidth` so `totalPagesJS` and `navigateToPageJS` miscount. | Extended `!important` to the full pagination parameter set: `column-count`, `column-width`, `column-gap`, `column-fill`, `height`, and `overflow` (both html and body). `margin: 0` and `-webkit-column-break-inside: avoid` left at normal specificity — they're rendering hints, not paging invariants. Test `paginationCSS_paginationParamsImportant_bug171Round2` pins the contract. |

## Round 2 closing — ship-as-is

> "This is now materially complete for the bug as filed. Making the full paging invariant set reader-owned closes the real remaining gap from round 2: author `!important` on `column-width`, `column-gap`, `height`, or `overflow` can no longer desynchronize `scrollWidth`, page count, and `scrollLeft` navigation. The tiny-viewport clamp is also safe; with `column-count: 1 !important`, `column-width: 1px !important` is just a floor, not a path to runaway fragmentation."

Residual edge cases acknowledged as theoretical and NOT merge-blocking:

- An EPUB with inline `style="column-count:2 !important; ..."` on the `body` element could still outrank a stylesheet rule. (Inline styles always win against external `!important`.)
- Scripted mutation post-load could fight the injected CSS.

Both are uncommon hostile-author cases, not the issue reported in #537.

## Test gate

30 EPUBPagination tests pass on iPhone 17 Pro Simulator (iOS 26.4, build 17E202):
- CSS suite: 8 tests (was 6 pre-fix, +2 column-count `!important` regression guards + 1 tiny-viewport clamp)
- Navigate / TotalPages / CurrentPage / Calculation / StyleTag suites: unchanged (22 tests)

Test command:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
    -project vreader.xcodeproj -scheme vreader \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -only-testing:vreaderTests/EPUBPaginationCSSTests \
    -only-testing:vreaderTests/EPUBPaginationNavigateTests \
    -only-testing:vreaderTests/EPUBPaginationTotalPagesTests \
    -only-testing:vreaderTests/EPUBPaginationCurrentPageTests \
    -only-testing:vreaderTests/EPUBPaginationCalculationTests \
    -only-testing:vreaderTests/EPUBPaginationStyleTagTests
```

Result: `** TEST SUCCEEDED **`.
