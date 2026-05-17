---
branch: fix/issue-804-bottom-chrome-hittable
threadId: 019e35ed-af9f-7c80-b31e-b19b3bdf84ea
rounds: 2
final_verdict: ship-as-is
date: 2026-05-17
---

# Codex Audit — Bug #209 / GH #804

Feature #60's chrome/library re-skin broke the Verification XCUITest
harness (9 of 25 verification tests failed). The fix addresses three
distinct root causes plus two Feature37 test-harness fixes. 12 files
changed (+213 / −50). Audit run read-only against the worktree.

## Round 1

| # | file:line | severity | issue | resolution |
|---|---|---|---|---|
| 1 | `vreader/App/TestSeeder.swift` (`seedTwoBooks`) | Medium | The `.twoBooks` seed uses fixed fingerprint keys, but per-book overrides are file-backed JSON under `Application Support/PerBookSettings` — `clearKnownPreferences()` wipes only UserDefaults, never that directory. A prior run's leftover override could reattach to a seeded book, making Feature37's "toggle starts OFF / isolation" assertions nondeterministic (or vacuous). | **Fixed** — added `clearPerBookSettings()`, called from `seedTwoBooks` right after `clearAllBooks`; it removes the `PerBookSettings` directory so each `.twoBooks` launch starts from known-empty state. |
| 2 | `vreader/App/TestSeeder.swift` (`insertRealTXTBook`) | Medium | `insertRealTXTBook` swallowed directory-creation + file-write failures with `try?` and then still inserted the `BookRecord` — a write failure silently produced metadata-without-a-file, i.e. the exact broken state Cause A exists to fix, only further from its real cause. | **Fixed** — `createDirectory` + `data.write` now run inside `do/catch`; on failure the function logs and `return`s before `insertBook`, so a write failure surfaces as a missing-from-library book, not a metadata-only ghost. |

Cause B (reader-container identifier propagation → scoped `Group`) and
Cause C (sheet-container identifier propagation → `.accessibilityElement(children: .contain)`)
drew **no findings** — Codex confirmed both are technically correct:
moving the container identifier onto the content-side `Group` confines
propagation to that subtree (still reaches the inner TXT/MD text view,
no longer clobbers the bottom-chrome sibling); `.accessibilityElement(children: .contain)`
is the correct way to give a sheet a resolvable container element
without flattening or hiding its child controls. No Swift 6 isolation
problem in `seedTwoBooks` / `TestLaunchConfig`.

## Round 2

Both fixes re-audited — **no findings**.

- (a) Clearing the whole `PerBookSettings` directory at seed time does
  not break `test_..._persists_across_reopen`: that test does one app
  launch in `setUpWithError`, then only in-process navigation (back to
  library, reopen the same book). `seedTwoBooks()` is not re-run on the
  reopen; the mid-test override survives because `savePerBookSnapshot()`
  recreates the directory on demand.
- (b) No new issue introduced. Clearing the whole directory is
  appropriate for a test-only seed whose contract is "start from
  known-empty per-book override state"; the write-failure change fails
  in the safer direction.
- (c) `clearPerBookSettings()` as a non-isolated `private static func`
  is correct under Swift 6 — it touches no actor-isolated state,
  captures nothing non-Sendable, does synchronous `FileManager` work
  only, and is concurrency-safe when called from the seeding task.

## Verdict

**ship-as-is.** Two audit rounds; all Round 1 findings (2 × Medium)
fixed and verified clean in Round 2. Zero open Critical/High/Medium/Low
findings.
