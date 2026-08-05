---
branch: feat/164-wi-6a-components
threadId: 019fcfdd-c919-72d3-93b6-8a62b2ea8b40
rounds: 3
final_verdict: ship-as-is
date: 2026-08-05
---

# Codex Audit Log — Feature #164 WI-6a (GH #2023)

The designed diagnostics components: log row + day header, level style/tokens,
filter bar, footer, and the bundle glyphs. Rendered over WI-5's
`DiagnosticsUiState`; the viewer shell itself is WI-6b.

## Scope of audit

Eight new files, all under
`android/app/src/{main,androidTest}/kotlin/com/vreader/app/diagnostics/ui/`:
`DiagnosticsLogRow.kt`, `DiagnosticsLevelStyle.kt`, `DiagnosticsFilterBar.kt`,
`DiagnosticsFooter.kt`, `DiagnosticsIcons.kt` and the three matching
`*Test.kt` connected suites.

The audit prompt named the feature's one CRITICAL requirement explicitly and
asked the auditor to attack it: can any path put an **unredacted** message
off-device (a second copy affordance, a share sheet, accessibility text,
long-press select-all, text substitution, a caller-supplied payload), and is
the display/clipboard asymmetry actually asserted or would the test pass under
both orderings? It also asked for rule-51 fidelity per token, per-acceptance
test strength, Compose/Kotlin correctness, and edge cases.

Runner: `scripts/run-codex.sh` (rule 53). Sessions —
r1 `019fcfdd-c919-72d3-93b6-8a62b2ea8b40`,
r2 `019fcfee-0ef7-75a3-9598-8b1e2ec08743`,
r3 `019fcffd-09ce-7df3-9250-5addab2c8e70`.

## Round 1 — 0 critical, 2 high, 7 medium, 4 low (block-recommended)

The CRITICAL requirement passed on its own terms: one egress, redacted at it;
no share/upload/second-copy path; the message `Text` is not in a
`SelectionContainer` and is not editable; the asymmetry test would fail both if
the paths were swapped and if the copy silently did nothing (the seeded
clipboard sentinel is what closes the second hole).

Fixed in `cae53a7d`:

- **HIGH — the level chip row could strand a filter off-screen.** The design
  draws a plain flex row; at a large accessibility font scale the trailing
  chips overflow and become unreachable, i.e. a filter the user cannot clear.
  The row now scrolls **on overflow only**, so nothing changes at the designed
  scale, and `everyLevelChipStaysReachableAtALargeFontScale` asserts it at
  `fontScale = 2f`.
- **MEDIUM — active chips had no border.** The design gives the active chip a
  *transparent* 0.5px border, not none: both forms occupy the same box, so a
  chip does not resize the row when it is selected. Now drawn in both states,
  with a `selectingAChipDoesNotResizeIt` height assertion.
- **MEDIUM — the "inactive = outlined" test was fill-only** and would have kept
  passing with the outline deleted. A border-color semantics seam was added and
  asserted (hardened again in round 2 — see below).
- **MEDIUM — the meta line was centered, not baseline-aligned.** Its three
  elements are three different sizes (10.5 / 10 / 9.5sp), so centering left the
  timestamp and level token visibly astride. `alignByBaseline()` on all three.
- **MEDIUM — the clamp assertion had only an upper bound**, so a 1- or 2-line
  clamp passed. Bounded on both sides.
- **MEDIUM — blank/duplicate category chips** would render an unlabelled tap
  target or two identically-tagged chips. Filtered, with a test.
- **LOW — KDoc overstatement.** "No call site can put an unredacted entry on the
  clipboard" is only true of this component's API, not of code that does not
  exist yet; and `ASSERT → ERROR` / `VERBOSE → DEBUG` are the implementer's
  extension of §6.3's `WARN` adjudication, not plan-adjudicated. Both reworded.
- **LOW — edge coverage.** Added ASSERT-dark, VERBOSE, newline-only,
  RTL-with-secret, truncation-sized, and repeated-tap tests.

Accepted with rationale (round 2 agreed both hold — they are design-owned):

- **Sub-48dp touch targets.** The designed chip is ~26dp and the Copy pill
  ~25dp. Growing them changes depicted geometry and the row's vertical rhythm,
  which rule 51 reserves to the design. The whole row is a large tap target for
  expand/collapse, so only the Copy pill is small.
