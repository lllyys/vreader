---
branch: fix/issue-602-azw3-mobi-tts-readaloud-gate
threadId: 019e33eb-4be7-7850-9a9a-18bb87d13e84
rounds: 2
final_verdict: ship-as-is
date: 2026-05-17
---

## Gate 4 — Codex implementation audit, Bug #176 / GH #602 (REOPENED)

Feature #60 WI-6c's `ReaderMorePopover` rendered every
`ReaderMoreMenuRow.allCases` row unconditionally — including
`Read aloud` — bypassing the `FormatCapabilities.tts` gate. On
AZW3/MOBI (which route through Foliate-js and exclude `.tts`) the row
reappeared and tapping it was a silent no-op, re-opening Bug #176.

Fix: `ReaderMoreMenuRow.visibleRows(for: FormatCapabilities?)` filters
`.readAloud` when the format lacks `.tts`; `ReaderMorePopover` gains a
`formatCapabilities` parameter and renders `resolvedRows`;
`ReaderContainerView+Sheets.swift` passes
`BookFormat(rawValue: book.format.lowercased())?.capabilities`.

Codex MCP, read-only sandbox. Thread `019e33eb-4be7-7850-9a9a-18bb87d13e84`.

> Provenance: the initial fix was drafted by a worktree subagent whose
> isolation leaked into the main tree; the subagent was stopped before
> its audit. The orchestrator recovered the WIP from `git stash`,
> verified it, and ran this audit. The audit therefore covers the
> recovered code end-to-end as if freshly authored.

## Round 1

- **Medium** — `ReaderMorePopoverTTSGateTests` (8 tests) only exercised
  `ReaderMoreMenuRow.visibleRows(for:)` (pure logic). Nothing verified
  that `ReaderMorePopover` actually *calls* `visibleRows(for:)` — a
  revert of the popover to `ForEach(allCases)` would keep every test
  green.

Confirmed correct in round 1: the gate solves the reopened root cause;
`.azw3` excludes `.tts` in `FormatCapabilities`; exactly one
production `ReaderMorePopover(` constructor exists (no missed previews
/ tests); `ReaderMorePopoverStateTests` compiled clean because it
never builds the view; the divider anchor (`dividerAfter` =
`.autoTurnPages`) is never gated; declared order preserved;
`ForEach(rows, id: \.self)` safe; `book.format.lowercased()` always a
valid `BookFormat` rawValue for real data, and the `nil → all rows`
fallback is intentional backward-compat; no concurrency issue; rule 51
respected (an existing row is hidden, no new UI); files within size
limit.

## Round 1 → fix applied

- **Medium (fixed)** — extracted `ReaderMorePopover.resolvedRows`
  (internal computed property = `visibleRows(for: formatCapabilities)`);
  `popoverCard` renders `ForEach(resolvedRows, …)`. Added 3 `@MainActor`
  wiring tests that construct a real `ReaderMorePopover` and assert
  `resolvedRows`: AZW3 drops `.readAloud`, EPUB keeps it, `nil` → all
  rows. A popover-level revert now fails the suite.

## Round 2

Verdict: **clean — no new findings; round-1 Medium resolved.**

- **Low (accepted)** — Codex noted the production call site
  (`ReaderContainerView+Sheets.swift` passing `…?.capabilities`) is not
  fully build-enforced (a future regression passing `nil` would still
  compile and the popover-level tests would stay green). Codex
  explicitly classified this as *residual integration risk, not a new
  finding or merge blocker*: one constructor site, a simple
  code-reviewable line, correct today, and the previously missing
  popover-level wiring is now tested. Accepted as-is; full end-to-end
  integration coverage is left as optional future hardening.

## Resolution summary

Round 1 Medium fixed; round 2 clean. The single round-2 Low is
accepted with rationale (Codex's own assessment: not a blocker).
Targeted suite: 11/11 pass. Zero open Critical/High/Medium findings.

**Verdict: ship-as-is.**
