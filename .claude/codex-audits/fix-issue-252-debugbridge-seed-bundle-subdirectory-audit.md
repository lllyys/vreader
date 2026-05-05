---
branch: fix/issue-252-debugbridge-seed-bundle-subdirectory
threadId: 019df725-73b0-7940-84e5-08aa2972317f
rounds: 2
final_verdict: ship-as-is
date: 2026-05-05
---

# Codex audit log — Bug #124 fix (GH #252)

## Round 1 — initial findings

| File | Line | Severity | Issue | Resolution |
|------|------|----------|-------|------------|
| `vreaderTests/Services/DebugBridge/DebugFixtureCatalogTests.swift` | 50 | Medium | `test_all_entriesResolveInTheTestBundle` still validated the old root-level lookup (`Bundle.main.url(forResource:withExtension:)`) and its comment claimed fixtures are flat-copied to bundle root. The bug-#124 regression could slip again outside `RealDebugBridgeContextTests` because no other suite gated on the `subdirectory:` lookup. | Fixed: updated the test to use `subdirectory: RealDebugBridgeContext.fixtureBundleSubdirectory` and rewrote the comment to point at `project.yml`'s pre-build script as the writer-side source of truth. |
| `vreaderTests/Services/DebugBridge/RealDebugBridgeContextTests.swift` | 68 | Low | The helper `makeFixtureBundle` hardcoded the literal `"DebugFixtures"` even though the production code now centralizes that constant in `RealDebugBridgeContext.fixtureBundleSubdirectory`. Kept two Swift-side literals instead of one shared source. | Fixed: replaced the literal with `RealDebugBridgeContext.fixtureBundleSubdirectory`. The helper now updates automatically if the constant changes. |
| `vreader/Services/DebugBridge/RealDebugBridgeContext.swift` | 46 | Low | The file is 477 lines, over the repo's "keep code files under ~300 lines" guideline. | **Deferred** per Codex's own recommendation: "Don't block this bugfix on a split." Pre-existing condition; this PR adds one constant + one parameter, doesn't worsen the design. Future PR can extract command-specific handlers when the area gets non-trivial changes. |

## Round 2 — verification re-pass

Tests after Round-1 fixes:

- `DebugFixtureCatalogTests`: all pass.
- `RealDebugBridgeContextTests`: 4 seed tests pass (the bug-#124 regression suite). One failure remains — `test_snapshot_withoutActiveReader_listsReaderFieldsAsPartial` asserts `snap.schemaVersion == 1` while the actual schemaVersion is 2. **Pre-existing on main** (verified by checking out `main` and reproducing the same failure). Out of scope for this PR.

Forcing change discovered during Round 2: the constant had to be marked `nonisolated static let` because `DebugFixtureCatalogTests` is not `@MainActor`-annotated, so it couldn't read the MainActor-isolated property. The `nonisolated` annotation is the precise Swift 6 idiom for an immutable string constant on a MainActor type — it doesn't leak mutable actor-isolated state.

Codex confirmed: "The catalog test now provides the intended cross-suite regression gate. ... `nonisolated static let` is the right Swift 6 choice here."

## Final verdict

**ship-as-is**

The fix:
- Adds `subdirectory: Self.fixtureBundleSubdirectory` to the `Bundle.url(...)` call in `RealDebugBridgeContext.seed`.
- Adds `nonisolated static let fixtureBundleSubdirectory = "DebugFixtures"` as the single source of truth for the path constant.
- Updates the test helper to use the constant.
- Updates `DebugFixtureCatalogTests` to exercise the same lookup shape, providing a cross-suite regression gate.

The constant matches what `project.yml`'s "Copy DebugFixtures (DEBUG only)" pre-build script writes (`${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/DebugFixtures` → `<app bundle>/DebugFixtures`). RED→GREEN proven by 4 seed tests.

Pre-existing test failure (`schemaVersion == 1`) is orthogonal to this fix.
