// Purpose: Regression-guard tests for bug #128 — the user-visible mitigation
// banner in `ReplacementRulesView` that warns users their rules will silently
// no-op in native reading mode. The banner is the bug's only feedback path
// while the proper fix (wire native TXT/MD through the transform pipeline)
// remains a feature-class follow-up. If the banner copy changes or
// disappears, this test forces an explicit decision in lockstep.
//
// @coordinates-with: vreader/Views/Settings/ReplacementRulesView.swift

import Testing
import Foundation
@testable import vreader

@Suite("ReplacementRulesView native-mode banner (bug #128 / GH #275)")
struct ReplacementRulesViewBannerTests {

    @Test func bannerText_isNonEmpty() {
        #expect(!ReplacementRulesView.nativeModeBannerText.isEmpty)
    }

    @Test func bannerText_mentionsUnifiedMode() {
        // The banner's whole purpose is telling the user that rules only
        // apply in Unified mode. If "Unified mode" is removed, the banner
        // has lost its informational value — this test will fail and force
        // a deliberate update.
        #expect(ReplacementRulesViewBannerTests.containsCaseInsensitive(
            haystack: ReplacementRulesView.nativeModeBannerText,
            needle: "Unified mode"
        ))
    }

    @Test func bannerText_pointsUserToReaderSettings() {
        // The banner needs to tell the user *where* to switch — otherwise
        // they're stuck. We don't pin the exact wording, but we do require
        // a hint at the in-reader settings affordance.
        #expect(ReplacementRulesViewBannerTests.containsCaseInsensitive(
            haystack: ReplacementRulesView.nativeModeBannerText,
            needle: "Reading Mode"
        ))
    }

    @Test func bannerText_namesTXTAsUnsupported() {
        // Bug #158 / GH #468: the picker is hidden for TXT, so the banner
        // must call out that "switch to Unified" doesn't apply for TXT users
        // — otherwise they hunt for a non-existent toggle. We require an
        // explicit mention of TXT so a future copy change that drops the
        // exclusion list flags here.
        #expect(ReplacementRulesViewBannerTests.containsCaseInsensitive(
            haystack: ReplacementRulesView.nativeModeBannerText,
            needle: "TXT"
        ))
    }

    // MARK: - Helpers

    private static func containsCaseInsensitive(haystack: String, needle: String) -> Bool {
        haystack.range(of: needle, options: .caseInsensitive) != nil
    }
}
