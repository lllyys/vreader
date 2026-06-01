// Purpose: Feature #42 Phase 2 WI-1b — minimal Swift surface proving the
// vendored libmobi (LGPL-3.0) C library links and is callable from Swift.
// The real AZW3/MOBI/KF8 → EPUB converter (WI-2: MobiToEPUBConverter) builds
// on this seam; WI-1b only establishes that the C interop works end-to-end —
// at both compile time (the bridging header resolves mobi.h) and runtime (the
// symbols are present in the linked binary, not merely declared).
//
// @coordinates-with: vreader/SupportingFiles/Libmobi-Bridging-Header.h,
//   vreader/Services/Libmobi/BUILD-RECIPE.md,
//   dev-docs/plans/20260528-feature-42-readium-libmobi-reader-engine.md

import Foundation

/// Thin namespace over the libmobi C API. WI-1b exposes only enough to prove
/// linkage; the conversion surface (`mobi_load_filename` → `mobi_parse_kf8` →
/// rawml → OPF/XML) lands in WI-2.
enum Libmobi {

    /// The vendored libmobi version string (e.g. `"0.12"`), read straight from
    /// the C `mobi_version()`. Non-nil iff the C symbol links and returns.
    static var version: String? {
        guard let c = mobi_version() else { return nil }
        return String(cString: c)
    }

    /// Allocate a libmobi context and immediately free it. Returns `true` if
    /// `mobi_init()` returned a non-NULL `MOBIData *` — proving both
    /// `mobi_init` and `mobi_free` link and run, not just resolve at link time.
    static func contextAllocates() -> Bool {
        guard let data = mobi_init() else { return false }
        mobi_free(data)
        return true
    }
}
