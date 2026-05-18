---
branch: feat/feature-66-reader-settings-subcontrol-reskin
threadId: 019e3ad3-ee9a-7840-be46-34938f35af59
rounds: 2
final_verdict: ship-as-is
date: 2026-05-18
---

# Codex Gate-4 audit — Feature #66 (Reader Settings sub-control re-skin)

Implementation audit per `.claude/rules/47-feature-workflow.md` Gate 4.
Independent auditor: Codex MCP (`gpt-5.2-codex`), read-only sandbox.
Audited the full feature diff (`git diff origin/main..HEAD`, pbxproj
excluded as mechanical xcodegen output).

## Scope audited

- WI-1 — `vreader/Views/Reader/Settings/SettingsSliderRow.swift` (new):
  custom accent-track slider replacing the native `Slider` in
  `ReaderSettingsPanel`'s font-size + line-spacing sections.
- WI-2 — `vreader/Views/Reader/Settings/TypefacePillToggle.swift` (new):
  custom typeface-preview pill toggle replacing the native segmented
  `Picker` in the font-family section.
- `vreader/Views/Reader/ReaderSettingsPanel.swift` — the three section
  swaps.
- `vreaderTests/Views/Reader/Settings/SettingsSliderRowTests.swift`,
  `vreaderTests/Views/Reader/Settings/TypefacePillToggleTests.swift`.

Audit dimensions (rule 47 Gate 4): correctness vs plan, edge cases,
security, duplicate/dead code, VReader compliance, bridge safety,
accessibility, SwiftUI correctness.

## Round 1

2 findings — 1 Medium, 1 Low. Verdict: `block-recommended`.

### Medium — `SettingsSliderRow`'s 44 pt hit target was not real

`SettingsSliderRow.swift` advertised a 44 pt minimum touch target via
the container's `.frame(minHeight: 44)`, but the drag gesture +
`contentShape` were attached only to the 24 pt-tall `track` subview.
The vertical padding and the leading/trailing glyph columns were dead
zones — a tap in much of the visible row did nothing, a direct-touch
usability regression versus the native `Slider` it replaced.
`.accessibilityRepresentation` fixes assistive-tech semantics but not
the physical target for sighted users.

**Resolution** (commit `fix(#66): Gate-4 round-1 — full-row hit target
for SettingsSliderRow`):

- The body now uses a single outer `GeometryReader`; the
  `DragGesture(minimumDistance: 0)` is attached to the outer padded
  container with `.contentShape(Rectangle())` — the whole row is
  interactive.
- New pure helper `SettingsSliderRow.trackFraction(forRowX:rowWidth:)`
  maps a full-row x-position into the track's logical 0...1 fraction,
  accounting for the layout constants (`horizontalPadding` 14,
  `leadingGlyphWidth` 24, `trailingGlyphWidth` 28, `columnSpacing` 12).
  A touch in a glyph zone clamps to the nearest track edge.
- The row has a definite `rowHeight` (48 pt = 24 pt track + 2×12 pt
  padding) so the body's `GeometryReader` lays out inside a `List` row
  (a bare `GeometryReader` collapses).
- `track(rowWidth:)` is now purely visual (no gesture); it takes the
  remaining width via `.frame(maxWidth: .infinity)`, the same width
  the gesture math assumes — so the thumb the user sees sits where
  their finger maps to.
- 6 new tests cover the full-row geometry (`trackWidth`,
  `trackOriginX`, `trackFraction` edge/midpoint/glyph-zone mapping,
  end-to-end row-touch → quantized-value).

### Low — `ReaderSettingsPanel.swift` not net-reduced

The plan's risk-4 exit check is "WI-1/2 must net-reduce" the oversized
panel; post-WI-2 the file was 847 lines vs the 843-line baseline.

**Resolution**: the three feature-#66 section doc comments were trimmed
to a concise rationale + design pointer (rule-22 information preserved);
`ReaderSettingsPanel.swift` is now 842 lines — a genuine net reduction.

### Round-1 clean dimensions

Correctness vs plan (scope honored — no brightness/margins control
added, the font pill preserves the existing 3-option set rather than
collapsing to the design's 2), edge-case math (min/max clamping,
degenerate range, step quantization, over-drag — all unit-tested),
security (no JS/WebView/unsafe-interpolation surface), duplicate/dead
code (none), VReader compliance (new files < 300 lines, no Swift 6
actor-isolation / Sendable issue), bridge safety (no reader bridge
touched), accessibility semantics (`.accessibilityRepresentation
{ Slider / Picker }` — correct pattern), SwiftUI binding /
live-preview / list-row styling.

## Round 2

Verification of the round-1 fixes. **No findings.** Verdict:
`ship-as-is`.

Codex confirmed:

- The Medium is genuinely resolved — the gesture is on the full padded
  row with `.contentShape(Rectangle())`; the whole 48 pt row is
  interactive.
- The `trackFraction(forRowX:rowWidth:)` geometry is internally
  consistent (`trackOriginX` = 14 + 24 + 12 = 50; `trackWidth`
  subtracts both paddings, both glyph columns, both gaps; glyph-zone
  touches clamp to 0...1).
- Visual/logical alignment holds — the track view receives the same
  effective width the gesture math assumes (fixed-width glyph columns
  + fixed padding/spacing, track takes the remainder via
  `.frame(maxWidth: .infinity)`).
- No regression from the fix — definite 48 pt `GeometryReader` height,
  continuous live updates preserved, no new concurrency issue.
- The Low is resolved — panel at 842 lines, trimmed comments still
  carry the design/scope rationale.

## Gate 4 outcome

2 rounds (within the rule-47 cap of 3). Zero open Critical/High/Medium
findings. **Final verdict: ship-as-is.**

## Verification note — environment recovery

During the audit-fix cycle the implementation was relocated from the
main repo checkout (where concurrent feature-#61 work had left
uncommitted `LibraryView.swift` / `CoverPickCoordinator.swift` state
that broke the build) into the designated isolated worktree
`agent-a115b7d47ec2d5d3d`. The WI-1 / WI-2 commits (`d47720f`,
`375af0e`) were intact in the object store, correctly stacked on the
current `origin/main` (`a7fb5ea`); the `feat/feature-66-...` branch ref
was re-pointed to `375af0e` and checked out in the clean worktree, and
the Gate-4 round-1 fix re-applied and committed there. The final
3-commit feature diff touches only feature-#66 surface-area files —
no feature-#61 contamination. All 32 feature-#66 tests pass under
`xcodebuild test` on the iPhone 17 simulator.
