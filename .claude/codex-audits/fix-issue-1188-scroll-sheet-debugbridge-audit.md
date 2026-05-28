---
branch: fix/issue-1188-scroll-sheet-debugbridge
threadId: 019e64aa-9e05-7161-b559-57d311e0a9d7
rounds: 3
final_verdict: ship-as-is
date: 2026-05-26
---

# Codex Audit — Bug #271 / GH #1188 (`scroll-sheet` DebugBridge command)

Adds a DEBUG-only `vreader-debug://scroll-sheet?to=<top|bottom>` command so the
Translate-tab `TranslationResultCard` ScrollView can be scrolled CU-free — the
accent translation card sits below the tall auto-extracted ORIGINAL card,
beyond even the `.large` AI-sheet fold (Bug #256), so it is otherwise
un-capturable by `simctl io screenshot`. Unblocks Feature #65 / GH #823 row 11.

## Round 1 — 1 Medium

| file:line | severity | issue | resolution |
|---|---|---|---|
| AIReaderPanel+DebugBridgeAIAction.swift:137 / TranslationResultCard.swift | Medium | `ai?action=translate` returns before translation finishes / before `TranslationResultCard` mounts. A verifier that issues `scroll-sheet?to=bottom` immediately can lose the scroll entirely — the fire-and-forget observer has no replay path, so the harness is race-prone rather than deterministic. | **Fixed.** Added DEBUG-only `DebugBridgeScrollSheetState` (Services-layer `@MainActor` singleton holding a `DebugCommand.ScrollTarget?`). `scrollSheet(target:)` now records the target there AND posts the notification. The observer gained a `.onAppear` replay path alongside `.onReceive`, so a scroll requested before the card mounts is applied on first appearance. Order-independent. |

Codex confirmed the standalone-command shape (vs. a `present` parameter) is
correct: the result card only exists after translate completes, so folding
scroll into `present` would be the wrong lifecycle.

## Round 2 — 1 Medium

| file:line | severity | issue | resolution |
|---|---|---|---|
| RealDebugBridgeContext+ScrollSheet.swift:38 | Medium | The process-global buffer survives unrelated lifecycles. If `scroll-sheet` is issued when no result card ever mounts, `pendingTarget` lingers across `reset`/reopen/a later translate, and the next `TranslationResultCard` consumes the stale request on `.onAppear`. | **Fixed.** Cleared the buffer at two Services-layer choke points: `reset()` (the verifier's hard session boundary) and `aiAction(...)` when `action == .translate` (a fresh translate produces a new card — forget the old target). The verifier issues `scroll-sheet` *after* `ai?action=translate`, so the legit target is recorded after the clear and survives. Covers cross-session (reset + next translate) and within-session (translate-A-fails → translate-B clears). |

## Round 3 — clean

No remaining findings. Verdict: **ship-as-is**. Codex confirmed: the leak path
is closed at the two right places; the translate-start clear precedes the legit
`scroll-sheet` set so it never wipes the intended request; `@MainActor`
isolation consistent; new symbols stay DEBUG-only (file-level `#if DEBUG`);
process-global singleton acceptable for this harness now that its stale-state
choke points are covered.

## Summary

3 rounds, 2 Mediums fixed, final verdict **ship-as-is**. The fix is a
self-contained DEBUG-only verification-harness command mirroring the existing
`present` / `seek` no-parallel-logic pattern; production reader behavior is
unchanged (the `ScrollViewReader` wrapper + anchor `.id`s are identity-only with
no visual delta — rule 51 not triggered; the observer + replay buffer are
`#if DEBUG`-gated so `verify-release-no-debugbridge.sh` stays green).
