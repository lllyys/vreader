# Feature #45 — Verification Harness Sweep — Implementation Plan

**Status**: Gate 1 (Plan)
**Date**: 2026-05-13
**Feature row**: `docs/features.md` § Feature #45 — status `PLANNED`
**GH Issue**: (assigned at PLANNED time — see features.md Notes column)

---

## Revision History

| Rev | Date       | Author       | Change                        |
|-----|------------|--------------|-------------------------------|
| v1  | 2026-05-13 | Claude Agent | Initial plan draft            |
| v2  | 2026-05-13 | Claude Agent | Manual audit fixes: corrected Feature #27 replacement rules UI path (global Settings, not reader panel); corrected Chinese conversion label to "Chinese Text"; clarified auto-page-turn toggle AID strategy; added `settingsView` AID to verified list |

---

## 1. Problem

`docs/features.md` and `docs/bugs.md` carry a monotonically-growing "Needs device verification" backlog. Every release adds entries faster than humans can verify old ones. The repetitive UI-driving work that verification requires is both error-prone and time-consuming for humans. The result: tracker statuses lie (`DONE` means "code shipped, untested"), regressions go undetected, and pre-release manual passes balloon in scope.

13 of the backlog items are simulator-automatable using XCUITest and the existing DebugBridge (`vreader-debug://`) harness introduced in feature #44. This plan builds the harness to auto-verify those 13 items, leaving only the irreducible real-device items in the human checklist.

The two items that remain manual after this feature:
- **Feature #26** — TTS audio quality (no programmatic way to QA voice quality on simulator)
- Any flow requiring real iCloud, real haptics, or real Apple ID

---

## 2. Surface Area

### New Files Created

#### `vreaderUITests/Verification/` — verification test suite root

All tests use `verify_feature_<NN>_<slug>` naming convention so failures map mechanically to tracker rows.

---

**`vreaderUITests/Verification/Feature37PerBookSettingsVerificationTests.swift`** (proving-ground item 1)

```
class Feature37PerBookSettingsVerificationTests: XCTestCase
  func verify_feature_37_perbook_settings_toggle_isolated_to_book()
    // open book A → settings → "Custom settings for this book" toggle ON
    // → change font size → back to library → open book B
    // → assert book B has original font size (not book A's override)
    // AID: "readerSettingsPanel", Toggle "Custom settings for this book"
    // AID: no unique ID on the toggle — locate via label string

  func verify_feature_37_perbook_settings_persists_across_reopen()
    // open book A → per-book ON → change font to XXL → back → reopen book A
    // → assert settings panel shows XXL font persisted
```

Key AccessibilityIDs used: `readerSettingsButton` (→ `readerSettingsPanel`), label-match on "Custom settings for this book" toggle.

---

**`vreaderUITests/Verification/Feature34CollectionsVerificationTests.swift`** (proving-ground item 2)

```
class Feature34CollectionsVerificationTests: XCTestCase
  func verify_feature_34_create_collection_appears_in_sidebar()
    // collectionsToolbarButton → newCollectionButton → newCollectionTextField
    // → type "Test Suite Collection" → addCollectionButton → filterDoneButton
    // → reopen sidebar → assert filterAllBooks + "Test Suite Collection" row exists

  func verify_feature_34_add_book_to_collection_filters_library()
    // create collection → long-press bookCard → "Add to Collection" → select
    // collection → filterAllBooks sidebar → tap collection filter → assert only
    // the tagged book is visible in library grid
```

Key AccessibilityIDs used: `collectionsToolbarButton`, `newCollectionButton`, `newCollectionTextField`, `addCollectionButton`, `filterDoneButton`, `filterAllBooks`, `bookCard_<fingerprintKey>`.

---

**`vreaderUITests/Verification/Feature11EPUBHighlightVerificationTests.swift`** (proving-ground item 3)

```
class Feature11EPUBHighlightVerificationTests: XCTestCase
  func verify_feature_11_epub_highlight_happy_path()
    // seed mini-epub3 → open → long-press word → Highlight menu → tap
    // → annotations panel → Highlights tab → assert highlight row exists
    // → close+reopen → assert highlight row still exists (persistence)
    // AID: "epubReaderContent", "readerAnnotationsButton", "annotationsPanelSheet",
    //       "Highlights" tab button, "highlightEmptyState" (must be absent)

  func verify_feature_11_epub_highlight_regression_bug77_buffering_race()
    // Specifically targets the JS buffering race (bug #77): rapid long-press
    // before DOMContentLoaded settles → verify highlight is still created
    // Uses vreader-debug://settle to gate on ready state before action
```

Key AccessibilityIDs used: `epubReaderContent`, `epubReaderContainer`, `readerAnnotationsButton`, `annotationsPanelSheet`, `highlightEmptyState` (must disappear), `highlightRow-<id>`.

---

**`vreaderUITests/Verification/Feature21PaginatedModeVerificationTests.swift`**

```
class Feature21PaginatedModeVerificationTests: XCTestCase
  func verify_feature_21_paged_mode_shows_paged_view()
    // seed books → open TXT book → readerSettingsButton → readingModeSection
    // → pick "Paged" → assert "nativeTextPagedView" appears
    // AID: "readerSettingsPanel", Picker "Reading Mode", "nativeTextPagedView"

  func verify_feature_21_paged_mode_page_navigation()
    // in paged mode → tap right zone → assert page number increments
    // AID: "nativeTextPagedView", "readingProgressLabel"
```

Key AccessibilityIDs used: `readerSettingsButton`, `readerSettingsPanel`, `nativeTextPagedView`, `readingProgressLabel`.

---

**`vreaderUITests/Verification/Feature23TXTTocVerificationTests.swift`**

```
class Feature23TXTTocVerificationTests: XCTestCase
  func verify_feature_23_txt_toc_populated_for_chinese_chapters()
    // seed war-and-peace (has chapter headers) → open → readerAnnotationsButton
    // → Contents tab → assert tocEmptyState is absent (entries exist)
    // AID: "annotationsPanelSheet", "Contents" tab button, "tocEmptyState" (must be absent),
    //       "tocRow-<id>" prefix

  func verify_feature_23_txt_toc_navigation_jumps_to_chapter()
    // tap a tocRow → assert reader scrolls to that chapter position
    // AID: "tocRow-<id>", "txtReaderContainer"
```

Key AccessibilityIDs used: `readerAnnotationsButton`, `annotationsPanelSheet`, `tocEmptyState`, `tocRow-<id>`.

---

**`vreaderUITests/Verification/Feature27ReplacementRulesVerificationTests.swift`**

```
class Feature27ReplacementRulesVerificationTests: XCTestCase
  func verify_feature_27_replacement_rule_ui_surface()
    // From library: settingsToolbarButton → "settingsReplacementRules" row visible
    // → tap → ReplacementRulesView navigation push renders (assert title/add button)
    // AID: "settingsToolbarButton", "settingsReplacementRules"
    // NOTE: Replacement rules live in global Settings (not reader settings panel).
    //       Path: LibraryView toolbar → SettingsView sheet → Replacement Rules row.

  func verify_feature_27_replacement_rule_applies_in_reader()
    // (a) From global Settings: add replacement rule pattern="Chapter" → replacement=""
    // (b) settingsDoneButton → library → open war-and-peace TXT
    // (c) assert "txtReaderContent" value does NOT contain visible "Chapter" tokens
    //     (spot-check via snapshot or textView value predicate)
    // AID: "settingsToolbarButton", "settingsReplacementRules", "settingsDoneButton",
    //       "txtReaderContent"
    // CAUTION: ReplacementRulesView has no explicit AID for "Add rule" button.
    //           Locate by label-match ("Add Rule" or "+" system button).
    //           Flag as AID-gap: "replacementRulesAddButton" needed in ReplacementRulesView.
```

Key AccessibilityIDs used: `settingsToolbarButton`, `settingsReplacementRules`, `settingsDoneButton`, `settingsView`, `txtReaderContent`. **Replacement rules are in global Settings (SettingsView), not in the reader settings panel. The `readerSettingsButton` / `readerSettingsPanel` path does NOT reach them.** AID gap: `replacementRulesAddButton` needed in `ReplacementRulesView.swift`.

---

**`vreaderUITests/Verification/Feature28ChineseConversionVerificationTests.swift`**

```
class Feature28ChineseConversionVerificationTests: XCTestCase
  func verify_feature_28_simp_to_trad_conversion_active()
    // seed war-and-peace (CJK content needed — or use a CJK fixture if available)
    // open → readerSettingsButton → scroll to "Chinese Text" segmented picker
    // → tap "Simp → Trad" segment → assert picker selection updated
    // AID: "readerSettingsPanel", Picker with accessibilityLabel "Chinese text conversion"
    //      (segmented style — locate via app.segmentedControls["Chinese text conversion"])
    // IMPORTANT: The picker label is "Chinese Text" (section header), accessibilityLabel
    //            is "Chinese text conversion". It is DISABLED unless format + mode supports it.
    //            Test must open a TXT book in Unified mode to enable the picker.
    //            NOTE: Needs CJK fixture for meaningful content assertion. Flag as
    //                  FIXTURE-GAP: a zh-simp TXT fixture is needed.

  func verify_feature_28_conversion_applies_to_reader_content()
    // Dependent on CJK fixture. Skips if fixture absent.
    // AID: "txtReaderContent" (value must contain trad chars, not simp chars)
```

Key AccessibilityIDs used: `readerSettingsPanel`. **Fixture gap: CJK TXT fixture needed**.

---

**`vreaderUITests/Verification/Feature29WebDAVVerificationTests.swift`**

```
class Feature29WebDAVVerificationTests: XCTestCase
  func verify_feature_29_webdav_backup_ui_available()
    // settingsToolbarButton → WebDAV section → assert "webdavBackupNowButton" exists
    // (smoke: UI surface is reachable, credentials form renders)
    // AID: "settingsToolbarButton", "webdavServerURL", "webdavBackupNowButton"

  func verify_feature_29_webdav_backup_executes_when_configured()
    // CONDITIONAL: skipped with XCTSkip if CI_WEBDAV_URL env var is unset
    // Configure from env vars → trigger backup → assert no "webdavBackupErrorText"
    // AID: "webdavTestButton", "webdavSaveButton", "webdavBackupNowButton",
    //       "webdavBackupErrorText" (must be absent)
```

Key AccessibilityIDs used: `settingsToolbarButton`, `webdavServerURL`, `webdavTestButton`, `webdavSaveButton`, `webdavBackupNowButton`, `webdavBackupErrorText`. **WebDAV test is CI-conditional** (`XCTSkip` when server URL absent).

---

**`vreaderUITests/Verification/Feature31AutoPageTurnVerificationTests.swift`**

```
class Feature31AutoPageTurnVerificationTests: XCTestCase
  func verify_feature_31_auto_page_turn_advances_page()
    // seed books → open TXT book → set paged mode → enable autoPageTurn
    // (short interval, e.g. 1s via settings) → wait 2.5s → assert page advanced
    // AID: "readerSettingsPanel", Toggle "Auto Page Turn", "nativeTextPagedView",
    //       "readingProgressLabel"
    // NOTE: Auto-page-turn toggle has no dedicated AID. Flag as AID-gap.
    // ANTI-FLAKE: Use XCTNSPredicateExpectation on readingProgressLabel value change,
    //             not Thread.sleep.
```

Key AccessibilityIDs used: `nativeTextPagedView`, `readingProgressLabel`. **AID gap: `autoPageTurnToggle` + `autoPageTurnIntervalSlider` needed in `ReaderSettingsPanel.swift`**. Fallback without AIDs: `app.switches["Auto page turn"]` + `app.sliders["Auto page turn interval"]`.

---

**`vreaderUITests/Verification/Feature35AnnotationsExportVerificationTests.swift`**

```
class Feature35AnnotationsExportVerificationTests: XCTestCase
  func verify_feature_35_export_button_triggers_share_sheet()
    // seed books → open a book → create highlight (gesture or via debug URL)
    // → readerAnnotationsButton → annotationsPanelSheet → annotationsExportButton
    // → assert share sheet / document picker appears (UIActivityViewController)
    // AID: "annotationsExportButton", "annotationsPanelSheet"
    // NOTE: Can't assert exported file contents via XCUI; assert sheet _presence_ only.

  func verify_feature_35_import_button_is_visible()
    // readerAnnotationsButton → annotationsPanelSheet → assert annotationsImportButton hittable
    // (import flow uses DocumentPicker — can't drive OS picker in XCUI without workaround)
    // AID: "annotationsImportButton"
```

Key AccessibilityIDs used: `annotationsExportButton`, `annotationsImportButton`, `annotationsPanelSheet`.

---

**`vreaderUITests/Verification/Feature36OPDSVerificationTests.swift`**

```
class Feature36OPDSVerificationTests: XCTestCase
  func verify_feature_36_opds_catalog_ui_surface()
    // opdsCatalogsToolbarButton → assert "opdsCatalogList" or "opdsEmptyState" present
    // → opdsAddCatalog button → assert form fields (opdsCatalogNameField, opdsCatalogURLField)
    // AID: "opdsCatalogsToolbarButton", "opdsCatalogList", "opdsEmptyState",
    //       "opdsAddCatalog", "opdsCatalogNameField", "opdsCatalogURLField",
    //       "opdsCatalogSaveButton"

  func verify_feature_36_opds_browse_with_local_fixture()
    // CONDITIONAL: skipped if CI_OPDS_URL env var unset
    // Configure local OPDS feed → browse → assert opdsEntryDetail reachable
    // AID: "opdsCatalog_<id>", "opdsEntryDetail", "opdsDownload_<format>"
```

Key AccessibilityIDs used: `opdsCatalogsToolbarButton`, `opdsEmptyState`, `opdsCatalogList`, `opdsAddCatalog`, `opdsCatalogNameField`, `opdsCatalogURLField`, `opdsCatalogSaveButton`. **OPDS browse is CI-conditional**.

---

**`vreaderUITests/Verification/Feature40TTSSentenceHighlightVerificationTests.swift`**

```
class Feature40TTSSentenceHighlightVerificationTests: XCTestCase
  func verify_feature_40_tts_sentence_highlight_fires_callback()
    // seed war-and-peace → open → readerTTSButton → ttsPlayPauseButton
    // → wait for ttsControlBar → use vreader-debug://snapshot to read
    //   DebugSnapshot.ttsState → assert sentenceRange is non-nil
    // AID: "readerTTSButton", "ttsControlBar", "ttsPlayPauseButton"
    // NOTE: Uses DebugBridge snapshot for assertion, not visual inspection.
    //       TTS uses AVSpeechSynthesizer on simulator (no audio, but callbacks fire).

  func verify_feature_40_tts_sentence_highlight_callback_count_advances()
    // After 2s of TTS playback, assert sentenceHighlightCount > 0
    // via snapshot.ttsState (DebugSnapshot schema v2, feature #49 WI-7a)
    // ANTI-FLAKE: XCTNSPredicateExpectation on snapshot sentinel file, not sleep.
```

Key AccessibilityIDs used: `readerTTSButton`, `ttsControlBar`, `ttsPlayPauseButton`. **DebugSnapshot `ttsState` field requires feature #49 WI-7a to be shipped** — verify before implementing this test.

---

**`vreaderUITests/Verification/Feature41TTSAutoScrollVerificationTests.swift`**

```
class Feature41TTSAutoScrollVerificationTests: XCTestCase
  func verify_feature_41_tts_autoscroll_advances_position()
    // seed war-and-peace → open in scroll mode → TTS start → 2s wait
    // → assert txtReaderContainer value (restoredOffset) changed from initial
    // AID: "txtReaderContainer" (value contains restoredOffset:<N>),
    //       "ttsPlayPauseButton", "ttsControlBar"
    // Uses same value-predicate pattern as TXTHighlightGestureVerificationTests.

  func verify_feature_41_tts_autoscroll_pauses_on_stop()
    // start TTS → record offset → stop → wait 2s → assert offset unchanged
```

Key AccessibilityIDs used: `txtReaderContainer`, `ttsPlayPauseButton`, `ttsStopButton`, `ttsControlBar`.

---

#### `vreaderUITests/Verification/Helpers/` — shared test helpers

These helpers are scoped to the Verification group. They do not modify existing `vreaderUITests/Helpers/` files.

**`vreaderUITests/Verification/Helpers/VerificationDebugBridgeHelper.swift`**

Helper methods wrapping `xcrun simctl openurl` calls for reset, seed, settle, snapshot. Provides a `settleApp(token:timeout:)` that watches the sentinel file produced by `vreader-debug://settle?token=<X>` instead of sleeping.

Concrete methods:
```
func resetApp()                                         // vreader-debug://reset
func seedFixture(named name: String)                    // vreader-debug://seed?fixture=<name>
func settleApp(token: String, timeout: TimeInterval)    // writes Caches/ready-<token>.json
func snapshotApp(dest: String) -> DebugSnapshotDTO?     // reads snapshot JSON
```

**`vreaderUITests/Verification/Helpers/VerificationSettingsHelper.swift`**

Reusable helpers for opening/closing the reader settings panel and scrolling to named sections.

```
func openReaderSettings(in app: XCUIApplication) -> XCUIElement  // returns panel element
func scrollToSection(_ sectionHeader: String, in panel: XCUIElement)
func closeReaderSettings(in app: XCUIApplication)
```

---

#### `vreaderTests/Verification/` — unit tests for harness helpers

**`vreaderTests/Verification/VerificationDebugBridgeHelperTests.swift`**

Swift Testing suite:

```
@Suite("VerificationDebugBridgeHelper")
struct VerificationDebugBridgeHelperSuite {
  @Test func resetURL_hasCorrectScheme()
  @Test func seedURL_encodesFixtureName()
  @Test func settleURL_encodesToken()
  @Test func snapshotURL_encodesDest()
  @Test func fixtureNamesInCatalog_resolveToBundle()
}
```

**`vreaderTests/Verification/VerificationSettingsHelperTests.swift`**

```
@Suite("VerificationSettingsHelper")
struct VerificationSettingsHelperSuite {
  // These are pure URL-construction tests; no app launch.
  @Test func sectionHeaderMatches_known_sections()
}
```

---

### Files Modified

| File | Change |
|------|--------|
| `vreaderUITests/Helpers/TestConstants.swift` | Add new `AccessibilityID` constants for identified gaps (see AID Gaps section) |
| `vreader/Views/Reader/ReaderSettingsPanel.swift` | Add `accessibilityIdentifier` to auto-page-turn toggle (`autoPageTurnToggle`) and auto-page-turn interval slider (`autoPageTurnIntervalSlider`) |
| `vreader/Views/Settings/ReplacementRulesView.swift` | Add `accessibilityIdentifier("replacementRulesAddButton")` to the Add Rule button |
| `docs/manual-test-checklist.md` | Mark 13 items "Auto-verified by `<test-name>`"; add "Real-device only" section for #26 and iCloud flows |

### Files OUT of Scope

- `vreaderTests/Services/DebugBridge/` — existing DebugBridge unit tests are unaffected
- `vreader/Views/` outside `ReaderSettingsPanel.swift` (no new production features — harness only)
- `vreader/Services/` — no service changes
- `vreaderUITests/` existing tests outside `Verification/` — untouched
- `vreaderUITests/Helpers/LaunchHelper.swift` — not modified; Verification uses it as-is
- `project.yml` scheme configuration — CI integration deferred to WI-4 (add `Verification` test plan entry)
- Any WebDAV or OPDS server fixtures — existing bundle fixtures from feature #44 are used; new CJK fixture is a conditional addition for feature #28

---

## 3. AID Gaps (Required Before Gate 3)

The following AccessibilityIDs are missing from production code but required for tests. WI-1 must add them to both `TestConstants.swift` and the production views **before** the tests that depend on them are written.

| AID String | Production File | Used By |
|---|---|---|
| `replacementRulesAddButton` | `ReplacementRulesView.swift` | Feature27 test (add a rule) |
| `autoPageTurnToggle` | `ReaderSettingsPanel.swift` | Feature31 test |
| `autoPageTurnIntervalSlider` | `ReaderSettingsPanel.swift` | Feature31 test |

