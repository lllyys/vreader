---
branch: feat/165-wi-4b-bounded-saf
threadId: 019fd3a5-d4c0-74d0-9111-ada30767fc68
rounds: 3
final_verdict: block-recommended
---

# Gate 4 — feature #165 WI-4b, the bounded SAF I/O boundary

Auditor: Codex `gpt-5.5`, reasoning `high`, read-only sandbox, via `scripts/run-codex.sh` (rule 53).
Three rounds, one thread per round:

| Round | Codex session | Raw log |
| --- | --- | --- |
| 1 | `019fd392-415d-7c60-8eb6-0cf9b8648c40` | `.reports/audit-r1.txt` |
| 2 | `019fd39e-93dc-73a2-90f7-09d32302427b` | `.reports/audit-r2.txt` |
| 3 | `019fd3a5-d4c0-74d0-9111-ada30767fc68` | `.reports/audit-r3.txt` |

Scope audited: `annotations/AnnotationsIoController.kt`, `annotations/SafDocumentPort.kt`,
`annotations/SafCleanup.kt`, and the three JVM suites under
`android/app/src/test/kotlin/com/vreader/app/annotations/`. `imports/**` was read-only context.

Every round was asked the same four standing questions: is every provider call bounded in BOTH
directions with no path that can park before a bound applies; is `dispose` genuinely mandatory
wherever a late result can be a `Closeable`; can a second `BoundedCallGate` be constructed or a
ledger other than the injected one be charged; and does any test depend on the BEST-EFFORT unblock
rather than on the GUARANTEE.

## Round 1 — 1 Critical, 2 High, 2 Medium, 1 Low

1. **CRITICAL — the timeout path could still wedge the caller.** `BoundedCallGate` runs `onExpiry`
   **synchronously on the caller's coroutine** immediately before returning `TimedOut`
   (`IncomingImportCoordinator.kt:228-231`). The round-1 code called `guard.abort()` / `closeQuietly(sink)`
   there, so a provider whose `close()` parks re-opened the exact defect this WI exists to close.
   Every park case was green at the time, because their fakes all closed promptly.
   **Fixed**: expiry cleanup is dispatched to a daemon lane and awaited by nobody
   (`SafCleanup.releaseAfterExpiry`). **Covered** by two new cases where the transfer AND its rescue
   close both park forever.
2. **HIGH — admission was not re-checked before the transfer.** A concurrent activity can spend the
   shared budget between the open and the read/write. **Fixed**: re-checked after `openInput` /
   `openOutput`, closing the descriptor and returning `Busy`. Cleanup close is deliberately NOT
   admission-gated — refusing cleanup trades a bounded wait for a certain fd leak.
3. **HIGH — export close failures were reported as a successful save.** For a SAF descriptor
   `close()` is where the write commits, so a swallowed close could tell the user a file exists that
   does not. **Fixed**: export uses a strict bounded close (throw → `Unreadable`, timeout →
   `Timeout`); import keeps a quiet, ignored close because its bytes were already read.
4. **MEDIUM — no import-close park case.** **Fixed**: `importCloseParkedForever_previewStillReturnsItsAnswer`.
5. **MEDIUM — the read/write fakes closed promptly**, so they could not catch finding 1.
   **Fixed**: `ParkingInputStream` / `ParkingOutputStream` take an optional `closeLatch`.
6. **LOW — fatal `Throwable`s were mapped to `ImportFailure.Unreadable`.** The gate wraps every
   `Throwable` into `BoundedCall.Failed`. **Fixed**: `rethrowIfFatal` on every `Failed` arm.

## Round 2 — 2 High, 1 Low (round-1 Critical confirmed closed)

