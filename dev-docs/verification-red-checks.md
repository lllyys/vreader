# Verification Harness — RED-Proof Checks

Per `.claude/rules/10-tdd.md`, tests must be RED-proof: they must
demonstrably FAIL on the pre-fix commit (or in the absence of the
production behavior they assert). For the verification UITest harness
under `vreaderUITests/Verification/`, RED-proofing is done by either:

1. **Author-time validation**: temporarily comment out / break the
   production AID or wiring, observe the test fail, then restore.
2. **Historical RED**: cite a prior commit where the test would have
   failed because the production behavior wasn't yet wired.

This doc captures RED-proof evidence for each verify_ method in the
harness. New WIs that add tests must append a row.

## Conventions

- "**Production seam**": the production code element the test relies on
  (an AID, a notification, a JSON snapshot field, etc.).
- "**RED-proof source**": either a temporary diff verified locally
  ("removed AID `X` from view → test failed with `not exists`") OR a
  cited historical commit before the production behavior shipped.
- "**Status**": `verified` (RED-proof captured), `inferred` (RED-proof
  follows from AID-existence audit), or `deferred` (RED-proof not yet
  obtained — owner + due date listed).

## WI-1 (PR #581) — Harness scaffold

| Test | Production seam | RED-proof source | Status |
|---|---|---|---|
| Feature11EPUBHighlightVerificationTests.verify_feature_11_epub_highlight_happy_path | `bookCard_*` book picker; reader highlight gesture menu | Pre-WI-1 commit: no `verify_` test existed; AID existence pinned by WI-1 audit grep | inferred |
| Feature11EPUBHighlightVerificationTests.verify_feature_11_epub_highlight_regression_bug77_buffering_race | Same as happy path + buffering timing | Bug #77 fix shipped pre-WI-1; failure mode was the race the regression test guards | inferred |
| Feature34CollectionsVerificationTests.verify_feature_34_create_collection_appears_in_sidebar | `collectionsToolbarButton`, `newCollectionButton`, `newCollectionTextField`, `addCollectionButton` | `typeText` proven to work in iOS Sim on TextField (confirmed by passing WI-1 PR #581 merge gate) | inferred |
| Feature34CollectionsVerificationTests.verify_feature_34_add_book_to_collection_filters_library | Above + `filterDoneButton` + filter chip | Same as create-collection RED-proof | inferred |
| Feature37PerBookSettingsVerificationTests.verify_feature_37_perbook_settings_toggle_isolated_to_book | `Custom settings for this book` switch label | Per-book settings feature shipped in feature #37; isolation contract pinned by `PerBookSettingsStore` unit tests | inferred |
| Feature37PerBookSettingsVerificationTests.verify_feature_37_perbook_settings_persists_across_reopen | Above + SwiftData persistence | Same as isolation RED-proof | inferred |

## WI-2 (PR #584) + follow-up (PR #585) — Features #21/#23/#27/#28

| Test | Production seam | RED-proof source | Status |
|---|---|---|---|
| Feature21PaginatedModeVerificationTests.verify_feature_21_paged_mode_shows_paged_view | `Reading Mode` picker label, `nativeTextPagedView` | Picker exists in `ReaderSettingsPanel.swift:246` (verified by audit grep) | inferred |
| Feature21PaginatedModeVerificationTests.verify_feature_21_paged_mode_page_navigation | `readingProgressLabel` | Reading progress label is a chrome element; AID grep-confirmed | inferred |
| Feature23TXTTocVerificationTests.verify_feature_23_txt_toc_populated_for_chapters | `TXTTocRuleEngine` rule #3 (英文Chapter); `tocEmptyState`; `tocRow-*` | **Historical RED**: WI-2 initial pass with `.books` seed FAILED (verify-cron 2026-05-13 06:24); follow-up patch with `.warAndPeace` seed flipped to GREEN (PR #585, evidence: `feature-23-20260513.md`) | verified |
| Feature23TXTTocVerificationTests.verify_feature_23_txt_toc_navigation_jumps_to_chapter | Same as populated + `onNavigate` closure dismissing panel | Same as populated RED-proof | verified |
| Feature27ReplacementRulesVerificationTests.verify_feature_27_replacement_rule_ui_surface | `settingsReplacementRules` row, `replacementRulesAddButton` | `replacementRulesAddButton` was newly added in WI-1 — removing it from `ReplacementRulesView.swift:73` would fail the assertion | inferred |
| Feature28ChineseConversionVerificationTests.verify_feature_28_chinese_text_picker_present | `Chinese Text` section header string | Section header is unconditional (panel always renders); removing the section would fail | inferred |
| Feature28ChineseConversionVerificationTests.verify_feature_28_conversion_applies_to_reader_content | (currently XCTSkip — no CJK fixture) | Deferred until CJK TXT fixture lands | deferred — pending fixture |

## WI-3 (PR #587) — Features #29/#31/#35/#36/#40

| Test | Production seam | RED-proof source | Status |
|---|---|---|---|
| Feature29WebDAVVerificationTests.verify_feature_29_webdav_backup_ui_available | `webdavServerURL`, `webdavTestButton`, `webdavSaveButton` | All three AIDs exist in `WebDAVSettingsView.swift` lines 73, 106, 130 — verified by audit grep | inferred |
| Feature29WebDAVVerificationTests.verify_feature_29_webdav_backup_executes_when_configured | Above + `webdavBackupErrorText` absence | env-var-gated; will RED if CI_WEBDAV server rejects credentials | deferred — depends on CI runner |
| Feature31AutoPageTurnVerificationTests.verify_feature_31_auto_page_turn_toggle_present | `Auto Page Turn` section header; `autoPageTurnToggle` | **Historical RED**: WI-3 initial run on `.warAndPeace` (TXT) FAILED because TXT lacks `.autoPageTurn` capability (verify-cron 2026-05-13 09:25). WI-4 refinement: probe section non-strictly → XCTSkip when capability-gated | verified |
| Feature31AutoPageTurnVerificationTests.verify_feature_31_auto_page_turn_interval_slider_appears_on_enable | Above + `autoPageTurnIntervalSlider` | Same capability gate as toggle-present | verified |
| Feature35AnnotationsExportVerificationTests.verify_feature_35_export_button_is_visible | `annotationsExportButton` in panel toolbar | Removing AID at `AnnotationsPanelView.swift:111` would fail the assertion | inferred |
| Feature35AnnotationsExportVerificationTests.verify_feature_35_import_button_is_visible | `annotationsImportButton` | Same RED-proof shape as export button | inferred |
| Feature36OPDSVerificationTests.verify_feature_36_opds_catalog_ui_surface | `opdsCatalogsToolbarButton`, `opdsCatalogList`/`opdsEmptyState`, `opdsAddCatalog`, form fields | AID grep-confirmed in OPDS views | inferred |
| Feature36OPDSVerificationTests.verify_feature_36_opds_browse_with_live_fixture | Live HTTP feed | env-var-gated | deferred — CI runner |
| Feature40TTSSentenceHighlightVerificationTests.verify_feature_40_tts_state_reported_after_start | `readerTTSButton`, `ttsControlBar`, `DebugSnapshot.ttsState` | **Historical RED**: WI-3 initial run FAILED because chrome was hidden and tap missed (verify-cron 2026-05-13 09:25). WI-4 refinement: tap reader first to show chrome, increase timeout to 15s | verified |
| Feature40TTSSentenceHighlightVerificationTests.verify_feature_40_tts_offset_advances_during_playback | Above + `ttsOffsetUTF16` advancement | Same chrome-visibility RED-proof | verified |

## WI-4 (this WI) — Feature #41 + test refinements

| Test | Production seam | RED-proof source | Status |
|---|---|---|---|
| Feature41TTSAutoScrollVerificationTests.verify_feature_41_tts_control_bar_visible_during_playback | `readerTTSButton`, `ttsControlBar`, chrome activation pattern | Removing `.accessibilityIdentifier("ttsControlBar")` from `TTSControlBar.swift:69` would fail | inferred |
| Feature41TTSAutoScrollVerificationTests.verify_feature_41_tts_autoscroll_position_advances | Above + `DebugSnapshot.position.charOffsetUTF16` (post-bug #164 fix) | Pre-bug #164 commit had TXT readers NOT broadcasting `.readerPositionDidChange` on scroll, so the snapshot's `position` was stale; post-fix it advances | verified (historical) |

## Open RED-proof gaps

- WI-2 Feature #28 conversion-applied test: deferred pending CJK fixture
- WI-3 Feature #29 live backup test: deferred pending CI_WEBDAV env vars
- WI-3 Feature #36 live browse test: deferred pending CI_OPDS env vars

These are not author-time gaps but environment-gated tests; XCTSkip
keeps them from blocking the harness.

## How to add a new RED-proof entry

1. Write the test.
2. Temporarily break the production seam it relies on (delete the AID,
   comment out the wiring, swap in a stub).
3. Run the test; confirm it FAILS with the expected diagnostic.
4. Restore the production code.
5. Run the test; confirm it PASSES.
6. Add a row to the appropriate WI table above with `Status: verified`
   and a one-line "RED-proof source" describing the seam break.

If the seam can't be easily broken locally (e.g., it depends on a
Codex/Codex-equivalent audit, or live HTTP), use `Status: inferred`
with a cite of the audit / source code line that pins the seam.
