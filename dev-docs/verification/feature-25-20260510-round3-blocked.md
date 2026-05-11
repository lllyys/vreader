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
result: blocked
---

# Feature #25 — Configurable tap zones — round-3 attempt (BLOCKED)

This iteration is recorded as `blocked` per SCHEMA. The deferred slice — "real tap → handler dispatch + Settings UI driving + native-mode safety" — requires real UI tap delivery to the iOS Simulator, and every available tap path is unavailable on this host.

## Blockers

1. **Computer-use MCP screenshot returns `SCContentFilter failure`.** `system_profiler SPDisplaysDataType` shows the only attached display is `Screen Sharing Virtual Display` (host driven through Screen Sharing — no real monitor). The MCP capture path refuses virtual-only displays even though `screencapture -x /tmp/cu-diagnose/sys.png` succeeds (3840x2160 PNG). Without a CU screenshot, `mcp__computer-use__left_click` rejects coordinates because it cannot validate the target window — observed: "Click at these coordinates would land on \"Code\", which is not in the allowed applications. Take a fresh screenshot to see the current window layout."
2. **AppleScript-based clicks fail with TCC error -25204** (`errAEEventNotPermitted` — Accessibility permission missing for the host process). `osascript -e 'tell application "System Events" to click at {1279, 418}'` produced this error. AppleScript-based key-event dispatch (`key code 124` / right-arrow) executed without OS error but did not advance the page (event not delivered to the simulator's UIKit responder chain).
3. **`xcrun simctl` provides no native tap injection.** Inspected `simctl --help`: only `keychain`, `pbcopy`, `pbpaste`, `screenshot`, `recordVideo`, `ui appearance`. No mouse/touch primitives.
4. **DebugBridge URL grammar has no `tap` host.** `DebugCommand.swift` enumerates `reset`, `seed`, `open`, `theme`, `settle`, `snapshot`, `eval` only — no programmatic dispatch into `.readerNextPage` / `.readerPreviousPage` / `.readerToggleChrome`. The deferred sub-slices for #25 inherently require gesture delivery; data-layer behavior was already covered by 26 unit tests in round-1 (`feature-25-20260507.md`).
5. **Existing UITest coverage stops at "section presence".** `vreaderUITests/Reader/ReaderSettingsPanelTests.swift:87` (`testReaderSettingsExposesTapZonesSection`) verifies only that the Tap Zones section header renders. There is no XCUITest that drives a tap zone end-to-end through to handler dispatch on a reader fixture.

## Acceptance criteria

| Criterion | Targeted by this round? | Result |
|---|---|---|
| Settings UI exposes left/center/right pickers | Yes | NOT VERIFIED — Settings sheet open requires a tap on the toolbar `readerSettingsButton`; same block as below |
| Real tap on left zone fires `previousPage` (default config) | Yes | NOT VERIFIED — no tap delivery |
| Real tap on center zone fires `toggleChrome` (default config) | Yes | NOT VERIFIED — no tap delivery |
| Real tap on right zone fires `nextPage` (default config) | Yes | NOT VERIFIED — no tap delivery |
| Reconfigured config (e.g. swap left↔right) propagates to dispatch | Yes | NOT VERIFIED — no tap delivery + no settings access |
| Native-mode safety (TXT/EPUB native renderers) | Yes | NOT VERIFIED — no tap delivery |

## Commands run

```bash
mkdir -p .claude/cron-logs && echo "$(date -Iseconds) verify FIRED" >> .claude/cron-logs/verify.log
xcrun simctl install FDF2EA2A-532E-48D4-9022-ADEB6CD053CC /Users/ll/Library/Developer/Xcode/DerivedData/vreader-hdhlhcqmxppsadhececcxeadpkvz/Build/Products/Debug-iphonesimulator/vreader.app
xcrun simctl launch booted com.vreader.app
xcrun simctl openurl booted "vreader-debug://reset?confirm=YES"
xcrun simctl openurl booted "vreader-debug://seed?fixture=mini-epub3"
xcrun simctl openurl booted "vreader-debug://open?bookId=epub:f284fd074ccd1d3c1a78985464d9e1be27975f4029f3c2ddef8428ca10684af4:2198"
# All of the above succeeded; reader opened to mini-epub3 Chapter One.

# Tap-delivery probe attempts (all failed):
osascript -e 'tell application "System Events" to click at {1279, 418}'
# → execution error: System Events got an error: An error of type -25204 has occurred. (-25204)

osascript -e 'tell application "Simulator" to activate
delay 0.3
tell application "System Events" to key code 124'
# → no OS error but key event was not delivered (post-key screenshot identical to pre-key)

# CU-diagnose verdict:
system_profiler SPDisplaysDataType | grep -A2 'Displays:'
# → "Screen Sharing Virtual Display:" (no real monitor)
screencapture -x /tmp/cu-diagnose/sys.png && file /tmp/cu-diagnose/sys.png
# → PNG image data, 3840 x 2160, 8-bit/color RGBA — works
mcp__computer-use__screenshot
# → "Tool screenshot failed: Screenshot capture returned nil (permission missing or SCContentFilter failure)"
mcp__computer-use__left_click  [1279, 418]
# → "Click at these coordinates would land on Code, which is not in the allowed applications."
```

## Observations

- The fixture-load + reader-open path is healthy on v3.14.122. The screenshot at `feature-25-r3-after-open-20260510.png` shows the EPUB reader on Chapter One with the default chrome (top toolbar + bottom chapter nav + progress bar). This part of the slice is fine.
- The `simctl io booted screenshot` path works (1206x2622 PNG produced). Visual inspection of the simulator state remains possible — the missing capability is exclusively *delivering* taps, not *observing* state.
- Per `cu-diagnose` matrix: this is the "Virtual only / `screencapture` works / MCP `screenshot` fails" row. **Remediation: plug an HDMI dummy plug or use BetterDisplay; alternatively grant the host process Accessibility TCC so AppleScript clicks/keys work.** Both are out of scope of an autonomous cron iteration.
- The 5 deferred sub-criteria above remain the same as round-2 (`feature-25-20260508.md`). No regression introduced; no progress made.

## Artifacts

- `dev-docs/verification/artifacts/feature-25-r3-after-seed-20260510.png` — Library after `vreader-debug://reset` + `vreader-debug://seed?fixture=mini-epub3`. One book card visible: "VReader Mini EPUB Fixture" / "VReader DebugBridge".
- `dev-docs/verification/artifacts/feature-25-r3-after-open-20260510.png` — Reader after `vreader-debug://open?bookId=epub:f284fd07…:2198`. EPUB on Chapter One, default chrome visible (search/bookmark/contents/audio/AA + chapter nav "Chapter 1 of 2" + progress bar).
- `dev-docs/verification/artifacts/feature-25-r3-after-rightarrow-20260510.png` — State immediately after AppleScript `key code 124` (right arrow). Identical to the previous shot; confirms key event was not delivered.

## Next session

When the host has either (a) a real display attached so `mcp__computer-use__screenshot` returns frames and `left_click` validates targets, or (b) Accessibility TCC granted to the host process so `osascript` clicks succeed, this slice can be closed in one round: tap left → confirm previous-page; tap center → confirm chrome toggle; tap right → confirm next-page; open settings → reconfigure → re-verify with swapped mapping.
