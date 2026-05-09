---
kind: feature
id: 11
status_target: VERIFIED
commit_sha: 6fc1cec99d5453d312979993f191999919e9a58a
app_version: 3.14.118 (build 227)
date: 2026-05-09
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.4
build_configuration: Debug
backend: bundled DebugFixtures (mini-epub3.epub) in Native EPUB mode
result: pass
---

## Summary

Round-4 verification of feature #11 (EPUB text highlighting and
note-taking) closes the long-deferred gesture-driven user-flow slice
that round-3 left at `partial`. Bug #159 / GH #472 (filed by round-3
verify cron, fixed in v3.14.118 the same session) shipped the XPath
namespace rewrite + CSS Highlight API priority change that unblocked
the visual paint pipeline.

**Result: PASS.** All four legs of the contract verified
end-to-end: gesture-driven creation → visible yellow paint → data
persistence in Highlights tab → survives close + reopen.

Status moves DONE → **VERIFIED**.

## Acceptance criteria

| Criterion | Slice | Result |
|---|---|---|
| EPUB highlight data persists across reload | Round-1 cross-ref | PASS |
| Bridge readiness (CSS Highlight API supported, JS hooks defined) | Round-2 cross-ref (`feature-11-20260506b.md`) | PASS |
| Gesture-driven creation: long-press → menu → tap "Highlight" | Round-3 cross-ref (`feature-11-20260509.md`) | PASS |
| Data persistence on gesture path | Round-3 cross-ref | PASS |
| **Visual render: yellow background paints on selected range in EPUB page** | This round: long-press on word "testing" in mini-epub3 paragraph 1 → custom VReader menu → tap Highlight → **yellow background visibly painted** | **PASS (post bug #159 fix)** |
| **Highlight survives book close + reopen** | This round: tap back arrow → Library → tap mini-epub3 → reader reopens at Chapter 1 → "testing" still rendered with yellow background; live probe confirms `cssHighlightCount: 1, styleEls: 1` post-reopen; Highlights tab shows row "🟡 testing" | **PASS** |

## Commands run

```bash
SIM=61149F0E-DC18-4BE2-BB37-52659F1F4F62
# v3.14.118 (commit 6fc1cec) installed from previous bug-159 close-gate iteration.

xcrun simctl terminate $SIM com.vreader.app
xcrun simctl openurl $SIM "vreader-debug://reset"
sleep 2
xcrun simctl openurl $SIM "vreader-debug://seed?fixture=mini-epub3"
sleep 2
xcrun simctl launch $SIM com.vreader.app

# UI driving via computer-use:
# 1. Tap mini-epub3 card → reader opens in Native EPUB mode at Chapter 1.
# 2. Double-click on text area to scroll up so paragraph 1 is visible.
# 3. Long-press on word "testing" in paragraph 1 (gesture: mouse_move(310,230)
#    + left_mouse_down + wait 1.2s + left_mouse_up).
# 4. iOS context menu appears with custom VReader actions:
#    Highlight | Add Note | Copy. Tap Highlight.
# 5. Selection animation dismisses. Word "testing" now has VISIBLE
#    yellow background (rgba(255, 235, 59, 0.5)).
# 6. Tap blank area to dismiss any remaining selection state.
# 7. Tap back arrow (toolbar) → Library → tap mini-epub3 card again.
# 8. Reader reopens at Chapter 1 (continues from saved position).
#    Word "testing" still has yellow background visible (above
#    toolbar in the dimmed area when chrome is showing).
# 9. Tap list icon (3rd toolbar icon) → side panel opens to Contents tab.
#    Tap Highlights tab → row "🟡 testing" visible.

# Live state probe via DebugBridge eval (bug #126's eval surface):
JS='JSON.stringify({cssHighlightCount: CSS.highlights ? CSS.highlights.size : -1, styleEls: document.querySelectorAll("style[id^=vreader-hl-style-]").length})'
B64=$(printf '%s' "$JS" | base64 | tr -d '\n')
xcrun simctl openurl $SIM "vreader-debug://eval?bridge=epub&js=$B64"
# Result: cssHighlightCount: 1, styleEls: 1 — restore path correctly
# re-injected the dynamic <style> element AND re-registered the
# highlight in CSS.highlights on chapter reload.

# Capture evidence
xcrun simctl io $SIM screenshot \
  dev-docs/verification/artifacts/feature-11-r4-step1-yellow-paint-visible-20260509.png
xcrun simctl io $SIM screenshot \
  dev-docs/verification/artifacts/feature-11-r4-step2-persists-after-reopen-20260509.png
xcrun simctl io $SIM screenshot \
  dev-docs/verification/artifacts/feature-11-r4-step3-highlights-tab-after-reopen-20260509.png
```

## Observations

- **Bug #159 fix (this session) closes the gap.** Round-3
  diagnosis: gesture path + data layer worked, visual paint was the
  gap. Bug #159's XPath namespace rewrite (`*[local-name()="name"]`)
  let `buildRange` resolve XHTML-namespaced selection paths; CSS
  Highlight API priority change moved highlight rendering into the
  text-paint layer (which follows CSS column transforms in paged
  EPUB mode); foliate-bridge.js DOMContentLoaded fix made
  `__foliate.overlayer` available even when the script loads at
  `.atDocumentEnd`.
- **Restore path works correctly on chapter reload.** Live probe
  after close+reopen shows `cssHighlightCount: 1` and `styleEls: 1`
  — the `EPUBHighlightActions.restoreHighlightsJS` path correctly
  re-injected both the dynamic `::highlight()` style rule AND the
  `CSS.highlights.set` registration on chapter load. The visual
  paint is present after reopen (visible in the dimmed reader area
  above the toolbar in step 2 artifact).
- **Cross-format note**: this round verifies EPUB Native mode only
  (the WKWebView + CSS Highlight API path). AZW3/MOBI highlights
  go through `FoliateViewBridge` (separate code path) — feature
  row 11 already documented "AZW3 highlights — Selection capture +
  CFI anchoring shipped; overlay restoration deferred to WI-7".
  AZW3 visual-render verification is out of scope for this round.

## Artifacts

- `dev-docs/verification/artifacts/feature-11-r4-step1-yellow-paint-visible-20260509.png`
  — Yellow background painted on word "testing" in paragraph 1 of
  mini-epub3 Chapter One immediately after tap-Highlight.
- `dev-docs/verification/artifacts/feature-11-r4-step2-persists-after-reopen-20260509.png`
  — Same highlight visible after closing book → returning to library
  → reopening book. Yellow paint persists (visible above top
  toolbar's dimmed area on chrome).
- `dev-docs/verification/artifacts/feature-11-r4-step3-highlights-tab-after-reopen-20260509.png`
  — Side panel Highlights tab showing "🟡 testing" entry with the
  yellow color dot, confirming data layer + UI panel alignment after
  reopen.

## Verdict

`pass` for feature #11's previously-blocked gesture-driven user-flow
slice. Combined with round-1's persistence + count slices, round-2's
bridge-readiness probes, round-3's gesture + data-layer slice, and
this round's visual paint + persistence slice, feature #11 has full
end-to-end coverage:

1. Data layer: SwiftData persistence + count exposure across reload.
2. Bridge readiness: CSS Highlight API supported, `__vreader_createHighlight`
   defined, programmatic round-trip works.
3. Gesture path: long-press → custom menu → tap Highlight → data persists.
4. Visual render: yellow background paints on selected range.
5. Restore: highlight survives close + reopen (data + paint).

**Feature #11 status: DONE → VERIFIED.** GH #404 close-gate satisfied.
