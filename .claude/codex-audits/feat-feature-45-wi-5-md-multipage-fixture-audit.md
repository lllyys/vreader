---
branch: feat/feature-45-wi-5-md-multipage-fixture
threadId: 019e28c7-02bb-78f2-95ee-ffaffa899c45
rounds: 3
final_verdict: ship-as-is
date: 2026-05-15
---

# Gate 4 audit log — Feature #45 WI-5 (MD multi-page fixture)

WI-5 adds `seedMDMultiPage` to `TestSeeder` — an in-code MD fixture sized to span ≥2 pages at 18pt on iPhone 17 Pro Sim's reader viewport, plus the launch-arg + dispatch + XCUITest enum wiring to seed it. Foundational WI for Feature #31's deferred live multi-page advancement verification slice.

## Round 1 (Codex thread `019e28be…` — prefix only, full UUID lost)

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 1 | Medium | `TestSeederMDMultiPageTests.seedMDMultiPageAndSeedMDWithTOCProduceDistinctCanonicalKeys()` hardcoded `fileByteCount: 678` for the TOC fixture — fragile across content edits to `generateMDWithHeadings()`. | Widened `generateMDWithHeadings()` from `private` to `internal` so the test can derive byte counts dynamically. (Reversed the Gate 2 round-1 decision to keep it private.) |
| 2 | Low | Chapters 4-5 of `generateMDMultiPage()` only had 2 paragraphs each and no H3, breaking the documented "5 chapters × 4 paragraphs + ≥5 H3" shape contract. | Padded chapters 4-5 to 4 paragraphs each + added H3 sections 4.1 and 5.1. Fingerprint hash updated accordingly. |
| 3 | Low | `TestSeeder.swift` now ~605 lines, over the 300-line file-size guideline (`.claude/rules/50-codebase-conventions.md`). | Accepted with rationale — broader file-split cleanup is out of scope for WI-5 (which only appends one seed pair). Tracked as residual repo debt; the full split is a follow-up. |
| 4 | Low | File-system orphan cleanup gap — old fixture files in `ImportedBooks/` from previous test runs aren't purged on seed. | Accepted — TestSeeder-wide concern, not WI-5-specific. Follow-up. |

Round-1 verdict: **Reject as-is** → 2 fixed (1, 2), 2 accepted with rationale (3, 4).

## Round 2 (same thread)

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 5 | Medium | Canonical-key test STILL reconstructed fingerprints from constants rather than exercising the live seed implementations. A future bug that gave both seeds the same hash literal + byte count would slip through. | Rewrote test to seed both fixtures into an in-memory `Schema(SchemaV6.models)` + `PersistenceActor`, fetch back via `fetchAllLibraryBooks()`, and compare the persisted `fingerprintKey`. Test method renamed `seedMDMultiPageAndSeedMDWithTOCProduceDistinctCanonicalKeysWhenLiveSeeded()`. Added `import SwiftData` to the test file. |
| 6 | Low | Doc-comment drift in `TestSeeder.swift:generateMDMultiPage` claiming "~6 KB". | Rewrote with invariant phrasing: paginates to ≥2 pages at 18pt; byte count drifts and is non-contractual. |
| 7 | Low | Doc-comment drift in `LaunchHelper.swift:TestSeedState.mdMultiPage`. | Same invariant phrasing applied. |

Round-2 verdict: **Reject as-is** → 3 fixed (5, 6, 7).

## Round 3 (fresh Codex thread `019e28c7-02bb-78f2-95ee-ffaffa899c45`)

The round-1/2 thread ID was prefix-only in session memory (`019e28be…`) — Codex MCP requires the full 32-char UUID to continue, so the round-3 audit started a fresh thread with a summary of prior findings to verify closure.

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 8 | Medium | `TestSeederMDMultiPagePaginationTests` called `MDRenderConfig()` without explicitly pinning `fontSize: 18`. Works today (default is 18), but a future default change would silently make the test false-green and no longer validate the documented "≥2 pages at 18pt" contract. | Test now constructs `MDRenderConfig(fontSize: 18)` explicitly. |
| 9 | Low | `VReaderApp.swift` `seedMDMultiPage` doc comment reintroduced exact-size drift ("~6 KB", "~678 B"). | Rewrote with invariant phrasing: paginates to ≥2 pages at 18pt on iPhone 17 Pro Sim; sibling `seedMDTOC` is the smaller single-page size class; byte counts non-contractual. |
| 10 | Low | The WI-5 plan section in `dev-docs/plans/20260513-feature-45-verification-harness-sweep.md` still said "Decision: keep `generateMDWithHeadings()` private" while the final code widens it to `internal`. Also still referenced the old 678-byte literal. | Updated surface-area item 4 + Risk note to reflect final state. Appended a Gate 4 audit-history table (rounds 1/2/3) to preserve the decision trail. |

Round-3 verdict (Codex): **follow-up-recommended** → all 3 findings (8, 9, 10) fixed inline before merge. Round 3 is the audit cap per rule 47; no further rounds.

## Closure note

All 7 round-1/2 findings closed and verified in the fresh round-3 read. Round-3 added 3 more (1 Medium, 2 Low), all fixed in-place. Test gate clean after every round of fixes (18 tests in 3 suites passing under `xcodebuild test -only-testing:vreaderTests/...`).

Items 3 (TestSeeder.swift LOC) and 4 (file-system orphan cleanup) remain residual TestSeeder-wide debt — accepted with rationale, not blocking this WI.

**Final verdict: ship-as-is.**

No remaining Critical/High/Medium findings. The two accepted Lows are out-of-scope debt items tracked for a future TestSeeder cleanup pass.
