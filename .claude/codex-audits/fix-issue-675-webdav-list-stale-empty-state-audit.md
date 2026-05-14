---
branch: fix/issue-675-webdav-list-stale-empty-state
threadId: 019e283f
rounds: 2
final_verdict: ship-as-is
date: 2026-05-15
---

# Codex audit — Bug #190 (GH #675) — WebDAV server profile list stale empty-state after mutations

## Round 1 — initial audit

**Files in scope** (`git diff main --name-only` excluding bugs.md / version bump):

- `vreader/Views/Settings/WebDAVSettingsView.swift`

**Diff summary**: hoisted `WebDAVProfileListViewModel()` from inline-in-NavigationLink-destination to a `@State` property on the parent (`WebDAVSettingsView`). NavigationLink destination now passes the stable VM instance to `WebDAVServerProfileListView(viewModel:)` instead of constructing a fresh VM per render.

**Codex findings** (1 Low):

| # | severity | file:line | issue | fix |
|---|---|---|---|---|
| 1 | Low | `vreader/Views/Settings/WebDAVSettingsView.swift:53-63` | The doc-comment for the new `@State` references `SettingsView.swift:21` — hard-coded line number that will rot when SettingsView changes (already the audit's own rule 22 anti-pattern; one of the changes that rule was written against). | Replace `SettingsView.swift:21` with a type-name reference (`SettingsView` owns `AISettingsViewModel` in `@State`…) so the comment survives reflows. |

**Resolution**: comment updated to reference type names only (no line numbers / file paths). Same commit.

## Round 2 — re-audit after fix

**Codex findings**: none.

**Verdict**: **ship-as-is**.

## Summary

- 2 rounds, 1 Low total, fixed in same commit.
- Root cause: SwiftUI re-evaluates the NavigationLink destination closure on every parent re-render. Constructing the VM inline produced a fresh, empty `WebDAVProfileListViewModel` instance every time the parent re-rendered — most visibly after the editor sheet's `dismiss()` returned to the parent. The list's `.task { await viewModel.loadProfiles() }` *was* firing on the new VM, but the empty-state flash visible during the async hop was the symptom the verify cron filed.
- Fix mirrors the canonical AI-sibling ownership pattern (`SettingsView` owns `AISettingsViewModel` in `@State` and threads it into `AISettingsSection` / `AIProviderListView`).
- No new test added: this is pure SwiftUI ownership semantics, not testable in unit-test layer without a ViewInspector-style harness vreader doesn't use. The bug is in **where the VM lives**, not in any method's behavior; existing 21+31 VM-level tests at WI-4a/4b cover the data layer correctness already established.
- Manual fallback evidence: not applicable, Codex MCP was available both rounds.

## Manual verification (pre-FIXED simulator pass on iPhone 17 Pro Simulator)

- Build under test: v3.21.61 (commit installed locally pre-bump).
- Steps: Settings → WebDAV Backup → Servers → tap pencil on Server A → Edit Name to "Server A (bug190 verify)" via clipboard paste → tap Save → editor dismisses.
  - **Pre-fix**: list rendered "No WebDAV Servers" empty state + Add Server CTA.
  - **Post-fix**: list immediately rendered renamed "Server A (bug190 verify)" entry — no empty-state flash.
  - Evidence: `dev-docs/verification/artifacts/bug-190-postfix-list-refreshes-after-save-20260515.png`.
- Add path: tap + → pasted "Server C (verify add)" / http://127.0.0.1:8082/ / vra / passworda → Add.
  - **Post-fix**: list shows BOTH "Server A (bug190 verify)" and "Server C (verify add)". Add-path also confirmed.
