---
branch: feat/feature-56-wi-8-more-menu-bilingual-row
threadId: 019e423e-657a-7e10-9c83-e95a2d33f1b1
rounds: 2
final_verdict: ship-as-is
date: 2026-05-20
---

# Feature #56 WI-8 — Codex Audit Log

Audit of the More-menu bilingual row + conditional re-translate row.
Audit dimensions covered: correctness against plan, edge cases,
security, duplicate / dead code, VReader compliance (Swift 6
concurrency, file-size, @MainActor), bridge safety, backward compat,
test design.

## Round 1 — initial audit (verdict: block-recommended)

Codex flagged 5 findings — 1 High, 2 Medium, 2 Low:

| File:line | Severity | Issue | Fix |
|---|---|---|---|
| `ReaderMorePopoverParts.swift:72` | High | `ReaderMoreMenuActionObservers` did not observe `.readerMoreBilingual` or `.readerMoreReTranslateChapter`; the rows posted notifications that never entered the host's action funnel. | Add `.onReceive` for the two new names; regression test pinning the inverse round-trip. |
| `ReaderMoreMenuRow.swift:109` | Medium | `dividerAnchor(in:)` could return a row absent from the visible set when a future filter hides both bilingual-cluster rows; the divider would silently vanish. | Return `ReaderMoreMenuRow?` with a defensive fallback through actually-present pre-divider rows. |
| `ReaderNotifications.swift:103` | Medium | Plan listed `.readerBookTranslationProgressDidChange` as part of WI-8's `ReaderNotifications.swift` changes; absent from the diff. | Add the notification name now so the contract is stable when WI-14 lands the producer/consumer. |
| `ReaderMoreMenuRow.swift:324` | Low | `BilingualRowState.on(targetLanguage: "")` rendered the literal "English ↔ " with trailing whitespace; no empty-target test. | Trim whitespace; fall back to a generic "On" label when empty. |
| `ReaderMorePopover.swift:298` | Low | `.none` and `.chevron` both rendered the same chevron — `TrailingControl.none` no longer meant "no trailing accessory" per its doc. | Either collapse semantics, or rename/document `.none`. |

## Round 1 fixes applied

1. **High — Observer funnel** — added `.onReceive(NotificationCenter.default.publisher(for: .readerMoreBilingual))` and `.onReceive(.readerMoreReTranslateChapter)` to `ReaderMoreMenuActionObservers`. The host's `handleMoreMenuAction` already includes the `.toggleBilingual` / `.presentReTranslatePicker` cases. New regression test `actionObserverDispatches_bilingualNotification` pins the inverse-init round-trip for both names.

2. **Medium — Divider anchor fallback** — `dividerAnchor(in:)` now returns `ReaderMoreMenuRow?`. When both bilingual-cluster rows are absent it walks a documented preference list (`.autoTurnPages, .readAloud, .bookDetails, .shareBook, .exportAnnotations`) and returns the first present row. Returns `nil` only on empty input. Popover unwraps via `if let anchor = dividerAnchor`. Two tests added: `dividerAnchor_fallsBack_whenBothBilingualRowsHidden`, `dividerAnchor_isNil_whenRowsEmpty`.

3. **Medium — Missing notification** — added `.readerBookTranslationProgressDidChange = "vreader.reader.bookTranslationProgressDidChange"` to `ReaderNotifications.swift` with doc comment naming WI-14's producer (`BookTranslationCoordinator`) and the `userInfo` shape (`fingerprintKey`, `completed`, `total`). Added a row to the architecture-doc Notification Bus table.

4. **Low — Empty target language** — `subDetail` for `.bilingual` `.on` now calls `target.trimmingCharacters(in: .whitespacesAndNewlines)` and returns the generic `"On"` label when the trimmed target is empty. Three tests added: `bilingualOnSub_safeOn_whenTargetIsEmpty`, `bilingualOnSub_safeOn_whenTargetIsWhitespace`, `bilingualOnSub_trimsAndRendersCJKTarget`.

5. **Low — `.none` vs `.chevron` semantic drift** — `trailingControl` now returns `.chevron` directly for the bilingual `.unavailable` state (matching the design's "Settings → Cellular when no SIM" pattern). The popover's `trailingAccessory` `.none` case renders `EmptyView()` — `.none` truly means no trailing accessory. The `bilingualUnavailableTrailing` test updated to expect `.chevron`.

## Round 2 — re-audit (verdict: ship-as-is)

Codex re-verified all 5 findings as fixed. One residual Low finding:

| File:line | Severity | Issue | Fix |
|---|---|---|---|
| `ReaderNotifications.swift:82` | Low | Comment drift — said the popover posts "one of its five rows" but WI-8 now ships seven enum rows and six/seven visible rows. Runtime code is correct; comment was stale. | Update the doc comment to describe the current row set without hard-coding the count. |

## Round 2 fix applied

- **Low — Comment drift** — rewrote the `ReaderNotifications.swift` doc block introducing the `readerMore*` notifications. The new copy avoids hard-coding the count and names WI-8 alongside WI-6c; the inverse `init?(notification:)` is cited as the single source of truth for the row set.

## Verdict — ship-as-is

After Round 2, all findings resolved. No new findings introduced in the fixes. Tests pass:

- `vreaderTests/ReaderMoreMenuBilingualTests` (30 tests)
- `vreaderTests/ReaderMorePopoverBilingualTests` (4 tests)
- `vreaderTests/ReaderMoreMenuRowTests` (updated, all pass)
- `vreaderTests/ReaderMorePopoverTTSGateTests` (updated, all pass)
- `vreaderTests/BookDetailsRouteTests` (updated, all pass)
- `vreaderTests/AnnotationsSheetRouteTests` (updated, all pass)
- Full `vreaderTests` suite: passed

## Tests run

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
    -project vreader.xcodeproj -scheme vreader \
    -destination 'platform=iOS Simulator,id=61149F0E-DC18-4BE2-BB37-52659F1F4F62' \
    -only-testing:vreaderTests \
    -parallel-testing-enabled NO
# ** TEST SUCCEEDED **
```
