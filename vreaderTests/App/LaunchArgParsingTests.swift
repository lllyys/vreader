// Purpose: Tests for TestLaunchConfig.parse — new launch args added for the
// verification harness (feature #45 WI-4c) and existing seed/feature flags.
// The new --reader-default-layout=<value> arg lets XCUITest seed the EPUB
// layout default without driving the SwiftUI segmented Picker (which doesn't
// transition state under XCUITest as of iOS 26.5).

import Testing
import Foundation
@testable import vreader

#if DEBUG

@Suite("TestLaunchConfig parsing")
struct LaunchArgParsingTests {

    @Test func defaultEPUBLayoutIsNilWithoutFlag() {
        let config = TestLaunchConfig.parse(["--uitesting"])
        #expect(config.defaultEPUBLayout == nil)
    }

    @Test func parsesPagedLayout() {
        let config = TestLaunchConfig.parse([
            "--uitesting", "--reader-default-layout=paged"
        ])
        #expect(config.defaultEPUBLayout == .paged)
    }

    @Test func parsesScrollLayout() {
        let config = TestLaunchConfig.parse([
            "--uitesting", "--reader-default-layout=scroll"
        ])
        #expect(config.defaultEPUBLayout == .scroll)
    }

    @Test func invalidLayoutValueFallsThroughToNil() {
        let config = TestLaunchConfig.parse([
            "--uitesting", "--reader-default-layout=garbage"
        ])
        #expect(config.defaultEPUBLayout == nil)
    }

    @Test func emptyLayoutValueFallsThroughToNil() {
        let config = TestLaunchConfig.parse([
            "--uitesting", "--reader-default-layout="
        ])
        #expect(config.defaultEPUBLayout == nil)
    }

    @Test func bareFlagWithoutEqualsValueFallsThroughToNil() {
        // `--reader-default-layout` without an `=value` suffix is not a match —
        // the parser only recognises the `<arg>=<rawValue>` form.
        let config = TestLaunchConfig.parse([
            "--uitesting", "--reader-default-layout"
        ])
        #expect(config.defaultEPUBLayout == nil)
    }

    @Test func laterLayoutFlagWinsOverEarlier() {
        // If the test harness or CI script accidentally passes the flag twice,
        // the LAST occurrence wins — matches the user's mental model of
        // command-line overrides.
        let config = TestLaunchConfig.parse([
            "--uitesting",
            "--reader-default-layout=scroll",
            "--reader-default-layout=paged"
        ])
        #expect(config.defaultEPUBLayout == .paged)
    }

    @Test func layoutFlagCoexistsWithOtherSeedFlags() {
        let config = TestLaunchConfig.parse([
            "--uitesting",
            "--seed-md-toc",
            "--reset-preferences",
            "--reader-default-layout=paged"
        ])
        #expect(config.isUITesting == true)
        #expect(config.seedMDTOC == true)
        #expect(config.seedResetPreferences == true)
        #expect(config.defaultEPUBLayout == .paged)
    }

    // MARK: - Feature #45 WI-4e: --tts-test-mode

    @Test func ttsTestModeDefaultsFalseWithoutFlag() {
        let config = TestLaunchConfig.parse(["--uitesting"])
        #expect(config.ttsTestMode == false)
    }

    @Test func ttsTestModeParsedWhenFlagPresent() {
        let config = TestLaunchConfig.parse([
            "--uitesting", "--tts-test-mode"
        ])
        #expect(config.ttsTestMode == true)
    }

    @Test func ttsTestModeCoexistsWithOtherFlags() {
        let config = TestLaunchConfig.parse([
            "--uitesting",
            "--seed-war-and-peace",
            "--reset-preferences",
            "--tts-test-mode"
        ])
        #expect(config.isUITesting == true)
        #expect(config.seedWarAndPeace == true)
        #expect(config.seedResetPreferences == true)
        #expect(config.ttsTestMode == true)
    }

    // MARK: - Feature #45 WI-5: --seed-md-multi-page

    @Test func seedMDMultiPageDefaultsFalse() {
        let config = TestLaunchConfig.parse(["--uitesting"])
        #expect(config.seedMDMultiPage == false)
    }

    @Test func seedMDMultiPageParsedWhenFlagPresent() {
        let config = TestLaunchConfig.parse([
            "--uitesting", "--seed-md-multi-page"
        ])
        #expect(config.seedMDMultiPage == true)
        #expect(config.isUITesting == true)
    }

    // MARK: - Bug #214 / GH #834: --seed-epub-fixture

    @Test func seedEPUBFixtureDefaultsFalse() {
        let config = TestLaunchConfig.parse(["--uitesting"])
        #expect(config.seedEPUBFixture == false)
    }

    @Test func seedEPUBFixtureParsedWhenFlagPresent() {
        let config = TestLaunchConfig.parse([
            "--uitesting", "--seed-epub-fixture"
        ])
        #expect(config.seedEPUBFixture == true)
        #expect(config.isUITesting == true)
    }

    @Test func seedEPUBFixtureNoneConfigIsFalse() {
        #expect(TestLaunchConfig.none.seedEPUBFixture == false)
    }

    @Test func seedEPUBFixtureCoexistsWithOtherFlags() {
        let config = TestLaunchConfig.parse([
            "--uitesting",
            "--seed-epub-fixture",
            "--reset-preferences"
        ])
        #expect(config.isUITesting == true)
        #expect(config.seedEPUBFixture == true)
        #expect(config.seedResetPreferences == true)
        // Mutually-exclusive seed flags stay false.
        #expect(config.seedEmpty == false)
        #expect(config.seedWarAndPeace == false)
    }
}

#endif
