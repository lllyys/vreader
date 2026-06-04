---
branch: feat/feature-91-wi-8b-vm-branch
threadId: 019e9386-9cc9-74d2-91f3-8f3a9401f352
rounds: 2
final_verdict: ship-as-is
date: 2026-06-05
---

# Codex Audit — Feature #91 WI-8b (slice 6: AIChatViewModel agentic-branch logic)

Gate-4 implementation audit (rule 47). Independent Codex runner via
`scripts/run-codex.sh -e high` (author/auditor separation, rule 48; rule-53
stdin-isolated watchdog).

## Scope

WI-8b slice 6 — the **VM-branch logic** (FOUNDATIONAL — dormant until the
construction-site registry wiring activates it):

- `vreader/Services/AI/AIService.swift` — `streamRequest(_:using:)` (gate-rechecking,
  pinned config; mirrors `sendRequest(_:using:)`).
- `vreader/ViewModels/AIChatViewModel.swift` — injected `featureFlags` +
  `agenticRegistry`; `sendMessage` resolves the provider ONCE when `agenticTools` is
  live-ON + a non-empty registry is injected → agentic loop if `supportsToolUse`,
  else stream via the SAME pinned config; otherwise the unchanged streaming path.
  `runAgenticTurn` + `consumeStream` helpers.
- `vreaderTests/ViewModels/AIChatViewModelAgenticTests.swift` (new) — 7 tests.

## Round 1 — findings (threadId 019e9386-9cc9-74d2-91f3-8f3a9401f352)

The success/error/`assistantIndex` paths were confirmed sound (assistant content is
written only after driver success, so the existing `catch` cleanup matches the
streaming path). Findings:

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| ReaderAICoordinator.swift / LibraryView.swift | High×2 | The branch is unreachable — both construction sites build `AIChatViewModel` without an injected `agenticRegistry`. | **Reclassified as deferred scope (round 2), not a code defect.** This slice is the VM-branch logic (foundational, dormant); the construction-site registry wiring needs a shared **Services-layer** persistent-`SearchIndexStore` factory (the persistent store is currently a Views-layer private static; `SearchIndexStore()` is in-memory) — that + Gate-5 device verification is the explicitly-deferred completing slice. |
| AIChatViewModel.swift fallback | **Medium** | The `supportsToolUse == false` fallback did an EXTRA `resolveToolProvider()` then `streamRequest()` → profile/consent/key could drift between the probe and the stream. | **Fixed.** Added `AIService.streamRequest(_:using:)`; `sendMessage` resolves ONCE — if non-tool, streams through the SAME pinned config (no re-resolve). |
| AIChatViewModel.swift gate | **Medium** | Agentic enablement was latched by the injected registry, not the live flag — a mid-session `agenticTools` OFF flip would keep using tools. | **Fixed.** Injected `featureFlags`; `sendMessage` re-checks `featureFlags.agenticTools` live. Test `flagOff_fallsBackToStreaming`. |
| AIChatViewModelAgenticTests.swift | Low | Missing branch-cleanup tests. | **Fixed.** `agenticThrow_removesPlaceholder_setsError`, `agenticEmptyFinalText_removesMessage`, `nonToolProvider_fallsBackToStreaming`. |

## Round 2 — verification (threadId 019e93a1-b782-74f2-af9d-3b3809e7d6af)

**PASS for this foundational slice.** All three round-1 CODE findings RESOLVED
(single resolution via the pinned-config overload; live-flag re-check; cleanup-path
coverage). The two prior Highs are correctly classified as deferred scope/wiring
items, NOT defects in the shipped VM-branch logic. No new code defects.

## Verdict

**ship-as-is** (foundational). Zero open code Critical/High/Medium. Test gate green:
`AIChatViewModelAgenticTests` (7 — agentic path without streaming, flag-OFF / no-
registry / non-tool fallbacks, citation suppression, throw-cleanup, empty-finalText
removal) + the `AIChatViewModelTests` streaming regression.

Remaining for #91 `DONE`: the construction-site registry wiring (a shared
Services-layer persistent-`SearchIndexStore` factory + injecting the registry at
`ReaderAICoordinator`/`LibraryView` under the flag) + `docs/architecture.md`, then
Gate-5 device verification → `VERIFIED`.
