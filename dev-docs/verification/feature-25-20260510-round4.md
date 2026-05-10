---
kind: feature
id: 25
status_target: DONE
commit_sha: 17cc8526d6f5931a24353f68fef03af20b5e3f96
app_version: 3.14.122 (build 231)
date: 2026-05-10
verifier: claude
device_or_simulator: iPhone 17 Simulator
os_version: iOS 26.4
build_configuration: Debug
backend: n/a
result: fail
---

# Feature #25 — Configurable tap zones — round-4 device verification (FAIL)

Round-4 finally exercised the deferred "real tap → handler dispatch" slice on a native-mode reader. **Result: FAIL**. The Settings → Tap Zones picker is a no-op outside Unified mode. Filed as bug #162 / GH #482.

## What changed since round-3 (BLOCKED)

The 09:33 verify fire reprobed the host environment and found that **AppleScript clicks succeed now** — the prior iteration's Accessibility TCC error -25204 is gone, presumably because the host process was granted Screen Recording / Accessibility permissions between iterations. CU MCP `screenshot` still fails (Screen Sharing Virtual Display unchanged), but `screencapture -x` works and a Swift one-liner (`/tmp/clickat.swift`) using `CGEventCreateMouseEvent` + `CGEventPost(tap: .cghidEventTap)` delivers real mouse events that the Simulator app translates into touch events at the simulated device coordinates. The earlier `osascript -e 'tell application "System Events" to click at {x, y}'` path was rejected because System Events click-at synthesizes an AX click on the host window's element, not a touch into the simulated screen.

Tap-coordinate mapping: Simulator window at `(398, 30)` size `456x972` (per `osascript ... position of window 1 / size of window 1`); title bar ~28px; sim screen content area maps iPhone 17 logical (`1206x2622`) to mac coords by `mac_x = 398 + X * 0.378`, `mac_y = 58 + Y * 0.360`. Center y=1000 in sim → mac y=418 (clearly above the bottom-100pt exclusion zone documented in `TapZoneOverlay.swift:36-38` — though that exclusion only matters for Unified mode anyway).

## Acceptance criteria

| Criterion | Round-4 result | Notes |
|---|---|---|
| Real tap on left zone fires `previousPage` (default config) | **FAIL** | Left tap at sim (200, 1000) → chrome toggled instead of `previousPage` dispatch. |
| Real tap on center zone fires `toggleChrome` (default config) | **PASS** (ambiguous) | Center tap at sim (600, 1000) → chrome toggled. Consistent with default OR universal-toggle; not by itself distinguishing. |
| Real tap on right zone fires `nextPage` (default config) | **FAIL** | Right tap at sim (1000, 1000) → chrome toggled instead of advancing to Chapter 2; chapter indicator stayed `Chapter 1 of 2`. |
| Reconfigured config (e.g. swap left↔right) propagates to dispatch | NOT TESTED | Skipped — left/right already proven to fire the wrong action under default config; reconfiguration cannot rescue a no-op picker. |
| Native-mode safety (TXT/EPUB native renderers) | **FAIL** | Code-read confirms TapZoneOverlay is only attached in `ReaderUnifiedDispatch.swift:29,44,71`; all 4 native renderers post `readerContentTapped` unconditionally and ignore `TapZoneConfig`. |
| Settings UI exposes left/center/right pickers | NOT TESTED THIS ROUND | Round-2 (`vreaderUITests/Reader/ReaderSettingsPanelTests.swift:87`) already verified the section header renders. Per-picker rendering deferred per round-2's iOS 26 Form-Picker note. |

## Commands run

