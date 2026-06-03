---
branch: feat/feature-86-wi-2-chat-context-foundation
threadId: codex-exec (run-codex.sh, 3 rounds)
rounds: 3
final_verdict: ship-as-is
date: 2026-06-03
---

# Codex audit — Feature #86 WI-2: Chat context-bar foundation + annotation bus (Gate 4)

## Implementation summary

The foundational, no-UI slice of the Chat context bar:

- `ChatContextScope` (section/chapter/bookSoFar/wholeBook; `summaryScope` mapping;
  `isOnDemand`/`spoilerAware`; `defaultScope == .chapter`).
- `ChatSourceSelection` (notes/highlights/bookmarks toggles; `activeCount`/`allOff`).
- `ChatCitation` — provenance-first (`sourceKind` + optional `locator`/`spanUTF16`/
  `sequence` + `aheadOfReader`).
- `ChatAnnotationContext` — pure serializer; notes = standalone `AnnotationRecord`s +
  highlights with a non-empty note (matches `AnnotationStreamBuilder`); locator-labelled,
  newest-first, budget-capped lines.
- `ChatContextAssembler` — combines scope text + annotation block, clamps, and retains
  only the citations that survived the clamp.
- `UTF16Clamp` — one shared grapheme-safe UTF-16 clamp.
- `.readerAnnotationsDidChange` — a new mutation-complete bus posted from the
  `PersistenceActor` highlight/bookmark/annotation mutation chokepoints (after a successful
  save), covering every caller (incl. import) by construction.

Plan: `dev-docs/plans/20260603-feature-86-wi2-chat-scope-sources-retrieval.md` (Gate-2, 4 rounds).

## Round 1 — 1 High + 2 Medium + 2 Low

| severity | issue | resolution |
|---|---|---|
| High | `ChatContextAssembler` returned the full input citations even when the clamp trimmed the annotation block away (or `maxUTF16==0`) — provenance didn't match the injected text. | **Fixed.** `retainedCitations` clears all citations when `bookContext` is empty and drops the annotation-kind citations when the block didn't fully survive the clamp (scope citation kept). Tests added for empty / full-trim / all-survive. |
| Medium | The serializer emitted no locator labels (the plan calls for labelled, newest-first entries). | **Fixed.** `ChatAnnotationContext.locatorLabel` (PDF `p.N` / TXT `@offset` / EPUB href basename) prefixes each line; per-kind label asserts added. |
| Medium | The bus suite allowed over-fulfillment and missed `updateHighlightColor`, `removeBookmark`, `updateBookmarkTitle`, `updateAnnotation`, import, and throwing paths. | **Fixed.** Added exactly-once assertion + the 4 missing mutation tests + an import-via-`AnnotationImporter` test + a throwing-mutation no-post test. |
| Low | Two drifted UTF-16 clamp impls; `assemble`'s `scope` param unused. | **Fixed.** Extracted `UTF16Clamp`; removed the unused `scope` param. |
| Low | Clamp boundary tests only checked `utf16.count` with BMP CJK. | **Fixed.** Added emoji/ZWJ + label coverage (then hardened in round 2). |

## Round 2 — 1 Medium + 1 Low (both test-rigor; no Critical/High)

Codex confirmed the assembler retention logic correct across all branches, `blockStartUTF16`
correct, `locatorLabel` complete, and the shared clamp resolved the duplication.

| severity | issue | resolution |
|---|---|---|
| Medium | `expectBusPosts` didn't truly prove exactly-once — `fulfillment` returns on the first delivery, so a second `.main`-enqueued post could land after observer teardown and be missed. | **Fixed.** Count every delivery, await the first, then `await MainActor.run { }` (FIFO — runs after any already-enqueued second block), remove the observer, assert `count == 1`. |
| Low | The ZWJ test proved scalar validity (round-trip), not grapheme integrity. | **Fixed.** New `UTF16ClampTests` asserts the result equals an EXACT whole-family-emoji / whole-apple prefix (`.count == 2`), proving no cluster/surrogate split. |

## Round 3 — 1 Medium (test determinism)

Confirmed the ZWJ Low fixed. Found that `expectBusPosts`'s round-2 fix was still not
deterministic: the observer delivered on `OperationQueue.main`, but the flush used
`await MainActor.run { }` — different ordering domains, so a duplicate post could still slip
past. **Fixed (final pass):** register the observer with `queue: nil` so
`NotificationCenter.post` delivers **synchronously** on the posting thread (inside the actor
mutation, before it returns); after `await body()` the `await` is a happens-before barrier,
so every post is already counted. `countBusPosts` then asserts `count == 1` (exactly-once),
`count == 0` (silent/no-op/throwing), or `count >= N` (import) with zero queue-ordering
ambiguity. Bus suite re-run green.

## Verdict

`ship-as-is`. The remaining concern at each round was test rigor (the production code —
assembler retention, locator labels, the shared clamp, the actor-chokepoint bus — was
confirmed correct from round 2 on); the final synchronous-delivery counting closes it
deterministically.

## Verification

- Unit (6 suites, all green via `scripts/run-tests.sh`): `ChatContextScopeTests`,
  `ChatSourceSelectionTests`, `ChatCitationTests`, `ChatAnnotationContextTests`,
  `ChatContextAssemblerTests`, `UTF16ClampTests`, `PersistenceActorAnnotationBusTests`.
- Tier: foundational (pure value types + serializers) + one additive notification (no
  user-observable behavior). No device verification required at this WI tier (rule 47 Gate 5).
