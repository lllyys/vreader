---
branch: fix/issue-1117-debugbridge-open-position-seek
threadId: 019e48ee-4d50-7f02-9be3-7f206f057af6
rounds: 2
final_verdict: ship-as-is
date: 2026-05-21
---

# Codex Audit — fix/issue-1117-debugbridge-open-position-seek

**Bug**: #257 / GH #1117 — DebugBridge `open?position=N` parses but does not move the reader (host-side seek deferred).
**Auditor**: Codex (gpt-5.2-codex) via MCP, read-only sandbox.
**Thread**: `019e48ee-4d50-7f02-9be3-7f206f057af6`
**Rounds**: 2 (max 3).
**Verdict**: **ship-as-is**.

## Round 1 — 1 Medium, 0 Critical/High

**Medium** — EPUB `open?position=` was a silent no-op. The new
`DebugPosition.epubCFI` → `Locator(cfi:)` conversion built a CFI-only locator,
but the live EPUB navigate observer (`EPUBReaderContainerView`) resolves the
spine by `locator.href`, not raw CFI — only Foliate (`FoliateReaderContainerView`)
consumes `cfi` directly. So an EPUB position silently dropped (the exact failure
class this bug was filed against). Recommended: resolve EPUB to an href-carrying
locator OR explicitly reject EPUB `position`; add a regression test.

Per-dimension round 1: Correctness (EPUB gap), Race/ordering PASS,
livePositionString staleness PASS (TXT reposts a `Locator` object via
`TXTReaderViewModel.broadcastPosition`; the retained-but-undispatched unified
renderer `userInfo` form is irrelevant), Concurrency PASS, Edge cases PASS
(position=0 valid + intentional; large offsets clamp in the VM; nil locator only
on already-rejected input), DEBUG gating PASS, Duplicate/dead code PASS.

### Fix applied (commit `bdab6f73`)
Chose the "fail loudly" option (matches the bug's original "fail loudly instead
of opening at the wrong place" contract; full EPUB CFI→href resolution is a
separate, large piece of work out of scope for a DEBUG harness bug):
- Added `DebugBridgeContextError.seekUnsupportedForFormat(format:position:)`.
- Step-2b guard in `open`: `if case .epubCFI = resolvedPosition` → throw BEFORE
  the open notification (no partial side effect, no 10s awaitReader wait).
- Added the case to `DebugBridge.stableErrorMessage(for:)`.
- Tests: EPUB CFI → throws + posts nothing; AZW3 CFI → reaches seek + posts
  navigate with the CFI (AZW3 stays supported via Foliate).

## Round 2 — clean

All 7 dimensions PASS. Round-1 Medium fully resolved. No new
Critical/High/Medium. Confirmed `if case .epubCFI` is the right discriminator
(keys off the resolved semantic position, cleanly excludes `.foliateCFI`, no
raw-format re-parse). The now-effectively-dead `epubCFI.locator()` on the open
path is acceptable to keep (correct pure conversion + symmetric/testable).

## Supported-format matrix (final)
| Format | `open?position=` grammar | Seeks? |
|---|---|---|
| TXT / MD | UTF-16 char offset (`charOffsetUTF16`) | Yes |
| PDF | 1-based page (mapped to 0-based `Locator.page`) | Yes |
| AZW3 (azw/mobi/prc) | CFI (Foliate `navigateToSearchResult(cfi:)`) | Yes |
| EPUB | CFI | No — rejected with `seekUnsupportedForFormat` (handler needs `href`) |
