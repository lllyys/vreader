# Feature #117 — Android OPDS catalog backend (parser + client + acquisition→import)

**Status:** Gate 1 (plan). Part of the #110 Android Phase-3 parity driver.

## Problem

iOS lets users add OPDS online catalogs and download books from them
(`vreader/Services/OPDS/{OPDSParser,OPDSClient,OPDSModels}.swift` + a browse UI).
Android has none of it. The **browse/add/download UI is design-gated** (rule 51 —
needs-design issue #1799), but the **OPDS feed parser + HTTP client + acquisition→
import pipeline is pure non-UI backend** that can be built + verified now (the
`#113 backup-model before #114 UI` precedent). This row is that backend slice ONLY.

## Surface area (all new, design-free, under `android/app/.../opds/`)

- **`OpdsModels.kt`** — value types mirroring the iOS OPDS 1.2 model:
  - `OpdsFeed(title, id, links, entries, baseUrl)` with derived `kind`
    (navigation/acquisition), `nextPageUrl`, `searchUrl`; `dedupedEntries`.
  - `OpdsEntry(title, id, author?, summary?, updated?, links)` with
    `coverUrl(baseUrl)`, `acquisitionLinks`, `navigationUrl(baseUrl)`.
  - `OpdsLink(rel?, href, type?, title?)` with `isAcquisition`
    (`rel startsWith "http://opds-spec.org/acquisition"`), `formatLabel`
    (epub/pdf/mobi), `resolvedHref(baseUrl)` (absolute-vs-relative resolution).
  - `OpdsError` sealed type: `InvalidXml / EmptyData / Network / Http(code) / InvalidUrl`.
- **`OpdsParser.kt`** — namespace-aware SAX parse of an Atom/OPDS feed → `OpdsFeed`.
  **Reuses the #116 WI-6 XXE hardening verbatim** (OPDS feeds are untrusted external
  XML): parser-independent fail-closed DOCTYPE ban + fixed-UTF-8 `Reader` +
  `resolveEntity` no-op + best-effort feature flags. Parses `<feed>`/`<entry>`/
  `<title>`/`<id>`/`<author><name>`/`<summary>`/`<content>`/`<updated>`/`<link>`
  (rel/href/type/title attrs); feed-level vs entry-level links; tolerates the OPDS
  `dcterms`/`opds` namespaces; malformed → `InvalidXml`, empty → `EmptyData`.
- **`OpdsClient.kt`** — `suspend fun fetchFeed(url): OpdsFeed` over `HttpURLConnection`
  (the WI-1 `WebDavClient` transport precedent): GET, manual redirect follow,
  content-type tolerance, typed `OpdsError` (timeout/offline/http). `baseUrl` =
  the final (post-redirect) request URL, threaded into the parsed feed for relative
  resolution. v1 = **no auth** (auth catalogs are a follow-on with the UI).
- **`OpdsAcquisitionService.kt`** — `suspend fun download(entry, into: BookImporter):
  Book`: pick the best supported acquisition link (epub > pdf; skip unsupported),
  stream the bytes → `BookImporter.importStream(displayName from the link/format)`
  → returns the imported `Book` (re-fingerprinted, canonical identity, idempotent).
  Typed failure on no-supported-acquisition / download error.

### Files OUT of scope (design-gated / speculative — do NOT build)

Saved-catalog store (DataStore), browse/search/add UI, ViewModels, Compose, cover
image loading, auth'd catalogs, the OpenSearch query flow. Those resume when
needs-design #1799 lands. No production entry point yet (no Library "Add source").

## Prior art / precedent

