---
branch: feat/feature-129-wi-3-chrome
threadId: b7rxlgpom
rounds: 2
final_verdict: ship-as-is
date: 2026-06-29
---

# Gate-4 audit — feature #129 WI-3 (the ReaderBottomChrome shell)

WI-3 adds the designed reader bottom chrome (`ReaderBottomChrome`): an interactive progress scrubber +
a Display-only toolbar (Contents/Notes/AI omitted until F/D — the LibraryScreen "omit non-functional
controls, no dead placeholders" precedent + the Gate-2 ruling). Standalone composable; per-host wiring
rides with each host's application (WI-4..7). Files: `reader/chrome/ReaderBottomChrome.kt`,
`ReaderBottomChromeUiTest.kt`.

## Round 1 (Codex `b7rxlgpom`, gpt-5.5/high) — 1 High, 2 Medium, 1 Low

| file | severity | issue | resolution |
|---|---|---|---|
| `ReaderBottomChrome.kt` | High | The thumb's RIGHT edge (not center) was placed at `progress`; at progress≈0 the parent width collapsed so the 14dp thumb could shrink/disappear. | **FIXED** — `BoxWithConstraints` computes `trackWidth`; the thumb's CENTER sits at `trackWidth * safeProgress - 7.dp`; the fill uses the fraction. |
| `ReaderBottomChrome.kt` | Medium | Rendered on `theme.background` with no distinct chrome surface + no top rule (the design's `t.chrome`/`t.rule`). | **FIXED** — added the 0.5dp top divider (`rule = ink@0.10`); chrome = `theme.background` (a documented local mapping; `ReaderTheme` has no separate chrome token). |
| `ReaderBottomChrome.kt` | Medium | Named/implemented as a scrubber but had no `onScrub` callback / pointer handling — host WIs couldn't wire seeking. | **FIXED** — added `onScrub: (Float)->Unit` + `detectTapGestures` + `detectHorizontalDragGestures` on the track (tap/drag → the clamped 0..1 fraction). A host WI wires it to seek. |
| `ReaderBottomChrome.kt` | Low | Same-package `ChromeLabel` + fully-qualified `androidx.compose.material3.Text` calls were noise. | **FIXED** — imported `Text`/`Color`, dropped the prefixes. |

## Round 2 (Codex re-audit) — production resolved, 1 Medium (test)

The auditor confirmed the round-1 production issues resolved (thumb centered, chrome/rule mapping
present, tap/drag call `onScrub` with a clamped fraction, `fillMaxWidth(safeProgress)` fine at 0/1). One
new finding:

| file | severity | issue | resolution |
|---|---|---|---|
| `ReaderBottomChromeUiTest.kt` | Medium | `performClick()` targets the `pointerInput`-only scrubber track (no semantics click action) → the test would fail / not exercise the gesture. | **FIXED** — `performTouchInput { click() }` (raw pointer input, which drives `detectTapGestures`). |

## Verdict

**ship-as-is.** Two rounds; all production + test findings fixed. Compiles clean (main + androidTest).

## Gate-5a verification note (instrumentation-platform flakiness — rule 47/52)

The connected `ReaderBottomChromeUiTest` could not be landed green this session — the **same instrumentation
platform flakiness** that blocked WI-2 (UTP crash with `tests="0"`, adb-shell congestion, instrumentation
wedges) recurred across WI-2 and WI-3 (3+ failed/wedged runs; the host has been running heavy build+audit+
emulator workloads for hours; a combined comma-class filter also fast-failed). Per rule 47/52 ("do not let
tooling flakiness block a code-proven WI"), WI-3 is **accepted** on: the code **compiles** (main +
androidTest), the Gate-4 audit is **ship-as-is**, and the **sibling connected sheet/list tests use the
identical `createComposeRule` + content-composable + `testTag`/`useUnmergedTree` harness and merged green**
(`ManageSheetUiTest` 3/3, `AssignSheetUiTest`, `CollectionShelfBarUiTest`). The chrome's live connected
confirmation is **consolidated into WI-8's acceptance pass** on a freshly cold-booted emulator (where all
the deferred connected tests run together). Lesson for the loop: run **one** test class per connected
invocation (a comma-separated `class=A,B` filter fast-fails with `tests="0"`).
