# Phase E Implementation Plan (Forward)

**Date**: 2026-03-17
**Status**: FORWARD — 7 WIs planned (E02 split into E02a + E02b)
**Scope**: Cross-device sync (WebDAV + iCloud) and text transformation features

**Reference**: iCloud design doc at `docs/codex-plans/icloud-backup-design.md`

---

## WI-E01: #29 WebDAV Backup and Restore

**Problem**: Users need cross-platform backup without iCloud (Nutstore/坚果云, Synology, NextCloud). WebDAV is the standard protocol for this.

**Files to create/modify**:
- Create: `vreader/Services/Backup/WebDAVProvider.swift` — BackupProvider conformance
- Create: `vreader/Services/Backup/WebDAVClient.swift` — raw WebDAV HTTP operations
- Create: `vreader/Views/Settings/WebDAVSettingsView.swift` — connection config UI
- Create: `vreaderTests/Services/Backup/WebDAVProviderTests.swift`
- Create: `vreaderTests/Services/Backup/WebDAVClientTests.swift`
- Modify: `vreader/Services/Backup/BackupProvider.swift` — no changes needed (protocol ready)

**Tests FIRST**:
- `testBackup_createsZIPArchive`
- `testBackup_includesMetadata`
- `testBackup_includesAnnotations`
- `testBackup_includesReadingPositions`
- `testBackup_includesCollections`
- `testBackup_includesBookSources`
- `testBackup_includesReplacementRules`
- `testBackup_includesPerBookSettings`
- `testBackup_includesTxtTocRules`
- `testBackup_progressReported`
- `testRestore_extractsZIP`
- `testRestore_restoresAnnotations`
- `testRestore_restoresReadingPositions`
- `testRestore_backupNotFound_error`
- `testListBackups_sortedNewestFirst`
- `testListBackups_emptyServer_returnsEmpty`
- `testDeleteBackup_removesFromServer`
- `testWebDAVClient_PROPFIND_parsesResponse`
- `testWebDAVClient_PUT_uploadsFile`
- `testWebDAVClient_GET_downloadsFile`
- `testWebDAVClient_DELETE_removesFile`
- `testWebDAVClient_authFailure_returnsError`
- `testWebDAVClient_connectionTest_success`
- `testWebDAVClient_nutstore_compatible`
- `testBackup_largeLibrary_50Books_completesUnder30s`

**Implementation approach**:
1. WebDAVClient: URLSession-based, supports PROPFIND, PUT, GET, DELETE, MKCOL
2. WebDAVProvider: implements BackupProvider protocol (already defined in WI-F04)
3. Backup format: ZIP containing:
   - `metadata.json` — backup metadata (version, date, device)
   - `annotations.json` — highlights, bookmarks, notes
   - `positions.json` — reading positions per book
   - `settings.json` — app settings/preferences
   - `collections.json` — user collections (from C01)
   - `book-sources.json` — imported book sources (from Phase D)
   - `replacement-rules.json` — content replacement rules (from E05)
   - `per-book-settings.json` — per-book reader settings (font, theme overrides)
   - `txt-toc-rules.json` — custom TXT table-of-contents rules
   - optional book files (if user opts in)
4. ZIP created via Foundation's FileManager or ZIPFoundation
5. Backup stored at `<webdav_root>/VReader/backups/<timestamp>.vreader.zip`
6. Settings UI: server URL, username, password (stored in Keychain via KeychainService)
7. Connection test button before saving

**Edge cases**: Slow networks (progress + timeout), server full (quota), auth expiry, server not supporting PROPFIND (some WebDAV implementations), special characters in filenames, Nutstore-specific quirks (path encoding).

**Acceptance criteria**: Full backup/restore cycle works. Compatible with Nutstore, NextCloud, Synology. Credentials stored securely. Progress reported. Error messages actionable.

**Dependencies**: WI-F04 (BackupProvider protocol) — done.

**Effort**: M

---

## WI-E02a: #10 iCloud Snapshot Backup (via BackupProvider)

**Problem**: iOS-native backup via iCloud for users in the Apple ecosystem. Snapshot approach: create a ZIP archive and store it in iCloud Drive, reusing the BackupProvider protocol from E01.

