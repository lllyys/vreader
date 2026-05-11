---
branch: feat/issue-50-wi-5-aiservice-dispatch
threadId: 019e16c7-5e87-72c2-b4d2-5f7aaf553e91
rounds: 2
final_verdict: ship-as-is
date: 2026-05-11
---

# Codex Gate-4 Audit — Feature #50 WI-5

AIService now dispatches on the active `ProviderProfile` from
`ProviderProfileStore`. Two-round Codex MCP audit (sandbox: read-only,
verdict thread `019e16c7-5e87-72c2-b4d2-5f7aaf553e91`).

## Round 1 findings

| # | File:line | Severity | Issue | Resolution |
|---|---|---|---|---|
| 1 | `vreader/Services/AI/AIService.swift:41` | Low | `apiKeyAccount` is retained but not marked `@available(*, deprecated, …)`, missing contract item 12's "deprecated fallback" framing | **Doc-comment fix, attribute deferred.** Expanded the comment to "DO NOT CALL FROM NEW CODE", explicitly named the migrator-only intent, and documented why `@available` is deferred (active legacy readers in `AISettingsViewModel` (WI-6a/6b scope) and `AIReaderAvailability` (WI-7 scope) would emit cascade warnings on every intermediate WI PR). The annotation lands in the cleanup PR per the plan's Backward compat table. |
| 2 | `vreaderTests/Services/AI/AIServiceProfileDispatchTests.swift:250` (was) | Low | `providerFactory_receivesSnapshotAndKey` is timing-based: factory spawns a detached `Task`, test sleeps 50 ms before asserting — flaky under load | **Fixed.** Replaced the actor-based inbox + fire-and-sleep with a class-based `Inbox: @unchecked Sendable`. The factory closure runs synchronously inside `resolveProvider()`. After `try await service.resolveProvider()` returns, the test thread reads the box with no concurrent access. No Task hop, no sleep. |

Everything else round-1 inspected matched the WI-5 contract:
`resolveProvider()` takes one snapshot, `provider:` short-circuits before
store/keychain access, factory injection sits after key resolution and
before production dispatch, missing/empty per-profile keys map to
`apiKeyMissing`, the production call sites use
`ProviderProfileStore.shared`, `AIConfigurationStore` is untouched, and
`AIChatViewModel` already calls `try await aiService.streamRequest(request)`.

`resolveProvider` exposed as internal (not `private`) for `@testable`
access was explicitly approved by the auditor: "it does not expand the
public module API, and I would not add another seam just to hide it."

## Round 2 findings

Zero. Verdict: **ship-as-is**.

Auditor verbatim on the doc-comment fix: "The expanded `apiKeyAccount`
comment in `AIService.swift:38` is sufficient for WI-5. The literal
`@available(*, deprecated)` marker would be cleaner in isolation, but
your rationale is sound: the repo still has live production and test
references to `AIService.apiKeyAccount` outside the migrator path,
including `AISettingsViewModel.swift:135` and
`AIReaderAvailability.swift:46`. Adding the attribute now would create
noisy intermediate warnings without changing behavior. For this slice,
the important contract is "legacy-only, retained for one release," and
the strengthened comment communicates that accurately."

Auditor verbatim on the test-isolation fix: "The revised inbox in
`AIServiceProfileDispatchTests.swift:245` is safe as written.
`resolveProvider()` invokes `factory(snapshot, apiKey)` synchronously
and immediately returns that value; there is no spawned task, no
escaping callback, and no second concurrent reader/writer. Once
`try await service.resolveProvider()` completes, the writes to `inbox`
are done. The `@unchecked Sendable` is acceptable here because the
test's actual access pattern is single-call, single-writer, post-call
read."

## Test gate

- 9/9 new dispatch tests pass (`AIServiceProfileDispatchTests`).
- 19/19 existing AIService tests pass (`AIServiceTests`).
- 51/51 AI VM tests pass (`AIChatViewModelTests`, `AITranslationTests`,
  `AIAssistantViewModelTests`, `AIReaderIntegrationTests`,
  `AIChatGeneralTests`).
- Full-suite run reports `TEST FAILED` due to SIGSEGV in unrelated
  AutoPageTurner + TTSService Speed Control tests (10 + 5 + 1 failures)
  — pre-existing simulator-restart flake pattern matching WI-4's PR.
  Crash signature: "Test crashed with signal segv" on tests that don't
  touch AI code (verified via xcresulttool `test-details` inspection
  of `AutoPageTurnerTests/intervalClamped_belowMin_becomesMin()`).
  Not introduced by WI-5.
