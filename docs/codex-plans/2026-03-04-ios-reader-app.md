# iOS Reader App - Implementation Plan

**Date:** 2026-03-04
**Status:** Draft
**Project:** vreader (iOS)

---

## 1. Research Summary

### Industry Best Practices for iOS Reader Apps

**Architecture:**

- SwiftUI + MVVM is the modern standard for new iOS apps (iOS 16+). UIKit is reserved for legacy or highly custom rendering needs.
- The Composable Architecture (TCA) from Point-Free is popular for testable state management, but adds complexity. For a reader app, plain MVVM with `@Observable` (iOS 17+) or `ObservableObject` (iOS 16+) is simpler and sufficient.
- Apple's own Books app, Kindle, and Readwise Reader all use a combination of native rendering for UI chrome and web views or custom text rendering for content display.

**File Format Support:**

- EPUB is the dominant open format (ePub 2/3). Kindle's KFX/AZW3 requires proprietary handling. PDF via PDFKit is built-in.
- Plain text and Markdown are trivial to support natively.
- For EPUB parsing, `ReadiumKit` (Readium Mobile) is the industry-standard open-source toolkit. It handles EPUB 2/3, PDF, and audiobooks with a mature, well-tested codebase.
- Alternatively, `FolioReaderKit` exists but is less maintained.

**Reading Experience:**

- Adjustable font size, font family, line spacing, margins, themes (light/dark/sepia) are table stakes.
- Pagination vs. scrolling: most dedicated readers offer both. Apple Books uses pagination. Kindle offers both.
- Night mode / OLED-friendly true black theme.

**Prior Art:**

- **Apple Books**: SwiftUI shell, custom rendering engine, iCloud sync.
- **Kindle**: UIKit-heavy, custom text rendering, Whispersync.
- **Readwise Reader**: Web-based reader with native shell, highlighting and annotation focus.
- **KOReader**: Open-source, C/Lua, not directly applicable but shows feature scope.

### AI Integration in Reader Apps

**Prior Art:**

- **Kindle X-Ray**: Character/concept lookup, vocabulary builder with contextual definitions. Works offline with pre-indexed data.
- **Readwise Reader Ghostreader**: AI summarization, Q\&A about highlighted text, auto-tagging. Uses OpenAI API. Context-aware — sends surrounding paragraphs, not entire book.
- **Google Play Books**: AI summaries and Q\&A for non-fiction. Server-side processing.
- **Apple Intelligence (iOS 18+)**: System-level summarization expanding to first-party apps. On-device for privacy.

**Best Practices:**

- Extract context window around current reading position (2000-4000 tokens) rather than sending entire book. Reduces latency, cost, and privacy exposure.
- Protocol-based AI provider abstraction enables swapping backends (OpenAI, Anthropic, local models, Apple Foundation Models).
- Cache responses per `(bookId, locator, actionType)` tuple to avoid redundant API calls for the same passage.
- Stream responses token-by-token for perceived speed.
- AI features must be fully optional — app works without any API key configured.
- Handle rate limits, network errors, and content policy rejections with clear user-facing messages.
- Vocabulary lookup should include pronunciation, part of speech, and usage in context.

### Technology Decision: Swift 6 + SwiftUI + Swift Data

| Choice                    | Rationale                                                                                      |
| ------------------------- | ---------------------------------------------------------------------------------------------- |
| **Swift 6**               | Strict concurrency checking catches data races at compile time.                                |
| **SwiftUI**               | Declarative UI, less boilerplate, native dark mode, accessibility built in.                    |
| **Swift Data**            | Apple's modern persistence (replaces Core Data). Simpler, SwiftUI-integrated.                  |
| **Readium Swift Toolkit** | Battle-tested EPUB/PDF parsing, saves months of format work.                                   |
| **Swift Testing**         | Modern test framework (`@Test`, `#expect`) over XCTest for new code.                           |
| **Minimum iOS 17**        | Enables `@Observable`, Swift Data, and latest SwiftUI features. Covers 85%+ of active devices. |

### Key Trade-offs

| Decision                          | Pro                                    | Con                              | Mitigation                                               |
| --------------------------------- | -------------------------------------- | -------------------------------- | -------------------------------------------------------- |
| iOS 17 minimum                    | Latest APIs, simpler code              | Drops iOS 16 users (\~15%)       | Can backport later if needed                             |
| SwiftUI only (no UIKit)           | Faster development, less code          | Some custom rendering limited    | Use UIViewRepresentable for EPUB content view            |
| Swift Data over Core Data         | Less boilerplate, modern               | Fewer migration tools, newer     | Start fresh, no migration needed                         |
| Readium over custom parser        | Save months, battle-tested             | Large dependency, learning curve | Wrap behind protocol for future swap                     |
| OpenAI-compatible REST API for AI | Wide provider support, well-documented | Requires network, API key        | Protocol abstraction, optional feature, response caching |

