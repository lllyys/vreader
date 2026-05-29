---
branch: feat/feature-42-wi7-readium-theme
threadId: codex-exec-readonly
rounds: 2
final_verdict: ship-as-is
date: 2026-05-29
---

# Gate-4 Implementation Audit — Feature #42 WI-7 (Readium theme/font → EPUBPreferences)

Independent Codex audit (`codex exec --sandbox read-only`) of WI-7: map vreader's
existing reader theme/font settings (`ReaderThemeV2` + `TypographySettings`) to
Readium `EPUBPreferences` and apply them live to the Readium EPUB navigator.
Author = implementing session (worktree agent + orchestrator fixes); auditor =
separate `codex exec` process (rule-48 author/auditor separation).

Changed files: `ReadiumEPUBReaderViewModel+Mapping.swift` (full mapping),
`ReadiumEPUBReaderViewModel.swift` (WI-5 wrapper), `ReadiumEPUBHost.swift`
(host reads settings → recompute → submitPreferences live),
`vreaderTests/ViewModels/ReadiumEPUBPreferencesMappingTests.swift` (new).

## Round 1 — 0 Critical / 0 High / 3 Medium

| File | Severity | Issue | Resolution |
|---|---|---|---|
| ReadiumEPUBReaderViewModel+Mapping.swift | **Medium** | `fontSize` mapped raw 18pt→1.0, bypassing the `FontSizeCalibrator` `.epub` band the legacy EPUB engine renders through → cross-format perceived-size regression. | FIXED — mapping gained `calibratedFontSizePt`; the host passes `settingsStore.calibrator.calibratedSize(forUnified: typography.fontSize, target: .epub)`, mapping computes `fontSize = calibratedFontSizePt / 18.0`. WI-5 wrapper passes `fontSizeBasePt` (18 → 1.0). |
| ReadiumEPUBReaderViewModel+Mapping.swift | **Medium** | `.system → nil` is not "publisher default" under `publisherStyles = false` — Readium falls back to its own old-style serif, not vreader's system sans (SF). | FIXED — `.system → .sansSerif` (closest Readium generic to SF). |
| ReadiumEPUBReaderViewModel+Mapping.swift | **Medium** | `.photo`/`useCustomBackground` not faithful — the opaque `backgroundColor` occludes the SwiftUI `ThemeBackgroundView` + the legacy `background-image` CSS isn't reproduced, so the decorative photo image is lost. | FIXED (documented) — file-header note marks it a Phase-1 cosmetic parity gap (readable opaque theme color; photo-image compositing is a deferred slice), flagged for WI-13 acceptance + the WI-14 default-ON flip. No code behavior change; the flag is OFF so nothing user-facing ships. Auditor confirmed no crash/data-risk path. |

Round-1 also confirmed (no bug): live updates work (host body reads `theme`/`typography`/`epubLayout` → `@Observable` deps tracked → `submitPreferences` re-invoked); `publisherStyles=false`, `pageMargins=1.0`, `lineHeight`, color-override composition (`effectiveBackgroundColor = backgroundColor ?? theme.bg`), safe-area assumptions all match Readium 3.9 source.

## Round 2 — clean

**No new Critical/High/Medium findings.** All 3 round-1 Mediums confirmed
resolved:
- Calibrated font size wired correctly; `typography.fontSize` read in the host body keeps the `@Observable` dependency + live re-submit.
- `FontSizeCalibrator.calibratedSize(forUnified:target:)` is pure/deterministic/Sendable, safe from the `@MainActor` host body.
- `.system → .sansSerif` valid against Readium 3.9.0; right tradeoff under `publisherStyles=false`.
- WI-5 wrapper still maps default 18pt → 1.0.
- Photo/custom-bg is a documented cosmetic parity gap behind the dark flag; no crash/data risk.

## Verdict

**ship-as-is.** Two audit rounds, zero open Critical/High/Medium. Test gate green:
62 tests / 4 suites (theme→base+colors, fontSize multiplier incl. min/max + the
calibrated-input regression, lineHeight, fontFamily incl. `.system→.sansSerif`,
publisherStyles, scroll, determinism).

## Known Phase-1 limitation carried forward

`.photo` / `useCustomBackground` renders as an opaque theme color under the
Readium engine (no decorative-image compositing). Tracked for WI-13 acceptance
and gates the WI-14 default-ON flip. Not a shipped regression (flag default OFF).
