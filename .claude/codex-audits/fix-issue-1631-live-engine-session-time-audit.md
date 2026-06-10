---
branch: fix/issue-1631-live-engine-session-time
threadId: 019eb2ae-8d27-7160-9248-dd7492b36c5a
rounds: 2
final_verdict: ship-as-is
date: 2026-06-11
---

# Gate-4 Codex audit — Bug #345 (live-engine session tracking + time display, GH #1631)

Independent audit via `scripts/run-codex.sh` (gpt-5.4, read-only), 2 rounds
(round-2 session 019eb2b8-c56a-73e3-acec-55c5881e9b1f).

## Round 1

| file:line | severity | issue | resolution |
|---|---|---|---|
| ReadiumEPUBHost+Body.swift:223 | High | No scene-phase pause/resume — backgrounded wall-clock time overcounts session rows, stats, and the label. | **Fixed** — host `.onChange(of: scenePhase)` → `handleScenePhaseChange` (bg-task-guarded `viewModel.onBackground()` / `onForeground()`); new VM methods forward to the lifecycle helper (position stays VM-owned). |
| FoliateBilingualContainerView.swift:371 | High | Same regression on the Foliate wrapper. | **Fixed** — container-level `handleScenePhaseChange` (bg-task-guarded flush + `onBackground(nil)`; `.active` → `onForeground()`). |
| FoliateBilingualContainerView.swift:380 | Medium | Teardown `Task { flush; close }` without a `beginBackgroundTask` guard — iOS can suspend before the writes land. | **Fixed** — `handleHostTeardown` rides begin/endBackgroundTask (the legacy Foliate host's precedent). |

Round 1 explicitly found NO double-begin/double-close issues, no
`.readerDidClose` stacking, and `close(locator: nil)` safe for stats.

## Round 2

| file:line | severity | issue | resolution |
|---|---|---|---|
| ReadiumEPUBReaderViewModel.swift:240 | High | `onBackground()` didn't await an in-flight debounced persist (the `closeAndFlush` Gate-4 lesson re-applied) — the final position could be lost on suspension. | **Fixed** — mirrors `closeAndFlush`: capture `inFlight = saveTask`, flush any pending locator, `await inFlight?.value`, then pause the session. |
| ReadiumEPUBReaderViewModel.swift:163 | Medium | An open completing while the app is already backgrounded begins the session segment in the background (the later `.active` doesn't correct it). | **Fixed** — the host checks `scenePhase != .active` right after `vm.open()` and pauses immediately; `.active` resumes. |

Round 2 confirmed: the Foliate changes clean; the teardown guard correct;
the `observedCore` / `FoliateSessionLifecycleModifier` body split (added
for SwiftUI's type-check budget) behavior-preserving. The round-2 fixes
are small mirrors of the already-audited `closeAndFlush` pattern,
verified by a green build + device sanity (chrome labels live on both
engines post-refactor).

## Verdict

**ship-as-is** after 2 rounds.
