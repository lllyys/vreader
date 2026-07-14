---
branch: feat/137-wi6a-paged-body
threadId: 019f615b-df0e-76f3-961c-7fdd5eadfa6b
rounds: 3
final_verdict: follow-up-recommended
date: 2026-07-15
---

# Codex Audit Log — Feature #137 WI-6a (Android paged TXT/MD renderer wiring)

Wire the WI-4 paginator + WI-5 navigator into the TXT/MD host: a real Compose
`LineMeasurer`, a new `TxtPagedBody` (HorizontalPager over `TxtPageIndex`, lazy
`renderPage`, off-main cancellable phase-1 pagination + load state, page-start
save/restore, reflow reconciliation), the `TxtReaderActivity` body branch
(`layout==Paged && !bilingual` → paged, else the extracted scroll `TxtBody`),
and the `TxtBody` extraction into `TxtReaderBody.kt`.

## Scope of audit

Codex (gpt-5.5 / high, read-only sandbox) audited the WI-6a diff:
- `android/app/src/main/kotlin/com/vreader/app/reader/paged/ComposeLineMeasurer.kt` (new — the production `LineMeasurer` over Compose `TextMeasurer`/`TextLayoutResult` line metrics)
- `android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderBody.kt` (new — `TxtPagedBody` + the extracted scroll `TxtBody` + `PagedRenderCache` + `TxtScrollFallback`)
- `android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt` (body branch + navigator/paginator/renderCache wiring + page-start save/restore + mode-aware chrome + test seams; `TxtBody` removed/extracted)
- `android/app/src/androidTest/kotlin/com/vreader/app/reader/TxtPagedBodyConnectedTest.kt` (the connected RED→GREEN driver)

Connected gate: `TxtPagedBodyConnectedTest` **6/6 GREEN** on `emulator-5554`
(`RUN-ANDROID-TESTS RESULT: SUCCEEDED`) — re-run after every audit-driven change.

## Round 1 (session 019f614b-375c-7661-a1e7-4b66b984fa17) — block-recommended

- **High** — phase-1 measured with the raw `textStyle` but phase-2 rendered with
  `LocalTextStyle.current.merge(textStyle)`; `bodyTextStyle()` leaves layout-affecting
  fields (letterSpacing) unset, so measured line breaks could diverge from rendered
  ones (non-deterministic pagination). **Fixed**: compute `effectiveStyle =
  LocalTextStyle.current.merge(textStyle)` ONCE and use it for BOTH the
  `paginator.index()` measure and the page `Text` render.
- **High** — paged mode left TTS / in-book search / scrubber / bookmark-jump chrome
  driving the hidden scroll `LazyListState` (dead controls). **Fixed**: hoisted
  `usePaged` above the chrome; a mode-aware `jumpToOffset` routes bookmark / annotation
  / search / scrubber jumps to the PAGER (via `pagedNavigator.pageContaining` +
  `pagedJumpRequest`) in paged mode; the read-aloud/TTS entry is disabled in paged
  mode; the progress fraction reads `pagedOffset` in paged mode.
- **Medium** — a superseded phase-1 pass was not token-cancelled (coroutine-cancel
  alone doesn't stop `TxtPaginator`'s tight CPU loop, which only aborts at
  `checkCancelled(token)`). **Fixed**: the in-flight `PaginationToken` is held in a
  `remember` and the prior one is `cancel()`ed before each new pass.
- **Low** — a transient stale save on reflow. **Reduced**: the settled-page save is
  suppressed while `localScrollTarget != null`.

## Round 2 (session 019f6156-3ab6-75c2-9dfb-e6329d80ee8f) — block-recommended

Confirmed the R1 style-mismatch, token-cancellation, and most chrome-routing fixes.
One **High remained**: the top-bar bookmark toggle/presence still derived `liveOffset`
from `listState.firstVisibleItemIndex` → bookmarked the WRONG position in paged mode.
Two narrow **Low**s (localScrollTarget cleared before scroll settled; a pre-index jump
collapsing to page 0). **Fixed all three**: moved `liveOffset`/`liveCanonical`/
`isBookmarked` below the hoisted `usePaged` and made `liveOffset` mode-aware
(`pagedOffset.value` in paged mode); clear `localScrollTarget` AFTER `scrollToPage`
settles + save the reconciled offset; `jumpToOffset` skips the paged jump while
`pagedNavigator.index == null`.

## Round 3 (session 019f615b-df0e-76f3-961c-7fdd5eadfa6b) — follow-up-recommended

Confirmed the R2 High resolved (bookmark toggle/presence uses `pagedOffset` in paged
mode; the `liveOffset` block move broke no earlier user — its only uses are in the
chrome call below it), and both R2 Lows resolved/reduced. One narrow new **Low**
remains, accepted as a follow-up (below). **No Critical/High/Medium blockers.**

### Accepted Low (follow-up, not a blocker)

`TxtReaderBody.kt` reflow-scroll cleanup can, under RAPID consecutive reflows (two
settings changes while a `scrollToPage()` is still suspended/cancelled), let the older
collector clear `localScrollTarget` and save its stale offset. This is a rapid-repeat
settings-change edge, NOT a normal page-turn/reflow path; the only effect is a briefly
stale persisted position, which the next settle overwrites (the conflated writer is
latest-wins). Suggested follow-up: only clear/save if `localScrollTarget == t` after
the scroll attempt. Deferred — narrow, self-correcting, and outside the WI-6a core
contract (which the connected test proves green).

## Rule-47 audit cap

3 rounds used (the cap). Final verdict `follow-up-recommended` — a shippable verdict
(∈ {ship-as-is, follow-up-recommended}); the single residual item is Low, narrow, and
self-correcting, accepted with rationale per rule 47.
