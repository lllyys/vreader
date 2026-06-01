// Feature #42 Phase 2 WI-1b: smoke test proving the vendored libmobi (LGPL-3.0)
// C library links and is callable from Swift through the bridging header. If
// these fail, the C interop (compile flags / bridging header / libxml2 link)
// is broken — which would block the WI-2 MobiToEPUBConverter entirely. This is
// the RED→GREEN seam for WI-1b: the test cannot even compile until the bridging
// header + project.yml wiring expose the libmobi symbols.

import Testing
@testable import vreader

@Suite("Libmobi C interop smoke (Feature #42 Phase 2 WI-1b)")
struct LibmobiSmokeTests {

    @Test("mobi_version() links and returns a non-empty version string")
    func versionLinks() {
        let v = Libmobi.version
        #expect(v != nil, "mobi_version() must link + return — nil means the C symbol didn't resolve")
        #expect(!(v ?? "").isEmpty, "version string must be non-empty")
    }

    @Test("mobi_init()/mobi_free() allocate + free a context at runtime")
    func contextAllocatesAndFrees() {
        #expect(Libmobi.contextAllocates(), "mobi_init() returned NULL — allocation/link failure")
    }
}
