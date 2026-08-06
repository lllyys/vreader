---
branch: fix/issue-368-azw3-display-control
threadId: 019fd49b-201b-7201-9bba-8f6886446fe2
rounds: 2
final_verdict: block-recommended
date: 2026-08-06
---

# Gate-4 audit — bug #368 (AZW3 has no Display (Aa) control)

Auditor: Codex (`scripts/run-codex.sh`, rule 53), read-only sandbox, independent of the
implementing session (rule 48 author/auditor separation).

| Round | threadId | Findings | Outcome |
| --- | --- | --- | --- |
| 1 | `019fd48e-de65-7b71-a750-2f54b59b9449` | 0 Critical, 0 High, **2 Medium**, 2 Low | changes requested |
| 2 | `019fd49b-201b-7201-9bba-8f6886446fe2` | 0 new findings; Medium-2 upheld | **block** |

Raw transcripts: `.reports/audit-r1.txt`, `.reports/audit-r2.txt` (worktree-local, not committed).

## Round 1

**Medium — the Display sheet could show and persist fabricated defaults.**
`Azw3ReaderActivity` collected `ReaderSettingsStore.settings` with `initialValue = ReaderSettings()`,
so a user with stored non-default settings who tapped Display inside the pre-emission window would
see Paper/18sp — and a slider dragged against that lying display would persist a value derived from
it. **FIXED**: the Activity now collects into a nullable `settingsOrNull` and renders
`ReaderSettingsSheet` **only** from a real emission (the EPUB `DisplaySettingsHost` posture). The
chrome + body keep their pre-#368 defaults-seeded frame — that flash predates this fix (the chrome
already collected with a defaults seed) and withholding the whole AZW3 reader on it would change how
every Kindle book opens. Round 2 accepted that scope line explicitly.

**Medium — the Layout (Paged/Scroll) toggle is inert while reading AZW3.** See "Open finding" below.

**Low — `rememberSaveable` restored a transient modal as open** after rotation / process death,
unlike both established hosts. **FIXED**: plain `remember(bookKey)`, matching TXT.

**Low — the new connected test file was 390 lines**, over the ~300 guideline. **FIXED**: the
reader-stack drain and the live-stylesheet probe moved to `Azw3DisplayProbeSupport.kt`
(test 258 lines, support 177).

Round 1 additionally confirmed, on its own reading of the code: the store → Flow → WebView wiring is
correct end to end; two collectors of the same DataStore-derived Flow are safe; the `nextSeq()`
stamping and process-scope launches match the store contract and the TXT/EPUB precedent exactly; the
required (non-nullable) `onOpenDisplay` is the right call because the capability is unconditional;
removing `Azw3BottomChrome`'s old both-callbacks-null early return is correct; `ToolbarDisplayButton`
is behaviour-preserving for EPUB/TXT/MD (modifier order, tag, typography, no added semantics); and the
connected test cannot false-green (hard fixture assertions rather than `assumeTrue`, fingerprint-checked
Activity identity, fail-closed `singleOrNull()` on the sentinel, fresh per-call result holders).

## Round 2

No new defects. All three fixed findings confirmed resolved, and the four re-audit questions answered
clean (`settingsOrNull ?: ReaderSettings()` cannot populate the sheet; a tap before the first emission
simply shows the sheet once real settings arrive; `remember(bookKey)` cannot survive a book change;
the probe extraction changes no timeouts, lifecycle stages, WebView traversal, or CSS equality
semantics; rule-22 comments accurate).

## Open finding — the reason this is `block-recommended`

**Medium — `Azw3ReaderActivity`: the designed Display sheet's Layout (Paged/Scroll) toggle is inert
for the book being read.** foliate-js owns AZW3 pagination outright, so AZW3 is always paged and
`foliateDisplayCss()` deliberately ignores `layout`. Wiring `onLayout` to the store persists a real,
global preference that the EPUB/TXT/MD hosts DO honour — but from inside a Kindle book the control
does nothing, which is the project's no-dead-controls prohibition.

Both available remedies are out of this lane:

- **Making foliate honour scrolled flow** is reachable in principle (`readerAPI.setLayout({flow})` →
  `renderer.setAttribute('flow', …)` exists in the bundle) but would change AZW3 pagination,
  locator/position mapping, the page-turn tap zones, and feature #138's windowed-pagination
  assumptions. That is a feature-workflow item with its own Gate-5, not a bug fix.
- **Hiding or dimming the toggle for AZW3** is an uncommitted UI variant — prohibited by rule 51.
  Verified directly rather than assumed: `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx:112-134`
  renders the Layout segmented control with selected/unselected states only. **No disabled or
  unavailable state is designed**, so there is nothing committed to apply.

The lane argued for shipping the five working controls with the sixth filed as a tracked blocker,
citing bug #344 (the bilingual sheet's dead "Sentence" granularity). Round 2 checked that row and
showed the lane had mis-cited it: #344 was marked **`BLOCKED: needs-design (#1646)`** and shipped only
after the designed disabled state (S-C, 45% opacity + info footnote) landed. That precedent supports
blocking, and rule 51's workflow says the same — stop the slice, file, mark the parent row blocked.
The slices are not separable in code: the sheet cannot ship without the toggle, because removing it
would itself be the prohibited per-host variant.

**Required before merge** (orchestrator-owned surfaces — a lane may not run `gh` or edit trackers):

1. File `Design needed: AZW3 capability state for the Display sheet's Layout toggle` with labels
   `enhancement` + `needs-design`, referencing `Refs #368`, and listing the states the design must
   cover (available/selected, and the unavailable treatment for a host whose pagination is engine-owned).
2. Cite that issue number on the bug #368 row and mark it `BLOCKED: needs-design (#<N>)`.
3. Resume this branch once the design lands — the implementation, its tests and this audit are complete
   and green; only the toggle's designed treatment is missing.
