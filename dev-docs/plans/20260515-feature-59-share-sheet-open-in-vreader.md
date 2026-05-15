# Feature #59 Plan — Share Sheet / "Open in vreader" registration

## Problem

When a user taps a book file in another app (Files, Mail, Safari downloads, AirDrop receive, third-party file managers) iOS shows an "Open in…" / Share Sheet listing apps that have declared support for that document type. **vreader is not in that list** because `Info.plist` declares no `CFBundleDocumentTypes` and no `UTImportedTypeDeclarations`. The app also has no production `.onOpenURL` / scene handler for `file://` URLs — the existing handler in `VReaderApp.swift:309` is `#if DEBUG`-wrapped and only matches `DebugCommand.scheme`.

All five formats (EPUB / PDF / TXT / MD / AZW3-MOBI-PRC-AZW) are otherwise fully supported by the existing `BookImporter.importFile(at:source:)` pipeline (verified — `vreader/Services/BookImporter.swift:68`), and `ImportSource.shareSheet` already exists in the enum (`vreader/Models/ImportSource.swift:6`). So this feature is purely the missing **system-level registration + import dispatch** — no new format-handling capability.

## Surface area

### Files modified (in this feature)

**`project.yml`** — add to `targets.vreader.info.properties`:

1. `CFBundleDocumentTypes` array — one entry per format family, each with:
   - `CFBundleTypeName` (human-readable, e.g. "EPUB Book")
   - `LSHandlerRank: Alternate` (we appear in "Open in…" without claiming default)
   - `LSItemContentTypes` — UTIs declared for this family
2. `UTImportedTypeDeclarations` array — declares the custom UTIs Apple does NOT provide (`com.amazon.azw3`, `com.amazon.mobi-pocket`):
   - `UTTypeIdentifier`
   - `UTTypeConformsTo: [public.data]`
   - `UTTypeDescription`
   - `UTTypeTagSpecification` with `public.filename-extension: [...]` and `public.mime-type: [...]`
3. `LSSupportsOpeningDocumentsInPlace: true` — required so Files / document-picker can hand the URL to vreader without copying first.

Sketched plist values (final form in WI-1 PR):

```yaml
CFBundleDocumentTypes:
  - CFBundleTypeName: "EPUB Book"
    LSHandlerRank: Alternate
    LSItemContentTypes:
      - org.idpf.epub-container
  - CFBundleTypeName: "PDF Document"
    LSHandlerRank: Alternate
    LSItemContentTypes:
      - com.adobe.pdf
  - CFBundleTypeName: "Plain Text"
    LSHandlerRank: Alternate
    LSItemContentTypes:
      - public.plain-text
  - CFBundleTypeName: "Markdown Document"
    LSHandlerRank: Alternate
    LSItemContentTypes:
      - net.daringfireball.markdown
  - CFBundleTypeName: "Kindle Book"
    LSHandlerRank: Alternate
    LSItemContentTypes:
      - com.amazon.azw3
      - com.amazon.mobi-pocket
LSSupportsOpeningDocumentsInPlace: true
UTImportedTypeDeclarations:
  - UTTypeIdentifier: com.amazon.azw3
    UTTypeConformsTo: [public.data]
    UTTypeDescription: "Amazon Kindle AZW3"
    UTTypeTagSpecification:
      public.filename-extension: [azw3, azw]
      public.mime-type: [application/vnd.amazon.ebook]
  - UTTypeIdentifier: com.amazon.mobi-pocket
    UTTypeConformsTo: [public.data]
    UTTypeDescription: "Mobipocket eBook"
    UTTypeTagSpecification:
      public.filename-extension: [mobi, prc]
      public.mime-type: [application/x-mobipocket-ebook]
```

