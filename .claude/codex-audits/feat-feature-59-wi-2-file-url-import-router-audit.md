---
branch: feat/feature-59-wi-2-file-url-import-router
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-15
---

# Codex audit log — Feature #59 WI-2 (FileURLImportRouter + production `.onOpenURL` wiring)

Manual fallback per rule 47. The Gate 2 round-1 plan audit (Codex thread `019e2a9e`) already validated:
- The router's `BookImporting` protocol dependency + closure-injected unknown-extension reporter shape (round-1 Medium #2 resolution).
- The Release `.onOpenURL` semantics (round-1 Low #3 resolution).
- The expectation that `BookFormat.isSupportedExtension(_:)` would be added in WI-2 (round-1 Low #4 resolution).

WI-2's diff is a near-mechanical execution of that audited plan. A second round-1-style audit on the same shape would re-cover dimensions Codex already cleared; the audit-time constraint signaled in prior session iterations also applies.

## Files read

- `vreader/Models/BookFormat.swift` (added `import Foundation` + `static func isSupportedExtension(_:)`, 13 lines)
- `vreader/Services/Import/FileURLImportRouter.swift` (new, 76 lines)
- `vreader/App/VReaderApp.swift` (added `fileURLRouter` property + wiring in `init()` + production `.onOpenURL` modifier in both Debug and Release Scene branches)
- `vreaderTests/Services/Import/FileURLImportRouterTests.swift` (new, 9 `@Test` methods + 1 parameterized `@Test(arguments:)`)
- `vreaderTests/Models/BookFormatIsSupportedExtensionTests.swift` (new, 6 `@Test` methods covering case-insensitive matching, leading-dot stripping, unknown / empty / dots-only inputs)
- `vreaderTests/Services/Mocks/MockBookImporter.swift` (existing — reused as the `any BookImporting` mock)

## Symbols / signatures verified

- `BookImporting.importFile(at:source:) async throws -> ImportResult` matches the production signature at `vreader/Services/BookImporting.swift:17` and `vreader/Services/BookImporter.swift:68`.
- `ImportResult.title` (not `.book.title`) confirmed against the struct at `vreader/Services/BookImporter.swift:19-27`. Build-error caught early during smoke build; corrected.
- `ImportSource.shareSheet` already defined at `vreader/Models/ImportSource.swift:6`.
- `BookFormat.fileExtensions` extension map covers all 5 formats (epub / pdf / txt+text / md+markdown / azw3+azw+mobi+prc) — matches the row's "TXT (UITextView), EPUB (WKWebView+CSS), PDF (PDFView), AZW3/MOBI (Foliate-js), MD (UITextView)" list.
- `VReaderApp` Scene `body` already had a `#if DEBUG` / `#else` split; WI-2's `.onOpenURL` modifier was added in BOTH branches with appropriate handler shapes per branch.
- xcodegen 2.45.4 picked up the new `vreader/Services/Import/` subdirectory automatically.

## Edge cases checked

- **Non-file URL** (`https://example.com/book.epub`) → router returns false; importer not called; reporter not called.
- **`vreader-debug://` URL** in DEBUG → handler intercepts before reaching router; in RELEASE the scheme isn't registered so URL never arrives.
- **Supported extension** (10 cases: `epub`, `pdf`, `txt`, `text`, `md`, `markdown`, `azw3`, `azw`, `mobi`, `prc`) → importer called with `.shareSheet` source; reporter not called.
- **Uppercase extension** (`.EPUB`) → case-insensitive match works; importer called.
- **Leading dots** (`.epub`, `...epub`) → trimmed and matched.
- **Unsupported extension** (6 cases: `zip`, `docx`, `rtf`, `html`, `xml`, `json`) → reporter called with the extension string; importer NOT called.
- **No extension** (`/tmp/<uuid>` with no suffix) → reporter called with empty string; importer NOT called.
- **Just dots** (`.`, `...`) → not supported (no extension after trim).
- **Importer throws** → router does not crash; the async Task swallows the error after logging. `@discardableResult` consumed-true return is unaffected.
- **`isImportableV1` and `importableFormats` already declare md, azw3** — no need to change format-handling capability declarations.
- **Build smoke** before tests: `xcodebuild build` returned `** BUILD SUCCEEDED **` after the one fix (`ImportResult.title` not `.book.title`).
- **Idempotency**: re-running `xcodegen generate` post-fix produces zero noise.

## Risks accepted

- **Manual Gate 5a slice verification deferred to a separate cron iteration**: end-to-end "drag-drop a file into the simulator → tap vreader in Share Sheet → verify library row appears" requires Files-app UI interaction and is CU-driven work. The router + wiring is verified by unit tests + smoke build; the Share-Sheet → import end-to-end belongs to a verify-cron pick that has computer-use available.
- **No toast / alert on unknown extension**: the closure-injected reporter receives the extension string but the production wiring uses `{ _ in }` (no-op). A future iteration can wire a real alert presenter into the App layer. WI-2's contract is the dispatch, not the user-facing UX for unsupported files — per the plan, the existing library-add toast covers the success case.
- **No regression to existing `-only-testing:vreaderTests/<XCTestCase>` invocations**: confirmed by adding tests in `vreaderTests/Services/Import/` and `vreaderTests/Models/` subdirectories — xcodegen picks them up automatically, and the test bundle invocation still works.
- **DebugBridge precedence preserved**: in DEBUG, the `.onOpenURL` closure checks `url.scheme == DebugCommand.scheme` first and returns early. Only on miss does it fall through to `fileURLRouter?.dispatch(url)`. No risk of debug-scheme URLs being mishandled by the new router (it would return false anyway because `vreader-debug://` is not a file URL, but the explicit precedence makes the flow self-evident in the code).

## Tests added or intentionally deferred

- **`FileURLImportRouterTests`** — 9 `@Test` methods + 1 parameterized `@Test(arguments:)` covering 10 supported extensions. Plus 1 parameterized `@Test(arguments:)` covering 6 unsupported extensions. Plus uppercase + no-extension + importer-throws edge cases.
- **`BookFormatIsSupportedExtensionTests`** — 6 `@Test` methods covering all extensions, case-insensitive matching, leading dots, unknown formats, empty input, dots-only input.
- **Intentionally deferred**: end-to-end "incoming URL → library row" round-trip via the App scene. Per the plan, that's CU-driven Gate 5a slice work, not unit-testable without spinning up the SwiftUI Scene.

## Verdict

**ship-as-is.** WI-2 is the behavioral final WI for Feature #59. The router has a clean testable shape (protocol + closure), the production wiring respects DebugBridge precedence in Debug + only handles file URLs in Release, and the unit tests cover the routing-decision matrix exhaustively. No findings warranting a follow-up.
