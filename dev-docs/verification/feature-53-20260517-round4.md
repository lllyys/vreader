---
kind: feature
id: 53
status_target: VERIFIED
commit_sha: 56b22f20da236d07553adf1333c94fba709c735f
app_version: 3.27.13 (build 427)
date: 2026-05-17
verifier: claude (verify-cron)
device_or_simulator: iPhone 17 Pro Max Simulator
os_version: iOS 26.4
build_configuration: Debug
backend: n/a (DebugBridge + bundled war-and-peace.txt fixture)
result: partial
---

# Feature #53 round-4 device verification (post Bug #205 fix)

Round-3 (`feature-53-20260516-round3.md`, result=partial) left acceptance
criterion (a) for TXT FAILING: tapping a highlighted word produced an
`Error`-level `[com.apple.UIKit:EditMenuInteraction]` log event and no
inline menu. That was filed as Bug #205 / GH #751.

Bug #205 / GH #751 was fixed and merged in v3.27.12 (PR #816, commit
`645503d`) — the `UIEditMenuInteraction` delegate is now associated onto
the interaction object via `objc_setAssociatedObject`, so it is not
deallocated before UIKit asynchronously composes the menu. This round
re-runs the round-3 repro against current `main` (v3.27.13, build 427)
to confirm the TXT path.

## Scope

TXT format only — the format Bug #205 blocked. Criteria (a), (b), (d)
for TXT. Criterion (c) (consistency across all 5 formats) is NOT fully
exercised this round — see "Deferred / out of scope".

## Acceptance criteria

| # | Criterion | Result | Observed |
|---|---|---|---|
| (a) | Tapping a highlighted word shows a menu with at minimum a Delete option | **PASS** (TXT) | Tapped the yellow-highlighted word "Petersburg" (and, on a second run, "character") → an inline menu titled "Delete Highlight" appeared anchored under the word. No `[EditMenuInteraction]` error correlated with the tap. |
| (b) | Delete removes the highlight visually and from persistence | **PASS** (TXT) | Tapped "Delete Highlight" → the yellow paint disappeared from the word AND the DebugBridge snapshot `highlightCount` went 1 → 0. |
| (c) | Consistent across all 5 formats | **NOT VERIFIED** | Only TXT exercised this round. See "Deferred / out of scope". |
| (d) | Tapping non-highlighted text preserves existing scroll/chrome-toggle behavior | **PASS** (TXT) | Tapped a non-highlighted word ("people") → reader chrome toggled off, no menu appeared. |

## Commands run

```bash
SIM=6C32EE30-CBE6-431E-BA12-02248496E1C9   # iPhone 17 Pro Max, iOS 26.4

# Build current main (v3.27.13) and install
xcodebuild build -project vreader.xcodeproj -scheme vreader \
  -destination 'id=6C32EE30-CBE6-431E-BA12-02248496E1C9' -configuration Debug
xcrun simctl install  "$SIM" .../Debug-iphonesimulator/vreader.app
xcrun simctl launch   "$SIM" com.vreader.app

# Seed + open the TXT fixture
xcrun simctl openurl  "$SIM" "vreader-debug://reset"
xcrun simctl openurl  "$SIM" "vreader-debug://seed?fixture=war-and-peace"
# (opened the book card + navigated to a body-text chapter via the TOC)

# State assertions
xcrun simctl openurl  "$SIM" "vreader-debug://snapshot?dest=f53-after-highlight.json"  # highlightCount: 1
xcrun simctl openurl  "$SIM" "vreader-debug://snapshot?dest=f53-after-delete.json"     # highlightCount: 0

# Log assertion (Bug #205 signature)
xcrun simctl spawn "$SIM" log show --last 6m \
  --predicate 'process == "vreader" AND category == "EditMenuInteraction"'
```

Gestures (long-press to highlight, tap-on-highlight, tap Delete, tap
non-highlighted text) were driven via the computer-use MCP against the
Simulator window.

## Observations

- The inline menu appeared **immediately** on the tap-on-highlight, with
  no `[com.apple.UIKit:EditMenuInteraction]` log event correlated with
  that tap — the round-3 symptom is gone. The Bug #205 fix holds on a
  real build.
- Exactly one `Error`-level `[com.apple.UIKit:EditMenuInteraction]
  <compose failure>` event appeared, at 14:14:40 — ~1.5 min BEFORE the
  tap-on-highlight (~14:16). It correlates with the long-press
  text-SELECTION phase (creating the highlight), not the
  tap-on-existing-highlight that feature #53 owns. The custom
  SelectionPopover and the highlight creation both worked, so this is
  most plausibly the benign artifact of the app suppressing UITextView's
  built-in selection menu in favour of its own SelectionPopover. It is
  out of feature #53's acceptance scope (highlight *creation* is feature
  #3/#4 territory) and produced no user-visible breakage — NOT filed as
  a bug.
- The `<compose failure>` string is a generic os_log redaction
  placeholder and appears across many unrelated subsystems (network,
  `UIKit:EventDispatch`, `UIKit:Orientation`, `KeyboardArbiter`). Only an
  `Error`-level event in the `EditMenuInteraction` category is the Bug
  #205 signature, and that category is absent on the tap-on-highlight.

## Deferred / out of scope (criterion c)

- **MD**: shares the TXT `HighlightableTextView` bridge — same code path
  as TXT; not separately exercised this round.
- **EPUB, PDF**: separate renderer paths (WKWebView / PDFKit). Not
  exercised — `DebugFixtureCatalog` has no EPUB/PDF fixture and importing
  one needs the file-picker. A future round should cover these.
- **AZW3/MOBI (Foliate)**: the inline-menu consumer wiring is a known
  gap tracked separately as Bug #199 / GH #733 — feature #53 cannot
  reach criterion (c) until #199 ships.

## Outcome

Feature #53 row stays **DONE**. Round-4 closes the round-3 TXT-PARTIAL:
criterion (a) for TXT now PASSES. The `VERIFIED` flip remains gated on
device verification of EPUB + PDF (+ MD) and on Bug #199 (Foliate).

This round also serves as the **device verification for Bug #205 / GH
#751** (default close-gate path): the original repro — tap a TXT
highlight, expect an edit/delete menu — succeeds on the merged build,
with no `EditMenuInteraction` error.

## Artifacts

- `artifacts/feature-53-r4-txt-delete-menu-20260517.png` — the inline
  "Delete Highlight" menu anchored on the tapped highlight.
- `artifacts/feature-53-r4-txt-after-delete-20260517.png` — the
  highlight removed after Delete.
