---
branch: feat/feature-71-wi-3-continuous-scroll-js
threadId: 019e6168-8d0d-7750-8246-5d8695820f9e
rounds: 2
final_verdict: ship-as-is
date: 2026-05-26
---

# Codex Gate-4 audit — Feature #71 WI-3 (EPUBContinuousScrollJS)

Independent audit (Codex MCP, separate process) of the pure JS-string
generators for the EPUB continuous-scroll multi-chapter document.

Files audited (new):
- `vreader/Views/Reader/EPUBContinuousScrollJS.swift` (235 lines, 7 generators)
- `vreaderTests/Views/Reader/EPUBContinuousScrollJSTests.swift` (13 tests, green)

## Round 1 — 1 Medium

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 1 | Medium | `removeChapterSectionJS` removed a section with no scroll compensation. `EPUBSpineWindow.evictFarFromAnchor` can trim the TOP end (when the reader scrolled down); removing a section above the viewport collapses content upward → the reader jumps. | **Fixed** — the generator now captures `wasAbove = el.offsetTop < root.scrollTop` + `before = root.scrollHeight`, removes the element, and for an above-viewport removal does `root.scrollTop -= (before - root.scrollHeight)` (mirrors the prepend anchor). Below-viewport removals are unchanged. Test strengthened to assert the compensation. |

## Round 2 — clean

No remaining Critical/High/Medium. Ship-as-is.

## Codex confirmations (no change needed)

- **Injection safety**: for the `evaluateJavaScript` context, single-quoted JS literals + `FoliateJSEscaper.escapeForJSString` are sufficient against literal breakout for `bodyHTML`, divider title, and search quote. `</script>` / backtick / `${` are irrelevant (not an HTML `<script>` context). `htmlEscape` (`&<>"`) on the divider title + href is enough before the section is JS-escaped.
- **Trust boundary**: this file intentionally does NOT sanitize active HTML in `bodyHTML`/`scopedStyleHTML` — matches the documented WI-2 trust boundary (`EPUBChapterBodyRewriter.swift`), not a new issue.
- **`themeCSS`** raw injection into `<style>` is acceptable as used (app-generated `FoliateStyleMapper.themeCSS`, not untrusted CSS). Becomes a `</style>` breakout only if the input ever widens to arbitrary CSS.
- **Prepend compensation** correct: `scrollHeight` reads before/after `insertAdjacentHTML` force synchronous layout, so `scrollTop += (after - before)` anchors the viewport.
- **Observer** (visibleSpineIndex = last section with `offsetTop <= scrollTop`, intraFraction, idempotency guard, near-boundary flags) sound for the direct-child-section DOM shape. **`scrollToSpineFractionJS`** clamp + non-finite→0 prevents `nan`/`inf`; Swift `Double` interpolation emits valid JS numerics.
- Empty body / nil divider / spineIndex 0 / missing section / CJK all fine.

## Verdict

**Ship-as-is.** Foundational tier (pure JS strings); covered by 13 unit tests +
the round-1 eviction-anchor fix. `restoreHighlightsInSectionJS` deferred to WI-6
(integration-coupled; not shipped untested).
