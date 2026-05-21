---
kind: feature
id: 64
status_target: VERIFIED
commit_sha: 080834199ce76af60e01d6ed608cd3f0bd5b29cb
app_version: 3.38.27 (build 602)
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
acceptance **round-3** verification against v3.38.27 (build 602), the first
release including BOTH:

- Bug #1084 fix (PR #1085, `0f124dfe`) — Stage-2 WebView-registration gate in
  `vreader-debug://settle?token=opened`.
- Bug #1086 fix (PR #1088, `08083419`) — Stage-1 early-settle fallback +
  observability in `EPUBWebViewBridgeCoordinator`.

Round-2 (`feature-64-20260521-round2.md`) concluded `partial` because EPUB hit
a Stage-1 settle timeout with no observable `didFinish`-side-effects. PR #1088
added Stage-1 instrumentation (`AppLogger.epub.info("loadFileURL: ...")`,
`didFinish: url=...`, `didFailProvisionalNavigation: ...`, `didFail: ...`) and
a 2.0s bounded fallback that synthesises both `setActiveEPUBWebView` and
`markReaderSettled` if `didFinish` doesn't fire in time. The author flagged
in the PR body: *"the brief explicitly asked to stop and file Bug #252 if a
deeper race were uncovered. The instrumentation added here was intended to
surface that race if it exists; the fallback is a defense-in-depth path."*

Round-3 directly tests whether those two fixes unblock the EPUB host-driven
verification path. Result:

1. **CU still down** — first `mcp__computer-use__screenshot` returned
   `CU display unavailable`. Tap-on-highlight popover observation remains
   structurally impossible from this session. (Round-1 + round-2 both
   reported the same.)
2. **TXT, MD, and AZW3 all settle cleanly post-#1088**, no regression. TXT
   and MD highlight-create paths through the DebugBridge complete end-to-end
   (`highlightCount: 0 → 1`, `lastError: null`). AZW3 settles cleanly through
   the Foliate WebView gate (Bug #1085's regression net for Foliate intact
   in #1088).
3. **EPUB STILL FAILS** — settle returns `error: "settle timeout"`,
   `phase: "unknown"` (same shape as round-2). Reproduced 2 independent
   times. The filtered `subsystem == "com.vreader.app"` log between
   `open: posted notification` and the settle timeout 41-55s later shows
   **ZERO new instrumentation logs**: no `loadFileURL: <file>`, no
   `didFinish: url=...`, no `didFailProvisionalNavigation`, no early-settle
   fallback fire. None of the new PR #1088 logs ever appear.

The critical diagnostic from PR #1088's instrumentation: the new log line
`[com.vreader.app:EPUB] loadFileURL: <file>` is emitted from
`EPUBWebViewBridge.updateUIView` *immediately before*
`webView.loadFileURL(...)`. The filtered `subsystem == "com.vreader.app"`
log stream did NOT contain that log on either EPUB attempt. **The
strongest inference from absence**: the run never reached the
`loadFileURL` logging site in `updateUIView`. The most parsimonious
explanation is that `updateUIView` was not invoked at all on the
`EPUBWebViewBridge` view for `mini-epub3`, i.e., the SwiftUI host
(`EPUBReaderContainerView`) never instantiated the bridge view, or the
bridge view never entered the view hierarchy, or the bridge's
`UIViewRepresentable.makeUIView` returned without `updateUIView` being
called downstream. **This is inference from absence on a filtered log
stream, not direct observation** — the next round should add
`AppLogger.epub.info` entry logs at the host layer
(`EPUBReaderContainerView.body` and `EPUBWebViewBridge.makeUIView`) to
directly observe what is or isn't being mounted; the current round
cannot directly distinguish "view tree never reached the bridge" from
"bridge mounted but `updateUIView` short-circuited before the log site".
What IS firm: the failure is upstream of the existing PR #1088
bridge-level instrumentation — neither #1085 (settle gate) nor #1086
(bridge-level fallback) could address it, because the bridge-level code
where they sit is never reached.

The 2.0s early-settle fallback in PR #1088 is scheduled inside
`EPUBWebViewBridge.updateUIView` immediately *after* `loadFileURL`. With
the run not reaching that schedule call (per the same log-absence
inference), the fallback `Task` is never scheduled, the cancel-token is
never armed, and the registry is never touched. The bridge
instrumentation can't observe what isn't there.

**Conclusion**: there is a layer-3 EPUB blocker upstream of the bridge.
Per the brief: *"if there is a THIRD EPUB race — file as Bug #252 and
stop"*. Filing **Bug #252** in `docs/bugs.md` (will be mirrored to GH as
a separate issue per the bug-tracker rule). With EPUB still blocked,
criterion 1 ("Tap-on-highlight opens unified popover") cannot be exercised
end-to-end on the EPUB format. Result remains `partial`; row #64 does NOT
flip to `VERIFIED`; GH #822 stays open with the existing
`awaiting-device-verification` label.

