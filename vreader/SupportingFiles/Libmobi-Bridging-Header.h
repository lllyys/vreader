//
//  Libmobi-Bridging-Header.h
//  Feature #42 Phase 2 (WI-1b): expose the vendored libmobi (LGPL-3.0) public
//  C API to Swift, for Kindle (AZW3/MOBI/KF8) → EPUB convert-on-import.
//
//  Only the public umbrella header `mobi.h` is exposed. It is self-contained
//  (includes only <stdio.h>/<stdint.h>/<stdbool.h>/<time.h>), so no internal
//  libmobi headers leak into the Swift module. The .c sources compile into the
//  app target (see project.yml); this header makes their declared symbols
//  callable from Swift. Compile flags (USE_LIBXML2, the libxml2 include path)
//  and the libxml2 link are configured on the vreader target in project.yml.
//
#include "mobi.h"
