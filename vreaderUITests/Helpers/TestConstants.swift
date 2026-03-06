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
    static let readerAnnotationsButton = "readerAnnotationsButton"
    static let readerSettingsButton = "readerSettingsButton"

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

    // MARK: - AI
    static let aiConsentView = "aiConsentView"
    static let aiConsentButton = "aiConsentButton"

    // MARK: - PDF Overlay
    static let pdfSessionTime = "pdfSessionTime"
    static let pdfPagesPerHour = "pdfPagesPerHour"
    static let pdfView = "pdfView"

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
