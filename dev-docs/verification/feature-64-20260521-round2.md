---
kind: feature
id: 64
status_target: VERIFIED
commit_sha: 0f124dfecd875153c822b710324a12d3306c4b68
app_version: 3.38.25 (build 600)
date: 2026-05-21
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator (UDID 1FAB9493-B97E-48F0-96C7-44A8E5AAA21E)
os_version: iOS 26.5
build_configuration: Debug
backend: n/a
result: partial
---

## Summary

Feature #64 (Unified cross-format highlight-action popover) — Gate-5b
acceptance round-2 verification attempt against v3.38.25 (build 600), the
first release including Bug #1084's fix (PR #1085, `0f124dfe`). Round-1
(against v3.38.22, evidence `feature-64-20260520.md`) returned `result:
partial` because (a) `mcp__computer-use__screenshot` returned `CU display
unavailable` throughout the run, and (b) the EPUB DebugBridge highlight-create
hit `no active EPUB WebView registered` due to the WebView-registration race
that Bug #1084 fixed.

Round-2 re-tested both blockers against the fix-shipped build:

1. **CU is still down** — first `mcp__computer-use__screenshot` after
   `request_access` granted (`com.apple.iphonesimulator` at `full` tier)
   returned `CU display unavailable`. Tap-on-highlight popover observation
   remains structurally impossible from this session. (Bug #1054 class; not
   feature #64's fault.)
2. **TXT, MD, and AZW3 (Foliate) probe-settle paths all work cleanly**
   against v3.38.25. The TXT and MD highlight-create paths through the
   DebugBridge complete end-to-end (`highlightCount: 0 → 1`,
   `lastError: null`). AZW3 settles cleanly via the Foliate WebView gate;
   `vreader-debug://highlight` is documented as a no-op on AZW3 (only
   TXT/MD/EPUB are wired) so highlightCount stays at 0 as expected — but
   the Foliate WebView readiness IS confirmed.
3. **EPUB hits a NEW, deeper blocker** — settle returns with
   `error: "settle timeout"` (not the new `webview not registered` sentinel
   that Bug #1085 added). The directly-observed symptoms: `settle` writes
   `error: "settle timeout"` 30s after the URL fires; the filtered
   `subsystem == "com.vreader.app"` log between `open: posted notification`
   and the settle timeout shows ZERO EPUB-load events (no didFinish, no
   `markReaderSettled`, no `setActiveEPUBWebView`); a subsequent
   `vreader-debug://highlight` URL fires the observer but logs
   `no active EPUB WebView registered`, and the post-highlight snapshot
   shows `highlightCount: 0`. Sequence repeated three times across
   separate fresh `simctl terminate`+`launch` cycles, identical outcome
   each time. The most parsimonious explanation is that
   `EPUBWebViewBridgeCoordinator.webView(_:didFinish:)` never runs for
   `mini-epub3` in this build (the callback is the sole caller of both
   `markReaderSettled` and `setActiveEPUBWebView`, and neither side-effect
   is visible) — but the round-2 instrumentation cannot directly confirm
   that `didFinish` was or was not invoked, because no entry log exists at
   that callback today. The new sentinel error `webview not registered`
   does not appear, which is consistent with Stage-1 of settle timing out
   before Stage-2's WebView-registration gate is ever entered. This
   differs in symptom shape from round-1's documented EPUB block: round-1
   logged `epub highlight observer: ... no active EPUB WebView
   registered` after the highlight URL fired, but the round-1 evidence
   file did not directly prove `didFinish` ran in that round either —
   round-1's PARTIAL row inferred the observer-invocation path was wired
   on v3.38.22 (`bridge wired but EPUB WKWebView not registered`). What
   round-2 establishes is that in v3.38.25 the registration gap is
   present AND not just a late-binding race that Bug #1085 would close.

The new EPUB blocker is filed as **Bug #251** in `docs/bugs.md` (will be
mirrored to GH as a separate issue per the bug-tracker rule). With EPUB
blocked, criterion 1 ("Tap-on-highlight opens unified popover") cannot be
exercised end-to-end on the EPUB format, so the criterion stays DEFERRED
and the overall verification result remains `partial`.

The DebugBridge evidence for TXT + MD highlight-creation continues to
demonstrate the wiring is correct on the layer below the device-tap behavior:
unified `HighlightCoordinator.create(...)` is invoked with the expected
parameters on both formats, `HighlightPopoverViewModel` / Router / Mutation
tests (64 tests / 7 suites) remained green throughout the round (this
session did not rebuild the unit suite — last known-green state is from
round-1's evidence). For acceptance purposes, the slice from
DebugBridge URL → `HighlightCoordinator.create(...)` → SwiftData write →
snapshot's `highlightCount` increment is confirmed working on TXT + MD;
this is half of criterion 1's evidence path. The tap-on-highlight side
(highlight render → tap → `HighlightActionPresenter` → popover present)
is the half that requires either CU or an `xcrun simctl io tap` synthesizer
that does not currently exist in the harness.

Per `dev-docs/verification/SCHEMA.md`, `result: partial` keeps the tracker
at `DONE awaiting partial-VERIFIED` — row #64 does NOT flip to `VERIFIED`,
and GH #822 stays open with the existing `awaiting-device-verification`
label. The follow-up evidence file (round-3) will require either Bug #251
fix to unblock EPUB OR a different verification path (e.g., a new
DebugBridge command that observes popover state).

## Acceptance criteria

| # | Criterion | Observed | Pass/Fail |
|---|-----------|----------|-----------|
| 1 | Tap-on-highlight opens unified popover on TXT | DebugBridge highlight-create succeeds (`highlightCount: 0 → 1`, `lastError: null` on snapshot `r2-txt-after-hl.json`). Tap-on-highlight observation requires CU; CU display unavailable; cannot exercise the tap path. | DEFERRED (CU blocker) |
| 1 | Tap-on-highlight opens unified popover on MD | DebugBridge highlight-create succeeds (`highlightCount: 0 → 1`, `lastError: null` on snapshot `r2-md-after-hl.json`). Tap-on-highlight observation requires CU; cannot exercise. | DEFERRED (CU blocker) |
| 1 | Tap-on-highlight opens unified popover on PDF | No DebugBridge `highlight` support for PDF per `docs/subsystems/debug-bridge.md` (only TXT/MD/EPUB are wired). No PDF fixture in `DebugFixtureCatalog`. Cannot create a highlight without CU; cannot observe tap without CU. | DEFERRED (harness gap + CU blocker) |
| 1 | Tap-on-highlight opens unified popover on EPUB | Settle returns `error: "settle timeout"`. Filtered `subsystem == "com.vreader.app"` log shows zero EPUB-load events between `open: posted notification` and the 30s-later timeout — `EPUBWebViewBridgeCoordinator.webView(_:didFinish:)` *appears not to fire* (the inference is supported by the absence of the callback's side-effects `markReaderSettled` and `setActiveEPUBWebView`, both of which would have produced observable downstream state; the callback's happy-path has no direct entry log today, so this is inference, not direct observation). Subsequent `vreader-debug://highlight` URL fires the observer but the WebView slot is empty (logs: `epub highlight observer: no active EPUB WebView registered`); post-highlight snapshot shows `highlightCount: 0`, `lastError: null`. Different symptom shape from Bug #1084's documented stale-write-guard race that Bug #1085 fixed. **Filed as Bug #251**. | DEFERRED (new blocker: Bug #251) |
| 1 | Tap-on-highlight opens unified popover on AZW3 | Settle returns cleanly (no error) — Foliate WebView path works end-to-end on `mini-azw3` fixture (Bug #1085 fix's gate enters Stage-2 and confirms registration). `vreader-debug://highlight` is a documented no-op on AZW3 (only TXT/MD/EPUB are wired in the observer), so `highlightCount` stays at 0 as expected. To exercise the tap-on-highlight path on AZW3, a highlight must first be created by the user (gesture path) OR a new bridge command must be added for AZW3/Foliate highlight-create. | DEFERRED (harness gap + CU blocker) |
| 2 | Popover shows correct excerpt, color swatch, note | Cannot observe popover (CU + EPUB-load blockers). | DEFERRED |
| 3 | Color change persists + repaints | Cannot exercise (no popover access). | DEFERRED |
| 4 | Note edit Save persists; reopen shows note; clear+save → empty state | Cannot exercise (no popover access). | DEFERRED |
| 5 | Copy puts excerpt on pasteboard; Share opens system share sheet | Cannot exercise (no popover access). | DEFERRED |
| 6 | Delete confirm → Confirm removes from persistence + clears render | Cannot exercise (no popover access). | DEFERRED |
| 7 | Long note + VoiceOver → bottom-sheet form | Cannot exercise (no popover access; VoiceOver needs CU). | DEFERRED |
| 8 | Light + dark themes both render correctly | Cannot exercise (no popover access). | DEFERRED |
| — | DebugBridge highlight-driver creates highlight on TXT (post-#1085) | Snapshot `r2-txt-after-hl.json`: `highlightCount: 1`, `currentBookId: txt:bd8285a8...:1705`, `lastError: null`. Log: `txt highlight observer: created start=0 end=20 color=yellow`. | PASS (supporting evidence — confirms #1085 did not regress TXT path) |
| — | DebugBridge highlight-driver creates highlight on MD (post-#1085) | Snapshot `r2-md-after-hl.json`: `highlightCount: 1`, `currentBookId: md:963155b0...:925`, `lastError: null`. Log: `md highlight observer: created start=0 end=20 color=yellow`. **First MD bridge highlight-create verification in this codebase** — round-1 did not exercise MD (it was assumed to share the TXT path; this confirms the assumption). | PASS (supporting evidence) |
| — | DebugBridge settle's new `webview not registered` sentinel (Bug #1085's contract) for EPUB | Could NOT exercise the new sentinel — EPUB settle hits Stage-1 timeout (`error: "settle timeout"`) so the new Stage-2 gate is never entered. The Stage-2 gate's behavior is covered by Bug #1085's 6 new XCTests (`RealDebugBridgeContextTests`) at the unit layer; device-layer verification of the new sentinel is blocked by Bug #251 (the deeper EPUB-didFinish blocker). | DEFERRED (Bug #251 blocks) |
| — | AZW3 (Foliate) settle settles cleanly (Bug #1085's regression net) | Snapshot `r2-azw3.json`: `highlightCount: 0`, `currentBookId: azw3:fadbaa44...:128650`, `format: azw3`, `lastError: null`. Settle returned in <4s with no error (Foliate WebView registered before the 5s Stage-2 budget expired). | PASS (Bug #1085 regression net intact for Foliate) |

## Commands run

```bash
UDID=1FAB9493-B97E-48F0-96C7-44A8E5AAA21E
APP="/Users/ll/Library/Developer/Xcode/DerivedData/vreader-hagfbubkbstwddhhbgetozikbipd/Build/Products/Debug-iphonesimulator/vreader.app"

# 0. CU probe (failed — CU display unavailable; same as round-1)
# mcp__computer-use__request_access {Simulator} → granted full tier
# mcp__computer-use__screenshot → "CU display unavailable"

# 1. Confirm installed version is pre-fix (v3.38.22), then build + install v3.38.25
plutil -p "$(xcrun simctl get_app_container "$UDID" com.vreader.app app)/Info.plist" \
    | grep -E "CFBundleShortVersionString|CFBundleVersion"
# → CFBundleShortVersionString = 3.38.22, CFBundleVersion = 597 (pre-#1085)

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
    -project vreader.xcodeproj -scheme vreader -configuration Debug \
    -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath /Users/ll/Library/Developer/Xcode/DerivedData/vreader-hagfbubkbstwddhhbgetozikbipd
xcrun simctl install "$UDID" "$APP"
plutil -p "$APP/Info.plist" | grep CFBundle
# → CFBundleShortVersionString = 3.38.25, CFBundleVersion = 600 (post-#1085)

bash scripts/grant-debug-scheme-approval.sh "$UDID"

# 2. TXT verification — round-1 baseline reproduced post-#1085
xcrun simctl openurl "$UDID" "vreader-debug://reset"
xcrun simctl openurl "$UDID" "vreader-debug://seed?fixture=war-and-peace"
KEY="txt:bd8285a80f01df96dedd20a02178043afb85c0b499127e300baf57b7f1ed7508:1705"
ENC=$(printf '%s' "$KEY" | sed 's/:/%3A/g')
xcrun simctl openurl "$UDID" "vreader-debug://open?bookId=$ENC"
xcrun simctl openurl "$UDID" "vreader-debug://settle?token=opened"
# → ready-opened.json: clean settle, no error
xcrun simctl openurl "$UDID" "vreader-debug://highlight?start=0&end=20&color=yellow"
xcrun simctl openurl "$UDID" "vreader-debug://snapshot?dest=round2-txt-after-hl.json"
# → highlightCount: 1, format: txt, lastError: null  → PASS

# 3. EPUB verification — three independent fresh attempts, all hit the same blocker
for attempt in 1 2 3; do
    xcrun simctl terminate "$UDID" com.vreader.app
    sleep 2
    xcrun simctl launch "$UDID" com.vreader.app
    sleep 5
    xcrun simctl openurl "$UDID" "vreader-debug://reset"
    sleep 3
    xcrun simctl openurl "$UDID" "vreader-debug://seed?fixture=mini-epub3"
    sleep 3
    KEY="epub:f284fd074ccd1d3c1a78985464d9e1be27975f4029f3c2ddef8428ca10684af4:2198"
    ENC=$(printf '%s' "$KEY" | sed 's/:/%3A/g')
    xcrun simctl openurl "$UDID" "vreader-debug://open?bookId=$ENC"
    sleep 20  # generous pre-settle wait
    xcrun simctl openurl "$UDID" "vreader-debug://settle?token=epub-attempt-$attempt"
    # Each attempt: settle writes `error: "settle timeout"` 30s after first openurl
    # (Stage-1 awaitSettle timed out — no `markReaderSettled` ever fired).
done
# → All three: ready-epub-*.json carries error="settle timeout", phase="unknown"

# After the first EPUB attempt's settle timeout, drive the highlight URL + snapshot
# to confirm the WebView slot is empty (the symptom that motivated Bug #251's filing):
xcrun simctl openurl "$UDID" "vreader-debug://highlight?start=0&end=20&color=yellow"
xcrun simctl openurl "$UDID" "vreader-debug://snapshot?dest=r2-epub-after-hl.json"
# → r2-epub-after-hl.json: highlightCount: 0, format: epub, lastError: null
# → log line: [DebugBridge] epub highlight observer: no active EPUB WebView registered for epub:f284fd...:2198

# Log inspection confirms the symptom — ZERO EPUB-load events between `open: posted notification`
# and the settle timeout 30s later (only DebugBridge events visible — no EPUB / WebView /
# didFinish events at info / debug / error level):
xcrun simctl spawn "$UDID" log show --last 120s \
    --predicate 'subsystem == "com.vreader.app"' --info --debug --style compact
# → Captured log block (PID 41071, attempt #2 in the round-2 session):
#   01:00:24.390 I  [DebugBridge] reset: removed 1 book(s)
#   01:00:26.535 I  [DebugBridge] seed: imported mini-epub3 → key=epub:f284fd...:2198 duplicate=false
#   01:00:28.666 I  [DebugBridge] open: posted notification for epub:f284fd...:2198
#   ── 30s gap with no com.vreader.app subsystem events ──
#   01:00:58.830 I  [DebugBridge] snapshot: wrote 514 bytes to r2-epub-mid.json
#   01:01:NN E  [DebugBridge] settle: ready-<token>.json with error=settle timeout
#   (subsequent attempt: same shape with different timestamps + token names)
# Note: this is a filtered log (only `subsystem == "com.vreader.app"`). The absence
# of EPUB-coordinator log lines is consistent with `didFinish` not running, but
# does not directly observe the callback's entry — the EPUBWebViewBridgeCoordinator's
# happy-path `didFinish` has no entry-level log emission today, so the inference is
# load-bearing on the absence of `markReaderSettled` / `setActiveEPUBWebView`
# side-effects (both of which would have produced observable downstream state).

# 4. MD verification — first-ever bridge highlight-create on MD
xcrun simctl terminate "$UDID" com.vreader.app && sleep 2
xcrun simctl launch "$UDID" com.vreader.app && sleep 5
xcrun simctl openurl "$UDID" "vreader-debug://reset" && sleep 2
xcrun simctl openurl "$UDID" "vreader-debug://seed?fixture=mini-markdown" && sleep 3
KEY="md:963155b04610b17a19e93ecd96dcca4201dcd6b1d2b959dc462e8dfcd1487754:925"
ENC=$(printf '%s' "$KEY" | sed 's/:/%3A/g')
xcrun simctl openurl "$UDID" "vreader-debug://open?bookId=$ENC" && sleep 5
xcrun simctl openurl "$UDID" "vreader-debug://settle?token=md-r2"
# → ready-md-r2.json: clean settle
xcrun simctl openurl "$UDID" "vreader-debug://highlight?start=0&end=20&color=yellow"
xcrun simctl openurl "$UDID" "vreader-debug://snapshot?dest=r2-md-after-hl.json"
# → highlightCount: 1, format: md, lastError: null  → PASS

# 5. AZW3 verification — confirm Foliate path works end-to-end (Bug #1085 regression net)
xcrun simctl terminate "$UDID" com.vreader.app && sleep 2
xcrun simctl launch "$UDID" com.vreader.app && sleep 5
xcrun simctl openurl "$UDID" "vreader-debug://reset" && sleep 2
xcrun simctl openurl "$UDID" "vreader-debug://seed?fixture=mini-azw3" && sleep 4
KEY="azw3:fadbaa44ae1f5130992b0c9fa795b90796900c6b56b9d19af4d49c5dccf27d33:128650"
ENC=$(printf '%s' "$KEY" | sed 's/:/%3A/g')
xcrun simctl openurl "$UDID" "vreader-debug://open?bookId=$ENC" && sleep 8
xcrun simctl openurl "$UDID" "vreader-debug://settle?token=azw3-r2"
# → ready-azw3-r2.json: clean settle (Foliate WebView registered within 5s Stage-2 budget)
xcrun simctl openurl "$UDID" "vreader-debug://highlight?start=0&end=20&color=yellow"
xcrun simctl openurl "$UDID" "vreader-debug://snapshot?dest=r2-azw3.json"
# → highlightCount: 0 (documented no-op for AZW3), lastError: null, format: azw3  → PASS
```

## Observations

1. **Bug #1084 fix didn't unblock EPUB autonomous verification in this codebase.**
   Bug #1085 added a Stage-2 WebView-registration gate to `settle`, but the
   gate is only entered after Stage-1 (`probe.awaitSettle`) succeeds. The
   EPUB blocker we're hitting now is at Stage-1: `EPUBWebViewBridgeCoordinator.webView(_:didFinish:)`
   never fires for `mini-epub3` in this session. The Stage-2 gate's
   new `webview not registered` sentinel is therefore never written —
   instead we get the pre-#1085 `settle timeout`. The fix is sound on
   its own merits (the unit tests in `RealDebugBridgeContextTests` exercise
   it); it just doesn't address the failure mode we're now hitting.

2. **AZW3 (Foliate) settles cleanly while EPUB doesn't.** Both paths
   use a WKWebView, both rely on `didFinish` to register the WebView slot
   and signal `markReaderSettled`. The asymmetry strongly suggests the
   regression is specific to `EPUBReaderHost` / `EPUBWebViewBridgeCoordinator`
   — possibly a change in v3.38.x that ships an EPUB-side wiring change
   between when round-1's harness last successfully opened `mini-epub3`
   (per the round-1 evidence's PARTIAL row, the EPUB observer did get
   invoked, which means `didFinish` did fire at least once on v3.38.22)
   and now (v3.38.25). I did not bisect — the bug filing recommends a
   bisect over v3.38.22..v3.38.25.

3. **MD path verified end-to-end via bridge for the first time.** Round-1
   assumed MD shared the TXT path (they both go through `TXTService` /
   the chunked `UITextView` host); round-2 confirms it. `highlightCount`
   increments cleanly on `mini-markdown` fixture. This isn't a #64-specific
   verification but it's a useful side-effect — feature #65 (AI sheet
   re-skin) and future MD-touching features can rely on the MD bridge
   path autonomously now.

4. **CU outage is becoming a chronic blocker.** Round-1 (2026-05-20) and
   round-2 (2026-05-21) both hit `CU display unavailable` despite multiple
   `request_access` retries. The verify cron's CU dependence for feature
   #64's criterion 1 is a structural risk — without either CU coming back
   OR a new DebugBridge command that exposes popover state, the feature
   cannot reach `VERIFIED` even if Bug #251 is fixed.

5. **Snapshot schema does not expose popover state.** `DebugSnapshot` v2
   (`DebugSnapshot.swift`) exposes `selection` (text selection, partial),
   `highlightCount`, `renderPhase`, `ttsState`, etc., but has no field
   for "is the unified highlight popover visible / what's its content".
   Adding a `popover: { visible: Bool, mode: String, excerpt: String, ... }`
   field to the snapshot would unblock criterion 1 verification without
   CU. This is a candidate WI for a future DebugBridge improvement
   (or for feature #64 to add a verification helper before it can reach
   VERIFIED).

6. **Stale ImportedBooks/ files on the simulator.** `vreader-debug://reset`
   purges the SwiftData library rows but leaves the on-disk
   `ImportedBooks/<format>_<sha>_<bytes>.<ext>` files. The directory
   carries 13 leftover files from previous sessions. This doesn't break
   the verification (the import re-creates the SwiftData rows, and the
   canonical-key + byte-count match the bundled fixture so dedupe works)
   but it's a tidiness regression worth filing as a low-severity bug
   later.

## Artifacts

- `dev-docs/verification/feature-64-20260521-round2.md` — this file
- DebugBridge snapshot files (in-simulator, not exported to repo — captured here for reference):
  - `Library/Caches/DebugBridge/round2-txt-after-hl.json` (TXT: `highlightCount: 1`, format `txt`)
  - `Library/Caches/DebugBridge/r2-md-after-hl.json` (MD: `highlightCount: 1`, format `md`)
  - `Library/Caches/DebugBridge/r2-azw3.json` (AZW3: `highlightCount: 0`, format `azw3`, no error)
  - `Library/Caches/DebugBridge/ready-epub-attempt-{1,2,3}.json` (EPUB: `error: "settle timeout"` on each attempt)
  - `Library/Caches/DebugBridge/r2-epub-after-hl.json` (EPUB: post-highlight snapshot — `highlightCount: 0`, format `epub`, `lastError: null` — and the matching log line `[DebugBridge] epub highlight observer: no active EPUB WebView registered`)
- Log snippets quoted inline in the Commands run section (no exported log files).
- Round-1 evidence: `dev-docs/verification/feature-64-20260520.md` (for comparison).
- New blocker: Bug #251 (this PR; row added in `docs/bugs.md`).
