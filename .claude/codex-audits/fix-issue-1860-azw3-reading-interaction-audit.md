---
branch: fix/issue-1860-azw3-reading-interaction
threadId: 019f1220-e867-75a1-b5e4-14bcaefd199c
rounds: 1
final_verdict: ship-as-is
date: 2026-06-29
---

# Gate-4 audit — bug #357 (GH #1860): AZW3 reader page-turn doesn't advance

Independent Codex audit (gpt-5.5, high reasoning, read-only sandbox) of the
fix diff for the AZW3/foliate Android reader reading-interaction bug.

## Root cause (confirmed by the audit)

The `WebView` created inside the Jetpack Compose `AndroidView` factory had the
default `WRAP_CONTENT` `LayoutParams`, so it measured its content height as 0
before content filled → a 0-height `foliate-view` viewport → the foliate
paginator computed `divisor = 1` → exactly 1 page → `readerAPI.next()` saw
`atEnd` and silently no-op'd. `goToFraction` still "worked" by scrolling within
the single giant page, which is why resume appeared functional while page-turn
did not.

## Fix

- `reader.html`: `html, body, foliate-view` height `100%` → `100vh; 100dvh`
  (viewport units; the `%`-chain resolves to 0 in the Android WebView).
- `Azw3ReaderActivity`: the factory `WebView` gets explicit
  `ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT)`.
- Re-added host-driven page-turn `TapZone`s (left=prev, right=next, centre
  reserved), shown when `Loaded`, driving `doc.prev()/next()` — mirrors iOS.
- Regression test taps the Compose `TapZone` and asserts the saved fraction
  advances.
- Removed the now-unused `androidx.test.uiautomator` androidTest dep.

## Findings (round 1) — no Critical/High

| file | severity | issue | resolution |
|---|---|---|---|
| `Azw3ReaderActivity.kt:199` | Medium | Transparent side `TapZone`s sit above the WebView, so gestures starting in the side thirds don't reach foliate (text selection / links / drag). | **Accepted with rationale.** Paginated mode has no scroll gesture to preserve; the side-tap page-turn is the intended contract (design `vreader-tap-zones.jsx`, mirrors iOS), and text selection/highlights are explicitly deferred from the AZW3 MVP to a future Foliate annotation adapter. Centre third stays free for WebView-native interactions. Applied Codex's own first suggested resolution: made the contract explicit in the code comment. |
| `reader.html:15` | Low | `100dvh` has no fallback; an older System WebView that supports the bridge but not dynamic viewport units could re-collapse the height. | **Fixed.** Added `height: 100vh; height: 100dvh;` (fallback-first) for both `html, body` and `foliate-view`. |
| `Azw3ReaderActivityTest.kt:118` | Low | `before` recorded right after the first saved position; a delayed initial relocate could inflate `after` without the tap proving advancement. | **Fixed.** The test now asserts the tap zone is displayed, then reads the fraction twice ~1s apart and requires stability before recording `before`, so only the tap can move it. |

## Dead-code / deps

Clean — `uiautomator` removal matches the diff; no remaining `UiDevice` use.

## Verdict

ship-as-is. No security regression (CSP + bridge/origin isolation unchanged from
WI-3/WI-8). Both the page-turn regression test and the restore test pass on a
real 6 MB CJK AZW3 on an API-35 emulator.
