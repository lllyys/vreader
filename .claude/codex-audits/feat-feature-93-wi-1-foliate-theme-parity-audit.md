---
branch: feat/feature-93-wi-1-foliate-theme-parity
threadId: 019e940d-dce9-7dd3-a6cf-05da12ac3674
rounds: 2
final_verdict: ship-as-is
date: 2026-06-05
---

# Gate-4 Implementation Audit — Feature #93 WI-1 (AZW3/MOBI Foliate theme-color parity)

Codex `gpt-5.4` / high effort, read-only. Author = claude (implementer);
auditor = Codex (separate context) — rule-48 author/auditor separation held.

Changed source files audited:
- `vreader/Models/ReaderThemeV2+EPUBCSS.swift`
- `vreader/Services/Foliate/FoliateStyleMapper.swift`
- `vreader/Views/Reader/FoliateSpikeView.swift`

## Round 1 — session `019e9409-1b36-7a32-bb13-a891cfd55378` → follow-up-recommended

| file:line | severity | issue | resolution |
|---|---|---|---|
| FoliateStyleMapper.swift:102 | Medium | Descendant `color: inherit` reset omitted headings `h1`-`h6`; a publisher `h1 { color }` survives `body { color }`, so chapter titles can mis-render on dark/sepia. EPUB resets heading color. | **Fixed** — headings prepended to the color-reset selector list (`h1, h2, h3, h4, h5, h6, p, div, …, font { color: inherit !important; }`). New regression test `descendantColorResetIncludesHeadings`. |
| ReaderThemeV2+EPUBCSS.swift:343 | Low | `outerBackgroundColorCSS` accessor is dead code — the host shell consumes `UIColor` (`theme.backgroundColor`) directly, not the CSS string. | **Fixed** — accessor removed; the unused param dropped from the `themeColorCSSAccessors` test. |

## Round 2 — session `019e940d-dce9-7dd3-a6cf-05da12ac3674` → ship-as-is

> No remaining/new Critical/High/Medium findings. Verified: the descendant
> color reset now includes `h1`-`h6` (consistent with EPUB's
> `ReaderThemeV2+EPUBCSS` heading reset); `outerBackgroundColorCSS` is gone
> with no live references (only a planning-doc note remains); the host shell
> uses `theme.backgroundColor` directly via `hostShellBackgroundColor` and the
> `hostBackgroundColor` representable property.

## Verdict

**ship-as-is.** Both round-1 findings resolved; no new Critical/High/Medium.
Test gate green (79 tests across `FoliateSpikeThemeCSS`,
`FoliateStyleMapperColorReset`, `FoliateStyleMapper`,
`FoliateStyleMapperCascadeFlatten`).