---

## 2. Core Features (MVP)

### P0 - Must Have

1. **Library view** - Grid/list of imported books with cover art
2. **EPUB reader** - Paginated reading with Readium
3. **PDF reader** - PDFKit-based viewing
4. **Reading position persistence** - Resume where you left off
5. **Typography settings** - Font size, font family, line spacing, theme
6. **Dark mode** - System-aware + manual toggle (light/dark/sepia)
7. **Bookmarks** - Mark and jump to pages
8. **Search** - Full-text search within a book
9. **File import** - Open from Files.app, share sheet, drag-and-drop
10. **Highlights and annotations** - Select text, highlight, add notes
11. **AI Integration** - Summarization, Q\&A, translation, vocabulary lookup for current reading content
12. **iCloud sync** - Library, reading positions, bookmarks, and highlights sync

### P1 - Should Have

13. **Table of contents** - Chapter navigation
14. **Reading statistics** - Time spent, pages read, progress

### P2 - Nice to Have

15. **OPDS catalog** - Browse and download from OPDS feeds
16. **Text-to-speech** - AVSpeechSynthesizer integration
17. **Markdown/plain text** - Basic support for .md and .txt files
18. **Export highlights** - Share annotations as Markdown

---

## 3. Project Structure

```
vreader/
├── AGENTS.md                          # Shared AI agent conventions
├── CLAUDE.md                          # Claude-specific notes
├── .claude/                           # Claude rules, skills, agents
├── docs/
│   └── codex-plans/
│       └── 2026-03-04-ios-reader-app.md
├── vreader.xcodeproj/                 # Xcode project
├── vreader/
│   ├── App/
│   │   ├── VReaderApp.swift           # @main entry point
│   │   └── AppState.swift             # Top-level app state
│   ├── Models/
│   │   ├── Book.swift                 # Swift Data model
│   │   ├── Bookmark.swift             # Bookmark model
│   │   ├── Highlight.swift            # Highlight/annotation model
│   │   ├── ReadingPosition.swift      # Position persistence model
│   │   └── AIInteraction.swift        # Cached AI response model
│   ├── Views/
│   │   ├── Library/
│   │   │   ├── LibraryView.swift      # Grid/list of books
│   │   │   ├── BookCard.swift         # Single book in grid
│   │   │   └── LibraryViewModel.swift
│   │   ├── Reader/
│   │   │   ├── ReaderView.swift       # Container for reading
│   │   │   ├── EPUBReaderView.swift   # EPUB rendering (Readium)
│   │   │   ├── PDFReaderView.swift    # PDF rendering (PDFKit)
│   │   │   ├── ReaderViewModel.swift
│   │   │   └── ReaderSettingsView.swift
│   │   ├── Bookmarks/
│   │   │   ├── BookmarksView.swift
│   │   │   └── BookmarksViewModel.swift
│   │   ├── AI/
│   │   │   ├── AIAssistantView.swift      # Bottom sheet AI panel
│   │   │   └── AIAssistantViewModel.swift # AI action state management
│   │   └── Settings/
│   │       ├── SettingsView.swift
│   │       ├── ThemeSettingsView.swift
│   │       └── AISettingsView.swift       # API key, provider config
│   ├── Services/
│   │   ├── BookImporter.swift         # File import logic
│   │   ├── ReadiumService.swift       # Readium wrapper
│   │   ├── SearchService.swift        # Full-text search
│   │   ├── ThemeService.swift         # Theme management
│   │   ├── AIService.swift            # AI provider abstraction (protocol + impl)
│   │   └── Mocks/
│   │       └── MockAIService.swift    # Mock for testing
│   ├── Utils/
│   │   ├── FileUtils.swift            # File path helpers
│   │   ├── DateUtils.swift            # Date formatting
│   │   └── TextExtractor.swift        # Extract text context from reading position
│   ├── Extensions/
│   │   └── Color+Theme.swift          # Color extensions
│   ├── Resources/
│   │   ├── Assets.xcassets
│   │   └── Fonts/                     # Bundled reading fonts
│   └── Preview Content/
├── vreaderTests/
│   ├── Models/
│   │   ├── BookTests.swift
│   │   ├── BookmarkTests.swift
│   │   ├── ReadingPositionTests.swift
│   │   └── AIInteractionTests.swift
│   ├── Services/
│   │   ├── BookImporterTests.swift
│   │   ├── SearchServiceTests.swift
│   │   ├── ThemeServiceTests.swift
│   │   ├── AIServiceTests.swift
│   │   └── Mocks/
│   │       └── MockAIService.swift
│   └── ViewModels/
│       ├── LibraryViewModelTests.swift
│       ├── ReaderViewModelTests.swift
│       ├── BookmarksViewModelTests.swift
│       └── AIAssistantViewModelTests.swift
└── vreaderUITests/
    ├── LibraryUITests.swift
    └── ReaderUITests.swift
```

