---
branch: fix/bug-277-readium-settle-slot
threadId: n/a (codex exec stdin; threadId not surfaced on the non-MCP path)
rounds: 1
final_verdict: ship-as-is
date: 2026-05-29
---

# Gate-4 Codex Audit — Bug #277 (GH #1241)

DebugBridge `settle` Stage-2 gate now recognizes the Readium navigator slot.

## Scope audited

Diff on branch `fix/bug-277-readium-settle-slot` vs `main` (53872b92, v3.40.31):

- `vreader/Services/DebugBridge/DebugReaderRegistry+WebViewWait.swift` — the
  `.epub` branch of `hasActiveWebView(for:format:)` now returns true when EITHER
  the legacy EPUB WebView slot OR the Readium navigator slot matches the key,
  under the same `expectedReaderToken` guard. Two private satisfier helpers
  extracted: `hasActiveEPUBWebView` (WebKit-gated) + `hasActiveReadiumNavigator`.
- `vreaderTests/Services/DebugBridge/ReadiumDebugProbeTests.swift` — RED→GREEN
  tests (Readium-only slot satisfies the gate; wrong-key / stale-token / legacy
  EPUB-slot guards; all via `makeIsolatedForTests()`).
- `docs/bugs.md` — row #277 OPEN → FIXED (tracker only).

## Audit invocation

```
codex exec --sandbox read-only - < .claude/codex-audits/bug-277-audit-prompt.md
```

Read-only sandbox. Author/auditor separation preserved (Codex is a separate
process from the implementing Claude Code session).

## Verdict — round 1

**No Critical/High/Medium/Low findings. ship-as-is.**

Audit notes (verbatim from Codex):

- `.epub` now accepts legacy EPUB WKWebView OR Readium navigator with correct
  short-circuit OR logic.
- Foliate path is unchanged.
- Readium satisfier keeps key match, live weak ref, and
  `slot token == expectedReaderToken`, so stale same-key reopen bindings do not
  satisfy the gate.
- DEBUG gating is intact; `hasActiveReadiumNavigator` is only called from the
  WebKit-enabled branch, and Release remains protected by file-scope `#if DEBUG`.
- No new MainActor/Sendable concern found.
- New Bug #277 tests use isolated registries for the new behavioral assertions
  and would fail pre-fix for the Readium-only slot case.

Codex did not run `xcodebuild` (read-only sandbox). Tests were run separately by
the implementing session: `ReadiumDebugProbeTests` 18/18 pass post-fix (the two
new behavioral tests failed pre-fix, confirming RED); full serial `vreaderTests`
bundle green.

## Resolution

Zero findings → no fix rounds required. Ship as-is.
