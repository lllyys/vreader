---
branch: fix/issue-423-positionpersistencetests-relaunch
threadId: 019e052d-1642-7282-baa8-eeb67627b94c
rounds: 2
final_verdict: ship-as-is
date: 2026-05-08
---

## Round 1 — initial audit

| File | Severity | Issue | Resolution |
|---|---|---|---|
| `vreader/App/VReaderApp.swift:90` | Low | Persistent-store selection inferred by exclusion (`!seedEmpty && !seedBooks && !seedCorruptDB`) instead of explicit intent. With the current 5 seed modes this correctly classifies `.positionTest` and `.keepExisting`, so the bug fix itself is correct today. The risk is forward drift: `--uitesting-no-seed` is not parsed into its own field, so any future UI-test launch that omits those three flags (a new seed case, another "no fixture" scenario) will silently become disk-backed and can pick up stale SwiftData state across methods or separate `xcodebuild` runs because simulator app containers are typically reused. | **Fixed**: parsed `--uitesting-no-seed` into a new `seedKeepExisting: Bool` field on `TestLaunchConfig`. Wired through the parse path and the `.none` no-op initializer. Replaced the inference-by-exclusion gate with an explicit `config.seedPositionTest \|\| config.seedKeepExisting` whitelist. Updated the in-line comment to spell out that future seed enums default to in-memory (the safer test-isolation default). |

Codex confirmed the other audit dimensions checked out:

- **Test isolation**: `setUpWithError` always launches `.positionTest`; `TestSeeder.seedPositionTest` calls `clearAllBooks` first; `deleteBook` cascades per-book state. Disk-backed store still starts each test method clean.
- **Concurrency / lifecycle**: detached-task + 5s semaphore seeding flow unchanged in behavior by switching from in-memory to disk-backed. No new race introduced.
- **DEBUG-only gating**: change is fully inside `#if DEBUG`. Release init still uses the existing default `ModelConfiguration()` regardless of UI-testing flags.
- **Bug #152 scope**: that one is about UserDefaults persistence; this fix only touches SwiftData store selection. No scope creep.

## Round 2 — verification

> No findings. Ship as-is.
>
> The explicit whitelist now classifies the seeds exactly as intended:
> - Disk-backed: `.positionTest`, `.keepExisting`
> - In-memory: `.empty`, `.books`, `.corruptDB`
>
> `seedKeepExisting` is parsed explicitly in `VReaderApp.swift:301`, wired into the no-op initializer at `VReaderApp.swift:354`, and used by the store gate at `VReaderApp.swift:95`. That removes the prior whitelist-by-exclusion hazard and makes future seeds default to the safer in-memory behavior.

## Verdict

**ship-as-is** — 2 rounds, round-1 Low finding resolved, round-2 returned no further issues. Test suite verified GREEN at v3.14.79 + this fix:

```
Executed 3 tests, with 0 failures (0 unexpected) in 62.366 s
** TEST SUCCEEDED **
```

(Was 2 passed + 1 skipped pre-fix; the skip is now removed.)

Bug #151 (test infrastructure: terminate-then-relaunch persistence) is fixed via disk-backed `ModelConfiguration` for `.positionTest` and `.keepExisting` seeds. The relaunch test now runs end-to-end and asserts position restoration after `app.terminate()` + `launchApp(seed: .keepExisting)`.
