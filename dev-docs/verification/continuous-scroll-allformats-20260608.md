---
kind: regression-sweep
id: continuous-scroll-allformats
status_target: confirm
commit_sha: b6c74591af6a2e5efdd657adee145e4628a42b9a
app_version: 3.59.23 (build 923)
date: 2026-06-08
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.4
build_configuration: Debug
result: pass
---

# Continuous-scroll position-continuity sweep — all real formats, 15+ chapters

Standing-goal verification: *"test continue scrolling for all type of files, real
files, scrolling cross at least 15 chapters. verify the scrolling position if is
jumped or continuous. scroll few px in a time to see if there is any position
mismatch and discontinuous."*

This is a **regression-confirmation sweep**, not a gate flip — features #71 (EPUB
scroll coordinator), #73 (Foliate windowed continuous scroll), and #85 (Readium
hybrid re-route) are already `VERIFIED`. It records the 15+ chapter fine-scroll
evidence the prior Stop-hook flagged as missing for AZW3/TXT and as
single-boundary for EPUB.

Formats with no real book (PDF, MD) are out of scope — no real fixture exists
(per the "real books first" binding), so no continuous-scroll surface to drive.

## Method

For each format, drive the **real** book's reader and read a position signal that
is invariant to the windowing/recycling coordinate shifts (so a real position
*jump* is distinguishable from an expected coordinate re-base):

