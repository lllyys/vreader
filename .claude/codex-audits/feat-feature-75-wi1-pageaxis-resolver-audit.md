---
branch: feat/feature-75-wi1-pageaxis-resolver
threadId: codex-exec-readonly
rounds: 1
final_verdict: ship-as-is
date: 2026-05-31
---

# Codex audit — Feature #75 WI-1 (PageAxisResolver pure seam)

Read-only `codex exec` audit. Foundational WI (no user-observable behavior →
unit tests + audit sufficient, no device verification per Gate 5).

## Summary

New `PageAxis` enum {horizontalLTR, horizontalRTL, verticalRL} + the pure
`PageAxisResolver.resolve(writingMode:direction:dir:lang:readingDirectionHint:)`
seam. Precedence: vertical-rl wins → computed direction authoritative → dir attr
→ book-level hint → `.auto` via lang primary subtag → default LTR. Per-document
(the Gate-2 keystone), not book-level.

## Files

- `vreader/Views/Reader/PageAxisResolver.swift` (new)
- `vreaderTests/Views/Reader/PageAxisResolverTests.swift` (new)

## Round 1 findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| PageAxisResolver.swift:53 | Medium | inputs lowercased but not trimmed — `" rtl "` etc. failed normalization, letting a lower-precedence value win. | Fixed — `normalize()` trims + lowercases all string inputs; whitespace tests added. |
| PageAxisResolver.swift:94 | Low | RTL language set missed `iw`/`prs`/`ckb`/`syr`. | Fixed — extended set (and excluded bare `ku` as script-ambiguous); parameterized RTL-tag test. |
| PageAxisResolverTests.swift:95 | Low | missing whitespace + precedence-boundary cases. | Fixed — added whitespace, `dir>hint`, `ltr-hint>rtl-lang`, ambiguous-`ku` tests. |

Codex confirmed no Swift 6 Sendable/concurrency issue (PageAxis Sendable,
stateless static pure logic).

## Verdict

ship-as-is. Tests: `PageAxisResolverTests` 21/21 green (precedence matrix +
normalization + extended RTL set). Foundational — consumed by WI-2's
`EPUBPaginationHelper(axis:)` and WI-3's load-time probe.
