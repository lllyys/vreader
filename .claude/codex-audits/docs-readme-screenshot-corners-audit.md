---
branch: docs/readme-screenshot-corners
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-19
---

## Scope

Rounds the corners of the three README "Screens" images with
transparency. Touches `docs/screenshots/{library,reader,settings}.png`,
plus `project.yml` / `project.pbxproj` (version bump — rebased onto
main: 3.31.0/460 → 3.31.1/461).

**No Swift source files changed.** The audit-gate hook fires on
`project.pbxproj` — false positive of the Swift-file heuristic. Manual
mini-audit.

## Manual audit evidence

### What changed and why

The three device-framed screenshots had hard dark **square** outer
corners — the black device-frame bezel filled the image rectangle all
the way to the square corners (the screen inside is rounded, the outer
edge was not). Against the README page that reads as a boxed, hard
edge — the same defect just fixed on the app icon.

Each image now carries a supersampled rounded-rectangle alpha mask
(RGBA): the four outer corners are transparent, rounded at a radius
measured per image from the frame geometry — `bezel thickness + inner
screen radius`, so the outer rounding is concentric with the screen's
inner rounding and the bezel stays a uniform thickness around the
corner. Measured radii: library 71 px, reader 67 px, settings 69 px.

### Correctness checks

1. **Transparent corners** — all three re-saved as `RGBA`; the mask was
   supersampled 4× then Lanczos-downscaled for a smooth edge. The mask
   edge feathers over the bezel black, no halo.
2. **Concentric bezel** — radius = `bezel + inner_radius`, so the
   rounded outer corner shares a centre with the screen's inner corner;
   verified visually on a 3× corner crop — uniform bezel, clean phone
   corner.
3. **Content untouched** — only the corner regions outside the rounded
   frame become transparent; the screen content and bezel edges are
   unchanged.
4. **README reference unchanged** — `README.md` already points the
   `Screens` table at these three paths; replacing the files in place
   is sufficient.
5. **Version bump** — 3.31.1 / build 461 (patch — docs / asset change),
   rebased over main's 3.31.0/460. `xcodegen generate` confirmed.

## Verdict

ship-as-is — three documentation image assets + version bump. No Swift
logic, no code risk. Manual fallback used because there is nothing to
send to Codex.
