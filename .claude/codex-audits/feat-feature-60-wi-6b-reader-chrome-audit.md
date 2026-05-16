---
branch: feat/feature-60-wi-6b-reader-chrome
threadId: 019e2ff9-609f-7163-82e7-e27d1aac117e
rounds: 2
final_verdict: ship-as-is
date: 2026-05-16
---

# Codex Audit — Feature #60 WI-6b reader top + bottom chrome re-skin

## Round 1 — 2 Medium, 3 Low

### Medium #1 — toolbar notifications unscoped (multiwindow cross-scene leak)
- **`ReaderBottomChrome.swift` / `ReaderContainerView.swift`** | Medium
  The four `.readerOpen*` toolbar notifications carry no reader
  identity, so in a multiwindow / multiple-`ReaderContainerView`
  configuration one tap would open sheets in every mounted reader.

**Resolution**: Accepted with rationale. WI-6b's four notifications
follow the existing reader-notification-bus pattern — `.readerContentTapped`,
`.readerBookmarkRequested`, `.readerPreviousPage`, `.readerNextPage`,
`.readerNavigateToLocator` are all global, nil-payload, unscoped. The
cross-scene leak already exists for those ~15 notifications; scoping
the bus by `fingerprintKey`/`readerToken` is a bus-wide architectural
change, not a WI-6b regression, and a simultaneous two-reader
configuration is not a currently supported mode. Codex round 2:
*"your rationale is correct ... Treating that as a bus-wide follow-up
rather than a WI-6b-specific blocker is defensible."*

### Medium #2 — zero bottom-safe-area fallback too low
- **`ReaderBottomChrome.swift`** | Medium
  Fallback bottom padding was `12`, but the design baseline is
  `paddingBottom: 28` — on zero-inset layouts the chrome sat 16pt too
  low.

**Resolution**: Fixed. Fallback is now `max(windowSafeAreaBottom, 28)`
— home-indicator devices still get the real (~34) inset; zero-inset
layouts hold the 28pt design baseline. Codex round 2 confirmed.

### Low #3 — toolbar label color flattened
- **`ReaderBottomChrome.swift`** | Low
  Non-accent toolbar buttons drew icon + label both in `inkColor`;
  the design renders non-primary labels in the dimmer `sub` token.

**Resolution**: Fixed. `toolbarButton` colors icon and label
separately — non-accent: icon `ink`, label `sub`; accent (AI): both
`accent` — matching `vreader-reader.jsx`. Codex round 2 confirmed.

### Low #4 — `ReadingProgressBar` is now a dead View
- **`ReadingProgressBar.swift`** | Low
  After the swap, `ReadingProgressBar`'s `View` body has no
  composition site; only its `clampedProgress` / `resolveSeekValue` /
  `formatLabel` statics are reused.

**Resolution**: Accepted with rationale. The statics are the live,
tested surface that `ReaderBottomChrome`'s scrubber reuses; the View
struct is retained as their home. Extracting the statics into a
non-View utility + migrating `ReadingProgressBarTests` is a mechanical
follow-up, not a correctness fix. Codex round 2: *"dead as a composed
View, but not dead as code ... reasonable for this slice."*

### Low #5 — docs-sync incomplete
- **`docs/architecture.md`** | Low
  The system diagram + Chrome section still named `ReaderChromeBar`.

**Resolution**: Fixed. The diagram and Chrome section now describe
`ReaderTopChrome` + `ReaderBottomChrome`; the Notification Bus table
already lists the four `.readerOpen*` notifications.

## Round 2 — clean

Codex verified the two fixes correct, the two acceptances reasonable,
and found no new issue: *"I do not see a new issue introduced by these
follow-up changes."*

## Verdict statement

**ship-as-is** after round 1 (2 Low + 1 Medium fixed; 1 Medium + 1 Low
accepted with rationale). Round 2 clean.

## Audit dimensions

1. Correctness vs design — matches `vreader-reader.jsx` `ReaderTopChrome`
   + `ReaderBottomChrome` after the round-1 color fix.
2. Edge cases — scrubber `DragGesture` width-0 guard correct; 0-progress
   handled; PDF discrete-step snapping correct; safe-area zero-inset
   fixed in round 1.
3. Concurrency — clean. `ReaderSafeAreaResolver.windowSafeAreaBottom`
   is `@MainActor`, read from SwiftUI `body` — fine.
4. Regression — chapter navigation still fully reachable after
   removing EPUB/TXT-chapter inline prev/next: TXT TOC uses the same
   decode/regex path; EPUB chapter jumps remain reachable via TOC +
   scrubber. `navigateChapter` / `currentChapterTitle` deletion
   orphaned nothing (no remaining caller).
5. Dead code — `ChapterBottomOverlay` + `navigateChapter` +
   `currentChapterTitle` removed; `ReadingProgressBar` View retained
   for its statics (Low #4, accepted).
6. Duplicate code — the 4 per-format `ReaderBottomChrome(...)` call
   sites are acceptable: the seek/progress wiring is genuinely
   format-specific.
7. VReader compliance — Swift 6 clean; `ReaderToolbarActionObservers`
   ViewModifier is a sound `body`-complexity workaround; new files
   under the size guideline.
8. Notification bus — `.onReceive` observers are SwiftUI-managed (no
   manual removal needed). Unscoped-notification concern is Medium #1
   (accepted).

## Test results

- Full `vreaderTests` gate: WI-6b code clean — 151 tests + the WI-6b
  suites pass. The only failures were `ReplacementTransformTests`
  (`replace_regex_groupCapture`, `regex_multipleMatches`) — a
  documented pre-existing parallel-execution flake; confirmed
  passing 14/14 in isolation.
- WI-6b test surface: `ReaderChromeButtonContractTests` (updated for
  the `.search` slot — count 4→5) + `ReaderBottomChromeTests` (new — 6
  tests pinning the toolbar button→notification routing).

## Follow-up items

- **Bus-wide notification scoping** (Medium #1): scope the reader
  notification bus by `fingerprintKey`/`readerToken` if multiwindow
  reader becomes a supported configuration. Pre-existing; ~15
  notifications affected.
- **`ReadingProgressBar` statics extraction** (Low #4): move the
  clamp/snap/format statics into a non-View utility + migrate the
  test file; delete the now-uncomposed View.
