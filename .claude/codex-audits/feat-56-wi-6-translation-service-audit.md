---
branch: feat/56-wi-6-translation-service
threadId: 019e417a-2e61-7ba2-a24e-fcf30d8da758
rounds: 3
final_verdict: ship-as-is
date: 2026-05-20
---

# Codex Audit — feat/56-wi-6-translation-service

**Feature**: #56 — bilingual reading mode (WI-6, foundational — the capstone
foundational WI).
**Scope**: `ChapterTranslationService` actor (cache lookup → segment → chunk
→ per-chunk request → strict JSON-array decode → per-segment fallback →
cache-write), plus `TranslationRequestSending`, `ChapterTranslationError`,
`ChapterTranslationResult`, `TranslationGranularity`.
**Auditor**: Codex (`mcp__plugin_codex-toolkit_codex__codex`), read-only sandbox.
**Thread**: `019e417a-2e61-7ba2-a24e-fcf30d8da758`. Gate 4 — implementation audit.

## Round 1 — 4 findings (0 Critical, 0 High, 2 Medium, 2 Low)

Codex confirmed no recombination bug, correct cancellation granularity.

1. **Medium — stale cache served.** A cached row was returned before the live
   source was segmented, so a row whose `sourceParagraphCount` no longer
   matched the live chapter was silently served (the plan's audit-driven
   additions require mismatched counts to be treated as stale).
   **Fix**: `translate(...)` now segments first; a cached row is served only
   when `cached.sourceParagraphCount == segments.count`; on a mismatch the row
   is deleted and the chapter re-translated.

2. **Medium — `.offline` never emitted.** Every non-cancellation failure
   collapsed to `.providerFailed`.
   **Fix**: added `mapTransportError(_:)` mapping connectivity errors to
   `.offline`.

3. **Low — cache-write `try?`** swallowed a store error (rule 50 §6).
   **Fix**: `do/catch` with an explicit log; the translation result is still
   returned (a cache-write failure must not fail the user's translation).

4. **Low — test coverage gaps** (stale-cache, cancellation mapping, specific
   error assertions).
   **Fix**: added stale-cache / fresh-cache / offline / cancellation tests;
   tightened the provider-error test to assert the exact typed case.

## Round 2 — 3 findings (0 Critical, 0 High, 1 Medium, 2 Low)

1. **Medium — `mapTransportError` over-classified `AIError.networkError` as
   `.offline`.** That error is a catch-all also thrown for invalid responses
   and misconfigured base URLs — mapping it to `.offline` would mis-drive the
   source-only fallback on a provider/config fault.
   **Fix**: `mapTransportError` no longer maps `AIError.networkError` at all —
   only a `URLError` with a connectivity code maps to `.offline`; everything
   else is `.providerFailed`.

2. **Low — stale-row delete still used `try?`.**
   **Fix**: `do/catch` with an explicit log (mirrors the cache-write pattern).

3. **Low — `cancelledTask` test non-specific.**
   **Fix**: the chunk loop is wrapped in `do/catch is CancellationError` →
   `ChapterTranslationError.cancelled`, so every `translate(...)` failure is a
   `ChapterTranslationError`; the test asserts the exact `.cancelled`.

## Round 3 — 0 findings

Codex confirmed: the offline mapping no longer has false positives; the Low
findings are resolved; wrapping the chunk loop to convert `CancellationError`
→ `.cancelled` is sound (does not swallow non-cancellation errors); no new
Critical/High/Medium introduced.

## Disposition

Zero Critical/High/Medium after round 3 (the rule-47 max). Final verdict:
**ship-as-is**.

### Plan-text note (not a code finding)

The plan's test-catalogue says "partial-failure leaves prior chunks cached".
The implementation does ONE all-or-nothing cache-write at the end. Codex
explicitly agreed the all-or-nothing behavior is **safer** — caching a partial
chapter is worse than caching nothing — and that the plan text, not the code,
should be corrected. Recorded here; the code keeps the all-or-nothing write.
