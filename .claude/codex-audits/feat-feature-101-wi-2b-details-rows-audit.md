---
branch: feat/feature-101-wi-2b-details-rows
threadId: 019eb5be-b346-75b0-a618-44aab62867bd
rounds: 2
final_verdict: ship-as-is
date: 2026-06-11
---

# Feature #101 WI-2b — Gate 4 implementation audit

Plan: `dev-docs/plans/20260611-feature-101-reading-time.md` (WI-2b: the
Book details Reading time group rendering the WI-2a model + the
`.readerSessionTimeDidChange` → `ReaderContainerView` live-session
mirror). Runner: `scripts/run-codex.sh` (codex exec, read-only).
Round-2 session: `019eb5c9-7b06-77b0-9be1-e0ef64685661`.

## Round 1 findings

| Finding | Severity | Resolution |
|---|---|---|
| `BookDetailsReadingTimeMirror.swift:60` — re-presenting Book details reused the previous `bookDetailsReadingStats` until the new fetch finished (stale totals flash; the "section omitted while in flight" contract broken on reopen) | Medium | **Fixed** — `readingStats = nil` cleared at present; r2 hardened this to the presentation TRIGGER (`handleMoreMenuAction` clears before flipping `showBookDetails`) so the sheet's first render is built from nil-cleared state. |
| `BookDetailsReadingTimeMirror.swift:63` — the `.onChange` fetch `Task` was untracked; an older fetch completing after a newer one (rapid close/reopen, book change) could overwrite state with stale stats | Medium | **Fixed** — `BookDetailsReadingTimeFetcher` (`@MainActor`, generation-stamped) through the new `BookReadingTimeStatsFetching` seam; `invalidate()` on book change. Regression tests `supersededFetchIsDropped` (out-of-order completions with delayed stub stores) + `invalidateDropsInFlightFetch`. |

Round 1 confirmed clean otherwise: notification keying, live-session
binding invalidation while the sheet is presented, concurrency
boundaries, file sizes.

## Round 2 (verify)

Fetcher fixes confirmed correct (generation stamping, `@State` fetcher
identity, `@MainActor` apply path, `Sendable` protocol boundary). One
residual: `.onChange(of: showBookDetails)` fires after the flip, so the
first presented render was not guaranteed to see the cleared state —
fixed exactly per the auditor's prescription by clearing at the
presentation trigger before the flip (commit "clear Reading time rows
at the presentation trigger").

## Verdict

ship-as-is. Tests: 23 green across the two touched suites (row
composition incl. in-flight/zero/dash states, mirror keying, fetcher
races) + WI-2a model/fetch suites unchanged. Device slice: Reading time
section renders live on iPhone 17 Pro sim ("28 sessions since Jun 10 /
10h total / This session <1m / Average session 22m") — artifact
`dev-docs/verification/artifacts/feature-101-wi2b-details-rows-20260611.png`.
