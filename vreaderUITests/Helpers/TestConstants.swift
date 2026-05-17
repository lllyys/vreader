import Foundation

/// Accessibility identifier constants mirroring production code.
/// Keep in sync with identifiers in the main target's SwiftUI views.
enum AccessibilityID {
    // MARK: - Library
    static let libraryView = "libraryView"
    static let importBooksButton = "importBooksButton"
    static let emptyLibraryState = "emptyLibraryState"
    static let viewModeToggle = "viewModeToggle"
    static let sortPicker = "sortPicker"

    // MARK: - Reader Chrome
    static let readerBackButton = "readerBackButton"
    static let readerSearchButton = "readerSearchButton"
    // Bug #209 / GH #804: Feature #60's v2 reader chrome (WI-6b
    // `ReaderBottomChrome`) renamed the bottom-toolbar buttons — the legacy
    // "Annotations" button is now "Notes" (`readerNotesButton`) and the
    // legacy "Settings" button is now "Display" (`readerDisplayButton`), per
    // `ReaderBottomChromeButton.accessibilityIdentifier`. The Notes button
    // still opens the annotations panel (`annotationsPanelSheet`); the
    // Display button still opens `ReaderSettingsPanel` (`readerSettingsPanel`).
    // The constant names keep the semantic role (Settings / Annotations) so
    // the existing call sites don't churn; only the underlying identifier
    // strings move to the v2 contract.
    static let readerAnnotationsButton = "readerNotesButton"
    static let readerSettingsButton = "readerDisplayButton"

    // MARK: - Sheets
    static let searchSheet = "searchSheet"
    static let annotationsPanelSheet = "annotationsPanelSheet"
    static let readerSettingsPanel = "readerSettingsPanel"

    // MARK: - Reader Placeholders
    static let epubReaderPlaceholder = "epubReaderPlaceholder"
    static let pdfReaderPlaceholder = "pdfReaderPlaceholder"
    static let txtReaderPlaceholder = "txtReaderPlaceholder"
    static let mdReaderPlaceholder = "mdReaderPlaceholder"
    static let unsupportedFormatView = "unsupportedFormatView"

    // MARK: - PDF Password
    static let pdfPasswordPrompt = "pdfPasswordPrompt"
    static let pdfPasswordField = "pdfPasswordField"
    static let pdfPasswordError = "pdfPasswordError"
    static let pdfPasswordCancel = "pdfPasswordCancel"
    static let pdfPasswordSubmit = "pdfPasswordSubmit"

    // MARK: - PDF Reader
    static let pdfReaderContainer = "pdfReaderContainer"
    static let pdfReaderContent = "pdfReaderContent"
    static let pdfReaderLoading = "pdfReaderLoading"
    static let pdfReaderError = "pdfReaderError"
    static let pdfBottomOverlay = "pdfBottomOverlay"
    static let pdfPageIndicator = "pdfPageIndicator"

    // MARK: - TXT/MD Reader
    static let txtReaderContainer = "txtReaderContainer"
    static let txtReaderLoading = "txtReaderLoading"
    static let txtReaderError = "txtReaderError"
    static let txtReaderContent = "txtReaderContent"
    static let txtReaderChunkedContent = "txtReaderChunkedContent"
    static let txtChapterTitleOverlay = "txtChapterTitleOverlay"
    static let txtChapterBottomOverlay = "txtChapterBottomOverlay"
    static let txtChapterPrevButton = "txtChapterPrevButton"
    static let txtChapterNextButton = "txtChapterNextButton"
    static let txtChapterIndicator = "txtChapterIndicator"
    static let mdReaderContainer = "mdReaderContainer"
    static let mdReaderLoading = "mdReaderLoading"
    static let mdReaderError = "mdReaderError"
    static let mdReaderContent = "mdReaderContent"

    // MARK: - Search
    static let searchView = "searchView"
    static let searchDismissButton = "searchDismissButton"
    static let searchResultsList = "searchResultsList"
    static let searchLoadingView = "searchLoadingView"
    static let searchNoResultsView = "searchNoResultsView"
    static let searchEmptyPromptView = "searchEmptyPromptView"
    static let loadMoreButton = "loadMoreButton"

    // MARK: - Annotations
    static let bookmarkEmptyState = "bookmarkEmptyState"
    static let tocEmptyState = "tocEmptyState"
    static let highlightEmptyState = "highlightEmptyState"
    static let annotationEmptyState = "annotationEmptyState"
    static let annotationEditCancel = "annotationEditCancel"
    static let annotationEditSave = "annotationEditSave"

