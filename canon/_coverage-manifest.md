# vreader coverage manifest v2 (generated 2026-07-11, patched post-C1a/C1b Codex audit)

Universe command (repo root): `git ls-files -co --exclude-standard` — 4621 paths.
Levels are ordered cumulative: listed < described < behavioral.
Ledger: canon/_coverage-ledger.json (per-file rows for described/behavioral; group rows for listed/excluded).

## Per-file rows (described/behavioral)

| path | level | owning dossier |
|---|---|---|
| .claude/hooks/__tests__/check_audit_debt.test.sh | behavioral | Module — automation and tooling |
| .claude/hooks/__tests__/check_codex_audit_artifact.test.sh | behavioral | Module — automation and tooling |
| .claude/hooks/__tests__/check_gh_issue_mirror.test.sh | behavioral | Module — automation and tooling |
| .claude/hooks/__tests__/check_terminal_status_evidence.test.sh | behavioral | Module — automation and tooling |
| .claude/hooks/__tests__/check_unfinished_verification.test.sh | behavioral | Module — automation and tooling |
| .claude/hooks/__tests__/code_paths_platform.test.sh | behavioral | Module — automation and tooling |
| .claude/hooks/check_audit_debt.sh | behavioral | Module — automation and tooling |
| .claude/hooks/check_codex_audit_artifact.sh | behavioral | Module — automation and tooling |
| .claude/hooks/check_gh_issue_mirror.sh | behavioral | Module — automation and tooling |
| .claude/hooks/check_terminal_status_evidence.sh | behavioral | Module — automation and tooling |
| .claude/hooks/check_unfinished_verification.sh | behavioral | Module — automation and tooling |
| .claude/hooks/lib/code-paths.sh | behavioral | Module — automation and tooling |
| .claude/hooks/refine_prompt.sh | behavioral | Module — automation and tooling |
| .claude/hooks/refine_prompt.txt | behavioral | Module — automation and tooling |
| .claude/rules/47-feature-workflow.md | described | Decision — six-gate workflow and lane dispatch |
| .claude/rules/48-parallel-execution.md | described | Decision — six-gate workflow and lane dispatch |
| .claude/rules/55-lane-dispatch.md | described | Decision — six-gate workflow and lane dispatch |
| .claude/skills/dispatch/SKILL.md | behavioral | Decision — six-gate workflow and lane dispatch |
| AGENTS.md | described | Module — automation and tooling |
| BUREAU.md | described | Decision — composite dossier schema |
| README.md | described | Architecture — system overview |
| android/app/build.gradle.kts | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/ai/AiChatPanelTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/ai/AiProviderEditSheetTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/ai/AiProviderListScreenTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/ai/AiRoundTripConnectedTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/annotations/AnnotationsConnectedTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/annotations/SelectionPopoverUiTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/backup/BackupRestoreScreenTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/backup/RestoreFlowTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/backup/SelectiveRestoreSheetTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/backup/ServerEditSheetTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/backup/WebDavRoundTripConnectedTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/backup/WebDavServersScreenTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/library/AssignSheetUiTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/library/CollectionShelfBarUiTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/library/ManageSheetUiTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/opds/OpdsRoundTripConnectedTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/opds/ui/OpdsAddSheetTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/opds/ui/OpdsBrowseScreenTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/opds/ui/OpdsErrorViewTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/opds/ui/OpdsSourceListScreenTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/opds/ui/OpdsUiRoundTripConnectedTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/reader/Azw3ReaderActivityTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/reader/BookOpenerTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/reader/MdHighlightConnectedTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/reader/MdReaderHighlightUiTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/reader/MdReaderRenderTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/reader/PdfDocumentTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/reader/PdfReaderActivityTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/reader/ReaderActivityTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/reader/TxtHighlightConnectedTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/reader/TxtReaderActivityTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/reader/chrome/ReaderBottomChromeUiTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/reader/foliate/FoliateSpikeHarnessTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/reader/settings/ReaderSettingsSheetUiTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/stats/ReadingStatsConnectedTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/stats/StatsUiTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/tts/AndroidTtsEngineTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/tts/TtsControlBarTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/tts/TtsSheetsTest.kt | behavioral | Module — Android port |
| android/app/src/androidTest/kotlin/com/vreader/app/tts/TxtTtsConnectedTest.kt | behavioral | Module — Android port |
| android/app/src/debug/kotlin/com/vreader/app/backup/BackupDebugActivity.kt | behavioral | Module — Android port |
| android/app/src/debug/kotlin/com/vreader/app/backup/PreviewBackupService.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/MainActivity.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/ai/AiChatPanel.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/ai/AiChatUiState.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/ai/AiChatViewModel.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/ai/AiClient.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/ai/AiMarkdownRenderer.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/ai/AiProviderEditSheet.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/ai/AiProviderFactory.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/ai/AiProviderKind.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/ai/AiProviderListScreen.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/ai/AiProviderStore.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsUiState.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsViewModel.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/ai/AiTypes.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/ai/AnthropicProvider.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/ai/OpenAiCompatibleProvider.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/ai/SseEventReader.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/annotations/Annotation.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/annotations/AnnotationAnchor.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/annotations/AnnotationColor.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/annotations/AnnotationsRepository.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/annotations/EpubAnnotationMapper.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/annotations/SelectionPopover.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/annotations/SelectionPopoverViewModel.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/backup/BackupCollector.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/backup/BackupRestoreScreen.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/backup/BackupScaffold.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/backup/BackupService.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/backup/BackupTokens.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/backup/BackupUiState.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/backup/BackupViewModel.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/backup/RestoreFlow.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/backup/RestoreImporter.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/backup/SelectiveRestoreSheet.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/backup/ServerEditSheet.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/backup/WebDavBackupService.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/backup/WebDavServersScreen.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/backup/archive/BackupArchive.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/backup/archive/BlobPath.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/backup/net/SecretCipher.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/backup/net/WebDavClient.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/backup/net/WebDavServerStore.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/data/BookImporter.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/data/CollectionDao.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/data/CollectionEntities.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/data/CollectionRepository.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/data/Daos.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/data/Entities.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/data/LibraryRepository.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/data/VReaderDatabase.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/library/CollectionManageSheet.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/library/CollectionSheets.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/library/CollectionShelfBar.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/library/LibraryScreen.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/library/LibraryViewModel.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/opds/OpdsAcquisitionService.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/opds/OpdsClient.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/opds/OpdsModels.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/opds/OpdsParser.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/opds/OpdsSourceStore.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/opds/ui/OpdsAddSheet.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/opds/ui/OpdsBrowseScreen.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/opds/ui/OpdsBrowseUiState.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/opds/ui/OpdsBrowseViewModel.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/opds/ui/OpdsErrorView.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/opds/ui/OpdsSourceListScreen.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/opds/ui/OpdsSourcesUiState.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/opds/ui/OpdsSourcesViewModel.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/reader/BookOpener.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/reader/ChunkTextMapper.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/reader/MarkdownOffsetMap.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/reader/MarkdownRenderer.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/reader/PdfDocument.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/reader/ReaderHighlightController.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/reader/ReadiumLocatorBridge.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/reader/ResumeResolver.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/reader/TxtDecoder.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/reader/TxtDocument.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/reader/TxtHighlightHitTester.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/reader/TxtHighlightWash.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/reader/TxtProgress.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/reader/TxtSelection.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/reader/TxtSourceOffsets.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderBottomChrome.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/reader/foliate/Azw3Document.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/reader/foliate/Azw3LocatorBridge.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/reader/foliate/FoliateAssetServer.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/reader/foliate/FoliateBridge.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/reader/foliate/FoliateBridgePolicy.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/reader/foliate/FoliateMessage.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/reader/foliate/FoliateMessageParser.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettings.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsSheet.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsStore.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderTheme.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/stats/InReaderTimePill.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/stats/ReadingStatsRepository.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/stats/ReadingTimeTracker.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/stats/StatsDashboard.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/stats/StatsUiState.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/stats/StatsViewModel.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/stats/clock/Clocks.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/tts/AndroidTtsEngine.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/tts/TtsChunker.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/tts/TtsControlBar.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/tts/TtsEngine.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/tts/TtsHighlight.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/tts/TtsModels.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/tts/TtsSpeedSheet.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/tts/TtsUiState.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/tts/TtsViewModel.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/tts/TtsVoiceFilter.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/tts/TtsVoiceSheet.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/ui/theme/Theme.kt | behavioral | Module — Android port |
| android/app/src/main/kotlin/com/vreader/app/xml/SafeXml.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/VersionWiringTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/ai/AiChatViewModelTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/ai/AiFakeServer.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/ai/AiMarkdownRendererTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/ai/AiProviderKindTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/ai/AiProviderStoreTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/ai/AiSettingsViewModelTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/ai/AnthropicProviderTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/ai/OpenAiCompatibleProviderTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/ai/SseEventReaderTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/annotations/AnnotationAnchorTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/annotations/AnnotationColorTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/annotations/AnnotationsRepositoryTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/annotations/EpubAnnotationMapperTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/annotations/SelectionPopoverViewModelTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/backup/BackupCollectorTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/backup/BackupColorTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/backup/BackupViewModelTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/backup/CollectionBackupTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/backup/RestoreImporterTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/backup/WebDavBackupServiceTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/backup/archive/BackupArchiveTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/backup/net/WebDavClientTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/backup/net/WebDavServerStoreTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/data/AnnotationDaoTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/data/BookImporterTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/data/CollectionDaoTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/data/CollectionRepositoryTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/data/LibraryRepositoryTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/data/ReadingStatsDaoTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/data/VReaderDatabaseMigrationTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/library/LibraryViewModelCollectionsTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/library/LibraryViewModelTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/opds/OpdsAcquisitionServiceTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/opds/OpdsClientAuthTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/opds/OpdsClientTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/opds/OpdsParserTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/opds/OpdsSourceStoreTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/opds/ui/OpdsBrowseViewModelTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/opds/ui/OpdsSourcesViewModelTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/reader/ChunkTextMapperTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/reader/MarkdownOffsetMapTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/reader/MarkdownRenderMapTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/reader/MarkdownRendererTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/reader/MdHighlightWashTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/reader/MdResumeTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/reader/PdfResumeTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/reader/ReadiumLocatorBridgeTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/reader/ResumeResolverTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/reader/TxtDecoderTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/reader/TxtDocumentTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/reader/TxtHighlightHitTesterTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/reader/TxtProgressTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/reader/TxtResumeTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/reader/TxtSelectionValidateTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/reader/TxtSourceOffsetsTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/reader/TxtWashMapperTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/reader/foliate/Azw3BackupRoundTripTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/reader/foliate/Azw3LocatorBridgeTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/reader/foliate/FoliateBridgePolicyTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/reader/foliate/FoliateBundleProvenanceTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/reader/foliate/FoliateMessageParserTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/reader/settings/ReaderSettingsStoreTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/reader/settings/ReaderThemeTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/stats/DateClockTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/stats/ReadingStatsRepositoryTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/stats/ReadingTimeTrackerTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/stats/StatsViewModelTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/tts/TtsChunkerTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/tts/TtsHighlightTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/tts/TtsModelsTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/tts/TtsViewModelTest.kt | behavioral | Module — Android port |
| android/app/src/test/kotlin/com/vreader/app/tts/TtsVoiceFilterTest.kt | behavioral | Module — Android port |
| android/build.gradle.kts | behavioral | Module — Android port |
| android/identity/build.gradle.kts | behavioral | Module — cross-platform contracts |
| android/identity/src/main/kotlin/vreader/contracts/DocumentFingerprint.kt | behavioral | Module — cross-platform contracts |
| android/identity/src/main/kotlin/vreader/contracts/Identity.kt | behavioral | Module — cross-platform contracts |
| android/identity/src/main/kotlin/vreader/contracts/Locator.kt | behavioral | Module — cross-platform contracts |
| android/identity/src/main/kotlin/vreader/contracts/VReaderLocator.kt | behavioral | Module — cross-platform contracts |
| android/identity/src/main/kotlin/vreader/contracts/backup/BackupDefaultsValue.kt | behavioral | Module — cross-platform contracts |
| android/identity/src/main/kotlin/vreader/contracts/backup/BackupJson.kt | behavioral | Module — cross-platform contracts |
| android/identity/src/main/kotlin/vreader/contracts/backup/BackupMetadata.kt | behavioral | Module — cross-platform contracts |
| android/identity/src/main/kotlin/vreader/contracts/backup/BackupSchema.kt | behavioral | Module — cross-platform contracts |
| android/identity/src/main/kotlin/vreader/contracts/backup/BackupSections.kt | behavioral | Module — cross-platform contracts |
| android/identity/src/main/kotlin/vreader/contracts/backup/BackupSectionsExtended.kt | behavioral | Module — cross-platform contracts |
| android/identity/src/test/kotlin/vreader/contracts/IdentityConformanceTest.kt | behavioral | Module — cross-platform contracts |
| android/identity/src/test/kotlin/vreader/contracts/backup/BackupConformanceTest.kt | behavioral | Module — cross-platform contracts |
| android/identity/src/test/kotlin/vreader/contracts/backup/BackupSectionsExtendedTest.kt | behavioral | Module — cross-platform contracts |
| android/identity/src/test/kotlin/vreader/contracts/backup/BackupSectionsTest.kt | behavioral | Module — cross-platform contracts |
| android/settings.gradle.kts | behavioral | Module — Android port |
| archive/bugs-history.md | described | Timeline — bug history and recurring classes |
| archive/comprehensive-testing-guide.md | described | Module — test architecture |
| archive/pr-checklist.md | described | Decision — six-gate workflow and lane dispatch |
| contracts/README.md | described | Module — cross-platform contracts |
| contracts/conformance/README.md | described | Module — cross-platform contracts |
| contracts/conformance/run.sh | behavioral | Module — cross-platform contracts |
| contracts/identity/DECISION.md | described | Module — cross-platform contracts |
| contracts/identity/backup-format.md | described | Module — cross-platform contracts |
| contracts/identity/cache-key.md | described | Module — cross-platform contracts |
| contracts/identity/fingerprint.md | described | Module — cross-platform contracts |
| contracts/identity/locator.md | described | Module — cross-platform contracts |
| dev-docs/README.md | described | Module — automation and tooling |
| dev-docs/debug-bridge.md | described | Module — debug bridge |
| dev-docs/verification-red-checks.md | described | Module — test architecture |
| docs/architecture.md | described | Architecture — system overview |
| docs/bugs.md | described | Timeline — bug history and recurring classes |
| docs/decisions/0001-android-port-strategy.md | described | Decision — Android port strategy |
| docs/decisions/README.md | described | Decision — Android port strategy |
| docs/features.md | described | Timeline — feature delivery history |
| docs/icon.png | listed | Architecture — system overview |
| docs/manual-test-checklist.md | described | Module — test architecture |
| docs/subsystems/debug-bridge.md | described | Module — debug bridge |
| docs/subsystems/sim-gesture-driver.md | described | Module — debug bridge |
| docs/tasks.md | described | Timeline — bug history and recurring classes |
| project.yml | described | Architecture — app layer and concurrency model |
| scripts/__tests__/agent-lock.test.sh | described | Module — automation and tooling |
| scripts/__tests__/check-write-set.test.sh | described | Module — automation and tooling |
| scripts/__tests__/deps-check.test.sh | described | Module — automation and tooling |
| scripts/__tests__/dispatch-shape.test.sh | described | Module — automation and tooling |
| scripts/__tests__/lock.test.sh | described | Module — automation and tooling |
| scripts/__tests__/reserve-id.test.sh | described | Module — automation and tooling |
| scripts/__tests__/run-android-tests.test.sh | described | Module — automation and tooling |
| scripts/__tests__/run-tests-watchdog.test.sh | described | Module — automation and tooling |
| scripts/__tests__/sim-lease.test.sh | described | Module — automation and tooling |
| scripts/__tests__/sweep-locks.test.sh | described | Module — automation and tooling |
| scripts/__tests__/tdd-guardian-test.test.sh | described | Module — automation and tooling |
| scripts/__tests__/worktree.test.sh | described | Module — automation and tooling |
| scripts/agent-lock.sh | behavioral | Module — automation and tooling |
| scripts/b329-1px-sweep.sh | behavioral | Module — automation and tooling |
| scripts/b329-analyze.py | behavioral | Module — automation and tooling |
| scripts/b329-gesture-probe.sh | behavioral | Module — automation and tooling |
| scripts/check-write-set.sh | behavioral | Module — automation and tooling |
| scripts/deps-check.sh | behavioral | Module — automation and tooling |
| scripts/grant-debug-scheme-approval.sh | behavioral | Module — automation and tooling |
| scripts/injection-canary-test.sh | behavioral | Module — automation and tooling |
| scripts/lib/lock.sh | behavioral | Module — automation and tooling |
| scripts/reserve-id.sh | behavioral | Module — automation and tooling |
| scripts/run-ai-roundtrip.sh | behavioral | Module — automation and tooling |
| scripts/run-android-tests.sh | behavioral | Module — automation and tooling |
| scripts/run-android-verify.sh | behavioral | Module — automation and tooling |
| scripts/run-codex.sh | behavioral | Module — automation and tooling |
| scripts/run-opds-roundtrip.sh | behavioral | Module — automation and tooling |
| scripts/run-tests.sh | behavioral | Module — automation and tooling |
| scripts/run-webdav-roundtrip.sh | behavioral | Module — automation and tooling |
| scripts/scan-untrusted-content.sh | behavioral | Module — automation and tooling |
| scripts/sim-lease.sh | behavioral | Module — automation and tooling |
| scripts/sim-tap.sh | behavioral | Module — automation and tooling |
| scripts/sweep-ghosts.sh | behavioral | Module — automation and tooling |
| scripts/tdd-guardian-test.sh | behavioral | Module — automation and tooling |
| scripts/verify-debug-has-debugbridge.sh | behavioral | Module — automation and tooling |
| scripts/verify-release-no-debugbridge.sh | behavioral | Module — automation and tooling |
| scripts/worktree-setup.sh | behavioral | Module — automation and tooling |
| scripts/worktree-teardown.sh | behavioral | Module — automation and tooling |
| spikes/android-reader-bench/app/build.gradle.kts | behavioral | Module — Android port |
| spikes/android-reader-bench/app/src/androidTest/kotlin/vreader/spike/AnchorRestoreTest.kt | behavioral | Module — Android port |
| spikes/android-reader-bench/app/src/androidTest/kotlin/vreader/spike/ReaderScrollBenchmark.kt | behavioral | Module — Android port |
| spikes/android-reader-bench/app/src/androidTest/kotlin/vreader/spike/SmokeTest.kt | behavioral | Module — Android port |
| spikes/android-reader-bench/app/src/main/kotlin/vreader/spike/ReaderOpener.kt | behavioral | Module — Android port |
| spikes/android-reader-bench/app/src/main/kotlin/vreader/spike/ScrollMetrics.kt | behavioral | Module — Android port |
| spikes/android-reader-bench/build.gradle.kts | behavioral | Module — Android port |
| spikes/android-reader-bench/fixtures/make-mini-cjk-epub.py | behavioral | Module — Android port |
| spikes/android-reader-bench/run-bench.sh | behavioral | Module — Android port |
| spikes/android-reader-bench/settings.gradle.kts | behavioral | Module — Android port |
| vreader/App/AITestSetup.swift | behavioral | Architecture — app layer and concurrency model |
| vreader/App/AppConfiguration.swift | behavioral | Architecture — app layer and concurrency model |
| vreader/App/ModelContainerFactory.swift | behavioral | Architecture — app layer and concurrency model |
| vreader/App/TestSeeder.swift | behavioral | Architecture — app layer and concurrency model |
| vreader/App/VReaderApp.swift | behavioral | Architecture — app layer and concurrency model |
| vreader/App/VReaderAppDelegate.swift | behavioral | Architecture — app layer and concurrency model |
| vreader/Models/AccentColor.swift | described | Module — persistence and data model |
| vreader/Models/AnnotationAnchor.swift | described | Module — annotations and highlights |
| vreader/Models/AnnotationNote.swift | described | Module — persistence and data model |
| vreader/Models/Book.swift | described | Module — persistence and data model |
| vreader/Models/BookCollection.swift | described | Module — persistence and data model |
| vreader/Models/BookFileState.swift | described | Module — persistence and data model |
| vreader/Models/BookFormat.swift | described | Module — persistence and data model |
| vreader/Models/BookSource.swift | described | Module — persistence and data model |
| vreader/Models/BookSourceRules.swift | described | Module — persistence and data model |
| vreader/Models/Bookmark.swift | described | Module — persistence and data model |
| vreader/Models/ChapterTranslation.swift | described | Module — persistence and data model |
| vreader/Models/ChapterTranslationRecord.swift | described | Module — persistence and data model |
| vreader/Models/ChatMessage.swift | described | Module — persistence and data model |
| vreader/Models/ChatSession.swift | described | Module — persistence and data model |
| vreader/Models/ChatSessionPayload.swift | described | Module — persistence and data model |
| vreader/Models/ContentReplacementRule.swift | described | Module — persistence and data model |
| vreader/Models/DocumentFingerprint.swift | described | Module — persistence and data model |
| vreader/Models/EPUBLayoutPreference.swift | described | Module — settings and preferences |
| vreader/Models/ExportedAnnotation.swift | described | Module — export |
| vreader/Models/FontSizeCalibration.swift | described | Module — settings and preferences |
| vreader/Models/FormatCapabilities.swift | described | Architecture — reader dispatch and format hosts |
| vreader/Models/GenerativeCoverStyle.swift | described | Module — persistence and data model |
| vreader/Models/Highlight.swift | described | Module — persistence and data model |
| vreader/Models/HighlightPopoverAction.swift | described | Module — persistence and data model |
| vreader/Models/ImportProvenance.swift | described | Module — persistence and data model |
| vreader/Models/ImportSource.swift | described | Module — persistence and data model |
| vreader/Models/ImportedBookFileURL.swift | described | Module — persistence and data model |
| vreader/Models/LegadoBookSourceDTO.swift | described | Module — persistence and data model |
| vreader/Models/LibraryBookItem.swift | described | Module — persistence and data model |
| vreader/Models/LibrarySortOrder.swift | described | Module — persistence and data model |
| vreader/Models/Locator.swift | described | Module — locator |
| vreader/Models/Migration/LocatorKeyBackfillMigration.swift | behavioral | Architecture — schema migration history |
| vreader/Models/Migration/SchemaV1.swift | behavioral | Architecture — schema migration history |
| vreader/Models/Migration/SchemaV10.swift | behavioral | Architecture — schema migration history |
| vreader/Models/Migration/SchemaV2.swift | behavioral | Architecture — schema migration history |
| vreader/Models/Migration/SchemaV3.swift | behavioral | Architecture — schema migration history |
| vreader/Models/Migration/SchemaV4.swift | behavioral | Architecture — schema migration history |
| vreader/Models/Migration/SchemaV5.swift | behavioral | Architecture — schema migration history |
| vreader/Models/Migration/SchemaV6.swift | behavioral | Architecture — schema migration history |
| vreader/Models/Migration/SchemaV7.swift | behavioral | Architecture — schema migration history |
| vreader/Models/Migration/SchemaV8.swift | behavioral | Architecture — schema migration history |
| vreader/Models/Migration/SchemaV9.swift | behavioral | Architecture — schema migration history |
| vreader/Models/Migration/V1toV2Migration.swift | behavioral | Architecture — schema migration history |
| vreader/Models/NamedHighlightColor.swift | described | Module — annotations and highlights |
| vreader/Models/ReaderEngine.swift | described | Architecture — reader dispatch and format hosts |
| vreader/Models/ReaderTheme+ToV2.swift | described | Module — settings and preferences |
| vreader/Models/ReaderTheme.swift | described | Module — persistence and data model |
| vreader/Models/ReaderThemeV2+ColorScheme.swift | described | Module — persistence and data model |
| vreader/Models/ReaderThemeV2+EPUBCSS.swift | described | Module — persistence and data model |
| vreader/Models/ReaderThemeV2.swift | described | Module — settings and preferences |
| vreader/Models/ReadingPosition.swift | described | Module — persistence and data model |
| vreader/Models/ReadingSession.swift | described | Module — persistence and data model |
| vreader/Models/ReadingStats.swift | described | Module — persistence and data model |
| vreader/Models/SelectionPopoverAction.swift | described | Module — persistence and data model |
| vreader/Models/SettingsRowPalette+SwiftUI.swift | described | Module — persistence and data model |
| vreader/Models/SettingsRowPalette.swift | described | Module — persistence and data model |
| vreader/Models/SheetSectionContract.swift | described | Module — persistence and data model |
| vreader/Models/TapZoneConfig.swift | described | Module — settings and preferences |
| vreader/Models/TokenSpan.swift | described | Module — persistence and data model |
| vreader/Models/TranslationUnitID.swift | described | Module — bilingual translation |
| vreader/Models/TypographySettings.swift | described | Module — settings and preferences |
| vreader/Models/UnifiedEPUBLoadResult.swift | described | Module — persistence and data model |
| vreader/Models/VReaderLocator.swift | described | Module — locator |
| vreader/Services/AI/AIChatAgenticSupport.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/AIConfiguration.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/AIConfigurationStore.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/AIConsentManager.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/AIContextExtracting.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/AIContextExtractor.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/AIError.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/AIProvider.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/AIReaderAvailability.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/AIResponseCache.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/AIService.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/AITool.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/AIToolRegistry.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/AITypes.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/AgenticChatDriver.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/AnthropicProvider+Streaming.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/AnthropicProvider+ToolUse.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/AnthropicProvider.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/BilingualAIReadiness.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/BookTranslationCoordinator.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/BookTranslationProgress.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/ChapterBounds.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/ChapterPrefetching.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/ChapterSegmenter.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/ChapterTranslationChunker.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/ChapterTranslationPrefetcher.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/ChapterTranslationService.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/ChatAnnotationCache.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/ChatAnnotationContext.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/ChatCitation.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/ChatCitationFactory.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/ChatContextAssembler.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/ChatContextScope+Menu.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/ChatContextScope.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/ChatSourceSelection.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/InterruptedTranslationJobStore.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/KeychainService+ProviderProfile.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/MockAIProvider.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/OpenAICompatibleProvider+ToolUse.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/ProviderConfigResolving.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/ProviderKind.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/ProviderProfile.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/ProviderProfileMigrator.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/ProviderProfileStore.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/ResolvedAIProviderConfig.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/SummaryScope.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/SummaryScopeResolver.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/Tools/AgenticToolRegistryBuilder.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/Tools/BookContentProviderAdapter.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/Tools/ClosedBookTextExtractor.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/Tools/GetBookContentGate.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/Tools/GetBookContentTool.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/Tools/LibraryBookSearchGate.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/Tools/LibrarySearchBackendAdapter.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/Tools/ListLibraryTool.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/Tools/SearchCurrentBookTool.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/Tools/SearchOtherBooksTool.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/Tools/ToolResultText.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/TranslationChunkContract.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/TranslationStyle.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/UTF16Clamp.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/UTF16TextSlicer.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AI/WholeBookReducer.swift | behavioral | Module — AI providers and tools |
| vreader/Services/AZW3/MOBICoverExtractor.swift | behavioral | Module — Kindle AZW3 and libmobi |
| vreader/Services/AZW3/MOBIMetadataParser.swift | behavioral | Module — Kindle AZW3 and libmobi |
| vreader/Services/AnnotationPersisting.swift | described | Module — annotations and highlights |
| vreader/Services/AnnotationRecord.swift | described | Module — annotations and highlights |
| vreader/Services/AutoPageTurner.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Services/BackgroundExecutionToken.swift | behavioral | Module — bilingual translation |
| vreader/Services/Backup/BackgroundDownloadSession.swift | behavioral | Module — backup and WebDAV |
| vreader/Services/Backup/BackupAIConversations.swift | behavioral | Module — backup and WebDAV |
| vreader/Services/Backup/BackupBlobStore.swift | behavioral | Module — backup and WebDAV |
| vreader/Services/Backup/BackupDataCollector.swift | behavioral | Module — backup and WebDAV |
| vreader/Services/Backup/BackupDataRestorer.swift | behavioral | Module — backup and WebDAV |
| vreader/Services/Backup/BackupProvider.swift | behavioral | Module — backup and WebDAV |
| vreader/Services/Backup/BackupReadingHistory.swift | behavioral | Module — backup and WebDAV |
| vreader/Services/Backup/BackupSectionDTOs.swift | behavioral | Module — backup and WebDAV |
| vreader/Services/Backup/BlobPath.swift | behavioral | Module — backup and WebDAV |
| vreader/Services/Backup/BookFileImportFinalizer.swift | behavioral | Module — backup and WebDAV |
| vreader/Services/Backup/BookFileMaterializer.swift | behavioral | Module — backup and WebDAV |
| vreader/Services/Backup/LazyDownloadCoordinator.swift | behavioral | Module — backup and WebDAV |
| vreader/Services/Backup/LazyDownloadDelegate.swift | behavioral | Module — backup and WebDAV |
| vreader/Services/Backup/LazyDownloadFinalizer.swift | behavioral | Module — backup and WebDAV |
| vreader/Services/Backup/LazyDownloadTaskMeta.swift | behavioral | Module — backup and WebDAV |
| vreader/Services/Backup/PROPFINDParser.swift | behavioral | Module — backup and WebDAV |
| vreader/Services/Backup/RemoteBookCatalog.swift | behavioral | Module — backup and WebDAV |
| vreader/Services/Backup/SelectiveRestoreCoordinator.swift | behavioral | Module — backup and WebDAV |
| vreader/Services/Backup/WebDAVBlobStore.swift | behavioral | Module — backup and WebDAV |
| vreader/Services/Backup/WebDAVClient.swift | behavioral | Module — backup and WebDAV |
| vreader/Services/Backup/WebDAVDownloadRequestBuilder.swift | behavioral | Module — backup and WebDAV |
| vreader/Services/Backup/WebDAVNetworkPolicy.swift | behavioral | Module — backup and WebDAV |
| vreader/Services/Backup/WebDAVProfileMigrator.swift | behavioral | Module — backup and WebDAV |
| vreader/Services/Backup/WebDAVProvider.swift | behavioral | Module — backup and WebDAV |
| vreader/Services/Backup/WebDAVProviderFactory.swift | behavioral | Module — backup and WebDAV |
| vreader/Services/Backup/WebDAVServerProfile.swift | behavioral | Module — backup and WebDAV |
| vreader/Services/Backup/WebDAVServerProfileStore.swift | behavioral | Module — backup and WebDAV |
| vreader/Services/Backup/ZIPWriter.swift | behavioral | Module — backup and WebDAV |
| vreader/Services/BasePageNavigator.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Services/BookContentCache.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Services/BookImporter.swift | behavioral | Module — import pipeline |
| vreader/Services/BookImporting.swift | behavioral | Module — import pipeline |
| vreader/Services/BookReadingStatsProviding.swift | behavioral | Module — reading stats |
| vreader/Services/BookSource/BookSourceHTTPClient.swift | behavioral | Module — book sources |
| vreader/Services/BookSource/BookSourcePipeline.swift | behavioral | Module — book sources |
| vreader/Services/BookSource/CSSRuleEvaluator.swift | behavioral | Module — book sources |
| vreader/Services/BookSource/ChapterCache.swift | behavioral | Module — book sources |
| vreader/Services/BookSource/HTMLHelper.swift | behavioral | Module — book sources |
| vreader/Services/BookSource/LegadoCompatibility.swift | behavioral | Module — book sources |
| vreader/Services/BookSource/LegadoImporter.swift | behavioral | Module — book sources |
| vreader/Services/BookSource/LegadoRuleParser.swift | behavioral | Module — book sources |
| vreader/Services/BookSource/PipelineTypes.swift | behavioral | Module — book sources |
| vreader/Services/BookSource/RegexRuleEvaluator.swift | behavioral | Module — book sources |
| vreader/Services/BookSource/RuleEngine.swift | behavioral | Module — book sources |
| vreader/Services/BookSource/SourceSharingService.swift | behavioral | Module — book sources |
| vreader/Services/BookSource/UpdateChecker.swift | behavioral | Module — book sources |
| vreader/Services/BookSource/WebPageEncodingDetector.swift | behavioral | Module — book sources |
| vreader/Services/BookmarkPersisting.swift | described | Module — annotations and highlights |
| vreader/Services/BookmarkRecord.swift | described | Module — annotations and highlights |
| vreader/Services/ChapterStartTypography.swift | described | Module — TXT reader |
| vreader/Services/ChapterTranslationStore.swift | behavioral | Module — bilingual translation |
| vreader/Services/ChatSessionPersisting.swift | behavioral | Module — AI providers and tools |
| vreader/Services/ChatSessionRecord.swift | described | Module — AI providers and tools |
| vreader/Services/CustomCoverStore.swift | behavioral | Module — import pipeline |
| vreader/Services/DebugBridge/DebugBridge.swift | behavioral | Module — debug bridge |
| vreader/Services/DebugBridge/DebugBridgeNotifications.swift | behavioral | Module — debug bridge |
| vreader/Services/DebugBridge/DebugCommand.swift | behavioral | Module — debug bridge |
| vreader/Services/DebugBridge/DebugFixtureCatalog.swift | behavioral | Module — debug bridge |
| vreader/Services/DebugBridge/DebugPositionResolver.swift | behavioral | Module — debug bridge |
| vreader/Services/DebugBridge/DebugReaderProbeAdapter.swift | behavioral | Module — debug bridge |
| vreader/Services/DebugBridge/DebugReaderRegistry+Settle.swift | behavioral | Module — debug bridge |
| vreader/Services/DebugBridge/DebugReaderRegistry+WebViewWait.swift | behavioral | Module — debug bridge |
| vreader/Services/DebugBridge/DebugReaderRegistry.swift | behavioral | Module — debug bridge |
| vreader/Services/DebugBridge/DebugSnapshot.swift | behavioral | Module — debug bridge |
| vreader/Services/DebugBridge/ReadiumDebugProbe.swift | behavioral | Module — debug bridge |
| vreader/Services/DebugBridge/RealDebugBridgeContext+AIAction.swift | behavioral | Module — debug bridge |
| vreader/Services/DebugBridge/RealDebugBridgeContext+Eval.swift | behavioral | Module — debug bridge |
| vreader/Services/DebugBridge/RealDebugBridgeContext+Locate.swift | behavioral | Module — debug bridge |
| vreader/Services/DebugBridge/RealDebugBridgeContext+Navigate.swift | behavioral | Module — debug bridge |
| vreader/Services/DebugBridge/RealDebugBridgeContext+PDFHighlight.swift | behavioral | Module — debug bridge |
| vreader/Services/DebugBridge/RealDebugBridgeContext+Page.swift | behavioral | Module — debug bridge |
| vreader/Services/DebugBridge/RealDebugBridgeContext+Present.swift | behavioral | Module — debug bridge |
| vreader/Services/DebugBridge/RealDebugBridgeContext+Provider.swift | behavioral | Module — debug bridge |
| vreader/Services/DebugBridge/RealDebugBridgeContext+ScrollBoundary.swift | behavioral | Module — debug bridge |
| vreader/Services/DebugBridge/RealDebugBridgeContext+ScrollSheet.swift | behavioral | Module — debug bridge |
| vreader/Services/DebugBridge/RealDebugBridgeContext+SeedSessions.swift | behavioral | Module — debug bridge |
| vreader/Services/DebugBridge/RealDebugBridgeContext+Seek.swift | behavioral | Module — debug bridge |
| vreader/Services/DebugBridge/RealDebugBridgeContext+SetLayout.swift | behavioral | Module — debug bridge |
| vreader/Services/DebugBridge/RealDebugBridgeContext+Settle.swift | behavioral | Module — debug bridge |
| vreader/Services/DebugBridge/RealDebugBridgeContext+Snapshot.swift | behavioral | Module — debug bridge |
| vreader/Services/DebugBridge/RealDebugBridgeContext+TXTContent.swift | behavioral | Module — debug bridge |
| vreader/Services/DebugBridge/RealDebugBridgeContext.swift | behavioral | Module — debug bridge |
| vreader/Services/Diagnostics/DiagnosticsLogEntry.swift | behavioral | Module — diagnostics |
| vreader/Services/Diagnostics/DiagnosticsLogSource.swift | behavioral | Module — diagnostics |
| vreader/Services/Diagnostics/DiagnosticsLogStore.swift | behavioral | Module — diagnostics |
| vreader/Services/Diagnostics/DiagnosticsRedactor.swift | behavioral | Module — diagnostics |
| vreader/Services/Diagnostics/OSLogDiagnosticsSource.swift | behavioral | Module — diagnostics |
| vreader/Services/DictionaryLookup.swift | behavioral | Module — library |
| vreader/Services/EPUB/EPUBComplexityClassifier.swift | behavioral | Module — EPUB reader |
| vreader/Services/EPUB/EPUBFileLoader.swift | behavioral | Module — EPUB reader |
| vreader/Services/EPUB/EPUBParser.swift | behavioral | Module — EPUB reader |
| vreader/Services/EPUB/EPUBParserProtocol.swift | behavioral | Module — EPUB reader |
| vreader/Services/EPUB/EPUBPreExtractor.swift | behavioral | Module — EPUB reader |
| vreader/Services/EPUB/EPUBScrollAnchorResolver.swift | behavioral | Module — EPUB reader |
| vreader/Services/EPUB/EPUBTextStripper.swift | behavioral | Module — EPUB reader |
| vreader/Services/EPUB/EPUBTypes.swift | behavioral | Module — EPUB reader |
| vreader/Services/EPUB/FoliateJS/epubcfi.js | behavioral | Module — EPUB reader |
| vreader/Services/EPUB/FoliateJS/foliate-bridge.js | behavioral | Module — EPUB reader |
| vreader/Services/EPUB/FoliateJS/footnotes.js | behavioral | Module — EPUB reader |
| vreader/Services/EPUB/FoliateJS/overlayer.js | behavioral | Module — EPUB reader |
| vreader/Services/EPUB/FoliateJS/text-walker.js | behavioral | Module — EPUB reader |
| vreader/Services/EPUB/FoliateJS/tts.js | behavioral | Module — EPUB reader |
| vreader/Services/EPUB/ReadingPositionPersisting.swift | behavioral | Module — EPUB reader |
| vreader/Services/EPUB/ZIPReader.swift | behavioral | Module — EPUB reader |
| vreader/Services/Export/AnnotationExporter.swift | behavioral | Module — export |
| vreader/Services/Export/JSONExportFormatter.swift | behavioral | Module — export |
| vreader/Services/Export/MarkdownExportFormatter.swift | behavioral | Module — export |
| vreader/Services/FeatureFlags.swift | behavioral | Architecture — app layer and concurrency model |
| vreader/Services/Foliate/FoliateHighlightTapResolver.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Services/Foliate/FoliateJSEscaper.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Services/Foliate/FoliateMessageParser.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Services/Foliate/FoliateNavSeek.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Services/Foliate/FoliateScrollModel.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Services/Foliate/FoliateScrolledWindowMath.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Services/Foliate/FoliateSearchAdapter.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Services/Foliate/FoliateSelectionDispatcher.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Services/Foliate/FoliateStyleMapper.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Services/Foliate/FoliateTOCConverter.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Services/Foliate/FoliateTTSAdapter.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Services/Foliate/FoliateTypes.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Services/Foliate/FoliateURLSchemeHandler.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Services/Foliate/JS/build-bundle.sh | behavioral | Module — Foliate AZW3 reader |
| vreader/Services/Foliate/JS/epub.js | behavioral | Module — Foliate AZW3 reader |
| vreader/Services/Foliate/JS/epubcfi.js | behavioral | Module — Foliate AZW3 reader |
| vreader/Services/Foliate/JS/fixed-layout.js | behavioral | Module — Foliate AZW3 reader |
| vreader/Services/Foliate/JS/foliate-bundle.js | behavioral | Module — Foliate AZW3 reader |
| vreader/Services/Foliate/JS/foliate-host.js | behavioral | Module — Foliate AZW3 reader |
| vreader/Services/Foliate/JS/foliate-reader.html | behavioral | Module — Foliate AZW3 reader |
| vreader/Services/Foliate/JS/footnotes.js | behavioral | Module — Foliate AZW3 reader |
| vreader/Services/Foliate/JS/mobi.js | behavioral | Module — Foliate AZW3 reader |
| vreader/Services/Foliate/JS/overlayer.js | behavioral | Module — Foliate AZW3 reader |
| vreader/Services/Foliate/JS/package-lock.json | listed | Module — Foliate AZW3 reader |
| vreader/Services/Foliate/JS/package.json | listed | Module — Foliate AZW3 reader |
| vreader/Services/Foliate/JS/paginator.js | behavioral | Module — Foliate AZW3 reader |
| vreader/Services/Foliate/JS/progress.js | behavioral | Module — Foliate AZW3 reader |
| vreader/Services/Foliate/JS/search.js | behavioral | Module — Foliate AZW3 reader |
| vreader/Services/Foliate/JS/text-walker.js | behavioral | Module — Foliate AZW3 reader |
| vreader/Services/Foliate/JS/tts.js | behavioral | Module — Foliate AZW3 reader |
| vreader/Services/Foliate/JS/view.js | behavioral | Module — Foliate AZW3 reader |
| vreader/Services/FontSizeCalibrator.swift | behavioral | Module — settings and preferences |
| vreader/Services/HapticFeedback.swift | behavioral | Module — settings and preferences |
| vreader/Services/HighlightLookup.swift | described | Module — annotations and highlights |
| vreader/Services/HighlightPersisting.swift | described | Module — annotations and highlights |
| vreader/Services/HighlightRecord.swift | described | Module — annotations and highlights |
| vreader/Services/Import/AnnotationImportError.swift | behavioral | Module — import pipeline |
| vreader/Services/Import/AnnotationImporter.swift | behavioral | Module — import pipeline |
| vreader/Services/Import/FileURLImportRouter.swift | behavioral | Module — import pipeline |
| vreader/Services/Import/VReaderAnnotationParser.swift | behavioral | Module — import pipeline |
| vreader/Services/ImportError.swift | behavioral | Module — import pipeline |
| vreader/Services/ImportJobQueue.swift | behavioral | Module — import pipeline |
| vreader/Services/KeychainService.swift | behavioral | Architecture — app layer and concurrency model |
| vreader/Services/Libmobi/BUILD-RECIPE.md | behavioral | Module — Kindle AZW3 and libmobi |
| vreader/Services/Libmobi/Libmobi.swift | behavioral | Module — Kindle AZW3 and libmobi |
| vreader/Services/Libmobi/MobiDocument.swift | behavioral | Module — Kindle AZW3 and libmobi |
| vreader/Services/Libmobi/MobiEPUBAssembler.swift | behavioral | Module — Kindle AZW3 and libmobi |
| vreader/Services/Libmobi/MobiEPUBConverter.swift | behavioral | Module — Kindle AZW3 and libmobi |
| vreader/Services/Libmobi/README.md | described | Module — Kindle AZW3 and libmobi |
| vreader/Services/LibraryPersisting.swift | behavioral | Module — library |
| vreader/Services/LibraryRefreshService.swift | behavioral | Module — library |
| vreader/Services/LibraryStatsReading.swift | behavioral | Module — reading stats |
| vreader/Services/Locator/LocatorFactory.swift | behavioral | Module — locator |
| vreader/Services/Locator/LocatorNormalizer.swift | behavioral | Module — locator |
| vreader/Services/Locator/LocatorRestorer.swift | behavioral | Module — locator |
| vreader/Services/MD/MDAttributedStringRenderer.swift | behavioral | Module — MD reader |
| vreader/Services/MD/MDChapterStartDecorator.swift | behavioral | Module — MD reader |
| vreader/Services/MD/MDChapterStartScanner.swift | behavioral | Module — MD reader |
| vreader/Services/MD/MDFileLoader.swift | behavioral | Module — MD reader |
| vreader/Services/MD/MDMetadataExtractor.swift | behavioral | Module — MD reader |
| vreader/Services/MD/MDParser.swift | behavioral | Module — MD reader |
| vreader/Services/MD/MDParserProtocol.swift | behavioral | Module — MD reader |
| vreader/Services/MD/MDReflowableTextSource.swift | behavioral | Module — MD reader |
| vreader/Services/MD/MDReplacementRuleFetcher.swift | behavioral | Module — MD reader |
| vreader/Services/MD/MDTypes.swift | behavioral | Module — MD reader |
| vreader/Services/MetadataExtractor.swift | behavioral | Module — import pipeline |
| vreader/Services/NoOpSessionStore.swift | behavioral | Module — reading stats |
| vreader/Services/OPDS/OPDSClient.swift | behavioral | Module — OPDS |
| vreader/Services/OPDS/OPDSModels.swift | behavioral | Module — OPDS |
| vreader/Services/OPDS/OPDSParser.swift | behavioral | Module — OPDS |
| vreader/Services/PageNavigator.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Services/PerBookSettings.swift | behavioral | Module — settings and preferences |
| vreader/Services/PersistenceActor+AnnotationBus.swift | behavioral | Module — persistence and data model |
| vreader/Services/PersistenceActor+Annotations.swift | behavioral | Module — persistence and data model |
| vreader/Services/PersistenceActor+Backup.swift | behavioral | Module — persistence and data model |
| vreader/Services/PersistenceActor+Bookmarks.swift | behavioral | Module — persistence and data model |
| vreader/Services/PersistenceActor+ChatSessions.swift | behavioral | Module — persistence and data model |
| vreader/Services/PersistenceActor+ChatSessionsBackup.swift | behavioral | Module — persistence and data model |
| vreader/Services/PersistenceActor+Collections.swift | behavioral | Module — persistence and data model |
| vreader/Services/PersistenceActor+Highlights.swift | behavioral | Module — persistence and data model |
| vreader/Services/PersistenceActor+Library.swift | behavioral | Module — persistence and data model |
| vreader/Services/PersistenceActor+ReadingHistory.swift | behavioral | Module — persistence and data model |
| vreader/Services/PersistenceActor+ReadingPosition.swift | behavioral | Module — persistence and data model |
| vreader/Services/PersistenceActor+ReadingWindow.swift | behavioral | Module — persistence and data model |
| vreader/Services/PersistenceActor+RemoteOnly.swift | behavioral | Module — persistence and data model |
| vreader/Services/PersistenceActor+Stats.swift | behavioral | Module — persistence and data model |
| vreader/Services/PersistenceActor.swift | behavioral | Module — persistence and data model |
| vreader/Services/PreferenceStore.swift | behavioral | Module — settings and preferences |
| vreader/Services/Reader/BilingualDisplaySegmentMap.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Services/Reader/BilingualParagraphRanges.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Services/Reader/ChapterTextProviding.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Services/Reader/EPUBChapterTextProvider.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Services/Reader/FoliateChapterTextProvider.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Services/Reader/FoliateSectionExtracting.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Services/Reader/MDChapterTextProvider.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Services/Reader/PDFChapterTextProvider.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Services/Reader/ReadiumBilingualChapterTracker.swift | behavioral | Module — EPUB reader |
| vreader/Services/Reader/ReadiumBilingualCommander.swift | behavioral | Module — EPUB reader |
| vreader/Services/Reader/ReadiumBilingualEvalAdapter.swift | behavioral | Module — EPUB reader |
| vreader/Services/Reader/ReadiumDecorationHighlightAdapter.swift | behavioral | Module — EPUB reader |
| vreader/Services/Reader/ReadiumEPUBHost+Bilingual.swift | behavioral | Module — EPUB reader |
| vreader/Services/Reader/ReadiumEPUBHost+BilingualDriver.swift | behavioral | Module — EPUB reader |
| vreader/Services/Reader/ReadiumEPUBHost+BilingualLoading.swift | behavioral | Module — EPUB reader |
| vreader/Services/Reader/ReadiumEPUBHost+Body.swift | behavioral | Module — EPUB reader |
| vreader/Services/Reader/ReadiumEPUBHost+ContinuousScroll.swift | behavioral | Module — EPUB reader |
| vreader/Services/Reader/ReadiumEPUBHost+Highlights.swift | behavioral | Module — EPUB reader |
| vreader/Services/Reader/ReadiumEPUBHost+TTSFollow.swift | behavioral | Module — EPUB reader |
| vreader/Services/Reader/ReadiumEPUBHost.swift | behavioral | Module — EPUB reader |
| vreader/Services/Reader/ReadiumNavigatorRepresentable.swift | behavioral | Module — EPUB reader |
| vreader/Services/Reader/ReadiumSelectionHighlightBuilder.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Services/Reader/TXTChapterTextProvider.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Services/Reader/TXTLoaderBackedChapterTextProvider.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Services/ReaderPositionService.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Services/ReaderSettingsStore.swift | behavioral | Module — settings and preferences |
| vreader/Services/ReaderTypography.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Services/ReadingModeMigration.swift | behavioral | Architecture — app layer and concurrency model |
| vreader/Services/ReadingSessionTracker.swift | behavioral | Module — reading stats |
| vreader/Services/ReflowableTextSource.swift | behavioral | Module — TXT reader |
| vreader/Services/Search/BackgroundIndexingCoordinator.swift | behavioral | Module — search |
| vreader/Services/Search/EPUBTextExtractor.swift | behavioral | Module — search |
| vreader/Services/Search/MDTextExtractor.swift | behavioral | Module — search |
| vreader/Services/Search/PDFTextExtractor.swift | behavioral | Module — search |
| vreader/Services/Search/PersistentSearchIndex.swift | behavioral | Module — search |
| vreader/Services/Search/SearchHitToLocatorResolver.swift | behavioral | Module — search |
| vreader/Services/Search/SearchIndexCore.swift | behavioral | Module — search |
| vreader/Services/Search/SearchIndexStore.swift | behavioral | Module — search |
| vreader/Services/Search/SearchQueryExecutor.swift | behavioral | Module — search |
| vreader/Services/Search/SearchService.swift | behavioral | Module — search |
| vreader/Services/Search/SearchTextExtractor.swift | behavioral | Module — search |
| vreader/Services/Search/SearchTextNormalizer.swift | behavioral | Module — search |
| vreader/Services/Search/SearchTokenizer.swift | behavioral | Module — search |
| vreader/Services/Search/TXTTextExtractor.swift | behavioral | Module — search |
| vreader/Services/SettingsNotifications.swift | behavioral | Module — settings and preferences |
| vreader/Services/Stats/ReadingStatsAggregator.swift | behavioral | Module — reading stats |
| vreader/Services/Stats/ReadingStatsCustomRange.swift | behavioral | Module — reading stats |
| vreader/Services/Stats/ReadingStatsModels.swift | behavioral | Module — reading stats |
| vreader/Services/SwiftDataSessionStore.swift | behavioral | Module — reading stats |
| vreader/Services/Sync/ChangeTokenStore.swift | behavioral | Module — sync |
| vreader/Services/Sync/CloudKitClient.swift | behavioral | Module — sync |
| vreader/Services/Sync/CloudKitRecordMapper.swift | behavioral | Module — sync |
| vreader/Services/Sync/DeviceIdentity.swift | behavioral | Module — sync |
| vreader/Services/Sync/DurableTombstoneStore.swift | behavioral | Module — sync |
| vreader/Services/Sync/FileAvailabilityStateMachine.swift | behavioral | Module — sync |
| vreader/Services/Sync/NSUKVSBridge.swift | behavioral | Module — sync |
| vreader/Services/Sync/SyncConflictResolver.swift | behavioral | Module — sync |
| vreader/Services/Sync/SyncOutboundQueue.swift | behavioral | Module — sync |
| vreader/Services/Sync/SyncPipeline.swift | behavioral | Module — sync |
| vreader/Services/Sync/SyncRecordDTOs.swift | behavioral | Module — sync |
| vreader/Services/Sync/SyncService.swift | behavioral | Module — sync |
| vreader/Services/Sync/SyncStatusMonitor.swift | behavioral | Module — sync |
| vreader/Services/Sync/SyncTypes.swift | behavioral | Module — sync |
| vreader/Services/Sync/TombstoneStore.swift | behavioral | Module — sync |
| vreader/Services/TOCBuilder.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Services/TOCChapterProgress.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Services/TOCProvider.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Services/TTS/HTTPSpeechSynthesizer.swift | behavioral | Module — TTS |
| vreader/Services/TTS/HTTPTTSChunkPlayer.swift | behavioral | Module — TTS |
| vreader/Services/TTS/HTTPTTSConfig.swift | behavioral | Module — TTS |
| vreader/Services/TTS/HTTPTTSConfigStore.swift | behavioral | Module — TTS |
| vreader/Services/TTS/HTTPTTSProvider.swift | behavioral | Module — TTS |
| vreader/Services/TTS/SpeechSynthesizing.swift | behavioral | Module — TTS |
| vreader/Services/TTS/TTSHighlightCoordinator.swift | behavioral | Module — TTS |
| vreader/Services/TTS/TTSProviderProtocol.swift | behavioral | Module — TTS |
| vreader/Services/TTS/TTSService.swift | behavioral | Module — TTS |
| vreader/Services/TTS/XCUITestMockSpeechSynthesizer.swift | behavioral | Module — TTS |
| vreader/Services/TXT/ChapterProgressCalculator.swift | behavioral | Module — TXT reader |
| vreader/Services/TXT/TXTAttributedStringBuilder.swift | behavioral | Module — TXT reader |
| vreader/Services/TXT/TXTChapterContentLoader.swift | behavioral | Module — TXT reader |
| vreader/Services/TXT/TXTChapterIndex.swift | behavioral | Module — TXT reader |
| vreader/Services/TXT/TXTChapterIndexBuilder.swift | behavioral | Module — TXT reader |
| vreader/Services/TXT/TXTChapterIndexStore.swift | behavioral | Module — TXT reader |
| vreader/Services/TXT/TXTChapterOffsetIndex.swift | behavioral | Module — TXT reader |
| vreader/Services/TXT/TXTChapterStartDecorator.swift | behavioral | Module — TXT reader |
| vreader/Services/TXT/TXTChunkedLoader.swift | behavioral | Module — TXT reader |
| vreader/Services/TXT/TXTContinuousChunkBuilder.swift | behavioral | Module — TXT reader |
| vreader/Services/TXT/TXTFileLoader.swift | behavioral | Module — TXT reader |
| vreader/Services/TXT/TXTLazyTextProvider.swift | behavioral | Module — TXT reader |
| vreader/Services/TXT/TXTOffsetMapper.swift | behavioral | Module — TXT reader |
| vreader/Services/TXT/TXTOffsetTranslator.swift | behavioral | Module — TXT reader |
| vreader/Services/TXT/TXTReflowableTextSource.swift | behavioral | Module — TXT reader |
| vreader/Services/TXT/TXTService.swift | behavioral | Module — TXT reader |
| vreader/Services/TXT/TXTServiceProtocol.swift | behavioral | Module — TXT reader |
| vreader/Services/TXT/TXTTextChunker.swift | behavioral | Module — TXT reader |
| vreader/Services/TXT/TXTTocRule.swift | behavioral | Module — TXT reader |
| vreader/Services/TXT/TXTTocRuleEngine.swift | behavioral | Module — TXT reader |
| vreader/Services/TextKit2Spike/SPIKE_RESULTS.md | listed | Module — TXT reader |
| vreader/Services/TextKit2Spike/TextKit2Paginator.swift | behavioral | Module — TXT reader |
| vreader/Services/TextMapping/OffsetMap.swift | behavioral | Module — text mapping |
| vreader/Services/TextMapping/ReplacementTransform.swift | behavioral | Module — text mapping |
| vreader/Services/TextMapping/SimpTradDictionary.swift | behavioral | Module — text mapping |
| vreader/Services/TextMapping/SimpTradTransform.swift | behavioral | Module — text mapping |
| vreader/Services/TextMapping/TextMapper.swift | behavioral | Module — text mapping |
| vreader/Services/TextMapping/TextTransform.swift | behavioral | Module — text mapping |
| vreader/Services/ThemeBackgroundStore.swift | behavioral | Module — settings and preferences |
| vreader/Services/Unified/PaginationCache.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Utils/AccessibilityFormatters.swift | behavioral | Architecture — app layer and concurrency model |
| vreader/Utils/AppLogger.swift | behavioral | Architecture — app layer and concurrency model |
| vreader/Utils/BookImporterEnvironment.swift | behavioral | Architecture — app layer and concurrency model |
| vreader/Utils/ContentHasher.swift | behavioral | Architecture — app layer and concurrency model |
| vreader/Utils/EncodingDetector.swift | behavioral | Architecture — app layer and concurrency model |
| vreader/Utils/ErrorMessageAuditor.swift | behavioral | Architecture — app layer and concurrency model |
| vreader/Utils/FileSizeFormatter.swift | behavioral | Architecture — app layer and concurrency model |
| vreader/Utils/HighlightedSnippet.swift | behavioral | Architecture — app layer and concurrency model |
| vreader/Utils/LazyDownloadCoordinatorEnvironment.swift | behavioral | Architecture — app layer and concurrency model |
| vreader/Utils/MonthBoundary.swift | behavioral | Architecture — app layer and concurrency model |
| vreader/Utils/PersistenceActorEnvironment.swift | behavioral | Architecture — app layer and concurrency model |
| vreader/Utils/QuoteRecovery.swift | behavioral | Architecture — app layer and concurrency model |
| vreader/Utils/ReadingTimeFormatter.swift | behavioral | Architecture — app layer and concurrency model |
| vreader/Utils/ReduceMotionHelper.swift | behavioral | Architecture — app layer and concurrency model |
| vreader/Utils/WebDAVNetworkPolicyEnvironment.swift | behavioral | Architecture — app layer and concurrency model |
| vreader/ViewModels/AIAssistantViewModel+BilingualSummary.swift | behavioral | Module — AI providers and tools |
| vreader/ViewModels/AIAssistantViewModel+Streaming.swift | behavioral | Module — AI providers and tools |
| vreader/ViewModels/AIAssistantViewModel.swift | behavioral | Module — AI providers and tools |
| vreader/ViewModels/AIChatViewModel+SessionTransitions.swift | behavioral | Module — AI providers and tools |
| vreader/ViewModels/AIChatViewModel+Sessions.swift | behavioral | Module — AI providers and tools |
| vreader/ViewModels/AIChatViewModel+Streaming.swift | behavioral | Module — AI providers and tools |
| vreader/ViewModels/AIChatViewModel.swift | behavioral | Module — AI providers and tools |
| vreader/ViewModels/AIProviderPickerViewModel.swift | behavioral | Module — AI providers and tools |
| vreader/ViewModels/AITranslationViewModel.swift | behavioral | Module — bilingual translation |
| vreader/ViewModels/AnnotationListViewModel.swift | behavioral | Module — annotations and highlights |
| vreader/ViewModels/BackupViewModel.swift | behavioral | Module — backup and WebDAV |
| vreader/ViewModels/BilingualReadingViewModel+Prefetch.swift | behavioral | Module — bilingual translation |
| vreader/ViewModels/BilingualReadingViewModel.swift | behavioral | Module — bilingual translation |
| vreader/ViewModels/BookTranslationViewModel.swift | behavioral | Module — bilingual translation |
| vreader/ViewModels/BookmarkListViewModel.swift | behavioral | Module — annotations and highlights |
| vreader/ViewModels/ChapterReTranslateBoundaries.swift | behavioral | Module — bilingual translation |
| vreader/ViewModels/ChapterReTranslateViewModel.swift | behavioral | Module — bilingual translation |
| vreader/ViewModels/EPUBReaderViewModel.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/ViewModels/FoliateReaderViewModel.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/ViewModels/HighlightListViewModel.swift | behavioral | Module — annotations and highlights |
| vreader/ViewModels/HighlightPopoverViewModel.swift | behavioral | Module — annotations and highlights |
| vreader/ViewModels/LibraryViewModel.swift | behavioral | Module — library |
| vreader/ViewModels/MDReaderViewModel.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/ViewModels/PDFReaderViewModel.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/ViewModels/ReaderLifecycleHelper.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/ViewModels/ReadingDashboardViewModel.swift | behavioral | Module — reading stats |
| vreader/ViewModels/ReadiumEPUBReaderViewModel+Mapping.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/ViewModels/ReadiumEPUBReaderViewModel+Navigation.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/ViewModels/ReadiumEPUBReaderViewModel.swift | behavioral | Module — EPUB reader |
| vreader/ViewModels/SearchViewModel.swift | behavioral | Module — search |
| vreader/ViewModels/SettingsHeaderViewModel.swift | behavioral | Module — settings and preferences |
| vreader/ViewModels/StreamCoalescer.swift | behavioral | Module — AI providers and tools |
| vreader/ViewModels/TXTReaderViewModel.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/ViewModels/UnifiedTextRendererViewModel.swift | behavioral | Module — TXT reader |
| vreader/ViewModels/WholeBookRetrievalViewModel.swift | behavioral | Module — AI providers and tools |
| vreader/Views/AI/AIAssistantView.swift | behavioral | Module — AI providers and tools |
| vreader/Views/AI/AIChatComposerState.swift | behavioral | Module — AI providers and tools |
| vreader/Views/AI/AIChatMessageRow.swift | behavioral | Module — AI providers and tools |
| vreader/Views/AI/AIChatView+Composer.swift | behavioral | Module — AI providers and tools |
| vreader/Views/AI/AIChatView.swift | behavioral | Module — AI providers and tools |
| vreader/Views/AI/AIConsentView.swift | behavioral | Module — AI providers and tools |
| vreader/Views/AI/ChatCitationRow.swift | behavioral | Module — AI providers and tools |
| vreader/Views/AI/ChatContextBar.swift | behavioral | Module — AI providers and tools |
| vreader/Views/AI/ChatMarkdownRenderer.swift | behavioral | Module — AI providers and tools |
| vreader/Views/AI/ChatRetrievalCluster.swift | behavioral | Module — AI providers and tools |
| vreader/Views/AI/ChatScopeMenu.swift | behavioral | Module — AI providers and tools |
| vreader/Views/AI/ChatSessionBar.swift | behavioral | Module — AI providers and tools |
| vreader/Views/AI/ChatSourcesMenu.swift | behavioral | Module — AI providers and tools |
| vreader/Views/AI/ConversationsSheet.swift | behavioral | Module — AI providers and tools |
| vreader/Views/AI/ConversationsSheetRows.swift | behavioral | Module — AI providers and tools |
| vreader/Views/Annotations/AddNoteSheet.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Annotations/AnnotationEditSheet.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Backup/BookDownloadSheet.swift | behavioral | Module — backup and WebDAV |
| vreader/Views/Backup/SelectiveRestorePicker.swift | behavioral | Module — backup and WebDAV |
| vreader/Views/BookCardView.swift | behavioral | Module — library |
| vreader/Views/BookCoverArtView.swift | behavioral | Module — library |
| vreader/Views/BookRowView.swift | behavioral | Module — library |
| vreader/Views/BookSource/BookSourceChapterListView.swift | behavioral | Module — book sources |
| vreader/Views/BookSource/BookSourceEditorView.swift | behavioral | Module — book sources |
| vreader/Views/BookSource/BookSourceListView.swift | behavioral | Module — book sources |
| vreader/Views/BookSource/BookSourceReaderView.swift | behavioral | Module — book sources |
| vreader/Views/BookSource/BookSourceSearchView.swift | behavioral | Module — book sources |
| vreader/Views/ContentView.swift | behavioral | Architecture — app layer and concurrency model |
| vreader/Views/GenerativeCoverMetrics.swift | behavioral | Module — library |
| vreader/Views/GenerativeCoverView.swift | behavioral | Module — library |
| vreader/Views/Library/BookInfoSheet.swift | behavioral | Module — library |
| vreader/Views/Library/CollectionSidebar.swift | behavioral | Module — library |
| vreader/Views/Library/ContinueReadingRail.swift | behavioral | Module — library |
| vreader/Views/Library/LibraryCardTranslateBadge.swift | behavioral | Module — library |
| vreader/Views/Library/LibraryContainerModel.swift | behavioral | Module — library |
| vreader/Views/Library/LibraryContinueCard.swift | behavioral | Module — library |
| vreader/Views/Library/LibraryFilterChips.swift | behavioral | Module — library |
| vreader/Views/Library/LibraryNavBar.swift | behavioral | Module — library |
| vreader/Views/Library/LibraryPillButton.swift | behavioral | Module — library |
| vreader/Views/Library/LibrarySearchBar.swift | behavioral | Module — library |
| vreader/Views/Library/LibrarySectionHeader.swift | behavioral | Module — library |
| vreader/Views/Library/LibraryView+Body.swift | behavioral | Module — library |
| vreader/Views/Library/LibraryViewObservers.swift | behavioral | Module — library |
| vreader/Views/Library/LibraryViewSheets.swift | behavioral | Module — library |
| vreader/Views/Library/ShareSheet.swift | behavioral | Module — library |
| vreader/Views/LibraryCardTokens.swift | behavioral | Module — library |
| vreader/Views/LibraryProgressRing.swift | behavioral | Module — library |
| vreader/Views/LibraryView.swift | behavioral | Module — library |
| vreader/Views/OPDS/OPDSBrowserView.swift | behavioral | Module — OPDS |
| vreader/Views/OPDS/OPDSCatalogListView.swift | behavioral | Module — OPDS |
| vreader/Views/OPDS/OPDSEntryView.swift | behavioral | Module — OPDS |
| vreader/Views/Reader/AIProviderPicker.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/AIReaderPanel+DebugBridgeAIAction.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/AIReaderPanel.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/AIReaderPanelHeader.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/AISummaryCard+Bilingual.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/AISummaryCard.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/AISummaryLangGlyphs.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/AISummaryLangPopover.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/AISummaryLangRow.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/AISummaryScopeChipStrip.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/AISummaryStateViews.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/AISummaryTabView+Bilingual.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/AISummaryTabView+Sections.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/AISummaryTabView.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/Annotations/AnnotationStreamBuilder.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/Annotations/AnnotationStreamItem.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/Annotations/AnnotationsEmptyStateArt.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/Annotations/AnnotationsEmptyStateView.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/Annotations/AnnotationsSheetRoute.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/Annotations/HighlightAnnotationCard.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/Annotations/HighlightEditHandoff.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/Annotations/HighlightsSheet+Delete.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/Annotations/HighlightsSheet+Export.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/Annotations/HighlightsSheet+Support.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/Annotations/HighlightsSheet.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/Annotations/NotesActionMenu.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/Annotations/NotesDeleteConfirm.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/Annotations/NotesDeleteRow.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/Annotations/NotesRowState.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/Annotations/NotesSwipeResolver.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/Annotations/StandaloneNoteCard.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/Annotations/TOCFilterField.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/Annotations/TOCSheet+Filter.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/Annotations/TOCSheet+Support.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/Annotations/TOCSheet.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/Annotations/TOCSheetRows.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/Annotations/TOCTitleFilter.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/Bilingual/BilingualAttributedStringComposer.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/Bilingual/BilingualCostStrip.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/Bilingual/BilingualDisplayPipeline.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/Bilingual/BilingualLanguage.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/Bilingual/BilingualLanguagePickerCell.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/Bilingual/BilingualOffsetRouter.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/Bilingual/BilingualPairing.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/Bilingual/BilingualPill.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/Bilingual/BilingualPillButtonStyle.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/Bilingual/BilingualRestoreReassertGate.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/Bilingual/BilingualRetranslateBanner.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/Bilingual/BilingualSettingsEditModel.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/Bilingual/BilingualSettingsEditRouter.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/Bilingual/BilingualSetupSheet+EditMode.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/Bilingual/BilingualSetupSheet+Sections.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/Bilingual/BilingualSetupSheet.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/Bilingual/BilingualSetupSheetContainer.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/Bilingual/BilingualSetupSheetState.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/Bilingual/BilingualTXTBridgeDelegateAdapter.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/Bilingual/BilingualTextRenderer.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/Bilingual/EPUBBilingualJS.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/Bilingual/EPUBBilingualOrchestrator.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/Bilingual/EPUBBilingualPipeline.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/Bilingual/FoliateBilingualJS.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/Bilingual/FoliateBilingualOrchestrator.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/Bilingual/FoliateBilingualPipeline.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/Bilingual/PDFBilingualPanel.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/Bilingual/PDFBilingualPanelBodies.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/Bilingual/PDFBilingualPanelState.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/Bilingual/ReaderAICoordinator.swift | behavioral | Module — AI providers and tools |
| vreader/Views/Reader/Bilingual/ReaderAIProvidersFlow.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/Bilingual/ReaderAIReadinessSheet.swift | behavioral | Module — AI providers and tools |
| vreader/Views/Reader/Bilingual/ReaderAIReadinessView.swift | behavioral | Module — AI providers and tools |
| vreader/Views/Reader/Bilingual/ReadinessProviderBlock.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/Bilingual/ReadinessRows.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/Bilingual/ReadinessTracker.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/Bilingual/ReadiumBilingualChapterTracker.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/Bilingual/ReadiumBilingualCommander.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/Bilingual/ReadiumBilingualEvalAdapter.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/Bilingual/ReadiumDecorationHighlightAdapter.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/Bilingual/ReadiumEPUBHost+Bilingual.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/Bilingual/ReadiumEPUBHost+BilingualDriver.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/Bilingual/ReadiumEPUBHost+BilingualLoading.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/Bilingual/ReadiumEPUBHost+Body.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/Bilingual/ReadiumEPUBHost+ContinuousScroll.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/Bilingual/ReadiumEPUBHost+Highlights.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/Bilingual/ReadiumEPUBHost+TTSFollow.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/Bilingual/ReadiumEPUBHost.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/Bilingual/ReadiumNavigatorRepresentable.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/BookDetails/BookDetailsActionRow.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/BookDetails/BookDetailsMetadataRow.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/BookDetails/BookDetailsReadingTimeMirror.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/BookDetails/BookDetailsSheet+Actions.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/BookDetails/BookDetailsSheet+Cards.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/BookDetails/BookDetailsSheet+Translate.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/BookDetails/BookDetailsSheet.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/BookDetails/BookDetailsTagFlow.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/BookDetails/BookDetailsViewModel.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/BookDetails/BookReadingTimeModel.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/BookDetails/BookReadingTimeRow.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/Color+ReaderHex.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/DebugAIActionEffect.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/DebugBridgeBilingualStatus.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/DebugBridgeHighlightObserver.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/DebugPresentSheetEffect.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/DictionarySheet.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/EPUBChapterBodyRewriter.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/EPUBChapterCSSScoper.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/EPUBChapterNavigationRouter.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/EPUBChapterResourceURL.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/EPUBChapterWrapPendingTarget.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/EPUBContinuousChapterProvider.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/EPUBContinuousScrollBridge.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/EPUBContinuousScrollCoordinator.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/EPUBContinuousScrollJS.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/EPUBDebugBridgeHighlightJS.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/EPUBHighlightActions.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/EPUBHighlightBridge.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/EPUBHighlightJS.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/EPUBHighlightRenderer.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/EPUBPageAxisProbe.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/EPUBPagedAxis.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/EPUBPagedProgress.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/EPUBPaginationHelper.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/EPUBProgressCalculator.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/EPUBReaderContainerView+Bilingual.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/EPUBReaderContainerView+ChapterWrap.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/EPUBReaderContainerView+ContinuousBilingual.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/EPUBReaderContainerView+ContinuousBilingualLoading.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/EPUBReaderContainerView+DebugBridgeHighlight.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/EPUBReaderContainerView+DebugBridgeScrollBoundary.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/EPUBReaderContainerView+Highlights.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/EPUBReaderContainerView+Navigation.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/EPUBReaderContainerView.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/EPUBReplacementJS.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/EPUBSelectionTokenCache.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/EPUBSpineWindow.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/EPUBSwipeGestureClassifier.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/EPUBWebViewBridge.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/EPUBWebViewBridgeCoordinator.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/EPUBWebViewBridgeJS.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/EPUBWebViewEvaluatorHandle.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/FoliateBilingualContainerView+BottomChrome.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Views/Reader/FoliateBilingualContainerView+Position.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Views/Reader/FoliateBilingualContainerView.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Views/Reader/FoliateBottomChromeLabels.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Views/Reader/FoliateBottomChromeSeek.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Views/Reader/FoliateCoordinatorBox.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Views/Reader/FoliateDebugSeekFractionObserver.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Views/Reader/FoliateHighlightJSBridge.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Views/Reader/FoliateHighlightMutator.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Views/Reader/FoliateHighlightRenderer.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Views/Reader/FoliateHighlightRestoreDispatcher.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Views/Reader/FoliatePositionRestoreController.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Views/Reader/FoliateReaderContainerView+Highlights.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Views/Reader/FoliateReaderContainerView+Navigation.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Views/Reader/FoliateReaderContainerView.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Views/Reader/FoliateSpikeView+HighlightTap.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Views/Reader/FoliateSpikeView+Restore.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Views/Reader/FoliateSpikeView+SectionExtracting.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Views/Reader/FoliateSpikeView+Selection.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Views/Reader/FoliateSpikeView.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Views/Reader/FoliateTOCAvailableObserver.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Views/Reader/FoliateViewBridge.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Views/Reader/FoliateViewCoordinator.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Views/Reader/HighlightActionCardSubviews.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/HighlightActionCardView.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/HighlightCoordinator.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/HighlightHitTolerance.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/HighlightPaintColor.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/HighlightPopoverActionRouter.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/HighlightPopoverContent.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/HighlightPopoverDeleteConfirm.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/HighlightPopoverMode.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/HighlightPopoverModifier.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/HighlightPopoverModifierBody.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/HighlightPopoverPresenter.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/HighlightRenderer.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/HighlightableTextView.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/LandingBloomCurve.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/LandingBloomPaint.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/MDReaderContainerView+Bilingual.swift | behavioral | Module — MD reader |
| vreader/Views/Reader/MDReaderContainerView+DebugBridgeHighlight.swift | behavioral | Module — MD reader |
| vreader/Views/Reader/MDReaderContainerView.swift | behavioral | Module — MD reader |
| vreader/Views/Reader/NativeTextPageNavigator.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/NativeTextPagedView.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/NativeTextPaginator.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/NoOpPersistenceStores.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/PDFAnnotationBridge.swift | behavioral | Module — PDF reader |
| vreader/Views/Reader/PDFHighlightRenderer.swift | behavioral | Module — PDF reader |
| vreader/Views/Reader/PDFHighlightTapResolver.swift | behavioral | Module — PDF reader |
| vreader/Views/Reader/PDFPageNavigator.swift | behavioral | Module — PDF reader |
| vreader/Views/Reader/PDFPasswordPromptView.swift | behavioral | Module — PDF reader |
| vreader/Views/Reader/PDFProgressHelper.swift | behavioral | Module — PDF reader |
| vreader/Views/Reader/PDFReaderContainerView+Bilingual.swift | behavioral | Module — PDF reader |
| vreader/Views/Reader/PDFReaderContainerView+DebugBridgePDFHighlight.swift | behavioral | Module — PDF reader |
| vreader/Views/Reader/PDFReaderContainerView+Highlights.swift | behavioral | Module — PDF reader |
| vreader/Views/Reader/PDFReaderContainerView+Overlays.swift | behavioral | Module — PDF reader |
| vreader/Views/Reader/PDFReaderContainerView.swift | behavioral | Module — PDF reader |
| vreader/Views/Reader/PDFViewBridge.swift | behavioral | Module — PDF reader |
| vreader/Views/Reader/PageAxisResolver.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/PageTurnAnimator.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReTranslate/ReTranslateFlowLayout.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/ReTranslate/ReTranslatePickerSheet.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/ReTranslate/ReTranslatePickerSheetParts.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/ReTranslate/ReTranslateProgress.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/ReaderAICoordinator.swift | behavioral | Module — AI providers and tools |
| vreader/Views/Reader/ReaderAIReadinessSheet.swift | behavioral | Module — AI providers and tools |
| vreader/Views/Reader/ReaderAIReadinessView.swift | behavioral | Module — AI providers and tools |
| vreader/Views/Reader/ReaderBottomChrome.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderBottomOverlay.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderChromeButton.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderContainerView+DebugBridgeLandingBloom.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderContainerView+DebugBridgePosition.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderContainerView+DebugBridgePresent.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderContainerView+DebugBridgeRenderedText.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderContainerView+DebugBridgeSearch.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderContainerView+DebugBridgeSetLayout.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderContainerView+ReTranslate.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderContainerView+SearchPollAction.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderContainerView+Sheets.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderContainerView.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderDebugBridgeBilingualObserver.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderDisplayControls.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderFormatHosts.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderMetricsReadout.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderMoreMenuBilingualContext.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderMoreMenuEffect.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderMoreMenuRow.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderMorePopover+Rows.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderMorePopover.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderMorePopoverParts.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderNotificationHandlers.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderNotificationModifier.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderNotifications.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderPositionHandoff.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderSafeAreaResolver.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderScrollIndicatorPolicy.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderScrubber.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderSearchCoordinator.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderSettingsPanel.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderSheetChrome.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderTOCBuilder.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderTapZoneRouter.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderToolbarActionObservers.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderTopChrome.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReaderUnifiedCoordinator.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReadingProgressBar.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ReadiumBilingualChapterTracker.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/ReadiumBilingualCommander.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/ReadiumBilingualEvalAdapter.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/ReadiumContinuousScrollModel.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Views/Reader/ReadiumDecorationHighlightAdapter.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/ReadiumEPUBHost+Annotations.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Views/Reader/ReadiumEPUBHost+Background.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Views/Reader/ReadiumEPUBHost+Bilingual.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/ReadiumEPUBHost+BilingualDriver.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/ReadiumEPUBHost+BilingualLoading.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/ReadiumEPUBHost+Body.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/ReadiumEPUBHost+BottomChrome.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Views/Reader/ReadiumEPUBHost+ContinuousScroll.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/ReadiumEPUBHost+Highlights.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/ReadiumEPUBHost+Navigation.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Views/Reader/ReadiumEPUBHost+TTSFollow.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/ReadiumEPUBHost.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/ReadiumNavigatorRepresentable.swift | behavioral | Module — EPUB reader |
| vreader/Views/Reader/ReadiumPositionBroadcast.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Views/Reader/ReadiumReaderCoordinator+Replacement.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Views/Reader/ReadiumReaderCoordinator+SelectionStyle.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Views/Reader/ReadiumReaderCoordinator+Transparency.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Views/Reader/ReadiumReaderCoordinator.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Views/Reader/ReadiumSelectionTokenCache.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Views/Reader/ReadiumTTSFollowMapper.swift | behavioral | Module — Foliate AZW3 reader |
| vreader/Views/Reader/ScrollProgressHelper.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/SelectionCardFallback.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/SelectionMenuSuppressingWebView.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/SelectionPopoverActionRouter.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/SelectionPopoverActionRow.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/SelectionPopoverPresenter.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/SelectionPopoverView.swift | behavioral | Module — annotations and highlights |
| vreader/Views/Reader/Settings/SettingsSliderRow.swift | behavioral | Module — settings and preferences |
| vreader/Views/Reader/Settings/TypefacePillToggle.swift | behavioral | Module — settings and preferences |
| vreader/Views/Reader/TTSControlBar.swift | behavioral | Module — TTS |
| vreader/Views/Reader/TTSTextSource.swift | behavioral | Module — TTS |
| vreader/Views/Reader/TXTBridgeShared+SelectionMapping.swift | behavioral | Module — TXT reader |
| vreader/Views/Reader/TXTBridgeShared.swift | behavioral | Module — TXT reader |
| vreader/Views/Reader/TXTChapterHighlightHelper.swift | behavioral | Module — TXT reader |
| vreader/Views/Reader/TXTChapterOverlayViews.swift | behavioral | Module — TXT reader |
| vreader/Views/Reader/TXTChunkedHighlightHelper.swift | behavioral | Module — TXT reader |
| vreader/Views/Reader/TXTChunkedReaderBridge.swift | behavioral | Module — TXT reader |
| vreader/Views/Reader/TXTChunkedScrollOffset.swift | behavioral | Module — TXT reader |
| vreader/Views/Reader/TXTPagedChapterAdvance.swift | behavioral | Module — TXT reader |
| vreader/Views/Reader/TXTReaderContainerView+Bilingual.swift | behavioral | Module — TXT reader |
| vreader/Views/Reader/TXTReaderContainerView+DebugBridgeHighlight.swift | behavioral | Module — TXT reader |
| vreader/Views/Reader/TXTReaderContainerView+Paged.swift | behavioral | Module — TXT reader |
| vreader/Views/Reader/TXTReaderContainerView.swift | behavioral | Module — TXT reader |
| vreader/Views/Reader/TXTTextViewBridge.swift | behavioral | Module — TXT reader |
| vreader/Views/Reader/TXTTextViewBridgeCoordinator.swift | behavioral | Module — TXT reader |
| vreader/Views/Reader/TXTViewConfig.swift | behavioral | Module — TXT reader |
| vreader/Views/Reader/TapZoneOverlay.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/TextHighlightHitResolver.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/TextHighlightHitTester.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/TextHighlightRenderer.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/TextReaderUIState.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/ThemeBackgroundView.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/TranslateBook/ReaderTranslateBanner.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/TranslateBook/TranslateBookActionRow.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/TranslateBook/TranslateBookConfirmAlert.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/TranslateBook/TranslateCancelAlert.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/TranslateBook/TranslateStatusSheet.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/TranslateLanguageRail.swift | behavioral | Module — bilingual translation |
| vreader/Views/Reader/TranslationPanel.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/TranslationResultCard.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/UIKitHighlightPopoverPresenter.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/UnifiedPagedView.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/UnifiedScrollView.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/Reader/UnifiedTextRenderer.swift | behavioral | Architecture — reader dispatch and format hosts |
| vreader/Views/ScreenSpaceDemo.swift | behavioral | Module — library |
| vreader/Views/Search/SearchBar.swift | behavioral | Module — search |
| vreader/Views/Search/SearchResultGrouping.swift | behavioral | Module — search |
| vreader/Views/Search/SearchResultRow.swift | behavioral | Module — search |
| vreader/Views/Search/SearchResultsGroupedList.swift | behavioral | Module — search |
| vreader/Views/Search/SearchStateViews.swift | behavioral | Module — search |
| vreader/Views/Search/SearchView.swift | behavioral | Module — search |
| vreader/Views/Search/SearchViewActions.swift | behavioral | Module — search |
| vreader/Views/Settings/AIProviderEditSheet+Sections.swift | behavioral | Module — settings and preferences |
| vreader/Views/Settings/AIProviderEditSheet.swift | behavioral | Module — settings and preferences |
| vreader/Views/Settings/AIProviderEditorView.swift | behavioral | Module — AI providers and tools |
| vreader/Views/Settings/AIProviderListView+Rows.swift | behavioral | Module — settings and preferences |
| vreader/Views/Settings/AIProviderListView.swift | behavioral | Module — AI providers and tools |
| vreader/Views/Settings/AISettingsSection.swift | behavioral | Module — AI providers and tools |
| vreader/Views/Settings/AISettingsViewModel+Editor.swift | behavioral | Module — settings and preferences |
| vreader/Views/Settings/AISettingsViewModel.swift | behavioral | Module — AI providers and tools |
| vreader/Views/Settings/Diagnostics/DiagnosticsFilterChips.swift | behavioral | Module — diagnostics |
| vreader/Views/Settings/Diagnostics/DiagnosticsLevelStyle.swift | behavioral | Module — diagnostics |
| vreader/Views/Settings/Diagnostics/DiagnosticsLogRow.swift | behavioral | Module — diagnostics |
| vreader/Views/Settings/Diagnostics/DiagnosticsLogView.swift | behavioral | Module — diagnostics |
| vreader/Views/Settings/Diagnostics/DiagnosticsLogViewModel.swift | behavioral | Module — diagnostics |
| vreader/Views/Settings/HTTPTTSSettingsView.swift | behavioral | Module — TTS |
| vreader/Views/Settings/KindResetPolicy.swift | behavioral | Module — settings and preferences |
| vreader/Views/Settings/PillSwitch.swift | behavioral | Module — settings and preferences |
| vreader/Views/Settings/ReplacementRulesView.swift | behavioral | Module — settings and preferences |
| vreader/Views/Settings/SettingsProfileCard.swift | behavioral | Module — settings and preferences |
| vreader/Views/Settings/SettingsRowStyle.swift | behavioral | Module — settings and preferences |
| vreader/Views/Settings/SettingsSectionHeader.swift | behavioral | Module — settings and preferences |
| vreader/Views/Settings/SettingsToggleRow.swift | behavioral | Module — settings and preferences |
| vreader/Views/Settings/SettingsView+StatsSheet.swift | behavioral | Module — settings and preferences |
| vreader/Views/Settings/SettingsView.swift | behavioral | Module — settings and preferences |
| vreader/Views/Settings/WebDAVProfileListViewModel+Editor.swift | behavioral | Module — settings and preferences |
| vreader/Views/Settings/WebDAVProfileListViewModel.swift | behavioral | Module — settings and preferences |
| vreader/Views/Settings/WebDAVServerProfileEditSheet+Sections.swift | behavioral | Module — settings and preferences |
| vreader/Views/Settings/WebDAVServerProfileEditSheet.swift | behavioral | Module — settings and preferences |
| vreader/Views/Settings/WebDAVServerProfileEditorView.swift | behavioral | Module — backup and WebDAV |
| vreader/Views/Settings/WebDAVServerProfileListView.swift | behavioral | Module — backup and WebDAV |
| vreader/Views/Settings/WebDAVSettingsView.swift | behavioral | Module — backup and WebDAV |
| vreader/Views/Shared/CoverPickCoordinator.swift | behavioral | Module — library |
| vreader/Views/Stats/ReadingDashboardView.swift | behavioral | Module — reading stats |
| vreader/Views/Stats/StatsCustomRangePicker+Subviews.swift | behavioral | Module — reading stats |
| vreader/Views/Stats/StatsCustomRangePicker.swift | behavioral | Module — reading stats |
| vreader/Views/Stats/StatsCustomRangePickerState.swift | behavioral | Module — reading stats |
| vreader/Views/Stats/StatsPerBookTable.swift | behavioral | Module — reading stats |
| vreader/Views/Stats/StatsTimeWindowBar.swift | behavioral | Module — reading stats |
| vreader/Views/Sync/FileAvailabilityBadge.swift | behavioral | Module — sync |
| vreader/Views/Sync/SyncStatusView.swift | behavioral | Module — sync |

