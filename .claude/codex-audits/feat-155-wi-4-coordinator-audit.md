---
branch: feat/155-wi-4-coordinator
threadId: 019fd039-ec53-7ae1-9426-bb72f0c867ea
rounds: 3
final_verdict: block-recommended
---

# Gate-4 audit — feature #155 WI-4 (`IncomingImportCoordinator` + `BoundedCallGate`)

Runner: `scripts/run-codex.sh` (rule 53), read-only sandbox, three rounds.
Full transcripts: `.reports/audit-r1.txt`, `.reports/audit-r2.txt`, `.reports/audit-r3.txt`.

| Round | threadId | Verdict |
| --- | --- | --- |
| 1 | `019fd025-56a9-7c00-8c57-393a2ab58408` | block-recommended |
| 2 | `019fd031-3a49-7732-8e06-81d96d1193d5` | block-recommended |
| 3 | `019fd039-ec53-7ae1-9426-bb72f0c867ea` | block-recommended |

The audit was asked, each round, the questions the brief names as load-bearing: can the queue
wedge on any path; can a stream leak on any path (including late-result disposal); and does the
bounded-call primitive deliver D8's guarantee or merely RELOCATE the block the way
`withContext(Dispatchers.IO)` did.

## Round 1 — findings and disposition

| Sev | Finding | Disposition |
| --- | --- | --- |
| **Critical** | The dedicated thread did NOT contain the production block. `BookImporter.importStream` switches to its injected dispatcher internally, so with the default the untrusted read parked on a shared `Dispatchers.IO` worker — enough of them starve backup/OPDS/search. Worse, the slot was recycled on timeout, so parked reads were **not** bounded by `MAX_IN_FLIGHT`. Comments claiming isolation were "materially false". | **Fixed.** Blocking work now runs on a private ELASTIC daemon lane (`inboundBlockingLane()`); `AppContainer` pins BOTH the inbound `BookImporter` and `IncomingBookResolver` to it, so their internal dispatcher switches stay inside the lane. `BoundedCallGate` counts abandoned calls; `acquireSlot()` refuses at `MAX_ABANDONED_CALLS` and the count self-heals. |
| High | Cancelling `appScope` stranded every QUEUED item — open fds, held slots — and `enqueue` kept succeeding into a channel nobody drains. | **Fixed.** The worker's completion closes the queue and drains/releases every undelivered item; post-shutdown `enqueue` fails its `trySend` and releases there. |
| High | `releaseSlot()` could return a permit never held and steal another owner's, raising the cap for everyone. | **Fixed.** Admission is an idempotent `ImportSlot` token carried by `IncomingItem.Ready`, so ownership transfer is type-checked and a double release is a no-op. |
| High | `DROP_OLDEST` silently violated one-outcome-per-input past 64 pending outcomes. | **Fixed** (see round 2 for the final shape). |
| Medium | Streams were closed more than once; a hostile stream need not tolerate it. | **Fixed.** `CountingGuardStream` is close-once via an atomic flag shared by `close()` and `abort()`. |
| Medium | `wasAlreadyPresent`'s artifact-directory proxy is semantically incorrect. | **Documented**, per the auditor's stated alternative: the KDoc enumerates all four ways it lies. Exact signal needs `BookImporter` to return it — out of write-set, named as a follow-up. |
| Medium | `closeQuietly` caught `Exception`, so an `Error` from a provider's `close()` killed the single worker. | **Fixed** (refined in round 2). |
| Low | Not interrupting a pooled thread is the correct call. | Confirmed; no change. |
| Low | File over the ~300-line guideline. | Accepted: the write-set is exactly three files, so splitting was not permitted. Recorded as debt. |

## Round 2 — findings and disposition

