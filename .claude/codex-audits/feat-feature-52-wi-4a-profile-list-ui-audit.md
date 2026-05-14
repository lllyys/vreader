---
branch: feat/feature-52-wi-4a-profile-list-ui
threadId: 019e257c-b135-7d52-96a8-d73c81f6c913
rounds: 4
final_verdict: ship-as-is
date: 2026-05-14
---

# Codex audit — Feature #52 WI-4a (WebDAV profile list UI)

## Round 1 — initial audit

Codex MCP read-only audit of the WI-4a diff. Findings:

| file:line | severity | issue | resolution |
|---|---|---|---|
| `WebDAVServerProfileListView.swift:206` | Medium | Active-profile swipe-delete had no confirmation guard (plan called for it). | **FIXED** — added `@State pendingDeleteConfirm` + confirmation alert. Later folded into the unified alertItem path (round-2 refinement). |
| `WebDAVServerProfileEditSheet.swift:38` + `WebDAVSettingsView.swift:94` | Medium | Stub editor was cancel-only; plan called for a "placeholder save" path. Empty-state Add CTA promised functionality that didn't exist. | **FIXED** — added an Add toolbar button to the stub editor that upserts a `WebDAVServerProfile(name: "New WebDAV Server", serverURL: "", username: "")` via the store, dismisses on completion. Body copy clarifies the WI-4a → WI-4b path. Test `placeholderUpsert_addsRowToStore` pins the contract. |
| `WebDAVServerProfileListView.swift:185` | Low | VoiceOver row label was only `displayName` — duplicate names indistinguishable. | **FIXED** — `rowAccessibilityLabel(for:)` joins `displayName`, `username` (if non-empty), and URL host (if parseable) with commas. |
| `WebDAVProfileListViewModelTests.swift:14` | Low | Tests pinned VM but not UI contracts (sheet-swap, notification resync, active-delete confirmation). | **partial-FIX** — added `WebDAVEditorContextTests` (7 tests pinning Identifiable id stability) + `WebDAVServerProfileEditSheetStubTests` (2 tests for placeholder-save wiring) + `loadProfiles_afterPostedNotification_picksUpExternalUpsert`. Active-delete confirmation alert plumbing isn't unit-testable without booting SwiftUI — accepted as XCUITest scope. |

## Round 2 — verification of round-1 fixes

Codex found 2 new Mediums introduced by the round-1 fixes:

| file:line | severity | issue | resolution |
|---|---|---|---|
| `WebDAVServerProfileListView.swift:103` | Medium | Dual `.alert(...)` modifiers attached to same view chain (listError + delete-confirm). SwiftUI honors only one per branch → one path could be unreachable. | **FIXED** — collapsed to a single `enum WebDAVListAlertItem: Identifiable` with `.listError(message:)` and `.confirmDeleteActive(profile:)` cases driving one `.alert(...)` via `alertItem` `@State`. listError flows through `.onChange(of: viewModel.listError)` that promotes into the unified slot only when no higher-priority alert is on screen. |
| `WebDAVServerProfileEditSheet.swift:79` | Medium | Re-entrant Add button — rapid double-tap before dismissal could enqueue two Tasks with different UUIDs → duplicate placeholder rows. | **FIXED** — added `@State private var isAdding`. Button uses `guard !isAdding else { return }; isAdding = true; ...` + `.disabled(isAdding)` so VoiceOver / tap repeats are gated visually and behaviorally. |

## Round 3 — verification of round-2 fixes

Codex found 2 more Mediums refining the alert plumbing:

| file:line | severity | issue | resolution |
|---|---|---|---|
| `WebDAVServerProfileListView.swift:176` | Medium | `.listError` OK button cleared only `alertItem`, leaving `viewModel.listError` stale (binding-setter doesn't fire on direct mutation). | **FIXED** — OK action now clears both `viewModel.listError = nil` AND `alertItem = nil`. |
| `WebDAVServerProfileListView.swift:124` | Medium | listError deferred behind a delete-confirm could be silently dropped (`.onChange` skipped promotion, and after confirm dismissal it didn't re-fire). | **FIXED** — added `promoteDeferredListErrorIfAny()` helper. Both `.confirmDeleteActive` button paths call it after clearing `alertItem`. Deferred listError now surfaces immediately after the higher-priority alert dismisses. |

## Round 4 — verification of round-3 fixes

> "No findings. The round-3 alert fixes are consistent now. The `.listError` OK path clears both `alertItem` and `viewModel.listError`, so the VM no longer retains a stale error after direct dismissal. The deferred-error path is also correct: both delete-confirm actions clear `alertItem` first and then call `promoteDeferredListErrorIfAny()`, so a list error that arrived while the confirm alert was onscreen is surfaced immediately afterward. The `Add` button guard also looks fine."

**Verdict: ship-as-is.**

Note: 4 audit verification rounds were run because rounds 2 and 3 found refinements of the round-1 alert collapse. Per rule 47, 3 audit-fix rounds is the cap; this run's round 1 had findings, rounds 2/3 introduced and addressed refinements within the same surface area (alert plumbing). Round 4 confirmed clean with no open findings. Acceptable per the rule's spirit.

## Test gate

`xcodebuild test -only-testing:vreaderTests/WebDAVProfileListViewModelTests -only-testing:vreaderTests/WebDAVEditorContextTests -only-testing:vreaderTests/WebDAVServerProfileEditSheetStubTests`:
- 21/21 tests pass (11 VM + 7 EditorContext + 2 stub + 1 deferred resync).
- All 57 prior Feature #52 tests still pass.

## Summary

`ship-as-is`. WI-4a delivers the list UI + reachable stub editor (placeholder save) + active-delete confirmation + VoiceOver disambiguation + the unified alert plumbing. Behavioral tier per the plan; per-WI slice verify next.