    // MARK: - Library toolbar
    static let collectionsToolbarButton = "collectionsToolbarButton"
    static let settingsToolbarButton = "settingsToolbarButton"
    static let opdsCatalogsToolbarButton = "opdsCatalogsToolbarButton"

    // MARK: - Collections sidebar
    static let filterAllBooks = "filterAllBooks"
    static let newCollectionButton = "newCollectionButton"
    static let newCollectionTextField = "newCollectionTextField"
    static let addCollectionButton = "addCollectionButton"
    static let filterDoneButton = "filterDoneButton"

    // MARK: - Book context menu — Add to Collection (Bug #210 / GH #809)
    /// The "Add to Collection" submenu in the book card long-press
    /// context menu. Bug #210: feature #60's library re-skin added a
    /// "Collections" toolbar button and per-collection filter chips, so
    /// the prior `label CONTAINS 'Collection'` query was ambiguous.
    static let addToCollectionMenu = "addToCollectionMenu"

    /// A single collection button inside the "Add to Collection"
    /// submenu. Format: "addToCollectionMenuItem_{collectionName}".
    static func addToCollectionMenuItem(_ collectionName: String) -> String {
        "addToCollectionMenuItem_\(collectionName)"
    }

    /// A collection's filter row in the collections sidebar. Format:
    /// "collectionFilterRow_{collectionName}". Bug #210: distinct from
    /// the library filter chip `libraryFilterChip_{name}`, which the
    /// re-skin's `LibraryFilterChips` row also renders per collection.
    static func collectionFilterRow(_ collectionName: String) -> String {
        "collectionFilterRow_\(collectionName)"
    }

    // MARK: - Global settings
    static let settingsView = "settingsView"
    static let settingsDoneButton = "settingsDoneButton"
    static let settingsReplacementRules = "settingsReplacementRules"

    // MARK: - Replacement rules
    static let replacementRulesAddButton = "replacementRulesAddButton"

    // MARK: - Reader settings panel
    static let autoPageTurnToggle = "autoPageTurnToggle"
    static let autoPageTurnIntervalSlider = "autoPageTurnIntervalSlider"

    // MARK: - Reader Settings — Chinese conversion (Feature #28)
    /// Bug #194: the segmented Picker's "Chinese Text" label is hidden by
    /// `.pickerStyle(.segmented)` — only segments render as static text.
    /// Tests query this stable identifier on the Picker wrapper instead.
    static let chineseTextPicker = "chineseTextPicker"

    // MARK: - EPUB reader
    static let epubReaderContainer = "epubReaderContainer"
    static let epubReaderContent = "epubReaderContent"

    // MARK: - TTS
    static let readerTTSButton = "readerTTSButton"
    static let ttsControlBar = "ttsControlBar"
    static let ttsPlayPauseButton = "ttsPlayPauseButton"

    // MARK: - Reading progress
    static let nativeTextPagedView = "nativeTextPagedView"
    static let readingProgressLabel = "readingProgressLabel"

    // MARK: - Annotations import/export
    static let annotationsExportButton = "annotationsExportButton"
    static let annotationsImportButton = "annotationsImportButton"

    // MARK: - OPDS
    static let opdsEmptyState = "opdsEmptyState"
    static let opdsCatalogList = "opdsCatalogList"
    static let opdsAddCatalog = "opdsAddCatalog"
    static let opdsCatalogNameField = "opdsCatalogNameField"
    static let opdsCatalogURLField = "opdsCatalogURLField"
    static let opdsCatalogSaveButton = "opdsCatalogSaveButton"

    // MARK: - AI
    static let aiConsentView = "aiConsentView"
    static let aiConsentButton = "aiConsentButton"

    // MARK: - PDF Overlay
    static let pdfSessionTime = "pdfSessionTime"
    static let pdfPagesPerHour = "pdfPagesPerHour"
    static let pdfView = "pdfView"

