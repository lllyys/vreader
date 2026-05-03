# Phase A Implementation Plan (Retroactive)

**Date**: 2026-03-17
**Status**: RETROACTIVE — all 5 WIs implemented
**Scope**: 5 quick-win features — search highlighting, custom covers, tap zones, theme backgrounds, per-book settings

## WI-A01: #22 Search Match Highlighting in Result List

**What was built**: Pure function `HighlightedSnippet.highlight()` that applies bold AttributedString runs to query matches in search result snippets.

**Files created/modified**:
- `vreader/Utils/HighlightedSnippet.swift` — Core logic (90 lines)
- `vreaderTests/Utils/HighlightedSnippetTests.swift` — 14 tests

**Key decisions**:
- Case-insensitive matching via NSRegularExpression.
- Multi-word queries split by whitespace; each word highlighted independently.
- Regex special characters in query escaped for literal matching.
- FTS5 `<b>...</b>` tags stripped before highlighting.
- Returns plain AttributedString when query is empty or has no matches.

**Tests (14)**:
- `emptyQuery_returnsPlainText`, `emptySnippet_returnsEmpty`
- `singleWordMatch_highlighted`, `caseInsensitiveMatch`, `fts5TagsStripped`
- `noMatch_returnsPlainText`, `multiWordQuery_highlightsBothWords`
- `multiWordQuery_worksWhenExactPhraseNotPresent`
- `multiWordQuery_duplicateWordHighlightsAllOccurrences`
- `singleWordQuery_stillWorks`, `whitespaceOnlyQuery_returnsPlainText`
- `multiWordQuery_withExtraSpaces_handledGracefully`
- `multiWordQuery_overlappingMatches_handled`
- `regexSpecialCharsInQuery_escaped`

**Gaps**: None identified. Thorough edge case coverage.

---

## WI-A02: #30 Custom Book Covers

**What was built**: `CustomCoverStore` enum with static methods for saving, loading, removing custom cover images per fingerprint key. JPEG storage with resize.

**Files created/modified**:
- `vreader/Services/CustomCoverStore.swift` — Store logic (139 lines)
- `vreaderTests/Services/CustomCoverStoreTests.swift` — 16 tests

**Key decisions**:
- JPEG compression at quality 0.8, max 512x512 (no upscale).
- Fingerprint keys sanitized (colons, slashes replaced) for filesystem safety.
- All methods accept optional `baseDirectory` for testability.
- Enum with static methods — no instance state.
- Images stored at `<baseDirectory>/CustomCovers/<sanitizedKey>.jpg`.

**Tests (16)**:
- `coverPath_uniquePerBook`, `coverPath_sanitizesColons`
- `setCover_savesImageToDisk`, `setCover_replacesExisting`
- `setCover_resizesLargeImage`, `setCover_doesNotUpscaleSmallImage`
- `getCover_returnsNil_whenNoCover`, `getCover_returnsImage_whenCoverSet`
- `removeCover_deletesFile`, `removeCover_noOpWhenNoCover`
- `hasCover_falseWhenNoCover`, `hasCover_trueAfterSave`, `hasCover_falseAfterRemove`
- `emptyFingerprintKey_handledGracefully`, `fingerprintKey_withSlashes_sanitized`
- `coverPath_isUnderCustomCoversSubdirectory`

**Gaps**: None. Pattern matches ThemeBackgroundStore cleanly.

---

## WI-A03: #25 Configurable Tap Zones

**What was built**: `TapZoneConfig` model (zone detection, action mapping), `TapZoneStore` (@Observable persistence), `TapZoneOverlay` (SwiftUI view modifier), `TapZoneDispatcher` (NotificationCenter dispatch).

**Files created/modified**:
- `vreader/Models/TapZoneConfig.swift` — Model + store (100 lines)
- `vreader/Views/Reader/TapZoneOverlay.swift` — Overlay modifier + dispatcher (55 lines)
- `vreaderTests/Views/Reader/TapZoneTests.swift` — 24 tests

**Key decisions**:
- Three horizontal zones: left/center/right at 33.33% each.
- Zone detection is a static pure function (`zone(atX:totalWidth:)`).
- Actions dispatched via NotificationCenter (`.readerContentTapped`, `.readerPreviousPage`, `.readerNextPage`).
- All types Codable + Sendable. TapZoneStore persists via UserDefaults.
- PDF wired via PDFPageNavigator (WI-B09).

**Tests (24)**:
- Zone detection: `tapInLeftZone`, `tapInCenterZone`, `tapInRightZone`, `leftEdge`, `rightEdge`, `centerExact`, `leftBoundary`, `pastLeftBoundary`, `rightBoundary`, `pastRightBoundary`, `zeroWidth`, `negativeX`, `xExceedsWidth`
- Configuration: `defaultZones_leftPrevPage_centerToggle_rightNextPage`, `actionForZone`, `codableRoundTrip`, `defaultCodableRoundTrip`, `customMapping`, `allActionsAssignable`
- Raw values: `zoneRawValues`, `actionRawValues`, `actionAllCases`
- Store: `defaultConfig`, `persistsCustomConfig`

