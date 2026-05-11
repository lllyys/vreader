---
branch: fix/issue-529-opds-browser-blank
threadId: 019e1738-808f-72e1-8e88-992f20ce08c8
rounds: 2
final_verdict: ship-as-is
date: 2026-05-11
---

# Codex Gate-4 Audit — Bug #170 / GH #529

OPDS catalog detail view renders blank after NavigationLink tap.
Two-round Codex MCP audit (sandbox: read-only, thread
`019e1738-808f-72e1-8e88-992f20ce08c8`).

## Round 1 findings

| # | File:line | Severity | Issue | Resolution |
|---|---|---|---|---|
| 1 | `vreader/Views/OPDS/OPDSBrowserView.swift:66` (initial fix) | Medium | `.onAppear`'s `guard feed == nil && errorMessage == nil` is not actually idempotent during the in-flight first fetch. A second `.onAppear` before the response lands would start a duplicate page-1 Task. If the user then paginates via `loadMoreRow` (append=true) and the late page-1 response lands AFTER the merge, the non-append branch (lines 251-252) overwrites the merged feed. | **Fixed.** Replaced the `feed/errorMessage` guard with a dedicated `@State private var hasStartedInitialLoad = false` flag, flipped synchronously on the main actor BEFORE the Task launches. The second `.onAppear` immediately returns `true` and bails. Sub-feeds construct new `OPDSBrowserView` instances via `NavigationLink` (line 112), each with its own independent gate. No cross-instance interference. |

No other blocking findings. `.onAppear` (vs `.task`) is "a defensible
workaround for the `.sheet -> NavigationStack -> NavigationLink`
lifecycle bug"; unstructured `Task` does not create a reference cycle;
no Swift 6 strict-concurrency problem from this call site. Mirror-based
regression test was explicitly NOT recommended; the bigger gap (if any)
would be request-dedup / stale-response coverage, addressed by the
fire-once flag.

## Round 2 findings

Zero. Verdict: **ship-as-is**.

Auditor verbatim:

> The `hasStartedInitialLoad` gate closes the race I flagged in round
> 1. In `OPDSBrowserView.swift:81`, the state flip happens
> synchronously on the main actor before the unstructured `Task` is
> created, so a second `onAppear` on the same view instance sees
> `true` and returns. That makes the initial-load path effectively
> single-shot per `OPDSBrowserView` instance, and each sub-feed gets
> its own independent gate because each `NavigationLink` builds a new
> view instance at `OPDSBrowserView.swift:112`.

> The comments are materially accurate now. The fire-once comment
> around line 31 matches the actual race being prevented, and the
> `.onAppear` comment at line 65 correctly describes the UX choice
> that re-entry after an error does not auto-retry.

## Pre-FIXED verify

Per `docs/bugs.md` workflow rule for UI/behavioral bugs: re-ran the
original repro from the issue body in the simulator with the
working-tree binary.

- v1 fix (rough): screenshot `bug-170-postfix-03-spinner-20260511.png`
  shows "Loading catalog..." spinner with "Gutenberg" title;
  `bug-170-postfix-05-final-20260511.png` shows 3 navigation entries
  (Popular / Latest / Random) with "Project Gutenberg" feed title.
  End-to-end SUCCESS.
- v2 fix (post-audit, fire-once flag):
  `bug-170-postfix-v2-01-spinner-20260511.png` confirms spinner still
  renders on tap; `bug-170-postfix-v2-02-loaded-20260511.png` confirms
  feed still loads to the same 3 entries. No regression from the audit
  fix.

The blank-with-back-chevron-only state from the bug body is GONE. The
fix is verified end-to-end against the real Project Gutenberg OPDS
endpoint (`https://www.gutenberg.org/ebooks.opds/`).

## Test gate

- 24/24 existing `OPDSParserTests` pass (no regression in OPDS data
  layer).
- Other suites not specifically run for this small structural fix
  (one SwiftUI file changed; no new logic, no signature changes).
- No new regression-guard unit test added per auditor recommendation —
  SwiftUI `@State` introspection requires patterns not present in this
  codebase, and the structural fix's primary verification IS the
  simulator pre-FIXED step.

## Diff summary

`vreader/Views/OPDS/OPDSBrowserView.swift`:

1. `@State private var isLoading = false` → `= true` (seed spinner-visible
   initial state so the empty-Group branch is unreachable on first frame).
2. Added `@State private var hasStartedInitialLoad = false` for the
   fire-once gate.
3. Removed `.task { ... }` (was firing-and-cancelling in nested
   presentations).
4. Added `.onAppear { guard !hasStartedInitialLoad else { return };
   hasStartedInitialLoad = true; Task { await loadFeed(...) } }`.
5. Inline doc comments at lines ~22, ~31, ~65 cite bug #170 / GH #529 +
   round-1 audit finding [1].

Net diff: ~25 LOC added (most of it explanatory comments), 1 LOC
deleted (the `.task` modifier). Single file. No signature changes,
no new dependencies, no other call sites affected.
