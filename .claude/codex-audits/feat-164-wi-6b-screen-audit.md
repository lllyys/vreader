---
branch: feat/164-wi-6b-screen
threadId: 019fd02c-a0ee-70a2-8198-06cda3e108e1
rounds: 2
final_verdict: ship-as-is
date: 2026-08-05
---

# Codex Audit Log — Feature #164 WI-6b (GH #2023)

`DiagnosticsScreen` + the four content states + the nav shell + the share button
(`DiagLogViewer`, `DiagNavSheet`, `DiagShareButton`, `DiagLoading`, `DiagEmpty`
in `dev-docs/designs/vreader-fidelity-v1/project/vreader-diagnostics.jsx`),
composed over WI-6a's row / chips / footer and WI-5's `DiagnosticsUiState`.

Rounds run through `scripts/run-codex.sh` (rule 53). Round-1 thread
`019fd023-2ca7-7d30-acf5-d678bc692874`; round-2 thread
`019fd02c-a0ee-70a2-8198-06cda3e108e1` (recorded in the frontmatter). Full
transcripts: `.reports/audit-r1.txt`, `.reports/audit-r2.txt`.

## Round 1 — `follow-up-recommended`

The prompt required an explicit, evidence-bearing answer to the three questions
this WI was most likely to get wrong. All three came back affirmative:

1. **Is the footer genuinely hidden in BOTH loading and empty?** Yes. One
   `chromeVisible` predicate is computed once (`DiagnosticsScreen.kt:127`) and
   read by the share slot (`:132`), the filter bar (`:138`) and the footer
   (`:168`), matching the design's single gate at `vreader-diagnostics.jsx:469`.
   This is the defect plan v1/v2 carried — a footer reading
   `"0 entries · recent activity · ● Capturing"` over a fresh install, which no
   artboard depicts.
2. **Does back have exactly one dismissal path?** Yes. `DiagnosticsNavShell`
   exposes a single `onBack`; `BackHandler` and the leading control both invoke
   that value, so a caller cannot supply divergent actions.
3. **Does the virtualization test bound composition?** Yes, and non-vacuously:
   probe liveness is asserted before the bound, `CountingRowProbe` counts
   CONCURRENT (not cumulative) live rows, an eager `Column` of 2000 probed rows
   would peak near 2000 and fail the `<= 60` bound, and `performScrollToIndex(2000)`
   correctly targets entry 1999 given the day header at lazy index 0.

Findings: no CRITICAL, no HIGH.

| Severity | Finding | Disposition |
| --- | --- | --- |
| **MEDIUM** | Interactive targets under Android's 48dp minimum: the 28dp share circle used a 44dp box (and called 44 the minimum), the back control had 6dp vertical padding around 15sp text, "Clear filters" likewise. No test asserted any bound. | **FIXED** — each control now carries a grown INVISIBLE target around an unchanged designed visual; the nav bar is pinned to its designed 53dp (13 + 28 + 12) so the larger targets cannot inflate it. Bounds assertions added for all three (`theBarsControlsMeetTheMinimumInteractiveSizeWithoutInflatingTheBar`, `theClearFiltersControlMeetsTheMinimumInteractiveSize`) — every other test clicks a node's center, which succeeds at any size and would never notice a target shrinking back. |
| **MEDIUM** | The bundle's `boxShadow: 0 -8px 28px rgba(0,0,0,0.25)` (`:148`) was omitted — a visible rule-51 fidelity gap. | **FIXED** — `Modifier.shadow(14.dp, top-rounded)` ordered BEFORE `clip`/`background`, the house translation of this exact bundle shadow (`ReaderAiProvidersList`). |
| *LOW* | Sheet height rounded to `0.96f` rather than the artboard's 740/768. | **FIXED** — now `740f / 768f`. |
| *LOW* | The back-parity test's KDoc overclaimed: the counter proves both paths reach `onBack`, not strict side-effect identity. | **FIXED** — KDoc reworded; the single-parameter API is named as the actual invariant. |
| *LOW* | Both test files sit slightly over the ~300-line convention (325 / 310). | **ACCEPTED** — the suggested fix (extract a shared fixture file) requires a NEW file outside this WI's declared write-set, which the lane contract forbids. Round 2 agreed this should not block and called the disposition correct. |