The acceptance criteria coverage that round-3 *does* contribute:

- Half of criterion 1 (the DebugBridge → `HighlightCoordinator.create(...)` →
  SwiftData write → snapshot `highlightCount` increment) is reconfirmed on
  TXT + MD with #1088 in place (no regression).
- AZW3 Foliate WebView path settles cleanly under #1088 (no regression on
  Bug #1085's gate behavior).
- The EPUB Stage-1 fallback in #1088 is *unit-tested* in
  `EPUBWebViewBridgeEarlySettleFallbackTests` (3 cases pass per PR body) —
  but **not** exercised on device because the upstream layer is broken.

## Acceptance criteria

| # | Criterion | Observed | Pass/Fail |
|---|-----------|----------|-----------|
| 1 | Tap-on-highlight opens unified popover on TXT | DebugBridge highlight-create succeeds (`highlightCount: 0 → 1`, `lastError: null` on snapshot `r3-txt-after-hl.json`). Tap-on-highlight observation requires CU; CU display unavailable. | DEFERRED (CU blocker) |
| 1 | Tap-on-highlight opens unified popover on MD | DebugBridge highlight-create succeeds (`highlightCount: 0 → 1`, `lastError: null` on snapshot `r3-md-after-hl.json`). Tap-on-highlight observation requires CU; CU display unavailable. | DEFERRED (CU blocker) |
| 1 | Tap-on-highlight opens unified popover on PDF | No DebugBridge `highlight` support for PDF per `docs/subsystems/debug-bridge.md` (only TXT/MD/EPUB are wired). No PDF fixture in `DebugFixtureCatalog`. Cannot create a highlight without CU; cannot observe tap without CU. | DEFERRED (harness gap + CU blocker) |
| 1 | Tap-on-highlight opens unified popover on EPUB | Settle returns `error: "settle timeout"`, `phase: "unknown"` 41-55s after `open` (2 independent attempts). **None of PR #1088's new logs appear** in the filtered `subsystem == "com.vreader.app"` stream: no `loadFileURL: <file>`, no `didFinish: url=...`, no `didFail*`, no early-settle fallback fire. The strongest inference from absence: the run did not reach the `loadFileURL` logging site inside `EPUBWebViewBridge.updateUIView`, which sits upstream of every PR #1085 / PR #1088 code path. **Filed as Bug #252**. | DEFERRED (new blocker: Bug #252) |
| 1 | Tap-on-highlight opens unified popover on AZW3 | Settle returns cleanly (no error) — Foliate WebView path works end-to-end on `mini-azw3` fixture. `vreader-debug://highlight` is a documented no-op on AZW3 (only TXT/MD/EPUB are wired in the observer), so `highlightCount` stays at 0 as expected. To exercise the tap-on-highlight path on AZW3, a highlight must first be created by the user (gesture path) OR a new bridge command must be added for AZW3/Foliate highlight-create. | DEFERRED (harness gap + CU blocker) |
| 2 | Popover shows correct excerpt, color swatch, note | Cannot observe popover (CU + EPUB-load blockers). | DEFERRED |
| 3 | Color change persists + repaints | Cannot exercise (no popover access). | DEFERRED |
| 4 | Note edit Save persists; reopen shows note; clear+save → empty state | Cannot exercise (no popover access). | DEFERRED |
| 5 | Copy puts excerpt on pasteboard; Share opens system share sheet | Cannot exercise (no popover access). | DEFERRED |
| 6 | Delete confirm → Confirm removes from persistence + clears render | Cannot exercise (no popover access). | DEFERRED |
| 7 | Long note + VoiceOver → bottom-sheet form | Cannot exercise (no popover access; VoiceOver needs CU). | DEFERRED |
| 8 | Light + dark themes both render correctly | Cannot exercise (no popover access). | DEFERRED |
| — | DebugBridge highlight-driver creates highlight on TXT (post-#1088) | Snapshot `r3-txt-after-hl.json`: `highlightCount: 1`, `currentBookId: txt:bd8285a8...:1705`, `lastError: null`. Log: `txt highlight observer: created start=0 end=20 color=yellow`. | PASS (regression net — confirms #1088 didn't regress TXT) |
| — | DebugBridge highlight-driver creates highlight on MD (post-#1088) | Snapshot `r3-md-after-hl.json`: `highlightCount: 1`, `currentBookId: md:963155b0...:925`, `lastError: null`. Log: `md highlight observer: created start=0 end=20 color=yellow`. | PASS (regression net) |
| — | AZW3 (Foliate) settles cleanly under #1088 (Bug #1085's regression net) | Snapshot `r3-azw3.json`: `highlightCount: 0`, `currentBookId: azw3:fadbaa44...:128650`, `format: azw3`, `lastError: null`. Settle returned in <11s with no error. | PASS (Bug #1085 regression net intact post-#1088) |
| — | PR #1088 Stage-1 instrumentation observable on EPUB load | **None of the new EPUB logs appear** in the filtered `subsystem == "com.vreader.app"` log stream: no `loadFileURL: <file>`, no `didFinish: url=...`, no `didFailProvisionalNavigation`, no `didFail`, no early-settle fallback. The bridge's `updateUIView` log site is not reached (inference from absence on a filtered stream). This was the diagnostic the PR #1088 author hoped would *resolve* the round-2 inference; instead it provides a stronger inference in the same direction: the failure is upstream of the bridge. **Direct observation requires** host-layer / `makeUIView` instrumentation, which the Bug #252 fix-direction names. | DEFERRED (Bug #252 — upstream of the instrumentation) |
| — | PR #1088 Stage-1 early-settle fallback fires on EPUB load | Unit-tested by `EPUBWebViewBridgeEarlySettleFallbackTests` (3 cases pass per PR body). **Not exercised on device**: the fallback `Task` is scheduled by `EPUBWebViewBridge.updateUIView` immediately after `loadFileURL`; under the inference that `updateUIView`'s log site is not reached, the fallback never schedules either. | DEFERRED (Bug #252 — upstream of the fallback) |

## Commands run

```bash
UDID=1FAB9493-B97E-48F0-96C7-44A8E5AAA21E
APP="/tmp/vreader-DD-r3/Build/Products/Debug-iphonesimulator/vreader.app"

# 0. CU probe (failed — CU display unavailable; same as round-1 and round-2)
# mcp__computer-use__screenshot → "CU display unavailable"

# 1. Build v3.38.27 + install + grant URL scheme approval
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
    -project vreader.xcodeproj -scheme vreader -configuration Debug \
    -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath /tmp/vreader-DD-r3
xcrun simctl install "$UDID" "$APP"
plutil -p "$APP/Info.plist" | grep CFBundle
# → CFBundleShortVersionString = 3.38.27, CFBundleVersion = 602 (post-#1086 fix)
bash scripts/grant-debug-scheme-approval.sh "$UDID"

# 2. TXT verification — post-#1088 baseline (no regression expected)
xcrun simctl launch "$UDID" com.vreader.app && sleep 5
xcrun simctl openurl "$UDID" "vreader-debug://reset" && sleep 2
xcrun simctl openurl "$UDID" "vreader-debug://seed?fixture=war-and-peace" && sleep 3
KEY="txt:bd8285a80f01df96dedd20a02178043afb85c0b499127e300baf57b7f1ed7508:1705"
ENC=$(printf '%s' "$KEY" | sed 's/:/%3A/g')
xcrun simctl openurl "$UDID" "vreader-debug://open?bookId=$ENC" && sleep 5
xcrun simctl openurl "$UDID" "vreader-debug://settle?token=txt-r3"
# → ready-txt-r3.json: clean settle, no error
xcrun simctl openurl "$UDID" "vreader-debug://highlight?start=0&end=20&color=yellow" && sleep 2
xcrun simctl openurl "$UDID" "vreader-debug://snapshot?dest=r3-txt-after-hl.json"
# → r3-txt-after-hl.json: highlightCount: 1, format: txt, lastError: null  → PASS

# 3. EPUB verification — 2 independent fresh attempts, both hit the same blocker
for attempt in 1 2; do
    xcrun simctl terminate "$UDID" com.vreader.app && sleep 2
    xcrun simctl launch "$UDID" com.vreader.app && sleep 5
    xcrun simctl openurl "$UDID" "vreader-debug://reset" && sleep 2
    xcrun simctl openurl "$UDID" "vreader-debug://seed?fixture=mini-epub3" && sleep 3
    KEY="epub:f284fd074ccd1d3c1a78985464d9e1be27975f4029f3c2ddef8428ca10684af4:2198"
    ENC=$(printf '%s' "$KEY" | sed 's/:/%3A/g')
    xcrun simctl openurl "$UDID" "vreader-debug://open?bookId=$ENC" && sleep 25
    xcrun simctl openurl "$UDID" "vreader-debug://settle?token=epub-r3-att${attempt}"
done
# → Both attempts: ready-epub-r3*.json carries error="settle timeout", phase="unknown"

# 4. Log capture — filtered to com.vreader.app subsystem. The conclusion below
#    is based on ABSENCE of expected app-subsystem logs in that filtered stream,
#    not direct observation of the SwiftUI/representable lifecycle.
xcrun simctl spawn "$UDID" log show --last 300s \
    --predicate 'subsystem == "com.vreader.app"' --info --debug --style compact
# → Captured (only DebugBridge events, no EPUB events at info / debug / error):
#   01:57:42.541 I  vreader[52953] [com.vreader.app:DebugBridge] reset: removed 1 book(s)
#   01:57:44.684 I  vreader[52953] [com.vreader.app:DebugBridge] seed: imported mini-epub3 → key=epub:f284fd...:2198 duplicate=false
#   01:57:47.810 I  vreader[52953] [com.vreader.app:DebugBridge] open: posted notification for epub:f284fd...:2198
#   ── ~41s gap with NO com.vreader.app subsystem events of any kind ──
#   01:58:28.780 E  vreader[52953] [com.vreader.app:DebugBridge] settle: ready-epub-r3.json with error=settle timeout
#   (attempt 2: same shape with a longer 55s gap due to the longer pre-settle wait)
# → No `loadFileURL: <file>` log (the new info log from EPUBWebViewBridge.updateUIView).
# → No `didFinish: url=<file>` log (the new info log from EPUBWebViewBridgeCoordinator).
# → No `didFailProvisionalNavigation: ...` / `didFail: ...` (the new error logs).
# → No early-settle fallback fire (would have written setActiveEPUBWebView + markReaderSettled).
# → No EPUB-category logs at any level.

# 5. MD verification — first re-confirm on v3.38.27
xcrun simctl terminate "$UDID" com.vreader.app && sleep 2
xcrun simctl launch "$UDID" com.vreader.app && sleep 5
xcrun simctl openurl "$UDID" "vreader-debug://reset" && sleep 2
xcrun simctl openurl "$UDID" "vreader-debug://seed?fixture=mini-markdown" && sleep 3
KEY="md:963155b04610b17a19e93ecd96dcca4201dcd6b1d2b959dc462e8dfcd1487754:925"
ENC=$(printf '%s' "$KEY" | sed 's/:/%3A/g')
xcrun simctl openurl "$UDID" "vreader-debug://open?bookId=$ENC" && sleep 5
xcrun simctl openurl "$UDID" "vreader-debug://settle?token=md-r3"
# → ready-md-r3.json: clean settle
xcrun simctl openurl "$UDID" "vreader-debug://highlight?start=0&end=20&color=yellow" && sleep 3
xcrun simctl openurl "$UDID" "vreader-debug://snapshot?dest=r3-md-after-hl.json"
# → r3-md-after-hl.json: highlightCount: 1, format: md, lastError: null  → PASS

# 6. AZW3 verification — confirm Foliate path still settles cleanly under #1088
xcrun simctl terminate "$UDID" com.vreader.app && sleep 2
xcrun simctl launch "$UDID" com.vreader.app && sleep 5
xcrun simctl openurl "$UDID" "vreader-debug://reset" && sleep 2
xcrun simctl openurl "$UDID" "vreader-debug://seed?fixture=mini-azw3" && sleep 4
KEY="azw3:fadbaa44ae1f5130992b0c9fa795b90796900c6b56b9d19af4d49c5dccf27d33:128650"
ENC=$(printf '%s' "$KEY" | sed 's/:/%3A/g')
xcrun simctl openurl "$UDID" "vreader-debug://open?bookId=$ENC" && sleep 10
xcrun simctl openurl "$UDID" "vreader-debug://settle?token=azw3-r3"
# → ready-azw3-r3.json: clean settle (Foliate WebView registered before 5s Stage-2 budget)
xcrun simctl openurl "$UDID" "vreader-debug://highlight?start=0&end=20&color=yellow" && sleep 3
xcrun simctl openurl "$UDID" "vreader-debug://snapshot?dest=r3-azw3.json"
# → r3-azw3.json: highlightCount: 0 (documented no-op for AZW3), lastError: null, format: azw3  → PASS
```

## Observations

1. **Three EPUB fix layers now exist; none address the actual problem.**
   - Bug #1084 / PR #1085: Stage-2 WebView-registration gate (after Stage-1
     settle resolves). Sound on its own merits (6 unit tests), unrelated to
     this failure.
   - Bug #1086 / PR #1088: Stage-1 early-settle fallback inside the bridge
     coordinator + observability for `didFinish` / `didFail*`. Also sound on
     its own merits (3 unit tests). Unrelated to this failure.
   - Bug #252 (this PR's filing): the layer ABOVE the bridge — neither the
     SwiftUI host nor the `UIViewRepresentable` ever lands `EPUBWebViewBridge`
     into the view hierarchy, so neither set of fixes is exercised.

2. **The new instrumentation strengthened the round-2 inference but did
   not close it.** Round-2 ended with the inference *"the most
   parsimonious explanation is that `didFinish` does not fire, but the
   round-2 instrumentation cannot directly confirm that."* Round-3 now
   strengthens that to a deeper inference: the filtered
   `subsystem == "com.vreader.app"` log stream does not contain any of
   PR #1088's new EPUB-category logs, including the
   `[com.vreader.app:EPUB] loadFileURL: <file>` line that's emitted
   inside `EPUBWebViewBridge.updateUIView` immediately before
   `webView.loadFileURL(...)`. The strongest inference from that
   absence: the run does not reach the `loadFileURL` log site inside
   `updateUIView`. This **remains inference from absence on a filtered
   stream** — round-3 did not add host-layer / `makeUIView` logs to
   prove the bridge wasn't mounted vs mounted-but-bypassed.
   Direct observation is the explicit fix-direction (b) named in Bug
   #252. The suspect surface moves from `EPUBWebViewBridgeCoordinator`
   *up* to either `EPUBReaderContainerView`'s SwiftUI body / route, the
   `ReaderContainerView.engineReaderView` dispatch, or `ReaderEngine`'s
   format resolution. (All of these were churned heavily by feature #56
   bilingual + feature #62 chrome rewire + feature #64 popover migration
   in v3.38.x.)

3. **Cross-reference with Bug #244** (user-triage 2026-05-20, "EPUB reader
   opens but content area is blank"). Bug #244's symptom is *production*
   user-visible — open an EPUB from the library, the reader chrome
   appears but the content area paints blank. Bug #252's symptom is
   *autonomous-harness*, but the underlying cause sits at the same layer.
   Plausible hypothesis: both Bug #244 and Bug #252 share a single root
   cause — an EPUB host/route regression in v3.38.x that prevents
   `EPUBWebViewBridge` from being mounted (or mounts it without ever
   reaching `updateUIView`). If so, the Bug #244 fix likely subsumes
   Bug #252 — and Bug #244's fix priority moves up because it now blocks
   automated verification of EVERY EPUB-touching feature, not just user
   reading.

4. **CU outage continues into a third session.** Round-1 (2026-05-20),
   round-2 (2026-05-21 morning), round-3 (2026-05-21 evening) all hit
   `CU display unavailable` despite `request_access` succeeding. The
   verify cron's CU dependence for feature #64's criterion 1 is now a
   structural risk over multiple days, not an isolated outage. Even with
   Bug #252 fixed AND Bug #244 fixed, criterion 1 cannot reach `pass`
   without either CU coming back OR a new DebugBridge command that
   exposes popover-visible state (see round-2 Observation #5).

5. **Decision: filing Bug #252 rather than blocking on a popover-state
   DebugBridge command.** The brief permitted either path. Filing Bug #252
   is the right call because: (a) it surfaces a regression that affects
   far more than this verification (per Observation #3, it likely shares
   a root cause with the user-reported Bug #244, which is a critical
   production bug); (b) the popover-state command is *also* needed, but
   filing it as a separate feature ask is a parallel track — building
   it doesn't change the fact that EPUB load is broken in v3.38.x.

6. **No new ImportedBooks/ leakage observed this round.** Round-2 observed
   the directory accumulating files across sessions (Observation #6 of
   round-2). The reset path didn't accumulate further this session, so
   it's not actively worsening; still candidate for a low-severity bug
   later.

## Artifacts

- `dev-docs/verification/feature-64-20260521-round3.md` — this file
- DebugBridge snapshot files (in-simulator, not exported to repo):
  - `Library/Caches/DebugBridge/r3-txt-after-hl.json` (TXT: `highlightCount: 1`, format `txt`)
  - `Library/Caches/DebugBridge/r3-md-after-hl.json` (MD: `highlightCount: 1`, format `md`)
  - `Library/Caches/DebugBridge/r3-azw3.json` (AZW3: `highlightCount: 0`, format `azw3`, no error)
  - `Library/Caches/DebugBridge/ready-epub-r3.json` (EPUB attempt 1: `error: "settle timeout"`)
  - `Library/Caches/DebugBridge/ready-epub-r3-att2.json` (EPUB attempt 2: `error: "settle timeout"`)
- Log snippets quoted inline in the Commands run section.
- Round-1 evidence: `dev-docs/verification/feature-64-20260520.md`
- Round-2 evidence: `dev-docs/verification/feature-64-20260521-round2.md`
- New blocker: Bug #252 (this PR; row added in `docs/bugs.md`).
- Cross-reference candidates: Bug #244 (production EPUB blank), Bug #251
  (FIXED in #1088 but the fix did not address the right layer).
