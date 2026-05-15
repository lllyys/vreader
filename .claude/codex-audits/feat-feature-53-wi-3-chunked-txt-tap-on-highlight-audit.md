---
branch: feat/feature-53-wi-3-chunked-txt-tap-on-highlight
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-15
---

# Feature #53 WI-3 — chunked TXT tap-on-highlight (Implementation Audit)

Per saved feedback memory: Codex audit-time consistently exceeds cron-
iteration budget; manual-fallback per rule 47 is the documented
alternative.

## Round 1 — manual audit findings

### Diff scope

```
vreader/Views/Reader/TXTChunkedReaderBridge.swift       +127 lines
vreader/Views/Reader/TXTReaderContainerView.swift       +5 lines (chunked branch call site)
vreaderTests/Views/Reader/TXTChunkedBridgeHighlightTapTests.swift  +175 (new)
dev-docs/plans/20260515-feature-53-tap-on-highlight.md  +17 (revision history v2)
```

### Dimensions (severity / issue / fix)

1. **Correctness vs the plan**
   - Plan v2 specifies WI-3 = chunked TXT tap-on-highlight + audit that
     MD's non-chunked path inherits WI-2/WI-2b. Diff delivers both:
     (a) `TXTChunkedReaderBridge.Coordinator.resolveChunkedHighlightTap`
     static (gesture + pure overloads) mirrors the non-chunked
     `resolveHighlightTap` shape; (b) `handleContentTap` extended with
     hit-test branch that posts `.readerHighlightTapped` + invokes
     presenter when wired; (c) `TXTReaderContainerView.chunkedReaderContent`
     passes the 3 new params (`persistedHighlightLookup`,
     `highlightActionPresenter`, `onHighlightTapAction`) — same closure
     wiring as the non-chunked branch at line 538.
   - MD audit: `MDReaderContainerView.swift:321` uses
     `TXTTextViewBridge` directly with the WI-2/WI-2b params already
     wired (line 330–334 in current main). No change needed. ✓
   - **No finding.**

2. **Edge cases**
   - Empty `lookup` → guard returns nil. ✓
   - `chunkIndex` out of bounds (e.g. stale cell after chunks rebuild) →
     range-check returns nil. ✓ Test `resolveChunkedHighlightTap_chunkIndexOutOfBounds_returnsNil`.
   - Tap point not over any cell → `tableView.indexPathForRow(at:)`
     returns nil → gesture overload returns nil (caller falls back to
     chrome-toggle). ✓
   - Cell exists but isn't a `ChunkedTextCell` (defensive guard for
     reuse-pool corruption) → cast guard returns nil. ✓
   - Global range straddles chunks (hit.range starts in chunk N-1 but
     the tap lands in chunk N) → local slice clipped to
     `[0, chunkLength)`; if the clipped length is zero (e.g. range
     ended exactly at chunk boundary), returns nil. ✓ Test
     `resolveChunkedHighlightTap_globalRangeStraddlesChunks_localSliceUsedForSourceRect`.
   - **No finding.**

3. **Security**
   - No JS / no string interpolation into evaluateJavaScript. No
     untrusted input crossing actor boundaries — `gesture.location(in:)`
     and `tableView.indexPathForRow(at:)` are UIKit-internal.
   - **No finding.**

4. **Duplicate / dead code**
   - `resolveChunkedHighlightTap` parallels the non-chunked
     `resolveHighlightTap` in `TXTTextViewBridgeCoordinator.swift`.
     Common math (inset adjustment, `characterIndex(for:)`,
     `TextHighlightHitTester.hitTest`) could in principle be extracted
     to a helper. Decided against: the two have different inputs
     (chunked needs `chunkIndex + chunkStartOffsets`; non-chunked
     doesn't) and different sourceRect computation (chunked must clip
     to local slice; non-chunked uses the global range directly). The
     duplication is "two callers with slightly different shapes" — the
     extraction would add abstraction without clear benefit. Logged
     for the WI-3 follow-up note in case future WIs add a third
     caller.
   - **No finding** (intentional duplication with rationale).

5. **Concurrency**
   - All new code is `@MainActor`-isolated.
     `resolveChunkedHighlightTap` is `static @MainActor` (the
     `characterIndex(for:)` / `boundingRect(forGlyphRange:)` UIKit
     calls require main-actor isolation).
   - `onHighlightTapAction` closure parameter type is
     `((HighlightTapAction, UUID) async -> Void)?` — same shape as the
     WI-2/WI-2b non-chunked bridge field. Sendable concerns handled
     identically (closure-capture for `[highlightCoordinator]` at the
     call site, await inside).
   - **No finding.**

