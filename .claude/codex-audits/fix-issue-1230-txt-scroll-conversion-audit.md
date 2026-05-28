---
branch: fix/issue-1230-txt-scroll-conversion
threadId: 019e6f66-0d1e-7290-8627-b4534bf74e11
rounds: 2
final_verdict: ship-as-is
date: 2026-05-29
---

# Codex audit — Bug #1230 (Simp→Trad conversion in scroll-layout TXT)

Fix: `TXTChunkedReaderBridge` now applies Simp→Trad conversion per-chunk at
render time (new `nonisolated static renderedChunkText(_:conversion:)`), keeping
chunks/offsets in SOURCE (raw) UTF-16 coordinates — the same precedent the paged
path uses (offset map discarded; valid because SimpTrad is 1:1 UTF-16 for BMP
CJK). The cache is invalidated + table reloaded on a Simp↔Trad toggle. The
container passes `chineseConversion` to the bridge and the DEBUG #1218 probe now
surfaces the converted text.

Files: TXTChunkedReaderBridge.swift, TXTReaderContainerView.swift,
TXTChunkedReaderConversionTests.swift (new).

## Round 1 — 1 High + 1 Low

| file:line | severity | issue | resolution |
|---|---|---|---|
| project.pbxproj | High | `TXTChunkedReaderConversionTests.swift` referenced by the test target but untracked in git → a clean checkout would fail. | **Fixed** — the test file is `git add`-ed in the fix commit (file exists on disk; pbxproj ref correct). |
| TXTReaderContainerView.swift (#1218 probe) | Low | The DEBUG probe converted the joined string as one piece, while production converts each chunk independently → possible chunk-boundary divergence + duplicated conversion logic. | **Fixed** — probe now maps `renderedChunkText($0, conversion:)` over `continuousChunks` then joins, matching the rendered cells exactly. |

Core verdict round 1: "Core fix looks correct... `updateUIView` computes `conversionChanged` before assigning the new value, then clears `attrStringCache` and reloads, so a Simp/Trad toggle should re-render visible cells." Offset handling acceptable under the documented SimpTrad 1:1-UTF16-BMP invariant (matches the paged-path precedent; a future non-1:1 transform would break offset math — documented limitation, not a defect for the current transform).

## Round 2

> Probe finding is resolved; no remaining Critical/High/Medium in the code [...]
> cannot mark the High fully resolved until `TXTChunkedReaderConversionTests.swift`
> is actually added to git.

→ Resolved by committing the test file (this commit).

## Summary

2 rounds. **Verdict: ship-as-is.** 5 `TXTChunkedReaderConversionTests` Swift
Testing cases green (simp→trad, trad→simp, .none no-op, UTF-16-length-preserved
offset invariant, empty). Build SUCCEEDED. Conversion now applies in the default
scroll-layout TXT path; positions stay in source coordinates per the paged-path
precedent. Codex ran read-only.
