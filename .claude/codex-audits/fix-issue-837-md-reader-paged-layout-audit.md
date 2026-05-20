---
branch: fix/issue-837-md-reader-paged-layout
threadId: 019e47a7-38eb-7a03-b175-def5e40f8df7
rounds: 2
final_verdict: follow-up-recommended
date: 2026-05-21
---

# Codex audit — Bug #215 / GH #837 — MD reader paged layout

**Branch**: `fix/issue-837-md-reader-paged-layout`
**Round-1 HEAD**: `986ca08c`
**Round-2 HEAD**: `fb528800`
**Round-3 HEAD**: see post-commit (this iteration applies the Round-2 Low #1 comment fix)
**Codex thread**: `019e47a7-38eb-7a03-b175-def5e40f8df7`

## Round 1 — verdict: needs-revision

Findings:

- **High #1** — paginator viewport != renderer interior. `updatePagination`
  received `proxy.size` (the GeometryReader's measured slot) but the rendered
  textView interior is smaller: the VStack reserves chrome-aware bottom
  padding, the page indicator (when chrome hidden) reserves its own row, and
  the paged textView's `textContainerInset = 16` on every side. Paginator
  packed more glyphs per page than the renderer could display.

- **High #2** — chrome-toggle didn't re-paginate. Tapping center flipped
  `isChromeVisible` but page boundaries stayed pinned to the pre-toggle
  viewport.

- **Medium** — Bug #218's selection-popover producer gap in MD paged mode
  is still unaddressed; the new comments overstate what works. Accepted as
  scope split from Bug #215.

- **Low #4** — chrome inset is a magic number (`128 + 8`) rather than a
  single source of truth from `ReaderBottomChrome`'s actual layout.
  Accepted as known fragility.

- **Low #5** — test coverage points at routing seams only; load-bearing UI
  contract (chrome-aware inset, indicator hide/show, chrome-toggle
  repagination, paginator/renderer box parity) was unguarded.

- **Low #6** — `MDReaderContainerView.swift` 526 LOC, over the 300-line
  budget. Pre-existing debt this PR makes slightly worse.

## Round 2 — verdict: follow-up-recommended

Round-1 High #1 fixed via `paginatorViewportSize(proxy:chromeVisible:)`
static helper that subtracts bottom-padding + indicator-when-hidden + 2×
textInset, plus `textContainer.lineFragmentPadding = 0` on the paged
textView for horizontal parity.

Round-1 High #2 fixed via `.onChange(of: isChromeVisible)` re-paginate
in `pagedReaderContent`.

Round-1 Low #5 addressed via new test suite
`MDReaderContainerViewPagedLayoutTests` (6 cases) locking both
formulas.

Round-1 Low #4 (chrome inset constant) and Low #6 (file size) remain as
documented debt — not blockers per Round-2 reading.

Remaining Round-2 Low findings:

- **Low #1** — comment drift: `.selectionPopoverPresenter` and
  `.unifiedHighlightPopoverPresenterIfAvailable` comments described MD as
  rendering "via the shared TXTTextViewBridge" but paged mode renders
  `NativeTextPagedView`. Fixed in Round-2-followup commit.

- **Low #2** — chrome inset still a magic constant. Carried over from
  Round-1; accepted as known debt.

- **Low #3** — file size 577 LOC (worsened from 526). Carried over from
  Round-1; refactor scope is its own PR (`MDReaderContainerView+Paged.swift`
  extraction, mirroring `+Bilingual.swift` precedent).

## Final disposition

**Verdict**: follow-up-recommended. No Critical/High/Medium open findings.
Three Low findings: (1) comment drift fixed inline; (2) chrome-inset
constant fragility — accepted, locked by test for now; (3) file-size debt —
accepted, deferred to a refactor PR.

The 3 named causes from the bug doc (mis-sized pages, chrome occlusion of
content + indicator, dead taps) are all addressed by this PR. Bug #218's
selection-popover facet remains an explicit scope split — documented in
the row body and in the updated comments.
