---
branch: fix/issue-489-epub-chapter-navigation
threadId: 019e47c8-fefd-7610-babd-8ad3951c6e46
rounds: 2
final_verdict: follow-up-recommended
date: 2026-05-21
---

# Codex Audit — Bug #165 / GH #489 (EPUB chapter navigation)

Branch: `fix/issue-489-epub-chapter-navigation`
Worktree: `.claude/worktrees/agent-abea36bef8b116a91`
Design source: `dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-navigation.md` §2.2 (paged-mode chapter wrap)

## Implementation summary

Side-tap in paged mode wraps across chapter boundaries per design §2.2:

| Position                       | Right tap                    | Left tap                       |
|--------------------------------|------------------------------|--------------------------------|
| Last page of chapter N (N<L)   | wrap to chapter N+1, page 0  | in-chapter previousPage        |
| First page of chapter N (N>0)  | in-chapter nextPage          | wrap to chapter N-1, last page |
| Last page of LAST chapter      | bounce (no-op)               | in-chapter previousPage        |
| First page of FIRST chapter    | in-chapter nextPage          | bounce (no-op)                 |

Production:
- `vreader/Views/Reader/EPUBChapterNavigationRouter.swift` — pure router (`decideNext`, `decidePrevious`).
- `vreader/Views/Reader/EPUBChapterWrapPendingTarget.swift` — @MainActor one-shot intent holder. `armWantsLastPage()` → set; `consume(totalPages:)` → resolve + clear; `clear()` / `cancelBecauseUnrelatedNavigationStarted()` → drop.
- `vreader/Views/Reader/EPUBReaderContainerView+ChapterWrap.swift` — `handleSideTapNext()` / `handleSideTapPrevious()` consume router decisions; `wrapForward()` / `wrapBackward()` mirror the chapter-load path (reset pagination, set contentURL).
- `vreader/Views/Reader/EPUBReaderContainerView.swift` — observers route through the new handlers; `onPaginationReady` callback consumes pending target; `.readerNavigateToLocator` cancels pending target.
- `vreader/Views/Reader/EPUBReaderContainerView+Navigation.swift` — `handleProgressSeek` cancels pending target.

Tests (all GREEN under `-only-testing:vreaderTests -parallel-testing-enabled NO`):
- `EPUBChapterNavigationRouterTests` (18 cases): middle, boundary-with-next, boundary-with-no-next (bounce), zero-pages, empty book, single-chapter book, stale spine indices (both directions, both extremes).
- `EPUBChapterWrapPendingTargetTests` (13 cases): lifecycle, one-shot semantics, zero/negative totalPages keep intent armed, dedicated `cancelBecauseUnrelatedNavigationStarted` entry point.

Full suite: 6986 tests, 695 suites, 0 failures.

## Scope deferral

Design §2.3 (continuous cross-chapter scroll: chapters render in one scrollable column, lazy-load ±1, hairline divider + heading, skeleton-pulse) is NOT implemented in this PR. It requires a multi-chapter WKWebView document architecture (today's bridge holds ONE chapter per loadFileURL). The bug row's primary symptom ("side-tap only toggles chrome") is the §2.2 path. §2.3 will be filed as a follow-up feature; the §2.2 "subtle horizontal nudge" bounce animation is left for follow-up too (design doesn't specify the animation curve).

## Audit rounds

### Round 1 — Codex thread `019e47c8`

Verdict: `fix-required`

Findings:

1. **High** — `chapterWrapPendingTarget` armed by `wrapBackward()` but never cleared from `.readerNavigateToLocator` (TOC / search) or `handleProgressSeek` (scrubber). Stale intent would force unrelated chapter navigations to land on last page.
   - Fix: added `chapterWrapPendingTarget.cancelBecauseUnrelatedNavigationStarted()` at both sites. Dedicated entry point (vs. `clear()`) for grep-precision in future audits.
2. **Medium** — Asymmetric stale-spine-index handling. `decideNext(currentSpineIndex: -1)` returned `.wrapToNextChapter`; `decidePrevious(currentSpineIndex: spineCount)` returned `.wrapToPreviousChapter`. Both must bounce.
   - Fix: added `0..<spineCount` guards in both `decideNext` and `decidePrevious` before applying the boundary truth table. Added two regression tests.

### Round 2 — Codex thread `019e47cd`

Verdict: `follow-up-recommended`

Findings:

- **Medium** — Container call-site coverage is by helper-contract tests only, not direct container exercises. A future edit that removes either `chapterWrapPendingTarget.cancelBecauseUnrelatedNavigationStarted()` call would not trip the new tests.
  - Accepted with rationale: the SwiftUI container is hard to drive in XCTest without a `ModelContainer` + viewmodel boot infrastructure. Attempting a source-text grep test (read source file from `Bundle.main`) failed because the simulator sandbox can't reach the host filesystem. The dedicated entry point name (`cancelBecauseUnrelatedNavigationStarted` — not generic `clear`) provides grep precision for future audits. Filed for follow-up: extracting a non-wrap-navigation dispatcher helper would make this directly unit-testable.

Round-2 also explicitly noted: "the production fix itself looks correct: clearing after `navigateToSpine` is still safely before any asynchronous chapter load can reach `onPaginationReady`, and the router's new `0..<spineCount` guards correctly collapse stale indices to bounce."

## Final verdict

Production correctness: confirmed correct by Codex round-2.
Test coverage: helper-contract tests catch type-level regression; container call-site coverage is acknowledged as a follow-up follow-up item, not a blocker.

**Verdict: follow-up-recommended.**

Ship-eligible per the bug fix workflow (Codex audit verdict ∈ {ship-as-is, follow-up-recommended}).
