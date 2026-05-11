---
name: sim-drive-fallback
description: Drive the iOS Simulator when computer-use can't — for bypassing CU outages, not diagnosing them (use `/cu-diagnose` for diagnosis). Trigger when `mcp__computer-use__screenshot` returns `CU display unavailable`, when the user mentions "CU fallback", "CU substitute", or "drive sim without computer-use", or when continuing a verification that was previously blocked by a CU outage.
---

# Sim Drive Fallback

CU MCP capture occasionally returns `"CU display unavailable"` on this
host even when a real monitor is attached and `screencapture -x`
succeeds at the OS level. This skill is the working substitute — the
subset of touch gestures that the iOS Simulator translates from mac
mouse/keyboard events posted via CGEventPost. Enough for most
single-tap / SwiftUI-sheet-drag / TextField-paste verifications.

## When to use

- A verify-cron iteration calls `mcp__computer-use__screenshot` and
  gets `CU display unavailable` (despite `request_access` returning a
  successful grant for Simulator).
- A user task mentions "CU substitute", "CU fallback", "drive the sim
  without computer-use", or "verify without CU".
- You need to verify a UI-gesture-driven bug fix or feature acceptance
  criterion and the primary CU path is out.
- You're picking up a verification that a prior cron iteration marked
  `blocked: CU display unavailable` — the workflow may now be possible
  through this toolkit even though CU itself is still down.

Do NOT use this for: rubber-band overscroll, long-press → context
menu, multi-touch / pinch, or anything requiring continuous WKWebView
touch-drag — those don't translate via CGEventPost. See "Capability
bounds" below.

## The toolchain

In typical order of use for one verification slice:

### 1. Capture — `xcrun simctl io booted screenshot <abs_path>`

```bash
xcrun simctl io booted screenshot /Users/ll/workspace/vreader/dev-docs/verification/artifacts/<filename>.png
```

Goes through CoreSimulator directly; survives any CU MCP outage.

**Always use an absolute path.** `simctl io` resolves relative paths
against an unpredictable cwd and may silently write to the wrong
location.

### 2. Element location — `osascript` accessibility tree query

```bash
osascript <<'EOF'
tell application "System Events"
    tell process "Simulator"
        try
            set kids to entire contents of window 1
            repeat with k in kids
                try
                    set kDesc to description of k
                    set kPos to position of k
                    set kSize to size of k
                    if (kDesc as string) is not "" then
                        log "elem: '" & (kDesc as string) & "' pos=(" & (item 1 of kPos as string) & "," & (item 2 of kPos as string) & ") size=" & (item 1 of kSize as string) & "x" & (item 2 of kSize as string)
                    end if
                end try
            end repeat
        end try
    end tell
end tell
EOF
```

Returns each accessibility element's **mac-space** coordinates
(`position`, `size`) and description string. This is the bedrock —
every click/drag uses these mac coords directly without any sim-coord
conversion math, which sidesteps bezel / title-bar / sheet-presentation
y-offset uncertainty.

Filter with `grep` for the element you want — the raw tree can return
hundreds of `group` nodes; element descriptions like `"Settings"`,
`"Add bookmark"`, `"Enable AI Assistant"`, `"Done"` are the useful
handles. SwiftUI exposes form labels, toggle row titles, and button
titles as `description`. `switch` (for `Toggle`), `Picker` segments,
and `Sheet Grabber` show up by role-name when their description is
empty.

### 3. Single tap — `clickat.swift`

```bash
swift /Users/ll/workspace/vreader/.claude/skills/sim-drive-fallback/scripts/clickat.swift <mac_x> <mac_y>
```

mouseDown → 50ms → mouseUp. Translates cleanly to an iOS touch for:
Settings buttons, Toggle switches, segmented controls, list rows,
picker selections, sheet Done buttons, in-sheet rows.

Click center for an element at `position=(px, py)` size `(w, h)` is
`(px + w/2, py + h/2)`.

### 4. Drag — `dragat.swift`