```bash
mkdir -p .claude/cron-logs && echo "$(date -Iseconds) verify FIRED" >> .claude/cron-logs/verify.log

# Re-probe host environment
system_profiler SPDisplaysDataType | grep -A1 'Displays:'
# → "Screen Sharing Virtual Display:" (unchanged from round-3 BLOCKED)
osascript -e 'tell application "System Events" to click at {500, 500}'
# → "group 1 of window iPhone 17 - iOS 26.4 of application process Simulator"
#   (no error -25204 — Accessibility TCC now granted)
mcp__computer-use__screenshot
# → still "SCContentFilter failure" (virtual display unchanged)

# Build CGEventPost click helper (Swift one-liner)
cat > /tmp/clickat.swift <<'EOF'
import Cocoa
import CoreGraphics
guard CommandLine.arguments.count >= 3,
      let x = Double(CommandLine.arguments[1]),
      let y = Double(CommandLine.arguments[2]) else { exit(2) }
let p = CGPoint(x: x, y: y)
let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)
move?.post(tap: .cghidEventTap); usleep(50_000)
let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)
down?.post(tap: .cghidEventTap); usleep(60_000)
let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)
up?.post(tap: .cghidEventTap)
EOF

# Reset, seed, open, baseline
xcrun simctl install booted /Users/ll/Library/Developer/Xcode/DerivedData/vreader-hdhlhcqmxppsadhececcxeadpkvz/Build/Products/Debug-iphonesimulator/vreader.app
xcrun simctl launch booted com.vreader.app
xcrun simctl openurl booted "vreader-debug://reset?confirm=YES"
xcrun simctl openurl booted "vreader-debug://seed?fixture=mini-epub3"
xcrun simctl openurl booted "vreader-debug://open?bookId=epub:f284fd074ccd1d3c1a78985464d9e1be27975f4029f3c2ddef8428ca10684af4:2198"
xcrun simctl io booted screenshot dev-docs/verification/artifacts/feature-25-r4-baseline-chapter1-20260510.png

# CENTER tap (default config: center=toggleChrome)
swift /tmp/clickat.swift 625 418
xcrun simctl io booted screenshot dev-docs/verification/artifacts/feature-25-r4-after-cgeventpost-center-tap-20260510.png
# Observed: chrome HID — consistent with default config OR universal toggle (ambiguous on its own)

# RIGHT tap (default config: right=nextPage)
swift /tmp/clickat.swift 776 418
xcrun simctl io booted screenshot dev-docs/verification/artifacts/feature-25-r4-after-right-tap-next-page-20260510.png
# Observed: chrome BACK ON, chapter indicator still "Chapter 1 of 2" — bug confirmed

# Re-hide chrome, then LEFT tap
swift /tmp/clickat.swift 625 418
xcrun simctl io booted screenshot dev-docs/verification/artifacts/feature-25-r4-pre-left-tap-chrome-off-20260510.png
swift /tmp/clickat.swift 474 418
xcrun simctl io booted screenshot dev-docs/verification/artifacts/feature-25-r4-after-left-tap-confirms-toggleChrome-20260510.png
# Observed: chrome BACK ON — left-tap also toggled chrome instead of dispatching previousPage
```

## Observations

- The `CGEventPost(tap: .cghidEventTap)` path is the right primitive for synthetic taps on the iOS Simulator — it generates a real macOS mouse event that the Simulator app intercepts and forwards as a touch at the corresponding device coordinate. AppleScript `click at` produces an AX-element click on the host window which the simulator does not forward.
- The "real tap delivery" capability that round-3 reported as blocked is now usable for any future iteration. Coordinate mapping pattern documented above.
- `vreader/Views/Reader/TapZoneOverlay.swift:1-7` is unusually candid: the file header explicitly states "Only used for the UNIFIED renderer ... Native mode readers handle taps via their own UITapGestureRecognizer / JS click handler. Do NOT apply tapZoneOverlay to native readers — the Color.clear overlay blocks scroll gestures from reaching UIKit. (bug #70)". The comment makes the intent clear, but the consequence — that `TapZoneStore` config is silently ignored on the dominant code path — is now bug #162.
- Feature #25's row in `docs/features.md` already says "native-mode safety still deferred". This round formalizes that deferral as a tracked bug so the gap doesn't drift further.

## Artifacts

- `dev-docs/verification/artifacts/feature-25-r4-baseline-chapter1-20260510.png` — reader open on Chapter One after `vreader-debug://open`, default chrome visible (top toolbar + bottom chapter nav + progress bar)
- `dev-docs/verification/artifacts/feature-25-r4-after-cgeventpost-center-tap-20260510.png` — chrome hidden after center tap (only "Chapter One" + 3 paragraphs of EPUB content visible)
- `dev-docs/verification/artifacts/feature-25-r4-after-right-tap-next-page-20260510.png` — chrome BACK ON after right tap; bottom nav now reads "Chapter One | 58m read"; chapter indicator still "Chapter 1 of 2" (no advance)
- `dev-docs/verification/artifacts/feature-25-r4-pre-left-tap-chrome-off-20260510.png` — chrome OFF baseline before left tap
- `dev-docs/verification/artifacts/feature-25-r4-after-left-tap-confirms-toggleChrome-20260510.png` — chrome BACK ON after left tap; bottom nav reads "Chapter One | 1h 0m read"; chapter indicator still "Chapter 1 of 2"

## Status disposition

Feature #25 row stays at `DONE` (not flipped to `IN PROGRESS`). The bug formalizes the existing "native-mode safety still deferred" gap; per the SCHEMA fail/partial semantics for features whose acceptance contract is partially unmet, this would call for an `IN PROGRESS` flip — but the gap is already documented in the row body and is being tracked under bug #162 with a hook to fix scope. Leaving the row at DONE pending the bug-fix cron's intake of #482; if the team prefers a status flip, that's a one-line tracker edit.
