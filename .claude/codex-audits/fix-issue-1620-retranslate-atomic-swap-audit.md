---
branch: fix/issue-1620-retranslate-atomic-swap
threadId: 019eb1dd-af18-74f3-86e2-9f8d43459506
rounds: 3
final_verdict: ship-as-is
date: 2026-06-10
---

# Gate-4 Codex audit — Bug #341 (re-translate destroys translation on failure, GH #1620)

Independent audit via `scripts/run-codex.sh` (gpt-5.4, read-only), briefed
adversarially with the full fix design (cache-read bypass + post-success
orphan delete) and explicitly pointed at the Bug #330 partial-degradation
interaction. Three rounds; round-2/-3 session ids
`019eb1e7-ff39-7190-b0e1-85f7844ead51` /
`019eb1ed-46c7-7000-9698-1aa8d007ac0f` (fresh `codex exec` invocations
continuing the same audit).

## Round 1

| file:line | severity | issue | resolution |
|---|---|---|---|
| ChapterReTranslateViewModel.swift:369 | Critical | The Bug #330 partial-degradation path returns SUCCESS without writing the cache (`lastChunkError != nil` skips the upsert); with a provider override the VM deleted the original-key row anyway → no replacement row on disk → reopen reproduces the original loss bug. | **Fixed** — durable-write check before the orphan delete. Regression test `partialDegradationWithOverride_keepsOriginalRow`. (Round 2 found the first version of this check insufficient — see below.) |
| ChapterReTranslateViewModel.swift:324 | Medium | Orphan-delete keys derived from mutable VM state (`selection`, `targetLanguage`) read across suspension points — a mid-flight selection change could translate under one key and delete by another. Separately, `initialProviderProfileID` is frozen at VM construction while the host reuses the VM across openings. | **Fixed (in-flight part)** — `runSubmit` snapshots `selection` + `targetLanguage` at entry (step 0) and resolve/translate/delete all read the snapshot. Regression test `midFlightSelectionChange_deletesBySubmittedSnapshotKey`. **Accepted with rationale (cross-session part)** — residual cost is a stranded stale row (disk, not data loss, once the delete is tied to a confirmed current-run write); Bug #342 (next in queue, GH #1621) removes `providerProfileID` from the cache key, eliminating this orphan-delete path at the root. Round 3 confirmed this acceptance as sound. |
| docs/architecture.md:217 | Low | Stale claim: "`submit()` deletes the original cache row by lookupKey" describes the pre-fix behavior. | **Fixed** — row updated to describe the atomic-swap flow. |

Round 1 also confirmed: `bypassCacheRead` default-false leaves
`BookTranslationCoordinator` + `ChapterTranslationPrefetcher` unchanged;
no Swift 6 actor-isolation violations; same-key failure/cancel/app-kill
loss paths closed by the no-delete-before-request change.

## Round 2

| file:line | severity | issue | resolution |
|---|---|---|---|
| ChapterReTranslateViewModel.swift:405 | High | The round-1 durable-write check (`store.translation(forKey: newKey) != nil`) treats a STALE pre-existing override row (from an earlier re-translate) as proof THIS run cached its replacement — a write-skipped partial degradation would still delete the original. | **Fixed** — `runSubmit` captures `submitTime = Date()` at step 0; the delete now requires `newRow.createdAt >= submitTime` (the store stamps `createdAt` at write time on both insert and replace). |
| ChapterReTranslateViewModelTests.swift:614 | Medium | `partialDegradationWithOverride_keepsOriginalRow` leaves `newKey` absent, so it passed without pinning the stale-pre-existing-row case. | **Fixed** — added `partialDegradationWithStalePreexistingOverrideRow_keepsOriginalRow` (seeds BOTH keys, success-without-cache-write, asserts the original survives). |

## Round 3

**CLEAN, ship-as-is.** Verified: the `createdAt >= submitTime` gate closes
the round-2 High (same device wall clock for both timestamps; the service
constructs the record only after translation completes; `>=` covers ties);
the new regression test correctly pins the stale-row case; no new issues
in the round-2 changes; the cross-session acceptance rationale is sound.

## Post-audit addition (not Swift-logic, verification harness)

`--mock-ai-fail-translate` launch flag (MockAIProvider /
AITestSetup / TestLaunchConfig): makes every `.translate` request throw a
deterministic provider failure so the close-gate device verification can
re-run the original repro (failed re-translate must keep the cached
translation). DEBUG-only, mirrors the `--mock-ai-translate-delay-ms`
precedent (feature #77 Gate-5b).

## Verdict

**ship-as-is** after 3 rounds. Critical + High + in-flight Medium fixed
with regression tests; cross-session Medium accepted with rationale and
superseded by Bug #342's key unification; Low doc drift fixed.
