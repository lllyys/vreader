---
branch: fix/135-epub-jsescape-line-terminators
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-06
---

## Manual audit evidence

JS-escape consolidation. Manual audit performed.

### Files changed

| File | Change |
|---|---|
| `vreader/Views/Reader/EPUBHighlightBridge.swift` | `jsEscape` delegates to `FoliateJSEscaper.escapeForJSString`. |
| `vreaderTests/Views/Reader/EPUBHighlightBridgeTests.swift` | Two tests updated to match correct new behavior; one new test for U+2028/U+2029/tab. |
| `docs/bugs.md` | New row #135 (FIXED, Low). |

### Why fix

`EPUBHighlightBridge.jsEscape` covered: `\\ ' " \n \r`. Missed: `\t` U+2028 U+2029.

U+2028 (LINE SEPARATOR) and U+2029 (PARAGRAPH SEPARATOR) terminate JS string literals per ECMAScript. They appear legitimately in some CJK ebooks. `searchHighlightJS(textQuote:)` interpolates user-controlled text directly — a search query containing one would produce a JS SyntaxError → `window.find` never runs → highlight silently fails.

The shared `FoliateJSEscaper.escapeForJSString` already handles all three correctly. Bug #135 = single-source-of-truth consolidation.

### Tests updated

Two existing tests asserted the OLD behavior of escaping `"` to `\"`. That was over-defensive: in a single-quoted JS string literal, `"` doesn't need escaping (per ECMAScript). The new behavior matches `FoliateJSEscaper` and is more accurate.

- `createHighlightJS escapes special characters in ID`: was asserting `!js.contains("'quotes\"")` — strict negative match on the bare-substring would fail with the new (correct) impl since `"` is no longer escaped to `\"`. Updated to assert positive `\\'quotes` (apostrophe IS escaped).
- `removeHighlightJS escapes special characters`: same shape; now positively asserts `id\\'with"quotes` rather than negatively asserting against the un-escaped form.

One new test added: `searchHighlightJS escapes U+2028 / U+2029 / tab` — directly covers the bug's repro scenarios.

### Edge cases checked

- **Other call sites** (`createHighlightJS`, `removeHighlightJS`, `restoreHighlightsJS`): take constrained inputs (UUIDs, DOM paths from JS bridge, color names) so the U+2028/U+2029 risk is theoretical for them. The fix still applies — single source of truth.
- **Backslash-first ordering**: `FoliateJSEscaper` does backslash first, matching what the old impl did. No double-escape risk.
- **`"` no longer escaped**: only matters inside single-quoted strings. The bridge always uses single quotes (`'\\(escaped)'`). Verified by reading the JS-generation code paths.

### Tests added

- `searchHighlightJS escapes U+2028 / U+2029 / tab — bug #135`: locks in the fix at the production-call-site level.

### Verdict

**ship-as-is**. Single-line fix in production (delegate to FoliateJSEscaper) + 1 new test + 2 test updates to match correct new behavior. No regression risk; FoliateJSEscaper has its own well-vetted implementation already in production for the Foliate reader.
