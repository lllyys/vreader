---
branch: fix/136-epub-css-jsescape-consolidation
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-06
---

## Manual audit evidence

Cluster-closing fix following bug #135. Manual audit performed.

### Files changed

| File | Change |
|---|---|
| `vreader/Views/Reader/EPUBWebViewBridgeJS.swift:50-53` | Inline 3-line escape replaced with `FoliateJSEscaper.escapeForJSString`. |
| `vreader/Views/Reader/EPUBPaginationHelper.swift:123-126` | Same. |
| `docs/bugs.md` | New row #136 (FIXED, Low, GH: #292). |

### Why low severity

Both call sites pass system-generated CSS (built from theme settings + viewport sizes — numeric values clamped upstream). No current input path delivers U+2028/U+2029 or other forbidden chars. This PR is consolidation against a future change.

### Edge cases checked

- **Build**: clean.
- **`EPUBPaginationTests`**: pass post-change. (No `EPUBWebViewBridgeJSTests` file exists; the tests for bridge JS happen inside the broader bridge test suites.)
- **`paginationCSS` upstream**: `viewportWidth`/`viewportHeight` are CGFloat → formatted via `Int()`. No way to inject U+2028. The CSS template itself is a static heredoc.
- **`injectThemeCSSJS` upstream**: callers pass a `<style>...</style>` tag; the function strips outer tags then escapes the inner CSS. The inner CSS is built from `ReaderTheme.css(fontSize:)` etc., all bound by enum cases + numeric values. No user-text path.

### What I deliberately did NOT change

- The CSS-extraction string-search at `injectThemeCSSJS:46-49`. It's fragile (literal `>` and `</style>` searches) but unrelated to the escape consolidation; out of scope. Left for a future audit.
- `EPUBPaginationHelper`'s upstream CSS-building functions: unchanged.

### Tests added

None. The escape consolidation produces a strict superset of the prior coverage. Existing `EPUBPaginationTests` regress nothing.

### Verdict

**ship-as-is**. Two-file consolidation. No behavior change for current inputs (constrained); strict superset of escapes for any future input. Closes the inline-escape cluster across the EPUB stack.
