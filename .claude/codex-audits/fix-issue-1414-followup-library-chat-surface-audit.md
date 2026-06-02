---
branch: fix/issue-1414-followup-library-chat-surface
threadId: codex-exec (RUN-CODEX RESULT SUCCEEDED, see /tmp/fix1414b-audit.txt)
rounds: 1
final_verdict: ship-as-is
date: 2026-06-03
---

# Gate-4 Codex audit — Bug #310 follow-up (Library general-chat cream-surface pin)

Follow-up to the original #310 fix (PR #1421, merged). **Device verification in
Dark Mode caught a regression the unit test missed**: routing the empty-state /
placeholder to the Paper-family dark `sub` token is correct for the reader AI
panel's CREAM sheet, but the general Library chat (`LibraryViewSheets.aiChatSheet`)
is `.sheet`-presented with NO surface pin — in system Dark Mode it fell to a
SYSTEM-DARK sheet, so the dark `sub` token rendered dark-on-dark (invisible).

This follow-up pins that sheet to the cream Paper surface: `theme: .paper` +
`.background(Color(paper.sheetSurfaceColor).ignoresSafeArea())` +
`.preferredColorScheme(.light)`. Independent audit (Codex gpt-5.4, high, read-only).

## Findings & resolutions

| # | file:line | severity | issue | resolution |
|---|---|---|---|---|
| — | — | — | **No correctness findings.** Scope confirmed correct (reader AI panel supplies its own theme at `AIReaderPanel.swift:154`, so this only affects the Library general chat). `.paper` pin is consistent with the repo's "library-owned sheet defaults to paper" pattern (`SettingsView.swift:175`) + the design's `theme \|\| THEMES.paper` fallback (`vreader-panels.jsx:601`). `.preferredColorScheme(.light)` is a no-op in Light Mode and the right way to align nav/title/button/keyboard chrome with the cream surface. | — |
| 1 | `LibraryViewSheets.swift` | Low | The fix was only device-verified; existing tests prove the token over cream but not that the presenter keeps pinning `.paper`/`.light`, so this host-level regression could recur while tests pass. | **FIXED** — exposed `LibraryViewSheets.generalChatTheme` (`static`) and added `AIChatViewContrastTests.libraryGeneralChat_pinsLightFamilyCreamSurface`: asserts the presenter pins a light-family (`!isDark`) Paper theme and that the secondary content clears AA over its surface. A host that drifts to a dark family now fails here, not silently in Dark Mode. |

## Device verification

iPhone 17 Pro Simulator, system Dark Mode, `--enable-ai`, merged-build + this
follow-up installed. Library → AI Chat:

- **Pre-fix** (`bug-310-library-chat-PREFIX-darkmode-regression-20260603.png`):
  dark sheet, "Start a conversation" + bubble icon near-invisible (dark-on-dark).
- **Post-fix** (`bug-310-library-chat-cream-darkmode-20260603.png`): cream sheet,
  empty-state + "Type a message…" placeholder legible (dark-on-cream); nav chrome
  dark-on-cream.

## Verdict

`ship-as-is` — no correctness findings; the Low (test coverage for the host pin)
is closed with a presenter-level regression test. The reader AI panel (the bug's
primary surface) uses the same `AIChatView` + tokens on its already-cream sheet.