**File budget:** Every Swift file stays under \~300 lines. ViewModels split by responsibility.

---

## 4. Implementation Phases

### Phase 1: Foundation (Week 1-2)

**Goal:** Xcode project, models, basic library view, file import.

### Phase 2: EPUB Reader (Week 3-4)

**Goal:** Open and read EPUB files with Readium, pagination, basic typography.

### Phase 3: PDF Reader + Settings (Week 5)

**Goal:** PDF viewing, typography/theme settings panel, reading position persistence.

### Phase 4: Bookmarks + Search (Week 6)

**Goal:** Bookmark system, full-text search, table of contents navigation.

### Phase 5: Highlights + Annotations (Week 7-8)

**Goal:** Text highlighting, annotations, annotation list view.

### Phase 6: AI Integration (Week 9-10)

**Goal:** AI service abstraction, summarization, Q\&A, translation, vocabulary lookup. Settings for API key and provider. Response caching.

### Phase 7: iCloud Sync + Polish (Week 11)

**Goal:** iCloud sync for metadata/positions/bookmarks/highlights, accessibility audit, performance profiling, app icon and launch screen.

---

## 5. Work Items

### WI-1: Project Scaffold and Data Models

**Goal:** Create Xcode project with Swift Package dependencies, define Swift Data models, establish test infrastructure.

**Non-goals:** No UI beyond a placeholder screen. No file parsing.

**Tasks:**

1. Create Xcode project targeting iOS 17+
2. Add Swift Package dependencies: Readium (r2-shared-swift, r2-streamer-swift, r2-navigator-swift)
3. Define Swift Data models: `Book`, `Bookmark`, `Highlight`, `ReadingPosition`
4. Set up test targets with Swift Testing framework
5. Configure CI-friendly test scheme

**Edge Cases:**

- Book with no title metadata (use filename as fallback)
- Book with no cover image (use placeholder)
- Duplicate book import (detect by file hash)
- ReadingPosition for deleted book (cascade delete)
- Unicode/CJK book titles and author names
- Extremely long title strings (truncation)
- Empty library (first-launch state)

**Acceptance Criteria:**

- [ ] `swift build` succeeds
- [ ] `swift test` passes all model tests
- [ ] Book model round-trips through Swift Data (insert, fetch, delete)
- [ ] Bookmark and Highlight cascade-delete when parent Book is deleted
- [ ] ReadingPosition stores chapter + progress percentage
- [ ] Duplicate detection test: same file hash returns existing Book

**Tests:**

- `BookTests.swift`: creation, default values, hash computation, title fallback
- `BookmarkTests.swift`: creation, ordering, cascade delete
- `ReadingPositionTests.swift`: persistence, update, deletion with book
- `HighlightTests.swift`: creation with text range, color, note

**Touched Areas:** New project, `Models/`, `vreaderTests/Models/`

**Rollback:** Delete Xcode project directory.

---

### WI-2: Book Import Service

**Goal:** Import EPUB and PDF files from Files.app, share sheet, and drag-and-drop. Copy to app sandbox, extract metadata.

**Non-goals:** No reading. No cloud import.

**Tasks:**

1. Implement `BookImporter` service with protocol for testability
2. Copy file to app's Documents directory with unique name
3. Extract metadata (title, author, cover, page count) using Readium for EPUB, PDFKit for PDF
4. Create `Book` record in Swift Data
5. Handle duplicate detection (SHA-256 hash of file)

**Edge Cases:**

- Corrupt EPUB file (invalid ZIP, missing content.opf)
- Corrupt PDF file (PDFDocument returns nil)
- File with no read permission (security-scoped bookmark expired)
- Import during low disk space
- Very large file (500MB+ PDF) — show progress
- File with non-UTF8 metadata encoding
- Concurrent imports of same file (race condition)
- Import from external drive that gets ejected mid-copy
- EPUB with DRM (detect and show message, do not attempt to strip)
- File extension mismatch (e.g., .epub that is actually a renamed .zip)

**Acceptance Criteria:**

- [ ] EPUB import extracts title, author, cover, language
- [ ] PDF import extracts title, page count
- [ ] Corrupt file import returns descriptive error, does not crash
- [ ] Duplicate file returns existing Book without re-copying
- [ ] File is copied to sandbox (original can be deleted)
- [ ] Import cancellation cleans up partial copy
- [ ] DRM-protected EPUB shows user-friendly error

**Tests:**

