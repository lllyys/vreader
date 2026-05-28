---
branch: fix/issue-1218-txt-content-read-probe
threadId: 019e6f45-f3c7-7883-a846-8a1e0fc18cde
rounds: 3
final_verdict: ship-as-is
date: 2026-05-29
---

# Codex audit — Bug #1218 (CU-free TXT-content read probe)

Adds a DEBUG-only `vreader-debug://txt-content?dest=<basename>` command that writes
the active TXT reader's rendered text to `Caches/DebugBridge/<dest>` (mirrors
`snapshot(dest:)`), plus a notification-driven `renderedText` on the probe
(mirrors bug #257 `livePositionString`). Unblocks the CU-free *read* half of
Feature #28's conversion verification. Implemented by an implementer subagent,
then corrected across 3 audit rounds.

Files: DebugCommand.swift, DebugBridge.swift, DebugReaderRegistry.swift,
DebugReaderProbeAdapter.swift, RealDebugBridgeContext+TXTContent.swift (new),
DebugBridgeNotifications.swift, ReaderContainerView.swift,
ReaderContainerView+DebugBridgeRenderedText.swift (new),
TXTReaderContainerView.swift, docs/subsystems/debug-bridge.md, + 3 test files.

## Round 1 — 2 High + 1 Medium

| file:line | severity | issue | resolution |
|---|---|---|---|
| TXTReaderContainerView.swift:402 | High | The probe was wired only into the paged chapter path; the continuous/chunked (scroll-layout) path — the surface #1218 actually targets — never posted (the `.task` early-returns for continuous mode). | **Fixed** — continuous-mode branch now posts `continuousChunks.joined()` before returning (round 1); legacy large-file chunked + legacy small paths also wired (round 3). |
| TXTReaderViewModel.swift:489 | High | Continuous chaptered TXT renders RAW text — Simp→Trad conversion is not applied in scroll mode (chunks built from raw `fullText`; conversion `.task` early-returns; `attributedString(forChunk:)` doesn't convert). | **Accepted as separate scope** — filed as a distinct product bug **GH #1230 / bugs.md #275** (the true Feature #28 conversion blocker). #1218 = the read capability (surfaces rendered text faithfully, raw or converted); #1230 = the conversion. Both needed for Feature #28. Codex confirmed the split is acceptable (round 2). |
| RealDebugBridgeContext+TXTContent.swift | Medium | Handler trusted any probe's `currentRenderedText` without gating on TXT format. | **Fixed** — `isTXT = probe.format.lowercased() == "txt"`; non-TXT → text:null, available:false. New test `test_txtContent_nonTXTFormatProbe_forcesUnavailable`. |

## Round 2

Finding 3 confirmed closed; the #1230 scope split confirmed acceptable. Finding 1
still only closed for continuous chaptered — legacy large-file chunked + legacy
small full-text paths still didn't post.

## Round 3

Wired the remaining two paths (legacy large-file chunked posts the converted
`splitResult.0.joined()`; legacy small-file closure restructured to return
`(wrapped, text)` and posts the converted `built.text`). Codex verdict verbatim:

> Clean: Finding 1 is fully closed across all four TXT render paths, Finding 3
> remains closed, and I see no remaining Critical/High/Medium issues.

## Summary

3 rounds. All four TXT render paths (paged, continuous chaptered, legacy large
chunked, legacy small) now surface their rendered text via the probe. The
continuous chaptered path posts RAW pending #1230; the other three convert.
**Verdict: ship-as-is.** Focused tests green (DebugCommandTests parser cases,
DebugBridgeTests routing, RealDebugBridgeContextTests handler incl. the non-TXT
gate). Build SUCCEEDED. All new symbols `#if DEBUG`-gated. Codex ran read-only.
