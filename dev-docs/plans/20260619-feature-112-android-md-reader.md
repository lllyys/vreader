# Feature #112 — Android Markdown (.md) reader (Phase 3, capability parity)

Status: Gate-2 audited, round 3 clean (2026-06-20). Second per-capability feature under the #110
Android Phase-3 driver, in reuse-leverage order (EPUB ✓ → TXT ✓ → **MD** → AZW3/PDF).
A thin delta over the TXT reader (#111).

## Problem

The Android app reads EPUB + TXT. iOS also reads `.md` (a Markdown attributed
string). Bring **Markdown reading** to Android: import a `.md` → Library → open in a
scrollable reader with the shared chrome → markdown rendered (headers, bold, italic,
inline code, bullet lists) → resume via `charOffsetUTF16`. Core read only; the rich MD
features (bilingual, highlights, TTS) are later #110 capabilities.

## Heavy reuse (the delta is small)

`.md` is text, so it reuses the #111 TXT stack:
- **`TxtDecoder`** (charset-detected decode) — identical.
- **`TxtDocument`** (range-based chunking + UTF-16 offset addressing, no normalization)
  — reused AS-IS. **Important (Gate-2)**: `TxtDocument` is **LINE-chunked** (splits at
  every newline + hard-splits a runaway line), NOT paragraph-chunked. So v1 markdown is
  a **single-line subset**: single-line ATX headers, single-line emphasis, inline code,
  single-line bullets — each renders within its own line-chunk. **Multi-line constructs
  are OUT of scope for v1** (fenced code blocks, multi-line list items, continuation
  paragraphs, emphasis spanning a newline) — those render as literal text and are a
  follow-on (would need paragraph-aware chunking).
- **resume** (`VReaderLocator.wrapLegacy(Locator(… charOffsetUTF16 = …))` + `ResumeResolver → Canonical`
  + the conflated-channel save + offset cache) — identical. Resume keys off the RAW
  `TxtDocument` source offsets, NOT rendered spans, so rendering can't drift it.
- **chrome** (back + title, `vreader-reader.jsx` reuse), open-from-storage, lifecycle —
  identical.
- `DocumentFingerprint.formatForFilename` already maps `md`/`markdown` → `BookFormat.md`;
  `BookImporter` already imports it.

**The ONLY new thing** is rendering a line-chunk's text as styled markdown instead of
plain text. The reader already has the format in its loaded `Book`; pass
`s.book.originalFormat` into `TxtBody` to pick markdown-vs-plain rendering (no broader
load-state change).

## Surface area

- `android/app/.../reader/MarkdownRenderer.kt` (NEW) — a small CommonMark subset
  parser: a chunk's text → a Compose `AnnotatedString` styling ATX headers (`#`..),
  `**bold**`, `*italic*`/`_italic_`, `` `code` ``, and `- `/`* ` bullet prefixes; lines
  that aren't markdown render verbatim. Pure JVM (returns `AnnotatedString`, a Compose
  type — testable for the span ranges). Unknown/edge syntax degrades to plain text (no
  crash). NOT a full CommonMark engine (no tables/blockquotes/nested lists in v1).
- `android/app/.../reader/TxtReaderActivity.kt` — render each chunk via the format:
  `BookFormat.md` → `MarkdownRenderer.render(chunk)`, else plain `Text`. The activity
  already loads the book (knows `originalFormat`); thread it to `TxtBody`. (Doc the
  activity as the plain/markdown text reader; a later rename to `TextReaderActivity` is
  cosmetic.)
- `android/app/.../MainActivity.kt` — route `BookFormat.md` → `TxtReaderActivity` (the
  exhaustive `when`: epub→Readium, txt+md→text reader, pdf/azw3→"not available yet").
- Tests: `MarkdownRendererTest` (JVM — the authoritative `AnnotatedString` span/style
  proof: headers/bold/italic/code/bullet spans, nested/escaped/intraword emphasis, code
  suppresses emphasis, CJK span arithmetic, chunk-boundary independence, malformed/empty
  no-crash); `MdReaderRenderTest` (instrumented — a synthetic `.md` opened **through the
  library/routing path**, asserting rendered text present + raw markers absent).
