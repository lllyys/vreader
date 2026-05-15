---
kind: feature
id: 53
status_target: VERIFIED
commit_sha: 3026aa1c46e277725eb162498c0c27a7cb5b5113
app_version: 3.23.3 (build 380)
date: 2026-05-16
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.5
build_configuration: Debug
backend: n/a
result: partial
---

# Feature #53 — Tap on highlighted text to get inline edit/delete options (Round 2 device verify)

Round-2 device verify post Bug #202 / GH #740 fix shipped at v3.23.3. Same-session bugfix cron addressed the chapter-mode TXT path missing `persistedHighlightLookup`, `highlightActionPresenter`, and `onHighlightTapAction` parameters. This round verifies the fix end-to-end on the merged build + tests the menu visibility issue that round-1 surfaced.

## Acceptance criteria

| Criterion | Tested format | Observed | Pass/Fail |
|---|---|---|---|
| (a) Tapping a highlighted word shows a menu with at minimum a Delete option | TXT chapter mode | Tap on yellow "Prince" (Chapter 1) and "Pavlovna's" (Chapter 2): chrome stays ON (no toggle) — hit-test path fires + early-return suppresses chrome-toggle. **BUT**: no inline edit/delete menu visibly appears. `UIEditMenuInteraction.presentEditMenu(with:)` is invoked but the popover never surfaces. Two confirmation screenshots (CU + simctl io). | **FAIL** — filed as Bug #203 / GH #743 (separate root cause: UIEditMenuConfiguration.sourcePoint coordinate-space mismatch) |
| (b) Delete removes the highlight visually and from persistence | TXT | Cannot test until (a) passes. | **DEFERRED** |
| (c) Consistent across all 5 formats | All | TXT shows the menu-invisibility issue; same presenter likely affects MD/EPUB/PDF. AZW3 still blocked by Bug #201. | **DEFERRED** |
| (d) Tapping non-highlighted text preserves existing scroll/chrome-toggle behavior | TXT chapter mode | Tap on non-highlighted text (e.g. (260, 320) middle of body paragraph): chrome correctly toggles. Bug #202 fix preserves this behavior — the hit-test only short-circuits when the tap lands inside a painted highlight. | **PASS** |
| (Bug #202 sub-claim) Hit-test path fires on tap-on-highlight in chapter mode | TXT chapter mode | Tap on yellow "Prince" no longer toggles chrome (was: did toggle on v3.23.1; see PR #741 round-1 evidence). Bug #202 fix's `chapterReaderContent` parameter wiring is functioning end-to-end. | **PASS** |

## Commands run

```bash
# Build + install fresh v3.23.3 (post-merge of PR #742)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
    -project vreader.xcodeproj -scheme vreader \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
APP_PATH="/Users/ll/Library/Developer/Xcode/DerivedData/vreader-hdhlhcqmxppsadhececcxeadpkvz/Build/Products/Debug-iphonesimulator/vreader.app"
xcrun simctl terminate booted com.vreader.app
xcrun simctl install booted "$APP_PATH"  # md5 matches build product
xcrun simctl launch booted com.vreader.app

# Reset + seed TXT
xcrun simctl openurl booted "vreader-debug://reset"
xcrun simctl openurl booted "vreader-debug://seed?fixture=war-and-peace"

# CU drove the rest:
# - Tap book cover (170, 290) → reader opens at title page
# - Tap Next (385, 677) → Chapter 1 body
# - Long-press "Prince" (190, 243) → selection menu Highlight/Add Note/Define
# - Tap Highlight (167, 283) → yellow paint applied
# - Tap elsewhere to clear selection
# - Tap on yellow "Prince" (183, 244) — TWO observations:
#     (a) chrome does NOT toggle (Bug #202 fix correct)
#     (b) menu does NOT visibly appear (Bug #203)

# Snapshot confirmation
xcrun simctl openurl booted "vreader-debug://snapshot?dest=feat53-r2-after-highlight.json"
# → highlightCount: 1, format: txt, currentBookId: txt:bd8285a8...:1705
```

## Observations

1. **Bug #202 fix is functioning correctly.** The chrome-toggle suppression is empirically confirmed on the merged build — tap on a painted highlight in TXT chapter mode no longer falls through to `TXTBridgeShared.postContentTappedNotification()`. The fix's "hit-test happens, early-return suppresses chrome-toggle" path is firing as designed.

2. **A separate, deeper bug has been exposed.** Pre-Bug-#202-fix, the chapter-mode path never reached `presenter.present(...)` at all (lookup was empty → hit-test always nil → chrome-toggle fall-through). The chrome-toggle masked the next-layer bug: `UIEditMenuConfiguration.sourcePoint` is consumed as interaction-view space, but `event.sourceRect` is window-space (set by `textView.convert(viewRect, to: nil)` in `resolveHighlightTap`). The popover is invoked but anchored at an unrenderable point.

3. **Unit tests don't catch this.** `TXTBridgeHighlightTapSubscriberTests` uses a `FakePresenter` that bypasses `UIEditMenuInteraction` entirely. The real iOS UIEditMenuInteraction code path has no unit test coverage; it requires either an integration test with a window-attached textView OR device verification.

4. **Likely a cross-format issue.** `UIKitHighlightActionPresenter` is shared across TXT, MD, EPUB, PDF (and Foliate via Bug #199). The same coordinate-space bug almost certainly applies to MD/EPUB/PDF. Foliate uses `sourceRect: .zero` intentionally (Bug #199 known follow-up — menu anchors at view origin), so its bug is "wrong position" not "invisible". A clean fix to Bug #203 likely improves all formats simultaneously.

5. **Verify-cron stayed strictly in scope.** Bug #203 was filed (GH #743 + docs/bugs.md row), not fixed.

## Artifacts

- `dev-docs/verification/artifacts/feature-53-r2-txt-tap-on-highlight-fast-20260516.png` — TXT Chapter 2 with "Pavlovna's" highlighted yellow, post tap-on-highlight, no menu visible. Captured via `simctl io booted screenshot` for fastest timing.

## Status implication

Feature #53 row stays at `DONE`. Path to `VERIFIED` (cumulative for all rounds):
1. Bug #201 / GH #739 (AZW3 selection wiring) — feature-class, unblocks AZW3 slice.
2. Bug #202 / GH #740 (TXT chapter-mode hit-test) — **FIXED + verified pre-merge for criterion (d) + the chrome-toggle suppression sub-claim**.
3. **Bug #203 / GH #743 (UIEditMenuConfiguration coordinate-space)** — new this round, blocks menu visibility for TXT (and likely MD/EPUB/PDF).
4. Subsequent rounds for MD/EPUB/PDF cross-format coverage.

Bug #202's `awaiting-device-verification` label can be partially-cleared: the chrome-toggle suppression is verified; the menu-appearance portion is now blocked on Bug #203 — leaving the label in place keeps it queryable.

GH #596 (Feature #53) stays open with `awaiting-device-verification`. Bug #199 / GH #733 close-gate still blocked on Bug #201.
