---
kind: feature
id: 36
status_target: VERIFIED
commit_sha: 263100a8cea4b75ec18154ba52fefd4890d66b4a
app_version: 3.14.151 (build 260)
date: 2026-05-11
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.4
build_configuration: Debug
backend: Project Gutenberg OPDS (https://www.gutenberg.org/ebooks.opds/)
result: pass
---

## Summary

Round-5 device verify of feature #36 (OPDS catalog support) against
merged-main `263100a` (v3.14.151). This run closes the 3 deferred legs
from round-4 (`feature-36-20260511-round4.md`):

1. Per-catalog navigation — **PASS**
2. Download → import round-trip — **PASS**
3. Edit / delete saved catalog — **PASS**

Combined with the 10/12 criteria already passing post-round-4, this
run brings feature #36 to **12/12 acceptance criteria** PASS and flips
the row from `DONE` to `VERIFIED`.

The round-5 run is unblocked by bug #170 (`fix(#529)`, PR #531, shipped
in v3.14.151) which fixed the blank OPDS detail view by replacing
`.task` with `.onAppear` + a fire-once gate, and seeding
`isLoading = true` so the spinner renders on the first frame.

## Acceptance criteria — round-5 outcomes

| Criterion | Round-5 result | Notes |
|---|---|---|
| Add a catalog with Name + URL | pass | Closed in round-4; reused saved Gutenberg row from prior test state. |
| Saved catalog persists across sheet dismiss/reopen | pass | Closed in round-4. |
| Per-catalog navigation (tap row → detail) | **pass** | Tap saved Gutenberg row → `OPDSBrowserView` renders spinner ("Loading catalog..."), then feed loads to navigation title "Project Gutenberg" with 3 entries (Popular / Latest / Random). Screenshot `feature-36-r5-03-popular-final-20260511.png`. |
| Sub-feed drill-down (navigation entry → acquisition feed) | **pass** | Tap "Popular" → spinner with "Popular" title; initial fetch hit network timeout; tap Retry → "All Books" acquisition feed loads with 11+ real Project Gutenberg books (Hegel, Frankenstein, Moby Dick, City of God, Pride & Prejudice, Romeo & Juliet, Crime & Punishment, Alice's Adventures in Wonderland, A Room with a View, Jekyll/Hyde…). Pagination "Load More" row present at bottom. Screenshot `feature-36-r5-04-retry-result-20260511.png`. |
| Error state UI on transient failure | **pass** | Initial Popular fetch timed out → `errorState(_:)` rendered correctly: triangle icon + "Failed to Load Catalog" headline + "Network error: The request timed out." body + "Retry" button. Retry tap re-invoked `loadFeed(url:)` and succeeded. |
| Book entry → acquisition detail view | **pass** | Tap "Alice's Adventures in Wonderland" row → `OPDSBrowserView` showing 2 acquisition variants (each with cover thumbnail + EPUB+MOBI format chips). Tap first variant → `OPDSEntryView` with cover image, title "Alice's Adventures in Wonderland", author "Carroll, Lewis", rights line "Public domain in the USA.", and two prominent action buttons "Download EPUB" + "Download MOBI". Screenshot `feature-36-r5-07-entry-detail-20260511.png`. |
| Download → import round-trip | **pass** | Tap "Download EPUB" → mid-download state, then success state with green check + "Downloaded! Book added to library." (`feature-36-r5-09-download-done-20260511.png`). Backed all the way out (Entry → sub-feed → All Books → Project Gutenberg → OPDS list → dismiss sheet) and confirmed Alice's Adventures in Wonderland appears as an EPUB book row in the Library with cover thumbnail, title, "Lewis Carroll" author, and EPUB tag (`feature-36-r5-15-library-after-dismiss-20260511.png`). End-to-end OPDS → import → Library closes. |
| Edit / delete saved catalog (swipe-to-delete) | **pass** | Swipe-left on the Gutenberg row using a 30-step CGEventPost slow-drag (~750ms total) successfully invokes SwiftUI's swipe action and deletes the row. Catalog list returns to empty state with globe icon + "No OPDS Catalogs" headline + Add Catalog CTA (`feature-36-r5-14-after-swipe-delete-20260511.png`). Round-4's 10-step 200ms drag was too fast (interpreted as tap); the slower primitive resolves it. |
| Form input via paste (Cmd+V) | pass | Closed in round-4. |
| Public OPDS endpoint wire-format reachability | pass | Closed in round-1 (curl probes) + round-4 (live use). |
| Cancel returns from Add form without saving | pass | Closed in round-2 (XCUITest). |
| Empty-state shape (no catalogs) | pass | Closed in round-3 (CU visual) + reconfirmed in round-5 after delete. |

## Why pass, not partial

Round-4 ended at 10/12 with bug #170 blocking per-catalog navigation
+ download/import + (separately) the swipe primitive being too fast
for edit/delete. After:

1. Bug #170 was fixed in PR #531 (lifecycle fix to OPDSBrowserView).
2. A slower 30-step CGEventPost swipe was used for edit/delete.

All 12 acceptance criteria now pass end-to-end against the real
Project Gutenberg OPDS endpoint with a real book actually downloaded
and imported into the library.

## Commands run

```bash
# Activate Simulator (clicks default to whatever app is frontmost,
# so re-activate before each gesture batch).
osascript -e 'tell application "Simulator" to activate'

# AX-tree query for button positions (mac-space coordinates).
osascript <<'OSA' 2>&1
tell application "System Events"
  tell process "Simulator"
    tell window 1
      set output to ""
      set allElems to entire contents
      repeat with e in allElems
        try
          if role of e is "AXButton" then
            set p to position of e
            set s to size of e
            set d to ""
            try; set d to description of e; end try
            set output to output & "BTN pos=" & (item 1 of p) & "," & (item 2 of p) & " sz=" & (item 1 of s) & "x" & (item 2 of s) & " | " & d & "\n"
          end if
        end try
      end repeat
      return output
    end tell
  end tell
end tell
OSA

# Tap "Popular" navigation entry inside Project Gutenberg feed.
swift .claude/skills/sim-drive-fallback/scripts/clickat.swift 626 308

# Tap "Retry" button on errorState.
swift .claude/skills/sim-drive-fallback/scripts/clickat.swift 626 678

# Tap "Alice's Adventures in Wonderland" row.
swift .claude/skills/sim-drive-fallback/scripts/clickat.swift 626 605

# Tap "Download EPUB" button in OPDSEntryView.
swift .claude/skills/sim-drive-fallback/scripts/clickat.swift 626 690

# Back-chevron in NavigationStack (button center at mac coords).
swift .claude/skills/sim-drive-fallback/scripts/clickat.swift 463 210

# Slow swipe-to-delete on Gutenberg row (30 steps × 25ms ≈ 750ms total).
# /tmp/slowswipe.swift is a one-off variant of dragat.swift with more
# intermediate mouseDragged events at longer intervals so iOS's gesture
# recognizer interprets the motion as a swipe rather than a tap.
swift /tmp/slowswipe.swift 810 278 470 278

# Dismiss OPDS sheet via Done button.
swift .claude/skills/sim-drive-fallback/scripts/clickat.swift 487 192

# Capture screenshots for evidence.
xcrun simctl io booted screenshot \
    dev-docs/verification/artifacts/feature-36-r5-NN-<label>-20260511.png
```

## Observations

- **Slower swipe primitive unblocks edit/delete.** Round-4 documented a
  CU-substitute limitation: `dragat.swift` at 10 steps × 20ms = 200ms
  total was interpreted as a tap rather than a swipe. A one-off
  variant with 30 steps × 25ms = ~750ms total + `usleep` between
  mouseDown and the first drag event is correctly recognized as a
  swipe by iOS's gesture recognizer. This pattern should probably be
  added to `sim-drive-fallback` as a dedicated `slowswipe.swift` so
  swipe-to-delete becomes a first-class primitive.
- **AX tree includes content behind sheets.** When OPDS sheet was
  active, the AX `entire contents` query of `window 1` returned BOTH
  the sheet content (Done/+/Gutenberg row) AND the LibraryView buttons
  behind it (Settings/AI Chat/Collections/OPDS Catalogs/Import/More
  toolbar at y=176). This is useful to confirm Library state without
  dismissing the sheet — we observed the Alice book row at
  `pos=425,278 desc="Alice's Adventures in Wonderland, by Lewis Carroll, EPUB format"`
  immediately after the download success state, before backing all
  the way out. Treat AX tree as cross-layer; the visual screenshot is
  the source of truth for what's actually displayed.
- **OPDS detail loads quickly when reachable.** Project Gutenberg root
  feed loads in <1 s; sub-feeds can take ~5-10 s (sometimes timeout).
  The error state + Retry button worked correctly when the initial
  fetch hit a network timeout, confirming the `errorState` branch
  isn't dead code.
- **Frontmost-app gotcha.** `swift clickat.swift` posts CGEvents to
  whatever app is frontmost. When VS Code is in front (the usual case
  during agent-driven verification), clicks land on VS Code, not on
  the Simulator. The fix is `osascript -e 'tell application
  "Simulator" to activate'` before each gesture batch. Worth adding
  to the CU-substitute toolkit prologue or having `clickat.swift`
  re-activate the Simulator itself.

## Artifacts

- `feature-36-r5-01-popular-spinner-20260511.png` — Popular sub-feed loading spinner
- `feature-36-r5-02-popular-loaded-20260511.png` — Project Gutenberg feed loaded
- `feature-36-r5-03-popular-final-20260511.png` — 3 nav entries visible (Popular/Latest/Random)
- `feature-36-r5-04-retry-result-20260511.png` — "All Books" feed after Retry
- `feature-36-r5-05-book-detail-20260511.png` — Alice sub-feed with 2 acquisition variants
- `feature-36-r5-06-alice-loaded-20260511.png` — variant list with cover + format chips
- `feature-36-r5-07-entry-detail-20260511.png` — `OPDSEntryView` for Alice (Download EPUB/MOBI buttons)
- `feature-36-r5-08-download-mid-20260511.png` — mid-download state
- `feature-36-r5-09-download-done-20260511.png` — green check "Downloaded! Book added to library."
- `feature-36-r5-10-back-1-20260511.png` — first back nav attempt (chevron coord miss)
- `feature-36-r5-11-library-with-alice-20260511.png` — Library state captured via AX (sheet still in foreground)
- `feature-36-r5-12-back-to-subfeed-20260511.png` — back to Alice sub-feed
- `feature-36-r5-13-after-3-backs-20260511.png` — back to "All Books" feed
- `feature-36-r5-14-after-swipe-delete-20260511.png` — Gutenberg deleted, empty state shown
- `feature-36-r5-15-library-after-dismiss-20260511.png` — Library after Done — Alice book visible with EPUB tag

## Disposition

Feature #36 flips from **DONE** to **VERIFIED**. GH issue #332 closes
on this run with closure comment citing commit `263100a` + this evidence
file. 12/12 acceptance criteria PASS end-to-end on iPhone 17 Pro Simulator
against live Project Gutenberg OPDS endpoint.

## Cross-references

- `dev-docs/verification/feature-36-20260507.md` — round-1 (parser + curl probes)
- `dev-docs/verification/feature-36-20260508.md` + `feature-36-20260508b.md` — rounds 2 + 3 (UI sheet leg, CU visual)
- `dev-docs/verification/feature-36-20260511-round4.md` — round-4 (attempted deferred legs, filed bug #170)
- `vreader/Views/OPDS/OPDSBrowserView.swift` — fix landed in PR #531 (bug #170)
- `vreader/Views/OPDS/OPDSEntryView.swift` — book detail + download
- `vreader/Views/OPDS/OPDSCatalogListView.swift` — catalog list + swipe-to-delete
- `vreader/Views/LibraryView.swift` — OPDS sheet entry point
- GH #332 — feature mirror
