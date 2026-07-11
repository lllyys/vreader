---
branch: feat/133-wi2-structured-query
threadId: 019f52d1-1828-7682-abce-d230fabb8d48
rounds: 1
final_verdict: ship-as-is
date: 2026-07-12
---

# Gate-4 audit — feature #133 WI-2 (SearchQueryBuilder.structuredQuery)

**Scope:** the WI-2 diff (`git diff origin/main..HEAD`) — additive
`SearchQueryBuilder.structuredQuery(raw): StructuredQuery?`, the new
`StructuredQuery.kt` model, the shared `buildGroupedParts` grouping refactor,
and `StructuredQueryTest.kt`.

**Tool:** `scripts/run-codex.sh` (rule 53), model gpt-5.6-sol, read-only sandbox,
1 round. Full output: `.reports/wi2-audit.txt`.

## Verdict: ship-as-is (no blocking findings)

Codex confirmed each audit focus:

1. **structuredQuery derives from the SAME grouping as ftsQuery, not the flat
   tokens.** Both `structuredQuery` and `ftsQuery` (via `buildFtsParts`) project
   from one `buildGroupedParts(tokens)` result. Structure is NOT reconstructed
   from `BuiltQuery.tokens`.
2. **Typed output correct:** contiguous CJK run → one ordered `Phrase`; the
   final eligible bareword → `PrefixTerm`; earlier barewords and FTS keywords →
   `Term`; blank / special-only → `null`.
3. **ftsQuery / BuiltQuery byte-for-byte unchanged.** The `buildFtsParts`
   refactor is behaviorally equivalent to the parent — grouping, quoting, order,
   final-unquoted-part selection, star placement, joining, and returned tokens
   are all unchanged. `BuiltQuery` and `ftsQuery` public signatures and
   construction are untouched. `git diff --check` clean. **No private→internal
   visibility lift occurred** — the new `GroupedPart` is file-private, safely
   additive.
4. **Tests assert concrete structure** (ordered CJK phrases, source order,
   prefix placement around trailing CJK/keywords, implicit-AND units, null
   cases). The FTS regression test uses hard-coded historical `fts`/`tokens`
   expectations (not derived from the new structured representation) so it is not
   tautological; the existing `SearchQueryBuilderTest` remains an independent
   regression layer.

## Non-blocking nit (accepted, no change)

Codex noted the comments say structure is derived from "the same `buildFtsParts`
grouping" while technically both projections now consume the newly extracted
`buildGroupedParts`. The `structuredQuery` KDoc already states "the SAME grouping
[ftsQuery] uses (via [buildGroupedParts])" and the file header describes the
`buildGroupedParts` factoring explicitly, so the design intent is accurately
documented. Codex itself concluded this "does not warrant a follow-up." No code
change.

## Test gate (independent of the audit's read-only sandbox)

- `RUN-ANDROID-TESTS RESULT: SUCCEEDED` — targeted `*StructuredQueryTest` (16) +
  `*SearchQueryBuilderTest` (13, unchanged, still green).
- `RUN-ANDROID-TESTS RESULT: SUCCEEDED` — full `:app:testDebugUnitTest` (no
  regression).
