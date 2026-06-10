---
kind: feature
id: 31
status_target: VERIFIED
commit_sha: 6936ccf848c75770b0ea1801477e7c0e49ca48fa
app_version: 3.27.23 (build 437)
date: 2026-05-17
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.4
build_configuration: Debug
backend: n/a (bundled multi-page MD fixture)
result: partial
---

# Feature #31 round-6 — criterion 5 disambiguated: MD Paged layout never engages (Bug #215 filed)

## Context

Round-5 (2026-05-15) verified criteria 1-4 and left criterion 5 (live
auto-page-turn advancement) as `deferred`, with three candidate
explanations it could not distinguish from a passive 6-second
screenshot wait:

> Either (a) the MD reader rendered the book in scroll mode despite
> Settings showing Paged, (b) auto-page-turn fired but the
> at-last-page short-circuit triggered, or (c) the chrome rendering
> for MD-paged-mode differs from EPUB-paged-mode...

Round-6 runs the round-5-suggested recipe — right-side-tap probe +
unified-log inspection + direct code/`defaults` reads — to
disambiguate. Verified against current `main` (`6936ccf`, v3.27.23
build 437); the build already installed on the simulator matches
`main` exactly, so no rebuild was needed.

## Acceptance criteria

Feature row contract: auto-page-turn advances pages over a
configurable interval in paged mode.

| # | Criterion | Round-5 | Round-6 |
|---|---|---|---|
| 1 | `--seed-md-multi-page` seeds an MD book that paginates to ≥2 pages | PASS | PASS (library shows "Test Markdown Multi-Page"; reader opens on it) |
| 2 | Pre-launch UserDefaults for auto-page-turn persist through the seed flow | PASS | PASS (`defaults read` → `readerAutoPageTurn=1`, `readerAutoPageTurnInterval=3`) |
| 3 | `--reader-default-layout=paged` applies to MD | PASS | PASS (`defaults read readerEPUBLayout` → `paged`) |
| 4 | Opening the book with paged layout opens cleanly | PASS | PASS (reader opens on Chapter 1, no crash) |
| 5 | Auto-page-turn timer advances pages over a 3-second interval | deferred | **FAIL** — see disambiguation below |

**Overall**: `partial`. Criterion 5 is now definitively FAIL (not
merely deferred): the MD reader does not enter paged mode at all, so
auto-page-turn has nothing to drive. Root cause filed as **Bug #215 /
GH #837**.

## Disambiguation — criterion 5

All three round-5 candidates were tested:

1. **Passive auto-turn** — opened the book, waited 11 s (≥3 × the 3 s
   interval) with no interaction. Content unchanged, progress stayed
   `0%`. (Reproduces round-5.)
2. **Manual right-side tap** — tapped the right third of the viewport
   (the default "next page" tap zone). No page advance, no scroll, no
   chrome toggle.
3. **Scroll / swipe** — a scroll-wheel event and a 310 px swipe-up
   drag both left the content unchanged.
4. **Chrome-responsiveness control** — tapping the "Display" toolbar
   button DID open the Display sheet, proving CU gestures reach the
   simulator and the reader UI is responsive. The static content is a
   real reader-state observation, not a tooling artifact.

The decisive evidence is the rendered chrome itself: the reader shows
a continuous **"0%" scrubber** and the body text is **clipped
mid-line** at the viewport bottom ("...low yellow fields and clumps
of"). `MDReaderContainerView.pagedReaderContent` renders a
`Text("Page X of Y")` indicator and breaks pages on whole lines —
neither is present. The reader is rendering the **scroll-content**
branch.

Code path: `MDReaderContainerView` body —
`if isPagedMode, let nav = uiState.pageNavigator { pagedReaderContent(...) } else { <scroll content> }`.
`isPagedMode` is `settingsStore?.epubLayout == .paged`;
`readerEPUBLayout` is confirmed `paged` at runtime, so `isPagedMode`
is true. The only way the `else` branch renders is
`uiState.pageNavigator == nil`. Auto-page-turn is wired "only when
autoPageTurn enabled + paged layout" (`MDReaderContainerView` header
comment), so a nil navigator means it never engages.

`--uitesting` is ruled out as a confound: the `VReaderApp` code
comment for issue #152 states `--uitesting` "only swaps the SwiftData
store" — it does not disable timers or animations.

## Commands run

```bash
SIM=61149F0E-DC18-4BE2-BB37-52659F1F4F62

# installed build already matches main 6936ccf
xcrun simctl get_app_container "$SIM" com.vreader.app
#   → CFBundleShortVersionString 3.27.23, CFBundleVersion 437  (== project.yml)

xcrun simctl spawn "$SIM" defaults write com.vreader.app readerAutoPageTurn -bool true
xcrun simctl spawn "$SIM" defaults write com.vreader.app readerAutoPageTurnInterval -float 3.0
xcrun simctl terminate "$SIM" com.vreader.app
xcrun simctl launch  "$SIM" com.vreader.app --uitesting --seed-md-multi-page --reader-default-layout=paged

# open the book via computer-use, wait 11 s, observe — content unchanged
# right-tap / scroll-wheel / swipe-up drag via computer-use — content unchanged
# tap "Display" toolbar button — Display sheet opens (UI responsive)

xcrun simctl spawn "$SIM" defaults read com.vreader.app readerEPUBLayout
#   → paged
xcrun simctl io "$SIM" screenshot \
  dev-docs/verification/artifacts/feature-31-r6-md-paged-renders-scroll-20260517.png
```

## Observations

- The MD paged-mode code path (`pagedReaderContent`,
  `NativeTextPagedView`, `NativeTextPageNavigator`) all exist — this
  is a non-functional feature, not a missing one: the navigator is
  never built.
- Bug #157 (FIXED, TXT auto-page-turn) explicitly predicted this:
  "MD reader likely has the same shape but needs a chaptered-MD
  fixture to verify." #157 FIXED the TXT instance via a
  capability-gate and kept `.autoPageTurn` enabled for MD on the
  assumption MD's paged path works. This round is the chaptered-MD
  verification #157 asked for; it shows MD's paged path does not work.
- Net user impact: the Auto Page Turn toggle and the Paged layout
  option are both offered to a Markdown reader, but neither does
  anything — the book always renders in scroll mode.

## Bug filed

**Bug #215 / GH #837** — "MD reader Paged layout never engages —
`pageNavigator` stays nil, renders scroll content; Auto Page Turn +
manual paged navigation both dead for Markdown." Severity Medium.
`docs/bugs.md` row #215 + Open Bug Detail entry. Not fixed this
iteration (verification scope only).

## Artifacts

- `dev-docs/verification/artifacts/feature-31-r6-md-paged-renders-scroll-20260517.png`
  — the MD reader after the 11 s auto-turn wait + manual probes:
  "0%" scrubber, no "Page X of Y", body clipped mid-line. The
  scroll-content render that confirms criterion 5 FAIL.

## Verdict

`partial`. Criteria 1-4 PASS (re-confirmed). Criterion 5 is now
**FAIL** — not the "needs a more targeted verification path" that
round-5 left open, but a confirmed product defect: the MD reader
never enters paged mode, so auto-page-turn cannot run. Feature #31
stays `DONE`; the `VERIFIED` flip is blocked on Bug #215 / GH #837.
Re-verify criterion 5 once #215 is fixed — the same recipe should
then show a "Page X of Y" indicator and a page advancing every 3 s.
