---
branch: feat/feature-90-bilingual-summary
threadId: 019e9867-8ff1-7331-9a6b-54d32c3fc897
rounds: 2
final_verdict: follow-up-recommended
date: 2026-06-05
---

# Gate-4 audit — Feature #90 WI-1 (AIAssistantViewModel bilingual-summary state + two-step generation)

WI-1 of #90: the VM logic for the bilingual summary — a `SummaryDisplayMode`
(`originalOnly`/`translatedOnly`/`interlinear`), a `BilingualLanguage`
`summaryTargetLanguage`, synchronous setters, `refreshSummaryTranslationIfNeeded()`,
a dedicated PRIVATE translate helper (`aiService.sendRequest(.translate)` on the
generated summary, NOT `performAction`), a `SummaryTranslationState` sub-state with
its own cancellable task + op-token, `retrySummaryTranslation()`, and
`cancelSummaryTranslation()`. NEW `AIAssistantViewModel+BilingualSummary.swift` +
the stored props + the `reset()` teardown on the base VM.

## Round history

| Round | Findings | Resolution |
|---|---|---|
| 1 (`019e9862`) | **H1** a re-summarize goes through `performAction`, NOT `reset()`, so the in-flight summary translation was NOT cancelled — a translation of summary A could land stale against summary B. **M1** the 12 tests missed the re-summarize supersede path (which is why H1 hid). | see below |
| 2 (`019e9867`) | High **resolved in production**. One Medium in the new TEST: the re-summarize test set `.translating` before translation A's request reached the gated provider, so the FIFO release was non-deterministic. | test made deterministic (wait for `provider.pendingCount >= 1`) |

## Fixes applied

**H1 (re-summarize teardown)** — `performAction(...)` now calls
`cancelSummaryTranslation()` at the top (right after the `streamTask` supersede +
`opCounter` bump, BEFORE `responseText` is cleared), so EVERY new action (including
a re-summarize) invalidates the old summary's translation task + token. The
in-flight translation's `Task.isCancelled` guard then drops its post-await write.

**M1 + the test** — added `reSummarizeSupersedesInFlightTranslation`, then made it
deterministic by waiting until translation A's request is actually pending at the
provider before launching the re-summarize, so the FIFO stale-release targets
translation A.

## Verified clean (round-1 audit)

The private helper writes ONLY `summaryTranslation` (never `responseText`/`state`/
`currentAction`); the op-token guards every post-await write; `.originalOnly`
makes no AI call; the setters are synchronous; `cancelSummaryTranslation()` is
wired into `reset()`; file sizes within the guideline (ext 176, base 254).

## Verdict

`follow-up-recommended`. WI-1 is clean (2 audit rounds → High resolved, no open
Critical/High/Medium; the one Medium was a test-determinism fix). 38 tests across
the BilingualSummary + base + scope suites pass. The two-step generation +
race/teardown contract is in place for WI-2 (LangRow/popover) + WI-3 (card render).
