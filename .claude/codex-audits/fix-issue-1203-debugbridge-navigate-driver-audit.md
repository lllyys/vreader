---
branch: fix/issue-1203-debugbridge-navigate-driver
threadId: 019e68ad-39af-7ac1-9b59-c04145be53f9
rounds: 1
final_verdict: ship-as-is
date: 2026-05-27
---

# Codex Audit — Bug #273 (DebugBridge `navigate` driver + multi-chapter EPUB fixture)

Gate-4 implementation audit for the verification-harness fix that unblocks
feature #71 WI-8 continuous-mode navigation device verification.

New surface (all DEBUG-only):

- `DebugCommand.navigate(spineIndex:fraction:)` + parser for
  `vreader-debug://navigate?spine=<N>[&fraction=<0...1>]`.
- `DebugBridgeContext.navigate(spineIndex:fraction:)` protocol method + dispatch.
- `RealDebugBridgeContext+Navigate.swift` — posts `.debugBridgeNavigateCommand`.
- `.debugBridgeNavigateCommand` notification.
- `EPUBReaderContainerView` DEBUG-only observer: resolves spine → href against
  `viewModel.metadata`, builds a `Locator` with the open book's fingerprint,
  re-posts `.readerNavigateToLocator` (the SAME WI-8 path a TOC/bookmark/search
  tap hits).
- `DebugFixtureCatalog`: `multi-chapter-epub` (4 viewport-tall chapters).

Files audited: `DebugCommand.swift`, `DebugBridge.swift`,
`RealDebugBridgeContext+Navigate.swift`, `DebugBridgeNotifications.swift`,
`EPUBReaderContainerView.swift`, `DebugFixtureCatalog.swift`, + the 4 test files.

## Round 1 — findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| docs/architecture.md:173 | Low | DebugBridge command row omitted the new `navigate` command. | Fixed — added `navigate` to the slash-list + a bug #273 sentence describing the spine→href→Locator→`.readerNavigateToLocator` path + the `multi-chapter-epub` fixture pairing. |
| docs/architecture.md:240 | Low | Notification bus table doesn't list `.debugBridgeNavigateCommand`. | Accepted with rationale — the architecture.md bus table lists NO DEBUG-only DebugBridge notification (`.debugBridgeSeekFraction`, `.debugBridgeScrollSheet`, `.debugBridgeSearchCommand` are all absent); those are documented in `docs/subsystems/debug-bridge.md`, which this PR updates with the full `navigate` grammar row. Adding only this one would be inconsistent. Codex accepted: "I accept the rationale … The updated DebugBridge service row is enough for architecture-level visibility." |

Code path: Codex confirmed clean — "The parser validates the intended cases,
the observer range-checks spine and no-ops on missing metadata or malformed
fingerprint, nil fraction is handled correctly, and reposting
`.readerNavigateToLocator` does not create a loop because it targets a different
notification. The `#if DEBUG` placement in the SwiftUI modifier chain is sound,
and the new context extension is file-scope DEBUG-gated."

## Verdict

**ship-as-is.** Zero open Critical/High/Medium; the one actioned Low is fixed,
the other accepted with rationale Codex endorsed. Round-1 verification reply:
"No remaining findings from the audit … this is clean to ship."

## Device verification (this fix + feature #71 WI-8)

Built + ran on iPhone 17 Pro Sim (UDID 61149F0E…) with `multi-chapter-epub`,
continuous mode (`-com.vreader.featureFlags.epubContinuousScroll YES
-readerEPUBLayout scroll`):

- **In-window** `navigate?spine=1&fraction=0`: scrollTop 0 → 10047, section 1
  exactly at viewport top, DOM unchanged `[0,1]` (scroll, no rebuild).
- **Out-of-window** `navigate?spine=3&fraction=0`: DOM rebuilt `[0,1]` → `[2,3]`
  (correct far-side eviction + target-window materialization); "Chapter Four"
  is the first visible text at the viewport top (`elementFromPoint(50,100)`).
  scrollTop 9970 vs section-3 offsetTop 10047 — a 77px gap that is exactly the
  Bug-#163 safe-area top inset (same inset section 0 gets at open), so the
  content lands correctly below the dynamic island.

Minor note (not a defect; terminal-WI polish): in-window lands at exact
`offsetTop`, out-of-window at `offsetTop − inset` — a 77px landing-consistency
nit between the two branches. Documented in the feature #71 row.

Evidence: `dev-docs/verification/bug-273-20260527.md`.
