---
branch: feat/feature-86-wi-4-sources-popover
threadId: codex-exec (run-codex.sh, 2 rounds)
rounds: 2
final_verdict: ship-as-is
date: 2026-06-03
---

# Codex audit — Feature #86 WI-4: Chat sources chip + sources popover (Gate 4)

## Implementation summary

The right-side **sources chip** + the **sources popover** (Notes / Highlights /
Bookmarks toggles), backed by a per-book annotation cache:

- `ChatAnnotationCache` (`@MainActor @Observable`) — loads the reader's annotations
  once on open + refreshes ONLY on `.readerAnnotationsDidChange` (never on relocate);
  fires `onChange` after each load so the coordinator re-assembles the context +
  the chip counts. `annotationBlock(for:maxUTF16:)` delegates to `ChatAnnotationContext`.
- `ChatSourcesMenu` — the popover (icon tile + label + "N in this book" + switch + footer).
- `ChatContextBar` — the right-side sources chip (green wash + count badge / "Off").
- `AIChatViewModel.setSources` → the shared `onScopeChanged` re-assembly funnel + `sourceCounts`.
- `ReaderAICoordinator` — owns the cache (persistence threaded from `ReaderContainerView`
  via `@Environment(\.persistenceActor)`); `refreshChatContext` folds the serialized
  annotation block into `ChatContextAssembler.assemble`.
- `AIChatView` — the two menus as mutually-exclusive overlays (scope leading, sources
  trailing) with a shared dismiss scrim.

Plan: `dev-docs/plans/20260603-feature-86-wi2-chat-scope-sources-retrieval.md` (WI-4).

## Round 1 — 1 High + 1 Low + 1 maintainability note

| severity | issue | resolution |
|---|---|---|
| High | `ChatAnnotationCache.load()` mutated the three arrays incrementally across awaits; two rapid `.readerAnnotationsDidChange` posts spawn overlapping fire-and-forget Tasks that could interleave → a stale/mixed snapshot. | **Fixed.** `load()` is now latest-wins + atomic: increment `loadGeneration`, capture `generation`, fetch all three into locals, `guard generation == loadGeneration` before committing all three + firing `onChange`. Only the newest reload publishes (`@MainActor` serializes the generation token). |
| Low | The bus carries no book identity → in a multi-reader scenario every cache would refetch on any annotation mutation. | **Accepted with rationale.** vreader opens exactly one reader at a time (one `ChatAnnotationCache` exists), so there's no cross-book redundancy in practice; threading `fingerprintKey` through the id-based mutation chokepoints (`removeBookmark(bookmarkId:)` etc.) would require extra fetches to resolve the key. |
| Note | `AIChatView.swift` was 418 lines (>300). | **Fixed.** Extracted the composer (`inputBar` + helpers + `secondaryContentColor`) into `AIChatView+Composer.swift`; `AIChatView.swift` dropped to ~290 lines. `inputText`/`isInputFocused` relaxed `private`→internal so the extension reads them; no behavior change. |

Round 1 explicitly cleared: no infinite loop in the `onChange → syncSourceCounts /
refreshChatContext` path (refresh never re-triggers `load()`); no retain cycle (the
coordinator/cache/observer captures are all `[weak self]`); the optional persistence
boundary is nil-safe and concurrency-sound (the three protocols are `Sendable`,
`PersistenceActor` is an actor); and no Rule-51 fidelity problem on the chip/popover.

## Round 2 — CLEAN

The latest-wins fix confirmed; the Low acceptance reasonable; the extraction behavior-
preserving. Zero open Critical/High/Medium.

## Verdict

`ship-as-is` after 2 rounds.

## Verification

- Unit (2 suites green via `scripts/run-tests.sh`): `ChatAnnotationCacheTests` (load /
  counts / refresh-on-bus-not-relocate / annotationBlock-respects-selection),
  `AIChatViewModelSourcesTests` (`setSources` funnel + default + no-op).
- Tier: behavioral. Gate-5 slice (device) follows in the PR — open the reader, tap the
  sources chip, toggle a kind, confirm the chip badge updates.