```bash
swift /Users/ll/workspace/vreader/.claude/skills/sim-drive-fallback/scripts/dragat.swift <x1> <y1> <x2> <y2>
```

mouseDown → 10 intermediate mouseDragged events (20ms apart) → mouseUp.
The intermediate moves matter — without them, iOS quantizes the motion
to a single touch.

Works for **SwiftUI `.sheet()` content scroll** (Reading Settings,
Filter, Add Collection sheet, etc.) and **sheet grabber expand** (drag
the grabber upward to grow the sheet from half-height to full).

**Does NOT translate** to WKWebView touch-drag — EPUB content scroll,
EPUB rubber-band overscroll, Foliate page advance. The mouse drag
never enters the web view's touch handler; you'll see the cursor move
but get no scroll/bounce response in the rendered document.

### 5. Text entry — clipboard + cmd+V

```bash
osascript -e 'set the clipboard to "the literal text"'
swift /Users/ll/workspace/vreader/.claude/skills/sim-drive-fallback/scripts/clickat.swift <field_x> <field_y>   # focus
swift /Users/ll/workspace/vreader/.claude/skills/sim-drive-fallback/scripts/pastekey.swift                      # paste
```

Simulator shares the mac clipboard. The cmd+V combo posts via
CGEventPost while Simulator is frontmost; the focused TextField
receives the paste. Verified working on collection-name fields, search
fields, etc.

Caveat: `SecureField` may swallow synthetic cmd+V on some iOS
versions. For passwords, document as `verification-blocked` rather
than work around.

## Canonical workflow — "tap → verify"

For the common "tap a UI control, screenshot to verify the state
change" slice:

1. Screenshot baseline: `xcrun simctl io booted screenshot <baseline>.png`.
2. AX-query for the target element's description; note its
   `position` and `size` in mac-space.
3. Compute click center `(cx, cy) = (px + w/2, py + h/2)`.
4. Run the `clickat.swift` command from the "Single tap" section above with `<cx> <cy>` substituted in.
5. `sleep 1` — let the UI settle. Sheet transitions and SwiftUI
   re-renders can take 200–500ms.
6. `xcrun simctl io booted screenshot <after>.png` — capture the new
   state.
7. (Optional) AX-query the changed element to verify state
   programmatically (e.g., `switch` role + `on/off` value, or the
   presence of a previously-hidden section).

## Worked example — bug #169 verification (the canonical reference)

Bug #169 was verified end-to-end via this stack: AX-query to find the
Settings gear and the AI-Assistant `switch`, three `clickat.swift`
taps (open Settings, toggle off, toggle on), three `simctl io
screenshot` captures between taps. Result: API Key / Provider
Configuration / Data & Privacy sections appeared and disappeared in
lock-step with the toggle in a single sheet session. See
`dev-docs/verification/bug-169-20260511.md` for full coords + the
3-screenshot proof chain — the canonical reference for any
"settings toggle reveals section" verification.

## Capability bounds

| Gesture | Works? | Notes |
| --- | --- | --- |
| Single tap (button / toggle / picker / row) | ✅ | CGEventPost mouseDown+Up translates 1:1 to iOS touch. The bulk of verifications fit here. |
| SwiftUI sheet content scroll | ✅ | Use `dragat.swift` inside the sheet body. Finger-up drag scrolls content up; finger-down drag scrolls content down. |
| Sheet grabber expand (half → full height) | ✅ | Drag the `Sheet Grabber` element upward. |
| TextField paste (cmd+V) | ✅ | Mac clipboard shared; `pastekey.swift` inserts into focused field. |
| Drag inside scroll view to trigger overscroll bounce | ⚠️ | Drag translates, but iOS rubber-band requires sustained dwell at edge AND scrollable content. With `scrollHeight == innerHeight` (e.g., short EPUB chapter), no bounce is possible. |
| Long-press → context menu | ❌ | `mouseDown + sleep + mouseUp` reads as a single tap, not a sustained iOS touch. The release fires the gesture recognizer's tap path before the long-press timer matures. |
| Multi-touch / pinch / two-finger swipe | ❌ | CGEventPost has no multi-finger primitive. |
| Double-tap with timing | ⚠️ | Two `clickat.swift` invocations can simulate, but iOS gesture recognizer rejects if the inter-tap gap is wrong. Single-tap-only is safer. |
| WKWebView touch-drag (EPUB content scroll) | ❌ | Mouse drag never enters the web view's touch handler; only native UIScrollView gestures respond. |
| EPUB / Foliate page advance via drag | ❌ | Same root cause as WKWebView touch-drag. |
| Hardware key (volume, home, side button) | ❌ | Use `xcrun simctl io booted hardware` / Hardware menu instead — out of scope for this skill. |

