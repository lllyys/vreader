---
branch: fix/issue-1428-translate-selection
threadId: codex-exec (RUN-CODEX RESULT SUCCEEDED, /tmp/fix1428-audit.txt)
rounds: 1
final_verdict: ship-as-is
date: 2026-06-03
---

# Gate-4 Codex audit — Bug #314 / #1428 (AI Translate uses context, not selection)

Independent audit (Codex gpt-5.4, high, read-only) of the diff: `AITranslationViewModel`
gains `hasExplicitSelection` + `isExplicitSelection` (translate the selection verbatim,
skip the `.section` window); `TranslationPanel.requestTranslation` translates the
selection when flagged; `ReaderContainerView` wires it. One round.

Auditor confirmed the core flow correct (selection re-tap keeps translating the
selection verbatim; `.readerOpenAITranslate` resets; no @MainActor/cancellation issue).

## Findings & resolutions

| # | file:line | severity | issue | resolution |
|---|---|---|---|---|
| 1 | `ReaderContainerView.swift:326` | High | Cold AI opens (toolbar / readiness handoff / Ask-AI) never reset the reused translation VM, so a prior selection-translate's `hasExplicitSelection=true` leaks into a later cold open → the next pill tap translates the stale selection verbatim. | **FIXED** — centralized via `pendingTranslateSelection` (@State): the `.readerTranslateRequested` consumer parks the selection; `onChange(of: showAIPanel)` applies it to the VM on a selection open and **clears `hasExplicitSelection` on every cold open** (parked == nil). No path leaks a stale flag. |
| 2 | `TXTBridgeShared.swift:68` | Medium | Whitespace-only TXT/MD selections (untrimmed) would be marked explicit + translated as verbatim whitespace (PDF/EPUB already reject whitespace → inconsistent). | **FIXED** — the centralized `onChange` apply trims the parked selection: whitespace-only → `hasExplicitSelection=false` (cold context fallback), for ALL formats at the single application point. |

## Verdict

`ship-as-is` — both findings fixed centrally in the `onChange(showAIPanel)` apply
(cold-open clear + whitespace trim-guard). VM-level behavior (verbatim vs extraction,
reset) unit-tested (`AITranslationViewModelTests`, 21 green incl. 3 new #314 tests);
the consumer→onChange→VM wiring is device-verified (Gate 5).
