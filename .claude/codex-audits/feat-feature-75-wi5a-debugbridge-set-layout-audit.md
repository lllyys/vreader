---
branch: feat/feature-75-wi5a-debugbridge-set-layout
threadId: codex-exec-gpt-5.5-20260531
rounds: 1
final_verdict: ship-as-is
date: 2026-05-31
---

# Codex Audit — Feature #75 WI-5a (`set-layout` DebugBridge command)

## Scope

DEBUG-only verification-harness command `set-layout?mode=<paged|scroll>` that
switches the live EPUB reader's layout preference CU-free (XCUITest cannot tap
the segmented `Picker(.segmented)` on iOS 26; the `--reader-default-layout=`
launch arg only pre-seeds the default before a book opens). Follows the
established `navigate` / `seek` / `present` DebugBridge command pattern.

Files reviewed (6 production):
- `vreader/Services/DebugBridge/DebugCommand.swift` (parser case + local `LayoutMode` enum)
- `vreader/Services/DebugBridge/DebugBridge.swift` (protocol method + dispatch case)
- `vreader/Services/DebugBridge/DebugBridgeNotifications.swift` (new notification name)
- `vreader/Services/DebugBridge/RealDebugBridgeContext+SetLayout.swift` (handler)
- `vreader/Views/Reader/EPUBReaderContainerView+DebugBridgeSetLayout.swift` (ViewModifier observer)
- `vreader/Views/Reader/EPUBReaderContainerView.swift` (applies the modifier)

## Audit focus

Parser validation completeness, notification `userInfo` round-trip
(parser → handler → observer), `[weak settingsStore]` capture correctness,
@MainActor / Sendable / Swift-6 concurrency, DEBUG gating (compile out of
Release), and the safety of the observer's `settingsStore.epubLayout` mutation
vs how the segmented Picker drives the same binding.

## Round 1 — findings

**Clean. No issues found across the six reviewed files.**

Codex verdict (gpt-5.5, read-only sandbox): parser validation, `mode` userInfo
round-trip, weak capture, MainActor path, DEBUG gating, and the
`settingsStore.epubLayout` mutation all match the established DebugBridge command
patterns.

## Resolution

No findings to resolve.

## Test evidence

- Targeted: `vreaderTests/DebugCommandTests` + `vreaderTests/RealDebugBridgeContextTests`
  + `vreaderTests/DebugBridgeTests` — 342 tests, 0 failures.
- New tests: 6 parser cases (valid paged/scroll, missing/invalid/empty mode,
  deep-path) + 2 handler cases (paged/scroll post the correct `mode` userInfo).
- Full `vreaderTests` suite run as the merge regression gate.

## Summary verdict

ship-as-is.
