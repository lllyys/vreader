---
branch: fix/issue-1301-epub-paged-within-chapter-resume
threadId: codex-exec-readonly
rounds: 2
final_verdict: ship-as-is
date: 2026-05-31
---

# Codex audit — Bug #293 / GH #1301 (EPUB paged within-chapter resume)

Read-only `codex exec` audit, 2 rounds.

## Fix summary

- Root cause: the paged load-finished branch called `setupPagination` but
  never consumed `pendingScrollFraction` (only the scroll-mode branch did);
  `setupPagination` navigated only to `pendingPaginationPage` (nil on a fresh
  open → page 0). Chapter-resume worked, within-chapter page-resume didn't.
- Fix: (1) new pure inverse seam `EPUBPagedProgress.pageForFraction(_:totalPages:)`
  (zero-based, `round(clamp(fraction)*(totalPages-1))`, guards `totalPages<=1`
  and non-finite input); (2) `setupPagination` computes the resume page from
  the restore fraction and hands it to the container via a widened
  `onPaginationReady(totalPages, resumePage)` callback; (3) the container syncs
  `pageNavigator`/`currentPaginationPage` from the resume page — which drives
  the JS nav through the proven `updateUIView` path — so the Swift page state
  is not stale.

## Files

- `vreader/Views/Reader/EPUBPagedProgress.swift` (new `pageForFraction`)
- `vreader/Views/Reader/EPUBWebViewBridgeCoordinator.swift` (`setupPagination`, callback signature)
- `vreader/Views/Reader/EPUBWebViewBridge.swift` (callback signature)
- `vreader/Views/Reader/EPUBReaderContainerView.swift` (`onPaginationReady` consumer)
- `vreaderTests/Views/Reader/EPUBPagedProgressTests.swift` (pageForFraction suite + round-trip + NaN)

## Round 1 findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| EPUBWebViewBridgeCoordinator.swift:625 | High | JS-only nav left `pageNavigator.currentPage` / `currentPaginationPage` stale → next side-tap pages from 0. | Fixed — resume page routed through `onPaginationReady` so the container syncs both Swift page states + `recordPagedProgress`; coordinator no longer JS-navs the fraction path. |
| EPUBPagedProgress.swift:67 | Low | `pageForFraction` could carry `NaN` through `Int(...rounded())` and trap. | Fixed — `guard fraction.isFinite`; added non-finite test. |

## Round 2

No findings. Codex confirmed: Swift page state in sync after resume; exactly one
JS nav (via `updateUIView`); no harmful race (explicit-page path passes
`resumePage == nil`); backward chapter-wrap still wins over fraction resume; no
Rule 51 / concurrency issue.

## Verdict

ship-as-is. Tests: `EPUBPagedProgressTests` 19/19 green (intra-chapter +
pageForFraction round-trip + whole-book composition + NaN). No visible chrome.
The end-to-end resume (reopen lands on the saved page) is device-verified
against a real EPUB at the close gate.
