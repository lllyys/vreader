---
branch: docs/readme-app-icon
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-19
---

## Scope

Adds the VReader app icon to the `README.md` header. Touches `README.md`
and `docs/icon.png` (new), plus `project.yml` / `project.pbxproj`
(version bump — rebased onto main: 3.30.6/457 → 3.30.7/458).

**No Swift source files changed.** The audit-gate hook fires on
`project.pbxproj` — false positive of the Swift-file heuristic. Manual
mini-audit.

## Manual audit evidence

### What changed and why

- `docs/icon.png` — the shipped app icon, downscaled with `sips` from
  `vreader/Assets.xcassets/AppIcon.appiconset/icon-1024.png` (the real
  `AppIcon` asset) to 256×256, 58 KB. Source is the authoritative
  shipped icon, not a design-bundle render — honest representation.
- `README.md` — a centered `<p align="center"><img …></p>` block added
  above the `# VReader` title, displaying the icon at 120 px width with
  an `alt` attribute.

### Correctness checks

1. **Icon provenance** — `docs/icon.png` is derived directly from the
   app's `AppIcon.appiconset/icon-1024.png`; it is the icon the app
   actually ships, not the design-tool export. Resize only, no other
   edit.
2. **Image path resolves** — README references `docs/icon.png`; the
   file exists at that path (repo-root-relative, renders on the GitHub
   project page).
3. **HTML-in-Markdown** — `<p align="center">` + `<img>` is standard
   GFM; the `<img>` has an `alt` attribute. The existing `# VReader`
   heading and all following content are unchanged.
4. **Version bump** — 3.30.7 / build 458 (patch — docs / asset change),
   rebased over main's 3.30.6/457. `xcodegen generate` confirmed.

## Verdict

ship-as-is — documentation + one image asset + version bump. No Swift
logic, no code risk. Manual fallback used because there is nothing to
send to Codex.
