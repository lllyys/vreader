---
branch: feat/feature-60-wi-7a-selection-popover-view
threadId: 019e2e53-7271-7971-bdb5-12eb60131236
rounds: 2
final_verdict: ship-as-is
date: 2026-05-16
---

# Codex Audit — Feature #60 WI-7a (SelectionPopoverView + action-row contract)

Scope: foundational `SelectionPopoverView` SwiftUI overlay +
`SelectionPopoverActionRow` enum (visible-action contract for the
new-selection popover). View body built per
`dev-docs/designs/vreader-fidelity-v1/project/vreader-reader.jsx:438-495`.
Legacy long-press UIMenu (`TXTBridgeShared.buildReaderEditMenu`) still
drives production — WI-7b replaces that path.

Files audited:
- `vreader/Views/Reader/SelectionPopoverActionRow.swift` (NEW, ~92 LOC)
- `vreader/Views/Reader/SelectionPopoverView.swift` (NEW, ~210 LOC)
- `vreaderTests/Views/Reader/SelectionPopoverActionRowTests.swift` (NEW, 8 tests)
- `docs/features.md` (row #60 plan v4 → v5 + WI-7a note)
- `dev-docs/plans/20260515-feature-60-visual-identity-v2.md` (revision history v5)

## Round 1 findings

| File:Line | Severity | Issue | Fix |
|---|---|---|---|
| `vreader/Views/Reader/SelectionPopoverView.swift:77-80,127-130` | Medium | Popover used `.system(..., design: .serif)` for the preview and plain `.system(...)` for action labels — missed Feature #60's typography contract (Source Serif 4 body + Inter chrome). Dormant in WI-7a but would surface visually incorrect once WI-7b wires the view in. | Route both fonts through `ReaderTypography.body(for: .sourceSerif4, size: 13)` (preview) and `ReaderTypography.body(for: .inter, size: 10.5)` (action labels), bridged to SwiftUI via `Font(UIFont)`. Inherits the existing WI-1 fallback chain (Source Serif 4 → Georgia → system serif; Inter → system sans) so the popover stays usable until WI-1b bundles the font binaries. |
| `vreader/Views/Reader/SelectionPopoverView.swift:58-59` | Low | Preview hidden only when `selectionText.isEmpty`. Whitespace/newline-only selections still rendered a quoted "empty" preview row. | Guard on `selectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty` so whitespace-only selections also collapse the preview. |
| `vreader/Views/Reader/SelectionPopoverView.swift:93-95` | Low | Color buttons used `30x30` swatches without an enlarged hit target, below the 36×36 accessibility minimum. | Wrap the visible `30x30` `Circle` in an outer `.frame(width: 36, height: 36)` with `.contentShape(Rectangle())` so the tap target meets the bar while the design's swatch dimensions stay intact. |

No production-path leak found. The legacy long-press flow still
goes through `TXTBridgeShared.buildReaderEditMenu` and the TXT
coordinators; the new popover types are not referenced from any
live path yet.

## Round 2 findings

No findings. Codex Round 2 verdict (verbatim):

> All three Round 1 issues are cleanly resolved... I do not see a
> new layout regression from the expanded hit area. The color row
> still uses HStack(spacing: 6), so the tappable frames are 36pt
> wide with 6pt spacing between frames; that preserves a real gap
> rather than causing the touch regions to butt together... WI-7a
> looks ready to ship.

## WI-7/7a/7b split judgement

Codex affirmed:

> The WI-7a/WI-7b split looks correct and appropriately isolates
> the no-regression foundation from the eventual UIMenu replacement.

## Summary

Ship-as-is. Foundational SelectionPopoverView + action-row contract
pinned by 8 contract tests + smoke build success. Typography routes
through `ReaderTypography` honoring WI-1's fallback chain. Color
buttons meet 36×36 hit-target minimum. Whitespace-only selections
collapse the preview row cleanly. WI-7b will replace the legacy
UIMenu path in a separate audited PR.
