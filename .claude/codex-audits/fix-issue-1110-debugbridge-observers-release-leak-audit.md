---
branch: fix/issue-1110-debugbridge-observers-release-leak
threadId: 019e6173-5bf7-7ec1-aab8-927dc788b64e
rounds: 1
final_verdict: ship-as-is
date: 2026-05-26
---

# Codex audit — Bug #254 / GH #1110 (LibraryDebugBridgeObservers Release leak)

Independent audit (Codex MCP, separate process) of the fix that stops
`LibraryDebugBridgeObservers` from leaking into the Release binary (which
failed `scripts/verify-release-no-debugbridge.sh`).

File audited: `vreader/Views/Library/LibraryViewObservers.swift` (only; +14/-7).

## Fix shape

Root cause: the `private struct LibraryDebugBridgeObservers: ViewModifier` AND
its `.modifier(...)` call site were both unconditional — only `body()` had
`#if DEBUG ... #else content #endif`. In Release the struct was an inert
passthrough but its symbol survived (matching the gate's Debug-pattern).

Fix: (1) wrap the whole struct in a file-scope `#if DEBUG ... #endif` (dropping
the now-redundant inner `#else content`); (2) gate the trailing call site with
an inline `#if DEBUG ... .modifier(LibraryDebugBridgeObservers(...)) ... #endif`.

## Round 1 — 1 Low (withdrawn)

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 1 | Low | The inline `#if DEBUG` in `body` isn't "file scope" / a dedicated extension file per rule 50 §11's preferred patterns; suggested a config-neutral `debugBridgeObserverModifier` property returning the struct (DEBUG) or `EmptyModifier()` (Release). | **Contested + WITHDRAWN by Codex.** Rule 50 §11's closing clause explicitly permits a single-line `#if DEBUG` "when a single line genuinely needs it" — this call site qualifies. The suggested alternative would add a Release-visible `EmptyModifier()` path + a new always-present `debugBridgeObserverModifier` symbol containing "debugBridge" — needless gate-risk + surface. The current fix leaves zero Debug* symbols in Release (verified). Codex agreed and withdrew the finding. |

## Codex confirmations (no change needed)

- **Correctness**: the symbol is removed from Release; DEBUG behavior is
  unchanged — the two observers (`.debugBridgeOpenBook` / `.debugBridgeLibraryChanged`)
  still attach in DEBUG exactly as before.
- **Postfix `#if` in the SwiftUI chain**: technically sound — conditional
  compilation runs before type-checking, so each config sees one concrete
  chain; differing `some View` underlying types across configs is fine.
- **Rule 50 §11**: struct file-scope gating is sufficient for symbol removal;
  no remaining DEBUG-only leak in this file; no sibling instance of the pattern.
- No dead code / naming / Swift 6 issues.

## Verification (pre-FIXED, Phase 6a)

- DEBUG build: **SUCCEEDED** (inline trailing `#if` compiles).
- Release build: **SUCCEEDED**; `scripts/verify-release-no-debugbridge.sh`
  → **"PASS: zero DebugBridge surface in Release build"**; `nm`/`strings` on the
  Release binary → **0** occurrences of `LibraryDebugBridgeObservers`. The gate
  that flagged the bug now passes.

## Verdict

**Ship-as-is.** No open findings (the sole Low was withdrawn). The fix is a
compile-gating change with no runtime-behavior delta; the release-hygiene gate
is the regression check (a unit test is not applicable per rule 10's
config/no-runtime-effect exception).
