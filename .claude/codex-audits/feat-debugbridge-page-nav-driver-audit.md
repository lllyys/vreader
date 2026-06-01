---
branch: feat/debugbridge-page-nav-driver
threadId: codex-exec-gpt-5.5-20260601
rounds: 1
final_verdict: ship-as-is
date: 2026-06-01
---

# Codex Audit — DebugBridge `page` command (feature #42/#75 nav driver)

## Scope

DEBUG-only `vreader-debug://page?dir=<next|prev>` command that posts the shared
`.readerNextPage` / `.readerPreviousPage` notification (existing release
notifications in `ReaderNotifications.swift`) — the bus every native reader host
observes (Readium → `goForward`/`goBackward`; legacy EPUB/Foliate paged → their
page nav). Built because XCUITest / synthetic idb swipes cannot reliably drive
Readium's own gesture recognizers, so a bus-level page-turn driver is the
reliable CU-free path to verify reading-order navigation.

Files:
- `vreader/Services/DebugBridge/DebugCommand.swift` (case + local `PageDirection` enum + parse)
- `vreader/Services/DebugBridge/DebugBridge.swift` (protocol method + dispatch)
- `vreader/Services/DebugBridge/RealDebugBridgeContext+Page.swift` (handler posts the notification)
- `vreaderTests/.../DebugCommandTests.swift` (5 parse tests)
- `vreaderTests/.../RealDebugBridgeContextTests.swift` (2 handler tests)
- `vreaderTests/.../DebugBridgeTests.swift` (both mock conformers)

## Round 1 — findings

Codex (gpt-5.5, read-only): **Clean — no findings.** Parser validation,
notification mapping (next→`.readerNextPage`, prev→`.readerPreviousPage`), DEBUG
gating, MainActor usage, and reuse of the existing reader nav bus all correct.

## Test evidence

- `vreaderTests/DebugCommandTests` + `RealDebugBridgeContextTests` +
  `DebugBridgeTests` — 349 tests, 0 failures.
- New: 5 parse cases (next/prev/missing/invalid/deep-path) + 2 handler cases
  (next→`.readerNextPage`, prev→`.readerPreviousPage`).

## Field note (the command worked — it diagnosed a #75 finding)

Driving `page?dir=next` on the vertical-rl fixture (via the command) confirmed the
command reaches Readium's `goToNextPage`/`goForward` end-to-end. In the default
**scroll** layout, `goForward` returns false for a single-spine-item book — that
is expected Readium scroll-mode behavior (scroll-mode advances by scrolling within
a resource; `goForward` moves between spine items, of which the single-chapter
fixture has none after the first). Verifying paged-mode vertical-rl page nav needs
Readium in paged mode, which `set-layout` does not currently reach (it wires only
the legacy host) — a follow-up harness gap. Documented in `docs/features.md` #75.

## Summary verdict

ship-as-is.
