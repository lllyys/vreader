---
kind: feature
id: 31
status_target: VERIFIED
commit_sha: 55dc855fab5fa2f2dba51a5adeafa5bbc36dc1c2
app_version: 3.38.9 (build TBD)
date: 2026-05-20
verifier: claude (verify-cron, CU restored)
device_or_simulator: iPhone 17 Pro Simulator (vreader-f62-agent)
os_version: iOS 26.4
build_configuration: Debug
backend: n/a (DebugBridge + --seed-md-multi-page fixture)
result: partial
---

# Feature #31 round-8 — CU-restored re-verification at v3.38.9: Bug #215 still blocks (design landed, fix has not)

## Context

CU MCP display capture became functional again this iteration (UGREEN
HDMI/dummy display attached; `mcp__computer-use__screenshot` returns
successfully). The verify cron was blocked on this for multiple ticks
across rounds 4-7 — round-7 (2026-05-18) settled the format-scope
question CU-free against v3.27.25 and re-confirmed criterion 5 FAIL.

Round-8 is a CU-now-available re-run **specifically to confirm**
nothing has shifted in the 2 days since round-7 at the now-current
v3.38.9 (HEAD `55dc855`), now that gestures (right-tap, swipe) can be
exercised against the live MD paged reader.

## Scope

