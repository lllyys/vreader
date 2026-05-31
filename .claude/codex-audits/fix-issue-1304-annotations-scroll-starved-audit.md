---
branch: fix/issue-1304-annotations-scroll-starved
threadId: codex-exec-readonly
rounds: 1
final_verdict: ship-as-is
date: 2026-05-31
---

# Codex audit — Bug #296 / GH #1304 (annotations list can't scroll)

Read-only `codex exec` audit of the fix.

## Fix summary

- Root cause: `NotesDeleteRow` attached its swipe `DragGesture` via
  `.highPriorityGesture`, which claimed every drag (no axis constraint at
  recognition) and starved the enclosing `HighlightsSheet` ScrollView's
  vertical pan. The horizontal-only guard ran in `.onEnded` (too late).
- Fix: (1) `.highPriorityGesture` → `.simultaneousGesture` so the ScrollView
  wins vertical motion; (2) extracted the reveal/dismiss/none decision into a
  pure `NotesSwipeResolver` seam — a vertical-dominant drag resolves to
  `.none`, so a scroll is never treated as a swipe.

## Files

- `vreader/Views/Reader/Annotations/NotesDeleteRow.swift` (modified)
- `vreader/Views/Reader/Annotations/NotesSwipeResolver.swift` (new)
- `vreaderTests/Views/Reader/Annotations/NotesSwipeResolverTests.swift` (new)

## Round 1 findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| NotesSwipeResolverTests.swift:80 | Low | Edge matrix pinned the exact negative (reveal) threshold but not the symmetric exact positive (dismiss) threshold. | Fixed — added `exactPositiveThreshold_whenRevealed_isNone`. |

Codex one-line verdict: "product fix looks correct. `.simultaneousGesture`
should restore vertical `ScrollView` pans, horizontal reveal/dismiss behavior
is preserved from the original inline logic, vertical-dominant drags resolve to
`.none`, no new UI chrome is introduced, and I see no Swift 6 concurrency
issue."

## Verdict

ship-as-is. Behavior-only change (Rule 51 carve-out — no new visible chrome).
Tests: `NotesSwipeResolverTests` 11/11 green. The gesture-arbitration aspect
(scroll restored) is not unit-observable and is covered by device verification
in the close gate against a real book.
