# Legado vs VReader — Architecture Comparison & Adoption Plan

**Date**: 2026-03-15
**Purpose**: Reference document for architectural decisions. Informs features #21-#37.
**Source**: Legado (github.com/gedoor/legado, 44.8k stars, Kotlin/Android)

---

## 1. Project Overview

|                   | Legado                                       | VReader                                                    |
| ----------------- | -------------------------------------------- | ---------------------------------------------------------- |
| **Platform**      | Android (Kotlin)                             | iOS (Swift 6, SwiftUI)                                     |
| **Stars**         | 44.8k                                        | —                                                          |
| **Core audience** | Chinese web novel readers                    | Local document readers                                     |
| **Philosophy**    | Content ingestion + unified reading pipeline | Document fidelity + platform-native rendering              |
| **Rendering**     | One custom Canvas engine for all formats     | Native renderer per format (UITextView, WKWebView, PDFKit) |
| **Persistence**   | Room (SQLite)                                | SwiftData + CloudKit                                       |
| **Concurrency**   | Kotlin coroutines                            | Swift 6 strict concurrency (actors)                        |
| **Testing**       | Limited visible test surface                 | 2040+ tests, TDD enforced                                  |

---

## 2. Rendering Architecture

### Legado: Single Engine

```
Any format → Text extraction → ChapterProvider (1053 lines) → TextPage[] → Canvas rendering
```

- EPUB: Parse ZIP → Jsoup strip HTML → plain text
- TXT: Encoding detect → regex TOC → byte-offset chapters
- PDF: MuPDF text extraction
- Web: HTTP fetch → rule engine → text extraction
- ALL feed into `ChapterProvider` which measures text with `TextPaint`, does CJK-aware line breaking (`ZhLayout`), and splits into pages

**Pros**: Pagination, TTS, replacement rules, page-turn animations all attach ONCE
**Cons**: Loses EPUB CSS/layout, PDF native rendering, complex documents break

### VReader: Multi-Engine

```
ReaderContainerView → format dispatch
├── TXT → UITextView (small) / UITableView chunked (large)
├── MD  → UITextView with NSAttributedString
├── EPUB → WKWebView with CSS theme injection + JS bridges
└── PDF → PDFKit PDFView
```

**Pros**: Full document fidelity, native platform behaviors, accessibility
**Cons**: Every cross-format feature must be implemented 4x, no pagination

---

## 3. Feature Comparison

### Reading Features

| Feature                | Legado                                                       | VReader             | Notes                                |
| ---------------------- | ------------------------------------------------------------ | ------------------- | ------------------------------------ |
| Pagination (pages)     | Yes (all formats)                                            | No (scroll only)    | Legado's core advantage              |
| Page turn animations   | 6 modes (cover, simulation, slide, scroll, horizontal, none) | None                | Via `PageDelegate` pattern           |
| Auto page turning      | Yes                                                          | No                  | Timed flip                           |
| Continuous scroll      | Yes                                                          | Yes (default)       | VReader's only mode                  |
| TTS read aloud         | System + HTTP TTS                                            | No                  | Legado tracks position during speech |
| Configurable tap zones | Yes (left/center/right → custom actions)                     | No                  | Toggle chrome only                   |
| Content replacement    | Yes (regex rules, importable)                                | No                  | Text cleaning                        |
| Simp/Trad conversion   | Yes                                                          | No                  | `ChineseConverter`                   |
| Reading progress bar   | No (uses page number)                                        | Yes (all 4 formats) | VReader ahead                        |

### Annotation & Highlight

