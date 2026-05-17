---
branch: fix/issue-830-booksource-test-parallel-safety
threadId: 019e356d-8c4d-7281-a78d-585f18e53bf2
rounds: 2
final_verdict: ship-as-is
date: 2026-05-17
---

# Codex audit — issue #830 (Bug #213): BookSourceHTTPClientTests not parallel-safe

## Scope

File audited:

- `vreaderTests/Services/BookSource/BookSourceHTTPClientTests.swift` —
  the fix: (1) the `@Suite` gains the `.serialized` trait so its
  `@Test` functions run one at a time; (2) `MockURLProtocol`'s
  process-global state (`requestHandler`, `capturedRequests`) is moved
  behind private `_`-prefixed storage guarded by an `NSLock`, with
  lock-synchronized public accessors and a lock-guarded
  record-and-snapshot in `startLoading()`.

## Round 1 — findings

| # | file:line | severity | issue | resolution |
|---|---|---|---|---|
| 1 | BookSourceHTTPClientTests.swift (`MockURLProtocol`) | Medium | `.serialized` fixes the reported cross-test contamination, but `MockURLProtocol.capturedRequests` was still an unsynchronized process-global `Array`. `fetchPage_concurrent_safe` drives 5 requests concurrently, so `startLoading()` could `append` to that array from multiple threads at once — a data race (UB). | **Fixed.** Moved the global state to private `_requestHandler` / `_capturedRequests` guarded by a `static let lock = NSLock()`. Public `requestHandler` / `capturedRequests` accessors lock get/set. `startLoading()` records the request and snapshots the handler under one lock acquisition, then releases the lock before invoking the handler / client callbacks. |

## Round 2 — verification

**No findings.** Codex confirmed the fix is correct and complete:

- The Medium is resolved — all reads/writes of the process-global
  mock state are synchronized; `startLoading()` records the request
  and snapshots the handler atomically with respect to resets and
  other concurrent requests.
- No deadlock — the lock is released before the handler and
  `URLProtocol` client callbacks run, so no slow work is performed
  under the lock.
- `.serialized` remains necessary and complements the lock: the lock
  makes each access memory-safe, but only `.serialized` prevents the
  cross-test *logical* interleaving (one test's `init()` resetting
  another test's suite-global handler mid-flight). The lock alone
  cannot fix that.
- No cross-suite hazard — `MockURLProtocol` is used only by this
  suite (repo-wide search) and is attached only to per-session
  `URLSessionConfiguration.ephemeral` `protocolClasses`, never
  globally registered, so it cannot affect other suites.
- `@Suite("BookSourceHTTPClient", .serialized)` is valid Swift
  Testing syntax and already used elsewhere in the repo.

## Verdict

**ship-as-is.** Two rounds — round 1 found one Medium (unsynchronized
global mutable state / intra-test concurrent-append race), fixed in
round 2; round 2 clean. The `.serialized` trait eliminates the
cross-test handler/capture contamination that made the suite fail
non-deterministically (8 vs 19 disjoint failures across two runs);
the `NSLock` makes `MockURLProtocol`'s global state memory-safe under
the concurrent requests `fetchPage_concurrent_safe` issues.

Verification: with `.serialized` alone the suite passed 14/14 across
3 consecutive isolated runs (pre-fix it failed 8–19 tests
non-deterministically); re-verified 3× with the lock added.