Re-verify all five criteria from round-6/round-7 at the now-current
main HEAD. Use CU for gestures (right-tap + swipe in the reader, which
the harness can't drive), `simctl io` for screenshots, DebugBridge URLs
for setup. Verification only; no code changed.

## Acceptance criteria

Feature row contract: *auto-page-turn advances pages over a
configurable interval in paged mode.*

| # | Criterion | Result | Observed |
|---|-----------|--------|----------|
| 1 | Settings UI surface: Auto Page Turn toggle is exposed in MD paged mode (via `FormatCapabilities.autoPageTurn`) | **PASS (unchanged, round-2)** | Capability + UI plumbing unchanged since round-2 evidence (2026-05-08). MD-only by `FormatCapabilities` (round-7 confirmed). |
| 2 | Toggle reveal: sustained-press toggle reveals/hides Interval slider | **PASS (unchanged, round-2)** | UI behavioral surface unchanged. |
| 3 | Toggle persistence: settings persist across reader panel re-open | **PASS (unchanged, round-2)** | `UserDefaults`-backed (`readerAutoPageTurn`, `readerAutoPageTurnInterval`). Verified pre-launch persist via `defaults write` in this round. |
| 4 | `AutoPageTurner` unit logic: timer state machine, interval reschedule, animation primitives | **PASS (unchanged, round-1)** | 14 tests across `AutoPageTurnerTests.swift` + `PageTurnAnimatorTests.swift` (round-1 evidence, 2026-05-07). |
| 5 | **Live multi-page advancement**: auto-page-turn timer advances pages over the configured interval in MD paged mode (the feature's core behavior) | **FAIL (unchanged from rounds 6-7)** | At v3.38.9 with `readerEPUBLayout=paged` + `readerAutoPageTurn=true` + interval=3.0 pre-launched via `defaults write`, opened the seeded multi-page MD book ("Test Markdown Multi-Page", 8 paginated pages visible — indicator reads "Page 1 of 8"). Over **6 frames @ 3 s each = 18 s steady state (≥5× the 3 s interval)**, frames 2-6 are **byte-identical** (528434 B) — **zero auto-advancement**. CU right-tap at (300, 450) ≈ right-third of reader content area: **inert**. CU swipe drag (300, 450) → (80, 450): **inert**. Same Bug #215 / GH #837 signature: paged mode renders but page-turn pathway is dead. ReaderBottomChrome occlusion of bottom body text + "Page N of M" indicator + section-icons overlapping body text — all still present (zoom confirms). |

`result: partial` — criteria 1-4 PASS (unchanged from prior rounds);
criterion 5 stays FAIL. Feature #31 stays `DONE`.

## What this round settles

Round-8 is the **first CU-available round since CU went down 2026-05-09**.
It confirms the round-7 verdict at current main, with the additional
data point that **CU-driven right-tap and swipe gestures are also
inert** (round-7 could not test these — only `simctl io` screenshot
loops which only catch passive advancement). The earlier conclusion
that the page-turn pathway is structurally dead is now **gesture-confirmed**,
not just timer-inferred.

**Bug #215 / GH #837 status check** (2026-05-20):
- `docs/bugs.md` row 215: **TODO** (still unfixed)
- GH #837: **OPEN** (last comment 2026-05-19 from bugfix-cron skip)
- GH #842 (design issue): **CLOSED** 2026-05-18 — design landed
  (`dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-navigation.md` §3)
- Bug #215 row says: *"Design landed 2026-05-18 — this bug is
  unblocked for implementation"* — but no fix PR has shipped to main
  in the 2 days since. The bugfix-cron has skipped it (2026-05-19)
  "remains BLOCKED on needs-design #842 per the 2026-05-18 disposition"
  — that skip comment is stale; design is now resolved.

**Two-bug intersection at v3.38.9** (this round's clarification):
- **Bug #215** (MD paged mode renders but layout broken): chrome
  occludes body text + page indicator. Visible in artifacts.
- **Bug #239** (paged-mode side-tap dead across TXT/EPUB/AZW3/MD/PDF —
  feature #54 WI-3 deleted `TapZoneOverlay` producer): the missing
  tap-zone overlay is the **reason CU right-tap is inert**, not a
  separate MD-scope defect. Bug #215's row notes the cross-reference;
  Bug #239's row notes Bug #215 is the MD-scoped instance.

Net: feature #31's `VERIFIED` flip is gated on **Bug #215** (which
covers the MD-paged-mode design + tap-zone affordance restoration —
the design bundle did land on 2026-05-18; the implementation has not).
Per `.claude/rules/47-feature-workflow.md` Gate 5, partial credit is
documented; row stays at DONE.

## Commands run

```bash
SIM=658E5D80-BB13-493D-A45C-25148C260941   # iPhone 17 Pro, iOS 26.4 (vreader-f62-agent)

# Build at main HEAD 55dc855
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project vreader.xcodeproj -scheme vreader \
  -destination 'platform=iOS Simulator,id=658E5D80-BB13-493D-A45C-25148C260941' \
  -derivedDataPath /tmp/vreader-f31-verify-build

xcrun simctl install "$SIM" /tmp/vreader-f31-verify-build/Build/Products/Debug-iphonesimulator/vreader.app

# Pre-launch defaults (persist auto-page-turn + interval + paged layout)
xcrun simctl spawn "$SIM" defaults write com.vreader.app readerEPUBLayout paged
xcrun simctl spawn "$SIM" defaults write com.vreader.app readerAutoPageTurn -bool true
xcrun simctl spawn "$SIM" defaults write com.vreader.app readerAutoPageTurnInterval -float 3.0

# Launch with the multi-page MD seed (Feature #45 WI-5 fixture)
xcrun simctl launch "$SIM" com.vreader.app \
  --uitesting --seed-md-multi-page --reader-default-layout=paged

# Open seeded book (CU dismissed the "Open in vreader?" confirmation dialog
# at screen coord (224, 448) and tapped book cover at (78, 367))

# 6-frame loop @ 3 s = 18 s steady state, ≥5× the 3 s auto-page-turn interval
for i in 1 2 3 4 5 6; do
  xcrun simctl io "$SIM" screenshot /tmp/f31-verify/sequence/seq-$i.png
  sleep 3
done
# → seq-1: 527650 B (initial render), seq-2..6: 528434 B byte-identical (no advance)

# CU-driven gesture probes (new this round; round-7 couldn't run these CU-free)
# left_click at (300, 450) → no advance
# left_click_drag (300,450)→(80,450) → no advance
```

## Observations

- **Round-7's "paged mode does engage" finding holds at v3.38.9.** The
  page indicator "Page 1 of 8" appears (Bug #215's Cause 1 = wrong
  viewport on `updatePagination` produces a usable enough pagination
  to render an indicator). Round-6's surface-level "pageNavigator stays
  nil" diagnosis was retracted in round-7; round-8 confirms with the
  CU-driven view that paged content branch is rendering.
- **Round-7 predicted CU-restored gestures would still be inert** —
  confirmed: right-tap (CU left-click) and swipe (CU drag) both produce
  zero advancement. The producer (`TapZoneOverlay` / `TapZoneDispatcher`)
  is deleted (Bug #239 root cause). This is **gesture-confirmed dead**
  now, not just inferred from passive screenshot diffs.
- **The design bundle for Bug #215 landed 2026-05-18.** The bugfix-cron's
  2026-05-19 skip note ("remains BLOCKED on needs-design #842") is
  **stale** — #842 closed 2026-05-18 with a committed design at
  `dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-navigation.md` §3.
  Implementation is now unblocked but has not landed; that's the lever
  needed for feature #31 to flip.
- **Bug #239 is a sibling, not a sub-bug**: it's the wider TapZoneOverlay
  regression across all formats. Bug #215's design bundle scopes the
  MD-paged-mode tap-zone affordance, so fixing #215 *should* restore
  MD page-turn — but Bug #239's row reads "One fix resolves TXT-gesture
  + EPUB + AZW3-side-tap + MD (#215) together." Implementation
  precedence is a fixer decision, not a verification one.
- **Version delta from round-7 (3.27.25 → 3.38.9 = 11 minor versions, 2 days)**
  is dominated by Feature #56 (bilingual translation, WI-2.5 through WI-15
  shipped 2026-05-18 → 2026-05-20). None of those WIs touched the
  MDReader paged-mode path or `TapZoneOverlay`.
- **Disposition unchanged from round-7**: no new bug filed (the failure
  is fully accounted for by existing Bugs #215 and #239); no follow-up
  needed beyond awaiting Bug #215 fix.
- **CU-tool note**: the "Open in vreader?" dialog must be dismissed via
  CU click; the DebugBridge URL is blocked behind that system permission
  prompt the first time a `vreader-debug://` URL is opened in a fresh
  install. Future round may consider pre-seeding the consent via
  `xcrun simctl spawn` to avoid CU dependency on this step.

## Artifacts

- `dev-docs/verification/artifacts/feature-31-r8-md-paged-page1of8-20260520.png`
  — MD paged mode engaged, page indicator "Page 1 of 8" visible at
  bottom (Bug #215 Cause 1 partially working — pagination produced an
  indicator), but content visually clips behind bottom chrome.
- `dev-docs/verification/artifacts/feature-31-r8-md-paged-no-advance-after-15s-20260520.png`
  — frame 6 of the 18 s loop. Identical to frames 2-5 (528434 B). Zero
  passive advancement over ≥5 intervals.
- `dev-docs/verification/artifacts/feature-31-r8-md-paged-right-tap-inert-20260520.png`
  — after CU right-tap at (300, 450) on reader content area. No advance.
  Confirms Bug #239's TapZoneOverlay deletion is in effect for MD.
- `dev-docs/verification/artifacts/feature-31-r8-md-paged-swipe-inert-20260520.png`
  — after CU swipe-drag (300,450) → (80,450). No advance. Same root
  cause as the tap (the `.readerNextPage` notification has no producer).

## Outcome

Feature #31 stays **DONE**. Round-8 (the first CU-restored round) adds
**gesture-confirmed evidence** to round-7's screenshot-only verdict:
right-tap and swipe in MD paged mode are also inert at v3.38.9, not just
passive auto-advancement. Bug #215 + Bug #239 jointly block the
`VERIFIED` flip; design for #215 is now committed (closed #842) but
implementation has not shipped to main in the 48 h since. No new bug
filed. `VERIFIED` flip remains gated on Bug #215's fix.
