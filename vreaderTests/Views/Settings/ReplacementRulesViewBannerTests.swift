// Purpose: Regression-guard tests for `ReplacementRulesView.nativeModeBannerText`.
//
// History:
// - Bug #128 / GH #275 — the banner was added as the user-visible mitigation
//   for native-mode rules silently no-op'ing; original assertions pinned
//   "Unified mode" + "Reading Mode" copy.
// - Bug #158 / GH #468 — the picker was hidden for TXT, so the banner was
//   extended to call out TXT explicitly; assertion added.
// - Bug #231 / GH #957 — feature #54 (WI-4) removed the Native/Unified
//   Reading Mode picker entirely, and (WI-7) wired content replacement rules
//   into the native Markdown reader. The old banner pointed users at a
//   deleted control ("Switch from the reader's Settings → Reading Mode") and
//   its "only when reading in Unified mode" premise became stale. The banner
//   was rewritten to reflect post-#54 reality: rules apply natively in MD;
//   EPUB / AZW3 / TXT support is pending; PDF is not supported. These
//   assertions pin the post-#54 truth so a future regression that reintroduces
//   the "Unified mode" / "Reading Mode" copy fails here.
//
// @coordinates-with: vreader/Views/Settings/ReplacementRulesView.swift
//   docs/bugs.md row 231 (GH #957), docs/features.md row 54.

import Testing
import Foundation
@testable import vreader

@Suite("ReplacementRulesView native-mode banner (bug #231 / GH #957)")
struct ReplacementRulesViewBannerTests {

    @Test func bannerText_isNonEmpty() {
        #expect(!ReplacementRulesView.nativeModeBannerText.isEmpty)
    }

    @Test func bannerText_namesMarkdownAndEPUBAsSupported() {
        // Post-#54 + Phase D-1: native Markdown (WI-7) AND EPUB (Phase D-1 via
        // `EPUBReplacementJS`) both apply replacement rules today. The banner's
        // informational core is naming the supported formats by their full
        // user-facing names. A future copy change that drops either call-out
        // trips this test.
        let banner = ReplacementRulesView.nativeModeBannerText
        #expect(ReplacementRulesViewBannerTests.containsCaseInsensitive(
            haystack: banner, needle: "Markdown"
        ))
        #expect(ReplacementRulesViewBannerTests.containsCaseInsensitive(
            haystack: banner, needle: "EPUB"
        ))
    }

    @Test func bannerText_doesNotMentionUnifiedMode() {
        // Bug #231: "Unified mode" is no longer a user-visible concept after
        // feature #54 — the Native/Unified picker was removed. The banner
        // must not reintroduce the term.
        #expect(!ReplacementRulesViewBannerTests.containsCaseInsensitive(
            haystack: ReplacementRulesView.nativeModeBannerText,
            needle: "Unified mode"
        ))
    }

    @Test func bannerText_doesNotPointToReadingModePicker() {
        // Bug #231: feature #54 (WI-4) removed the Reading Mode picker from
        // the reader's Display panel. The banner must not instruct users to
        // use a control that no longer exists.
        #expect(!ReplacementRulesViewBannerTests.containsCaseInsensitive(
            haystack: ReplacementRulesView.nativeModeBannerText,
            needle: "Reading Mode"
        ))
    }

    @Test func bannerText_namesPendingFormats_AZW3_TXT() {
        // AZW3 / TXT currently do NOT apply replacement rules — they're the
        // remaining pending formats after Phase D-1 wired EPUB. The banner's
        // job is to tell users exactly which formats are pending so they don't
        // silently configure rules expecting them to take effect today. A copy
        // change that drops either pending format trips this test.
        let banner = ReplacementRulesView.nativeModeBannerText
        #expect(ReplacementRulesViewBannerTests.containsCaseInsensitive(
            haystack: banner, needle: "AZW3"
        ))
        #expect(ReplacementRulesViewBannerTests.containsCaseInsensitive(
            haystack: banner, needle: "TXT"
        ))
    }

    @Test func bannerText_namesPDFAsUnsupported() {
        // PDF is structurally not a text-transform target (no source-text
        // seam — PDFKit renders rendered pages, not source text). The
        // banner must keep calling out PDF as not-supported so a PDF user
        // doesn't silently configure rules that can't apply at all. We
        // require both "PDF" and a "not supported" phrasing so a future
        // copy change that drops the unsupported framing trips here.
        let banner = ReplacementRulesView.nativeModeBannerText
        #expect(ReplacementRulesViewBannerTests.containsCaseInsensitive(
            haystack: banner, needle: "PDF"
        ))
        #expect(ReplacementRulesViewBannerTests.containsCaseInsensitive(
            haystack: banner, needle: "not supported"
        ))
    }

    // MARK: - Helpers

    private static func containsCaseInsensitive(haystack: String, needle: String) -> Bool {
        haystack.range(of: needle, options: .caseInsensitive) != nil
    }
}