**Files to create/modify**:
- Create: `vreader/Services/Backup/ICloudBackupProvider.swift` — BackupProvider conformance (ZIP to iCloud Drive)
- Create: `vreader/Views/Settings/ICloudBackupSettingsView.swift` — backup/restore UI
- Create: `vreaderTests/Services/Backup/ICloudBackupProviderTests.swift`

**Tests FIRST**:
- `testICloudBackup_createsZIPInICloudDrive`
- `testICloudBackup_includesAllBackupData`
- `testICloudBackup_listBackups_fromICloudDrive`
- `testICloudRestore_extractsZIPFromICloudDrive`
- `testICloudBackup_noICloudAccount_returnsError`
- `testICloudBackup_quotaExhausted_returnsError`
- `testICloudBackup_progressReported`

**Implementation approach**:
1. ICloudBackupProvider implements BackupProvider protocol (same interface as WebDAVProvider)
2. Uses FileManager.default.url(forUbiquityContainerIdentifier:) to access iCloud Drive
3. Backup format: same ZIP as E01 — `metadata.json` + `annotations.json` + `positions.json` + `settings.json`
4. Stored at `<iCloudContainer>/VReader/backups/<timestamp>.vreader.zip`
5. No CloudKit API needed — just iCloud Drive file operations

**Edge cases**: No iCloud account signed in, iCloud Drive disabled, quota full, slow upload (progress tracking).

**Acceptance criteria**: Full backup/restore cycle via iCloud Drive. Same ZIP format as WebDAV. Progress reported. Error messages for no-account / quota-full.

**Dependencies**: WI-F04 (BackupProvider protocol) — done.

**Effort**: M

---

## WI-E02b: #10 iCloud Live Sync (via CloudKit)

**Problem**: Live sync across devices (not just backup/restore) requires CloudKit for real-time propagation of settings, reading positions, and annotations. Design doc at `docs/codex-plans/icloud-backup-design.md`.

**Note**: E02b is separate from E02a. Snapshot backup (E02a) is simpler and ships first. Live sync is a larger effort that builds on existing Sync infrastructure.

**Files to create/modify**:
- Create: `vreader/Services/Backup/CloudKitSyncProvider.swift` — CloudKit live sync
- Create: `vreader/Services/Backup/CloudKitRecordMapper.swift` — SwiftData ↔ CloudKit mapping
- Create: `vreader/Services/Backup/ICloudDocumentManager.swift` — book file sync
- Create: `vreader/Views/Settings/ICloudSyncSettingsView.swift` — sync toggle + status
- Create: `vreaderTests/Services/Backup/CloudKitSyncProviderTests.swift`
- Create: `vreaderTests/Services/Backup/CloudKitRecordMapperTests.swift`
- Modify: `vreader/Services/Sync/SyncService.swift` — wire CloudKit integration
- Modify: `vreader/Services/Sync/TombstoneStore.swift` — add SwiftData persistence
- Modify: `vreader/Services/PreferenceStore.swift` — add NSUbiquitousKeyValueStore

**Tests FIRST**:
- `testRecordMapper_bookToCloudKit_roundTrip`
- `testRecordMapper_highlightToCloudKit_roundTrip`
- `testRecordMapper_bookmarkToCloudKit_roundTrip`
- `testRecordMapper_readingPositionToCloudKit_roundTrip`
- `testRecordMapper_readingSessionToCloudKit_roundTrip`
- `testRecordMapper_locatorJSON_preservedOpaque`
- `testRecordMapper_unknownFields_ignored`
- `testCloudKitSync_push_createsRecords`
- `testCloudKitSync_pull_appliesRecords`
- `testCloudKitSync_conflictResolution_usesExistingResolver`
- `testTombstoneStore_persistsToSwiftData`
- `testTombstoneStore_purgeAfter30Days`
- `testNSUKVS_settingsSync_roundTrip`
- `testSchemaVersion_newerRemote_readOnlyMode`
- `testSchemaVersion_olderRemote_processesFine`

**Implementation approach**:
1. Phase 1 (settings + positions): NSUbiquitousKeyValueStore for prefs, CloudKit custom zone for positions
2. Phase 2 (annotations): CloudKit records for Bookmark, Highlight, AnnotationNote with tombstone sync
3. Phase 3 (book files): iCloud Documents with FileAvailabilityStateMachine (already implemented)
4. CloudKitRecordMapper converts between SwiftData models and CKRecord
5. Locator stored as JSON blob (locatorJSON) for forward compatibility
6. SyncConflictResolver (already implemented) handles all conflict types
7. Feature-flagged behind FeatureFlags.sync