- **White on `#e0826f` in dark (~2.8:1).** The design specifies `#fff` on the
  tinted chip; substituting a color would be self-designed UI.
- **`DiagnosticsLogRowTest.kt` exceeds ~300 lines.** The WI's write-set permits
  exactly three test files, so splitting is not available to this slice.

## Round 2 — 0 critical, 1 high, 1 medium, 2 low (block-recommended)

Round 2 caught a finding round 1 had let stand on a **false premise** — the
class of finding worth the whole gate:

- **HIGH — the Copy glyph.** Round 1 accepted Material's
  `Icons.Outlined.ContentCopy` because `vreader-icons.jsx` has no `Copy` entry
  for `vreader-diagnostics.jsx:295` to resolve. Round 2 checked the *whole*
  bundle and found the glyph committed **twice** —
  `AAGlyph(name = "copy")` (`vreader-annotations-actions.jsx:60`, 24×24, stroke
  1.7, round caps/joins: the pulse icon's exact vocabulary) and `HPCopyGlyph`
  (`vreader-highlight-popover.jsx:413`, a 20×20 variant). So there *was* a
  committed path to transcribe, and the substitution was unjustified.
  `a049a10b` adds `DiagnosticsIcons.Copy` transcribing the 24×24 form; no
  scoped file imports `androidx.compose.material.icons` any more.
- **MEDIUM — the new border seam was still vacuous.** A separate `.border(…)`
  and a separate `.semantics { diagnosticsBorderColor = … }` can be
  half-deleted, leaving every border assertion passing over a chip with no
  outline (and `selectingAChipDoesNotResizeIt` cannot catch it, because a
  Compose border draws inside the bounds and does not affect measurement).
  Replaced by `Modifier.diagnosticsOutline(color, shape)`, which draws and
  publishes in ONE expression, applied to the chips and the Copy pill. Its own
  KDoc states the residual limit: it is an observability seam, not a proof.
- **LOW ×2 — two tests did not do what their names said.** The "4068-byte" test
  `take(4068)`-ed a string that was never that long, so it never reached the
  truncation boundary; it now builds exactly 4068 UTF-8 bytes and asserts the
  size. The newline-only test asserted only the clipboard; it now asserts the
  rendered message first.

## Round 3 — clean

Zero findings at every severity. The auditor verified the glyph transcription
**arc by arc** (all four radius-2 corners terminate correctly and in the right
sweep direction; the rear-page path matches `M5 15V5a2 2 0 012-2h8`; stroke,
caps, joins and viewport correct), confirmed `diagnosticsOutline` materially
closes the deletion gap, confirmed the modifier order at every call site and
that the fill and border semantics land as distinct keys on the node the tests
query, confirmed both test corrections are non-vacuous, and swept the two
fix commits for regressions — none, including no new egress path for an
unredacted message.

Verdict: **ship-as-is**.

## Test evidence (connected, `emulator-5554`, Pixel-class AVD API 35)

Final state, one class per invocation through `scripts/run-android-tests.sh`
(rule 52 — never a bare `gradlew`, never a comma-joined class list):

| Suite | Result |
| --- | --- |
| `DiagnosticsLogRowTest` | `tests="24" failures="0" errors="0"` |
| `DiagnosticsFilterBarTest` | `tests="14" failures="0" errors="0"` |
| `DiagnosticsFooterTest` | `tests="5" failures="0" errors="0"` |
| JVM `*diagnostics*` regression | 307 tests, 0 failures (unchanged from main) |

`RUN-ANDROID-TESTS RESULT: SUCCEEDED` on every run. Raw logs and the three
audit transcripts are in the worktree's `.reports/` (not committed).

## Open items handed to the orchestrator

Neither is this lane's to close:

1. The design bundle references `Icons.Copy` from two surfaces
   (`vreader-diagnostics.jsx:295`, `bilingual-summarize-artboards.jsx:116`)
   without defining it in `vreader-icons.jsx`, while defining the same glyph
   twice under other names. A bundle-hygiene fix, not a `needs-design`.
2. Plan §6.3 adjudicates `WARN`'s treatment but not `ASSERT` or `VERBOSE`. The
   implementation extends the same principle (and the chips' existing level
   sets) and says so in `DiagnosticsLevelStyle.kt`; recording it in §6.3 would
   close the gap in the plan itself.
