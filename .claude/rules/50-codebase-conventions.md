# 50 - Codebase Conventions

Undocumented patterns found across vreader's Swift codebase. Follow these for consistency.

## 1. Concurrency: actors and @MainActor

vreader uses Swift 6 strict concurrency.

**Persistence is actor-isolated:**

```swift
actor PersistenceActor {
    func insertBook(_ record: BookRecord) async throws -> BookRecord { ... }
}
```

- All SwiftData mutations go through `PersistenceActor`. No direct `ModelContext` use from views.
- Tests use an in-memory `ModelContainer` per test, no shared state.

**UI types are `@MainActor`:**

```swift
@MainActor
@Observable
final class LibraryViewModel { ... }
```

- ViewModels, observable stores, and reader hosts all `@MainActor`.
- For test files containing only `@MainActor` types, mark the test class `@MainActor` to avoid hop ceremony.

**Crossing actors:**

- `await` actor methods. No `assumeIsolated` except in narrow constructor contexts (e.g., `VReaderApp.init()` → `MainActor.assumeIsolated` is OK because App.init runs on main, but prefer `@MainActor` on the App struct itself).
- Pass values, not actor-isolated references, across actor boundaries.

## 2. Persistence: SwiftData via PersistenceActor

**Pattern:**

- Entities live in `vreader/Models/` (e.g., `Book`, `Highlight`, `Bookmark`).
- A schema-versioned migration plan in `VReaderMigrationPlan.swift`.
- `PersistenceActor+Foo.swift` extension files split CRUD by feature (Library, Highlights, Bookmarks, Collections).

**Key types:**

- `DocumentFingerprint` — `{format}:{SHA256}:{byteCount}` deterministic identity for a book file. Used as `fingerprintKey` everywhere.
- `Locator` — universal position: `href + progression` (EPUB), `page` (PDF), `charOffsetUTF16` (TXT/MD).
- `BookRecord`, `HighlightRecord`, `BookmarkRecord` — value-type DTOs returned across the actor boundary, decoupled from `@Model` classes.

**Rule:** never return `@Model` instances from `PersistenceActor` — they're context-bound. Return record value types instead.

## 3. Reader Architecture

`vreader/Views/Reader/ReaderContainerView.swift` is the dispatcher. Format hosts it routes to:

