---
branch: feat/debug-mock-ai-provider
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-06-06
---

# Audit — DEBUG MockAIProvider harness (key-free AI verification)

Manual-fallback audit. Codex (`codex exec`) has repeatedly wedged on this
codebase (rule 53 / memory `feedback_codex_exec_stdin_wedge`); per rule 47 a
manual evidence-bearing audit is the documented alternative when the tool is
genuinely unavailable.

## Manual audit evidence

**Files read (the full diff):**
- `vreader/Services/AI/MockAIProvider.swift` (new)
- `vreader/Services/AI/AIReaderAvailability.swift` (mockProvider seam)
- `vreader/Services/AI/AIService.swift` (resolveProvider + providerInstance injection)
- `vreader/App/AITestSetup.swift` (mockAI param)
- `vreader/App/VReaderApp.swift` (--mock-ai flag + config)
- `vreaderTests/Services/AI/MockAIProviderTests.swift` (new)
- `vreaderTests/ViewModels/AIChatViewModelTurn2HangTests.swift` (new)

**Symbols / signatures verified:**
- `AIProvider` protocol required members: `sendRequest`, `streamRequest`,
  `providerName` (no default — caught + fixed during build), `supportsToolUse`
  + `sendToolRequest` (have extension defaults). MockAIProvider implements the
  three required ones; relies on the defaults for tool-use (correct — the mock
  drives the non-tool streaming path).
- `AIResponse(content:actionType:promptVersion:createdAt:)`,
  `AIStreamChunk(text:isComplete:)`, `AIRequest(actionType:bookFingerprint:locator:contextText:userPrompt:targetLanguage:promptVersion:)` — all match.
- `AIService` is an `actor`; `resolveProvider()` (async) + `providerInstance(for:)`
  (sync) are actor-isolated. `AITestOverride` is `@MainActor`.
- Test seam `AIService(featureFlags:consentManager:keychainService:provider:)`
  exists and is used by the existing session tests — reused, not invented.

## Dimensions

**1. Swift 6 concurrency.** `nonisolated(unsafe) static var mockProvider:
(any AIProvider)?` on the `@MainActor AITestOverride` enum. `any AIProvider`
is `Sendable` (the protocol refines `Sendable`). Write happens on MainActor at
launch (`AITestSetup.apply`, before any AI request); reads happen on the
`AIService` actor during requests (strictly after launch). No concurrent
write+read window, so `nonisolated(unsafe)` is sound + lets the actor read it
without a MainActor hop. **No finding.**

**2. DEBUG gating / Release safety.** MockAIProvider, the `mockProvider` seam
(inside the `#if DEBUG` AITestOverride), the two AIService injection points
(`#if DEBUG`), and AITestSetup (whole file `#if DEBUG`) are all gated. In
`VReaderApp`, the `config.mockAI` Bool + `args.contains("--mock-ai")` are inert
in Release; the `AITestSetup.apply` call already required DEBUG (it references a
DEBUG-only type and compiled in Release before this change). The
`verify-release-no-debugbridge` gate enforces zero DEBUG symbols in Release.
**No finding.**

**3. Static leak across requests/tests.** `mockProvider` is `nil` unless
`--mock-ai` is passed. No test sets it (MockAIProviderTests construct the
provider directly; Turn2HangTests inject via the `provider:` constructor seam,
not the static). So it stays nil through the suite — no cross-test leak.
**No finding** (Low note: if a future XCUITest sets it via `--mock-ai`, the
process is fresh per launch, so no leak).

**4. Does the injection bypass legitimate gates?** The mock returns at the TOP
of `resolveProvider`/`providerInstance`, ahead of profile+key resolution — that
is the intent (key-free). The availability/feature-flag/consent gates are
checked in `AIService.sendRequest` BEFORE provider resolution and are SET by
`AITestSetup` when `mockAI` is on, so the mock does not bypass them. With
`mockProvider == nil` (all production + non-mock test builds) both injection
points are a pure no-op → production behavior byte-for-byte unchanged.
**No finding.**

**5. Test quality (behavior vs wiring).** MockAIProviderTests assert content
reflection, deterministic equality, incremental chunking + terminal complete,
and per-action shaping — behavior, not wiring. AIChatViewModelTurn2HangTests
drives two SEQUENTIAL real turns with a timeout-guarded completion check (a
hang becomes a deterministic failure, not a wall-clock stall) and asserts the
streamed `[MOCK]` reply landed. Behavior-level. **No finding.**

## Resolution

All five dimensions clean. The harness is additive + DEBUG-only; the one
sharp edge (`nonisolated(unsafe)`) is justified by the launch-once/read-after
lifecycle and documented inline.

**Verdict: ship-as-is.**
