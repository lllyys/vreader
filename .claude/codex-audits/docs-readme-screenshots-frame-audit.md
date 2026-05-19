---
branch: docs/readme-screenshots-frame
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-19
---

## Scope

Reframes the three README "Screens" images — replaces the heavy black
device frame with a light phone mockup. Touches
`docs/screenshots/{library,reader,settings}.png`, plus `project.yml` /
`project.pbxproj` (version bump 3.31.1/461 → 3.31.2/462).

**No Swift source files changed.** The audit-gate hook fires on
`project.pbxproj` — false positive of the Swift-file heuristic. Manual
mini-audit.

## Manual audit evidence

### What changed and why

The screenshots carried a thick black device-frame bezel that read as a
heavy black border on the README page. The fix, per user request, is a
*lighter* phone mockup (not removing the device entirely).

Per image: the screen content is located by a mode-based scan and
cropped out of the black bezel; masked to a rounded rectangle (radius
78 px, the device's real screen rounding); then composited onto a thin
**warm light-gray** rounded bezel (14 px, `#cdcbc6`) with a soft drop
shadow (offset 16 px, blur 19 px, ~20 % black). Outer corners and the
area around the device are transparent (RGBA). All three: 616×1338
screen → 736×1484 framed canvas.

This mirrors the design bundle's own device treatment in
`ios-frame.jsx` (`IOSDevice`): a light frame with a soft shadow — not a
black bezel.

### Correctness checks

1. **Light frame, no black** — the bezel is `#cdcbc6` (light warm
   gray); verified on a downscaled preview of `reader.png` — the phone
   floats with a soft shadow, no heavy border.
2. **Transparent surround** — all three re-saved `RGBA`; shadow and
   bezel masks supersampled 4× then Lanczos-downscaled for smooth
   edges.
3. **Concentric bezel** — outer radius = screen radius 78 + bezel 14 =
   92, so the 14 px bezel is uniform around the corner.
4. **Content intact** — only the black device frame was removed; the
   app screen content is unchanged and unclipped (full `reader.png`
   preview: nav bar, body text, scrubber, toolbar all present).
5. **README reference unchanged** — `README.md` already points the
   `Screens` table at these three paths; the `width="230"` display
   scales the framed images consistently.
6. **Version bump** — 3.31.2 / build 462 (patch — docs / asset
   change). `xcodegen generate` confirmed.

## Verdict

ship-as-is — three documentation image assets + version bump. No Swift
logic, no code risk. Manual fallback used because there is nothing to
send to Codex.
