---
kind: feature
id: 53
status_target: VERIFIED
commit_sha: 3f12e8f4e6feb649cadc2d2e2ec430bd19b46672
app_version: 3.27.15 (build 429)
date: 2026-05-17
verifier: claude (verify-cron)
device_or_simulator: iPhone 17 Pro Max Simulator
os_version: iOS 26.4
build_configuration: Debug
backend: n/a (DebugBridge + bundled mini-epub3 fixture)
result: partial
---

# Feature #53 round-5 EPUB device verification

Round-4 (`feature-53-20260517-round4.md`, result=partial) device-verified
the **TXT** tap-on-highlight path: criteria (a)/(b)/(d) PASS after the
Bug #205 fix shipped. Round-4 explicitly deferred EPUB/PDF/MD for
criterion (c), citing — among other reasons — that "`DebugFixtureCatalog`
has no EPUB/PDF fixture". That claim is now stale: `DebugFixtureCatalog`
ships a `mini-epub3` EPUB fixture. This round exercises the **EPUB**
format, the next format toward criterion (c).

## Scope

EPUB format only. Criteria (a), (b), (d) for EPUB, using the bundled
`mini-epub3` fixture. Criterion (c) (consistency across all 5 formats)
is not closed this round — see "Deferred / out of scope".

## Acceptance criteria

| # | Criterion | Result | Observed |
|---|-----------|--------|----------|
| (a) | Tapping a highlighted word shows a menu with at minimum a Delete option | **FAIL** (EPUB) | Created a yellow highlight on the word "incididunt" (long-press → SelectionPopover → yellow swatch; `highlightCount` 0→1). Tapping the highlighted word produced **no menu** — the tap toggled the reader chrome instead, identical to a generic content tap. Reproduced 3× including once with the EPUB font enlarged (fontSize 60) so the highlight was a large, unambiguous tap target. Filed as **Bug #211 / GH #820**. |
| (b) | Delete removes the highlight visually and from persistence | **BLOCKED** (EPUB) | Cannot be exercised through the feature: the inline Delete menu (criterion (a)) never appears, so there is no Delete affordance to invoke. The highlight itself persists correctly (`highlightCount` stayed 1 across taps), and could be removed via the annotations/Notes panel — but that is not feature #53's tap-to-delete path. |
| (c) | Consistent across all 5 formats | **NOT VERIFIED** | TXT passes (round-4); EPUB fails this round; MD/PDF/Foliate not exercised. See "Deferred / out of scope". |
| (d) | Tapping non-highlighted text preserves existing scroll/chrome-toggle behavior | **PASS** (EPUB) | Tapped a non-highlighted word ("dolor") → reader chrome toggled, no menu appeared. The pre-existing EPUB content-tap → chrome-toggle behavior is intact. |

## Commands run

```bash
SIM=6C32EE30-CBE6-431E-BA12-02248496E1C9   # iPhone 17 Pro Max, iOS 26.4

# Seed + open the EPUB fixture
xcrun simctl openurl "$SIM" "vreader-debug://reset"
xcrun simctl openurl "$SIM" "vreader-debug://seed?fixture=mini-epub3"
# (opened the "VReader Mini EPUB Fixture" book card from the Library)
xcrun simctl openurl "$SIM" "vreader-debug://theme?mode=light&fontSize=28"

# State assertions
xcrun simctl openurl "$SIM" "vreader-debug://snapshot?dest=f53r5-after-highlight.json"  # highlightCount: 1
xcrun simctl openurl "$SIM" "vreader-debug://snapshot?dest=f53r5-final.json"            # highlightCount: 1 (unchanged after taps)

# Root-cause probes — eval JS in the EPUB WKWebView (base64-encoded js param)
#   probe 1: registry / CSS Highlight / caret API state
#   probe 2: install a capture-phase click counter, tap, read it back
#   probe 3: replay the WI-4 hit-test (caretPositionFromPoint + compareBoundaryPoints)
xcrun simctl openurl "$SIM" "vreader-debug://eval?bridge=f53hit&js=<base64>"
```

