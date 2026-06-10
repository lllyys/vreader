---
kind: feature
id: 53
status_target: VERIFIED
commit_sha: 8cab12a4574304831666decf343ffc477943ae31
app_version: 3.27.25 (build 439)
date: 2026-05-18
verifier: claude (verify-cron)
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.4
build_configuration: Debug
backend: n/a (DebugBridge + --seed-md-toc launch fixture)
result: partial
---

# Feature #53 round-8 — MD-format device verification (scroll mode)

Round-7 (`feature-53-20260518-round7.md`) attempted the **MD** slice and
concluded criteria (a)/(b) were "BLOCKED" — filing Bug #218 / GH #843. That
conclusion was **retracted** (see round-7's `## CORRECTION`): round-7 ran with
`readerEPUBLayout=paged` lingering from Bug #215's repro, so the MD book opened
in paged mode (`NativeTextPagedView`), which has no `TXTTextViewBridge` and so
no selection→popover producer. Bug #218 was reclassified a DUPLICATE of
Bug #215 (MD paged-mode layout, `BLOCKED: needs-design #842`).

This round re-runs the MD slice in **scroll mode** with the layout explicitly
controlled (`--reader-default-layout=scroll`). MD scroll mode routes body text
through `TXTTextViewBridge` — the same bridge TXT uses — so the #53
tap-on-highlight path should behave identically to the round-4 TXT slice.

## Scope

MD format, **scroll mode**, criteria (a)/(b)/(d), using the `--seed-md-toc`
TestSeeder launch fixture ("Test Markdown TOC"). Verification only; no code
changed.

## Acceptance criteria

| # | Criterion | Result | Observed |
|---|-----------|--------|----------|
| (a) | Tapping a highlighted word shows a menu with at minimum a Delete option | **PASS** | Precondition established first: long-pressed the MD body word "document" → the feature-#60 `SelectionPopover` appeared (4 colour swatches + Note / Translate / Ask AI / Read) → tapped the yellow swatch → DebugBridge `highlightCount` 0→1, yellow background painted on "document". Then a single tap on the highlighted word surfaced the inline **"Delete Highlight"** menu (red/destructive style) anchored below the word. Reproduced 2×. |
| (b) | Delete removes the highlight visually and from persistence | **PASS** | Tapping "Delete Highlight" removed the yellow paint from "document" (visual) AND DebugBridge `highlightCount` went 1→0 (persistence). Reproduced 2×. |
| (c) | Consistent across all 5 formats | **PARTIAL** | 3/5 verified — TXT (round-4) + EPUB (round-6) + **MD-scroll (this round)** pass. PDF not exercised (`DebugFixtureCatalog` ships no PDF fixture and there is no `--seed-pdf` launch arg — harness gap, not a product defect). Foliate (AZW3/MOBI) gated on Bug #199 / GH #733 (inline-menu consumer wiring). |
| (d) | Tapping non-highlighted text preserves existing scroll/chrome-toggle behavior | **PASS** | Tapped non-highlighted MD body text (words on the "Content for the first chapter…" / "tests H2 heading extraction" lines) → **no #53 inline menu appeared**; the reader chrome toggled normally (hidden ↔ visible). Reproduced 2×. |

`result: partial` — criteria (a)/(b)/(d) for MD all **PASS**; criterion (c)
remains open (PDF + Foliate). Feature #53 stays `DONE`. Same round shape as
round-4 (TXT slice) and round-6 (EPUB slice): the format slice fully passes,
the all-5-formats criterion stays incomplete.

## Commands run

```bash
SIM=61149F0E-DC18-4BE2-BB37-52659F1F4F62   # iPhone 17 Pro, iOS 26.4

# merged-main v3.27.25 build 439 (8cab12a) already installed (preserve data)
xcrun simctl terminate "$SIM" com.vreader.app
xcrun simctl launch    "$SIM" com.vreader.app \
  --uitesting --seed-md-toc --reader-default-layout=scroll

# UI (computer-use): open "Test Markdown TOC"
#   → confirmed SCROLL mode visually: "0%" scrubber, no "Page X of Y" indicator
xcrun simctl openurl "$SIM" "vreader-debug://settle?token=r8ready"
xcrun simctl openurl "$SIM" "vreader-debug://snapshot?dest=f53r8-baseline.json"
#   → format: md, highlightCount: 0, renderPhase: idle

# UI: long-press body word "document" → SelectionPopover → tap yellow swatch
xcrun simctl openurl "$SIM" "vreader-debug://snapshot?dest=f53r8-after-create.json"
#   → highlightCount: 1   (MD-scroll highlight CREATION works)

# UI: tap the highlighted "document" → inline "Delete Highlight" menu → tap it
xcrun simctl openurl "$SIM" "vreader-debug://snapshot?dest=f53r8-after-delete.json"
#   → highlightCount: 0   (criterion b — persistence removal)

# UI: tap non-highlighted body text → no menu, chrome toggles (criterion d)

xcrun simctl io "$SIM" screenshot \
  dev-docs/verification/artifacts/feature-53-r8-md-scroll-*-20260518.png
```

## Observations

- **Scroll mode confirmed before any gesture.** The reader opened with a "0%"
  progress scrubber and no "Page X of Y" page indicator — the scroll-mode
  signature. Round-7's confound (paged mode lingering from Bug #215) is
  eliminated by `--reader-default-layout=scroll`.
- **MD scroll mode inherits the TXT path verbatim.** `MDReaderContainerView`
  routes body text through `TXTTextViewBridge` (`MDReaderContainerView.swift:329`)
  — the identical bridge + coordinator the round-4 TXT slice verified. So the
  #53 tap-on-highlight presenter (`UIKitHighlightActionPresenter` +
  `HighlightCoordinator.handleTapAction`, WI-2/WI-2b) and the feature-#60
  `SelectionPopover` producer are both inherited for free. All three criteria
  behaved identically to the TXT slice.
