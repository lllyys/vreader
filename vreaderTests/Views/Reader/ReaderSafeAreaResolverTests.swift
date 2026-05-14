// Tests for `ReaderSafeAreaResolver.combine`, the pure-function half of the
// Bug #179 fix. The `windowSafeAreaTop` half reads `UIApplication.shared`
// and isn't unit-testable without a UI/system harness — slice-tested at
// runtime via device verification of the bug repro.

import Testing
@testable import vreader

#if canImport(UIKit)
import UIKit

@Suite("ReaderSafeAreaResolver.combine")
struct ReaderSafeAreaResolverCombineSuite {

    @Test("both zero → 0 (no DI compensation when device truly has no top inset)")
    func bothZero() {
        #expect(ReaderSafeAreaResolver.combine(0, 0) == 0)
    }

    @Test("geometry value only → use it (GeometryReader measured before window scene lookup)")
    func geometryOnly() {
        #expect(ReaderSafeAreaResolver.combine(59, 0) == 59)
    }

    @Test("window value only → use it (Bug #179 primary repro: proxy=0 race covered by window probe)")
    func windowOnly() {
        #expect(ReaderSafeAreaResolver.combine(0, 59) == 59)
    }

    @Test("both equal → that value (sanity)")
    func bothEqual() {
        #expect(ReaderSafeAreaResolver.combine(59, 59) == 59)
    }

    @Test("geometry > window → geometry (proxy is freshest measurement of the hosting view)")
    func geometryWinsWhenLarger() {
        #expect(ReaderSafeAreaResolver.combine(70, 59) == 70)
    }

    @Test("window > geometry → window (cache or other-scene value lifts the result)")
    func windowWinsWhenLarger() {
        #expect(ReaderSafeAreaResolver.combine(20, 59) == 59)
    }

    @Test("negative geometry clamps to 0 (mirrors EPUB bug #167 audit-fix)")
    func negativeGeometryClamps() {
        #expect(ReaderSafeAreaResolver.combine(-10, 59) == 59)
    }

    @Test("negative window clamps to 0 (defensive — UIWindow never reports negative, but match the contract)")
    func negativeWindowClamps() {
        #expect(ReaderSafeAreaResolver.combine(59, -10) == 59)
    }

    @Test("both negative → 0 (never under-inset)")
    func bothNegativeClampsToZero() {
        #expect(ReaderSafeAreaResolver.combine(-10, -20) == 0)
    }

    @Test("iPad landscape baseline (5pt top safe area) flows through")
    func smallNonZeroFlowsThrough() {
        #expect(ReaderSafeAreaResolver.combine(5, 0) == 5)
        #expect(ReaderSafeAreaResolver.combine(0, 5) == 5)
    }
}

#endif
