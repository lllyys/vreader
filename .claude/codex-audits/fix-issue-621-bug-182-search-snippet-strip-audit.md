---
branch: fix/issue-621-bug-182-search-snippet-strip
threadId: 019e2c4d-e91b-7353-afa5-263b6f79326d
rounds: 2
final_verdict: ship-as-is
date: 2026-05-15
---

# Codex Audit — Bug #182 / GH #621

EPUB cross-chapter search-tap silently produces no yellow highlight; PDF
in-page search-tap has the same dormant defect because both readers feed
`Locator.textQuote` to plain-text matchers (`window.find()` for EPUB,
`PDFDocument.findString` for PDF) and the resolver was stashing the raw
display snippet (`...prefix<b>match</b>suffix...`) as `textQuote`.

## Files changed

- `vreader/Services/Search/SearchHitToLocatorResolver.swift`
  (+47 −2; added `cleanSnippetForTextQuote(_:)`, routed `resolveEPUB` /
  `resolvePDF` through it)
- `vreaderTests/Services/Search/SearchHitToLocatorResolverTests.swift`
  (+194 −1; 13 new tests covering both indirect-via-resolve and direct
  `cleanSnippetForTextQuote` branches)

## Round 1 findings

| File:line | Severity | Issue | Fix |
|---|---|---|---|
| `SearchHitToLocatorResolver.swift:135` | Low | `stripHTMLTags` was a permissive `<…>` walker — math notation `1 < 2 > 1` would have been mangled into `1 1` | Replaced with two targeted `replacingOccurrences(of:with:)` calls — one for `<b>`, one for `</b>`. Helper function removed. Literal angle brackets now pass through unchanged. |
| `SearchHitToLocatorResolverTests.swift:242` | Low | Initial 5 tests covered happy path but not the branches most likely to silently regress: `nil`, `""`, whitespace-only, `<b></b>`, `<b>   </b>`, lone `<b>` / `</b>` | Added 8 direct unit tests on `cleanSnippetForTextQuote` covering each branch; added regression guard for the math-notation case that motivated finding #1. |
| `SearchHitToLocatorResolver.swift:94` | Low (architectural) | The fix still depends on parsing the display-snippet format. Future change to `extractSnippet` could re-break highlighting. | Accepted as known limitation. Better long-term shape is separating `snippet` (display) and `matchedText` (navigation) on `SearchHit`; filing as follow-up architectural cleanup. The new test suite catches regressions at this layer if extractSnippet changes shape. |

Also tightened the bold-extraction branch to trim before the empty check, so
`<b></b>` and `<b>   </b>` both return `nil` (whitespace-only matches are
useless to the downstream matchers).

## Round 2 verification

| File:line | Severity | Issue | Fix |
|---|---|---|---|
| `SearchHitToLocatorResolver.swift:108` | Low (doc drift) | Doc comment still said the fallback "strips any straggling HTML tags," which is no longer true after the targeted change | Updated doc comment to say "any literal `<b>` / `</b>` markers"; explicitly noted math notation / generics are preserved verbatim. |

Codex confirmed: "No findings on correctness, security, or branch coverage."
The narrowed fallback is sound, the trim-before-empty-check is sound, the
new tests cover the flagged branches.

## Resolution summary

- All 3 Low findings from round 1: fixed (#1, #2) or accepted with rationale (#3).
- 1 Low doc-drift finding from round 2: fixed.
- Zero open findings of any severity.

## Manual audit evidence

Not applicable — Codex MCP was available for both rounds (thread
`019e2c4d-e91b-7353-afa5-263b6f79326d`).

## Test gate

`xcodebuild test -only-testing:vreaderTests/SearchHitToLocatorResolverTests`
→ 24 tests, all pass.

Full suite `xcodebuild test -only-testing:vreaderTests` → 1050 tests, 4
pre-existing unrelated failures (BookFormatAZW3 × 2 and
SelectiveRestoreCoordinator × 2), confirmed against clean `main` via
`git stash` + targeted re-run; my changes do not touch those subsystems.

## Final verdict

**ship-as-is**.

The fix delivers the symptom resolution promised in the bug report: EPUB
cross-chapter and PDF in-page search-tap now produce a non-empty,
plain-text `textQuote` that the readers can find via their respective
matchers. The known limitation (snippet-format coupling) is filed as a
future architectural cleanup, not a blocker.
