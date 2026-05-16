---
branch: feat/app-icon-vreader-identity
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-16
---

## Scope

Ships the VReader app icon from the claude.ai/design handoff (share token `SEI7UfqurCl2Kuj6ctt__Q`). The branch touches:

- `vreader/Assets.xcassets/AppIcon.appiconset/icon-1024.png` (new — the icon raster)
- `vreader/Assets.xcassets/AppIcon.appiconset/Contents.json` (added `"filename": "icon-1024.png"`)
- `project.yml` + `vreader.xcodeproj/project.pbxproj` (version bump 3.23.17/394 → 3.24.0/395)

**No Swift source files changed.** The audit-gate hook fired because `project.pbxproj` (which references `.swift` paths) is in the diff — a false positive of the Swift-file heuristic. Manual mini-audit per the `/fix-issue` fallback procedure.

## Manual audit evidence

### Files read / verified

- `vreader/Assets.xcassets/AppIcon.appiconset/Contents.json` — confirmed the single-size 1024×1024 iOS slot now carries `"filename": "icon-1024.png"`; `idiom: universal`, `platform: ios` unchanged. Valid asset-catalog JSON.
- `icon.svg` (design source) — confirmed the design is a full-bleed 1024×1024 square (`<rect width="1024" height="1024" fill="url(#paper)">`); the rounded corners come only from a `clipPath` with `rx="229"` (macOS squircle).

### Correctness checks

1. **iOS opacity requirement** — verified via PIL: the shipped `icon-1024.png` is `mode=RGB`, `size=1024×1024`, fully opaque. TL corner `(246,239,222)`, BR corner `(234,216,180)`, center `(240,227,200)`. The delivered raster was RGBA with transparent corners (alpha 0–255, ~4.3% transparent — baked macOS rounding); it was composited onto the opaque paper gradient (`#f6efde→#ead8b4` diagonal per `icon.svg`'s linearGradient) and saved as RGB. Correct iOS app-icon form — iOS applies its own corner mask.
2. **Design fidelity** — the composite preserves every design pixel inside the squircle region (the icon's own alpha was used as the paste mask); only the previously-transparent corner triangles are filled, and they get the matching gradient. iOS re-masks those corners anyway, so the fill is effectively invisible.
3. **Build** — `xcodebuild build -scheme vreader -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` → `** BUILD SUCCEEDED **`. The asset catalog compiles; `actool` accepts the icon.
4. **Version bump** — `project.yml` and `project.pbxproj` both reflect 3.24.0 / build 395 (minor — new user-visible asset). xcodegen regen confirmed.

### Edge cases checked

- **Single-size vs ladder** — the asset catalog already declared single-size 1024 (modern Xcode 16 / iOS 17). The bundle's macOS-style size ladder (16–512) is design source-of-truth, not shipping iOS assets — intentionally excluded from this PR.
- **Alpha at App Store submission** — the icon is now RGB (no alpha channel), so it passes App Store icon-opacity validation. (The delivered RGBA would have been flagged.)
- **No DEBUG-only symbols, no notifications, no concurrency surface** — this is an asset-only change; the codebase-conventions / Swift-6 / file-size rules do not apply.

### Risks accepted

None. Asset-only change, build-verified, design-faithful.

## Verdict

ship-as-is — asset + asset-catalog + version-bump only. No code risk. Manual fallback used because there is no Swift logic to send to Codex.
