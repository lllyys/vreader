---
kind: feature
id: 2
status_target: VERIFIED
commit_sha: 6199fb4a4d9fce7d730508c3523e0c51177fd411
app_version: 3.21.52 (build 329)
date: 2026-05-14
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.5
build_configuration: Debug
backend: n/a (bundled mini-epub3 fixture)
result: partial
---

# Feature #2 — Highlight search result at destination (round 4 — EPUB leg)

## Context

Prior rounds (1, 2, 3) of feature #2 focused on the TXT path and
documented it as blocked on bugs #154/#160 (chapter-mode visual paint).
EPUB cross-chapter highlight was never device-verified. This round
attempted the EPUB leg, riding the recent bug #182 fix
(`pendingHighlightJS` deferred to `didFinish`, v3.21.50) and bug
#187 fix (BackgroundIndexingCoordinator strong-self capture so EPUB
indexing actually runs, v3.21.51) — both shipped earlier this
session as preconditions.

## Acceptance criteria

The feature row's acceptance criterion is "highlight search result at
destination" — for EPUB, that means: search → tap a result in a
DIFFERENT chapter → reader navigates to the matched chapter AND a
temporary yellow background appears on the matched word for ~3
seconds before auto-clearing.

| Sub-criterion | Observed | Pass? |
|---|---|---|
| Search returns results for words in the EPUB | Search for "navigation" returned 1 hit ("...hapter Two The second chapter exists so **navigation** between chapters can be tested. It is s..." with `chapter2` label) on first attempt after reset+seed+open. **Was blocked across rounds 1-3 because EPUB indexing silently failed (bug #187); now works.** | **PASS** |
| Tapping the result navigates to the matched chapter | Reader's bottom chrome flipped from "Chapter 1 of 2 — Chapter One" to "Chapter 2 of 2 — Chapter Two". | **PASS** |
| Yellow highlight visible on matched word for ~3s | Three rapid simctl screenshot captures at t=500ms, t=1500ms, t=3500ms post-tap returned byte-identical images (120079 bytes each). The captured frame shows chrome bar visible at top + empty white viewport area + chrome bar at bottom. Faint "End of fixture." text visible at the very top-left (above the chrome bar — content rendered at scrollTop ≈ -safeAreaTop). The matched word "navigation" was NOT visible in the visible viewport during the 3-second highlight window. With chrome toggled OFF (via a tap, which itself triggers feature #5 auto-dismiss) some seconds later, Chapter Two content visible at top of viewport with "Chapter Two / The second chapter exists so navigation between chapters can be tested. / End of fixture." — no yellow paint anywhere. Cannot confirm whether the deferred-eval JS fired but produced no visible paint, OR didn't fire at all. | **INCONCLUSIVE** |
| Scroll lands on the matched word | After the cross-chapter navigation, scroll position appears to be at the very top of chapter 2 (Chapter Two h1 + first paragraph visible). The matched "navigation" word is in that first paragraph, so technically the matched word IS in the visible area when chrome is hidden. However, no scroll-into-view animation was observed (the navigation seems to land at chapter top by default after `loadFileURL`, not specifically at the matched word). | **PASS-CONDITIONAL** (matched word is visible at default chapter-top scroll because chapter 2 is short, NOT because scroll-to-match worked) |
| Auto-clear of highlight on next action | Not exercised — highlight was never visibly painted. | **N/A** |

**Overall**: partial. Two upstream preconditions (search no-results bug #187 + cross-chapter navigation) now pass on the EPUB path, which is itself a net new pass relative to rounds 1-3. The yellow-highlight-visible criterion remains unverified — could not capture clear evidence of the highlight either painting OR failing to paint during the 3-second window due to chrome-bar overlap with the small chapter 2 content area.

## Commands run

```bash
SIM_ID="1FAB9493-B97E-48F0-96C7-44A8E5AAA21E"
BUILD_DIR="/Users/ll/Library/Developer/Xcode/DerivedData/vreader-hdhlhcqmxppsadhececcxeadpkvz/Build/Products/Debug-iphonesimulator"

# Install latest build (v3.21.52 includes bug #187 fix from v3.21.51)
xcrun simctl install "$SIM_ID" "$BUILD_DIR/vreader.app"

# Reset + seed mini-epub3
xcrun simctl openurl "$SIM_ID" "vreader-debug://reset"
xcrun simctl openurl "$SIM_ID" "vreader-debug://seed?fixture=mini-epub3"
```

Then via Simulator UI (driven through `mcp__computer-use__*`):
1. Tap book cover → reader opens at Chapter 1 of 2.
2. Tap search icon (top toolbar magnifying glass) → search sheet presents.
3. Paste "navigation" into search field via clipboard fast-path (`write_clipboard` + `cmd+v`).
4. **Search returns 1 result** with snippet "...hapter Two The second chapter exists so navigation between chapters can be tested. It is s..." and label `chapter2`. (This is the bug #187 fix in action.)
5. Tap the result row.
6. Capture screenshots at t≈500ms / t≈1500ms / t≈3500ms via `xcrun simctl io booted screenshot`.

## Observations

- **Bug #187 fix lands cleanly**: search returns results for the mini-epub3 fixture on first attempt after install + reset + seed + open. Prior rounds attempted this exact path with EPUB books and got zero results because the BackgroundIndexingCoordinator actor was deallocated before its detached task ran. The strong-self capture fix (v3.21.51) restored expected behavior.
- **Cross-chapter navigation works**: tap-result→navigate transition is clean. The reader's chrome chapter label correctly flipped from "1 of 2 — Chapter One" to "2 of 2 — Chapter Two".
- **Highlight visibility could not be confirmed**: this is the bug #182 fix verification. Three captures within the 3-second auto-clear window returned BYTE-IDENTICAL frames (the simctl frame buffer had not changed in 3+ seconds). The frames showed empty content area with chrome visible. Faint "End of fixture." was visible at top-left, which is the LAST line of chapter 2 — suggesting scroll position might have been at the end-of-chapter rather than at the matched word. Cannot conclusively say whether the deferred-eval JS executed but produced no visible paint, or never fired.
- **Chrome bar overlap**: the iPhone 17 Pro top chrome (search/bookmark/list/speaker/AA icons) occupies ~150-200px of vertical space. Chapter 2's content (3 short paragraphs) fits in roughly the same space. With chrome visible, the matched-word area is effectively occluded — visual highlight inspection requires chrome OFF, but toggling chrome counts as a "next action" that triggers feature #5 auto-dismiss.
- **Identical-frame captures hint at slow render settle**: 3 captures spanning 3 seconds returned the same byte sequence. This suggests the WKWebView didn't repaint between t=500ms and t=3500ms after the URL change. Either the render was hung or the simctl frame buffer caches longer than expected.

## Artifacts

- `dev-docs/verification/artifacts/feature-2-r4-01-search-result-cross-chapter-20260514.png` — pre-tap, search panel showing the cross-chapter result for "navigation".
- `dev-docs/verification/artifacts/feature-2-r4-02-after-tap-t0500ms-20260514.png` — t≈500ms post-tap; reader on Chapter 2 chrome visible, content area empty, faint "End of fixture." visible top-left.
- `dev-docs/verification/artifacts/feature-2-r4-03-after-tap-t1500ms-20260514.png` — t≈1500ms; **byte-identical to t=500ms**.
- `dev-docs/verification/artifacts/feature-2-r4-04-after-tap-t3500ms-after-autoclear-20260514.png` — t≈3500ms; **also byte-identical**.
- `dev-docs/verification/artifacts/feature-2-r4-05-final-chrome-on-ch2-20260514.png` — final state with chrome visible, scroll position appears at ~70% (4m read), suggesting some scroll-to-end behavior happened post-tap.

## Verdict

`partial` — the **bug #187 close-gate verification is essentially achieved by this round** (search now returns results on the EPUB path; the original repro of bug #187 is observably gone). However, **feature #2 EPUB-leg verification remains incomplete** because the yellow-highlight render slice is inconclusive. The bug #182 fix (deferred pendingHighlightJS) is on the code path; whether it produced a visible yellow highlight on "navigation" within the 3-second window is unverified.

**Recommended next round**: use the DebugBridge eval bridge to query the rendered DOM directly post-tap (`vreader-debug://eval?bridge=epub&js=document.body.innerHTML`) to see if the highlight span was injected. That bypasses the visual-capture timing issue. Alternatively, use a larger EPUB fixture where chapter 2 content extends beyond the chrome bar's coverage area so the matched word is visible without toggling chrome.

Feature #2 stays at `DONE`. Bug #187's close-gate verification can proceed — search returning results on a freshly-seeded EPUB is direct evidence the fix held.