- `BookImporterTests.swift`: import valid EPUB, import valid PDF, corrupt EPUB, corrupt PDF, duplicate detection, disk space handling (mocked), DRM detection, concurrent import guard
- Test fixtures: small valid EPUB, small valid PDF, corrupt files

**Touched Areas:** `Services/BookImporter.swift`, `vreaderTests/Services/BookImporterTests.swift`, test fixtures

**Rollback:** Remove `BookImporter.swift` and tests.

---

### WI-3: Library View

**Goal:** Display imported books in a grid with cover thumbnails. Support list/grid toggle, sort, and delete.

**Non-goals:** No reading navigation. No search.

**Tasks:**

1. `LibraryView` with `LazyVGrid` for grid mode, `List` for list mode
2. `BookCard` component showing cover, title, author, progress
3. `LibraryViewModel` managing sort order, layout mode, deletion
4. Empty state view with import CTA
5. Pull-to-refresh (re-scan metadata)
6. Swipe-to-delete with confirmation
7. Context menu (delete, info)

**Edge Cases:**

- Empty library (show onboarding/empty state)
- Library with 1000+ books (performance with LazyVGrid)
- Missing cover image (placeholder with first letter of title)
- Very long title (2-line truncation)
- RTL book titles (Arabic, Hebrew)
- VoiceOver accessibility labels for every interactive element
- Dynamic Type support (all text scales)
- Landscape orientation layout change
- iPad multi-column layout

**Acceptance Criteria:**

- [ ] Grid view shows book covers in responsive columns
- [ ] List view shows title, author, progress in rows
- [ ] Empty state displays import prompt
- [ ] Delete removes book and file from sandbox
- [ ] Sort by title, author, date added, last read
- [ ] VoiceOver reads book title, author, progress percentage
- [ ] Dynamic Type scales all text appropriately

**Tests:**

- `LibraryViewModelTests.swift`: sort ordering (all 4 modes), delete action updates state, toggle layout mode, empty state detection
- UI tests: `LibraryUITests.swift` — grid renders, delete flow, empty state

**Touched Areas:** `Views/Library/`, `vreaderTests/ViewModels/LibraryViewModelTests.swift`

**Rollback:** Remove `Views/Library/` directory.

---

### WI-4: EPUB Reader with Readium

**Goal:** Open and read EPUB files with paginated display, basic navigation (swipe/tap to turn pages).

**Non-goals:** No typography customization yet. No bookmarks.

**Tasks:**

1. `ReadiumService` wrapping Readium's Streamer and Navigator
2. `EPUBReaderView` using `UIViewControllerRepresentable` to wrap Readium's navigator
3. `ReaderViewModel` managing current position, page turns, chapter info
4. Page turn via swipe gesture and edge taps
5. Progress bar at bottom
6. Save reading position on page turn and app background

**Edge Cases:**

- EPUB with fixed layout (comics, picture books) vs. reflowable
- EPUB with embedded fonts
- EPUB with MathML content
- EPUB with SVG images
- Very short EPUB (1 page) — no pagination needed
- EPUB with right-to-left reading direction (manga)
- Memory pressure during large EPUB rendering
- App backgrounded during page turn animation
- EPUB with broken internal links
- EPUB 2 vs EPUB 3 differences
- Rapid page turns (debounce position save)

**Acceptance Criteria:**

- [ ] EPUB opens and displays first chapter content
- [ ] Swipe left/right turns pages
- [ ] Tap left/right edges turns pages
- [ ] Progress bar shows current position (0-100%)
- [ ] Position is restored on re-open
- [ ] Fixed-layout EPUBs render correctly
- [ ] RTL EPUBs page in correct direction
- [ ] Position save is debounced (not every frame)

**Tests:**

- `ReaderViewModelTests.swift`: page turn updates position, position restore, progress calculation, debounce logic
- `ReadiumServiceTests.swift`: open valid EPUB, handle missing file, position save/load
- Integration test with test EPUB fixture

**Touched Areas:** `Views/Reader/`, `Services/ReadiumService.swift`, `vreaderTests/`

**Rollback:** Remove reader views and ReadiumService.

---

### WI-5: PDF Reader

**Goal:** Open and read PDF files with PDFKit, page navigation, zoom.

**Non-goals:** No annotation on PDF. No form filling.

**Tasks:**

1. `PDFReaderView` wrapping `PDFView` via `UIViewRepresentable`
2. Page navigation (swipe, page indicator)
3. Pinch-to-zoom
4. Save/restore reading position (page number)
5. Thumbnail page navigator

**Edge Cases:**

- Password-protected PDF (prompt for password)
- PDF with 5000+ pages (thumbnail generation performance)
- PDF with no text layer (scanned document)
- PDF with very large pages (architectural drawings)
- Corrupt PDF that partially loads
- PDF with embedded multimedia
- Memory pressure with large PDFs (tile-based rendering)

