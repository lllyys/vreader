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
backend: n/a (DebugBridge + mini-azw3 fixture)
result: partial
---

# Feature #53 round-9 — Foliate (AZW3/MOBI) device verification

Round-8 (`feature-53-20260518-round8.md`) verified the MD-scroll slice and left
criterion (c) at 3/5 — "PDF + Foliate (Bug #199) remain." Bug #199 / GH #733
(the Foliate inline-menu consumer wiring) has since shipped to `main` (status
`FIXED`, `awaiting-device-verification`), so the Foliate gate is lifted. This
round verifies the **Foliate (AZW3/MOBI)** format slice — and doubles as the
device-verification close-gate for Bug #199.

## Scope

AZW3/MOBI (Foliate) format, criteria (a)/(b)/(d), using the `mini-azw3`
DebugBridge fixture ("The Masque of the Red Death", PG #1064). Verification
only; no code changed.

## Acceptance criteria

| # | Criterion | Result | Observed |
|---|-----------|--------|----------|
| (a) | Tapping a highlighted word shows a menu with at minimum a Delete option | **PASS** | Precondition: long-pressed the AZW3 body word "ebook" → the reader's "Text Selection" card surfaced with a **Highlight** button → tapped it → DebugBridge `highlightCount` 0→1, yellow paint rendered on "ebook". Then a single tap on the highlighted word surfaced the inline **"Delete Highlight"** menu. Reproduced 2×. *(Observation: the menu anchors at the reader view's top-left origin, not adjacent to the highlight — the known `sourceRect == .zero` limitation documented in Bug #199's row. Criterion (a) requires only that the menu appear, which it does.)* |
| (b) | Delete removes the highlight visually and from persistence | **PASS** | Tapping "Delete Highlight" removed the yellow paint from "ebook" (visual — Bug #199's fix evaluates `removeAnnotationJS` for immediate removal) AND DebugBridge `highlightCount` went 1→0 (persistence). Reproduced 2×. |
| (c) | Consistent across all 5 formats | **PARTIAL** | 4/5 verified — TXT (round-4) + EPUB (round-6) + MD-scroll (round-8) + **Foliate/AZW3 (this round)** pass. Only PDF remains, blocked on the harness gap (`DebugFixtureCatalog` ships no PDF fixture, no `--seed-pdf` launch arg). |
| (d) | Tapping non-highlighted text preserves existing scroll/chrome-toggle behavior | **PASS** | Tapped non-highlighted AZW3 body text ("United" in the license paragraph) → **no #53 menu appeared**; the reader chrome toggled normally (hidden ↔ visible). Reproduced 2×. |

`result: partial` — criteria (a)/(b)/(d) for the Foliate format all **PASS**;
criterion (c) is 4/5 (PDF remains). Feature #53 stays `DONE`. Same round shape
as round-4 (TXT), round-6 (EPUB), round-8 (MD-scroll): the format slice fully
passes, the all-5-formats criterion stays incomplete.

## Also: Bug #199 / GH #733 close-gate

This round is the device-verification close-gate for **Bug #199** ("Foliate
(AZW3/MOBI) highlight tap posts `.readerHighlightTapped` but no inline menu
surfaces"). The fix shipped 2026-05-16 (branch
`fix/issue-733-foliate-highlight-tap-consumer`, status `FIXED`). Round-9
confirms the fix on the live `FoliateSpikeView` path: tapping an AZW3 highlight
surfaces the inline "Delete Highlight" menu and Delete removes the highlight
(visual + persistence) — the Bug #199 symptom is gone. GH #733 closed.

## Commands run

```bash
SIM=61149F0E-DC18-4BE2-BB37-52659F1F4F62   # iPhone 17 Pro, iOS 26.4

# merged-main v3.27.25 build 439 (8cab12a) already installed
xcrun simctl terminate "$SIM" com.vreader.app
xcrun simctl launch    "$SIM" com.vreader.app --uitesting
xcrun simctl openurl   "$SIM" "vreader-debug://reset"
xcrun simctl openurl   "$SIM" "vreader-debug://seed?fixture=mini-azw3"
xcrun simctl openurl   "$SIM" "vreader-debug://open?bookId=azw3%3Afadbaa44...%3A128650"
xcrun simctl openurl   "$SIM" "vreader-debug://settle?token=r9ready"
xcrun simctl openurl   "$SIM" "vreader-debug://snapshot?dest=f53r9-open2.json"
#   → format: azw3, highlightCount: 0, renderPhase: idle

# UI (computer-use): long-press body word "ebook" → "Text Selection" card → tap Highlight
xcrun simctl openurl   "$SIM" "vreader-debug://snapshot?dest=f53r9-after-create.json"
#   → highlightCount: 1   (AZW3 highlight creation works)

# UI: tap the highlighted "ebook" → inline "Delete Highlight" menu → tap it
xcrun simctl openurl   "$SIM" "vreader-debug://snapshot?dest=f53r9-after-delete.json"
#   → highlightCount: 0   (criterion b — persistence removal)

# UI: tap non-highlighted body text → no menu, chrome toggles (criterion d)

xcrun simctl io "$SIM" screenshot \
  dev-docs/verification/artifacts/feature-53-r9-azw3-*-20260518.png
```

## Observations

- The Foliate/AZW3 reader uses a different selection UI than the TXT/MD/EPUB
  `HighlightableTextView` path: a long-press surfaces a "Text Selection" card
  with a **Highlight** button (the AZW3 "selection capture + CFI anchoring"
  flow), not the feature-#60 `SelectionPopover`. Highlight creation works.
- The #53 tap-on-highlight path on Foliate is the WI-5 producer
  (`.readerHighlightTapped` via `FoliateHighlightTapResolver`) plus the Bug #199
  consumer (`FoliateHighlightTapHandlerModifier` → `UIKitHighlightActionPresenter`).
  Round-9 confirms both halves work end-to-end on the live `FoliateSpikeView`.
- **Known limitation (not a #53 defect, NOT newly discovered):** the inline
  menu anchors at the reader view's top-left origin, not at the tapped
  highlight, because `foliate-host.js` doesn't forward annotation rects so
  `sourceRect` stays `.zero`. This is already documented in Bug #199's row as a
  "separate enhancement" follow-up. It does not violate #53 criterion (a) ("a
  menu ... appears"). Not filed as a new bug (already documented); recommend
  triage promote the follow-up to its own tracked row if a positioned menu is
  wanted. Not verified against this round (verify-cron scope).
- Criterion (c) is now 4/5. The only remaining slice is **PDF**, blocked on the
  long-standing harness gap (no PDF fixture in `DebugFixtureCatalog`, no
  `--seed-pdf` launch arg) — a harness addition, not a product defect.
- Verification-only round: no bug discovered, no code changed.

## Artifacts

- `dev-docs/verification/artifacts/feature-53-r9-azw3-selection-highlight-affordance-20260518.png`
  — long-press on AZW3 body text surfaces the "Text Selection" card with the
  Highlight button.
- `dev-docs/verification/artifacts/feature-53-r9-azw3-highlight-rendered-20260518.png`
  — yellow highlight painted on "ebook".
- `dev-docs/verification/artifacts/feature-53-r9-azw3-delete-highlight-menu-20260518.png`
  — criterion (a): the inline "Delete Highlight" menu (anchored at the view
  origin per the known `sourceRect == .zero` limitation).
- `dev-docs/verification/artifacts/feature-53-r9-azw3-after-delete-20260518.png`
  — criterion (b): the highlight is gone after Delete (`highlightCount` 1→0).
- `dev-docs/verification/artifacts/feature-53-r9-azw3-normal-tap-no-menu-20260518.png`
  — criterion (d): tapping non-highlighted text shows no menu and toggles the
  reader chrome.

## Outcome

Feature #53 stays **DONE**. The Foliate (AZW3/MOBI) slice of criterion (c) is
**PASS** (criteria a/b/d all reproduced 2×). Criterion (c) is now 4/5: TXT
(round-4) + EPUB (round-6) + MD-scroll (round-8) + Foliate (round-9) verified;
only PDF remains (harness gap — no fixture). The `VERIFIED` flip is gated
solely on the PDF slice. This round also completed the Bug #199 / GH #733
device-verification close-gate.