**`vreader/App/VReaderApp.swift`** — adjust both `#if DEBUG` and `#else` Scene branches (currently lines 301-328) to add a production `.onOpenURL { url in dispatchIncomingFile(url) }` modifier that runs **in both Debug and Release**, BUT in DEBUG it falls through to the existing `DebugCommand.scheme` branch first (debug-bridge URLs take priority; file URLs fall through). Specifically:
   - Extract a helper `func handleIncomingURL(_ url: URL) -> Bool` on a new `FileURLImportRouter`-like type (location TBD in WI-2 — see "Rejected alternatives").
   - In DEBUG: existing debug-scheme guard stays; if it doesn't match, call the file-URL handler.
   - In Release: only the file-URL handler runs.

**New file `vreader/Services/Import/FileURLImportRouter.swift`** (~80-120 LOC, fits under the 300-line guideline). **Per Codex round-1 Medium #2**, the router depends on the `BookImporting` protocol (which exists at `vreader/Services/BookImporting.swift:9`), NOT the concrete `BookImporter` — this is the testability seam. Unknown-extension reporting is a closure injected at init so unit tests can assert it without spinning up SwiftUI alert UI:

```swift
@MainActor
final class FileURLImportRouter {
    private let bookImporter: any BookImporting
    private let reportUnknownExtension: (String) -> Void
    private let logger = Logger(subsystem: "com.vreader.app", category: "FileURLImportRouter")

    init(bookImporter: any BookImporting,
         reportUnknownExtension: @escaping (String) -> Void) {
        self.bookImporter = bookImporter
        self.reportUnknownExtension = reportUnknownExtension
    }

    /// Returns true if the URL was a recognized book file and import was attempted.
    /// Returns false if URL scheme/format isn't handled here (caller may fall through).
    @discardableResult
    func dispatch(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        guard BookFormat.isSupportedExtension(url.pathExtension) else {
            reportUnknownExtension(url.pathExtension)
            return true  // we consumed it (and reported); don't fall through
        }
        Task { @MainActor in
            await performImport(at: url)
        }
        return true
    }

    private func performImport(at url: URL) async { /* delegates to bookImporter.importFile */ }
}
```

The App-layer composition wires the production alert presenter into the `reportUnknownExtension` closure. The import path delegates to `bookImporter.importFile(at: url, source: .shareSheet)`. Security-scope is handled INSIDE the importer (already does `startAccessingSecurityScopedResource` at line 85), so the router does not need to re-scope.

Mocks needed for unit tests:
- A `MockBookImporting` (already a project pattern — search `vreaderTests/` for existing mocks).
- A captured-call array for the unknown-extension closure.
- Optionally a fake clock / scheduler if the unit test wants to assert the async `Task` was scheduled deterministically (otherwise the `Task` runs on its own).

**`vreader/Models/BookFormat.swift`** — add `static func isSupportedExtension(_ ext: String) -> Bool`. Codex round-1 Low #4 confirmed this helper does not exist today; treating it as expected WI-2 work (not a "maybe").

### Files OUT of scope

- `vreader/Services/BookImporter.swift` — already handles security-scoped resources and all five formats; no internal change.
- `vreader/Models/ImportSource.swift` — `.shareSheet` already exists.
- `vreader.entitlements` — `LSSupportsOpeningDocumentsInPlace` is a plist key, not an entitlement.
- iOS 17+ App Intents / Quick Actions — explicitly OUT per row note (f).
- The library-row navigation after a successful import — UX decision deferred to WI-2's PR description (current default: land back on Library with the new row highlighted, mirroring Files-app import).
- A custom "import in progress" sheet — defer to a future iteration; the existing toast/HUD path is enough for slice acceptance.

## Prior art / project precedent / rejected alternatives

