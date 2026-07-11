---
branch: feat/132-wi2-reader-top-chrome
threadId: 019f501c-278d-7372-8129-fb4b87770e34
rounds: 3
final_verdict: ship-as-is
date: 2026-07-11
---

# Gate-4 audit — feature #132 WI-2 ReaderTopChrome

Independent Codex audit (gpt-5.6-sol) of the `ReaderTopChrome` composable + its
instrumented Compose test, per rule 47 Gate-4 / rule 53. Author (this lane) is
separate from the auditor (Codex `codex exec`), satisfying rule-48 author/auditor
separation.

Scope: `android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderTopChrome.kt`
+ `android/app/src/androidTest/kotlin/com/vreader/app/reader/chrome/ReaderTopChromeTest.kt`.

## Round 1 (thread 019f501c-278d-7372-8129-fb4b87770e34) — block-recommended

- **[High] Title not centered across the full bar.** A weighted `Text` between
  independently-sized leading + trailing clusters centers within the *remaining*
  space, so with null/asymmetric trailing slots the title drifts right —
  violating the committed `ReaderTopChrome` fidelity.
  **Fixed (round 2):** restructured the bar to a `Box` overlay — the title is
  `fillMaxWidth()` + `TextAlign.Center` centered across the whole bar, with the
  leading back control aligned `CenterStart` and the trailing cluster aligned
  `CenterEnd`, both overlaid; the title reserves horizontal padding so it never
  overlaps the end controls.
- **[Medium] Back-control touch target untested.** The a11y test asserted Search
  + More but not the always-present back control.
  **Fixed (round 2):** `controlsMeetMinimumTouchTarget` now also asserts the
  "Back to library" control's height >= 48dp.
- **[Medium] `bookmarkSlot` had no >=48dp guarantee.** The wrapper supplied
  neither a minimum size nor semantics.
  **Fixed (round 2):** the slot wrapper now enforces `sizeIn(minWidth = 48dp,
  minHeight = 48dp)`; a new test asserts the wrapper is >= 48dp in both dims.
- **[Low] Long-title test proves node existence, not `maxLines`/ellipsis.**
  **Accepted:** `maxLines = 1` + `TextOverflow.Ellipsis` are set statically on
  the title `Text`, and the bar is a fixed-height row so wrap-driven growth is
  structurally impossible; the Compose test API cannot externally read a node's
  `maxLines`/`overflow` without a probe param, which would pollute the fixed
  brief signature.

Confirmed correct in round 1: nullable Search/More/bookmark omit-when-null
behavior (the #129 dead-control rule), slot order, state hoisting, `ReaderTheme`
token map (same as `ReaderBottomChrome`), content descriptions on built-in
controls, RTL-aware back icon (`Icons.AutoMirrored`), and all requested testTags.

## Round 2 (thread 019f5022-b899-7b11-8946-14b7116f7d23) — block-recommended

The round-1 High is confirmed resolved (title now centered relative to the full
bar independent of asymmetric end controls). Two Mediums raised:

- **[Medium] 132dp title padding < max trailing cluster (3 * 48dp = 144dp)** →
  up to 12dp overlap.
  **Fixed (round 3):** reserved padding raised 132dp -> 144dp.
- **[Medium] `bookmarkSlot` 48dp envelope != the clickable child's target.**
  **Accepted with rationale:** `bookmarkSlot` is a host-supplied composable per
  the plan; #135 fills it with its own 48dp toggle. The wrapper guarantees a
  >=48dp layout *envelope*; it cannot (and must not) enlarge an arbitrary child's
  clickable area, since making dead space around the child clickable with no
  action would be wrong. The interactive 48dp target is #135's toggle's own
  responsibility — the correct layer contract.
- **[Low]** long-title test — as accepted in round 1.

## Round 3 (thread 019f5028-1407-7180-886f-95a7d401f8dd) — ship-as-is

"No open High or Medium findings remain. The 144dp reservation correctly covers
the maximum three-control trailing cluster. The bookmark wrapper correctly
guarantees the slot's layout envelope; #135 remains responsible for its toggle's
actual 48dp interactive target. The accepted long-title test limitation remains
Low."

## Verdict

**ship-as-is** — zero open Critical/High/Medium after 3 rounds; the two Low items
are accepted with rationale above.
