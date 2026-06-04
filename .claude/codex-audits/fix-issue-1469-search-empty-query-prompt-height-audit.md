---
branch: fix/issue-1469-search-empty-query-prompt-height
threadId: 019e9024-ffcd-79e3-b97f-14de5c08fdf2
rounds: 1
final_verdict: ship-as-is
date: 2026-06-03
---

# Codex Audit — Bug #319 / GH #1469 (Search empty-query prompt height fill)

Phase-4 implementation audit (`/fix-issue`). Independent Codex runner via
`scripts/run-codex.sh -e high` (author/auditor separation, rule 48).

## Scope

Bug fix — the empty-query search sheet left a black void below the help text.
`SearchPromptView`'s outer frame lacked `maxHeight: .infinity`, so the VStack
sized to content height and `SearchView`'s `.background(theme.sheetSurfaceColor)`
covered only the top band; the rest showed the default black sheet background.
The sibling states (`SearchNoResultsView`, `loadingView`) already fill height.

- `vreader/Views/Search/SearchStateViews.swift` — `SearchPromptView` frame
  `.frame(maxWidth: .infinity, alignment: .leading)` → `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)`.
- `vreaderTests/Views/Search/SearchViewReskinTests.swift` — `promptFillsAvailableHeight()` (RED→GREEN via `UIHostingController.sizeThatFits`) + `import SwiftUI`.
- `docs/bugs.md` — added the Bug #319 row.

## Round 1 — verdict (threadId 019e9024-ffcd-79e3-b97f-14de5c08fdf2)

**No findings. ship-as-is.**

Codex confirmed:
- The fix is correct for the root cause — the cream `.background` is on the outer
  `VStack` in `SearchView`, so the prompt branch must consume the remaining height
  for the background to cover the sheet. `alignment: .topLeading` is the correct
  companion change (once the prompt fills height, plain `.leading` no longer
  defines vertical placement; `.topLeading` keeps content pinned where intended).
- The change is scoped to the `.prompt` content state; siblings already use the
  same fill-height pattern.
- The regression test is sound — `UIHostingController.sizeThatFits(in:)` is
  deterministic for this contract; the `>= 700` threshold has ample margin
  between pre-fix content height (≈100) and post-fix fill height (≈800); the suite
  is already `@MainActor`; `import SwiftUI` is required for `UIHostingController`.
- **Rule 51 satisfied** — restores the designed `SearchEmptyState` fill behavior
  (`vreader-search.jsx:120`), not new self-designed UI.

## Verdict

**ship-as-is.** Zero findings. RED→GREEN established (`SearchViewReskinTests` —
RED at content height pre-fix, GREEN ≈ fill height post-fix). Targeted suite green.