## Round 2 — `ship-as-is`

Re-audited the changed files and re-checked the round-1 answers for regression.
**No CRITICAL, HIGH or MEDIUM findings.** Both MEDIUMs verified RESOLVED, not
merely claimed:

- **Touch targets** — a fixed 53dp parent does permit a 48dp child; the back
  row's `heightIn` is honoured given the modifier order; normal accessibility
  font scaling fits without clipping; start/end alignment behaves under RTL. The
  pinned bar changes the design's 13/12 split to a 12.5/12.5 centering —
  imperceptible and intended.
- **Shadow** — `shadow → clip → background` confirmed correct: the shadow is
  emitted outside the clipped surface, the background cannot paint over it, and
  no opaque surface or scrim z-fighting is introduced.

Regression checks all held: the single chrome predicate, the one dismissal path,
and the concurrent-composition bound.

### Round-2 finding

| Severity | Finding | Disposition |
| --- | --- | --- |
| *LOW* | `DiagnosticsShareButton.kt:75` / `DiagnosticsStates.kt:215` — the default bounded ripple now fills the enlarged 48dp clickable shape, so a PRESS momentarily paints larger than the designed 28dp circle / ~30dp pill. | **ACCEPTED, not fixed.** (a) Round 2's verdict is already `ship-as-is` and the auditor calls it minor with no accessibility or operational impact; (b) indication is not exposed to the semantics tree, so the suggested rewiring (shared `MutableInteractionSource`, `indication = null` outside, ripple on the inner visual) would ship **unverified by any connected test** — trading a transient press affordance for an untested change to press-state rendering is the worse deal at this point in the WI; (c) it matches shipped house precedent — `BookDetailsSheet`'s header action is the same enlarged-clickable-around-smaller-visual pattern. Worth folding into WI-7/WI-8 if the ripple is ever visually reviewed. |

## Verification evidence

Connected, on `emulator-5554` (one class per invocation; `--rerun-tasks`), AFTER
the round-1 fixes:

- `DiagnosticsScreenTest` — **10 tests, 0 failures**
- `DiagnosticsStatesTest` — **14 tests, 0 failures**
- `com.vreader.app.diagnostics.ui` package sweep — **67 tests, 0 failures**
  (WI-6a's 43 unchanged: 43 + 10 + 14)
- JVM `*diagnostics*` — **307 tests, 0 failures** (baseline unchanged)

`scripts/check-orphan-surfaces.sh`:
`ALLOWED DiagnosticsScreen … ORPHANED, allowlisted in scripts/.orphan-surfaces-allow`,
`reachable=22 allowlisted=1`, orphan count 13 → 12 (WI-6a's `DiagnosticsFilterBar`
gained a production call site; `DiagnosticsScreen` is the one annotated
`#164 pending #171` entry, which WI-8 removes).

## Rule 51

Every string, colour, dimension and glyph traces to the committed bundle; the
`Filter`, `Share` and `ChevronL` glyphs are transcribed from `vreader-icons.jsx`
rather than taken from Material, following WI-6a's precedent. Two deliberate,
plan-authorised divergences: the loading subtitle is `logcat · com.vreader.app`
rather than the iOS `OSLogStore · …` (plan §6.6), and the filtered-empty body
single-sources `CAPTURE_SCOPE_LABEL` instead of the design's hardcoded
"last 24 hours" (plan §6.5). The capture-unavailable empty-state copy is
deliberately NOT repaired here — it ships verbatim and is tracked as **GH #2022**;
round 1 explicitly confirmed this is not a finding.