| Host                             | Format            | Renderer                                                         |
| -------------------------------- | ----------------- | ---------------------------------------------------------------- |
| `TXTReaderHost`                  | `.txt`            | `UITextView` (TextKit 1) or chunked `UITableView` (>500K UTF-16) |
| `MDReaderHost`                   | `.md`             | `UITextView` with Markdown attributed string                     |
| `EPUBReaderHost`                 | `.epub`           | `EPUBWebViewBridge` (custom WKWebView + JS)                      |
| `FoliateBilingualContainerView`  | `.azw3` (incl. `.azw`/`.mobi`/`.prc`) | wraps `FoliateSpikeView` (WKWebView + Foliate-js bundle) + the bilingual VM / orchestrator / setup-sheet (feature #56 WI-11) |
| `PDFReaderHost`                  | `.pdf`            | `PDFView` (PDFKit)                                               |

Note: AZW3/MOBI used to route directly to `FoliateSpikeView`. Feature #56 WI-11 added `FoliateBilingualContainerView` as a wrapper between the dispatcher and the spike so the bilingual VM / orchestrator / setup-sheet wiring applies without modifying the spike itself; non-bilingual paths see no runtime overhead beyond an idle notification observer. Bug #246 / GH #1072 separately hardened the dispatch to read `fingerprint.format` (the canonical `BookFormat` parsed from `book.fingerprintKey`) rather than `book.format` (the parallel String `@Model` column).

**Bridge convention:** UIKit views (`UITextView`, `WKWebView`, `PDFView`) wrap in `UIViewRepresentable`. A `Coordinator` class handles delegate callbacks, gestures, and JS messages.

**Rule:** Reader bridges receive their data via `@State` ownership in the host, not via global stores. Configuration flows through `ReaderSettingsStore` (an `@Observable` `@MainActor` class).

## 4. Notification Bus

Cross-component reader communication uses `NotificationCenter` because SwiftUI's `Environment` doesn't bridge UIKit.

**Conventions:**

- All names live in `ReaderNotifications.swift` (release) or `DebugBridgeNotifications.swift` (DEBUG only).
- Names are namespaced: `vreader.<scope>.<event>`.
- Payloads use `userInfo` typed via documented keys (e.g., `["fingerprintKey": String]`).
- For DEBUG-only flows, both the `Notification.Name` extension AND the observer block are wrapped in `#if DEBUG`.

**Rule:** every observer must `removeObserver` in `defer` (in tests) or in `onDisappear` / deinit (in views).

## 5. Bridge Cleanup

Reader bridges that attach UIKit observers / gesture recognizers / WKScriptMessageHandlers must release them on teardown:

```swift
final class Coordinator: NSObject, WKScriptMessageHandler {
    private var notificationToken: NSObjectProtocol?
    private weak var webView: WKWebView?

    func attach(to webView: WKWebView) {
        self.webView = webView
        webView.configuration.userContentController.add(self, name: "vreader")
        notificationToken = NotificationCenter.default.addObserver(
            forName: .readerNavigateToLocator, object: nil, queue: .main
        ) { [weak self] _ in self?.handleNavigate() }
    }

    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "vreader")
        if let token = notificationToken {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
```

**Rule:** any handler attached via `addObserver`, `add(_:name:)`, `addTarget(_:action:)` must have a matching removal in `deinit` or an explicit `cleanup()` called from the SwiftUI host's `.onDisappear`.

## 6. Error Handling

**Swift errors propagate via `throws`:**

```swift
enum ImportError: Error {
    case fileNotReadable(String)
    case unsupportedFormat(String)
    var userMessage: String { ... }
}
```

- Custom `enum` for each subsystem's errors.
- `userMessage: String` computed property for UI display — sanitizes paths and internal details.

**Rule:** never use `try?` to silently swallow errors. Either handle them or propagate. The only acceptable swallow is a logged warning at a leaf where re-raising would corrupt invariants.

## 7. Logging

Use `OSLog` (via `Logger`):

```swift
private let log = Logger(subsystem: "com.vreader.app", category: "Foo")
log.info("loaded \(count) books")
log.error("failed: \(String(describing: error), privacy: .public)")
```

- Subsystem is always `"com.vreader.app"`.
- Category names a module/feature: `"Library"`, `"Persistence"`, `"DebugBridge"`.
- Use `privacy: .public` only when the value is genuinely safe to log.

**Rule:** no bare `print()` in production code — only via `Logger`. The historical migration to OSLog was tracked in commits `746f7a5` / `917d8c2`.

## 8. Test Conventions

- Tests in `vreaderTests/<MirroringSourcePath>/<Name>Tests.swift`.
- Helpers in `vreaderTests/Helpers/` (e.g., `CollectionTestHelper`).
- One test class per source file under test.
- `setUp()` / `tearDown()` are `async throws` if any dependency is async.
- See `10-tdd.md` for full TDD discipline + pattern catalog.

## 9. File Organization

- Plugin-style features (`Foliate/`, `BookSource/`, `DebugBridge/`) live under `vreader/Services/<Name>/`.
- View files live under `vreader/Views/<Area>/`.
- A feature ≥3 source files gets its own directory.
- Aim for files under ~300 lines; split when growing past that.

## 10. Imports

- `import Foundation`, `import SwiftUI`, `import SwiftData`, `import OSLog`, `import UIKit` (where needed).
- Avoid Foundation umbrella imports (`@_exported`).
- No third-party Swift packages currently — the only external code is Foliate-js (vendored as a JS bundle, not SPM).

## 11. DEBUG Gating

DEBUG-only code MUST be wrapped in `#if DEBUG` blocks at file scope OR in dedicated `#if DEBUG`-gated extension files. The `verify-release-no-debugbridge.sh` gate enforces zero DEBUG-only symbols in Release.

**Pattern:**

```swift
#if DEBUG

import Foundation

@MainActor
final class DebugFoo { ... }

#endif
```

Don't `#if DEBUG` individual lines inside otherwise-production code unless a single line genuinely needs it.

## 12. Android / Kotlin + Compose conventions (feature #107)

Sections 1–11 above are the **iOS/Swift** conventions. The Android app (`android/`,
landing in #106) is a second native app — these are its analogs, so a Kotlin PR
reads like the Swift one. Source of truth for the port strategy:
`docs/decisions/0001-android-port-strategy.md`.

1. **Concurrency** — Kotlin coroutines + structured concurrency are the
   actor/`@MainActor` analog. Repos/use-cases run on an injected
   `CoroutineDispatcher` (never hardcode `Dispatchers.IO`); UI state is updated on
   `Dispatchers.Main`. Expose `StateFlow`/`SharedFlow`, collect with
   `repeatOnLifecycle`. No `GlobalScope`; scope to `viewModelScope` /
   lifecycle.
2. **Persistence** — **Room** is the SwiftData analog. DAOs are the CRUD seam
   (the `PersistenceActor+Foo` analog); return value-type DTOs / domain models
   from the repository, not `@Entity` rows, across boundaries. Schema-versioned
   `Migration`s mirror `VReaderMigrationPlan`; an additive column is a lightweight
   `Migration`, a data transform is a custom one (cf. feature #108/#109 lessons).
3. **Reader** — EPUB via **Readium-Kotlin** (decided viable by Spike B #105),
   Kindle/native via the legacy-compat path; one Compose host per format, the
   `ReaderContainerView` dispatcher analog.
4. **UI** — **Jetpack Compose**, unidirectional data flow: a ViewModel owns
   `StateFlow<UiState>`, the composable is a pure function of state + emits events.
   Hoist state; `@Composable` previews for designed surfaces only (rule 51 still
   binds — UI from claude.ai/design, no self-invented Compose screens).
5. **DI** — constructor injection at boundaries (interfaces, so tests mock the
   boundary — the `LibraryPersisting` analog). Hilt/Koin module wiring at the app
   edge, not in domain code.
6. **Errors** — sealed `Result`/domain error types with a `userMessage`, the Swift
   `enum … : Error { var userMessage }` analog; never swallow silently.
7. **Logging** — the platform `Logger`/Timber, namespaced like the OSLog
   categories; no bare `println` in production.
8. **Files** — package-by-feature under `android/app/src/main/java/...`, mirror the
   `vreader/Services/<Name>/` layout; keep files focused (~300 lines).

Cross-platform identity/locator/backup/schema stay **contract-bound**
(`contracts/`); only those surfaces require strict iOS↔Android parity (ADR-0001).
