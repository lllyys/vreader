---
branch: fix/issue-319-perbook-override-semantics
threadId: 019dfcdf-c920-71e3-8690-684b492c28fe
rounds: 1
final_verdict: ship-as-is
date: 2026-05-06
---

# Codex audit — bug #145 (per-book override semantics in bridge theme observer)

## Round 1

**Findings**:

| File:Line | Severity | Issue | Resolution |
|---|---|---|---|
| `vreader/Views/Reader/ReaderContainerView.swift:201` | Low | Per-book disable in same session doesn't re-resolve from globals. `ReaderSettingsPanel` deletes the per-book file but doesn't trigger live re-resolve. Pre-existing, not introduced by this PR. | **Filed as follow-up bug #147 (GH #323)**. Touches a different code path (settings panel UI flow, not the bridge observer); cleaner as a separate fix. |
| `vreader/Views/Reader/ReaderContainerView.swift:199` | Low | No automated regression test for the new field-level gate. | **Justified deferral**. Gate's correctness rests on three components: (1) `PerBookSettingsOverride` field-level optionality — covered by existing `perBookSettings_partialOverride` test; (2) Swift `?.field == nil` — language guarantee; (3) View observer composition — verified end-to-end on device. Adding a View-level unit test would require lifting the gate into a static helper or constructing a `ReaderContainerView` in test — over-engineering for 6 lines of straightforward conditional. |

**Verdict**: `ship-as-is`.

Codex round-1 confirmation:

> The bridge observer change is narrowly scoped, matches the documented per-field inheritance contract in `PerBookSettings.swift:19`, and the two residual concerns are both reasonable as follow-up scope rather than merge blockers. On the test question, I agree with your cost/benefit read. For this specific fix, device verification plus the existing store tests is enough. I would not force a helper extraction or view-construction test just to unit-test six lines of straightforward gating logic.

## Other audit dimensions confirmed

- Per-book check correctly skips when per-book has the field, applies otherwise.
- Edge case (malformed JSON): `PerBookSettingsStore.settings` returns nil, bridge applies — consistent with existing reopen semantics. Right behavior.
- Field-level granularity: `themeName` and `fontSize` are independent; per-book that sets only `themeName` allows bridge fontSize through. Matches documented partial-override contract.
- Sync file I/O in `.onReceive`: acceptable for DEBUG-only path fired once per bridge command.
- Concurrency: observer on main run loop; sync read on main is fine.
- Bridge change does NOT propagate INTO per-book file (correct — bridge writes global; per-book is its own write surface).

## Summary

Bug #145 fixed:
- `.onReceive(.debugBridgeThemeChanged)` observer now reads `PerBookSettingsStore.settings(for:baseURL:)` and gates each field independently.
- `themeName != nil` in per-book → skip bridge theme. Otherwise apply.
- `fontSize != nil` in per-book → skip bridge fontSize. Otherwise apply.

One follow-up bug filed:
- **Bug #147 (GH #323)**: per-book disable doesn't re-resolve from globals in same session (pre-existing, unrelated code path).

Device verification: per-book file with `{"themeName":"sepia"}` written; opened EPUB shows sepia (`rgb(244, 237, 221)`); `vreader-debug://theme?mode=light` correctly ignored — body bg stays sepia.