- iOS `OPDSParser`/`OPDSModels`/`OPDSClient` (the shape to mirror).
- #116 `WebDavClient` (HttpURLConnection transport + redirect + typed errors) and its
  **WI-6 XXE hardening** (the load-bearing lesson — reuse, don't re-derive).
- #116 `BookImporter.importStream` (the download→import seam; `expectedKey` not used
  here — OPDS entries don't pre-declare a fingerprint).

## Work items

| WI | Scope | Tier |
| --- | --- | --- |
| WI-1 | `OpdsModels` + `OpdsParser` (Atom→feed, XXE-hardened, rels/relative-URL/CJK/malformed). JVM tests against fixture feeds (navigation, acquisition, paginated, relative hrefs, CJK, malformed, DOCTYPE-rejected). | foundational |
| WI-2 | `OpdsClient` (HTTP GET + redirect + typed errors; ServerSocket-fake JVM tests) + `OpdsAcquisitionService` (download→`BookImporter`). **Connected round-trip** (final WI): serve a static OPDS feed + a real EPUB over local HTTP, fetch→parse→download→import on the emulator → feature VERIFIED + evidence. | behavioral |

## Test catalogue

- `OpdsParserTest` (JVM): navigation feed, acquisition feed (epub/pdf links),
  relative-href resolution against baseUrl, `nextPageUrl`/`searchUrl`, entry dedup,
  CJK title/author, missing-optional fields, malformed XML → `InvalidXml`, empty →
  `EmptyData`, **DOCTYPE feed → rejected** (XXE), **UTF-16 DOCTYPE → not bypassed**.
- `OpdsClientTest` (JVM, ServerSocket fake): 200 feed parse, 301/302 redirect follow
  + baseUrl = final URL, 404 → `Http(404)`, unreachable → `Network`, content-type
  tolerance.
- `OpdsAcquisitionServiceTest` (Robolectric): pick epub over pdf, skip unsupported,
  download→import yields a `Book` with the canonical key, no-acquisition → typed error.
- `OpdsConnectedTest` (androidTest, gated by an arg like #116): live local HTTP serving
  feed + EPUB → fetch→download→import on the emulator.

## Risks + mitigations

- **Untrusted XML (XXE).** OPDS feeds are remote/untrusted — *higher* XXE exposure than
  WebDAV. Mitigation: reuse the #116 WI-6 hardening verbatim + JVM tests for DOCTYPE +
  UTF-16-bypass. (This is the single most important correctness item.)
- **Relative URL resolution.** OPDS hrefs are frequently relative; wrong baseUrl →
  broken downloads. Mitigation: baseUrl = the post-redirect final URL; explicit
  resolved-href tests.
- **Acquisition link selection.** Multiple formats / indirect-acquisition. v1: direct
  acquisition links only, prefer epub; skip indirect/unsupported with a typed error.

## Backward compat

Purely additive (new package, no entity/schema change, no production wiring). Nothing
to migrate.

## Acceptance criteria

1. `OpdsParser` parses navigation + acquisition Atom feeds (rels, relative hrefs,
   pagination, CJK) and is XXE-hardened (DOCTYPE rejected, UTF-16 not a bypass) — JVM.
2. `OpdsClient` fetches a feed over HTTP with redirect-follow + typed errors — JVM.
3. `OpdsAcquisitionService` downloads an entry's EPUB → imports it via `BookImporter`
   to a canonical-identity `Book` (idempotent) — Robolectric.
4. **Connected round-trip**: a live local OPDS feed + EPUB → fetch→parse→download→
   import on the emulator; the book lands in the library. Evidence file.
5. No UI / production entry point (design-gated #1799); readers + backup unaffected.

## Audit fixes applied (Gate-2, Codex — "revise, then proceed")

- **(High) Acquisition selection too broad** → `OpdsLink.acquisitionKind`: auto-import
  ONLY `http://opds-spec.org/acquisition` (generic) + `.../acquisition/open-access`.
  `buy`/`borrow`/`subscribe`/`sample`/`preview` + `opds:indirectAcquisition` →
  `OpdsError.UnsupportedAcquisition` (no silent import in a no-UI backend).
- **(High) Download display-name underspecified** → derive `displayName` = sanitized
  entry/link title + an extension chosen from the supported MIME FIRST
  (`epub`→`.epub`, `pdf`→`.pdf`), then the href path's extension as fallback (mirrors
  iOS `fileExtension(for:)`). Tests: title-without-ext, href-without-ext. (BookImporter
  picks format from the extension, not MIME.)
- **(Medium) Feed-size / decompression limits** → `OpdsClient.maxFeedBytes` (e.g. 8MB)
  bounded read + reject oversized before SAX; redirect cap (5).
- **(Medium) gzip** → v1 sends `Accept-Encoding: identity` (do NOT request gzip — avoids
  a decompression-bomb surface); a `Content-Encoding: gzip` response is bounded-
  decompressed via `GZIPInputStream` defensively. Test both.
- **(Medium) Download response validation** → require 2xx; reject `text/html`; cheap
  magic check before import (EPUB = ZIP `PK\x03\x04`, PDF = `%PDF-`) → typed error,
  so an HTML login/error page never imports under an `.epub` name.
- **(Low) SAX localName-first** → handler keys off `localName.ifBlank { qName }` (OPDS
  uses the default Atom namespace); test default-ns + prefixed-ns feeds.
- **(Low) android.speech** → N/A; not in this plan (it was only in the audit prompt).

`expectedKey` is NOT used for OPDS imports (OPDS entries don't declare a vreader
fingerprint — confirmed by the auditor). baseUrl = the post-redirect final URL.

## Revision history

- **v1** (2026-06-22) — Gate-1 draft.
- **v2** (2026-06-22) — Gate-2 Codex audit (revise-then-proceed): 2 High + 4 Medium +
  2 Low, all folded in above. No redesign; the 2-WI split + the backend-before-UI call
  + the BookImporter/HttpURLConnection/XXE-reuse assumptions confirmed.
