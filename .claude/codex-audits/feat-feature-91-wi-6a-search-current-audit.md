---
branch: feat/feature-91-wi-6a-search-current
threadId: 019e9158-f373-7312-ae32-b08c72f8965a
rounds: 2
final_verdict: ship-as-is
date: 2026-06-04
---

# Codex Audit — Feature #91 WI-6a (SearchCurrentBookTool)

Gate-4 implementation audit (rule 47). Independent Codex runner via
`scripts/run-codex.sh -e high` (author/auditor separation, rule 48; rule-53
stdin-isolated watchdog).

## Scope

Behavioral WI-6a — the first agentic tool executor:

- `vreader/Services/AI/Tools/SearchCurrentBookTool.swift` (new) — `struct
  SearchCurrentBookTool: AITool`; wraps `SearchProviding.search` scoped to the
  open book's fingerprint (always page 0, pageSize = maxResults), strips FTS5
  `<b>…</b>` markers, formats one line per result, byte-clamps the content, and
  turns a missing query / search failure into an `isError` ToolResult — never a
  throw (the AITool contract).
- `vreaderTests/Services/AI/Tools/SearchCurrentBookToolTests.swift` (new) — a
  local capturing `SearchProviding` stub (records query / fingerprint / page /
  pageSize / callCount).

## Round 1 — findings (threadId 019e9144-b0cb-7af0-b3de-56dfe08b29ac)

Page-0 forwarding, `<b>`-strip, the Character-boundary UTF-8 clamp loop
(`max(0,…)` underflow-safe), and `Sendable` over `any SearchProviding` all
confirmed sound. Findings:

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| SearchCurrentBookTool.swift `run`/`format` | **Medium** | Only the populated-results path was byte-clamped; the `catch` + zero-match branches echoed `query` verbatim, so an oversized model-supplied query could blow the tool_result budget. | **Fixed.** Every return path now routes through `clamp(...)` (a private `errorResult(_:)` clamps error/missing-query text; `format` clamps both the zero-match and populated branches), and the echoed query is normalized to one short line via `oneLine(_:maxChars:120)` before reuse. |
| SearchCurrentBookTool.swift `format` line | **Medium** | `sourceContext` (book-controlled chapter/section text) was inserted verbatim while only the snippet was normalized — embedded newlines / `]` broke the documented one-line-per-result contract and let hostile book metadata shape the output. | **Fixed.** Both snippet AND sourceContext go through `oneLine()` (strip `<b>`, collapse whitespace/newlines, char-cap), and the row format changed to `N. snippet — source` (em-dash separator, no closing bracket a title could spoof). New test `sourceContextNormalizedToOneLine` pins one-line-per-result with an embedded-newline title. |
| SearchCurrentBookToolTests.swift | **Medium** | The forwarding test proved `query` + `page == 0` but not current-book scoping or the request-side cap (the reused shared stub captured neither `bookFingerprint` nor `pageSize`). | **Fixed.** Replaced with a local `CapturingSearch` actor that records `lastFingerprint` + `lastPageSize`; `searchesScopedAndFormats` asserts `lastFingerprint == bookFP` and `lastPageSize == maxResults`. |
| SearchCurrentBookToolTests.swift | Low | The "byte-bounded" test asserted only result count, never byte length / truncation marker / UTF-8 boundary. | **Fixed.** `contentIsByteBounded` feeds 8 multibyte (CJK) results with `maxContentBytes = 256` and asserts `result.content.utf8.count <= 256` AND the `…(truncated)` marker is present. |

## Round 2 — verification (threadId 019e9158-f373-7312-ae32-b08c72f8965a)

All four **RESOLVED**, **no new issues** in static review:

1. RESOLVED — every user-visible return path is byte-clamped; the echoed query is one-lined first.
2. RESOLVED — both snippet and sourceContext go through `oneLine()`; the `N. snippet — source` format removes the newline / `]` spoofing hole.
3. RESOLVED — the test asserts `lastFingerprint == bookFP` and `lastPageSize == maxResults` on the capturing stub.
4. RESOLVED — multibyte CJK byte-bound coverage with `utf8.count <= limit` + truncation-marker assertions.

(The auditor's sandbox couldn't run `xcodebuild`; verification was source-level.
The test gate was run by the author via `scripts/run-tests.sh
vreaderTests/SearchCurrentBookToolTests` → `RUN-TESTS RESULT: SUCCEEDED`,
10 tests.)

## Verdict

**ship-as-is.** Zero open Critical/High/Medium after round 2. `SearchCurrentBookToolTests`
green (10 tests: definition shape, scoped-page-0 forwarding + pageSize cap,
one-line normalization of hostile titles, zero-match non-error, missing/blank
query never calls search, thrown-search → isError, result cap, multibyte
byte-bound + truncation marker).
