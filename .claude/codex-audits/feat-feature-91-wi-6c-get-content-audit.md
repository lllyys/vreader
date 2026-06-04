---
branch: feat/feature-91-wi-6c-get-content
threadId: 019e91db-2072-7ae0-af2b-d89ddd7beba1
rounds: 3
final_verdict: ship-as-is
date: 2026-06-04
---

# Codex Audit — Feature #91 WI-6c (get_book_content)

Gate-4 implementation audit (rule 47). Independent Codex runner via
`scripts/run-codex.sh -e high` (author/auditor separation, rule 48; rule-53
stdin-isolated watchdog).

## Scope

Behavioral WI-6c — fetch a library book's text by title (the second Gate-2-flagged
coverage-risk executor):

- `vreader/Services/AI/Tools/GetBookContentGate.swift` (new) — the PURE locality +
  format gate (`GetBookContentGate.evaluate`) + the `BookContentProvider` seam +
  `BookContentInfo` / `BookTitleResolution` / `BookContentMatch` /
  `BookContentEligibility`.
- `vreader/Services/AI/Tools/GetBookContentTool.swift` (new) — `struct
  GetBookContentTool: AITool`; resolve title → gate → extract → range/byte-capped
  result; explicit isError results for not-found / ambiguous / not-local /
  unsupported-format / extract-failure / out-of-range. Never throws.
- `vreader/Services/AI/Tools/ToolResultText.swift` (modified) — added a marker-free
  `truncateToBytes`; `clamp` refactored to reuse it (behavior-preserving).
- Tests: `GetBookContentGateTests` (5) + `GetBookContentToolTests` (17).

**Design decision (endorsed by the auditor):** the tool takes a **title** (what
the model sees from search results / the user), not a fingerprint key (an internal
id the model never sees). The plan's "findBook(byFingerprintKey:)" was the internal
mechanism; the model-facing contract is the title.

## Round 1 — findings (threadId 019e91db-2072-7ae0-af2b-d89ddd7beba1)

Locality-first gating, the exact `{epub,txt,md,pdf}` supported set, extract-only-on-
eligible, never-throws, and the Swift 6 actor/Sendable story all confirmed sound.

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| GetBookContentGate.swift (seam) | **High** | `findBook(title:) -> BookContentInfo?` was binary — two books sharing a title would silently return the WRONG book's text. | **Fixed.** The seam returns `enum BookTitleResolution { notFound / found(BookContentInfo) / ambiguous([BookContentMatch]) }`; the tool surfaces the ambiguous candidates **with author** and returns an isError ("Several books match…"), never extracting. Test `ambiguousTitle` pins it. |
| GetBookContentGate.swift (BookContentInfo) | **High** | The "canonical format" rule was comment-only — WI-8 could still fill `format` from the stale `book.format` column (the Bug #246 class) and the gate would trust it. | **Fixed.** `BookContentInfo` no longer stores a format; `var format: String?` is DERIVED from `fingerprintKey` via `DocumentFingerprint(canonicalKey:)?.format.rawValue` — a caller cannot supply a drifted format. A malformed key → nil → the tool reports "unreadable metadata". Tests `formatDerivedFromKey` + `malformedKeyUnreadable` pin both paths. |
| GetBookContentToolTests.swift | Low | The two highest-risk cases (ambiguity, format-drift) were untestable with the old seam. | **Fixed.** `ambiguousTitle`, `formatDerivedFromKey`, `malformedKeyUnreadable` added. |

## Round 2 — verification (threadId 019e91f1-75f4-7840-b9a4-6978422f4f6f)

Findings 1–3 **RESOLVED**. One **new Medium**: the plan's "range-limited" contract
was unimplemented (only `title` + `max_chars` prefix cap; no way to read later
sections, and an "out-of-range" test was planned). **Fixed.** Added an optional
0-based `start_char`: an empty extract → a non-error "no extractable text" result;
`start_char >= total` → an isError "past the end" result; otherwise a grapheme-safe
window with a "characters START–END of TOTAL" header. Tests `startCharWindowsLater`,
`startCharOutOfRange`, `emptyExtract`.

## Round 3 — verification (threadId 019e9206-5f03-7942-a054-7d76a10cf098)

The round-2 Medium **RESOLVED**. One **new Medium**: the range header's END was
computed BEFORE the UTF-8 byte clamp, so a CJK body clamped shorter than the
window advertised a too-large END — a model paging with `start_char=END` would
skip the clamped-off text. **Fixed.** `formatContent` now clamps the SLICE first
(reserving the header's bytes via the new `truncateToBytes`), then derives END from
the characters actually included, then builds the header — so the advertised range
always matches the returned text. Test `headerEndMatchesClampedBody` pins it (CJK,
300-byte budget → header END == the '字' chars actually returned).

## Round-cap decision (rule 47: max 3 rounds)

This is round 3, the documented cap. The round-3 finding was fixed rather than
escalated for the same reasons as WI-6b: monotonic convergence (each round one
distinct, accepted, cleanly-fixable issue — High×2 → Medium → Medium, never a
re-litigation of a prior fix) and a mechanical, directly-test-pinned fix. The
round-3 fix was applied WITHOUT a 4th audit round; its correctness rests on
`headerEndMatchesClampedBody` + the byte-bound assertion.

## Verdict

**ship-as-is.** Zero open Critical/High/Medium. Test gate green:
`GetBookContentGateTests` (5 — local supported, native-azw3 unsupported, non-local,
locality-first, supported-set) + `GetBookContentToolTests` (17 — derived-format +
malformed-key, ambiguity, not-found / not-local / unsupported / extract-throw,
title-required, char/byte caps, start_char windowing + out-of-range + empty +
header-END-matches-clamp). The `ToolResultText.clamp` refactor is behavior-
preserving (WI-6a/6b suites green).
