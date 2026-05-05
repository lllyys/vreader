---
branch: refactor/consolidate-foliatets-jsescape
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-06
---

## Manual audit evidence

Follow-up consolidation to bug #135. Manual audit performed.

### Files changed

| File | Change |
|---|---|
| `vreader/Services/Foliate/FoliateTTSAdapter.swift` | Two call sites delegate to `FoliateJSEscaper.escapeForJSString`; the private duplicate `escapeForJS` removed. |

### Why fix

Same incomplete-escape pattern as bug #135 (which fixed the EPUB-side `jsEscape`). `FoliateTTSAdapter.escapeForJS` covered only `\\`, `'`, `\n`, `\r` — missing `\t`, U+2028, U+2029.

Inputs to `initTTSJS` (granularity: "word"/"sentence") and `setMarkJS` (numeric string from Intl.Segmenter) are constrained today, so this is **not an active vulnerability** — purely consolidation against a future change that might pass user-controlled input through these helpers.

### What I deliberately did NOT change

- The two function signatures (`initTTSJS`, `setMarkJS`).
- The interpolation patterns (single-quoted JS strings).
- Existing tests: `FoliateTTSAdapterTests` continues to pass; assertions don't depend on which characters get escaped.

### Edge cases checked

- **Build**: clean.
- **Tests**: `FoliateTTSAdapterTests` passes unchanged.
- **Other call sites of removed `escapeForJS`**: grep returned only the two `static func ...JS` sites within the same file. Both updated.

### Verdict

**ship-as-is**. Two-line consolidation + 1-block deletion. No behavior change for current inputs (constrained); strict superset of escapes for any future input.