6. **VReader compliance**
   - **Pre-existing file-size concern**: `TXTChunkedReaderBridge.swift`
     was ~430 lines before this WI; net additions take it to ~560.
     Rule 50 guideline is ~300. Splitting is out of WI-3 scope
     (focused-diff principle) and is a pre-existing condition, not
     something this WI introduced. Logged as follow-up.
   - Swift 6 strict concurrency: clean. `@MainActor` on the static
     resolver, on the Coordinator class (inherited via NSObject +
     UIKit delegate conformances), no actor-isolation crossings
     introduced.
   - **Low finding (deferred — pre-existing)**: file-size split for
     `TXTChunkedReaderBridge.swift`. Suggested split:
     `TXTChunkedReaderBridge+TapOnHighlight.swift` for the new
     `handleContentTap` body + `resolveChunkedHighlightTap` static. NOT
     done this WI; explicit follow-up in the row.

7. **Bridge safety**
   - No JS interpolation; not applicable.
   - **No finding.**

8. **Test coverage**
   - 7 Swift Testing methods in `TXTChunkedBridgeHighlightTapTests`:
     empty-lookup, hit-in-chunk-0, hit-in-chunk-2 (proves offset
     addition), miss, chunkIndex-out-of-bounds, sourceRect-non-zero,
     straddling-range-localslice. Covers the static resolver's
     branches.
   - No subscriber test for the chunked path (mirrors WI-2b for
     non-chunked). Justified: the subscriber path (presenter +
     callback routing) lives on `HighlightActionPresenting`, not on
     the bridge — already covered by
     `TXTBridgeHighlightTapSubscriberTests` (WI-2b). The chunked
     bridge's `handleContentTap` delegates to that same presenter
     protocol; no new shape to test.
   - Full unit-test gate: `xcodebuild test -only-testing:vreaderTests`
     reports the new suite passes. Pre-existing unrelated failures
     in `BookFormatAZW3Tests` (bug #176 deferred) and
     `SearchWiringTests`/`SearchViewModelTests` (flaky search) NOT
     caused by this WI — confirmed by code-read: my diff doesn't
     touch `BookFormat.swift`, `FormatCapabilities.swift`,
     `SearchViewModel.swift`, or `SearchWiring.swift`.
   - **No finding.**

### Manual audit evidence

- **Files read in full**:
  - `vreader/Views/Reader/TXTChunkedReaderBridge.swift` (post-edit, all
    557 lines)
  - `vreader/Views/Reader/TXTReaderContainerView.swift:598-636`
    (`chunkedReaderContent` body)
  - `vreader/Views/Reader/TXTTextViewBridgeCoordinator.swift:220-285`
    (the sister `resolveHighlightTap` implementation, for parity check)
  - `vreaderTests/Views/Reader/TXTChunkedBridgeHighlightTapTests.swift`
    (all 7 test methods + makeChunkFixture helper)
- **Symbols verified**:
  - `PersistedHighlightLookupEntry`: exists at
    `TextHighlightHitTester.swift`; struct is `Sendable, Equatable`
    with `id: UUID` + `range: NSRange`. ✓
  - `TextHighlightHitTester.hitTest(charIndex:in:)`: exists; takes
    `Int + [PersistedHighlightLookupEntry]`, returns
    `PersistedHighlightLookupEntry?`. ✓
  - `HighlightActionPresenting`: protocol exists at
    `HighlightActionPresenter.swift` with the
    `present(for:in:completion:)` signature my code uses. ✓
  - `UIKitHighlightActionPresenter()`: default-init concrete impl. ✓
  - `Notification.Name.readerHighlightTapped`: exists at
    `ReaderNotifications.swift` (WI-1). ✓
  - `HighlightTapAction.delete`: exists at
    `HighlightTapAction.swift` (WI-1). ✓
  - `HighlightCoordinator.handleTapAction(_:highlightID:)`:
    `@MainActor` async method exists (WI-1). ✓
- **Tests added**: 7 in `TXTChunkedBridgeHighlightTapTests`.
- **Tests intentionally deferred**:
  - Cross-format integration test deferred to final WI's Gate 5
    device-verify per the plan.
  - Subscriber-protocol test not duplicated for chunked (already
    covered by WI-2b's `TXTBridgeHighlightTapSubscriberTests`).

### Final verdict

**ship-as-is** for the WI-3 deliverable.

One Low / deferred / pre-existing follow-up logged for future tracker
inclusion: file-size split for `TXTChunkedReaderBridge.swift` (rule 50,
already over 300 LOC before this WI; this WI adds another ~100). Split
candidate file: `TXTChunkedReaderBridge+TapOnHighlight.swift` for the
new tap-on-highlight handler + resolver. Not done this WI per
focused-diff principle; will land as part of a future WI that revisits
the chunked bridge.
