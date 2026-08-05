---
branch: feat/155-wi-5-activity
threadId: 019fd0b6-8423-7500-925b-0b56054f9f9f
rounds: 3
final_verdict: follow-up-recommended
date: 2026-08-05
---

# Codex Audit Log — feature #155 WI-5 (ImportActivity end-to-end)

Work item: wire the exported inbound-document entry point — `urisFrom(intent)` → per URI
{ self-targeting guard → BOUNDED `peek` → pre-open size/free-space preflight → BOUNDED
`resolveAndOpen` → in-flight slot } → `enqueue` on the process-wide coordinator → hand off to
MainActivity → `finish()`.

Write-set (binding): `imports/ImportActivity.kt`, `MainActivity.kt`, `res/values/strings.xml`
(untouched — see Rule 51 below), `androidTest/.../IncomingIntentImportConnectedTest.kt`.
`IncomingImportCoordinator.kt`, `IncomingBookResolver.kt`, `LibraryViewModel.kt`, `VReaderApp.kt`,
`AndroidManifest.xml` and the plan are owned elsewhere, so findings whose only correct fix lives
there are recorded below as follow-ups rather than fixed here.

Runner: `scripts/run-codex.sh` (rule 53), read-only sandbox, three rounds.

| Round | Thread | Verdict |
| --- | --- | --- |
| 1 | `019fd0a4-880e-7242-bce1-3fd8dd0b3eaa` | 1 Critical, 2 High, 4 Medium, 1 Low |
| 2 | `019fd0ae-e1d8-7282-9692-619170447e3f` | block-recommended (1 Critical residual, 2 Medium, 1 Low) |
| 3 | `019fd0b6-8423-7500-925b-0b56054f9f9f` | **follow-up-recommended** (1 new Medium, fixed) |

## Round 1 — findings and responses

| Sev | Finding | Response |
| --- | --- | --- |
| CRITICAL | Hostile-provider calls unbounded across concurrent activities: `BoundedCallGate.call` launches its job before consulting any budget, and `MAX_ABANDONED_CALLS` was only ever consulted inside `acquireSlot()` — which a stalled URI never reaches under the new admission order. | FIXED in scope: `admitOne` consults `gate.abandonedCalls` before issuing a bounded call, restoring the consultation point. Residual (atomic admission) → follow-up F1. |
| HIGH | The slot no longer precedes the open, so it does not cap open descriptors; the code claimed otherwise. | Order is BINDING spec (see F2 — the plan contradicts itself). Not re-ordered; the comment now states the real worst case (one transient descriptor per activity, N across concurrent activities, plus whatever sits in abandoned calls) and names the follow-up. |
| HIGH | Lifecycle cancellation mid-batch produces ZERO outcomes, while the comments claimed "exactly one per URI" absolutely. | FIXED: the contract is now stated per window (see round 2 C) and `aCancelledBatchLeaksNoSlotAndNoDescriptor` pins it. |
| MEDIUM | The batch-level `handedOff` flag is not stronger than a per-URI transfer guard: a slot can escape between `acquireSlot()` and the `Ready` construction, and a partially-accepted `enqueue` would release items the coordinator owns. | FIXED: items are offered to `enqueue` ONE AT A TIME with a `transferred` counter, and the slot is held under its own `try/finally` from acquisition until the item carrying it is returned. |
| MEDIUM | Batch cleanup aborts on the first fatal `close()`, stranding every later slot. | FIXED: `releaseAll` isolates each item, remembers the first fatal and rethrows it after everything is released. |
| MEDIUM | `finish()` is skipped if the hand-off throws. | FIXED: `finish()` moved into a `finally`. |
| MEDIUM | `outcomes` is a single-consumer `receiveAsFlow`; a second collector competes rather than broadcasts. | ACCEPTED — one production collector is added (MainActivity), and `NEW_TASK\|CLEAR_TOP\|SINGLE_TOP` reuses the one instance. Round 3 downgraded the exotic multi-task case to LOW; the fix belongs to the coordinator → follow-up F3. |
| LOW | The own-authority guard fails OPEN when the PackageManager lookup throws or returns null. | FIXED: the applicationId prefix is checked first, the lookup is defence in depth. |
| — (test) | The Rule-51 copy test retyped the literals it asserted; no mid-loop cancellation test. | FIXED: the copy test now DERIVES its expectations by driving the shipped `LibraryViewModel` through two real failures; the cancellation test was added. |

