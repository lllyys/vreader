# Feature #28 — TXT Native-Mode Chinese Conversion (WI-A)

**Date**: 2026-05-12  
**Feature**: #28 Simplified/Traditional Chinese conversion  
**GH Issue**: #239  
**Plan scope**: WI-A — TXT native-mode conversion path (the primary gap keeping GH #239 open)

---

## Problem

Chinese conversion (`SimpTradTransform`) is wired only to `ReaderUnifiedCoordinator.activeTransforms`, which runs in Unified reading mode. TXT format does NOT have `.unifiedReflow` capability (removed in bug #158 / GH #468 — the Unified renderer truncated TXT content). As a result, TXT is effectively always in Native mode, and the picker is disabled entirely.

Bug #120 Path B (FIXED, PR #311ish) correctly disabled the picker in Native mode for all formats. But the third acceptance criterion for feature #28 — "Body text actually converts in default user state" — is still not met. Default user state for Chinese ebook reading is: TXT format in Native reading mode.

TXT readers hold NSAttributedString built from the raw file text. The string build is a pure transform (text → NSAttributedString via `TXTAttributedStringBuilder`). Applying `SimpTradTransform` before building the attributed string gives us character-level conversion that's:
- Correct: CJK characters are 1:1 replacements, all UTF-16 offsets are preserved
- Efficient: O(n) single-pass over the text
- Idiomatic: mirrors what `ReaderUnifiedCoordinator` already does for Unified mode

---

## Surface Area

### Files to modify

**`vreader/Views/Reader/TXTReaderContainerView.swift`** (currently 735 lines)
- `attrStringKey` (line ~97): add `settingsStore?.chineseConversion.rawValue ?? "none"` to the key string
- `.task(id: attrStringKey)` (line ~242): after resolving source text (chapter or full), apply transform via `TextMapper.apply(transforms:to:)` before passing to `TXTAttributedStringBuilder.build()` or building chunks
- Local helper `transformedText(_ source: String) -> String` inside the task body: calls `TextMapper.apply(transforms:to:).text` (return type is `TransformResult`, not `String` — use `.text` accessor)
- NOTE: native mode discards the `OffsetMap` from `TransformResult`. This is acceptable because `SimpTradTransform` (Hans-Hant ICU) produces 1:1 UTF-16 mappings for all BMP CJK characters. Reading positions and highlight ranges saved in source-text coordinates remain valid in transformed-text coordinates. Comment in implementation must document this invariant.

**`vreader/Views/Reader/ReaderSettingsPanel.swift`** (line ~476+)
- Promote `ChineseConversionDisableReason` from `private enum` to `internal enum` (same file, for testing)
- Add `static func chineseConversionDisableReason(for format: BookFormat?, readingMode: ReadingMode, capabilities: FormatCapabilities?) -> ChineseConversionDisableReason?` — testable static helper mirroring `shouldShowReadingModeSection(for:)` pattern
- TXT in native mode → `nil` (no disable reason)
- MD in native mode → `nil` (MD has `.unifiedReflow` for Unified, and now also supports native transform)
- EPUB in native mode → `.nativeMode` (unchanged; no native transform for EPUB)
- PDF regardless of mode → `.formatUnsupported` (unchanged)
- Update the private `chineseConversionDisableReason` computed property to call the static helper

### Files NOT in scope

- `MDReaderContainerView.swift` — MD is deferred to WI-B. MD render pipeline is load-once via `MDFileLoader`; reactive rebuild on conversion change requires threading `transforms` through `MDParser` and a re-render mechanism. Separate WI.
- `EPUBWebViewBridge.swift` / `FoliateViewBridge.swift` — EPUB/AZW3 native mode conversion is not planned
- `SimpTradTransform.swift`, `TextMapper.swift` — unchanged
- `FormatCapabilities.swift` — no capability bit needed; gate logic lives in `ReaderSettingsPanel`
- `ReaderContainerView.swift` — the existing `onChange(of: settingsStore.chineseConversion)` block only updates `unifiedCoordinator.activeTransforms`; TXT native rebuild is handled by `attrStringKey` task
- `TXTChunkedReaderBridge.swift` — chunks are `[String]` transformed before building; no bridge changes needed

---

## Prior Art / Project Precedent

- **`TXTAttributedStringBuilder`**: already decoupled from file loading. Accepts `text: String` and builds from it. Transform-before-build is a one-liner.
- **`attrStringKey` reactive rebuilds**: TXTReaderContainerView already uses a composite string key (`attrStringKey`) to trigger attributed string rebuilds on theme/font/layout changes. Adding `chineseConversion` is an identical extension of this existing pattern.
- **`ReaderSettingsPanel.shouldShowReadingModeSection(for:)` static helper pattern**: Gate 1 (reading mode visibility) uses a static testable method. The Chinese conversion gate follows the same pattern to enable unit testing.
- **`TextMapper.apply(transforms:to:)`**: used in `ReaderUnifiedCoordinator.applyTransforms`. Identical call site in TXT native mode.

**Rejected alternatives:**
- Add `.nativeTextTransform` to `FormatCapabilities`: adds complexity to the capability system for a single feature. The `bookFormat: BookFormat?` parameter already exists on `ReaderSettingsPanel`; format-direct check is sufficient.
- Apply conversion in `TXTReaderViewModel.open()`: the ViewModel is conversion-unaware. Keeping conversion at the display layer (view's task body) avoids threading settings state into service code.
- Apply conversion via NSAttributedString character iteration post-build: character substitution is more complex on attributed strings than on plain strings. Apply before build.

---

## Work-Item Sequencing

### WI-A (this plan) — TXT native-mode conversion
**Tier**: Behavioral (changes visible text in TXT reader)
**PR size**: small (~40–60 lines of change across 2 files + tests)

Changes:
1. `TXTReaderContainerView.attrStringKey` includes `chineseConversion`
2. `.task(id: attrStringKey)`: transform text before all three build paths
3. `ReaderSettingsPanel.chineseConversionDisableReason`: static helper; TXT/MD native mode → `nil`

Tests:
- `ReaderSettingsPanelChineseConversionGateTests.swift` — static helper, all format/mode combos
- `TXTReaderContainerViewChineseConversionTests.swift` — `attrStringKey` changes when `chineseConversion` changes; `internal` accessor on `attrStringKey`

### WI-B (future, not this plan) — MD native-mode conversion
Thread `transforms` through `MDFileLoader.load()` → `parser.parse()` → `MDAttributedStringRenderer.render()`. Add `.onChange(of: settingsStore?.chineseConversion)` in `MDReaderContainerView` that re-opens the file with the new transform.

---

## Test Catalogue

**New: `vreaderTests/Views/Reader/ReaderSettingsPanelChineseConversionGateTests.swift`**
- `txt_nativeMode_noDisableReason` — TXT, readingMode=.native → reason is nil (picker enabled)
- `md_nativeMode_noDisableReason` — MD, readingMode=.native → reason is nil (picker enabled)
- `epub_nativeMode_disabledNativeMode` — EPUB, readingMode=.native → reason is `.nativeMode`
- `epub_unifiedMode_noDisableReason` — EPUB, readingMode=.unified, caps includes .unifiedReflow → nil
- `pdf_anyMode_disabledFormatUnsupported` — PDF, any mode → reason is `.formatUnsupported`
- `azw3_unifiedMode_noDisableReason` — AZW3, readingMode=.unified → nil
- `nil_caps_fallback_unified_nativeMode_forTXT` — nil capabilities + TXT + native → nil (backward compat for previews)

**New: `vreaderTests/Views/Reader/TXTReaderContainerViewChineseConversionTests.swift`**
- `attrStringKey_changeOnChineseConversionChange` — construct two `TXTReaderContainerView` instances differing only in `chineseConversion`, confirm `attrStringKey` differs (requires `attrStringKey` promoted to `internal`)
- `attrStringKey_sameWhenConversionNone` — two instances with `.none` have same key

**Existing tests (no changes expected):**
- `SimpTradTransformTests.swift` — transform logic unchanged
- `TXTAttributedStringBuilderTests.swift` — builder interface unchanged

---

## Risks + Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Large TXT file performance — applying transform before chunking adds O(n) pass | Low | SimpTradTransform is dictionary lookup; 500K chars ≈ <50ms. Same cost as Unified mode. Measure in tests, add TODO if > 200ms threshold. |
| UTF-16 offset correctness — CJK chars are all BMP (1 UTF-16 unit); transform preserves offsets | Low | Document invariant in code comment. Edge case: if a surrogate-pair char maps to a CJK replacement (not real in practice), offset shift would be off. Not possible with real SimpTrad dictionaries. |
| `attrStringKey` string-comparison fragility | Low | Key is intentionally opaque; tests check that it CHANGES (not exact value), so format is stable. |
| Chunked path — text chunks need to be rebuilt from transformed text | Low | In `.task` body, apply transform BEFORE `TXTTextChunker.split()`. Chunks will be from transformed text. Already handled in the single pass. |

---

## Backward Compatibility

- No schema changes; `chineseConversion` is already persisted in `UserDefaults`.
- Books opened before this WI: no change. If `chineseConversion == .none`, transform is a no-op.
- If a user previously had `chineseConversion == .simplified` selected while in Native mode (before bug #120 Path B disabled the picker), the setting is still persisted. After this WI, opening a TXT book will show converted text as the user originally requested. No unexpected behavior.
- `ReaderSettingsPanel` gate change: TXT/MD native mode picker becomes enabled. Users who previously couldn't change this setting will now be able to.

---

## Manual Audit Evidence (Gate 2 — Codex MCP unavailable)

**Files read**: `TXTReaderContainerView.swift`, `ReaderSettingsPanel.swift` (lines 476–520), `TextMapper.swift` (full), `SimpTradTransform.swift` (full), `FormatCapabilities.swift` (full), `ReaderUnifiedCoordinator.swift` (33–60), `ReaderSettingsPanelReadingModeGateTests.swift`

**Symbols verified**: `TXTReaderContainerView.attrStringKey` (line 96) ✓, `.task(id: attrStringKey)` (line 242) ✓, `TextMapper.apply(transforms:to:) -> TransformResult` ✓, `SimpTradTransform(direction:)` ✓, `ChineseConversionDirection.none` ✓, `ReaderSettingsPanel.ChineseConversionDisableReason` (private enum, line 487) ✓, `FormatCapabilities.unifiedReflow` ✓, `ReadingMode.native/.unified` ✓, `BookFormat.txt/.md/.epub/.pdf/.azw3` ✓

**Edge cases checked**: conversion==.none identity passthrough ✓; chapter text path ✓; large-file chunked path (transform before split) ✓; small-file full path ✓; Task.isCancelled guards unchanged ✓; highlight position after transform relies on 1:1 UTF-16 invariant ✓; Sendable safety of transform in Task.detached ✓

**Findings fixed in v2**:
1. (Medium) `TextMapper.apply()` returns `TransformResult`, not `String` — implementation must use `.text` accessor. Plan updated.
2. (Low) Native mode discards `OffsetMap` — document 1:1 UTF-16 invariant. Plan updated.
3. (Low) Three render paths need independent transform application — explicitly noted in plan.

**Risks accepted**: Non-1:1 UTF-16 mapping edge case in CFStringTransform Hans-Hant is theoretically possible but not observed in practice for CJK chars. Consistent with how the rest of the codebase handles this.

## Revision History

- v1 (2026-05-12): Initial plan, WI-A scope (TXT only; MD deferred to WI-B).
- v2 (2026-05-12): Gate 2 manual audit — two Medium/Low findings fixed (TextMapper return type, offset map invariant doc). Verdict: proceed to Gate 3.
