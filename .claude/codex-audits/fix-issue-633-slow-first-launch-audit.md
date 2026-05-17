---
branch: fix/issue-633-slow-first-launch
threadId: 019e3443-fc24-7d11-9b71-da6cccf37753
rounds: 1
final_verdict: ship-as-is
date: 2026-05-17
---

## Gate 4 — Codex implementation audit, Bug #186 / GH #633

`VReaderApp.init()` (on `@MainActor`) built the SwiftData container with
`ModelContainer(for: schema, migrationPlan: VReaderMigrationPlan.self,
configurations:)`. Passing `migrationPlan:` forces SwiftData to
materialize and validate every schema the plan references (SchemaV1–V6)
while building the migration graph — even on a fresh install where there
is no store to migrate. That wasted main-thread work is the
multi-second first-launch freeze.

Fix: a new `ModelContainerFactory` (`vreader/App/ModelContainerFactory.swift`)
decides whether the plan is needed. On a fresh install (the store file
is absent on disk) or an in-memory store, the plan is skipped — the
store IS the latest schema by construction, nothing to migrate.
Existing installs (store file present) still get the plan.

The "proper" alternative — moving container creation off-`@MainActor`
and rendering an async loading state — was rejected: it requires a
launch/loading screen that is not depicted in any committed design
bundle (`dev-docs/designs/vreader-fidelity-v1/` has no launch/splash/
loading screen), so per rule 51 it cannot be self-designed. The
conditional-migration-plan fix needs no UI and directly targets the
issue's stated root cause.

Codex MCP, read-only sandbox. Thread `019e3443-fc24-7d11-9b71-da6cccf37753`.

## Round 1

**Audit result on GH #633: No findings — clean.**

- **Correctness** — on a fresh install `ModelContainer(for: schema,
  configurations:)` is given `Schema(SchemaV6.models)`, so the created
  store is the current schema by construction; the migration plan is
  only needed to upgrade an existing persisted store. Consistent with
  Apple's `ModelContainer` / `ModelConfiguration` API contracts.
- **Edge cases** — in-memory configs correctly skip the plan
  (`isStoredInMemoryOnly` is ephemeral, nothing to migrate). The DEBUG
  disk-backed UI-test relaunch path is correct: launch 1 sees no file →
  creates V6 without the plan; launch 2 sees the file → reopens with the
  plan. A corrupt / partially-written existing store file still takes
  the migration-plan path — the safer choice.
- **`ModelConfiguration.url`** — a reliable non-optional property; reading
  it before container creation is side-effect-free (does not materialize
  a file).
- **No data-loss risk** — the factory checks the SAME `configuration.url`
  later passed into `ModelContainer`, so there is no new url mismatch:
  if an install's store were ever at a different url, the app would
  already be pointing SwiftData at the wrong store independently of this
  change.
- **Concurrency** — `ModelContainerFactory` is pure synchronous code;
  `ModelContainer` is `Sendable`; the call still runs from `@MainActor`
  `VReaderApp.init()`. No isolation issue.

**Residual note (accepted, not a finding):** the unit tests prove the
`shouldApplyMigrationPlan` predicate (including file-exists → true) and
the in-memory `makeContainer` path, but do not exercise a real
disk-backed two-launch migration. Accepted: the decision predicate is
unit-tested for both outcomes, and the disk-backed relaunch behavior is
already covered end-to-end by the existing `--uitesting-no-seed`
keep-existing UI tests (which still pass). The actual launch-speed cure
is confirmed by post-merge device verification (`awaiting-device-verification`).

## Resolution summary

Zero Critical/High/Medium/Low findings. `xcodebuild build-for-testing`
compiles clean; the Swift Testing suite (992 tests, 104 suites) passes,
including the new `ModelContainerFactory` suite. The 8 XCTest failures
in the run (`TTSServiceSpeedControlTests`, `AutoPageTurnerWiringTests`,
`BackgroundIndexingCoordinatorTests`) are the pre-existing process-crash
flake documented in prior verification docs — unrelated to app launch,
neither introduced nor worsened here.

**Verdict: ship-as-is.**
