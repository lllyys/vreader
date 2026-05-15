---
kind: feature
id: 2
status_target: VERIFIED
commit_sha: 47f384afe8fe2c338a1210733363043dc37e8c2b
app_version: 3.22.8 (build 360)
date: 2026-05-15
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.5
build_configuration: Debug
backend: n/a (bundled mini-epub3 fixture)
result: fail
---

# Feature #2 — Highlight search result at destination (round 5 — DOM-probe EPUB leg)

## Context

Round 4 (2026-05-14) attempted the EPUB leg post bug #182 (pendingHighlightJS
deferred to didFinish) + bug #187 (BackgroundIndexingCoordinator strong-self
capture) fixes. It found cross-chapter navigation worked, search returned
results, but the yellow-highlight render slice was **inconclusive** — three
post-tap screenshots were byte-identical, leaving open whether the highlight
JS executed-and-produced-no-paint vs. never-fired.

This round uses the recommended next step from round 4: query the EPUB
WKWebView DOM directly via `vreader-debug://eval?bridge=epub` to detect
the presence of the `.vreader_search_highlight` span, bypassing the
visual-capture timing issue. Three probes at t≈0.8s, t≈2.3s, t≈5.3s
post-tap all return `count: 0` — definitive evidence that the highlight
span is **never injected** into the chapter-2 DOM following cross-chapter
search-tap navigation.

This contradicts the FIXED claim on bug #182 row in `docs/bugs.md`. Net
effect: **bug #182 must be REOPENED**.

## Acceptance criteria

| Sub-criterion | Observed | Pass? |
|---|---|---|
| Search returns results for words in the EPUB | Search for "navigation" returns 1 hit (`chapter2` label, snippet "...hapter Two The second chapter exists so **navigation** between chapters can be tested. It is s..."). Bug #187 fix still healthy. | **PASS** |
| Tapping the result navigates to the matched chapter | Reader's bottom chrome flips from "Chapter 1 of 2 — Chapter One" to "Chapter 2 of 2 — Chapter Two". DOM probe confirms `document.title === "Chapter Two"`. | **PASS** |
| Matched word lands inside viewport after navigation | DOM probe at t≈5.3s: `scrollTop: 0`, `clientHeight === scrollHeight (2131)`. Chapter 2 content fits entirely in viewport; matched word "navigation" is in the first paragraph (probe returns paragraph 1 text starting "The second chapter exists so navigation between chapters can be tested..."). | **PASS** |
| Yellow highlight `.vreader_search_highlight` span injected into DOM during the 3s window | DOM probe at **t≈0.8s**: `count: 0, firstOuterHTMLHead: null, texts: []`. DOM probe at **t≈2.3s**: identical `count: 0`. DOM probe at **t≈5.3s** (past 3s auto-clear window): identical `count: 0`. The highlight span is **never created** anywhere in the document. | **FAIL** |
| Visual yellow paint on matched word | Post-tap screenshot (`artifacts/feature-2-r5-02-post-tap-chapter2-no-highlight-20260515.png`) shows reader on Chapter 2 (chrome label confirms), scrubber at far-right, no yellow paint anywhere. Consistent with `count: 0` DOM probe. | **FAIL** |
| Auto-clear of highlight on next action | N/A — span never existed to clear. | **N/A** |

**Overall**: `fail`. Yellow-highlight render slice for cross-chapter EPUB
search is **confirmed broken**, not "inconclusive" as round 4 worded
it. Bug #182 close-gate verification therefore **FAILS** — the row's
"FIXED 2026-05-14" claim describes the code change (coordinator stash
fields + deferred eval in `didFinish`) but the runtime behavior the
fix was supposed to produce does not occur.

## Commands run

```bash
SIM_ID="1FAB9493-B97E-48F0-96C7-44A8E5AAA21E"

# Confirm installed build has bug #182 fix (shipped v3.21.50, well below installed)
APP_BUNDLE=$(xcrun simctl get_app_container booted com.vreader.app app)
plutil -extract CFBundleShortVersionString raw "$APP_BUNDLE/Info.plist"
# → 3.22.8

# Reset library + seed mini-epub3 fixture
xcrun simctl openurl "$SIM_ID" "vreader-debug://reset"
xcrun simctl openurl "$SIM_ID" "vreader-debug://seed?fixture=mini-epub3"
```

Then via Simulator UI (driven through `mcp__computer-use__*`):
1. Tap library row "VReader Mini EPUB Fixture" → reader opens at Chapter 1 of 2.
2. Tap search icon (magnifying glass) → search panel appears.
3. Set clipboard to "navigation" (`echo -n navigation | xcrun simctl pbcopy booted`); double-tap search field; tap "Paste" callout.
4. Search returns 1 result with `chapter2` label.
5. **Tap result row** at simulator coordinate (264, 192) — this is the moment of interest.
6. Within ~0.8s, fire DOM probe via `vreader-debug://eval`:

