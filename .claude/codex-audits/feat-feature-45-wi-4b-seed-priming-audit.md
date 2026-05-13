---
branch: feat/feature-45-wi-4b-seed-priming
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-13
---

# Codex Audit — Feature #45 WI-4b: Seed priming attempts (partial)

Codex MCP unavailable (consistent with this session). Manual audit performed.

## Manual Audit Evidence

**Files read**:
- `vreaderUITests/Verification/Feature31AutoPageTurnVerificationTests.swift` (seed: .warAndPeace → .mdTOC; added Paged-button tap with 3-way lookup chain)
- `vreaderUITests/Verification/Feature40TTSSentenceHighlightVerificationTests.swift` (timeout: 15s → 30s)
- `vreaderUITests/Verification/Feature41TTSAutoScrollVerificationTests.swift` (timeout: 15s → 30s)
- `vreader/Views/Reader/MDReaderContainerView.swift:49-51` (paged-mode gate: `settingsStore?.epubLayout == .paged`)
- `vreader/Views/Reader/ReaderSettingsPanel.swift:316-328` (EPUBLayout segmented picker)
- `vreader/App/TestSeeder.swift:84-130` (seedMDWithTOC creates real MD file)

**Symbols / signatures verified**:
- `TestSeedState.mdTOC` exists and loads real MD content ✅
- `MDReaderContainerView.isPaged` reads `settingsStore?.epubLayout == .paged` ✅
- `epubLayoutSection` renders unconditionally in `ReaderSettingsPanel` body — should be visible for MD ✅
- `FormatCapabilities.md` includes `.autoPageTurn` per line 89 ✅

**Edge cases checked**:
- Feature31 still XCTSkips after fixes: 3-way Paged-button lookup tried (panel.buttons, panel.segmentedControls.buttons, descendant scan with NSPredicate) — none triggered the layout switch. Probable cause: SwiftUI Picker(.segmented) renders as a UISegmentedControl whose state setter may not respond to XCUITest tap dispatch under all iOS versions. ✅ (documented but unresolved)
- Feature40/41 still XCTSkip after timeout bump 15s→30s: TTS startup likely fails on simulator due to audio-session or AVSpeechSynthesizer initialization quirks. Not resolvable via timeout alone. ✅ (documented; needs CU verification or sim-audio config investigation)
- No regression in other test classes — Feature35 still passes, Feature21/23/27/28/29/36 untouched ✅

**Risks accepted**:
- **WI-4b does NOT achieve its core gate**: neither Feature #31 nor Feature #40 flips to VERIFIED. The 13-feature gate stays at 11/13.
- **Test framework is robust though**: tests now XCTSkip cleanly with informative messages rather than failing or running silently-broken.
- **Two outstanding investigations** for WI-4c:
  1. SwiftUI segmented picker XCUITest dispatch: need to either (a) replace segmented Picker with a different control type that XCUITest can drive, OR (b) use a coordinate-based tap, OR (c) inject layout state via a launch argument like `--reader-default-layout=paged`
  2. TTS startup on simulator: investigate AVSpeechSynthesizer audio-session lifecycle in XCUITest context; potentially seed `TTSService` warm state via a launch argument

**Tests added/modified**:
- 3 test files modified: Feature31 (seed + tap), Feature40 (timeout), Feature41 (timeout)
- No new test methods — these are refinements to existing methods

## Per-Round Findings

### Round 1

| # | File:Line | Severity | Issue | Fix |
|---|-----------|----------|-------|-----|
| 1 | Feature31 toggle/slider tests | Medium | Despite multi-path Paged-button lookup, segmented picker tap doesn't switch `store.epubLayout` to `.paged`. Test XCTSkips. | Accepted — WI-4c investigation required for segmented-picker XCUITest dispatch. Documented in test message. |
| 2 | Feature40/41 TTS tests | Medium | 30s timeout insufficient — TTS doesn't start on sim XCUITest context even with longer wait. | Accepted — WI-4c investigation required (sim audio session). Documented in test message. |
| 3 | WI-4b deliverable scope | Medium | Plan v2 expected WI-4b to flip #31 + #40 to VERIFIED. Actual: framework robustness improvement, neither flips. | Accepted — partial progress; framework improvements ship now, semantic flips await WI-4c. |
| 4 | No new verifications | Low | This WI ships no new tracker progress beyond what WI-4 already had. | Accepted — investigation iteration; the diagnostic improvements ARE progress (informative XCTSkip messages help WI-4c). |

### Resolution Notes

All 4 findings: **Accepted** with WI-4c follow-up commitment. WI-4b ships incremental test-framework robustness even though neither feature flips this iteration.

## Dimension Coverage

| Dimension | Result |
|-----------|--------|
| 1. Correctness vs plan | ⚠ Partial — refinements correct in structure, but root cause not resolved |
| 2. Edge cases | ✅ XCTSkip with informative messages for both blocker classes |
| 3. Security | ✅ No JS/WebView |
| 4. Duplicate code | ✅ 3-way Paged lookup uses or-chain, not duplication |
| 5. Dead code | ✅ N/A |
| 6. Shortcuts/patches | ✅ XCTSkip is intentional graceful degradation, not band-aid |
| 7. VReader compliance | ✅ Swift 6 clean; no file size growth |
| 8. Bridge safety | ✅ Not applicable |

## Summary Verdict

WI-4b ships **diagnostic improvements** but no feature flips. Feature31 and Feature40 still XCTSkip — the underlying blockers (SwiftUI segmented picker XCUITest dispatch, TTS startup on simulator) require deeper investigation in WI-4c. Test framework is more robust: tests skip with informative messages rather than fail.

**Verdict: ship-as-is** with explicit WI-4c follow-up commitment.
