---
branch: fix/issue-317-theme-bridge-propagation
threadId: 019dfcab-cbe8-7c13-b8ad-b6e5e4e15351
rounds: 1
final_verdict: ship-as-is
date: 2026-05-06
---

# Codex audit — bug #144 (theme bridge live-propagation)

## Round 1

**Findings**:

| File:Line | Severity | Issue | Resolution |
|---|---|---|---|
| `vreader/Views/Reader/ReaderContainerView.swift:190` | Medium | DEBUG observer mutates the live `settingsStore` directly, bypassing per-book override semantics. When the active book has Custom settings enabled, the bridge mutation overrides for the current session but reopen re-applies the persisted per-book value. | **Deferred to follow-up bug #145 (GH #319)**. Verification flow only — typical bug #144 path (freshly-imported book, no per-book override) is unaffected. Fix shape (from audit): re-resolve via `PerBookSettingsStore.resolve(perBook:global:)` when per-book override exists. |
| `vreader/Views/Reader/ReaderContainerView.swift:190` | Low | First-mount race — fire-and-forget notification can be missed if posted before `.onReceive` subscription is active. | **Deferred to follow-up bug #146 (GH #320)**. Real-world impact limited: typical automation (`open` → settle → `theme`) attaches observer before the theme command lands. Fix shape: reconciliation in `.task` or shared observable settings source. |

**Verdict**: `ship-as-is`.

## Codex confirmation on the verified contract

> The branch fixes bug #144's intended contract for the verified path: `vreader-debug://theme` now updates the live reader without relaunch, the producer/observer wiring is DEBUG-only, the notification payload contract is coherent, and the added tests cover the new posting behavior correctly.
>
> The two issues are real but appropriately follow-up scope, not merge blockers for this PR:
> - Per-book override drift is a semantic gap outside the current verification flow.
> - The first-mount race is timing-sensitive and does not affect the documented `open` → `settle` → `theme` automation path.

## Other audit dimensions confirmed

- `userInfo` encoding fine (omitting `fontSize` key when nil is the right contract).
- The extra `UserDefaults.set` from `settingsStore.theme = ...` is redundant but idempotent — the bridge handler already wrote, the observer's assignment writes again, but `didSet` is a no-op when the value already matches.
- DEBUG gating clean — notification name + post site + observer + tests all behind `#if DEBUG`.
- Notification tests cover the producer contract correctly (positive: posted with mode, posted with fontSize, fontSize key omitted when nil).
- Main-actor / run-loop delivery looks sound; no actor-isolation bug.
- Multiple live `ReaderContainerView`s (theoretical future case) all observing the global theme notification is acceptable for a global debug command.

## Summary

Bug #144 fixed:
- `RealDebugBridgeContext.theme(_:_:)` posts `.debugBridgeThemeChanged` after writing UserDefaults.
- `ReaderContainerView` observes via DEBUG-only `.onReceive(...)` and mirrors the change into the @State-owned settings store.
- 3 new producer-contract tests using XCTestExpectation pattern.

Two follow-up bugs filed:
- **Bug #145 (GH #319)**: per-book override semantics bypass.
- **Bug #146 (GH #320)**: first-mount race for late-attached observer.

Device verification: dark→light theme switch via bridge command without app relaunch produces `rgb(28,28,30)` → `rgb(255,255,255)` body backgroundColor on the live mini-epub3 EPUB.
