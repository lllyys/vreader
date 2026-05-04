---
branch: fix/codex-audit-followup
threadId: 019df29d-02f3-74b2-8670-661dd7caa97b
rounds: 4
final_verdict: ship-as-is
date: 2026-05-04
---

# Codex audit log — fix/codex-audit-followup

Audits the consistency-after-failure follow-up to the v3.12.6..v3.12.9 bug fixes (#115, #116, #112, #114). Original audit (3 rounds against v3.12.9) found 4 issues; this PR fixes 3 of them (#117, #118, #119) and the iterative review caught 4 more during the fix itself.

## Round 1

**Findings**:

| Severity | Where | Issue |
|---|---|---|
| Medium | `LazyDownloadFinalizer.finalize()` | Two-call persistence (setBookFileState + setBlobPath) leaves row half-promoted on second-call failure. Comment "reconcile will retry" is wrong — reconcile only scans `.downloading` rows. |
| Low | `insertRemoteOnlyBookRecords` | Returns ALL processed keys, including dedupe-hits with existing `.local` rows. SelectiveRestoreCoordinator then posts `.bookFileStateDidChange(state: remoteOnly)` for rows that are actually `.local`. |

**Verdict**: Follow-up needed. Fixed both inline.

## Round 2

After fix:

**Findings**:

| Severity | Where | Issue |
|---|---|---|
| Medium | `LazyDownloadCoordinator.reattachAndReconcile` recovery branch | Uses `bookRecord.originalExtension` ("mobi" for an AZW3 imported as .mobi) but the live lazy-download path writes the file under canonical `BookFormat.fileExtensions.first` ("azw3"). Recovery would miss the file under the wrong extension. |
| Low | Test coverage | Tests exercised `tryPromoteFromDisk` in isolation but no integration test asserted reattach actually suppresses `.failed` transition when recovery succeeds. |

**Verdict**: Follow-up needed. Fixed both — `tryPromoteFromDisk` now takes `candidateExtensions: [String]`, reconcile passes both originalExtension AND canonical extension. New integration test in `LazyDownloadReattachTests` (`reattach_canonicalFileOnDiskWithMatchingSHA_recoversToLocalAndSuppressesFailed`) wires a real finalizer + seeds two rows (one matching, one not) and asserts the matching row recovers to `.local` while the non-matching row still flips to `.failed`.

## Round 3

After fix:

**Findings**:

| Severity | Where | Issue |
|---|---|---|
| Low | `insertRemoteOnlyBookRecords` | TOCTOU window between `findBook` (returns nil) and `insertBook` (idempotent dedupe). A concurrent `.local` insert in that gap would make this code append the key as "inserted" and post `.bookFileStateDidChange(state: remoteOnly)` for a row that's actually `.local`. |

**Verdict**: Follow-up needed. Fixed by collapsing the per-record decision into a single synchronous `ModelContext` block (fetch → if-empty insert+save → append), no inter-call await.

## Round 4

After fix:

**Verdict**: **Ship as-is.**

> The TOCTOU window is closed for the app's intended write path: there's no `await` between fetch and save, the whole per-record decision runs inside one `PersistenceActor` turn with one `ModelContext`, and `insertedKeys` is now appended only after a successful inline create+save.
>
> Only caveat: this assumes the repo's existing contract holds that SwiftData writes go through `PersistenceActor`. If some external code writes the same `Book` concurrently through another context, that broader invariant is still outside this helper. Nothing in this diff blocks shipping.

## Test coverage

| Suite | Before | After | New |
|---|---|---|---|
| WebDAVBlobStoreTests | 12 | 14 | +2 (bug #117 + ancestor ordering) |
| PersistenceActorRemoteOnlyTests | 13 | 15 | +2 (promoteToLocalClearBlob + unknown key) |
| LazyDownloadFinalizerTests | 5 | 9 | +4 (recovery: matching SHA, second candidate ext, missing file, wrong SHA) |
| LazyDownloadReattachTests | 14 | 15 | +1 (integration: end-to-end recovery suppresses .failed) |
| SelectiveRestoreCoordinatorTests | 8 | 9 | +1 (bug #119 partial-success notifications) |
| Total | | 116 | +10 |

All 116 tests across 8 affected suites pass. Full unit suite: 710 tests, 20 pre-existing failures unchanged (TXTChapterContentLoader, V1toV2Migration, DebugFixture).

## What still might bite us

The ship-as-is verdict has one caveat Codex named explicitly: "this assumes the repo's existing contract holds that SwiftData writes go through `PersistenceActor`." If anywhere in the codebase writes `Book` rows via a `ModelContext` that's not the actor's, the inline TOCTOU close-out doesn't help. Worth a follow-up audit to grep for any `ModelContext(modelContainer)` outside `PersistenceActor*.swift`.
