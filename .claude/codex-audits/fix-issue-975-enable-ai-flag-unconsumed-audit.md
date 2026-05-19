---
branch: fix/issue-975-enable-ai-flag-unconsumed
threadId: 019e4113-426b-7cf1-9abc-cdfc1dafd788
rounds: 1
final_verdict: ship-as-is
date: 2026-05-20
---

# Codex Audit — Bug #237 / GH #975 (`--enable-ai` flag parsed but never consumed)

## Scope

Files changed for the fix:

- `vreader/App/VReaderApp.swift` — consume `config.enableAI` by writing
  `AITestOverride.forceAvailable`.
- `vreader/Services/AI/AIReaderAvailability.swift` — add the DEBUG-only
  `@MainActor enum AITestOverride` seam; `isAvailable` short-circuits on it;
  `isAvailable` made `@MainActor`.
- `vreaderTests/ViewModels/AIReaderIntegrationTests.swift` — two new tests in
  the `AIReaderAvailability` suite; suite made `@MainActor`.
- `docs/bugs.md` — tracker row #237 status flip (not code).

## Round 1 — findings

**No findings.** Codex read the actual files and the production callers and
reported zero Critical/High/Medium/Low issues.

Audit confirmations (verbatim points from the Codex verdict):

| Dimension | Result |
|---|---|
| Root cause | Fixed — `--enable-ai` parsed into `TestLaunchConfig.enableAI` (`VReaderApp.swift:548`) and now consumed at `VReaderApp.swift:195`. |
| Choke point | `AIReaderAvailability.isAvailable` is the correct place — both production callers (`LibraryView.swift:363`, `ReaderAICoordinator.swift:32`) already route through it, so the override is centralized, not duplicated per call site. |
| Release safety | Sound — the override type and the read path are both `#if DEBUG`-gated; no path for the seam to exist in a shipped Release build. |
| Security | Preserved — even in DEBUG the override only affects surface *visibility*; real AI request execution still checks feature flag + consent in `AIService.swift:100` / `AIService.swift:125`. |
| Swift 6 concurrency | Coherent — `VReaderApp` is `@MainActor`, `AITestOverride` is `@MainActor`, production callers are main-actor-isolated. `@MainActor` is the correct isolation choice over `nonisolated(unsafe)`. |
| Parallel-test race | Handled — the shared global is `@MainActor`-isolated, the new override tests are in an `@MainActor` suite, and the override-flipping test has no suspension point between set and `defer` reset. |
| Dead code | `config.enableAI` is no longer dead; no other parsed-but-unused `TestLaunchConfig` flag found. |

## Residual gap (noted, not a defect)

Codex observed: the two new unit tests verify the `AITestOverride` →
`isAvailable` seam behavior, not a full app-launch wiring test that drives
launch args through `VReaderApp.init()`. Codex explicitly stated this is **not
a defect in this patch** — it is an integration gap.

**Resolution — accepted.** The launch-arg → `VReaderApp` → `AITestOverride`
wiring is exercised end-to-end by the bug's own close-gate device verification
(Phase 9: launch the merged build with `--enable-ai`, observe an AI surface).
The unit tests cover the `isAvailable` decision logic; the close-gate covers
the launch-arg wiring. No additional unit test is warranted — a unit test of
`VReaderApp`'s `App.body` setup block is not feasible without an App harness.

## Verdict

**ship-as-is.** Clean on round 1. The fix resolves the root cause (unconsumed
`--enable-ai` flag) with a minimal, Release-safe, concurrency-correct seam that
follows the existing `TTSTestOverride` precedent.
