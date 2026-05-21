---
branch: fix/issue-1078-toc-sheet-current-chapter
threadId: 019e480e-abd0-7931-9f06-5b14e1f82eed
rounds: 1
final_verdict: follow-up-recommended
date: 2026-05-21
---

# Codex Gate-4 Audit — Bug #248 / GH #1078

**Branch**: `fix/issue-1078-toc-sheet-current-chapter`
**Base**: `c030f62f` (v3.38.38)
**Implementation HEAD audited**: `5a79c13c`
**Codex thread**: `019e480e-abd0-7931-9f06-5b14e1f82eed`
**Date**: 2026-05-21
**Verdict**: `follow-up-recommended`

## What was audited

The fix restoring the TOC sheet's auto-scroll-to-current-chapter capability
(dropped by feature #62 WI-5 when it replaced the legacy `TOCListView` with
`TOCSheet`). Diff captured at `/tmp/issue-1078-diff.txt`; Codex read it plus the
full source files and the design jsx in a read-only sandbox.

- `TOCSheet.tocEntryList`: `ScrollViewReader` + per-row `.id(entry.id)` +
  `.task(id: currentChapterScrollTarget)` retry loop (100/300/600 ms,
  `proxy.scrollTo(target, anchor: .center)`).
- `TOCSheet+Support`: `currentChapterScrollTarget: String?` + DEBUG hook.
- `TOCContentsRow`: extracted styling decision into a `Style` value + DEBUG
  `styleForTesting` hook (pure refactor of the existing inline styling).
- 8 new `TOCSheetTests`.

## Findings

### Medium — unit tests don't exercise the live `proxy.scrollTo`

The new tests pin the derived target id (`currentChapterScrollTarget`) and the
styling decision (`StyleProbe`), but the actual scroll lives in the SwiftUI
`.task` + `proxy.scrollTo(...)` call, which a unit test can't drive. If someone
later removes the `.task(id:)` or attaches it to the wrong subtree, the unit
tests still pass.

**Disposition: ACCEPTED.** SwiftUI `ScrollViewReader.scrollTo` is not
unit-testable (the proxy only exists inside a live render tree). Per rule 47
Gate 5, scroll behavior is verified at the device/integration tier — the
Phase 6a in-sim verification directly observes the current chapter centered in
the visible TOC after opening the sheet (evidence in this PR + the bug row's
verification note). The unit layer pins everything that *is* unit-testable: the
target-id resolution (the input to `scrollTo`) and the styling decision. This
matches the precedent — the legacy `TOCListView` scroll was likewise
device-verified, not unit-tested.

### Low — light-mode current-row tint is 0.06 in code vs 0.08 in the design jsx

`TOCContentsRow` uses `accentColor.opacity(theme.isDark ? 0.12 : 0.06)`; the
design `vreader-panels.jsx` line 323 specifies `rgba(140,47,47,0.08)` for the
light current-row background.

**Disposition: ACCEPTED (out of scope for this bug).** Codex explicitly
confirmed this branch did NOT introduce the drift — the pre-existing inline
styling (shipped by feature #62 WI-3) already used `0.06`, and this fix's
refactor preserved it byte-for-byte. Changing it here would be a drive-by edit
outside Bug #248's scope (auto-scroll + the already-correct accent+bold
highlight). The `0.06`-vs-`0.08` reconciliation is a separate design-fidelity
cleanup, not a regression this PR caused.

## Codex's positive confirmations (no findings)

- `ScrollViewReader` is the right mechanism; `.task(id: currentChapterScrollTarget)`
  is the right key (re-fires when the active chapter changes while the sheet is
  open).
- Cancellation handled correctly: `.task(id:)` cancels on identity change /
  disappearance, `Task.sleep` is cancellation-aware, the loop exits on
  `Task.isCancelled`.
- Stable `TOCEntry.id` (not raw index) is the better scroll key; production TOC
  builders feed `sequenceIndex` into `TOCEntry.id`, mitigating duplicate-id risk
  at the model layer.
- The row-style refactor preserves the prior rendering: same corner radius, same
  fill application, same foreground + weight mapping. `style.background != Color.clear`
  is a sound "has tint" check (DEBUG-only probe; `Style.make` emits exactly
  `Color.clear` or the accent tint).
- No Rule 51 violation — no new UI chrome invented; only restored behavior plus
  the existing (designed) highlight treatment.
- Swift 6 / @MainActor: no blocker. Touched files stay under the ~300-line limit.

## Gate-4 acceptance

Zero open Critical/High/Medium **must-fix** findings. The one Medium is a
test-tier observation satisfied by Gate-5 device verification; the one Low is
pre-existing and out of scope. Gate 4 passes — proceed to test gate + verify.
