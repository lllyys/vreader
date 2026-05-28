# DebugFixtures — provenance and licensing

These fixtures are bundled into Debug builds only (the Run Script in
`project.yml`'s `targets.vreader.preBuildScripts` excludes them from
Release). They drive `vreader-debug://seed?fixture=<name>` for
deterministic on-device test setup.

| Fixture | Source | Variant | Bytes (file) | Bytes (uncompressed) | License | Retrieval |
|---|---|---|---:|---:|---|---|
| `war-and-peace.txt` | hand-authored synthetic | n/a | 1,708 | 1,708 | Project-internal | n/a |
| `mini-epub3.epub` | hand-authored synthetic (3 paragraphs, EPUB 3.x) | n/a | 2,198 | 2,198 | Project-internal | n/a |
| `mini-azw3.azw3` | [Project Gutenberg ebook 1064](https://www.gutenberg.org/ebooks/1064) — *The Masque of the Red Death* by Edgar Allan Poe | `1064.kindle.noimages` (Mobipocket E-book, version 6, codepage 65001) | 128,650 | 37,894 | Public domain in the USA per [Project Gutenberg licence](https://www.gutenberg.org/policy/license.html) | 2026-05-07 |
| `mini-markdown.md` | hand-authored synthetic Markdown (feature #70 cross-format calibration) | n/a | 925 | 925 | Project-internal | n/a |
| `multi-chapter-epub.epub` | hand-authored synthetic (4 chapters × 40 paragraphs, viewport-tall, EPUB 3.x) — feature #71 continuous-scroll navigation harness (Bug #273) | n/a | 4,270 | 52,662 | Project-internal | n/a |
| `multi-page-pdf.pdf` | synthetic text-layer PDF generated via `cupsfilter` (6 pages, selectable text) — feature #17 PDF render/theme harness | PDF 1.3, 6 pages | 23,685 | 23,685 | Project-internal | n/a |

## Notes

- `mini-azw3.azw3` is stored under the `.azw3` extension because vreader's
  `BookFormat.azw3` collapses `azw3 / azw / mobi / prc` into one importer
  path, and Foliate-js sniffs the magic bytes at runtime — the file
  extension is purely organizational. The actual bytes are MOBI6
  (Mobipocket version 6).
- Project Gutenberg's licence permits unrestricted redistribution of
  public-domain US works; including this work in our DEBUG-only bundle
  is consistent with their terms. Public-domain status is "in the USA"
  per Gutenberg; consumers in jurisdictions with longer copyright
  terms should verify locally — but this fixture only ships in DEBUG
  builds run by developers, not in App Store releases.

## Adding a new fixture

1. Drop the file in this directory (any extension; the rsync is wholesale).
2. Add a row to `vreader/Services/DebugBridge/DebugFixtureCatalog.swift`'s
   `entries` array.
3. Add a row to the table above with provenance + licensing.
4. Update `DebugFixtureCatalogTests` (set assertion + per-fixture test).
5. The bundle-existence test
   (`test_all_entriesResolveInTheTestBundle`) catches catalog/bundle drift.
