---
branch: docs/triage-azw3-bottombar-and-fontsize
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-21
---

## Scope

Docs-only triage filing. Adds two new summary rows + two
Open-Bug-Details entries to `docs/bugs.md`:

- Bug #260 — AZW3/MOBI reader never mounts the bottom chrome (High).
- Bug #261 — AZW3/MOBI reader renders body text too large (Medium).

Touches `docs/bugs.md` only, plus `project.yml` / `project.pbxproj`
(version bump 3.39.2/623 → 3.39.3/624).

**No Swift source files changed.** The audit-gate hook fires on
`project.pbxproj` — false positive of the Swift-file heuristic.
Manual mini-audit.

## Manual audit evidence

### Investigation done at triage time (Bug #260)

1. `grep -rl "ReaderBottomChrome(" vreader/Views/Reader/*Foliate*`
   → 0 files. The Foliate host mounts no bottom chrome.
2. Per-format mount sites confirmed: `EPUBReaderContainerView+Navigation.swift:31`,
   `MDReaderContainerView.swift:97`, `PDFReaderContainerView+Overlays.swift`,
   TXT container — all four native formats mount it.
3. `readerChromeOverlay` (`ReaderContainerView+Sheets.swift:281`)
   mounts only `ReaderTopChrome` at the shared level — confirms the
   bottom chrome is per-format, not shared.
4. `git log -S "ReaderBottomChrome" -- "vreader/Views/Reader/Foliate*.swift"`
   → empty (never present in any Foliate file).
5. Confirmed Bug #108 (AZW3 center-tap chrome) is FIXED in v3.39.1 —
   so the user's complaint is NOT the center-tap toggle (that now
   works); it's that the bottom bar is architecturally absent.

### Investigation done at triage time (Bug #261)

1. `FoliateSpikeView.themeCSS(for:)` (lines 62-73) routes
   `store.typography.fontSize` (default 18) through
   `FontSizeCalibrator.calibratedFoliateSize(forUnified:)`.
2. `FontSizeCalibrationProfile.standard` sets `foliate: 1.12`
   (`FontSizeCalibration.swift:88`) — identical to `epub: 1.12`.
3. The profile's doc-comment (lines 74-83) explicitly calls these
   *"conservative, identity-leaning estimates"* whose literals
   *"Gate-5 behavioral verification confirms or re-tunes"*.
4. Bug #166's root-cause note (still in tracker) documents that
   WebView formats compound the book's own stylesheet — the
   em-compounding hypothesis.

### Correctness checks

1. **Bug-vs-feature (both)**:
   - #260: the bottom chrome IS implemented and wired to four
     formats; AZW3 was skipped. Implemented-for-others-not-AZW3 =
     bug (parity gap), not a never-built feature.
   - #261: font sizing IS implemented + calibrated for AZW3; the
     output is wrong (too large). Implemented-but-wrong = bug.
2. **No open duplicate** — no row covers AZW3-bottom-bar-missing or
   AZW3-font-too-big. Bug #108 (FIXED) is the center-tap toggle, a
   different issue. Bug #166 (FIXED) is general cross-format
   inconsistency, residual split to feature #491.
3. **One-issue-per-triage** — the user's single message carried two
   distinct symptoms; filed as two separate bugs with an explicit
   cross-reference (they compound: #261's only workaround lives in
   #260's missing bar).
4. **Rule-51 note on the #260 fix** — mounting the existing
   `ReaderBottomChrome` on the Foliate host is reusing a designed
   component on a format that lacks it (cf. bug #156 / #172), NOT
   inventing UI; the bug entry says so. The eventual fix does not
   need a `Design needed:` issue.
5. **GH mirror** — #1130 (`bug` + `severity:high`) for #260; #1131
   (`bug` + `severity:medium`) for #261. Both stamped in Notes.
6. **Bug IDs** — max on `main` was 259; 260 + 261 are the next free
   pair. No collision.
7. **No fix attempted** — classification + root-cause + fix
   direction only.
8. **Version bump** — 3.39.3 / build 624 (patch — docs / tracker
   triage). `xcodegen generate` + `xcodebuild build` SUCCEEDED on
   iPhone 17 Pro Simulator (Debug).

## Verdict

ship-as-is — documentation only, two bug filings, no code risk.
Manual fallback used because there is nothing to send to Codex.