- **Bug #218 confirmed a misfile.** Round-7's "MD highlight creation has no
  working UI affordance" is disproven — creation works (the SelectionPopover
  appears; `highlightCount` 0→1). #218 was reclassified DUPLICATE of Bug #215
  by the bugfix cron; this round is the independent re-confirmation.
- **Criterion (c) is now 3/5.** Two slices remain, unchanged from round-7:
  - **PDF** — no DebugBridge PDF fixture and no `--seed-pdf` launch arg; the
    PDF slice cannot be device-exercised without a harness addition. This is a
    harness gap, not a product defect.
  - **Foliate (AZW3/MOBI)** — gated on Bug #199 / GH #733 (the AZW3 reader
    fires `.readerHighlightTapped` but the inline-menu consumer wiring is a
    tracked follow-up).
- **MD paged mode was deliberately not exercised.** MD's *paged* renderer
  (`NativeTextPagedView`) has no selection producer and no tap-zone overlay —
  a known facet of Bug #215 (`BLOCKED: needs-design #842`). #53's criterion (c)
  "all 5 formats" is a per-format contract; MD-the-format is satisfied by its
  default (scroll) renderer. Whether #53 must also hold in MD paged mode is
  folded into Bug #215's #842 design work — not a separate #53 gap.
- Verification-only round: no bug discovered, no code changed.

## Artifacts

- `dev-docs/verification/artifacts/feature-53-r8-md-scroll-selectionpopover-20260518.png`
  — long-press on MD body text surfaces the feature-#60 `SelectionPopover`
  (highlight-creation affordance) in scroll mode.
- `dev-docs/verification/artifacts/feature-53-r8-md-scroll-highlight-rendered-20260518.png`
  — yellow highlight painted on the word "document" after tapping the yellow
  swatch.
- `dev-docs/verification/artifacts/feature-53-r8-md-scroll-delete-highlight-menu-20260518.png`
  — criterion (a): single-tapping the highlighted word surfaces the inline
  "Delete Highlight" menu.
- `dev-docs/verification/artifacts/feature-53-r8-md-scroll-after-delete-20260518.png`
  — criterion (b): the highlight is gone after tapping Delete (`highlightCount`
  1→0).
- `dev-docs/verification/artifacts/feature-53-r8-md-scroll-normal-tap-no-menu-20260518.png`
  — criterion (d): tapping non-highlighted body text shows no menu and toggles
  the reader chrome normally.

## Outcome

Feature #53 stays **DONE**. The MD slice of criterion (c) — left "blocked" by
round-7's confounded run — is now **PASS** in scroll mode (criteria a/b/d all
reproduced 2×). Criterion (c) is 3/5: TXT (round-4) + EPUB (round-6) +
MD-scroll (round-8) verified; PDF (harness gap — no fixture) and Foliate
(Bug #199 / GH #733) remain. The `VERIFIED` flip is gated only on those two.
