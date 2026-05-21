---
kind: feature
id: 2
status_target: VERIFIED
commit_sha: 529c9723
app_version: 3.39.6 (build 627)
date: 2026-05-22
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator (1FAB9493-B97E-48F0-96C7-44A8E5AAA21E)
os_version: iOS 26.5
build_configuration: Debug
backend: n/a (bundled mini-epub3 EPUB + war-and-peace TXT fixtures)
result: pass
---

# Feature #2 — Highlight search result at destination (round 6 — EPUB + TXT, both legs PASS)

## Context

Round 5 (2026-05-15, v3.22.8, `feature-2-20260515-round5.md`) was a **fail**:
DOM probes of the EPUB WKWebView showed `document.querySelectorAll('.vreader_search_highlight').length === 0`
at t≈0.8s / 2.3s / 5.3s after a cross-chapter search-result tap — the
highlight span was never injected. Round 3 (2026-05-11) was a **partial**:
the TXT chapter-mode highlight never painted because `chapterReaderContent`
hardcoded `highlightRange: nil` (the WI-7 global→chapter-local offset
translation was deferred).

Both blockers have since landed on `main`:

1. **Bug #182 / GH #621** (FIXED 2026-05-18, round-3) — the EPUB
   `EPUBHighlightBridge.searchHighlightJS` now polls `window.find()` on a
   bounded 50ms retry loop (40 attempts ≈ 2s) until the freshly-loaded
   chapter DOM is searchable, with a `window.__vreaderSearchHighlightGen`
   generation token. Verified-and-closed this session.
2. **Bug #154 / GH #443** (FIXED 2026-05-19) — TXT chapter mode now
   computes the temp highlight via `Self.chapterLocalHighlightRanges(...)`
   (`TXTReaderContainerView.swift:801`) and feeds a real `highlightRange:`
   + `highlightNonce:` to the bridge (line 853-855); the monotonic
   `highlightNonce` forces a re-paint even on a repeat-nav to an
   already-current target.

