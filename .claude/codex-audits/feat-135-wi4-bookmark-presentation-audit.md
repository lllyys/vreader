---
branch: feat/135-wi4-bookmark-presentation
threadId: 019f51ae-8183-7a00-b69c-b6a29665b11b
rounds: 3
final_verdict: ship-as-is
date: 2026-07-11
---

# Gate-4 audit — feature #135 WI-4 (per-format bookmark presentation projection)

Independent Codex audit (rule 53, `scripts/run-codex.sh`) of the pure, read-time
per-format bookmark presentation projection:
`reader/nav/BookmarkPresentation.kt` (+ `BookmarkTocIndex`, `BookmarkRowUi`,
`BookmarkDateRenderer`) and `reader/nav/BookmarkPreviewProvider.kt`, with the
pure-JVM `BookmarkPresentationTest`.

Author/auditor separation preserved: implementation by the Claude lane, audit by
a separate Codex `codex exec` process.

## Round 1 — verdict: block-recommended (session `019f51a4-2cfd-7583-bc6a-54b9e7932a4f`)

- **High** — EPUB chapter lookup mixed book-wide `totalProgression` with
  chapter-local `progression` into one binary-search key (non-monotonic → wrong
  chapter); a missing target progression defaulted to `0.0` and could fabricate a
  chapter.
- **Medium** — a null TXT/MD `charOffsetUTF16` fabricated a start-of-book preview
  (called the provider at offset 0) instead of yielding a null preview.
- **Medium** — the `BookmarkPreviewProvider` contract did not forbid I/O, so the
  "no I/O / deterministic" claim was unenforced.
- **Low** — PDF rendered a negative page as `p. 0` and could overflow at
  `Int.MAX_VALUE + 1`.

### Round-1 fixes applied

- EPUB fast path binary-searches on `totalProgression` ONLY, checking the
  monotonic precondition while searching (no O(n) prescan) and aborting to an
  href-exact fallback; no fabricated chapter.
- Null TXT/MD offset → `preview = null`, provider skipped; stored-negative offset
  clamped to 0.
- `BookmarkPreviewProvider` KDoc requires a pure, side-effect-free read over
  already-decoded in-memory text (no file/DB/mutable-state access).
- PDF renders `p. N` only for a valid non-negative, non-overflowing page.

## Round 2 — verdict: block-recommended (session `019f51a9-50e4-7b41-9678-c483d1de762e`)

TXT / provider-purity / PDF findings **confirmed resolved**. The EPUB fix was
still unsound: the "abort while searching" only detected a missing
`totalProgression` on entries the binary search happened to visit, so a null
outside the probe path (or an out-of-order populated sequence) went undetected.
Auditor's recommended shape: validate/index the TOC once, then search a trusted
structure.

### Round-2 fix applied

- Introduced `BookmarkTocIndex.build(entries)` — a single pass that validates
  EVERY entry has `totalProgression` AND the sequence is non-decreasing, setting
  a `monotonic` flag once. `nearest()` then binary-searches O(log n) on the
  trusted flag, else uses the href-exact fallback. The caller builds the index
  once per TOC and reuses it across rows (O(n + m·log n), never O(n·m)).
  `bookmarkRow` now takes `BookmarkTocIndex?` instead of `List<TocEntry>?`.
- Added the auditor's targeted test (a large odd-sized TOC whose sole null
  `totalProgression` lies outside the probe path is still detected → correct
  chapter via fallback) and isolated the post-build O(log n) lookup-bound test.

## Round 3 — verdict: block-recommended → fixed → ship-as-is (session `019f51ae-8183-7a00-b69c-b6a29665b11b`)

Fast-path correctness (prevalidated index), TXT null-offset, provider purity,
PDF validation, and deterministic date all **confirmed**. One remaining defect:

- **High** — `hrefFallback()` picked the LAST qualifying same-`href` entry in
  list order, not the entry with the greatest `progression <= target`, so an
  out-of-order same-href TOC returned the wrong chapter; a null entry
  `progression` (defaulted to 0.0) could select an unplaceable entry.
- **Nit** — `build()` is "up to O(n)" (early-exits at the first invalid entry),
  not literally a full pass; the doc should say so.

### Round-3 fixes applied

- `hrefFallback()` now tracks the entry with the maximum non-null
  `progression <= target.progression` (nearest-at-or-above by progression, not
  list order); a null-progression same-href entry is skipped as unplaceable
  (never fabricated).
- `build()` KDoc corrected to "single pass, up to O(n) (early-exits at the first
  invariant break; the monotonic flag is set only when the whole list validated)".
- Added two tests: reversed same-href order → greatest-progression entry; a
  null-progression same-href entry is skipped.

### Round-3 fix confirmation — verdict: ship-as-is (session `019f51b1-811c-7953-a434-857ed038c857`)

Confirmed: (a) `hrefFallback` returns the greatest-progression-at-or-below entry
regardless of list order; (b) null-progression same-href entries are skipped;
(c) no new correctness or crash issue introduced.

## Final state

Zero open Critical/High/Medium findings. `BookmarkPresentationTest` — 29 tests, 0
failures, 0 skipped (pure-JVM `:app:testDebugUnitTest`,
`RUN-ANDROID-TESTS RESULT: SUCCEEDED`). Final verdict: **ship-as-is**.