- **Project precedent**: `BookImporter.importFile(at:source: .shareSheet)` is already the documented import entrypoint — used by Library-view's drag-drop and document-picker flows. The router doesn't need to invent a new import path; it dispatches to the existing one.
- **Apple-recognized UTIs**: `org.idpf.epub-container`, `com.adobe.pdf`, `public.plain-text` are public system UTIs. `net.daringfireball.markdown` is the Apple-recognized public conformance for `.md` (since macOS 12 / iOS 15 — used by Notes / Quick Look).
- **Custom Kindle UTIs**: Apple does not provide a public UTI for `.azw3`/`.mobi`/`.prc`. `com.amazon.azw3` and `com.amazon.mobi-pocket` are the de facto identifiers used by Apple Books and Kindle for iOS to disambiguate file ownership.
- **Rejected — single combined `com.amazon.kindle` UTI**: collapsing all Kindle extensions into one `com.amazon.kindle` UTI is simpler but lower fidelity (`.azw3` and `.mobi` are genuinely different formats). Two declared imported types is the canonical pattern, matches Kindle's own UTI tree on iOS.
- **Rejected — `LSHandlerRank: Owner` for Kindle types**: claiming `Owner` would make vreader the default opener of `.azw3`/`.mobi` files system-wide on any device with vreader installed, regardless of whether the user has Kindle installed. We're a polite alternative, not a primary handler — `Alternate` is the right choice.
- **Rejected — sceneDelegate / `UIApplicationDelegate.application(_:open:options:)`**: SwiftUI's `.onOpenURL` is the idiomatic surface for our App lifecycle and is already wired for the debug-bridge case. Adding a UIKit AppDelegate just for this would invert the architecture without benefit.
- **Rejected — file-copy-on-import (not opening in place)**: declaring `LSSupportsOpeningDocumentsInPlace: false` would force iOS to copy files into vreader's container before delivering the URL. That doubles the disk usage for large AZW3 files. The existing security-scope path in `BookImporter` handles in-place URLs correctly (already verified in prior import flows).

## Work-item sequencing

**WI-1 (behavioral — metadata-only implementation with intentionally incomplete user-visible behavior, ~80 LOC plist diff + smoke verification)** — Info.plist additions. PR ships:
1. `project.yml` edits adding `CFBundleDocumentTypes`, `UTImportedTypeDeclarations`, `LSSupportsOpeningDocumentsInPlace`.
2. `xcodegen generate` regenerates `vreader.xcodeproj/project.pbxproj`.
3. Smoke build + visual Share-Sheet confirmation on iPhone 17 Pro Simulator (manual): pull an EPUB into the simulator via drag-drop into Files.app, share it → confirm "vreader" appears in destinations. WITHOUT WI-2, tapping vreader does nothing — that's expected.
4. No production code changes. No `.onOpenURL` handler yet.

