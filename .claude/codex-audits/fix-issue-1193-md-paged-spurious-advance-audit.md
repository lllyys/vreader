---
branch: fix/issue-1193-md-paged-spurious-advance
threadId: 019e6810-17e6-71f3-baae-9ced4f332613
rounds: 2
final_verdict: ship-as-is
date: 2026-05-27
---

# Codex Audit — Bug #272 / GH #1193 (DebugBridge open?position= "stale position")

Gate-4 audit of `git diff main`. Author = implementing Claude session; auditor =
Codex MCP (separate process). 2 rounds, terminal verdict **ship-as-is**.

## Root cause (decisive — 3 prior ticks couldn't pin it)

Diagnosed via DIAG instrumentation of the page mutators + a device repro: the
"833" was NOT a navigate-drop or persistence bug. The verification simulator had
`readerAutoPageTurn=true` **persisted from a prior session** (likely a prior
auto-page-turn feature verification that enabled it via the app). The harness
`reset` wiped the library but NOT reader settings, so the leaked setting made the
`AutoPageTurner` advance the paged MD reader on open (page 0 → last page = offset
833), masking the `open?position=` seek. With the default `autoPageTurn=false`,
`open?position=0` correctly lands at 0 (verified). #272 is a DevTools/Verification
non-determinism, not a production navigate/persistence bug.

## Fix

`RealDebugBridgeContext.reset()` clears the reader-settings UserDefaults keys via
the injected `userDefaults`, iterating the new single-source-of-truth
`ReaderSettingsStore.allPersistedDefaultsKeys`. Each fresh reader mount
(`ReaderContainerView`'s `@State ReaderSettingsStore`) then reads deterministic
defaults — the same "takes effect on next open" pattern as the `theme` command.
DEBUG-only (`RealDebugBridgeContext` is `#if DEBUG`), `@MainActor`.

## Round 1 findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| RealDebugBridgeContext.swift | Low | The local `readerSettingsDefaultsKeys` list was a third copy of the reader-settings key surface (drift risk: a future setting could silently survive reset). | **FIXED.** Introduced `ReaderSettingsStore.allPersistedDefaultsKeys` as the single source; `reset()` iterates it; local copy deleted. Added drift-guard test `allPersistedDefaultsKeysCoversEveryKey` (set-equality vs the individual `*Key` constants + duplicate check). |

Round 1 also confirmed: clearing the keys solves the root cause; the list was complete; safe for the verifier's reset-first contract; no release/concurrency concern.

## Round 2

"No remaining Critical/High/Medium/Low issues in `git diff main`." Shared-source refactor correct, drift-guard test adequate.

## Verification

- Unit: `test_reset_clearsLeakedReaderSettings` — real `reset()` + real `UserDefaults` suite + real `ReaderSettingsStore` reading back `autoPageTurn=false`.
- Device: with representative app-domain `readerAutoPageTurn=true` pollution, reset clears it → `open?position=0` lands at `position: 0` (vs 833 before). (Device-level `simctl defaults write` pollution is NOT representative — no in-app `removeObject` can reach it in the simulator's split-defaults model; that's a documented harness quirk, not the real leak path.)

## Verdict

**ship-as-is.** Zero open findings.