## Round 2 — findings and responses

| Sev | Finding | Response |
| --- | --- | --- |
| CRITICAL | The `abandonedCalls` threshold is racy across concurrent activities; a write-set-local mitigation exists (a process-wide `Mutex` serializing `admit`). | ESCALATED to round 3 rather than implemented unilaterally — see "The one open question" below. Round 3 agreed the mutex is the worse trade. Partially fixed: the threshold is now re-checked immediately before `resolveAndOpen` too. Residual → follow-up F1. |
| MEDIUM | **Real hole**: the guard only inspected `content://` authorities. A `file://` URI carries NO authority, and `ContentResolver.openInputStream` opens it with THIS process's uid — a sender that suppresses its own StrictMode could hand us `file:///data/data/<us>/databases/…` and have our private data land in the library as a book. | FIXED: `isSelfTargeted` rejects our own authorities, an empty `content://` authority, any `file://` path inside app-private storage (canonicalized on both sides, failing CLOSED on an unresolvable path), and every scheme the manifest does not advertise. Two new URIs in the total-invariant batch pin it. |
| MEDIUM | The cancellation contract was broader than the behaviour: after construction the transfer loop can still enqueue everything. | FIXED: the contract now names both windows exactly — during construction (abandoned wholesale) vs after (no suspension point, so every item transfers and only the hand-off is skipped; the coordinator buffers the outcomes). |
| LOW | The copy test's directly-constructed `LibraryViewModel` is never cleared, so its scope outlives the database teardown. | FIXED: owned through a `ViewModelStore`, cleared on the main thread in a `finally`. |

## The one open question (round 2 → round 3)