**Gaps**: None. Accessibility labels on overlay view are good.

---

## WI-A04: #32 Reading Theme Backgrounds

**What was built**: `ThemeBackgroundStore` for saving/loading/removing background images per theme. `ThemeBackgroundView` SwiftUI component for rendering backgrounds in reader.

**Files created/modified**:
- `vreader/Services/ThemeBackgroundStore.swift` — Store logic (48 lines)
- `vreader/Views/Reader/ThemeBackgroundView.swift` — SwiftUI view (24 lines)
- `vreaderTests/Services/ThemeBackgroundTests.swift` — 11 tests

**Key decisions**:
- Max dimension 1024px (vs 512px for covers). JPEG quality 0.8.
- Stored at `<baseDirectory>/ThemeBackgrounds/<themeName>.jpg`.
- Uses pixel dimensions for resize check (avoids scale mismatch).
- ThemeBackgroundView reloads on theme change and useCustomBackground toggle.
- Background opacity controlled by `settingsStore.backgroundOpacity`.

**Tests (11)**:
- `saveBackground_savesImageToDisk`, `saveBackground_resizesLargeImage`
- `saveBackground_doesNotResizeSmallImage`, `loadBackground_returnsNil_whenNone`
- `loadBackground_returnsImage_whenSet`, `removeBackground_deletesFile`
- `removeBackground_doesNotThrow_whenNoFile`, `saveBackground_resizesHighScaleImage`
- `saveBackground_overwritesExisting`, `backgroundPath_uniquePerTheme`
- `backgroundPath_usesJPEGExtension`

**Gaps**: ThemeBackgroundStore has compact formatting (single-line methods) — could benefit from formatting cleanup but is functional.

---

## WI-A05: #37 Per-Book Reading Settings

**What was built**: `PerBookSettingsOverride` model (all fields optional), `ResolvedSettings` (fully resolved), `PerBookSettingsStore` (JSON file persistence + resolution).

**Files created/modified**:
- `vreader/Services/PerBookSettings.swift` — Model + store (127 lines)
- `vreaderTests/Services/PerBookSettingsTests.swift` — 15 tests

**Key decisions**:
- All override fields Optional — nil means "inherit from global".
- Stored as JSON files keyed by fingerprint at `<baseURL>/<sanitizedKey>.json`.
- Pure value type + enum namespace — no singletons.
- `resolve()` merges per-book overrides onto global ReaderSettingsStore values.
- File-based storage keeps per-book settings isolated from UserDefaults.
- Colons replaced with underscores in filenames. Empty keys mapped to `_empty_key`.

**Tests (15)**:
- `perBookSettings_defaultsToNil`, `perBookSettings_savesAndRestores`
- `perBookSettings_differentBooks_independent`, `perBookSettings_deleteRemoves`
- `perBookSettings_codable_roundTrip`, `perBookSettings_codable_roundTrip_allNils`
- `resolvedSettings_usesPerBook_whenSet`, `resolvedSettings_usesGlobal_whenNoPerBook`
- `perBookSettings_partialOverride`, `resolvedSettings_allFieldsOverridden`
- `perBookSettings_emptyFingerprintKey`, `perBookSettings_deleteNonexistent_noError`
- `perBookSettings_directoryCreatedOnSave`, `perBookSettings_specialCharsInKey`
- `perBookSettings_overwriteExisting`

**Gaps**: UI for editing per-book settings not yet built (ReaderSettingsPanel integration pending). The resolve() method requires @MainActor, which may need attention when called from background contexts.

---

## Phase A Summary

| WI | Tests | Lines (impl) | Lines (test) | Status |
|----|-------|-------------|-------------|--------|
| A01 | 14 | 90 | 160 | DONE |
| A02 | 16 | 139 | 206 | DONE |
| A03 | 24 | 155 | 95 | DONE |
| A04 | 11 | 72 | 105 | DONE |
| A05 | 15 | 127 | 222 | DONE |
| **Total** | **80** | **583** | **788** | **DONE** |

## Integration Notes

- All WIs are independent — no cross-WI dependencies.
- A03 (tap zones) is a prerequisite for Phase B pagination (B06, B08, B09).
- A05 (per-book settings) UI integration with ReaderSettingsPanel is pending.
- All implementations follow the enum-with-static-methods pattern for stores.
- All use optional `baseDirectory`/`baseURL` parameter for testability.

## Manual Testing

See `docs/manual-test-checklist.md` for phase-specific test items.
