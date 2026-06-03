---
branch: feat/feature-86-wi-6-citations
threadId: codex-exec (run-codex.sh, 3 rounds)
rounds: 3
final_verdict: ship-as-is
date: 2026-06-03
---

# Codex audit — Feature #86 WI-6: provenance "Drew on" citations (Gate 4)

## Implementation summary

The per-reply provenance row:

- `ChatMessage.citations` (default `[]`).
- `ChatCitationFactory` — scope citation always; per-source citation only when ON &&
  count>0; whole-book span citation (spoiler-aware `aheadOfReader`, label by
  `coverage.isComplete`). Provenance-first: scope-level labels, no fabricated ordinals.
- `AIChatViewModel.pendingCitations`; `sendMessage` SNAPSHOTS them after the whole-book
  read trigger but before the stream, stamping the assistant reply (no mid-send mis-stamp).
- `ReaderAICoordinator.refreshChatContext` computes the citations + feeds them through
  `ChatContextAssembler` (which retains only those surviving the clamp).
- `ChatCitationRow` — the "Drew on" chips (a tiny `FlowRow` Layout), amber `· ahead` for
  whole-book spoilers.

Plan: `dev-docs/plans/20260603-feature-86-wi2-chat-scope-sources-retrieval.md` (WI-6).

## Round 1 — 1 High + 2 Medium

| severity | issue | resolution |
|---|---|---|
| High | The whole-book coverage citation read `digest?.coverage` regardless of phase — a stale digest surviving `disarm()` (+ a pre-read provider failure) could stamp `wholeBookSpan` on a send that actually used the `.bookSoFar` fallback. | **Fixed.** Gate the coverage on the SAME condition as the scope text — `usesWholeBookDigest = scope==.wholeBook && availableContext non-empty` (i.e. `.ready`/`.partial`). |
| Medium | Citation retention was all-or-nothing for the whole annotation block; a partial clamp keeping Notes but cutting Bookmarks dropped ALL annotation citations → under-report. | **Fixed.** PER-SECTION retention: an annotation citation survives iff its section header (`ChatAnnotationContext.{notes,highlights,bookmarks}Header`, now shared constants the serializer uses) is present in the clamped text. Test: `partialClamp_retainsSurvivingSectionsOnly`. Removed the dead `annotationKinds` set. |
| Medium | `ChatCitationRow`'s accessibility label read only the chip label, so VoiceOver couldn't distinguish a spoiler chip. | **Fixed.** The label appends ", ahead" for `aheadOfReader` chips. |

Round 1 explicitly cleared: the send-time snapshot is placed correctly (after the awaited
whole-book update, before request construction — no mid-stream re-stamp); the empty
assistant row is removed on failure (no citation leak from a failed send); `@MainActor`/
`Sendable` fine; `ChatCitation` UUID churn is harmless once copied into a stamped reply.

## Round 2 — 1 Medium

The High + a11y Medium confirmed fixed. New: the `bounded.contains(header)` retention had
false positives — the header could appear in scope/note content, or survive with no items.

**Fixed (round 3).** Retention now checks the section's FIRST BULLET survived:
`firstBulletUTF16Offset(forHeader:in:)` locates the section via the LINE-ANCHORED marker
`"\n<header>\n- "` (a header substring inside content can't false-match) and a citation is
retained iff `bounded.utf16.count > firstBullet` (the first item, not merely the header,
survived). Tests: `headerSurvivesButItemCut_dropsCitation`, `headerInScopeContent_doesNot
FalseRetain`.

## Round 3 — 1 Medium fixed + 1 Medium accepted (round cap)

The round-2 first-bullet check surfaced two finer edges:

| issue | resolution |
|---|---|
| `firstBulletUTF16Offset` searched the whole `combined` string, so scope prose matching `"\n<header>\n- "` could false-retain. | **Fixed.** Search ONLY the annotation `block` (offset rebased by `blockStartUTF16`); scope text is never scanned. Test strengthened: `headerLineShapeInScopeContent_doesNotFalseRetain` (scope text with the exact `\nNotes:\n- …` shape + empty block → not retained). |
| The offset is after `- `, but items are `- [label] text`, so a clamp keeping only `- [p.12] ` retains. | **Accepted with rationale (round cap).** This requires the combined context to exceed the 12K budget AND the clamp to land precisely inside a bullet's `[label]` prefix — a rare double-edge. The chips are **advisory provenance**, not a correctness/security boundary, so a narrow over-report (the model saw the section's header + first label but not its text) is low-harm. A fully precise item-text-offset check would require the serializer to emit per-item text offsets threaded through the cache → coordinator → assembler — disproportionate for this edge. Rule 47 permits accept-with-rationale at the 3-round cap. |

The file-size note (`ReaderAICoordinator` ~344) is also **accepted** (grew across WI-2..6).

## Verdict

`ship-as-is`. The retention went through 4 rounds of genuine accuracy improvement
(all-or-nothing → header-present → first-bullet → block-scoped first-bullet); the one
residual is an accepted narrow over-report at the round cap. Zero open Critical/High; one
accepted Medium with documented rationale.

## Verification

- Unit (green via `scripts/run-tests.sh`): `ChatCitationFactoryTests` (scope always;
  source-only-when-on-and-nonempty; whole-book spoiler span; partial-vs-complete label;
  no fabricated ordinals; ChatMessage carries citations), `ChatContextAssemblerSection
  RetentionTests` (per-section retention). No regression in `ChatContextAssemblerTests`.
- Tier: behavioral. Gate-5 — the "Drew on" row renders under a reply; the actual
  citation *content* depends on a real AI answer (provider-key-blocked) → keyed-verification
  (the factory + retention + a11y are unit-proven).
