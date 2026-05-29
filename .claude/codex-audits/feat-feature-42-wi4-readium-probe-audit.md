---
branch: feat/feature-42-wi4-readium-probe
threadId: codex-exec-2026-05-29-wi4
rounds: 1
final_verdict: ship-as-is
date: 2026-05-29
---

# Codex Gate-4 audit — Feature #42 Phase-1 WI-4 (ReadiumDebugProbe)

Foundational DEBUG-only WI: a Readium-navigator registration + JS-eval seam in the DebugBridge
registry, so WI-5's `ReadiumEPUBHost` render is CU-free verifiable. Spike resolved Risk 5 —
Readium 3.9 `EPUBNavigatorViewController` exposes a public `evaluateJavaScript(_:) async -> Result`
(runs JS on the visible spine), so the probe uses a protocol seam (`ReadiumNavigatorEvaluating`,
`evaluateJavaScriptValue -> Data` raw JSON, no Readium import in the registry) + key+token-guarded
`setActiveReadiumNavigator`/`readiumNavigator`. Settle reuses `markReaderSettled`/`awaitReaderSettled`
(WI-5 calls from `navigator(_:locationDidChange:)`). NO host/dispatch/engine wiring.

## Round 1 — zero findings

Codex verdict verbatim: "Findings: none. The key+token guard mirrors EPUB/Foliate, stale writes are
rejected when `expectedReaderToken` is set, lookup requires both key and token, and the slot clears
on active unregister plus reset. The seam stays protocol-based with no Readium import, returns raw
JSON `Data` consistent with `DebugReaderProbe.evaluateJavaScript`, and remains MainActor-confined.
DEBUG gating is clean. **WI-4 AUDIT: PASS (ship-as-is).**"

## Notes

`DebugReaderRegistry.swift` is now ~515 lines (was 461 pre-WI-4, already over the ~300 soft limit;
Swift requires stored slots in the class, so accessor methods live in the sibling
`ReadiumDebugProbe.swift` per the existing `+Settle.swift`/`+WebViewWait.swift` split). A
registry-file split is pre-existing tech-debt, out of this WI's scope. 13 `ReadiumDebugProbeTests` +
37 registry/settle regression pass; full build SUCCEEDED; Release gate `verify-release-no-debugbridge.sh`
PASS (zero DebugBridge surface — all DEBUG-gated).