**Corrected: `replacementRulesSection` was incorrectly planned for `ReaderSettingsPanel.swift`. Replacement rules are accessed via the global Settings sheet (`settingsToolbarButton` → `settingsReplacementRules`), not via the reader settings panel. No changes to `ReaderSettingsPanel.swift` are needed for feature #27.**

**Note on `perBookCustomSettingsToggle`**: The per-book toggle exists (Toggle "Custom settings for this book") but has no `accessibilityIdentifier`. Tests for feature #37 can locate it by label text (`app.switches.matching(NSPredicate(format: "label == 'Custom settings for this book'"))`). This is acceptable because the label is stable — no production AID change required.

**Note on auto-page-turn**: The auto-page-turn Toggle label is "Auto page turn" (accessibilityLabel). The interval Slider label is "Auto page turn interval". Both can be located via label-match (`app.switches["Auto page turn"]`, `app.sliders["Auto page turn interval"]`). Dedicated AIDs are still recommended for stability. The `accessibilityLabel` fallback is documented in the test comment.

---

## 4. Prior Art / Project Precedent / Rejected Alternatives

### Prior art used as the pattern

**`TXTHighlightGestureVerificationTests.swift`** is the canonical template:
- `setUp` uses `launchApp(seed:resetPreferences:)` — never `vreader-debug://reset` for tests that use `LaunchHelper`, since the app restarts fresh each time
- `continueAfterFailure = false`
- `@MainActor` on the test class
- `XCTNSPredicateExpectation` for all async waits — no `Thread.sleep`
- `waitForExistence(timeout:)` / `waitForHittable(timeout:)` / `waitForDisappearance(timeout:)` from `LaunchHelper.swift` extension
- Accessibility-ID-first element location; falls back to label-match only when AID absent

**`DebugBridgeTests.swift`** and `RealDebugBridgeContextTests.swift` show how `vreader-debug://` commands are tested at the unit level. The `VerificationDebugBridgeHelper` in this plan follows the same command URL schema.

**`CollectionSidebarTests.swift`** shows the pattern for testing sidebar-based features: `resetPreferences: true` on launch + label-string tap for tabs/sections.

**`OPDSCatalogListTests.swift`** shows the conditional server-dependent test pattern: tests assert UI surface without a live server; browsing tests are structurally present but stub-safe (they assert the entry-point button is hittable, not that a live catalog loads).

### Rejected alternative: DebugBridge URL-only verification

