---
branch: fix/issue-323-perbook-disable-reresolve
threadId: 019dfcff-ed00-7f62-af11-fb2ad4b84ee3
rounds: 2
final_verdict: ship-as-is
date: 2026-05-06
---

# Codex audit — bug #147 (per-book disable doesn't re-resolve from globals)

## Round 1

**Findings**:

| File:Line | Severity | Issue | Resolution |
|---|---|---|---|
| `vreader/Services/ReaderSettingsStore.swift:83` | High | `reconcileFromDefaults()` did not mirror `typography` when `readerTypography` was absent or undecodable in `UserDefaults` — unlike `init` which falls back to `TypographySettings()`. Bug #147 still present for the common "global typography never customized" case. | **Fixed in round 2** — extracted typography (and every other key's) loading into private static helpers used by both `init` and `reconcileFromDefaults`. `loadTypography` returns `TypographySettings()` when defaults has no entry; reconcile assigns unconditionally with the per-field equality guard. Single source of truth for default-fallback semantics. |

**Verdict round 1**: `block-recommended`.

## Round 2

After the helper-extraction refactor:

**No new findings.**

Codex round-2 confirmation:

> The typography path is fixed: `loadTypography` now returns `TypographySettings()` when `readerTypography` is missing or undecodable, and `reconcileFromDefaults()` compares against that resolved value and assigns when needed. That closes the exact gap from round 1.
>
> `init`/`reconcileFromDefaults()` parity is now effectively exact for the settings this store owns: `theme`, `readingMode`, `typography`, `epubLayout`, `pageTurnAnimation`, `chineseConversion`, `autoPageTurnInterval`, and `backgroundOpacity` all use shared loaders. `autoPageTurn` and `useCustomBackground` still read `defaults.bool(...)` directly in both places, so they remain consistent too.

**Verdict round 2**: `ship-as-is`.

## Other audit dimensions confirmed

- Key coverage is otherwise complete — every setting in init has a parallel reconcile path.
- Per-field equality guards correctly avoid unnecessary `didSet` work.
- `suppressPersistence` not a concurrency hazard — `ReaderSettingsStore` is `@MainActor`; calls serialized.
- `deletePerBookOverride()` ordering: file deleted FIRST, then reconcile. Correct.
- Theme-path test is faithful reproduction of the live per-book apply path.
- `debugBridgeThemeChanged` vs disable serialized on main; last-write-wins, not a data race.
- User-driven persisted change before reconcile: reconcile reads the persisted value back. Right behavior.

## Test coverage

4 Swift Testing `@Test`s in `ReaderSettingsStoreTests`:

1. `reconcileFromDefaults_resetsThemeFromGlobalAfterPerBookDisable` — drives the bug #147 scenario through `applyResolvedSettings` (suppresses persistence) then asserts reconcile pulls the global back.
2. `reconcileFromDefaults_isIdempotent` — no-op when defaults already match.
3. `reconcileFromDefaults_resetsToDefaultTypographyWhenDefaultsHasNoEntry` — round-2-driven test for the High finding: defaults has no `readerTypography` entry, per-book applied a custom fontSize, reconcile resets to `TypographySettings()` default.
4. `reconcileFromDefaults_resetsFontSizeFromGlobalAfterPerBookDisable` — same as #1 for fontSize when defaults has an entry.

## Summary

Bug #147 fixed:
- `ReaderSettingsStore` gained `func reconcileFromDefaults()`.
- `ReaderSettingsPanel.deletePerBookOverride()` calls reconcile after deleting the file.
- Single-source-of-truth refactor: 8 private static `load*(_:)` helpers used by both `init` and `reconcileFromDefaults` to enforce parity.

The reconcile primitive was prototyped in last iteration's bug #146 attempt and reverted (because bug #146 wasn't a real race). This iteration re-adds it because bug #147 IS a real bug; the same primitive serves a different and valid use case.
