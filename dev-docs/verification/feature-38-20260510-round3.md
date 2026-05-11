---
kind: feature
id: 38
status_target: DONE
commit_sha: 41067e5
app_version: 3.14.123 (build 232)
date: 2026-05-10
verifier: claude
device_or_simulator: iPhone 17 Simulator
os_version: iOS 26.4
build_configuration: Debug
backend: bundled DebugFixtures (mini-epub3.epub)
result: partial
---

## Summary

Round-3 verification of feature #38 (Hierarchical/tree TOC display) on
merged-main `41067e5` (v3.14.123, build 232). Closes the **tap-to-navigate**
slice that rounds 1 (2026-05-07) and 2 (2026-05-09) had deferred. Hierarchical
indent rendering (level ≥ 1) remains structurally blocked on bundled fixtures
— same as round-2 finding.

**Net change:** of the two UI-driven legs deferred from round-1, one is now
PASS (tap-entry → navigate). The other (visual-hierarchy render at level ≥ 1)
still requires a multi-level TOC fixture. Status stays `DONE`; flip to
`VERIFIED` still gated on a nested-TOC fixture.

## Acceptance criteria

| Criterion | Observed | Pass/Fail |
|---|---|---|
| 1-4. Builders / converter populate `entry.level` correctly | 69-test suite green — pinned 2026-05-07 | PASS (round-1 cross-ref) |
| 5. View applies leading padding proportional to `entry.level` | Code-read at `TOCListView.swift:125-130` confirms; UI-render exercised only at level=0 (mini-epub3 has 2 flat entries) | PARTIAL (level ≥ 1 still un-exercised) |
| 6. View distinguishes h1 vs h2+ font/weight | Same as #5 — code-read confirms; only level=0 branch rendered | PARTIAL |
| 7. **Tap-entry → navigate to that locator** | Tapped Chapter Two row in open TOC sheet on mini-epub3; reader navigated from Chapter 1 of 2 → Chapter 2 of 2; sheet auto-dismissed; bottom chrome updated to "Chapter Two" + "20m read"; progress bar advanced from start → ~50% | **PASS** (newly closed this round) |

## Commands run

```bash
SIM=$(xcrun simctl list devices booted | grep -oE '\([0-9A-F-]{36}\)' | tr -d '()' | head -1)
# 53F548AE-9C89-4CB6-A6F7-17D5550F52EB (iPhone 17, iOS 26.4)

# Build + install (already on merged main 41067e5):
xcrun simctl openurl booted "vreader-debug://reset"
xcrun simctl openurl booted "vreader-debug://seed?fixture=mini-epub3"

# Open mini-epub3 from library: tap "Mini EPUB 3" card via accessibility coords
# Reader opens at Chapter One, ~9m read.
# Tap toolbar contents button (4th from left) → TOC sheet slides up.

# Tap-to-navigate verify — synthesize macOS click at the Chapter Two row's
# Accessibility-reported mac coordinates:
osascript <<EOF
tell application "System Events"
    tell process "Simulator"
        try
            set kids to entire contents of window 1
            repeat with k in kids
                try
                    set kDesc to description of k
                    if (kDesc as string) contains "Chapter" then
                        set kPos to position of k
                        set kSize to size of k
                        log "Chapter elem: " & (kDesc as string) & " pos=" & ¬
                            (item 1 of kPos as string) & "," & ¬
                            (item 2 of kPos as string) & " size=" & ¬
                            (item 1 of kSize as string) & "x" & ¬
                            (item 2 of kSize as string)
                    end if
                end try
            end repeat
        end try
    end tell
end tell
EOF
# → TOC sheet rows reported at:
#   "Chapter One" pos=(1250, 671) size=355x56
#   "Chapter Two" pos=(1250, 727) size=355x56

# CGEventPost click at row center (mac 1427, 755):
swift /tmp/clickat.swift 1427 755
xcrun simctl io booted screenshot after_tap.png
```

## Observations

- **Calibration breakthrough**: synthetic CGEventPost taps require pixel-precise
  targeting in mac coordinates, not sim coordinates. Earlier round-2 sessions
  attempted to derive mac coords arithmetically from sim physical coords using
  the window position + a constant title-bar offset; the offset is non-trivial
  to estimate (88 logical points for top toolbar buttons, but TOC sheet rows
  in `.sheet` modal don't follow the same offset). The reliable method:
  query the Simulator process's Accessibility tree (`tell process "Simulator"
  → entire contents of window 1 → position`), filter for the desired element
  description, and use those mac-space positions directly. This bypasses
  bezel / title bar / sheet-presentation y-offset uncertainty entirely.
  Documented for future verify-cron iterations.
- The TOC sheet's row entries ARE exposed via Accessibility — they show up
  with `description = "Chapter One"` / `"Chapter Two"` and 355×56 hit areas.
  Other elements (Table of Contents header, Contents/Bookmarks/Highlights/
  Notes tabs) are also accessible; could drive Bookmarks/Highlights/Notes
  panel verification the same way in future rounds.
- After the tap, the reader navigated correctly and the chrome updated:
  bottom progress label flipped from "Chapter 1 of 2" → "Chapter 2 of 2",
  middle label from "Chapter One" → "Chapter Two", time-to-end estimate
  from "9m read" → "20m read" (cumulative reading time across the rest of
  the book), progress bar from 0% → ~50% (start of Chapter Two). All
  consistent with `TOCListView.onTap → readerCoordinator.navigate(to: locator)`
  routing through the EPUB navigation pipeline.
- `mini-epub3` remains the only bundled fixture with a non-empty TOC. The
  level ≥ 1 indent rendering still cannot be visually exercised end-to-end.
  Round-2's recommendation stands: bundle a 5-10KB nested-TOC fixture
  (`mini-nested-toc.epub` with Part/Chapter/Section nesting), then the
  remaining PARTIAL criteria flip to PASS and #38 can move to `VERIFIED`.
- No bugs observed during this round. Earlier session-state issues (vreader
  process crash, macOS UserNotificationCenter dialog blocking the simulator)
  resolved cleanly via `osascript` button-click on "Ignore" + relaunch via
  `simctl launch booted com.vreader.app`.

## Artifacts

- `dev-docs/verification/artifacts/feature-38-r2-toc-sheet-open-20260510.png`
  — TOC sheet open on mini-epub3 with Chapter One highlighted (current) and
  Chapter Two listed below, both flat (level = 0).
- `dev-docs/verification/artifacts/feature-38-r2-after-tap-chapter-two-20260510.png`
  — reader on Chapter Two after the tap-to-navigate succeeded; chrome shows
  "Chapter 2 of 2" / "Chapter Two" / "20m read" with progress bar at ~50%.

## Verdict

`partial` — tap-to-navigate slice now PASS; visual-hierarchy slice (level ≥ 1
indent + font differentiation) still PARTIAL pending nested-TOC fixture. Net
progress: one of the two UI-driven legs deferred from round-1 is now closed.
Status stays `DONE` (does NOT flip to `VERIFIED` this round). Round-2's
recommended follow-up (bundle a nested-TOC fixture) remains open and is the
only remaining structural blocker between #38 and `VERIFIED`.
