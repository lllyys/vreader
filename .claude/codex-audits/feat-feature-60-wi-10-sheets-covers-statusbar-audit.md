---
branch: feat/feature-60-wi-10-sheets-covers-statusbar
threadId: 019e30aa-1011-7b20-86d0-1d56e537f58c
rounds: 2
final_verdict: follow-up-recommended
date: 2026-05-16
---

# Codex Gate 4 audit — feature #60 WI-10 (sheet re-skins + generative covers + status-bar tinting)

Independent implementation audit (Codex MCP, `read-only` sandbox,
`model_reasoning_effort: high`) of the WI-10 diff — the FINAL work item
of feature #60 (visual identity v2). WI-10 ships three things:

- **A.** Re-skin the 5 app sheets to a reusable `ReaderSheetChrome`
  component matching the committed design `dev-docs/designs/
  vreader-fidelity-v1/project/vreader-panels.jsx` (`Sheet` wrapper).
- **B.** A generative book-cover fallback (`GenerativeCoverView` +
  `GenerativeCoverStyle`) wired into `BookCoverArtView`'s no-image path.
- **C.** Status-bar tinting via `ReaderThemeV2.preferredColorScheme`.

## Round 1 — findings

0 Critical, 1 High, 3 Medium, 2 Low.

- **High — `AnnotationsPanelView` 4-tab unified sheet not depicted in
  the design.** The design has separate `TOCSheet` + `HighlightsSheet`;
  the app implements them as one unified 4-tab sheet. **Resolution:**
  the unified 4-tab IA *predates feature #60* — WI-10 re-skinned its
  chrome only (re-skinning an existing surface, not inventing UI).
  Filed **GH #793** (`needs-design`) to track splitting it into the
  design's two separate sheets as a follow-up IA work item.
  `docs/architecture.md` now states it is a pre-#60 surface re-skinned
  chrome-only with the split tracked in #793. Codex round 2 accepted
  tracking-via-issue (the WI-6c precedent) as a non-blocking
  resolution.
- **Medium — App Settings `sectionsForTesting` was misleading.** It
  claimed the design's 4 groups while the real UI renders the
  feature-#50 `AISettingsSection` composite's 3 sub-sections.
  **Fixed** — `SettingsView.sectionsForTesting` now returns only the 3
  groups it declares directly (`Cloud & Sync / Reading / About`); the
  "AI" group is delegated to the established `AISettingsSection`
  (re-shaping that feature-#50 component is out of WI-10 scope).
  `SheetSectionContract` documents the delegation; the composition
  test asserts the 3 declared groups + that each is a design-contract
  group.
- **Medium — generative covers off-spec.** Author/footer text used the
  system font instead of the design's Source Serif 4 / Inter pairings;
  the editorial style invented a surname-as-footer where the design
  draws `book.year`; the animal style used a literal `pawprint.fill`.
  **Fixed** — author/footer text routes through `ReaderTypography` with
  the design's per-style families; the editorial year footer is
  *omitted* (`LibraryBookItem` carries no year — no invented
  substitute); the animal glyph is a neutral abstract diamond mark
  inside the design's framed box (the design's specific animal SVG is
  not a reusable asset).
- **Medium — `ReaderSheetChrome` dropped the design `Sheet`'s default
  close button.** The design auto-renders a circular close button when
  no custom trailing slot is given. **Fixed** — `ReaderSheetChrome`
  takes an optional `onClose`; when set with no custom `trailing`, it
  renders the design's default circular close button. The Display
  sheet passes `onClose: { dismiss() }`.
- **Low — dead params in `BookCoverArtView`.** `coverColor` /
  `formatIcon` / `formatBadge` are unused after the generative
  fallback. **Fixed** — removed from `BookCoverArtView` + the now-dead
  computed props in the 3 callers (`formatColor` kept in `BookRowView`
  — still used by the feature-#47 file-state chip).
- **Low — file sizes over the ~300-line guideline.** **Partially
  fixed** — `AIReaderPanelHeader.swift` extracted from `AIReaderPanel`
  (now ~315); `GenerativeCoverMetrics.swift` extracted from
  `GenerativeCoverView` (now 291). `AnnotationsPanelView` (~330) and
  `ReaderSettingsPanel` (~737) **accepted with rationale**: splitting
  `AnnotationsPanelView` forces loosening `private` on several `@State`
  props (an access-level code-smell); `ReaderSettingsPanel` is a
  pre-#60 ~708-line file and WI-10 added only the ~29-line chrome
  wrapper — splitting it is a large out-of-scope drive-by refactor.

Round 1 also confirmed clean: the deterministic `fingerprintKey →
style/palette` policy (FNV-1a), `ReaderThemeV2.preferredColorScheme`,
the retained feature-#50 `AIProviderPicker` (preserves a shipped
control — not invented UI), and the inner `NavigationStack` in App
Settings (required for `NavigationLink` push). No Swift 6
actor-isolation or retain-cycle problem found.

## Round 2 — re-verification

Codex re-audited the complete `9e6e8a2..7f370ed` post-fix delta:
**zero new Critical / High / Medium findings.** All Round-1 fixes
confirmed present on disk — the default close button, the honest App
Settings section contract, the generative-cover typography +
omitted-footer + abstract-mark fixes, the removed dead params, and the
status-bar tinting wiring. The GH #793 follow-up is accepted as
post-merge design debt, not a blocker.

## Resolution summary

1 High + 3 Medium + 2 Low from round 1: the 3 Medium + the 2 Low were
**fixed in-branch** before the round-2 verdict; the 1 High is
**resolved via tracking** — GH #793 (`needs-design`) for splitting the
pre-#60 unified annotations sheet to match the design's separate
TOC/Highlights sheets. No accepted-with-rationale Medium/High remains
open; the only accepted-with-rationale items are the two Low file-size
findings (`AnnotationsPanelView`, `ReaderSettingsPanel`).

## Final verdict

**follow-up-recommended.** Codex round 2 returned zero new findings and
approves the Gate 4 audit for the shipped WI-10 scope. The
implementation has no blocker; the single follow-up — splitting the
unified annotations sheet to the design's two-sheet IA — is filed as
GH #793.
