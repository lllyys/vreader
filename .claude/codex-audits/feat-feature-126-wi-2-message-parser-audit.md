---
branch: feat/feature-126-wi-2-message-parser
threadId: 019f114f-416f-79c3-a0df-6c7574a32398
rounds: 1
final_verdict: follow-up-recommended
date: 2026-06-29
---

# Gate-4 audit — feature #126 WI-2 (FoliateMessageParser)

Codex (gpt-5.5/high) audited the pure bridge-message parser. Verdict:
**follow-up-recommended** (1 Medium, 2 Low). The auditor confirmed the kotlinx
usage is idiomatic and that `prim(key)?.takeIf { it.isString }` is the correct API to
distinguish a JSON string from number/bool/null. All findings fixed in-branch:

| # | sev | finding | resolution |
|---|---|---|---|
| 1 | **Medium** | `int()/dbl()` parsed from `JsonPrimitive.content`, so a quoted numeric string (`"3"`) was accepted as a number AND `"fraction":"NaN"`/`"Infinity"` could yield a non-finite Double — corrupting the `fraction` resume anchor (hostile-payload gap). | **Fixed** — `int()`/`dbl()` now reject JSON strings (`takeUnless { it.isString }`) and `dbl()` requires `isFinite()`. Tests `nonFiniteOrStringFraction_isRejected` + `quotedNumericSectionIndex_isRejected_defaults` lock it. |
| 2 | Low | `str()` documented "non-blank" but only rejected `""` → `"name":"   "` became `Other("   ")`. | **Fixed** — `str()` uses `isNotBlank()`; a blank `name` now → `null` (non-usable). Test `blankName_returnsNull`. |
| 3 | Low | Tests didn't lock hostile scalar types (numeric/null/bool name & title, NaN/Infinity fraction, non-object detail). | **Fixed** — added `nonStringName_returnsNull`, `numericOrNullTitle_isAbsent`, `nonFiniteOrStringFraction_isRejected`, `nonObjectDetail_degradesToEmpty`, etc. |

The parser never throws (parse wraps decode in `runCatching`, returns `null` for
non-usable input, `Other` for unknown names) — safe inside the WebMessageListener callback.

Re-verification: `FoliateMessageParserTest` **22/22** green via `:app:testDebugUnitTest`.

**Verdict: follow-up-recommended** — all findings fixed + test-proven in-branch.