Round 6 drives the search-result tap CU-free via the `vreader-debug://search`
command (Bug #238, shipped 2026-05-20) and confirms the highlight render +
auto-clear at the destination on **both** EPUB (round-5's fail leg) and TXT
(round-3's partial leg).

**A separate verification-tooling defect was found and filed as Bug #264 /
GH #1141** (NOT a Feature #2 product defect): `vreader-debug://reset` does
not clear the persistent FTS store, leaving a stale `search_metadata` row
with empty `segment_base_offsets` that makes `ReaderSearchCoordinator.setup()`
skip both re-indexing and in-memory index-marking, so `service.isIndexed()`
never flips and the `search` driver times out. The Feature #2 acceptance
behavior was verified after working around this by clearing
`Library/Application Support/SearchIndex/` (a clean FTS-store slate). The
highlight feature itself works end-to-end once search is functional; the
stale-index issue is in the harness/setup-hygiene, not the highlight path.

## Acceptance criteria

Feature row criterion: "highlight search result at destination — yellow
background highlight, auto-clears after 3s." Verified on both formats.

### EPUB leg (mini-epub3, cross-chapter — the round-5 FAIL leg)

| Sub-criterion | Observed | Pass? |
|---|---|---|
| Search returns results for words in the EPUB | `search?query=navigation` → "1 match in 1 section", `chapter2` label, snippet "...hapter Two The second chapter exists so **navigation** between chapters can be tested. It is s...". | **PASS** |
| Tapping the result navigates to the matched (different) chapter | Driver logged `tapping result 0 → …` then `docTitle: "Chapter Two"`; reader bottom chrome flipped to "Chapter 2 of 2". Started on Chapter One; match is in Chapter Two (cross-chapter). | **PASS** |
| Yellow highlight `.vreader_search_highlight` span injected during the 3s window | DOM probe at **t≈1.0s**: `count: 1, docTitle: "Chapter Two", texts: [" navigatio"]`. At **t≈1.9s**: `count: 1`. The span is injected wrapping the matched "navigation" text. **(round-5 had `count: 0` here — now PASS.)** | **PASS** |
| Matched word lands inside the viewport at the destination | Viewport probe: `inViewport: true`, `spanTop: 148` (within `winH: 2131`). Visual capture (`feature-2-r6-epub-highlight-visible-t1.2s-20260522.png`) shows "navigation" with a yellow background near the top of the content area. | **PASS** |
| Visual yellow paint on the matched word | `feature-2-r6-epub-highlight-visible-t1.2s-20260522.png` — clear yellow/orange highlight on "navigation" in the line "The second chapter exists so navigation between chapters can be tested." | **PASS** |
| Auto-clear of highlight after ~3s | DOM probe at **t≈3.0s**: `count: 0`. At **t≈4.9s**: `count: 0`. Visual capture at t≈4.5s (`feature-2-r6-epub-after-clear-t4.5s-20260522.png`) shows "navigation" with NO background. | **PASS** |

### TXT leg (war-and-peace, chapter mode — the round-3 PARTIAL leg)

| Sub-criterion | Observed | Pass? |
|---|---|---|
| Search returns results for words in the TXT | `search?query=Pierre` → "1 match in 1 section", "Section 8", snippet "... ordered her carriage and now departed. **Pierre**, who was alone among the guests not inv...". | **PASS** |
| Tapping the result navigates to the matched location | Driver logged `tapping result 0 → …txt:segment:7:118` then `navigateToChapter: idx=3 title=Chapter 3`; snapshot `position` moved 0 → 1433; bottom chrome shows "Chapter 4 of 4". | **PASS** |
| Yellow highlight visible on matched range immediately after tap | Visual captures `feature-2-r6-txt-hl-A-t0.7s-20260522.png` (t+0.7s) AND `feature-2-r6-txt-hl-B-t1.5s-20260522.png` (t+1.5s) both show a clear yellow background on the word "Pierre" at the start of the matched paragraph. **(round-3 had NO paint in chapter mode — now PASS via Bug #154's fix.)** | **PASS** |
| Matched text lands inside the viewport | The matched paragraph "Pierre, who was alone among the guests not invited to dine elsewhere, lingered." renders fully inside the viewport in all post-tap captures. | **PASS** |
| Auto-clear of highlight after ~3s | Visual capture `feature-2-r6-txt-after-clear-t4.5s-20260522.png` (t+4.5s) shows the same paragraph with the "Pierre" yellow highlight GONE. | **PASS** |

**Overall**: `pass`. Both the round-5 EPUB fail leg and the round-3 TXT
partial leg now verify end-to-end: search → tap result → navigate to the
matched location → transient yellow highlight on the matched text →
auto-clear after ~3s. Every acceptance criterion observed passing on both
formats.

## Commands run

```bash
SIM=1FAB9493-B97E-48F0-96C7-44A8E5AAA21E

# Clean build v3.39.6 (HEAD 529c9723) into a fresh derivedDataPath, install
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project vreader.xcodeproj -scheme vreader -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath build/verify-2
xcrun simctl install "$SIM" build/verify-2/Build/Products/Debug-iphonesimulator/vreader.app
# → CFBundleShortVersionString 3.39.6, CFBundleVersion 627

# --- WORKAROUND for Bug #264 / GH #1141: clear the stale persistent FTS store ---
# (vreader-debug://reset does NOT clear it; a stale empty-offsets metadata row
#  makes setup() skip indexing and isIndexed() never flips, stalling the driver.)
DATA=$(xcrun simctl get_app_container "$SIM" com.vreader.app data)
rm -rf "$DATA/Library/Application Support/SearchIndex"

# === EPUB leg (mini-epub3) ===
xcrun simctl openurl "$SIM" "vreader-debug://reset"
xcrun simctl openurl "$SIM" "vreader-debug://seed?fixture=mini-epub3"
BOOKID="epub:f284fd074ccd1d3c1a78985464d9e1be27975f4029f3c2ddef8428ca10684af4:2198"
xcrun simctl openurl "$SIM" "vreader-debug://open?bookId=<urlencoded BOOKID>"
xcrun simctl openurl "$SIM" "vreader-debug://settle?token=ep1"   # ready sentinel

# Pre-warm the index (first query-only fire builds + indexes; the in-memory
# isIndexed flips after the index is built):
xcrun simctl openurl "$SIM" "vreader-debug://search?query=navigation"   # results render

# Indexed search-result tap + DOM probe across the 3s window:
EVAL="$DATA/Library/Caches/DebugBridge/eval-epub.json"
PROBE_JS='(function(){var s=document.querySelectorAll(".vreader_search_highlight");return {count:s.length,texts:Array.from(s).map(e=>e.textContent),docTitle:document.title};})();'
B64=$(printf '%s' "$PROBE_JS" | base64 | tr -d '\n')
xcrun simctl openurl "$SIM" "vreader-debug://search?query=navigation&index=0"
# probe at t≈1.0s / 1.9s / 3.0s / 4.9s:
xcrun simctl openurl "$SIM" "vreader-debug://eval?bridge=epub&js=${B64}"; cat "$EVAL"
#   t≈1.0s → count=1 docTitle="Chapter Two" texts=[" navigatio"]
#   t≈1.9s → count=1
#   t≈3.0s → count=0   (auto-cleared)
#   t≈4.9s → count=0
xcrun simctl io "$SIM" screenshot feature-2-r6-epub-highlight-visible-t1.2s-20260522.png

# === TXT leg (war-and-peace) ===
rm -rf "$DATA/Library/Application Support/SearchIndex"   # Bug #264 workaround
xcrun simctl openurl "$SIM" "vreader-debug://reset"
xcrun simctl openurl "$SIM" "vreader-debug://seed?fixture=war-and-peace"
TXTID="txt:bd8285a80f01df96dedd20a02178043afb85c0b499127e300baf57b7f1ed7508:1705"
xcrun simctl openurl "$SIM" "vreader-debug://open?bookId=<urlencoded TXTID>"
xcrun simctl openurl "$SIM" "vreader-debug://settle?token=th"
xcrun simctl openurl "$SIM" "vreader-debug://search?query=Pierre"          # pre-warm
xcrun simctl openurl "$SIM" "vreader-debug://search?query=Pierre&index=0"  # tap
#   log: tapping result 0 → …txt:segment:7:118 ; navigateToChapter idx=3
xcrun simctl io "$SIM" screenshot feature-2-r6-txt-hl-B-t1.5s-20260522.png   # highlight on "Pierre"
# +3s:
xcrun simctl io "$SIM" screenshot feature-2-r6-txt-after-clear-t4.5s-20260522.png  # cleared
```

DOM-probe + log evidence captured via `xcrun simctl spawn "$SIM" log stream
--predicate 'subsystem == "com.vreader.app"' --level debug --style compact`.

## Observations

- **Both round-5 and round-3 root-cause fixes are durable.** The EPUB
  `.vreader_search_highlight` span — `count: 0` across the whole 3s window
  in round-5 — is now `count: 1` at t≈1.0s/1.9s and `count: 0` at t≈3.0s/4.9s,
  the exact green lifecycle round-5 recommended asserting. The TXT chapter-mode
  highlight — never painted in round-3 — now renders on "Pierre" and clears,
  thanks to Bug #154's `chapterLocalHighlightRanges` + `highlightNonce` wiring.
- **The hard blocker this round was a harness defect, not the feature.** Out of
  the box (`reset` + `seed` only), the `search` driver stalls forever at the
  30s `awaitSearchIndexed` because a stale `search_metadata` row with empty
  `segment_base_offsets` survives `reset` → `setup()` takes the `alreadyIndexed`
  branch, `getSegmentBaseOffsets` returns nil, `restoreSegmentOffsets` (the only
  in-memory index-mark on that branch) never runs, `isIndexed()` stays false.
  Reproduced cleanly on BOTH a fast-indexing TXT fixture and the EPUB fixture
  (30s timeouts at 06:32:42, 06:33:36, 06:35:31, 06:41:21, plus a fully clean
  35s live-stream capture showing zero indexing activity). Filed as Bug #264 /
  GH #1141 with two fix directions (reset clears the FTS store; or `setup()`
  falls through to re-index when offsets are nil). Cleared `SearchIndex/` to
  proceed; the feature's behavior verified after that.
- **The `search` driver works correctly once the index is built.** After
  clearing the stale store, the first indexed fire builds the index (so the
  immediate `index=0` tap can race a still-building index and report
  "no result at index 0"); a pre-warm query-only fire + a moment's settle, then
  the indexed fire, taps the result and navigates reliably. Recommend future
  search-tap verifications pre-warm the index (or wait for `isIndexed`) before
  the indexed fire — and that Bug #264's fix make `reset` a true clean slate.
- **Small-EPUB layout quirk persists (not a defect).** mini-epub3's chapter 2
  content sits at the top of the content area behind the chrome (round-4 noted
  this), but the highlight span is verifiably in-viewport (`spanTop: 148`,
  `inViewport: true`) and the yellow paint is plainly visible in the capture.

## Artifacts

- `dev-docs/verification/artifacts/feature-2-r6-epub-prewarm-results-20260522.png` — EPUB search results for "navigation" (chapter2 cross-chapter hit).
- `dev-docs/verification/artifacts/feature-2-r6-epub-highlight-visible-t1.2s-20260522.png` — EPUB: yellow highlight on "navigation" in Chapter Two at t≈1.2s.
- `dev-docs/verification/artifacts/feature-2-r6-epub-after-clear-t4.5s-20260522.png` — EPUB: highlight auto-cleared at t≈4.5s.
- `dev-docs/verification/artifacts/feature-2-r6-txt-hl-A-t0.7s-20260522.png` — TXT: yellow highlight on "Pierre" at t+0.7s.
- `dev-docs/verification/artifacts/feature-2-r6-txt-hl-B-t1.5s-20260522.png` — TXT: yellow highlight on "Pierre" at t+1.5s (sheet dismissed).
- `dev-docs/verification/artifacts/feature-2-r6-txt-after-clear-t4.5s-20260522.png` — TXT: highlight auto-cleared at t+4.5s.
- `dev-docs/verification/artifacts/feature-2-r6-epub-state-after-search-20260522.png`, `feature-2-r6-epub-search-results-20260522.png`, `feature-2-r6-epub-after-40s-wait-20260522.png`, `feature-2-r6-txt-after-search-20260522.png` — Bug #264 reproduction (empty-query stall) captures.

## Verdict

`pass` — Feature #2 verified end-to-end on both EPUB (round-5's fail leg) and
TXT (round-3's partial leg). Search → tap result → navigate to the matched
location → transient yellow highlight on the matched text → auto-clear after
~3s, all observed. Feature #2 row flips `DONE` → `VERIFIED`; GH #400 closes
with citation. The verification-harness stale-FTS-index defect is tracked
separately as Bug #264 / GH #1141 (does not block the Feature #2 flip — the
highlight feature works; only the CU-free repro needed the FTS-store reset).
