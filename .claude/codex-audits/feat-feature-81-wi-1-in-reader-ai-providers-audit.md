---
branch: feat/feature-81-wi-1-in-reader-ai-providers
threadId: 019e87d4-fee2-7c50-b87a-a32ebe234a2a
rounds: 1
final_verdict: ship-as-is
date: 2026-06-02
---

# Gate-4 implementation audit — Feature #81 (in-reader AI Providers entry)

Codex gpt-5.5 / high effort, read-only sandbox (via `scripts/run-codex.sh`).
Audited the WI-1 diff + the 3 new production files against
`dev-docs/plans/20260602-feature-81-in-reader-ai-providers-entry.md`.

## Verdict

Audit returned **follow-up-recommended** with **zero Critical/High/Medium** and
**4 Low** findings. All 4 Lows were FIXED in this PR, so the post-fix state is
**ship-as-is**.

The auditor explicitly confirmed the load-bearing correctness points clean:
- editor-save activation is buffered and re-emitted from
  `AIProviderListView.sheet(onDismiss:)` (runs AFTER the editor dismisses, never
  underneath it);
- the reader flow EXPLICITLY calls `setActive(savedID)` so a non-first add still
  becomes the engine (the Gate-2 Critical);
- the Library path (nil seams) is byte-identical;
- concurrency + SwiftUI navigation choices sound;
- Rule 51 clean (banner + empty state match the committed design; flag/consent
  gates explicitly out of scope).

## Findings + resolutions

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| `AIProviderListView.swift` (handleRowActivation) | Low | `onRowActivated` fired even if `setActive` rejected a stale id | FIXED — `guard viewModel.activeID == profile.id` before firing. Now in `AIProviderListView+Rows.swift`. |
| `ReaderAIProvidersFlow.swift:61` | Low | `handleEditorSaveSuccess` refreshed + popped even if `setActive` rejected | FIXED — `guard viewModel.activeID == id else { return }` before `onConfigured` + pop. New regression test `editorSaveSuccess_rejectedActivation_doesNotRefreshOrPop`. |
| `BilingualSetupSheetContainer.swift:39` | Low | `let onConfigured` stored but never read (only captured into the flow at init) | FIXED — removed the dead stored property; `onConfigured` is an init param captured into `ReaderAIProvidersFlow`. |
| `AIProviderListView.swift:314` | Low | File over the ~300-line guideline | FIXED — row activation + list/row rendering moved to `AIProviderListView+Rows.swift` (main file now 210 lines). |

## Tests

- `ReaderAIProvidersFlowTests` (6): open/push, activate+refresh+pop, **non-first-add
  activation (Critical)**, rejected-activation no-pop (Low fix), row-activated pop.
- `AIProviderEditSheetSaveSuccessTests` (4): add fires wasAdd=true, edit fires
  wasAdd=false, failure does NOT fire, nil hook no-op.
- Regression: `AISettingsViewModelEditorTests`, `BilingualSetupSheetTests` green.
- Full app builds with all 6 host swaps.
