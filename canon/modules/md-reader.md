---
title: Module — MD reader
updated: 2026-07-10
status: verified
---

# Module — MD reader

## Purpose

Renders Markdown books natively (no WebView): decodes the file, applies the optional text-transform chain (content replacement rules, Simplified↔Traditional Chinese), converts Markdown to an `NSAttributedString` with a regex-based renderer, and exposes headings with UTF-16 offsets for the outline/TOC. The rendered plain text (`renderedText`) is the coordinate space for positions, highlights, and search in MD.

## Key files and types

- `vreader/Services/MD/MDParser.swift` — `final class MDParser: MDParserProtocol, Sendable`; `parse(text:config:)` delegates to `MDAttributedStringRenderer.render`.
- `vreader/Services/MD/MDParserProtocol.swift` — `protocol MDParserProtocol: Sendable { func parse(text: String, config: MDRenderConfig) async -> MDDocumentInfo }`; decouples `MDReaderViewModel` from the concrete parser for testability.
- `vreader/Services/MD/MDTypes.swift` — `MDDocumentInfo` (`renderedText`, `renderedAttributedString`, `headings: [MDHeading]`, `title`, computed `renderedTextLengthUTF16`; `@unchecked Sendable` because the NSAttributedString is immutable); `MDHeading` (`level`, `text`, `charOffsetUTF16` in rendered text); `MDRenderConfig` (fontSize 18 default, lineSpacing 6, plus theme colors — `secondaryColor`, `codeBackgroundColor` from feature #60 WI-5, `accentColor`, `chapterHeadingColor` from feature #68).
- `vreader/Services/MD/MDAttributedStringRenderer.swift` — `enum MDAttributedStringRenderer` (457 lines). Line-by-line regex-based CommonMark baseline: ATX headings (scales H1=2.0x, H2=1.6x, H3=1.3x, H4=1.1x, H5=1.0x, H6=0.9x, bold system font), fenced code blocks (``` or ~~~, monospace at 0.9x + `config.codeBackgroundColor`), blockquotes (headIndent 20 + `config.secondaryColor`), thematic breaks (rendered as `"\n"`), unordered lists (`"\u{2022} "` bullet, tab per 2-space indent level), ordered lists (`N.` / `N)` marker kept in the rendered prefix), inline earliest-match loop for code / bold-italic / bold / italic / links. Header comment records the intent to later replace with swift-markdown's `MarkupWalker` (no SPM dependency today).
- `vreader/Services/MD/MDFileLoader.swift` — `MDFileLoader.load(url:parser:positionStore:bookFingerprintKey:renderConfig:chineseConversion:replacementRules:)`: reads bytes, `EncodingDetector.detect`, builds the transform chain (`ReplacementTransform` first, then `SimpTradTransform` — a rule targeting simplified text must run before conversion; feature #54 WI-7 order), parses in `Task.detached`, restores the saved position clamped to `renderedTextLengthUTF16` (non-fatal, falls back to 0).
- `vreader/Services/MD/MDReplacementRuleFetcher.swift` — fetches enabled `ContentReplacementRule` rows (global `scopeKey == ""` or exact fingerprint key) via a SwiftData `FetchDescriptor` predicate on a detached `ModelContext`, mapping to value-type `ReplacementRuleDescriptor` (feature #54 WI-7).
- `vreader/Services/MD/MDMetadataExtractor.swift` — `MetadataExtractor` conformance for import: title = first ATX H1 (trailing `#` markers stripped), truncated to 255 chars, else filename fallback; uses `EncodingDetector` (not UTF-8-only).
- `vreader/Services/MD/MDChapterStartDecorator.swift` + `MDChapterStartScanner.swift` — feature #68 WI-3 chapter-start typography. Decorator restyles only the leading heading (`headings.first` with `charOffsetUTF16 == 0`) and drop-caps the first PLAIN body paragraph; the scanner classifies blocks attribute-based (background color / monospace font → code block, head indent → blockquote, `"\u{2022} "` or digit+`.`/`)`+space prefix → list) and scans at most 24 paragraphs, 8 scalars per paragraph. CONTRACT: `decorate(...).string == attributed.string` — attributes only.
- `vreader/Services/MD/MDReflowableTextSource.swift` — single-segment `ReflowableTextSource` adapter over the rendered (not source) text; empty rendered text → zero segments.

## Dependencies

Internal: `EncodingDetector` (shared multi-encoding detection), the [[Module — text mapping]] transform chain (`TextMapper`, `ReplacementTransform`, `SimpTradTransform`), `ReadingPositionPersisting` (position restore), `ChapterStartTypography` + `ReaderTypography` (feature #68 constants/fonts), `ContentReplacementRule` (SwiftData `@Model`), `MetadataExtractor`/`BookImporter` (import seam, see [[Module — import pipeline]]). External: Foundation, UIKit (`#if canImport(UIKit)`-gated), SwiftData. No swift-markdown package.

## Data flow

`MDReaderHost` (dispatched by `ReaderContainerView.swift:1239`, see [[Architecture — reader dispatch and format hosts]]) → `MDReaderViewModel` → `MDFileLoader.load`: bytes → decode → transforms (source text, BEFORE parse) → `MDParser.parse` → `MDDocumentInfo`. `vreader/ViewModels/MDReaderViewModel.swift:196` then applies `MDChapterStartDecorator.decorate` to the rendered attributed string. Headings carry `charOffsetUTF16` into the outline; display goes through the shared `UITextView` bridge infrastructure. MD paged mode reuses `NativeTextPageNavigator` (TextKit 1) per its `@coordinates-with` header.

## Concurrency

Parsing and file I/O run inside `Task.detached` in `MDFileLoader.load` with a `Task.isCancelled` check between parse and position restore. `MDParser` is `Sendable`; `MDAttributedStringRenderer` is a static enum (pure computation on any executor). `MDReplacementRuleFetcher` never passes `@Model` rows across actors — only `ReplacementRuleDescriptor` values.

## Edge cases and invariants

- Empty text → empty `MDDocumentInfo` (no headings, empty attributed string).
- Transform-before-parse keeps rendered coordinates self-consistent at parse time, but `MDFileLoader.restoreOffset` does no semantic re-derivation: it just reloads the previously saved numeric `charOffsetUTF16` and clamps it to the new `renderedTextLengthUTF16` (no `OffsetMap` conversion or quote recovery). A length-changing replacement-rule edit therefore can shift the restored position within the new rendered text rather than track the original semantic location.
- `SimpTradTransform` is 1:1 UTF-16 for BMP CJK, so positions/highlights survive a conversion toggle (bug #178 / GH #606).
- SwiftData `#Predicate` quirk: global-scope match uses `rule.scopeKey == ""` because `String.isEmpty` silently matched nothing (comment in `MDReplacementRuleFetcher.descriptors`).
- Drop-cap: heading blocks are excluded by offset matching (`headingOffsets`) because a rendered heading has no distinctive run attribute — without it `# H1\n\n## H2\n\nBody` would mis-drop-cap the `## H2` line; surrogate pairs are reconstructed so supplementary-plane letters get a UTF-16 length-2 cap range; CJK initials are ineligible (`ChapterStartTypography.isDropCapEligible`).
- Restored offsets are clamped to `[0, renderedTextLengthUTF16]`; restore failure is non-fatal.

## History

Feature #54 WI-7 (content replacement rules wired into native MD via `replacementRules` + `MDReplacementRuleFetcher`); bug #178 / GH #606 (Chinese conversion applied to MD source before parse); feature #60 WI-5 (theme-aware code-block/blockquote colors replacing platform defaults); feature #68 WI-3 (chapter-start typography, decorator + scanner split to honor the ~300-line file budget); WI-008c (loader extracted from `MDReaderViewModel.open()`); WI-6B (canonical rendered-text normalization rules referenced in the renderer header). The Android port re-implements MD offset mapping separately — feature #125's `MarkdownOffsetMap` + `ChunkTextMapper` under `android/app/src/main/kotlin/com/vreader/app/reader/` (see [[Module — Android port]] and [[Module — text mapping]]).

**Sources.** [[session 014jggU2u3f3t6YRoPLS457u · 2026-07-10]] · [[session 014jggU2u3f3t6YRoPLS457u-audit · 2026-07-11]]
**Verified.** 2026-07-11 — checked against: vreader/Services/MD/MDParser.swift, vreader/Services/MD/MDParserProtocol.swift, vreader/Services/MD/MDTypes.swift, vreader/Services/MD/MDAttributedStringRenderer.swift, vreader/Services/MD/MDFileLoader.swift, vreader/Services/MD/MDReplacementRuleFetcher.swift, vreader/Services/MD/MDMetadataExtractor.swift, vreader/Services/MD/MDChapterStartDecorator.swift, vreader/Services/MD/MDChapterStartScanner.swift, vreader/Services/MD/MDReflowableTextSource.swift, vreader/Views/Reader/ReaderContainerView.swift, vreader/Views/Reader/MDReaderContainerView.swift, vreader/Views/Reader/NativeTextPageNavigator.swift, vreader/Views/Reader/ReaderFormatHosts.swift, vreader/ViewModels/MDReaderViewModel.swift, vreader/Services/ChapterStartTypography.swift, vreader/Services/TextMapping/SimpTradTransform.swift, vreader/Services/TextMapping/TextMapper.swift, vreader/Services/TextMapping/ReplacementTransform.swift, vreader/Services/EPUB/ReadingPositionPersisting.swift, vreader/Services/ReaderTypography.swift, vreader/Services/MetadataExtractor.swift, vreader/Services/BookImporter.swift, vreader/Utils/EncodingDetector.swift, vreader/Models/ContentReplacementRule.swift, docs/bugs.md, archive/bugs-history.md, docs/features.md, archive/plans/2026-03-10-full-refactor.md, archive/plans/WI-6B-markdown-reader-plan.md, android/app/src/main/kotlin/com/vreader/app/reader/MarkdownOffsetMap.kt, android/app/src/main/kotlin/com/vreader/app/reader/ChunkTextMapper.kt, canon/architecture/reader-dispatch.md, canon/modules/text-mapping.md, canon/modules/import-pipeline.md, canon/modules/android-port.md.
