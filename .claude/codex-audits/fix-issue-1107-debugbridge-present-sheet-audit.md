---
branch: fix/issue-1107-debugbridge-present-sheet
threadId: 019e4846-2483-7482-9c96-b882b9bfc8b7
rounds: 2
final_verdict: ship-as-is
date: 2026-05-21
---

# Codex Audit — fix/issue-1107-debugbridge-present-sheet

**Bug**: #253 / GH #1107 — DebugBridge `present?sheet=…` command
**Auditor**: Codex MCP (gpt-5.2-codex), thread `019e4846-2483-7482-9c96-b882b9bfc8b7`
**Sandbox**: read-only
**Rounds**: 2
**Verdict**: ship-as-is (clean after round-1 fixes)

## Scope

Production diff for the new DEBUG-only `vreader-debug://present?sheet=<toc|highlights|ai|settings|bookmarks>[&tab=<...>]`
command: parser (`DebugCommand.swift`), dispatch (`DebugBridge.swift`),
handler (`RealDebugBridgeContext+Present.swift`), notification
(`DebugBridgeNotifications.swift`), pure resolver
(`DebugPresentSheetEffect.swift`), reader-host observer
(`ReaderContainerView+DebugBridgePresent.swift`), body wiring
(`ReaderContainerView.swift`).

## Round 1 — findings

- **Medium** — `present?sheet=ai&tab=translate` did not mirror the production
  selectionless-translate path. `ReaderOpenAITranslateObserver` calls
  `translationViewModel?.reset()` before opening the Translate tab cold; the
  new debug path only set `aiInitialTab`/`showAIPanel`, so a prior selection's
  stale translated text + result could still be visible — corrupting the very
  verification the command exists to enable.
  **Fix**: the `.ai` observer case now calls `ensureAIReady()` then
  `resolvedAICoordinator.translationViewModel?.reset()` when `initialTab ==
  .translate`, matching production. (commit `9fb1b61c`)

- **Low** — `DebugPresentSheetEffect` re-encoded the annotations routing table
  for the production-equivalent default cases (`toc → .toc(.contents)`,
  `highlights → .highlights(.all)`), introducing a second source of truth that
  weakens the "same presentation path / no parallel logic" invariant.
  **Fix**: the default (no-tab) `toc`/`highlights` cases now derive from
  `AnnotationsSheetRoute.route(forChromeButton: .contents)` / `.notes` (with a
  literal fallback). Debug-only sub-tabs (`bookmarks` alias, non-default
  highlight filters) remain local. (commit `9fb1b61c`)

Parser edge cases (empty sheet, empty tab, tab-on-no-tab-sheet, unknown sheet,
unknown tab, duplicate keys, trailing slash, deep path), the
lowercase-URL → capitalized-rawValue tab mapping, DEBUG gating, and
MainActor/Sendable isolation were all confirmed correct in round 1.

## Round 2 — verification

Both fixes confirmed resolved. Codex verified `ensureAIReady()` before
`translationViewModel?.reset()` is the correct order — `resolvedAICoordinator`
is lazily created on access and `ensureAIReady()` materializes the AI VMs
first, so the translate-only reset is not a silent no-op on a nil VM.

**Final verdict (verbatim)**: "Clean — both findings are resolved,
`ensureAIReady()` before `translationViewModel?.reset()` is the correct order
because `resolvedAICoordinator` is lazily created on access and
`ensureAIReady()` calls `setupIfNeeded()` to materialize the AI VMs first, so
the translate-only reset mirrors production and is not a silent cold-open
no-op."
