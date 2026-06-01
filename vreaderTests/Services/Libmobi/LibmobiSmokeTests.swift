// Feature #42 Phase 2 WI-1b: smoke test proving the vendored libmobi (LGPL-3.0)
// C library links and is callable from Swift through the bridging header. If
// these fail, the C interop (compile flags / bridging header) is broken —
// which would block the WI-2 MobiToEPUBConverter entirely. This is the
// RED→GREEN seam for WI-1b: the test cannot even compile until the bridging
// header + project.yml wiring expose the libmobi symbols.
//
// Scope of the RUNTIME guarantee (Codex Gate-4 Low): these two cases prove
// `mobi_version` and `mobi_init`/`mobi_free` resolve and run. They do NOT
// exercise the USE_LIBXML2-gated xmlwriter/OPF path — that runs only inside a
// real MOBI→EPUB conversion, which lands in WI-2 (and is verified there with a
// real fixture). The libxml2 *link* is nonetheless already proven at build
// time: xmlwriter.c references libxml2 symbols, so the app would fail to link
// if `-lxml2` weren't resolving. Runtime coverage of that path is WI-2's job.

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
