---
branch: fix/issue-743-uieditmenu-coord-space
threadId: 019e2d96-8bbd-7340-9b0c-6b37d4501cd7
rounds: 2
final_verdict: ship-as-is
date: 2026-05-16
---

# Codex Gate 4 implementation audit — Bug #203 / GH #743 (UIEditMenuConfiguration coord-space mismatch)

Per `.claude/rules/47-feature-workflow.md` Gate 4. Audit of the TXT producer
coordinate-space fix that closes Feature #53 acceptance criterion (a) for
TXT: tapping a highlighted word now shows the inline edit/delete menu at
the correct anchor instead of off-screen.

## Scope

Branch: `fix/issue-743-uieditmenu-coord-space`

### Production source (2 files)

- `vreader/Views/Reader/TXTTextViewBridgeCoordinator.swift` — drop
  `textView.convert(viewRect, to: nil)`, return `viewRect` (textView-local).
  Presenter view = the textView; `UIEditMenuConfiguration.sourcePoint`
  expects interaction-view coords.
- `vreader/Views/Reader/TXTChunkedReaderBridge.swift`:
  - Pure-point overload now returns textView-local.
  - Gesture-based wrapper converts textView-local → tableView-local via
    `textView.convert(event.sourceRect, to: tableView)` before returning;
    presenter view = the tableView.

### Contract documentation (2 files)

- `vreader/Views/Reader/ReaderNotifications.swift` — rewrote the
  doc-comment on `.readerHighlightTapped` + `ReaderHighlightTapEvent.sourceRect`
  with a per-bridge coord-space table (TXT non-chunked / TXT chunked /
  EPUB / PDF / Foliate). Pre-fix, the comment said "screen-space" which is
  now stale.
- `vreader/Views/Reader/HighlightActionPresenter.swift` — rewrote the file
  header to cite the new contract + explicitly state the presenter does
  NOT normalize coordinates.

### Tests (2 files)

- `vreaderTests/Views/Reader/TXTBridgeHighlightTapTests.swift` — added
  `resolveHighlightTap_returnsViewLocalRect_notWindowSpace`. Embeds the
  textView in a UIWindow at offset (50, 100); asserts
  `event.sourceRect.origin.x < 50` and `.y < 100`. Pre-fix, the rect
  origin would be ≥ those values (window-space).
- `vreaderTests/Views/Reader/TXTChunkedBridgeHighlightTapTests.swift` —
  added `resolveChunkedHighlightTap_pureOverload_returnsViewLocalRect_notWindowSpace`
  with the same shape, pinning the pure-point overload's contract.

## Round 1 findings

Zero Critical / High / Medium. Three Lows.

| # | file:line | severity | issue | resolution |
|---|---|---|---|---|
| 1 | `vreader/Views/Reader/ReaderNotifications.swift:59` + `:115` | Low | Doc-comments still said `sourceRect` is "screen-space" — now stale. The shared contract is the easiest place for a future producer to reintroduce the bug. | **Reworded** both comments. New language: rect is in the coordinate space of the same `UIView` the bridge later passes to `present(for:in:)`. Per-bridge table added. |
| 2 | `vreader/Views/Reader/HighlightActionPresenter.swift:3` | Low | File header said bridges post a "screen-space rect", while the protocol doc at lines 31-33 correctly requires view-local. File internally inconsistent. | **Reworded** the header. Now cites the contract on `ReaderHighlightTapEvent.sourceRect` + states explicitly that the presenter does not normalize coordinates. |
| 3 | `vreaderTests/Views/Reader/TXTChunkedBridgeHighlightTapTests.swift:219` | Low | The new regression test pins the pure-point overload only; the gesture/tableView wrapper at `TXTChunkedReaderBridge.swift:403` is not directly tested. | **Accepted with rationale**. The wrapper logic is one extra `textView.convert(event.sourceRect, to: tableView)` call against UIKit framework code (40+ years of UIView shipping). Building a UITableView + ChunkedTextCell + tap-gesture-recognizer fixture for one line of conversion code would be testing UIKit, not vreader. Pure-point overload IS pinned; doc-comments at the wrapper now make the boundary explicit. |

## Round 2 verification

Codex final verdict (quoted from thread `019e2d96-8bbd-7340-9b0c-6b37d4501cd7`):

> Gate 4 verdict: ship.
>
> Round 2 resolved the two documentation findings. The shared contract is
> now explicit and internally consistent in `ReaderNotifications.swift:56`
> and `HighlightActionPresenter.swift:1`, and it matches the actual
> producer behavior across TXT, chunked TXT, EPUB, PDF, and Foliate.
>
> I accept the remaining test gap rationale for the chunked gesture
> wrapper. The wrapper logic at `TXTChunkedReaderBridge.swift:403` is a
> thin adapter around the already-pinned pure helper plus a single UIKit
> `convert(_:to:)` call, and the added contract docs make that boundary
> clear. No open Critical/High/Medium findings remain.

## Test gate

```
xcodebuild test -only-testing:vreaderTests/TXTBridgeHighlightTapTests \
                -only-testing:vreaderTests/TXTChunkedBridgeHighlightTapTests \
                -only-testing:vreaderTests/TXTBridgeHighlightTapSubscriberTests \
                -only-testing:vreaderTests/HighlightActionPresenterTests
```

Result: 16 tests in 3 suites + the presenter tests, all passing. ** TEST
SUCCEEDED **

Broader `vreaderTests` suite shows only the pre-existing failures (Bug
#200 BookFormatAZW3Tests + BookSourceHTTPClient + ReplacementTransform —
none introduced by this diff).

## Cross-checks performed by Codex

- Coordinate-space consistency across all 5 producers: TXT non-chunked
  textView-local, TXT chunked tableView-local, EPUB webView-local, PDF
  pdfView-local, Foliate `.zero` (known follow-up). All match the views
  passed to `present(for:in:)`.
- The new regression tests genuinely catch the old bug by construction:
  the pre-fix code explicitly called `convert(_, to: nil)`, so embedding
  the view at offset (50, 100) made those assertions fail before the fix.
- Degradation: when the textView is not in a window (test fixtures), the
  new code returns view-local coords without depending on window
  conversion — no NaN / zero / degenerate output.

## Summary verdict

**Ship-as-is.** Gate 4 clean after 2 rounds. Closes Feature #53 acceptance
criterion (a) for TXT minimum and pins the cross-bridge coordinate-space
contract so future producers don't re-introduce the same bug. PDF + EPUB
checked clean; Foliate stays at `.zero` as a separately-tracked follow-up.
