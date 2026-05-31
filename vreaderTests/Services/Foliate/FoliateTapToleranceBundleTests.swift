// Purpose: Bug #287 / GH #1268 — pins the AZW3/Foliate highlight-tap tolerance
// contract across the editable JS sources and the built foliate-bundle.js the
// reader's WebView actually loads. The tolerance behavior itself runs in JS (no
// Swift-runnable seam), so — mirroring FoliatePaginatorScrollBoundaryTests —
// these tests grep the source + bundle for the load-bearing contract:
//
//   - overlayer.js declares `hitTestWithTolerance` (the 44pt-min slop +
//     nearest-center variant).
//   - view.js uses it as a fallback after the exact `hitTest` miss AND marks
//     the event `__vreaderAnnotationHit` so the page-turn is suppressed.
//   - foliate-host.js absorbs the tap when `__vreaderAnnotationHit` is set.
//   - the built bundle carries all three (rebuild gate: if you edit the JS
//     without running build-bundle.sh, this fails).
//
// @coordinates-with: vreader/Services/Foliate/JS/{overlayer,view,foliate-host}.js,
//   vreader/Services/Foliate/JS/foliate-bundle.js

import Testing
import Foundation
@testable import vreader

@Suite("Foliate tap tolerance — JS contract (Bug #287)")
struct FoliateTapToleranceBundleTests {

    private final class BundleToken {}

    private func loadBundle() throws -> String {
        let candidates: [Bundle] = [Bundle(for: BundleToken.self), .main]
        for candidate in candidates {
            if let url = candidate.url(forResource: "foliate-bundle", withExtension: "js") {
                return try String(contentsOf: url, encoding: .utf8)
            }
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private func loadSource(_ relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Foliate
            .deletingLastPathComponent()  // Services
            .deletingLastPathComponent()  // vreaderTests
            .deletingLastPathComponent()  // repo root
        let url = repoRoot.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Source contract

    @Test("overlayer.js declares the tolerant hitTest")
    func overlayerDeclaresTolerantHitTest() throws {
        let src = try loadSource("vreader/Services/Foliate/JS/overlayer.js")
        #expect(src.contains("hitTestWithTolerance"),
                "overlayer.js must declare hitTestWithTolerance — the 44pt-min slop variant for near-miss highlight taps.")
        // The slop must derive from a 44pt-min target (mirrors Swift HighlightHitTolerance).
        #expect(src.contains("minTarget = 44"),
                "the tolerant hitTest must expand toward a 44pt minimum touch target.")
    }

    @Test("view.js uses the tolerant fallback and marks the event for suppression")
    func viewWiresToleranceAndSuppression() throws {
        let src = try loadSource("vreader/Services/Foliate/JS/view.js")
        #expect(src.contains("hitTestWithTolerance"),
                "view.js must call hitTestWithTolerance as the fallback after the exact hitTest miss.")
        #expect(src.contains("__vreaderAnnotationHit"),
                "view.js must mark the event so the host absorbs the tap (no page-turn).")
        // Must run in the capture phase so it precedes the host's bubble tap handler.
        #expect(src.contains("}, true)"),
                "the annotation click handler must register in the capture phase (true) so it fires before the host's page-turn tap handler.")
    }

    @Test("foliate-host.js absorbs the tap on an annotation hit")
    func hostAbsorbsAnnotationTap() throws {
        let src = try loadSource("vreader/Services/Foliate/JS/foliate-host.js")
        #expect(src.contains("event.__vreaderAnnotationHit"),
                "foliate-host.js must early-return when the event was marked an annotation hit, so a near-miss highlight tap does not turn the page.")
    }

    // MARK: - Built bundle stays in sync (rebuild gate)

    @Test("built foliate-bundle.js carries the tolerance + suppression contract")
    func bundleCarriesContract() throws {
        let text = try loadBundle()
        #expect(text.contains("hitTestWithTolerance"),
                "foliate-bundle.js must contain hitTestWithTolerance — run build-bundle.sh after editing the JS sources.")
        #expect(text.contains("__vreaderAnnotationHit"),
                "foliate-bundle.js must contain the __vreaderAnnotationHit suppression marker — run build-bundle.sh after editing the JS sources.")
    }
}
