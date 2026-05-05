---
branch: fix/44-stale-tests-batch
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-06
---

## Manual audit evidence

Codex MCP not invoked for this stale-test cleanup batch. Manual audit performed.

### Files changed

| File | Change | Lines |
|---|---|---|
| `vreaderTests/Models/SchemaV1Tests.swift` | `migrationPlanHasSchemas`: `count == 2` → presence check by name | +5 |
| `vreaderTests/Models/Migration/V1toV2MigrationTests.swift` | `migrationPlanIncludesBothSchemas`: `count == 2` → V1 + V2 presence check | +4 |
| `vreaderTests/Services/TXT/TXTChapterContentLoaderTests.swift` | helper `makeTestData` populates UTF-16 offsets; 3 ad-hoc tests likewise updated; `startByteBeyondDataReturnsEmpty` rewritten to assert new `decodeFailed` contract | +27 |
| `docs/features.md` | feature #44 row gets round 8 to verification history | tracker only |

### Why each test was stale

- **migrationPlanHasSchemas** / **migrationPlanIncludesBothSchemas** (hardcoded `count == 2`): production `VReaderMigrationPlan.schemas` has expanded V1→V6 over the project's life. The tests were never updated.
- **TXTChapterContentLoader cluster (16 tests)**: production switched from byte-range reads (`startByte`/`endByte`) to UTF-16-offset reads (`globalStartUTF16`/`textLengthUTF16`) — see `TXTChapterContentLoader.loadChapter` lines 30–66. The struct's UTF-16 fields default to `-1`. Tests constructed `TXTChapter` without UTF-16 values, so every load threw `decodeFailed` at the `start >= 0, length >= 0` bounds check.
- **startByteBeyondDataReturnsEmpty**: name + assertion claimed graceful empty-string return, but production now treats out-of-range UTF-16 offsets as a programming error per its inline comment _"Unpopulated UTF-16 offsets — should not happen with new builder."_ Test rewritten to match the new contract; name kept for git-blame continuity, with an explanatory comment.

### What I deliberately did NOT change

- Production code: completely untouched. This batch is test-only.
- Test names: kept identical to preserve git-blame and any external references.
- The `makeTestData` byte-count fields (`startByte`/`endByte`): kept populated even though `loadChapter` no longer reads them; the data structure still carries them and a future test addition might. Removing them would be a drive-by refactor.

### Edge cases checked

- **GBK fixture's UTF-16 length**: `"你好世界"` is 4 BMP CJK characters. Each is 1 UTF-16 code unit. So `textLengthUTF16 = 4`. Confirmed by counting on macOS shell: `python3 -c "print(len('你好世界'))" == 4`.
- **Empty chapter**: `globalStartUTF16: 5, textLengthUTF16: 0`. The bounds check `start < full.length` is satisfied (5 < 12 for "Some content"); `safeLen = min(0, ...) = 0` so the empty-string branch is taken. Verified by the test passing.
- **Out-of-range chapter**: `globalStartUTF16: 100` with `full.length: 5` → `start < full.length` is FALSE → `decodeFailed` thrown. Test catches and asserts.
- **Concurrency**: `concurrentLoadsDoNotCrash` test was already in the failing batch; passes after the helper fix without further changes — `loader.cacheCount` is `nonisolated` already.

### Risks accepted

- **`startByteBeyondDataReturnsEmpty` semantic flip**: from "returns empty" to "throws decodeFailed". This matches what production already does (and has done since the UTF-16 cutover). The renamed-but-not-renamed approach (test name unchanged, comment explains) keeps blame history intact while honestly describing the new behavior. Alternative would be a rename — out of scope for this stale-test batch.

### Tests added

None. This is a cleanup batch — fixes existing tests' assertions to match production's actual behavior. The tests themselves provide regression coverage; new tests would be redundant.

### Verdict

**ship-as-is**. 19 stale-test issues closed in one batch. Behavior of the production code is unchanged. Closes a substantial fraction of feature #44 acceptance criterion (e). Manual audit clean across the 8 dimensions.
