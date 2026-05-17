---
branch: fix/issue-758-debugbridge-thememode
threadId: 019e33d6-e0ac-73e0-8564-fb9d0ec8644e
rounds: 1
final_verdict: ship-as-is
date: 2026-05-17
---

## Gate 4 — Codex implementation audit, Bug #206 / GH #758

`DebugCommand.ThemeMode` only accepted `dark`/`light`, so Feature #60's
5-theme palette (paper / sepia / dark / oled / photo) could not be
driven from `vreader-debug://theme?mode=<X>` — sepia/oled/photo verify
slices got `parse.invalidParam` and silently fell back to UI gestures.

Fix: extend `ThemeMode` to the 5-theme palette plus `light` as a
backward-compatible alias for `paper`; replace the two-valued ternary
in `RealDebugBridgeContext.theme` with an exhaustive `switch`; derive
the invalid-mode error message from `ThemeMode.allCases`.

Codex MCP, read-only sandbox. Thread `019e33d6-e0ac-73e0-8564-fb9d0ec8644e`.

## Round 1

**Verdict: clean — no Critical/High/Medium/Low findings.**

Codex confirmed:

- **Root cause fixed** — `ThemeMode` now accepts all 5 `ReaderThemeV2`
  cases; `light → paper` matches the existing migration contract in
  `ReaderTheme+ToV2.swift` and `ReaderThemeV2.swift`.
- **Exhaustiveness** — the `switch mode` in `RealDebugBridgeContext.theme`
  is exhaustive (no `default`), so any future `ThemeMode` case forces a
  compile error rather than a silent fallback.
- **Error-message drift removed** — building the invalid-mode message
  from `ThemeMode.allCases` eliminates the stale hard-coded `dark|light`.
- **Security** — no JS-exec or filesystem-path surface touched; the
  surrounding parser's basename validation is unchanged.
- **DEBUG / concurrency / size** — files stay DEBUG-gated,
  `RealDebugBridgeContext` stays `@MainActor`, file-size rule respected.
- **Tests meaningful** — the parser test fails pre-fix (those raw
  values were rejected); the bridge test verifies persistence for the
  new modes; the existing `light` notification test still covers the
  alias collapsing to canonical `"paper"`.

## Resolution summary

Zero findings in round 1. Codex's only residual note was that it did
not execute the suite in the read-only session — covered by the
Phase 5 `xcodebuild test` gate (RED confirmed pre-fix: 1 failure;
GREEN post-fix: 77/77 in the DebugBridge slice).

**Verdict: ship-as-is.**
