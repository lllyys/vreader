---
branch: feat/feature-60-wi-5-txt-md-theme
threadId: 019e2e0a-cce5-76f0-97d8-f2d794d71b6e
rounds: 2
final_verdict: ship-as-is
date: 2026-05-16
---

# Codex Gate 4 audit — Feature #60 WI-5 (TXT + MD theme injection)

Audit of WI-5: routing `ReaderSettingsStore`'s TXT/MD color
accessors through `ReaderThemeV2`'s 7-token surface (`backgroundColor`
/ `inkColor` / `subColor` / `paperColor`) via the WI-4
`ReaderTheme.asV2` projection. Mirrors WI-4 (EPUB CSS) for the
TXT/MD render paths so TXT and MD pick up the new visual identity.

## Round 1 — initial audit

| Finding | Severity | Resolution |
|---|---|---|
| `MDAttributedStringRenderer.swift:213, 238` — WI-5 was incomplete for MD: blockquote bodies still hard-coded `UIColor.secondaryLabel`, fenced code blocks still hard-coded `UIColor.secondarySystemBackground`. Body text routed through V2 but secondary surfaces stayed platform-default. | Medium | **Fixed**: extended `MDRenderConfig` with `secondaryColor` (default `.secondaryLabel`) and `codeBackgroundColor` (default `.secondarySystemBackground`) — defaults preserve backward-compat for any caller constructing the config directly. `ReaderSettingsStore.mdRenderConfig` now passes `theme.asV2.subColor` and `theme.asV2.paperColor`. `MDAttributedStringRenderer` reads the new fields instead of UIKit defaults. The 34 existing MD renderer tests continue to pass. |
| `TXTViewConfigThemeTests.swift:105, 113` — alpha-only assertions for `uiSecondaryTextColor` would have passed a regression to the wrong RGB with the same alpha. | Low | **Fixed**: strengthened both tests to full RGB + alpha assertions, pinning RGB equals ink-RGB (proving the routing). Added two new tests for `mdRenderConfig.secondaryColor` and `.codeBackgroundColor` pinning per-theme V2 values. |

## Round 2 — verification of round-1 fixes

**No findings.** Codex confirmed:

- `MDRenderConfig`'s `Equatable` extension correctly includes both
  new fields, so config diffing won't miss theme changes.
- `paperColor` is a defensible mapping for `codeBackgroundColor` —
  the token's documented meaning is the text-container/elevated
  surface, which matches "code block as nested surface" better than
  `chromeColor`. The lighter-on-Paper result is a visual choice,
  not a correctness bug.
- Other `MDRenderConfig(...)` call sites are safe — remaining
  constructors are tests using legacy/default behavior, and the
  defaults preserve that path.

**Residual gap closed inline**: Codex flagged (not as a finding) the
absence of renderer-level tests proving the new fields propagate
when they differ from defaults. Closed by adding two tests in
`MDAttributedStringRendererTests.swift` (`blockquoteUsesConfigSecondaryColor`,
`fencedCodeBlockUsesConfigCodeBackground`) that inject non-default
colors (`.red` / `.green`) and assert they reach the rendered
attributed string. Total new test count: 12 V2 theme tests + 2
renderer-level tests = 14 new.

## Final verdict

**ship-as-is**

- Zero open Critical / High / Medium findings.
- 20+ V2 + renderer tests pass; 9 ReaderSettingsStore tests pass;
  34 MD renderer tests pass — no regressions in adjacent suites.
- Plan promises (TXT/MD theme injection via V2 + per-theme color
  flow, including code-block + blockquote secondary surfaces) all
  met.

## Manual fallback section

Not applicable — Codex MCP available throughout; thread id
`019e2e0a-cce5-76f0-97d8-f2d794d71b6e` used for both rounds.
