---
branch: fix/issue-988-paged-side-tap-page-turn
threadId: 019e477e-9369-7010-a91b-6a2bd418d266
rounds: 1
final_verdict: follow-up-recommended
date: 2026-05-21
---

# Codex audit — Bug #239 / GH #988 — Paged-layout side-tap page-turn restoration

**Branch:** `fix/issue-988-paged-side-tap-page-turn`
**Base:** `main` @ `7d6b2f9e` (v3.38.32)
**Codex thread:** `019e477e-9369-7010-a91b-6a2bd418d266`
**Model:** default (read-only sandbox, approval policy never)
**Round 1:** **follow-up-recommended** — one Medium finding on pre-existing notification scoping, otherwise clean.

## Codex verdict

> "The core Bug #239 repro itself looks fixed. I traced TXT non-chunked/chunked, MD, PDF, EPUB, and Foliate tap paths to the new router; the EPUB `{x,w}` JS payload and legacy `'tap'` fallback are handled correctly, and the `pagedLayout` / `isPaged` snapshots are refreshed in both make/update paths so live paged↔scroll toggles should reroute the next tap without rebuilding recognizers."
>
> "I did not find a separate concurrency or JS-injection blocker. The Foliate observer lifecycle is acceptable with weak captures plus `deinit` removal, and the EPUB/Foliate JS additions serialize numbers only."

## Findings

### Medium — page-turn notifications still process-global and unscoped

`ReaderTapZoneRouter.swift:90` posts `.readerNextPage` / `.readerPreviousPage` with `object: nil`. The new Foliate observers consume those globals unfiltered in `FoliateSpikeView.swift:519`. The other reader containers also consume the same global notifications without book identity filtering in `TXTReaderContainerView.swift:564`, `MDReaderContainerView.swift:231`, `EPUBReaderContainerView.swift:249`, and `PDFReaderContainerView.swift:247`. In a multi-scene `WindowGroup` case, a side tap in one live reader can turn pages in another. PDF is the sharpest edge because it does not even guard paged mode before consuming the notification.

**Resolution: accepted as pre-existing debt, deferred to follow-up.**

Rationale:

1. **Pre-existing, not introduced by this fix.** The unscoped `.readerNextPage` / `.readerPreviousPage` contract has existed since feature #25 (commit `dddefef4`, the original tap-zone landing). The deleted `TapZoneDispatcher.dispatch` (pre-#54 producer) ALSO posted `object: nil` — the new `ReaderTapZoneRouter.dispatch` mirrors that contract byte-for-byte. The five consumer observers (TXT/MD/EPUB/PDF + the new Foliate ones in this PR) all predate Bug #239 in either form (the four format observers were left dangling after #54 deleted the producer; this PR re-arms them with no contract change).

2. **vreader is single-window today.** `vreader/SupportingFiles/Info.plist` has no `UIApplicationSupportsMultipleScenes` key (single-window default). The multi-scene `WindowGroup` failure mode Codex describes is hypothetical for the current build. The `WindowGroup` in `VReaderApp.swift:381` is structural — `Application_Main` doesn't allow multiple scenes without the Info.plist flag.

3. **The PDF "no paged-layout guard" sub-finding is moot under this fix.** PDF's `.readerNextPage` observer (line 247) doesn't gate on `isPaged`, but the new `ReaderTapZoneRouter` IS the gate — in `.scroll` layout the router posts `.readerContentTapped`, never `.readerNextPage`, so the unguarded observer is unreachable by the only producer that exists today. (If a future feature adds a NEW producer that bypasses the router, the PDF guard becomes load-bearing — but that future producer would also need to scope-by-key, so addressing both together is the right shape.)

4. **Same-format reader-instance race already covered by `deinit` ordering.** The FoliateSpikeView coordinator's observers are removed in `deinit` (the new `foliateNextPageToken` / `foliatePrevPageToken` teardown in the audited diff). UIKit dismantle order can briefly outlive the coordinator's deinit on iOS — and that's why this PR's tokens use `[weak self]` + `MainActor.assumeIsolated` + nonisolated(unsafe) storage matching the sibling `foliateRequestAnnotationJSDelete` / `foliateRequestBilingualEvalJS` observer pattern that's already production. No regression on that front.

5. **Scope discipline (rule 48 / 47-feature-workflow Gate 4).** Promoting this finding to "blocker" in Bug #239's scope would require parallel changes to all 5 consumer observers AND the producer payload AND any future producer for `.readerNextPage`. That's a feature-shaped refactor ("scope reader page-turn notifications by reader identity"), not a bug fix. Per rule 47, scope creep on a regression repair is itself a risk; the right move is to ship the regression fix and file the scoping work as its own row.

**Follow-up task to file** (separate bug, post-merge):

> Bug — page-turn notifications (`.readerNextPage` / `.readerPreviousPage` / `.readerContentTapped`) are unscoped by book identity; in a future multi-scene setup or if a stale reader teardown overlaps a new reader's mount, the wrong reader could consume the event. Scope the producer + consumers by `fingerprintKey` + `readerToken` (matching the `DebugReaderRegistry` precedent used for #142). PDF's `.readerNextPage` observer additionally lacks a paged-layout guard — gated implicitly by the router today, but should be defense-in-depth.

## Manual confirmation of audit non-findings

- **EPUB JS dict vs. string body**: `EPUBWebViewBridgeCoordinator.swift` parses `message.body as? [String: Any]` with `NSNumber` casts; falls back to the legacy `.readerContentTapped` post when the body isn't the dict shape. Confirmed.
- **EPUB JS injection safety**: the new JS body uses `e.clientX`, `document.documentElement.clientWidth`, `window.innerWidth` — pure number serialization, no user-controlled strings. WebKit's message channel auto-serializes the dict; no `evaluateJavaScript` interpolation here. Clean.
- **Foliate observer concurrency**: token storage is `nonisolated(unsafe)` per the sibling annotation-delete/create observer pattern; `deinit` removes both; `[weak self]` + `MainActor.assumeIsolated` in closures. Same posture as production-shipping observers since Bug #199 / #201.
- **TXT bridge `gesture.view == nil` fallback**: `TXTTextViewBridgeCoordinator.handleContentTap` casts `gesture.view as? UITextView` and falls back to `TXTBridgeShared.postContentTappedNotification()` (pre-fix unconditional behavior) if the cast fails. In real flow this happens when the gesture recognizer is being torn down mid-fire; chrome-toggle is the safe fallback.
- **VReader compliance**: `ReaderTapZoneRouter.swift` is 113 lines (<300 cap); Swift 6 strict concurrency compatible (`enum ReaderTapZoneRouter` is value-type, all static funcs); no `try?` swallowing; no `print()`.

## Test gate

```
xcodebuild test -only-testing:vreaderTests -parallel-testing-enabled NO -derivedDataPath build/issue-988
→ 6978 tests / 694 suites pass / 0 failures (~39s wall-clock)
```

## Verdict applied to this PR

**Round 1: follow-up-recommended → accepted, no code changes from this round.** The lone Medium finding is documented as pre-existing architectural debt with a concrete follow-up; the audit's positive verdict on correctness + concurrency + JS safety + edge cases stands. No additional Codex rounds were run — the finding was explicit ("the core Bug #239 repro itself looks fixed") and the scoping work is genuinely out of #239's scope.
