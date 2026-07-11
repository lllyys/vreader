---
branch: feat/133-wi4-txtmd-resolver
threadId: 019f52f4-ef2c-7dd2-89bf-19f1957f6eb8
rounds: 2
final_verdict: ship-as-is
date: 2026-07-12
---

# Gate-4 audit — feature #133 WI-4 (TXT/MD in-book hit resolver)

Independent Codex audit (`scripts/run-codex.sh`, model gpt-5.6-sol, read-only sandbox) of the
WI-4 diff: `InBookSearchHitResolver` (format-agnostic FTS-track seam) +
`TxtMdInBookHitResolver` (chunk + `RawOccurrence` -> jumpable canonical `Locator` via
`charOffsetUTF16 = TxtDocument.offsetForChunk(sectionIndex) + rawOccurrence.startUtf16`) +
`TxtMdInBookHitResolverTest`.

## Round 1 — block-recommended (thread 019f52f4-ef2c-7dd2-89bf-19f1957f6eb8)

- **High-1 — tests did not exercise the real extractor.** `roundTrip_matchesExtractorBoundaries`
  built a second `TxtDocument` instead of driving `TxtMdTextExtractor.extract()`, so it compared
  `TxtDocument` to itself and could not catch extractor decode/emission drift.
- **High-2 — out-of-range inputs were not reliably rejected.** `TxtDocument.offsetForChunk`
  CLAMPS an invalid `sectionIndex` (-1 -> chunk 0, oversized -> last), and `validatedOrNull()`
  only checks non-negativity + range ordering — so a `sectionIndex` past `chunkCount` or an
  occurrence span past the chunk's own length would produce a "valid" locator pointing outside
  the chunk, contradicting the promised out-of-range -> null contract and breaking the
  `chunkForOffset` round-trip.
- **Medium-3 — interface KDoc overclaimed EPUB parity.** The seam embeds the TXT/FTS coordinate
  model; the KDoc implied a future EPUB implementation would back the same `(sectionIndex,
  RawOccurrence)` signature, which is unnatural for EPUB (Readium returns navigable locators
  directly).
- Core formula, `validatedOrNull()` usage, `fingerprintKey` derivation, and CJK UTF-16-vs-byte
  assertions were confirmed correct.

## Round-1 fixes applied

1. `TxtMdInBookHitResolver.resolve` now rejects (-> null) BEFORE the offset math:
   `sectionIndex !in [0, chunkCount)`, `startUtf16 < 0`, `endUtf16 < startUtf16`, and
   `endUtf16 > textForChunk(sectionIndex).length`. `validatedOrNull()` remains the final
   structural gate.
2. `roundTrip_matchesRealExtractorBoundaries` now drives `TxtMdTextExtractor.extract()` over a
   real temp UTF-8 file + `Book` + a `CollectingSink`, then resolves an occurrence from EACH
   emitted `BookTextSection` and asserts `chunkForOffset(charOffsetUTF16) == section.sectionIndex`
   plus the exact `offsetForChunk + rawStart` re-derivation.
3. Interface KDoc narrowed: it is the FTS-track (TXT/MD) resolver seam WI-6 dispatches to; EPUB
   resolves natively via Readium (WI-5), NOT this interface (matches plan §4).
4. Added out-of-range tests: negative offset, negative sectionIndex, sectionIndex past
   chunkCount, span past chunk length, inverted span.

## Round 2 — ship-as-is (thread 019f52f8-21e5-7350-9461-ea9c77f676e6)

No findings. All three round-1 findings confirmed resolved; remaining invariants
(exact `offsetForChunk(sectionIndex) + startUtf16`, `validatedOrNull()` as the construction gate,
CJK exact UTF-16 offsets, correct `fingerprintKey`, range start/end shifted by the same chunk
offset) all verified. (Codex could not run the Gradle gate in its read-only sandbox; the gate was
run in-lane via `scripts/run-android-tests.sh` — `RUN-ANDROID-TESTS RESULT: SUCCEEDED`, targeted +
full JVM suite.)

**Final verdict: ship-as-is.**
