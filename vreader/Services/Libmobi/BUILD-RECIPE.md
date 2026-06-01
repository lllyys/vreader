# libmobi — iOS build recipe (Feature #42 Phase 2, WI-1)

Vendored [libmobi](https://github.com/bfabiszewski/libmobi) (commit
`906274205c11944b628da1c553b255acb1af7c55`) for **Kindle convert-on-import**
(AZW3/MOBI/KF8 → EPUB), so converted books render through the Readium engine.

**License: LGPL-3.0** (user-accepted 2026-06-01). `LICENSE` retained; source
vendored under `src/` (LGPL source-availability is satisfied by keeping the
sources in-tree). Distribution must preserve the relink ability — favor a
dynamically-linked / separately-archivable static lib over folding objects into
the app binary (revisit at the App-Store-packaging step).

## Verified build (iOS Simulator arm64, Xcode 26.5 SDK)

The biggest Phase-2 risk — *does libmobi build for iOS without cmake/autotools?* —
is **answered: yes.** All 17 `src/*.c` compile + archive into a 285 KB `.a`, with
the conversion symbols present (`mobi_load_file`, `mobi_get_rawml`,
`mobi_decompress_lz77/huffman`, `mobi_parse_opf`/`write` via `xmlwriter.c`).

Key facts that made it work:
- **No external zlib** — `miniz.c`/`miniz.h` are bundled.
- **libxml2 is the only external dep**, gated behind `#ifdef USE_LIBXML2`
  (`opf.c:20`). iOS ships libxml2 as a system lib + headers at
  `$(SDKROOT)/usr/include/libxml2`. Define `USE_LIBXML2=1` to get OPF/NCX
  generation (required to emit EPUB).
- **Do NOT define `HAVE_CONFIG_H`.** `src/config.h` does
  `#ifdef HAVE_CONFIG_H → #include "../config.h"`, and `../config.h` is a
  configure-generated file that doesn't exist in-tree. Leaving `HAVE_CONFIG_H`
  undefined skips it and uses the in-tree defaults — all sources then compile.

Verified per-file recipe:
```bash
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
CLANG=$(xcrun --sdk iphonesimulator --find clang)
for c in src/*.c; do
  "$CLANG" -arch arm64 -isysroot "$SDK" -mios-simulator-version-min=15.0 \
    -DUSE_LIBXML2=1 -O2 -Isrc -I"$SDK/usr/include/libxml2" -c "$c" -o "build/$(basename ${c%.c}).o"
done
ar rcs build/libmobi.a build/*.o      # → links; mobi_load_file etc. present
# device build: same with --sdk iphoneos + -arch arm64 + -mios-version-min;
# then xcodebuild -create-xcframework to package sim+device.
```

## Remaining WIs (this is WI-1a — dependency vendored + build de-risked)

- **WI-1b** — dedicated xcodegen static-library target (`Libmobi`) with the flags
  above + a module map (`module Libmobi { header "mobi.h" }`) so Swift can
  `import Libmobi`; link `libxml2.tbd`; a Swift smoke test (`mobi_version`,
  open a fixture MOBI → `mobi_get_rawml` non-nil).
- **WI-2** — Swift `MobiToEPUBConverter` wrapper (off-main actor) around
  `mobi_load_filename` → `mobi_get_rawml` → `mobi_write_opf`/EPUB packaging.
- **WI-3** — fidelity spike: convert a real `.azw3`/`.mobi` from `test-books/`,
  assert spine/anchors/NCX survive; decide keep-source + `converterVersion`.
- **WI-4** — `BookImporter` integration: AZW3/MOBI/PRC → convert → import as EPUB
  (Readium engine); retain the original source per the plan.
- **WI-5** — device verification (import a Kindle book → renders via Readium with
  the full #42 criteria).
