---
branch: feat/feature-75-wi2-pagination-axis
threadId: codex-exec-readonly
rounds: 1
final_verdict: ship-as-is
date: 2026-05-31
---

# Codex audit — Feature #75 WI-2 (EPUBPaginationHelper axis-aware generators)

Read-only `codex exec` audit. Foundational WI (pure string/Int generators →
unit-tested; WKWebView multicol layout validated on-device in WI-5).

## Summary

New pure `EPUBPagedAxis` — `scrollOffset(page:viewportWidth:axis:)` (LTR positive,
RTL/verticalRL negative `scrollLeft`) + `directionCSS(axis:)` (LTR empty, RTL
`direction:rtl`, verticalRL `writing-mode`+`direction`). Wired into
`navigateToPageJS`, `paginationCSS`, `injectPaginationCSSJS` with `axis` defaulting
to `.horizontalLTR` so existing callers are unchanged.

## Round 1 findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| EPUBPaginationHelper.swift:76 | Low | LTR not byte-identical — empty directionCSS line added whitespace. | Fixed — conditional `directionLine` (empty for LTR); test `paginationCSS_ltr_defaultMatchesExplicitLTR` pins byte-identity. |
| EPUBPaginationHelper.swift:233 | Medium | `injectPaginationCSSJS` wrapper had no axis param → runtime paged path couldn't inject RTL/vertical CSS. | Fixed — added `axis: PageAxis = .horizontalLTR`, threaded to `paginationCSS`. |

Codex confirmed: RTL negative-`scrollLeft` + page-0=0 correct; verticalRL reusing
RTL offset acceptable as a WI-2 hypothesis with WI-5 device validation BINDING
before claiming vertical support; clamps correct; no Swift 6 issue.

## Verdict

ship-as-is. Tests: `EPUBPagedAxisTests` (offset + directionCSS + paginationCSS
LTR-byte-identity + RTL/vertical injection + navigateToPageJS RTL) green; existing
`EPUBPaginationTests` unchanged. verticalRL scroll axis is device-validated in WI-5.