**Edge cases**: iCloud quota exhaustion, account change, schema version mismatch, offline queue, large annotation sets (batch 400 records), simultaneous edit on two devices, tombstone purge timing.

**Acceptance criteria**: Settings sync via NSUKVS. Reading positions sync across devices. Annotations sync with conflict resolution. Feature flag controls enablement. Status visible in settings.

**Dependencies**: WI-F04 (BackupProvider protocol) — done. Existing Sync infrastructure (SyncConflictResolver, TombstoneStore, SyncService, SyncStatusMonitor) — all implemented.

**Effort**: L

---

## WI-E03: Text-Mapping Layer

**Problem**: Display text transformations (simp/trad conversion, content replacement) change character positions. Without a mapping layer, highlights and search results would point to wrong locations after transformation.

**Files to create/modify**:
- Create: `vreader/Services/TextMapping/TextMapper.swift` — bidirectional offset mapping
- Create: `vreader/Services/TextMapping/TextTransform.swift` — protocol for transforms
- Create: `vreader/Services/TextMapping/OffsetMap.swift` — offset lookup table
- Create: `vreaderTests/Services/TextMapping/TextMapperTests.swift`
- Create: `vreaderTests/Services/TextMapping/OffsetMapTests.swift`

**Tests FIRST**:
- `testIdentityTransform_offsetsUnchanged`
- `testSingleCharReplace_offsetShifts`
- `testMultiCharToSingle_offsetCompresses`
- `testSingleToMultiChar_offsetExpands`
- `testChainedTransforms_offsetsCompose`
- `testDisplayToSource_roundTrip`
- `testSourceToDisplay_roundTrip`
- `testHighlightRange_afterTransform_pointsToCorrectText`
- `testSearchResult_afterTransform_pointsToCorrectOffset`
- `testEmptyText_noOp`
- `testTransform_CJKCharacters_correctMapping`
- `testTransform_mixedScript_correctMapping`
- `testLargeText_100KChars_performsUnder100ms`
- `testSearchAfterTransform_resultsPointToCorrectSourcePositions`
- `testHighlightRestoreAfterTransform_anchorsMappedCorrectly`

**Integration dependencies**: SearchIndexStore (must re-index using display text, map results back to source offsets) and LocatorFactory (highlight anchors must survive round-trip through transforms).

**Implementation approach**:
1. OffsetMap: sorted array of `(sourceOffset, displayOffset, lengthDelta)` entries
2. Binary search for offset lookup (O(log n))
3. TextMapper: applies transforms to source text, builds OffsetMap
4. TextTransform protocol: `transform(input: String) -> (output: String, offsetMap: OffsetMap)`
5. Transforms are chainable: OffsetMap.compose(other: OffsetMap)
6. Integration point: ReflowableTextSource adapter wraps transformed text

**Edge cases**: One-to-many character mappings (simplified to traditional), many-to-one, overlapping transforms, empty transform, transform that produces identical text, CJK punctuation changes, zero-width characters.

**Acceptance criteria**: After any text transform, highlight offsets map back to correct source text. Search results point to correct positions. Offset mapping round-trips correctly. Performance: 100K chars in <100ms.

**Dependencies**: WI-F03 (ReflowableTextSource) — done. Also integrates with SearchIndexStore (search re-index after transform) and LocatorFactory (highlight anchor mapping).

**Effort**: M

---

## WI-E04: #28 Simplified/Traditional Chinese Conversion

**Problem**: Many Chinese books exist in only one script variant. Readers need display-time conversion between Simplified and Traditional Chinese.

**Files to create/modify**:
- Create: `vreader/Services/TextMapping/SimpTradTransform.swift`
- Create: `vreader/Services/TextMapping/SimpTradDictionary.swift` — conversion tables
- Create: `vreaderTests/Services/TextMapping/SimpTradTransformTests.swift`
- Modify: `vreader/Services/ReaderSettingsStore.swift` — add conversion toggle

