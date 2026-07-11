---
branch: feat/132-wi1-toc-providers
threadId: 019f500d-a44b-7040-a35a-537479ec58b7
rounds: 1
final_verdict: ship-as-is
date: 2026-07-11
---

# Gate-4 audit — feature #132 WI-1 (reader/nav TOC model + providers)

Independent Codex review (gpt-5.6-sol, read-only sandbox) of the WI-1 diff:
`reader/nav/{TocEntry,TocProvider,ReadiumTocProvider,EmptyTocProvider}.kt` +
`ReadiumTocProviderTest.kt`.

## Verdict: ship-as-is (no blocking findings)

Codex confirmed all six requested focus points:

1. **Adapter-(i) is correctly located** in `ReadiumTocProvider`:
   `native.toJSON().toString()` → `bridge.toEnvelope(...)` → `envelope.legacyLocator`.
   `ReadiumLocatorBridge` stays pure-JVM and Readium-free (no Readium types added).
2. **`locatorFromLink(link) == null` skips only that entry** — descendants are still
   visited, preserving their structural depth (a null container skips its own row but
   its locatable children are not dropped).
3. **Flatten is preorder with correct depth**: top-level 0, child 1, grandchild 2.
4. **Canonical `Locator` carries the Book identity triple** (`contentSHA256`,
   `fileByteCount`, `originalFormat`); `fingerprintKey` derives from that same triple.
5. **The exact native `ReadiumLocator` instance is retained per emitted entry**;
   nullable `Link.title` and missing `locations.position` are represented safely as
   nullable fields (`title: String?`, `pageLabel: String?`).
6. **No coroutine/isolation issue in `suspend toc()`** — deterministic in-memory
   traversal on the caller's context, no shared mutable state, no suspension boundary
   needing synchronization.

## Non-blocking observations (accepted, no code change)

- **Recursive flatten stack depth**: an extremely pathological TOC could theoretically
  overflow the stack via recursion. Real EPUB TOC nesting is shallow (typically ≤4
  levels), so this is not a reason to block WI-1. Accepted; a follow-up could convert
  to an explicit work-stack if a real deeply-nested book ever surfaces.
- Codex could not execute the targeted test in its read-only sandbox (watchdog needs to
  write log/sentinel files). The lane ran the suite separately:
  `RUN-ANDROID-TESTS RESULT: SUCCEEDED`, JUnit report `tests="9" failures="0"`.

## Test evidence

`scripts/run-android-tests.sh` with `ANDROID_CMD="cd android && ./gradlew
:app:testDebugUnitTest --tests '*ReadiumTocProviderTest'"` →
`RUN-ANDROID-TESTS RESULT: SUCCEEDED`; JUnit XML: 9 tests, 0 failures, 0 skipped.
Coverage: identity-triple canonical locator, nested-children depth, null-locator skip,
null title tolerated, empty publication → empty, `EmptyTocProvider` → empty, duplicate
hrefs with different fragments → distinct entries, native locator retained, page label
from `locations.position` (else null).