WI-1 is **behavioral** per rule 47 (Codex round-1 Medium #1): the Share Sheet entry appearing IS a user-visible behavior change, even though tapping it is intentionally a no-op until WI-2 wires the dispatch. Gate 5a slice verification confirms the Share Sheet entry shows up; the "tap does nothing" state is documented in the PR description as intentional partial-delivery.

**WI-2 (behavioral, ~150-200 LOC)** — `FileURLImportRouter` + production `.onOpenURL` wiring. PR ships:
1. New `vreader/Services/Import/FileURLImportRouter.swift` (the type sketched above).
2. `VReaderApp.swift` modifications: add the production `.onOpenURL` handler in BOTH Debug and Release Scene branches. In Debug, debug-bridge scheme handled first, file URLs fall through to the router.
3. `BookFormat.swift` — add `isSupportedExtension(_:)` helper if missing.
4. Unit tests:
   - `FileURLImportRouterTests` — covers dispatch routing (file vs. non-file URL, supported vs. unsupported extension, debug-scheme not consumed by router).
   - `BookFormatTests` — `isSupportedExtension` cases.
5. Slice verification on iPhone 17 Pro Simulator: drag-drop EPUB / PDF / TXT / MD / AZW3 into Files.app one by one; share each to vreader; confirm import lands and library row appears (or toast confirms). Verify duplicate (same file twice) does NOT create a duplicate row (BookImporter fingerprint-dedupe path already handles this).

WI-2 is **behavioral** per rule 47: changes app behavior on incoming file URLs.

WI-2 is also the **final WI** of Feature #59. Its PR carries `Refs #667`. Once merged, the row flips to `DONE`; Gate 5b's evidence file flips to `VERIFIED`.

**Decision: 2 WIs.** WI-3 (UX polish — custom toast on successful import, in-progress sheet for large files, unknown-extension alert) was considered but rolled into WI-2 because (a) the alert is one method call, (b) the existing library-add toast already covers the success case, and (c) the in-progress sheet is a future iteration's nice-to-have, not part of Feature #59's acceptance criteria.

## Test catalogue

| File | What it covers | Framework |
|---|---|---|
| `vreaderTests/Services/Import/FileURLImportRouterTests.swift` (new) | dispatch routing: file vs. non-file URL → returns false vs. true; supported extension → calls bookImporter.importFile; unsupported extension → presents alert + returns true; debug scheme passthrough (when router invoked from a debug context shouldn't NOT eat the URL — though typically the App-layer routes debug URLs first) | Swift Testing (`@Suite`, `@Test`) |
| `vreaderTests/Models/BookFormatExtensionTests.swift` (new or extend existing) | `isSupportedExtension`: case-insensitive match for `.epub`, `.pdf`, `.txt`, `.md`, `.markdown`, `.azw3`, `.azw`, `.mobi`, `.prc`; rejects empty / nil / `.zip` / `.docx` | Swift Testing |
| `vreaderTests/App/VReaderAppOnOpenURLTests.swift` (optional, see Risks) | wiring test if doable without spinning up the App scene; otherwise covered manually in slice verification | Swift Testing |

Existing tests touched: none. `BookImporter` tests already cover the import-path correctness; the router only delegates.

## Risks + mitigations

1. **UTI conformance conflicts**: a competing reader app declaring a slightly different conforming UTI tree might hide vreader or shadow another app. Mitigation: WI-2 slice verification on a sim with Apple Books installed; WI-2 PR description records the observed Share Sheet order.
2. **`LSSupportsOpeningDocumentsInPlace` interactions with existing book-files-directory model**: the existing `BookImporter` already handles security-scoped URLs; opening-in-place doesn't change the import logic. Mitigation: WI-2 covers a `.epub` from Files-app icloud (where the file may be a lazy cloud file) — the test/slice verification step confirms the security-scope path doesn't drop frames on first open.
3. **Markdown UTI conflicts with editors**: `net.daringfireball.markdown` is widely declared by Bear / iA Writer / Drafts. Mitigation: slice verification on a sim/device with one Markdown editor installed confirms vreader appears in the sheet without claiming default (`LSHandlerRank: Alternate` enforces this).
4. **App-scene `.onOpenURL` wiring testability**: SwiftUI Scene-level modifiers aren't easily exercisable in unit tests. Mitigation: the router is a separate testable type; the Scene wiring is exercised via slice verification (visual Share-Sheet → confirm import lands). If a future iteration wants a unit test for the wiring, it can use the `vreader-debug://` harness with a `file://` URL injected via `xcrun simctl openurl`.
5. **Custom UTI shadowing on real device**: a real-device test with Kindle for iOS installed may show vreader and Kindle competing for `.azw3`. Per `LSHandlerRank: Alternate`, both appear in "Open in…" with the system default (likely the most-recently-used). Mitigation: slice verification records the observed behavior on simulator; a follow-up device test post-merge confirms.
6. **`SwiftUI .onOpenURL` not invoked under all share-sheet entry flows**: AirDrop, Mail attachments, and Files all use slightly different OS plumbing. Mitigation: slice verification tests at least Files + Safari-download paths; AirDrop + Mail are documented as device-only follow-ups in the WI-2 PR.

## Backward compat

- **Existing imports**: no change. The router is a NEW entry point, parallel to Library-view's existing import paths. All imports converge on `BookImporter.importFile(at:source:)` regardless of entry point.
- **Existing AZW3/MOBI files in Library**: no change. Already imported books have stable fingerprints; the new UTI declarations don't affect their identity.
- **Older clients on iOS 17**: `LSSupportsOpeningDocumentsInPlace` + `CFBundleDocumentTypes` have been in iOS since iOS 11. No iOS-version gate needed beyond the existing iOS 17.0+ deployment target.
- **DebugBridge URL scheme**: unchanged. In **Debug** builds, `vreader-debug://` URLs flow through the same `.onOpenURL` modifier and are intercepted by the existing scheme guard before falling through to the file-URL router. In **Release** builds, `vreader-debug://` is not registered at all (the `CFBundleURLTypes` injection runs only in Debug via the post-compile script in `project.yml`) so the scheme cannot launch the app — if some non-file URL ever did reach `.onOpenURL` in Release, `FileURLImportRouter.dispatch` returns `false` (non-file URL guard) and nothing happens. Codex round-1 Low #3 corrected the prior wording.

## Acceptance criteria

(Lifted verbatim from the row, refined where needed)

| # | Criterion | How verified |
|---|---|---|
| a | On iOS Share Sheet for an `.epub` file in Files / Mail / Safari, "vreader" appears in the destinations list | Slice verification — visual screenshot, recorded in PR Gate 5a |
| b | Tapping the destination launches vreader, imports the file, and lands on either the library or the freshly-opened reader (current decision: Library with the new row scrolled into view) | Slice verification — visual + check that the row exists post-import |
| c | Same flow for `.azw3`, `.mobi`, `.prc`, `.azw`, `.md`, `.markdown`, `.txt`, `.pdf` | Slice verification — one each from a fixture set (sim drag-drop) |
| d | Duplicate handling: same file shared twice does not create a duplicate library row | Slice verification — share → confirm row → share again → confirm same row, not a second |
| e | Files-app context menu shows "Open in vreader" without a copy step (i.e., `LSSupportsOpeningDocumentsInPlace: true` honored) | Slice verification — confirmed by observing iOS's "Open" vs "Copy to vreader" wording |
| f | `LSHandlerRank: Alternate` confirmed by NOT becoming the default handler on a clean simulator | Slice verification — Share Sheet shows vreader as an alternative, not the auto-picked default |

## Manual Audit Evidence

This section will be populated during Gate 2 (independent plan audit) — see Audit fixes applied table below.

## Audit fixes applied (Gate 2 round-1 — Codex thread `019e2a9e`)

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 1 | Medium | WI-1 misclassified as foundational. Registering `CFBundleDocumentTypes` is user-visible: vreader starts appearing in Share Sheet / "Open in…", which is behavioral even if tap-to-import isn't wired yet. | **Fixed.** Reclassified WI-1 as behavioral with the qualifier "metadata-only implementation with intentionally incomplete user-visible behavior." Gate 5a slice verification will confirm the Share Sheet entry appears. |
| 2 | Medium | `FileURLImportRouter` sketch hard-wired concrete `BookImporter` + a method-style `presentUnknownExtensionAlert`, making unsupported-extension and async-dispatch branches awkward to unit-test. | **Fixed.** Router now depends on `any BookImporting` (protocol exists at `vreader/Services/BookImporting.swift:9`); unknown-extension reporting injected as a closure. Listed the exact mock surfaces unit tests need (MockBookImporting, captured-call array, optional scheduler). |
| 3 | Low | Release `vreader-debug://` edge-case wording was imprecise. The scheme is not registered in Release at all (per the post-compile script in `project.yml`), so it cannot launch the app. | **Fixed.** Backward-compat section updated with the correct Debug-only registration story + the no-op fall-through behavior if a non-file URL did somehow reach `.onOpenURL` in Release. |
| 4 | Low | `BookFormat.isSupportedExtension(_:)` was hedged as "add if missing." Confirmed missing today. | **Fixed.** Surface-area §3 now lists this as expected WI-2 work, not a maybe. |

Gate 2 round-1 verdict (Codex `019e2a9e`, 2026-05-15): 4 findings (2 Medium, 2 Low), all resolved in this revision. Plan is ready for Gate 3.
