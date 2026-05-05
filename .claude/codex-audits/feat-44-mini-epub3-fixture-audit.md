---
branch: feat/44-mini-epub3-fixture
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-05
---

## Manual audit evidence

Codex MCP not invoked for this change. Manual audit performed across the
8 dimensions defined in `/fix-issue` Phase 4b.

### Files read

- `vreader/Services/DebugBridge/DebugFixtureCatalog.swift` (changed) — full file, 57 lines.
- `vreaderTests/Services/DebugBridge/DebugFixtureCatalogTests.swift` (changed) — full file, 73 → 81 lines.
- `vreader/Resources/DebugFixtures/mini-epub3.epub` (new) — binary; structure verified via Python's `zipfile` module: 6 entries, `mimetype` first and uncompressed (EPUB spec compliance), `META-INF/container.xml` + `OEBPS/content.opf` + `OEBPS/nav.xhtml` + 2 chapter XHTMLs.
- `project.yml` — confirmed the existing pre-build script `Copy DebugFixtures (DEBUG only)` uses `rsync -a --delete` over `${SRCROOT}/vreader/Resources/DebugFixtures` and the absence-gate script `scripts/verify-release-no-debugbridge.sh` auto-discovers fixture filenames by walking the directory.
- `vreader/Services/DebugBridge/RealDebugBridgeContext.swift` (line 1, fixtureBundleSubdirectory const) — confirmed the catalog test reuses the same constant the production seed handler uses.

### Symbols / signatures verified

- `DebugFixture` struct shape and `Format` enum case `.epub` already exist (line 26 of catalog) — no new types introduced.
- `DebugFixtureCatalog.entries`, `.all()`, `.find(name:)` API surface unchanged.
- `RealDebugBridgeContext.fixtureBundleSubdirectory` is `nonisolated static let` — accessible from the test bundle without main-actor hop.

### Edge cases checked

- **EPUB structure**: mimetype is first entry AND uncompressed (verified via `zipfile.ZipInfo.compress_type == ZIP_STORED`). EPUB 3 spec requires this; non-compliant fixtures may fail Foliate's archive sniffing. PASS.
- **Catalog name collision**: `test_all_entriesHaveDistinctNames` (existing) covers this; the new `mini-epub3` ≠ `war-and-peace`. PASS.
- **Bundle resolution**: `test_all_entriesResolveInTheTestBundle` (existing) walks every entry and asserts `Bundle.main.url(forResource:withExtension:subdirectory:)` returns non-nil. Test passed — confirms the rsync pre-build script picks up `mini-epub3.epub` by the `--delete` filter even though no `inputFiles` change was needed.
- **Release leakage**: re-ran `scripts/verify-release-no-debugbridge.sh` post-change against a clean Release build. All six sub-checks PASS — auto-discovered fixture filenames correctly NOT in Release bundle.
- **Empty / corrupt EPUB**: out-of-scope for this fixture (this is a happy-path fixture; corrupt-input tests use synthetic in-test EPUBs already, see `EPUBParserTests.swift`).
- **CJK content**: fixture is ASCII-only by design (smaller, deterministic); CJK coverage already exists in `EPUBParserTests.cjkTitlesPreserved`. Not a regression risk for this fixture.

### Risks accepted

- **Cover image absent** in `mini-epub3.epub` — by design; this iteration targets feature #44 Foliate happy-path verification (settle / eval), NOT feature #43 cover extraction. A future iteration adds a separate cover-bearing fixture if needed.
- **Synthetic, not real-world** — fixture is hand-crafted XHTML, not a real-world publisher EPUB. Adequate for unit-level happy-path; real-world EPUB edge cases (encryption, fonts, DRM-attempt) remain in `EPUBParserTests`'s synthetic-input arsenal.

### Tests added

- `test_find_miniEpub3_returnsEPUBFixture` — direct positive test for the new entry's resolution.
- Existing `test_all_entriesResolveInTheTestBundle` automatically covers the new fixture's bundle presence (no change required, parametric over `entries`).
- `test_all_returnsKnownFixtureNames` updated from singleton set to two-element set.

### Verdict

**ship-as-is**. Change is mechanical extension of an existing, well-tested catalog. Release absence-gate re-runs clean. No new attack surface, no concurrency risk, no Bridge interaction. LOC delta: +14 lines across 2 Swift files + 2.2 KB binary fixture.
