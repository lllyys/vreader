---
branch: fix/issue-1328-settings-dark-on-dark
threadId: codex-exec-gpt-5.5-20260601
rounds: 1
final_verdict: ship-as-is
date: 2026-06-01
---

# Codex Audit — Bug #297 / GH #1328 (App Settings dark-on-dark in Dark Mode)

## Scope

The App Settings sheet pins the light `.paper` theme (`SettingsView.theme = .paper`)
and backs the `Form` with `theme.sheetSurfaceColor`, but the grouped `Section`s
(Cloud & Sync, AI, Reading, About) never set `.listRowBackground`, so their rows
fell through to the appearance-aware system `secondarySystemGroupedBackground`
(charcoal in Dark Mode) — rendering the near-black `.paper` row labels nearly
invisible. Fix: add a design-matched `sheetCardSurfaceColor` token
(`vreader-panels.jsx`: light `#fff`, dark `rgba(255,255,255,0.04)`) and apply
`.listRowBackground(Color(theme.sheetCardSurfaceColor))` to the four grouped
sections. The profile card already used `.listRowBackground(.clear)` (it draws its
own card), so it is left untouched.

Files:
- `vreader/Views/Reader/ReaderSheetChrome.swift` (+ `sheetCardSurfaceColor` token)
- `vreader/Views/Settings/SettingsView.swift` (+ 3 `.listRowBackground`)
- `vreader/Views/Settings/AISettingsSection.swift` (+ 1 `.listRowBackground`)
- `vreaderTests/Views/SheetReSkinSnapshotTests.swift` (+ 2 token tests)

## Round 1 — findings

Codex (gpt-5.5, read-only). **0 Critical/High/Medium. 1 Low (accepted).**

| # | file:line | sev | issue | resolution |
|---|---|---|---|---|
| 1 | SheetReSkinSnapshotTests.swift:116,132 | Low | The two new tests pin the token VALUES (light=#fff, dark=white@0.04) but don't prove the four sections actually apply `.listRowBackground` — removing the modifiers would still pass. | ACCEPTED with rationale (below). |

### Finding #1 — accepted, rationale

- The token-value test matches the **established re-skin convention** in this very
  file: the existing `sheetSurfaceLightForLightThemes` / `…Dark…` tests
  (lines ~100/108) are likewise token-value tests, not application tests. My tests
  are shape-consistent with precedent.
- The repo has **no ViewInspector** (no SwiftUI view-tree assertion harness), so
  `.listRowBackground` *application* is not unit-assertable without adding a new
  dependency — out of scope for a 4-line CSS-class fix.
- The "is the modifier actually applied" behavioral check is covered by the
  **Phase 6a pre-FIXED simulator verification**: open App Settings in system Dark
  Mode on the working-tree build and confirm the rows render on the cream/white
  card (labels legible) rather than charcoal. That exercises the real render path
  the unit test can't reach.

## Verdict

**ship-as-is** — zero Critical/High/Medium; the single Low test-completeness
finding is accepted with rationale and backstopped by Phase 6a device verification.
