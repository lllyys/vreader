---
kind: feature
id: 53
status_target: DONE
commit_sha: cfab8c507b4c3a92e8a17ea51c5d1a72f5e44a06
app_version: 3.23.9 (build 386)
date: 2026-05-16
verifier: claude (verify-cron)
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.5
build_configuration: Debug
backend: n/a (DebugBridge + bundled war-and-peace.txt fixture)
result: partial
---

# Feature #53 round-3 device verification (Bug #203 close-gate)

Picks up the Feature #53 round-2 deferred slice (`feature-53-20260516-round2.md`,
result=partial). Round-2 filed Bug #203 (UIEditMenuConfiguration sourcePoint
coord-space mismatch); that fix shipped in v3.23.7 (commit `abbbac4`, PR #748).
Round-3 re-runs the TXT acceptance criterion (a) repro on a fresh post-fix build
to determine whether the menu now appears visibly anchored over the tapped
highlight.

## Acceptance criteria (subset under test this round)

| Criterion | Observed | Pass/Fail |
|---|---|---|
| (a) TXT minimum: tapping a highlighted word shows a menu with at minimum a Delete option | Bug #202 chrome-toggle suppression confirmed (chrome stays off after tap-on-yellow); `highlightCount=1` confirmed via DebugBridge snapshot; but menu still **NOT visible**. `[com.apple.UIKit:EditMenuInteraction]` logs `Error`-level events at the present call site. | **FAIL** (distinct latent issue — filed as Bug #205) |

Other acceptance criteria for Feature #53 (MD/EPUB/PDF/Foliate paths) NOT exercised this round — TXT was the round-2 target and remains the only one verified end-to-end. Round-4 will cover them after Bug #205 is FIXED.

## Commands run

\`\`\`bash
# Build clean from main (commit cfab8c5, v3.23.9 / build 386)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project /Users/ll/workspace/vreader/vreader.xcodeproj -scheme vreader \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/vreader-verify-build
xcrun simctl install booted /tmp/vreader-verify-build/Build/Products/Debug-iphonesimulator/vreader.app

# Verify install version (build 386 = v3.23.9)
xcrun simctl listapps booted | grep -A 5 "com.vreader.app\"" | grep CFBundleVersion

# Seed + open
xcrun simctl openurl booted "vreader-debug://reset"
xcrun simctl openurl booted "vreader-debug://seed?fixture=war-and-peace"
xcrun simctl launch booted com.vreader.app

# Tap book card (CU) → reader opens at chapter 1 page 1/4
# Tap Next → page 2/4 (text content visible: "Well, Prince, so Genoa...")
# Long-press at (181, 243) → custom selection menu (Highlight/Add Note/Define/▶) visible
# Tap Highlight at (170, 284) → "Prince" rendered yellow

# Verify highlight persisted
xcrun simctl openurl booted "vreader-debug://snapshot?dest=verify-post-tap.json"
cat \$(xcrun simctl get_app_container booted com.vreader.app data)/Library/Caches/DebugBridge/verify-post-tap.json
# → highlightCount: 1 ✓

# Dismiss selection via neutral tap → chrome toggled off (confirms Bug #202 fix path)
# Tap on yellow "Prince" at (185, 243) — repeat
# Confirm via CU screenshot — menu does NOT appear

# Check iOS log for UIEditMenuInteraction events
xcrun simctl spawn booted log show --last 1m --predicate 'process == "vreader"' | grep -i EditMenuInteraction
# → 2 Error events correlated with the tap-on-yellow timestamps
\`\`\`

## Observations

- **Bug #202's chrome-toggle suppression IS active**: tapping on yellow "Prince" does NOT toggle the reader chrome (the chrome had been hidden by the prior neutral-area tap and STAYED hidden after the tap-on-yellow). This confirms the tap is reaching `TXTTextViewBridge.Coordinator.handleContentTap`'s hit-test path and short-circuiting before `TXTBridgeShared.postContentTappedNotification()` (chrome-toggle).
- **Bug #203's coord-space fix shipped**: the source produces `viewRect` (textView-local) instead of `windowRect` (window-space). Verified via the regression-guard test `resolveHighlightTap_returnsViewLocalRect_notWindowSpace` (passing in PR #748).
- **The menu still doesn't appear**, and iOS subsystem `[com.apple.UIKit:EditMenuInteraction]` logs `Error`-level events at each tap-on-yellow attempt. The error body is privacy-redacted (`<compose failure>`), but the severity + subsystem confirm UIKit is rejecting the `interaction.presentEditMenu(with: cfg)` call.
- **Likely root cause** (suspect, not confirmed by fix-attempt): the presenter at `HighlightActionPresenter.swift:118-124` adds a `UIEditMenuInteraction` to the textView and presents the menu synchronously in the same call. The TXT non-chunked path passes the `HighlightableTextView` as the host view. UITextView already owns its own internal `UIEditMenuInteraction` for selection handling — a second one may conflict, producing the UIKit rejection.

## Filing decision

Per verify-cron scope guard: "If you discover a bug during verification, FILE it but DO NOT fix it." Filed **Bug #205 / GH #751** — UIEditMenuInteraction Error + menu invisible despite Bug #203 fix. Bug #205 is a distinct latent issue exposed by the Bug #203 fix landing; the coord-space change took the failure from "anchored off-screen due to wrong coords" to "rejected by UIKit before display."

## Verdict

- Feature #53 row stays at **DONE** (not VERIFIED). Acceptance criterion (a) still fails for TXT pending Bug #205 fix.
- Bug #203 close-gate verify is `partial` — the shipped fix DID land and works for what it was scoped to (the coord-space contract), but the user-visible end-to-end behavior is blocked by Bug #205. Bug #203 row stays FIXED (the fix it shipped is correct); the awaiting-device-verification close-gate is replaced with a comment cross-referencing Bug #205.
- Round-4 deferred until Bug #205 is FIXED + a similar device-verify reproduces the menu visibly.

## Artifacts

- `dev-docs/verification/artifacts/bug-203-verify-01-reader-open-20260516.png` — Library + Reader baseline post-launch.
- `dev-docs/verification/artifacts/bug-203-verify-02-after-launch-20260516.png` — Library view, war-and-peace seeded.
- `dev-docs/verification/artifacts/bug-203-verify-03-prefix-yellow-pre-tap-20260516.png` — Yellow "Prince" highlight visible, chrome hidden, immediately before the tap-on-yellow.