    // MARK: - WebDAV Settings (Feature #29)
    // Bug #195: Feature #52 (multi-WebDAV-server profiles, VERIFIED 2026-05-09)
    // moved these fields out of a top-level WebDAV form into a profile-edit
    // sheet reached via:
    //   WebDAVSettingsView -> `webdavServersNavLink` (NavigationLink)
    //                      -> WebDAVServerProfileListView
    //                      -> `addWebDAVProfileButton` (toolbar +)
    //                      -> WebDAVServerProfileEditSheet
    // The pre-#52 identifiers below are NOT wired to any production view
    // anymore but are kept in TestConstants to document the old surface
    // and to fail a `grep` if a test still references them. New tests
    // should use the `webdavProfileEdit*` identifiers under the
    // "WebDAV Server Profile Edit Sheet" section below.
    static let webdavServerURL = "webdavServerURL"               // STALE — no production wire
    static let webdavUsername = "webdavUsername"                 // STALE — no production wire
    static let webdavPassword = "webdavPassword"                 // STALE — no production wire
    static let webdavTestButton = "webdavTestButton"             // STALE — no production wire
    static let webdavSaveButton = "webdavSaveButton"             // STALE — no production wire

    // MARK: - WebDAV Settings — top-level entry points (Feature #52)
    /// NavigationLink from WebDAVSettingsView into the profile list.
    static let webdavServersNavLink = "webdavServersNavLink"
    /// Toolbar "+" on WebDAVServerProfileListView that opens the edit sheet
    /// in add-mode.
    static let addWebDAVProfileButton = "addWebDAVProfileButton"

    // MARK: - WebDAV Server Profile Edit Sheet (Feature #52)
    /// TextField for the server URL (https://...) inside the profile edit sheet.
    static let webdavProfileEditServerURL = "webdavProfileEditServerURL"
    /// TextField for the username inside the profile edit sheet.
    static let webdavProfileEditUsername = "webdavProfileEditUsername"
    /// Button row that runs a connection test from inside the edit sheet
    /// (shown only in edit-mode — see Bug #184 design).
    static let webdavProfileEditTestConnection = "webdavProfileEditTestConnection"
    /// Add-mode footer note that replaces the Test Connection button until
    /// the profile is saved (Bug #184 design).
    static let webdavProfileEditTestConnectionNote = "webdavProfileEditTestConnectionNote"
    static let webdavBackupNowButton = "webdavBackupNowButton"
    static let webdavBackupErrorText = "webdavBackupErrorText"

    // MARK: - Search Result Row
    static let searchResultRow = "searchResultRow"

    // MARK: - Dynamic Identifiers

    /// Book card identifier in grid mode. Format: "bookCard_{fingerprintKey}".
    static func bookCard(_ fingerprintKey: String) -> String {
        "bookCard_\(fingerprintKey)"
    }

    /// Book row identifier in list mode. Format: "bookRow_{fingerprintKey}".
    static func bookRow(_ fingerprintKey: String) -> String {
        "bookRow_\(fingerprintKey)"
    }

    /// Individual search result. Format: "searchResult_{id}".
    static func searchResult(_ id: String) -> String {
        "searchResult_\(id)"
    }

    /// Individual bookmark row. Format: "bookmarkRow-{id}".
    static func bookmarkRow(_ id: String) -> String {
        "bookmarkRow-\(id)"
    }

    /// Individual TOC row. Format: "tocRow-{id}".
    static func tocRow(_ id: String) -> String {
        "tocRow-\(id)"
    }

    /// Individual highlight row. Format: "highlightRow-{id}".
    static func highlightRow(_ id: String) -> String {
        "highlightRow-\(id)"
    }

    /// Individual annotation row. Format: "annotationRow-{id}".
    static func annotationRow(_ id: String) -> String {
        "annotationRow-\(id)"
    }
}

// MARK: - Launch Argument Constants
// Feature #45 WI-4c — additional launch args for verification tests that
// can't drive the production UI gesture (e.g. SwiftUI segmented Picker
// doesn't dispatch tap-to-segment under XCUITest). Pass via
// `launchApp(extraLaunchArguments:)`.

enum LaunchArgs {
    /// `--reader-default-layout=paged` — pre-seeds EPUB layout preference
    /// to `.paged` before any `ReaderSettingsStore` reads it. Bypasses the
    /// segmented Picker in Reader Settings. Used by the auto-page-turn
    /// verification test (feature #31).
    static let readerLayoutPaged = "--reader-default-layout=paged"

    /// `--reader-default-layout=scroll` — explicit scroll-layout override.
    /// Same mechanism as the paged variant; rarely needed because scroll
    /// is the production default.
    static let readerLayoutScroll = "--reader-default-layout=scroll"
}
