// Purpose: Bug #348 — the reading surface shows NO system scroll
// indicator. The committed progress affordance is the bottom scrubber
// (feature #8) + the #101 metrics label; no canvas depicts a side rail,
// and under the #83/#85 stitched window the indicator is MISLEADING
// (it tracks the loaded window, not the book — jumping on every
// append/evict). One shared policy so every engine's bridge applies
// the same rule (rule-51-exempt: removes UNDESIGNED system chrome).
//
// @coordinates-with: TXTTextViewBridge.swift, TXTChunkedReaderBridge.swift,
//   EPUBWebViewBridge.swift, EPUBContinuousScrollJS.swift,
//   FoliateViewBridge.swift, ReadiumNavigatorRepresentable.swift,
//   PDFViewBridge.swift

#if canImport(UIKit)
import UIKit

/// Bug #348: hides the system scroll indicators on reader CONTENT
/// surfaces. Non-reader surfaces (sheets, lists) keep theirs.
enum ReaderScrollIndicatorPolicy {

    /// Hide both indicators on one scroll view.
    static func hide(on scrollView: UIScrollView) {
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
    }

    /// Recursively hide indicators on every `UIScrollView` under `root`
    /// (engines that wrap their scroller privately — Readium's spine
    /// webviews, PDFView's internal scroller).
    static func hideIndicators(in root: UIView) {
        for subview in root.subviews {
            if let scrollView = subview as? UIScrollView {
                hide(on: scrollView)
            }
            hideIndicators(in: subview)
        }
    }
}
#endif
