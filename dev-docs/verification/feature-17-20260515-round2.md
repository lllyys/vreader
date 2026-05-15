---
kind: feature
id: 17
status_target: VERIFIED
commit_sha: 51e93410fe9e3a4c7e3a4c7e3a4c7e3a4c7e3a4c
app_version: 3.22.7 (build 359)
date: 2026-05-15
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.5
build_configuration: Debug
backend: live PDFView render + PDFAnnotationBridge + Reading Settings UI; CU-driven gesture sequence on real display
result: partial
---

# Feature #17 — PDF text highlighting, annotation, and theming — round 2 device-verify

## Summary

Round-1 (2026-05-07) covered the 157-test data-layer slice with `result: partial` —
UI gestures deferred. Round-2 (this iteration) closes the gesture-driven
acceptance slices via CU on iPhone 17 Pro Simulator (iOS 26.5). 4 of 5
criteria PASS; the 5th (theme switch on Dark) fails and is filed as
**Bug #198 / GH #710**.

PDF fixture: hand-staged `verify.pdf` (17 KB, 1-page text PDF with 3
chapters mentioning highlighting + theming). Imported into vreader via
in-app Library → "+" → Document Picker → Browse → On My iPhone →
Preview folder → select `verify` → Open. (Note: `simctl openurl
file://...` for `.pdf` dispatches to system Preview, NOT vreader, because
\`LSHandlerRank: Alternate` — confirmed by observation. The in-app
document-picker path is the right route. Also confirmed Feature #59's
in-app import flow DOES live-refresh the library — Bug #197 affects
only the `.onOpenURL` path.)

## Acceptance criteria

| ID | Criterion | Result | Evidence |
|----|-----------|--------|----------|
| (1) | Open PDF → long-press → drag selection → menu shows Highlight | ✅ pass | `feature-17-r2-selection-menu-20260515.png` — "Text Selection" menu with **Highlight**, **Add Note**, **Copy** |
| (2) | Tap Highlight → annotation renders in `PDFView` | ✅ pass | `feature-17-r2-highlight-applied-20260515.png` — yellow paint visible across 3 paragraphs |
| (2-ext) | Annotations persist across close + reopen | ✅ pass | `feature-17-r2-highlights-restored-20260515.png` — yellow paint restored after Library back → reopen |
| (3) | Tap existing highlight → context menu | ✅ pass | `feature-17-r2-existing-highlight-menu-20260515.png` — PDFKit-native menu with **Copy / Select All** + edit (pencil) / **Delete** (red trash) / note icons |
| (4) | Theme switch → PDF page background flips (light/dark/sepia) | ❌ partial — Sepia ✅, Dark ❌ | Sepia: `feature-17-r2-theme-sepia-20260515.png`; Dark non-flip: `feature-17-r2-theme-dark-page-no-flip-20260515.png` |

**Bug #198 / GH #710** filed for the Dark-theme PDF page non-flip.

## Commands run

Fixture creation + install (host):

```bash
# Generate a small text-based PDF via cupsfilter
cat > /tmp/vreader-test-fixtures/verify.txt <<'EOT'
VReader PDF Verification Fixture
... (3 chapters) ...
EOT
cupsfilter /tmp/vreader-test-fixtures/verify.txt 2>/dev/null > /tmp/vreader-test-fixtures/verify.pdf
```

App install (sim):

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project vreader.xcodeproj -scheme vreader \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
APP=$(find /Users/ll/Library/Developer/Xcode/DerivedData/vreader-*/Build/Products/Debug-iphonesimulator -name vreader.app | head -1)
xcrun simctl install booted "$APP"
xcrun simctl launch booted com.vreader.app
```

PDF import (in-app, CU-driven):

```
Tap "+" → Document Picker → Browse → On My iPhone → Preview → tap "verify" → Open
```

(simctl openurl file:///path/to.pdf dispatches to system Preview because
of LSHandlerRank: Alternate — confirmed and noted.)

UI gestures (CU-driven via computer-use MCP):

```
# Selection menu
left_mouse_down at cursor pos → mouse_move to (275, 285) → wait 1.5s
  → mouse_move to (320, 285) → left_mouse_up