- **OUT of scope** (render as literal text in v1, no crash): tables, blockquotes, nested
  lists, **ordered lists** (`1. `), **links/images/autolinks** (`[t](u)`, `![]()`,
  `<http://…>`), **raw HTML**, **HTML entities** (`&amp;`), **thematic breaks** (`---`),
  backslash escapes beyond `\*`/`\_`, and **`__bold__` (double underscore)** — v1 emphasis
  is **only** `*`/`**` and single `_italic_`; double-underscore is literal. Also OUT:
  bilingual, highlights, TTS, AZW3/PDF.

## Work items

| WI | Scope | Tier |
|---|---|---|
| WI-1 | `MarkdownRenderer` (chunk → `AnnotatedString`, the CommonMark subset) + JVM tests; wire format-aware rendering into the existing text reader + route `md`. Instrumented md-render test (synthetic fixture). | behavioral (single WI — the rest is reused from #111) |

## Test catalogue

`MarkdownRendererTest` (JVM) is the **authoritative style proof** — it asserts the
concrete `AnnotatedString` span ranges + `SpanStyle` attributes the renderer produces,
which the instrumented Compose test cannot inspect. Cases:

- **Headers**: `# H1` / `## H2` / `### H3` — larger `fontSize` + `FontWeight.Bold` span
  over the text WITHOUT the leading `#`/space markers; the `# ` prefix is consumed, not
  rendered.
- **Emphasis**: `**bold**` (Bold span on the inner text, `**` delimiters dropped),
  `*italic*` and `_italic_` (Italic span), **nested/mixed** `***both***` and
  `**bold _and italic_**` (overlapping spans), **escaped** `\*literal\*` (renders the
  `*`, no emphasis), **underscores inside a word** `foo_bar_baz` (NOT italic — intraword
  `_` is literal, the CommonMark rule).
- **Inline code**: `` `code` `` (monospace `FontFamily`, backticks dropped); **code
  suppresses emphasis** `` `a*b*c` `` (the `*` inside code is literal, no italic span).
- **Bullets**: `- item` / `* item` (bullet glyph prefix, marker consumed).
- **Passthrough / robustness**: a plain line (verbatim, zero spans), a malformed
  `**unterminated` (no crash — renders the `**` literally), a malformed EOF marker
  `trailing **` , the empty string `""`, a bare `#`/`## ` (empty heading — no crash,
  renders as an empty/whitespace styled line).
- **Unicode/CJK**: `**中文**` and `# 標題` — span offsets are correct over multi-byte
  (UTF-16) text (the bug-class TXT decode already exercises CJK; here the concern is span
  arithmetic, not bytes).
- **Chunk-boundary**: a token split by `TxtDocument`'s 4000-char hard chunk boundary
  (and a CRLF line) renders each half as its own chunk — a `**` opened in chunk N and
  closed in chunk N+1 does NOT span chunks (each chunk renders independently; the marker
  is literal in each), confirming the single-line-subset contract.
- Instrumented (`MdReaderRenderTest`): a synthetic `.md` fixture is opened **through the
  library/routing path** — there is no `onOpenBook` helper (routing is an inline lambda
  in `MainActivity`), so the test **launches `MainActivity`** (`ActivityScenario` /
  `createAndroidComposeRule<MainActivity>()`), seeds/imports the `.md`, waits for the
  library row, and **taps it** — exercising the real `BookFormat.md → TxtReaderActivity`
  route. Assert the rendered heading + bold body **text is present** AND the raw markers
  (`# `, `**`) are **absent** from the on-screen text — the visual proof that rendering
  (not literal markdown) happened. The exact span styling is proven by
  `MarkdownRendererTest`, not here.
- **TXT-renders-literally regression** (the Gate-2-r2 Medium — threading `originalFormat`
  into `TxtBody` must NOT markdown-render TXT): a `BookFormat.txt` fixture whose content
  is `# not heading **not bold**` renders the markers **literally** (raw `# ` and `**`
  visible on screen, no Bold/heading span). Covers it both as a `MarkdownRendererTest`-
  adjacent unit assertion (the renderer is only invoked for `md`) and as an instrumented
  TXT-open assertion — a single markdown-everything bug must fail at least one.
- **MD resume** (the Gate-2-r2 Low — acceptance claims resume is verified for `md`): seed
  a legacy `Locator(format = "md", charOffsetUTF16 = …)` via `VReaderLocator.wrapLegacy`,
  open the MD reader path, and assert it restores to the expected later chunk
  (`ResumeResolver → Canonical → chunkForOffset`), mirroring `TxtResumeTest` for `md`.

## Risks + mitigations

- **R1 — markdown parsing scope creep.** Bound v1 to the inline subset above; anything
  unrecognized renders verbatim (graceful). Full CommonMark (tables, nested lists) is a
  follow-on.
- **R2 — real fixture.** No real `.md` book exists (the documented real-books-first
  exception: "no real MD today"); use a synthetic `.md` fixture. The decode/offset/
  resume paths are already real-book-verified via the #111 TXT path (same code).
- **R3 — offset fidelity with markdown.** `TxtDocument` offsets index the raw decoded
  text (markdown source), so `charOffsetUTF16` resume is unaffected by rendering.

## Backward compat

Additive: a new render path for a format the importer already accepts; no schema change;
TXT/EPUB unaffected.

## Acceptance criteria

1. A `.md` imports, appears in the Library (`MD` chip), opens with markdown **rendered**
   (heading styled, bold/italic/code visible).
2. Scroll + resume work (reused TXT infra; resume verified).
3. `MarkdownRendererTest` (JVM, authoritative span proof) + `MdReaderRenderTest`
   (instrumented, library-path render) pass.
4. TXT/EPUB reading unaffected; routing opens `md` → the text reader.

## Revision history

- **v1** (2026-06-19) — initial Gate-1 draft.
- **v2** (2026-06-20) — Gate-2 audit round 1 (Codex). Findings addressed:
  - *(Medium)* `TxtDocument` is **line-chunked, not paragraph-chunked** → v1 markdown
    scoped explicitly to a **single-line subset**; multi-line constructs (fenced code,
    multi-line lists, continuation paragraphs, emphasis across a newline) declared OUT of
    scope (render verbatim), with chunk-boundary independence pinned by a test.
  - *(Medium)* Test design under-specified → `MarkdownRendererTest` made the
    authoritative `AnnotatedString` span/style proof; instrumented `MdReaderRenderTest`
    re-scoped to import a `.md` and open it **through the library/routing path** (proving
    `md` routing too), asserting rendered text present + raw markers absent.
  - *(Medium)* Edge-case catalogue thin → expanded (nested/mixed/escaped/intraword
    emphasis, inline-code suppresses emphasis, empty headings, malformed EOF markers,
    CJK span arithmetic, 4000-char chunk-boundary + CRLF).
  - *(Low)* Render wiring wording clarified to "pass `s.book.originalFormat` into
    `TxtBody`" (no broader load-state change).
  - Core approach **confirmed sound** by the auditor: `AnnotatedString` is the right
    return type, a hand-rolled CommonMark-subset parser is fine for v1, the single-WI
    split is appropriate, txt+md reuse is clean, and resume/offset fidelity is unaffected
    (offsets index the raw markdown source, not rendered spans).
- **v3** (2026-06-20) — Gate-2 audit round 2 (Codex). Findings addressed:
  - *(Medium)* `MainActivity.onOpenBook` does not exist (routing is an inline lambda) →
    `MdReaderRenderTest` re-specified to **launch `MainActivity`**, seed the `.md`, wait
    for the library row, and tap it (exercising the real route).
  - *(Medium)* Test plan didn't prove TXT still renders literally after threading
    `originalFormat` into `TxtBody` → added a **TXT-renders-literally regression**
    (`# not heading **not bold**` for `BookFormat.txt`, raw markers asserted visible).
  - *(Low)* MD resume not directly tested → added an **MD resume** test (legacy
    `Locator(format="md", …)` round-trip).
  - *(Low)* OUT-of-scope list ambiguous → enumerated `__bold__`/ordered lists/links/
    images/raw HTML/entities/thematic breaks/broader escapes as literal; v1 emphasis is
    only `*`/`**`/single `_italic_`.
  - *(Low)* fixed `wrapLegacy` wording (takes a `Locator`, not a bare offset); status
    header updated to Gate-2.
  - Auditor re-confirmed all model assumptions exist and one WI is the right cohesion.