The `vreader-debug://snapshot` command (feature #49 WI-7a) could be used to drive all verifications without XCUI gestures — just send commands and read back JSON. Rejected because:
1. Snapshot-only testing does not prove the **gesture path** works (e.g., long-press highlight). Feature #11's original bug was in the gesture pipeline, not persistence.
2. XCUITest drives the same code paths a real user exercises; `simctl openurl` bypasses SwiftUI and UIKit gesture recognizers.
3. The project already has XCUI infrastructure that works and is maintainable — adding a parallel test runner would fragment coverage.

DebugBridge is used as a **complement** in this plan (settle + snapshot for async-state assertions), not a replacement.

### Rejected alternative: Snapshot-diffing (visual regression)

Rejected per features.md Scope "Excluded": separate concern, separate feature if/when it arrives. This harness verifies behavior, not pixels.

### Rejected alternative: Docker WebDAV / OPDS for all CI runs

Real-server tests add CI complexity (container management, port allocation, teardown). The plan uses `XCTSkip` when server env vars are absent, preserving the ability to run the full suite when a server is available without blocking CI when it isn't. This mirrors the pattern used in feature #46's Docker integration tests.

---

## 5. Work-Item Sequencing

### WI-1 — Harness scaffolding + AID gaps + proving-ground items (#37, #34, #11)

**Type**: Behavioral
**PR size estimate**: ~350 LOC (2 helper files + 3 feature test files + AID additions)

Deliverables:
1. `vreaderUITests/Verification/Helpers/VerificationDebugBridgeHelper.swift`
2. `vreaderUITests/Verification/Helpers/VerificationSettingsHelper.swift`
3. `vreaderTests/Verification/VerificationDebugBridgeHelperTests.swift` (Swift Testing)
4. `vreaderTests/Verification/VerificationSettingsHelperTests.swift` (Swift Testing)
5. `vreaderUITests/Verification/Feature37PerBookSettingsVerificationTests.swift`
6. `vreaderUITests/Verification/Feature34CollectionsVerificationTests.swift`
7. `vreaderUITests/Verification/Feature11EPUBHighlightVerificationTests.swift`
8. AID additions to `vreader/Views/Reader/ReaderSettingsPanel.swift` (autoPageTurnToggle, autoPageTurnIntervalSlider) and `vreader/Views/Settings/ReplacementRulesView.swift` (replacementRulesAddButton)
9. Add new AID constants to `vreaderUITests/Helpers/TestConstants.swift`

Gate: all tests pass in `xcodebuild test -only-testing:vreaderUITests/Verification/Feature37PerBookSettingsVerificationTests` etc. + `vreaderTests/Verification`.

---

### WI-2 — Features #21, #23, #27, #28

**Type**: Behavioral
**PR size estimate**: ~280 LOC (4 feature test files)

Deliverables:
1. `vreaderUITests/Verification/Feature21PaginatedModeVerificationTests.swift`
2. `vreaderUITests/Verification/Feature23TXTTocVerificationTests.swift`
3. `vreaderUITests/Verification/Feature27ReplacementRulesVerificationTests.swift`
4. `vreaderUITests/Verification/Feature28ChineseConversionVerificationTests.swift`

Prerequisite: WI-1 AID additions merged (`replacementRulesAddButton` AID in `ReplacementRulesView.swift` needed by feature #27 test).

Note on feature #28: if no CJK TXT fixture is available in the bundle, `verify_feature_28_conversion_applies_to_reader_content` is implemented as `XCTSkip("CJK TXT fixture not present in bundle")` with a fixture-request filed in the WI-2 PR description. The UI-surface test (`verify_feature_28_simp_to_trad_conversion_active`) does not require CJK content and runs unconditionally.

Gate: all tests in WI-2 test files pass.

---

### WI-3 — Features #29, #31, #35, #36, #40

**Type**: Behavioral
**PR size estimate**: ~300 LOC (5 feature test files)

Deliverables:
1. `vreaderUITests/Verification/Feature29WebDAVVerificationTests.swift`
2. `vreaderUITests/Verification/Feature31AutoPageTurnVerificationTests.swift`
3. `vreaderUITests/Verification/Feature35AnnotationsExportVerificationTests.swift`
4. `vreaderUITests/Verification/Feature36OPDSVerificationTests.swift`
5. `vreaderUITests/Verification/Feature40TTSSentenceHighlightVerificationTests.swift`

Dependency check before implementation: confirm `DebugSnapshot.ttsState` schema is available (feature #49 WI-7a). If not shipped, feature #40 TTS state assertion falls back to asserting `ttsControlBar` is visible (weaker but valid smoke check).

Gate: all tests pass (server-dependent tests skip cleanly when env vars absent).

---

### WI-4 — Feature #41, CI integration, docs update

**Type**: Behavioral + foundational (CI integration is foundational; #41 test is behavioral)
**PR size estimate**: ~200 LOC

Deliverables:
1. `vreaderUITests/Verification/Feature41TTSAutoScrollVerificationTests.swift`
2. CI: Add `Verification` test plan to `project.yml` scheme (new `testPlans` entry under `vreaderUITests` target, referencing `Verification/` directory)
3. Update `docs/manual-test-checklist.md`: mark 13 items auto-verified, add "Real-device only" section
4. Update `docs/architecture.md`: add `vreaderUITests/Verification/` to the UITest section
5. Add `dev-docs/verification-red-checks.md`: record RED-proof checks for regression tests

Gate: `xcodebuild test -only-testing:vreaderUITests/Verification` exits 0 in under 8 minutes on the CI runner. All 13 features reach `VERIFIED` status in `docs/features.md`.

---

### WI-4c — Production-code launch args to unblock #31 and #40/#41 XCUITest verification

**Type**: Foundational (production code launch args + DebugBridge endpoint) + Behavioral (test refactors that consume them)
**PR size estimate**: ~200 LOC (production + tests + 1 unit test file)

**Why this WI exists** — WI-4 + WI-4b discovered two blockers that prevent the last 2 of the 13 verification tests from flipping to `pass` (logged in commit 6615c8b's body, "Findings (deferred to WI-4c)"):

1. **Feature #31 (auto page turn)**: SwiftUI `Picker(.segmented)` tap dispatch under XCUITest does not transition `ReaderSettingsStore.epubLayout` from `.scroll` to `.paged`. The picker IS rendered (architecture grep confirms), but the tap-on-segment gesture is swallowed by XCUITest's segmented-control routing. WI-4b shipped a 3-way fallback lookup (`panel.buttons["Paged"]` → `segmentedControls.buttons["Paged"]` → `descendants[label == "Paged"]`); none of the three transition the store under XCUITest. Symptom: `verify_feature_31_auto_page_turn_advances_page` XCTSkips because `autoPageTurn` toggle (gated on `epubLayout == .paged`) never appears.
2. **Feature #40/#41 (TTS sentence highlight + auto-scroll)**: `AVSpeechSynthesizer` does not begin speech under XCUITest context on iPhone 17 Pro Sim, even with 30 s timeouts. The synthesizer is constructed but `speak(_:)` never advances the speech delegate to `didStart`. CU verified TTS works end-to-end (2026-05-09 feature #26 round-2), so this is XCUITest-context specific — likely the audio-session activation requirement that XCUITest's runner-test split breaks. Symptom: `verify_feature_40_*` and `verify_feature_41_*` XCTSkip with "ttsControlBar did not appear in 30s".

Both blockers cost roughly the same to work around with **production-code launch args** (lowest blast radius — no behavior change for end users, additive only): the test bypasses the gesture/audio-session activation by setting a DEBUG-only flag that the production code reads at known points in the lifecycle.

**Surface area** — file-by-file with concrete signatures:

1. `vreader/App/VReaderApp.swift`:
   - `parseLaunchConfig(from:)` (around line 340-384): add two `args.contains(...)` checks and a `String?` parse for `--reader-default-layout=<value>`.
   - `TestLaunchConfig` struct (around line 317): add `defaultEPUBLayout: EPUBLayoutPreference?` and `ttsAutostart: Bool` fields.
   - In the existing `#if DEBUG` early-setup block (around line 90-156, where preferences are reset): if `config.defaultEPUBLayout != nil`, write its `rawValue` to `UserDefaults.standard` under `ReaderSettingsStore.epubLayoutKey` BEFORE `ReaderSettingsStore.init` runs anywhere (this is the cleanest injection point because the store reads `defaults.string(forKey: epubLayoutKey)` lazily at init time per `ReaderSettingsStore.swift:58, 83`).
2. `vreader/Services/DebugBridge/DebugCommand.swift` + `DebugBridgeHandler.swift`:
   - Add new case `tts(action: String)` parsed from `vreader-debug://tts?action=start` (and optionally `stop`).
   - Handler delegates to a new `Notification.Name.debugTTSCommand` posted to whoever owns `ReaderContainerView.ttsService` (the active reader observes for `.debugTTSCommand` and calls `ttsService.startSpeaking(text:fromOffset:)` with the current book's text via `ReflowableTextSource`).
3. `vreader/Views/Reader/ReaderContainerView.swift`:
   - Add observer for `.debugTTSCommand` notification when DEBUG is set, that resolves the current book's `ReflowableTextSource` and invokes `ttsService.startSpeaking`. This mirrors the production path of the TTS play button without requiring the audio-session-blocking gesture.
4. `vreaderUITests/Verification/Feature31AutoPageTurnVerificationTests.swift`:
   - Replace the WI-4b 3-way Paged lookup with `launchApp(seed: .mdTOC, resetPreferences: true, launchArguments: ["--reader-default-layout=paged"])`. Drop the XCTSkip path. Assert `autoPageTurnToggle.waitForExistence(timeout: 5)` succeeds.
5. `vreaderUITests/Verification/Feature40TTSSentenceHighlightVerificationTests.swift`:
   - After `launchApp(seed: .warAndPeace)` and opening the book, fire `vreader-debug://tts?action=start` via `VerificationDebugBridgeHelper`. Assert `ttsControlBar.waitForExistence(timeout: 5)` succeeds and `ttsState.isSpeaking == true` in `DebugSnapshot`.
6. `vreaderUITests/Verification/Feature41TTSAutoScrollVerificationTests.swift`:
   - Same pattern as #40. The scroll-offset assertion stays the same.
7. `vreaderUITests/Helpers/TestConstants.swift`:
   - Add `static let readerDefaultLayoutPaged = "--reader-default-layout=paged"` and `static let ttsAutostartURL = URL(string: "vreader-debug://tts?action=start")!`.
8. `vreaderTests/App/LaunchArgParsingTests.swift` (new):
   - Unit tests asserting `parseLaunchConfig` correctly extracts `--reader-default-layout=paged` → `.paged`, `--reader-default-layout=scrolled` → `.scroll`, `--reader-default-layout=garbage` → `nil` (falls through), and `--tts-autostart` → `true`. ~8 cases covering all enum values + invalid inputs.

**Prior art / project precedent / rejected alternatives**:

- **Precedent**: the codebase already uses production-code launch args for test purposes — `--uitesting`, `--seed-position-test`, `--reset-preferences`, `--dynamic-type-XS`, `--enable-ai`, `--reduce-motion`. All gated by `#if DEBUG` at the App level. WI-4c follows the same pattern.
- **Rejected**: replace `Picker(.segmented)` with `Picker(.menu)` for EPUB layout. Lowest cost code-wise but changes user-visible behavior (segmented control is the deliberate design choice). Rejected to preserve UX.
- **Rejected**: pure XCUITest workaround (e.g., coordinate-based tap on segment). WI-4b tried 3 variants of accessibility lookups; none transitioned the store. Coordinate-based tap is brittle (resolution-dependent + scrolls off in tests that scroll the panel) and worth avoiding when a production-code arg is cheap.
- **Rejected**: launch the TTS service with a mock `SpeechSynthesizing` adapter under XCUITest. Higher complexity (test-only DI path) than the DebugBridge URL approach, AND it would test a mock rather than the real synthesizer, weakening the test's signal.
- **Rejected**: schedule TTS via `Timer.scheduledTimer` after a fixed delay. Race-prone, doesn't match the production play-button path.

**Files OUT of scope**:

- All other `Feature*VerificationTests.swift` (untouched — they pass).
- `xctestplan` + project.yml scheme entry (originally listed in WI-4; deferred to a follow-up WI-4d if the user wants CI gating; not blocking VERIFIED status flips).
- `docs/manual-test-checklist.md` (separate WI-4d).
- `ReaderSettingsStore` internals — we use the existing UserDefaults injection point, not a new init parameter.

**Test catalogue for WI-4c**:

| File | What It Covers |
|---|---|
| `vreaderTests/App/LaunchArgParsingTests.swift` (new) | `parseLaunchConfig` parses `--reader-default-layout=<value>` correctly for all valid enum strings + falls through on invalid. Same for `--tts-autostart`. |
| `vreaderTests/Services/DebugBridge/DebugCommandTests.swift` (extend) | `DebugCommand.parse(URL("vreader-debug://tts?action=start"))` returns `.tts(action: "start")`; `tts?action=stop` returns `.tts(action: "stop")`; missing action falls through. |
| `Feature31AutoPageTurnVerificationTests` (refactor) | RED: pre-WI-4c, test XCTSkips. GREEN: post-WI-4c, test asserts `autoPageTurnToggle.exists == true`. |
| `Feature40TTSSentenceHighlightVerificationTests` (refactor) | RED: pre-WI-4c, XCTSkip on `ttsControlBar` timeout. GREEN: post-WI-4c, `ttsControlBar` appears within 5 s of `tts?action=start` URL fire. |
| `Feature41TTSAutoScrollVerificationTests` (refactor) | Same shape as #40. |

**Risks + mitigations**:

- **Risk**: writing to UserDefaults before `ReaderSettingsStore.init` runs may race with another path that reads the same key. **Mitigation**: do it inside the synchronous `parseLaunchConfig` + immediate UserDefaults write path that runs in `VReaderApp.init`'s App body builder, before any view body is evaluated. Add a unit test asserting that after the launch-arg write, `ReaderSettingsStore(defaults: testDefaults).epubLayout == .paged`.
- **Risk**: the `tts?action=start` URL fires before the book is loaded → `startSpeaking` no-ops. **Mitigation**: in the test, `launchApp` then `tapFirstBook(in:)` (existing helper) and wait for the book's reader to load before firing the URL. The notification observer in `ReaderContainerView` only attaches AFTER `task` runs, so it can't fire too early.
- **Risk**: the `Notification.Name.debugTTSCommand` listener is wired to the wrong reader instance when multiple readers are loaded (shouldn't happen in tests, but worth verifying). **Mitigation**: include the `fingerprintKey` in the URL `?action=start&key=<fp>` and have the observer filter by key, returning no-op for mismatch. Tests use single-book seeds.
- **Risk**: TTS audio-session activation may still fail under XCUITest even when called from the notification handler (this is the cause we're trying to bypass, but it may be uniform). **Mitigation**: WI-4c includes a small spike — write the DebugBridge URL handler and try it locally before committing the test refactors. If it doesn't unblock TTS, fall back to mocking `SpeechSynthesizing` with a test-only adapter that synchronously fires the speech-progress delegate callbacks. The audit (Gate 2) should call this out.

**Backward compat**: all launch args are additive and `#if DEBUG`-gated. Release builds ignore them. Production EPUB layout default is unchanged (UserDefaults absent → `.scroll` per existing `loadEPUBLayout` fallback).

**Edge cases**:

- `--reader-default-layout=foo` (invalid value): falls through; no UserDefaults write; store reads existing/default.
- `--tts-autostart` and `tts?action=start` URL both fired: idempotent — `startSpeaking` no-ops if already speaking.
- `tts?action=stop` before any start: no-op (existing `TTSService` behavior).
- Two consecutive `--reader-default-layout=paged` launches without `--reset-preferences`: idempotent UserDefaults write.

**Gate**: 
- All 5 acceptance tests for WI-4c pass (LaunchArgParsing unit + DebugCommand unit + 3 refactored Feature tests).
- `Feature31AutoPageTurnVerificationTests` passes without `XCTSkip`.
- `Feature40TTSSentenceHighlightVerificationTests` passes without `XCTSkip`.
- `Feature41TTSAutoScrollVerificationTests` passes without `XCTSkip`.
- 13-feature VERIFIED gate reaches 13/13. Update Feature #31, #40, #41 rows to `VERIFIED` with evidence files. Update Feature #45 row's notes.

#### WI-4c — Gate 2 audit (manual fallback, Codex MCP unavailable)

Date: 2026-05-13. Codex MCP (`mcp__plugin_codex-toolkit_codex__codex`) returned `stream disconnected before completion: error sending request for url (https://chatgpt.com/backend-api/codex/responses)` twice in a row — auditor genuinely unavailable, not just inconvenient. Per rule 47 manual-fallback evidence is required below.

**Files read** (paths):

- `vreader/App/VReaderApp.swift` (lines 85-160 + 317-403) — confirmed `TestLaunchConfig` struct + `parseLaunchConfig` injection points.
- `vreader/Services/ReaderSettingsStore.swift` (lines 14, 21, 53, 58, 83, 122) — confirmed `epubLayoutKey = "readerEPUBLayout"` UserDefaults key, `init(defaults:)` reads `loadEPUBLayout` lazily, store rereads on every `init`.
- `vreader/Models/EPUBLayoutPreference.swift` (lines 15-19) — confirmed enum cases `scroll` (rawValue "scroll") and `paged` (rawValue "paged"). The plan originally said `--reader-default-layout=scrolled`; correction below makes it `scroll` to match the rawValue.
- `vreader/Services/Foliate/FoliateTTSAdapter.swift`, `vreader/Services/TTS/TTSService.swift` (line 70, 179) — confirmed `startSpeaking(text:fromOffset:)` entry point and `extractText(from:startOffset:)` static helper.
- `vreader/Views/Reader/ReaderContainerView.swift` (line 57) — confirmed `@State var ttsService = TTSService()`.
- `vreader/Services/DebugBridge/DebugCommand.swift` + `DebugBridgeNotifications.swift` — confirmed existing pattern: `extension Notification.Name { static let debugBridgeOpenBook = Notification.Name("vreader.debugBridge.openBook") }`. Naming correction below: the plan's `.debugTTSCommand` should be `.debugBridgeTTSCommand` to match the established convention.
- `vreader/Services/ReflowableTextSource.swift` — confirmed protocol exists with `TXTReflowableTextSource` / `MDReflowableTextSource` concrete types.
- `vreaderUITests/Helpers/LaunchHelper.swift` (lines 99-178) — confirmed `launchApp(seed:colorScheme:dynamicType:enableAI:enableSync:reduceMotion:resetPreferences:)` signature. **Critical finding**: there is NO `launchArguments:` parameter on `launchApp` or `vreaderUITests_launchApp`. The plan must add `extraLaunchArguments: [String] = []` to BOTH signatures, threaded through to `args.append(contentsOf: extraLaunchArguments)` after the existing args (line 171, before `app.launchArguments = args`).
- `vreaderUITests/Helpers/LaunchHelper.swift` (line 230) — confirmed `tapFirstBook(in:)` exists.

**Symbols / signatures verified** (which fields/types/enums I confirmed exist):

- `EPUBLayoutPreference.scroll` ✓, `EPUBLayoutPreference.paged` ✓ (raw strings "scroll" / "paged").
- `ReaderSettingsStore.epubLayoutKey` ✓ static constant.
- `ReaderSettingsStore.loadEPUBLayout(defaults:)` ✓ pure lookup.
- `TTSService.startSpeaking(text:fromOffset:)` ✓ MainActor.
- `TestLaunchConfig` ✓ has `seedBooks`, `seedPositionTest`, etc. fields. Adding `defaultEPUBLayout: EPUBLayoutPreference?` and `ttsAutostart: Bool` follows the same pattern.
- `Notification.Name` extension pattern ✓ (existing prefix `vreader.debugBridge.*`).
- `XCUIApplication.launchArguments` ✓ array set via `app.launchArguments = args` at line 173.
- `tapFirstBook(in:)` ✓ exists.

**Edge cases checked** (the list — none missed in the plan, but explicit confirmation):

- `--reader-default-layout=foo` → falls through to no UserDefaults write → store reads existing/default (`.scroll`). ✓ covered in plan.
- `--reader-default-layout=scroll` and `--reader-default-layout=paged` → writes rawValue → store reads correctly. ✓ covered.
- `--tts-autostart` without book open → observer attached but no source until book loads → idempotent. ✓ covered.
- `tts?action=start` URL fires before observer attaches → notification posted to empty observer set → no-op. ✓ acceptable.
- `tts?action=stop` before any start → existing `TTSService` no-op. ✓ verified by reading TTSService:70 (defensive guard inside `startSpeaking`).
- Two consecutive `--reader-default-layout=paged` launches → idempotent UserDefaults write. ✓ implicit.
- Release build receives a `--reader-default-layout=paged` arg → `#if DEBUG` gate prevents parsing → arg silently ignored. ✓ matches existing pattern for `--seed-position-test`.

**Findings — fixes incorporated into plan**:

| # | Severity | Finding | Plan fix |
|---|---|---|---|
| 1 | High | The `--reader-default-layout=scrolled` rawValue is wrong; the actual enum rawValue is `scroll`. Tests would fail. | Change all references in the plan from `scrolled` to `scroll`. Done in revision 2 below. |
| 2 | High | `launchApp` has no `launchArguments:` parameter — plan claimed otherwise. Without this, the test refactors are impossible. | Add `extraLaunchArguments: [String] = []` to both `launchApp` and `vreaderUITests_launchApp` in WI-4c's surface area. Plan revision 2 includes this. |
| 3 | Medium | Plan said `Notification.Name.debugTTSCommand` but the established convention is `debugBridgeTTSCommand` (prefix `vreader.debugBridge.*`). | Rename in plan revision 2. |
| 4 | Medium | The TTS autostart hypothesis (audio-session activation breaking in XCUITest) is unverified. If the DebugBridge URL path also fails for the same reason, WI-4c's TTS work won't unblock #40/#41. | Plan revision 2: WI-4c starts with a 30-minute spike — implement the DebugBridge URL handler skeleton + `startSpeaking` call + manual `simctl openurl` test BEFORE writing any test refactors. If TTS still doesn't start, the audit hypothesis is wrong; fall back option: ship a test-only `SpeechSynthesizing` adapter (`MockSpeechSynthesizer` that synchronously invokes the delegate callbacks for "willSpeakRange" / "didStart" / "didFinish") wired by a `--tts-test-mode` launch arg. The Mock approach weakens the test (tests a mock, not real synth) but is acceptable given CU has already verified TTS works end-to-end at the production layer (feature #26 round-2 evidence).
| 5 | Low | The plan lacks an explicit `WI-4c.spike` deliverable distinct from the eventual TTS work. | Plan revision 2 adds a "Spike-0 (~30 min)" first sub-step in WI-4c. |

**Risks accepted** (with rationale):

- The Spike-0 + fallback to Mock SpeechSynthesizing is acceptable because (a) feature #40/#41 are device-verified-orthogonal — CU already proved TTS works in production; what's being tested in XCUITest is the *wiring* (notification → highlight coordinator → UI state), which the mock exercises identically; (b) the existing `SpeechSynthesizing` protocol is already injected (see `vreader/Services/TTS/SpeechSynthesizing.swift` "Delegate forwarding: TTSService sets this to receive callbacks") so the test-only adapter is a clean swap, not a code-surgery.
- The `Notification.Name.debugBridge*` prefix rename has a knock-on cost of touching ~3 lines, accepted as cosmetic compliance with the established convention.

**Tests added or intentionally deferred**:

- `vreaderTests/App/LaunchArgParsingTests.swift` (new, ~8 cases) — added.
- `vreaderTests/Services/DebugBridge/DebugCommandTests.swift` (extend) — added.
- Spike-0 has no automated tests (it's a manual `simctl openurl` smoke check). Acceptable for a 30-min spike whose outcome dictates the rest of the WI's shape.

**Plan revision 2 (audit fixes applied)**:

1. Change all `--reader-default-layout=scrolled` → `--reader-default-layout=scroll` throughout the surface-area section.
2. Change all references to `Notification.Name.debugTTSCommand` → `Notification.Name.debugBridgeTTSCommand`.
3. Add to surface area item 4 (Feature31 test refactor): a sub-bullet "Requires `extraLaunchArguments:` parameter added to `launchApp` and `vreaderUITests_launchApp` in `vreaderUITests/Helpers/LaunchHelper.swift` (LaunchHelper change ships with this WI; do not depend on it being there)."
4. Add Spike-0 as the first sub-step of WI-4c: "Implement the `vreader-debug://tts?action=start` URL handler and the `ReaderContainerView` notification observer. Manually `simctl openurl` after opening a book in the running Sim. If `ttsService.state` transitions to `.speaking` within 5 s of the URL fire, proceed with the test refactors as planned. If TTS doesn't start, branch to the Mock fallback: implement `MockSpeechSynthesizer: SpeechSynthesizing` in `vreader/Services/TTS/` gated `#if DEBUG`, wired by a `--tts-test-mode` launch arg that swaps the production `AVSpeechSynthesizer` for the mock in `TTSService.init`. The mock's `speak(_:)` synchronously fires the delegate's `didStart` + a synthesized `willSpeakRange` for each NSRange in the utterance to keep the test signal honest."

The revision-2 corrections are accepted as the binding plan. Implementation in the next cron iteration's WI-4c starts at Spike-0.

---

## 6. Test Catalogue

### Unit Tests (run in `vreaderTests/`)

| File | Suite | What It Covers |
|------|-------|----------------|
| `vreaderTests/Verification/VerificationDebugBridgeHelperTests.swift` | `VerificationDebugBridgeHelper` | URL construction for reset/seed/settle/snapshot commands; edge cases: empty token, missing fixture name, special chars in token |
| `vreaderTests/Verification/VerificationSettingsHelperTests.swift` | `VerificationSettingsHelper` | Section-header string matching; no app launch |

### UITests (run in `vreaderUITests/`)

| File | Happy Path Method | Regression Methods |
|------|---|---|
| `Feature37PerBookSettingsVerificationTests.swift` | `verify_feature_37_perbook_settings_toggle_isolated_to_book` | `verify_feature_37_perbook_settings_persists_across_reopen` |
| `Feature34CollectionsVerificationTests.swift` | `verify_feature_34_create_collection_appears_in_sidebar` | `verify_feature_34_add_book_to_collection_filters_library` |
| `Feature11EPUBHighlightVerificationTests.swift` | `verify_feature_11_epub_highlight_happy_path` | `verify_feature_11_epub_highlight_regression_bug77_buffering_race` |
| `Feature21PaginatedModeVerificationTests.swift` | `verify_feature_21_paged_mode_shows_paged_view` | `verify_feature_21_paged_mode_page_navigation` |
| `Feature23TXTTocVerificationTests.swift` | `verify_feature_23_txt_toc_populated_for_chinese_chapters` | `verify_feature_23_txt_toc_navigation_jumps_to_chapter` |
| `Feature27ReplacementRulesVerificationTests.swift` | `verify_feature_27_replacement_rule_removes_text_from_reader` | — |
| `Feature28ChineseConversionVerificationTests.swift` | `verify_feature_28_simp_to_trad_conversion_active` | `verify_feature_28_conversion_applies_to_reader_content` (conditional) |
| `Feature29WebDAVVerificationTests.swift` | `verify_feature_29_webdav_backup_ui_available` | `verify_feature_29_webdav_backup_executes_when_configured` (conditional) |
| `Feature31AutoPageTurnVerificationTests.swift` | `verify_feature_31_auto_page_turn_advances_page` | `verify_feature_31_auto_page_turn_pauses_on_stop` |
| `Feature35AnnotationsExportVerificationTests.swift` | `verify_feature_35_export_button_triggers_share_sheet` | `verify_feature_35_import_button_is_visible` |
| `Feature36OPDSVerificationTests.swift` | `verify_feature_36_opds_catalog_ui_surface` | `verify_feature_36_opds_browse_with_local_fixture` (conditional) |
| `Feature40TTSSentenceHighlightVerificationTests.swift` | `verify_feature_40_tts_sentence_highlight_fires_callback` | `verify_feature_40_tts_sentence_highlight_callback_count_advances` |
| `Feature41TTSAutoScrollVerificationTests.swift` | `verify_feature_41_tts_autoscroll_advances_position` | `verify_feature_41_tts_autoscroll_pauses_on_stop` |

**Total test methods (UITests)**: 26 (13 happy-path + 13 regression/secondary)
**Total test methods (unit)**: ~7

---

## 7. Risks + Mitigations

### Risk 1 — Timing / flakiness in WebView-backed readers (features #11, #40, #41)

**Risk**: EPUB highlight and TTS tests rely on WKWebView rendering completing before gesture/action. Previous bugs (#77 buffering race) were timing-related.

**Mitigation**: Use `vreader-debug://settle?token=<X>` to gate on the app's own ready signal before any gesture. The settle token writes `Caches/ready-<token>.json` only after `DOMContentLoaded` + a configurable layout settle cycle. `VerificationDebugBridgeHelper.settleApp(token:timeout:)` polls for this file. Never use `Thread.sleep`.

### Risk 2 — WebDAV / OPDS server dependency

**Risk**: Tests that require a live server will fail in environments where no server is available.

**Mitigation**: All server-dependent tests call `XCTSkip("CI_WEBDAV_URL not set")` when the env var is absent. CI runs the full suite only when job-level server containers are started. Local development can run the server-independent subset without skips.

### Risk 3 — Fixture pollution between tests

**Risk**: One test's created highlight / collection / per-book setting leaks into the next test.

**Mitigation**: Every test class uses `continueAfterFailure = false` and `setUp` calls `launchApp(seed: .books, resetPreferences: true)` — this relaunches the app with an in-memory SwiftData container (not the on-disk database) and wipes known UserDefaults keys. Per-book settings files in the sandbox are written by the app under the standard documents directory — `resetPreferences: true` does NOT clear these. **AID mitigation**: features #37, #31 must call `launchApp` with a fresh app instance (relaunching clears the sandbox on simulator between runs only if the simulator's data is reset, which `--uitesting` does not do automatically). For per-book settings specifically, the test must explicitly turn off the per-book toggle in `tearDown` or use a fixture fingerprintKey that changes between runs.

**Stronger mitigation**: `setUp` should add a `vreader-debug://reset` call via `xcrun simctl openurl` *in addition to* the in-memory seed, to ensure any PerBookSettingsStore files are cleared. Document this in `VerificationDebugBridgeHelper`.

### Risk 4 — Chapter-mode vs non-chapter-mode distinctions (TXT)

**Risk**: Feature #23 (TOC) tests only exercise the non-chapter TXT path if `war-and-peace.txt` doesn't have chapter markers matching `TXTTocRuleEngine`. The fixture must be verified to contain `Chapter` / `第X章` / similar patterns.

**Mitigation**: WI-2 includes a preflight check — inspect `war-and-peace.txt` fixture to confirm chapter headers exist. If not, the test will use the fixture that feature #44 provides that is known to have chapter markers, or a dedicated TOC-test fixture is added to the bundle.

### Risk 5 — DebugSnapshot `ttsState` availability (features #40, #41)

**Risk**: Feature #49 WI-7a is needed to surface `ttsState` in `DebugSnapshot`. If it's not yet merged when WI-3 implements the feature #40 test, the snapshot-based assertion is unavailable.

**Mitigation**: WI-3 pre-checks that `DebugSnapshot` contains `ttsState`. If absent, the test uses a fallback assertion (`ttsControlBar` visible + `ttsPlayPauseButton` state = "Pause"). The stronger `sentenceHighlightCount` assertion is added in a follow-up commit once feature #49 WI-7a ships. This is explicitly noted in the PR description.

### Risk 6 — OPDS URL encoding and `resetPreferences` interaction

**Risk**: OPDS catalogs are persisted in UserDefaults under `opds.savedCatalogs`, and `--uitesting` does NOT reset UserDefaults (only SwiftData). `resetPreferences: true` wipes known keys — but OPDS catalog storage key must be included in the wipe list.

**Mitigation**: Confirm `--reset-preferences` handler in `VReaderApp.swift` includes the OPDS UserDefaults key. If not, add it in WI-3. Test launches for feature #36 pass `resetPreferences: true`.

### Risk 7 — Feature #28 CJK fixture absence

**Risk**: No CJK TXT fixture currently in the bundle. The `verify_feature_28_conversion_applies_to_reader_content` test would have nothing to convert.

**Mitigation**: The content-conversion test is marked `XCTSkip` when the fixture is absent. A CJK fixture addition request is filed as a follow-up task. The UI-surface test (picker appears and accepts selection) runs unconditionally and is sufficient for `VERIFIED` status on this feature's core claim.

### Risk 8 — Auto-page-turn interval minimum on simulator

**Risk**: Setting a 1-second auto-page-turn interval for tests may not trigger fast enough or may be too aggressive for the test runner.

**Mitigation**: Use 2 seconds as the test interval (configurable via `autoPageTurnIntervalSlider` AID once added, or `app.sliders["Auto page turn interval"]` label-match in the interim). Assert using `XCTNSPredicateExpectation` with a 10-second timeout on `readingProgressLabel` value change, not a fixed sleep. If the assertion flakes in CI, bump the interval to 3 seconds.

---

## 8. Backward Compatibility

This feature adds new test files only. No production code changes (other than three `accessibilityIdentifier` additions in `ReaderSettingsPanel.swift` which are purely additive and do not affect app behavior).

Existing tests in `vreaderUITests/` are unaffected — the new files live in `Verification/` subdirectory and do not share state or modify any helpers shared with existing tests. `LaunchHelper.swift` and `TestConstants.swift` are extended (additive only).

The CI test gate command `xcodebuild test -only-testing:vreaderUITests` continues to work; a new `only-testing:vreaderUITests/Verification` target is added without replacing the existing gate.

---

## 9. Acceptance Criteria Mapping

From `docs/features.md` Feature #45:

| Criterion | Addressed By |
|---|---|
| 13 items reach `VERIFIED`, each citing test name | 13 test files × 2+ methods; WI-4 updates tracker |
| 2 items stay manual, listed in checklist | WI-4 updates `docs/manual-test-checklist.md` |
| `xcodebuild test -only-testing:vreaderUITests/Verification` exits 0 in <8min | WI-4 CI integration + timing validation |
| Each regression test fails on pre-fix commit (RED proof) | WI-4 `dev-docs/verification-red-checks.md` |
| Checklist updated with "Auto-verified by" lines | WI-4 `docs/manual-test-checklist.md` |
| CI prints per-verification summary line | WI-4 (xcodebuild native output provides this) |
| No test uses `sleep` / `Thread.sleep` | Anti-flake invariant enforced in code review |
| Helper LOC <500; per-feature test avg ~80 LOC | Tracked during implementation; split if needed |

---

## 10. Known Limitations (to be addressed in audit)

1. **Feature #11 regression test** — the "rapid long-press before DOMContentLoaded" race (bug #77) is hard to reproduce deterministically in XCUI without a fault injection path. The test uses `vreader-debug://settle` to gate on a *settled* state, which means the happy path is exercised but the pre-settle race is only partially covered. A future improvement would add a DebugBridge command to delay DOMContentLoaded artificially.

2. **Feature #41 auto-scroll assertion** — asserting that `txtReaderContainer.value` changes (i.e., `restoredOffset:N` increases) is an indirect proxy. A direct assertion would require reading scroll offset from the UITextView, which is not exposed via accessibility value on all iOS versions. The proxy is sufficient for regression detection but could produce false-passes if the offset value changes for a reason other than TTS scroll.

3. **Feature #40 TTS assertions depend on simulator behavior** — `AVSpeechSynthesizer` on simulator fires `speakingWillBegin/didFinish` delegate callbacks but with different timing than device. The `sentenceHighlightCount` assertion via DebugSnapshot is more reliable than trying to observe live highlight changes in the WKWebView.

4. **The CJK fixture gap for feature #28** — identified and explicitly handled via `XCTSkip`. Not a blocker for `VERIFIED` status given that the picker UI assertion is sufficient.

---

---

## 11. Manual Audit Evidence (Gate 2 — Codex unavailable, manual fallback)

Codex MCP stream disconnected on first ping attempt (2026-05-13). Manual audit performed per rule 47 fallback procedure.

### Files Read

- `docs/features.md` (feature #45 plan section via `grep -A 120`)
- `docs/architecture.md` (full)
- `vreaderUITests/Helpers/LaunchHelper.swift` (full)
- `vreaderUITests/Reader/TXTHighlightGestureVerificationTests.swift` (full)
- `vreaderUITests/Helpers/TestConstants.swift` (full — all AccessibilityID constants)
- `vreaderUITests/Library/CollectionSidebarTests.swift` (head)
- `vreaderUITests/Library/OPDSCatalogListTests.swift` (head)
- `vreaderUITests/Reader/ReaderSettingsPanelTests.swift` (head)
- `vreaderTests/Services/DebugBridge/DebugFixtureCatalogTests.swift` (full)
- `vreaderTests/Services/DebugBridge/RealDebugBridgeContextTests.swift` (head)
- `vreader/Services/DebugBridge/DebugCommand.swift` (grep)
- `vreader/Views/Reader/ReaderSettingsPanel.swift` (targeted grep + sed reads)
- `vreader/Views/Reader/ReaderChromeBar.swift` (grep)
- `vreader/Views/Reader/AnnotationsPanelView.swift` (grep)
- `vreader/Views/Reader/TTSControlBar.swift` (grep)
- `vreader/Views/Reader/NativeTextPagedView.swift` (grep)
- `vreader/Views/Annotations/HighlightListView.swift` (grep)
- `vreader/Views/Annotations/AnnotationListView.swift` (grep)
- `vreader/Views/Bookmarks/TOCListView.swift` (grep)
- `vreader/Views/Library/CollectionSidebar.swift` (grep)
- `vreader/Views/LibraryView.swift` (grep)
- `vreader/Views/OPDS/OPDSCatalogListView.swift` (grep)
- `vreader/Views/Settings/WebDAVSettingsView.swift` (grep)
- `vreader/Views/Settings/SettingsView.swift` (grep)
- `vreader/Views/Settings/ReplacementRulesView.swift` (grep)

### Symbols / Signatures Verified

- All `AccessibilityID` constants in `TestConstants.swift` cross-checked against production views
- `DebugCommand` cases: `reset`, `seed`, `open`, `settle`, `snapshot`, `eval`, `theme` — confirmed
- `LaunchHelper.launchApp(seed:resetPreferences:)` — confirmed parameter names
- `ReaderSettingsPanel` sections verified: `readingModeSection` (Picker "Reading Mode"), `autoPageTurnSection` (Toggle "Auto page turn" + Slider "Auto page turn interval"), `chineseConversionSection` (Picker label "Chinese Text", accessibilityLabel "Chinese text conversion"), `perBookSection` (Toggle "Custom settings for this book")
- Replacement rules path confirmed: `settingsToolbarButton` → `settingsReplacementRules` (SettingsView, not ReaderSettingsPanel) — this was a critical plan error in v1, fixed in v2
- `nativeTextPagedView` AID confirmed in `NativeTextPagedView.swift:36`
- TTS AIDs confirmed: `ttsPlayPauseButton`, `ttsStopButton`, `ttsControlBar`, `ttsSpeedSlider`
- Collection AIDs confirmed: `collectionsToolbarButton`, `newCollectionButton`, `newCollectionTextField`, `addCollectionButton`, `filterAllBooks`, `filterDoneButton`
- OPDS AIDs confirmed: `opdsCatalogsToolbarButton`, `opdsEmptyState`, `opdsCatalogList`, `opdsAddCatalog`, `opdsCatalogNameField`, `opdsCatalogURLField`, `opdsCatalogSaveButton`
- Annotation AIDs confirmed: `annotationsExportButton`, `annotationsImportButton`, `annotationsPanelSheet`, `highlightEmptyState`
- WebDAV AIDs confirmed: `webdavServerURL`, `webdavTestButton`, `webdavSaveButton`, `webdavBackupNowButton`, `webdavBackupErrorText`
- TOC AIDs confirmed: `tocEmptyState`, `tocRow-<id>`
- `settingsToolbarButton`, `settingsView`, `settingsDoneButton`, `settingsReplacementRules` confirmed in `SettingsView.swift` and `LibraryView.swift`
- `readerTTSButton` confirmed in `ReaderChromeBar.swift:55` (id: "readerTTSButton")

### Findings Fixed (v1 → v2)

| Severity | Finding | Fix Applied |
|---|---|---|
| **High** | Feature #27 test described path through `readerSettingsPanel` — WRONG. Replacement rules are in global `SettingsView` (`settingsReplacementRules`). | Rewrote Feature27 test description with correct path. Updated Modified Files table. Changed AID gap from `replacementRulesSection` in ReaderSettingsPanel to `replacementRulesAddButton` in ReplacementRulesView. |
| **Medium** | Chinese conversion picker described with label "Chinese Conversion" — actual label is "Chinese Text", accessibilityLabel is "Chinese text conversion". | Corrected picker label + access pattern in Feature28 section. Added note that picker is disabled unless format + mode supports it; test must use Unified mode. |
| **Low** | AID gap table listed `autoPageTurnIntervalStepper` — UI is a Slider, not a Stepper. | Corrected to `autoPageTurnIntervalSlider`. |
| **Low** | AID gap table listed `replacementRulesSection` in wrong file. | Corrected per High finding above. |

### Edge Cases Checked

- Fixture availability: `war-and-peace.txt`, `mini-epub3.epub`, `mini-azw3.azw3` confirmed in `DebugFixtureCatalog.all()`; no CJK TXT fixture — documented as fixture gap for feature #28
- `resetPreferences: true` effect on OPDS UserDefaults key — flagged as risk #6 with mitigation
- Auto-page-turn on simulator timing — flagged as risk #8 with 2-second interval recommendation
- Feature #40 `ttsState` snapshot dependency on feature #49 WI-7a — flagged as risk #5 with fallback
- ChineseConversionDisableReason gate: picker disabled for native mode / non-unified formats — documented in Feature28 test notes

### Risks Accepted (with rationale)

- Feature #11 regression test cannot perfectly replicate the bug #77 pre-settle race (deterministic fault injection not available) — accepted because the settle-gated happy path still exercises the fixed code path.
- Feature #41 uses `restoredOffset` proxy for TTS scroll assertion — accepted as sufficient for regression detection.
- CJK fixture absence for feature #28 content test — accepted with `XCTSkip` + fixture-request follow-up.

*End of Gate 1 Plan — v2 (manual audit complete)*

---

## WI-4c-b Spike-0 verdict (2026-05-13)

**PASS.** The `vreader-debug://tts?action=start` URL drove `AVSpeechSynthesizer` to active speech under the same iOS Simulator (iPhone 17 Pro, iOS 26.5) configuration that XCUITest would run against.

**What was exercised:**
- Built app installed to booted sim via `xcrun simctl install`.
- Launched with `--seed-md-toc --reset-preferences` → MD book ("Test Markdown TOC") present in library.
- Tapped book → reader opened (MD paged renderer, light theme).
- Fired `xcrun simctl openurl booted "vreader-debug://tts?action=start"`.

**Observed (3 s after URL fire):**
- Yellow word-highlight band painted at the current TTS offset → `willSpeakRangeOfSpeechString` delegate callback fired → synthesizer is actively speaking.
- `TTSControlBar` appeared at the bottom of the reader → `ttsService.state != .idle`.
- Page advanced from 0% to ~27% by the time the stop URL was fired → real audio session activated and read through.

**Stop URL also works:**
- Fired `vreader-debug://tts?action=stop`.
- TTSControlBar disappeared, highlight band cleared → `ttsService.state == .idle` again.

**Evidence:**
- `dev-docs/verification/artifacts/feature-45-wi-4c-b-tts-start-spike0-20260513.png`
- `dev-docs/verification/artifacts/feature-45-wi-4c-b-tts-stop-spike0-20260513.png`

**Implications for WI-4c-b:**
- The Mock `SpeechSynthesizing` fallback (revision-2 fallback) is NOT needed for Feature #40 / #41 verification — production audio path is XCUITest-reachable via this URL after all.
- Feature #40 test refactor: open book → `vreader-debug://tts?action=start` → wait for control bar → snapshot. The remaining gap is wiring `ttsState` / `ttsOffsetUTF16` into `RealDebugBridgeContext+Snapshot.swift` (currently hardcoded nil; Feature #40 risk #5 in the plan). That's a follow-up WI in this same plan, not a spike outcome.
- Feature #41 test refactor: open book → start TTS → assert TTSControlBar XCUI element exists.

**Branch:** `feat/45-wi-4c-b-tts-debugbridge`. RED→GREEN complete:
- 4 new parser tests in `DebugCommandTests` (start, stop, missing, invalid) — all passing.
- `RealDebugBridgeContext.tts(action:)` posts `.debugBridgeTTSCommand`.
- `ReaderContainerView` observer calls `startTTS()` / `ttsService.stop()` based on action.
- Mock `DebugBridgeContext` conformers (Slow, Recording) updated with `tts` stub for compile.
- Total diff: 117 lines added across 7 files. No deletions. File-size budget intact (all files <300 lines).

---

## WI-4c-c — TTS snapshot wiring (2026-05-13)

### Problem

WI-4c-b proved `vreader-debug://tts?action=start` drives the production AVSpeechSynthesizer. But the harness can't yet *assert* on TTS state from a snapshot: `RealDebugBridgeContext+Snapshot.swift` currently hardcodes `ttsState: nil` and `ttsOffsetUTF16: nil` (the DebugSnapshot init defaults them to nil; the call site doesn't pass them in). This blocks Feature #40's "TTS playback verified by snapshot" assertion path — the XCUITest run can fire `tts?action=start` and wait for the TTSControlBar element to appear, but a state-driven test (e.g., "snapshot 1.5s after start has ttsState=speaking and an offset that has moved past 0") needs the snapshot to actually carry those fields.

### Scope (this WI)

- `vreader/Services/DebugBridge/DebugReaderProbeAdapter.swift`: add optional `ttsProbe: (@MainActor () -> (state: String, offsetUTF16: Int?))?` closure; override the protocol's default `currentTTSState` / `currentTTSOffsetUTF16` to delegate to the closure when set.
- `vreader/Views/Reader/ReaderContainerView.swift` (DEBUG `.onAppear`): wire `probe.ttsProbe = { (ttsService.state.publicName, ttsService.state == .idle ? nil : ttsService.currentOffsetUTF16) }`. Closure captures the SwiftUI-owned `ttsService` (which is `@MainActor @Observable`) — safe because the closure runs `@MainActor` on snapshot evaluation.
- `vreader/Services/DebugBridge/RealDebugBridgeContext+Snapshot.swift`: pass `probe?.currentTTSState` and `probe?.currentTTSOffsetUTF16` into the `DebugSnapshot.init`; update the `partial` array to mark `ttsState` and `ttsOffsetUTF16` partial when the probe doesn't supply them (no probe at all, or the probe is from a host that never wires the closure).

**OUT of scope:**
- Wiring `settingsProvenance` (the third v2 field) — feature #50 owns the per-format settings provenance signal.
- Wiring `currentRenderPhase` overrides per format — feature #50 territory.
- Updating the Foliate/EPUB hosts to register their own `DebugReaderProbe` types — those still use the adapter via `ReaderContainerView`; per-format probe classes are feature #50.

### Prior art / project precedent

- `DebugReaderProbeAdapter.positionProvider` (existing closure pattern) — exact precedent for "view-owned state delivered via @MainActor closure to a DEBUG probe."
- `TTSService.State.publicName` extension (already shipped in feature #49 WI-1, lives in `DebugReaderRegistry.swift` line 84-92) — the mapping from State enum to wire value already exists; this WI just calls into it.
- `DebugSnapshot.TTSStateValue` constants (already shipped) — wire values already pinned at `idle`/`speaking`/`paused`.
- `DebugReaderProbe` default impls returning nil (already shipped) — the protocol surface is already defined; this WI just provides a real implementation through the closure.

### Work-item sequencing

Single WI. Three files modified (adapter, ReaderContainerView, snapshot extension) + tests added to `RealDebugBridgeContextSnapshotTests` (or equivalent). Estimated PR size: ~80-120 lines added.

### Test catalogue

- `DebugReaderProbeAdapterTests` (new file or appended): `currentTTSState_isNilByDefault`, `currentTTSState_returnsClosureValue`, `currentTTSOffsetUTF16_isNilByDefault`, `currentTTSOffsetUTF16_returnsClosureValue` — pure unit tests, no app state.
- `RealDebugBridgeContextSnapshotTests` (appended): one test that wires a `DebugReaderProbeAdapter` with a `ttsProbe` returning `("speaking", 42)`, registers it, runs `snapshot`, decodes the file, asserts `ttsState == "speaking"` && `ttsOffsetUTF16 == 42` && `partial` does NOT contain `ttsState` / `ttsOffsetUTF16`. Second test for the inverse: no `ttsProbe` set → `ttsState == nil` && `ttsOffsetUTF16 == nil` && `partial` DOES contain both.

### Risks + mitigations

- **Risk**: closure captures `ttsService` strongly via `[ttsService]` or implicit capture, holding the SwiftUI @State value past view dismiss. **Mitigation**: `ReaderContainerView`'s `.onDisappear` already calls `DebugReaderRegistry.shared.unregister(probe)` and clears `debugProbe = nil`. The probe is the closure's only retainer; when the probe drops, the closure drops, and `ttsService` releases naturally. No new lifecycle work needed.
- **Risk**: closure runs after view dismissal if a `snapshot` URL fires concurrently. **Mitigation**: the probe is `weak` in the registry; once unregistered, `current` returns nil and the snapshot path skips the closure entirely.
- **Risk**: `ttsService.currentOffsetUTF16` is `0` while idle (not nil), so unconditionally returning it would mislead consumers. **Mitigation**: condition on `state == .idle ? nil : ttsService.currentOffsetUTF16`. When state is `.idle`, offset is meaningless → wire as nil.

### Backward compat

- `DebugSnapshot` already accepts v1 archives (decoder defaults the v2 fields to nil per the existing `init(from:)`). No schema bump.
- Existing consumers that don't read `ttsState` / `ttsOffsetUTF16` are unaffected.

### Acceptance criteria

1. `DebugReaderProbeAdapter` exposes a `ttsProbe` closure; default-nil leaves the protocol's default-nil behavior in place.
2. `ReaderContainerView.onAppear` wires the closure when DEBUG.
3. `RealDebugBridgeContext+Snapshot.swift` passes the probe's TTS fields into `DebugSnapshot.init`; `partial` reflects which fields are present.
4. Unit tests cover both the with-closure and without-closure paths.
5. `xcodebuild test -only-testing:vreaderTests` green.

### Manual Audit Evidence (Gate 2, 2026-05-13)

Codex MCP unavailable this session (`stream disconnected before completion` on every call all day). Manual fallback per rule 47.

**Files read:**
- `vreader/Services/DebugBridge/DebugReaderProbeAdapter.swift` (full)
- `vreader/Services/DebugBridge/DebugReaderRegistry.swift` (full, incl. `TTSService.State.publicName` extension)
- `vreader/Services/DebugBridge/DebugSnapshot.swift` (full, incl. v2 init + decoder)
- `vreader/Services/DebugBridge/RealDebugBridgeContext+Snapshot.swift` (full)
- `vreader/Views/Reader/ReaderContainerView.swift` lines 320-400 (onAppear/onDisappear probe wiring) + grep for ttsService access
- `vreader/Services/TTS/TTSService.swift` lines 1-180 (state, currentOffsetUTF16, lifecycle)
- `vreaderTests/Services/DebugBridge/RealDebugBridgeContextTests.swift` lines 373-490 (existing snapshot tests)

**Symbols / signatures verified:**
- `TTSService` is `@MainActor @Observable` with `private(set) var state: State`, `private(set) var currentOffsetUTF16: Int` (both @MainActor-isolated). ✓
- `TTSService.State.publicName` extension exists at `DebugReaderRegistry.swift:84-92`, maps `.idle` → `"idle"`, `.speaking` → `"speaking"`, `.paused` → `"paused"`. ✓
- `DebugSnapshot.init` accepts `ttsState: String? = nil, ttsOffsetUTF16: Int? = nil, settingsProvenance: String? = nil` as the last three params (defaulted). ✓
- `DebugReaderProbe` declares `currentTTSState: String? { get }` and `currentTTSOffsetUTF16: Int? { get }` with default impls returning nil at `DebugReaderRegistry.swift:74-79`. ✓
- `DebugReaderProbeAdapter` has `positionProvider` and `jsEvaluator` closures as exact prior art — same `@MainActor` capture pattern. ✓
- `ReaderContainerView.onDisappear` already calls `DebugReaderRegistry.shared.unregister(probe); debugProbe = nil` — the lifecycle is sound. ✓

**Edge cases checked:**
- `ttsService.currentOffsetUTF16 = 0` on `.idle` (verified at `TTSService.swift:146`). My `state == .idle ? nil : currentOffsetUTF16` correctly maps this to nil. ✓
- `.paused` state — offset is meaningful (mid-read). My condition correctly keeps offset for `.paused` (not equal to `.idle`). ✓
- No probe registered → `probe == nil` branch in snapshot. Need to add `ttsState`/`ttsOffsetUTF16` to that branch's partial list. ✓ (added to TDD test catalog)
- Probe registered but no `ttsProbe` closure → protocol defaults return nil → fields go to partial. ✓
- Snapshot fires after view dismiss → registry returns nil → no closure invoked. ✓

**Audit-driven additions (incorporated into plan):**

1. **Critical — existing snapshot tests will break**: `test_snapshot_withoutActiveReader_listsReaderFieldsAsPartial` asserts `Set(["currentBookId", "format", "position", "selection"])` exactly; `test_snapshot_withActiveReader_populatesReaderFieldsAndShrinksPartial` asserts `Set(["selection", "position"])`; `test_snapshot_withActiveReaderAndPosition_propagatesPosition` (line 451) asserts similar. ALL THREE need updating when ttsState/ttsOffsetUTF16 join partial. Adding to acceptance criterion 4: "existing snapshot partial-set assertions updated to reflect ttsState/ttsOffsetUTF16 inclusion when not wired."

2. **Medium — partial-array logic for no-probe branch**: when `probe == nil`, both new fields are nil and must join partial. Add to the `if probe == nil` branch at `RealDebugBridgeContext+Snapshot.swift:42`.

3. **Medium — partial-array logic for probe-without-closure branch**: when `probe != nil` but `probe.currentTTSState == nil` (the adapter's `ttsProbe` is unset), the fields are still nil. Need new conditional branches: `if probe?.currentTTSState == nil { partial.append("ttsState") }` and same for offset.

4. **Low — `settingsProvenance` triple**: the v2 schema has three new fields; this WI wires only two. The third (`settingsProvenance`) stays nil and must also be in `partial` (matching the documented intent). However, that's out of scope; per "files OUT of scope" the third field is feature #50 territory. Resolution: add `settingsProvenance` to partial unconditionally in this WI (since no probe path supplies it yet) — that's a cheap addition that keeps the partial array honest and avoids needing another WI to add a one-liner later.

**Risks accepted:**
- `settingsProvenance` always partial after this WI. Accepted: feature #50 will provide the real signal. Partial array correctly tells consumers "this field is not yet populated by any path."

**Tests intentionally deferred:**
- None.

**Verdict:** ship-as-is (with the three audit-driven additions folded into the plan above). Acceptance criteria updated below.

**Acceptance criteria (post-audit, revised):**

1. `DebugReaderProbeAdapter` exposes a `ttsProbe: (@MainActor () -> (state: String, offsetUTF16: Int?))?` closure; default-nil leaves the protocol's default-nil behavior in place.
2. `ReaderContainerView.onAppear` (DEBUG only) wires the closure to `ttsService`.
3. `RealDebugBridgeContext+Snapshot.swift` passes `probe?.currentTTSState`, `probe?.currentTTSOffsetUTF16` into `DebugSnapshot.init`; `partial` array correctly reflects which v2 fields are unwired (no-probe, probe-without-closure, settingsProvenance always partial).
4. New unit tests cover (a) `DebugReaderProbeAdapter.currentTTSState/Offset` with and without `ttsProbe` set; (b) snapshot with a probe whose `ttsProbe` returns `("speaking", 42)` populates the fields and removes them from partial; (c) snapshot with a probe but no `ttsProbe` keeps fields nil and lists them in partial.
5. Existing snapshot tests (`test_snapshot_withoutActiveReader_*`, `test_snapshot_withActiveReader_*`, `test_snapshot_withActiveReaderAndPosition_*`) updated for the new partial-array members.
6. `xcodebuild test -only-testing:vreaderTests` green.


---

## WI-4d — Refactor Feature40/41 XCUITest verification to use DebugBridge TTS URL (2026-05-14)

### Problem

WI-4c-b shipped `vreader-debug://tts?action=start` (the URL handler that drives
the production AVSpeechSynthesizer in a way XCUITest can reach), and WI-4c-c
wired `ttsState`/`ttsOffsetUTF16` into `DebugSnapshot`. The remaining work is
to actually USE these in the XCUITest verification tests for features #40 and
#41, which still XCTSkip on the `ttsButton.tap()` path because AVSpeechSynthesizer
won't activate its audio session under XCUITest's runner-test split.

Both tests currently flow: tap reader → `ttsButton.tap()` → wait 30s for
`ttsControlBar` → XCTSkip when it never appears. After this WI the flow becomes:
tap reader → fire `vreader-debug://tts?action=start` → wait 5s for
`ttsControlBar` → snapshot to confirm `ttsState == "speaking"` and
`ttsOffsetUTF16 > 0`.

### Scope

1. `vreaderUITests/Verification/Helpers/VerificationDebugBridgeHelper.swift`:
   add `func ttsAction(_ action: String)` method that fires
   `vreader-debug://tts?action=<action>` (mirrors `seedFixture`/`settleApp`
   shape). Add `DebugCommand.ttsURL(action:)` static helper.
2. `vreaderUITests/Verification/Feature40TTSSentenceHighlightVerificationTests.swift`:
   replace `ttsButton.tap()` path with `bridgeHelper.ttsAction("start")`.
   Drop the AVSpeech XCTSkip. Reduce control-bar timeout from 30s to 5s
   (the URL path is synchronous; the bar appears within ~1s once the URL
   fires per WI-4c-b spike-0).
3. `vreaderUITests/Verification/Feature41TTSAutoScrollVerificationTests.swift`:
   same refactor pattern.

**Files OUT of scope:**

- `Feature31AutoPageTurnVerificationTests.swift` — already refactored in
  WI-4c-a to use `LaunchArgs.readerLayoutPaged`. Its remaining XCTSkip is
  a defensive fallback for "section not present" — out of scope to touch.
- Production code (DebugCommand, ReaderContainerView observer) — already
  shipped in WI-4c-b.
- `RealDebugBridgeContext+Snapshot.swift` and `DebugReaderProbeAdapter.swift`
  — already shipped in WI-4c-c.
- TTS-stop test paths — feature #40/#41 acceptance criteria don't require
  testing stop; existing tests don't exercise it.

### Prior art / project precedent

- `seedFixture(named:)` and `settleApp(token:)` in `VerificationDebugBridgeHelper`
  — exact precedent for "fire-and-observe" URL helper methods. `ttsAction`
  follows the same shape.
- WI-4c-b's `DebugCommand.parse` already accepts `action=start|stop` and
  routes through `.debugBridgeTTSCommand`; consumer side is wired.
- WI-4c-b spike-0 verified the URL drives real AVSpeech successfully under
  the same iOS Simulator XCUITest would use.

### Work-item sequencing

Single WI. 3 files modified (helper + 2 tests). PR size: ~60-80 LOC.

### Test catalogue

- `Feature40TTSSentenceHighlightVerificationTests.verify_feature_40_tts_state_reported_after_start`:
  RED (pre-WI-4d): XCTSkips on AVSpeech session. GREEN: asserts
  `snapshot["ttsState"] != "idle"` within 5s of firing the URL.
- `Feature40TTSSentenceHighlightVerificationTests.verify_feature_40_tts_offset_advances_during_playback`:
  same RED→GREEN; the offset-advancement check now actually runs.
- `Feature41TTSAutoScrollVerificationTests.verify_feature_41_tts_control_bar_visible_during_playback`:
  RED→GREEN.
- `Feature41TTSAutoScrollVerificationTests.verify_feature_41_tts_autoscroll_position_advances`:
  RED→GREEN.

No new unit tests — `DebugCommand.parse` for `tts?action=start` is already
covered by `DebugCommandTests` (WI-4c-b shipped 4 cases).

### Risks + mitigations

- **Risk**: the test app launches `--reset-preferences` so any pre-existing
  TTS provider config is wiped. `startTTS()` may surface a provider-selection
  sheet on first activation. **Mitigation**: the spike-0 path used the URL
  AFTER the reader was loaded; that code path goes through `startTTS()` which
  reads `ttsService` directly. The provider-selection sheet was a finding
  about the BUTTON-tap path going through a different flow. The URL path
  bypasses that. If the test still fails, the symptom would be "URL fires
  but ttsControlBar never appears" — we'd then need to investigate the
  observer side. Spike-0 evidence suggests this won't reproduce.
- **Risk**: AccessibilityID.ttsControlBar may rename. **Mitigation**:
  AccessibilityID is the single source of truth used across production and
  tests; refactoring would propagate automatically.
- **Risk**: XCUITest's container-path lookup may break post-launch.
  **Mitigation**: `VerificationDebugBridgeHelper.appDataContainerPath()`
  is already used by all snapshot reads; this WI doesn't change that path.

### Backward compat

- All changes are additive (one new helper method) or test-only refactors.
- No production-code change.

### Edge cases

- TTS already speaking (idempotent start): `ttsService.startSpeaking` is
  guarded by `state != .idle` in production. The URL handler calls
  `startTTS()` which reads `ttsService.state` first. No double-start.
- URL fires before reader has loaded the book: spike-0's reader-tap pattern
  is preserved (`tapFirstBook` + `waitForExistence(readerBackButton)`)
  before firing the URL.

### Gate

- `xcodebuild test -only-testing:vreaderUITests/Feature40TTSSentenceHighlightVerificationTests`
  passes without XCTSkip (both methods).
- `xcodebuild test -only-testing:vreaderUITests/Feature41TTSAutoScrollVerificationTests`
  passes without XCTSkip (both methods).
- `xcodebuild test -only-testing:vreaderTests` stays green (unit test
  surface unchanged).

### Acceptance criteria

1. `VerificationDebugBridgeHelper.ttsAction(_:)` method exists; fires
   `vreader-debug://tts?action=<action>` via `xcrun simctl openurl booted`.
2. `DebugCommand.ttsURL(action:)` static helper constructs the URL.
3. Feature40 + Feature41 tests use `bridgeHelper.ttsAction("start")`
   instead of `ttsButton.tap()`.
4. Both tests' `XCTSkip` branches for AVSpeech audio session are removed
   (the defensive `Reader TTS button not present` skip stays — that's a
   genuine accessibility surface check).
5. Control-bar timeout reduced 30s → 5s.
6. Both XCUITest verification tests pass without XCTSkip on iPhone 17 Pro Sim.

### Gate 2 — Independent audit (manual fallback)

Codex MCP unavailable this session (`stream disconnected before completion`
across the day). Manual fallback per rule 47.

**Files read:**
- `vreaderUITests/Verification/Helpers/VerificationDebugBridgeHelper.swift`
  (full, 200 lines)
- `vreaderUITests/Verification/Feature40TTSSentenceHighlightVerificationTests.swift`
  (full, 153 lines)
- `vreaderUITests/Verification/Feature41TTSAutoScrollVerificationTests.swift`
  (full)
- `vreader/Services/DebugBridge/DebugCommand.swift` (already includes
  the `tts(action:)` case from WI-4c-b, lines 130-145)
- `vreader/Views/Reader/ReaderContainerView.swift` (already observes
  `.debugBridgeTTSCommand` from WI-4c-b)

**Symbols verified:**
- `xcrun simctl openurl booted <url>` is the same mechanism `seedFixture`
  uses — proven to work for DebugBridge URLs in WI-4c-b spike-0. ✓
- `DebugCommand.parse("vreader-debug://tts?action=start")` returns
  `.tts(action: "start")` — verified in `DebugCommandTests` (WI-4c-b). ✓
- `AccessibilityID.ttsControlBar` is the canonical identifier used by
  `TTSControlBar.swift` and current tests. ✓

**Edge cases checked:**
1. URL fires before book reader loads → existing tests already wait on
   `readerBackButton.waitForExistence(timeout: 15)` before any action. ✓
2. URL fires twice (test reruns): production `startTTS()` is idempotent
   on `state != .idle`. ✓
3. Test setup `--reset-preferences` wipes any TTS-provider state: the URL
   path doesn't depend on user-config; uses default AVSpeech. ✓
4. Helper method missing the URL construction: `DebugCommand.ttsURL` is
   a new static func; covered by RED step (writing the test before the
   helper).

**Risks accepted:**
- None Critical/High. Single risk Low: the 5s control-bar timeout may be
  slightly aggressive for slow CI runners; production URL fires within
  1s per spike-0, so 5s has 5× headroom.

**Verdict:** ship-as-is. WI is mechanical refactor that follows existing
helper patterns and is gated by clear XCUITest assertions.

### WI-4d outcome (2026-05-14) — PARTIAL

**Shipped:** `VerificationDebugBridgeHelper.ttsAction(_:)` + `DebugCommand.ttsURL(action:)`. Clean abstraction parallel to `seedFixture` / `settleApp` / `snapshotApp`. Compiles, doesn't change any test behavior on its own.

**Deferred:** the Feature40/41 test refactors. Investigation revealed an
infrastructure blocker that's broader than WI-4d's scope:

**Blocker — simctl-from-XCUITest-runner-sandbox URL delivery is unreliable.**
The VerificationDebugBridgeHelper.send() method spawns `/usr/bin/xcrun simctl
openurl booted <url>` via posix_spawn. But `/usr/bin/xcrun` is on the host
Mac filesystem, not inside the iOS Simulator sandbox where the XCUITest
runner-app runs. posix_spawn from the runner sandbox can't reach the host
binary, so the URL never fires.

Evidence:
1. Manual repro from a Mac terminal (outside XCUITest) — TTS URL delivers
   successfully (`ttsState: "speaking"` in post-fire snapshot, confirmed
   in this session 2026-05-14 ~02:48).
2. XCUITest test using `bridgeHelper.ttsAction("start")` — no app behavior
   observed; `ttsControlBar.waitForExistence(timeout: 5)` fails.
3. Other tests that use `bridgeHelper.settleApp` happen to also have a
   fallback `waitForExistence` on a non-settle UI element, so the settle
   failure is masked — they appear to pass without proving simctl URL
   delivery from sandbox actually works.

This is a foundational infrastructure problem that affects ALL XCUITest
verification tests that try to drive DebugBridge URLs from inside the
test. It's broader than WI-4d, and fixing it requires one of:

- **(a)** Move simctl invocations to the host side via a pre-test script
  + IPC mechanism (XCTAttachment, a shared file watcher). Significant
  infrastructure work.
- **(b)** Replace simctl with an in-app URL-firing mechanism (e.g., a
  test-only HTTP endpoint inside the test app that the runner POSTs to,
  bridging back to the DebugBridge URL handler).
- **(c)** Mock `AVSpeechSynthesizer` via a test-only `SpeechSynthesizing`
  adapter (the original WI-4c plan's fallback option). Bypasses the
  URL-delivery question entirely.

Acting on any of these is a separate WI (likely a feature-class one).
Out of scope for this iteration.

**Status:** Feature #45 IN PROGRESS. Helper method shipped. Feature40/41
test refactors deferred to WI-4e (TBD) pending the simctl-from-sandbox
investigation. Both test files reverted to their pre-WI-4d state (still
XCTSkip on AVSpeech audio session). Helper method is harmless (additive
only) and unblocks future work once the routing question is resolved.

**Acceptance criteria (revised):**

1. ~~Feature40 + Feature41 tests use `bridgeHelper.ttsAction("start")` instead of `ttsButton.tap()`~~ — DEFERRED
2. ~~Both XCUITest verification tests pass without XCTSkip~~ — DEFERRED
3. `VerificationDebugBridgeHelper.ttsAction(_:)` method exists, compiles, follows the established fire-and-observe helper pattern — DONE
4. `DebugCommand.ttsURL(action:)` static helper constructs the URL — DONE
5. `xcodebuild build-for-testing` succeeds — DONE

---

## WI-4e — Mock SpeechSynthesizer for XCUITest TTS verification (2026-05-14)

**Type**: Foundational (production-target DEBUG-only test adapter + launch arg) + Behavioral (Feature40/41 XCUITest unskip).
**PR size estimate**: ~150 LOC.

**Why this WI exists** — WI-4d shipped the helper (`bridgeHelper.ttsAction(_:)` + `DebugCommand.ttsURL(action:)`) but couldn't ship the actual Feature40/41 unskip because of two stacked blockers:

1. **Real `AVSpeechSynthesizer` doesn't transition to speaking under XCUITest headless** on iPhone 17 Pro Sim, even when the production code path is exercised via real button tap. CU device-verified TTS at the production layer (Feature #26 round-2, 2026-05-09); the synth-stuck behavior is XCUITest-specific.
2. **`simctl openurl` from inside the XCUITest runner sandbox is unreliable** for URL delivery to the host app: `/usr/bin/xcrun` is on the host Mac filesystem, not the iOS sim sandbox where the runner app's posix_spawn executes. So firing `vreader-debug://tts?action=start` from `VerificationDebugBridgeHelper.send()` inside the runner does not reliably reach the running app's URL handler.

WI-4e adopts the WI-4c plan v2's documented FALLBACK (Finding #4 mitigation, plan line 645): swap the production `AVSpeechSynthesizer` for a deterministic DEBUG-only mock under a `--tts-test-mode` launch arg. The mock fires `AVSpeechSynthesizerDelegate` callbacks on a synthetic timeline so that `ttsState` transitions to `.speaking` and `ttsOffsetUTF16` advances without real audio. This bypasses BOTH blockers above:

- Blocker (1) is bypassed: the mock doesn't depend on AVSpeechSynthesizer's audio session.
- Blocker (2) is bypassed: tests tap the real `readerTTSButton` (a normal SwiftUI Button that dispatches taps fine under XCUITest, unlike segmented Pickers) — no URL fire needed for the start action.

**Surface area** — file-by-file with concrete signatures:

1. `vreader/Services/TTS/XCUITestMockSpeechSynthesizer.swift` (new, `#if DEBUG`-wrapped):
   - `final class XCUITestMockSpeechSynthesizer: NSObject, SpeechSynthesizing`.
   - `weak var delegateTarget: AVSpeechSynthesizerDelegate?` and `let probeSynth = AVSpeechSynthesizer()` (used only as the `_ synthesizer:` parameter passed to delegate callbacks — never has `speak()` called on it).
   - `private var currentTask: Task<Void, Never>?` so `stopSpeaking()` cancels in-flight callbacks.
   - `var isSpeaking` / `var isPaused` mutable Bools updated by speak/pause/continue/stop.
   - `speak(_ utterance:)`:
     - Set `isSpeaking = true`.
     - Spawn `currentTask = Task { @MainActor [weak self] in ... }`.
     - The task: extracts text length from `utterance.speechString`, fires N synthetic `willSpeakRangeOfSpeechString` callbacks spaced ~250ms apart (N ≤ 10, sliced evenly across the text length), then fires `didFinish` and sets `isSpeaking = false`.
     - All callbacks invoke `delegateTarget?.speechSynthesizer(probeSynth, willSpeakRangeOfSpeechString:utterance:)` etc.
     - If cancelled (via `stopSpeaking`), the task fires `didCancel` instead of `didFinish` and exits early.
   - `pauseSpeaking()` → just flip `isPaused`/`isSpeaking`; no delegate callback (matches real synth behavior: pause doesn't fire didCancel).
   - `continueSpeaking()` → flip flags back; the task continues unaffected (acceptable simplification — the real synth has gaps, the mock just keeps ticking).
   - `stopSpeaking()` → cancel `currentTask`, set flags, fire `didCancel` on a fresh `Task @MainActor`.

2. `vreader/Services/TTS/SpeechSynthesizing.swift`:
   - Add `#if DEBUG`-wrapped `enum TTSTestOverride { @MainActor static var useMockSynthesizer: Bool = false }`.
   - The flag is the single source of truth for whether `TTSService` should pick the mock at construction time. It is NOT exposed outside DEBUG.

3. `vreader/Services/TTS/TTSService.swift`:
   - Change the `init(synthesizerFactory:)` DEFAULT factory from `{ SystemSpeechSynthesizer() }` to `{ Self.defaultSynthesizer() }` where:
     ```swift
     @MainActor
     private static func defaultSynthesizer() -> SpeechSynthesizing {
         #if DEBUG
         if TTSTestOverride.useMockSynthesizer {
             return XCUITestMockSpeechSynthesizer()
         }
         #endif
         return SystemSpeechSynthesizer()
     }
     ```
   - Update the delegate-wiring branch at line 58-60 to also handle the mock:
     ```swift
     if let system = synthesizer as? SystemSpeechSynthesizer {
         system.delegateTarget = self
     }
     #if DEBUG
     else if let mock = synthesizer as? XCUITestMockSpeechSynthesizer {
         mock.delegateTarget = self
     }
     #endif
     ```
   - No change to the existing `AVSpeechSynthesizerDelegate` extension; it already operates on the synthesizer-agnostic state writes.

4. `vreader/App/VReaderApp.swift`:
   - `TestLaunchConfig` struct: add `let ttsTestMode: Bool`.
   - `TestLaunchConfig.parse`: add `args.contains("--tts-test-mode")` → `ttsTestMode`.
   - `TestLaunchConfig.none`: add `ttsTestMode: false`.
   - In the existing `#if DEBUG` early-setup block (around line 90-156): if `config.ttsTestMode`, set `TTSTestOverride.useMockSynthesizer = true` BEFORE any view body is evaluated (so the first `TTSService()` call inside `ReaderContainerView`'s `@State` initializer picks up the override).

5. `vreaderUITests/Verification/Feature40TTSSentenceHighlightVerificationTests.swift`:
   - `setUpWithError`: replace `launchApp(seed: .warAndPeace, resetPreferences: true)` with `launchApp(seed: .warAndPeace, resetPreferences: true, extraLaunchArguments: ["--tts-test-mode"])`.
   - `openReaderAndStartTTS()`: tighten timeout from 30s to 8s on `controlBar.waitForExistence` (mock fires `didStart` immediately). Drop the XCTSkip rationale that cites audio session unavailability.
   - Both `verify_*` test methods: drop their XCTSkip fallback paths; the snapshot's `ttsState` should now reliably read non-idle.

6. `vreaderUITests/Verification/Feature41TTSAutoScrollVerificationTests.swift`:
   - Same as #5.

7. `vreaderTests/Services/TTS/XCUITestMockSpeechSynthesizerTests.swift` (new):
   - `@Suite("XCUITestMockSpeechSynthesizer")`.
   - Test: `speak fires didStart immediately` — assert `delegateTarget.didStartCount == 1` within 100ms.
   - Test: `speak fires willSpeakRange multiple times across utterance` — assert at least 2 callbacks within 1.5s.
   - Test: `speak ends with didFinish when allowed to complete` — assert didFinish fires within 3s, isSpeaking flips to false.
   - Test: `stopSpeaking fires didCancel and cancels remaining willSpeakRange` — assert didCancel fires, no more willSpeakRange after stop.
   - Test: `speak twice cancels first utterance` — assert first task fires didCancel.

8. `vreaderTests/App/TestLaunchConfigTests.swift` (extend or create):
   - Test: `parse(arguments: ["--tts-test-mode"]) returns config with ttsTestMode == true`.
   - Test: `parse(arguments: []) returns config with ttsTestMode == false`.

**Prior art / project precedent / rejected alternatives**:

- **Precedent**: `SpeechSynthesizing` protocol already exists in `vreader/Services/TTS/SpeechSynthesizing.swift` (lines 22-30) with `SystemSpeechSynthesizer` as the production adapter (lines 41-72). `TTSService.init(synthesizerFactory:)` already accepts an injected factory (line 53). Unit tests in `vreaderTests/Services/TTSServiceTests.swift` already construct with `MockSpeechSynthesizer` (a different, simpler mock that lives in the test target). WI-4e extends this DI plumbing into the production target, gated `#if DEBUG`, for XCUITest scenarios.
- **Precedent**: `TestLaunchConfig` already wires `--reader-default-layout=`, `--seed-*`, `--reset-preferences`, `--enable-ai`, etc. — all DEBUG-only launch args that flip behavior at `VReaderApp.init`. WI-4e adds one more flag following the same shape.
- **Rejected — option (a) host-side simctl bridge**: move URL delivery to a pre-test script + IPC mechanism (XCTAttachment, shared file watcher) so the runner-app sandbox never has to spawn xcrun. Significant infrastructure work (new bridge + xctestplan hooks). Out of proportion for one feature's worth of test refactor.
- **Rejected — option (b) in-app HTTP endpoint**: a test-only HTTP server inside the app that the runner POSTs to, bridging back to the DebugBridge URL handler. Adds attack surface (even if DEBUG-only), more moving parts, doesn't address the AVSpeechSynthesizer-stuck-headless problem (still need the mock for that).
- **Rejected — extend the test-target `MockSpeechSynthesizer`** to live in the production target as-is: it doesn't fire delegate callbacks (line 398-443 of TTSServiceTests). XCUITest needs callbacks to drive `ttsState`. A new adapter with synthetic delegate scheduling is the minimum-viable fix.

**Files OUT of scope**:

- `verify-release-no-debugbridge.sh` — the new symbols `XCUITestMockSpeechSynthesizer` and `TTSTestOverride` are `#if DEBUG`-wrapped at file scope, which the existing release-symbol check already covers. No script change needed; spot-check during Gate 4 audit.
- Feature #31 auto page turn picker — different blocker class (SwiftUI segmented picker tap dispatch under XCUITest). Separate WI.
- `bridgeHelper.ttsAction(_:)` (WI-4d shipped) — keep as future-use helper; not exercised by WI-4e because tests use real button tap instead of URL fire.

**Test catalogue for WI-4e**:

| File | RED (pre-WI-4e) | GREEN (post-WI-4e) |
|---|---|---|
| `vreaderTests/Services/TTS/XCUITestMockSpeechSynthesizerTests.swift` (new) | Tests fail — type doesn't exist | 5 tests pass: didStart immediate, willSpeakRange ≥2, didFinish at end, stopSpeaking → didCancel, speak-twice cancels first |
| `vreaderTests/App/TestLaunchConfigTests.swift` (extend or create) | Test fails — `ttsTestMode` field doesn't exist on config | 2 tests pass: flag parsed + default false |
| `Feature40TTSSentenceHighlightVerificationTests` (refactor) | XCTSkips on ttsControlBar 30s timeout | `verify_feature_40_tts_state_reported_after_start` + `verify_feature_40_tts_offset_advances_during_playback` both pass; ttsState reports "speaking" within 8s of TTS button tap |
| `Feature41TTSAutoScrollVerificationTests` (refactor) | XCTSkips on same path | Both `verify_feature_41_*` methods pass; ttsOffsetUTF16 advances during the 3s sample window |

**Risks + mitigations**:

- **Risk — Mock weakens test signal**: tests exercise mock delegate callbacks rather than real synth. **Mitigation**: real synth is device-verified via CU 2026-05-09 (Feature #26 round-2 evidence). WI-4e tests the wiring (TTSService state machine, `TTSHighlightCoordinator`, snapshot's `ttsState` field, `ReaderContainerView` auto-scroll behavior) — only the audio engine is mocked. The signal lost is "real AVSpeechSynthesizer activates audio session correctly," which is not what the verification tests claim to cover anyway.
- **Risk — Mock timing flakiness**: synthetic callbacks fired with `Task.sleep` could be slower than test polling. **Mitigation**: mock fires `didStart` synchronously (no sleep), then first `willSpeakRange` within 250ms. Test polling intervals are 1s / 3s — well above this. Unit tests assert `≤ 100ms` for didStart and `≤ 1.5s` for the second willSpeakRange to catch regressions.
- **Risk — `TTSTestOverride.useMockSynthesizer` flag leaks state across launches**: it's a static, so a second `VReaderApp.init` in the same process could pick up the prior launch's value. **Mitigation**: `VReaderApp.init` writes the flag unconditionally from `TestLaunchConfig` (true if `--tts-test-mode` present, false otherwise). XCUITest tears down between tests via `XCUIApplication.terminate` + relaunch, which creates a new process — flag is reset at process start anyway. Add a defensive write in the `else` branch.
- **Risk — DEBUG-only symbol accidentally ships in Release**: `verify-release-no-debugbridge.sh` already enforces this for all `#if DEBUG` blocks. **Mitigation**: file-scope `#if DEBUG` wraps the entire `XCUITestMockSpeechSynthesizer.swift` body and the `TTSTestOverride` enum.
- **Risk — `defaultSynthesizer()` evaluated before `VReaderApp.init` writes the flag**: `@State var ttsService = TTSService()` in `ReaderContainerView` is initialized on first view body evaluation, which happens AFTER `VReaderApp.body` runs (which is after `VReaderApp.init` returns). **Mitigation**: confirmed in Gate 2 audit by reading the SwiftUI lifecycle — `View.body` doesn't evaluate during `App.init`. Tests will catch a regression here as the existing Feature 40/41 would XCTSkip again.

**Backward compat**: fully additive `#if DEBUG`. Release builds do not contain the mock symbol or the launch arg parsing branch. No SwiftData migration. `--tts-test-mode` absent from launch args → identical to current behavior.

**Edge cases**:

- `--tts-test-mode` set + book seed has empty TXT → `startTTS()` early-returns (whitespace-trim guard at TTSService line 71) → no mock callbacks → test XCTSkip path retained for the no-text scenario (acceptable; the relevant test seeds include `.warAndPeace` which is non-empty).
- User taps TTS button twice in quick succession with mock active → second `speak()` cancels first; first task fires `didCancel`; `TTSService.handleCancelledUtterance(generation:)` ignores the stale cancel because `currentGeneration` already incremented (existing generation-counter logic at TTSService line 92). No assertion change needed.
- Mock `stopSpeaking()` called when nothing is speaking → `currentTask` is nil; no callback fires; `isSpeaking` already false. Matches real synth no-op.
- `pauseSpeaking()` / `continueSpeaking()` on the mock → don't suspend the inner Task. Acceptable simplification for verification tests; Feature40/41 don't exercise pause/resume.

**Gate** (WI-4e acceptance):

- `vreaderTests` suite passes (existing tests + 5 new unit tests + 2 new launch-config tests).
- Feature40 + Feature41 XCUITest verification tests pass without XCTSkip on a clean simulator boot.
- `xcodebuild build -configuration Release` succeeds; new DEBUG-only symbols compile out (file-scope `#if DEBUG` wrap is the primary defense — see Gate 2 audit finding #1 below for release-guard script scope clarification).
- Feature #45 row Notes updated to reflect WI-4e DONE + Feature 40/41 unskipped.
- Evidence file `dev-docs/verification/feature-40-<YYYYMMDD>.md` (and feature-41 same date) for the post-merge VERIFIED flip on those rows. WI-4e itself is a tooling/infra change inside Feature #45; the verification-evidence files belong to Features 40 and 41 once their rows flip.

#### WI-4e — Gate 2 audit (manual fallback, Codex MCP unavailable)

Date: 2026-05-14. Codex MCP returned `stream disconnected before completion` continuously across this session (matching the 2026-05-13 outage noted in WI-4c's audit). Manual fallback per rule 47 + rule 48.

**Files read** (paths):

- `vreader/Services/TTS/SpeechSynthesizing.swift` (full) — confirmed `SpeechSynthesizing: AnyObject` protocol shape (`speak(_:)`, `pauseSpeaking()`, `continueSpeaking()`, `stopSpeaking()`, `isSpeaking`, `isPaused`), `SpeechUtteranceProtocol` (read-only `speechString`, mutable `rate`/`pitchMultiplier`/`volume`), and the existing `SystemSpeechSynthesizer` delegate-forwarding pattern via `delegateTarget`.
- `vreader/Services/TTS/TTSService.swift` (full) — confirmed `@MainActor @Observable final class TTSService: NSObject`, `init(synthesizerFactory:)` with default `{ SystemSpeechSynthesizer() }`, the `if let system = synthesizer as? SystemSpeechSynthesizer { system.delegateTarget = self }` wiring, `currentGeneration` + `handleCancelledUtterance(generation:)` stale-cancel filter, the `AVSpeechSynthesizerDelegate` extension at lines 200-245 (nonisolated methods that hop to MainActor via `Task @MainActor in`).
- `vreaderTests/Services/TTSServiceTests.swift` (lines 395-443) — confirmed test-target `MockSpeechSynthesizer: SpeechSynthesizing` exists but does NOT fire delegate callbacks (just records call flags). New production-target mock cannot reuse it.
- `vreader/Views/Reader/ReaderContainerView.swift` (line 57 + lines 220-243) — confirmed `@State var ttsService = TTSService()` and the existing `.onReceive(.debugBridgeTTSCommand)` observer wiring `startTTS()` on `action == "start"`.
- `vreader/App/VReaderApp.swift` (lines 40-150 + 325-440) — confirmed `TestLaunchConfig` shape, `parse(_:)` adds Bool fields via `args.contains("--flag")`, and the existing DEBUG early-setup block at lines 121-148 that writes UserDefaults for `--reader-default-layout=` BEFORE any view body evaluates. This is the exact precedent for the new `TTSTestOverride.useMockSynthesizer = config.ttsTestMode` write.
- `vreaderUITests/Helpers/LaunchHelper.swift` (lines 95-220) — confirmed `extraLaunchArguments: [String] = []` parameter already exists on all three `launchApp` variants (`LaunchHelper.launchApp`, free `launchApp`, `vreaderUITests_launchApp`); WI-4c's audit finding #2 was already addressed.
- `vreaderUITests/Verification/Feature40TTSSentenceHighlightVerificationTests.swift` (full) — confirmed structure: `setUpWithError` calls `launchApp(seed: .warAndPeace, resetPreferences: true)`; `openReaderAndStartTTS()` taps `readerTTSButton` (real button, no URL fire), then `XCTSkip`s on 30s `controlBar.waitForExistence` timeout. Two `verify_*` methods both follow the open-then-snapshot pattern.
- `scripts/verify-release-no-debugbridge.sh` (lines 1-100) — confirmed the symbol pattern is DebugBridge-scoped (`'vreader-debug|DebugBridge|DebugCommand|DebugFixture|DebugSnapshot|LoggingDebugBridgeContext|DebugBridgeProvider|RealDebugBridgeContext|DebugBridgeContextError'`). It is NOT a generic DEBUG-symbol leak check; precedent symbols like `TestSeeder` and `TestLaunchConfig` rely solely on file-scope `#if DEBUG` for release exclusion.
- `.claude/rules/50-codebase-conventions.md` "11. DEBUG Gating" — confirmed the codebase convention: `#if DEBUG` at file scope is the standard primary defense; the release-guard script is a belt-and-suspenders DebugBridge-specific check, not a general DEBUG-symbol scanner.

**Symbols / signatures verified**:

- `SpeechSynthesizing: AnyObject` ✓ — class-bound, satisfied by `NSObject` subclass.
- `AVSpeechSynthesizerDelegate` methods (`willSpeakRangeOfSpeechString`, `didFinish`, `didCancel`) ✓ — all take `AVSpeechSynthesizer` as the first arg, requiring the mock to own an `AVSpeechSynthesizer` instance solely as a typing tag (never speak'd on).
- `AVSpeechUtterance` ✓ — `Foundation`-based, `init(string:)`, mutable `rate`/`pitchMultiplier`/`volume`. The protocol's `SpeechUtteranceProtocol` cast back to `AVSpeechUtterance` in `XCUITestMockSpeechSynthesizer.speak(_:)` is safe because the production callers (`TTSService.startSpeaking` line 121) construct `AVSpeechUtterance` directly.
- `TestLaunchConfig` ✓ — struct with `Sendable`, all fields immutable `let`. Adding `let ttsTestMode: Bool` follows the same shape as `enableAI`, `enableSync`, etc.
- `TestLaunchConfig.parse(_:)` ✓ — pure function over `[String]`. Adding `args.contains("--tts-test-mode")` is one line.
- `TestLaunchConfig.none` ✓ — must extend with `ttsTestMode: false` to keep the struct construction balanced.
- `LaunchHelper.launchApp(...)` ✓ — `extraLaunchArguments` parameter present at lines 107, 152, 201, threaded through to `args.append(contentsOf:)` at line 183.
- `TTSService.startSpeaking` ✓ — calls `synthesizer.speak(utterance)` at line 123 with the constructed `AVSpeechUtterance`, then sets `state = .speaking`. The mock's `speak(_:)` receives this utterance and uses it as the delegate-callback param.
- `TTSService.handleCancelledUtterance(generation:)` filter ✓ — generation match required for `.idle` flip; stale cancels from in-flight Tasks are dropped. Mock's async `didCancel` is safe under restart.
- `verify-release-no-debugbridge.sh` ✓ — pattern is DebugBridge-only; no extension needed for `XCUITestMockSpeechSynthesizer` / `TTSTestOverride`.

**Edge cases checked**:

- SwiftUI lifecycle: `VReaderApp.init` writes `TTSTestOverride.useMockSynthesizer` BEFORE any `View.body` evaluates. `ReaderContainerView.@State var ttsService = TTSService()` initializer doesn't run until the user navigates to a book (post-launch). Safe ordering — verified by reading the lines 121-148 precedent: the `--reader-default-layout` UserDefaults write happens at the same point and is consumed by `ReaderSettingsStore.init` which is also a downstream view init.
- Mock didCancel race during restart: TTSService's `startSpeaking` increments `currentGeneration` BEFORE calling `synthesizer.stopSpeaking()`. The stale cancel Task that the mock spawns will reference the previous utterance, but `didCancel` (TTSService line 229-244) gates on `state == .speaking` — by the time the stale cancel reaches MainActor, the new utterance has already set state to `.speaking`, so the cancel returns early. Safe.
- Mock `pauseSpeaking()` / `continueSpeaking()`: don't actually suspend the inner Task. **Accepted simplification** — Feature 40/41 verification tests don't exercise pause/resume; future tests that need it will trigger a follow-up WI to extend the mock. Code comment will flag this explicitly.
- Mock `speak()` called on empty utterance text: TTSService line 71 guard (`!trimmed.isEmpty`) prevents this from ever calling `synthesizer.speak()`. Mock never sees empty text.
- `--tts-test-mode` set but no book opened: `ReaderContainerView` never mounts → `TTSService` never constructed → no mock instantiated. No-op. Test path with empty seed XCTSkips at the "open book" step, before reaching TTS surface.
- `TTSTestOverride.useMockSynthesizer` static state leaks across launches in the same process: XCUITest tears down via `XCUIApplication.terminate` (fresh process per test). Process boundary resets the static to its default `false`. Plus `VReaderApp.init` writes the flag unconditionally on each launch — defensive idempotency.
- `XCUITestMockSpeechSynthesizer` instantiated outside `@MainActor` (e.g., a background test runner): the class can be instantiated anywhere (its init is not @MainActor), but `delegateTarget` write + `speak` callback Tasks are `@MainActor`. TTSService wiring at line 58-60 happens during TTSService.init, which IS @MainActor — safe.
- `verify-release-no-debugbridge.sh` regression: the new symbols don't match the script's pattern, so the script will not detect a leak directly. **Mitigation**: file-scope `#if DEBUG` is the codebase's documented primary defense (rule 50 section 11). Belt-and-suspenders for our own symbols is unnecessary; the existing pattern intentionally scopes to DebugBridge to avoid scope creep on the script.

**Findings**:

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 1 | Low | Plan's "Gate" section said `verify-release-no-debugbridge.sh` "clean" for new symbols. Script's pattern is DebugBridge-scoped; new symbols are protected only by file-scope `#if DEBUG`. | Reworded Gate bullet to clarify: file-scope `#if DEBUG` is the primary defense; the script is DebugBridge-specific by design. No script extension needed. |
| 2 | Low | Plan said the mock's `pauseSpeaking()` / `continueSpeaking()` are "Acceptable simplification" but didn't specify what happens if a test ever calls them. | Implementation note (will land in code comment of XCUITestMockSpeechSynthesizer): "Pause/resume flip `isPaused` / `isSpeaking` flags but DO NOT suspend the inner callback Task. Feature 40/41 verification tests do not exercise pause/resume; a future WI extending mock coverage to pause/resume tests must add Task suspension here." |
| 3 | Info | Plan's surface area item 7 lists 5 unit test cases. Audit confirmed each is achievable with `await Task.sleep(nanoseconds:)` + `#expect` (Swift Testing). | No change. |

**Risks accepted** (with rationale):

- **Mock weakens the test signal**: real synth is CU-device-verified (Feature #26 round-2, 2026-05-09 evidence). What the verification tests claim — sentence-highlight callbacks fire + scroll advances — is a wiring property, not an audio-engine property. Mock exercises the same wiring.
- **Pause/resume not actually paused in mock**: out of scope for Feature 40/41; future WI extends if needed (see finding #2).

**Tests added or intentionally deferred**: per plan section 7 + 8 above (5 unit + 2 launch-config + 2 XCUITest refactors). None deferred.

**Concurrency / Swift 6**:

- `TTSTestOverride.useMockSynthesizer` is `@MainActor static var` — only read/written on MainActor (init flag in App.init's @MainActor body; read in TTSService's @MainActor init).
- `XCUITestMockSpeechSynthesizer` is `NSObject` subclass (required by AVSpeechSynthesizerDelegate). All MainActor-touching code goes through explicit `Task { @MainActor in ... }`.
- No new `Sendable` warnings expected; types involved (`AVSpeechSynthesizer`, `AVSpeechUtterance`, `NSRange`) have well-established cross-actor passability in iOS 17+ SDKs.

**VReader compliance**:

- Swift 6 strict concurrency: clean per the above.
- `@MainActor` correctness: SwiftUI views and TTSService stay MainActor; mock's class itself is not MainActor (per protocol `SpeechSynthesizing: AnyObject` not being MainActor-bound, matching `SystemSpeechSynthesizer`).
- File size: new `XCUITestMockSpeechSynthesizer.swift` ~80 LOC; well under 300. Updates to `TTSService.swift` (~10 LOC), `SpeechSynthesizing.swift` (~5 LOC), `VReaderApp.swift` (~5 LOC), `Feature40TTSSentenceHighlightVerificationTests.swift` (~5 LOC), `Feature41TTSAutoScrollVerificationTests.swift` (~5 LOC) all small and additive.
- Bridge safety: not applicable (no WKWebView / JS surface).

**Audit verdict**: ship-as-is with finding #1 wording fix + finding #2 code comment. Both fixes incorporated above. Plan revision 2 is the binding spec.

**SHIPPED 2026-05-14** at commit `ac04679` (PR #643). `XCUITestMockSpeechSynthesizer.swift`, `SpeechSynthesizing.swift` (with `TTSTestOverride`), `TTSService.swift` factory rewire, `VReaderApp.swift` `--tts-test-mode` launch arg + parser, Feature40/41 verification-test refactors all landed. Note: a 2026-05-15 Gate 2 post-hoc audit (Codex thread `019e2964`) of THIS plan section (before the SHIPPED marker was added) flagged that (a) the original Task-based mock design would have needed to move to main-queue scheduled callbacks + monotonic generation tokens in practice — re-audit the LANDED `XCUITestMockSpeechSynthesizer.swift` if you're inspecting the mock's correctness; and (b) the Feature40/41 Gate-5 acceptance bar should require non-idle `ttsState` + increasing `ttsOffsetUTF16` + increasing `position.charOffsetUTF16` rather than just `ttsControlBar` visibility. Both items are post-ship code-review concerns, not plan blockers.


---

## WI-5 — MD multi-page fixture for live-advancement verification (2026-05-15)

**Type**: Foundational (new DEBUG-only seed; no production behavior change).
**PR size estimate**: ~120 LOC (TestSeeder + VReaderApp dispatch + LaunchHelper enum case + 1 short unit-test file + the MD content itself).

**Why this WI exists** — Feature #31 (Auto page turning) is the last of the 13 features the plan promised to flip to `VERIFIED` whose UI-surface XCUITest passes (toggle present + interval slider appears on enable, `Feature31AutoPageTurnVerificationTests.swift`) but whose **live multi-page advancement slice** has been DEFERRED across three verification rounds (`feature-31-20260508.md`, `feature-31-20260514-round3.md`). Root cause documented in round-3: the existing `seedMDWithTOC` generator emits a 678-byte MD doc that paginates to a single page at 18pt, so `AutoPageTurner` short-circuits with "already at last page" and no observable advancement is possible.

Round-3's evidence file names three unblock paths:
- (a) larger MD seed fixture (~5KB+) — minimum-risk
- (b) new DebugBridge URL for MD `readerReadingMode=paged`
- (c) further capability-gating per bug #157 option-b

WI-5 ships path (a). Once available, a follow-on WI can add a live-advancement XCUITest method or close the slice via a manual device-verify pass.

**Surface area** — file-by-file with concrete signatures:

1. `vreader/App/TestSeeder.swift`:
   - **Add** `static func seedMDMultiPage(persistence: PersistenceActor) async` — mirrors `seedMDWithTOC` exactly except:
     - Uses `generateMDMultiPage()` content (below) → ~6-8 KB byte size, well above the 5KB pre-check threshold; expected to paginate ≥2 pages at 18pt on iPhone 17 Pro Sim's reader viewport (the load-bearing assertion)
     - Uses a distinct fingerprint hash suffix (`...c0c002`) so it doesn't collide with `seedMDWithTOC`'s `...c0c001`
     - Title `"Test Markdown Multi-Page"` / author `"MD Author"` (consistent naming with sibling seeds)
   - **Add** `internal static func generateMDMultiPage() -> String` — emits a structured MD doc: 5 chapters × 4 paragraphs of ~60 words each (filler "Lorem-ipsum-ish" but unique per chapter to make TOC navigation observable). Heading hierarchy: `# Title` then `## Chapter N: <title>` × 5 with `### Section N.M` subsections to mirror the TOC pattern users would see in real books. Target file size: ~6 KB. Concrete heading layout in §"Test catalogue" below. **`internal` (not `private`)** so `TestSeederMDMultiPageTests` and `TestSeederMDMultiPagePaginationTests` can call it directly without exposing seeding side effects. `TestSeeder` is an uninstantiable enum, so the effective surface stays module-private.

2. `vreader/App/VReaderApp.swift`:
   - `TestLaunchConfig` struct (around line 366): add `let seedMDMultiPage: Bool` after `seedMDTOC: Bool`.
   - `TestLaunchConfig.none` static (around line 467): add `seedMDMultiPage: false`.
   - `TestLaunchConfig.parse(_:)` (around line 405): add `seedMDMultiPage: args.contains("--seed-md-multi-page")`. **Audit fix (round-1 Medium #3)**: `parse(_:)` converts `arguments` to a `Set<String>` at the top of the function (line 406), so launch-arg order is **discarded**. Dispatch is **first-match-wins** via the `else if` chain in the seed handler, not "last-flag-wins" as the round-1 plan claimed.
   - `--uitesting` seed dispatch handler (around line 160-171): add an `else if seedConfig.seedMDMultiPage` branch that calls `await TestSeeder.seedMDMultiPage(persistence: persistence)`. Insert AFTER the `seedMDTOC` branch. This is the actual seed entry — the gate is `if config.isUITesting` at line 121, NOT line 97.
   - Disk-backed-store whitelist (line 94-101): add `|| config.seedMDMultiPage` to the `needsDiskBackedStore` ||-chain. Rationale is parity with `seedMDTOC` and `seedWarAndPeace`, which are already whitelisted — same shape of seed (writes a `BookRecord` + an `ImportedBooks/*.md` file), same expected storage behaviour. **Audit fix (round-1 Medium #5)**: round-1 plan mislabeled this as the "boot-detection / seed-block-entry gate" — it is the **disk-backed-store whitelist**, a separate concern. **Audit fix (round-2 Low)**: round-1 rationale invoked `Task.detached` persistence semantics that aren't load-bearing here; corrected to a simple parity statement.

3. `vreaderUITests/Helpers/LaunchHelper.swift`:
   - **Audit fix (round-1 Low #6)**: the enum is `TestSeedState`, not `BookSeed`. (The round-1 plan named it `BookSeed`, which doesn't exist.)
   - `TestSeedState` enum (around line 17): add `case mdMultiPage` after `case mdTOC`.
   - `TestSeedState.launchArgument`: add `case .mdMultiPage: return "--seed-md-multi-page"`.

4. `vreaderTests/App/TestSeederMDMultiPageTests.swift` (new, ~50 LOC):
   - Swift Testing `@Suite("TestSeeder.seedMDMultiPage")`.
   - **Test (size floor)**: `generated content exceeds 5KB threshold` — asserts `generateMDMultiPage().utf8.count > 5_000`. Catches regression where someone trims the filler text below the threshold.
   - **Test (chapter shape)**: `generated content has >= 5 H2 chapter headings` — asserts the heading count by counting `## Chapter` occurrences. Catches regression that collapses chapter structure.
   - **Test (canonical-key distinctness)**: `seedMDMultiPage and seedMDWithTOC produce distinct fingerprint canonical keys` — constructs both seed records' `DocumentFingerprint` and asserts `canonicalKey` differs. **Audit fix (round-1 Medium #4)**: round-1 plan claimed "No collision possible" based on title/content differences, but `DocumentFingerprint.canonicalKey` is `format + contentSHA256 + fileByteCount` (per `Models/DocumentFingerprint.swift:23`). Title differences are irrelevant. This test pins the actual contract — distinct hashes + distinct byte counts produce distinct canonical keys.
   - **Audit fix (round-1 High #1)**: round-1 plan included a test comparing string outputs of `generateMDMultiPage()` and `generateMDWithHeadings()`, but `generateMDWithHeadings()` is `private` and the WI didn't widen it. Two options were on the table:
     - (a) widen both helpers to `internal`
     - (b) drop the comparison test in favor of the canonical-key test (above), which gets the same regression-protection signal without needing both helpers' bodies to be reachable from tests
     - **Gate 2 decision**: option (b) — keep `generateMDWithHeadings()` `private`, only widen `generateMDMultiPage()` to `internal`.
     - **Final state (Gate 4 round-1 update)**: BOTH helpers are now `internal`. The Gate 4 round-1 audit found that the round-2 canonical-key test still hardcoded `fileByteCount: 678` for the TOC fixture, which is fragile across content edits. Fix: widen `generateMDWithHeadings()` to `internal` so the test can derive byte counts dynamically (the round-2 test was later replaced again in round-2 of Gate 4 with a live-seeding approach, but the `internal` widening stayed because it has no API-surface cost — `TestSeeder` is an uninstantiable enum). See "Audit fixes applied (Gate 4 round-1)" table below.
   - `generateMDMultiPage()` is `internal` (not `private`) for testability. Documented inline: `// internal so TestSeederMDMultiPageTests can call directly. TestSeeder is an uninstantiable enum so this stays effectively module-private.`

5. `vreaderTests/App/TestSeederMDMultiPagePaginationTests.swift` (new, ~60 LOC):
   - **Audit fix (round-1 High #2 + round-2 High + round-3 High)**: pagination is driven by **rendered Markdown** (NSAttributedString output of `MDAttributedStringRenderer.render(_:config:)`) against `UIScreen.main.bounds.size` in `TextReaderUIState.swift:91` (`nav.paginateAttributed(attributedText: attrStr, viewportSize: UIScreen.main.bounds.size)`). The raw Markdown source has heading-marker characters (`# Foo`, `## Bar`) that the renderer strips/restyles, so byte count of the raw text is not what production paginates against. Round-2's fix that called `NativeTextPaginator.paginate(text:font:viewportSize:)` with the raw source skipped the render step and could over- or under-count pages.
   - This test file runs the **full production render pipeline**: `let doc = MDAttributedStringRenderer.render(text: TestSeeder.generateMDMultiPage(), config: MDRenderConfig())` to get `doc.renderedAttributedString`, then `let paginator = NativeTextPaginator(); paginator.paginateAttributed(attributedText: doc.renderedAttributedString, viewportSize: UIScreen.main.bounds.size); #expect(paginator.totalPages >= 2)`. This mirrors the exact code path in `TextReaderUIState.updatePagination(...)`.
   - Two `@Test @MainActor` methods (`@MainActor` because `UIScreen.main` is MainActor-isolated in Swift 6 + `NativeTextPaginator` instance methods are MainActor):
     - `generatedFixture_renders_to_attributed_text_at_default_config()` — asserts `doc.renderedAttributedString.length > 0` and `doc.headings.count >= 5` (sanity that the renderer doesn't collapse the structure).
     - `renderedFixture_paginates_to_at_least_two_pages_on_main_screen_at_18pt()` — the load-bearing assertion against the full render + paginate pipeline.
   - Test runs on iPhone 17 Pro Simulator as part of the `xcodebuild test` flow — `UIScreen.main.bounds.size` resolves to the simulator's logical size (393×852 on iPhone 17 Pro). If a future contributor runs the test on a smaller simulator and the page count drops below 2, the test fails RED with a clear actionable signal: bump the generated content size.

6. `vreaderTests/App/LaunchArgParsingTests.swift` (extend if exists, else create):
   - **Test**: `parse(arguments: ["--uitesting", "--seed-md-multi-page"]) returns config with seedMDMultiPage == true && isUITesting == true`.
   - **Test**: `parse(arguments: ["--uitesting"]) returns config with seedMDMultiPage == false`.
   - Same shape as the existing `seedMDTOC` parsing test pattern. Falls back to a new `@Suite` if no prior file exists.

**Files OUT of scope**:

- `Feature31AutoPageTurnVerificationTests.swift` — does NOT add the live-advancement XCUITest method this WI. Adding it requires deciding the assertion strategy (DebugSnapshot for current page index vs. SwiftUI element-state polling) and the timeout for `AutoPageTurner`'s 5-second default interval. Tracked as a follow-up note in the plan's Acceptance Criteria mapping.
- `ReaderSettingsStore.swift` — no new launch arg for auto-page-turn enable / interval. The follow-on WI may add `--reader-default-auto-page-turn=true` and `--reader-default-auto-page-turn-interval=<seconds>` if the XCUITest path needs them; this WI's scope is the fixture only.
- `DebugFixtureCatalog.swift` — the existing MD seeds are not catalog-driven (they're generated in-code in `TestSeeder`), so this WI follows the same pattern. The catalog stays focused on file-backed fixtures (TXT/EPUB/AZW3).

**Prior art / project precedent / rejected alternatives**:

- **Precedent**: `TestSeeder.seedMDWithTOC` (lines 84-131) is the canonical pattern for in-code generated MD fixtures. WI-5 mirrors its shape exactly — same fingerprint construction, same file write, same record insertion. No invention.
- **Precedent**: `TestLaunchConfig.parse` already adds `args.contains("--seed-*")` flags one by one (`--seed-empty`, `--seed-books`, `--seed-position-test`, `--seed-war-and-peace`, `--seed-md-toc`, `--seed-corrupt-db`). WI-5 adds one more in the same style.
- **Rejected — extend `seedMDWithTOC` instead of adding a new seed**: existing test fixtures (mdTOC XCUITest + the corresponding unit tests) rely on the current 678-byte content. Lengthening the existing fixture changes the byte count, hash, and TOC structure that downstream tests assert on. Cheap risk of breaking unrelated TOC tests. New seed = zero blast radius on existing callers.
- **Rejected — file-backed fixture in `DebugFixtures/`**: catalog-driven file fixtures need an Xcode resource phase entry (per `project.yml`'s `Resources/DebugFixtures/**` block) AND a `DebugFixture` catalog entry AND a hash recomputation. The in-code generator avoids all three for what is fundamentally a deterministic synthetic string. The existing TXT / EPUB / AZW3 fixtures are file-backed because they need real format-conformance bytes; an MD doc is plain UTF-8 text generated at run time.

**Test catalogue for WI-5**:

| File | RED (pre-WI-5) | GREEN (post-WI-5) |
|---|---|---|
| `vreaderTests/App/TestSeederMDMultiPageTests.swift` (new) | All 3 tests fail — `generateMDMultiPage()` doesn't exist | 3 tests pass: byte count > 5_000, ≥5 H2 chapters, distinct canonical key from `seedMDWithTOC`'s fingerprint |
| `vreaderTests/App/TestSeederMDMultiPagePaginationTests.swift` (new) | Both tests fail — `generateMDMultiPage()` doesn't exist | 2 tests pass: (a) `MDAttributedStringRenderer.render(_:config:)` produces a non-empty `renderedAttributedString` with ≥5 detected headings; (b) `NativeTextPaginator.paginateAttributed(..., viewportSize: UIScreen.main.bounds.size)` against the **rendered** attributed string returns `totalPages >= 2` — mirrors the production render + paginate pipeline exactly per `TextReaderUIState.swift:91`. |
| `vreaderTests/App/LaunchArgParsingTests.swift` (extended) | Test fails — `seedMDMultiPage` field doesn't exist on `TestLaunchConfig` | 2 tests pass: flag parsed, default false |
| Manual integration (Gate 5a slice) | n/a — seed flag not parseable | `xcrun simctl launch booted com.vreader.app --console-pty --uitesting --seed-md-multi-page` puts a multi-page MD book in the library. Manual verify of MD paged-mode + auto-advance is the follow-on iteration's scope; this WI's slice closes once the seed lands a book in the library with `format == .md` and the unit-level pagination test passes. |

**Generated content layout** (concrete for `generateMDMultiPage()`):

```
# Multi-Page Test Document

A test fixture for verifying live multi-page advancement under
Auto Page Turn. Content sized to span multiple pages at 18pt on
iPhone 17 Pro Simulator's MD paged-mode reader viewport.

## Chapter 1: Opening

<paragraph 1 - ~60 words of unique filler about beginnings>

<paragraph 2 - ~60 words about setting>

### Section 1.1: A first subsection

<paragraph 3 - ~60 words>

<paragraph 4 - ~60 words>

## Chapter 2: Development

<4 paragraphs of ~60 words each, unique per chapter>

### Section 2.1: ...

## Chapter 3: Complication

<4 paragraphs ...>

## Chapter 4: Climax

<4 paragraphs ...>

## Chapter 5: Resolution

<4 paragraphs ...>
```

Total target: ~6 KB after UTF-8 encoding. 5 chapters × 4 paragraphs = 20 body paragraphs + 5 chapter headings + 3 subsection headings + 1 title + 1 intro = enough structure to make page transitions observable and TOC validation possible in a future test.

**Risks + mitigations**:

- **Risk — content too short to paginate** (Codex round-1 High #2 + round-2 High + round-3 High): byte count alone doesn't prove pagination because production paginates the **rendered** Markdown (NSAttributedString output of `MDAttributedStringRenderer.render(_:config:)`) against `UIScreen.main.bounds.size` (per `TextReaderUIState.swift:91`), not raw source bytes. Heading markers like `## Chapter 1` are stripped/restyled by the renderer, so raw-source pagination drifts from production behaviour. **Mitigation**: the dedicated `TestSeederMDMultiPagePaginationTests` runs the full production pipeline — `MDAttributedStringRenderer.render(_:config:)` → `NativeTextPaginator.paginateAttributed(..., viewportSize: UIScreen.main.bounds.size)` — and asserts `totalPages >= 2` on the rendered output. This is the load-bearing assertion; if 6 KB falls short on the test simulator's screen size after rendering, the test fails RED and we bump content size before the WI ships.
- **Risk — `generateMDMultiPage` and `generateMDWithHeadings` made `internal` widens public surface**: both are `static` on `TestSeeder` which is itself wrapped in `enum TestSeeder { ... }` (uninstantiable). API surface impact is zero — only test targets in the same module can reach them. The Gate 2 round-1 decision was to keep `generateMDWithHeadings()` `private`; this was later overturned in Gate 4 round-1 to enable dynamic byte-count derivation in the canonical-key test (which was itself subsequently replaced with live-seeding in Gate 4 round-2 — see audit-history tables for the trail). The `internal` widening on `generateMDWithHeadings()` has no API cost so it stayed.
- **Risk — UserDefaults seed flag leaks to non-test launches**: the existing precedent (`seedMDTOC`, `seedWarAndPeace`) handles this by gating the seed branch on `config.isUITesting`. WI-5 follows the same gate — the seed only fires when `--uitesting` is also present in launch args.
- **Risk — fingerprint canonical-key collision** (Codex round-1 Medium #4): round-1 plan claimed "No collision possible" based on title differences, but `DocumentFingerprint.canonicalKey` is `format:contentSHA256:fileByteCount` (per `Models/DocumentFingerprint.swift:23`) — title is irrelevant. **Mitigation**: distinct contentSHA256 (`...c0c002` vs `...c0c001`) AND distinct fileByteCount (the two fixtures sit in different size classes; exact byte counts drift as fixture text edits and are not contractual). The new live-seeding `seedMDMultiPage and seedMDWithTOC produce distinct canonical keys when live-seeded` unit test (Gate 4 round-2 fix — see audit-history table) pins this contract against the actual seed implementations rather than reconstructed fingerprints.
- **Risk — XCUITest accidentally seeds both `--seed-md-toc` and `--seed-md-multi-page`** (Codex round-1 Medium #3): `TestLaunchConfig.parse` does `let args = Set(arguments)` so launch-arg order is **discarded**. Dispatch is **first-match-wins** via the `else if` chain in the seed handler, not "last-flag-wins". **Mitigation**: `TestSeedState` is an enum so an XCUITest can only pass ONE seed; `LaunchArgParsingTests` covers the single-flag cases. Multi-seed flag mixing is not a documented or supported scenario; documenting the first-match semantics so future seeds added between the existing branches don't surprise their authors.

**Backward compat**:

- Pure additive `#if DEBUG`. Release builds (`TestSeeder` already excluded from release builds per file-scope `#if DEBUG`) contain neither the seed function nor the launch-arg parsing branch. No SwiftData migration. Existing `--seed-md-toc` callers continue unaffected.

**Acceptance criteria** (WI-5):

1. `xcrun simctl launch booted com.vreader.app --console-pty --uitesting --seed-md-multi-page` succeeds; library contains exactly one MD book titled "Test Markdown Multi-Page" after launch.
2. `TestSeedState.mdMultiPage` enum case usable from XCUITest helpers without compile-error.
3. `generateMDMultiPage()` produces a string > 5_000 UTF-8 bytes with ≥5 `## Chapter` headings.
4. `xcodebuild test -only-testing:vreaderTests/TestSeederMDMultiPageTests` passes 3/3.
5. `xcodebuild test -only-testing:vreaderTests/TestSeederMDMultiPagePaginationTests` passes 2/2 — full production render + paginate pipeline (`MDAttributedStringRenderer.render(_:config:)` → `NativeTextPaginator.paginateAttributed(...)`) on the generated fixture produces `totalPages >= 2` against `UIScreen.main.bounds.size` on iPhone 17 Pro Simulator (393×852).
6. `xcodebuild test -only-testing:vreaderTests/LaunchArgParsingTests` (or its replacement) passes the 2 new cases.
7. **Gate 5a slice**: pre-merge simulator launch confirms the seeded book appears in the library with format `.md`. (Live-advancement device-verify is the follow-on iteration's scope; the load-bearing pagination assertion is the unit test above.)
8. Feature #31 row note updated: pre-WI-5 deferred slice is now SEEDABLE (live-advancement device verify with this fixture is a follow-on iteration, not part of WI-5).

**Audit fixes applied** (Gate 2 round-1 — Codex thread `019e28b1`):

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 1 | High | Test 3 (string comparison `generateMDMultiPage` vs `generateMDWithHeadings`) doesn't compile — `generateMDWithHeadings()` is `private`. | Replaced with canonical-key distinctness test that pins the actual `DocumentFingerprint` contract without needing both helpers to be reachable. `generateMDWithHeadings()` stays `private`. |
| 2 | High | 5KB byte-count threshold doesn't prove pagination — `NativeTextPaginator` paginates rendered attributed text against viewport size. | Added a separate `TestSeederMDMultiPagePaginationTests` for the pagination assertion (later refined in finding #11 to use the full `MDAttributedStringRenderer.render(_:config:)` → `NativeTextPaginator.paginateAttributed(...)` production pipeline rather than the raw-source `paginate(text:font:viewportSize:)` shortcut this row originally described). Byte threshold demoted to a cheap pre-check. |
| 3 | Medium | "Last-flag-wins" mitigation is factually wrong — `parse(_:)` does `let args = Set(arguments)` so order is discarded. | Reworded to first-match-wins via the `else if` chain, documented in the surface area section. |
| 4 | Medium | "No fingerprint collision possible" is overstated — title differences don't matter; `canonicalKey` is `format:SHA256:byteCount`. | Reworded to "distinct contentSHA256 + distinct fileByteCount"; added the canonical-key distinctness unit test to pin the contract. |
| 5 | Medium | Line 97 reference mislabels the disk-backed-store whitelist as the seed-block-entry gate. The actual gate is `if config.isUITesting` at line 121. | Reworded — line 94-101 is the disk-backed-store whitelist (add `seedMDMultiPage` there for parity with `seedMDTOC`); the seed dispatch is at line 121's `if config.isUITesting` block. |
| 6 | Low | `BookSeed` enum doesn't exist — it's `TestSeedState`. There's no `LaunchHelper.BookSeed` namespace. | Renamed all references to `TestSeedState.mdMultiPage`. |

**Audit fixes applied (Gate 2 round-2 — Codex thread `019e28b1`)**:

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 7 | High | Pagination test viewport was hardcoded to `CGSize(width: 393, height: 750)`, smaller than production's `UIScreen.main.bounds.size` (which is ~393×852 on iPhone 17 Pro). Smaller viewport over-paginates → false pass. | Test now uses `UIScreen.main.bounds.size` directly. Test method marked `@MainActor` (`UIScreen.main` is MainActor-isolated in Swift 6). |
| 8 | Medium | Surface area item 1 signature still said `private static func generateMDMultiPage()` while items 4-5 said `internal`. | Item 1 signature now reads `internal static func generateMDMultiPage()`. Sibling `generateMDWithHeadings()` stays `private`. |
| 9 | Low | Surface area listed two items numbered "5" and "6" (LaunchArgParsingTests appeared twice). | Removed the duplicate. Items now numbered 1-6 cleanly. |
| 10 | Low | Disk-backed-store whitelist rationale claimed `Task.detached` persistence semantics, which aren't load-bearing here. | Reworded as parity with `seedMDTOC` / `seedWarAndPeace` (same shape of seed, same expected storage behaviour). |

**Audit fixes applied (Gate 2 round-3 — Codex thread `019e28b1`)**:

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 11 | High | Pagination test still used `NativeTextPaginator.paginate(text:font:viewportSize:)` with the **raw Markdown source string**, skipping the MD render pipeline. Production paginates the **rendered NSAttributedString** (`MDAttributedStringRenderer.render(_:config:).renderedAttributedString`), which strips heading markers and restyles text — so raw-source pagination drifts from production. | Test now runs the full production pipeline: `MDAttributedStringRenderer.render(text: TestSeeder.generateMDMultiPage(), config: MDRenderConfig())` → `NativeTextPaginator.paginateAttributed(attributedText: doc.renderedAttributedString, viewportSize: UIScreen.main.bounds.size)`. Two test methods now: (a) render produces non-empty attributed string with ≥5 detected headings; (b) rendered output paginates to ≥2 pages. |
| 12 | Low | Surface area item 1 said "high enough at 18pt to paginate ≥3 pages" but the acceptance gate only asserts `>= 2 pages`. | Lowered prose claim to "expected to paginate ≥2 pages at 18pt" matching the test assertion. |

Gate 2 round-1 verdict: **Reject as-is** → fixes applied (findings 1-6).
Gate 2 round-2 verdict: **Reject as-is** → fixes applied (findings 7-10).
Gate 2 round-3 verdict: **Reject as-is** → fixes applied (findings 11-12).

Round 3 is the max audit cap per rule 47. Plan accepted into Gate 3 (TDD).

**Audit fixes applied (Gate 4 round-1 — Codex thread `019e28be`, prefix only — full UUID lost)**:

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 13 | Medium | Canonical-key test hardcoded `fileByteCount: 678` for the TOC fixture — fragile across fixture content edits. | Widened `generateMDWithHeadings()` from `private` to `internal` so the test can derive both byte counts dynamically. (Overturns the Gate 2 round-1 "stays private" decision.) |
| 14 | Low | Chapters 4-5 only had 2 paragraphs and no H3 subsection, breaking the documented "5 chapters × 4 paragraphs + ≥5 H3" shape contract. | Padded chapters 4-5 to 4 paragraphs each and added H3 sections 4.1 and 5.1. |
| 15 | Low | TestSeeder.swift now ~605 lines, over the 300-line guideline. | Accepted with rationale — broader file-split cleanup is out of scope for WI-5 (which only appended one seed pair). Tracked as residual repo debt. |
| 16 | Low | File-system orphan cleanup gap (TestSeeder-wide concern, not WI-5-specific). | Accepted — TestSeeder-wide concern beyond WI-5's surface. |

**Audit fixes applied (Gate 4 round-2 — same thread)**:

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 17 | Medium | Canonical-key test still reconstructed fingerprints from constants rather than exercising the live seed implementations. A future bug that gave both seeds the same hash literal + byte count would slip through. | Rewrote test to seed both fixtures into an in-memory `Schema(SchemaV6.models)` + `PersistenceActor`, fetch back via `fetchAllLibraryBooks()`, and compare the persisted `fingerprintKey`. Test method renamed `seedMDMultiPageAndSeedMDWithTOCProduceDistinctCanonicalKeysWhenLiveSeeded()`. Added `import SwiftData`. |
| 18 | Low | Doc-comment drift in `TestSeeder.swift` and `LaunchHelper.swift` claiming "~6 KB" — drifted as fixture content evolved. | Replaced with load-bearing-contract phrasing: paginates to ≥2 pages at 18pt on iPhone 17 Pro's screen; byte count drifts and is not contractual. |

**Audit fixes applied (Gate 4 round-3 — fresh thread `019e28c7-02bb-78f2-95ee-ffaffa899c45` because the original prefix-only thread ID couldn't be continued)**:

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 19 | Medium | Pagination test called `MDRenderConfig()` without explicitly pinning `fontSize: 18`. Works today because the default is 18, but a future default change would silently make the test false-green. | Test now constructs `MDRenderConfig(fontSize: 18)` explicitly, so the documented "≥2 pages at 18pt" contract is self-evident in the test source. |
| 20 | Low | `VReaderApp.swift` `seedMDMultiPage` doc comment reintroduced exact-size drift ("~6 KB", "~678 B"). | Rewrote with invariant phrasing: paginates to ≥2 pages at 18pt; sibling seed is the smaller single-page size class; byte counts non-contractual. |
| 21 | Low | This plan doc still said "Decision: keep `generateMDWithHeadings()` private" while the final code widens it to `internal`. | Updated surface-area item 4 + Risk note to reflect final state; added this Gate 4 round-1/2/3 audit-history table so the decision trail is preserved. |

Gate 4 round-1 verdict: **Reject as-is** → fixes applied.
Gate 4 round-2 verdict: **Reject as-is** → fixes applied.
Gate 4 round-3 verdict (Codex thread `019e28c7`): **follow-up-recommended** → all 3 findings (19, 20, 21) fixed inline before merge. Round 3 is the audit cap per rule 47; remaining items 15 + 16 are accepted-with-rationale (broader TestSeeder cleanup beyond WI-5).


---

## WI-6 — Named test-plan selector for the Verification subset (BLOCKED on Bug #192 / GH #686) (revision 2 — 2026-05-15)

**Type**: Foundational (build-system artifact; no production behavior change, no test-content change).
**PR size estimate**: ~80 LOC across `TestPlans/Verification.xctestplan` (new, ~50 LOC JSON), `TestPlans/All.xctestplan` (new sibling all-tests plan to preserve the current default `Cmd+U` behavior, ~20 LOC JSON), `project.yml` (~8 LOC additions under `targets.vreader.scheme.testPlans`), `docs/architecture.md` (~3 LOC cross-ref).

**Why this WI exists** — the WI-4 acceptance gate is: "`xcodebuild test -only-testing:vreaderUITests/Verification` exits 0 in under 8 minutes". That invocation works today via the `-only-testing:` flag. WI-6 adds the same selector as a named scheme alias (`-testPlan Verification`) so future commands + CI runs can spell it more concisely and so the Verification subset is durably named (not embedded as a string in every CI invocation).

**Scope clarification (Codex round-1 High #4)** — WI-6 is renamed from "CI test-plan integration" to "Named test-plan selector for the Verification subset" because no CI workflow exists in this repo today (`.github/workflows/` is empty per `git ls-files`). Shipping a GHA workflow that calls `xcodebuild test -testPlan Verification` is a *separate* WI (or feature row); WI-6 ships the durable test-plan artifact, not the CI integration. If/when a GHA workflow is added, it can reference the test plan by name. Both interpretations are useful; we ship the foundational piece first.

**Surface area** — file-by-file with concrete signatures:

1. **New `TestPlans/Verification.xctestplan`** (Codex round-1 Low #6: top-level `TestPlans/` directory, not nested under `vreaderUITests/`, because (a) Xcode convention puts scheme artifacts at project root and (b) we'll have a sibling `All.xctestplan` so a project-level grouping is cleaner). Hand-authored Xcode 16 testplan JSON shape:

   ```json
   {
     "configurations" : [
       { "id" : "<uuid>", "name" : "Verification", "options" : {} }
     ],
     "defaultOptions" : {
       "targetForVariableExpansion" : { "containerPath": "container:vreader.xcodeproj", "identifier": "<vreader-target-uuid>", "name": "vreader" }
     },
     "testTargets" : [
       {
         "selectedTests" : [
           "Feature11EPUBHighlightVerificationTests",
           "Feature17PDFHighlightVerificationTests",
           "Feature21TXTReaderVerificationTests",
           "Feature23EPUBChapterNavVerificationTests",
           "Feature27SearchVerificationTests",
           "Feature28SearchHighlightDismissVerificationTests",
           "Feature29SearchTOCVerificationTests",
           "Feature31AutoPageTurnVerificationTests",
           "Feature35BookmarkVerificationTests",
           "Feature36SearchPanelVerificationTests",
           "Feature40TTSSentenceHighlightVerificationTests",
           "Feature41TTSAutoScrollVerificationTests"
         ],
         "target" : { "containerPath": "container:vreader.xcodeproj", "identifier": "<vreaderUITests-target-uuid>", "name": "vreaderUITests" }
       }
     ],
     "version" : 1
   }
   ```

   **Membership is explicit** (Codex round-1 High #2). The exact 12 classes listed above are derived from `docs/architecture.md:284-315` — they are the simulator-automatable backlog items from Feature #45's contract. Plan-level note: the actual file count of `*VerificationTests` files under `vreaderUITests/Verification/` may be ≥12 (some classes contain multiple `@Test` methods); Gate 5 verifies inclusion-vs-actual by running the plan and grep'ing the `xcresult` for any unexpected entries. CU-driven tests (none today, but if any are ever added under `vreaderUITests/` outside `Verification/`) are automatically excluded by virtue of explicit-only inclusion.

2. **New `TestPlans/All.xctestplan`** (Codex round-1 High #1: preserve the current `Cmd+U` default). Same JSON shape but with `"testTargets":[{"target":{...vreaderTests...}},{"target":{...vreaderUITests...}}]` and NO `selectedTests` key (= include all). Mark this as the scheme's default plan.

3. **`project.yml`** at `targets.vreader.scheme` (Codex round-1 Low #5: explicit YAML surface). Currently has just `testTargets:` (lines 166-169). Add a `testPlans:` key adjacent:

   ```yaml
       scheme:
         testTargets:
           - vreaderTests
           - vreaderUITests
         testPlans:
           - path: TestPlans/All.xctestplan
             defaultPlan: true
           - path: TestPlans/Verification.xctestplan
   ```

   xcodegen regenerates `vreader.xcodeproj/project.pbxproj` with these as the scheme's test plan references. Both `project.yml` and the regenerated `pbxproj` get committed in one commit.

4. **`docs/architecture.md`** Verification Harness section (around line 284): add a one-line cross-ref. Specifically, append a paragraph: "Run only the verification subset with `xcodebuild test -testPlan Verification`. The named plan lives at `TestPlans/Verification.xctestplan`; membership is checked-in and reviewed via the WI-6 acceptance criteria. The default `Cmd+U` test plan (`TestPlans/All.xctestplan`) is unchanged and runs the full vreaderTests + vreaderUITests suites."

**Files OUT of scope** — GHA workflow (`.github/workflows/verification.yml`), `vreaderUITests/` test files themselves (no test-content change), `vreaderTests/` (no membership change).

**Prior art / project precedent / rejected alternatives**:

- **Precedent**: This repo has no checked-in `.xctestplan` files today (`git ls-files | grep xctestplan` returns empty). xcodegen project spec documents the `testPlans:` key as `[path:..., defaultPlan: bool]` array; the `path:` is relative to project root.
- **Rejected — dedicated UI-test scheme** (a `vreaderVerification` scheme): would be more isolated but doubles the scheme count and creates an "is this scheme or that scheme" decision for every dev. Test plans achieve the same scoping with a single scheme and zero scheme-pollution.
- **Rejected — wildcard membership** (`-skip-testing` patterns): Codex round-1 High #2 noted "*VerificationTests" wildcard isn't implementable. Explicit listing is the canonical Xcode pattern; the small extra editing cost when adding a new verification class is worth the clarity.
- **Rejected — keep `-only-testing:` and skip the test plan entirely**: works for ad-hoc invocations but doesn't surface the subset as a named entity in Xcode's scheme picker; harder for the next developer to discover.

**Test catalogue** — no new tests added; this WI doesn't change test content. The verification IS the build-system functional gate (Gate 5).

**Risks + mitigations**:

- **Risk — xctestplan JSON schema drift across Xcode versions**. Xcode 16's testplan format is at "version: 1" today; future Xcode major versions may bump it. **Mitigation**: pin to the known-good shape in the plan above; regenerate the testplan via Xcode UI ("Convert to use test plans" command) if needed in the future.
- **Risk — UUID stability across xcodegen runs**. The `id` fields inside the testplan JSON need to be stable so the pbxproj reference doesn't churn. **Mitigation**: generate UUIDs once when authoring the testplan, commit them as-is, never regenerate via Xcode (which would assign fresh UUIDs).
- **Risk — `Cmd+U` default flips to Verification-only**. **Mitigation**: ship the `All.xctestplan` sibling plan + mark it `defaultPlan: true` in `project.yml`. Gate 5 verifies that `xcodebuild test -scheme vreader` (no `-testPlan` flag) still runs the full suite.

**Backward compat**: existing `-only-testing:vreaderUITests/Verification` invocations continue to work unchanged. Adding a named test plan is purely additive.

**Gate 4 audit focus** (audit log when run):

- Test plan JSON shape correctness — open the plan in Xcode after xcodegen regen; the scheme picker should show both plans.
- Membership exactness: the Verification plan's `selectedTests` list contains exactly the 12 classes named in §1 above, no more, no less.
- xcodegen idempotency: `xcodegen generate` re-run produces zero noise in `pbxproj` (testPlans references should be stable).
- All.xctestplan exists, is marked default, and `Cmd+U` / `xcodebuild test -scheme vreader` still runs the full suite.
- Top-level `TestPlans/` directory created (Codex Low #6); no scheme artifacts mixed with test source files.

**Gate 5 verification (slice acceptance criteria)** — Codex round-1 Medium #3 tightening:

1. `xcodebuild test -project vreader.xcodeproj -scheme vreader -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` (no `-testPlan` flag) runs the FULL suite (all-tests-plan default) and exits 0 (subject to pre-existing Bug #176 AZW3 TTS failures being out of scope).
2. `xcodebuild test -project vreader.xcodeproj -scheme vreader -testPlan Verification -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` exits 0 within an 8-minute budget on a clean DerivedData. The 8-minute figure is a planning estimate (not a checked-in measured constant); Gate 5 records the actual elapsed time for future reference.
3. Inspecting the post-run `xcresult` (or the test-plan inclusion list via `xcodebuild -showTestPlans`) confirms exactly the 12 named Verification classes ran, no more, no less.
4. Opening `vreader.xcodeproj` in Xcode and clicking the scheme picker shows both `All` and `Verification` test plans available; `All` is the default.

**Gate 5 verification approach**: this is a build-system change so Gate 5 IS the functional `xcodebuild` invocation. No device-level UI test needed.

**Status**: PENDING. Gate 1 done (this plan). Gate 2 audit round 1 produced the revisions above (Codex thread `019e2982`); round 2 will re-audit the revised plan.

**Audit fixes applied (Gate 2 round-1 — Codex thread `019e2982`)**:

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 1 | High | Single Verification plan would make `Cmd+U` Verification-only, breaking the all-tests default. | Added sibling `All.xctestplan` to the surface area, marked it `defaultPlan: true` in `project.yml`. Gate 5 §1 verifies `xcodebuild test -scheme vreader` (no `-testPlan`) still runs the full suite. |
| 2 | High | "Includes only `*VerificationTests` wildcard" is vague + not implementable. | Replaced with explicit 12-class `selectedTests` list derived from `docs/architecture.md:284-315`. Gate 4 audit + Gate 5 §3 verify exact membership. |
| 3 | Medium | Gate 5 acceptance criterion ("exits 0") would pass on an empty/under-selected plan. | Added Gate 5 §3 explicit-membership verification + Gate 5 §1 full-suite-default verification + Gate 5 §4 Xcode-scheme-picker check. |
| 4 | Medium | "CI integration" name conflicts with the scope (no GHA workflow shipped). | Renamed WI-6 to "Named test-plan selector for the Verification subset"; added Scope clarification paragraph naming a future separate WI for the GHA workflow if/when one is added. |
| 5 | Low | `project.yml` surface not named explicitly. | Surface-area §3 now names `targets.vreader.scheme.testPlans` exactly + shows the YAML literal. |
| 6 | Low | Putting `Verification.xctestplan` under `vreaderUITests/Verification/` mixes source + scheme artifacts. | Moved both plans to top-level `TestPlans/`. |

**Audit fixes applied (Gate 2 round-2 — same Codex thread `019e2982`)**:

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 7 | Critical | The round-1 revised 12-class membership list was wrong: invented `Feature17PDFHighlightVerificationTests` (doesn't exist), invented several renamed class names (`Feature21TXTReader...` is actually `Feature21PaginatedMode...`, etc.), omitted real `Feature34CollectionsVerificationTests` and `Feature37PerBookSettingsVerificationTests`. Actual repo has 13 classes: Feature11/21/23/27/28/29/31/34/35/36/37/40/41. | Reverted to deriving membership from filesystem (`ls vreaderUITests/Verification/Feature*VerificationTests.swift`) rather than reconstructing from memory. Membership list to be fixed when WI-6 unblocks. |
| 8 | Critical | Test methods are named `verify_*` not `test_*`. XCTest's standard discovery only finds methods starting with `test`. A test plan filters DISCOVERED tests; it cannot invent discovery for non-test methods. As written, the test plan would select classes that expose zero XCTest-discoverable methods to the runner. Verified via `xcodebuild test -only-testing:vreaderUITests/Feature11EPUBHighlightVerificationTests` → `Executed 0 tests`. | Filed as **Bug #192 (GH #686)** — a pre-existing latent bug in the entire 13-class Verification suite (25 `verify_*` methods all invisible to XCTest). WI-6 is **BLOCKED** until Bug #192 is fixed (rename `verify_*` → `test_verify_*`, ~25 mechanical renames + re-run to surface real failures previously masked by silent no-op). The bug-fix cron handles the fix in a separate iteration. |
| 9 | Medium | Round-1 note "file count of `*VerificationTests` files may be ≥12 (some classes contain multiple `@Test` methods)" was framework-confused. These are XCTestCase files, not Swift Testing `@Test` suites. | Will rewrite in XCTest terms once WI-6 unblocks. |

Gate 2 round-2 verdict (Codex): **revise** → 2 of 3 findings escalated to a separate bug (Bug #192), which blocks WI-6 entirely. Round 3 is not run because the WI is now blocked on external work, not on plan revisions. WI-6 stays at BLOCKED status pending Bug #192 fix. Once Bug #192 lands, this plan needs one more revision (correct 13-class membership list from filesystem; clarify XCTest discovery semantics) and a round-3 audit before Gate 3 can start.