Gestures (long-press to create the highlight, tap-on-highlight,
tap-on-non-highlighted-word) were driven via the computer-use MCP
against the Simulator window. The installed binary predates commit
`3f12e8f` by a few patch/test-only releases; `vreader/Views/Reader/EPUBHighlightJS.swift`
— the file containing the defect — has not changed since feature #53
WI-4 shipped it (`ee05d61`, PR #721), so the finding holds for current
`main`.

## Observations

The EPUB tap-on-highlight path (feature #53 WI-4) is wired end-to-end
but contains a single-line logic defect. DebugBridge `eval` probes
isolated it precisely:

- **The JS-side machinery is intact.** `window.__vreader_highlightRanges`
  is populated with the highlight's UUID; the CSS Highlight API entry
  (`vreader-<id>`) is painted; `document.caretPositionFromPoint` is
  available.
- **The `click` event fires.** An injected capture-phase click counter
  recorded `clicks: 1` after the tap, landing on a `<p>` element — so
  the tap is NOT being swallowed by native gesture/touch cancellation.
  The injected counter also fired, which proves the WI-4 highlight
  listener did not call `e.stopImmediatePropagation()` — i.e. it ran
  but did not register a hit.
- **The hit-test compares the wrong boundary points.** Replaying the
  WI-4 listener's logic against the live highlight Range: the tap's
  caret resolved (via the same `caretPositionFromPoint`) to offset 102
  in the paragraph text node; the highlight Range spans offsets 97–107
  in the *same* node (`sameNodeAsRangeStart: true`). The membership
  test returned `startVsProbe=-1, endVsProbe=-1, hit=false`. It should
  hit — offset 102 is inside [97, 107].
- **Root cause.** `EPUBHighlightJS.swift` (WI-4 `click` listener) calls
  `range.compareBoundaryPoints(Range.END_TO_START, probe)` intending to
  test `range.end >= probe.start`. Per the DOM spec, `END_TO_START`
  compares `range`'s *start* boundary to `probe`'s *end* boundary — not
  `range`'s end to `probe`'s start. The correct constant is
  `Range.START_TO_END`. With the wrong constant, every tap whose caret
  offset is past the highlight's first character misses; no
  `highlightTapHandler` message posts, `.readerHighlightTapped` never
  fires, and the tap falls through to the chrome-toggle.
- This is filed as **Bug #211 / GH #820** (severity Medium). It is not
  a duplicate of #199 (Foliate consumer-wiring gap) or #182 (EPUB
  *search-result* highlight).
- Criterion (d) holds: a non-highlighted-word tap toggles the reader
  chrome and shows no menu — the existing EPUB content-tap behavior is
  unchanged.

## Deferred / out of scope (criterion c)

- **MD**: shares the TXT `HighlightableTextView` bridge — covered in
  principle by round-4's TXT pass; not separately exercised.
- **PDF**: separate `PDFKit` renderer path; `DebugFixtureCatalog` has
  no PDF fixture. Not exercised.
- **AZW3/MOBI (Foliate)**: inline-menu consumer wiring is a known gap
  tracked as Bug #199 / GH #733.
- Criterion (c) cannot be reached until EPUB (Bug #211), Foliate
  (Bug #199), and PDF all pass.

## Outcome

Feature #53 row stays **DONE**. Round-5 finds **EPUB criterion (a)
FAILS** — tapping an EPUB highlight surfaces no inline menu — and files
**Bug #211 / GH #820** with a confirmed root cause. Criterion (b) for
EPUB is blocked behind (a); criterion (d) for EPUB passes. The
`VERIFIED` flip remains gated on EPUB (Bug #211), Foliate (Bug #199),
and PDF.

This round is verification-only: the bug was filed, not fixed (the
bug-fix workflow owns the fix).

## Artifacts

- `artifacts/feature-53-r5-epub-highlight-present-20260517.png` — the
  EPUB reader with the yellow highlight painted on "incididunt".
- `artifacts/feature-53-r5-epub-tap-no-menu-20260517.png` — after
  tapping the highlight: no menu, chrome toggled (the Bug #211
  symptom).
