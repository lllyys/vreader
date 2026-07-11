---
branch: feat/132-wi4-annotations-review-sheet
threadId: 019f505b-7e1a-7432-9604-6ea4f19df114
rounds: 3
final_verdict: ship-as-is
date: 2026-07-11
---

# Gate-4 audit — feature #132 WI-4 (AnnotationsReviewSheet + AnnotationCards)

Independent Codex audit (rule 53 `scripts/run-codex.sh`, read-only sandbox) of the
new annotations review sheet against the committed design
`dev-docs/designs/vreader-fidelity-v1/project/vreader-android-annotations.jsx`
(`AnnotationsSheet` / `HighlightCard` / `StandaloneNoteCard`).

Files audited:
- `android/app/src/main/kotlin/com/vreader/app/annotations/AnnotationsReviewSheet.kt`
- `android/app/src/main/kotlin/com/vreader/app/annotations/AnnotationCards.kt`
- `android/app/src/main/kotlin/com/vreader/app/annotations/AnnotationItem.kt`
- `android/app/src/androidTest/kotlin/com/vreader/app/annotations/AnnotationsReviewSheetTest.kt`

## Round 1 — verdict: block-recommended (4 rule-51 fidelity findings)

The behavioral gates all passed on round 1 (All/Highlights/Notes chips only — no
Bookmarks; sheet-level Share only; per-card Copy/Share + the `…` menu genuinely
absent + absence-asserted; nullable `onJumpToAnnotation` capability gate correct;
filters narrow; empty -> `annot-empty`). Four visual-fidelity mismatches with the
named design components:

1. **High** — `StandaloneNoteCard` used a solid accent bar at 70% opacity; the
   design specifies a repeating 4px-on / 4px-off dashed rule at full `ui.tint`.
2. **Medium** — both cards omitted the design's `meta` line (`HighlightCard`
   rendered only `· Note`; `StandaloneNoteCard` rendered only `STANDALONE`).
3. **Medium** — the empty state omitted the design's circular Highlighter-icon
   badge and changed the approved explanatory copy.
4. **Low** — theme-token fidelity incomplete: the designed `ui.cardShadow` was
   not applied.

## Round 2 — fixes applied (diff mis-parse — inconclusive)

All four findings fixed in code (dashed rule via `DashedRule` +
`PathEffect.dashPathEffect`; `metaLine(createdAt, locator.page)` on both cards;
empty-state circular `Icons.Outlined.BorderColor` badge + restored copy;
`Modifier.shadow(theme.cardElevation(), shape)` card shadow). The round-2
re-audit was run against a pasted `git diff` and the auditor mis-parsed it as a
stale pre-fix revision ("Shadow unresolved" / "appears to be the Round-1
version") even though the fixes were confirmed present on disk and in the commit.
Inconclusive — re-run reading files on disk.

## Round 3 — verdict: ship-as-is (files read on disk)

Re-audited by reading the current files directly (session
`019f505f-ff4b-7bb3-becd-780a3602f0f4`). All four prior findings confirmed
resolved:

1. `StandaloneNoteCard` uses `DashedRule(theme.accent)` — a vertical
   `PathEffect.dashPathEffect(4dp on, 4dp off)` line at full accent, not a solid bar.
2. Both cards render `metaLine(record.createdAt, record.locator.page)`.
3. Empty state has the circular `Icons.Outlined.BorderColor` badge + the exact
   approved "tap the note icon on a chapter" copy.
4. Shared card chrome applies `.shadow(theme.cardElevation(), shape, clip = false)`.

All WI-4 gates re-confirmed:
- Only `All / Highlights / Notes` filters; no Bookmarks (#135).
- Only sheet-level Share (`annot-share`).
- No per-card Copy, Share, or `…` menu on the review cards (design gate).
- `onJumpToAnnotation` nullable; `.clickable` attached only when the derived
  callback is non-null (capability gate, no dead no-op).
- Filters narrow correctly (All = highlights + notes); empty filtered result ->
  `annot-empty`.
- `AnnotationItem` has only `Highlight` and `Note` variants (`BookmarkCard` is #135).

**No blocking or follow-up finding.** The implementation matches the relevant
design definitions.

## Verdict

**ship-as-is** (round 3).

Round-1 audit log: `.reports/wi4-audit.txt` (session `019f505b-7e1a-7432-9604-6ea4f19df114`).
Round-3 re-audit log: `.reports/wi4-audit-r3.txt` (session `019f505f-ff4b-7bb3-becd-780a3602f0f4`).