If a verification target falls into the ❌ row, mark the slice as
**verification-blocked** with the tooling-gap reason — it's not a code
regression, and CU coming back online is the resolution path.

## Concurrency with other sessions

Unlike CU MCP (which serializes desktop access — second session gets
denied at `request_access` time), this toolkit has no lock. Every
tool goes straight to a macOS-native subsystem, so multiple Claude
Code sessions can use it at the same time. The catch: writes share
global state, so concurrent writers race.

| Operation | Subsystem | Concurrent sessions |
|---|---|---|
| `simctl io … screenshot` | CoreSimulator IPC | ✅ each gets own snapshot |
| `osascript` AX query | Accessibility API | ✅ read-only |
| `clickat.swift` / `dragat.swift` | HID event tap (global) | ⚠️ events go to the frontmost window NOW — concurrent sessions race |
| `set the clipboard` + `cmd+V` | NSPasteboard + global keystroke | ⚠️ last writer wins on the clipboard |

Two practical implications:
- **CGEventPost targets the frontmost window.** If another app comes
  forward between your AX-query (which fixes coords against the
  Simulator) and your `clickat.swift`, the click lands in that other
  app. Bring Simulator forward (`open -a Simulator`) right before any
  CGEventPost sequence if you suspect drift.
- **For overlapping cron iterations** (vreader has 4 — verify, bugfix,
  watchdog, feature), if two ever both drive the sim at the same time,
  clicks and clipboard state will interleave. The OS won't error;
  you'll just get non-deterministic output. If this becomes routine
  (it hasn't yet), serialize sim driving with a `flock /tmp/sim-drive.lock`
  wrapper around each CGEventPost sequence — cheap fix, preserves the
  read paths' concurrency.

## Origin + reference verifications

- `dev-docs/verification/feature-38-20260510-round3.md` — first round
  that switched from CU MCP to this stack (TOC tap-to-navigate slice).
  Documents the AX-query technique.
- `dev-docs/verification/bug-169-20260511.md` — full end-to-end
  verification of bug #169 (AI Settings toggle re-render). 3
  screenshots in the same Settings sheet proving the toggle ON→OFF→ON
  cycle works. Closest canonical reference for "tap + sheet + toggle +
  verify".

## What this skill does NOT include

- Does not fix CU MCP (workaround, not repair — `/cu-diagnose` handles diagnosis).
- Does not record screen video (use sequential screenshots).
- Does not control hardware keys, rotation, or background-app states (those go through `xcrun simctl` directly).

## Quick reference card

`SKILL=/Users/ll/workspace/vreader/.claude/skills/sim-drive-fallback/scripts`

```bash
xcrun simctl io booted screenshot /absolute/path/output.png   # capture
swift "$SKILL/clickat.swift" <cx> <cy>                        # tap
swift "$SKILL/dragat.swift" <x1> <y1> <x2> <y2>               # drag (SwiftUI sheets only)
osascript -e 'set the clipboard to "the text"' && swift "$SKILL/pastekey.swift"   # paste into focused TextField
```

For element coordinates use the `osascript` AX-tree query in section
**The toolchain → Element location** above; the same snippet, no need
to duplicate it here.
