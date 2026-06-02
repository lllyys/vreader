---
branch: feat/feature-82-wi-1-readiness-container
threadId: 019e883a-0025-7771-9da5-f0c6a20a4794
rounds: 2
final_verdict: ship-as-is
date: 2026-06-02
---

# Gate-4 implementation audit — Feature #82 WI-1 (in-reader AI readiness container)

Codex gpt-5.5 / high effort, read-only (via `scripts/run-codex.sh`). Audited the
readiness model + the new readiness views + the container rewire against
`dev-docs/plans/20260602-feature-82-in-reader-ai-readiness.md`.

## Verdict

Round 1: **block-recommended** — 2 High + 1 Medium. Round 2: **follow-up-recommended**
— all 3 round-1 findings RESOLVED + 1 new Medium, fixed. Post-fix state is
**ship-as-is** (zero open Critical/High/Medium).

Auditor confirmed clean: no `grantConsent()` call in the readiness flow outside the
consent card's own toggle binding; row/editor pop is `isReady`-gated; key-less
providers stay not-ready; new files < 300 lines; project references updated
(ReaderAIProvidersView removed).

## Findings + resolutions

| Round | File:line | Severity | Issue | Resolution |
|---|---|---|---|---|
| 1 | `ReaderAIReadinessView.swift` | High | Provider profiles never loaded (ReadinessProviderBlock renders `viewModel.profiles`; the deleted AIProviderListView used to `loadProfiles()`) | `.task` now calls `flow.viewModel.loadProfiles()`. |
| 1 | `ReaderAIReadinessView.swift` | High | `.onChange(of: vm.hasConsent)` unreliable — `hasConsent` is a computed UserDefaults pass-through, not observed | Consent card uses an explicit `Binding(get/set)` whose setter writes `hasConsent` then drives `handleGateToggled()`; the `.onChange(of: hasConsent)` removed (AI toggle keeps `.onChange` — `isAIEnabled` IS observed stored state). |
| 1 | `ReaderAIProvidersFlow.swift` | Medium | `startedReady` not reset per push | `openProviders()` resets `startedReady = nil`; the view's `.task` recompute re-commits it. New test `openProviders_resetsStartedReadyPerPush`. |
| 2 | `ReaderAIReadinessView.swift` | Medium | `startedReady` snapshot delayed behind async `loadProfiles()` — a gate toggle during the load could record the post-toggle state as initial + skip the pop | `.task` now runs `recompute()` (commits `startedReady`, reads the store directly) BEFORE `loadProfiles()`. |

## Tests

- `ReaderAIProvidersFlowTests` (12): gate capture, **consent never granted by the
  flow**, Change-flow no-auto-pop (startedReady), set-up gate-toggle-to-ready pop,
  ready-gated editor/row pop, key-less no-pop, non-first-add Critical (preserved),
  per-push startedReady reset, concurrent-recompute convergence.
- Full app builds with the views + the container rewire; `ReaderAIProvidersView`
  removed.