Round 2 proposed a process-wide `Mutex` around the whole `admit` operation as an in-write-set
mitigation for the racy ceiling. It was NOT implemented unilaterally; round 3 was asked to weigh it
against the counter-argument (head-of-line blocking on an EXPORTED entry point, reintroducing
exactly the silent-stalling property `BoundedCallGate`'s own rationale rejects).

Round 3's independent judgment: **the mutex is not the better engineering call** — its
head-of-line blocking is bounded only by roughly `MAX_BATCH × RESOLVE_TIMEOUT × 2`, i.e. one
20-URI intent could occupy it for ~20 minutes. The correct fix is an atomic permit reserved inside
`BoundedCallGate.call()` before the job is launched (≈10 lines, in a file this WI may not edit).
Per-call threshold consultation plus a filed follow-up is the accepted resolution.

## Round 3 — verification and the one new finding

Verified fixed: scheme matching is case-insensitive and fails closed on null/unadvertised schemes;
canonicalization defeats `..`, symlinks and `/data/data` vs `/data/user/0`; `abandonedCalls` is
consulted before BOTH bounded calls; `enqueue` is genuinely non-suspending so the cancellation
contract is accurate; the ViewModel store is cleared before teardown. No new leak window found.

| Sev | Finding | Response |
| --- | --- | --- |
| MEDIUM | `appPrivateRoots()` omitted device-protected internal storage (`applicationInfo.deviceProtectedDataDir`, `/data/user_de/<user>/<package>`) — a second, distinct internal root, not a subdirectory of `dataDir`. Nothing stores there today, so it is not a live disclosure path, but the comment's coverage claim was too broad. | FIXED before shipping: the root is added, with a comment saying why it is listed despite being unused today. |

## Rule 51 (the WI's tightest constraint)

**PASS, verified by the auditor against the shipped source.** `MainActivity.importFailureMessage`
introduces NO new user-facing string: the three failure strings are `LibraryViewModel.import`'s
shipped SAF-import copy reused verbatim, and success is SILENT for a new book AND for a duplicate.
A too-large document deliberately reports the generic failure copy rather than a bespoke message.
`res/values/strings.xml` was in the write-set but is not created — there was nothing to add. The
in-progress / added / already-in-library / unsupported treatments remain blocked on
**needs-design #2030**.

## Follow-ups (outside this WI's write-set — must be filed)

- **F1 (Critical, `IncomingImportCoordinator.kt`)** — `BoundedCallGate.call` launches its job
  before any atomic reservation, so `MAX_ABANDONED_CALLS` is a racy threshold, not a ceiling:
  N concurrently-launched `ImportActivity` instances can each read it below the limit and each
  park a thread (and possibly an fd). Fix: reserve an atomic permit before launching the job and
  release it when the call actually terminates. Both audits name this as the structurally correct
  repair.
- **F2 (High, the plan)** — `dev-docs/plans/20260804-feature-155-android-document-handler.md`
  contradicts itself inside the WI-5 Spec block: line 1043 mandates "acquire only … after
  resolution succeeds" while line 1051 claims "The permit is acquired BEFORE any stream exists, so
  concurrent ImportActivity instances cannot collectively exceed MAX_IN_FLIGHT open fds"
  (`IncomingImportCoordinator.acquireSlot`'s KDoc says the same). The code follows the binding
  acquire-after-resolution order; the fd-cap sentence is therefore false as written and needs the
  orchestrator to adjudicate — accept the weakened bound with F1's ceiling, or re-order and add a
  separate pre-open call budget.
- **F3 (Low, `IncomingImportCoordinator.kt`)** — `outcomes` is a single-consumer
  `receiveAsFlow`; an exotic multi-task launch could put two MainActivity collectors in
  competition. A broadcast/event-owner correction belongs to the coordinator.
- **F4 (Low, this file)** — `ImportActivity.kt` is 499 lines, over the ~300-line guideline. Both
  natural splits — WI-2's `urisFrom` payload extractor plus its two constants (~110 lines), and
  `ImportDependencies` (~20 lines) — require a NEW file, which is outside this WI's declared
  write-set (a new Kotlin file needs no project regeneration, so this is a write-set constraint,
  not a technical one). Roughly half the file is rationale comment rather than code.

## Gates

- JVM: `:app:testDebugUnitTest --tests '*imports*' --rerun-tasks` → **151 tests / 0 failures**
  (unchanged from the pre-change baseline).
- Connected: `:app:connectedDebugAndroidTest` class
  `com.vreader.app.imports.IncomingIntentImportConnectedTest --rerun-tasks` on `emulator-5554` →
  **11 tests / 0 failures / 0 errors**.

## Mutation pass (each mutation applied alone, then reverted)

| Mutation | Test that went RED | Observed failure |
| --- | --- | --- |
| Acquire the slot BEFORE resolution (the pre-D8 order) | `aStalledResolutionNeverHoldsAnInFlightSlot` | "slot 19 refused while a resolution was stalled" |
| Drop the `dispose` hook on `resolveAndOpen` | `aResolveResultArrivingAfterTheBoundIsDisposed` | "the late PendingImport's fd was never disposed" |
| Replace the catch-all with an enumerated `catch` list | `everyFailureClassInOneBatchYieldsOneOutcomePerUriInOrder` | `RuntimeException: provider blew up` escaped the batch |
| Omit `FLAG_ACTIVITY_NEW_TASK` from the hand-off | `theHandoffIntentTargetsMainActivityInItsOwnTask` | "FLAG_ACTIVITY_NEW_TASK" |
| Remove the confused-deputy guard | `everyFailureClassInOneBatchYieldsOneOutcomePerUriInOrder` | our own FileProvider URI came back `Imported(...)` |

No mutation survived.

Raw round output: `.reports/audit-r1.txt`, `.reports/audit-r2.txt`, `.reports/audit-r3.txt`.
