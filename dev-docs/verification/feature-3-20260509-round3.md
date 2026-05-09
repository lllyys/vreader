---
kind: feature
id: 3
status_target: DONE
commit_sha: 5e26cc8415d3e7571ed37e0a5d96920927354791
app_version: 3.14.119 (build 228)
date: 2026-05-09
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.4
build_configuration: Debug
backend: bundled DebugFixtures (war-and-peace.txt) in Native TXT mode
result: fail
---

## Summary

Round-3 verification of feature #3 (Manual text highlighting) targeted
the TXT highlight gesture path that round-2 (`feature-3-20260508.md`)
left at `partial`/inconclusive. Now that feature #11 round-4 (this
same session) verified EPUB highlighting end-to-end via the same
long-press → custom-menu → tap-Highlight pattern, we can rule out
CU/menu-wide failure modes and definitively name the TXT path as
broken.

**Result: FAIL.** The TXT Highlight action consistently fires (menu
dismisses cleanly) but nothing persists — no yellow paint on the
selected word, no entry in the Highlights tab. 6/6 attempts across
round-2 (4) and round-3 (2) produce identical "No Highlights" empty
state. Filed as **bug #160 / GH #476** (Reader/* Medium). Per
verify-cron scope, this round files but does not fix.

Status stays `DONE`. VERIFIED is gated on bug #160 fix.

## Acceptance criteria

| Criterion | Slice | Result |
|---|---|---|
| Per-format renderers covered | Cross-ref to #11/#17 | PASS (round-1) |
| 84 unit tests across 14 suites cover data layer | Round-1 cross-ref | PASS |
| Custom 4-item menu structure (Highlight \| Add Note \| Define \| ▶) | Round-2 + this round: long-press on "Genoa" → menu visible with all 4 items | PASS |
| Define sibling action works via gesture | #33 round 2 cross-ref | PASS |
| **TXT Highlight action persists + paints visually** | This round: 2/2 attempts on "Genoa" and "that" → menu dismisses cleanly → NO yellow paint AND NO entry in Highlights tab | **FAIL → bug #160** |
| Cross-format consistency: same gesture works for EPUB | This session: feature #11 round-4 verified EPUB Highlight end-to-end (PASS) | PASS — confirms TXT-specific failure |

## Commands run

```bash
SIM=61149F0E-DC18-4BE2-BB37-52659F1F4F62
# v3.14.119 (commit 5e26cc8) installed from previous feature #11 round-4 iteration.

xcrun simctl terminate $SIM com.vreader.app
xcrun simctl openurl $SIM "vreader-debug://reset"
sleep 2
xcrun simctl openurl $SIM "vreader-debug://seed?fixture=war-and-peace"
sleep 2
xcrun simctl launch $SIM com.vreader.app

# UI driving via computer-use:
# Attempt 1:
#   1. Tap war-and-peace card → reader opens at Chapter I.
#   2. Long-press on "Genoa" in paragraph 1 (mouse_move(361,250) +
#      left_mouse_down + wait 1.2s + left_mouse_up).
#   3. iOS context menu appears with Highlight | Add Note | Define | ▶.
#   4. Tap Highlight at (298, 281) → menu dismisses; selection
#      handles still visible briefly.
#   5. Tap blank area → selection clears. NO yellow background on "Genoa".
#   6. Tap list icon (toolbar) → Contents tab → tap Highlights tab.
#      → "No Highlights" empty state.
#
# Attempt 2 (different word, different coords):
#   7. Long-press on word "that" between "tell me" and "this means"
#      (mouse_move(400,290) + left_mouse_down + wait 1.3s +
#      left_mouse_up). Menu appears.
#   8. Tap Highlight at (323, 313) → menu dismisses.
#   9. Tap blank area; menu/selection clears. NO yellow background on "that".
#   10. Re-open Highlights tab → still "No Highlights".

# Capture evidence
xcrun simctl io $SIM screenshot \
  dev-docs/verification/artifacts/bug-160-txt-highlight-no-paint-20260509.png
xcrun simctl io $SIM screenshot \
  dev-docs/verification/artifacts/bug-160-txt-highlight-tab-empty-20260509.png
```

## Observations

- **Bug is TXT-Highlight-action-specific.** Three rule-outs:
  1. EPUB Highlight via same gesture pattern works (feature #11
     round-4 this session).
  2. Define on the same TXT menu works via CU (round-2 cross-ref to
     feature #33 round 2).
  3. Different words at different coordinates produce identical
     outcome (rules out coordinate-mismatch).
- **Code surface** (suspect, not yet code-read in detail).
  `TXTBridgeShared.swift:60-68` defines the Highlight `UIAction`
  whose handler calls `postSelectionNotification(.readerHighlightRequested, ...)`.
  `postSelectionNotification` (lines 21-41) builds a
  `TextSelectionInfo` (with chunkOffset-adjusted UTF-16 range) and
  posts the notification. Observer in
  `ReaderNotificationModifier.swift:48-62` validates the range,
  builds a locator, and calls `highlightCoordinator.create(...)`.
  Failure is somewhere between the UIAction handler firing and the
  `PersistenceActor.addHighlight` call.
- **Possible root causes** (need code-read to confirm):
  1. `chunkOffset` mismatch in chunked-bridge path producing invalid
     global UTF-16 offsets.
  2. `ReaderNotificationModifier` not applied at the right view
     scope for the TXT renderer (observer never registered).
  3. Stale `range` capture if the menu is rebuilt between long-
     press and tap.
  4. iOS 26.4 regression in UIMenu/UIAction notification dispatch.
- **Cross-feature implication**: feature #4 (Add notes) shares the
  same menu and the same notification-post pattern (via
  `.readerAnnotationRequested`); likely affected but not yet
  verified by this round.

## Artifacts

- `dev-docs/verification/artifacts/bug-160-txt-highlight-no-paint-20260509.png`
  — war-and-peace.txt at Chapter I after tap-Highlight on "Genoa";
  word renders with no yellow background.
- `dev-docs/verification/artifacts/bug-160-txt-highlight-tab-empty-20260509.png`
  — Side panel Highlights tab showing "No Highlights" empty state
  immediately after the Highlight tap.

## Verdict

`fail` for feature #3's gesture-driven user-flow slice on TXT.
Round-1's data-layer slice (84 tests) + round-2's menu-structure
slice cover the components in isolation, but the integration gap
between UIAction firing and `PersistenceActor.addHighlight` is
broken. Filed bug #160 / GH #476.

Feature #3 status stays `DONE`; do **not** flip to `VERIFIED` until
bug #160 is fixed. Bug-fix cron will pick up GH #476.
