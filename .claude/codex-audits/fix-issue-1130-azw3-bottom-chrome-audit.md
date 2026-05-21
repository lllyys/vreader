---
branch: fix/issue-1130-azw3-bottom-chrome
threadId: 019e4b93-bebe-78a2-af25-4c36b84b0382
rounds: 1
final_verdict: ship-as-is
date: 2026-05-22
---

# Codex Audit — Bug #260 / GH #1130: AZW3/MOBI reader mounts bottom chrome

## Scope

Mount the shared `ReaderBottomChrome` (Contents / Notes / Display / AI toolbar +
reading-progress scrubber) on the live AZW3/MOBI Foliate host
(`FoliateBilingualContainerView` → `FoliateSpikeView`), which previously mounted
ZERO bottom chrome. Minimal parity fix matching the four native containers
(EPUB / MD / PDF / TXT) — explicitly NOT a refactor of chrome ownership to the
shared `ReaderContainerView` level.

Files audited:
- `FoliateSpikeView.swift` (relocate forwards `fraction`/`tocLabel`/`sectionTotal`; new `.foliateRequestSeekFraction` observer → `readerAPI.goToFraction`)
- `FoliateBilingualContainerView.swift` + `FoliateBilingualContainerView+BottomChrome.swift` (mounts `ReaderBottomChrome`, own `isChromeVisible` synced to `.readerContentTapped`, progress from relocate fraction, seek poster)
- `FoliateBottomChromeSeek.swift` (pure clamped goToFraction JS builder)
- `FoliateBottomChromeLabels.swift` (pure position-label formatter)
- `ReaderContainerView.swift` (threads `ttsService`)
- `ReaderNotifications.swift` (new `.foliateRequestSeekFraction`, updated `.foliateRelocated` doc)

## Round 1 findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| `FoliateBilingualContainerView.swift:148`, `ReaderContainerView.swift:273,807` | High | Foliate bottom chrome does not share the top chrome's source of truth. When the More popover is open, `ReaderContainerView`'s `.readerContentTapped` handler closes the popover WITHOUT toggling top chrome, while the container blindly toggles its own `isChromeVisible` → top/bottom desync. | **Accepted — pre-existing across all 5 formats, fixed by scope.** Verified the four native containers (`EPUBReaderContainerView.swift:251`, `TXTReaderContainerView.swift:567`, `MDReaderContainerView.swift:252`, `PDFReaderContainerView.swift:244`) use the IDENTICAL blind `isChromeVisible.toggle()` on `.readerContentTapped` with their own local `@State`. My Foliate container faithfully replicates that pattern — it does not introduce the desync. The correct fix (hoist chrome visibility to the shared level) is the refactor the bug brief explicitly prohibits; a Foliate-only fix would diverge from the 4 native containers. Codex agreed: "ship parity now, file a separate cross-format bug, fix it uniformly later." → filed as follow-up. |
| `ReaderTOCBuilder.swift:21`, `FoliateTOCConverter.swift:15` | High | `Contents` is hollow for AZW3/MOBI: `ReaderTOCFactory.buildTOC` has no azw3/mobi branch (falls to `default: []`), so the live Foliate TOC sheet shows the empty state. The live `FoliateSpikeView.onBookReady` also drops the parsed `toc` (passes only `title`). | **Accepted — pre-existing AZW3 gap, deferred to follow-up.** Independent of this bug (which is "the bottom bar never MOUNTS"). The mount delivers a working scrubber + Display + AI + Notes-listing; Contents-data is a separate defect. Filed in the follow-up bug. |
| `ReaderContainerView+Sheets.swift:423,443`, dead `FoliateReaderContainerView.swift:87` | High | `.readerNavigateToLocator` / `.readerPositionDidChange` are only observed/produced by the DEAD `FoliateReaderContainerView`, never the live `FoliateBilingualContainerView`. So sheet-driven locator navigation (TOC row tap, Notes/Highlight row tap → jump into content) is not end-to-end on the live Foliate path. | **Accepted — pre-existing AZW3 gap, deferred to follow-up.** Notes panel opens + lists AZW3 highlights (format-agnostic `HighlightListViewModel` by fingerprintKey + feature #64 persistence), but jumping FROM a row back into content is unwired. Independent of the bottom-chrome mount. Filed in the follow-up bug. |

No Critical findings. No Medium/Low findings.

## Code-defect verdict (the written diff)

Codex confirmed (explicit yes/no): **zero must-fix issues in the written mount /
relocate / seek / observer / labels diff.** Specifically validated:
- Bottom-chrome mount is correct; no duplicate mount on the live Foliate path.
- Scrubber binds to a REAL Foliate progress source (relocate `fraction` →
  `FoliateMessageParser` → `.foliateRelocated` → container binding).
- `Display` (`.readerOpenDisplay` → `showSettings`) and `AI` (`.readerOpenAI` →
  `showAIPanel`) routing correct via `ReaderContainerView`'s existing observers.
- No new Swift 6 concurrency / actor-isolation hazard in the `nonisolated(unsafe)`
  token + `.main` queue + `MainActor.assumeIsolated` seek observer.
- No JS-injection hazard in the `goToFraction` seek bridge (Double arg, NaN/inf
  clamped to a finite 0...1 literal).

## Scope resolution (confirmed with Codex)

This PR is an **incremental "mount the missing Foliate bottom chrome" delivery**:
- Mergeable now: yes.
- `#260` FIXED scoped to "bottom chrome was missing and now mounts" (the reported
  symptom "azw3 didnt show the botton bar"): defensible.
- A follow-up bug is filed for the remaining live-Foliate TOC data + locator
  navigation + cross-format chrome-desync gaps.
- The PR body + GH closure language stay precise — NO claim of full Foliate
  bottom-chrome parity until the follow-up lands.

## Verdict

**ship-as-is.** All three High findings are pre-existing gaps resolved by scope
discipline (parity + a filed follow-up bug), not defects in this diff. The mount,
progress source, seek bridge, toolbar wiring, and concurrency are correct as
written.