**Acceptance Criteria:**

- [ ] PDF opens and displays first page
- [ ] Swipe navigates pages
- [ ] Pinch-to-zoom works smoothly
- [ ] Position (page number) persists across sessions
- [ ] Password-protected PDF prompts for password
- [ ] Page count shown in UI

**Tests:**

- `PDFReaderViewModelTests.swift`: page navigation, zoom level persistence, position save/restore, password prompt trigger
- Test fixtures: small PDF, password-protected PDF

**Touched Areas:** `Views/Reader/PDFReaderView.swift`, ViewModel, tests

**Rollback:** Remove PDF reader files.

---

### WI-6: Typography and Theme Settings

**Goal:** Adjustable reading experience: font size, font family, line spacing, margins, color themes.

**Non-goals:** No per-book settings (global only for MVP).

**Tasks:**

1. `ThemeService` managing current theme (light/dark/sepia) and typography settings
2. `ReaderSettingsView` bottom sheet with controls
3. Font size slider (12-32pt range)
4. Font family picker (system, serif, sans-serif, 2-3 bundled fonts)
5. Line spacing slider (1.0-2.0)
6. Margin slider (narrow/normal/wide)
7. Theme picker (light/dark/sepia/OLED black)
8. Persist settings with `@AppStorage` or Swift Data
9. Apply settings to Readium navigator via CSS injection

**Edge Cases:**