## Group rows (listed / excluded)

| path group | files | disposition | level | owning dossier / reason |
|---|---|---|---|---|
| .cc-suite.md | 1 | included | listed | Module — automation and tooling |
| .claude/ | 2 | included | listed | Module — automation and tooling |
| .claude/agents/ | 2 | included | listed | Module — automation and tooling |
| .claude/codex-audits/ | 762 | included | listed | Module — automation and tooling |
| .claude/commands/ | 13 | included | listed | Module — automation and tooling |
| .claude/cron-logs/ | 1 | included | listed | Module — automation and tooling |
| .claude/cron-prompts/ | 4 | included | listed | Module — automation and tooling |
| .claude/rules/ | 15 | included | described | Module — automation and tooling |
| .claude/skills/ | 21 | included | described | Module — automation and tooling |
| .claude/tdd-guardian/ | 2 | included | listed | Module — automation and tooling |
| .claude/workflows/ | 1 | included | listed | Module — automation and tooling |
| .codex/ | 1 | included | listed | Module — automation and tooling |
| .codex/prompts/ | 1 | excluded |  | placeholder/system file |
| .gemini/commands/ | 1 | excluded |  | placeholder/system file |
| .gemini/skills/ | 1 | excluded |  | placeholder/system file |
| .github/ | 1 | included | listed | Module — automation and tooling |
| .gitignore | 1 | included | listed | Module — automation and tooling |
| AGENTS.md | 1 | included | listed | Module — automation and tooling |
| BUREAU.md | 1 | excluded |  | bureau infrastructure |
| CLAUDE.md | 1 | included | listed | Module — automation and tooling |
| GEMINI.md | 1 | included | listed | Module — automation and tooling |
| TestPlans/ | 2 | included | listed | Architecture — app layer and concurrency model |
| android/ | 4 | included | listed | Module — Android port |
| android/app/schemas/com.vreader.app.data.VReaderDatabase/ | 4 | included | listed | Module — Android port |
| android/app/src/androidTest/assets/ | 10 | included | listed | Module — Android port |
| android/app/src/androidTest/assets/foliate-spike/ | 4 | included | listed | Module — Android port |
| android/app/src/debug/ | 1 | included | listed | Module — Android port |
| android/app/src/debug/res/xml/ | 1 | included | listed | Module — Android port |
| android/app/src/main/ | 1 | included | listed | Module — Android port |
| android/app/src/main/assets/foliate/ | 3 | included | listed | Module — Android port |
| android/app/src/test/resources/ | 1 | included | listed | Module — Android port |
| android/gradle/wrapper/ | 2 | excluded |  | binary asset |
| archive/ | 2 | included | listed | Timeline — bug history and recurring classes |
| archive/plans/ | 20 | included | listed | Timeline — bug history and recurring classes |
| canon/ | 6 | excluded |  | bureau output (the knowledge base itself) |
| canon/architecture/ | 4 | excluded |  | bureau output (the knowledge base itself) |
| canon/decisions/ | 4 | excluded |  | bureau output (the knowledge base itself) |
| canon/logbook/ | 2 | excluded |  | bureau output (the knowledge base itself) |
| canon/logbook/2026/07/ | 2 | excluded |  | bureau output (the knowledge base itself) |
| canon/modules/ | 28 | excluded |  | bureau output (the knowledge base itself) |
| canon/timeline/ | 2 | excluded |  | bureau output (the knowledge base itself) |
| contracts/conformance/ | 1 | included | listed | Module — cross-platform contracts |
| contracts/vectors/ | 4 | included | listed | Module — cross-platform contracts |
| dev-docs/ | 2 | included | listed | Timeline — feature delivery history |
| dev-docs/designs/ | 205 | included | listed | Timeline — feature delivery history |
| dev-docs/integration-tests/ | 1 | included | described | Module — test architecture |
| dev-docs/plans/ | 96 | included | listed | Timeline — feature delivery history |
| dev-docs/test-debt/ | 1 | included | described | Module — test architecture |
| dev-docs/verification/ | 1281 | included | listed | Timeline — feature delivery history |
| docs/ | 2 | included | listed | Module — test architecture |
| docs/parity/ | 2 | included | described | Module — Android port |
| docs/screenshots/ | 3 | excluded |  | binary asset |
| spikes/android-reader-bench/ | 4 | included | listed | Module — Android port |
| spikes/android-reader-bench/app/src/main/ | 1 | included | listed | Module — Android port |
| spikes/android-reader-bench/baselines/ | 1 | included | listed | Module — Android port |
| spikes/android-reader-bench/fixtures/ | 1 | excluded |  | binary asset |
| spikes/android-reader-bench/gradle/wrapper/ | 2 | excluded |  | binary asset |
| vreader.xcodeproj/ | 1 | included | listed | Architecture — app layer and concurrency model |
| vreader.xcodeproj/project.xcworkspace/ | 2 | included | listed | Architecture — app layer and concurrency model |
| vreader.xcodeproj/xcshareddata/ | 1 | included | listed | Architecture — app layer and concurrency model |
| vreader/Assets.xcassets/ | 1 | excluded |  | asset catalog |
| vreader/Assets.xcassets/AccentColor.colorset/ | 1 | excluded |  | asset catalog |
| vreader/Assets.xcassets/AppIcon.appiconset/ | 2 | excluded |  | asset catalog |
| vreader/Models/ | 1 | excluded |  | placeholder/system file |
| vreader/Resources/DebugFixtures/ | 13 | included | listed | Module — debug bridge |
| vreader/Resources/Fonts/ | 9 | included | listed | Architecture — app layer and concurrency model |
| vreader/Services/ | 1 | excluded |  | placeholder/system file |
| vreader/Services/Foliate/JS/vendor/ | 2 | excluded |  | vendored foliate-js bundle |
| vreader/Services/Libmobi/src/ | 36 | excluded |  | vendored C library (libmobi) |
| vreader/SupportingFiles/ | 3 | included | listed | Architecture — app layer and concurrency model |
| vreader/Utils/ | 1 | excluded |  | placeholder/system file |
| vreader/ViewModels/ | 1 | excluded |  | placeholder/system file |
| vreader/Views/ | 11 | included | listed | Architecture — system overview |
| vreaderTests/ | 1 | included | listed | Module — test architecture |
| vreaderTests/Accessibility/ | 1 | included | listed | Module — test architecture |
| vreaderTests/App/ | 9 | included | listed | Module — test architecture |
| vreaderTests/Contracts/ | 2 | included | listed | Module — test architecture |
| vreaderTests/Fixtures/ | 24 | included | listed | Module — test architecture |
| vreaderTests/Helpers/ | 2 | included | listed | Module — test architecture |
| vreaderTests/Integration/ | 12 | included | listed | Module — test architecture |
| vreaderTests/Models/ | 52 | included | listed | Module — test architecture |
| vreaderTests/Services/ | 300 | included | listed | Module — test architecture |
| vreaderTests/Utils/ | 6 | included | listed | Module — test architecture |
| vreaderTests/Verification/ | 2 | included | listed | Module — test architecture |
| vreaderTests/ViewModels/ | 51 | included | listed | Module — test architecture |
| vreaderTests/Views/ | 257 | included | listed | Module — test architecture |
| vreaderUITests/ | 2 | included | listed | Module — test architecture |
| vreaderUITests/AI/ | 2 | included | listed | Module — test architecture |
| vreaderUITests/Accessibility/ | 1 | included | listed | Module — test architecture |
| vreaderUITests/Annotations/ | 1 | included | listed | Module — test architecture |
| vreaderUITests/Errors/ | 2 | included | listed | Module — test architecture |
| vreaderUITests/Helpers/ | 3 | included | listed | Module — test architecture |
| vreaderUITests/Keyboard/ | 1 | included | listed | Module — test architecture |
| vreaderUITests/Library/ | 10 | included | listed | Module — test architecture |
| vreaderUITests/Navigation/ | 1 | included | listed | Module — test architecture |
| vreaderUITests/Reader/ | 18 | included | listed | Module — test architecture |
| vreaderUITests/Search/ | 1 | included | listed | Module — test architecture |
| vreaderUITests/Sync/ | 2 | included | listed | Module — test architecture |
| vreaderUITests/Verification/ | 30 | included | listed | Module — test architecture |
