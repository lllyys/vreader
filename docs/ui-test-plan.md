# vreader UI Test Plan

**Date:** 2026-03-06
**Branch:** `dev-ui-test`
**Target Device:** iPhone 17 Pro (iOS 26)
**Status:** Draft v2 (post-review fixes)

---

## 0. Preface

### 0.1 Goals

Design comprehensive XCUITest integration tests that verify every UI surface in vreader is correctly laid out, accessible, and comfortable for iPhone 17 Pro users. Tests validate element presence, touch target compliance, Dynamic Type scaling, dark/light mode, VoiceOver traversal, and navigation flows.

### 0.2 Current App State

> **Critical context**: The app is under active development. Several integration layers are not yet wired. Tests must be written against what *exists today*, not what is planned. This section tracks the placeholder/integration boundary so implementers know which tests are immediately feasible vs. which require production code changes first.

| Area                          | Current State                                                            | Impact on Tests                                                      |
| ----------------------------- | ------------------------------------------------------------------------ | -------------------------------------------------------------------- |
| Library -> Reader navigation  | **No NavigationLink exists** — LibraryView has no tap-to-open navigation | WI-UI-0 must wire this before WI-UI-6+                               |
| EPUB/PDF/TXT/MD readers       | **All placeholders** — `Text("EPUB reader placeholder")` etc.            | Reader state tests (WI-UI-8, WI-UI-9) test placeholder presence only |
| Annotations panel tabs        | **ContentUnavailableView placeholders**                                  | WI-UI-11 tests empty placeholders, not real data                     |
| Search sheet                  | **Placeholder view**                                                     | WI-UI-10 tests placeholder presence only                             |
| Launch argument handling      | **Not implemented** in VReaderApp                                        | WI-UI-0 must add this                                                |
| Test data seeding             | **No mechanism**                                                         | WI-UI-0 must define the contract                                     |
| Feature flags via launch args | `FeatureFlags.setOverride()` exists but no launch arg parsing            | WI-UI-0 must bridge this                                             |

### 0.3 Testing Strategy

| Layer                     | Framework                | Scope                                                                     |
| ------------------------- | ------------------------ | ------------------------------------------------------------------------- |
| UI integration (XCUITest) | XCTest + XCUIApplication | Full app launch, element existence, navigation flows, accessibility audit |
| ViewModel unit            | Swift Testing (existing) | Already covered by 1097 unit tests in 122 suites                          |

**Snapshot/ViewInspector testing is explicitly out of scope.** XCUITest is the single mandatory automated approach for UI verification.

All UI tests go in the `vreaderUITests` target. Test command:

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test   
  -project vreader.xcodeproj -scheme vreader   
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1'
```

**Note:** Exit code 65 with "Test run with N tests passed" is a PASS (known `simctl` false negative on this Xcode version).

### 0.4 iPhone 17 Pro Considerations

| Attribute        | Value                         | Impact                                        |
| ---------------- | ----------------------------- | --------------------------------------------- |
| Screen size      | 393 x 852 pt (2556 x 1179 px) | Content width constraints, grid layout        |
| Dynamic Island   | 126 x 37.33 pt cutout         | Navigation bar must not clip under cutout     |
| Home indicator   | 5pt bar at bottom             | Bottom-anchored overlays need safe area inset |
| Safe area top    | \~59pt (with nav bar)         | Toolbar elements must be below safe area      |
| Safe area bottom | \~34pt                        | PDF bottom overlay, reader content padding    |
| Pixel density    | 3x                            | Thin borders/lines remain visible             |

### 0.5 Anti-Flake Strategy

All tests must use explicit waits rather than arbitrary `sleep()` calls.

**Required wait utilities** (defined in `LaunchHelper.swift`):

```swift
extension XCUIElement {
    /// Wait for element to exist with configurable timeout (default 5s).
    @discardableResult
    func waitForExistence(timeout: TimeInterval = 5) -> Bool {
        waitForExistence(timeout: timeout)
    }

