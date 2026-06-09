---
branch: feat/feature-77-bilingual-verify-harness
threadId: 019eaa84-ec7c-7570-a289-7901578bca7e
rounds: 1
final_verdict: ship-as-is
date: 2026-06-09
---

# Codex Audit — Feature #77 Gate-5b bilingual-verify harness

DEBUG-only DebugBridge command (`bilingual?action=enable|disable|status`) +
`--mock-ai-translate-delay-ms` knob that drives interlinear bilingual mode CU-free
across the Readium (default EPUB), Foliate (AZW3/MOBI), and legacy EPUB
(paged + continuous) hosts, so the inline loading shimmer (Feature #77 WI-1..5)
is verifiable without the setup-sheet + AI-provider gates an automated run can't
satisfy.

Scope audited (16 files): DebugCommand / DebugBridge / DebugBridgeNotifications /
RealDebugBridgeContext, ReaderDebugBridgeBilingualObserver, DebugBridgeBilingualStatus,
EPUBReaderContainerView(+Bilingual), ReadiumEPUBHost+Bilingual,
FoliateBilingualContainerView, MockAIProvider, AITestSetup, VReaderApp + tests.

## Round 1 findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| AITestSetup.swift:51 | Medium | `UInt64(max(0, ms)) * 1_000_000` traps on overflow for a huge positive `--mock-ai-translate-delay-ms`. | **Fixed** — extracted `nanosForDelayMS(_:)` that floors negatives at 0 and caps at a 60s ceiling before the multiply (no harness needs longer). Test: `AITestSetupTests.nanosForDelayMS_clampsAndConverts`. |
| DebugCommand.swift:622 | Medium | `granularity` wasn't validated at the parser boundary; a typo failed open to the persisted default via the host's optional `TranslationGranularity(rawValue:)`. | **Fixed** — parse now throws `invalidParam("granularity")` on anything but `paragraph`/`sentence`. Tests: `…InvalidGranularity_throwsInvalidParam`, `…ParagraphGranularity_accepted`. |
| DebugCommand.swift:629 | Low | `status` `dest` skipped the basename validation `snapshot`/`txt-content` use; written via `appendingPathComponent`. | **Fixed** — `validateBasename(dest, paramName: "dest")` in the `status` branch. Test: `…PathTraversalDest_throwsInvalidParam`. |
| EPUBReaderContainerView+Bilingual.swift:406 | Low | The three per-host DEBUG handlers are near-copy-paste (set lang/granularity → dismiss sheet → enable → enumerate → status), a drift risk. | **Accepted with rationale** — the shared preamble is ~5 lines; the load-bearing part (the enumerate/clear seam) genuinely differs per host (Readium `runBilingualEnumerateForCurrentChapter`, Foliate scoped `enumerateJS(sectionIndex:)`, legacy paged/continuous branch). Extracting a protocol across three distinct SwiftUI view structs (different stored properties) adds more indirection than the 5 saved lines justify in DEBUG-only verification tooling. The per-host divergence is exactly where a shared helper would NOT help. |

Codex explicitly confirmed (no finding): no host-specific enumerate mismatch in
`handleDebugBilingualEnable` (legacy mirrors `confirmBilingualSetup`'s
paged/continuous branch; Readium funnels through
`runBilingualEnumerateForCurrentChapter`; Foliate mirrors the scoped
`enumerateJS(sectionIndex: currentSectionIndex)` confirm path); no `#if DEBUG`
leak into Release; no `userInfo` key mismatch on the `.debugBridgeBilingualCommand`
notification path.

## Verdict

ship-as-is — both Mediums + the path-safety Low fixed and covered by tests; the
dedup Low accepted with rationale. Build SUCCEEDED; DebugCommandBilingualTests,
MockAIProviderTests, AITestSetupTests, DebugBridgeTests all green.