```bash
DATA_CONTAINER=$(xcrun simctl get_app_container booted com.vreader.app data)
EVAL_PATH="$DATA_CONTAINER/Library/Caches/DebugBridge/eval-epub.json"

PROBE_JS='(function(){var s=document.querySelectorAll(".vreader_search_highlight");var first=s[0];return {count:s.length,texts:Array.from(s).map(function(e){return e.textContent}),firstOuterHTMLHead:first?first.outerHTML.substring(0,200):null,docTitle:document.title||null,bodyTextHead:(document.body?document.body.textContent.substring(0,160):null)};})();'
PROBE_B64=$(printf '%s' "$PROBE_JS" | base64 | tr -d '\n')

# Probe at t≈0.8s, t≈2.3s, t≈5.3s post-tap
rm -f "$EVAL_PATH"
xcrun simctl openurl "$SIM_ID" "vreader-debug://eval?bridge=epub&js=${PROBE_B64}"
sleep 0.3 && cat "$EVAL_PATH"
```

Three identical-shape responses:
```json
{
  "bridge": "epub",
  "format": "epub",
  "fingerprintKey": "epub:f284fd074ccd1d3c1a78985464d9e1be27975f4029f3c2ddef8428ca10684af4:2198",
  "result": {
    "count": 0,
    "texts": [],
    "firstOuterHTMLHead": null,
    "docTitle": "Chapter Two",
    "bodyTextHead": "\n  Chapter Two\n  The second chapter exists so navigation between chapters can be tested. ..."
  },
  "ts": "..."
}
```

Scroll state probe (separate JS, same eval path) at t≈9s:
```json
"result": {
  "scrollTop": 0,
  "scrollHeight": 2131,
  "clientHeight": 2131,
  "paraCount": 2,
  "paragraphs": [
    "The second chapter exists so navigation between chapters can be tested. It is sh",
    "End of fixture."
  ]
}
```

## Observations

- **DOM probe is conclusive where screenshots were not.** Round 4's three
  byte-identical screenshots could have meant either "highlight painted
  but capture missed it" or "no highlight ever painted". Querying
  `document.querySelectorAll('.vreader_search_highlight').length` removes
  the timing ambiguity — count=0 at three time points spanning the 3s
  auto-clear window means the JS-side span insertion path **did not run**
  (or ran but produced 0 matches; see next bullet).
- **window.find() not the culprit.** The matched text "navigation" is
  plainly in the loaded chapter-2 DOM body — the scroll-state probe
  confirms it's in the first `<p>` of the chapter. If
  `EPUBHighlightBridge.searchHighlightJS`'s `window.find('navigation', false, false, true)`
  had executed against this DOM, it would have matched and the span
  would have been injected. Combined with `count: 0`, this points to
  the searchHighlightJS **never being evaluated** post-cross-chapter
  load — not to its body failing.
- **Suspect: pendingHighlightJS deferred-eval path doesn't trigger on
  cross-chapter loads.** Bug #182's fix added a stash + replay pattern
  in `EPUBWebViewBridge.Coordinator` (mirroring `pendingScrollFraction`).
  The likely failure mode: `updateUIView`'s URL-change branch stashes
  the JS, but `didFinish` either (a) doesn't fire for the new chapter
  load, (b) clears the stash before evaluating, or (c) evaluates but
  the JS is empty by then. A code-read of
  `EPUBWebViewBridge.swift` + `EPUBWebViewBridgeCoordinator.swift`
  around the `pendingHighlightJS` / `didFinish` pair is the next
  step for the bug-fix cron iteration.
- **DOM probe technique is reusable.** Future EPUB / Foliate search-
  highlight verifications can short-circuit the visual-capture issue by
  querying the highlight DOM class directly. Worth recording in the
  feature #45 verification harness as a pattern.

## Artifacts

- `dev-docs/verification/artifacts/feature-2-r5-01-search-result-pre-tap-20260515.png`
  — search panel showing 1 hit for "navigation" with chapter2 label.
- `dev-docs/verification/artifacts/feature-2-r5-02-post-tap-chapter2-no-highlight-20260515.png`
  — reader on Chapter 2 (chrome confirms), no yellow paint visible.
- `dev-docs/verification/artifacts/feature-2-r5-eval-epub-t5s-20260515.json`
  — final DOM probe at t≈5.3s post-tap: `count: 0`, `docTitle: "Chapter Two"`.
- `dev-docs/verification/artifacts/feature-2-r5-eval-epub-scrollstate-20260515.json`
  — scroll-state probe at t≈9s: chapter 2 fits in viewport, matched paragraph is `<p>` #1.

## Verdict

`fail` — feature #2 EPUB-leg verification is **definitively** unmet for
cross-chapter search-result tap. Net effect on the tracker:

- **Bug #182 (GH #621)**: REOPEN — the FIXED claim was code-complete but
  runtime-incomplete; the deferred-eval pendingHighlightJS path does not
  in fact result in a `.vreader_search_highlight` span being injected
  into the chapter-2 DOM. Awaiting-device-verification label converts
  to a confirmed device-verify FAIL.
- **Feature #2 row in `docs/features.md`**: stays DONE (the underlying
  code is in place); flip to VERIFIED still gated on bug #182's real
  fix landing.

**Recommended next round (after bug #182 properly fixed)**: re-run this
exact recipe and assert `count: 1` at t≈0.8s and t≈2.3s, then `count: 0`
at t≈5.3s (auto-clear). The three probes give an unambiguous green
signal for the full lifecycle.