1. **HIGH — the new expiry lane was itself unbounded.** A cached pool meant a parked rescue close
   held a thread NO ledger charges (the gate's count self-heals when the original call returns).
   **Fixed**: zero-core `ThreadPoolExecutor` over a `SynchronousQueue`, `maximumPoolSize =
   MAX_EXPIRY_CLOSES`, `DiscardPolicy` — past the cap the best-effort close is dropped, which is
   legal precisely because nothing depends on it. **Covered** by
   `theBestEffortCloseLaneIsBoundedAndNeverBlocksTheCaller`.
2. **LOW — quiet close discarded the `BoundedCall` result**, losing fatal errors the gate had
   wrapped. **Fixed**: `closeQuietly` inspects `Failed` and calls `rethrowIfFatal`.
3. **HIGH, ACCEPTED AS AN INHERITED RESIDUAL — admission is a CHECK, not a RESERVATION.**
   `BoundedCallGate` charges the ledger only on give-up, so two concurrent callers can both pass the
   same check. This is a property of the **shipped** gate — whose own KDoc
   (`IncomingImportCoordinator.kt:265-267`) already records it as a filed follow-up — and
   `imports/**` is read-only for this feature. The auditor's suggested in-scope fix, a
   controller-side reservation counter, is **exactly the second admission budget §8.5 forbids**: two
   budgets each admit their own quota and double the ceiling they exist to lower. Round 3 was asked
   to judge that reasoning and agreed: *"Accepting the inherited admission race is reasonable under
   this scope. I do not see an in-scope fix that preserves 'one injected gate/ledger' and leaves
   `imports/**` untouched."* Documented in the controller header.

## Round 3 — 1 High. **Verdict: `block-recommended`.**

**HIGH — a timed-out transfer could still leak its descriptor once rescue submissions start being
discarded.** Round 2's cap made the lane safe but created a new hole: `READ`/`WRITE` return a value,
not a `Closeable`, so they had no `dispose`; the reader and the writer both deliberately leave the
stream to their caller; and once `DiscardPolicy` drops the rescue, nothing owns that descriptor when
the parked transfer finally returns.

**Fixed after round 3** (and therefore NOT independently re-audited — see below):

- both transfers now carry a `dispose` that closes directly on the abandoned job's own thread, where
  blocking delays nobody and the ledger's charge correctly persists while the fd is genuinely held;
- both opens' `dispose` likewise closes directly instead of dispatching (a dispatched dispose
  inherits the discard — a mutation proved that case was untested, and the test was added);
- `CloseOnce` gives the export sink the close-once discipline `CountingGuardStream` already provides
  on the import side, so `onExpiry`, `dispose` and the ordinary close cannot double-close;
- four new cases: both directions' "rescue discarded, descriptor still closed", and both
  directions' "late-opened stream disposed while the lane is saturated".

## Why this hands off `blocked` rather than clean

The audit ladder's cap is three rounds. Round 3 returned `block-recommended`, its finding was fixed
and mutation-covered, but **the lane may not certify its own fix to an auditor's finding**. A
round-4 independent audit of the round-3 fix is the remaining gate. Nothing else is open:
round 1's Critical and round 2's High/Low are confirmed closed by round 3, and round 2's
admission-reservation High is an accepted inherited residual with the auditor's concurrence.

## Residuals shipped knowingly

- **Admission is a threshold, not a hard cap** (round 2 item 3) — belongs to `BoundedCallGate`, a
  filed follow-up against `IncomingImportCoordinator`, out of this write-set.
- **A hostile provider that parks in `close()` can pin ledger slots.** With `dispose` closing on the
  abandoned job's thread, the charge persists until the close returns. That is the honest accounting
  — the descriptor really is still held — and it never blocks a caller.
- **A rescue close that wins the race and then parks leaves the fd un-closed**, with `dispose`
  seeing the close-once flag already set. Bounded to `MAX_EXPIRY_CLOSES` threads; the caller is
  unaffected.

## Test-gate evidence

`ANDROID_CMD="cd android && ./gradlew :app:testDebugUnitTest --tests '*ackup*' --tests '*nnotation*'
--rerun-tasks" scripts/run-android-tests.sh` → `RUN-ANDROID-TESTS RESULT: SUCCEEDED`,
**313 tests / 0 failures across 32 classes**, run twice consecutively to rule out the order-dependence
that an earlier revision of these tests genuinely had.
