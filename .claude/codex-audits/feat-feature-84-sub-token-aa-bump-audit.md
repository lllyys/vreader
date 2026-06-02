---
branch: feat/feature-84-sub-token-aa-bump
threadId: 019e88ef-83ea-7491-afea-9015497c00a5
rounds: 1
final_verdict: follow-up-recommended
date: 2026-06-02
---

# Gate-4 Codex audit — Feature #84 (secondary-text `sub`-token AA bump)

Independent audit (Codex gpt-5.4, high effort, read-only) of the diff bumping
the light-family `ReaderThemeV2.sub` token from ink@0.55 → ink@0.68 per the
landed design `design-notes/secondary-text-sub-token.md` (resolves the closed
needs-design #1292; GH #1413). One round; author=this session, auditor=Codex
(rule-48 separation preserved).

## Findings & resolutions

| # | file:line | severity | issue | resolution |
|---|---|---|---|---|
| 1 | `vreaderTests/Services/EPUBThemeOverrideCSSV2Tests.swift:47,68` | Medium | `ReaderThemeV2+EPUBCSS` serializes `subColor` into `a:visited`; the test still hard-codes `0.55`, so the global bump would fail that suite (incomplete diff). | **FIXED** — updated Paper/Sepia `a:visited` assertions to `0.68`. The darkening is consistent with the design's deliberate choice of the *global* `sub` token (it rejected a scoped `subAA` token) and is a strict legibility improvement for visited links. |
| 2 | `ReaderBottomChrome.swift:69`, `ReadingDashboardView.swift:178`, `TranslationPanel.swift:65` | Medium | `0.68` clears AA on the Display sheet `#fcf8f0` (Sepia 4.88:1) but only ~4.27:1 / ~4.39:1 on Sepia `chromeColor` / `paperColor`, where some reader chrome renders `sub`. So the global bump doesn't make *all* Sepia `sub` text AA. | **ACCEPTED with rationale** — the change matches the binding design exactly (it targets the cream sheet) and is a *strict improvement* everywhere (was 3.36:1; alpha-up raises contrast on every surface). Bringing the other light-family surfaces to a full 4.5:1 needs either a darker value or per-surface tokens — both design decisions the landed note did not make (and the per-surface `subAA` token was the explicitly *rejected* alternative). Recorded as a follow-up to surface to the user, alongside the design note's own out-of-scope Dark/OLED item. NOT chased here (would be self-designed UI per Rule 51). The new AA test asserts AA over `sheetSurfaceColor` only — honest scoping, no global-AA claim. |
| 3 | `vreader/Models/ReaderThemeV2.swift:9` | Low | Source-of-truth drift: header + tests say values are pinned to `vreader-themes.jsx` (still `sub`=0.55), but the code now follows `secondary-text-sub-token.md`. | **FIXED** — updated the header comment in `ReaderThemeV2.swift` and the test-matrix comment in `ReaderThemeV2Tests.swift` to state the design note supersedes the bundle for the light-family `sub` value. (Did not hand-edit the design bundle `.jsx` — design artifacts are not code-edited; the note is the newer design authority.) |
| 4 | `ReaderSettingsPanelContrastTests.swift:97` | Low | `secondaryChromeLabelClearsSecondaryBar` (≥3.0) is now redundant — the new ≥4.5 AA test on the same themes/surface subsumes it. | **FIXED** — removed the redundant ≥3.0 test. |

## Verified by the auditor

- `0.68` is correct per `secondary-text-sub-token.md`; ratios reproduced exactly:
  Paper 5.8198:1, Sepia 4.8834:1 over `#fcf8f0`.
- No other runtime/test pin of light-family `sub`=0.55 beyond the EPUB CSS suite
  (the remaining `0.55` hits are design artifacts / comments / unrelated numbers).
- Dark/OLED unchanged is defensible — the landed note explicitly scopes them out;
  their ~3.75:1 / ~3.06:1 over `#222020` remains known debt, not a hidden
  regression introduced here.

## Verdict

`follow-up-recommended` — all Critical/High/Medium findings resolved (one fixed,
one accepted with rationale tied to a surfaced follow-up); both Lows fixed. The
follow-up: lift the remaining light-family surfaces (Sepia `chromeColor` /
`paperColor`) and Dark/OLED secondary text to AA — a separate design decision to
surface to the user, not this slice's scope.