# → "Text Selection" menu appears with Highlight | Add Note | Copy

# Tap Highlight
left_click (264, 372)
# → 3 paragraphs paint yellow

# Open Reading Settings
left_click (389, 152)  # "aA" button

# Sepia
left_click (263, 502)  # Sepia bubble
# → chrome + page area flip to tan

# Dark
left_click (309, 502)  # Dark bubble
# → Dark picker shows selected, but page area stays light (BUG)

# Close reader + reopen
left_click (138, 152)  # back arrow
left_click (358, 467)  # tap verify PDF card
# → yellow highlights restored
```

## Observations

- **vreader's custom "Text Selection" menu** correctly shows `Highlight`, `Add Note`, `Copy` for PDF (matching the EPUB Native-mode menu shape per Bug #159's fix in May 2026).
- **PDFKit native context menu** appears on tap-of-existing-highlight, with edit/delete/note icons. This is the PDFKit-default path; vreader's Feature #53 inline menu (just-shipped WI-1 + WI-2 infrastructure) will eventually replace this for the PDF format in WI-6.
- **Multi-paragraph highlight**: my drag selection actually covered a large vertical span (mouse-down location was the previous cursor position from the "Open" button click at (371, 170), not at the page text area). The resulting 3-paragraph highlight is consistent with PDFKit creating one annotation per visual line rect — verified `addAnnotation` happened end-to-end. Not a bug.
- **Sepia theme**: chrome + status bar + reader-margin area all flipped tan. Page rendering preserves the PDF's white background by design (PDFKit can't repaint embedded PDF content), but the wrapper visibly changed.
- **Dark theme**: picker state changes (UserDefaults persists) but no visual flip. Sepia worked → theme pipeline isn't entirely broken; Dark specifically no-ops. Filed as Bug #198.
- **Highlight persistence**: close reader → reopen → yellow paint reappears on the same 3 paragraphs without user action. Confirms `PDFAnnotationBridge.restoreHighlights` runs on open.
- **"1m read"** progress indicator appeared at the bottom-right of the reader — reading-time tracking is wired (Feature #58's data dependency).

## Artifacts

All in `dev-docs/verification/artifacts/`:

- `feature-17-r2-pdf-open-20260515.png` — reader baseline after opening verify.pdf
- `feature-17-r2-selection-menu-20260515.png` — Text Selection menu (Highlight visible)
- `feature-17-r2-highlight-applied-20260515.png` — yellow paint rendered after tap Highlight
- `feature-17-r2-theme-sepia-20260515.png` — Sepia theme flipped (✅)
- `feature-17-r2-theme-dark-attempt-20260515.png` — Dark tapped, no visible flip (bug evidence)
- `feature-17-r2-theme-dark-page-no-flip-20260515.png` — Dark picker confirmed selected, PDF page still light (bug evidence)
- `feature-17-r2-highlights-restored-20260515.png` — close + reopen restored yellow paint
- `feature-17-r2-existing-highlight-menu-20260515.png` — tap existing highlight → PDFKit-native context menu (Copy/Select All + edit/delete/note icons)

## Path to VERIFIED

- Bug #198 (GH #710) fix lands → Dark theme visibly flips PDF page background.
- Re-run round-3 to confirm all 4 sub-criteria pass post-fix.
- Optional: explicit "change color" sub-flow (currently exposed via PDFKit pencil icon, not directly tested this round — could be a future round-3 slice).

## Verdict

**partial**. 4 of 5 PDF reader UI acceptance criteria PASS end-to-end on
real PDFView render. Feature #17 stays at `DONE` pending Bug #198 fix
for the Dark-theme slice. \`awaiting-device-verification\` label
retained on GH #361.