- Minimum font size with Dynamic Type already enlarged (don't fight system settings)
- OLED black theme needs pure #000000 background
- Sepia theme color values must maintain WCAG AA contrast
- Settings applied mid-chapter must not jump reading position
- CJK text may need different line spacing defaults
- Bundled fonts missing glyphs for certain scripts (fallback chain)
- Settings sync conflict between devices (last-write-wins)

**Acceptance Criteria:**

- [ ] Font size change is reflected immediately in reader
- [ ] Theme change applies to reader and UI chrome
- [ ] Settings persist across app launches
- [ ] All themes maintain WCAG AA text contrast ratio
- [ ] Settings panel does not obscure current reading content
- [ ] CJK content renders with appropriate spacing

**Tests:**

- `ThemeServiceTests.swift`: default values, persistence round-trip, contrast validation for each theme, font size bounds clamping, CJK spacing defaults
- ViewModel tests for settings panel state

**Touched Areas:** `Services/ThemeService.swift`, `Views/Reader/ReaderSettingsView.swift`, `Views/Settings/`

**Rollback:** Remove theme service and settings views.

---

### WI-7: Bookmarks and Table of Contents

**Goal:** Bookmark pages, view bookmark list, navigate via table of contents.

**Non-goals:** No highlight/annotation. No bookmark export.

**Tasks:**

1. Bookmark button in reader toolbar (toggle)
2. Bookmarks list view (sorted by position)
3. Table of contents view from EPUB/PDF metadata
4. Navigate to bookmark or TOC entry
5. Bookmark with optional user label
6. Visual indicator on bookmarked pages

**Edge Cases:**

- EPUB with no TOC (flat list of chapters)
- PDF with no outline/bookmarks (show page numbers only)
- Bookmark at exact chapter boundary
- Deleting a bookmark while viewing bookmark list
- 100+ bookmarks (scrollable list performance)
- Bookmark position invalidated by EPUB reflow at different font size

**Acceptance Criteria:**

- [ ] Tap bookmark button toggles bookmark on current page
- [ ] Bookmark list shows all bookmarks sorted by position
- [ ] Tapping bookmark navigates to saved position
- [ ] TOC displays chapter hierarchy (nested for EPUB)
- [ ] Bookmark indicator visible on bookmarked pages
- [ ] Delete bookmark from list via swipe

**Tests:**

- `BookmarksViewModelTests.swift`: add/remove bookmark, toggle, sort order, navigate action, duplicate prevention
- `BookmarkTests.swift`: model validation, cascade delete with book

**Touched Areas:** `Views/Bookmarks/`, `Models/Bookmark.swift`, ViewModel tests

**Rollback:** Remove bookmark views and logic.

---

### WI-8: Full-Text Search

**Goal:** Search within the current book's text content.

**Non-goals:** No cross-library search. No regex.

**Tasks:**

1. `SearchService` extracting text from EPUB (Readium) and PDF (PDFKit)
2. Search bar in reader with results list
3. Navigate to search result location
4. Highlight search matches in content
5. Result count display
6. Debounced search-as-you-type

**Edge Cases:**

- Empty search query (show nothing, no error)
- Search in scanned PDF with no text layer (no results, show explanation)
- CJK search (full-width/half-width normalization)
- Search with diacritics (cafe vs cafe with accent)
- Very long book (10,000+ results) — paginate results
- Search query with special regex characters (treat as literal)
- Search during page load (wait for content ready)

**Acceptance Criteria:**

- [ ] Search returns matching passages with context
- [ ] Tapping result navigates to location in book
- [ ] Match highlighted in reader content
- [ ] Empty query shows no results (no crash)
- [ ] CJK search works with normalization
- [ ] Diacritics-insensitive search option
- [ ] Results load progressively (not blocking UI)

**Tests:**

- `SearchServiceTests.swift`: basic search, empty query, CJK normalization, diacritics handling, no text layer, result count limiting, special characters
- ViewModel tests for debounce behavior

**Touched Areas:** `Services/SearchService.swift`, reader view search overlay, tests

**Rollback:** Remove SearchService and search UI.

---

### WI-9: Highlights and Annotations

**Goal:** Select text, apply color highlights, add notes. View all annotations for a book.

**Non-goals:** No highlight export. No shared annotations.

**Tasks:**

1. Text selection handler in EPUB reader (Readium decoration API)
2. Highlight color picker (yellow, green, blue, pink, purple)
3. Annotation note editor (text input)
4. Annotations list view sorted by position
5. Navigate to annotation location
6. Delete/edit annotations

**Edge Cases:**

- Highlight spanning multiple paragraphs
- Highlight spanning page boundary
- Overlapping highlights (merge or layer)
- Highlight on image caption text
- Very long annotation note
- Highlight position invalidated by font size change
- Selecting text that includes footnote markers

**Acceptance Criteria:**

- [ ] Long-press text shows highlight menu
- [ ] Highlight color applied and persisted
- [ ] Note can be added to any highlight
- [ ] Annotations list shows all highlights with preview text
- [ ] Tapping annotation navigates to location
- [ ] Highlights survive font size changes

**Tests:**

- `HighlightTests.swift`: creation, color, note, position data
- ViewModel tests: add/edit/delete highlight, sort by position, overlapping highlight handling

**Touched Areas:** `Models/Highlight.swift`, `Views/Reader/`, annotation list view, tests

**Rollback:** Remove highlight model extensions and annotation views.

---

### WI-10: iCloud Sync and Polish

**Goal:** Sync library metadata and reading positions via iCloud. Accessibility and performance polish.

**Non-goals:** No file sync (books stay on device). No cross-platform sync.

**Tasks:**

1. Enable CloudKit for Swift Data models (Book metadata, positions, bookmarks, highlights)
2. Conflict resolution strategy (last-write-wins for positions, merge for bookmarks)
3. Accessibility audit: VoiceOver, Dynamic Type, Reduce Motion
4. Performance profiling: launch time, memory, scroll performance
5. App icon and launch screen
6. Error handling review: all user-facing errors have clear messages

**Edge Cases:**

- iCloud disabled by user (graceful fallback to local-only)
- iCloud quota exceeded
- Sync conflict: same book bookmarked differently on two devices
- Network interruption during sync
- First sync with large library (progress indicator)
- User signs out of iCloud (data stays local)

**Acceptance Criteria:**

- [ ] Reading position syncs between devices within 30 seconds
- [ ] Bookmarks and highlights sync correctly
- [ ] iCloud disabled gracefully degrades to local storage
- [ ] VoiceOver can navigate entire app
- [ ] Dynamic Type scales all text
- [ ] Reduce Motion disables all animations
- [ ] Cold launch under 1 second on iPhone 14+

**Tests:**

- Sync conflict resolution unit tests
- Accessibility audit checklist (manual)
- Performance benchmarks (Instruments traces)

**Touched Areas:** All models (CloudKit annotations), App configuration, accessibility modifiers throughout

**Rollback:** Disable CloudKit sync, revert model changes.

---

### WI-11: AI Integration

**Goal:** Provide contextual AI-powered reading assistance: summarize current chapter/selection, answer questions about the text, translate passages, and look up vocabulary with definitions and usage context.

**Non-goals:**

- No fine-tuning or training on user data.
- No full-book analysis (context is limited to surrounding text window).
- No on-device model hosting for MVP (use cloud API; on-device can be added later via Apple Foundation Models).
- No AI-generated annotations that auto-persist (user must explicitly save).
- No AI features for PDF (EPUB only for MVP; PDF text extraction is unreliable).

**Tasks:**

1. Define `AIServiceProtocol` with methods: `summarize(context:)`, `ask(question:context:)`, `translate(text:targetLanguage:)`, `lookupVocabulary(word:context:)`
2. Implement `OpenAICompatibleAIService` conforming to protocol, using `URLSession` for streaming HTTP requests to any OpenAI-compatible endpoint (OpenAI, Anthropic via proxy, Ollama, etc.)
3. Implement `MockAIService` for testing (returns canned responses with configurable delay)
4. Create `TextExtractor` utility to extract a context window (approximately 2000-4000 tokens) around the current Readium locator position
5. Create `AIInteraction` Swift Data model to cache responses keyed by `(bookId, locatorHash, actionType)` with timestamp and expiration
6. Build `AIAssistantView` as a resizable bottom sheet with four action buttons (Summarize, Ask, Translate, Vocabulary) and a streaming response display area
7. Build `AIAssistantViewModel` managing action state (idle, loading, streaming, complete, error), request cancellation, and cache lookup
8. Add `AISettingsView` in Settings for API endpoint URL, API key (stored in Keychain), model name, and target translation language
9. Integrate AI button into reader toolbar (only visible when API key is configured)
10. Implement request cancellation via `Task.cancel()` when user dismisses sheet or starts new request

**Edge Cases:**

- No API key configured (AI button hidden in toolbar; settings show setup instructions)
- Invalid API key (401 response; show "Invalid API key" error, do not retry)
- Network unavailable (show offline message with option to retry; check cached responses first)
- API rate limit exceeded (429 response; show "Rate limited, try again in X seconds" with retry-after header)
- API returns content policy rejection (show neutral "Could not process this text" message)
- Very long selected text exceeding context window (truncate to window size with notification to user)
- Empty text selection for Q\&A (prompt user to select text or use current page context)
- Response streaming interrupted mid-token (display partial response with "Interrupted" indicator)
- Concurrent requests (cancel previous request before starting new one)
- CJK text in vocabulary lookup (handle multi-byte characters, provide pinyin/romaji where applicable)
- RTL text in translation (preserve text direction in response display)
- User switches to different book while AI request is in-flight (cancel request, clear state)
- Cached response for same passage (return immediately without API call; show "cached" indicator)
- API endpoint URL with/without trailing slash (normalize URL)

**Acceptance Criteria:**

- [ ] Summarize action returns a concise summary of the current chapter or selection
- [ ] Q\&A action accepts a user question and returns an answer grounded in the surrounding text
- [ ] Translate action translates selected text to the configured target language
- [ ] Vocabulary lookup returns definition, part of speech, pronunciation, and usage in context
- [ ] Responses stream token-by-token with visible typing indicator
- [ ] Cached responses are returned instantly without network call
- [ ] No API key configured: AI button not visible in toolbar
- [ ] Invalid API key shows clear error message
- [ ] Network unavailable shows offline message and checks cache
- [ ] Rate limit shows retry-after message
- [ ] Content policy rejection shows neutral error
- [ ] Long text is truncated to context window with user notification
- [ ] Cancelling a request stops streaming and shows partial response
- [ ] Switching books cancels in-flight request
- [ ] API key stored in Keychain, not in UserDefaults or plain text
- [ ] All AI features work without crashing when the service returns unexpected JSON

**Tests:**

- `AIServiceTests.swift`:
  - Successful summarize request returns parsed response
  - Successful ask request with question and context
  - Successful translate request
  - Successful vocabulary lookup with structured response
  - 401 error mapped to `AIError.invalidAPIKey`
  - 429 error mapped to `AIError.rateLimited(retryAfter:)`
  - Network error mapped to `AIError.networkUnavailable`
  - Content policy rejection mapped to `AIError.contentFiltered`
  - Malformed JSON response mapped to `AIError.invalidResponse`
  - Empty context text returns `AIError.emptyContext`
  - Request cancellation does not throw unexpected error
  - URL normalization (trailing slash handling)
- `AIInteractionTests.swift`:
  - Creation with all fields
  - Cache key uniqueness (different locator or action type produces different key)
  - Expiration check (expired responses not returned)
  - Cascade delete when parent Book is deleted
- `AIAssistantViewModelTests.swift`:
  - Idle state on initialization
  - Summarize action transitions: idle -> loading -> streaming -> complete
  - Error state on API failure
  - Cancel action transitions to idle with partial response preserved
  - Cache hit returns response without calling service
  - Switching action type cancels previous request
  - CJK vocabulary lookup passes correct parameters
  - No API key configured returns appropriate state
- `TextExtractorTests.swift` (in Utils tests):
  - Extracts context window around position
  - Handles position at start of book (no preceding context)
  - Handles position at end of book (no following context)
  - Truncates to max token count
  - Preserves paragraph boundaries (does not cut mid-sentence)

**Touched Areas:**

- `Services/AIService.swift` (new)
- `Services/Mocks/MockAIService.swift` (new)
- `Models/AIInteraction.swift` (new)
- `Views/AI/AIAssistantView.swift` (new)
- `Views/AI/AIAssistantViewModel.swift` (new)
- `Views/Settings/AISettingsView.swift` (new)
- `Utils/TextExtractor.swift` (new)
- `Views/Reader/ReaderView.swift` (modified — add AI toolbar button)
- `vreaderTests/Services/AIServiceTests.swift` (new)
- `vreaderTests/Services/Mocks/MockAIService.swift` (new)
- `vreaderTests/Models/AIInteractionTests.swift` (new)
- `vreaderTests/ViewModels/AIAssistantViewModelTests.swift` (new)

**Rollback:** Remove all files in `Views/AI/`, `Services/AIService.swift`, `Models/AIInteraction.swift`, `Utils/TextExtractor.swift`, `Views/Settings/AISettingsView.swift`, and revert `ReaderView.swift` toolbar change.

---

## 6. Testing Strategy

### Unit Tests (Swift Testing framework)

| Layer      | What to Test                                                                              | Framework     |
| ---------- | ----------------------------------------------------------------------------------------- | ------------- |
| Models     | Creation, validation, defaults, relationships, cascade delete                             | Swift Testing |
| ViewModels | State transitions, computed properties, action handlers                                   | Swift Testing |
| Services   | Import, search, theme application, sync conflict resolution, AI request/response handling | Swift Testing |
| Utils      | File hashing, date formatting, text normalization, text context extraction                | Swift Testing |

### Integration Tests

| Scenario                    | Approach                                                           |
| --------------------------- | ------------------------------------------------------------------ |
| EPUB import end-to-end      | Test fixture EPUB, verify model and file in sandbox                |
| Reading position round-trip | Import, read, save position, re-open, verify position              |
| Search across chapters      | Multi-chapter test EPUB, verify cross-chapter results              |
| AI context extraction       | Open test EPUB, navigate to position, verify extracted text window |

### UI Tests (XCUITest)

| Flow                | What to Verify                                             |
| ------------------- | ---------------------------------------------------------- |
| Library empty state | Import CTA visible, tap opens file picker                  |
| Open book           | Tap book in library, reader displays content               |
| Bookmark flow       | Open book, tap bookmark, verify in bookmark list           |
| Settings            | Change font size, verify text changes                      |
| AI assistant        | Tap AI button, select action, verify response area appears |

### Test Fixtures

Maintain a `vreaderTests/Fixtures/` directory with:

- `valid.epub` — Small reflowable EPUB with 3 chapters
- `fixed-layout.epub` — Fixed layout EPUB
- `rtl.epub` — Right-to-left EPUB
- `valid.pdf` — Small multi-page PDF
- `protected.pdf` — Password-protected PDF (password: "test")
- `corrupt.epub` — Invalid ZIP file with .epub extension
- `corrupt.pdf` — Truncated PDF file
- `no-toc.epub` — EPUB without table of contents

### Coverage Targets

Start with conservative thresholds and ratchet up:

| Metric     | Initial Target |
| ---------- | -------------- |
| Statements | 60%            |
| Branches   | 50%            |
| Functions  | 65%            |
| Lines      | 60%            |

---

## 7. Dependency Summary

| Dependency            | Purpose                        | License |
| --------------------- | ------------------------------ | ------- |
| Readium Swift Toolkit | EPUB/PDF parsing and rendering | BSD-3   |
| (built-in) PDFKit     | PDF rendering                  | Apple   |
| (built-in) Swift Data | Persistence                    | Apple   |
| (built-in) CloudKit   | iCloud sync                    | Apple   |
| (built-in) URLSession | AI API HTTP requests           | Apple   |

**AI provider note:** The AI service uses the OpenAI-compatible REST API format, which is supported by OpenAI, Anthropic (via compatibility layer), Ollama (local), and many other providers. No third-party SDK is required — standard `URLSession` with SSE streaming is sufficient. Apple Foundation Models (on-device, announced for iOS 26) can be added as an additional `AIServiceProtocol` conformance when available, enabling fully offline AI features.

**No third-party UI libraries.** SwiftUI provides everything needed. Minimizing dependencies reduces maintenance burden and binary size.

---

## 8. Open Questions

1. **Minimum iOS version**: 17 is proposed. Should we support 16 for wider reach at the cost of more complex code?
2. **iPad support**: Should iPad be a first-class target from Phase 1, or added after iPhone MVP?
3. **Book file sync**: Should actual EPUB/PDF files sync via iCloud Drive, or only metadata? File sync is expensive in storage but enables true multi-device reading.
4. **OPDS support timeline**: Is catalog browsing a P1 or P2 feature for the target audience?
5. **Offline-first**: Should the app assume always-offline (reader apps typically do), or is there online content to consider?
6. **AI provider strategy**: Should the MVP ship with OpenAI-compatible API only, or also include Apple Foundation Models support from day one? Foundation Models requires iOS 26+ (currently beta) which would limit the AI feature to newest devices. The protocol abstraction allows adding it later without architecture changes.

