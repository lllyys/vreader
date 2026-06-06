---
branch: feat/feature-74-bloom-verify-harness
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-06-06
---

# Gate-4 audit — Feature #74 locate-bloom CU-free verification harness (DEBUG-only)

A DEBUG-only verification affordance (the plan's recommended unblock): a
`vreader-debug://locate?highlight=N` command that posts `.readerNavigateToLocator`
with the Nth persisted highlight's locator (the SAME channel the annotations-row
tap uses) to fire the locate bloom through the real render path, plus
`DebugSnapshot.landingBloomCount` / `landingBloomPeakIntensity` read back from
`HighlightableTextView` so a CU-free `snapshot` can assert the bloom fired (the
~1.5s sub-second visual cannot be screenshot/video-captured on the Screen-Sharing
virtual display). Adds a non-chaptered `bloom-sample.txt` fixture (the
non-chunked `TXTTextViewBridge` path the bloom lives in).

## Manual fallback — why

The independent Codex auditor (`scripts/run-codex.sh`) wedged at 0% CPU during
the file-read phase (rule-53 ghost; killed, no findings emitted). Per rule 47,
manual-fallback is used with evidence below.

## Manual Audit Evidence

**Files read**: `RealDebugBridgeContext+Locate.swift`,
`ReaderContainerView+DebugBridgeLandingBloom.swift`, `HighlightableTextView.swift`,
`DebugSnapshot.swift`, `RealDebugBridgeContext+Snapshot.swift`, `DebugCommand.swift`,
`DebugBridge.swift`, `DebugReaderRegistry.swift`, `DebugReaderProbeAdapter.swift`,
`DebugBridgeNotifications.swift`, `DebugFixtureCatalog.swift`,
`ReaderNotificationHandlers.swift` (the navigate handler), `TXTTextViewBridge.swift`
(the bloom trigger), `TXTChunkedReaderBridge.swift` (the chunked path).

**Symbols / behavior verified**:
- The `locate` handler posts `highlights[index].locator` — identical to the real
  `HighlightsSheet` row tap (`HighlightsSheet+Delete.swift:104 onNavigate(record.locator)`),
  so it drives the production path, not a parallel one. No `@Model` crosses the
  actor boundary (uses the `HighlightRecord` value type). No-op guards mirror
  `navigate`/`seek`/`present`.
- `handleNavigateToLocator` sets `highlightRange` from the locator's
  `charRangeStart/EndUTF16`; the DEBUG `highlight?` command builds the locator via
  `LocatorFactory.txtRange` (carries the full range), so `landingTrigger` matches
  the persisted highlight → the bloom fires. Confirmed by the e2e below.
- DEBUG-gating: every harness symbol is `#if DEBUG`; `verify-release-no-debugbridge.sh`
  against the Release `.app` printed `PASS: zero DebugBridge surface in Release`.
- Schema bump v2→v3: the two new fields are optionals with `decodeIfPresent`/
  `encodeOptional` (forward/back compat) — pinned by `DebugSnapshotTests` (21).
- The readback chain (HighlightableTextView records count/peak → posts
  `.debugBridgeLandingBloomChanged` → `ReaderContainerView` caches onto the probe
  → snapshot reads) is proven end-to-end by the e2e (not just unit-mocked).

**Edge cases checked**: index out-of-range / no active reader (no-op, tested);
empty/negative/non-int `highlight` param (parse errors, tested); the chunked
bridge has the navigate-repaint but NO bloom trigger (the e2e showed count=0 for
chaptered war-and-peace) — see the filed gap.

**Tests** (re-run green on this branch): `DebugCommandTests` (229),
`DebugSnapshotTests` (21), `DebugReaderProbeAdapterTests` (11),
`HighlightableTextViewTests` (19), `DebugBridgeTests` (31), `DebugFixtureCatalogTests`
(after adding `bloom-sample` to the expected-names set). The 3 new `locate`
handler tests in `RealDebugBridgeContextTests` pass; that suite's sole failure
(`test_seed_miniAzw3_importsAzw3FromBundle`) is a pre-existing environment-dependent
test (needs a `Bundle.main` AZW3 fixture), unrelated to this change.

**e2e (the load-bearing verification)** — on the booted iPhone 17 Pro Simulator,
Debug build of this branch:
```
reset → seed bloom-sample → open → highlight?start=300&end=420 → snapshot
  ⇒ landingBloomCount=0, landingBloomPeakIntensity=0
→ locate?highlight=0 → settle → snapshot
  ⇒ landingBloomCount=1, landingBloomPeakIntensity=1.0   (> the 0.4 resting wash)
```
The bloom fired through the real `.readerNavigateToLocator` → `TXTTextViewBridge`
→ `playLandingBloom` CADisplayLink path, and the readback propagated to the
snapshot. This is the CU-free verification of feature #74's bloom mechanism that
the sub-second visual could not provide.

**Risks accepted**: the readback notification carries no `fingerprintKey` (a locate
bloom can only originate on the currently-active reader, which is the registered
probe). Build (Debug + Release) SUCCEEDED. `ship-as-is`.

## Scope finding (filed separately)

The bloom trigger lives ONLY in `TXTTextViewBridge` (non-chunked / paged /
chapter-at-a-time). The chunked `TXTChunkedReaderBridge` (chaptered TXT in SCROLL
layout — the large-CJK-novel case) has the navigate-repaint but NO
`playLandingBloom`, so it does NOT bloom. Filed as a bug; #74 stays open pending
that fix. This harness verifies BOTH paths once the chunked bloom is wired.
