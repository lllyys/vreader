---
description: "Diagnose why `mcp__computer-use__screenshot` is failing. Runs a 4-step checklist (display state, OS-level capture, MCP capture, allowlist) and outputs a verdict + concrete remediation. Use whenever CU returns `CU display unavailable` or any other capture error."
---

# /cu-diagnose

Diagnose computer-use capture failures end-to-end. The MCP host has its
own capture path that depends on (a) macOS Screen Recording TCC,
(b) a real-display attachment (or a virtual-display tool the MCP
recognises), and (c) the apps in the allowlist being visible.

Run the steps below in order and report a single-screen verdict.

## Step 1 — Display state

```bash
system_profiler SPDisplaysDataType 2>/dev/null | grep -A2 'Displays:' | head -20
```

Look for the display name. Expected values:

- A real monitor name like `LG UltraFine`, `Studio Display`, `27-inch iMac`, etc.
- `Built-in Display` on a MacBook
- `Apple Silicon` GPU output to an attached panel

**Red flag**: only `Screen Sharing Virtual Display` appears. That means
no physical monitor is attached and the Mac is being driven entirely
through Screen Sharing / Remote Desktop / VNC. The MCP capture path
typically can't capture from a virtual-only display, even when macOS's
own `screencapture -x` can.

## Step 2 — OS-level capture

```bash
mkdir -p /tmp/cu-diagnose
screencapture -x /tmp/cu-diagnose/sys.png && file /tmp/cu-diagnose/sys.png
```

Expected: `PNG image data, <width> x <height>, 8-bit/color RGBA`.

**Red flag**: `screencapture` itself errors or produces a 0-byte file.
That means TCC is denying screen recording at the OS level. Check
**System Settings → Privacy & Security → Screen Recording** and
confirm the host process (most often Visual Studio Code or Terminal —
walk up the parent tree from the running `claude` process to find it)
is in the list with the toggle ON.

If you just toggled it on, the host process needs a restart for TCC
to take effect — TCC reads at process launch.

## Step 3 — Process tree

```bash
PID=$(cat .claude/scheduled_tasks.lock 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["pid"])' 2>/dev/null)
while [ -n "$PID" ] && [ "$PID" -gt 1 ]; do
  PROC=$(ps -o pid=,ppid=,comm= -p "$PID" 2>/dev/null) || break
  echo "  $PROC"
  PID=$(echo "$PROC" | awk '{print $2}')
done
```

This walks from `claude` up to the GUI ancestor. The TCC-responsible
process is usually the topmost GUI app in the chain (Visual Studio
Code, Terminal, iTerm2, …). That's the one you'd grant Screen
Recording to in System Settings.

## Step 4 — MCP-level capture

Try `mcp__computer-use__request_access` (call from Claude, not from the
shell) with the relevant apps in the allowlist, then call
`mcp__computer-use__screenshot`. Capture the response.

Possible outcomes:

- **`granted: [...]` then a successful screenshot** → CU works. You're
  done. Drive UI verification normally.
- **`granted: [...]` then `screenshot` returns `CU display unavailable`**
  → cross-reference with steps 1 and 2. If step 1 shows virtual-only
  display and step 2 shows working `screencapture`, the issue is the
  virtual-display class — the MCP host refuses to capture from a
  Screen Sharing display. See remediation below.
- **`screenshot` returns `Accessibility and Screen Recording
  permission(s) not yet granted`** → grant in System Settings, then
  restart the host process.

## Verdict matrix

| Display | `screencapture` | MCP `screenshot` | Diagnosis |
|---|---|---|---|
| Real monitor | works | works | CU is healthy. Drive verification. |
| Real monitor | works | fails | MCP server stuck — try `/mcp` to reconnect. |
| Real monitor | fails | fails | TCC missing for host process. Grant Screen Recording + restart host. |
| Virtual only | works | fails | **No real display attached.** Plug in HDMI dummy plug or use BetterDisplay. The MCP capture path won't work otherwise. |
| Virtual only | fails | fails | Both TCC and display issues. Grant TCC first, then plug in a display. |

## Output

Print a single section with:

- `Display:` <name>
- `screencapture:` <works|fails>
- `MCP screenshot:` <works|fails>
- `Verdict:` one line from the matrix above
- `Remediation:` exact next action the user should take

Keep it under 10 lines. No prose. The user wants the verdict, not the journey.

## When to run

- The verify cron logs `blocked` because CU returned `CU display unavailable`.
- A user-driven session tries `screenshot` and gets any error.
- After a host process restart, before kicking off a UI-gesture verification slice — confirm CU is live.