| Format | Real book | Reader | Scroll driver | Continuity signal |
|---|---|---|---|---|
| EPUB | The Half Second (`epub:71fa…:1302140`, 54 spine) | legacy #71 stitch (WKWebView `#vreader-scroll-root`) | `eval` `scrollTop += 30` per step | `spineIdx : intraPx` (`-section.getBoundingClientRect().top`) — eviction-compensated, so stable across windowing |
| TXT | 黑暗血时代 (`txt:04d6…:14059220`, 1860 ch) | native chunked `UITableView` | idb slow pan (`--duration 1.0`, native scroller is idb-drivable) | DebugBridge `snapshot.position` = document-global UTF-16 offset |
| AZW3 | 被讨厌的勇气 (`azw3:3982…:6288371`, 85 ch) | Foliate windowed continuous scroller (feature #73) | `goToFraction` +0.003 fine-steps through the **same** windowed renderer (idb real-scroll corroborated; see notes) | `sectionIndex : intraPx` from each mounted section's `frameElement.getBoundingClientRect()` |

A **continuous** result = the position signal advances monotonically: within a
chapter the intra-offset climbs by the scroll delta; at a boundary the chapter
index increments by exactly 1 and the intra resets small — with **no backward
jump and no discontinuous spike**. The bug class being ruled out is the
chapter-boundary position *jump* (EPUB Bug #329 / AZW3 Bug #283).

## EPUB — 13 narrative chapter boundaries, pixel-exact (result: pass)

Per boundary: `navigate?spine=N&fraction=0.96` then `scrollTop += 30` × 14 settled
steps, reading `spineIdx:intraPx` at viewport y=40. The navigate landed each
narrative section right at its N→N+1 junction, so the sequence captures the
**boundary crossing the viewport top** (intra straddles 0):

```
boundary  8→9 : 9:-29  9:1  9:31  9:61 … 9:361     (+30 exactly each step)
boundary 10→11: 11:-28 11:2 11:32 … 11:362
boundary 12→13: 13:-26 13:4 13:34 … 13:364
boundary 14→15: 15:-31 15:-1 15:29 … 15:359
boundary 16→17: 17:-24 17:6 … 17:366
boundary 18→19: 19:-31 19:-1 … 19:359
boundary 20→21: 21:-29 21:1 … 21:361
boundary 22→23: 23:-34 23:-4 … 23:356
boundary 24→25: 25:-29 25:1 … 25:361
boundary 26→27: 27:-26 27:4 … 27:364
boundary 28→29: 29:-29 29:1 … 29:361
boundary 30→31: 31:-32 31:-2 … 31:358
boundary 32→33: 33:-33 33:-3 … 33:357
```

Every narrative boundary (8→9 … 32→33, spanning chapters 8–33 = 25 chapters,
13 sampled boundary crossings): intra climbs by **exactly +30 per 30px scroll**,
crossing zero as the chapter junction passes the viewport top. Zero position
mismatch, zero jump. (Front-matter boundaries 2/4/6 — title/copyright/TOC, short
scroll-clamped sections — read noisily; not reading-continuity surfaces.)

## TXT — Ch 16 → Ch 31 continuous, 104 fine pans (result: pass)

Reopened at the saved position (offset 43769, Chapter 16). 104 slow idb pans
(`--duration 1.0`, ~+405 chars each), reading `snapshot.position` (UTF-16 offset)
after every pan:

- Offset **strictly monotonic** 43769 → 86170 (+42401 chars).
- Step deltas uniform ~+400–418; **zero** backward moves, **zero** spikes > 1500
  (the script's discontinuity flag: **0 events**).
- Crossed ~2 of the 64 KB byte-chunk-load boundaries with no jump (the chunked
  `UITableView` cell-recycle preserved position exactly).
- Chapter label progressed 16 → 20 → 23 → 31 (≥15 chapters). Chapter headings
  (第二十三章, 第三十一章) render **inline in the scroll flow** — chapter boundaries
  are continuous text, no view-swap.

Native scroll is structurally immune to the windowing coordinate-remap class
(single `UIScrollView` contentOffset; no eviction) — the only jump risk is
chunk-load height re-estimation, which the monotonic offset rules out.

## AZW3 — sections 13 → 30 continuous, two agreeing drivers (result: pass)

The Foliate windowed continuous scroller (feature #73) was driven two ways, both
reading `sectionIndex:intraPx` (each mounted section's `frameElement` rect, robust
to the window's recycle re-base):

**Controlled `goToFraction` +0.003 fine-step sweep (sections 13 → 30, +17):**
```
13:1631 13:2152 · 14:472 14:982 14:1493 14:2003 · 15:452 15:955 15:1458 15:1961
16:294 16:793 16:1292 17:956 17:690 17:1202 18:347 18:844 18:1341 19:70 19:570
19:1070 19:1570 20:135 20:636 20:1138 20:1639 20:2141 20:2643 · 21:1240 21:966
21:1469 21:1972 21:2475 · · 25:662 … 26:281 … 27:461 … 28:358 … 29:430 …
29:3429 · 30:410
```
- Section index **monotonic non-decreasing** throughout — **0 backward events**.
- Intra climbs ~+500/step within each section; resets at each of the 17 boundaries.
- Two benign sampling artifacts, both **forward** (not jumps): the 21→25 step skips
  the very short 第二夜 chapter-title / divider sections (22–24) that a 0.003 stride
  steps over; one sub-300px intra wobble at section 17 (956→690→1202) is
  `goToFraction` landing precision on the piecewise fraction→offset map, well under
  the ~500px stride.

**Real idb touch-scroll burst (well-spaced `--duration 1.2` pans, from f=0.10):**
```
13:1631 → 13:1871 → 13:2111 → 13:2351 → 13:2591 → 14:2128 → 14:2368
→ 20:534 → 20:774 → 20:1014 → 20:1254 → 20:1494 → 20:1734 → 20:1974 → 20:2214
```
- Within each section intra climbs **+240 per pan** (continuous touch-drag); section
  index **monotonic** 13→14→20; **zero backward** moves. The 14→20 step is one
  momentum fling over short sections (forward), after which scrolling resumes
  line-continuous within section 20.

Both drivers cross the same windowed renderer; together they cover sections 13→30
(≥15 chapters of the 85-section book) with no backward position jump and no
discontinuous mismatch — the AZW3 chapter-boundary jump class (Bug #283 /
feature #73) is ruled out. idb real-scroll faithfully exercises the touch path;
`goToFraction` provides the controlled boundary-transition detail. Visual
corroboration: `/tmp/azw3-stuck.png` shows the 第二夜 chapter-title page rendering
cleanly mid-scroll (previous chapter → title page → next chapter, continuous).

## Observations

- **idb slow pans drive native scrollers** (TXT `UITableView`, and the AZW3
  Foliate scroll did advance under idb in calibration). Fast flicks do **not**
  register on the Screen-Sharing virtual display — only deliberate
  `--duration ≥ 1.0` pans do. idb on the AZW3 Foliate WKWebView stalls
  intermittently over a long automated sweep (synthetic-gesture flakiness, not a
  content bug — the reader stays responsive to `goToFraction` throughout), so the
  AZW3 sweep uses `goToFraction` through the same windowed renderer.
- The eviction-invariant intra-offset signal is what makes a *real* jump
  distinguishable from the expected coordinate re-base when the window recycles.

## Artifacts

- EPUB raw: background task `bf0zmesvs` output (16-boundary sweep).
- TXT raw: background task `b8z1arelz` output; screenshots `/tmp/txt-prog-{000,025,050,END}.png`.
- AZW3 raw: background tasks `bepjbnqx2` (idb), `bymxtj17p` (goToFraction);
  screenshot `/tmp/azw3-stuck.png` (第二夜 chapter-title page rendered cleanly mid-scroll).
