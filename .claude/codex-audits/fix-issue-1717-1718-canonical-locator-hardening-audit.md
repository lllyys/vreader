---
branch: fix/issue-1717-1718-canonical-locator-hardening
threadId: 019ed4xx-355356
rounds: 2
final_verdict: ship-as-is
date: 2026-06-17
---

# Codex Gate-4 audit — bugs #355 (lane hardening) + #356 (narrowed → #109)

Runner: `scripts/run-codex.sh -m gpt-5.4 -e high`. Two rounds.

## Round 1 — 2 High + 2 Medium
- High: Swift non-finite still omits + `?? Locator(...)` bypass paths persist invalid
  locators (collision #356 targets, on Swift). | High: NFC changes the persisted
  canonicalHash (18 profileKey/locatorHash sites) with no migration → dedupe/toggle
  drift. → **User chose to track the migration-sensitive iOS change rather than rush
  a re-key of persisted data.** REVERTED the iOS Locator.swift NFC change; filed
  feature #109 (iOS NFC + recompute migration + non-finite persistence guarding);
  #356 → IN PROGRESS (narrowed). Kotlin reference keeps NFC + reject (no migration).
- Medium: the "NFD" vector was NFC bytes → removed from the shared set, replaced by a
  Kotlin-only NFC unit test with explicit ́/á escapes. | Medium: cross-diff
  could false-pass on stale .out → run.sh `rm -rf .out` first; Swift emit `try`
  (fail-loud).

## Round 2 — 1 Medium (cache-key half)
Verbatim: Swift "is genuinely reverted … No residual NFC behavior change"; deferring to
#109 "is sound", #356 "correctly still open as IN PROGRESS"; both round-1 Mediums "are
genuinely fixed"; removing the shared NFD vector is "an intentional and explicitly
documented temporary blind spot, not a new bug"; the Kotlin reference change "is
correct". One Medium: #355's cache-key half wasn't done (still happy-path). FIXED: added
cache-key edge vectors (empty/CJK/delimiter), cross-diffed cache-key too, and forced the
Kotlin test to re-run (`cleanTest`) so it always emits.

## Verdict
ship-as-is. #355 (lane over-claims) FIXED: locator + cache-key edge vectors, direct
Swift-vs-Kotlin byte cross-diff (both byte-identical), stale-file/cache holes closed.
#356 narrowed — Kotlin reference + contract NFC/reject; iOS production NFC + migration +
non-finite persistence guarding tracked as feature #109 (user-approved deferral of a
migration-sensitive re-key). Verified: run.sh both → CONFORMANCE RESULT: PASS.
