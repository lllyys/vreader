---
branch: fix/issue-338-decodewithhint-fallsback-test-broken
threadId: 019dffa9-036b-7640-8ddc-90a3c33a2fc5
rounds: 2
final_verdict: ship-as-is
date: 2026-05-07
---

# Codex audit log — bug #148 (GH #338)

## Round 1

**Findings:**

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| `vreaderTests/Services/TXT/TXTServiceTests.swift:298` | Low | Test name + leading comment said "hint encoding fails to decode", but the new setup never reaches the decode attempt on the hint path. It exercises the fallback by making `encodingFromName` return nil — a different sub-case. | **Fixed** — renamed to `decodeWithHint_fallsBack_whenHintEncodingIsUnknown`; comment rewritten to explain Foundation decoder leniency makes the decoder-rejects-bytes sub-case unreliable in unit tests, so the unknown-name sub-case is the cleaner path. |
| `vreaderTests/Services/TXT/TXTServiceTests.swift:314` | Low | Hard-coded `"ZZZ-NotReal"` sentinel only safe as long as `encodingFromName` never adds that alias; future drift could silently degrade. | **Fixed** — added `#expect(TXTService.encodingFromName(hintName) == nil, ...)` guard before calling `decodeWithHint`. If a future alias is added under this name, the assertion fails loudly. |

## Round 2

**Findings:** None.

## Verdict

**ship-as-is** — Round 1 found two Low naming/robustness improvements; both addressed. Round 2 confirms clean.

## Manual context

The fix itself is structurally trivial (one test method's body
rewrite, no production code change). What's interesting is the
Foundation-decoder-leniency observation that necessitated the
rename: Swift's `String(data:, encoding: .utf16)` accepts any
even-byte payload (and silently drops a trailing odd byte),
producing UTF-16 code units regardless of content. There's no
reliable way to make it return nil from a unit test, so any test
that wants to exercise the fallback branch must trigger it via the
`encodingFromName` lookup, not the decode call.
