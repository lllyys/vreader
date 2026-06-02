---
branch: feat/feature-78-wi1-2-ask-ai-selection
threadId: codex-exec (RUN-CODEX RESULT SUCCEEDED, /tmp/feat78-implaudit.txt)
rounds: 1
final_verdict: ship-as-is
date: 2026-06-03
---

# Gate-4 Codex audit — Feature #78 WI-1+2+3 (Ask-AI / Read on selection)

Independent impl audit (Codex gpt-5.4, high, read-only) of the diff wiring the
selection-popover `.askAI`/`.read` actions per the Gate-2-audited plan. One
round; author=this session, auditor=Codex (rule-48 separation).

The auditor explicitly confirmed **no runtime logic break**: the seed reaches
the chat in BOTH the AI-available open and the post-readiness handoff
(`pendingAskAIText` → `onChange(showAIPanel)` → `ensureAIReady()` →
`chatViewModel?.seedInput(...)`); the non-handoff readiness dismiss clears
`pendingAskAIText` + restores `aiInitialTab = .summarize`; no new
Sendable/@MainActor defect.

## Findings & resolutions

| # | file:line | severity | issue | resolution |
|---|---|---|---|---|
| 1 | `AIChatViewModelTests.swift:338` | Medium | Coverage stopped at VM-level seed storage; the view/host-seam paths (seed-before-mount consumption, readiness handoff-vs-abandon, TTS preempt-no-resume) were unpinned. | **PARTIALLY UNIT-PINNED + device-verified.** Extracted `AIChatView.seedDecision(seededInput:currentInput:)` (pure) + 3 tests (apply-on-empty / drop-over-draft / none) — pins the highest-risk consumption logic. The host-state wiring (readiness abandon-cleanup) + TTS preemption are SwiftUI view-body / service behaviors not cleanly unit-isolable; the TTS preempt is already the pinned `TTSService.startSpeaking` "restart while speaking" contract (`TTSServiceTests`), and the abandon-cleanup + drain path were traced clean by the auditor. Both are device-verified in Gate 5. |
| 2 | `SelectionPopoverActionRouter.swift:46` | Low | `Result.deferredNotYetWired` doc still named `.askAI`/`.read` as the forward-trace case (now wired). | **FIXED** — reworded to a generic fallback for any future unwired action. |
| 3 | `SelectionPopoverActionRouterTests.swift:23` | Low | Stale suite header said `.askAI`/`.read` "have no production consumer yet". | **FIXED** — header updated to the wired contract. |

## Verdict

`ship-as-is` — no logic break; Medium addressed (pure seed-decision helper +
tests; remaining view/host wiring device-verified in Gate 5); both Lows fixed.
Suites green: `SelectionPopoverActionRouterTests`, `SelectionPopoverPresenterTests`,
`AIChatViewModelTests` (incl. seed + seedDecision tests).
