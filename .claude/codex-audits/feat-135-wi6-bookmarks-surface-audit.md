---
branch: feat/135-wi6-bookmarks-surface
threadId: 019f51eb-9121-77d3-974c-7e33ded741da,019f51f3-619e-79c2-a50d-34e450513bb5
rounds: 2
final_verdict: ship-as-is
date: 2026-07-11
---

# Gate-4 audit — feature #135 WI-6 (Android Bookmarks surface)

Independent Codex audit (`scripts/run-codex.sh`, rule 53) of the WI-6 diff: the
two-tab `TocBookmarksSheet` (Contents | Bookmarks) + the review-sheet `Bookmarks`
filter chip + `BookmarkCard`. Scope: rule-51 design fidelity, one-writer reuse of
#132's `TocContentsSheet`, dismiss-on-Succeeded navigation posture, capability-gated
tap-to-jump, and #132 back-compat.

## Round 1 — verdict: block-recommended (thread 019f51eb-9121-77d3-974c-7e33ded741da)

- **P1 — nullable jump capability produced clickable dead rows.** Both scaffold
  arms converted `onJumpBookmark == null` into `{ JumpResult.Failed }`, then
  `BookmarkRow` always installed `.clickable` — so a #132/unwired caller rendered
  clickable bookmark rows whose tap silently did nothing. That is outcome-handling,
  not capability-gating, and inconsistent with the review `BookmarkCard` (which
  omits `.clickable` when the callback is null). **Fixed:** `onJumpBookmark` is now
  threaded NULLABLE (`((BookmarkRecord) -> JumpResult)?`) through `TocBookmarksSheet`
  → `BookmarksTab` → `BookmarkRow`, which omits `.clickable` when null; the scaffold
  and `EpubReaderSheets` pass the nullable callback through directly (dropped the
  `?: { JumpResult.Failed }` synthesis). Added `nonNullJump_bookmarkRowsAreClickable`
  + `nullJump_bookmarkRowsAreNotClickable` tests.
- **P2 — TOC bookmark icon did not match the committed design.** The Bookmarks-tab
  row used Material's FILLED bookmark; `vreader-panels.jsx` line 353 depicts the
  stroked/outline `Icons.Bookmark size={18} stroke={1.7}`. (The FILLED icon is
  correct only for the separate review `BookmarkCard`, matching
  `vreader-android-annotations.jsx` `BookmarkFilled`.) **Fixed:** the TOC row now
  uses `Icons.Outlined.BookmarkBorder`; the review card keeps the filled icon.

Everything else checked out in round 1: `TocContentsSheet.kt` has no diff from
`main` (reused via `TocContentsSheetContent`, not edited — one-writer serialization);
successful jumps dismiss, failed jumps stay open; empty states + no-delete assertions
present; both scaffold + EPUB Toc arms use `TocBookmarksSheet`; new params are
nullable/defaulted (back-compat); no host wiring leaked.

## Round 2 — verdict: ship-as-is (thread 019f51f3-619e-79c2-a50d-34e450513bb5)

Both round-1 findings confirmed resolved:
- P1: `onJumpBookmark` stays nullable through `ReaderChromeScaffold`,
  `EpubReaderSheets`, `TocBookmarksSheet`, and `BookmarksTab`; `BookmarkRow` adds
  `.clickable` only when the callback exists (`assertHasNoClickAction()` for the null
  case). Review cards gate the same way.
- P2: the TOC row uses `Icons.Outlined.BookmarkBorder` (matches the stroked design);
  the review `BookmarkCard` retains `Icons.Filled.Bookmark`.

Re-audit: rule-51 fidelity matches `vreader-panels.jsx` + `vreader-android-annotations.jsx`
(no invented delete or failure UI); `TocContentsSheet` reused unchanged;
dismiss-on-Succeeded-only + tested empty state; capability-gated tap-to-jump; #132
back-compat via nullable/defaulted params; no host wiring leaked (`ReaderActivity`
remains unwired — WI-7 feeds `bookmarks`/`onJumpBookmark`); `git diff --check` passes.

**Final verdict: ship-as-is.**
