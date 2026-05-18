# Feature #66 — Reader Settings sub-control re-skin — implementation plan

- **Feature row**: `docs/features.md` #66 (TODO)
- **GH issue**: #824
- **Design source** (committed, rule 51 satisfied):
  `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx` —
  `SliderRow`, `ReaderSettingsSheet`.
- **Author**: feature-cron (Gate 1), 2026-05-18
- **Lineage**: v2 follow-on of feature #60 (VERIFIED).

## 1. Problem

`ReaderSettingsPanel.swift` got the v2 chrome + theme swatches (feature
#60 WI-11), but its typography sub-controls are still native iOS:
**font-size** and **line-spacing** are plain `Slider`s, and
**font-family** is a native segmented `Picker`. The committed design
(`vreader-panels.jsx`) specifies a custom accent-track `SliderRow`
(22 pt thumb, leading/trailing glyphs) and a typeface-preview pill
toggle. (Feature #60 acceptance item 7 — "Reader Settings sheet matches
design" — recorded `result: pass` at Gate 5b although the sub-controls
were never re-skinned; that overstatement is a verification-integrity
note for `/triage`, not in this feature's code scope.)

## 2. Scope correction (Gate-2 round-1) — read first

The v1 plan named controls that do not exist; round-1 audit corrected
the surface:

- **There is NO reader-brightness control** in `ReaderSettingsPanel` /
  `ReaderSettingsStore` / `TypographySettings`. The v1 "brightness"
  slider does not exist. The only non-typography slider in the panel is
  the conditional **background-opacity** slider (`store.backgroundOpacity`,
  `0.05...1` step `0.05`) in `themeBackgroundSection`.
- **There is NO margins control** anywhere — confirmed by audit. The
  design's margins `SliderRow` has no VReader counterpart; adding one
  would be a new capability, not a re-skin. Out of scope, definitively.

**Corrected scope**: re-skin exactly the two real typography sliders
(`fontSizeSection`, `lineSpacingSection`) with `SettingsSliderRow`, and
the `fontFamilySection` segmented `Picker` with `TypefacePillToggle`.
The `backgroundOpacity` slider **may** adopt `SettingsSliderRow` for
visual consistency (it is the same control class) but is a secondary,
optional adoption — flagged, not required, because it is non-typography
and conditionally shown.

**Font-family option-count discrepancy** (round-1 High finding 1): the
current `fontFamilySection` picker shows **3** options (`system`,
`serif`, `monospace`) while `ReaderFontFamily` has **5** persisted cases
(`+ sourceSerif4, inter`); the design depicts a **2**-option pill.
`TypefacePillToggle` re-skins **the existing control as-is** — it
presents exactly the option set the current picker presents (a faithful
re-skin, behavior-preserving). It does **not** reduce to the design's
2 options: a font-choice reduction is a behavior change (needs legacy-
value mapping + a persisted-value policy) and is **out of scope** — it
is recommended as a separate `IDEA` row ("Reader font-family set
rationalization — reconcile the 3-shown / 5-persisted / 2-designed
mismatch") for `/triage`.

## 3. Surface area

### New files

- `vreader/Views/Reader/Settings/SettingsSliderRow.swift` —
  `struct SettingsSliderRow: View`, the custom accent-track slider
  mirroring the design's `SliderRow`. **`CGFloat`-native** API (the
  real bindings are `CGFloat`, not `Double` — round-1 finding 3):
  `init(value: Binding<CGFloat>, range: ClosedRange<CGFloat>, step:
  CGFloat, leading: Glyph, trailing: Glyph, accessibilityLabel: String)`.
  22 pt thumb, accent-tinted track. **Accessibility** (round-1 finding
  4): backed by `.accessibilityRepresentation { Slider(...) }` so
  VoiceOver/assistive tech get genuine native slider semantics (label,
  value, adjustable action); 44 pt minimum hit target.
- `vreader/Views/Reader/Settings/TypefacePillToggle.swift` —
  `struct TypefacePillToggle: View`, a pill toggle presenting the
  **current** `fontFamilySection` option set (§2), each option rendered
  in its own typeface. `.accessibilityRepresentation` of a `Picker` for
  assistive-tech parity.

### Modified files

- `vreader/Views/Reader/ReaderSettingsPanel.swift` (843 lines today —
  already over the ~300 guideline). Replace the `fontSizeSection` and
  `lineSpacingSection` native `Slider`s with `SettingsSliderRow`
  (`store.typography.fontSize` / `lineSpacing`, ranges
  `TypographySettings.fontSizeRange` / `lineSpacingRange`), and the
  `fontFamilySection` `Picker` with `TypefacePillToggle`. Moving the
  controls into the new files also net-reduces this oversized file.

### Out of scope

- `autoPageTurnInterval` slider, `epubLayout` / `pageTurnAnimation`
  segmented pickers — not typography; audit confirmed exclusion correct.
- A new margins control (does not exist — §2).
- Reducing the font-family option set to the design's 2 (§2 — a
  behavior change, separate `IDEA` row).
- `ReaderSettingsStore` / `TypographySettings` — untouched; this is a
  pure control-skin swap binding the identical `CGFloat` properties.

## 4. Prior art / project precedent / rejected alternatives

- **Precedent — feature #60 theme swatches**: #60 WI-11 already replaced
  this panel's native theme picker with custom swatches; #66 extends
  that pattern to the remaining native controls.
- **Precedent — `ReaderSettingsStore`** (`@Observable @MainActor`,
  audit-confirmed): the new controls bind the identical properties.
- **Rejected — restyle native `Slider`/`Picker` in place**: SwiftUI
  exposes no accent-track / custom-thumb / glyph affordances.
- **Rejected — design's 2-option font pill**: not behavior-preserving
  (§2); re-skin the existing control instead.

## 5. Work-item sequencing

| WI | Title | Tier | PR size |
|----|-------|------|---------|
| WI-1 | `SettingsSliderRow` + swap font-size & line-spacing sliders | **behavioral** | medium |
| WI-2 | `TypefacePillToggle` + swap the font-family picker | **behavioral** (final WI) | small–medium |

- **WI-1** — build `SettingsSliderRow` (`CGFloat` API, accessibility
  representation); swap `fontSizeSection` + `lineSpacingSection`. RED:
  `SettingsSliderRowTests`. Behavioral, not final → `patch` per the
  `/feature-workflow` skill's Gate-3 step *3f. Version bump →
  "Bump tier (deterministic per WI)"* table
  (`.claude/skills/feature-workflow/SKILL.md`): foundational → `patch`,
  behavioral-but-not-final → `patch`, final WI → `minor`. This is the
  workflow's deterministic per-WI refinement of rule 40's general
  "feature → minor"; the audited #61 and #63 plans apply the same
  table.
- **WI-2** — build `TypefacePillToggle`; swap `fontFamilySection`;
  completes the re-skin. Final WI → `minor`.
- 2 WIs; both touch `ReaderSettingsPanel.swift`, so they land in
  sequence.

## 6. Test catalogue

- `vreaderTests/Views/Reader/Settings/SettingsSliderRowTests.swift`
  (WI-1): the `Binding<CGFloat>` round-trips against the real
  `TypographySettings.fontSizeRange` / `lineSpacingRange`; `step`
  quantization; min/max boundaries; the accessibility representation
  exposes label + value.
- `vreaderTests/Views/Reader/Settings/TypefacePillToggleTests.swift`
  (WI-2): selecting each option in the current `ReaderFontFamily` set
  updates the binding; the bound value pre-selects the matching pill.
- Existing `ReaderSettingsPanel` tests re-run as regression guards in
  both WI PRs (bindings + effects unchanged).
- Gate 5 — `Feature66ReaderSettingsControlsVerificationTests`: open
  Reader Settings → assert the custom slider rows + the typeface pill
  resolve, a change persists, and an **assistive-tech audit** pass over
  the custom controls. DebugBridge-drivable, CU-free.

## 7. Risks + mitigations

1. **Accessibility regression** (round-1 finding 4). Native
   `Slider`/`Picker` carry adjustable semantics for free.
   *Mitigation*: `SettingsSliderRow` / `TypefacePillToggle` are backed
   by `.accessibilityRepresentation { Slider/Picker }` so assistive
   tech sees genuine native semantics; 44 pt hit targets. Gate 5
   includes an explicit assistive-tech pass.
2. **Live preview** (round-1 finding 5). Font-size & line-spacing drag
   must update the reader live, as the native `Slider` does.
   *Mitigation*: `SettingsSliderRow` emits continuous `Binding` updates
   during drag — no debounce. (If `backgroundOpacity` later adopts the
   control, note it drives `ThemeBackgroundView` / EPUB photo-background
   surfaces, not just a preview — verified then, not here.)
3. **Theme-surface rendering** (round-1 finding 5). The custom track /
   thumb / pill must keep adequate contrast across every `ReaderThemeV2`
   sheet surface (light / sepia / dark / OLED / photo-background) and
   render correctly under Dynamic Type. *Mitigation*: WI-1/WI-2 tests +
   the Gate-5 pass cover all theme surfaces and large content sizes.
4. **`ReaderSettingsPanel.swift` file size.** Already 843 lines; WI-1/2
   must net-reduce it (controls move to new files) — an explicit WI
   exit check.

## 8. Backward compatibility

- No schema change, no migration, no persisted-state change. Pure
  view-layer control swap; `ReaderSettingsStore` / `TypographySettings`
  and all preference keys, ranges, effects, and the font-family option
  set are untouched. No older-client / older-backup impact.

## 9. Revision history / Gate-2 audit trail

| Version | Date | Change |
|---|---|---|
| v1 | 2026-05-18 | Initial draft (feature-cron, Gate 1). |
| v2 | 2026-05-18 | Gate-2 round-1 (Codex `019e39f9`): 6 findings applied — "brightness" control does not exist + no margins control; scope corrected to font-size + line-spacing sliders + font-family pill (High); the design's 2-option pill conflicts with the 3-shown/5-persisted `ReaderFontFamily` model — the pill re-skins the existing option set, font-set reduction carved out as a separate `IDEA` row (High); `SettingsSliderRow` API made `CGFloat`-native (Medium); accessibility mitigation strengthened to `.accessibilityRepresentation` (Medium); risks expanded to theme-surface contrast + Dynamic Type + the real `backgroundOpacity` control (Medium); WI-1 `patch` rationale (Medium). |
| v3 | 2026-05-18 | Gate-2 round-2 (Codex `019e39f9`): the sole remaining Medium — WI-1 bump-tier rationale mis-cited as "rule 47 §3f" — corrected to cite the real source, the `/feature-workflow` skill's Gate-3 §3f "Bump tier (deterministic per WI)" table. No design change. |

### Gate 2 — Independent plan audit

**Round 1** — Codex MCP, thread `019e39f9-9162-78b3-8e0b-b24a523d8876`,
2026-05-18. 2 High + 4 Medium — all applied in v2 (5 as fixes; finding
6 accepted-with-rationale: rule 47 §3f's per-WI bump table explicitly
assigns `patch` to a behavioral-but-not-final WI and `minor` to the
final WI — the same pattern the audited #61 and #63 plans use). Codex
confirmed `ReaderSettingsStore` is `@Observable @MainActor`, the named
`fontSizeSection` / `lineSpacingSection` / `fontFamilySection` controls
exist as native `Slider`/`Picker`, the out-of-scope exclusions are
correct, and the 2-WI split is sound once the font-family scope was
fixed.

**Round 2** — Codex MCP, same thread, 2026-05-18. v2 confirmed: all
round-1 control/model/accessibility/risk findings genuinely resolved.
**One Medium remained** — the WI-1 `patch` rationale cited a
non-existent "rule 47 §3f". Codex's offered resolution: "cite the
actual file/lines of a binding rule." Applied in **v3**: the per-WI
bump table is real but lives in the `/feature-workflow` skill's Gate-3
step 3f (`.claude/skills/feature-workflow/SKILL.md`), not `rule 47` —
the citation is corrected to the real source.

**Round 3** — Codex MCP, same thread, 2026-05-18. Verdict: **"Gate-2
clean. Zero open Critical/High/Medium findings."** Codex confirmed the
v3 citation is correct — the per-WI bump table at
`.claude/skills/feature-workflow/SKILL.md` (foundational → `patch`,
behavioral-but-not-final → `patch`, final WI → `minor`) supports WI-1's
`patch` and WI-2's `minor` exactly. No remaining findings.

**Gate 2 PASSED** (3 rounds — within the rule-47 cap). Zero open
Critical/High/Medium findings. Plan ready for Gate 3 (TDD
implementation), starting at WI-1.
