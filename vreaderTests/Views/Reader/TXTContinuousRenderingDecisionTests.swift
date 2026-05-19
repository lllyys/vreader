// Purpose: Tests for the continuous-vs-single-chapter render decision in
// TXTReaderContainerView (Bug #180 re-scoped fix, WI-5). Verifies the pure
// `shouldOpenContinuous` seam picks the continuous path for chaptered TXT in
// Scroll layout and the single-chapter path for Paged layout.
//
// Tests live in vreaderTests/Views/Reader/ to mirror the source path.

#if canImport(UIKit)
import Testing
@testable import vreader

@Suite("TXTReaderContainerView — continuous render decision")
struct TXTContinuousRenderingDecisionTests {

    @Test func chapteredTxtInScrollLayoutPicksContinuous() {
        #expect(TXTReaderContainerView.shouldOpenContinuous(epubLayout: .scroll) == true)
    }

    @Test func chapteredTxtInPagedLayoutPicksSingleChapter() {
        #expect(TXTReaderContainerView.shouldOpenContinuous(epubLayout: .paged) == false)
    }

    @Test func nilLayoutDefaultsToContinuous() {
        // No settings store (preview / tests) → default to the continuous
        // scroll surface, which is the design's default reading layout.
        #expect(TXTReaderContainerView.shouldOpenContinuous(epubLayout: nil) == true)
    }
}
#endif