| Feature                            | Legado                | VReader                                                                   | Notes                |
| ---------------------------------- | --------------------- | ------------------------------------------------------------------------- | -------------------- |
| Text highlighting                  | Custom text rendering | CSS Highlight API (EPUB) + PDFAnnotation (PDF) + NSAttributedString (TXT) | Different approaches |
| Notes/annotations                  | Basic                 | Yes (unified AnnotationAnchor schema across formats)                      | VReader ahead        |
| Search highlighting at destination | No                    | Yes (per-format, yellow highlight)                                        | VReader ahead        |
| Export annotations                 | No                    | Planned (#35)                                                             | —                    |

### Content Sources

| Feature                 | Legado                             | VReader                  | Notes                   |
| ----------------------- | ---------------------------------- | ------------------------ | ----------------------- |
| Book source scraping    | Yes (core feature, 25+ rule types) | Planned (#24)            | Legado's killer feature |
| OPDS catalog            | No                                 | Planned (#36)            | Cleaner standard        |
| Local file import       | Yes (TXT, EPUB, PDF, UMD, MOBI)    | Yes (TXT, EPUB, PDF, MD) | Similar                 |
| Web novel subscriptions | Yes                                | No                       | —                       |

### Library & Organization

| Feature             | Legado               | VReader                     | Notes         |
| ------------------- | -------------------- | --------------------------- | ------------- |
| Custom book covers  | Yes                  | Planned (#30)               | —             |
| Collections/tags    | Bookshelves + groups | Planned (#34)               | —             |
| Reading statistics  | Basic                | Yes (sessions, time, speed) | VReader ahead |
| Library sort/filter | Yes                  | Yes (persistent prefs)      | Similar       |

### AI Features

| Feature                | Legado | VReader                           | Notes          |
| ---------------------- | ------ | --------------------------------- | -------------- |
| AI summarization       | No     | Yes                               | VReader unique |
| AI chat (book context) | No     | Yes                               | VReader unique |
| AI translation         | No     | Yes (9 languages, bilingual view) | VReader unique |
| Dictionary/define      | No     | Planned (#33)                     | —              |

### Settings & Customization

| Feature                | Legado                       | VReader                   | Notes         |
| ---------------------- | ---------------------------- | ------------------------- | ------------- |
| Font/size/spacing      | Yes                          | Yes                       | Similar       |
| Themes                 | Multiple + background images | Basic light/dark + colors | Legado richer |
| Per-book settings      | Yes                          | Planned (#37)             | —             |
| Click zone config      | Yes                          | Planned (#25)             | —             |
| Padding per-edge       | Yes                          | No                        | —             |
| Font weight adjustment | Yes                          | No                        | —             |

### Backup & Sync

| Feature               | Legado                   | VReader           | Notes                    |
| --------------------- | ------------------------ | ----------------- | ------------------------ |
| WebDAV backup         | Yes                      | Planned (#29)     | Legado uses Nutstore/坚果云 |
| iCloud sync           | N/A (Android)            | Design only (#10) | —                        |
| Reading progress sync | Yes (WebDAV)             | No                | —                        |
| Source/rule sharing   | Yes (JSON import/export) | No                | —                        |

---

## 4. What VReader SHOULD Adopt

### High Priority Patterns

#### 4.1 ReflowableTextSource Abstraction

Legado's key insight: abstract text content from rendering. VReader should add a `ReflowableTextSource` protocol that yields ordered text segments with stable offsets. TXT, MD, and optionally EPUB-text-mode can conform to this.

**Why**: Enables shared pagination, TTS, and replacement rules without 4x implementation.

#### 4.2 Shared Reader Lifecycle Coordinator

VReader has open/close/background/session logic duplicated across 4 ViewModels. Extract to a `ReaderLifecycleCoordinator` that all ViewModels delegate to.

**Why**: Reduces duplication, prevents lifecycle bugs (historically the most common regression area).

#### 4.3 Format Capability Flags

Add a capability system so shared features can query what each format supports:

```swift
protocol ReaderCapabilities {
    var supportsPagination: Bool { get }
    var supportsTextSelection: Bool { get }
    var supportsTTS: Bool { get }
    var supportsReplacementRules: Bool { get }
}
```

**Why**: Features like TTS can degrade gracefully per format instead of crashing.

#### 4.4 TXT TOC Rule Engine (Feature #23)

Directly adopt Legado's `txtTocRule.json` patterns. 25 battle-tested regex rules for Chinese, English, numbered headings, special symbols. Auto-detect best rule from 512KB sample.

#### 4.5 Page Turn Delegate Pattern (Feature #21)

Legado's `PageDelegate` abstract class with 6 subclasses is clean. Adopt the PATTERN (pluggable page turn strategy) but implement in SwiftUI/UIKit, not the Android Canvas code.

#### 4.6 Book Source Rule Engine (Feature #24)

Adopt Legado's `BookSource` JSON schema for compatibility with the massive existing source ecosystem. Implement the rule engine in Swift (SwiftSoup for HTML parsing).

#### 4.7 Configurable Tap Zones (Feature #25)

Simple action mapping: divide screen into zones, each maps to an action. Legado stores this as user preference. Quick win, prerequisite for page mode.

### Medium Priority Patterns

#### 4.8 Content Replacement Rules (Feature #27)

Legado's regex-based text cleaning is useful for messy TXT files. But VReader must implement a text-mapping layer to avoid desyncing highlights/search/bookmarks.

#### 4.9 WebDAV Backup (Feature #29)

Simpler than iCloud, cross-platform, works with Nutstore. Adopt Legado's `AppWebDav` pattern: backup as ZIP, restore by overwriting, progress sync as small JSON files.

#### 4.10 Reading Theme Backgrounds (Feature #32)

Legado supports custom background images per theme. Straightforward to add in VReader.

### Low Priority Patterns

#### 4.11 Simp/Trad Conversion (Feature #28)

Useful for CJK audience. Needs the same text-mapping layer as #27.

#### 4.12 Auto Page Turning (Feature #31)

Depends on pagination (#21). Timed page flip or auto-scroll.

---

## 5. What VReader Should NOT Adopt

### 5.1 Single Rendering Engine

**Don't flatten EPUB to plain text.** Legado loses CSS layout, tables, math, SVG, links, and accessibility. VReader's WKWebView preserves all of this. The tradeoff is worth it for document-quality reading.

### 5.2 Custom Canvas Text Rendering

**Don't replace UITextView/WKWebView/PDFKit with custom drawing.** On iOS, fighting system frameworks is a net loss — you lose accessibility, text selection, Dynamic Type, VoiceOver, and system dictionary for free.

### 5.3 Mega-Engine Pattern

**Don't create one object that owns everything.** Legado's `ChapterProvider` is 1053 lines and growing. VReader's per-format separation is better for testability and maintenance.

### 5.4 Book Source Scraping as Default Content Model

**Don't make web scraping the primary UX.** VReader is a document reader with scraping as an advanced feature. The library should stay file-first, with web sources as an addition.

### 5.5 Room-Style Raw SQL

**Keep SwiftData.** VReader's actor-isolated persistence is safer than raw SQL for concurrent access patterns.

---

## 6. Architecture Plan for Paginated Reading (Feature #21)

### Recommended Approach: Hybrid

Keep the multi-engine shell. Add pagination as a rendering MODE, not a replacement.

```
ReaderContainerView
├── TXT/MD
│   ├── ScrollMode (current UITextView/UITableView)
│   └── PageMode (new: TextKit multiple text containers)
├── EPUB
│   ├── ScrollMode (current WKWebView)
│   └── PageMode (CSS column-based OR Readium toolkit OR text-mode fallback)
├── PDF
│   └── PageMode (native — PDFKit already has pages)
└── PageTurnAnimationLayer (shared, above all renderers)
```

### Per-Format Strategy

| Format          | Pagination Method                                                                 | Effort | Risk                       |
| --------------- | --------------------------------------------------------------------------------- | ------ | -------------------------- |
| **PDF**         | Already paginated (PDFKit)                                                        | None   | None                       |
| **TXT/MD**      | TextKit `NSTextContainer` array — measure text, split into page-sized containers  | M      | Medium (TextKit 1 quirks)  |
| **EPUB scroll** | CSS `column-width` + `overflow: hidden` in WKWebView — browser handles pagination | M      | Medium (cross-browser CSS) |
| **EPUB text**   | Extract text like Legado, use TXT/MD paginator                                    | L      | High (loses CSS fidelity)  |

### Page Turn Animations

Shared layer above renderers:

```swift
protocol PageTurnDelegate {
    func animateForward(from: UIView, to: UIView)
    func animateBackward(from: UIView, to: UIView)
}

class SlidePageTurn: PageTurnDelegate { ... }
class CoverPageTurn: PageTurnDelegate { ... }
class NonePageTurn: PageTurnDelegate { ... }
// SimulationPageTurn deferred — complex, low priority
```

---

## 7. Architecture Plan for Book Source (Feature #24)

### Phased Delivery

| Phase | Scope                                                                                        | Effort |
| ----- | -------------------------------------------------------------------------------------------- | ------ |
| 1     | BookSource model + management UI + HTTP client + HTML parser (SwiftSoup) + one vetted source | M      |
| 2     | Rule import/export (Legado JSON compatible) + chapter cache + offline reading                | M      |
| 3     | Encoding detection + cookies/headers + update detection + source sharing                     | M      |
| 4     | Broader Legado compatibility + JS execution (if needed)                                      | L      |

### Rule Engine Design

```swift
protocol RuleEvaluator {
    func evaluate(_ rule: String, in document: Document) -> [String]
}

class CSSRuleEvaluator: RuleEvaluator { ... }     // SwiftSoup CSS selectors
class XPathRuleEvaluator: RuleEvaluator { ... }    // libxml2 XPath
class RegexRuleEvaluator: RuleEvaluator { ... }    // NSRegularExpression
class JSONPathRuleEvaluator: RuleEvaluator { ... } // Custom or library
// JSRuleEvaluator deferred to Phase 4
```

---

## 8. Shared Abstractions to Build

### 8.1 ReflowableTextSource

```swift
protocol ReflowableTextSource {
    var totalLength: Int { get }
    func text(in range: Range<Int>) -> String
    func attributes(at offset: Int) -> TextAttributes
}
```

Conformers: `TXTTextSource`, `MDTextSource`, `EPUBTextSource` (optional)

### 8.2 ReaderLifecycleCoordinator

Extract from 4 ViewModels: open, close, background save, session tracking, position restore.

### 8.3 FormatCapabilities

```swift
struct FormatCapabilities: OptionSet {
    static let pagination = FormatCapabilities(rawValue: 1 << 0)
    static let textSelection = FormatCapabilities(rawValue: 1 << 1)
    static let tts = FormatCapabilities(rawValue: 1 << 2)
    static let replacementRules = FormatCapabilities(rawValue: 1 << 3)
    static let highlights = FormatCapabilities(rawValue: 1 << 4)
}
```

### 8.4 BackupProvider

```swift
protocol BackupProvider {
    func backup(data: BackupData) async throws
    func restore() async throws -> BackupData
    func syncProgress(_ progress: ReadingProgress) async throws
}

class WebDAVBackupProvider: BackupProvider { ... }
class ICloudBackupProvider: BackupProvider { ... }
class LocalExportProvider: BackupProvider { ... }
```

---

## 9. Implementation Priority

See `docs/codex-plans/2026-03-15-v2-roadmap.md` for the full execution plan.

**Summary**: 18 features → 47 WIs across 6 phases (Phase 0 foundation → A quick wins → B reader core → C library → D web content → E sync & text).

**Dual-mode architecture**: Native (current renderers) + Unified (TextKit 2 reflow). Both support scroll + paged. Unified scoped to TXT/MD/simple EPUB. Complex EPUB falls back to Native. PDF always PDFKit.

**Phase order**:
1. Phase 0: Foundation abstractions + performance fixes + TextKit 2 spike (11 WIs)
2. Phase A: Quick wins — #22, #25, #30, #32, #37 (5 WIs)
3. Phase B: Pagination + TTS + dictionary + TXT TOC (13 WIs)
4. Phase C: Collections + annotation export + OPDS (4 WIs)
5. Phase D: Book source scraping — Legado-compatible (8 WIs)
6. Phase E: WebDAV + iCloud backup + text transforms + HTTP TTS (6 WIs)

---

## 10. Known Performance Issues (2026-03-15)

Large TXT files (~15MB, ~7.5M CJK chars) have two performance problems:
- **Slow open** (bug #60): Encoding detection + full text load + FTS5 indexing all happen in series before UI shows content. Several seconds of spinner.
- **Slow search** (bug #61): FTS5 index built fresh on every open. `BackgroundIndexingCoordinator` exists but reader doesn't use it. Index not persisted.

**These are I/O and indexing bottlenecks, not renderer problems.** The chunked UITableView renders fine once loaded. Fixes: persist FTS5 index, stream encoding detection (sample 8KB), defer indexing to background, load visible chunks first.

**Architecture implication**: Codex confirmed these don't change the renderer decision. Option A (keep multi-engine + Phase 0 abstractions) remains correct. The performance fixes belong in Phase 0 alongside the lifecycle extraction.

---

## 11. Architecture Decision Record (2026-03-15, revised)

**Decision**: Dual-mode architecture — keep Native (multi-engine) AND add Unified (TextKit 2 reflow). User can switch between them. Both support scroll and paged layout.

**Native mode**: WKWebView (EPUB), PDFKit (PDF), UITextView (TXT/MD). Unchanged from V1.

**Unified mode**: TextKit 2 reflow engine for TXT, MD, and simple EPUB chapters. Pixel-identical rendering across these formats. Complex EPUBs fall back to Native. PDF stays on PDFKit.

**Alternatives rejected**:
- Option B (Readium for EPUB+PDF): High migration, PDF not clearly better than PDFKit
- Option C (WKWebView for all text): Loses chunked TXT performance, high risk
- Option D (Readium for everything): Very high migration, delays V2
- Option E (Full custom Canvas): Extreme effort, loses system features (selection, a11y, dictionary)

**Rationale**:
1. Zero regression risk — Native mode is unchanged, always available as fallback
2. Unified gives pixel-identical reading for reflowable text without throwing away native fidelity
3. Large CJK TXT performance requires native chunked rendering in Native mode
4. PDFKit is already strong — no reason to replace it
5. Phase 0 abstractions (lifecycle coordinator, format capabilities, PageNavigator) shared by both modes

**Critical safeguard**: WI-F09 (cross-mode locator normalization) + WI-F10 (mode-switch persistence tests) ensure highlights/bookmarks/position survive engine switching.

**Future**: Readium EPUB spike if CSS-column pagination (B06) proves too difficult in WKWebView.

---

## 12. Key Takeaways

1. **Legado optimizes for web novels; VReader optimizes for documents.** Different audiences, different tradeoffs.
2. **Adopt Legado's PATTERNS, not its architecture.** The rule engine, TOC rules, page turn delegate, and tap zone concepts are portable. The single-rendering-engine is not.
3. **Dual-mode is the right answer.** Native (format fidelity) + Unified (pixel-identical reflow) gives users the best of both worlds. Neither engine alone is sufficient.
4. **Unified scope is limited.** TXT, MD, simple EPUB only. Complex EPUB stays on WKWebView. PDF stays on PDFKit. Don't try to unify everything.
5. **The biggest architectural gap is shared abstractions.** VReader needs ReflowableTextSource, ReaderLifecycleCoordinator, FormatCapabilities, and PageNavigator to scale.
6. **Cross-mode data integrity is the #1 risk.** Locator/anchor normalization (WI-F09) and mode-switch tests (WI-F10) must be built before any feature work.
7. **Book source scraping is an epic, not a feature.** Phase it carefully and aim for Legado JSON compatibility to leverage the existing source ecosystem.
8. **Large file performance is an I/O/indexing problem, not a renderer problem.** Fix with persistent FTS5 index, streaming load, and deferred indexing — not by changing renderers.