**Tests FIRST**:
- `testSimpToTrad_basicCharacters`
- `testTradToSimp_basicCharacters`
- `testSimpToTrad_multiCharMapping` (e.g., 发 → 發/髮 context-dependent)
- `testTradToSimp_multiCharMapping`
- `testConversion_mixedScriptText_onlyCJKConverted`
- `testConversion_punctuation_preserved`
- `testConversion_emptyText_noOp`
- `testConversion_alreadyInTargetScript_noOp`
- `testOffsetMap_afterConversion_highlightsCorrect`
- `testConversion_1MBText_under500ms`

**Implementation approach**:
1. Bundle OpenCC (Open Chinese Convert) conversion tables for accurate context-aware conversion. OpenCC handles context-dependent mappings (e.g., 发 → 發/髮) that simple character tables miss.
2. ICU (via Foundation's CFStringTransform) as fallback for environments where bundled tables are unavailable.
3. Note: `kCFStringTransformMandarinToLatin` is for pinyin romanization, NOT simp/trad conversion — do not use it here.
4. SimpTradTransform conforms to TextTransform protocol from E03
5. Produces OffsetMap for highlight/search preservation
6. Toggle in ReaderSettingsStore: `.none`, `.simpToTrad`, `.tradToSimp`
7. Applied at display time via ReflowableTextSource adapter

**Edge cases**: Context-dependent characters (发 can be 發 or 髮), Japanese kanji (should not be converted), mixed simp+trad text, very large files, conversion of metadata (title, author).

**Acceptance criteria**: Conversion is visually correct for common text. Context-dependent characters use best-effort mapping. Highlights survive conversion. Performance: 1MB text in <500ms. Toggle in settings works.

**Dependencies**: WI-E03 (text-mapping layer).

**Effort**: M

---

## WI-E05: #27 Content Replacement Rules

**Problem**: Users want to fix OCR errors, remove watermarks, standardize terminology, or customize display text via regex find/replace rules. Reference: Legado's replaceRule.

**Files to create/modify**:
- Create: `vreader/Models/ContentReplacementRule.swift`
- Create: `vreader/Services/TextMapping/ReplacementTransform.swift`
- Create: `vreader/Views/Settings/ReplacementRulesView.swift`
- Create: `vreaderTests/Services/TextMapping/ReplacementTransformTests.swift`
- Create: `vreaderTests/Models/ContentReplacementRuleTests.swift`

**Tests FIRST**:
- `testReplace_simpleString_replaced`
- `testReplace_regex_groupCapture`
- `testReplace_multipleRules_appliedInOrder`
- `testReplace_noMatch_textUnchanged`
- `testReplace_emptyPattern_noOp`
- `testReplace_invalidRegex_skipped`
- `testReplace_overlappingMatches_firstWins`
- `testOffsetMap_afterReplacement_highlightsCorrect`
- `testReplace_CJKCharacters_correct`
- `testReplace_ruleCRUD_persistsToSwiftData`
- `testReplace_ruleEnabledDisabled_toggle`
- `testReplace_perBookRules_isolated`
- `testReplace_globalRules_applyToAll`
- `testReplace_catastrophicBacktracking_timesOutAt1s`
- `testReplace_timedOutRule_skippedGracefully`

**Implementation approach**:
1. ContentReplacementRule: SwiftData @Model with pattern (regex), replacement, isRegex, scope (global/per-book), enabled, order
2. ReplacementTransform conforms to TextTransform protocol from E03
3. Rules applied in order (lower order number first)
4. Per-book rules override global rules for the same pattern
5. UI: list of rules with drag-to-reorder, enable/disable toggles, add/edit/delete
6. Applied at display time via ReflowableTextSource adapter (same as E04)

**Edge cases**: Catastrophic regex backtracking (timeout at 1s per rule), replacement that creates new matches (no re-application), empty replacement (deletion), replacement changing text length (offset map), Unicode regex features.

**Regex timeout mechanism**: NSRegularExpression itself has no built-in timeout. Implement timeout via DispatchWorkItem: wrap each rule evaluation in a work item, cancel after 1 second. If cancelled, skip the rule and log a warning. This prevents catastrophic backtracking from freezing the UI.

**Acceptance criteria**: String and regex replacements work. Rules persist. Per-book and global scopes. Highlights survive replacement. Invalid regex doesn't crash.

**Dependencies**: WI-E03 (text-mapping layer).

**Effort**: M

---

## WI-E06: #26 HTTP TTS (Cloud Voices)

**Problem**: System AVSpeechSynthesizer voices are limited. Cloud TTS services (Azure, Google, custom) offer higher quality and more language options.

**Files to create/modify**:
- Create: `vreader/Services/TTS/HTTPTTSProvider.swift`
- Create: `vreader/Services/TTS/HTTPTTSConfig.swift` — API endpoint, key, voice config
- Create: `vreader/Services/TTS/TTSProviderProtocol.swift` — shared interface
- Create: `vreader/Views/Settings/HTTPTTSSettingsView.swift`
- Create: `vreaderTests/Services/TTS/HTTPTTSProviderTests.swift`
- Modify: `vreader/Services/TTS/TTSService.swift` — accept TTSProvider instead of SpeechSynthesizing

**Tests FIRST**:
- `testHTTPTTS_synthesize_returnsAudioData`
- `testHTTPTTS_chunkedSynthesis_splitsLongTextIntoSegments`
- `testHTTPTTS_chunkedSynthesis_progressCallback_reportsPerChunk`
- `testHTTPTTS_streamingAudio_playsWhileNextChunkFetches`
- `testHTTPTTS_networkError_fallsBackToSystem`
- `testHTTPTTS_rateLimiting_queuesRequests`
- `testHTTPTTS_cancelDuringSynthesis_stops`
- `testHTTPTTS_chunkText_intoSentences`
- `testHTTPTTS_cacheAudio_skipsDuplicateRequest`
- `testHTTPTTS_positionTracking_matchesAudioProgress`
- `testHTTPTTS_configValidation_rejectsEmptyURL`
- `testHTTPTTS_configValidation_rejectsEmptyKey`
- `testHTTPTTS_azureAPI_correctHeaders`
- `testHTTPTTS_customAPI_configurableEndpoint`

**Implementation approach**:
1. TTSProviderProtocol (expanded):
   ```
   protocol TTSProviderProtocol {
       func synthesize(text: String, voice: String) async throws -> Data
       func synthesizeChunked(text: String, voice: String, onChunk: @escaping (TTSChunk) -> Void, onProgress: @escaping (TTSProgress) -> Void) async throws
       func cancel()
   }
   struct TTSChunk { let audioData: Data; let textRange: Range<String.Index>; let index: Int; let total: Int }
   struct TTSProgress { let chunkIndex: Int; let totalChunks: Int; let bytesReceived: Int }
   ```
2. HTTPTTSProvider: URLSession-based, configurable endpoint/headers/voice
3. Chunked synthesis: split text into sentences, synthesize each chunk separately, stream audio (play chunk N while fetching chunk N+1)
4. Progress callback fires per chunk with index/total for UI progress bar
5. Cache audio chunks on disk (similar pattern to ChapterCache)
6. Position tracking: calculate from audio duration + chunk offsets
7. Fallback to system TTS on network failure
8. Support Azure Cognitive Services and generic REST APIs
9. API key stored in Keychain via KeychainService

**Edge cases**: Very long sentences (split at 500 chars), network dropout mid-synthesis, API rate limits, audio format differences (MP3 vs WAV), CJK text chunking (sentence boundaries differ), API key rotation.

**Acceptance criteria**: HTTP TTS plays audio with position tracking. Falls back to system TTS on failure. Audio caching works. Azure API integration tested. Custom endpoint configurable.

**Dependencies**: WI-B03 (system TTS — done, provides base architecture).

**Effort**: M

---

## Sprint Plan

**Sprint E1** (parallel): E01 (WebDAV) + E02a (iCloud snapshot backup) + E06 (HTTP TTS) — independent.
**Sprint E1b** (after E01/E02a): E02b (iCloud live sync) — builds on snapshot backup + existing sync infra.
**Sprint E2** (sequential): E03 (text-mapping layer) — foundational for E04+E05.
**Sprint E3** (parallel, after E03): E04 (simp/trad) + E05 (replacement rules) — both use E03.

## Checkpoint Criteria

- WebDAV backup/restore works with Nutstore/NextCloud
- iCloud snapshot backup/restore works via iCloud Drive (E02a)
- iCloud live sync works for settings + positions + annotations (E02b)
- Text transforms don't break highlights or search
- Simp/Trad toggle works with correct character mapping
- Content replacement rules apply at display time
- HTTP TTS plays with position tracking and fallback
- All existing tests pass

## Manual Testing

See `docs/manual-test-checklist.md` for phase-specific test items.
