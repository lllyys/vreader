---
branch: fix/issue-1428-translate-selection-panel-open
threadId: 019ead03-9279-7940-a5a8-c7b621740165
rounds: 1
final_verdict: ship-as-is
date: 2026-06-09
---

# Codex Audit — Bug #314 / GH #1428 re-fix (AI Translate uses book-context, not the selection)

## Root cause (reopened)

The 2026-06-03 fix parked the selection in `ReaderContainerView.pendingTranslateSelection`
and applied it ONLY in `.onChange(of: showAIPanel)`. But `onChange` does NOT fire when
the AI panel is ALREADY open (no state change), so a selection-translate while the panel
is open never set `hasExplicitSelection` → `requestTranslation` fell to the cold
`.section` context window (the book-start front-matter).

## Fix

- `AITranslationViewModel.isExplicitSelection(parked:)` — pure decision (nil/whitespace → false).
- `ReaderContainerView.applyPendingTranslateSelection()` (in +Sheets.swift) — the SINGLE
  apply path: sets `originalText` + `hasExplicitSelection` from the parked value and
  CONSUMES it (clears `pendingTranslateSelection`).
- `.readerTranslateRequested` handler — applies directly when `showAIPanel` is already
  true (onChange won't fire); else opens the panel (onChange applies).
- `onChange(of: showAIPanel)` — calls the shared helper (cold opens with no parked
  selection clear the flag → context fallback).

## Findings

**No findings.** Codex confirmed: closed-open is covered exactly once (the closed path only
sets `showAIPanel = true`; the open-time `onChange` drains via the shared helper, which
consumes `pendingTranslateSelection`) — no double-apply, no stale pending value, the cold
`.readerOpenAITranslate` reset() path is unaffected.

## Verification (exception)

The failure mode is a SwiftUI view-timing race: a touch text-SELECTION made while the AI
sheet is already open. Reproducing it CU-free requires synthesizing a WKWebView long-press
selection while a sheet is presented at a detent — and the available tooling can't (CU
display flapped to unavailable mid-session; idb not on PATH). Deterministic high-fidelity
tests drive the same decision + translate path the production fix routes through:
- `AITranslationTests.isExplicitSelection_decision` — the parked-selection decision the
  view applies (the exact branch the fix added).
- `AITranslationTests.translate_explicitSelection_translatesVerbatim_noWindowExtraction` —
  `hasExplicitSelection` → the verbatim translate path (no `.section` re-extraction).
The view-apply wiring (handler-already-open + onChange) is the un-unit-testable SwiftUI
lifecycle glue, audit-confirmed above.

## Verdict

ship-as-is — no findings; the decision + verbatim path are unit-tested; close under
verification-exception (the touch-while-sheet-open race isn't CU-reproducible with current tooling).
