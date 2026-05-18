---
branch: docs/readme-icon-rounded
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-19
---

## Scope

Replaces `docs/icon.png` (the README header icon) with a rounded,
transparent-cornered version. Touches `docs/icon.png` only, plus
`project.yml` / `project.pbxproj` (version bump 3.30.7/458 →
3.30.8/459).

**No Swift source files changed.** The audit-gate hook fires on
`project.pbxproj` — false positive of the Swift-file heuristic. Manual
mini-audit.

## Manual audit evidence

### What changed and why

The previous `docs/icon.png` (added in PR #872) was a full-bleed cream
square — in a README `<img>` no corner mask is applied, so it rendered
as a hard-edged box whose cream edge contrasted with the white page
like an unwanted border.

New `docs/icon.png`: the v2 app icon (the variant with the oxblood
rules flanking the centre dot), cropped from a user-supplied render to
its 240×240 bounds, then given a supersampled rounded-rectangle alpha
mask (radius 54 px ≈ 22.5 %, iOS-proportioned). The four corners are
now fully transparent (RGBA), so the icon sits cleanly on any README
background — light or dark — with no square border.

### Correctness checks

1. **Transparent corners** — output verified `RGBA`, `hasAlpha: yes`,
   240×240. The rounded-rect mask was supersampled 4× then Lanczos-
   downscaled for a smooth, halo-free edge; the icon content is cream
   to its bounds, so the mask edge feathers over cream (no white
   halo).
2. **Content unclipped** — the "V" wordmark and "READER" caption are
   centred, far inside the 54 px corner radius; rounding clips only
   background.
3. **README reference unchanged** — `README.md` already points
   `<img src="docs/icon.png" width="120">` at this path; replacing the
   file in place is sufficient.
4. **Icon provenance note** — this is the v2 design icon (with the
   flanking rules). It differs slightly from the current
   `vreader/Assets.xcassets/AppIcon.appiconset/icon-1024.png`, which
   lacks those rules; the shipped `AppIcon` asset is a candidate for a
   separate sync, out of scope here.
5. **Version bump** — 3.30.8 / build 459 (patch — docs / asset
   change). `xcodegen generate` confirmed.

## Verdict

ship-as-is — one documentation image asset + version bump. No Swift
logic, no code risk. Manual fallback used because there is nothing to
send to Codex.
