---
branch: fix/issue-939-debugreader-await-isolation
threadId: 019e3f4d-1b63-7441-b6cf-1df9a03dd568
rounds: 1
final_verdict: ship-as-is
date: 2026-05-19
---

# Codex Audit — Issue #939 (Bug #228)

`DebugReaderRegistryAwaitReaderTests` shares the `DebugReaderRegistry.shared`
singleton — same parallel-test isolation defect class as bug #227, on the
`awaitReader`/`waiters` path.

## Scope

Files changed in `HEAD^..HEAD`:

- `vreaderTests/Services/DebugBridge/DebugReaderRegistryAwaitReaderTests.swift`
  — `makeRegistry()` swapped from `DebugReaderRegistry.shared.reset(); return
  .shared` to `DebugReaderRegistry.makeIsolatedForTests()`; new RED test
  `bug228_concurrentResetOnSiblingRegistry_doesNotCancelOwnWaiter`.
- `docs/bugs.md` — `#228` numbering-collision renumber (GH #938 row → `#229`,
  GH #939 row keeps `#228`).

Production file `vreader/Services/DebugBridge/DebugReaderRegistry.swift` was
NOT modified — the fix is test-side only (the `makeIsolatedForTests()` factory
already exists from PR #940 / bug #227).

## Round 1

Auditor: Codex MCP (`mcp__plugin_codex-toolkit_codex__codex`), read-only
sandbox, thread `019e3f4d-1b63-7441-b6cf-1df9a03dd568`.

Audit prompt covered: correctness vs root cause, RED-test quality (determinism,
behavior-vs-wiring, timing robustness), edge cases on residual shared state,
concurrency hazards in the new test's background `Task`, VReader compliance
(Swift 6, `@MainActor`, `#if DEBUG`, file size), and the `docs/bugs.md`
collision resolution.

**Findings: none.** Codex verdict verbatim: "The change is clean on the points
you asked about."

Key points confirmed by the auditor:

- `makeIsolatedForTests()` is the correct seam — constructs the same
  `@MainActor` registry type with fresh empty state; removing the `reset()`
  call drops no needed precondition because each test now owns a brand-new
  instance.
- The new RED test exercises the real failure mode (one context suspended in
  `awaitReader`, another calling `reset()`, the rightful `register(_:)`
  happening later). The 30ms/30ms staging is generous relative to the 2.0s
  timeout; the background `Task` stays on `@MainActor`, so the captures of
  `registryA`, `registryB`, `probeB` are actor-safe — no data race.
- The suite has no remaining `.shared` use. The other singleton users named in
  the bug row (`RealDebugBridgeContextTests`, the XCTest `DebugReaderRegistryTests`)
  are out of this fix's scope and AC — `XCTestCase` runs methods serially per
  class, so they cannot suspend a sibling's `waiters` continuation under
  parallelism (lower risk, correctly deferred).
- The `docs/bugs.md` renumber is consistent and complete — row 228 keeps GH
  #939, row 229 documents the GH #938 renumber, both notes explain the
  collision per the `#225/#226` precedent.

## Resolution

No findings to resolve. No second round needed.

## RED path taken (per the issue's "not currently observed failing" caveat)

The issue documented #228 as a *latent* defect — "not currently observed
failing." A deterministic exposing test WAS constructible, so the preventive-
hardening fallback was not needed:

`bug228_concurrentResetOnSiblingRegistry_doesNotCancelOwnWaiter` stands up the
two concurrent test contexts itself rather than relying on the parallel
scheduler. It calls `makeRegistry()` twice and (1) asserts the two instances
are distinct (`registryA !== registryB`) — this assertion alone fails on the
pre-fix code where both are `.shared` — and (2) suspends an `awaitReader`
waiter on registry B while a background `Task` calls `reset()` on registry A,
then `register(_:)` on registry B, proving A's `reset()` cannot spuriously
time out B's waiter.

Verified RED on the pre-fix `makeRegistry()` (`xcodebuild test
-only-testing:vreaderTests/DebugReaderRegistryAwaitReaderTests`): the new test
failed both assertions, AND its background `reset()` on the shared singleton
cross-cancelled `case2`/`case5`'s suspended `awaitReader` waiters — empirically
demonstrating the latent defect was one `reset()`-calling test away from
manifesting suite-wide. Verified GREEN post-fix: all 7 tests pass, 3/3
consecutive full-suite runs, deterministic.

## Manual audit evidence (supplement — not a fallback)

Codex was available; this section records the author's own pre-audit checks.

- **Files read**: `DebugReaderRegistry.swift`, `DebugReaderRegistry+Settle.swift`,
  `DebugReaderRegistryAwaitReaderTests.swift`, `DebugReaderRegistrySettleCoreTests.swift`
  (the #227 precedent), `DebugReaderRegistryTests.swift` (XCTest),
  `RealDebugBridgeContextTests.swift`.
- **Symbols verified to exist**: `DebugReaderRegistry.makeIsolatedForTests()`
  (DEBUG-only static factory, `DebugReaderRegistry.swift:265`), `awaitReader`,
  `register`, `reset`, `Waiter`, `waiters`, `DebugReaderRegistryError.awaitReaderTimeout`,
  `FakeProbe` (test-local).
- **Edge cases checked**: residual `.shared` routing in the suite (none after
  fix); `reset_cancelsPendingWaitersWithTimeoutError` still valid on an
  isolated instance (it resets its OWN registry — yes); `XCTestCase` parallelism
  for `DebugReaderRegistryTests` / `RealDebugBridgeContextTests` (serial per
  class — lower risk, out of AC scope).
- **Risks accepted**: `RealDebugBridgeContextTests` and `DebugReaderRegistryTests`
  still use `.shared`. Out of this issue's AC (which names only
  `DebugReaderRegistryAwaitReaderTests`) and out of the allowed write-set.
  They are `XCTestCase` (no intra-class `@Test` parallelism) and do not suspend
  on `waiters`, so they are genuinely lower-risk; the #228 row already records
  them as an optional follow-up. Not a new bug — no separate filing.

## Verdict

**ship-as-is.** Test-side-only isolation fix mirroring the merged bug #227 fix;
zero production-code change; deterministic RED→GREEN; Codex round 1 clean.
