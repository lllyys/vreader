---
branch: fix/issue-1581-translate-timeout-not-offline
threadId: 019eac1a-fd12-7920-8d21-fe2b72243b5d
rounds: 1
final_verdict: ship-as-is
date: 2026-06-09
---

# Codex Audit — Bug #333 / GH #1581 (long-chapter re-translate timeout mislabeled "offline")

## Root cause

`ChapterTranslationService.mapTransportError` mapped `URLError` `.timedOut` AND
`.cannotConnectToHost` to `.offline` alongside the genuine connectivity codes, so a
long-chapter request that TIMED OUT (large payload / slow provider) surfaced as
"You appear to be offline" while the device was online.

## Fix

- `.notConnectedToInternet` / `.networkConnectionLost` / `.dataNotAllowed` → `.offline` (genuine connectivity).
- `.timedOut` → NEW `ChapterTranslationError.timedOut` (distinct "request timed out — chapter may be too long" message in `ChapterReTranslateViewModel`).
- `.cannotConnectToHost` → `.providerFailed` (provider/config fault, not device offline).

## Round 1 findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| ChapterPrefetching.swift:13 | Low | The protocol's error-contract comment still listed only `.offline`/`.cancelled`/`.providerFailed`, omitting the new `.timedOut`. Stale doc could mislead consumers into assuming timeout collapses into another bucket. | **Fixed** — comment now names `.timedOut` explicitly as a non-offline transient failure that leaves the unit retryable. |

Codex confirmed (no functional findings): the semantic split is correct
(timeout ≠ offline, host-unreachable ≠ offline); the bilingual prefetch path
(`BilingualReadingViewModel+Prefetch`) special-cases only `.offline`/cancellation,
so the new `.timedOut` falls into the generic failure → `.failed` (unit left
unfetched + retryable) — the correct behavior for a prefetch timeout; `Equatable`
still holds; no consumer pattern-matched `.offline` expecting it to also mean timeout.

## Verification (exception)

A real provider timeout can't be reproduced on a device without a fault-injection
harness. High-fidelity integration tests drive the SAME code paths the production
failure hits:
- `ChapterTranslationServiceTests.timedOutURLError_throwsTimedOutNotOffline` — injects
  `URLError(.timedOut)` through the real `translate()` boundary; `mapTransportError` runs
  for real and yields `.timedOut` (not `.offline`).
- `...cannotConnectToHostURLError_throwsProviderFailedNotOffline` — `.cannotConnectToHost`
  → `.providerFailed` (not `.offline`).
- `ChapterReTranslateViewModelTests.submit_timeout_showsTimedOutNotOffline` — the real
  `errorMessage` renders the timeout copy and NOT "offline".

## Verdict

ship-as-is — the one doc Low fixed; semantic split confirmed correct; covered by
high-fidelity integration tests at the real `translate()` + ViewModel boundaries.