| Sev | Finding | Disposition |
| --- | --- | --- |
| High | `closeQuietly` still rethrew `CancellationException`, which a hostile `close()` can throw like anything else. It replaced the item's outcome, propagated out of the sole worker, and in `shutdown()` aborted the drain, stranding every item behind it. | **Fixed.** Cleanup contains every non-fatal throwable; `shutdown()` isolates each drained item with its own `try/finally`. Two regression tests. |
| High | Cross-importer same-key rollback race: `promote -> upsert -> conditional rollback` is not atomic per key, so two concurrent same-key imports where one upsert FAILS can leave the winner's row pointing at a deleted artifact. | **Deferred, and the auditor agreed in round 3** that this is the correct disposition: the race is instance-independent (two calls on ONE `BookImporter` race identically), so it is pre-existing rather than introduced here, and fixing it needs a per-key lock inside `BookImporter.kt` — outside this WI's write-set. The `AppContainer` comment now states this precisely. **Reported as a follow-up in the HANDOFF.** |
| High | The `UNLIMITED` outcome channel made an exported entry point a memory-exhaustion surface. | **Fixed.** `Channel(MAX_PENDING_OUTCOMES = 256, DROP_LATEST)`: still cannot suspend the worker, bounded, degrades explicitly. Round 3 verified the explicit capacity IS honored (unlike `Channel.BUFFERED` + a non-SUSPEND policy, which collapses to 1 — the defect the round-1 tests caught). |
| Medium | `MAX_ABANDONED_CALLS` is a threshold, not the strict ceiling the code and test claimed. | **Documented honestly**: provable worst case is `MAX_ABANDONED_CALLS + MAX_IN_FLIGHT`. One strict combined budget was rejected in-code with rationale — it would let 20 stuck providers deny every future import, the silent-denial mode D8 rejected. Round 3 accepted this. |
| Medium | Swallowing every `Error` hid real VM corruption. | **Fixed.** `VirtualMachineError` / `ThreadDeath` / `LinkageError` propagate; everything a provider can throw is contained per item. |
| Low | Plan drift (D8/D9/§5/WI-4/WI-5 still describe the superseded shapes). | `dev-docs/` is orchestrator-owned; the exact drift list is in the HANDOFF. |

## Round 3 (final) — findings and disposition

| Sev | Finding | Disposition |
| --- | --- | --- |
| **High** | The input `queue` was still `Channel.UNLIMITED`: `Ready` items are bounded by `MAX_IN_FLIGHT`, but `PreResolved` envelopes hold no slot, so a hostile launch loop could enqueue faster than one worker drains. "Must-fix in WI-4 because the queue and its admission policy are implemented in this file." | **Fix applied** (`queueDepth` + `MAX_PENDING_ITEMS = 256`, refusing the newest PreResolved, mirroring the outcome channel's DROP_LATEST) **but NOT independently re-audited — the 3-round cap was reached.** New test `PreResolved envelopes cannot grow the queue without bound while the worker is busy`; mutation-verified. |
| Medium | The multithreaded admission test decremented its own counter before releasing, so `peak <= MAX_IN_FLIGHT` did not strictly prove the bound; it also never asserted the threads terminated. | **Fixed** exactly as instructed: release before un-counting, plus `threads.none { it.isAlive }`. |

Round 3 explicitly verified as **complete**: the cleanup-cancellation containment and per-item
shutdown isolation; the honored `Channel(256, DROP_LATEST)` capacity and honest degradation
wording; the fatal-error policy. It rated the abandoned-call threshold an acceptable resolution
and the same-key rollback race "correctly deferred", and found **no new Critical**.

## Why this artifact records `block-recommended`

Rule 47's Gate-4 bar is three audit-fix rounds, then escalate — and the brief is explicit: *do not
certify your own fix to an independent auditor's finding.* Round 3's High was fixed and
mutation-tested, but the fix itself has had **no independent review**, so the honest verdict at the
cap is `block-recommended` and the lane returns `outcome: blocked`. The merge-gate hook will refuse
`gh pr merge` on this verdict by design; the orchestrator decides whether to spend a fourth audit
round on the (small, localized) delta or to escalate.

## Mutation pass (run against the FINAL shipped code, all six killed)

| Mutation | Test that went RED |
| --- | --- |
| `sourceUri` re-derived from `pending.uri.toString()` | `the pre-capped sourceUri is passed to the importer VERBATIM` |
| Slot released only on non-timeout paths | 6 RED, incl. `liveness is GUARANTEED …` and `abandoned calls are bounded …` |
| Guard stream not closed on the over-cap path | `an undeclared oversize stream …`, `an endless stream …` |
| Outcome `Channel` → non-replaying `MutableSharedFlow` | 20 RED, incl. `… every outcome reaches a LATE collector` |
| Late-result disposal skipped in `BoundedCallGate` | `a late result is DISPOSED, never leaked` |
| Input-queue bound removed for `PreResolved` | `PreResolved envelopes cannot grow the queue without bound …` |

## Test gate

`RUN-ANDROID-TESTS RESULT: SUCCEEDED` — 168 tests / 0 failures across
`*imports*` + `*BookImporterTest*` (33 in `IncomingImportCoordinatorTest`; in-package baseline
was unchanged and green).
