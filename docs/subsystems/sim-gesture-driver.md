# Simulator gesture driver — `scripts/sim-tap.sh` (idb)

CU-free way to drive **real gestures** on the booted iOS Simulator: tap by
accessibility label or point, swipe, launch apps, dump the on-screen element
tree, screenshot. Built on Facebook's [idb](https://github.com/facebook/idb).

## Why this exists

The computer-use MCP host builds its app catalog from LaunchServices at launch
and **cannot target the Simulator** — `Simulator.app` is nested inside
`Xcode.app` (`/Applications/Xcode.app/Contents/Developer/Applications/`), not a
top-level app, so `request_access` returns `not_installed` and MCP-CU can't
tap or swipe the simulator. `idb` talks to the simulator directly over its own
companion socket and synthesizes gestures, sidestepping the catalog entirely.

This complements, it does not replace, the two existing CU-free tools:

| Tool | Drives | Use when |
|---|---|---|
| **DebugBridge** (`vreader-debug://`) | app state: reset / seed / open / settle / snapshot / eval | you can express the action as a bridge command (preferred — deterministic) |
| **XCUITest** | gestures via the accessibility API, headless | the verification is a repeatable regression test (Gate-5 / close-gate) |
| **`sim-tap.sh`** (idb) | ad-hoc real taps / swipes + screenshot | a gesture the bridge has no command for AND you don't need (yet) to author a full XCUITest — a quick interactive check, or driving a surface no DebugBridge command reaches |

Order of preference is unchanged: **DebugBridge command → XCUITest → idb**.
Reach for idb when the first two can't express the gesture, not before.

## One-time install

```bash
brew install facebook/fb/idb-companion
pip3 install --user fb-idb        # installs `idb` to ~/Library/Python/3.9/bin
```

`scripts/sim-tap.sh` sets its own PATH for the user-site `idb`, so it runs from
any shell without a `.zshrc` change. To call bare `idb` directly, add
`export PATH="$HOME/Library/Python/3.9/bin:$PATH"` to `~/.zshrc`.

## Commands

```bash
scripts/sim-tap.sh launch com.vreader.app   # open an app by bundle id (deterministic)
scripts/sim-tap.sh tree                      # dump on-screen elements: label  centerX  centerY
scripts/sim-tap.sh label "Display"           # tap the element whose AXLabel == "Display"
scripts/sim-tap.sh xy 340 434                # tap point (x, y) in POINTS
scripts/sim-tap.sh swipe 201 680 201 180     # swipe (x1 y1 -> x2 y2) in POINTS
scripts/sim-tap.sh button HOME               # HOME | LOCK | SIDE_BUTTON | SIRI | APPLE_PAY
scripts/sim-tap.sh shot [/path/out.png]      # screenshot (default: /tmp/sim-shot.png)
```

`SIM_UDID=<udid>` overrides the target; default is the first booted simulator.

## The see → act → see loop

`tree` is how you confirm **where you are** before acting, and `shot` is how
you assert the result. A typical slice:

```bash
scripts/sim-tap.sh launch com.vreader.app          # open
scripts/sim-tap.sh tree | grep -i "back to library" # confirm we're in the reader
scripts/sim-tap.sh label "Display"                  # act
scripts/sim-tap.sh shot /tmp/after.png              # assert (read the PNG)
```

To **open an app**, prefer `launch <bundle-id>` over hunting its home-screen
icon — icon position is unstable (App Library, folders, multi-page) while the
bundle id is deterministic. Use `label`/`xy` for in-app controls.

## Boundaries — what idb does NOT do

- **WebView text is not in the AX tree.** EPUB/AZW3 content renders in a
  WKWebView; its paragraphs are not native accessibility elements, so `tree`
  won't list them and `label` can't target them. Tap native chrome (toolbar,
  sheets, buttons) by label; drive in-WebView assertions through DebugBridge
  `eval` instead.
- **Scroll vs. Paged matters.** In the reader's **Scroll** mode a *horizontal*
  swipe does nothing — advance with a *vertical* `swipe 201 680 201 180`. In
  **Paged** mode a horizontal swipe turns the page. Check the mode first.
- **idb cannot conjure fixtures.** A book has to exist before you can open it;
  seed it via DebugBridge (`seed=<fixture>`), which only ships TXT / MD / EPUB
  today (no PDF / AZW3 fixture — that gap is unchanged).
- **Gestures aren't a regression test.** An idb-driven check is ad-hoc; for
  Gate-5 / close-gate verification that must re-run later, author the XCUITest.

## Provenance

Added v3.41.12 (PR #1305 the tool, follow-up PR the workflow integration).
Root-cause + install walkthrough lives in this repo's session history; the
script header is the authoritative usage reference.