    /// Wait for element to become hittable (exists + visible + enabled).
    func waitForHittable(timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "isHittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
```

**Rules:**

- Never use `Thread.sleep()` or `usleep()` in UI tests.
- Always `waitForExistence(timeout:)` before asserting on an element.
- Use `waitForHittable(timeout:)` before tap actions.
- Default timeout: 5 seconds. Loading states: 10 seconds.
- Sheet presentation: wait for sheet identifier, not a fixed delay.

### 0.6 Swift UI Test Target Gate

The `vreaderUITests` target must:

1. Compile without warnings (`xcodebuild build-for-testing` succeeds).
2. All tests pass on iPhone 17 Pro simulator.
3. No `Thread.sleep()` calls in test code.
4. Every test method has at least one assertion or `performAccessibilityAudit()` call.

### 0.7 Accessibility Identifiers Inventory

The codebase already has 60+ accessibility identifiers. Each WI below maps tests to these identifiers. Missing identifiers will be added as part of the implementation.

### 0.8 Scope Clarification

This plan targets a **native SwiftUI iOS app** built with Swift 6 and iOS 17+. CSS/web design rules from the VMark editor (design tokens, dark theme selectors, popup patterns) do **not** apply. SwiftUI theming uses `@Environment(\.colorScheme)` and system trait overrides.

---

## WI-UI-0: Integration Prerequisites

**Goal:** Wire the minimum production code changes needed to make UI tests feasible. Without these, most tests beyond library element presence are blocked.

**Non-goals:** Building real reader implementations. This is scaffolding only.

### Acceptance Criteria

1. **Library -> Reader navigation:**
   - `LibraryView` wraps each book item in a `NavigationLink` (or `.navigationDestination`) that pushes `ReaderContainerView`.
   - `ReaderContainerView` receives a `BookRecord` (or `LibraryBookItem`) and renders the appropriate format placeholder.
   - Back navigation returns to library.

2. **Launch argument handling in VReaderApp:**

   - `VReaderApp.init()` reads `ProcessInfo.processInfo.arguments` for test flags.
   - Supported flags:

   | Flag                  | Effect                                                    |
   | --------------------- | --------------------------------------------------------- |
   | `--uitesting`         | Enables test mode (disables animations, skips onboarding) |
   | `--seed-empty`        | Seeds empty database (clean state)                        |
   | `--seed-books`        | Seeds database with fixture books (see fixture manifest)  |
   | `--force-dark`        | Forces `.dark` color scheme                               |
   | `--force-light`       | Forces `.light` color scheme                              |
   | `--dynamic-type-XS`   | Sets Dynamic Type to `.xSmall`                            |
   | `--dynamic-type-XXXL` | Sets Dynamic Type to `.xxxLarge`                          |
   | `--dynamic-type-AX5`  | Sets Dynamic Type to `.accessibilityExtraExtraExtraLarge` |
   | `--enable-ai`         | Sets `FeatureFlags.setOverride(.aiAssistant, true)`       |
   | `--enable-sync`       | Sets `FeatureFlags.setOverride(.sync, true)`              |
   | `--reduce-motion`     | Simulates reduce motion preference                        |

   - Flags are `#if DEBUG` guarded — no effect in release builds.

3. **Test data seeding contract:**
   - A `TestSeeder` class (DEBUG-only) creates fixture `BookRecord` entries in the persistence layer.
   - Seeded books cover all 4 formats: EPUB, PDF, TXT, MD.
   - At least one book per format, plus edge cases (long title, nil author, CJK title, zero reading time).
   - Seeder is invoked from `VReaderApp.init()` when `--seed-books` flag is present.

4. **Fixture manifest:**

   | Fixture                  | Format | Title                                                                                          | Author        | Notes                 |
   | ------------------------ | ------ | ---------------------------------------------------------------------------------------------- | ------------- | --------------------- |
   | `fixture-epub.epub`      | EPUB   | "Test EPUB Book"                                                                               | "Test Author" | Minimal valid EPUB    |
   | `fixture-pdf.pdf`        | PDF    | "Test PDF Document"                                                                            | "PDF Author"  | 3-page PDF            |
   | `fixture-txt.txt`        | TXT    | "Test Plain Text"                                                                              | nil           | ASCII content         |
   | `fixture-md.md`          | MD     | "Test Markdown"                                                                                | "MD Author"   | Headings + paragraphs |
   | `fixture-long-title.txt` | TXT    | "A Very Long Book Title That Should Definitely Trigger Truncation in Both Grid and List Modes" | "Author Name" | Truncation test       |
   | `fixture-cjk.txt`        | TXT    | "Chinese Japanese Korean"                                                                      | nil           | CJK title             |
   | `fixture-zero-time.epub` | EPUB   | "Unread Book"                                                                                  | "Author"      | readingTime = 0       |
   | `fixture-password.pdf`   | PDF    | "Protected PDF"                                                                                | nil           | Password: "test123"   |

   - Fixture files go in `vreaderUITests/Fixtures/` (test bundle, not app bundle).
   - `TestSeeder` creates `BookRecord` entries pointing to bundled fixture file paths.

### Edge Cases

- Launch with both `--seed-empty` and `--seed-books`: `--seed-empty` wins (later flag overrides).
- Launch without `--uitesting`: no test behavior, app runs normally.
- Fixture files missing from bundle: seeder logs warning, skips that book.
- Launch argument parsing must not crash on unknown flags.

### Files to Create/Modify

| File                                  | Action                                                |
| ------------------------------------- | ----------------------------------------------------- |
| `vreader/Views/LibraryView.swift`     | Add NavigationLink/destination to ReaderContainerView |
| `vreader/App/VReaderApp.swift`        | Add launch argument parsing (DEBUG-only)              |
| `vreader/App/TestSeeder.swift`        | Create (DEBUG-only test data seeder)                  |
| `vreader/Services/FeatureFlags.swift` | Ensure `setOverride` works from launch arg path       |
| `vreaderUITests/Fixtures/`            | Add fixture files                                     |

### Dependencies

None (first WI — must be completed before all others).

### Rollback

Revert LibraryView changes, delete TestSeeder, remove launch arg handling.

---

## WI-UI-1: Test Infrastructure Setup

**Goal:** Establish the XCUITest infrastructure with launch configuration helpers, accessibility identifier constants, and shared test utilities.

**Non-goals:** Writing actual view tests (those come in WI-UI-2+).

### Acceptance Criteria

1. `vreaderUITests/Helpers/TestConstants.swift` defines all accessibility identifier constants as an enum, mirroring the identifiers in production code (no stringly-typed duplication).
2. `vreaderUITests/Helpers/LaunchHelper.swift` provides `launchApp()` with configurable launch arguments:
   - Calls through to the flags defined in WI-UI-0.
   - Provides typed API: `launchApp(seed: .empty, colorScheme: .dark, dynamicType: .ax5)`.
   - Includes `XCUIElement` wait extensions (see 0.5 Anti-Flake Strategy).
3. `vreaderUITests/Helpers/AccessibilityAuditHelper.swift` wraps `XCUIApplication.performAccessibilityAudit()` (iOS 17+) for automated WCAG checks.
   - Provides `auditCurrentScreen(app:excluding:)` that runs the audit and calls `XCTFail` on any violation.
4. Existing `VReaderUITests.swift` placeholder test is replaced with a proper smoke test that verifies app launch succeeds and the library view appears.
5. All helpers compile and the smoke test passes on iPhone 17 Pro simulator.

### Incremental Accessibility Gate

Every WI from this point forward must include at least one `performAccessibilityAudit()` call on the primary screen being tested. This replaces the big-bang WI-UI-17 approach.

### Edge Cases

- App launch with corrupted database (init error screen should appear)
- Launch arguments for seeded data must not leak into production builds (verified by `#if DEBUG` guard)

### Files to Create/Modify

| File                                                    | Action              |
| ------------------------------------------------------- | ------------------- |
| `vreaderUITests/Helpers/TestConstants.swift`            | Create              |
| `vreaderUITests/Helpers/LaunchHelper.swift`             | Create              |
| `vreaderUITests/Helpers/AccessibilityAuditHelper.swift` | Create              |
| `vreaderUITests/VReaderUITests.swift`                   | Replace placeholder |

### Dependencies

WI-UI-0 (launch argument handling must exist in production code).

### Rollback

Delete new files, restore `VReaderUITests.swift` to original.

---

## WI-UI-2: Library View -- Layout and Element Presence (Pilot Vertical Slice)

**Goal:** Verify the library screen displays all expected elements in both empty and populated states, grid and list modes. **This is the pilot WI** — it proves the entire test pipeline end-to-end (seeding, launching, querying, asserting, accessibility audit) before scaling to other screens.

**Non-goals:** Testing actual book import (file system integration). Testing sort correctness (covered by ViewModel unit tests).

### Acceptance Criteria

1. **Empty state tests:**
   - Empty library shows books icon, "Your Library is Empty" title, description text, and "Import Books" button.
   - "Import Books" button has `importBooksButton` identifier and is hittable.
   - Empty state container has `emptyLibraryState` identifier.
   - Navigation title shows "Library".
2. **Populated state tests:**
   - With seeded books, library shows book items (not empty state).
   - View mode toggle (`viewModeToggle`) exists and is hittable.
   - Sort picker (`sortPicker`) exists and is hittable.
   - Grid mode shows `BookCardView` items with title, format badge, and cover placeholder.
   - List mode shows `BookRowView` items with format icon (44x44pt), title, author, and metadata.
3. **View mode toggle:**
   - Tapping `viewModeToggle` switches between grid and list.
   - Button label updates ("Switch to list view" / "Switch to grid view").
4. **Sort picker interaction:**
   - Tapping sort picker reveals menu with "Title", "Date Added", "Last Read", "Reading Time" options.
5. **Pull-to-refresh:**
   - Scroll gesture triggers refresh (swipe down in populated list).
6. **Accessibility audit:** `performAccessibilityAudit()` passes on both empty and populated states.

### Edge Cases

- Library with 1 book (no scrolling needed)
- Book with nil author (author line hidden)
- Book with zero reading time (reading time label hidden)
- Book with very long title (truncation in both grid/list modes)
- Book title with CJK characters

### Tests

```
LibraryEmptyStateTests:
  - testEmptyStateShowsAllElements
  - testImportButtonIsHittable
  - testNavigationTitleIsLibrary
  - testEmptyStateAccessibilityAudit

LibraryPopulatedTests:
  - testPopulatedStateShowsBooks
  - testViewModeToggleExists
  - testSortPickerExists
  - testGridModeShowsCards
  - testListModeShowsRows
  - testViewModeToggleSwitchesLayout
  - testSortPickerShowsAllOptions
  - testPopulatedStateAccessibilityAudit

LibraryEdgeCaseTests:
  - testSingleBookDisplay
  - testBookWithNilAuthorHidesAuthorLine
  - testBookWithZeroReadingTimeHidesLabel
  - testLongTitleTruncation
```

### Pilot Verification

After completing WI-UI-2, verify:

- [ ] `xcodebuild test` command succeeds end-to-end
- [ ] Test seeding produces visible books
- [ ] Wait utilities prevent flakes (run 3x consecutively)
- [ ] Accessibility audit reports zero violations
- [ ] Test execution time is under 60 seconds

If any of these fail, fix the infrastructure before proceeding to WI-UI-3+.

### Files to Create/Modify

| File                                                  | Action |
| ----------------------------------------------------- | ------ |
| `vreaderUITests/Library/LibraryEmptyStateTests.swift` | Create |
| `vreaderUITests/Library/LibraryPopulatedTests.swift`  | Create |
| `vreaderUITests/Library/LibraryEdgeCaseTests.swift`   | Create |

### Dependencies

WI-UI-0, WI-UI-1 (infrastructure).

### Rollback

Delete test files.

---

## WI-UI-3: Library View -- Touch Targets and Dynamic Type

**Goal:** Verify all interactive elements in the library meet Apple HIG minimum 44x44pt touch targets, and that the layout degrades gracefully across Dynamic Type sizes.

**Non-goals:** Pixel-perfect rendering verification.

### Acceptance Criteria

1. **Touch target compliance (44x44pt minimum):**
   - View mode toggle button frame >= 44x44pt.
   - Sort picker button frame >= 44x44pt.
   - Import Books button frame >= 44x44pt.
   - Each book row/card is tappable with frame height >= 44pt.
   - Format icon in list mode occupies 44x44pt frame.
2. **Dynamic Type scaling (xSmall through AX5):**
   - At `xSmall`: All text is present (use `waitForExistence`), no critical labels disappear.
   - At `xxxLarge`: Layout has no overlapping elements (verified by checking element frames don't intersect).
   - At `AX5` (largest accessibility size): No elements extend beyond screen width (element `frame.maxX <= 393`). Import button remains hittable.
3. **Accessibility audit at each Dynamic Type size.**

### Measurable Criteria

"No overlap" means: for any two sibling elements A and B, `A.frame.intersects(B.frame)` is false OR one is a container of the other. "No overflow" means: `element.frame.maxX <= app.windows.firstMatch.frame.width`.

### Edge Cases

- AX5 + long book title: title wraps or truncates, does not overlap other elements
- AX5 + book with all metadata (author, reading time, speed): all fit within row
- Bold Text accessibility setting enabled: layout still valid

### Tests

```
LibraryTouchTargetTests:
  - testViewModeToggleMinimumSize
  - testSortPickerMinimumSize
  - testImportButtonMinimumSize
  - testBookRowMinimumHeight
  - testFormatIconSize

LibraryDynamicTypeTests:
  - testLayoutAtXSmall
  - testLayoutAtDefault
  - testLayoutAtXXXLarge
  - testLayoutAtAX5
  - testNoElementOverflowAtAX5
  - testAccessibilityAuditAtAX5
```

### Files to Create/Modify

| File                                                   | Action |
| ------------------------------------------------------ | ------ |
| `vreaderUITests/Library/LibraryTouchTargetTests.swift` | Create |
| `vreaderUITests/Library/LibraryDynamicTypeTests.swift` | Create |

### Dependencies

WI-UI-0, WI-UI-1, WI-UI-2.

### Rollback

Delete test files.

---

## WI-UI-4: Library View -- Dark Mode and Accessibility

**Goal:** Verify the library view renders correctly in dark mode and passes accessibility audit.

**Non-goals:** Programmatic contrast ratio measurement (deferred to visual QA).

### Acceptance Criteria

1. **Dark mode rendering:**
   - App launches in dark mode (via `--force-dark` launch argument).
   - Library view appears without crashes.
   - Navigation bar, toolbar buttons, and book items are all present (exist and hittable).
   - Empty state is visible with all elements present.
2. **Light mode rendering:**
   - Same checks as dark mode to establish baseline (via `--force-light`).
3. **Accessibility audit:**
   - `performAccessibilityAudit()` on library view reports zero issues in both color schemes.
   - Each book item has a combined accessibility label including title, author, format, and reading time.
   - View mode toggle has dynamic accessibility label.
   - Sort picker has "Sort books" accessibility label.
   - Empty state import button has "Import Books" label.
4. **VoiceOver traversal order:**
   - Accessibility elements appear in logical order: navigation title -> toolbar buttons -> book items (or empty state).
   - All interactive elements are reachable.

### Edge Cases

- VoiceOver with Dynamic Type AX5 simultaneously
- Book item with no author: accessibility label omits "by" prefix
- Book item with zero reading time: accessibility label omits reading time

### Tests

```
LibraryDarkModeTests:
  - testDarkModeLaunchDoesNotCrash
  - testDarkModeEmptyStateVisible
  - testDarkModePopulatedStateVisible
  - testLightModeBaseline
  - testDarkModeAccessibilityAudit
  - testLightModeAccessibilityAudit

LibraryAccessibilityTests:
  - testBookItemAccessibilityLabel
  - testBookItemWithNoAuthorLabel
  - testBookItemWithZeroReadingTimeLabel
  - testViewModeToggleAccessibilityLabel
  - testSortPickerAccessibilityLabel
  - testVoiceOverTraversalOrder
```

### Files to Create/Modify

| File                                                     | Action |
| -------------------------------------------------------- | ------ |
| `vreaderUITests/Library/LibraryDarkModeTests.swift`      | Create |
| `vreaderUITests/Library/LibraryAccessibilityTests.swift` | Create |

### Dependencies

WI-UI-0, WI-UI-1, WI-UI-2.

### Rollback

Delete test files.

---

## WI-UI-5: Delete Confirmation Dialog

**Goal:** Verify the delete book confirmation dialog appears, has correct content, and both Cancel and Delete actions work.

**Non-goals:** Verifying the book is actually deleted from persistence (ViewModel test coverage).

### Acceptance Criteria

1. **Context menu delete (grid mode):**
   - Long press on a book card reveals context menu with "Delete" option.
   - Tapping "Delete" shows confirmation alert with book title.
   - Alert has "Cancel" and "Delete" buttons.
   - "Cancel" dismisses the alert without removing the book.
   - "Delete" dismisses the alert (book removal verified by element count change).
2. **Swipe-to-delete (list mode):**
   - Swiping left on a book row reveals "Delete" button.
   - Tapping the swipe action shows the same confirmation dialog.
3. **Alert text:**
   - Alert title is "Delete Book".
   - Alert message contains the book title in quotes.
   - Alert message includes "This cannot be undone."
4. **Accessibility audit on alert.**

### Edge Cases

- Delete the last book in library: transitions to empty state
- Cancel after swipe: swipe action retracts
- Delete with very long book title: alert message is present (no crash)

### Tests

```
DeleteConfirmationTests:
  - testContextMenuDeleteShowsAlert
  - testAlertContainsBookTitle
  - testCancelDismissesAlert
  - testDeleteRemovesBookFromList
  - testSwipeToDeleteShowsAlert
  - testDeleteLastBookShowsEmptyState
```

### Files to Create/Modify

| File                                                   | Action |
| ------------------------------------------------------ | ------ |
| `vreaderUITests/Library/DeleteConfirmationTests.swift` | Create |

### Dependencies

WI-UI-0, WI-UI-1, WI-UI-2.

### Rollback

Delete test file.

---

## WI-UI-6: Reader Container View -- Navigation and Chrome

**Goal:** Verify the reader container's navigation bar, toolbar buttons, and sheet presentations work for all format types.

**Non-goals:** Testing actual reader content rendering (readers are placeholders — see 0.2). Tests verify placeholder elements exist and chrome (toolbar, sheets) works.

### Prerequisites (from WI-UI-0)

NavigationLink from LibraryView to ReaderContainerView must be wired. Without this, no test in this WI can navigate to the reader.

### Acceptance Criteria

1. **Navigation to reader:**
   - Tapping a book in the library navigates to the reader container.
   - Reader shows format-specific placeholder (e.g., `epubReaderPlaceholder`, `pdfReaderPlaceholder`).
2. **Back button:**
   - Back button is present and hittable (SwiftUI auto-generates this from NavigationStack).
   - Tapping back returns to the library.
3. **Toolbar buttons:**
   - Search button (`readerSearchButton`) exists with label "Search in book".
   - Annotations button (`readerAnnotationsButton`) exists with label "Bookmarks and annotations".
   - Settings button (`readerSettingsButton`) exists with label "Reading settings".
   - All three buttons are hittable.
4. **Settings sheet:**
   - Tapping settings button presents the ReaderSettingsPanel sheet.
   - Sheet has `readerSettingsPanel` identifier.
   - Sheet shows "Reading Settings" title.
   - Sheet can be dismissed by swipe down or drag indicator.
5. **Annotations panel sheet:**
   - Tapping annotations button presents the AnnotationsPanelSheet.
   - Sheet has `annotationsPanelSheet` identifier.
   - Sheet shows segmented picker with "Bookmarks", "Contents", "Highlights", "Notes".
   - Each tab shows a placeholder ContentUnavailableView.
   - Sheet can be dismissed.
6. **Search sheet:**
   - Tapping search button presents the search sheet.
   - Sheet has `searchSheet` identifier.
   - Sheet can be dismissed.
7. **Unsupported format:**
   - A book with unknown format shows `unsupportedFormatView`.
8. **Accessibility audit on reader chrome.**

### Edge Cases

- Double tap on toolbar button: sheet does not double-present
- Dismiss sheet by swipe down: no state leak
- Back navigation while sheet is open: sheet dismisses, then navigates back

### Tests

```
ReaderNavigationTests:
  - testNavigateToEPUBReader
  - testNavigateToPDFReader
  - testNavigateToTXTReader
  - testNavigateToMDReader
  - testBackButtonReturnsToLibrary
  - testToolbarButtonsExist
  - testToolbarButtonAccessibilityLabels
  - testAllToolbarButtonsHittable
  - testReaderChromeAccessibilityAudit

ReaderSettingsSheetTests:
  - testSettingsSheetPresents
  - testSettingsSheetTitle
  - testSettingsSheetDismiss

ReaderAnnotationsPanelTests:
  - testAnnotationsPanelPresents
  - testAnnotationsPanelHasTabs
  - testAnnotationsPanelTabSwitching
  - testAnnotationsPanelDismiss

ReaderSearchSheetTests:
  - testSearchSheetPresents
  - testSearchSheetDismiss

ReaderUnsupportedFormatTests:
  - testUnsupportedFormatShowsMessage
```

### Files to Create/Modify

| File                                                       | Action |
| ---------------------------------------------------------- | ------ |
| `vreaderUITests/Reader/ReaderNavigationTests.swift`        | Create |
| `vreaderUITests/Reader/ReaderSettingsSheetTests.swift`     | Create |
| `vreaderUITests/Reader/ReaderAnnotationsPanelTests.swift`  | Create |
| `vreaderUITests/Reader/ReaderSearchSheetTests.swift`       | Create |
| `vreaderUITests/Reader/ReaderUnsupportedFormatTests.swift` | Create |

### Dependencies

WI-UI-0 (NavigationLink), WI-UI-1, WI-UI-2 (needs populated library).

### Rollback

Delete test files.

---

## WI-UI-7: Reader Settings Panel -- Full Interaction

**Goal:** Verify all controls in the ReaderSettingsPanel work: theme picker, font size slider, line spacing slider, font family picker, CJK toggle, and preview.

**Non-goals:** Verifying actual rendering changes in reader content (readers are placeholders).

### Acceptance Criteria

1. **Theme picker:**
   - Three theme circles visible (light, sepia, dark).
   - Each circle is tappable (44x44pt touch target verified by frame check).
   - Selected theme has `.isSelected` accessibility trait.
   - Theme circles have labels: "light theme", "sepia theme", "dark theme".
2. **Font size slider:**
   - Slider exists with "Font size" accessibility label.
   - Slider value changes when adjusted.
   - Current value display shows point size (e.g., "18pt").
3. **Line spacing slider:**
   - Slider exists with "Line spacing" accessibility label.
   - Current value display shows multiplier (e.g., "1.4x").
4. **Font family picker:**
   - Segmented picker with "System", "Serif", "Monospace" options.
   - "Font family" accessibility label.
   - Each segment is selectable.
5. **CJK spacing toggle:**
   - Toggle exists with "CJK character spacing" accessibility label.
   - Toggle is tappable.
   - Footer text explains the setting.
6. **Accessibility audit on settings panel.**

### Edge Cases

- Toggle CJK spacing rapidly: no crash
- Switch all three font families rapidly: no crash

### Tests

```
ReaderSettingsThemeTests:
  - testThemeCirclesPresent
  - testThemeCircleTouchTargets
  - testThemeCircleSelection
  - testThemeCircleAccessibilityLabels

ReaderSettingsTypographyTests:
  - testFontSizeSliderExists
  - testFontSizeSliderAccessibilityLabel
  - testLineSpacingSliderExists
  - testFontFamilyPickerExists
  - testFontFamilySegments
  - testCJKToggleExists
  - testCJKToggleFooterText
  - testSettingsPanelAccessibilityAudit
```

### Files to Create/Modify

| File                                                        | Action |
| ----------------------------------------------------------- | ------ |
| `vreaderUITests/Reader/ReaderSettingsThemeTests.swift`      | Create |
| `vreaderUITests/Reader/ReaderSettingsTypographyTests.swift` | Create |

### Dependencies

WI-UI-6 (settings sheet access).

### Rollback

Delete test files.

---

## WI-UI-8: PDF Reader Container -- States and Overlays

**Goal:** Verify the PDF reader container's loading, error, password, and content states display correctly.

**Current state:** PDF reader shows placeholder text. The state machine (loading/error/password/content) exists in `PDFReaderContainerView` but is not exercised without a real PDF file URL. Tests verify placeholder presence and password prompt UI (which is a standalone view).

**Non-goals:** Testing PDFKit rendering fidelity. Testing position persistence (ViewModel test).

### Acceptance Criteria

1. **Placeholder state (current):**
   - Navigating to a PDF book shows `pdfReaderPlaceholder` identifier.
2. **Password prompt (standalone view, testable now):**
   - `PDFPasswordPromptView` shows lock icon and explanation text.
   - SecureField (`pdfPasswordField`) is present and focusable.
   - Cancel button (`pdfPasswordCancel`) is present and hittable.
   - Unlock button (`pdfPasswordSubmit`) is present.
   - Unlock button is disabled when password field is empty.
   - Unlock button becomes enabled after typing.
3. **Touch targets:**
   - Cancel and Unlock buttons >= 44x44pt.
   - Password field is tappable.
4. **Accessibility audit on password prompt.**

### Future Tests (blocked until reader wiring)

These tests should be added when real PDF loading is wired:

- `testLoadingStateShowsProgress`
- `testErrorStateShowsMessage`
- `testContentStateShowsPDFView`
- `testBottomOverlayShowsPageIndicator`
- `testPageIndicatorFormat`
- `testPasswordErrorDisplayed`

### Edge Cases

- Password with special characters (Unicode, emoji)
- Submit password via keyboard return key (not just button)

### Tests

```
PDFReaderPlaceholderTests:
  - testPDFPlaceholderExists

PDFPasswordTests:
  - testPasswordPromptShowsAllElements
  - testUnlockButtonDisabledWhenEmpty
  - testUnlockButtonEnabledAfterTyping
  - testCancelButtonIsHittable
  - testPasswordFieldIsFocusable
  - testPasswordPromptTouchTargets
  - testPasswordPromptAccessibilityAudit
```

### Files to Create/Modify

| File                                                    | Action |
| ------------------------------------------------------- | ------ |
| `vreaderUITests/Reader/PDFReaderPlaceholderTests.swift` | Create |
| `vreaderUITests/Reader/PDFPasswordTests.swift`          | Create |

### Dependencies

WI-UI-0, WI-UI-6. Password prompt may need direct presentation (not through reader navigation) if reader wiring isn't available.

### Rollback

Delete test files.

---

## WI-UI-9: TXT and MD Reader Containers -- States

**Goal:** Verify TXT and MD reader containers display their current placeholder states.

**Current state:** Both readers show placeholder text. State machines exist but are not exercised without file URLs.

**Non-goals:** Testing TextKit rendering fidelity. Testing scroll position persistence.

### Acceptance Criteria

1. **TXT Reader placeholder:**
   - Navigating to a TXT book shows `txtReaderPlaceholder` identifier.
2. **MD Reader placeholder:**
   - Navigating to an MD book shows `mdReaderPlaceholder` identifier.
3. **Accessibility audit on both placeholders.**

### Future Tests (blocked until reader wiring)

These tests should be added when real text loading is wired:

- `testTXTLoadingState` / `testTXTErrorState` / `testTXTContentState`
- `testMDLoadingState` / `testMDErrorState` / `testMDContentState`
- `testTextViewIsReadOnly` / `testTextViewIsSelectable` / `testTextViewScrolls`

### Tests

```
TXTReaderPlaceholderTests:
  - testTXTPlaceholderExists
  - testTXTPlaceholderAccessibilityAudit

MDReaderPlaceholderTests:
  - testMDPlaceholderExists
  - testMDPlaceholderAccessibilityAudit
```

### Files to Create/Modify

| File                                                    | Action |
| ------------------------------------------------------- | ------ |
| `vreaderUITests/Reader/TXTReaderPlaceholderTests.swift` | Create |
| `vreaderUITests/Reader/MDReaderPlaceholderTests.swift`  | Create |

### Dependencies

WI-UI-0, WI-UI-6.

### Rollback

Delete test files.

---

## WI-UI-10: Search View -- Placeholder State

**Goal:** Verify the search sheet displays its current placeholder state.

**Current state:** Search sheet shows placeholder content. The full search UI (empty prompt, loading, results, no results, load more, error) exists in `SearchView.swift` but is not mounted in the reader yet.

**Non-goals:** Testing FTS5 search correctness (SearchService unit tests). Testing locator navigation.

### Acceptance Criteria

1. **Search sheet opens:** Tapping search button presents a sheet with `searchSheet` identifier.
2. **Sheet dismisses:** Done/swipe dismisses the sheet.
3. **Accessibility audit on search sheet.**

### Future Tests (blocked until search is mounted)

These tests should be added when SearchView is wired into the reader:

- `testEmptyPromptState`
- `testSearchFieldAcceptsInput`
- `testLoadingState`
- `testResultsDisplay` / `testResultRowContent`
- `testNoResultsState`
- `testLoadMoreButton`
- `testDoneButtonDismisses`
- `testErrorAlert`
- `testClearQueryReturnsToEmpty`
- `testSpecialCharacterQuery`

### Tests

```
SearchSheetPlaceholderTests:
  - testSearchSheetOpens
  - testSearchSheetDismisses
  - testSearchSheetAccessibilityAudit
```

### Files to Create/Modify

| File                                                      | Action |
| --------------------------------------------------------- | ------ |
| `vreaderUITests/Search/SearchSheetPlaceholderTests.swift` | Create |

### Dependencies

WI-UI-6 (search sheet access).

### Rollback

Delete test file.

---

## WI-UI-11: Annotations Panel -- Placeholder States

**Goal:** Verify the annotations panel's four tabs display their placeholder ContentUnavailableViews.

**Current state:** All four tabs (Bookmarks, Contents, Highlights, Notes) show `ContentUnavailableView` placeholders.

**Non-goals:** Testing persistence operations. Testing navigation from annotation to reader position.

### Acceptance Criteria

1. **Tab switching:** Segmented picker switches between all 4 tabs.
2. **Each tab shows a ContentUnavailableView** with appropriate icon and text.
3. **Accessibility audit on annotations panel.**

### Future Tests (blocked until annotation views are wired)

These tests should be added when real annotation data flows:

- `testBookmarkEmptyState` / `testBookmarkPopulatedList` / `testBookmarkSwipeToDelete`
- `testTOCPopulatedList` / `testTOCNestedIndentation`
- `testHighlightPopulatedList` / `testHighlightColorIndicator` / `testHighlightSwipeToDelete`
- `testAnnotationPopulatedList` / `testAnnotationContextMenu` / `testAnnotationEditSheet`
- `testAnnotationEditSaveDisabledWhenEmpty` / `testAnnotationEditCancel`

### Tests

```
AnnotationsPanelPlaceholderTests:
  - testAnnotationsPanelOpens
  - testAnnotationsPanelHasFourTabs
  - testBookmarksTabShowsPlaceholder
  - testContentsTabShowsPlaceholder
  - testHighlightsTabShowsPlaceholder
  - testNotesTabShowsPlaceholder
  - testAnnotationsPanelAccessibilityAudit
```

### Files to Create/Modify

| File                                                                | Action |
| ------------------------------------------------------------------- | ------ |
| `vreaderUITests/Annotations/AnnotationsPanelPlaceholderTests.swift` | Create |

### Dependencies

WI-UI-6 (annotations panel access).

### Rollback

Delete test file.

---

## WI-UI-12: AI Assistant View -- All States

**Goal:** Verify the AI assistant view renders correctly in all seven states: idle, loading, streaming, complete, error, consent required, and feature disabled.

**Non-goals:** Testing actual AI API calls. Testing consent persistence.

### Acceptance Criteria

1. **Feature disabled state:**
   - When AI feature flag is OFF, shows wand icon and "AI features are currently disabled" text.
2. **Consent required state:**
   - When AI is enabled but consent not given, shows `aiConsentView` with lock shield icon, "AI Assistant" title, and privacy explanation.
   - "I Agree -- Enable AI" button (`aiConsentButton`) is present and hittable.
   - Button has `.borderedProminent` style.
   - Revocation notice text is visible.
3. **Idle state:**
   - After consent, shows "Select an action to get AI assistance" text.
4. **Loading state:**
   - Shows ProgressView with "Processing..." text.
5. **Streaming state:**
   - Shows ScrollView with response text accumulating.
6. **Complete state:**
   - Shows ScrollView with full response text.
   - Text is selectable (`.textSelection(.enabled)`).
7. **Error state:**
   - Shows warning icon and error message.
   - Error message is user-friendly (sanitized).
8. **Accessibility audit on consent view and assistant view.**

### Testing Approach

States 3-7 (idle, loading, streaming, complete, error) require ViewModel state manipulation. Since XCUITest cannot directly set ViewModel state, these tests require one of:

- A `--ai-mock-state=idle|loading|streaming|complete|error` launch argument that sets a mock ViewModel state.
- Or defer to unit tests (already covered).

**Recommendation:** Test states 1-2 (feature disabled, consent required) via XCUITest with feature flag launch arguments. States 3-7 are better covered by ViewModel unit tests. Add XCUITest coverage when the AI assistant is fully integrated.

### Edge Cases

- Consent view with Dynamic Type AX5: all text visible
- Consent button touch target >= 44x44pt

### Tests

```
AIAssistantStateTests:
  - testFeatureDisabledState
  - testConsentRequiredState
  - testConsentButtonHittable

AIConsentViewTests:
  - testConsentViewElements
  - testConsentButtonTouchTarget
  - testConsentViewAccessibilityAudit
```

### Files to Create/Modify

| File                                            | Action |
| ----------------------------------------------- | ------ |
| `vreaderUITests/AI/AIAssistantStateTests.swift` | Create |
| `vreaderUITests/AI/AIConsentViewTests.swift`    | Create |

### Dependencies

WI-UI-0, WI-UI-1 (with `--enable-ai` flag).

### Rollback

Delete test files.

---

## WI-UI-13: Sync Status Views

**Goal:** Verify sync status badge and file availability badge render all states correctly.

**Non-goals:** Testing actual sync operations. Testing CloudKit integration.

### Testing Approach

`SyncStatusView` conditionally renders based on `monitor.status`. Since XCUITest cannot inject sync states, these tests require either:

- A `--sync-mock-state=idle|syncing|error|offline` launch argument.
- Or verify only the `.disabled` state (sync feature off) and `.idle` state (sync enabled, default).

**Recommendation:** Test `.disabled` (hidden) and basic presence when sync is enabled. Specific state rendering is better covered by ViewInspector or unit tests.

### Acceptance Criteria

1. **Sync disabled:** With `--enable-sync` absent, no sync badge is visible.
2. **Sync enabled:** With `--enable-sync`, sync status area is present.
3. **FileAvailabilityBadge:** When visible, badge elements exist.
4. **Accessibility labels** use `AccessibilityFormatters.accessibleSyncStatus`.
5. **Accessibility audit.**

### Tests

```
SyncStatusViewTests:
  - testSyncDisabledHidesBadge
  - testSyncEnabledShowsBadge
  - testSyncAccessibilityAudit

FileAvailabilityBadgeTests:
  - testBadgeHiddenWhenAvailable
  - testBadgeAccessibilityLabels
```

### Files to Create/Modify

| File                                                   | Action |
| ------------------------------------------------------ | ------ |
| `vreaderUITests/Sync/SyncStatusViewTests.swift`        | Create |
| `vreaderUITests/Sync/FileAvailabilityBadgeTests.swift` | Create |

### Dependencies

WI-UI-0, WI-UI-1 (with `--enable-sync` flag).

### Rollback

Delete test files.

---

## WI-UI-14: Error Screens and Alert Dialogs

**Goal:** Verify all error states and alert dialogs display correctly with user-friendly messages.

**Non-goals:** Testing error recovery logic.

### Acceptance Criteria

1. **App init error screen (VReaderApp):**
   - When database fails to init (via `--seed-corrupt-db` launch argument), error screen shows warning icon, "Unable to Open Library" title, and sanitized error message.
   - No file paths or technical details in error message.
   - Screen has combined accessibility label.
2. **Library error alert:**
   - Error alert shows "Error" title, error message, and "OK" button.
   - "OK" button dismisses the alert.
3. **Accessibility audit on error screen.**

### Edge Cases

- Error message containing HTML tags: rendered as plain text
- Error message with Unicode characters

### Tests

```
ErrorScreenTests:
  - testInitErrorScreen
  - testInitErrorNoFilePaths
  - testInitErrorAccessibilityAudit

AlertDialogTests:
  - testLibraryErrorAlert
  - testLibraryErrorAlertDismisses
```

### Files to Create/Modify

| File                                           | Action |
| ---------------------------------------------- | ------ |
| `vreaderUITests/Errors/ErrorScreenTests.swift` | Create |
| `vreaderUITests/Errors/AlertDialogTests.swift` | Create |

### Dependencies

WI-UI-0, WI-UI-1.

### Rollback

Delete test files.

---

## WI-UI-15: Full Navigation Flow Integration

**Goal:** Verify end-to-end navigation flows work: library -> reader -> settings -> back, library -> reader -> annotations -> tab switch -> dismiss, and all transitions are smooth.

**Non-goals:** Testing every possible permutation of navigation.

### Acceptance Criteria

1. **Library to reader and back:**
   - Tap book -> reader appears (placeholder visible) -> tap back -> library appears.
   - Library state is preserved after returning from reader.
2. **Reader to settings and back:**
   - Tap settings -> sheet appears -> dismiss sheet -> reader visible.
3. **Reader to annotations panel:**
   - Tap annotations -> panel appears -> switch tabs -> dismiss -> reader visible.
4. **Full round trip:**
   - Library -> tap book -> reader -> settings sheet -> dismiss -> annotations panel -> dismiss -> back button -> library.
5. **Reduce Motion:**
   - With `--reduce-motion` flag, all transitions complete without animation.
   - No crashes from suppressed animations.

### Edge Cases

- Rapid back/forward navigation (tap book, immediately tap back)
- Open sheet then tap back button
- Navigate to different format readers in sequence

### Tests

```
NavigationFlowTests:
  - testLibraryToReaderAndBack
  - testReaderSettingsRoundTrip
  - testReaderAnnotationsRoundTrip
  - testFullNavigationRoundTrip
  - testRapidBackNavigation
  - testReduceMotionTransitions
```

### Files to Create/Modify

| File                                                  | Action |
| ----------------------------------------------------- | ------ |
| `vreaderUITests/Navigation/NavigationFlowTests.swift` | Create |

### Dependencies

WI-UI-0, WI-UI-1, WI-UI-2, WI-UI-6.

### Rollback

Delete test file.

---

## WI-UI-16: Keyboard Interaction

**Goal:** Verify keyboard-driven interactions work correctly for PDF password entry and any other currently-mounted text fields.

**Non-goals:** Testing hardware keyboard shortcuts (iOS reader app is primarily touch). Search and annotation edit keyboard tests are deferred until those views are mounted.

### Acceptance Criteria

1. **PDF password SecureField:**
   - Tapping password field raises keyboard.
   - Typing obscured characters appear.
   - Return key triggers password submission.
   - Keyboard dismisses after submission.
2. **Safe area with keyboard:**
   - Keyboard does not obscure the active input field.

### Future Tests (blocked until search/annotations are wired)

- `testSearchFieldKeyboard` / `testSearchFieldTyping`
- `testAnnotationEditKeyboard`
- `testInputVisibleWithKeyboard`

### Edge Cases

- Emoji keyboard input: no crash
- Paste into password field: works correctly

### Tests

```
KeyboardInteractionTests:
  - testPDFPasswordKeyboard
  - testPDFPasswordReturnKey
  - testPasswordFieldVisibleWithKeyboard
```

### Files to Create/Modify

| File                                                     | Action |
| -------------------------------------------------------- | ------ |
| `vreaderUITests/Keyboard/KeyboardInteractionTests.swift` | Create |

### Dependencies

WI-UI-8.

### Rollback

Delete test file.

---

## WI-UI-17: Cross-Screen Accessibility Audit Sweep

**Goal:** Run `performAccessibilityAudit()` on every reachable screen in a single test suite, serving as a regression safety net. Individual WIs already include per-screen audits; this is the consolidated sweep.

**Non-goals:** Manual VoiceOver testing (requires human testers).

### Acceptance Criteria

1. **Screens audited (all reachable in current app state):**
   - Library (empty state)
   - Library (populated state)
   - Reader container (each format placeholder)
   - Reader settings panel
   - Annotations panel
   - Search sheet (placeholder)
   - AI consent view (with `--enable-ai`)
   - PDF password prompt
   - Error init screen
2. **Audit categories checked:**
   - Dynamic Type
   - Sufficient contrast
   - Touch target sizes
   - Element descriptions (labels)
3. **All audits pass with zero violations.**
4. **Dark mode sweep:** All screens audited again with `--force-dark`.
5. **AX5 sweep:** Library and reader chrome audited with `--dynamic-type-AX5`.

### Tests

```
GlobalAccessibilityAuditTests:
  - testLibraryEmptyAudit
  - testLibraryPopulatedAudit
  - testReaderContainerAudit
  - testReaderSettingsAudit
  - testAnnotationsPanelAudit
  - testSearchSheetAudit
  - testAIConsentAudit
  - testPDFPasswordPromptAudit
  - testErrorScreenAudit
  - testDarkModeAuditAllScreens
  - testAX5AuditLibraryAndReaderChrome
```

### Files to Create/Modify

| File                                                               | Action |
| ------------------------------------------------------------------ | ------ |
| `vreaderUITests/Accessibility/GlobalAccessibilityAuditTests.swift` | Create |

### Dependencies

WI-UI-0 through WI-UI-14 (all screens must be navigable).

### Rollback

Delete test file.

---

## Appendix A: Complete Accessibility Identifier Registry

| Identifier                | View                   | Purpose                |
| ------------------------- | ---------------------- | ---------------------- |
| `libraryView`             | ContentView            | Root library container |
| `importBooksButton`       | LibraryView            | Import CTA button      |
| `emptyLibraryState`       | LibraryView            | Empty state container  |
| `viewModeToggle`          | LibraryView            | Grid/list toggle       |
| `sortPicker`              | LibraryView            | Sort menu              |
| `readerBackButton`        | ReaderContainerView    | Back to library        |
| `readerSearchButton`      | ReaderContainerView    | Open search            |
| `readerAnnotationsButton` | ReaderContainerView    | Open annotations panel |
| `readerSettingsButton`    | ReaderContainerView    | Open settings          |
| `searchSheet`             | ReaderContainerView    | Search sheet           |
| `annotationsPanelSheet`   | ReaderContainerView    | Annotations panel      |
| `epubReaderPlaceholder`   | ReaderContainerView    | EPUB placeholder       |
| `pdfReaderPlaceholder`    | ReaderContainerView    | PDF placeholder        |
| `txtReaderPlaceholder`    | ReaderContainerView    | TXT placeholder        |
| `mdReaderPlaceholder`     | ReaderContainerView    | MD placeholder         |
| `unsupportedFormatView`   | ReaderContainerView    | Unknown format         |
| `readerSettingsPanel`     | ReaderSettingsPanel    | Settings panel         |
| `pdfReaderContainer`      | PDFReaderContainerView | PDF container          |
| `pdfReaderContent`        | PDFReaderContainerView | PDF view               |
| `pdfReaderLoading`        | PDFReaderContainerView | Loading overlay        |
| `pdfReaderError`          | PDFReaderContainerView | Error overlay          |
| `pdfBottomOverlay`        | PDFReaderContainerView | Bottom bar             |
| `pdfPageIndicator`        | PDFReaderContainerView | Page X/Y               |
| `pdfSessionTime`          | PDFReaderContainerView | Session timer          |
| `pdfPagesPerHour`         | PDFReaderContainerView | Speed display          |
| `pdfView`                 | PDFViewBridge          | PDFKit view            |
| `pdfPasswordPrompt`       | PDFPasswordPromptView  | Password dialog        |
| `pdfPasswordField`        | PDFPasswordPromptView  | Password input         |
| `pdfPasswordError`        | PDFPasswordPromptView  | Wrong password msg     |
| `pdfPasswordCancel`       | PDFPasswordPromptView  | Cancel button          |
| `pdfPasswordSubmit`       | PDFPasswordPromptView  | Unlock button          |
| `txtReaderContainer`      | TXTReaderContainerView | TXT container          |
| `txtReaderLoading`        | TXTReaderContainerView | Loading state          |
| `txtReaderError`          | TXTReaderContainerView | Error state            |
| `txtReaderContent`        | TXTReaderContainerView | Text view              |
| `mdReaderContainer`       | MDReaderContainerView  | MD container           |
| `mdReaderLoading`         | MDReaderContainerView  | Loading state          |
| `mdReaderError`           | MDReaderContainerView  | Error state            |
| `mdReaderContent`         | MDReaderContainerView  | Attributed text        |
| `searchView`              | SearchView             | Search container       |
| `searchDismissButton`     | SearchView             | Done button            |
| `searchResultsList`       | SearchView             | Results list           |
| `searchResult_{id}`       | SearchView             | Individual result      |
| `searchResultRow`         | SearchResultRow        | Row view               |
| `loadMoreButton`          | SearchView             | Pagination button      |
| `searchLoadingView`       | SearchView             | Loading spinner        |
| `searchNoResultsView`     | SearchView             | No results             |
| `searchEmptyPromptView`   | SearchView             | Initial prompt         |
| `bookmarkEmptyState`      | BookmarkListView       | Empty state            |
| `bookmarkRow-{id}`        | BookmarkListView       | Bookmark row           |
| `tocEmptyState`           | TOCListView            | Empty state            |
| `tocRow-{id}`             | TOCListView            | TOC row                |
| `highlightEmptyState`     | HighlightListView      | Empty state            |
| `highlightRow-{id}`       | HighlightListView      | Highlight row          |
| `annotationEmptyState`    | AnnotationListView     | Empty state            |
| `annotationRow-{id}`      | AnnotationListView     | Annotation row         |
| `annotationEditCancel`    | AnnotationEditSheet    | Cancel button          |
| `annotationEditSave`      | AnnotationEditSheet    | Save button            |
| `aiConsentView`           | AIConsentView          | Consent container      |
| `aiConsentButton`         | AIConsentView          | Agree button           |

---

## Appendix B: Test Execution Order

WI-UI-0 must be completed first (production code prerequisites). WI-UI-1 is next (test infrastructure). WI-UI-2 is the pilot vertical slice that validates the full pipeline. After WI-UI-2 passes, remaining WIs can be parallelized.

```
WI-UI-0  (integration prerequisites -- production code)
   |
WI-UI-1  (test infrastructure)
   |
WI-UI-2  (library layout -- PILOT VERTICAL SLICE)
   |
   +-- Verify pilot passes 3x without flakes
   |
   +-- WI-UI-3  (touch targets + dynamic type)
   +-- WI-UI-4  (dark mode + a11y)
   +-- WI-UI-5  (delete dialog)
   |
   +-- WI-UI-6  (reader navigation)
   |      |
   |      +-- WI-UI-7  (settings panel)
   |      +-- WI-UI-8  (PDF reader placeholder + password)
   |      +-- WI-UI-9  (TXT/MD reader placeholders)
   |      +-- WI-UI-10 (search placeholder)
   |      +-- WI-UI-11 (annotations placeholders)
   |
   +-- WI-UI-12 (AI assistant -- feature flag states)
   +-- WI-UI-13 (sync views -- feature flag states)
   +-- WI-UI-14 (error screens)
   |
   +-- WI-UI-15 (navigation flows) -- depends on WI-UI-2, WI-UI-6
   +-- WI-UI-16 (keyboard)         -- depends on WI-UI-8
   +-- WI-UI-17 (global a11y sweep) -- depends on all above
```

---

## Appendix C: File Structure

```
vreaderUITests/
  Fixtures/
    fixture-epub.epub
    fixture-pdf.pdf
    fixture-txt.txt
    fixture-md.md
    fixture-long-title.txt
    fixture-cjk.txt
    fixture-zero-time.epub
    fixture-password.pdf
  Helpers/
    TestConstants.swift
    LaunchHelper.swift
    AccessibilityAuditHelper.swift
  Library/
    LibraryEmptyStateTests.swift
    LibraryPopulatedTests.swift
    LibraryEdgeCaseTests.swift
    LibraryTouchTargetTests.swift
    LibraryDynamicTypeTests.swift
    LibraryDarkModeTests.swift
    LibraryAccessibilityTests.swift
    DeleteConfirmationTests.swift
  Reader/
    ReaderNavigationTests.swift
    ReaderSettingsSheetTests.swift
    ReaderAnnotationsPanelTests.swift
    ReaderSearchSheetTests.swift
    ReaderUnsupportedFormatTests.swift
    ReaderSettingsThemeTests.swift
    ReaderSettingsTypographyTests.swift
    PDFReaderPlaceholderTests.swift
    PDFPasswordTests.swift
    TXTReaderPlaceholderTests.swift
    MDReaderPlaceholderTests.swift
  Search/
    SearchSheetPlaceholderTests.swift
  Annotations/
    AnnotationsPanelPlaceholderTests.swift
  AI/
    AIAssistantStateTests.swift
    AIConsentViewTests.swift
  Sync/
    SyncStatusViewTests.swift
    FileAvailabilityBadgeTests.swift
  Errors/
    ErrorScreenTests.swift
    AlertDialogTests.swift
  Navigation/
    NavigationFlowTests.swift
  Keyboard/
    KeyboardInteractionTests.swift
  Accessibility/
    GlobalAccessibilityAuditTests.swift
```

Total: 30 test files, \~95 test methods across 18 work items (WI-UI-0 through WI-UI-17).

---

## Appendix D: Future Test Backlog

Tests deferred until integration layers are wired. Track these and add them as features ship.

| Blocked Feature      | Tests Needed                                                           | Unblocked When                               |
| -------------------- | ---------------------------------------------------------------------- | -------------------------------------------- |
| Real PDF loading     | Loading/error/content states, page indicator, session time             | PDF file URL pipeline wired                  |
| Real TXT/MD loading  | Loading/error/content states, read-only/selectable/scrollable          | Text file URL pipeline wired                 |
| Search mounting      | Full search flow (empty prompt, results, no results, load more, error) | SearchView mounted in reader                 |
| Annotation data flow | Bookmark/TOC/highlight/annotation CRUD, edit sheet, swipe-to-delete    | Annotation ViewModels wired to persistence   |
| AI response states   | Idle, loading, streaming, complete, error states                       | AI ViewModel state injection via launch args |
| Sync state rendering | All 5 sync states, file availability badge states                      | Sync mock state injection                    |
| Large library scroll | 100+ books, lazy loading performance                                   | Test seeder supports bulk insertion          |

